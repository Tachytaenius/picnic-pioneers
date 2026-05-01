local info = {}

info.parameters = {
	{
		name = "densityExponent",
		steps = 5,
		rangeMin = 0.25,
		rangeMax = 3
	}
}

function info.getDensity(x, y, z, densityExponent)
	return math.max(0, 1 - math.sqrt(x^2+y^2+z^2)) ^ densityExponent
end

return info
