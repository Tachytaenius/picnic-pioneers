local game = {}

function game:initCelestialGraphics()
	local width, height = love.graphics.getDimensions()
	self.screenCanvasses.celestialOutputCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba32f"
	})
end

function game:drawCelestial()
	local outputCanvas = self.screenCanvasses.celestialOutputCanvas
	love.graphics.setCanvas(outputCanvas)
	love.graphics.clear(0, 0, 0, 1)

	love.graphics.setCanvas()
end

return game
