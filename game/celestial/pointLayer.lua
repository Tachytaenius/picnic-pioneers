-- There are lots of different coordinate systems in this file...
-- In general, anything that needs to be both large and precise has either been avoided (e.g. by scaling down), or arbitrary precision numbers have been used

local ffi = require("ffi")
local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local setValueNoiseFunctionVars = require("threadCode.common.setValueNoiseFunctionVars")
local initSampleDistribution = require("threadCode.common.initSampleDistribution")

local util = require("util")
local consts = require("consts")

local game = {}

local function randomTODO(...)
	-- TODO: Not this!
	return love.math.random(...)
end
local function randomRangeTODO(lower, upper)
	return lower + love.math.random() * (upper - lower)
end

local function getBoundingBoxChunksForSize(chunkSize, x, y, z)
	-- TODO: I think this and the code using it breaks (slightly) when size[x/y/z] / chunkSize is an integer
	local minX, maxX = math.floor(-x / chunkSize), math.floor(x / chunkSize)
	local minY, maxY = math.floor(-y / chunkSize), math.floor(y / chunkSize)
	local minZ, maxZ = math.floor(-z / chunkSize), math.floor(z / chunkSize)
	return minX, maxX, minY, maxY, minZ, maxZ
end

local galaxyPointLayerInfo = {
	fixedParentObjectPosition = consts.galaxyGroupPosition,
	fixedParentObjectRadii = consts.galaxyGroupScale * mathsies.vec3(1, 1, consts.galaxyGroupZScaleRatio),
	fixedParentObjectShapeTypeName = consts.galaxyGroupShapeTypeName,
	fixedParentObjectShapeSubtypeId = 0, -- TODO: Allow selecting from closest subtype to given parameters...?
	fixedParentObjectAttenuationShapeTypeName = consts.galaxyGroupAttenuationShapeName,
	fixedParentObjectAttenuationShapeSubtypeId = 0
}

galaxyPointLayerInfo.features = {
	-- "sent" means present on both CPU and GPU, "unsent" means only present on CPU, nil means not present
	shapeTypeSubtypeIds = "sent",
	attenuationShapeTypeSubtypeIds = "sent",
	radii = "unsent",
	mass = "unsent",

	shapeTypeSet = {
		{
			name = "ellipticalGalaxy",
			weight = 1,
			scaleMin = 7.5e18,
			scaleMax = 1e19,
			attenuationShapeTypes = {
				{
					name = "genericNebulae",
					weight = 1,
					-- 2.5 * 10^-20 metres^-1 in the middle, converted from "1.8 magnitudes per kiloparsec" attenuation coefficient measurement near the sun
					mulRangeMin = 6.25e-21,
					mulRangeMax = 1e-19
				}
			}
		},
		{
			name = "spiralGalaxy",
			weight = 7,
			scaleMin = 3e19,
			scaleMax = 7.5e20,
			attenuationShapeTypes = {
				{
					name = "genericNebulae",
					weight = 1,
					mulRangeMin = 6.25e-21,
					mulRangeMax = 1e-19
				}
			}
		}
	}
}

function galaxyPointLayerInfo:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count)
	local randomChoice = util.weightedRandomChoice
	local shapeTypeSet = self.features.shapeTypeSet
	local extraInfo = self.chunkExtraInfo[chunkBufferIndex]
	local radii = extraInfo.radii
	local mass = extraInfo.mass
	local nextLayerMaxDensity = self.childPointLayer.maxPointDensity
	local nextLayerAverageMassPerPoint = self.childPointLayer.averageMassPerPoint
	local nextLayerAverageLuminousFluxRPerPoint = self.childPointLayer.averageLuminousFluxRPerPoint
	local nextLayerAverageLuminousFluxGPerPoint = self.childPointLayer.averageLuminousFluxGPerPoint
	local nextLayerAverageLuminousFluxBPerPoint = self.childPointLayer.averageLuminousFluxBPerPoint
	local luminousFluxScale = self.chunkSize ^ -2
	for i = 0, count - 1 do
		local x = randomTODO()
		local y = randomTODO()
		local z = randomTODO()

		local choice = randomChoice(shapeTypeSet, randomGeneratorTODO)
		local shapeType = self.gameObject.pointLayerShapeTypes[choice.name]
		local shapeTypeId = shapeType.id
		local shapeSubtypeId = randomTODO(0, shapeType.subtypeCount - 1)

		local attenuationChoice = choice.attenuationShapeTypes and randomChoice(choice.attenuationShapeTypes, randomGeneratorTODO)
		local attenuationType = self.gameObject.pointLayerShapeTypes[attenuationChoice and attenuationChoice.name or consts.noAttenuationShapeTypeName]
		local attenuationTypeId = attenuationType.id
		local attenuationSubtypeId = randomTODO(0, attenuationType.subtypeCount - 1)

		local scale = randomRangeTODO(choice.scaleMin, choice.scaleMax)
		local zScaleRatio = randomRangeTODO(shapeType.zScaleRatioMin, shapeType.zScaleRatioMax)

		local xRadius = scale
		local yRadius = scale
		local zRadius = scale * zScaleRatio
		radii[i * 3] = xRadius
		radii[i * 3 + 1] = yRadius
		radii[i * 3 + 2] = zRadius

		local baseAmount
		if shapeType.needsTrueRatio then
			-- Interpolate between samples
			local where = shapeType.zScaleRatioSamples * (zScaleRatio - shapeType.zScaleRatioMin) / (shapeType.zScaleRatioMax - shapeType.zScaleRatioMin)
			local prevSample = math.max(0, math.min(1, math.floor(where))) -- Clamp for safety
			local whereAfterPrevious = where - prevSample -- Should be (more or less) between 0 and 1
			local samples = shapeType.subtypeBaseObjectAmounts[shapeSubtypeId]
			local sampleA = samples[prevSample]
			local sampleB = samples[math.min(shapeType.zScaleRatioSamples - 1, prevSample + 1)]
			baseAmount = sampleA + whereAfterPrevious * (sampleB - sampleA)
		else
			baseAmount = shapeType.subtypeBaseObjectAmounts[shapeSubtypeId]
		end
		local amountWithin = baseAmount * xRadius * yRadius * zRadius * nextLayerMaxDensity -- Estimate
		mass[i] = amountWithin * nextLayerAverageMassPerPoint

		local r = amountWithin * nextLayerAverageLuminousFluxRPerPoint * luminousFluxScale
		local g = amountWithin * nextLayerAverageLuminousFluxGPerPoint * luminousFluxScale
		local b = amountWithin * nextLayerAverageLuminousFluxBPerPoint * luminousFluxScale

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b, shapeTypeId, shapeSubtypeId, attenuationTypeId, attenuationSubtypeId)
	end
end

function galaxyPointLayerInfo:generateRemainingCurrentObjectInfo()
	local currentObject = self.currentObject
end

function galaxyPointLayerInfo:getGlobalCelestialObjectIdParameters(stage, forceFakeCurrentObject) -- Not quite the same as the 128-bit number split into four 32-bit numbers that this produces
	local currentObject = forceFakeCurrentObject or self.currentObject
	local objectType = consts.idObjectTypes.galaxy
	local galaxyChunkId = currentObject.chunkId
	local galaxyId = currentObject.pointId
	-- local starChunkId
	-- local starId
	-- local systemBodyId
	return objectType, stage, galaxyChunkId, galaxyId
end

local starSystemPointLayerInfo = {}

starSystemPointLayerInfo.features = {
	mass = "unsent",
	bodies = true -- Final layer, treated differently
}

function starSystemPointLayerInfo:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count)
	local extraInfo = self.chunkExtraInfo[chunkBufferIndex]
	local mass = extraInfo.mass
	local luminousFluxScale = self.chunkSize ^ -2
	for i = 0, count - 1 do
		local x = randomTODO()
		local y = randomTODO()
		local z = randomTODO()

		-- Copied in consts.lua (for now)
		local randomValue = randomTODO()
		local exponentT = consts.starMassRandomTerm1Weight * randomValue ^ consts.starMassRandomTerm1Exponent + (1 - consts.starMassRandomTerm1Weight) * randomValue
		local exponent = consts.starMassExponentRangeLow + exponentT * (consts.starMassExponentRangeHigh - consts.starMassExponentRangeLow)
		local starMass = consts.starMassMultiplier * 10 ^ exponent
		mass[i] = starMass
		local density = consts.starDensity
		local temperature = consts.starEffectiveTemperature
		local volume = starMass / density
		local radius = (volume / (2 / 3 * consts.tau)) ^ (1 / 3)
		local area = 2 * consts.tau * radius ^ 2
		local luminousExitance = consts.stefanBoltzmannConstant * temperature ^ 4
		local luminousFlux = luminousExitance * area -- TEMP, replace all the incorrect photometry terms with correct (spectral!) radiometric ones. and MAKE SURE that the vec3 spectral flux --> RGB is correct!!!!
		local r = luminousFlux * luminousFluxScale * randomRangeTODO(0.5, 1.5)
		local g = luminousFlux * luminousFluxScale * randomRangeTODO(0.5, 1.5)
		local b = luminousFlux * luminousFluxScale * randomRangeTODO(0.5, 1.5)

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b)
	end
end

function starSystemPointLayerInfo:generateRemainingCurrentObjectInfo()
	local currentObject = self.currentObject
	self.gameObject:generateStarSystem(currentObject)
end

function starSystemPointLayerInfo:getGlobalCelestialObjectIdParameters(stage)
	local parentObject = self.parentPointLayer.currentObject
	local currentObject = self.currentObject
	local objectType = consts.idObjectTypes.starSystem
	local galaxyChunkId = parentObject.chunkId
	local galaxyId = parentObject.pointId
	local starChunkId = currentObject.chunkId
	local starId = currentObject.pointId
	-- local systemBodyId
	return objectType, stage, galaxyChunkId, galaxyId, starChunkId, starId
end

