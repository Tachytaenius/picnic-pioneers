local info = {}

info.attenuation = true

info.parameters = {
	{
		name = "nebulaExponent",
		samples = 3,
		rangeMin = 5,
		rangeMax = 7
	},
	{
		name = "distanceExponent",
		samples = 3,
		rangeMin = 0.8,
		rangeMax = 1.2
	},
	{
		name = "nebulaMultiplier",
		samples = 6,
		rangeMin = 1,
		rangeMax = 400
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

-- Attenuation shape density functions can return values greater than 1.
-- The only reason emission shapes can't is that there is a maximum expected number of points per chunk (corresponding to a return value of 1).

info.needsTrueRatio = true
function info.getDensity(x, y, z, xTrueRatio, yTrueRatio, zTrueRatio, nebulaExponent, distanceExponent, nebulaMultiplier)
	return
		math.max(0, 1 - math.sqrt(x^2+y^2+z^2)) ^ distanceExponent * (
			2 * valueNoise(1, xTrueRatio, yTrueRatio, zTrueRatio) + -- Multiply the noise by 2 to give an average of 1 so that the object's attenuation multiplier is more or less the average
			nebulaMultiplier * (
				(
					valueNoise(2, xTrueRatio, yTrueRatio, zTrueRatio) +
					valueNoise(3, xTrueRatio, yTrueRatio, zTrueRatio) +
					valueNoise(4, xTrueRatio, yTrueRatio, zTrueRatio)
				) / 3
			) ^ nebulaExponent
		)
end

return info
