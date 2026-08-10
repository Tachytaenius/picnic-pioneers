local rngManager = require("lib.rng")
local dmath = require("lib.dmath")

local mathsies = require("lib.mathsies")
local consts = require("consts")

local game = {}

-- We don't want seeds for anything to collide across the universe
-- We essentially assign a unique 128-bit id to every object in the game and use it as a seed when generating the object
-- The id is constructed from ids in a hierarchy. Galaxy chunk id, galaxy id within galaxy chunk, star chunk id within galaxy, etc

-- object type bits: 4
-- generation stage bits: 4
-- galaxy chunk id bits: 36
-- galaxy id bits: 12
-- star chunk id bits: 36
-- star id bits: 12
-- celestial body bits: 16
-- Some bits remain unused
-- The chunk ids being 36 bits is referenced in initPointLayers
function game:getGlobalCelestialObjectIdNumbers(objectType, stage, galaxyChunkId, galaxyId, starChunkId, starId, systemBodyId)
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
		-- 8 bits free
		stage * 2 ^ 20 +
		objectType * 2 ^ 16 +
		systemBodyId

	return a, b, c, d
end
-- Designed not to clash with any celestial objects
-- function game:getShapeIntegralNoiseSeed(averagingIteration, typeId, subTypeId)
function game:getShapeIntegralNoiseSeed(averagingIteration) -- No need to even specify type or subtype
	local a = 0 -- typeId?
	local b = 0 -- subTypeId?
	local c = averagingIteration
	local d = consts.idObjectTypes.special * 2 ^ 16
	return a, b, c, d
end

function game:initCelestialRNG()
	-- Oh wait, there's nothing we need to put here...?
	-- If that rngManager module that loads the rng shared library ends up being able to return multiple instances, I guess that would go here.

	-- Debug...
	-- self.isCelestialRNGSeeded = debug
end

function game:seedCelestialRNG(a, b, c, d)
	rngManager.seedRNGLua(a, b, c, d)

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

	return rngManager.rng.nextDouble()
end

function game:celestialRandomRange(lower, upper)
	return lower + (upper - lower) * self:celestialRandom()
end

function game:celestialRandomInt(n) -- [0, n)
	return math.floor(self:celestialRandom() * n)
end

function game:celestialRandomRangeInt(lower, upper) -- [lower, upper)
	return lower + self:celestialRandomInt(upper - lower)
end

function game:celestialRandomOnSphereSurface(radius)
	local phi = self:celestialRandom() * consts.tau
	local cosTheta = self:celestialRandom() * 2 - 1
	local theta = dmath.acos(cosTheta)

	return radius * mathsies.vec3.fromAngles(theta, phi)
end

function game:celestialRandomInSphereVolume(radius)
	local phi = self:celestialRandom() * consts.tau
	local cosTheta = self:celestialRandom() * 2 - 1
	local theta = dmath.acos(cosTheta)

	local u = self:celestialRandom()
	local r = radius * u ^ (1 / 3)

	return r * mathsies.vec3.fromAngles(theta, phi)
end

function game:celestialRandomChoice(choices)
	local random = self:celestialRandom()
	local weightSum = 0
	for _, choice in ipairs(choices) do
		weightSum = weightSum + choice.weight
	end
	local x = random * weightSum
	for _, choice in ipairs(choices) do
		if x < choice.weight then
			-- return choice.value
			return choice
		end
		x = x - choice.weight
	end
	return nil
end

function game:celestialRandomOrientation()
	-- Angles
	local phi = self:celestialRandom() * consts.tau
	local cosTheta = self:celestialRandom() * 2 - 1
	local theta = dmath.acos(cosTheta)
	-- Get a random roll angle with the probability density function 2 / pi * sin(x / 2) ^ 2 where x is in [0, pi)
	-- Source for above is https://math.stackexchange.com/questions/442418/random-generation-of-rotation-matrices#comment7610329_442423
	-- The integral of that function is (x - sin(x)) / pi, which... can't be inverted analytically, it seems
	-- So we're going to use a numerical method.
	local function newtonRaphson(f, fDeriv, input, initOutputGuess, iters)
		local output = initOutputGuess
		for _=1, iters do
			output = output - (f(output) - input) / fDeriv(output)
		end
		return output
	end
	local function f(x)
		return (x - dmath.sin(x)) / consts.pi
	end
	local function fDeriv(x)
		return 2 / consts.pi * dmath.sin(x / 2) ^ 2
	end
	local rollRand = self:celestialRandom()
	local roll = rollRand == 0 and 0 or newtonRaphson(f, fDeriv, rollRand, consts.pi * rollRand, 16)
	-- Sphere point (rotation axis)
	local st, sp, ct, cp = dmath.sin(theta), dmath.sin(phi), dmath.cos(theta), dmath.cos(phi)
	local sphereX = st*sp
	local sphereY = ct
	local sphereZ = st*cp
	-- Make quaternion
	local s, c = dmath.sin(roll / 2), dmath.cos(roll / 2)
	local x, y, z, w = sphereX * s, sphereY * s, sphereZ * s, c
	local len = math.sqrt(x^2 + y^2 + z^2 + w^2)
	x = x / len
	y = y / len
	z = z / len
	w = w / len
	return x, y, z, w
end

-- Old (not working) code for testing rotation uniformity
-- local samplepositions = {
-- 	{c=0,v=consts.rightVector},
-- 	{c=0,v=consts.upVector},
-- 	{c=0,v=consts.forwardVector}
-- }
-- local count = 100000
-- for _=1, count do
-- 	local rot = mathsies.quat(randomOrientation())
-- 	local vec = mathsies.vec3.rotate(consts.forwardVector, rot)
-- 	local mind, minv = math.huge, nil
-- 	for _, v in ipairs(samplepositions) do
-- 		local d = mathsies.vec3.distance(vec, v.v)
-- 		if d < mind then
-- 			mind = d
-- 			minv = v
-- 		end
-- 	end
-- 	if minv then
-- 		minv.c=minv.c+1
-- 	end
-- end
-- for _, v in ipairs(samplepositions) do
-- 	print(v.c, v.v)
-- end

return game
