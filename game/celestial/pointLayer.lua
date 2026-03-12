-- There are lots of different coordinate systems in this file...
-- In general, anything that needs to be both large and precise has either been avoided (e.g. by scaling down), or arbitrary precision numbers have been used

local ffi = require("ffi")
local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local consts = require("consts")

local game = {}

local galaxyPointLayerFunctions = {}

local function randomTODO()
	-- TODO: Not this!
	return love.math.random()
end

function galaxyPointLayerFunctions:getDensity(realX, realY, realZ) -- The position is in units where 1 is the side length of a chunk. Returned density is in proper units
	return 1 -- TODO
end

function galaxyPointLayerFunctions:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex)
	local density = self:getDensity(realX, realY, realZ)
	local amount = density * self.maxPointDensity * self.chunkVolume -- TODO: Rename properly.
	local count = math.floor(amount)
	if randomTODO() < amount % 1 then -- Use fractional part of amount as a probability
		count = count + 1
	end
	count = math.min(self.maxPointsPerChunk, count) -- Just in case

	for i = 0, count - 1 do
		local x = randomTODO()
		local y = randomTODO()
		local z = randomTODO()

		local r = 0.0001
		local g = 0.0001
		local b = 0.0001

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b)
	end

	return count
end

local starPointLayerFunctions = {}

function starPointLayerFunctions:getDensity(realX, realY, realZ)
	return 1 -- TODO
end

function starPointLayerFunctions:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex)
	local density = self:getDensity(realX, realY, realZ)
	local amount = density * self.maxPointDensity * self.chunkVolume
	local count = math.floor(amount)
	if randomTODO() < amount % 1 then
		count = count + 1
	end
	count = math.min(self.maxPointsPerChunk, count)

	for i = 0, count - 1 do
		local x = randomTODO()
		local y = randomTODO()
		local z = randomTODO()

		local r = randomTODO() * 0.001
		local g = randomTODO() * 0.001
		local b = randomTODO() * 0.001

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b)
	end

	return count
end

function game:initPointLayers()
	self.pointLayers = {}

	-- Topmost layer is treated specially
	local galaxyLayer = self:newPointLayer("galaxies", "Galaxies", consts.galaxyLayerChunkSize, consts.maxGalacticDensity, 4, galaxyPointLayerFunctions)
	galaxyLayer.fixedParentObjectPosition = consts.galaxyGroupPosition
	galaxyLayer.fixedParentObjectRadii = consts.galaxyGroupRadii
	self:newPointLayer("stars", "Stars", consts.starLayerChunkSize, consts.maxStellarDensity, 9, starPointLayerFunctions)

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
end

local pointLayerFunctions = {}

function pointLayerFunctions:getBoundingBoxChunks()
	local size
	if self.parentPointLayer then
		local currentObject = self.parentPointLayer.currentObject
		assert(currentObject, "Should not be calling getBoundingBoxChunks on a point layer if its parent doesn't have a current object")
		size = currentObject.radii
	else
		size = self.fixedParentObjectRadii
	end
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
	local curAddr = index * self.pointBuffer:getElementStride() / consts.bytesPerFloat
	for i = 1, self.pointFormatVarCount do
		local property = select(i, ...)
		self.pointDataFFI[curAddr + self.pointDataIndexMap[i - 1]] = property -- Casts from double to float
	end
end

function pointLayerFunctions:getPointPosition(chunkBufferIndex, pointId) -- Position within chunk, where 1 is chunk size
	local index = chunkBufferIndex * self.maxPointsPerChunk + pointId
	assert(index >= 0 and index < self.maxPoints, "chunkBufferIndex and pointId given to setPoint exceed point buffer capacity")
	local curAddr = index * self.pointBuffer:getElementStride() / consts.bytesPerFloat

	local x = self.pointDataFFI[curAddr + self.pointFormatOffsets.x / consts.bytesPerFloat]
	local y = self.pointDataFFI[curAddr + self.pointFormatOffsets.y / consts.bytesPerFloat]
	local z = self.pointDataFFI[curAddr + self.pointFormatOffsets.z / consts.bytesPerFloat]
	return x, y, z
