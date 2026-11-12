local consts = require("consts")

-- Returns spectral radiance
local function planckLaw(wavelength, temperature) -- Wavelength is in metres, temperature in Kelvin
	local h = consts.planckConstant
	local e = consts.e
	local c = consts.speedOfLight
	local k = consts.boltzmannConstant
	return 2 * h * c ^ 2 / wavelength ^ 5 / (e ^ (h * c / wavelength / k / temperature) - 1)
end

return planckLaw
