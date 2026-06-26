local info = {}

info.valueNoiseInfo = {
	{
		countX = 32,
		countY = 32,
		countZ = 32
	}
}

info.parameters = {
	{
		name = "densityExponent",
		steps = 3,
		rangeMin = 0.25,
		rangeMax = 3
	}
}

function info.getDensity(x, y, z, densityExponent)
	return valueNoise(1, x, y, z) * math.max(0, 1 - math.sqrt(x^2+y^2+z^2)) ^ densityExponent
end

return info