function game:initPointLayers()
	self.pointLayers = {}

	self.slowdownSampleDistribution = initSampleDistribution(consts.shapeSlowdownIntegralHighestStepCount, consts.pointLayerShapeTypeAmountIntegralMaxThreads)

	-- Topmost layer is treated specially
	-- TODO: Allow it to collapse to a point when sufficiently far away. Since that's just one point there's no need for optimisations like chunks etc. Would definitely be easier if the topmost point layer has a semi-functioning parent point layer for this purpose
	local topLayer = self:newPointLayer("galaxies", "Galaxies", consts.galaxyLayerChunkSize, consts.maxGalacticDensity, 7, galaxyPointLayerInfo)
	self:newPointLayer("starSystems", "Star Systems", consts.starLayerChunkSize, consts.maxStellarDensity, 13, starSystemPointLayerInfo)

	self.valueNoiseDataReusableForPointLayers = nil -- If no point layers took this then it now no longer will be used

	-- Find distance at which top layer shape has the same angular radius as points
	local topRadius = math.max(topLayer.fixedParentObjectRadii.x, topLayer.fixedParentObjectRadii.y, topLayer.fixedParentObjectRadii.z)
	topLayer.fixedParentObjectPointDistance = self:getSphereResolvableDistance(topRadius)

	self:seedCelestialRNG(self:getGlobalCelestialObjectIdNumbers(
		consts.idObjectTypes.universe,
		consts.objectGenerationStages.noiseValues
	))
	topLayer:handleThreadedShapeInit("prepare")
	topLayer:handleThreadedShapeInit("expect")

	local highestMaxPoints
	for _, pointLayer in ipairs(self.pointLayers) do
		self.pointLayers[pointLayer.name] = pointLayer
		highestMaxPoints = highestMaxPoints and math.max(highestMaxPoints, pointLayer.maxPoints) or pointLayer.maxPoints
	end
	if highestMaxPoints then
		self.pointDrawableBuffer = love.graphics.newBuffer(consts.pointDrawableBufferFormat, highestMaxPoints, {
			shaderstorage = true,
			debugname = "Point Drawable Buffer"
		})
	end

	-- Checks

	local topLayerShapeType = self.pointLayerShapeTypes[topLayer.fixedParentObjectShapeTypeName]
	if topLayerShapeType.needsTrueRatio then
		assert(topLayer.fixedParentObjectRadii.x == topLayer.fixedParentObjectRadii.y,
			"Bad radii for top point layer. x and y must be the same for shape types that have needsTrueRatio. Objects with those shape types can only be lengthened/shortened relative to other axes on the z axis for now. Spheres or oblate/prolate spheroids, no triaxial ellipsoids."
		)
		local xyScale = topLayer.fixedParentObjectRadii.x -- x equals y was asserted
		local zScaleRatio = topLayer.fixedParentObjectRadii.z / xyScale
		if not (topLayerShapeType.zScaleRatioMin <= zScaleRatio and zScaleRatio <= topLayerShapeType.zScaleRatioMax) then
			error("Top point layer's z scale ratio is " .. zScaleRatio .. " but must be between " .. topLayerShapeType.zScaleRatioMin .. " and " .. topLayerShapeType.zScaleRatioMax)
		end
	end

	for i, pointLayer in ipairs(self.pointLayers) do
		local assertMessage = "All point layers must have shape types and not bodies except the last one"
		if i < #self.pointLayers then
			assert(pointLayer.features.shapeTypeSet and not pointLayer.features.bodies, assertMessage)
		elseif i == #self.pointLayers then
			assert(not pointLayer.features.shapeTypeSet and pointLayer.features.bodies, assertMessage)
		end
	end

	-- TODO: Verify?
	local starAverageMass = consts.averageStarMass
	local starAverageLuminousFluxR = consts.averageStarLuminousFluxR
	local starAverageLuminousFluxG = consts.averageStarLuminousFluxG
	local starAverageLuminousFluxB = consts.averageStarLuminousFluxB
	for i = #self.pointLayers, 1, -1 do
		local pointLayer = self.pointLayers[i]
		if i == #self.pointLayers then
			pointLayer.averageMassPerPoint = starAverageMass
			pointLayer.averageLuminousFluxRPerPoint = starAverageLuminousFluxR
			pointLayer.averageLuminousFluxGPerPoint = starAverageLuminousFluxG
			pointLayer.averageLuminousFluxBPerPoint = starAverageLuminousFluxB
		else
			local childPointLayer = pointLayer.childPointLayer
			local totalWeight = 0
			local averageAmountPreDivide = 0
			for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
				-- TODO: When adding attenuation, consider the average luminous flux seen from all directions. Wait, shouldn't that be luminous intensity? (TODO: Investigate any potential errors around that)

				-- NOTE: If a factor is added to make the distribution of scales non-uniform, ensure that the per-layer average mass estimates are changed accordingly
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name] -- shapeTypeInfo is the point layer's usage of the shape, shapeType is the shape type itself
				local minS, maxS = shapeTypeInfo.scaleMin, shapeTypeInfo.scaleMax
				local minZR, maxZR = shapeType.zScaleRatioMin, shapeType.zScaleRatioMax
				local averageBaseObjectAmountMultiplier =
					1 / 8 *
					(minS + maxS) *
					(minS ^ 2 + maxS ^ 2) *
					(minZR + maxZR)

				local total = 0
				assert(not shapeType.attenuation, "Attenuation shape types cannot be used for point density")
				for subtypeId = 0, shapeType.subtypeCount - 1 do
					local subtypeBaseAmount
					if shapeType.needsTrueRatio then
						subtypeBaseAmount = 0
						for zSample = 0, shapeType.zScaleRatioSamples - 1 do
							subtypeBaseAmount = subtypeBaseAmount + shapeType.subtypeBaseObjectAmounts[subtypeId][zSample]
						end
					else
						subtypeBaseAmount = shapeType.subtypeBaseObjectAmounts[subtypeId]
					end
					total = total +
						subtypeBaseAmount *
						averageBaseObjectAmountMultiplier *
						childPointLayer.maxPointDensity
				end
				local countMultiplier = shapeType.needsTrueRatio and shapeType.zScaleRatioSamples or 1
				local averageAmountThisShapeTypeInfo = total / (shapeType.subtypeCount * countMultiplier)

				averageAmountPreDivide = averageAmountPreDivide + averageAmountThisShapeTypeInfo
				totalWeight = totalWeight + shapeTypeInfo.weight
			end
			local averageAmount = averageAmountPreDivide / totalWeight
			pointLayer.averageMassPerPoint = averageAmount * childPointLayer.averageMassPerPoint
			pointLayer.averageLuminousFluxRPerPoint = averageAmount * childPointLayer.averageLuminousFluxRPerPoint
			pointLayer.averageLuminousFluxGPerPoint = averageAmount * childPointLayer.averageLuminousFluxGPerPoint
			pointLayer.averageLuminousFluxBPerPoint = averageAmount * childPointLayer.averageLuminousFluxBPerPoint
		end
	end

	-- Ensure no objects could be too big for the celestal id system to work on its contained points or to smoothly transition between resolvable and unresolved
	for i = 1, #self.pointLayers do
		local layer = self.pointLayers[i]
		if not layer.features.shapeTypeSet then
			goto continue
		end
		for j, shapeTypeInfo in ipairs(layer.features.shapeTypeSet) do
			local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
			local identifier = "point layer " .. i .. ", shape type info " .. j
			assert(shapeTypeInfo.scaleMin <= shapeTypeInfo.scaleMax, "Scale min and max are flipped for " .. identifier)
			local largestX = shapeTypeInfo.scaleMax
			local largestY = shapeTypeInfo.scaleMax
			local largestZ = shapeTypeInfo.scaleMax * shapeType.zScaleRatioMax
			local minX, maxX, minY, maxY, minZ, maxZ = getBoundingBoxChunksForSize(layer.chunkSize, largestX, largestY, largestZ)
			local widthChunks = maxX - minX + 1
			local heightChunks = maxY - minY + 1
			local depthChunks = maxZ - minZ + 1
			local largestChunkCount = widthChunks * heightChunks * depthChunks
			local maximumChunks = 2 ^ 36
			if largestChunkCount >= maximumChunks then -- 36 bits as per getGlobalCelestialObjectIdNumbers
				error("Too many chunks possible for " .. identifier .. ". Must be at most " .. maximumChunks)
			end

			local maxAllowedResolvableDistance = layer.chunkSize * consts.pointMinDistanceInChunk / 2 / consts.pointAsyncSetupDistanceMultiplier
			local maxAllowedRadius = self:getSphereRadiusFromResolvableDistance(maxAllowedResolvableDistance)
			local largestRadius = math.max(largestX, largestY, largestZ)
			-- local largestResolvableDistance = self:getSphereResolvableDistance(largestRadius)
			if largestRadius > maxAllowedRadius then
				error("Maximum size of " .. identifier .. " (" .. largestRadius .. ") is too high, must be at most " .. maxAllowedRadius)
			end
		end
	    ::continue::
	end
	-- TODO: Check universe size too (but really it should be its own point layer that only ever has one point?)
end

local pointLayerFunctions = {}

function pointLayerFunctions:getDensity(realX, realY, realZ) -- The position is in units where 1 is the side length of a chunk. Returned density is a proportion from 0 to 1, where 1 is the point layer's max density
	local shapeTypeName, shapeSubtypeId, size
	if self.parentPointLayer then
		local currentObject = self.parentPointLayer.currentObject
		assert(currentObject, "Should not be calling getDensity on a point layer if its parent doesn't have a current object")
		shapeTypeName = currentObject.shapeTypeName
		shapeSubtypeId = currentObject.shapeSubtypeId
		size = currentObject.radii
	else
		shapeTypeName = self.fixedParentObjectShapeTypeName
		shapeSubtypeId = self.fixedParentObjectShapeSubtypeId
		size = self.fixedParentObjectRadii
	end
	local shapeType = self.gameObject.pointLayerShapeTypes[shapeTypeName]
	local densityFunction = shapeType.getDensity
	local densityParametersScratchTable = self.gameObject:decodeShapeSubtypeIntoScratchTable(shapeType, shapeSubtypeId)
	self:prepareValueNoiseFunction()
	if shapeType.needsTrueRatio then
		local sizeRatios = size / math.max(size.x, size.y, size.z)
		local x = realX / size.x * self.chunkSize
		local y = realY / size.y * self.chunkSize
		local z = realZ / size.z * self.chunkSize
		return densityFunction(
			x, y, z,
			x * sizeRatios.x, y * sizeRatios.y, z * sizeRatios.z,
			unpack(densityParametersScratchTable)
		)
	else
		return densityFunction(
			realX / size.x * self.chunkSize,
			realY / size.y * self.chunkSize,
			realZ / size.z * self.chunkSize,
			unpack(densityParametersScratchTable)
		)
	end
end

