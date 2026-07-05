local info = {
	raySteps = 16
}

info.parameters = {
	{
		name = "densityExponent",
		steps = 2,
		rangeMin = 1.5,
		rangeMax = 4
	},
	{
		name = "armCount",
		steps = 4,
		rangeMin = 2,
		rangeMax = 8
	},
	{
		name = "armEndRotation", -- Overall orientation of the galaxy should account for some notion of clockwise/anticlockwise
		steps = 3,
		rangeMin = 4,
		rangeMax = 9
	}
}

local sqrt = math.sqrt
local sin = math.sin
local cos = math.cos
local min = math.min
local max = math.max
local abs = math.abs
local atan2 = math.atan2

local coreProportion = 0.175
local coreFullProportion = 0.25
function info.getDensity(x, y, z, densityExponent, armCount, armEndRotation)
	local length2D = sqrt(x ^ 2 + y ^ 2)
	local length3D = sqrt(x ^ 2 + y ^ 2 + z ^ 2)
	local swirlAngle = armEndRotation * length2D
	local c, s = cos(swirlAngle), sin(swirlAngle)
	local swirledX = x * c - y * s
	local swirledY = x * s + y * c

	local galaxyCoreFactor = max(0, min(1,
		(swirlAngle - coreFullProportion) / (coreProportion - coreFullProportion)
	))

	local armVerticalTaperEnd = 1 - 0.9 * min(1, length2D)
	local armVerticalTaperStart = armVerticalTaperEnd * 0.8
	local armVerticalTaper = max(0, min(1,
		(abs(z) - armVerticalTaperEnd) / (armVerticalTaperStart - armVerticalTaperEnd)
	))

	local armFactor = armVerticalTaper * (
		sin(atan2(swirledY, swirledX) * armCount) * 0.5 + 0.5
	) ^ (3.3 * length2D)
	local baseDensity = armFactor * (1 - galaxyCoreFactor) + 1 * galaxyCoreFactor

	return max(0, baseDensity * (1 - length3D)) ^ densityExponent
end

return info