end

function pointLayerFunctions:getPointLuminousFlux(chunkBufferIndex, pointId) -- Is also scaled down to match same distance units as its position
	local index = chunkBufferIndex * self.maxPointsPerChunk + pointId
	assert(index >= 0 and index < self.maxPoints, "chunkBufferIndex and pointId given to setPoint exceed point buffer capacity")
	local curAddr = index * self.pointBuffer:getElementStride() / consts.bytesPerFloat

	local r = self.pointDataFFI[curAddr + self.pointFormatOffsets.r / consts.bytesPerFloat]
	local g = self.pointDataFFI[curAddr + self.pointFormatOffsets.g / consts.bytesPerFloat]
	local b = self.pointDataFFI[curAddr + self.pointFormatOffsets.b / consts.bytesPerFloat]
	return r, g, b
end

function pointLayerFunctions:generateChunkCommon(realX, realY, realZ, chunkId, chunkBufferIndex)
	local chunkPointCount = self:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex) -- Specified per layer

	self:setChunkPointCount(chunkBufferIndex, chunkPointCount)
	if chunkPointCount > 0 then
		local pointIdStart = chunkBufferIndex * self.maxPointsPerChunk
		self.pointBuffer:setArrayData(self.pointData, pointIdStart + 1, pointIdStart + 1, chunkPointCount)
	end
end

function pointLayerFunctions:setChunkEmpty(x, y, z, chunkBufferIndex)
	local chunk = self.chunkExtraInfo[x][y][z]
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
	for x = math.floor(positionRelative.x - 0.5), math.floor(positionRelative.x + 0.5) do
		for y = math.floor(positionRelative.y - 0.5), math.floor(positionRelative.y + 0.5) do
			for z = math.floor(positionRelative.z - 0.5), math.floor(positionRelative.z + 0.5) do
				local xInChunkBuffer = x % self.chunkBufferSideLength
				local yInChunkBuffer = y % self.chunkBufferSideLength
				local zInChunkBuffer = z % self.chunkBufferSideLength
				local chunkBufferIndex = xInChunkBuffer + yInChunkBuffer * self.chunkBufferSideLength + zInChunkBuffer * self.chunkBufferSideLength * self.chunkBufferSideLength
				for pointId = 0, self:getChunkPointCount(chunkBufferIndex) - 1 do
					temp.x, temp.y, temp.z = self:getPointPosition(chunkBufferIndex, pointId)
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

