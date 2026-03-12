local game = {}

function game:draw()
	-- self:drawShip()
	-- love.graphics.draw(self.screenCanvasses.shipOutputCanvas)

	self:drawCelestial()
	love.graphics.draw(self.screenCanvasses.celestialOutputCanvas)
end

return game
