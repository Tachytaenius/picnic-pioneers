-- There are lots of different coordinate systems in this file...
-- In general, anything that needs to be both large and precise has either been avoided (e.g. by scaling down), or arbitrary precision numbers have been used

local ffi = require("ffi")
local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local util = require("util")
local consts = require("consts")
local pointLayerShapeTypes = require("pointLayerShapeTypes")

local game = {}

local function randomTODO()
	-- TODO: Not this!
	return love.math.random()
end

local galaxyPointLayerInfo = {}

galaxyPointLayerInfo.features = {
	-- "sent" means present on both CPU and GPU, "unsent" means only present on CPU, nil means not present
	shapeTypeId = "sent",
	radii = "unsent",
	mass = "unsent",

	shapeTypeSet = {
		{
			name = "ellipticalGalaxy",
			weight = 1,
			scaleMin = 2e19,
			scaleMax = 8e21
		}
		-- We also add spiral galaxies with arms
	}
}
for n = 2, 4 do
	local weight = 5
	table.insert(galaxyPointLayerInfo.features.shapeTypeSet, {
		name = "spiralGalaxy" .. n .. "Arms",
		weight = weight,
		scaleMin = 8e19,
		scaleMax = 2e22
	})
end

function galaxyPointLayerInfo:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count)
	local randomChoice = util.weightedRandomChoice
	local shapeTypeSet = self.features.shapeTypeSet
	local extraInfo = self.chunkExtraInfo[chunkBufferIndex]
	local radii = extraInfo.radii
	local mass = extraInfo.mass
	local nextLayerChunkSize = self.childPointLayer.chunkSize
	local nextLayerMaxDensity = self.childPointLayer.maxPointDensity
	-- TODO: Calculate all the way from base layer (stars) using shape types and weights etc to get these values
	local averageMassPerContainedPoint = 1.989e30 -- TEMP
	local averageLuminousFluxPerContainedPointR = 3.562e28 -- TEMP -- Proper units
	local averageLuminousFluxPerContainedPointG = 3.562e28
	local averageLuminousFluxPerContainedPointB = 3.562e28
	local luminousFluxScale = self.chunkSize ^ -2
	for i = 0, count - 1 do
		local x = randomTODO()
		local y = randomTODO()
		local z = randomTODO()

		-- local choice = randomChoice(shapeTypeSet, randomGeneratorTODO)
		-- local shapeTypeId = pointLayerShapeTypes[choice.name].id
		-- local scale = randomTODO() * (choice.scaleMax - choice.scaleMin) + choice.scaleMin
		-- local shapeTypeId = pointLayerShapeTypes.testDisk.id -- TEMP
		local shapeTypeId = pointLayerShapeTypes.galaxyCluster.id
		local scale = 8e20 -- TEMP

		-- NOTE/TEMP/TODO? changes made that may be wrong: scale is no longer divided by nextLayerChunkSize, amountWIthin is now multiplied by nextLayerMaxDensity, and there is no multiplication by nextLayerChunkSize when creating a currentObject

		local xRadius = scale
		local yRadius = scale
		local zRadius = scale / 100 -- TEMP, etc etc etc
		radii[i * 3] = xRadius
		radii[i * 3 + 1] = yRadius
		radii[i * 3 + 2] = zRadius

		local amountWithin = pointLayerShapeTypes[shapeTypeId].baseObjectAmount * xRadius * yRadius * zRadius * nextLayerMaxDensity -- Estimate
		mass[i] = amountWithin * averageMassPerContainedPoint
		-- print(mass[i])
		GM = mass[i] -- TEMP!!!!!

		local r = amountWithin * averageLuminousFluxPerContainedPointR * luminousFluxScale
		local g = amountWithin * averageLuminousFluxPerContainedPointG * luminousFluxScale
		local b = amountWithin * averageLuminousFluxPerContainedPointB * luminousFluxScale

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b, shapeTypeId)
	end
end

function galaxyPointLayerInfo:generateRemainingCurrentObjectInfo()
	local currentObject = self.currentObject
end

local starPointLayerInfo = {}

starPointLayerInfo.features = {
	mass = "unsent",
	properScaleRadius = "unsent",
	bodies = true -- Final layer, treated differently
}

