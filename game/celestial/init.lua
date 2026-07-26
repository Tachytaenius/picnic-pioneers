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

	self.drawVolumetricShader = love.graphics.newShader("shaders/drawing/drawVolumetric.glsl")

	self.brightnessMultiplyShader = love.graphics.newShader("shaders/drawing/brightnessMultiply.glsl")

	self.starShader = love.graphics.newShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/skyDirection.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/star.glsl")
	)

	local width, height = self.screenWidth, self.screenHeight
	-- This isn't actually faster, it seems:
	-- self.screenCanvasses.pointCanvas = love.graphics.newCanvas(width, height, {
	-- 	format = "rgba8", -- For faster additive blending
	-- 	debugname = "Point Canvas"
	-- })
	self.screenCanvasses.celestialOutputCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba16f",
		debugname = "Celestial Output Canvas"
	})

	self.pointAttenuationTexture = love.graphics.newCanvas(
		math.ceil(width * consts.pointAttenuationTextureScale),
		math.ceil(height * consts.pointAttenuationTextureScale),
		consts.pointAttenuationTextureSteps,
		{
			type = "volume",
			format = "r16f",
			computewrite = true
		}
	)
	self.pointAttenuationTexture:setFilter("linear")
	self.pointAttenuationTexture:setWrap("clamp", "clamp", "clamp")

	local clearPointAttenuationTexture = love.image.newImageData(1, 1, "r16f")
	clearPointAttenuationTexture:setPixel(0, 0, 1, 0, 0, 1)
	self.clearPointAttenuationTexture = love.graphics.newVolumeImage({clearPointAttenuationTexture}, {
		linear = true -- Shouldn't make any difference for a value of 1, though
	})
	self.clearPointAttenuationTexture:setFilter("nearest") -- No need to increase sampling cost (if linear even does for a 1x1x1 texture clamped on all axes)
	self.clearPointAttenuationTexture:setWrap("clamp", "clamp", "clamp")

	-- Place ship
	self.ship = {
		position = bm.vec3(0, 0, 0), -- Arbitrary precision, used to define position with enough information at each size scale
		orientation = mathsies.quat(),
		verticalFOV = math.rad(80)
	}
	-- self.ship.position = self.ship.position - bm.vec3(0, 0, 1.75 * consts.galaxyGroupRadii.z) -- TEMP

	-- Initial handlePointLayers call to get everything consistent, including pointLayerGravityWellSlowdownFactor for first handleShipMovement call
	self:handlePointLayers()
end

return game
