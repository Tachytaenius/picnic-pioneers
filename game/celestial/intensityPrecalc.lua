-- TODO: Cache results

local ffi = require("ffi")

local mathsies = require("lib.mathsies")
local consts = require("consts")
local util = require("util")

local game = {}

-- TODO: Move to consts
local thetaSamples = 4
local phiSamples = 4
local localSizeZ = 8
local maxRaySteps = 32

local directionSamples = thetaSamples * phiSamples

local directionConstArrayCode
local cosineConstArrayCode

function game:makeRandomNoiseValues(averagingIteration, childPointLayer)
	self:seedCelestialRNG(self:getShapeIntegralNoiseSeed(averagingIteration, consts.shapeIntegralNoiseSeedTypes.intensities))
	if childPointLayer.hasNoiseEmission then
		childPointLayer:randomiseValueNoiseCore("Emission", childPointLayer.maxNoiseValuesEmission)
	end
	if childPointLayer.hasNoiseAttenuation then
		childPointLayer:randomiseValueNoiseCore("Attenuation", childPointLayer.maxNoiseValuesAttenuation)
	end
	-- Buffers are sent to the shader elsewhere (the calls above involve setArrayData (which sends the actual data to the GPU))
end

function game:clearPrecalc()
	self.precalcClearShader:send("canvas", self.precalcCanvas)
	local w, h, d = self.precalcClearShader:getLocalThreadgroupSize()
	love.graphics.dispatchThreadgroups(self.precalcClearShader,
		math.ceil(self.precalcCanvas:getWidth() / w),
		math.ceil(self.precalcCanvas:getHeight() / h),
		math.ceil(self.precalcCanvas:getLayerCount() / d)
	)
end

function game:setupPrecalcShader(shapeType, attShapeType)
	local volumetricShaderParams = self.shapeIntensityPrecalcShaderParams[shapeType.name][attShapeType.name]
	local defines = volumetricShaderParams[2].defines
	defines.DIRECTION_CONST_ARRAY = directionConstArrayCode
	defines.COSINE_CONST_ARRAY = cosineConstArrayCode
	defines.D_PHI = consts.tau / phiSamples
	defines.Z_SIZE = localSizeZ
	defines.LAYERS = self.precalcCanvas:getLayerCount()
	defines.RESULT_CANVAS_FORMAT = self.precalcCanvas:getFormat()
	local volumetricShader = love.graphics.newComputeShader(unpack(volumetricShaderParams))

	volumetricShader:send("brightnessMultiplier", 1)
	volumetricShader:send("size", {self.precalcCanvas:getDimensions()})
	volumetricShader:send("resultCanvas", self.precalcCanvas)
	volumetricShader:send("maxRaySteps", maxRaySteps)

	return volumetricShader
end

function game:sendNoiseBuffers(volumetricShader, shapeType, attShapeType, childPointLayer)
	if childPointLayer.hasNoiseEmission and shapeType.noiseInfo then
		if volumetricShader:hasUniform("EmissionNoiseValues") then
			volumetricShader:send("EmissionNoiseValues", childPointLayer.valueNoiseBufferEmission)
		end
	end
	if childPointLayer.hasNoiseAttenuation and attShapeType.noiseInfo then
		if volumetricShader:hasUniform("AttenuationNoiseValues") then
			volumetricShader:send("AttenuationNoiseValues", childPointLayer.valueNoiseBufferAttenuation)
		end
	end
end

function game:sendSubtypeParams(volumetricShader, virtualObject)
	-- Emission
	local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(virtualObject.shapeType, virtualObject.subtypeId)
	for i, parameter in ipairs(virtualObject.shapeType.parameters) do
		local name = "emissionShape_" .. parameter.name
		if volumetricShader:hasUniform(name) then
			volumetricShader:send(name, densityParametersScratchTable[i])
		end
	end

	-- Attenuation
	local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(virtualObject.attShapeType, virtualObject.attSubtypeId)
	for i, parameter in ipairs(virtualObject.attShapeType.parameters) do
		local name = "attenuationShape_" .. parameter.name
		if volumetricShader:hasUniform(name) then
			volumetricShader:send(name, densityParametersScratchTable[i])
		end
	end
