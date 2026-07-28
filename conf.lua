local util = require("util")
util.load()
local consts = require("consts")
consts.load()

function love.conf(t)
	t.identity = consts.loveIdentity
	t.version = consts.loveVersion
	t.window.title = consts.windowTitle
	t.window.width = consts.windowWidth
	t.window.height = consts.windowHeight
	t.window.resizable = true
	t.graphics.gammacorrect = true
end
