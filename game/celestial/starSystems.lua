local consts = require("consts")
local util = require("util")
local mathsies = require("lib.mathsies")

local game = {}

function game:generateStarSystem(layerObject)
	local bodies = {}

	local massSum = 0
	for i = 1, consts.maxStarsPerSystem do
		if layerObject.starParams[i][1] == consts.invalidStarParam then
			break
		end
		local radius, mass, radiantFluxR, radiantFluxG, radiantFluxB = self:generateStar(unpack(layerObject.starParams[i]))
		local radiantFlux = mathsies.vec3(radiantFluxR, radiantFluxG, radiantFluxB)
		massSum = massSum + mass
		local star = {
			type = "star",
			mass = mass,
			radius = radius,
			radiantFlux = radiantFlux,
			radiantIntensity = radiantFlux / (consts.tau * 2),
			position = mathsies.vec3((i - 1) * 1.5e9, 0, 0) -- TODO: Kepler orbits
		}
		table.insert(bodies, star)
	end

	local remainingMass = math.max(0, layerObject.mass - massSum)

	layerObject.bodies = bodies
end

-- All params are in [0, 1] (RNG being noninclusive may never allow reaching 1 though)
-- Returns radius, mass, and radiant flux (aka luminosity)
local solarLuminosity = 3.828e26
local solarMass = 2e30
local solarRadius = 6.957e8
local solarVolume = 2 / 3 * consts.tau * solarRadius ^ 3
local solarDensity = solarMass / solarVolume
local tau = consts.tau
local starMassParamWeight = 0.85
local starMassParamExponent = 120
local starMassExponentRangeLow = 28
local starMassExponentRangeHigh = 30.5
local starMassMultiplier = 1
local max = math.max
local function massLuminosityRelationDwarf(mass)
	local mass = mass / solarMass
	return max(0, solarLuminosity * (0.372324 * mass ^ 4 - 0.0152364 * mass ^ 3 + 0.068376 * mass ^ 2 + 0.00682457 * mass - 0.000314545)) -- Desmos fit to Wikipedia data
end
local function massRadiusRelationDwarf(mass)
	local mass = mass / solarMass
	-- 1 kilometre is arbitrary but zero radius would be bad!
	-- The parameters above shouldn't allow anywhere near this, though.
	-- This is just safety in case they're changed.
	return max(1000, solarRadius * (0.891494 * mass ^ 0.8412)) -- Desmos fit to Wikipedia data
end
local function massLuminosityRelation(mass)
	local mass = mass / solarMass -- Change units
	local temp
	if mass < 0.43 then
		temp = 0.23 * mass ^ 2.3
	elseif mass < 2 then
		temp = mass ^ 4
	elseif mass < 55 then
		temp = 1.4 * mass ^ 3.5
	else
		temp = 32000 * mass
	end
	return solarLuminosity * temp
end
local function massRadiusRelation(mass)
	local mass = mass / solarMass
	local temp
	if mass < 1 then
		temp = mass ^ 0.8
	else
		temp = mass ^ 0.57
	end
	return solarRadius * temp
end
function game:generateStar(param1, param2)--, param3)
	-- Nonlinear relationship between mass param and actual mass
	local exponentT = starMassParamWeight * param1 ^ starMassParamExponent + (1 - starMassParamWeight) * param1
	local exponent = starMassExponentRangeLow + exponentT * (starMassExponentRangeHigh - starMassExponentRangeLow)
	local starMass = starMassMultiplier * 10 ^ exponent

	local dwarf = starMass <= 0.6 * solarMass

	local fluxMulLow = 0.9
	local fluxMulHigh = 1.1
	local fluxMul = fluxMulLow + (fluxMulHigh - fluxMulLow) * param2

	local radius = (dwarf and massRadiusRelationDwarf or massRadiusRelation)(starMass)
	local area = 2 * tau * radius ^ 2
	local radiantFlux = fluxMul * (dwarf and massLuminosityRelationDwarf or massLuminosityRelation)(starMass)

	local starEffectiveTemperature = (radiantFlux / (area * consts.stefanBoltzmannConstant)) ^ (1 / 4)

	-- 1e-9 because nm to m
	-- This would be better if averaged over the range of the bins with more than one sample but that would get computationally expensive
	local radianceR = util.planckLaw(self.rSpectrumMiddle * 1e-9, starEffectiveTemperature)
	local radianceG = util.planckLaw(self.gSpectrumMiddle * 1e-9, starEffectiveTemperature)
	local radianceB = util.planckLaw(self.bSpectrumMiddle * 1e-9, starEffectiveTemperature)

	-- Surface radiance is flux / area / pi steradians
	-- So flux from surface radiance is surface radiance * area * pi steradians
	local radiantFluxR = radianceR * area * (tau / 2)
	local radiantFluxG = radianceG * area * (tau / 2)
	local radiantFluxB = radianceB * area * (tau / 2)

	return radius, starMass, radiantFluxR, radiantFluxG, radiantFluxB
end

return game
