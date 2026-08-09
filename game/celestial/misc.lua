local dmath = require("dmath")

local consts = require("consts")

local game = {}

function game:getSphereResolvableDistance(radius)
	return radius / math.sqrt(1 - dmath.cos(consts.pointAngularRadius) ^ 2)
end

function game:getSphereRadiusFromResolvableDistance(resolvableDistance)
	return resolvableDistance * math.sqrt(1 - dmath.cos(consts.pointAngularRadius) ^ 2)
end

return game
