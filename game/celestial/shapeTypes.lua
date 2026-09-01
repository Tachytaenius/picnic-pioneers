local ffi = require("ffi")
local json = require("lib.json")

local util = require("util")
local consts = require("consts")

local processShapeNoiseLayerInfo = require("threadCode.common.processShapeNoiseLayerInfo")
local setValueNoiseForShapeTypeDensityFunc = require("threadCode.common.setValueNoiseForShapeTypeDensityFunc")
local initSampleDistribution = require("threadCode.common.initSampleDistribution")

local game = {}

local decodeShapeSubtypeScratchTable = {} -- Actual parameters
function game:decodeShapeSubtypeIntoScratchTable(type, subtypeId)
	assert(subtypeId < type.subtypeCount, "Shape subtype id is too large")

	for i = 1, #decodeShapeSubtypeScratchTable do
		decodeShapeSubtypeScratchTable[i] = nil
	end

	local temp = subtypeId
	for parameterIndex, parameter in ipairs(type.parameters) do
		if parameter.steps == 1 then
			goto continue
		end
		local stepThisParam = temp % parameter.steps
		local lerpI = stepThisParam / (parameter.steps - 1)
		local valueThisParam = parameter.rangeMin + (parameter.rangeMax - parameter.rangeMin) * lerpI
		decodeShapeSubtypeScratchTable[parameterIndex] = valueThisParam
		temp = math.floor(temp / parameter.steps)
		::continue::
	end
	return decodeShapeSubtypeScratchTable
end

function game:subtypeFromSamplingId(shapeType, samplingId)
	assert(samplingId < shapeType.sampleCount, "Shape sampling id is too large")

	-- I just really wanted to make this work without any extra tables for some reason

	local remainingInformation = samplingId -- Whatever occupied the least significant side of the encoding (i.e. changed with every increment) for subtype ids is on the other side (i.e. changes least often when incrementing)
	local constructedSubtype = 0

	for parameterIndex = #shapeType.parameters, 1, -1 do
		local parameter = shapeType.parameters[parameterIndex]

		local sampleThisParam = remainingInformation % parameter.samples
		local sampleLerp = parameter.samples == 1 and 0.5 or sampleThisParam / (parameter.samples - 1)
		local stepThisParam = parameter.steps == 1 and 0 or math.floor(sampleLerp * (parameter.steps - 1) + 0.5)
		constructedSubtype = constructedSubtype * parameter.steps + stepThisParam

		remainingInformation = math.floor(remainingInformation / parameter.samples)
	end
	return constructedSubtype
end

