local valueNoise = require("threadCode.common.valueNoise")

return function(shapeType)
	local environment = {valueNoise = valueNoise}
	setmetatable(environment, {__index = _G})
	setfenv(shapeType.getDensity, environment)
end