end

function game:sendRadiusBasedUniforms(volumetricShader, virtualObject, virtualObjectNumber, childPointLayer, shaderScale, samplingDiskRadius)
	if volumetricShader:hasUniform("baseEmission") then
		volumetricShader:send("baseEmission", {
			shaderScale ^ -1 * childPointLayer.maxPointDensity * childPointLayer.averageRadiantIntensityRPerPoint,
			shaderScale ^ -1 * childPointLayer.maxPointDensity * childPointLayer.averageRadiantIntensityGPerPoint,
			shaderScale ^ -1 * childPointLayer.maxPointDensity * childPointLayer.averageRadiantIntensityBPerPoint
		})
	end
	if volumetricShader:hasUniform("baseAttenuation") then
		volumetricShader:send("baseAttenuation", virtualObject.attMultiplier * shaderScale ^ -1)
	end
	volumetricShader:send("shapeRadii", {
		shaderScale * virtualObject.scale,
		shaderScale * virtualObject.scale,
		shaderScale * virtualObject.zScaleRatio * virtualObject.scale
	})
	volumetricShader:send("samplingDiskRadius", samplingDiskRadius)
	volumetricShader:send("directionGroup", virtualObjectNumber)
end

function game:doPrecalcDispatch(volumetricShader, virtualObjectNumber)
	self:clearPrecalc()

	local w, h, d = volumetricShader:getLocalThreadgroupSize()
	love.graphics.dispatchThreadgroups(volumetricShader,
		math.ceil(self.precalcCanvas:getWidth() / w),
		math.ceil(self.precalcCanvas:getHeight() / h),
		math.ceil(self.precalcCanvas:getLayerCount() / d)
	)
	self.precalcCanvas:generateMipmaps()
	self.resultCopyShader:send("directionGroup", virtualObjectNumber)
	love.graphics.dispatchThreadgroups(self.resultCopyShader, 1)
end

function game:processIntensities(shapeTypeInfo, virtualObjectCount, extraInfoPerVirtualObject, dataFFI, strideFloats)
	local dPhi = consts.tau / phiSamples

	for virtualObjectNumber = 0, virtualObjectCount - 1 do
		local extra = extraInfoPerVirtualObject[virtualObjectNumber]

		local areaAveragedOverByMipmaps = (2 * extra.samplingDiskRadius) ^ 2 -- We don't want the average for each direction so we multiply the area back in
		local shaderScale = extra.shaderScale

		local sumR = 0
		local sumG = 0
		local sumB = 0
		local i = 0
		for thetaSampleId = 0, thetaSamples - 1 do
			local theta = consts.tau / 2 * thetaSampleId / thetaSamples
			local nextTheta = consts.tau / 2 * (thetaSampleId + 1) / thetaSamples
			local cosine = math.cos(theta)
			local nextCosine = math.cos(nextTheta)
			local multiplier = cosine - nextCosine
			for phiSampleId = 0, phiSamples - 1 do
				local phi = consts.tau * (phiSampleId + 0.5) / phiSamples

				local baseFloatIndex = (i + directionSamples * virtualObjectNumber) * strideFloats
				local sampleR = dataFFI[baseFloatIndex + 0] * areaAveragedOverByMipmaps / shaderScale ^ 2
				local sampleG = dataFFI[baseFloatIndex + 1] * areaAveragedOverByMipmaps / shaderScale ^ 2
				local sampleB = dataFFI[baseFloatIndex + 2] * areaAveragedOverByMipmaps / shaderScale ^ 2
				sumR = sumR + sampleR * dPhi * multiplier
				sumG = sumG + sampleG * dPhi * multiplier
				sumB = sumB + sampleB * dPhi * multiplier

				i = i + 1
			end
		end
		-- Divide by full sphere solid angle to get intensity instead of flux
		local avgIntensityR = sumR / (2 * consts.tau)
		local avgIntensityG = sumG / (2 * consts.tau)
		local avgIntensityB = sumB / (2 * consts.tau)
		local rgb = shapeTypeInfo.unscaledIntensities[virtualObjectNumber]
		-- Gets averaged over multiple noise averaging iterations
		rgb.r = rgb.r + avgIntensityR / extra.virtualObject.scale ^ 3
		rgb.g = rgb.g + avgIntensityG / extra.virtualObject.scale ^ 3
		rgb.b = rgb.b + avgIntensityB / extra.virtualObject.scale ^ 3
	end
