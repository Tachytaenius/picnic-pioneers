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

	love.graphics.setShader(self.spectralToRGBShader)
	self.spectralToRGBShader:send("spectralToXYZ", self.spectralToXYZMatrix)
	love.graphics.draw(self.screenCanvasses.outputCanvas)
	love.graphics.setShader()
end

return game
