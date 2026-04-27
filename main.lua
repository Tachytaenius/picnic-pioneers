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
	local maxLuminance = 0
	local data = love.graphics.readbackTexture(state.screenCanvasses.celestialLuminanceCanvas)
	for x = 0, data:getWidth() - 1 do
		for y = 0, data:getHeight() - 1 do
			local luminance = data:getPixel(x, y)
			maxLuminance = math.max(maxLuminance, luminance)
		end
	end
	love.graphics.print( -- TEMP
		love.timer.getFPS() .. "\n" ..
		"x: " .. tostring(state.ship.position.x) .. "\n" ..
		"y: " .. tostring(state.ship.position.y) .. "\n" ..
		"z: " .. tostring(state.ship.position.z) .. "\n" ..
		"factor: " .. state:getGravityWellSlowdownFactor() .. "\n" ..
		"speed: " .. state:getMaxMovementSpeed() .. (love.keyboard.isDown("lshift") and " * 100" or "") .. "\n" ..
		"max \"luminance\" order: " .. math.floor(math.log10(maxLuminance)) .. "\n" ..
		"max \"luminance\": " .. maxLuminance
	)
end
