local version = love.filesystem.read("version.txt") or "unknown" -- This file is provided on build

-- Assume that this love instance runs on a separate thread to
-- whatever started it (rounding modes are per-thread).
local extutils = require("lib.extutils")
extutils.ensureRoundingMode()

local bm = require("bigmaths")
local consts = require("consts")
consts.loadAll()
local game = require("game")
local settings = require("settings")
local util = require("util")

---@type Gamestate
local state

local initCoroutine
local shouldResize
local skipOneUpdate

local function clearCache()
	print("Clearing cache...")
	local success, err = pcall(util.recursiveDelete, "cache")
	if not success then
		error("Error clearing cache:\n\n" .. err)
	end
	print("Cache cleared")
end

function love.load(args)
	local startPosStrings = {}

	local i = 1
	while true do
		local arg = args[i]
		if not arg then
			break
		end
		i = i + 1
		if arg == "--clearCache" then
			clearCache()
		elseif arg == "--noRun" then
			love.event.quit()
			return
		elseif arg == "--startPosition" then
			startPosStrings[1] = args[i]
			startPosStrings[2] = args[i + 1]
			startPosStrings[3] = args[i + 2]
			i = i + 3
		elseif arg == "--brightnessMultiplier" then
			consts.celestialLuminanceMultiplier = tonumber(args[i])
			i = i + 1
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

	-- Setup window
	util.remakeWindow(consts.defaultWindowWidth, consts.defaultWindowHeight)

	initCoroutine = coroutine.create(function() state:initState({
		shipPosition = bm.vec3(unpack(startPosStrings))
	}) end)

	shouldResize = false

	skipOneUpdate = false
end

function love.update(dt)
	if state.loadInfo then
		if not state.loadInfo.skippedFirstUpdate then
			state.loadInfo.skippedFirstUpdate = true -- Skipped loading update
			return
		end

		local start = love.timer.getTime()
		local time
		repeat
			if coroutine.status(initCoroutine) == "dead" then
				state.loadInfo = nil
				skipOneUpdate = true -- Skipped actual game update
				break
			end

			local success, err = coroutine.resume(initCoroutine)
			if not success then
				error("Game init failed:\n\n" .. err .. "\n\nCoroutine traceback:\n" .. debug.traceback(initCoroutine))
			end
			time = love.timer.getTime() - start
		until time >= consts.initMaxTickLength

		return
	end

	if shouldResize then -- Don't handle during loading
		state:resizeGameScreen(love.graphics.getDimensions())
	end

	if skipOneUpdate then
		-- Avoid large initial dt
		skipOneUpdate = false
		return
	end

	local dtLimited = math.min(dt, consts.maxDeltaTime)
	state:update(dtLimited)

	-- TEMP (would we want this to be dmath's exp?)
	local rate = 5
	if love.keyboard.isDown("-") then
		consts.celestialLuminanceMultiplier = consts.celestialLuminanceMultiplier * math.exp(-rate * dt)
	end
	if love.keyboard.isDown("=") then
		consts.celestialLuminanceMultiplier = consts.celestialLuminanceMultiplier * math.exp(rate * dt)
	end
end

-- TEMP
local function printPos()
	if not (state and state.ship) then
		return false
	end
	print(tostring(state.ship.position.x) .. " " .. tostring(state.ship.position.y) .. " " .. tostring(state.ship.position.z))
	return true
end
function love.keypressed(key)
	if key == "p" then
		printPos()
	end
end

function love.draw()
	if state.loadInfo then
		-- TODO: Clean this up!!!

		local done = state.loadInfo.shapeTypePrecalcIntegralsDone
		local required = state.loadInfo.shapeTypePrecalcIntegralsRequired
		if done and required then
			love.graphics.print(
				"Precalculating (and caching) various object masses...\n" ..
				math.floor(done / required * 100) .. "%"
			)
			return
		end
		
		local done = state.loadInfo.starPrecalcSamplesDone
		local required = state.loadInfo.starPrecalcSamplesRequired
		if done and required then
			love.graphics.print(
				"Precalculating average star properties...\n" ..
				math.floor(done / required * 100) .. "%"
			)
			return
		end

		-- Misc loading
		love.graphics.print("Loading...")
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
