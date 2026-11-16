local consts = require("consts")
local util = require("util")
local mathsies = require("lib.mathsies")
local dmath = require("lib.dmath")

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
		local radiantIntensity = radiantFlux / (consts.tau * 2)
		massSum = massSum + mass

		local attenuationSpectralRatio = mathsies.vec3(
			self:celestialRandomRange(0.5, 1.5),
			self:celestialRandomRange(0.5, 1.5),
			self:celestialRandomRange(0.5, 1.5)
		)
		local constantAttenuationCoefficient = attenuationSpectralRatio * self:celestialRandomRange(0.001, 0.1) / radius
		local constantEmissionCoefficient = mathsies.vec3(
			self:getStarConstEmissionCoeff(radius, radiantIntensity.x, constantAttenuationCoefficient.x),
			self:getStarConstEmissionCoeff(radius, radiantIntensity.y, constantAttenuationCoefficient.y),
			self:getStarConstEmissionCoeff(radius, radiantIntensity.z, constantAttenuationCoefficient.z)
		)

		local star = {
			type = "star",
			systemStarNumber = i,
			mass = mass,
			radius = radius,
			radiantFlux = radiantFlux,
			radiantIntensity = radiantIntensity,
			position = mathsies.vec3((i - 1) * 5e9, 0, 0), -- TODO: Kepler orbits
			constantAttenuationCoefficient = constantAttenuationCoefficient,
			constantEmissionCoefficient = constantEmissionCoefficient
		}
		table.insert(bodies, star)
		self:generateStarLookupTables(star)
		self:writeToStarLookupTextures(star)
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
local stefanBoltzmannConstant
local binRange
local rStart
local gStart
local bStart
local starPlanckLawSamplesPerBin
local planckLaw = util.planckLaw
local function bin(wavelengthStart, temperature)
	local sum = 0
	for i = 0, starPlanckLawSamplesPerBin - 1 do
		sum = sum + planckLaw(wavelengthStart + binRange * (i + 0.5) / starPlanckLawSamplesPerBin, temperature)
	end
	return sum / starPlanckLawSamplesPerBin
end
function game:generateStar(param1, param2)--, param3)
	-- TODO: Code cleanup...
	stefanBoltzmannConstant = stefanBoltzmannConstant or consts.stefanBoltzmannConstant
	binRange = binRange or self.spectralBinRange
	rStart = rStart or self.rSpectrumStart
	gStart = gStart or self.gSpectrumStart
	bStart = bStart or self.bSpectrumStart
	starPlanckLawSamplesPerBin = starPlanckLawSamplesPerBin or consts.starPlanckLawSamplesPerBin

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

	local starEffectiveTemperature = (radiantFlux / (area * stefanBoltzmannConstant)) ^ (1 / 4)

	-- This would be better if averaged over the range of the bins with more than one sample but that would get computationally expensive
	local radianceR = bin(rStart, starEffectiveTemperature)
	local radianceG = bin(gStart, starEffectiveTemperature)
	local radianceB = bin(bStart, starEffectiveTemperature)

	-- Surface radiance is flux / area / pi steradians
	-- So flux from surface radiance is surface radiance * area * pi steradians
	local radiantFluxR = radianceR * area * (tau / 2)
	local radiantFluxG = radianceG * area * (tau / 2)
	local radiantFluxB = radianceB * area * (tau / 2)

	return radius, starMass, radiantFluxR, radiantFluxG, radiantFluxB
end

function game:generateStarLookupTables(body)
	local radiantIntensity = body.radiantIntensity
	local starVolume = 2 / 3 * consts.tau * body.radius ^ 3

	local set = self.starSystemLookupInfoSet[body.systemStarNumber]
	local temperature = set.temperature
	local density = set.density
	local scattering = set.scattering
	local absorption = set.absorption
	local emission = set.emission

	local constantAttenuationCoefficient = body.constantAttenuationCoefficient
	local constantEmissionCoefficient = body.constantEmissionCoefficient

	for i = 1, consts.starLUTDepthSamples do
		-- Has no effect
		temperature[i] = 0
		density[i] = 0

		-- Constant for now
		scattering[i][1], scattering[i][2], scattering[i][3] = 0, 0, 0
		absorption[i][1], absorption[i][2], absorption[i][3] = mathsies.vec3.components(constantAttenuationCoefficient)
		emission[i][1], emission[i][2], emission[i][3] = mathsies.vec3.components(constantEmissionCoefficient)
	end
end

function game:writeToStarLookupTextures(body)
	local set = self.starSystemLookupInfoSet[body.systemStarNumber]
	local function write(name, scaleFactor)
		local data = set[name]
		local imageData = set[name .. "LUTImageData"]
		local canvas = set[name .. "LUTCanvas"]
		for i = 1, consts.starLUTDepthSamples do
			imageData:setPixel(i - 1, 0,
				data[i][1] * scaleFactor,
				data[i][2] * scaleFactor,
				data[i][3] * scaleFactor
			)
		end
		canvas:replacePixels(imageData)
	end
	-- No scale factor is needed (yet?) since distances, radiances etc are unscaled when rendering bodies (unlike when rendering whole galaxies etc)
	write("scattering", 1)
	write("absorption", 1)
	write("emission", 1)
end

function game:makeStarLookupInfo(noGraphical)
	local info = {noGraphical = noGraphical}

	-- CPU-side
	info.temperature = {}
	info.density = {}
	local function newSpectral()
		local ret = {}
		for i = 1, consts.starLUTDepthSamples do
			ret[i] = {}
		end
		return ret
	end
	info.scattering = newSpectral()
	info.absorption = newSpectral()
	info.emission = newSpectral()

	if not noGraphical then
		-- GPU-side
		local function new(name)
			local w, h = consts.starLUTDepthSamples, 1
			local format = "rgba32f"
			info[name .. "LUTImageData"] = love.image.newImageData(w, h, format) -- Stored here in units appropriate for the GPU
			local canvas = love.graphics.newCanvas(w, h, {format = format})
			canvas:setFilter("linear")
			canvas:setWrap("clamp")
			info[name .. "LUTCanvas"] = canvas
		end
		new("scattering")
		new("absorption")
		new("emission")
	end

	return info
end

function game:makeStarSystemLookupInfoSet()
	local infoSet = {}
	for i = 1, consts.maxStarsPerSystem do
		infoSet[i] = self:makeStarLookupInfo()
	end
	return infoSet
end

function game:getStarConstEmissionCoeff(R, i, s)
	-- https://www.desmos.com/calculator/dv6dlqkmny
	if s == 0 then
		return 3 * i / (2 * consts.tau * R ^ 3)
	end
	return (i * 4 * s ^ 3) / (consts.tau * (2 * R ^ 2 * s ^ 2 + dmath.exp(-2 * R * s) * (2 * R * s + 1) - 1))
end

return game
