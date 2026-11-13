local consts = require("consts")

local h
local e
local c
local k

-- Returns spectral radiance
local function planckLaw(wavelength, temperature) -- Wavelength is in metres, temperature in Kelvin
	h = h or consts.planckConstant
	e = e or consts.e
	c = c or consts.speedOfLight
	k = k or consts.boltzmannConstant
	return 2 * h * c ^ 2 / wavelength ^ 5 / (e ^ (h * c / wavelength / k / temperature) - 1)
end

return planckLaw
