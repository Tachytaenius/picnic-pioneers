local game = {}

function game:updateCelestial(dt)
	self:handleShipMovement(dt)
	self:handlePointLayers()

	self.celestialTime = self.celestialTime + dt
end

return game