-- Expects RNG to be seeded appropriately
function pointLayerFunctions:randomiseValueNoise(type)
	local suffix = type == "attenuation" and "Attenuation" or type == "emission" and "Emission"
	local relevantShapeTypeName
	if type == "emission" then
		relevantShapeTypeName =
			self.parentPointLayer and (self.parentPointLayer.currentObject or self.parentPointLayer.currentPotentialObject).shapeTypeName
			or self.fixedParentObjectShapeTypeName
	elseif type == "attenuation" then
		relevantShapeTypeName =
			self.parentPointLayer and (self.parentPointLayer.currentObject or self.parentPointLayer.currentPotentialObject).attenuationShapeTypeName
			or self.fixedParentObjectAttenuationShapeTypeName
	end
	if not relevantShapeTypeName then
		return
	end
	local shapeType = self.gameObject.pointLayerShapeTypes[relevantShapeTypeName]
	if not shapeType.noiseInfo then
		-- Won't be used, can safely leave it as it is
		return
	end
	-- This layer will have a noise buffer/data if its parent can have a shape type that has noise.
	local buffer = self["valueNoiseBuffer" .. suffix]
	local data = self["valueNoiseData" .. suffix]
	local dataFFI = self["valueNoiseDataFFI" .. suffix]
	for i = 0, shapeType.noiseInfo.requiredValueCount - 1 do
		dataFFI[i] = randomTODO()
	end
	buffer:setArrayData(data, 1, 1, shapeType.noiseInfo.requiredValueCount)
end

function pointLayerFunctions:prepareValueNoiseFunction() -- This is per shape type, so in case multiple layers use the same shape type this must be set before every use of the density function
	-- For point density (emission) only, not for attenuation
	local relevantShapeTypeName =
		self.parentPointLayer and self.parentPointLayer.currentObject.shapeTypeName
		or self.fixedParentObjectShapeTypeName
	local shapeType = self.gameObject.pointLayerShapeTypes[relevantShapeTypeName]
	if not shapeType.noiseInfo then
		return
	end
	local layers = shapeType.noiseInfo.layers
	local dataFFI = self.valueNoiseDataFFIEmission
	setValueNoiseFunctionVars(layers, dataFFI)
end

function pointLayerFunctions:getBoundingBoxChunks()
	local size
	if self.parentPointLayer then
		local currentObject = self.parentPointLayer.currentObject
		assert(currentObject, "Should not be calling getBoundingBoxChunks on a point layer if its parent doesn't have a current object")
		size = currentObject.radii
	else
		size = self.fixedParentObjectRadii
	end
	return getBoundingBoxChunksForSize(self.chunkSize, mathsies.vec3.components(size))
end

function pointLayerFunctions:setChunkPointCount(chunkBufferIndex, count)
	self.chunkPointCountDataFFI[chunkBufferIndex] = count
end

function pointLayerFunctions:getChunkPointCount(chunkBufferIndex)
	return self.chunkPointCountDataFFI[chunkBufferIndex]
end

function pointLayerFunctions:setPoint(chunkBufferIndex, pointId, ...) -- First two args start at 0.
	local index = chunkBufferIndex * self.maxPointsPerChunk + pointId
	assert(index >= 0 and index < self.maxPoints, "chunkBufferIndex and pointId given to setPoint exceed point buffer capacity")
	assert(select("#", ...) == self.pointFormatVarCount, "Incorrect number of point variables given to setPoint")
	local curAddr = index * self.pointBuffer:getElementStride() / consts.bytesPerGPUVar
	for i = 1, self.pointFormatVarCount do
		local property = select(i, ...)
		self.ffiDataTypeFromPointVarIndex[i - 1][curAddr + self.pointDataIndexMap[i - 1]] = property -- Casts from double to float
	end
end

function pointLayerFunctions:getPointVars(chunkBufferIndex, pointId, name, type, count)
	local index = chunkBufferIndex * self.maxPointsPerChunk + pointId
	assert(index >= 0 and index < self.maxPoints, "chunkBufferIndex and pointId given to setPoint exceed point buffer capacity")
	local index = index * self.pointBuffer:getElementStride() / consts.bytesPerGPUVar
	local index = index + self.pointFormatOffsets[name]

	local ffiData =
		type == "float" and self.pointDataFFIFloat or
		type == "int32" and self.pointDataFFIInt or
		type == "uint32" and self.pointDataFFIUint

	if count == 1 or not count then
		return ffiData[index]
	elseif count == 2 then
		return ffiData[index], ffiData[index + 1]
	elseif count == 3 then
		return ffiData[index], ffiData[index + 1], ffiData[index + 2]
	elseif count == 4 then
		return ffiData[index], ffiData[index + 1], ffiData[index + 2], ffiData[index + 3]
	else
		error("Invalid count " .. count .. " to getPointVars")
	end
end

function pointLayerFunctions:generateChunkCommon(realX, realY, realZ, chunkId, chunkBufferIndex)
	local density = self:getDensity(
		-- Density is sampled in middle of chunk
		realX + 0.5,
		realY + 0.5,
		realZ + 0.5
	)
	local amount = density * self.maxPointDensity * self.chunkVolume
	local count = math.floor(amount)
	if randomTODO() < amount % 1 then -- Use fractional part of amount as a probability
		count = count + 1
	end
	count = math.min(self.maxPointsPerChunk, count) -- Just in case

	self:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count) -- Specified per layer

	self:setChunkPointCount(chunkBufferIndex, count)
	if count > 0 then
		local pointIdStart = chunkBufferIndex * self.maxPointsPerChunk
		self.pointBuffer:setArrayData(self.pointData, pointIdStart + 1, pointIdStart + 1, count)
	end
end

function pointLayerFunctions:setChunkEmpty(chunkBufferIndex)
	local chunk = self.chunkExtraInfo[chunkBufferIndex]
	chunk.x = nil
	chunk.y = nil
	chunk.z = nil
	self:setChunkPointCount(chunkBufferIndex, 0)
end

function pointLayerFunctions:getClosestPointIn2x2x2(referencePosition)
	local parentOrigin
	if not self.parentPointLayer then
		parentOrigin = self.fixedParentObjectPosition
	else
		assert(self.parentPointLayer.currentObject, "Can't call getClosestPointIn2x2x2 on a pointLayer that isn't loaded")
		parentOrigin = self.parentPointLayer.currentObject.position
	end
	local positionRelative = bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
		(referencePosition - parentOrigin) / self.chunkSize
	)

	local closestChunkX
	local closestChunkY
	local closestChunkZ
	local closestIdInChunk
	local closestDistance = math.huge

	local temp = mathsies.vec3() -- No need to generate tons of new vec3s
	for x = math.floor(positionRelative.x - 0.5), math.floor(positionRelative.x + 0.5) do
		for y = math.floor(positionRelative.y - 0.5), math.floor(positionRelative.y + 0.5) do
			for z = math.floor(positionRelative.z - 0.5), math.floor(positionRelative.z + 0.5) do
				local xInChunkBuffer = x % self.chunkBufferSideLength
				local yInChunkBuffer = y % self.chunkBufferSideLength
				local zInChunkBuffer = z % self.chunkBufferSideLength
				local chunkBufferIndex = xInChunkBuffer + yInChunkBuffer * self.chunkBufferSideLength + zInChunkBuffer * self.chunkBufferSideLength * self.chunkBufferSideLength
				local chunkExtraInfo = self.chunkExtraInfo[chunkBufferIndex]
				if not (
					chunkExtraInfo.x == x and
					chunkExtraInfo.y == y and
					chunkExtraInfo.z == z
				) then
					goto continue
				end
				for pointId = 0, self:getChunkPointCount(chunkBufferIndex) - 1 do
					temp.x, temp.y, temp.z = self:getPointVars(chunkBufferIndex, pointId, "position", "float", 3)
					temp.x = temp.x + x
					temp.y = temp.y + y
					temp.z = temp.z + z
					local distance = mathsies.vec3.distance(positionRelative, temp)
					if distance < closestDistance then
						closestChunkX = x
						closestChunkY = y
						closestChunkZ = z
						closestIdInChunk = pointId
						closestDistance = distance
					end
				end
				::continue::
			end
		end
	end

	return closestChunkX, closestChunkY, closestChunkZ, closestIdInChunk, closestDistance
end

-- Actions are "prepare" (when near to an object but not close enough to need the results yet),
-- "expect" (when the results are needed), and
-- "cancel" (when there is no longer an object nearby or the point layer is not active)
-- RNG should be be seeded appropriately for value noise if action == "prepare".
-- action being prepare or expect means the the other two arguments are needed.
function pointLayerFunctions:handleThreadedShapeInit(action)
	if action == "prepare" then
		if self.threadedShapeInitWorkInfo then
			if not self.threadedShapeInitWorkInfo.completed then -- Not strictly necessary since the result is also popped on expect (or cleared on cancel). But if completion status is needed pre-expect, then this code would help.
				local result = love.thread.getChannel("shapeAmountDataStageManagerResult" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):pop()
				if not result then
					self.gameObject:checkThreadsForErrors()
				else
					self.threadedShapeInitWorkInfo.completed = true
				end
			end
			return
		end
		self.started = love.timer.getTime()

		self:randomiseValueNoise("emission")
		self:randomiseValueNoise("attenuation")

		self.threadedShapeInitWorkInfo = {
			completed = false,
			resultChannelSuffix = "Layer" .. self.index
		}

		local shapeTypeName, shapeSubtypeId, radii
		if self.parentPointLayer then
			local currentObject = self.parentPointLayer.currentObject or self.parentPointLayer.currentPotentialObject
			shapeTypeName = currentObject.shapeTypeName
			shapeSubtypeId = currentObject.shapeSubtypeId
			radii = currentObject.radii
		else
			shapeTypeName = self.fixedParentObjectShapeTypeName
			shapeSubtypeId = self.fixedParentObjectShapeSubtypeId
			radii = self.fixedParentObjectRadii
		end
		local shapeType = self.gameObject.pointLayerShapeTypes[shapeTypeName]
		local scratch = self.gameObject:decodeShapeSubtypeIntoScratchTable(shapeType, shapeSubtypeId)

		local scaledRadii = radii / math.max(radii.x, radii.y, radii.z)
		local infoTable = {
			shapeTypeId = shapeType.id,
			params = scratch,
			valueNoiseData = self.valueNoiseDataEmission,
			type = "massWrite",
			shapeMassData = self.shapeMassData,
			massDataStartOffsets = consts.shapeSlowdownIntegralDataStarts,
			resultChannelSuffix = self.threadedShapeInitWorkInfo.resultChannelSuffix,
			ratioX = shapeType.needsTrueRatio and scaledRadii.x,
			ratioY = shapeType.needsTrueRatio and scaledRadii.y,
			ratioZ = shapeType.needsTrueRatio and scaledRadii.z
		}
		love.thread.getChannel("shapeAmountDataStageManagerInfo"):push(infoTable)
	elseif action == "expect" then
		-- Ideally we want it to be finished by the time we get here, due to the time it takes to fly up to a galaxy
		if self.threadedShapeInitWorkInfo and not self.threadedShapeInitWorkInfo.completed then
			local result
			while not result do
				result = love.thread.getChannel("shapeAmountDataStageManagerResult" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):demand(consts.shapeIntegralThreadTimeout)
				if not result then
					self.gameObject:checkThreadsForErrors()
				end
			end
			self.threadedShapeInitWorkInfo.completed = true
		end
	elseif action == "cancel" then
		if self.threadedShapeInitWorkInfo and not self.threadedShapeInitWorkInfo.completed then
			love.thread.getChannel("shapeAmountDataStageManagerCancel" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):supply("cancel") -- TODO: Timeout

			love.thread.getChannel("shapeAmountDataStageManagerInfo" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):clear() -- This clear shouldn't be necessary
			love.thread.getChannel("shapeAmountDataStageManagerResult" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):clear() -- This one might be sometimes
		end
		self.threadedShapeInitWorkInfo = nil
	else
		error("Unknown handleThreadedShapeInit action " .. action)
	end
