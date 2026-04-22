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
		[0] = "galaxyChunk",
		"galaxy",
		"starChunk",
		"starSystem",
		"celestialBody"
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

	consts.gravitationalConstant = 6.674e-11

	consts.starLayerChunkSize = 4e17
	consts.maxStellarDensity = 4.72e-51 -- Stellar density near the sun
	consts.galaxyLayerChunkSize = 4e23
	-- consts.maxGalacticDensity = 3e-69 -- Universe mass density divided by milky way mass
	consts.maxGalacticDensity = 1e-70
	consts.galaxyGroupPosition = bm.vec3(0, 0, 0)
	consts.galaxyGroupRadii = mathsies.vec3(1e27) -- Radius does not need to be precise like position does
	consts.galaxyGroupShapeTypeName = "galaxyCluster"

	consts.slowdownDistanceExponent = -3

	consts.diskMeshVertices = 5
	consts.pointAngularRadius = 0.005
	consts.pointFadeStart = 0.9

	consts.celestialLuminanceMultiplier = 1 / 5e-4
	consts.pointPreparationThreadgroupSize = 256
	consts.pointLayerShapeTypeAmountIntegralSteps = 32
end

return consts
