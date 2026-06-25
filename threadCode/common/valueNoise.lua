local trilinearMix = require("threadCode.common.trilinearMix")

-- valueNoiseDataFFI and currentNoiseLayers must be setfenv'd in

local min, max = math.min, math.max

local function clamp(x, l, u)
	return max(l, min(u, x))
end

local floor = math.floor

local function getValue(data, start, sizeX, sizeY, sizeZ, posX, posY, posZ)
	local index = start + posX + posY * sizeX + posZ * sizeX * sizeY
	return data[index]
end

return function(layerIndex, x, y, z)
	x = x * 0.5 + 0.5
	y = y * 0.5 + 0.5
	z = z * 0.5 + 0.5
	local layer = currentNoiseLayers[layerIndex]
	local start = layer.start
	local sizeX = layer.countX
	local sizeY = layer.countY
	local sizeZ = layer.countZ
	local cellSizeX = 1 / (sizeX - 1)
	local cellSizeY = 1 / (sizeY - 1)
	local cellSizeZ = 1 / (sizeZ - 1)
	local mixX = (x % cellSizeX) / cellSizeX
	local mixY = (y % cellSizeY) / cellSizeY
	local mixZ = (z % cellSizeZ) / cellSizeZ
	local cellX = clamp(floor(x / cellSizeX), 0, sizeX - 2)
	local cellY = clamp(floor(y / cellSizeY), 0, sizeY - 2)
	local cellZ = clamp(floor(z / cellSizeZ), 0, sizeZ - 2)
	return trilinearMix(
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 0, cellY + 0, cellZ + 0),
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 0, cellY + 0, cellZ + 1),
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 0, cellY + 1, cellZ + 0),
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 0, cellY + 1, cellZ + 1),
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 1, cellY + 0, cellZ + 0),
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 1, cellY + 0, cellZ + 1),
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 1, cellY + 1, cellZ + 0),
		getValue(valueNoiseDataFFI, start, sizeX, sizeY, sizeZ, cellX + 1, cellY + 1, cellZ + 1),
		mixX, mixY, mixZ
	)
end
