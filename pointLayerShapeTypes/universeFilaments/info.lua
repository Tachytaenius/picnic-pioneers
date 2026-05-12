local info = {}

info.valueNoiseInfo = {
	{
		countX = 12,
		countY = 12,
		countZ = 12
	},
	{
		countX = 16,
		countY = 16,
		countZ = 16
	}
}

local noise1Exponent = 10
local noise2Exponent = 10
local distExponent = 2

-- valueNoise is given by setfenv elsewhere in the codebase
function info.getDensity(x, y, z)
	local len = math.sqrt(x^2+y^2+z^2)

	local noise1Value = math.max(0, 1 - math.abs(valueNoise(1, x, y, z) * 2 - 1)) ^ noise1Exponent
	local noise2Value = math.max(0, 1 - math.abs(valueNoise(2, x, y, z) * 2 - 1)) ^ noise2Exponent

	local densityMultiplier = math.max(0, 1 - len) ^ distExponent

	return densityMultiplier * noise1Value * noise2Value
end

return info
