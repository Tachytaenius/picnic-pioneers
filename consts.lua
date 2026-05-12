local consts = {}

function consts.load()
	local util = require("util")
	local bm = require("bigmaths")
	local mathsies = require("lib.mathsies")

	consts.identity = "picnic-pioneers"
	consts.loveVersion = "12.0"
	consts.windowTitle = "Picnic Pioneers"

	consts.tau = math.pi * 2

	consts.maxDeltaTime = 0.1

	consts.rightVector = mathsies.vec3(1, 0, 0)
	consts.upVector = mathsies.vec3(0, 1, 0)
	consts.forwardVector = mathsies.vec3(0, 0, 1)

	consts.mapmDigits = 4

	consts.bytesPerGPUVar = 4

	consts.pointMinDistanceInChunk = 0.03125 -- Use of this during generation is TODO!!!!

	consts.idObjectTypes = util.makeBidirectional({
		[0] = "universe",
		"galaxyChunk",
		"galaxy",
		"starChunk",
		"starSystem",
		"systemBody"
	})

	-- TEMP/TODO
	consts.controls = {
		moveRight = "d",
		moveLeft = "a",
		moveUp = "e",
		moveDown = "q",
		moveForwards = "w",
		moveBackwards = "s",

		pitchDown = "k",
		pitchUp = "i",
		yawRight = "l",
		yawLeft = "j",
		rollAnticlockwise = "u",
		rollClockwise = "o"
	}

	-- Buffer formats

	consts.intBufferFormat = {
		{name = "value", format = "int32"}
	}

	consts.uintBufferFormat = {
		{name = "value", format = "uint32"}
	}

	consts.floatBufferFormat = {
		{name = "value", format = "float"}
	}

	consts.indirectDrawBufferFormat = {
		{name = "vertexCount", format = "uint32"},
		{name = "instanceCount", format = "uint32"},
		{name = "baseVertex", format = "uint32"},
		{name = "baseInstance", format = "uint32"}
	}

	consts.pointDrawableBufferFormat = {
		{name = "direction", format = "floatvec3"},
		{name = "luminance", format = "floatvec3"}
	}

	-- Vertex formats

	consts.pointDiskVertexFormat = {
		{name = "VertexPosition", location = 0, format = "floatvec2"},
		{name = "VertexFade", location = 1, format = "float"}
	}

	-- Simulation/graphics parameters

	consts.gravitationalConstant = 6.6743e-11
	consts.planckConstant = 6.6261e-34
	consts.speedOfLight = 299792458
	consts.stefanBoltzmannConstant = 5.67037442e-8

	consts.starLayerChunkSize = 4e17
	consts.maxStellarDensity = 4.72e-51 -- Stellar density near the sun
	consts.galaxyLayerChunkSize = 1e25
	consts.maxGalacticDensity = 1e-73
	consts.galaxyGroupPosition = bm.vec3(0, 0, 0)
	consts.galaxyGroupRadii = mathsies.vec3(5e26, 5e26, 5e26) -- Radius does not need to be precise like position does
	consts.galaxyGroupShapeTypeName = "universeFilaments"

	consts.slowdownDistanceExponent = -6
	consts.gravityFactorExponent = 1/6
	consts.gravityMovementRate = 4e3

	consts.diskMeshVertices = 5
	consts.pointAngularRadius = 0.006
	consts.pointFadeStart = 0.9

	consts.celestialLuminanceMultiplier = 1 / 2e-11

	consts.pointPreparationThreadgroupSize = 256
	consts.pointLayerShapeTypeAmountIntegralSteps = 64 -- TODO: Use threads for this and bump number up
	consts.volumetricMaxRaySteps = 64

	-- TEMP
	consts.starDensity = 1408
	consts.starEffectiveTemperature = 5772
end

return consts
