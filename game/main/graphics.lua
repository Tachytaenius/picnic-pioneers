local game = {}

function game:initGraphics()
	self.screenCanvasses = {} -- Canvasses for which the size is supposed to match the game output size

	self:initShipGraphics()
	self:initCelestialGraphics()
end

function game:draw()
	self:drawShip()
	love.graphics.draw(self.screenCanvasses.shipOutputCanvas)

	-- self:drawCelestial()
	-- love.graphics.draw(self.screenCanvasses.celestialOutputCanvas)
end

return game
