local bm = require("bigmaths")
local consts = require("consts")
local game = require("game")

local state

function love.load()
	bm.mapm.digits(consts.mapmDigits)
	love.graphics.setDefaultFilter("nearest", "nearest")
	state = game:newState()
	state:initState()
end

function love.update(dt)
	local dtLimited = math.min(dt, consts.maxDeltaTime)
	state:update(dtLimited)
end

function love.draw()
	state:draw()
	love.graphics.print( -- TEMP
		love.timer.getFPS() .. "\n" ..
		"x: " .. tostring(state.ship.position.x) .. "\n" ..
		"y: " .. tostring(state.ship.position.y) .. "\n" ..
		"z: " .. tostring(state.ship.position.z)
	)
end
