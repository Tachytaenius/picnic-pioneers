local game = {}

function game:initShipGraphics()
	local width, height = love.graphics.getDimensions()
	self.screenCanvasses.shipOutputCanvas = love.graphics.newCanvas(width, height)
end

function game:drawShip()
	local outputCanvas = self.screenCanvasses.celestialOutputCanvas
	love.graphics.setCanvas(outputCanvas)
	love.graphics.clear(0, 0, 0, 1)

	love.graphics.setCanvas()
end

return game
