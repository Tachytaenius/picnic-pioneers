local consts = require("consts")
local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local game = {}

function game:generateStarSystem(layerObject)
	local remainingMass = layerObject.mass

	local bodies = {}

	-- All heavily TODO

	local starMass = remainingMass
	remainingMass = 0
	local starDensity = 1408
	local starVolume = starMass / starDensity
	local star = {
		type = "star",
		mass = starMass,
		radius = (starVolume / (2 / 3 * consts.tau)) ^ (1 / 3),
		luminousFlux = layerObject.luminousFlux,
		position = mathsies.vec3(0, 0, 0) -- TODO: Kepler orbits
	}
	table.insert(bodies, star)

	layerObject.bodies = bodies
end

return game
