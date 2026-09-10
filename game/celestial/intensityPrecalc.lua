-- TODO: Needs complete rewrite. Very unconfident in the correctness of this code. Upon rewriting, use functions much more to make cleaner, easier-to-work-with code. Notably, the sin(theta) stuff is broken and ...... ughh

local ffi = require("ffi")

local mathsies = require("lib.mathsies")
local consts = require("consts")
local util = require("util")

local game = {}

function game:getPointLayerIntensities()
	-- No need for dmath with graphics, this is all going on the GPU where we don't trust any determinism at all (NOTE: this means the result of these calculations, the average (attenuated) radiant intensities, are not to be considered deterministic)
	local format = "rgba32f"
	local maxRaySteps = 32
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
					local maxZRatioSamples = 3
					zRatioSamplesThis = math.min(maxZRatioSamples, math.max(1, math.floor(0.5 + zScaleRatioDiff * zRatioSamplesPerRatioDiff))) -- We ignore needsTrueRatio and shapeType.zScaleRatioSamples
				end

				local scaleSamplesThis = 6

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

	-- Get sines
	local sineTotal = 0
	local sines = {}
	for thetaSampleId = 0, thetaSamples - 1 do
		local theta = consts.tau / 2 * (thetaSampleId + 0.5) / thetaSamples
		local sine = math.sin(theta)
		table.insert(sines, sine)
		sineTotal = sineTotal + sine -- Divide by this. Probably wrong. Very unconfident in all of this and wanting to rewrite it all.
	end
	local sineConstArrayCode = "const float sines[] = float[](" .. table.concat(sines, ", ") .. ");"

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
			local scaleInfoByDirGroup = {}
			for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
				local resultBufferDirGroup = 0

				local attenuationSamples = countsByLayer[pointLayer].attenuationSamplesFromInfos[shapeTypeInfo]
				for attenuationId = 0, attenuationSamples - 1 do
					local attLerp = attenuationSamples > 1 and (attenuationId / (attenuationSamples - 1)) or 0.5
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
					defines.SINE_CONST_ARRAY = sineConstArrayCode
					defines.DTHETA_DPHI = (consts.tau / 2) / (thetaSamples) * consts.tau / (phiSamples)
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
								local scaleLerp = scaleSampleId / (scaleSampleCount - 1)
								local scale = shapeTypeInfo.scaleMin + scaleLerp * (shapeTypeInfo.scaleMax - shapeTypeInfo.scaleMin)

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
									local zScaleRatioLerp = zRatioSampleCount > 1 and (zRatioSampleId / (zRatioSampleCount - 1)) or 0.5
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

									mulByResultDirGroup[resultBufferDirGroup] = areaAveragedOverByMipmaps / shaderScale ^ 2 / scale ^ 3
									scaleInfoByDirGroup[resultBufferDirGroup] = scaleSampleId

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

				local bytesPerFloat = 4
				local entries = countsByLayer[pointLayer].resultBufferSizesFromInfos[shapeTypeInfo]
				local data = love.graphics.readbackBuffer(resultBuffer)
				local dataFFI = ffi.cast("float*", data:getFFIPointer())
				local strideFloats = resultBuffer:getElementStride() / bytesPerFloat

				shapeTypeInfo.unscaledIntensities = { -- NOTE: All divided by their radius cubed
					-- Array part of this table starts at 0
					scales = countsByLayer[pointLayer].scaleSamplesFromInfos[shapeTypeInfo],
					zRatios = countsByLayer[pointLayer].zRatioSamplesFromInfos[shapeTypeInfo],
					shapeSampleCount = shapeType.sampleCount,
					attenuationShapeSampleCount = self.pointLayerShapeTypes[shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.name or consts.noAttenuationShapeTypeName].sampleCount,
					attenuationSamples = countsByLayer[pointLayer].attenuationSamplesFromInfos[shapeTypeInfo]
				}

				local rSum, gSum, bSum = 0, 0, 0
				local groupCount = math.floor(entries / directionSamples)
				for group = 0, groupCount - 1 do
					local r = 0
					local g = 0
					local b = 0

					for i = 0, directionSamples - 1 do
						local i2 = group * directionSamples + i

						r = r + dataFFI[i2 * strideFloats + 0]
						g = g + dataFFI[i2 * strideFloats + 1]
						b = b + dataFFI[i2 * strideFloats + 2]
					end
					local mul = mulByResultDirGroup[group]
					r = r * mul / directionSamples
					g = g * mul / directionSamples
					b = b * mul / directionSamples

					shapeTypeInfo.unscaledIntensities[group] = {
						r = r,
						b = b,
						g = g
					}

					-- For averaging for the whole layer
					if group < groupCount - 1 then
						local min = scaleInfoByDirGroup[group] / (shapeTypeInfo.unscaledIntensities.scales - 1)
						local max = (scaleInfoByDirGroup[group] + 1) / (shapeTypeInfo.unscaledIntensities.scales - 1)
						local scaleAverage = (min + max) * (min ^ 2 + max ^ 2) / 4
						rSum = rSum + r * scaleAverage
						gSum = gSum + g * scaleAverage
						bSum = bSum + b * scaleAverage
					end
				end

				local r = rSum / groupCount
				local g = gSum / groupCount
				local b = bSum / groupCount




				local rSum, gSum, bSum = 0, 0, 0
				local count = 0
				local scaleStep = 1 / 25
				local attMin, attMax, attShape
				if shapeTypeInfo.attenuationInfo then
					attMin = shapeTypeInfo.attenuationInfo.mulRangeMin
					attMax = shapeTypeInfo.attenuationInfo.mulRangeMax
					attShape = shapeTypeInfo.attenuationInfo.name
				else
					attMin = 0
					attMax = 0
					attShape = consts.noAttenuationShapeTypeName
				end
				attShape = self.pointLayerShapeTypes[attShape]
				for s = 0, shapeTypeInfo.unscaledIntensities.scales - 1, scaleStep do
					for z = 0, shapeTypeInfo.unscaledIntensities.zRatios - 1 do
						for a = 0, shapeTypeInfo.unscaledIntensities.attenuationSamples - 1 do
							for sh = 0, shapeTypeInfo.unscaledIntensities.shapeSampleCount - 1 do
								for ash = 0, shapeTypeInfo.unscaledIntensities.attenuationShapeSampleCount - 1 do
									local r, g, b = self:getInterpolatedIntensity(
										shapeTypeInfo,
										util.lerp(shapeTypeInfo.scaleMin, shapeTypeInfo.scaleMax, s / (shapeTypeInfo.unscaledIntensities.scales - 1)),
										util.lerp(shapeType.zScaleRatioMin, shapeType.zScaleRatioMax, z / (shapeTypeInfo.unscaledIntensities.zRatios - 1)),
										util.lerp(attMin, attMax, a / (shapeTypeInfo.unscaledIntensities.attenuationSamples - 1)),
										self:subtypeFromSamplingId(shapeType, sh),
										self:subtypeFromSamplingId(attShape, ash)
									)
									rSum = rSum + r
									gSum = gSum + g
									bSum = bSum + b
									count = count + 1
								end
							end
						end
					end
				end
				local r = rSum / count
				local g = gSum / count
				local b = bSum / count



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

