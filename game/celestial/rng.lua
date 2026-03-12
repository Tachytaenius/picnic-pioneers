-- TODO: Find suitable RNG

local mathsies = require("lib.mathsies")
local consts = require("consts")

local game = {}

-- We don't want seeds for anything to collide across the universe
-- We essentially assign a unique 128-bit id to every object in the game and use it as a seed when generating the object
-- The id is constructed from ids in a hierarchy. Galaxy chunk id, galaxy id within galaxy chunk, star chunk id within galaxy, etc

-- object type bits: 4
-- galaxy chunk id bits: 36
-- galaxy id bits: 12
-- star chunk id bits: 36
-- star id bits: 12
-- celestial body bits: 16

-- Some bits remain unused

local function getObjectCelestialIdNumbers(objectType, galaxyChunkId, galaxyId, starChunkId, starId, celestialBodyId)
	galaxyChunkId = galaxyChunkId or 0
	galaxyId = galaxyId or 0
	starChunkId = starChunkId or 0
	starId = starId or 0
	celestialBodyId = celestialBodyId or 0

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
		celestialBodyId

	return a, b, c, d
end

function game:initCelestialRNG()
	-- TODO

	-- Debug...
	-- self.isCelestialRNGSeeded = false
end

function game:seedCelestialRNGWithObject(...)
	local a, b, c, d = getObjectCelestialIdNumbers(...)

	-- TODO

	-- Debug...
	-- self.isCelestialRNGSeeded = true
	-- self.celestialRNGSeedA = a
	-- self.celestialRNGSeedB = b
	-- self.celestialRNGSeedC = c
	-- self.celestialRNGSeedD = d
	-- self.celestialRNGCallNumber = 0
end

function game:celestialRandom()
	-- Debug...
	-- assert(self.isCelestialRNGSeeded, "Celestial RNG cannot be called without initialising seed")
	-- self.celestialRNGCallNumber = self.celestialRNGCallNumber + 1

	-- TODO
	return love.math.random() -- TEMP
end

function game:celestialRandomRange(lower, upper)
	return lower + (upper - lower) * self:celestialRandom()
end

function game:celestialRandomInt(n) -- [0, n)
	return math.floor(self:celestialRandom() * n)
end

function game:celestialRandomRangeInt(lower, upper) -- [0, n)
	return lower + self:celestialRandomInt(upper - lower)
end

function game:celestialRandomOnSphereSurface(radius)
	local phi = self:celestialRandom() * consts.tau
	local cosTheta = self:celestialRandom() * 2 - 1
	local theta = math.acos(cosTheta)

	return radius * mathsies.vec3.fromAngles(theta, phi)
end

function game:celestialRandomInSphereVolume(radius)
	local phi = self:celestialRandom() * consts.tau
	local cosTheta = self:celestialRandom() * 2 - 1
	local theta = math.acos(cosTheta)

	local u = self:celestialRandom()
	local r = radius * u ^ (1 / 3)

	return r * mathsies.vec3.fromAngles(theta, phi)
end

return game
