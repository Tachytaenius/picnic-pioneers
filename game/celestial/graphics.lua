local util = require("util")
local consts = require("consts")

local game = {}

function game:drawCelestial()
	love.graphics.setCanvas(self.screenCanvasses.celestialLuminanceCanvas)
	love.graphics.clear(0, 0, 0, 1)

	self:drawPointLayers()
	self:drawStarSystem()

	love.graphics.setCanvas(self.screenCanvasses.celestialOutputCanvas)
	self.brightnessMultiplyShader:send("multiplier", consts.celestialLuminanceMultiplier)
	love.graphics.setShader(self.brightnessMultiplyShader)
	love.graphics.draw(self.screenCanvasses.celestialLuminanceCanvas)
	love.graphics.setCanvas()
	love.graphics.setShader()
end

return game
