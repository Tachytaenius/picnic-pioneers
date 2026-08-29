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
		samples = 3,
		rangeMin = 0.25,
		rangeMax = 3
	}
}

info.zScaleRatioMin = 0.1 -- Less than 1 is flatter (lenticular?). Oblate vs prolate spheroids.
info.zScaleRatioMax = 3
info.zScaleRatioSamples = 8
info.needsTrueRatio = true -- Will be passed coordinates that depend on shape object ratios, and the (no longer necessarily linear) effect that scaling has on the total mass of the object will be precomputed for varying scales and interpolated between for real scales

local max = math.max
local sqrt = math.sqrt

function info.getDensity(x, y, z, xTrueRatio, yTrueRatio, zTrueRatio, densityExponent)
	return
		valueNoise(1, xTrueRatio, yTrueRatio, zTrueRatio) *
		max(0, 1 - sqrt(x^2+y^2+z^2)) ^ densityExponent
end

return info