function starPointLayerInfo:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count)
	local extraInfo = self.chunkExtraInfo[chunkBufferIndex]
	local properScaleRadius = extraInfo.properScaleRadius
	local mass = extraInfo.mass
	local luminousFluxScale = self.chunkSize ^ -2
	for i = 0, count - 1 do
		local x = randomTODO()
		local y = randomTODO()
		local z = randomTODO()

		local r = (randomTODO() * 0.5 + 0.75) * 3.562e28 * luminousFluxScale
		local g = (randomTODO() * 0.5 + 0.75) * 3.562e28 * luminousFluxScale
		local b = (randomTODO() * 0.5 + 0.75) * 3.562e28 * luminousFluxScale

		local radius = 6.957e8 -- TEMP/TODO
		properScaleRadius[i] = radius
		local starMass = 1.989e30 * 10 ^ (randomTODO() * 2 - 1)
		mass[i] = starMass

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b)
	end
end

function starPointLayerInfo:generateRemainingCurrentObjectInfo()
	local currentObject = self.currentObject
end

function game:initPointLayers()
	pointLayerShapeTypes.load()

	self.pointLayers = {}

	-- Topmost layer is treated specially
	-- TODO: Allow it to collapse to a point when sufficiently far away. Since that's just one point there's no need for optimisations like chunks etc.
	local topLayer = self:newPointLayer("galaxies", "Galaxies", consts.galaxyLayerChunkSize, consts.maxGalacticDensity, 4, galaxyPointLayerInfo)
	topLayer.fixedParentObjectPosition = consts.galaxyGroupPosition
	topLayer.fixedParentObjectRadii = consts.galaxyGroupRadii
	topLayer.fixedParentObjectShapeTypeName = consts.galaxyGroupShapeTypeName
	self:newPointLayer("stars", "Stars", consts.starLayerChunkSize, consts.maxStellarDensity, 9, starPointLayerInfo)

	-- Find distance at which top layer shape has the same angular radius as points
	local topRadius = math.max(topLayer.fixedParentObjectRadii.x, topLayer.fixedParentObjectRadii.y, topLayer.fixedParentObjectRadii.z)
	topLayer.fixedParentObjectPointDistance = topRadius / math.sqrt(1 - math.cos(consts.pointAngularRadius) ^ 2)

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
end

local pointLayerFunctions = {}

