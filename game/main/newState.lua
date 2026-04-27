local game = {}

function game:newState()
	local state = {}

	setmetatable(state, {
		__index = self -- self is the full game table (rather than the file-local one here) if this is called as game:newState(), which it should be
	})

	return state
end

function game:initState()
	-- Common graphics init
	self.screenCanvasses = {} -- Canvasses for which the size is supposed to match the game output size
	self.dummyTexture = love.graphics.newImage(love.image.newImageData(1, 1))

	self:initShip()
	self:initCelestial()
end

return game
