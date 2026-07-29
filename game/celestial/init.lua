local bm = require("bigmaths")
local mapm = bm.mapm
local mathsies = require("lib.mathsies")

local consts = require("consts")
local util = require("util")

---@class ScreenCanvasses
---@field public celestialOutputCanvas love.Canvas
---@field public pointTotalTransmittanceCanvas love.Canvas

---@class Gamestate
---@field public screenCanvasses ScreenCanvasses
---@field public pointLayers table<string|number, PointLayer>
local game = {}

---@param width number
---@param height number
--- resizeCelestialScreen sets game.screenWidth and game.screenHeight.
--- It also recreates each canvas in screenCanvasses and the canvasses for each PointLayer with the updated dimensions, if necessary.
function game:resizeCelestialScreen(width, height, forceRecreate)
	local changed = width ~= self.screenWidth or height ~= self.screenHeight
	if not changed and not forceRecreate then
		return
	end

	for _, canvas in ipairs(self.screenCanvasses) do
		canvas:release()
	end

	self.screenWidth = width
	self.screenHeight = height
	self.volumetricCanvasWidth = math.ceil(consts.volumetricCanvasScale * self.screenWidth)
	self.volumetricCanvasHeight = math.ceil(consts.volumetricCanvasScale * self.screenHeight)

	self.screenCanvasses.pointTotalTransmittanceCanvas = love.graphics.newCanvas(width, height, { -- Gets multiplied down as the camera progresses out from the smallest layer to the largest. Distinct from the point attenuation texture because that is recalculated per-layer
		format = "r16f",
		debugname = "Point Total Transmittance Canvas",
		computewrite = true
	})
	self.screenCanvasses.celestialOutputCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba16f",
		debugname = "Celestial Output Canvas",
		computewrite = true
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

	for _, pointLayer in ipairs(self.pointLayers) do
		if pointLayer.volumetricCanvas then
			pointLayer.volumetricCanvas:release()
		end
		if pointLayer.volumetricAddCountCanvas then
			pointLayer.volumetricAddCountCanvas:release()
		end

		-- pointLayer.volumetricCanvasCameraInfo = nil -- Not needed since the new canvas is ready for new rays to add in
		pointLayer.volumetricCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
			debugname = pointLayer.debugName .. " Volumetric Canvas",
			format = "rgba32f", -- RGB for luminance and A for opacity (1 - transmittance). 32 bits to maintain precision when adding up. When drawing the value of the point total transmittance canvas, it was shown to become imprecise (banding and other artifacts) after a while with 16 bits.
			computewrite = true
		})
		pointLayer.volumetricAddCountCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
			debugname = pointLayer.debugName .. " Volumetric Addition Count Canvas",
			format = "r8ui",
			computewrite = true
		})
	end
end

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
	self.attenuationAccumulationShader = love.graphics.newShader("shaders/drawing/attenuationAccumulation.glsl")

	self.brightnessMultiplyShader = love.graphics.newShader("shaders/drawing/brightnessMultiply.glsl")

	self.starShader = love.graphics.newComputeShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/bodies/star.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/body.glsl")
	)

	self:resizeCelestialScreen(self.screenWidth, self.screenHeight, true)

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
