local valueNoise = require("threadCode.common.valueNoise")

return function(currentNoiseLayers, valueNoiseDataFFI)
	local environment = {
		currentNoiseLayers = currentNoiseLayers,
		valueNoiseDataFFI = valueNoiseDataFFI
	}
	setmetatable(environment, {__index = _G})
	setfenv(valueNoise, environment)
end
