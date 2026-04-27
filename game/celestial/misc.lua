local consts = require("consts")

local game = {}

function game:getSphereResolvableDistance(radius)
	return radius / math.sqrt(1 - math.cos(consts.pointAngularRadius) ^ 2)
end

return game