end

function game:clearPointLayers(startIndex)
	for i = startIndex, #self.pointLayers do
		local pointLayer = self.pointLayers[i]
		pointLayer.currentObject = nil
		if pointLayer.parentPointLayer and not pointLayer.parentPointLayer.currentPotentialObject then
			pointLayer:handleThreadedShapeInit("cancel")
		end
		pointLayer.currentPotentialObject = nil
	end
end

function game:newPointLayer(name, debugName, chunkSize, maxPointDensity, chunkBufferSideLength, layerInfo)
	local new = {}

	for k, v in pairs(pointLayerFunctions) do
		new[k] = v
	end
	for k, v in pairs(layerInfo) do -- Should include features
		new[k] = v
	end

	new.parentPointLayer = self.pointLayers[#self.pointLayers]
	if new.parentPointLayer then
		new.parentPointLayer.childPointLayer = new
	end
	table.insert(self.pointLayers, new)
	new.index = #self.pointLayers
	new.gameObject = self -- HACK...

	new.name = name
	new.debugName = debugName
	new.chunkSize = chunkSize
	new.maxPointDensity = maxPointDensity
	new.chunkBufferSideLength = chunkBufferSideLength

	new.chunkVolume = chunkSize ^ 3
	new.chunkBufferTotalSize = chunkBufferSideLength ^ 3
	new.maxPointsPerChunk = math.ceil(new.chunkVolume * new.maxPointDensity)
	new.maxPoints = new.chunkBufferTotalSize * new.maxPointsPerChunk

	-- Add features to the following two tables
	new.pointBufferFormat = {}
	local defines = {
		THREADGROUP_SIZE = consts.pointPreparationThreadgroupSize,
		POINT_COUNT = new.maxPoints
	}
	local unsentFeatureNames = {}
	local function tryFeature(name, format, defineName, forcePresence)
		local presence = forcePresence or layerInfo.features[name]
		if not presence then
			return
		end

		assert(presence == "sent" or presence == "unsent", "\"" .. name .. "\" feature must be either \"sent\" to GPU or \"unsent\", \"" .. presence .. "\" is invalid")

		if presence == "sent" then
			table.insert(new.pointBufferFormat, {name = name, format = format})
			if defineName then
				defines["FEATURE_" .. defineName] = true
			end
		elseif presence == "unsent" then
			unsentFeatureNames[name] = true -- For use in chunk extra data
		end
	end
	tryFeature("position", "floatvec3", "POSITION", "sent")
	tryFeature("luminousFlux", "floatvec3", "LUMINOUS_FLUX", "sent")
	tryFeature("shapeTypeSubtypeIds", "uint32vec2", "SHAPE_TYPE_SUBTYPE")
	tryFeature("attenuationShapeTypeSubtypeIds", "uint32vec2", "ATTENUATION_SHAPE_TYPE_SUBTYPE")
	tryFeature("radii", "floatvec3", "RADII")
	tryFeature("mass", "float", "MASS") -- For final layer (star systems)

	new.pointBuffer = love.graphics.newBuffer(new.pointBufferFormat, new.maxPoints, {
		shaderstorage = true,
		debugname = debugName .. " Points"
	})

	assert((new.pointBuffer:getElementStride() / consts.bytesPerGPUVar) % 1 == 0, "Something has gone terribly wrong!")

	new.pointData = love.data.newByteData(new.pointBuffer:getElementStride() * new.maxPoints)
	new.pointDataFFIFloat = ffi.cast("float*", new.pointData:getFFIPointer())
	new.pointDataFFIInt = ffi.cast("int32_t*", new.pointData:getFFIPointer())
	new.pointDataFFIUint = ffi.cast("uint32_t*", new.pointData:getFFIPointer())

	new.pointFormatVarCount = 0 -- Considers vec3 as 3 variables etc
	new.ffiDataTypeFromPointVarIndex = {} -- Determines how to interpret each number
	new.pointFormatOffsets = {} -- Maps the start of a variable (float, vec3, etc) to its offset in the FFI data array(s)
	new.pointDataIndexMap = {}
	local dataTypeMap = {
		float = new.pointDataFFIFloat,
		int32 = new.pointDataFFIInt,
		uint32 = new.pointDataFFIUint
	}
	for _, variable in ipairs(new.pointBuffer:getFormat()) do
		local num, type
		if variable.format == "float" or variable.format == "int32" or variable.format == "uint32" then
			num = 1
			type = variable.format
		else
			local _, _, typeString, numString = variable.format:find("^(.*)vec([0-9]*)$")
			type = typeString
			num = numString and tonumber(numString) or 1
		end
		new.pointFormatOffsets[variable.name] = variable.offset / consts.bytesPerGPUVar
		for i = 0, num - 1 do
			new.pointDataIndexMap[new.pointFormatVarCount] = variable.offset / consts.bytesPerGPUVar + i
			new.ffiDataTypeFromPointVarIndex[new.pointFormatVarCount] = dataTypeMap[type]
			new.pointFormatVarCount = new.pointFormatVarCount + 1
		end
	end

	new.pointPreparationShader = love.graphics.newComputeShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/points.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/pointPreparation.glsl"),
		{
			defines = defines
		}
	)

	new.chunkPointCountBuffer = love.graphics.newBuffer(consts.intBufferFormat, new.chunkBufferTotalSize, {
		shaderstorage = true,
		debugname = debugName .. " Chunk Point Counts"
	})
	new.chunkPointCountData = love.data.newByteData(new.chunkPointCountBuffer:getElementStride() * new.chunkBufferTotalSize)
	new.chunkPointCountDataFFI = ffi.cast("int32_t*", new.chunkPointCountData:getFFIPointer())

	local maxNoiseValuesEmission = 0
	local maxNoiseValuesAttenuation = 0
	local hasNoiseEmission = false
	local hasNoiseAttenuation = false
	local relevantShapeTypeSet = new.parentPointLayer and new.parentPointLayer.features.shapeTypeSet
	if not relevantShapeTypeSet then
		assert(new.index == 1, "Only the top layer should not have a parent layer")
		local shapeType = self.pointLayerShapeTypes[new.fixedParentObjectShapeTypeName]
		if shapeType.noiseInfo then
			hasNoiseEmission = true
			maxNoiseValuesEmission = math.max(maxNoiseValuesEmission, shapeType.noiseInfo.requiredValueCount)
		end

		local shapeType = self.pointLayerShapeTypes[new.fixedParentObjectAttenuationShapeTypeName]
		if shapeType and shapeType.noiseInfo then
			hasNoiseAttenuation = true
			maxNoiseValuesAttenuation = math.max(maxNoiseValuesAttenuation, shapeType.noiseInfo.requiredValueCount)
		end
	else
		for _, shapeTypeInfo in ipairs(relevantShapeTypeSet) do
			local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
			if shapeType.noiseInfo then
				hasNoiseEmission = true
				maxNoiseValuesEmission = math.max(maxNoiseValuesEmission, shapeType.noiseInfo.requiredValueCount)
			end
			if not shapeTypeInfo.attenuationShapeTypes then
				goto continue
			end
			for _, shapeTypeInfo in ipairs(shapeTypeInfo.attenuationShapeTypes) do
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
				if shapeType.noiseInfo then
					hasNoiseAttenuation = true
					maxNoiseValuesAttenuation = math.max(maxNoiseValuesAttenuation, shapeType.noiseInfo.requiredValueCount)
				end
			end
			::continue::
		end
	end
	new.hasNoiseAttenuation = hasNoiseAttenuation
	new.hasNoiseEmission = hasNoiseEmission
	local function addNoiseData(type, maxNoiseValues)
		local capitalised = type == "emission" and "Emission" or type == "attenuation" and "Attenuation"
		new["maxNoiseValues" .. capitalised] = maxNoiseValues

		new["valueNoiseBuffer" .. capitalised] = love.graphics.newBuffer(consts.floatBufferFormat, new["maxNoiseValues" .. capitalised], {
			shaderstorage = true,
			debugname = debugName .. " " .. capitalised .. " Noise Values"
		})
		local requiredSize = new["valueNoiseBuffer" .. capitalised]:getElementStride() * new["maxNoiseValues" .. capitalised]
		if
			self.valueNoiseDataReusableForPointLayers and
			self.valueNoiseDataReusableForPointLayers:getSize() == requiredSize
		then
			new["valueNoiseData" .. capitalised] = self.valueNoiseDataReusableForPointLayers
			self.valueNoiseDataReusableForPointLayers = nil
		else
			new["valueNoiseData" .. capitalised] = love.data.newByteData(requiredSize)
		end
		new["valueNoiseDataFFI" .. capitalised] = ffi.cast("float*", new["valueNoiseData" .. capitalised]:getFFIPointer())
	end
	if hasNoiseAttenuation then
		addNoiseData("attenuation", maxNoiseValuesAttenuation)
	end
	if hasNoiseEmission then
		addNoiseData("emission", maxNoiseValuesEmission)
	end

	new.chunkExtraInfo = {}
	for x = 0, new.chunkBufferSideLength - 1 do
		for y = 0, new.chunkBufferSideLength - 1 do
			for z = 0, new.chunkBufferSideLength - 1 do
				local extraInfo = {
					x = nil,
					y = nil,
					z = nil
				}
				for name in pairs(unsentFeatureNames) do
					extraInfo[name] = {}
				end
				local chunkBufferIndex = x + y * new.chunkBufferSideLength + z * new.chunkBufferSideLength * new.chunkBufferSideLength
				new.chunkExtraInfo[chunkBufferIndex] = extraInfo
			end
		end
	end

	local bytesPerFloat = 4
	new.shapeMassData = love.data.newByteData(bytesPerFloat * consts.shapeSlowdownIntegralDataCount)
	new.shapeMassDataFFI = ffi.cast("float*", new.shapeMassData:getFFIPointer())

	new.volumetricCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
		debugname = debugName .. " Volumetric Canvas",
		format = "rgba16f",
		computewrite = true
	})
	new.volumetricAddCountCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
		debugname = debugName .. " Volumetric Addition Count Canvas",
		format = "r8ui",
		computewrite = true
	})

	return new