function pointLayerFunctions:getDensity(realX, realY, realZ) -- The position is in units where 1 is the side length of a chunk. Returned density is a proportion from 0 to point layer max density
	local shapeTypeName, size
	if self.parentPointLayer then
		local currentObject = self.parentPointLayer.currentObject
		assert(currentObject, "Should not be calling getDensity on a point layer if its parent doesn't have a current object")
		shapeTypeName = currentObject.shapeTypeName
		size = currentObject.radii
	else
		shapeTypeName = self.fixedParentObjectShapeTypeName
		size = self.fixedParentObjectRadii
	end
	local densityFunction = pointLayerShapeTypes[shapeTypeName].getDensity
	return densityFunction(realX / size.x * self.chunkSize, realY / size.y * self.chunkSize, realZ / size.z * self.chunkSize)
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
	-- TODO: I think this and the code using it breaks (slightly) when size[x/y/z] / chunkSize is an integer
	local minX, maxX = math.floor(-size.x / self.chunkSize), math.floor(size.x / self.chunkSize)
	local minY, maxY = math.floor(-size.y / self.chunkSize), math.floor(size.y / self.chunkSize)
	local minZ, maxZ = math.floor(-size.z / self.chunkSize), math.floor(size.z / self.chunkSize)
	return minX, maxX, minY, maxY, minZ, maxZ
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
	local density = self:getDensity(realX, realY, realZ)
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

	new.name = name
	new.debugName = debugName
	new.chunkSize = chunkSize
	new.maxPointDensity = maxPointDensity
	new.chunkBufferSideLength = chunkBufferSideLength

	new.chunkVolume = chunkSize ^ 3
	new.chunkBufferTotalSize = chunkBufferSideLength ^ 3
	new.maxPointsPerChunk = math.ceil(new.chunkVolume * new.maxPointDensity)
	new.maxPoints = new.chunkBufferTotalSize * new.maxPointsPerChunk

	-- TODO: Don't waste VRAM on unsent features
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
	tryFeature("shapeTypeId", "uint32", "SHAPE_TYPE")
	tryFeature("radii", "floatvec3", "RADII")
	tryFeature("mass", "float", "MASS") -- For final layer (stars)
	tryFeature("properScaleRadius", "float", nil) -- For final layer (stars)

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
		if variable.format == "float" or variable.format == "int" or variable.format == "uint32" then
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

	new.parentPointLayer = self.pointLayers[#self.pointLayers]
	if new.parentPointLayer then
		new.parentPointLayer.childPointLayer = new
	end
	table.insert(self.pointLayers, new)
	new.index = #self.pointLayers
	return new
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
							local chunkId = x2 + y2 * widthChunks + z2 * heightChunks * depthChunks

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

		-- Reveals bug, will fix. move out of galaxy render range and start holding c and suddenly galaxy is broken
		if love.keyboard.isDown("c") --[[and not pointLayer.parentPointLayer]] then -- TEMP
			local x, y, z = pointLayer:getPointVars(0, 0, "position", "float", 3)
			self.ship.position = parentOrigin + pointLayer.chunkSize * bm.vec3(0+x, 0+y, 0+z)
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
			-- TODO: Also check that its angular radius isn't smaller than that of the points
			local x2, y2, z2 = closestChunkX - minX, closestChunkY - minY, closestChunkZ - minZ
			local chunkId = x2 + y2 * widthChunks + z2 * heightChunks * depthChunks

			if not (
				pointLayer.currentObject and
				pointLayer.currentObject.chunkId == chunkId and
				pointLayer.currentObject.pointId == closestIdInChunk
			) then
				local chunkBufferX = closestChunkX % pointLayer.chunkBufferSideLength
				local chunkBufferY = closestChunkY % pointLayer.chunkBufferSideLength
				local chunkBufferZ = closestChunkZ % pointLayer.chunkBufferSideLength
				local chunkBufferIndex = chunkBufferX + chunkBufferY * pointLayer.chunkBufferSideLength + chunkBufferZ * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength

				local x, y, z = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "position", "float", 3)
				local r, g, b = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "luminousFlux", "float", 3)

				pointLayer.currentObject = { -- TODO: Make this be layer-specific and dynamic on features
					chunkId = chunkId,
					chunkBufferIndex = chunkBufferIndex, -- Won't change for the same object
					pointId = closestIdInChunk,

					-- chunkX = closestChunkX,
					-- chunkY = closestChunkY,
					-- chunkZ = closestChunkZ
				}
				local currentObject = pointLayer.currentObject
				local chunkExtraInfo = pointLayer.chunkExtraInfo[chunkBufferIndex]
				-- Features with consistent ways of calculating
				currentObject.position =
					parentOrigin + pointLayer.chunkSize *
					bm.vec3(closestChunkX + x, closestChunkY + y, closestChunkZ + z)
				currentObject.luminousFlux = mathsies.vec3(r, g, b) * pointLayer.chunkSize ^ 2 -- Bring back to proper units
				if pointLayer.features.shapeTypeId then
					local shapeTypeId
					if pointLayer.features.shapeTypeId == "sent" then
						shapeTypeId = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "shapeTypeId", "uint32", 1)
					elseif pointLayer.features.shapeTypeId == "unsent" then
						shapeTypeId = chunkExtraInfo.shapeTypeId[closestIdInChunk]
					end
					currentObject.shapeTypeName = pointLayerShapeTypes[shapeTypeId].name
				end
				if pointLayer.features.radii then
					local nextLayerChunkSize = pointLayer.childPointLayer.chunkSize
					local xRadius, yRadius, zRadius
					if pointLayer.features.radii == "sent" then
						xRadius, yRadius, zRadius = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "radii", "float", 3)
					elseif pointLayer.features.radii == "unsent" then
						xRadius = chunkExtraInfo.radii[closestIdInChunk * 3]
						yRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 1]
						zRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 2]
					end
					assert(xRadius and yRadius and zRadius, "Missing radii")
					currentObject.radii = mathsies.vec3(xRadius, yRadius, zRadius) -- TODO: Make sure it never goes over separation between points (/2)
				end
				-- Remaining features are generated (or fetched from extra info) in possibly layer-specific ways
				pointLayer:generateRemainingCurrentObjectInfo()

				remakeAll = true
			end
		else
			pointLayer.currentObject = nil
			self:clearPointLayers(pointLayerIndex + 1)
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

	local topLayer = self.pointLayers[1]
	if topLayer.topLayerOutOfRange then
		-- TODO: Calculate
		return 1
	end

	for pointLayerIndex, pointLayer in ipairs(self.pointLayers) do
		local massSent
		if pointLayer.features.mass == "sent" then
			massSent = true
		elseif pointLayer.features.mass == "unsent" then
			massSent = false
		else
			goto continue
		end

		local parentOrigin, parentRadii, parentShapeTypeName
		if not pointLayer.parentPointLayer then
			parentOrigin = pointLayer.fixedParentObjectPosition
			parentRadii = pointLayer.fixedParentObjectRadii
			parentShapeTypeName = pointLayer.fixedParentObjectShapeTypeName
		elseif pointLayer.parentPointLayer.currentObject then
			parentOrigin = pointLayer.parentPointLayer.currentObject.position
			parentRadii = pointLayer.parentPointLayer.currentObject.radii
			parentShapeTypeName = pointLayer.parentPointLayer.currentObject.shapeTypeName
		else
			break
		end
		local positionRelativeFull = bm.vec3.toMathsiesVec3(referencePosition - parentOrigin)
		local positionRelative = bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
			(referencePosition - parentOrigin) / pointLayer.chunkSize
		)

		local totalThisLayer = 0

		local temp = mathsies.vec3() -- No need to generate tons of new vec3s
		local xLower, xUpper = math.floor(positionRelative.x - 0.5), math.floor(positionRelative.x + 0.5)
		local yLower, yUpper = math.floor(positionRelative.y - 0.5), math.floor(positionRelative.y + 0.5)
		local zLower, zUpper = math.floor(positionRelative.z - 0.5), math.floor(positionRelative.z + 0.5)
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
								-- if pointLayerIndex==2 then print(pointLayerIndex, "out", mass, distance * pointLayer.chunkSize, mass * (distance * pointLayer.chunkSize) ^ exponent) end
								totalThisLayer = totalThisLayer + mass * (distance * pointLayer.chunkSize) ^ exponent
							end
						end
					end
					::continue::
				end
			end
		end

		local radiusChunks = parentRadii / pointLayer.chunkSize
		local detail = 12
		local sampleCount, sampledVolume = 0, 0 -- TEMP
		local densityFunction = pointLayerShapeTypes[parentShapeTypeName].getDensity
		local function sample(x, y, z, w, h, d)
			sampleCount = sampleCount + 1
			sampledVolume = sampledVolume + w * h * d

			local averageMassPerPoint = pointLayerIndex == 1 and GM or 1.989e30 -- TEMP
			local density = densityFunction(x, y, z) * pointLayer.maxPointDensity * averageMassPerPoint
			local trueDeltaX = x * parentRadii.x - positionRelativeFull.x
			local trueDeltaY = y * parentRadii.y - positionRelativeFull.y
			local trueDeltaZ = z * parentRadii.z - positionRelativeFull.z
			local trueW = w * parentRadii.x
			local trueH = h * parentRadii.y
			local trueD = d * parentRadii.z
			local dist = math.sqrt(trueDeltaX ^ 2 + trueDeltaY ^ 2 + trueDeltaZ ^ 2)
			if dist > 0 then
				totalThisLayer = totalThisLayer + density * dist ^ exponent * trueW * trueH * trueD
			end
		end
		-- Sample boxes in a grid that (TODO) decreases in detail the further out you go (TODO end), missing the cell containing the chunks that we have already checked the points of
		local lerp, sign = util.lerp, util.sign
		for xi = -detail, detail do
			for yi = -detail, detail do
				for zi = -detail, detail do
					-- I got tired at this point. This code can probably be improved

					local xi, xSide = math.abs(xi), sign(xi)
					local yi, ySide = math.abs(yi), sign(yi)
					local zi, zSide = math.abs(zi), sign(zi)

					-- TODO: Make this work when outside chunk range

					local sampleX, xCellSize
					if xSide == -1 then
						local xa = math.min(1, xLower / radiusChunks.x)
						-- xLower / radiusChunks.x is approximately equal to (positionRelative.x / pointLayer.chunkSize - sampledChunksWidth / 2) / radiusChunks.x
						local xb = -1
						if xa <= xb then
							goto continue
						end
						xCellSize = (xa - xb) / detail
						sampleX = lerp(xa, xb, (xi + 0.5) / detail)
					elseif xSide == 1 then
						local xa = math.max(-1, (xUpper + 1) / radiusChunks.x)
						local xb = 1
						if xa >= xb then
							goto continue
						end
						xCellSize = (xb - xa) / detail
						sampleX = lerp(xa, xb, (xi + 0.5) / detail)
					elseif math.abs(positionRelative.x / radiusChunks.x) < 1 then
						xCellSize = (xUpper + 1 - xLower) / radiusChunks.x
						sampleX = positionRelative.x / radiusChunks.x
					else
						goto continue
					end

					local sampleY, yCellSize
					if ySide == -1 then
						local ya = math.min(1, yLower / radiusChunks.y)
						local yb = -1
						if ya < yb then
							goto continue
						end
						yCellSize = (ya - yb) / detail
						sampleY = lerp(ya, yb, (yi + 0.5) / detail)
					elseif ySide == 1 then
						local ya = math.max(-1, (yUpper + 1) / radiusChunks.y)
						local yb = 1
						if ya > yb then
							goto continue
						end
						yCellSize = (yb - ya) / detail
						sampleY = lerp(ya, yb, (yi + 0.5) / detail)
					elseif math.abs(positionRelative.y / radiusChunks.y) < 1 then
						yCellSize = (yUpper + 1 - yLower) / radiusChunks.y
						sampleY = positionRelative.y / radiusChunks.y
					else
						goto continue
					end

					local sampleZ, zCellSize
					if zSide == -1 then
						local za = math.min(1, zLower / radiusChunks.z)
						local zb = -1
						if za < zb then
							goto continue
						end
						zCellSize = (za - zb) / detail
						sampleZ = lerp(za, zb, (zi + 0.5) / detail)
					elseif zSide == 1 then
						local za = math.max(-1, (zUpper + 1) / radiusChunks.z)
						local zb = 1
						if za > zb then
							goto continue
						end
						zCellSize = (zb - za) / detail
						sampleZ = lerp(za, zb, (zi + 0.5) / detail)
					elseif math.abs(positionRelative.z / radiusChunks.z) < 1 then
						zCellSize = (zUpper + 1 - zLower) / radiusChunks.z
						sampleZ = positionRelative.z / radiusChunks.z
					else
						goto continue
					end

					if xi == 0 and yi == 0 and zi == 0 then
						goto continue
					end

					sample(sampleX, sampleY, sampleZ, xCellSize, yCellSize, zCellSize)

					::continue::
				end
			end
		end

		-- TEMP
		local chunkCheckedVolume = sampledChunksWidth * sampledChunksHeight * sampledChunksDepth / (radiusChunks.x * radiusChunks.y * radiusChunks.z)
		-- is 2 ^ 3 - sampledVolume approximately equal to chunkCheckedVolume when the size of everything is small enough to avoid huge rounding error? (it should be!!!!!!!)
		-- print(pointLayerIndex, sampleCount, chunkCheckedVolume, 2 ^ 3 - sampledVolume, totalThisLayer) -- -1 to 1 on each axis

		total = total + totalThisLayer

		::continue::
	end

	-- print(total, 1 / (total / consts.gravitySlowdownResultDivisor) ^ consts.gravitySlowdownResultExponent)

	return total