end

function game:codegenIntensityPrecalcArrays()
	-- Get cosines
	local cosines = {}
	for thetaSampleId = 0, thetaSamples do -- One more than there are theta samples
		local theta = consts.tau / 2 * thetaSampleId / thetaSamples
		local cosine = math.cos(theta)
		table.insert(cosines, cosine)
	end
	cosineConstArrayCode = "const float cosines[] = float[](" .. table.concat(cosines, ", ") .. ");"

	-- Get directions
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
	directionConstArrayCode = table.concat(directionConstArrayCodeLines, " ")
end

function game:makePrecalcGraphicsObjects(maxRequiredResultBufferSize)
	local power = 5
	local canvasSize = 2 ^ power -- For nice doubling/halving mipchain

	self.precalcCanvas = love.graphics.newCanvas(canvasSize, canvasSize, {
		format = "rgba32f",
		debugname = "Intensity Precalculation Canvas",
		mipmaps = "manual",
		type = "array",
		layers = directionSamples,
		computewrite = true
	})

	self.precalcClearShader = love.graphics.newComputeShader("shaders/misc/precalcClear.glsl", {
		debugname = "Intensity Precalculation Clear Shader",
		defines = {
			FORMAT = self.precalcCanvas:getFormat()
		}
	})

	self.resultCopyShader = love.graphics.newComputeShader("shaders/misc/resultCopy.glsl", {
		debugname = "Intensity Precalculation Result Copy Shader",
		defines = {
			LOD = self.precalcCanvas:getMipmapCount() - 1,
			LAYERS = self.precalcCanvas:getLayerCount()
		}
	})
	self.resultCopyShader:send("readCanvas", self.precalcCanvas)

	self.resultBuffer = love.graphics.newBuffer(consts.vec3BufferFormat, maxRequiredResultBufferSize, {
		shaderstorage = true,
		debugname = "Intensity Precalculation Result Buffer"
	})
	self.resultCopyShader:send("Results", self.resultBuffer)
end