function game:newPointLayer(name, debugName, chunkSize, maxPointDensity, chunkBufferSideLength, layerSpecificFunctions)
	local new = {}

	for k, v in pairs(pointLayerFunctions) do
		new[k] = v
	end
	for k, v in pairs(layerSpecificFunctions) do
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

	-- TODO: Dynamically construct depending on what the layer needs
	new.pointBufferFormat = {
		{name = "position", format = "floatvec3"},
		{name = "luminousFlux", format = "floatvec3"}
	}
	new.pointPreparationShader = love.graphics.newComputeShader("shaders/drawing/pointPreparation.glsl", {defines = {
		-- TODO: Dynamically define features like blinking stars, brightness based on rotation, etc
		THREADGROUP_SIZE = consts.pointPreparationThreadgroupSize
	}})

	new.chunkPointCountBuffer = love.graphics.newBuffer(consts.intBufferFormat, new.chunkBufferTotalSize, {
		shaderstorage = true,
		debugname = debugName .. " Chunk Point Counts"
	})
	new.chunkPointCountData = love.data.newByteData(new.chunkPointCountBuffer:getElementStride() * new.chunkBufferTotalSize)
	new.chunkPointCountDataFFI = ffi.cast("int32_t*", new.chunkPointCountData:getFFIPointer())

	new.pointBuffer = love.graphics.newBuffer(new.pointBufferFormat, new.maxPoints, {
		shaderstorage = true,
		debugname = debugName .. " Points"
	})
	new.pointData = love.data.newByteData(new.pointBuffer:getElementStride() * new.maxPoints)
	new.pointDataFFI = ffi.cast("float*", new.pointData:getFFIPointer())
	local pointFormatVarCount = 0
	local pointFormatOffsets = {}
	local pointDataIndexMap = {}
	local function registerPointFormatVar(name, byteOffset)
		pointFormatOffsets[name] = byteOffset
		pointDataIndexMap[pointFormatVarCount] = byteOffset / consts.bytesPerFloat
		pointFormatVarCount = pointFormatVarCount + 1
	end
	for _, variable in ipairs(new.pointBuffer:getFormat()) do
		if variable.name == "position" then
			registerPointFormatVar("x", variable.offset)
			registerPointFormatVar("y", variable.offset + consts.bytesPerFloat)
			registerPointFormatVar("z", variable.offset + consts.bytesPerFloat * 2)
		elseif variable.name == "luminousFlux" then
			registerPointFormatVar("r", variable.offset)
			registerPointFormatVar("g", variable.offset + consts.bytesPerFloat)
			registerPointFormatVar("b", variable.offset + consts.bytesPerFloat * 2)
		end
	end
	new.pointFormatVarCount = pointFormatVarCount
	new.pointFormatOffsets = pointFormatOffsets
	new.pointDataIndexMap = pointDataIndexMap

	new.chunkExtraInfo = {}
	for x = 0, new.chunkBufferSideLength - 1 do
		new.chunkExtraInfo[x] = {}
		for y = 0, new.chunkBufferSideLength - 1 do
			new.chunkExtraInfo[x][y] = {}
			for z = 0, new.chunkBufferSideLength - 1 do
				new.chunkExtraInfo[x][y][z] = {
					x = nil,
					y = nil,
					z = nil,
					masses = {} -- Starts at 0
				}
			end
		end
	end

	new.parentPointLayer = self.pointLayers[#self.pointLayers]
	table.insert(self.pointLayers, new)
	new.index = #self.pointLayers
	return new
end

function game:handlePointLayers()
	local remakeAll = false
	for i, pointLayer in ipairs(self.pointLayers) do
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

					local currentChunk = pointLayer.chunkExtraInfo[x][y][z]
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
							pointLayer:setChunkEmpty(x, y, z, chunkBufferIndex)
						end
					end
				end
			end
		end

		if updateChunkCountBuffer then
			pointLayer.chunkPointCountBuffer:setArrayData(pointLayer.chunkPointCountData, 1, 1, pointLayer.chunkBufferTotalSize)
		end

		if love.keyboard.isDown("c") and not pointLayer.parentPointLayer then -- TEMP
			local x, y, z = pointLayer:getPointPosition(0, 0)
			self.ship.position = parentOrigin + pointLayer.chunkSize * bm.vec3(0+x, 0+y, 0+z)
		end

		local closestChunkX, closestChunkY, closestChunkZ, closestIdInChunk, closestDistance = pointLayer:getClosestPoint(self.ship.position)
		if closestIdInChunk and closestDistance < consts.pointMinDistanceInChunk / 2 then
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

				local x, y, z = pointLayer:getPointPosition(chunkBufferIndex, closestIdInChunk)
				local r, g, b = pointLayer:getPointLuminousFlux(chunkBufferIndex, closestIdInChunk)

				pointLayer.currentObject = {
					chunkId = chunkId,
					chunkBufferIndex = chunkBufferIndex, -- Won't change
					pointId = closestIdInChunk,
					-- chunkX = closestChunkX,
					-- chunkY = closestChunkY,
					-- chunkZ = closestChunkZ,
					position = parentOrigin + pointLayer.chunkSize * bm.vec3(closestChunkX + x, closestChunkY + y, closestChunkZ + z),
					luminousFlux = mathsies.vec3(r, g, b) * pointLayer.chunkSize ^ 2, -- Bring back to proper units
					-- TODO: Generate remaining info, including radii
					radii = mathsies.vec3(100, 4, 100) * consts.starLayerChunkSize -- TEMP
				}

				remakeAll = true
			end
		else
			pointLayer.currentObject = nil
			self:clearPointLayers(i + 1)
			break
		end
	end
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
		preparationShader:send("pointCount", pointLayer.maxPoints)
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
