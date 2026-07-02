local game = {}

function game:update(dt)
	self:updateShip(dt)
	self:updateCelestial(dt)

	self:checkThreadsForErrors()
end

return game