function game:getIntensityForLowestLayer()
	local pointLayer = self.pointLayers[#self.pointLayers]

	-- TODO: Stars as shape types
	-- TODO: Remove deterministic unattenuated CPU calculations from game
	local starAverageRadiantIntensityR = pointLayer.averageUnattenuatedRadiantIntensityRPerPoint
	local starAverageRadiantIntensityG = pointLayer.averageUnattenuatedRadiantIntensityGPerPoint
	local starAverageRadiantIntensityB = pointLayer.averageUnattenuatedRadiantIntensityBPerPoint

	pointLayer.averageRadiantIntensityRPerPoint = starAverageRadiantIntensityR
	pointLayer.averageRadiantIntensityGPerPoint = starAverageRadiantIntensityG
	pointLayer.averageRadiantIntensityBPerPoint = starAverageRadiantIntensityB
end

function game:countIntensitiesToMeasure()
	local intensitiesToMeasure = 0
	local maxRequiredResultBufferSize = 0
	local countsByLayer = {}
	for pointLayerIndex = #self.pointLayers, 1, -1 do
		local pointLayer = self.pointLayers[pointLayerIndex]
		if pointLayerIndex == #self.pointLayers then
			goto continue
		else
			local counts = {}
			countsByLayer[pointLayerIndex] = counts

			counts.scaleSamplesFromInfos = {}
			counts.zRatioSamplesFromInfos = {}

			counts.attenuationSamplesFromInfos = {}

			counts.resultBufferSizesFromInfos = {}
			counts.virtualObjectCountsFromInfos = {}

			counts.averagingIterationsFromInfos = {}

			for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]

				-- TODO: Move sample counts to consts too

				local zRatioSamplesThis
				if shapeType.needsTrueRatio then
					zRatioSamplesThis = shapeType.zScaleRatioSamples
				else
					zRatioSamplesThis = 3
				end

				local scaleSamplesThis = 5

				local attenuationSamplesThis = not shapeTypeInfo.attenuationInfo and 1 or
					shapeTypeInfo.attenuationInfo.mulRangeMin == shapeTypeInfo.attenuationInfo.mulRangeMax and 1 or
					4

				local attShapeType = self.pointLayerShapeTypes[shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.name or consts.noAttenuationShapeTypeName]
				local virtualObjectsThisInfo = -- Virtual objects as in, the "virtual" objects that are imaged on the GPU
					scaleSamplesThis *
					zRatioSamplesThis *
					shapeType.sampleCount *
					attShapeType.sampleCount *
					attenuationSamplesThis
				local hasNoise = shapeType.noiseInfo or attShapeType.noiseInfo
				local averagingIterationCount = hasNoise and 3 or 1
				local resultBufferSizeThis = virtualObjectsThisInfo * directionSamples
				maxRequiredResultBufferSize = math.max(maxRequiredResultBufferSize, resultBufferSizeThis)
				intensitiesToMeasure = intensitiesToMeasure + virtualObjectsThisInfo * averagingIterationCount

				counts.scaleSamplesFromInfos[shapeTypeInfo] = scaleSamplesThis
				counts.zRatioSamplesFromInfos[shapeTypeInfo] = zRatioSamplesThis
				counts.resultBufferSizesFromInfos[shapeTypeInfo] = resultBufferSizeThis
				counts.virtualObjectCountsFromInfos[shapeTypeInfo] = virtualObjectsThisInfo
				counts.attenuationSamplesFromInfos[shapeTypeInfo] = attenuationSamplesThis
				counts.averagingIterationsFromInfos[shapeTypeInfo] = averagingIterationCount
			end
		end
	    ::continue::
	end
	return intensitiesToMeasure, maxRequiredResultBufferSize, countsByLayer
end

function game:doIntensityPrecalcShapeTypeInfoAveragingIteration(pointLayer, shapeTypeInfo, volumetricShader, layerCountSet)
	local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
	local attenuationShapeTypeName = shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.name or consts.noAttenuationShapeTypeName
	local attenuationShapeType = self.pointLayerShapeTypes[attenuationShapeTypeName]

	local attenuationSamples = layerCountSet.attenuationSamplesFromInfos[shapeTypeInfo]
	local scaleSampleCount = layerCountSet.scaleSamplesFromInfos[shapeTypeInfo]
	local zRatioSampleCount = layerCountSet.zRatioSamplesFromInfos[shapeTypeInfo]

	local virtualObjectNumber = 0
	local extraInfoPerVirtualObject = {}

	for samplingId = 0, shapeType.sampleCount - 1 do
		local subtypeId = self:subtypeFromSamplingId(shapeType, samplingId)
		for attSamplingId = 0, attenuationShapeType.sampleCount - 1 do
			local attSubtypeId = self:subtypeFromSamplingId(attenuationShapeType, attSamplingId)
			local virtualObject = { -- This table is reused
				shapeType = shapeType,
				attShapeType = attenuationShapeType,
				subtypeId = subtypeId,
				attSubtypeId = attSubtypeId
			}

			self:sendSubtypeParams(volumetricShader, virtualObject)

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
				virtualObject.attMultiplier = attenuationMultiplier

				for scaleSampleId = 0, scaleSampleCount - 1 do
					local scaleLerp = scaleSampleCount > 1 and (scaleSampleId / (scaleSampleCount - 1)) or 0.5
					local scale = shapeTypeInfo.scaleMin + scaleLerp * (shapeTypeInfo.scaleMax - shapeTypeInfo.scaleMin)
					virtualObject.scale = scale

					for zRatioSampleId = 0, zRatioSampleCount - 1 do
						local zScaleRatioLerp = zRatioSampleCount > 1 and (zRatioSampleId / (zRatioSampleCount - 1)) or 0.5
						local zRatio = shapeType.zScaleRatioMin + zScaleRatioLerp * (shapeType.zScaleRatioMax - shapeType.zScaleRatioMin)
						virtualObject.zScaleRatio = zRatio

						-- All radius-based info acquired

						local shaderScale = 1 / virtualObject.scale
						local samplingDiskRadius = math.max(virtualObject.zScaleRatio, 1) * virtualObject.scale * shaderScale

						extraInfoPerVirtualObject[virtualObjectNumber] = {
							virtualObject = util.shallowClone(virtualObject),
							shaderScale = shaderScale,
							scaleIteration = scaleSampleId,
							samplingDiskRadius = samplingDiskRadius
						}

						self:sendRadiusBasedUniforms(volumetricShader, virtualObject, virtualObjectNumber, pointLayer.childPointLayer, shaderScale, samplingDiskRadius)

						self:doPrecalcDispatch(volumetricShader, virtualObjectNumber)
						virtualObjectNumber = virtualObjectNumber + 1
						self.loadInfo.intensitiesMeasured = self.loadInfo.intensitiesMeasured + 1
						self.loadInfo.intensityBreakCountdown = self.loadInfo.intensityBreakCountdown - 1
						if self.loadInfo.intensityBreakCountdown <= 0 then
							self.loadInfo.intensityBreakCountdown = self.loadInfo.intensityBreakInterval
							self.loadInfo.forceLoadingBreak = true
						end
						coroutine.yield()
					end
				end
			end
		end
	end

	assert(virtualObjectNumber == layerCountSet.resultBufferSizesFromInfos[shapeTypeInfo] / directionSamples and virtualObjectNumber == layerCountSet.virtualObjectCountsFromInfos[shapeTypeInfo], "Something went wrong with the precalculation stuff. Three values should be equal but they're not.")

	local data = love.graphics.readbackBuffer(self.resultBuffer)
	local dataFFI = ffi.cast("float*", data:getFFIPointer())
	local strideFloats = self.resultBuffer:getElementStride() / consts.bytesPerGPUVar

	self:processIntensities(shapeTypeInfo, layerCountSet.virtualObjectCountsFromInfos[shapeTypeInfo], extraInfoPerVirtualObject, dataFFI, strideFloats)

	return extraInfoPerVirtualObject
