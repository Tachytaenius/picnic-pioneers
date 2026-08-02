local game = {}

function game:draw()
	love.graphics.setCanvas(self.screenCanvasses.outputCanvas)
	love.graphics.clear(0, 0, 0, 1)
	local POVEntity = self.players[1]
	self:drawPlayerPOV(POVEntity)
	self:drawCelestial(POVEntity)
	love.graphics.setCanvas(self.screenCanvasses.outputCanvas)
	love.graphics.draw(self.screenCanvasses.shipCanvas)
	love.graphics.setCanvas()
	love.graphics.draw(self.screenCanvasses.outputCanvas)
end

return game
