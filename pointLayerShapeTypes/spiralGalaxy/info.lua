local info = {}

info.parameters = {
	{
		name = "densityExponent",
		steps = 3,
		rangeMin = 1.5,
		rangeMax = 5
	},
	{
		name = "armCount",
		steps = 6,
		rangeMin = 2,
		rangeMax = 7
	},
	{
		name = "armEndRotation", -- Overall orientation of the galaxy should account for some notion of clockwise/anticlockwise
		steps = 4,
		rangeMin = 2,
		rangeMax = 8
	}
}

local coreProportion = 0.175
local coreFullProportion = 0.25
function info.getDensity(x, y, z, densityExponent, armCount, armEndRotation)
	local length2D = math.sqrt(x ^ 2 + y ^ 2)
	local length3D = math.sqrt(x ^ 2 + y ^ 2 + z ^ 2)
	local swirlAngle = armEndRotation * length2D
	local c, s = math.cos(swirlAngle), math.sin(swirlAngle)
	local swirledX = x * c - y * s
	local swirledY = x * s + y * c

	local galaxyCoreFactor = math.max(0, math.min(1,
		(swirlAngle - coreFullProportion) / (coreProportion - coreFullProportion)
	))

	local armVerticalTaperEnd = 1 - 0.9 * math.min(1, length2D)
	local armVerticalTaperStart = armVerticalTaperEnd * 0.8
	local armVerticalTaper = math.max(0, math.min(1,
		(math.abs(z) - armVerticalTaperEnd) / (armVerticalTaperStart - armVerticalTaperEnd)
	))

	local armFactor = armVerticalTaper * (
		math.sin(math.atan2(swirledY, swirledX) * armCount) * 0.5 + 0.5
	) ^ (3.3 * length2D)
	local baseDensity = armFactor * (1 - galaxyCoreFactor) + 1 * galaxyCoreFactor

	return math.max(0, baseDensity * (1 - length3D)) ^ densityExponent
end

return info
