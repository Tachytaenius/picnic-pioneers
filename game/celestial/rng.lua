local mathsies = require("lib.mathsies")
local consts = require("consts")

local game = {}

-- We don't want seeds for anything to collide across universes or galaxies or anything
-- We essentially assign a unique 128-bit id to every object in the game and use it as a seed when generating the object
-- The id is constructed from ids in a hierarchy. Universe id, galaxy id within universe, star chunk id within galaxy, etc

-- universe seed bits: 32
-- object type bits: 8
-- galaxy id bits: 16
-- star chunk id bits: 36
-- star id bits: 12
-- celestial body bits: 16

-- Some bits remain unused

local function getObjectCelestialIdNumbers(universeSeed, objectType, galaxyId, starChunkId, starId, celestialBodyId)
	galaxyId = galaxyId or 0
	starChunkId = starChunkId or 0
	starId = starId or 0
	celestialBodyId = celestialBodyId or 0

	-- Arrange to have fewer operations than if we did it in order
	local a = universeSeed
	local b = galaxyId + celestialBodyId * 2 ^ 16
	local c = starChunkId % 2 ^ 32
	local d = math.floor(starChunkId / 2 ^ 32) + starId * 2 ^ 4 + objectType * 2 ^ 16 -- 8 bits free. Time? Interpolate between objects at different times (cyclically)?

	return a, b, c, d
end

function game:initCelestialRNG()
	self.universeSeed = love.math.random(0, 2 ^ 32 - 1) -- For modifying overall RNG results
	-- The RandomGenerators get reseeded based on position, universe seed, etc before calls
	-- Two because each one can only have a 64-bit seed
	self.celestialRNG1 = love.math.newRandomGenerator()
	self.celestialRNG2 = love.math.newRandomGenerator()

	-- Debug...
	-- self.isClestialRNGSeeded = false
end

function game:seedCelestialRNGWithObject(...) -- Doesn't need universe seed to be specified
	local a, b, c, d = getObjectCelestialIdNumbers(self.universeSeed, ...)
	self.celestialRNG1:setSeed(a, b)
	self.celestialRNG2:setSeed(c, d)

	-- Debug...
	-- self.isClestialRNGSeeded = true
	-- self.celestialRNGSeedA = a
	-- self.celestialRNGSeedB = b
	-- self.celestialRNGSeedC = c
	-- self.celestialRNGSeedD = d
	-- self.celestialRNGCallNumber = 0
end

function game:celestialRandom()
	-- Debug...
	-- assert(self.isClestialRNGSeeded, "Celestial RNG cannot be called without initialising seed")
	-- self.celestialRNGCallNumber = self.celestialRNGCallNumber + 1

	return (self.celestialRNG1:random() + self.celestialRNG2:random()) % 1
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
