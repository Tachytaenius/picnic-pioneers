local ffi = require("ffi")

local mathsies = require("lib.mathsies")
local consts = require("consts")

local game = {}

function game:getPointLayerIntensities()
	-- TEMP: Continue to ignore attenuation for now-- just check that unattenuated and "attenuated" are the same :)
	local phiSamples = 1
	local thetaSamples = 1
	local directionSamples = phiSamples * thetaSamples
	local power = 7
	local canvasSize = 2 ^ power -- For nice doubling/halving mipchain
	local precalcCanvas = love.graphics.newCanvas(canvasSize, canvasSize, {
		format = "rgba32f",
		debugname = "Intensity Precalculation Canvas",
		mipmaps = "manual",
		computewrite = true
	})
	local resultCopyShader = love.graphics.newComputeShader("shaders/misc/resultCopy.glsl", {
		debugname = "Intensity Precalculation Result Copy Shader",
		defines = {
			LOD = precalcCanvas:getMipmapCount() - 1
		}
	})
	resultCopyShader:send("readCanvas", precalcCanvas)

	-- Count how many to do
	local intensitiesToMeasure = 0
	local maxRequiredResultBufferSize = 0
	local countsByLayer = {}
	for pointLayerIndex = #self.pointLayers, 1, -1 do
		local pointLayer = self.pointLayers[pointLayerIndex]
		if pointLayerIndex == #self.pointLayers then
			goto continue
		else
			local counts = {}
			countsByLayer[pointLayer] = counts
			counts.scaleSamplesFromInfos = {}
			counts.zRatioSamplesFromInfos = {}
			counts.resultBufferSizesFromInfos = {}
			for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
				local minZR, maxZR = shapeType.zScaleRatioMin, shapeType.zScaleRatioMax
				local zScaleRatioDiff = math.abs(maxZR - minZR)
				local zRatioSamplesThis
				if shapeType.needsTrueRatio then
					zRatioSamplesThis = shapeType.zScaleRatioSamples
				else
					local zRatioSamplesPerRatioDiff = 2.5
					local maxZRatioSamples = 12
					zRatioSamplesThis = math.min(maxZRatioSamples, math.max(1, math.floor(0.5 + zScaleRatioDiff * zRatioSamplesPerRatioDiff))) -- We ignore needsTrueRatio and shapeType.zScaleRatioSamples
				end
				local scaleSamplesThis = 24

				local virtualObjectsThisInfo = scaleSamplesThis * zRatioSamplesThis * shapeType.sampleCount -- Virtual objects as in, the "virtual" objects that are imaged on the GPU
				local resultBufferSizeThis = virtualObjectsThisInfo -- TODO: Once directional, mul virtualobjectsthisinfo by directionsamples
				maxRequiredResultBufferSize = math.max(maxRequiredResultBufferSize, resultBufferSizeThis)
				intensitiesToMeasure = intensitiesToMeasure + virtualObjectsThisInfo

				counts.scaleSamplesFromInfos[shapeTypeInfo] = scaleSamplesThis
				counts.zRatioSamplesFromInfos[shapeTypeInfo] = zRatioSamplesThis
				counts.resultBufferSizesFromInfos[shapeTypeInfo] = resultBufferSizeThis
			end
		end
	    ::continue::
	end
	local resultBuffer = love.graphics.newBuffer(consts.vec3BufferFormat, maxRequiredResultBufferSize, {
		shaderstorage = true,
		debugname = "Intensity Precalculation Result Buffer"
	})
	resultCopyShader:send("Results", resultBuffer)

	-- Get intensities
	self.loadInfo.intensitiesMeasured = 0
	self.loadInfo.intensitiesToMeasure = intensitiesToMeasure
	coroutine.yield()
	for pointLayerIndex = #self.pointLayers, 1, -1 do
		local pointLayer = self.pointLayers[pointLayerIndex]
		if pointLayerIndex == #self.pointLayers then
			-- TODO: Stars as shape types
			-- TODO: Remove deterministic unattenuated CPU calculations from game
			local starAverageRadiantIntensityR = pointLayer.averageUnattenuatedRadiantIntensityRPerPoint
			local starAverageRadiantIntensityG = pointLayer.averageUnattenuatedRadiantIntensityGPerPoint
			local starAverageRadiantIntensityB = pointLayer.averageUnattenuatedRadiantIntensityBPerPoint

			pointLayer.averageRadiantIntensityRPerPoint = starAverageRadiantIntensityR
			pointLayer.averageRadiantIntensityGPerPoint = starAverageRadiantIntensityG
			pointLayer.averageRadiantIntensityBPerPoint = starAverageRadiantIntensityB
		else
			local childPointLayer = pointLayer.childPointLayer

			local averagingIteration = 0
			self:seedCelestialRNG(self:getShapeIntegralNoiseSeed(averagingIteration, consts.shapeIntegralNoiseSeedTypes.intensities))
			if childPointLayer.hasNoiseEmission then
				childPointLayer:randomiseValueNoiseCore("Emission", childPointLayer.maxNoiseValuesEmission)
			end

			local weightTotalForAllShapeTypeInfos = 0
			local intensityTotalRForAllShapeTypeInfos = 0
			local intensityTotalGForAllShapeTypeInfos = 0
			local intensityTotalBForAllShapeTypeInfos = 0
			local mulByResultIndex = {} -- Starts at 0
			for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]

				local resultBufferIndex = 0

				local volumetricShader = self.shapeIntensityPrecalcShaders[shapeType.name]["noAttenuation"]
				if pointLayer.hasNoiseEmission and shapeType.noiseInfo then
					if volumetricShader:hasUniform("EmissionNoiseValues") then
						volumetricShader:send("EmissionNoiseValues", childPointLayer.valueNoiseBufferEmission)
					end
				end

				for samplingId = 0, shapeType.sampleCount - 1 do
					-- TODO: If has noise then repeat this for a bunch of noise value sets
					local subtype = self:subtypeFromSamplingId(shapeType, samplingId)
					local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(shapeType, subtype)
					for i, parameter in ipairs(shapeType.parameters) do
						local name = "emissionShape_" .. parameter.name
						if volumetricShader:hasUniform(name) then
							volumetricShader:send(name, densityParametersScratchTable[i])
						end
					end
					local maxRaySteps = 120
					local w, h = volumetricShader:getLocalThreadgroupSize()
					volumetricShader:send("brightnessMultiplier", 1)
					volumetricShader:send("size", {precalcCanvas:getDimensions()})
					volumetricShader:send("resultCanvas", precalcCanvas)
					volumetricShader:send("maxRaySteps", maxRaySteps)

					local scaleSampleCount = countsByLayer[pointLayer].scaleSamplesFromInfos[shapeTypeInfo]
					local zRatioSampleCount = countsByLayer[pointLayer].zRatioSamplesFromInfos[shapeTypeInfo]
					for scaleSampleId = 0, scaleSampleCount - 1 do
						local lower = shapeTypeInfo.scaleMin + (scaleSampleId) / scaleSampleCount * (shapeTypeInfo.scaleMax - shapeTypeInfo.scaleMin)
						local upper = shapeTypeInfo.scaleMin + (scaleSampleId + 1) / scaleSampleCount * (shapeTypeInfo.scaleMax - shapeTypeInfo.scaleMin)
						local scale = shapeTypeInfo.scaleMin + (scaleSampleId + 0.5) / scaleSampleCount * (shapeTypeInfo.scaleMax - shapeTypeInfo.scaleMin)

						local shaderScale = 1 / scale -- Rather than the reciprocal of the max of the radii
						if volumetricShader:hasUniform("baseEmission") then
							volumetricShader:send("baseEmission", {
								shaderScale ^ -1 * childPointLayer.maxPointDensity * childPointLayer.averageRadiantIntensityRPerPoint,
								shaderScale ^ -1 * childPointLayer.maxPointDensity * childPointLayer.averageRadiantIntensityGPerPoint,
								shaderScale ^ -1 * childPointLayer.maxPointDensity * childPointLayer.averageRadiantIntensityBPerPoint
							})
						end
						for zRatioSampleId = 0, zRatioSampleCount - 1 do
							local zScaleRatioLerp = zRatioSampleCount > 1 and ((zRatioSampleId + 0.5) / zRatioSampleCount) or 0.5
							local zRatio = shapeType.zScaleRatioMin + zScaleRatioLerp * (shapeType.zScaleRatioMax - shapeType.zScaleRatioMin)

							volumetricShader:send("shapeRadii", {
								shaderScale * scale,
								shaderScale * scale,
								shaderScale * zRatio * scale
							})

							local samplingDiskRadius = math.max(zRatio, 1) * scale * shaderScale
							volumetricShader:send("samplingDiskRadius", samplingDiskRadius)

							love.graphics.setCanvas(precalcCanvas)
							love.graphics.clear()
							love.graphics.setCanvas()

							for thetaSampleId = 0, thetaSamples - 1 do
								local theta = consts.tau / 2 * (thetaSampleId + 0.5) / thetaSamples
								-- local sinTheta = math.sin(theta) -- No need for dmath with graphics, this is all going on the GPU where we don't trust any determinism at all (NOTE: this means the result of these calculations, the average (attenuated) radiant intensities, are not to be considered deterministic)
								for phiSampleId = 0, phiSamples - 1 do
									local phi = consts.tau * (phiSampleId + 0.5) / phiSamples

									local cameraOrientation =
										mathsies.quat.fromAxisAngle(consts.rightVector * (theta - consts.tau / 4)) *
										mathsies.quat.fromAxisAngle(consts.upVector * phi)
									local cameraForwards = mathsies.vec3.rotate(consts.forwardVector, cameraOrientation)
									local cameraRight = mathsies.vec3.rotate(consts.rightVector, cameraOrientation)
									local cameraUp = mathsies.vec3.rotate(consts.upVector, cameraOrientation)

									volumetricShader:send("cameraForwards", {mathsies.vec3.components(cameraForwards)})
									volumetricShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
									volumetricShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})

									love.graphics.dispatchThreadgroups(volumetricShader,
										math.ceil(precalcCanvas:getWidth() / w),
										math.ceil(precalcCanvas:getHeight() / h)
									)
								end
							end

							-- local cpuside do
							-- 	local baseAmount
							-- 	if shapeType.needsTrueRatio then
							-- 		baseAmount = self:getSubtypeBaseAmountWithSamples(shapeType, subtype, zRatio)
							-- 	else
							-- 		baseAmount = self:getSubtypeBaseAmountWithSamples(shapeType, subtype)
							-- 	end
							-- 	local amountWithin = baseAmount * scale^3 * zRatio * childPointLayer.maxPointDensity
							-- 	cpuside = amountWithin * childPointLayer.averageRadiantIntensityRPerPoint
							-- end
							precalcCanvas:generateMipmaps()

							resultCopyShader:send("index", resultBufferIndex)
							love.graphics.dispatchThreadgroups(resultCopyShader, 1)

							local areaAveragedOverByMipmaps = (2 * samplingDiskRadius) ^ 2 -- We don't want the average so we multiply the area back in

							local good = (lower + upper) * (lower ^ 2 + upper ^ 2) / 4 -- Average volume scale with radius scales evenly distributed between lower and upper
							local bad = ((lower + upper) / 2) ^ 3 -- Volume scale of the average radius scale
							local compensate = good / bad -- (This approaches 1 as the number of scale samples increases to infinity and this is needed less)

							-- print(compensate)
							mulByResultIndex[resultBufferIndex] = areaAveragedOverByMipmaps / shaderScale ^ 2 / directionSamples * compensate
							resultBufferIndex = resultBufferIndex + 1
							-- local data = love.graphics.readbackTexture(precalcCanvas, nil, precalcCanvas:getMipmapCount())
							-- local r = data:getPixel(0, 0)
							-- local areaAveragedOverByMipmaps = (2 * samplingDiskRadius) ^ 2
							-- local calculatedIntensity = r / shaderScale ^ 2 * areaAveragedOverByMipmaps / directionSamples
							-- print(cpuside / calculatedIntensity)

							self.loadInfo.intensitiesMeasured = self.loadInfo.intensitiesMeasured + 1
							coroutine.yield()
						end
						-- Dummy sync readback to keep the loading process from becoming unresponsive??
						love.graphics.readbackBuffer(resultBuffer, 4)
						coroutine.yield()
					end
				end

				local rSum, gSum, bSum = 0, 0, 0
				local bytesPerFloat = 4
				local entries = countsByLayer[pointLayer].resultBufferSizesFromInfos[shapeTypeInfo]
				local data = love.graphics.readbackBuffer(resultBuffer)
				local dataFFI = ffi.cast("float*", data:getFFIPointer())
				local strideFloats = resultBuffer:getElementStride() / bytesPerFloat
				for i = 0, entries - 1 do
					local mul = mulByResultIndex[i]
					rSum = rSum + dataFFI[i * strideFloats + 0] * mul
					gSum = gSum + dataFFI[i * strideFloats + 1] * mul
					bSum = bSum + dataFFI[i * strideFloats + 2] * mul
				end
				local r = rSum / entries
				local g = gSum / entries
				local b = bSum / entries
				intensityTotalRForAllShapeTypeInfos = intensityTotalRForAllShapeTypeInfos + r * shapeTypeInfo.weight
				intensityTotalGForAllShapeTypeInfos = intensityTotalGForAllShapeTypeInfos + g * shapeTypeInfo.weight
				intensityTotalBForAllShapeTypeInfos = intensityTotalBForAllShapeTypeInfos + b * shapeTypeInfo.weight
				weightTotalForAllShapeTypeInfos = weightTotalForAllShapeTypeInfos + shapeTypeInfo.weight
			end

			pointLayer.averageRadiantIntensityRPerPoint = intensityTotalRForAllShapeTypeInfos / weightTotalForAllShapeTypeInfos
			pointLayer.averageRadiantIntensityGPerPoint = intensityTotalGForAllShapeTypeInfos / weightTotalForAllShapeTypeInfos
			pointLayer.averageRadiantIntensityBPerPoint = intensityTotalBForAllShapeTypeInfos / weightTotalForAllShapeTypeInfos

			-- print("gpu " .. pointLayer.averageRadiantIntensityRPerPoint, "cpu " .. pointLayer.averageUnattenuatedRadiantIntensityRPerPoint, "gpu/cpu " .. pointLayer.averageRadiantIntensityRPerPoint / pointLayer.averageUnattenuatedRadiantIntensityRPerPoint)
		end
	end
	coroutine.yield()
	self.loadInfo.intensitiesMeasured = nil
	self.loadInfo.intensitiesToMeasure = nil
end

return game
