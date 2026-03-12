local util = require("util")
local consts = require("consts")

local game = {}

function game:drawCelestial()
	local outputCanvas = self.screenCanvasses.celestialOutputCanvas
	love.graphics.setCanvas(outputCanvas)
	love.graphics.clear(0, 0, 0, 1)

	self:drawPointLayers()

	love.graphics.setCanvas()
end

return game
