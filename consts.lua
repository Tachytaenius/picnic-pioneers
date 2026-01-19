local mathsies = require("lib.mathsies")

local util = require("util")

local consts = {}

consts.identity = "picnic-pioneers"
consts.loveVersion = "12.0"
consts.windowTitle = "Picnic Pioneers"

consts.tau = math.pi * 2

consts.maxDeltaTime = 0.1

consts.rightVector = mathsies.vec3(1, 0, 0)
consts.upVector = mathsies.vec3(0, 1, 0)
consts.forwardVector = mathsies.vec3(0, 0, 1)

consts.mapmDigits = 32

consts.idObjectTypes = util.makeBidirectional({
	[0] = "universe",
	"starChunk",
	"starSystem",
	"celestialBody"
})

return consts
