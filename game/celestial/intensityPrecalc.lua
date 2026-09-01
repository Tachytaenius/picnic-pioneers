local ffi = require("ffi")

local mathsies = require("lib.mathsies")
local consts = require("consts")

local game = {}

function game:getPointLayerIntensities()
	-- TEMP: Continue to ignore attenuation for now-- just check that unattenuated and "attenuated" are the same :)
	-- No need for dmath with graphics, this is all going on the GPU where we don't trust any determinism at all (NOTE: this means the result of these calculations, the average (attenuated) radiant intensities, are not to be considered deterministic)
	local format = "rgba32f"
	local maxRaySteps = 64
	local phiSamples = 9
	local thetaSamples = 6
	local directionSamples = phiSamples * thetaSamples
	local power = 5
	local canvasSize = 2 ^ power -- For nice doubling/halving mipchain
	local precalcCanvas = love.graphics.newCanvas(canvasSize, canvasSize, {
		format = format,
		debugname = "Intensity Precalculation Canvas",
		mipmaps = "manual",
		type = "array",
		layers = directionSamples,
		computewrite = true
	})
	local resultCopyShader = love.graphics.newComputeShader("shaders/misc/resultCopy.glsl", {
		debugname = "Intensity Precalculation Result Copy Shader",
		defines = {
			LOD = precalcCanvas:getMipmapCount() - 1,
			LAYERS = precalcCanvas:getLayerCount()
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

			counts.attenuationSamplesFromInfos = {}

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
					local maxZRatioSamples = 4
					zRatioSamplesThis = math.min(maxZRatioSamples, math.max(1, math.floor(0.5 + zScaleRatioDiff * zRatioSamplesPerRatioDiff))) -- We ignore needsTrueRatio and shapeType.zScaleRatioSamples
				end

				local scaleSamplesThis = 4

				local attenuationSamplesThis = not shapeTypeInfo.attenuationInfo and 1 or
					shapeTypeInfo.attenuationInfo.mulRangeMin == shapeTypeInfo.attenuationInfo.mulRangeMax and 1 or
					4

				local virtualObjectsThisInfo = -- Virtual objects as in, the "virtual" objects that are imaged on the GPU
					scaleSamplesThis *
					zRatioSamplesThis *
					shapeType.sampleCount *
					self.pointLayerShapeTypes[shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.name or consts.noAttenuationShapeTypeName].sampleCount *
					attenuationSamplesThis
				local resultBufferSizeThis = virtualObjectsThisInfo * directionSamples
				maxRequiredResultBufferSize = math.max(maxRequiredResultBufferSize, resultBufferSizeThis)
				intensitiesToMeasure = intensitiesToMeasure + virtualObjectsThisInfo

				counts.scaleSamplesFromInfos[shapeTypeInfo] = scaleSamplesThis
				counts.zRatioSamplesFromInfos[shapeTypeInfo] = zRatioSamplesThis
				counts.resultBufferSizesFromInfos[shapeTypeInfo] = resultBufferSizeThis
				counts.attenuationSamplesFromInfos[shapeTypeInfo] = attenuationSamplesThis
			end
		end
	    ::continue::
	end
	local resultBuffer = love.graphics.newBuffer(consts.vec3BufferFormat, maxRequiredResultBufferSize, {
		shaderstorage = true,
		debugname = "Intensity Precalculation Result Buffer"
	})
	resultCopyShader:send("Results", resultBuffer)

	-- Get direction const array
	local directionConstArrayCodeLines = {}
	table.insert(directionConstArrayCodeLines, "const vec3 directions[] = vec3[](")
	local function addVec(x, y, z)
		table.insert(directionConstArrayCodeLines, "\tvec3(" .. x .. ", " .. y ..  ", " .. z .. "),")
	end
	for thetaSampleId = 0, thetaSamples - 1 do
		local theta = consts.tau / 2 * (thetaSampleId + 0.5) / thetaSamples
		for phiSampleId = 0, phiSamples - 1 do
			local phi = consts.tau * (phiSampleId + 0.5) / phiSamples

			local cameraOrientation =
				mathsies.quat.fromAxisAngle(consts.rightVector * (theta - consts.tau / 4)) *
				mathsies.quat.fromAxisAngle(consts.upVector * phi)
			local cameraForwards = mathsies.vec3.rotate(consts.forwardVector, cameraOrientation)
			local cameraRight = mathsies.vec3.rotate(consts.rightVector, cameraOrientation)
			local cameraUp = mathsies.vec3.rotate(consts.upVector, cameraOrientation)

			addVec(mathsies.vec3.components(cameraForwards))
			addVec(mathsies.vec3.components(cameraRight))
			addVec(mathsies.vec3.components(cameraUp))
		end
	end
	directionConstArrayCodeLines[#directionConstArrayCodeLines] = -- Remove comma from last entry (assuming it was a vec3 line)
		directionConstArrayCodeLines[#directionConstArrayCodeLines]:sub(1, -2)
	table.insert(directionConstArrayCodeLines, ");")
	local directionConstArrayCode = table.concat(directionConstArrayCodeLines, " ")

	local precalcClearShader = love.graphics.newComputeShader("shaders/misc/precalcClear.glsl", {
		debugname = "Intensity Precalculation Clear Shader",
		defines = {
			FORMAT = format
		}
	})
	precalcClearShader:send("canvas", precalcCanvas)
	local function clearPrecalc()
		local w, h, d = precalcClearShader:getLocalThreadgroupSize()
		love.graphics.dispatchThreadgroups(precalcClearShader,
			math.ceil(precalcCanvas:getWidth() / w),
			math.ceil(precalcCanvas:getHeight() / h),
			math.ceil(precalcCanvas:getLayerCount() / d)
		)
	end
	-- local function clearPrecalc()
	-- 	for i = 1, precalcCanvas:getLayerCount() do
	-- 		love.graphics.setCanvas(precalcCanvas, i)
	-- 		love.graphics.clear()
	-- 	end
	-- 	love.graphics.setCanvas()
	-- end

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
			local function nextRandomNoiseValues()
				self:seedCelestialRNG(self:getShapeIntegralNoiseSeed(averagingIteration, consts.shapeIntegralNoiseSeedTypes.intensities))
				if childPointLayer.hasNoiseEmission then
					childPointLayer:randomiseValueNoiseCore("Emission", childPointLayer.maxNoiseValuesEmission)
				end
				if childPointLayer.hasNoiseAttenuation then
					childPointLayer:randomiseValueNoiseCore("Attenuation", childPointLayer.maxNoiseValuesAttenuation)
				end
				averagingIteration = averagingIteration + 1
			end

			local weightTotalForAllShapeTypeInfos = 0
			local intensityTotalRForAllShapeTypeInfos = 0
			local intensityTotalGForAllShapeTypeInfos = 0
			local intensityTotalBForAllShapeTypeInfos = 0
			local mulByResultDirGroup = {} -- Starts at 0
			for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
				local resultBufferDirGroup = 0

				local attenuationSamples = countsByLayer[pointLayer].attenuationSamplesFromInfos[shapeTypeInfo]
				for attenuationId = 0, attenuationSamples - 1 do
					local attLerp = attenuationSamples > 1 and ((attenuationId + 0.5) / attenuationSamples) or 0.5
					local attMin, attMax
					if shapeTypeInfo.attenuationInfo then
						attMin = shapeTypeInfo.attenuationInfo.mulRangeMin
						attMax = shapeTypeInfo.attenuationInfo.mulRangeMax
					else
						attMin = 0
						attMax = 0
					end
					local attenuationMultiplier = attMin + attLerp * (attMax - attMin)

					-- TODO: If has noise then repeat this for a bunch of noise value sets
					local attenuationShapeTypeName = shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.name or consts.noAttenuationShapeTypeName
					local attenuationShapeType = self.pointLayerShapeTypes[attenuationShapeTypeName]
					local volumetricShaderParams = self.shapeIntensityPrecalcShaderParams[shapeType.name][attenuationShapeTypeName]

					local defines = volumetricShaderParams[2].defines
					defines.DIRECTION_CONST_ARRAY = directionConstArrayCode
					defines.Z_SIZE = 8
					defines.LAYERS = precalcCanvas:getLayerCount()
					defines.RESULT_CANVAS_FORMAT = format
					local volumetricShader = love.graphics.newComputeShader(unpack(volumetricShaderParams))

					if childPointLayer.hasNoiseEmission and shapeType.noiseInfo then
						if volumetricShader:hasUniform("EmissionNoiseValues") then
							volumetricShader:send("EmissionNoiseValues", childPointLayer.valueNoiseBufferEmission)
						end
					end
					if childPointLayer.hasNoiseAttenuation and attenuationShapeType.noiseInfo then
						if volumetricShader:hasUniform("AttenuationNoiseValues") then
							volumetricShader:send("AttenuationNoiseValues", childPointLayer.valueNoiseBufferAttenuation)
						end
					end

					for samplingId = 0, shapeType.sampleCount - 1 do
						local subtype = self:subtypeFromSamplingId(shapeType, samplingId)
						local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(shapeType, subtype)
						for i, parameter in ipairs(shapeType.parameters) do
							local name = "emissionShape_" .. parameter.name
							if volumetricShader:hasUniform(name) then
								volumetricShader:send(name, densityParametersScratchTable[i])
							end
						end

						for attSamplingId = 0, attenuationShapeType.sampleCount - 1 do
							nextRandomNoiseValues() -- Just randomise every now and then

							local attSubtype = self:subtypeFromSamplingId(attenuationShapeType, attSamplingId)
							local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(attenuationShapeType, attSubtype)
							for i, parameter in ipairs(attenuationShapeType.parameters) do
								local name = "attenuationShape_" .. parameter.name
								if volumetricShader:hasUniform(name) then
									volumetricShader:send(name, densityParametersScratchTable[i])
								end
							end

							local w, h, d = volumetricShader:getLocalThreadgroupSize()
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
								if volumetricShader:hasUniform("baseAttenuation") then
									volumetricShader:send("baseAttenuation", attenuationMultiplier * shaderScale ^ -1)
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

									volumetricShader:send("directionGroup", resultBufferDirGroup)

									clearPrecalc()
									love.graphics.dispatchThreadgroups(volumetricShader,
										math.ceil(precalcCanvas:getWidth() / w),
										math.ceil(precalcCanvas:getHeight() / h),
										math.ceil(precalcCanvas:getLayerCount() / d)
									)
									precalcCanvas:generateMipmaps()
									resultCopyShader:send("directionGroup", resultBufferDirGroup)
									love.graphics.dispatchThreadgroups(resultCopyShader, 1)

									local areaAveragedOverByMipmaps = (2 * samplingDiskRadius) ^ 2 -- We don't want the average so we multiply the area back in

									local good = (lower + upper) * (lower ^ 2 + upper ^ 2) / 4 -- Average volume scale with radius scales evenly distributed between lower and upper
									local bad = ((lower + upper) / 2) ^ 3 -- Volume scale of the average radius scale
									local compensate = good / bad -- (This approaches 1 as the number of scale samples increases to infinity and this is needed less)

									mulByResultDirGroup[resultBufferDirGroup] = areaAveragedOverByMipmaps / shaderScale ^ 2 * compensate
									resultBufferDirGroup = resultBufferDirGroup + 1

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
									-- local data = love.graphics.readbackTexture(precalcCanvas, nil, precalcCanvas:getMipmapCount())
									-- local r = data:getPixel(0, 0)
									-- local calculatedIntensity = r / shaderScale ^ 2 * areaAveragedOverByMipmaps / directionSamples * compensate
									-- print(calculatedIntensity / cpuside, shaderScale ^ - 1, attenuationMultiplier)

									self.loadInfo.intensitiesMeasured = self.loadInfo.intensitiesMeasured + 1
									coroutine.yield()
								end
							end
							-- Dummy sync readback to keep the loading process from becoming unresponsive??
							love.graphics.readbackBuffer(resultBuffer, 4)
							coroutine.yield()
						end
					end
				end

				local rSum, gSum, bSum = 0, 0, 0
				local bytesPerFloat = 4
				local entries = countsByLayer[pointLayer].resultBufferSizesFromInfos[shapeTypeInfo]
				local data = love.graphics.readbackBuffer(resultBuffer)
				local dataFFI = ffi.cast("float*", data:getFFIPointer())
				local strideFloats = resultBuffer:getElementStride() / bytesPerFloat
				for i = 0, entries - 1 do
					local group = math.floor(i / directionSamples)
					local mul = mulByResultDirGroup[group]
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

			-- print("gpu " .. pointLayer.averageRadiantIntensityRPerPoint, "cpu " .. pointLayer.averageUnattenuatedRadiantIntensityRPerPoint, "gpu/cpu " .. pointLayer.averageRadiantIntensityRPerPoint / pointLayer.averageUnattenuatedRadiantIntensityRPerPoint, maxRaySteps, canvasSize)
		end
	end
	coroutine.yield()
	self.loadInfo.intensitiesMeasured = nil
	self.loadInfo.intensitiesToMeasure = nil
end

return game