local scratchTable = {}
function game:getInterpolatedIntensity(shapeTypeInfo, scale, zScaleRatio, attenuationMultiplier, shapeSubtypeId, attenuationShapeSubtypeId)
	local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
	local attenuationShapeType = self.pointLayerShapeTypes[shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.name or consts.noAttenuationShapeTypeName]
	local attenuationMin = shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.mulRangeMin or 0
	local attenuationMax = shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.mulRangeMax or 0
	local intensities = shapeTypeInfo.unscaledIntensities

	local numParams =
		3 + -- For scale, zScaleRatio, and attenuationMultiplier
		#shapeType.parameters +
		#attenuationShapeType.parameters

	local lerpFactors = {}
	local leftSamples = {}
	local rightSamples = {}
	local counts = {}
	local function addDimension(lower, upper, value, samples)
		if samples == 1 then
			-- Skip this dimension
			numParams = numParams - 1
			return
		end

		local lerpOverall = lower == upper and 0.5 or (value - lower) / (upper - lower)
		local left = samples == 1 and 0 or math.min(samples - 2, math.floor(lerpOverall * (samples - 1)))
		local right = math.min(left + 1, samples - 1)
		local lerp = lerpOverall * (samples - 1) - left

		table.insert(lerpFactors, lerp)
		table.insert(leftSamples, left)
		table.insert(rightSamples, right)
		table.insert(counts, samples)
	end

	local function addShape(shapeType, shapeSubtypeId)
		self:decodeShapeSubtypeIntoScratchTable(shapeType, shapeSubtypeId, scratchTable)
		for i, paramVal in ipairs(scratchTable) do
			local paramDef = shapeType.parameters[i]
			addDimension(paramDef.rangeMin, paramDef.rangeMax, paramVal, paramDef.samples)
		end
	end

	-- Must match order in precalculation
	addDimension(attenuationMin, attenuationMax, attenuationMultiplier, intensities.attenuationSamples)
	addShape(shapeType, shapeSubtypeId)
	addShape(attenuationShapeType, attenuationShapeSubtypeId)
	addDimension(shapeTypeInfo.scaleMin, shapeTypeInfo.scaleMax, scale, intensities.scales)
	addDimension(shapeType.zScaleRatioMin, shapeType.zScaleRatioMax, zScaleRatio, intensities.zRatios)

	local mixNSampleArgs = {}
	for gridSides = 0, 2 ^ numParams - 1 do
		local index = 0
		for i = 1, numParams do
			local bit = i - 1
			local doLeft = math.floor(gridSides / 2 ^ bit) % 2 == 0
			local paramSample = (doLeft and leftSamples or rightSamples)[i]
			index = index * counts[i] + paramSample
		end
		local intensity = intensities[index]
		table.insert(mixNSampleArgs, mathsies.vec3(
			intensity.r,
			intensity.g,
			intensity.b
		))
	end
	local vec
	if #lerpFactors == 0 then
		vec = mixNSampleArgs[1]
	else
		local lerpFactorsFlipped = {}
		for i, v in ipairs(lerpFactors) do
			lerpFactorsFlipped[numParams - i + 1] = v
		end
		vec = util.mixN(lerpFactorsFlipped, unpack(mixNSampleArgs))
	end
	vec = vec * scale ^ 3
	return mathsies.vec3.components(vec)
end

return game