end

function game:finishHandlingPointLayers(pointLayer)
	pointLayer.currentObject = nil
	self:clearPointLayers(pointLayer.index + 1)
end

function game:handlePointLayers()
	local remakeAll = false
	for pointLayerIndex, pointLayer in ipairs(self.pointLayers) do
		local updateChunkCountBuffer = false

		local parentOrigin
		if not pointLayer.parentPointLayer then
			parentOrigin = pointLayer.fixedParentObjectPosition
		else
			assert(pointLayer.parentPointLayer.currentObject, "handlePointLayers loop has run into a point layer that shouldn't be being handled")
			parentOrigin = pointLayer.parentPointLayer.currentObject.position
		end
		local positionRelative = bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
			(self.ship.position - parentOrigin) / pointLayer.chunkSize
		)

		local minX, maxX, minY, maxY, minZ, maxZ = pointLayer:getBoundingBoxChunks()
		local widthChunks = maxX - minX + 1
		local heightChunks = maxY - minY + 1
		local depthChunks = maxZ - minZ + 1

		local chunkBufferStartRealX = math.floor((positionRelative.x - pointLayer.chunkBufferSideLength / 2) / pointLayer.chunkBufferSideLength) * pointLayer.chunkBufferSideLength
		local chunkBufferStartRealY = math.floor((positionRelative.y - pointLayer.chunkBufferSideLength / 2) / pointLayer.chunkBufferSideLength) * pointLayer.chunkBufferSideLength
		local chunkBufferStartRealZ = math.floor((positionRelative.z - pointLayer.chunkBufferSideLength / 2) / pointLayer.chunkBufferSideLength) * pointLayer.chunkBufferSideLength

		local viewMinXInChunkBuffer = (positionRelative.x - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength
		local viewMinYInChunkBuffer = (positionRelative.y - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength
		local viewMinZInChunkBuffer = (positionRelative.z - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength

		for x = 0, pointLayer.chunkBufferSideLength - 1 do
			for y = 0, pointLayer.chunkBufferSideLength - 1 do
				for z = 0, pointLayer.chunkBufferSideLength - 1 do
					local realX = x + chunkBufferStartRealX + (x + 0.5 < viewMinXInChunkBuffer and pointLayer.chunkBufferSideLength or 0)
					local realY = y + chunkBufferStartRealY + (y + 0.5 < viewMinYInChunkBuffer and pointLayer.chunkBufferSideLength or 0)
					local realZ = z + chunkBufferStartRealZ + (z + 0.5 < viewMinZInChunkBuffer and pointLayer.chunkBufferSideLength or 0)

					local chunkBufferIndex = x + y * pointLayer.chunkBufferSideLength + z * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength

					local currentChunk = pointLayer.chunkExtraInfo[chunkBufferIndex]
					if
						remakeAll or
						currentChunk.x ~= realX or
						currentChunk.y ~= realY or
						currentChunk.z ~= realZ
					then
						currentChunk.x = realX
						currentChunk.y = realY
						currentChunk.z = realZ
						updateChunkCountBuffer = true

						if
							minX <= realX and realX <= maxX and
							minY <= realY and realY <= maxY and
							minZ <= realZ and realZ <= maxZ
						then
							local x2, y2, z2 = realX - minX, realY - minY, realZ - minZ
							local chunkId = x2 + y2 * widthChunks + z2 * widthChunks * heightChunks

							pointLayer:generateChunkCommon(realX, realY, realZ, chunkId, chunkBufferIndex, x, y, z)
						else
							pointLayer:setChunkEmpty(chunkBufferIndex)
						end
					end
				end
			end
		end

		if updateChunkCountBuffer then
			pointLayer.chunkPointCountBuffer:setArrayData(pointLayer.chunkPointCountData, 1, 1, pointLayer.chunkBufferTotalSize)
		end

		if not pointLayer.parentPointLayer then
			if
				math.abs(positionRelative.x) > widthChunks + pointLayer.chunkBufferSideLength / 2 or
				math.abs(positionRelative.y) > heightChunks + pointLayer.chunkBufferSideLength / 2 or
				math.abs(positionRelative.z) > depthChunks + pointLayer.chunkBufferSideLength / 2
			then
				pointLayer.topLayerOutOfRange = true
				pointLayer.currentObject = nil
				pointLayer.currentPotentialObject = nil
				self:clearPointLayers(pointLayerIndex + 1)
				break
			else
				pointLayer.topLayerOutOfRange = false
			end
		end
		local closestChunkX, closestChunkY, closestChunkZ, closestIdInChunk, closestDistance = pointLayer:getClosestPointIn2x2x2(self.ship.position)
		if closestIdInChunk and closestDistance < consts.pointMinDistanceInChunk / 2 then
			local x2, y2, z2 = closestChunkX - minX, closestChunkY - minY, closestChunkZ - minZ
			local chunkId = x2 + y2 * widthChunks + z2 * widthChunks * heightChunks

			local chunkBufferX = closestChunkX % pointLayer.chunkBufferSideLength
			local chunkBufferY = closestChunkY % pointLayer.chunkBufferSideLength
			local chunkBufferZ = closestChunkZ % pointLayer.chunkBufferSideLength
			local chunkBufferIndex = chunkBufferX + chunkBufferY * pointLayer.chunkBufferSideLength + chunkBufferZ * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength

			local chunkExtraInfo = pointLayer.chunkExtraInfo[chunkBufferIndex]

			-- Some early feature getting
			local shapeTypeId, shapeSubtypeId
			if pointLayer.features.shapeTypeSubtypeIds then
				if pointLayer.features.shapeTypeSubtypeIds == "sent" then
					shapeTypeId, shapeSubtypeId = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "shapeTypeSubtypeIds", "uint32", 2)
				elseif pointLayer.features.shapeTypeId == "unsent" then
					shapeTypeId, shapeSubtypeId = chunkExtraInfo.shapeTypeId[closestIdInChunk * 2], chunkExtraInfo.shapeTypeId[closestIdInChunk * 2 + 1]
				end
			end
			local attenuationShapeTypeId, attenuationShapeSubtypeId
			if pointLayer.features.attenuationShapeTypeSubtypeIds then
				if pointLayer.features.attenuationShapeTypeSubtypeIds == "sent" then
					attenuationShapeTypeId, attenuationShapeSubtypeId = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "attenuationShapeTypeSubtypeIds", "uint32", 2)
				elseif pointLayer.features.attenuationShapeTypeId == "unsent" then
					attenuationShapeTypeId, attenuationShapeSubtypeId = chunkExtraInfo.attenuationShapeTypeId[closestIdInChunk * 2], chunkExtraInfo.attenuationShapeTypeId[closestIdInChunk * 2 + 1]
				end
			end
			local xRadius, yRadius, zRadius
			if pointLayer.features.radii == "sent" then
				xRadius, yRadius, zRadius = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "radii", "float", 3)
			elseif pointLayer.features.radii == "unsent" then
				xRadius = chunkExtraInfo.radii[closestIdInChunk * 3]
				yRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 1]
				zRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 2]
			end

			if pointLayer.childPointLayer then
				if
					pointLayer.currentPotentialObject and
					(
						pointLayer.currentPotentialObject.chunkId ~= chunkId or
						pointLayer.currentPotentialObject.pointId ~= closestIdInChunk
					)
				then
					pointLayer.currentPotentialObject = nil
					pointLayer.childPointLayer:handleThreadedShapeInit("cancel")
				end

				pointLayer.currentPotentialObject = pointLayer.currentPotentialObject or {
					chunkId = chunkId,
					pointId = closestIdInChunk,
					chunkBufferIndex = chunkBufferIndex,

					chunkX = closestChunkX,
					chunkY = closestChunkY,
					chunkZ = closestChunkZ,

					shapeTypeName = self.pointLayerShapeTypes[shapeTypeId].name,
					shapeSubtypeId = shapeSubtypeId,
					attenuationShapeTypeName = self.pointLayerShapeTypes[attenuationShapeTypeId].name,
					attenuationShapeSubtypeId = attenuationShapeSubtypeId,
					radii = xRadius and mathsies.vec3(xRadius, yRadius, zRadius) or nil
				}
				self:seedCelestialRNG(self:getGlobalCelestialObjectIdNumbers(
					pointLayer:getGlobalCelestialObjectIdParameters(consts.objectGenerationStages.noiseValues, pointLayer.currentPotentialObject)
				))
				pointLayer.childPointLayer:handleThreadedShapeInit("prepare")
			end

			local resolvable
			if not pointLayer.features.radii then
				resolvable = true
			else
				if pointLayer.features.radii == "sent" then
					xRadius, yRadius, zRadius = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "radii", "float", 3)
				elseif pointLayer.features.radii == "unsent" then
					xRadius = chunkExtraInfo.radii[closestIdInChunk * 3]
					yRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 1]
					zRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 2]
				end
				assert(xRadius and yRadius and zRadius, "Missing radii")
				local maxRadius = math.max(xRadius, yRadius, zRadius)
				-- local trueDistance = bm.mapm.tonumber(bm.vec3.distance(self.ship.position, objectPosition))
				local trueDistance = pointLayer.chunkSize * closestDistance
				resolvable = trueDistance <= self:getSphereResolvableDistance(maxRadius)
			end

			if not resolvable then
				self:finishHandlingPointLayers(pointLayer)
				break
			end

			if not (
				pointLayer.currentObject and
				pointLayer.currentObject.chunkId == chunkId and
				pointLayer.currentObject.pointId == closestIdInChunk
			) then
				if pointLayer.childPointLayer then
					pointLayer.childPointLayer:handleThreadedShapeInit("expect")
				end

				local r, g, b = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "luminousFlux", "float", 3)

				pointLayer.currentObject = {
					chunkId = chunkId,
					chunkBufferIndex = chunkBufferIndex, -- Won't change for the same object
					pointId = closestIdInChunk,

					-- chunkX = closestChunkX,
					-- chunkY = closestChunkY,
					-- chunkZ = closestChunkZ
				}
				local currentObject = pointLayer.currentObject
				-- Features with consistent ways of calculating
				local x, y, z = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "position", "float", 3)
				local objectPosition = parentOrigin + pointLayer.chunkSize * bm.vec3(closestChunkX + x, closestChunkY + y, closestChunkZ + z)
				currentObject.position = objectPosition
				currentObject.luminousFlux = mathsies.vec3(r, g, b) * pointLayer.chunkSize ^ 2 -- Bring back to proper units
				if pointLayer.features.shapeTypeSubtypeIds then
					currentObject.shapeTypeName = self.pointLayerShapeTypes[shapeTypeId].name
					currentObject.shapeSubtypeId = shapeSubtypeId
				end
				if pointLayer.features.attenuationShapeTypeSubtypeIds then
					currentObject.attenuationShapeTypeName = self.pointLayerShapeTypes[attenuationShapeTypeId].name
					currentObject.attenuationShapeSubtypeId = attenuationShapeSubtypeId
				end
				if pointLayer.features.radii then
					currentObject.radii = mathsies.vec3(xRadius, yRadius, zRadius)
				end
				if pointLayer.features.mass then
					local mass
					if pointLayer.features.mass == "sent" then
						mass = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "mass", "float", 1)
					elseif pointLayer.features.mass == "unsent" then
						mass = chunkExtraInfo.mass[closestIdInChunk]
					end
					currentObject.mass = mass
				end
				-- Remaining features are generated (or fetched from extra info) in possibly layer-specific ways
				self:seedCelestialRNG(self:getGlobalCelestialObjectIdNumbers(
					pointLayer:getGlobalCelestialObjectIdParameters(consts.objectGenerationStages.main)
				))
				pointLayer:generateRemainingCurrentObjectInfo()

				remakeAll = true
			end
		else
			pointLayer.currentPotentialObject = nil
			self:finishHandlingPointLayers(pointLayer)
			break
		end
	end

	-- Calculate once per tick, while we know that everything is consistent with the position of the ship when this function was called
	self.pointLayerGravityWellSlowdownFactor = self:getPointLayerGravityWellSlowdownFactor()
