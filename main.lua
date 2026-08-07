local bm = require("bigmaths")
local consts = require("consts")
local game = require("game")
local settings = require("settings")
local util = require("util")

---@type Gamestate
local state

local initCoroutine
local shouldResize

local function clearCache()
	print("Clearing cache...")
	local success, err = pcall(util.recursiveDelete, "cache")
	if not success then
		error("Error clearing cache:\n\n" .. err)
	end
	print("Cache cleared")
end

function love.load(args)
	for _, arg in ipairs(args) do
		if arg == "--clearCache" then
			clearCache()
		elseif arg == "--noRun" then
			love.event.quit()
			return
		else
			error("Invalid argument \"" .. arg .. "\"")
		end
	end

	bm.mapm.digits(consts.mapmDigits)
	love.graphics.setDefaultFilter("nearest", "nearest")
	settings:load()
	settings:save()
	state = game:newState()
	state.loadInfo = {}
	initCoroutine = coroutine.create(function() state:initState() end)

	shouldResize = false
end

function love.update(dt)
	if state.loadInfo then
		if not state.loadInfo.skippedFirstUpdate then
			state.loadInfo.skippedFirstUpdate = true
			return
		end

		local start = love.timer.getTime()
		local time
		repeat
			local success, err = coroutine.resume(initCoroutine)
			if not success then
				error("Game init failed:\n\n" .. err)
			end
			time = love.timer.getTime() - start
		until time >= consts.initMaxTickLength

		if coroutine.status(initCoroutine) == "dead" then
			state.loadInfo = nil
		end

		return
	end

	if shouldResize then -- Don't handle during loading
		state:resizeGameScreen(love.graphics.getDimensions())
	end

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
	if state.loadInfo then
		local done = state.loadInfo.shapeTypePrecalcIntegralsDone
		local required = state.loadInfo.shapeTypePrecalcIntegralsRequired
		if done and required then
			love.graphics.print(
				"Loading...\n" ..
				math.floor(done / required * 100) .. "%"
			)
		end
		return
	end

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
	shouldResize = true
end
