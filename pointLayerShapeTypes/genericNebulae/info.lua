local info = {}

-- Attenuation shape density functions can return values greater than 1.
-- The only reason emission shapes can't is that there is a maximum expected number of points per chunk (corresponding to a return value of 1).

info.needsTrueRatio = true

info.averageAttenuationSpectrumForPrecalc = true -- Use less averaging iterations to get the right average spectral radiances going through this attenuation shape type
-- Only set averageAttenuationSpectrumForPrecalc if the average values of an attenuation shape type are equal for the whole spectrum

info.attenuation = true

info.parameters = {
	{
		name = "nebulaExponent",
		samples = 2,
		rangeMin = 5,
		rangeMax = 7
	},
	{
		name = "nebulaMultiplier",
		samples = 3,
		rangeMin = 1,
		rangeMax = 500
	}
}

info.valueNoiseInfo = {
	{
		countX = 7,
		countY = 7,
		countZ = 7
	},
	{
		countX = 31,
		countY = 31,
		countZ = 31
	},
	{
		countX = 51,
		countY = 51,
		countZ = 51
	},
	{
		countX = 101,
		countY = 101,
		countZ = 101
	},

	-- Colour
	{
		countX = 5,
		countY = 5,
		countZ = 5
	},
	{
		countX = 5,
		countY = 5,
		countZ = 5
	},
	{
		countX = 5,
		countY = 5,
		countZ = 5
	}
}

return info