end

function game:getPointLayerGravityWellSlowdownFactor()
	local total = 0
	local referencePosition = self.ship.position

	local exponent = consts.slowdownDistanceExponent

	-- Not needed since the top point layer remains loaded and the calculations work fine
	-- local topLayer = self.pointLayers[1]
	-- local distToTopLayer = bm.mapm.tonumber(bm.vec3.distance(topLayer.fixedParentObjectPosition, referencePosition))
	-- if distToTopLayer >= topLayer.fixedParentObjectPointDistance then
	-- 	local shapeType = self.pointLayerShapeTypes[topLayer.fixedParentObjectShapeTypeName]
	-- 	local shapeSubtypeId = topLayer.fixedParentObjectShapeSubtypeId
	-- 	local mass = -- Estimate
	-- 		shapeType.subtypeBaseObjectAmounts[shapeSubtypeId] * -- NOTE: if this block is ever uncommented, this needs to account for shape types with needsTrueRatio
	-- 		topLayer.fixedParentObjectRadii.x *
	-- 		topLayer.fixedParentObjectRadii.y *
	-- 		topLayer.fixedParentObjectRadii.z *
	-- 		topLayer.maxPointDensity *
	-- 		topLayer.averageMassPerPoint
	-- 	return mass * distToTopLayer ^ exponent
	-- end

	for pointLayerIndex, pointLayer in ipairs(self.pointLayers) do
		local massSent
		if pointLayer.features.mass == "sent" then
			massSent = true
		elseif pointLayer.features.mass == "unsent" then
			massSent = false
		else
			goto continue
		end

		local parentOrigin, parentRadii, parentShapeTypeName, parentShapeSubtypeId
		if not pointLayer.parentPointLayer then
			parentOrigin = pointLayer.fixedParentObjectPosition
			parentRadii = pointLayer.fixedParentObjectRadii
			parentShapeTypeName = pointLayer.fixedParentObjectShapeTypeName
			parentShapeSubtypeId = pointLayer.fixedParentObjectShapeSubtypeId
		elseif pointLayer.parentPointLayer.currentObject then
			parentOrigin = pointLayer.parentPointLayer.currentObject.position
			parentRadii = pointLayer.parentPointLayer.currentObject.radii
			parentShapeTypeName = pointLayer.parentPointLayer.currentObject.shapeTypeName
			parentShapeSubtypeId = pointLayer.parentPointLayer.currentObject.shapeSubtypeId
		else
			break
		end
		local positionRelativeFull = bm.vec3.toMathsiesVec3(referencePosition - parentOrigin)
		local positionRelative = bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
			(referencePosition - parentOrigin) / pointLayer.chunkSize
		)

		local totalThisLayer = 0

		local temp = mathsies.vec3() -- No need to generate tons of new vec3s
		local xLower = math.floor(positionRelative.x - 0.5)
		local yLower = math.floor(positionRelative.y - 0.5)
		local zLower = math.floor(positionRelative.z - 0.5)
		local xUpper = xLower + 1
		local yUpper = yLower + 1
		local zUpper = zLower + 1
		local sampledChunksWidth = xUpper - xLower + 1
		local sampledChunksHeight = yUpper - yLower + 1
		local sampledChunksDepth = zUpper - zLower + 1
		for x = xLower, xUpper do
			for y = yLower, yUpper do
				for z = zLower, zUpper do
					local xInChunkBuffer = x % pointLayer.chunkBufferSideLength
					local yInChunkBuffer = y % pointLayer.chunkBufferSideLength
					local zInChunkBuffer = z % pointLayer.chunkBufferSideLength
					local chunkBufferIndex = xInChunkBuffer + yInChunkBuffer * pointLayer.chunkBufferSideLength + zInChunkBuffer * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength
					local chunkExtraInfo = pointLayer.chunkExtraInfo[chunkBufferIndex]
					if not (
						chunkExtraInfo.x == x and
						chunkExtraInfo.y == y and
						chunkExtraInfo.z == z
					) then
						goto continue
					end
					for pointId = 0, pointLayer:getChunkPointCount(chunkBufferIndex) - 1 do
						if not (
							pointLayer.currentObject and
							pointLayer.currentObject.chunkBufferIndex == chunkBufferIndex and
							pointLayer.currentObject.pointId == pointId
						) then
							temp.x, temp.y, temp.z = pointLayer:getPointVars(chunkBufferIndex, pointId, "position", "float", 3)
							temp.x = temp.x + x
							temp.y = temp.y + y
							temp.z = temp.z + z
							local distance = mathsies.vec3.distance(positionRelative, temp)

							local mass
							if massSent then
								mass = pointLayer:getPointVars(chunkBufferIndex, pointId, "mass", "float", 1)
							else
								mass = chunkExtraInfo.mass[pointId]
							end

							if distance * pointLayer.chunkSize > 0 then
								totalThisLayer = totalThisLayer + mass * (distance * pointLayer.chunkSize) ^ exponent
							end
						end
					end
					::continue::
				end
			end
		end

		local doLods = true
		if doLods then
			local gridIters = 0
			local samples = 0
			local dataVolumeToRealVolume = parentRadii.x * parentRadii.y * parentRadii.z
			local function gravity(mass, x, y, z)
				local finalX = x * parentRadii.x
				local finalY = y * parentRadii.y
				local finalZ = z * parentRadii.z
				local finalMass = mass * pointLayer.averageMassPerPoint * pointLayer.maxPointDensity * dataVolumeToRealVolume
				local distance = math.sqrt(
					(finalX - positionRelativeFull.x) ^ 2 +
					(finalY - positionRelativeFull.y) ^ 2 +
					(finalZ - positionRelativeFull.z) ^ 2
				)
				if distance > 0 then
					totalThisLayer = totalThisLayer + finalMass * distance ^ exponent
				end
			end
			local massData = pointLayer.shapeMassDataFFI
			local range = consts.lodBoxRange
			local posX = positionRelativeFull.x / parentRadii.x * 0.5 + 0.5
			local posY = positionRelativeFull.y / parentRadii.y * 0.5 + 0.5
			local posZ = positionRelativeFull.z / parentRadii.z * 0.5 + 0.5
			local cutRegionStartX = xLower * pointLayer.chunkSize / parentRadii.x
			local cutRegionStartY = yLower * pointLayer.chunkSize / parentRadii.y
			local cutRegionStartZ = zLower * pointLayer.chunkSize / parentRadii.z
			local cutRegionEndX = (xUpper + 1) * pointLayer.chunkSize / parentRadii.x
			local cutRegionEndY = (yUpper + 1) * pointLayer.chunkSize / parentRadii.y
			local cutRegionEndZ = (zUpper + 1) * pointLayer.chunkSize / parentRadii.z
			local nextLodStartX = 0
			local nextLodStartY = 0
			local nextLodStartZ = 0
			local nextLodEndX = 1
			local nextLodEndY = 1
			local nextLodEndZ = 1
			for lod = 0, consts.shapeSlowdownIntegralDetail do -- Go from lowest detail to highest, leaving gaps for the next lod
				local lodStepCount = 2 ^ lod
				local lodReadOffset = consts.shapeSlowdownIntegralDataStarts[lod]
				local isHighestDetailLod = lod == consts.shapeSlowdownIntegralDetail
				local posXThisLod = math.floor(posX * lodStepCount)
				local posYThisLod = math.floor(posY * lodStepCount)
				local posZThisLod = math.floor(posZ * lodStepCount)
				local thisLodStartX = nextLodStartX
				local thisLodStartY = nextLodStartY
				local thisLodStartZ = nextLodStartZ
				local thisLodEndX = nextLodEndX
				local thisLodEndY = nextLodEndY
				local thisLodEndZ = nextLodEndZ
				nextLodStartX = math.huge
				nextLodStartY = math.huge
				nextLodStartZ = math.huge
				nextLodEndX = -math.huge
				nextLodEndY = -math.huge
				nextLodEndZ = -math.huge
				for x = thisLodStartX, thisLodEndX - 1 do
					for y = thisLodStartY, thisLodEndY - 1 do
						for z = thisLodStartZ, thisLodEndZ - 1 do
							gridIters = gridIters + 1
							if
								math.abs(x - posXThisLod) <= range and
								math.abs(y - posYThisLod) <= range and
								math.abs(z - posZThisLod) <= range and
								not isHighestDetailLod -- For the highest detail lod, read from the whole range without leaving a gap
							then
								-- Leave to next lod (which is higher detail)
								nextLodStartX = math.min(nextLodStartX, x * 2)
								nextLodStartY = math.min(nextLodStartY, y * 2)
								nextLodStartZ = math.min(nextLodStartZ, z * 2)
								nextLodEndX = math.max(nextLodEndX, (x + 1) * 2)
								nextLodEndY = math.max(nextLodEndY, (y + 1) * 2)
								nextLodEndZ = math.max(nextLodEndZ, (z + 1) * 2)
							else
								samples = samples + 1
								local sampleI = lodReadOffset + x + y * lodStepCount + z * lodStepCount ^ 2

								local sampleStartX = x / lodStepCount * 2 - 1 -- *2-1 because shape types' coordinates go from -1 to 1
								local sampleStartY = y / lodStepCount * 2 - 1
								local sampleStartZ = z / lodStepCount * 2 - 1
								local sampleEndX = (x + 1) / lodStepCount * 2 - 1
								local sampleEndY = (y + 1) / lodStepCount * 2 - 1
								local sampleEndZ = (z + 1) / lodStepCount * 2 - 1
								local sampleCentreX = (sampleStartX + sampleEndX) / 2
								local sampleCentreY = (sampleStartY + sampleEndY) / 2
								local sampleCentreZ = (sampleStartZ + sampleEndZ) / 2
								local sampleVolume =
									(sampleEndX - sampleStartX) *
									(sampleEndY - sampleStartY) *
									(sampleEndZ - sampleStartZ)
								local sampleMass = massData[sampleI]
								if sampleMass == 0 then
									-- Early return
									goto continue
								end

								local sampleCutStartX = math.max(sampleStartX, cutRegionStartX)
								local sampleCutEndX = math.min(sampleEndX, cutRegionEndX)
								local sampleCutStartY = math.max(sampleStartY, cutRegionStartY)
								local sampleCutEndY = math.min(sampleEndY, cutRegionEndY)
								local sampleCutStartZ = math.max(sampleStartZ, cutRegionStartZ)
								local sampleCutEndZ = math.min(sampleEndZ, cutRegionEndZ)
								local cutCentreX = (sampleCutStartX + sampleCutEndX) / 2
								local cutCentreY = (sampleCutStartY + sampleCutEndY) / 2
								local cutCentreZ = (sampleCutStartZ + sampleCutEndZ) / 2
								local cutVolume =
									math.max(0, sampleCutEndX - sampleCutStartX) *
									math.max(0, sampleCutEndY - sampleCutStartY) *
									math.max(0, sampleCutEndZ - sampleCutStartZ)

								if cutVolume == 0 then
									-- Usually this branch is taken
									gravity(sampleMass, sampleCentreX, sampleCentreY, sampleCentreZ)
								else
									-- This branch is only taken if the current sample AABB intersects with the AABB of chunks whose points have been iterated over.

									-- Split up AABB that has had other AABB removed from it into (at most) 3^3-1 smaller AABBs. We miss out the removed AABB to avoid errors where the distance is far lower than it should be and the calculation goes wrong.

									local density = sampleMass / sampleVolume
									-- Since this branch is rarely taken, we are OK to use some tables.
									local xCoords = {sampleStartX, sampleCutStartX, sampleCutEndX, sampleEndX}
									local yCoords = {sampleStartY, sampleCutStartY, sampleCutEndY, sampleEndY}
									local zCoords = {sampleStartZ, sampleCutStartZ, sampleCutEndZ, sampleEndZ}

									for xi = 1, 3 do
										for yi = 1, 3 do
											for zi = 1, 3 do
												if xi == 2 and yi == 2 and zi == 2 then
													-- Skip centre as it's the cut AABB where the points were checked
													goto continue
												end

												local startX = xCoords[xi]
												local endX = xCoords[xi + 1]
												local startY = yCoords[yi]
												local endY = yCoords[yi + 1]
												local startZ = zCoords[zi]
												local endZ = zCoords[zi + 1]

												local volume =
													(endX - startX) *
													(endY - startY) *
													(endZ - startZ)

												local centreX = (startX + endX) / 2
												local centreY = (startY + endY) / 2
												local centreZ = (startZ + endZ) / 2

												local mass = volume * density -- May be 0

												gravity(mass, centreX, centreY, centreZ)

											    ::continue::
											end
										end
									end
								end
							end
						    ::continue::
						end
					end
				end
			end
		else
			local shapeType = self.pointLayerShapeTypes[parentShapeTypeName]
			local ratioX, ratioY, ratioZ
			if shapeType.needsTrueRatio then
				ratioX, ratioY, ratioZ = mathsies.vec3.components(parentRadii / math.max(parentRadii.x, parentRadii.y, parentRadii.z))
			end
			local scratch = self:decodeShapeSubtypeIntoScratchTable(shapeType, parentShapeSubtypeId)
			for i = 1, #self.slowdownSampleDistribution do
				local infoTable = {
					shapeTypeId = shapeType.id,
					params = scratch,
					valueNoiseData = pointLayer.valueNoiseData,
					type = "gravitySlowdown",
					firstSample = self.slowdownSampleDistribution[i].firstSample,
					lastSample = self.slowdownSampleDistribution[i].lastSample,
					stepCount = self.slowdownSampleDistribution.stepCount,

					exponent = exponent,
					-- From radius 1 (as in the shape type density function) to full object radii
					scaleX = parentRadii.x,
					scaleY = parentRadii.y,
					scaleZ = parentRadii.z,
					-- For shape types that need this information (their density function signatures are different)
					ratioX = ratioX,
					ratioY = ratioY,
					ratioZ = ratioZ,
					-- These all work in full positions
					referencePosX = positionRelativeFull.x,
					referencePosY = positionRelativeFull.y,
					referencePosZ = positionRelativeFull.z,
					cutRegionStartX = xLower * pointLayer.chunkSize,
					cutRegionStartY = yLower * pointLayer.chunkSize,
					cutRegionStartZ = zLower * pointLayer.chunkSize,
					cutRegionEndX = (xUpper + 1) * pointLayer.chunkSize,
					cutRegionEndY = (yUpper + 1) * pointLayer.chunkSize,
					cutRegionEndZ = (zUpper + 1) * pointLayer.chunkSize,
					sampleDensityMultiplier = pointLayer.averageMassPerPoint * pointLayer.maxPointDensity
				}
				love.thread.getChannel("shapeAmountsInfo"):push(infoTable)
			end
			local results = {}
			for _=1, #self.slowdownSampleDistribution do
				local result
				while not result do
					result = love.thread.getChannel("shapeAmountsResult"):demand(consts.shapeIntegralThreadTimeout)
					if not result then
						self:checkThreadsForErrors()
					end
				end
				table.insert(results, result)
			end
			table.sort(results, function(a, b) -- Sort for determinism
				return a.firstSample < b.firstSample
			end)
			for _, v in ipairs(results) do
				totalThisLayer = totalThisLayer + v.rangeTotal
			end
		end

		total = total + totalThisLayer
		::continue::
	end

	return total
