local consts = require("consts")
local util = require("util")

local game = {}

function game:newState()
	local state = {}

	setmetatable(state, {
		__index = self -- self is the full game table (rather than the file-local one here) if this is called as game:newState(), which it should be
	})

	return state
end

function game:initState(initParams)
	-- Common graphics init
	self.screenCanvasses = {} -- Canvasses for which the size is supposed to match the game output size. There are also scaled canvasses like those in point layers for their volumetrics or the point attenuation texture
	self.screenWidth, self.screenHeight = love.graphics.getDimensions()
	self.dummyTexture = love.graphics.newImage(love.image.newImageData(1, 1))

	self:initShip(initParams)
	self:initCelestial(initParams)
	self:resizeGameScreen(self.screenWidth, self.screenHeight, true)
end

---@param width number
---@param height number
---@param forceRecreate boolean
--- resizeGameScreen sets game.screenWidth and game.screenHeight.
--- It also recreates each canvas in screenCanvasses and the canvasses for each PointLayer with the updated dimensions, if necessary.
function game:resizeGameScreen(width, height, forceRecreate)
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
	self.screenCanvasses.outputCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba16f",
		debugname = "Output Canvas",
		computewrite = true
	})
	self.screenCanvasses.shipCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba8",
		debugname = "Ship Canvas"
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
			format = "rg32f", -- R for radiance and A for opacity (1 - transmittance). 32 bits to maintain precision when adding up. When drawing the value of the point total transmittance canvas, it was shown to become imprecise (banding and other artifacts) after a while with 16 bits.
			computewrite = true
		})
		pointLayer.volumetricAddCountCanvas = love.graphics.newCanvas(self.volumetricCanvasWidth, self.volumetricCanvasHeight, {
			debugname = pointLayer.debugName .. " Volumetric Addition Count Canvas",
			format = "r8ui",
			computewrite = true
		})
	end
end

return game
