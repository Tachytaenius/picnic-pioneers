local util = require("util")
util.load()

local game = require("game")

local consts = require("consts")

local state

function love.load()
	love.graphics.setDefaultFilter("nearest", "nearest")
	state = game:newState()
	state:initState()
	state:initGraphics()
end

function love.update(dt)
	local dtLimited = math.min(dt, consts.maxDeltaTime)
	state:update(dtLimited)
end

function love.draw()
	state:draw()
	love.graphics.print(love.timer.getFPS()) -- TEMP
end
