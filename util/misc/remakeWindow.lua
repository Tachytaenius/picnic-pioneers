local consts = require("consts")
local settings = require("settings")
local util = require("util")

return function(width, height)
	local _, _, flags = love.window.getMode()
	local currentDisplay = flags.display

	love.window.setMode(
		width, height,
		{
			fullscreen = settings.fullscreen,
			borderless = settings.fullscreen,
			display = currentDisplay,
			resizable = true
		}
	)
	love.window.setIcon(util.getScaledImageData(consts.iconPath, consts.iconScale))
	love.window.setTitle(consts.windowTitle)
end