end

function game:drawPointLayers()
	local outputCanvas = love.graphics.getCanvas()
	local aspectRatio = outputCanvas:getWidth() / outputCanvas:getHeight()

	local cameraPositionFull = self.ship.position
	local cameraOrientation = self.ship.orientation
	local cameraVerticalFOV = self.ship.verticalFOV

	local cameraForwards = mathsies.vec3.rotate(consts.forwardVector, cameraOrientation)
	local cameraUp = mathsies.vec3.rotate(consts.upVector, cameraOrientation)
	local cameraRight = mathsies.vec3.rotate(consts.rightVector, cameraOrientation)
	local cameraToClip = mathsies.mat4.perspectiveLeftHanded(
		aspectRatio,
		cameraVerticalFOV,
		2,
		0.5
	)
	local worldToCameraStationary = mathsies.mat4.camera(mathsies.vec3(), cameraOrientation)
	local skyToClip = cameraToClip * worldToCameraStationary
	local clipToSky = mathsies.mat4.inverse(skyToClip)

	love.graphics.setShader(self.pointDrawablesShader)
	love.graphics.setBlendMode("add")

	for _, pointLayer in ipairs(self.pointLayers) do
		local parentOrigin
		if not pointLayer.parentPointLayer then
			parentOrigin = pointLayer.fixedParentObjectPosition
		else
			if not pointLayer.parentPointLayer.currentObject then
				break -- Outside of any objects below this scale
			end
			parentOrigin = pointLayer.parentPointLayer.currentObject.position
		end
		local cameraPosition = bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
			(cameraPositionFull - parentOrigin) / pointLayer.chunkSize
		)

		-- TODO: Volumetrics

		-- TODO: Point attenuation

		-- Points

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
		local diagonalFOV = cameraVerticalFOV * math.sqrt(1 ^ 2 + aspectRatio ^ 2) -- Angular distance from camera forwards at corners of screen
		local maxAngleFromCentre = diagonalFOV / 2 + consts.pointAngularRadius
		local minDot = math.cos(maxAngleFromCentre)
		local fadeInRadius = (pointLayer.chunkBufferSideLength / 2 - 0.5) * consts.pointFadeStart
		local fadeOutRadius = pointLayer.chunkBufferSideLength / 2 - 0.5
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
		preparationShader:send("fadeInRadius", fadeInRadius)
		preparationShader:send("fadeOutRadius", fadeOutRadius)
		-- preparationShader:send("skyToClip", {mathsies.mat4.components(skyToClip)}) -- TODO
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