end

function game:drawPointLayers()
	local outputCanvas = self.screenCanvasses.celestialOutputCanvas
	local aspectRatio = outputCanvas:getWidth() / outputCanvas:getHeight()
	love.graphics.setCanvas(outputCanvas)

	local luminanceMultiplier = consts.celestialLuminanceMultiplier

	local cameraPositionFull = self.ship.position
	local cameraOrientation = self.ship.orientation
	local cameraVerticalFOV = self.ship.verticalFOV
	local diagonalFOV = 2 * math.atan(math.sqrt(1 ^ 2 + aspectRatio ^ 2) * math.tan(cameraVerticalFOV / 2))

	local cameraForwards = mathsies.vec3.rotate(consts.forwardVector, cameraOrientation)
	local cameraUp = mathsies.vec3.rotate(consts.upVector, cameraOrientation)
	local cameraRight = mathsies.vec3.rotate(consts.rightVector, cameraOrientation)
	local vertexZAtFurthestAngle = math.cos(diagonalFOV / 2)
	local cameraToClip = mathsies.mat4.perspectiveLeftHanded(
		aspectRatio,
		cameraVerticalFOV,
		-- 1, -- Only a point disk vertex right in the centre of the screen has any chance of being clipped, and it will just be pushed slightly away from the centre. I don't see how any holes could form.
		1.01, -- But whatever lol
		-- vertexZAtFurthestAngle
		vertexZAtFurthestAngle * 0.99
	)
	local worldToCameraStationary = mathsies.mat4.camera(mathsies.vec3(), cameraOrientation)
	local skyToClip = cameraToClip * worldToCameraStationary
	local clipToSky = mathsies.mat4.inverse(skyToClip)

	-- local vec = mathsies.vec3(1, 1, 1) -- 1, 1 for top right. Z doesn't matter because of normalisation below.
	-- vec = clipToSky * vec
	-- local angle = math.acos(mathsies.vec3.dot(mathsies.vec3.normalise(vec), mathsies.vec3(0, 0, 1)))
	-- print(angle - diagonalFOV / 2) -- Very very very close to 0. This means that the diagonal FOV calculation is correct.

	love.graphics.setBlendMode("add")

	for _, pointLayer in ipairs(self.pointLayers) do
		local parentOrigin, parentObjectShapeTypeName, parentObjectShapeSubtypeId, parentObjectRadii, attenuationShapeTypeName, attenuationShapeSubtypeId
		if not pointLayer.parentPointLayer then
			parentOrigin = pointLayer.fixedParentObjectPosition
			parentObjectShapeTypeName = pointLayer.fixedParentObjectShapeTypeName
			parentObjectShapeSubtypeId = pointLayer.fixedParentObjectShapeSubtypeId
			parentObjectRadii = pointLayer.fixedParentObjectRadii
			attenuationShapeTypeName = pointLayer.fixedParentObjectAttenuationShapeTypeName
			attenuationShapeSubtypeId = pointLayer.fixedParentObjectAttenuationShapeSubtypeId
		else
			if not pointLayer.parentPointLayer.currentObject then
				break -- Outside of any objects below this scale
			end
			parentOrigin = pointLayer.parentPointLayer.currentObject.position
			parentObjectShapeTypeName = pointLayer.parentPointLayer.currentObject.shapeTypeName
			parentObjectShapeSubtypeId = pointLayer.parentPointLayer.currentObject.shapeSubtypeId
			parentObjectRadii = pointLayer.parentPointLayer.currentObject.radii
			attenuationShapeTypeName = pointLayer.parentPointLayer.currentObject.attenuationShapeTypeName
			attenuationShapeSubtypeId = pointLayer.parentPointLayer.currentObject.attenuationShapeSubtypeId
		end
		local cameraPositionFullRelative = cameraPositionFull - parentOrigin
		local cameraPosition = bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
			cameraPositionFullRelative / pointLayer.chunkSize
		)

		-- Fade in/out roles are swapped between volumetric and point
		local fullyPointRadius = (pointLayer.chunkBufferSideLength / 2 - 0.5) * consts.pointFadeStart
		local fullyVolumetricRadius = pointLayer.chunkBufferSideLength / 2 - 0.5
		-- In terms of proper units and not chunks
		local fullyPointRadiusProperUnits = fullyPointRadius * pointLayer.chunkSize
		local fullyVolumetricRadiusProperUnits = fullyVolumetricRadius * pointLayer.chunkSize

		-- Volumetrics

		if pointLayer.volumetricCanvasCameraInfo then
			if
				pointLayer.volumetricCanvasCameraInfo.position ~= cameraPositionFull or
				pointLayer.volumetricCanvasCameraInfo.orientation ~= cameraOrientation or
				pointLayer.volumetricCanvasCameraInfo.brightnessMultiplier ~= luminanceMultiplier
			then
				-- TODO: Reprojection
				local original = love.graphics.getCanvas()
				love.graphics.setCanvas(pointLayer.volumetricCanvas)
				love.graphics.clear()
				love.graphics.setCanvas(pointLayer.volumetricAddCountCanvas)
				love.graphics.clear()
				love.graphics.setCanvas(original)
			end
		end
		pointLayer.volumetricCanvasCameraInfo = {
			position = bm.vec3.clone(cameraPositionFull),
			orientation = mathsies.quat.clone(cameraOrientation),
			brightnessMultiplier = luminanceMultiplier
		}

		local distanceUnitScale = 1 / math.max(parentObjectRadii.x, parentObjectRadii.y, parentObjectRadii.z)
		local shapeType = self.pointLayerShapeTypes[parentObjectShapeTypeName]
		local attenuationShapeType = self.pointLayerShapeTypes[attenuationShapeTypeName]
		local volumetricShader = self.shapeVolumeShaders[parentObjectShapeTypeName][attenuationShapeTypeName or consts.noAttenuationShapeTypeName]

		-- Send shape params for point density (aka emission)
		local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(shapeType, parentObjectShapeSubtypeId)
		for i, parameter in ipairs(shapeType.parameters) do
			volumetricShader:send("emissionShape_" .. parameter.name, densityParametersScratchTable[i])
		end
		-- And for attenuation
		local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(attenuationShapeType, attenuationShapeSubtypeId)
		for i, parameter in ipairs(attenuationShapeType.parameters) do
			volumetricShader:send("attenuationShape_" .. parameter.name, densityParametersScratchTable[i])
		end

		if pointLayer.hasNoiseEmission and shapeType.noiseInfo then
			volumetricShader:send("EmissionNoiseValues", pointLayer.valueNoiseBufferEmission)
		end
		if pointLayer.hasNoiseAttenuation and attenuationShapeType.noiseInfo then
			volumetricShader:send("AttenuationNoiseValues", pointLayer.valueNoiseBufferAttenuation)
		end

		local cornerDirs = {}
		for y = 1, -1, -2 do
			for x = -1, 1, 2 do
				local clipSpacePos = mathsies.vec3(x, y, -1) -- -1 for near plane but it makes no difference one everything is normalised in the compute shader. It may need to be consistent per-corner, though
				local result = clipToSky * clipSpacePos
				-- table.insert(cornerDirs, result.x)
				-- table.insert(cornerDirs, result.y)
				-- table.insert(cornerDirs, result.z)
				table.insert(cornerDirs, {mathsies.vec3.components(result)})
			end
		end
		volumetricShader:send("brightnessMultiplier", luminanceMultiplier)
		volumetricShader:send("preNormaliseCornerDirs", unpack(cornerDirs))
		volumetricShader:send("size", {pointLayer.volumetricCanvas:getDimensions()})
		volumetricShader:send("resultCanvas", pointLayer.volumetricCanvas)
		volumetricShader:send("additionCountCanvas", pointLayer.volumetricAddCountCanvas)
		volumetricShader:send("rayStepVariance", 1)
		volumetricShader:send("raySeed", love.math.random(0, 2 ^ 32 - 1))
		volumetricShader:send("fadeInRadius", fullyVolumetricRadiusProperUnits * distanceUnitScale)
		volumetricShader:send("fadeOutRadius", fullyPointRadiusProperUnits * distanceUnitScale)
		volumetricShader:send("fadeExponent", consts.pointFadeExponent)
		-- volumetricShader:send("clipToSky", {mathsies.mat4.components(clipToSky)})
		volumetricShader:send("cameraPosition", {mathsies.vec3.components(bm.vec3.toMathsiesVec3(cameraPositionFullRelative * distanceUnitScale))})
		volumetricShader:send("maxRaySteps", consts.volumetricMaxRaySteps)
		volumetricShader:send("shapeRadii", {mathsies.vec3.components(distanceUnitScale * parentObjectRadii)})
		volumetricShader:send("baseEmission", {
			-- TODO: Understand how these distanceUnitScale things work. I thought you multiplied in an amount with an exponent corresponding to the exponent on the distance dimension?
			distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageLuminousFluxRPerPoint / (2 * consts.tau), -- TODO: This 4pi is definitely wrong... or something around it is
			distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageLuminousFluxGPerPoint / (2 * consts.tau),
			distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageLuminousFluxBPerPoint / (2 * consts.tau)
		})
		volumetricShader:send("baseAttenuation", 1e4) -- TODO
		-- volumetricShader:send("luminousIntensityPerPoint", {1, 1, 1})
		-- volumetricShader:send("maxDensity", 1)
		local w, h = volumetricShader:getLocalThreadgroupSize()
		love.graphics.dispatchThreadgroups(volumetricShader,
			math.ceil(pointLayer.volumetricCanvas:getWidth() / w),
			math.ceil(pointLayer.volumetricCanvas:getHeight() / h)
		)

		love.graphics.setShader(self.drawVolumetricShader)
		self.drawVolumetricShader:send("additions", pointLayer.volumetricAddCountCanvas)
		self.drawVolumetricShader:send("scale", consts.volumetricCanvasScale)
		love.graphics.draw(pointLayer.volumetricCanvas, 0, 0, 0, 1 / consts.volumetricCanvasScale)

		-- TODO: Point attenuation

		-- Points

		-- love.graphics.setCanvas(self.screenCanvasses.pointCanvas)
		-- love.graphics.clear(0, 0, 0, 1)

		self.pointIndirectDrawArgsBuffer:setArrayData({
			self.pointDiskMesh:getVertexCount(),
			0, -- This gets incremented (on the GPU)
			0,
			0
		})

		local diskDistanceToSphere = 1 - math.cos(consts.pointAngularRadius) -- Unit sphere spherical cap height from angular radius
		local diskSolidAngle = consts.tau * diskDistanceToSphere
		local scaleToGetAngularRadius = math.tan(consts.pointAngularRadius)
		local luminanceCalcConst = luminanceMultiplier / (diskSolidAngle * 2 * consts.tau)

		local maxAngleFromCentre = diagonalFOV / 2 + consts.pointAngularRadius
		local minDot = math.cos(maxAngleFromCentre)
		local currentObjectInfo = pointLayer.currentObject or pointLayer.currentPotentialObject
		local skipIndex =
			currentObjectInfo and (
				currentObjectInfo.chunkBufferIndex * pointLayer.maxPointsPerChunk + currentObjectInfo.pointId
			) or pointLayer.maxPoints -- Use unreachable skip index
		if pointLayer.currentPotentialObject and not pointLayer.currentObject then
			-- Draw in a CPU-calculated direction to fix precision issues when on the approach to small galaxies
			local object = pointLayer.currentPotentialObject
			local x, y, z = pointLayer:getPointVars(object.chunkBufferIndex, object.pointId, "position", "float", 3)
			local position = bm.vec3(object.chunkX + x, object.chunkY + y, object.chunkZ + z)
			local difference = position - cameraPositionFullRelative / pointLayer.chunkSize
			local distance = bm.vec3.length(difference)
			if distance == 0 then
				skipIndex = pointLayer.maxPoints -- Use unreachable skip index
			else
				local direction = difference / distance
				direction = bm.vec3.toMathsiesVec3(direction)
				distance = bm.mapm.tonumber(distance)
				local r, g, b = pointLayer:getPointVars(object.chunkBufferIndex, object.pointId, "luminousFlux", "float", 3)
				local luminance = mathsies.vec3(r, g, b) / distance ^ 2 * luminanceCalcConst
				self.individualPointShader:send("diskDistanceToSphere", diskDistanceToSphere)
				self.individualPointShader:send("scale", scaleToGetAngularRadius)
				self.individualPointShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
				self.individualPointShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
				self.individualPointShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
				self.individualPointShader:send("direction", {mathsies.vec3.components(direction)})
				self.individualPointShader:send("luminance", {mathsies.vec3.components(luminance)})
				love.graphics.setShader(self.individualPointShader)
				love.graphics.draw(self.pointDiskMesh)
			end
		end

		local preparationShader = pointLayer.pointPreparationShader
		preparationShader:send("luminanceCalcConst", luminanceCalcConst)
		preparationShader:send("chunkBufferSideLength", pointLayer.chunkBufferSideLength)
		preparationShader:send("viewMinPosInChunkBuffer", {
			(cameraPosition.x - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength,
			(cameraPosition.y - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength,
			(cameraPosition.z - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength
		})
		preparationShader:send("cameraPosition", {
			(cameraPosition.x + pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength + pointLayer.chunkBufferSideLength / 2,
			(cameraPosition.y + pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength + pointLayer.chunkBufferSideLength / 2,
			(cameraPosition.z + pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength + pointLayer.chunkBufferSideLength / 2
		})
		preparationShader:send("minDot", minDot)
		preparationShader:send("cameraForwards", {mathsies.vec3.components(cameraForwards)})
		preparationShader:send("fadeInRadius", fullyPointRadius)
		preparationShader:send("fadeOutRadius", fullyVolumetricRadius)
		preparationShader:send("fadeExponent", consts.pointFadeExponent)
		-- preparationShader:send("skyToClip", {mathsies.mat4.components(skyToClip)}) -- TODO (this is for attenuation)
		preparationShader:send("skipIndex", skipIndex)
		preparationShader:send("maxPointsPerChunk", pointLayer.maxPointsPerChunk)
		preparationShader:send("IndirectDrawBuffer", self.pointIndirectDrawArgsBuffer)
		preparationShader:send("Points", pointLayer.pointBuffer)
		preparationShader:send("PointDrawables", self.pointDrawableBuffer)
		preparationShader:send("ChunkPointCounts", pointLayer.chunkPointCountBuffer)
		local threadgroupCount = math.ceil(pointLayer.maxPoints / preparationShader:getLocalThreadgroupSize())
		love.graphics.dispatchThreadgroups(preparationShader, threadgroupCount)

		local drawShader = self.pointDrawablesShader
		love.graphics.setShader(drawShader)
		drawShader:send("PointDrawables", self.pointDrawableBuffer)
		drawShader:send("diskDistanceToSphere", diskDistanceToSphere)
		drawShader:send("scale", scaleToGetAngularRadius)
		drawShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
		drawShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
		drawShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
		-- current shader should be drawShader
		love.graphics.drawIndirect(self.pointDiskMesh, self.pointIndirectDrawArgsBuffer, 1)

		-- love.graphics.setCanvas(outputCanvas)
		-- love.graphics.setShader()
		-- love.graphics.draw(self.screenCanvasses.pointCanvas)
	end

	love.graphics.setShader()
	love.graphics.setBlendMode("alpha")
end

return game
