local bm = require("bigmaths")
local mapm = bm.mapm

local game = {}

function game:newState()
	local state = {}

	setmetatable(state, {
		__index = self -- self is the full game table (rather than the file-local one here) if this is called as game:newState(), which it should be
	})

	return state
end

function game:initState()
	self.time = mapm.number(0) -- Will be used for celestial simulation, so it's arbitrary precision
	self.seed = love.math.random(0, 2 ^ 32 - 1)
	self.rng = love.math.newRandomGenerator(self.seed)
end

return game
