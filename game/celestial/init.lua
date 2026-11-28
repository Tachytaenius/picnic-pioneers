local bm = require("bigmaths")
local mapm = bm.mapm
local mathsies = require("lib.mathsies")

local consts = require("consts")
local util = require("util")

---@class ScreenCanvasses
---@field public lightCanvas love.Canvas
---@field public transmittanceCanvas love.Canvas

---@class Gamestate
---@field public screenCanvasses ScreenCanvasses
---@field public pointLayers table<string|number, PointLayer>
---@field public state fun(self: Gamestate, dt: number)
---@field public drawCelestial fun(self: Gamestate)
---@field public getGravityWellSlowdownFactor fun(self: Gamestate): number
---@field public getMaxMovementSpeed fun(self: Gamestate): number
---@field public handleShipMovement fun(self: Gamestate, dt: number)
---@field public handlePointLayers fun(self: Gamestate)
---@field public initPointLayers fun(self: Gamestate)
---@field public initCelestialRNG fun(self: Gamestate)
---@field public loadShapeTypes fun(self: Gamestate)
local game = {}

function game:initCelestial(initParams)
	-- Basic init
	self.celestialTime = mapm.number(0) -- Will be used for celestial simulation, so it's arbitrary precision
	self:initCelestialRNG()

	-- Mix of graphics and non-graphics
	self.amountDataStageManagerThread = love.thread.newThread("threadCode/amountDataStageManager.lua")
	self.amountDataStageManagerThread:start(consts.shapeSlowdownIntegralDetail, consts.pointLayerShapeTypeAmountIntegralMaxThreads)
	coroutine.yield()
	self:loadShapeTypes()
	coroutine.yield()
	self:initPointLayers()
	coroutine.yield()
	-- self.starSystemLookupInfoSet = self:makeStarSystemLookupInfoSet()

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

	self.starShader = love.graphics.newComputeShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/structs.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/bodyBasics.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/bodies/star.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/body.glsl")
	)

	local clearPointAttenuationTexture = love.image.newImageData(1, 1, "rgba16f")
	clearPointAttenuationTexture:setPixel(0, 0, 1, 1, 1, 1)
	self.clearPointAttenuationTexture = love.graphics.newVolumeImage({clearPointAttenuationTexture}, {
		linear = true -- Shouldn't make any difference for a value of 1, though
	})
	self.clearPointAttenuationTexture:setFilter("nearest") -- No need to increase sampling cost (if linear even does for a 1x1x1 texture clamped on all axes)
	self.clearPointAttenuationTexture:setWrap("clamp", "clamp", "clamp")

	self.miscPointAddShader = love.graphics.newComputeShader("shaders/drawing/miscPointAdd.glsl")
	self.rotationReprojectionShader = love.graphics.newComputeShader("shaders/drawing/rotationReprojection.glsl")
	self.reprojectionCopyShader = love.graphics.newComputeShader("shaders/drawing/reprojectionCopy.glsl")
	self.applyTempTransmittanceShader = love.graphics.newComputeShader("shaders/drawing/applyTempTransmittance.glsl")

	-- Place ship
	self.ship = {
		position = initParams.shipPosition or bm.vec3(0, 0, 0), -- Arbitrary precision, used to define position with enough information at each size scale
		orientation = mathsies.quat()
	}

	-- Initial handlePointLayers call to get everything consistent, including pointLayerGravityWellSlowdownFactor for first handleShipMovement call
	self:handlePointLayers()
end

return game
