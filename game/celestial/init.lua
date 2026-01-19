local bm = require("bigmaths")
local mapm = bm.mapm
local mathsies = require("lib.mathsies")
local util = require("util")
local consts = require("consts")

local game = {}

function game:initCelestial()
	-- Consts for here
	-- Galaxy group
	local galaxyCountMin, galaxyCountMax = 1, 125
	local galaxyGroupRadiusMin, galaxyGroupRadiusMax = 9e23, 5e24
	local galaxyRadiusMin, galaxyRadiusMax = 8e19, 2e21
	local galaxyMinSeparation = 3e22 -- Must be more than combined galaxy radii
	-- Individual galaxy
	local galaxyDistancePowerMin, galaxyDistancePowerMax = 0.4, 0.7
	local galaxyHaloProportionMin, galaxyHaloProportionMax = 0.05, 0.2
	local galaxySquashFactorMin, galaxySquashFactorMax = 0.1, 0.3

	-- Basic init
	self.celestialTime = mapm.number(0) -- Will be used for celestial simulation, so it's arbitrary precision
	self:initCelestialRNG()

	-- Generate galaxies
	self.galaxies = {}
	self:seedCelestialRNGWithObject(consts.idObjectTypes.universe)
	local groupRadius = self:celestialRandomRange(galaxyGroupRadiusMin, galaxyGroupRadiusMax)
	for _=1, self:celestialRandomRangeInt(galaxyCountMin, galaxyCountMax) do
		local newGalaxyPosition = self:celestialRandomInSphereVolume(groupRadius)
		local newGalaxyRadius = self:celestialRandomRange(galaxyRadiusMin, galaxyRadiusMax)

		local tooClose = false
		for _, galaxy in ipairs(self.galaxies) do
			local distance = mathsies.vec3.distance(newGalaxyPosition, galaxy.position)
			if distance < galaxyMinSeparation then
				tooClose = true
				break
			end
		end
		if tooClose then
			-- Don't bother retrying
			goto continue
		end

		local new = {}
		new.position = newGalaxyPosition
		new.radius = newGalaxyRadius
		new.distancePower = self:celestialRandomRange(galaxyDistancePowerMin, galaxyDistancePowerMax)
		new.haloProportion = self:celestialRandomRange(galaxyHaloProportionMin, galaxyHaloProportionMax)
		new.squash = self:celestialRandomRange(galaxySquashFactorMin, galaxySquashFactorMax)
		new.squashDirection = self:celestialRandomOnSphereSurface(1)
		table.insert(self.galaxies, new)

	    ::continue::
	end
end

return game