end

function game:handleShapeTypeInfoPrecalc(pointLayer, shapeTypeInfo, layerCountSet)
	local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
	local attShapeType = self.pointLayerShapeTypes[shapeTypeInfo.attenuationInfo and shapeTypeInfo.attenuationInfo.name or consts.noAttenuationShapeTypeName]
	local volumetricShader = self:setupPrecalcShader(shapeType, attShapeType)
	self:sendNoiseBuffers(volumetricShader, shapeType, attShapeType, pointLayer.childPointLayer)

	local unscaledIntensities = { -- All divided by their scales cubed
		-- As well as the array part:
		scales = layerCountSet.scaleSamplesFromInfos[shapeTypeInfo],
		zRatios = layerCountSet.zRatioSamplesFromInfos[shapeTypeInfo],
		shapeSampleCount = shapeType.sampleCount,
		attenuationShapeSampleCount = attShapeType.sampleCount,
		attenuationSamples = layerCountSet.attenuationSamplesFromInfos[shapeTypeInfo]
	}
	shapeTypeInfo.unscaledIntensities = unscaledIntensities
	local virtualObjectCount = layerCountSet.virtualObjectCountsFromInfos[shapeTypeInfo]
	for i = 0, virtualObjectCount - 1 do
		-- These are added to over multiple averaging iterations, and then divided down after the iterations are complete
		unscaledIntensities[i] = {
			r = 0,
			g = 0,
			b = 0
		}
	end

	local averagingIterationCount = layerCountSet.averagingIterationsFromInfos[shapeTypeInfo]
	local extraInfoPerVirtualObject
	for averagingIteration = 0, averagingIterationCount - 1 do
		self:makeRandomNoiseValues(averagingIteration, pointLayer.childPointLayer)
		extraInfoPerVirtualObject = self:doIntensityPrecalcShapeTypeInfoAveragingIteration(pointLayer, shapeTypeInfo, volumetricShader, layerCountSet)
	end

	local infoR, infoG, infoB = 0, 0, 0
	for i = 0, virtualObjectCount - 1 do
		local rgb = unscaledIntensities[i]
		rgb.r = rgb.r / averagingIterationCount
		rgb.g = rgb.g / averagingIterationCount
		rgb.b = rgb.b / averagingIterationCount

		-- For averaging for the whole layer
		local extra = extraInfoPerVirtualObject[i]

		local scaleMin = shapeTypeInfo.scaleMin
		local scaleMax = shapeTypeInfo.scaleMax

		local lerpStart = extra.scaleIteration / unscaledIntensities.scales
		local min = scaleMin + lerpStart * (scaleMax - scaleMin)

		local lerpEnd = (extra.scaleIteration + 1) / unscaledIntensities.scales
		local max = scaleMin + lerpEnd * (scaleMax - scaleMin)

		local scaleAverage = (min + max) * (min ^ 2 + max ^ 2) / 4
		infoR = infoR + rgb.r * scaleAverage
		infoG = infoG + rgb.g * scaleAverage
		infoB = infoB + rgb.b * scaleAverage
	end

	infoR = infoR / virtualObjectCount
	infoG = infoG / virtualObjectCount
	infoB = infoB / virtualObjectCount

	return shapeTypeInfo.weight, infoR, infoG, infoB
