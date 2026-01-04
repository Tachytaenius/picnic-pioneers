local consts = require("consts")

function love.conf(t)
	t.identity = consts.loveIdentity
	t.version = consts.loveVersion
	t.graphics.gammacorrect = true
end
