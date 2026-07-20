local info = {}

info.valueNoiseInfo = {
	{
		countX = 27,
		countY = 27,
		countZ = 27
	},
	{
		countX = 27,
		countY = 27,
		countZ = 27
	}
}

info.constants = {
	noise1Exponent = 80,
	noise2Exponent = 80,
	distExponent = 1
}

-- valueNoise is given by setfenv elsewhere in the codebase
function info.getDensity(x, y, z)
	local len = math.sqrt(x^2+y^2+z^2)

	local noise1Value = math.max(0, 1 - math.abs(valueNoise(1, x, y, z) * 2 - 1)) ^ info.constants.noise1Exponent
	local noise2Value = math.max(0, 1 - math.abs(valueNoise(2, x, y, z) * 2 - 1)) ^ info.constants.noise2Exponent

	local densityMultiplier = math.max(0, 1 - len) ^ info.constants.distExponent

	return densityMultiplier * noise1Value * noise2Value
end

return info