end

function game:getPointLayerIntensities()
	local intensitiesToMeasure, maxRequiredResultBufferSize, countsByLayer = self:countIntensitiesToMeasure()
	self:codegenIntensityPrecalcArrays()
	self:makePrecalcGraphicsObjects(maxRequiredResultBufferSize)

	self:getIntensityForLowestLayer()

	self.loadInfo.intensitiesMeasured = 0
	self.loadInfo.intensitiesToMeasure = intensitiesToMeasure
	self.loadInfo.intensityBreakInterval = 20
	self.loadInfo.intensityBreakCountdown = self.loadInfo.intensityBreakInterval
	coroutine.yield()

	for pointLayerIndex = #self.pointLayers - 1, 1, -1 do
		local pointLayer = self.pointLayers[pointLayerIndex]

		local weightTotalForAllShapeTypeInfos = 0
		local intensityTotalRForAllShapeTypeInfos = 0
		local intensityTotalGForAllShapeTypeInfos = 0
		local intensityTotalBForAllShapeTypeInfos = 0

		for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
			local infoWeight, infoR, infoG, infoB = self:handleShapeTypeInfoPrecalc(pointLayer, shapeTypeInfo, countsByLayer[pointLayerIndex])
			weightTotalForAllShapeTypeInfos = weightTotalForAllShapeTypeInfos + infoWeight
			intensityTotalRForAllShapeTypeInfos = intensityTotalRForAllShapeTypeInfos + infoR * infoWeight
			intensityTotalGForAllShapeTypeInfos = intensityTotalGForAllShapeTypeInfos + infoG * infoWeight
			intensityTotalBForAllShapeTypeInfos = intensityTotalBForAllShapeTypeInfos + infoB * infoWeight
		end

		pointLayer.averageRadiantIntensityRPerPoint = intensityTotalRForAllShapeTypeInfos / weightTotalForAllShapeTypeInfos
		pointLayer.averageRadiantIntensityGPerPoint = intensityTotalGForAllShapeTypeInfos / weightTotalForAllShapeTypeInfos
		pointLayer.averageRadiantIntensityBPerPoint = intensityTotalBForAllShapeTypeInfos / weightTotalForAllShapeTypeInfos

		-- print("gpu " .. pointLayer.averageRadiantIntensityRPerPoint, "cpu " .. pointLayer.averageUnattenuatedRadiantIntensityRPerPoint, "gpu/cpu " .. pointLayer.averageRadiantIntensityRPerPoint / pointLayer.averageUnattenuatedRadiantIntensityRPerPoint)
	end

	self.loadInfo.intensitiesMeasured = nil
	self.loadInfo.intensitiesToMeasure = nil
	coroutine.yield()
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
	addShape(shapeType, shapeSubtypeId)
	addShape(attenuationShapeType, attenuationShapeSubtypeId)
	addDimension(attenuationMin, attenuationMax, attenuationMultiplier, intensities.attenuationSamples)
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
