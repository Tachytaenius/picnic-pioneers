-- There are lots of different coordinate systems in this file...
-- In general, anything that needs to be both large and precise has either been avoided (e.g. by scaling down), or arbitrary precision numbers have been used

local ffi = require("ffi")
local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local setValueNoiseFunctionVars = require("threadCode.common.setValueNoiseFunctionVars")

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
	fixedParentObjectRadii = consts.galaxyGroupRadii,
	fixedParentObjectShapeTypeName = consts.galaxyGroupShapeTypeName,
	fixedParentObjectShapeSubtypeId = 0 -- TODO: Allow selecting from closest subtype to given parameters...?
}

galaxyPointLayerInfo.features = {
	-- "sent" means present on both CPU and GPU, "unsent" means only present on CPU, nil means not present
	shapeTypeSubtypeIds = "sent",
	radii = "unsent",
	mass = "unsent",

	shapeTypeSet = {
		{
			name = "ellipticalGalaxy",
			weight = 1,
			scaleMin = 7.5e18,
			scaleMax = 9e19,
			-- NOTE: If a factor is added to make the distribution of scales non-uniform, ensure that the per-layer average mass estimates are changed accordingly
			zScaleRatioMin = 1.5, -- Less than 1 is flatter
			zScaleRatioMax = 4
		},
		{
			name = "spiralGalaxy",
			weight = 16,
			scaleMin = 3e19,
			scaleMax = 9e20,
			zScaleRatioMin = 0.075,
			zScaleRatioMax = 0.2,
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

		local scale = randomRangeTODO(choice.scaleMin, choice.scaleMax)
		local zScaleRatio = randomRangeTODO(choice.zScaleRatioMin, choice.zScaleRatioMax)

		local xRadius = scale
		local yRadius = scale
		local zRadius = scale * zScaleRatio
		radii[i * 3] = xRadius
		radii[i * 3 + 1] = yRadius
		radii[i * 3 + 2] = zRadius

		local amountWithin = shapeType.subtypeBaseObjectAmounts[shapeSubtypeId] * xRadius * yRadius * zRadius * nextLayerMaxDensity -- Estimate
		mass[i] = amountWithin * nextLayerAverageMassPerPoint

		local r = amountWithin * nextLayerAverageLuminousFluxRPerPoint * luminousFluxScale
		local g = amountWithin * nextLayerAverageLuminousFluxGPerPoint * luminousFluxScale
		local b = amountWithin * nextLayerAverageLuminousFluxBPerPoint * luminousFluxScale

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b, shapeTypeId, shapeSubtypeId)
	end
end

function galaxyPointLayerInfo:generateRemainingCurrentObjectInfo()
	local currentObject = self.currentObject
end

function galaxyPointLayerInfo:getGlobalCelestialObjectIdParameters() -- Separate from the 128-bit number split into four 32-bit numbers that this produces
	local currentObject = self.currentObject
	local objectType = consts.idObjectTypes.galaxy
	local galaxyChunkId = currentObject.chunkId
	local galaxyId = currentObject.pointId
	-- local starChunkId
	-- local starId
	-- local systemBodyId
	return objectType, galaxyChunkId, galaxyId
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

function starSystemPointLayerInfo:getGlobalCelestialObjectIdParameters()
	local parentObject = self.parentPointLayer.currentObject
	local currentObject = self.currentObject
	local objectType = consts.idObjectTypes.starSystem
	local galaxyChunkId = parentObject.chunkId
	local galaxyId = parentObject.pointId
	local starChunkId = currentObject.chunkId
	local starId = currentObject.pointId
	-- local systemBodyId
	return objectType, galaxyChunkId, galaxyId, starChunkId, starId
end

function game:initPointLayers()
	self.pointLayers = {}

	self.slowdownSampleDistribution = self:initSampleDistribution(consts.shapeSlowdownIntegralHighestStepCount)
	self.massDataSampleDistributions = {} -- 0-indexed
	for i = 0, consts.shapeSlowdownIntegralDetail do
		self.massDataSampleDistributions[i] = self:initSampleDistribution(2 ^ i)
	end

	-- Topmost layer is treated specially
	-- TODO: Allow it to collapse to a point when sufficiently far away. Since that's just one point there's no need for optimisations like chunks etc. Would definitely be easier if the topmost point layer has a semi-functioning parent point layer for this purpose
	local topLayer = self:newPointLayer("galaxies", "Galaxies", consts.galaxyLayerChunkSize, consts.maxGalacticDensity, 17, galaxyPointLayerInfo)
	self:newPointLayer("starSystems", "Star Systems", consts.starLayerChunkSize, consts.maxStellarDensity, 13, starSystemPointLayerInfo)

	self.valueNoiseDataReusableForPointLayers = nil -- If no point layers took this then it now no longer will be used

	-- Find distance at which top layer shape has the same angular radius as points
	local topRadius = math.max(topLayer.fixedParentObjectRadii.x, topLayer.fixedParentObjectRadii.y, topLayer.fixedParentObjectRadii.z)
	topLayer.fixedParentObjectPointDistance = self:getSphereResolvableDistance(topRadius)

	-- TODO: Seed RNG with consistent seed for the universe
	topLayer:randomiseValueNoise()
	topLayer:writeMassData()

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

	-- Check
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

				local minS, maxS = shapeTypeInfo.scaleMin, shapeTypeInfo.scaleMax
				local minZR, maxZR = shapeTypeInfo.zScaleRatioMin, shapeTypeInfo.zScaleRatioMax
				local averageBaseObjectAmountMultiplier =
					1 / 8 *
					(minS + maxS) *
					(minS ^ 2 + maxS ^ 2) *
					(minZR + maxZR)

				local total = 0
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
				-- shapeTypeInfo is the point layer's usage of the shape, shapeType is the shape type itself
				for subtypeId = 0, shapeType.subtypeCount - 1 do
					total = total +
						shapeType.subtypeBaseObjectAmounts[subtypeId] *
						averageBaseObjectAmountMultiplier *
						childPointLayer.maxPointDensity
				end
				local averageAmountThisShapeTypeInfo = total / shapeType.subtypeCount

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
			local identifier = "point layer " .. i .. ", shape type info " .. j
			assert(shapeTypeInfo.scaleMin <= shapeTypeInfo.scaleMax, "Scale min and max are flipped for " .. identifier)
			assert(shapeTypeInfo.zScaleRatioMin <= shapeTypeInfo.zScaleRatioMax, "Z scale ratio min and max are flipped for " .. identifier)
			local largestX = shapeTypeInfo.scaleMax
			local largestY = shapeTypeInfo.scaleMax
			local largestZ = shapeTypeInfo.scaleMax * shapeTypeInfo.zScaleRatioMax
			local minX, maxX, minY, maxY, minZ, maxZ = getBoundingBoxChunksForSize(layer.chunkSize, largestX, largestY, largestZ)
			local widthChunks = maxX - minX + 1
			local heightChunks = maxY - minY + 1
			local depthChunks = maxZ - minZ + 1
			local largestChunkCount = widthChunks * heightChunks * depthChunks
			local maximumChunks = 2 ^ 36
			if largestChunkCount >= maximumChunks then -- 36 bits as per getGlobalCelestialObjectIdNumbers
				error("Too many chunks possible for " .. identifier .. ". Must be at most " .. maximumChunks)
			end

			local maxAllowedResolvableDistance = layer.chunkSize * consts.pointMinDistanceInChunk / 2
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
	local returnValue = densityFunction(
		realX / size.x * self.chunkSize,
		realY / size.y * self.chunkSize,
		realZ / size.z * self.chunkSize,
		unpack(densityParametersScratchTable)
	)
	return returnValue
end

function pointLayerFunctions:randomiseValueNoise()
	-- Should be called with RNG set
	local relevantShapeTypeName =
		self.parentPointLayer and self.parentPointLayer.currentObject.shapeTypeName
		or self.fixedParentObjectShapeTypeName
	local shapeType = self.gameObject.pointLayerShapeTypes[relevantShapeTypeName]
	if not shapeType.noiseInfo then
		-- Won't be used, can safely leave it as it is
		return
	end
	-- This layer will have a noise buffer/data if it can ever be contained in a shape type that has noise.
	for i = 0, shapeType.noiseInfo.requiredValueCount - 1 do
		self.valueNoiseDataFFI[i] = randomTODO()
	end
	self.valueNoiseBuffer:setArrayData(self.valueNoiseData, 1, 1, shapeType.noiseInfo.requiredValueCount)
end

function pointLayerFunctions:prepareValueNoiseFunction() -- This is per shape type, so in case multiple layers use the same shape type this must be set before every use of the density function
	local relevantShapeTypeName =
		self.parentPointLayer and self.parentPointLayer.currentObject.shapeTypeName
		or self.fixedParentObjectShapeTypeName
	local shapeType = self.gameObject.pointLayerShapeTypes[relevantShapeTypeName]
	if not shapeType.noiseInfo then
		return
	end
	local layers = shapeType.noiseInfo.layers
	local dataFFI = self.valueNoiseDataFFI
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
	local amount = density * self.maxPointDensity * self.chunkVolume -- TODO: Rename properly.
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

function pointLayerFunctions:getClosestPoint(referencePosition)
	local parentOrigin
	if not self.parentPointLayer then
		parentOrigin = self.fixedParentObjectPosition
	else
		assert(self.parentPointLayer.currentObject, "Can't call getClosestPoint on a pointLayer that isn't loaded")
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
	-- TODO: Fix assumption that there are points in the 2x2x2 chunk cube around the ship. Maybe spiral outwards when searching? Or just have a distance limit?
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

function pointLayerFunctions:writeMassData()
	local s = love.timer.getTime()

	local shapeTypeName, shapeSubtypeId
	if self.parentPointLayer then
		local currentObject = self.parentPointLayer.currentObject
		shapeTypeName = currentObject.shapeTypeName
		shapeSubtypeId = currentObject.shapeSubtypeId
	else
		shapeTypeName = self.fixedParentObjectShapeTypeName
		shapeSubtypeId = self.fixedParentObjectShapeSubtypeId
	end
	local shapeType = self.gameObject.pointLayerShapeTypes[shapeTypeName]
	local scratch = self.gameObject:decodeShapeSubtypeIntoScratchTable(shapeType, shapeSubtypeId)

	local distributions = self.gameObject.massDataSampleDistributions
	for lod = consts.shapeSlowdownIntegralDetail, 0, -1 do
		local sampleDistribution = distributions[lod]

		for i = 1, #sampleDistribution do
			local infoTable = {
				shapeTypeId = shapeType.id,
				params = scratch,
				valueNoiseData = self.valueNoiseData,
				type = "massWrite",
				firstSample = sampleDistribution[i].firstSample,
				lastSample = sampleDistribution[i].lastSample,
				stepCount = sampleDistribution.stepCount,

				shapeMassData = self.shapeMassData,
				lodToWriteTo = lod,
				massDataStartOffsets = consts.shapeSlowdownIntegralDataStarts
			}
			love.thread.getChannel("shapeAmountsInfo"):push(infoTable)
		end

		for _=1, #sampleDistribution do
			while true do
				local finished = love.thread.getChannel("shapeAmountsResult"):demand(consts.shapeIntegralThreadTimeout)
				if finished then
					break
				else
					self.gameObject:checkThreadsForErrors()
				end
			end
		end
	end

	local e = love.timer.getTime()
	-- print(e - s) -- TODO: Minimise (or spread out over multiple frames before it's needed, rather)
end

function game:clearPointLayers(startIndex)
	for i = startIndex, #self.pointLayers do
		local pointLayer = self.pointLayers[i]
		pointLayer.currentObject = nil
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

	new.pointPreparationShader = love.graphics.newComputeShader("shaders/drawing/pointPreparation.glsl", {defines = defines})

	new.chunkPointCountBuffer = love.graphics.newBuffer(consts.intBufferFormat, new.chunkBufferTotalSize, {
		shaderstorage = true,
		debugname = debugName .. " Chunk Point Counts"
	})
	new.chunkPointCountData = love.data.newByteData(new.chunkPointCountBuffer:getElementStride() * new.chunkBufferTotalSize)
	new.chunkPointCountDataFFI = ffi.cast("int32_t*", new.chunkPointCountData:getFFIPointer())

	local maxNoiseValues = 0
	local hasNoise = false
	local relevantShapeTypeSet = new.parentPointLayer and new.parentPointLayer.features.shapeTypeSet
	if not relevantShapeTypeSet then
		assert(new.index == 1, "Only the top layer should not have a parent layer")
		local shapeType = self.pointLayerShapeTypes[new.fixedParentObjectShapeTypeName]
		if shapeType.noiseInfo then
			hasNoise = true
			maxNoiseValues = math.max(maxNoiseValues, shapeType.noiseInfo.requiredValueCount)
		end
	else
		for _, shapeTypeInfo in ipairs(relevantShapeTypeSet) do
			local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
			if shapeType.noiseInfo then
				hasNoise = true
				maxNoiseValues = math.max(maxNoiseValues, shapeType.noiseInfo.requiredValueCount)
			end
		end
	end
	new.hasNoise = hasNoise
	if hasNoise then
		new.maxNoiseValues = maxNoiseValues

		new.valueNoiseBuffer = love.graphics.newBuffer(consts.floatBufferFormat, new.maxNoiseValues, {
			shaderstorage = true,
			debugname = debugName .. " Noise Values"
		})
		local requiredSize = new.valueNoiseBuffer:getElementStride() * new.maxNoiseValues
		if
			self.valueNoiseDataReusableForPointLayers and
			self.valueNoiseDataReusableForPointLayers:getSize() == requiredSize
		then
			new.valueNoiseData = self.valueNoiseDataReusableForPointLayers
			self.valueNoiseDataReusableForPointLayers = nil
		else
			new.valueNoiseData = love.data.newByteData(requiredSize)
		end
		new.valueNoiseDataFFI = ffi.cast("float*", new.valueNoiseData:getFFIPointer())
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
				self:clearPointLayers(pointLayerIndex + 1)
				break
			else
				pointLayer.topLayerOutOfRange = false
			end
		end
		local closestChunkX, closestChunkY, closestChunkZ, closestIdInChunk, closestDistance = pointLayer:getClosestPoint(self.ship.position)
		if closestIdInChunk and closestDistance < consts.pointMinDistanceInChunk / 2 then
			local x2, y2, z2 = closestChunkX - minX, closestChunkY - minY, closestChunkZ - minZ
			local chunkId = x2 + y2 * widthChunks + z2 * widthChunks * heightChunks

			local chunkBufferX = closestChunkX % pointLayer.chunkBufferSideLength
			local chunkBufferY = closestChunkY % pointLayer.chunkBufferSideLength
			local chunkBufferZ = closestChunkZ % pointLayer.chunkBufferSideLength
			local chunkBufferIndex = chunkBufferX + chunkBufferY * pointLayer.chunkBufferSideLength + chunkBufferZ * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength

			local chunkExtraInfo = pointLayer.chunkExtraInfo[chunkBufferIndex]

			local resolvable
			local xRadius, yRadius, zRadius
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
					local shapeTypeId, shapeSubtypeId
					if pointLayer.features.shapeTypeSubtypeIds == "sent" then
						shapeTypeId, shapeSubtypeId = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "shapeTypeSubtypeIds", "uint32", 2)
					elseif pointLayer.features.shapeTypeId == "unsent" then
						shapeTypeId, shapeSubtypeId = chunkExtraInfo.shapeTypeId[closestIdInChunk * 2], chunkExtraInfo.shapeTypeId[closestIdInChunk * 2 + 1]
					end
					currentObject.shapeTypeName = self.pointLayerShapeTypes[shapeTypeId].name
					currentObject.shapeSubtypeId = shapeSubtypeId
				end
				if pointLayer.features.radii then
					currentObject.radii = mathsies.vec3(xRadius, yRadius, zRadius) -- TODO: Make sure it never goes over separation between points (/2)
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
				-- TODO: Seed RNG with pointLayer:getGlobalCelestialObjectIdParameters()
				if pointLayer.childPointLayer then
					if pointLayer.childPointLayer.hasNoise then
						pointLayer.childPointLayer:randomiseValueNoise()
					end
					pointLayer.childPointLayer:writeMassData()
				end
				-- Remaining features are generated (or fetched from extra info) in possibly layer-specific ways
				pointLayer:generateRemainingCurrentObjectInfo()

				remakeAll = true
			end
		else
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
	-- 		shapeType.subtypeBaseObjectAmounts[shapeSubtypeId] *
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
			local massData = pointLayer.shapeMassDataFFI
			local range = consts.lodBoxRange
			local posX = positionRelativeFull.x / parentRadii.x * 0.5 + 0.5
			local posY = positionRelativeFull.y / parentRadii.y * 0.5 + 0.5
			local posZ = positionRelativeFull.z / parentRadii.z * 0.5 + 0.5
			local cutRegionStartX = xLower * pointLayer.chunkSize / parentRadii.x * 0.5 + 0.5
			local cutRegionStartY = yLower * pointLayer.chunkSize / parentRadii.y * 0.5 + 0.5
			local cutRegionStartZ = zLower * pointLayer.chunkSize / parentRadii.z * 0.5 + 0.5
			local cutRegionEndX = (xUpper + 1) * pointLayer.chunkSize / parentRadii.x * 0.5 + 0.5
			local cutRegionEndY = (yUpper + 1) * pointLayer.chunkSize / parentRadii.y * 0.5 + 0.5
			local cutRegionEndZ = (zUpper + 1) * pointLayer.chunkSize / parentRadii.z * 0.5 + 0.5
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
				local thisLodCutRegionStartX = cutRegionStartX * lodStepCount
				local thisLodCutRegionStartY = cutRegionStartY * lodStepCount
				local thisLodCutRegionStartZ = cutRegionStartZ * lodStepCount
				local thisLodCutRegionEndX = cutRegionEndX * lodStepCount
				local thisLodCutRegionEndY = cutRegionEndY * lodStepCount
				local thisLodCutRegionEndZ = cutRegionEndZ * lodStepCount
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
								local sampleCutStartX = math.max(x, thisLodCutRegionStartX)
								local sampleCutEndX = math.min((x + 1), thisLodCutRegionEndX)
								local sampleCutStartY = math.max(y, thisLodCutRegionStartY)
								local sampleCutEndY = math.min((y + 1), thisLodCutRegionEndY)
								local sampleCutStartZ = math.max(z, thisLodCutRegionStartZ)
								local sampleCutEndZ = math.min((z + 1), thisLodCutRegionEndZ)
								local cutVolume =
									math.max(0, sampleCutEndX - sampleCutStartX) *
									math.max(0, sampleCutEndY - sampleCutStartY) *
									math.max(0, sampleCutEndZ - sampleCutStartZ)
								local volumeProportion = math.max(0, 1 - cutVolume)
								local mass = massData[sampleI] * pointLayer.averageMassPerPoint * pointLayer.maxPointDensity * dataVolumeToRealVolume * volumeProportion
								local samplePosX = ((x + 0.5) / lodStepCount * 2 - 1) * parentRadii.x
								local samplePosY = ((y + 0.5) / lodStepCount * 2 - 1) * parentRadii.y
								local samplePosZ = ((z + 0.5) / lodStepCount * 2 - 1) * parentRadii.z
								local distance = math.sqrt(
									(samplePosX - positionRelativeFull.x) ^ 2 +
									(samplePosY - positionRelativeFull.y) ^ 2 +
									(samplePosZ - positionRelativeFull.z) ^ 2
								)
								if distance > 0 then
									totalThisLayer = totalThisLayer + mass * distance ^ exponent
								end
							end
						end
					end
				end
			end
		else
			local shapeType = self.pointLayerShapeTypes[parentShapeTypeName]
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
	local outputCanvas = love.graphics.getCanvas()
	local aspectRatio = outputCanvas:getWidth() / outputCanvas:getHeight()

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
		local parentOrigin, parentObjectShapeTypeName, parentObjectShapeSubtypeId, parentObjectRadii
		if not pointLayer.parentPointLayer then
			parentOrigin = pointLayer.fixedParentObjectPosition
			parentObjectShapeTypeName = pointLayer.fixedParentObjectShapeTypeName
			parentObjectShapeSubtypeId = pointLayer.fixedParentObjectShapeSubtypeId
			parentObjectRadii = pointLayer.fixedParentObjectRadii
		else
			if not pointLayer.parentPointLayer.currentObject then
				break -- Outside of any objects below this scale
			end
			parentOrigin = pointLayer.parentPointLayer.currentObject.position
			parentObjectShapeTypeName = pointLayer.parentPointLayer.currentObject.shapeTypeName
			parentObjectShapeSubtypeId = pointLayer.parentPointLayer.currentObject.shapeSubtypeId
			parentObjectRadii = pointLayer.parentPointLayer.currentObject.radii
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

		local distanceUnitScale = 1 / math.max(parentObjectRadii.x, parentObjectRadii.y, parentObjectRadii.z)
		local shapeType = self.pointLayerShapeTypes[parentObjectShapeTypeName]
		local volumetricShader = shapeType.volumetricShader

		-- Send shape params
		local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(shapeType, parentObjectShapeSubtypeId)
		for i, parameter in ipairs(shapeType.parameters) do
			volumetricShader:send("shape_" .. parameter.name, densityParametersScratchTable[i])
		end

		if pointLayer.hasNoise and shapeType.noiseInfo then
			volumetricShader:send("NoiseValues", pointLayer.valueNoiseBuffer)
		end
		volumetricShader:send("fadeInRadius", fullyVolumetricRadiusProperUnits * distanceUnitScale)
		volumetricShader:send("fadeOutRadius", fullyPointRadiusProperUnits * distanceUnitScale)
		volumetricShader:send("fadeExponent", consts.pointFadeExponent)
		volumetricShader:send("clipToSky", {mathsies.mat4.components(clipToSky)})
		volumetricShader:send("cameraPosition", {mathsies.vec3.components(bm.vec3.toMathsiesVec3(cameraPositionFullRelative * distanceUnitScale))})
		volumetricShader:send("maxRaySteps", consts.volumetricMaxRaySteps)
		volumetricShader:send("shapeRadii", {mathsies.vec3.components(distanceUnitScale * parentObjectRadii)})
		volumetricShader:send("baseEmission", {
			-- TODO: Understand how these distanceUnitScale things work. I thought you multiplied in an amount with an exponent corresponding to the exponent on the distance dimension?
			distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageLuminousFluxRPerPoint / (2 * consts.tau), -- TODO: This 4pi is definitely wrong... or something around it is
			distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageLuminousFluxGPerPoint / (2 * consts.tau),
			distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageLuminousFluxBPerPoint / (2 * consts.tau)
		})
		-- volumetricShader:send("luminousIntensityPerPoint", {1, 1, 1})
		-- volumetricShader:send("maxDensity", 1)
		love.graphics.setShader(volumetricShader)
		love.graphics.draw(self.dummyTexture, 0, 0, 0, outputCanvas:getDimensions())

		-- TODO: Point attenuation

		-- Points

		love.graphics.setShader(self.pointDrawablesShader)

		self.pointIndirectDrawArgsBuffer:setArrayData({
			self.pointDiskMesh:getVertexCount(),
			0, -- This gets incremented (on the GPU)
			0,
			0
		})

		local diskDistanceToSphere = 1 - math.cos(consts.pointAngularRadius) -- Unit sphere spherical cap height from angular radius
		local diskSolidAngle = consts.tau * diskDistanceToSphere
		local scaleToGetAngularRadius = math.tan(consts.pointAngularRadius)
		local luminanceCalcConst = 1 / (diskSolidAngle * 2 * consts.tau)

		local maxAngleFromCentre = diagonalFOV / 2 + consts.pointAngularRadius
		local minDot = math.cos(maxAngleFromCentre)
		local skipIndex =
			pointLayer.currentObject and (
				pointLayer.currentObject.chunkBufferIndex * pointLayer.maxPointsPerChunk + pointLayer.currentObject.pointId
			) or pointLayer.maxPoints -- Use unreachable skip index

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
		drawShader:send("PointDrawables", self.pointDrawableBuffer)
		drawShader:send("diskDistanceToSphere", diskDistanceToSphere)
		drawShader:send("scale", scaleToGetAngularRadius)
		drawShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
		drawShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
		drawShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
		-- current shader should be drawShader
		love.graphics.drawIndirect(self.pointDiskMesh, self.pointIndirectDrawArgsBuffer, 1)
	end

	love.graphics.setShader()
	love.graphics.setBlendMode("alpha")
end

return game
