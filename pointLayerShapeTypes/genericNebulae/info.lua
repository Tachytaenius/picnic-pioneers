local info = {}

info.attenuation = true

info.parameters = {
	{
		name = "noiseExponent",
		steps = 3,
		rangeMin = 5,
		rangeMax = 7
	},
	{
		name = "distanceExponent",
		steps = 3,
		rangeMin = 0.8,
		rangeMax = 1.2
	}
}

info.valueNoiseInfo = {
	{
		countX = 7,
		countY = 7,
		countZ = 7
	},
	{
		countX = 15,
		countY = 15,
		countZ = 15
	},
	{
		countX = 25,
		countY = 25,
		countZ = 25
	},
	{
		countX = 33,
		countY = 33,
		countZ = 33
	}
}

info.needsTrueRatio = true
function info.getDensity(x, y, z, xTrueRatio, yTrueRatio, zTrueRatio, noiseExponent, distanceExponent)
	return
		math.max(0, 1 - math.sqrt(x^2+y^2+z^2)) ^ distanceExponent * (
			valueNoise(1, xTrueRatio, yTrueRatio, zTrueRatio) * (
				valueNoise(2, xTrueRatio, yTrueRatio, zTrueRatio) +
				valueNoise(3, xTrueRatio, yTrueRatio, zTrueRatio) +
				valueNoise(4, xTrueRatio, yTrueRatio, zTrueRatio)
			) / 3
		) ^ noiseExponent
end

return info
