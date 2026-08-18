---@class bm.vec3
---@field x mapm.number
---@field y mapm.number
---@field z mapm.number

---@class mathsies.vec3
---@field x number
---@field y number
---@field z number

---@class BufferFormat
---@field name string
---@field format string
---@field location number|nil

---@class Consts
---@field identity string
---@field loveVersion string
---@field windowTitle string
---@field windowWidth number
---@field windowHeight number
---@field tau number
---@field maxDeltaTime number
---@field rightVector mathsies.vec3
---@field upVector mathsies.vec3
---@field forwardVector mathsies.vec3
---@field mapmDigits number
---@field bytesPerGPUVar number
---@field pointMinDistanceInChunk number
---@field pointAsyncSetupDistanceMultiplier number
---@field idObjectTypes table<string, number>
---@field objectGenerationStages table<string, number>
---@field noAttenuationShapeTypeName string
---@field controls table<string, string>
---@field intBufferFormat BufferFormat[]
---@field uintBufferFormat BufferFormat[]
---@field floatBufferFormat BufferFormat[]
---@field indirectDrawBufferFormat BufferFormat[]
---@field pointDrawableBufferFormat BufferFormat[]
---@field pointDiskVertexFormat BufferFormat[]
---@field gravitationalConstant number
---@field planckConstant number
---@field speedOfLight number
---@field stefanBoltzmannConstant number
---@field starLayerChunkSize number
---@field maxStellarDensity number
---@field galaxyLayerChunkSize number
---@field maxGalacticDensity number
---@field galaxyGroupPosition bm.vec3
---@field galaxyGroupScale number
---@field galaxyGroupZScaleRatio number
---@field galaxyGroupShapeTypeName string
---@field galaxyGroupAttenuationShapeName string
---@field galaxyGroupAttenuationMultiplier number
---@field slowdownDistanceExponent number
---@field gravityFactorExponent number
---@field gravityMovementRate number
---@field pointAttenuationTextureScale number
---@field pointAttenuationTextureSteps number
---@field diskMeshVertices number
---@field pointAngularRadius number
---@field pointFadeStart number
---@field pointFadeExponent number
---@field celestialLuminanceMultiplier number
---@field pointPreparationThreadgroupSize number
---@field pointLayerShapeTypeAmountIntegralMaxThreads number
---@field shapeIntegralThreadTimeout number
---@field pointLayerShapeTypeAmountIntegralSteps number
---@field pointLayerShapeTypeAmountIntegralAverageRepeatCount number
---@field lodBoxRange number
---@field shapeSlowdownIntegralDetail number
---@field shapeSlowdownIntegralHighestStepCount number
---@field shapeSlowdownIntegralDataStarts number[]
---@field shapeSlowdownIntegralDataCount number
---@field volumetricMaxRaySteps number
---@field volumetricCanvasScale number
---@field volumetricMaxPixelAdditions number
---@field starDensity number
---@field starEffectiveTemperature number
---@field starMassRandomTerm1Weight number
---@field starMassRandomTerm1Exponent number
---@field starMassExponentRangeLow number
---@field starMassExponentRangeHigh number
---@field starMassMultiplier number
---@field averageStarMass number
---@field averageStarLuminousFluxR number
---@field averageStarLuminousFluxG number
---@field averageStarLuminousFluxB number
local consts = {}

function consts.load()
	local util = require("util")
	local bm = require("bigmaths")
	local mathsies = require("lib.mathsies")

	consts.identity = "picnic-pioneers"
	consts.loveVersion = "12.0"

	consts.windowTitle = "Picnic Pioneers"
	consts.defaultWindowWidth = 640
	consts.defaultWindowHeight = 480
	consts.iconPath = "icon.png"
	consts.iconScale = 16

	-- Determinism! Being silly about the precision. Taken from OEIS.
	consts.tau = 6.28318530717958647692528676655900576839433879875021164194988918461563281257241799725606965068423413
	consts.pi = consts.tau / 2

	consts.maxDeltaTime = 0.1
	consts.initMaxTickLength = 0.2

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

	consts.noAttenuationShapeTypeName = "noAttenuation"

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

	consts.entityVertexFormat = {
		{name = "VertexPosition", location = 0, format = "floatvec3"},
		{name = "VertexTexCoord", location = 1, format = "floatvec2"},
		{name = "VertexNormal", location = 2, format = "floatvec3"}
	}
	consts.entityLoadObjZMultiplier = -1 -- Notably not a vertex format :3

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
	consts.galaxyGroupOrientation = mathsies.quat()
	consts.galaxyGroupScale = 5e27 -- Object radii do not need to be precise like positions do
	consts.galaxyGroupZScaleRatio = 1
	consts.galaxyGroupShapeTypeName = "universeFilaments"
	consts.galaxyGroupAttenuationShapeName = consts.noAttenuationShapeTypeName
	consts.galaxyGroupAttenuationMultiplier = 0

	consts.slowdownDistanceExponent = -6
	consts.gravityFactorExponent = 1/6
	consts.gravityMovementRate = 4e3

	consts.pointAttenuationTextureScale = 0.2
	consts.pointAttenuationTextureSteps = 6
	assert(consts.pointAttenuationTextureSteps > 1, "A pointAttenuationTextureSteps count of 1 would mean no point attenuation since the first layer in the point attenuation texture is always 1")

	consts.diskMeshVertices = 5
	consts.pointAngularRadius = 0.006
	-- This fade is the distance to an object when its brightness (in point form) fades out:
	consts.pointFadeStart = 1 / 3
	consts.pointFadeExponent = 1
	-- This fade is across the disk of a point:
	consts.pointDiskFadeExponent = 2.5

	consts.POVFarDistance = 10000
	consts.POVNearDistance = 0.01

	consts.celestialLuminanceMultiplier = 1e14

	-- TODO: Move some of these out as they're not really simulation or graphics parameters in the sense that I meant.
	consts.pointPreparationThreadgroupSize = 512

	consts.pointLayerShapeTypeAmountIntegralMaxThreads = 7
	consts.shapeIntegralThreadTimeout = 1

	consts.pointLayerShapeTypeAmountIntegralSteps = 80
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

	consts.starParamCount = 2
	consts.maxStarsPerSystem = 3
	consts.invalidStarParam = -1
end

return consts
