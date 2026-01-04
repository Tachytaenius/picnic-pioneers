local game = {}

function game:update(dt)
	self:updateShip(dt)
	self:updateCelestial(dt)
end

return game
