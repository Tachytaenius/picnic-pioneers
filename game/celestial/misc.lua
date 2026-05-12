local consts = require("consts")

local game = {}

function game:getSphereResolvableDistance(radius)
	return radius / math.sqrt(1 - math.cos(consts.pointAngularRadius) ^ 2)
end

-- object type bits: 4
-- galaxy chunk id bits: 36
-- galaxy id bits: 12
-- star chunk id bits: 36
-- star id bits: 12
-- celestial body bits: 16
-- Some bits remain unused
function game:getGlobalCelestialObjectIdNumbers(objectType, galaxyChunkId, galaxyId, starChunkId, starId, systemBodyId)
	galaxyChunkId = galaxyChunkId or 0
	galaxyId = galaxyId or 0
	starChunkId = starChunkId or 0
	starId = starId or 0
	systemBodyId = systemBodyId or 0

	local a = galaxyChunkId % 2 ^ 32
	local b = starChunkId % 2 ^ 32
	local c =
		math.floor(galaxyChunkId / 2 ^ 32) * 2 ^ 28 +
		math.floor(starChunkId / 2 ^ 32) * 2 ^ 24 +
		galaxyId * 2 ^ 12 +
		starId
	local d =
		-- 20 bits free
		objectType * 2 ^ 16 +
		systemBodyId

	return a, b, c, d
end

return game