function game:getSubtypeBaseAmountWithSamples(shapeType, shapeSubtypeId, zScaleRatio)
	local zSampleLerp, zSampleAIdx, zSampleBIdx
	if shapeType.needsTrueRatio then
		local where = (zScaleRatio - shapeType.zScaleRatioMin) / (shapeType.zScaleRatioMax - shapeType.zScaleRatioMin)
		local whereSamples = where * (shapeType.zScaleRatioSamples - 1)
		local prevSample = math.max(0, math.min(shapeType.zScaleRatioSamples - 1, math.floor(whereSamples)))

		zSampleLerp = whereSamples - prevSample -- Should be (more or less) between 0 and 1
		zSampleAIdx = prevSample
		zSampleBIdx = math.min(shapeType.zScaleRatioSamples - 1, prevSample + 1)
	else
		-- Should be no zScaleRatio passed in
	end

	local lerpFactors = {}
	local leftSamples = {}
	local rightSamples = {}
	local temp = shapeSubtypeId
	for parameterIndex, parameter in ipairs(shapeType.parameters) do
		local stepThisParam = temp % parameter.steps
		local stepLerp = parameter.steps == 1 and 0.5 or stepThisParam / (parameter.steps - 1) -- From parameter min to parameter max
		local leftSample = parameter.samples == 1 and 0 or math.min(parameter.samples - 2, math.floor(stepLerp * (parameter.samples - 1)))

		local rightSample = leftSample + 1
		local samplingLerp = stepLerp * (parameter.samples - 1) - leftSample
		rightSample = math.min(parameter.samples - 1, rightSample) -- Enforce maximum after calculating lerp factor to avoid division by 0

		lerpFactors[#shapeType.parameters - parameterIndex + 1] = samplingLerp -- Flipped because lerp factors are popped from the top in mixN
		leftSamples[parameterIndex] = leftSample
		rightSamples[parameterIndex] = rightSample

		temp = math.floor(temp / parameter.steps)
	end

	local mixNSampleArgs = {}
	-- The sample base amounts form an n-dimensional grid of hypercubes :3
	for gridSides = 0, 2 ^ #shapeType.parameters - 1 do
		local samplingId = 0
		for parameterIndex, parameter in ipairs(shapeType.parameters) do
			local bit = parameterIndex - 1
			local doLeft = math.floor(gridSides / 2 ^ bit) % 2 == 0
			local paramSample = (doLeft and leftSamples or rightSamples)[parameterIndex]
			samplingId = samplingId * parameter.samples + paramSample
		end
		local baseAmountThisSample
		if shapeType.needsTrueRatio then
			local zSamples = shapeType.sampleBaseObjectAmounts[samplingId]
			local a = zSamples[zSampleAIdx]
			local b = zSamples[zSampleBIdx]
			baseAmountThisSample = a + zSampleLerp * (b - a)
		else
			baseAmountThisSample = shapeType.sampleBaseObjectAmounts[samplingId]
		end
		table.insert(mixNSampleArgs, baseAmountThisSample)
	end

	if #lerpFactors == 0 then
		return mixNSampleArgs[1]
	end
	return util.mixN(lerpFactors, unpack(mixNSampleArgs))
end

-- Multiply by object's real radii to estimate object count
-- densityFunction should return 0 when the inputs are further from the origin than 1
-- densityFunction return values should be within [0, 1]
function game:getShapeTypeBaseObjectAmount(sampleDistribution, integralThreads, shapeType, subtypeId, valueNoiseData, ratioX, ratioY, ratioZ)
	local scratch = self:decodeShapeSubtypeIntoScratchTable(shapeType, subtypeId)

	-- Set threads going
	for i = 1, #sampleDistribution do
		local infoTable = {
			shapeTypeId = shapeType.id,
			params = scratch,
			valueNoiseData = valueNoiseData,
			type = "baseAmount",
			firstSample = sampleDistribution[i].firstSample,
			lastSample = sampleDistribution[i].lastSample,
			stepCount = sampleDistribution.stepCount,
			ratioX = ratioX,
			ratioY = ratioY,
			ratioZ = ratioZ
		}
		love.thread.getChannel("shapeAmountsInfo"):push(infoTable)
	end

	-- Gather up results
	local results = {}
	for _=1, #sampleDistribution do
		-- The sum is sorted by thread id. This makes it [a little closer to being] deterministic.
		-- It's floats, so order can matter. Also, the thread count could make a difference, though I'm sure there are ways to make it a setting that does not affect a single bit of the final float by distributing the additions in a particular way.
		local result
		while not result do
			result = love.thread.getChannel("shapeAmountsResult"):demand(consts.shapeIntegralThreadTimeout)
			if not result then
				self:checkThreadsForErrors()
			end
		end
		table.insert(results, result)
	end

	table.sort(results, function(a, b)
		return a.firstSample < b.firstSample
	end)

	local total = 0
	for _, v in ipairs(results) do
		total = total + v.rangeTotal
	end

	return total
end

local function getShaderNoiseString(shapeType, attenuationMode)
	if not shapeType.noiseInfo then
		return ""
	end

	local prefix = attenuationMode and "attenuation" or "emission"
	local layerCodeLines = {}
	for _, layer in ipairs(shapeType.noiseInfo.layers) do
		table.insert(layerCodeLines,
			"NoiseLayer (" .. layer.start .. ", ivec3(" .. table.concat({layer.countX, layer.countY, layer.countZ}, ", ") .. "))"
		)
	end
	return
		"#define NOISE_LAYERS_NAME " .. prefix .. "NoiseLayers" .. "\n" ..
		"#define BUFFER_NAME " .. (attenuationMode and "AttenuationNoiseValues" or "EmissionNoiseValues") .. "\n" ..
		"#define ARRAY_NAME " .. (attenuationMode and "attenuationNoiseValues" or "emissionNoiseValues") .. "\n" ..
		"#define NOISE_FUNCTION_NAME " .. (attenuationMode and "attenuationValueNoise" or "emissionValueNoise") .. "\n" ..
		"#define GET_FUNCTION_NAME " .. (attenuationMode and "attenuationGetValue" or "emissionGetValue") .. "\n" ..
		"#define COUNT_CONST_NAME " .. prefix .. "NoiseLayerCount\n" ..
		"const int " .. prefix .. "NoiseLayerCount = " .. #shapeType.noiseInfo.layers .. ";\n" ..
		"const NoiseLayer NOISE_LAYERS_NAME[" .. prefix .. "NoiseLayerCount] = {" .. table.concat(layerCodeLines, ", ") .. "};\n" ..
		"#line 1\n" .. love.filesystem.read("shaders/include/valueNoise.glsl") ..
		"#undef NOISE_LAYERS_NAME\n" ..
		"#undef BUFFER_NAME\n" ..
		"#undef ARRAY_NAME\n" ..
		"#undef NOISE_FUNCTION_NAME\n" ..
		"#undef GET_FUNCTION_NAME\n" ..
		"#undef COUNT_CONST_NAME\n"
end

local function getShapeTypeParamUniforms(prefix, shapeType)
	local lines = {}
	if shapeType.parameters then
		for _, param in ipairs(shapeType.parameters) do
			lines[#lines+1] = "uniform float " .. prefix .. param.name .. ";\n"
		end
	end
	if shapeType.constants then
		for constant, value in pairs(shapeType.constants) do -- The fact that pairs' order is undefined shouldn't matter.
			lines[#lines+1] = "const float " .. prefix .. constant .. "=" .. value .. ";\n"
		end
	end
	return table.concat(lines)
end

local function getAttenuationShaderCode(shapeType)
	return
		"#define SHAPE_DENSITY_SAMPLE_TYPE sampleAttenuationShapeDensity\n" ..
		"#define VALUE_NOISE attenuationValueNoise\n" ..
		"#define PARAM(name) attenuationShape_##name\n" ..
		getShapeTypeParamUniforms("attenuationShape_", shapeType) ..
		"#line 1\n" .. love.filesystem.read(shapeType.shaderPath)
end

local function getIncludesFromShapeTypes(shapeTypes)
	local seenIncludes = {}
	for _, shapeType in ipairs(shapeTypes) do
		if shapeType.shaderIncludes then
			for _, includePath in ipairs(shapeType.shaderIncludes) do
				if not seenIncludes[includePath] then
					seenIncludes[includePath] = true
					seenIncludes[#seenIncludes+1] = includePath
				end
			end
		end
	end
	return seenIncludes
end

local function loadShaderIncludes(seenIncludes)
	local includeStrings = {}
	for _, includePath in ipairs(seenIncludes) do
		local filePath = "shaders/include/" .. includePath .. ".glsl"
		local fileCode = love.filesystem.read(filePath)
		if not fileCode then
			error("Can't find shape type file " .. filePath)
		end
		table.insert(includeStrings, "#line 1\n" .. fileCode)
	end
	return seenIncludes
end

-- :)
-- 100% bit-for-bit exact, which is probably what we want.
-- Maybe hex floats (%a) have some nasty surprises wrt determinism. Denormal numbers?
ffi.cdef([=[
    typedef struct {
        uint32_t lo;
        uint32_t hi;
    } intPair;
    typedef union {
        double x;
        intPair raw;
    } numConverter;
]=])
local converter = ffi.new("numConverter")
local function encodeDouble(x)
    converter.x = x
    return string.format("%08x%08x", converter.raw.hi, converter.raw.lo)
end
local function decodeDouble(code)
    local hiStr = string.sub(code, 1, 8)
    local loStr = string.sub(code, 9, 16)
    converter.raw.hi = tonumber(hiStr, 16)
    converter.raw.lo = tonumber(loStr, 16)
    return converter.x
end
local function checkCode(code)
	if type(code) ~= "string" then
		return false
	end
	if #code ~= 16 then
		return false
	end
	if string.match(code, "[^%x]") then -- If there are any non-hexadecimal chars
		return false
	end
	return true
end

local function cacheShapeType(shapeType, code, resolution, noiseAveraging)
	local dirPath = "cache/shapeTypes/"
	love.filesystem.createDirectory(dirPath)

	local resultsToEncode = {}
	for i = 0, shapeType.sampleCount - 1 do
		if shapeType.needsTrueRatio then
			resultsToEncode[i + 1] = {}
			for j = 0, shapeType.zScaleRatioSamples - 1 do
				local amount = shapeType.sampleBaseObjectAmounts[i][j]
				resultsToEncode[i + 1][j + 1] = encodeDouble(amount)
			end
		else
			local amount = shapeType.sampleBaseObjectAmounts[i]
			resultsToEncode[i + 1] = encodeDouble(amount)
		end
	end

	local contents = json.encode({
		code = code,
		resolution = resolution,
		noiseRepeat = shapeType.noiseInfo and noiseAveraging or nil,
		results = resultsToEncode
	})

	love.filesystem.write(dirPath .. shapeType.name .. ".json", contents)
end
local function readCache(shapeType, cachedInfo)
	if shapeType.needsTrueRatio then
		local results = {}
		if #cachedInfo.results ~= shapeType.sampleCount then
			return false
		end
		for samplingId = 0, shapeType.sampleCount - 1 do
			local sampleResults = cachedInfo.results[samplingId + 1]
			if type(sampleResults) ~= "table" then
				return false
			end

			local resultsInner = {}
			results[samplingId] = resultsInner
			if #sampleResults ~= shapeType.zScaleRatioSamples then
				return false
			end
			for zSample = 0, shapeType.zScaleRatioSamples - 1 do
				local code = sampleResults[zSample + 1]
				if not checkCode(code) then
					return false
				end
				resultsInner[zSample] = decodeDouble(code)
			end
		end
		return results
	else
		local results = {}
		if #cachedInfo.results ~= shapeType.sampleCount then
			return false
		end
		for samplingId = 0, shapeType.sampleCount - 1 do
			local code = cachedInfo.results[samplingId + 1]
			if not checkCode(code) then -- Will return if code is not present
				return false
			end
			results[samplingId] = decodeDouble(code)
		end
		return results
	end
end
local function handleCache(shapeType, code, resolution, noiseAveraging)
	local dirPath = "cache/shapeTypes/"
	love.filesystem.createDirectory(dirPath)

	local cachedInfoString = love.filesystem.read(dirPath .. shapeType.name .. ".json")
	if not cachedInfoString then
		return false
	end

	local cachedInfo = util.safeJsonDecode(cachedInfoString)
	if not cachedInfo then
		return false
	end

	-- Information about the shape type must not depend on any values outside of the lua file if they can change!
	if cachedInfo.code ~= code then
		return false
	end
	if shapeType.noiseInfo then -- Since the code is the same, we assume that what was stored also does/doesn't have noiseInfo etc
		if cachedInfo.noiseRepeat ~= noiseAveraging then
			return false
		end
	else
		if cachedInfo.noiseRepeat then
			-- ???
			return false
		end
	end

	if cachedInfo.resolution ~= resolution then
		return false
	end

	assert(cachedInfo.results, "Cached info for shape type " .. shapeType.name .. " has no results data?")

	-- TODO: Version info? a) what about unknown versions and b) what about *not* recreating all unnecessarily every update? ... Don't use the game version but rather a "result version" which is changed when different results are expected. Best kept as a string rather than a number for flexibility.

	return readCache(shapeType, cachedInfo)
end

function game:loadShapeTypes()
	local maxRequiredNoiseValues = 0

	local pointLayerShapeTypes = {} -- Passing name gives id, passing id gives name

	local path = "pointLayerShapeTypes/"
	for _, itemName in ipairs(love.filesystem.getDirectoryItems(path)) do
		local itemPath = path .. itemName
		if love.filesystem.getInfo(itemPath, "directory") then
			local shapeType = {}
			pointLayerShapeTypes[itemName] = shapeType
			table.insert(pointLayerShapeTypes, shapeType)
			shapeType.name = itemName

			local code = love.filesystem.read(itemPath .. "/info.lua")
			local info = load(code)()
			shapeType.code = code

			shapeType.constants = info.constants
			shapeType.parameters = info.parameters or {}

			shapeType.needsTrueRatio = info.needsTrueRatio
			shapeType.getDensity = info.getDensity
			setValueNoiseForShapeTypeDensityFunc(shapeType)

			shapeType.zScaleRatioMin = info.zScaleRatioMin
			shapeType.zScaleRatioMax = info.zScaleRatioMax
			if not shapeType.zScaleRatioMin and not shapeType.zScaleRatioMax then
				-- Default
				shapeType.zScaleRatioMin = 1
				shapeType.zScaleRatioMax = 1
			end
			assert(shapeType.zScaleRatioMin <= shapeType.zScaleRatioMax, "Z scale ratio min and max are flipped for shape type " .. itemName)

			shapeType.attenuation = info.attenuation

			shapeType.zScaleRatioSamples = info.zScaleRatioSamples
			if not shapeType.needsTrueRatio then
				assert(not shapeType.zScaleRatioSamples, "Non-needsTrueRatio shape type \"" .. itemName .. "\" can't have zScaleRatioSamples")
			elseif not shapeType.attenuation then
				assert(shapeType.zScaleRatioSamples > 1, "Shape type zScaleRatioSamples must be at least 2")
			end

			shapeType.shaderIncludes = info.shaderIncludes
			shapeType.shaderPath = itemPath .. "/shaderCode.glsl"

			local amount = processShapeNoiseLayerInfo(shapeType, info) -- Adds info to shapeType
			maxRequiredNoiseValues = math.max(amount, maxRequiredNoiseValues) -- Amount can be 0

			-- Max subtype count is max uint32
			-- The remaining portion of subtype count after discrete parameters have taken from it is given fairly to each continuous parameter.
			-- Perhaps too fairly since sometimes there is some wasted space-- maybe let n of the continuous parameters' steps be incremented by 1 until just before n causes the subtype count to exceed 2^32
			local subtypeCount = 1
			local continuousParamCount = 0
			for _, parameter in ipairs(shapeType.parameters) do
				if parameter.discrete then
					subtypeCount = subtypeCount * parameter.steps
					parameter.samples = parameter.steps
				else
					continuousParamCount = continuousParamCount + 1
				end
			end
			local sampleCount = subtypeCount
			if continuousParamCount > 0 then
				local stepsForContinuousParams = math.floor((2^32 / subtypeCount) ^ (1 / continuousParamCount))
				subtypeCount = subtypeCount * stepsForContinuousParams ^ continuousParamCount

				for _, parameter in ipairs(shapeType.parameters) do
					if not parameter.discrete then
						parameter.steps = stepsForContinuousParams
						sampleCount = sampleCount * parameter.samples
					end
				end
			end
			shapeType.subtypeCount = subtypeCount
			shapeType.sampleCount = sampleCount -- For precalculation
		end
	end
	-- Must match sorting in shapeAmounts.lua
	table.sort(pointLayerShapeTypes, function (a, b)
		return a.name < b.name
	end)
	for i, v in ipairs(pointLayerShapeTypes) do
		v.id = i - 1
	end
	local count = #pointLayerShapeTypes
	for i = 1, count do
		pointLayerShapeTypes[i - 1], pointLayerShapeTypes[i] = pointLayerShapeTypes[i], nil
	end

	local maxThreads = consts.pointLayerShapeTypeAmountIntegralMaxThreads
	local integralThreads = {}
	self.shapeIntegralThreads = integralThreads
	for i = 1, maxThreads do
		integralThreads[i] = love.thread.newThread("threadCode/shapeAmounts.lua")
		integralThreads[i]:start()
	end
	self:checkThreadsForErrors()
	local resolution = consts.pointLayerShapeTypeAmountIntegralSteps
	local noiseAveraging = consts.pointLayerShapeTypeAmountIntegralAverageRepeatCount
	local sampleDistribution = initSampleDistribution(resolution, consts.pointLayerShapeTypeAmountIntegralMaxThreads)

	local bytesPerFloat = 4
	local valueNoiseData = love.data.newByteData(bytesPerFloat * maxRequiredNoiseValues)
	local valueNoiseDataFFI = ffi.cast("float*", valueNoiseData:getFFIPointer())

	local requiredIntegrals = 0
	for id = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[id]

		if shapeType.attenuation then
			goto continue
		end

		local code = shapeType.code
		local result = handleCache(shapeType, code, resolution, noiseAveraging)
		if result then
			shapeType.sampleBaseObjectAmounts = result
		else
			shapeType.needsCalculating = true
			local multiplier = shapeType.noiseInfo and noiseAveraging or 1
			local multiplier2 = shapeType.zScaleRatioSamples or 1
			requiredIntegrals = requiredIntegrals + shapeType.sampleCount * multiplier * multiplier2
		end

	    ::continue::
	end

	local loadInfo = self.loadInfo
	loadInfo.shapeTypePrecalcIntegralsRequired = requiredIntegrals
	loadInfo.shapeTypePrecalcIntegralsDone = 0
	local alreadyDoneNoiseless = false
	for averagingIteration = 0, noiseAveraging - 1 do
		-- Init noise for the integrals. They are allowed to use the same value data
		self:seedCelestialRNG(self:getShapeIntegralNoiseSeed(averagingIteration, consts.shapeIntegralNoiseSeedTypes.baseAmounts))
		for i = 0, maxRequiredNoiseValues - 1 do
			valueNoiseDataFFI[i] = self:celestialRandom()
		end

		for id = 0, count - 1 do
			local shapeType = pointLayerShapeTypes[id]

			if not shapeType.needsCalculating then
				goto continue
			end

			if shapeType.attenuation then
				goto continue
			end

			if not shapeType.noiseInfo and alreadyDoneNoiseless then
				goto continue
			end

			local sampleBaseObjectAmounts = shapeType.sampleBaseObjectAmounts or {}
			for samplingId = 0, shapeType.sampleCount - 1 do
				local subtypeId = self:subtypeFromSamplingId(shapeType, samplingId)
				if shapeType.needsTrueRatio then
					sampleBaseObjectAmounts[samplingId] = sampleBaseObjectAmounts[samplingId] or {}
					for zScaleStep = 0, shapeType.zScaleRatioSamples - 1 do
						local scaleX = 1
						local scaleY = 1
						local lerpFactor = zScaleStep / (shapeType.zScaleRatioSamples - 1)
						local scaleZ = shapeType.zScaleRatioMin + lerpFactor * (shapeType.zScaleRatioMax - shapeType.zScaleRatioMin)
						local divisor = math.max(scaleX, scaleY, scaleZ)
						local ratioX, ratioY, ratioZ = scaleX / divisor, scaleY / divisor, scaleZ / divisor
						local result = self:getShapeTypeBaseObjectAmount(sampleDistribution, integralThreads, shapeType, subtypeId, valueNoiseData, ratioX, ratioY, ratioZ)
						sampleBaseObjectAmounts[samplingId][zScaleStep] = (sampleBaseObjectAmounts[samplingId][zScaleStep] or 0) + result

						loadInfo.shapeTypePrecalcIntegralsDone = loadInfo.shapeTypePrecalcIntegralsDone + 1
						coroutine.yield()
					end
				else
					local result = self:getShapeTypeBaseObjectAmount(sampleDistribution, integralThreads, shapeType, subtypeId, valueNoiseData, nil, nil, nil)
					sampleBaseObjectAmounts[samplingId] = (sampleBaseObjectAmounts[samplingId] or 0) + result

					loadInfo.shapeTypePrecalcIntegralsDone = loadInfo.shapeTypePrecalcIntegralsDone + 1
					coroutine.yield()
				end
			end
			shapeType.sampleBaseObjectAmounts = sampleBaseObjectAmounts

			::continue::
		end

		alreadyDoneNoiseless = true
	end
	loadInfo.shapeTypePrecalcIntegralsDone = nil
	loadInfo.shapeTypePrecalcIntegralsRequired = nil

	-- Divide down the averaging sums for the shape types with noise
	for id = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[id]

		if not shapeType.needsCalculating then
			goto continue
		end

		if shapeType.attenuation then
			goto continue
		end

		if shapeType.noiseInfo then
			-- sampleBaseObjectAmounts' entries will have been added to multiple times to get an average
			if shapeType.needsTrueRatio then
				for samplingId = 0, shapeType.sampleCount - 1 do
					local zSamples = shapeType.sampleBaseObjectAmounts[samplingId]
					for i = 0, shapeType.zScaleRatioSamples - 1 do
						zSamples[i] = zSamples[i] / noiseAveraging
					end
				end
			else
				for samplingId = 0, shapeType.sampleCount - 1 do
					shapeType.sampleBaseObjectAmounts[samplingId] = shapeType.sampleBaseObjectAmounts[samplingId] / noiseAveraging
				end
			end
		end

		::continue::
	end

	-- Get all needed shader combinations
	local shapeVolumeShaders = {}
	local shapeIntensityPrecalcShaderParams = {}
	for i = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[i]
		if shapeType.attenuation then
			goto continue
		end
		shapeVolumeShaders[shapeType.name] = shapeVolumeShaders[shapeType.name] or {}
		shapeIntensityPrecalcShaderParams[shapeType.name] = shapeIntensityPrecalcShaderParams[shapeType.name] or {}
		for j = 0, count - 1 do
			local otherShapeType = pointLayerShapeTypes[j]
			if not otherShapeType.attenuation then
				goto continue
			end

			local includeStrings = loadShaderIncludes(getIncludesFromShapeTypes({shapeType, otherShapeType}))

			local emissionNoiseString = getShaderNoiseString(shapeType, false)
			local attenuationNoiseString = getShaderNoiseString(otherShapeType, true)

			local shapeTypeCode =
				-- Emission
				"#define SHAPE_DENSITY_SAMPLE_TYPE sampleEmissionShapeDensity\n" ..
				"#define VALUE_NOISE emissionValueNoise\n" ..
				"#define PARAM(name) emissionShape_##name\n" ..
				getShapeTypeParamUniforms("emissionShape_", shapeType) ..
				"#line 1\n" .. love.filesystem.read(shapeType.shaderPath) ..
				"#undef SHAPE_DENSITY_SAMPLE_TYPE\n" ..
				"#undef VALUE_NOISE\n" ..
				"#undef PARAM\n" ..
				-- Attenuation
				getAttenuationShaderCode(otherShapeType)

			local code =
				"#pragma language glsl4\n" ..
				"#line 1\n" .. love.filesystem.read("shaders/include/lib/random.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/include/structs.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/include/trilinearMix.glsl") ..
				emissionNoiseString ..
				attenuationNoiseString ..
				"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
				table.concat(includeStrings) ..
				shapeTypeCode ..
				"#line 1\n" .. love.filesystem.read("shaders/drawing/layerVolumetrics.glsl")
			shapeVolumeShaders[shapeType.name][otherShapeType.name] = love.graphics.newComputeShader(
				code,
				{
					debugname = "Vol. Shader for Emi. " .. shapeType.name .. ", Att. " .. otherShapeType.name,
					defines = {
						MAX_ADDITIONS = consts.volumetricMaxPixelAdditions,
						RESULT_CANVAS_FORMAT = "rgba32f"
					}
				}
			)
			shapeIntensityPrecalcShaderParams[shapeType.name][otherShapeType.name] = { -- More info is applied at the site where this is used
				code,
				{
					debugname = "Int.Precalc. Shader for Emi. " .. shapeType.name .. ", Att. " .. otherShapeType.name,
					defines = {
						INTENSITY_PRECALC = true
					}
				}
			}
		    ::continue::
		end
	    ::continue::
	end

	for i = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[i]
		if not shapeType.attenuation then
			goto continue
		end

		local includeStrings = loadShaderIncludes(getIncludesFromShapeTypes({shapeType}))

		shapeType.pointAttenuationShader = love.graphics.newComputeShader(
			"#pragma language glsl4\n" ..
			"#line 1\n" .. love.filesystem.read("shaders/include/lib/random.glsl") ..
			"#line 1\n" .. love.filesystem.read("shaders/include/structs.glsl") ..
			"#line 1\n" .. love.filesystem.read("shaders/include/trilinearMix.glsl") ..
			getShaderNoiseString(shapeType, true) ..
			-- Note that there is no raycasts.glsl. Attenuation shape type sampling may go outside the sphere and even the box that shape types are sampled in, so ensure that all shape types won't break (i.e. will always return 0) in those cases
			table.concat(includeStrings) ..
			getAttenuationShaderCode(shapeType) ..
			"#line 1\n" .. love.filesystem.read("shaders/drawing/pointAttenuation.glsl"),
			{
				debugname = "Point Attenuation Shader for " .. shapeType.name
			}
		)

	    ::continue::
	end

	-- NOTE: Would be better off doing each shape type one by one and caching after each one so's not to waste work if quitting mid-load
	for id = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[id]
		if shapeType.needsCalculating then
			shapeType.needsCalculating = nil
			cacheShapeType(shapeType, shapeType.code, resolution, noiseAveraging)
		end
		shapeType.code = nil
	end

	self.pointLayerShapeTypes = pointLayerShapeTypes
	self.shapeVolumeShaders = shapeVolumeShaders
	self.shapeIntensityPrecalcShaderParams = shapeIntensityPrecalcShaderParams

	self.valueNoiseDataReusableForPointLayers = valueNoiseData -- Generously donate valueNoiseData to the point layers now that it won't be used again here
end

function game:checkThreadsForErrors()
	for _, thread in ipairs(self.shapeIntegralThreads) do
		local err = thread:getError()
		assert(not err, err)
	end
	local err = self.amountDataStageManagerThread:getError()
	assert(not err, err)
end

return game
