local consts = {}

function consts.load()
	local util = require("util")
	local bm = require("bigmaths")
	local mathsies = require("lib.mathsies")

	consts.identity = "picnic-pioneers"
	consts.loveVersion = "12.0"

	consts.windowTitle = "Picnic Pioneers"
	consts.windowWidth = 800
	consts.windowHeight = 600

	consts.tau = math.pi * 2

	consts.maxDeltaTime = 0.1

	consts.rightVector = mathsies.vec3(1, 0, 0)
	consts.upVector = mathsies.vec3(0, 1, 0)
	consts.forwardVector = mathsies.vec3(0, 0, 1)

	consts.mapmDigits = 16

	consts.bytesPerGPUVar = 4

	consts.pointMinDistanceInChunk = 0.03125 -- Use of this during generation is TODO!!!!
	consts.pointAsyncSetupDistanceMultiplier = 1.2 -- Generate point info before reaching the point's resolvability distance

	consts.idObjectTypes = util.makeBidirectional({
		[0] = "special", -- E.g. shape type integral noise seed

		"universe",
		"galaxyChunk",
		"galaxy",
		"starChunk",
		"starSystem",
		"systemBody"
	})

	consts.objectGenerationStages = util.makeBidirectional({ -- For multithreading
		[0] = "main",
		"noiseValues"
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
	consts.galaxyGroupRadii = mathsies.vec3(1e27) -- Radius does not need to be precise like position does
	consts.galaxyGroupShapeTypeName = "universeFilaments"

	consts.slowdownDistanceExponent = -6
	consts.gravityFactorExponent = 1/6
	consts.gravityMovementRate = 4e3

	consts.diskMeshVertices = 5
	consts.pointAngularRadius = 0.006
	consts.pointFadeStart = 1 / 3
	consts.pointFadeExponent = 1 -- TODO: Ensure fair tradeoff between point and volumetric

	consts.celestialLuminanceMultiplier = 1e14

	consts.pointPreparationThreadgroupSize = 512

	consts.pointLayerShapeTypeAmountIntegralMaxThreads = 7
	consts.shapeIntegralThreadTimeout = 1
	consts.pointLayerShapeTypeAmountIntegralSteps = 100
	consts.pointLayerShapeTypeAmountIntegralAverageRepeatCount = 8 -- Skips noiseless shape types

	consts.lodBoxRange = 2
	consts.shapeSlowdownIntegralDetail = 7
	-- Derived
	consts.shapeSlowdownIntegralHighestStepCount = 2 ^ consts.shapeSlowdownIntegralDetail
	local currentStart = 0
	consts.shapeSlowdownIntegralDataStarts = {}
	for i = 0, consts.shapeSlowdownIntegralDetail do
		consts.shapeSlowdownIntegralDataStarts[i] = currentStart
		local sideLengthThisDetail = 2 ^ i
		local count = sideLengthThisDetail ^ 3
		currentStart = currentStart + count
	end
	consts.shapeSlowdownIntegralDataCount = currentStart

	consts.volumetricMaxRaySteps = 8
	consts.volumetricCanvasScale = 1
	consts.volumetricMaxPixelAdditions = 240 -- Shouldn't go above 255

	consts.starDensity = 1408 -- TEMP?
	consts.starEffectiveTemperature = 5772

	consts.starMassRandomTerm1Weight = 0.75
	consts.starMassRandomTerm1Exponent = 20
	consts.starMassExponentRangeLow = 28.25
	consts.starMassExponentRangeHigh = 31.5
	consts.starMassMultiplier = 1.5
	-- Derived
	-- TEMP/TODO: Properly, please... this is copy/pasted from pointLayer.lua's starSystemPointLayerInfo:generateChunk
	local count = 10000
	local sumMass = 0
	local sumFluxR = 0
	local sumFluxG = 0
	local sumFluxB = 0
	for i = 1, count do
		local randomValue = (i - 0.5) / count
		local exponentT = consts.starMassRandomTerm1Weight * randomValue ^ consts.starMassRandomTerm1Exponent + (1 - consts.starMassRandomTerm1Weight) * randomValue
		local exponent = consts.starMassExponentRangeLow + exponentT * (consts.starMassExponentRangeHigh - consts.starMassExponentRangeLow)
		local starMass = consts.starMassMultiplier * 10 ^ exponent
		sumMass = sumMass + starMass
		local density = consts.starDensity
		local temperature = consts.starEffectiveTemperature
		local volume = starMass / density
		local radius = (volume / (2 / 3 * consts.tau)) ^ (1 / 3)
		local area = 2 * consts.tau * radius ^ 2
		local luminousExitance = consts.stefanBoltzmannConstant * temperature ^ 4
		local luminousFlux = luminousExitance * area
		sumFluxR = sumFluxR + luminousFlux
		sumFluxG = sumFluxG + luminousFlux
		sumFluxB = sumFluxB + luminousFlux
	end
	consts.averageStarMass = sumMass / count
	consts.averageStarLuminousFluxR = sumFluxR / count
	consts.averageStarLuminousFluxG = sumFluxG / count
	consts.averageStarLuminousFluxB = sumFluxB / count
end

return consts
