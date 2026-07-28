local bm = require("bigmaths")
local consts = require("consts")
local game = require("game")

---@type Gamestate
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

	-- TEMP
	local rate = 5
	if love.keyboard.isDown("-") then
		consts.celestialLuminanceMultiplier = consts.celestialLuminanceMultiplier * math.exp(-rate * dt)
	end
	if love.keyboard.isDown("=") then
		consts.celestialLuminanceMultiplier = consts.celestialLuminanceMultiplier * math.exp(rate * dt)
	end
end

function love.draw()
	state:draw()
	love.graphics.print( -- TEMP
		"fps: " .. love.timer.getFPS() .. "\n" ..
		"x: " .. tostring(state.ship.position.x) .. "\n" ..
		"y: " .. tostring(state.ship.position.y) .. "\n" ..
		"z: " .. tostring(state.ship.position.z) .. "\n" ..
		"factor: " .. state:getGravityWellSlowdownFactor() .. "\n" ..
		"base max speed: " .. state:getMaxMovementSpeed() .. "\n" ..
		-- "max \"luminance\" order: " .. math.floor(math.log10(maxLuminance)) .. "\n" ..
		-- "max \"luminance\": " .. maxLuminance .. "\n" ..
		"\"luminance\" multiplier order: " .. math.floor(math.log10(consts.celestialLuminanceMultiplier)) .. "\n" ..
		"\"luminance\" multiplier: " .. consts.celestialLuminanceMultiplier
	)
end

function love.resize(w, h)
	state:resizeCanvas(w, h)
end
