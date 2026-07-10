local util = require("util")
local consts = require("consts")

local game = {}

function game:drawCelestial()
	love.graphics.setCanvas(self.screenCanvasses.celestialOutputCanvas)
	love.graphics.clear(0, 0, 0, 1)
	love.graphics.setCanvas()

	self:drawPointLayers()
	self:drawStarSystem()

	love.graphics.setCanvas()
end

return game
