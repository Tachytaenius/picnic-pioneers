local bm = require("bigmaths")
local mapm = bm.mapm
local mathsies = require("lib.mathsies")

local consts = require("consts")
local util = require("util")

local game = {}

function game:initCelestial()
	-- Basic init
	self.celestialTime = mapm.number(0) -- Will be used for celestial simulation, so it's arbitrary precision
	self:initCelestialRNG()

	-- Mix of graphics and non-graphics
	self.amountDataStageManagerThread = love.thread.newThread("threadCode/amountDataStageManager.lua")
	self.amountDataStageManagerThread:start(consts.shapeSlowdownIntegralDetail, consts.pointLayerShapeTypeAmountIntegralMaxThreads)
	self:loadShapeTypes()
	self:initPointLayers()

	-- Graphics init

	self.pointIndirectDrawArgsBuffer = love.graphics.newBuffer(consts.indirectDrawBufferFormat, 1, {
		shaderstorage = true,
		indirectarguments = true,
		debugname = "Point Indirect Draw Args"
	})
	self.pointDiskMesh = util.generatePointDiskMesh(consts.diskMeshVertices)
	self.pointDrawablesShader = love.graphics.newShader("shaders/drawing/pointDrawables.glsl", {defines = {INSTANCED = true}})
	self.individualPointShader = love.graphics.newShader("shaders/drawing/pointDrawables.glsl")

	self.brightnessMultiplyShader = love.graphics.newShader("shaders/drawing/brightnessMultiply.glsl")

	self.starShader = love.graphics.newShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/skyDirection.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/star.glsl")
	)

	self.stackVolumetricsShader = love.graphics.newShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/random.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/stackVolumetrics.glsl"),
		{
			debugname = "Volumetric Draw Shader"
		}
	)

	self.stackedVolumetricsCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
		format = "rgba32f",
		debugname = "Stacked Volumetrics Canvas",
	})

	self.denoiseVolumetricsShader = love.graphics.newShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/denoise.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/denoiseVolumetrics.glsl")
	)

	local width, height = self.screenWidth, self.screenHeight
	self.screenCanvasses.celestialLuminanceCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba32f",
		debugname = "Celestial Luminance Canvas"
	})
	self.screenCanvasses.celestialOutputCanvas = love.graphics.newCanvas(width, height, {
		debugname = "Celestial Output Canvas"
	})

	-- Place ship
	self.ship = {
		position = bm.vec3(0, 0, 0), -- Arbitrary precision, used to define position with enough information at each size scale
		orientation = mathsies.quat(),
		verticalFOV = math.rad(80)
	}
	self.ship.position = self.ship.position - bm.vec3(0, 0, 1.75 * consts.galaxyGroupRadii.z) -- TEMP

	-- Initial handlePointLayers call to get everything consistent, including pointLayerGravityWellSlowdownFactor for first handleShipMovement call
	self:handlePointLayers()
end

return game
