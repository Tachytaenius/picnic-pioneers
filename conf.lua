local util = require("util")
util.load()
local consts = require("consts")
consts.load()

function love.conf(t)
	t.identity = consts.loveIdentity
	t.version = consts.loveVersion
	t.graphics.gammacorrect = true
end
