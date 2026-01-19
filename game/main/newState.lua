local game = {}

function game:newState()
	local state = {}

	setmetatable(state, {
		__index = self -- self is the full game table (rather than the file-local one here) if this is called as game:newState(), which it should be
	})

	return state
end

function game:initState()
	self:initShip()
	self:initCelestial()
end

return game
