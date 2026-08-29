local dmath = require("lib.dmath")

local info = {}

info.zScaleRatioMin = 0.08
info.zScaleRatioMax = 0.2
local average = (info.zScaleRatioMax + info.zScaleRatioMin) / 2
local noiseDimension = 25

info.valueNoiseInfo = {
	{
		countX = noiseDimension,
		countY = noiseDimension,
		countZ = math.ceil(average * noiseDimension)
	},
	{
		countX = noiseDimension,
		countY = noiseDimension,
		countZ = math.ceil(average * noiseDimension)
	},
	{
		countX = noiseDimension,
		countY = noiseDimension,
		countZ = math.ceil(average * noiseDimension)
	}
}

info.parameters = {
	{
		name = "densityExponent",
		samples = 2,
		rangeMin = 1.5,
		rangeMax = 4
	},
	{
		name = "armCount",
		discrete = true,
		steps = 6,
		rangeMin = 2,
		rangeMax = 7
	},
	{
		name = "armEndRotation", -- Overall orientation of the galaxy should account for some notion of clockwise/anticlockwise
		samples = 4,
		rangeMin = 2.5,
		rangeMax = 7
	}
}

local coreProportion = 0.1
local coreFullProportion = 0.35
local armVerticalTaperPower = 1.5
local noiseOffsetSize = 0.03
local averageZRatio = average
info.constants = { -- For GPU mostly
	coreProportion = coreProportion,
	coreFullProportion = coreFullProportion,
	armVerticalTaperPower = armVerticalTaperPower,
	noiseOffsetSize = noiseOffsetSize,
	averageZRatio = averageZRatio
}

local sqrt = math.sqrt
local min = math.min
local max = math.max
local abs = math.abs

-- These need to be deterministic
local sin = dmath.sin
local cos = dmath.cos
local atan2 = dmath.atan2

-- TODO: Move magic numbers to shape constants

function info.getDensity(x, y, z, densityExponent, armCount, armEndRotation)
	local originalLength3D = sqrt(x ^ 2 + y ^ 2 + z ^ 2)
	if originalLength3D > 1 then
		return 0
	end
	local xOffset = (valueNoise(1, x, y, z) * 2 - 1) * noiseOffsetSize
	local yOffset = (valueNoise(2, x, y, z) * 2 - 1) * noiseOffsetSize
	local zOffset =
		(valueNoise(3, x, y, z) * 2 - 1) * noiseOffsetSize /
		averageZRatio -- It *is* divide, not multiply, right? (Or do we just not do anything?)
	local x = x + xOffset * (1 - originalLength3D) -- Stop the offset noise towards the edges to avoid excessive variation in base amount
	local y = y + yOffset * (1 - originalLength3D)
	local z = z + zOffset * (1 - originalLength3D)

	local length2D = sqrt(x ^ 2 + y ^ 2)
	-- local length3D = sqrt(x ^ 2 + y ^ 2 + z ^ 2)
	local length3DZScaled = sqrt(x ^ 2 + y ^ 2 + (z / 3) ^ 2) -- For core proportion
	local swirlAngle = armEndRotation * length2D
	local c, s = cos(swirlAngle), sin(swirlAngle)
	local swirledX = x * c - y * s
	local swirledY = x * s + y * c

	local galaxyCoreFactor = max(0, min(1,
		(length3DZScaled - coreFullProportion) / (coreProportion - coreFullProportion)
	))

	local armVerticalTaperEnd = 1 - 0.9 * min(1, length2D)
	local armVerticalTaperStart = armVerticalTaperEnd * 0.05
	local armVerticalTaper = max(0, min(1,
		(abs(z) - armVerticalTaperEnd) / (armVerticalTaperStart - armVerticalTaperEnd)
	)) ^ armVerticalTaperPower

	local armFactor = armVerticalTaper * (
		sin(atan2(swirledY, swirledX) * armCount) * 0.5 + 0.5
	) ^ (3.3 * length2D)
	local baseDensity = armFactor * (1 - galaxyCoreFactor) + 1 * galaxyCoreFactor

	return max(0, baseDensity * (1 - originalLength3D)) ^ densityExponent
end

return info
