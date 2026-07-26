local ffi = require("ffi")

local processShapeNoiseLayerInfo = require("threadCode.common.processShapeNoiseLayerInfo")
local setValueNoiseForShapeTypeDensityFunc = require("threadCode.common.setValueNoiseForShapeTypeDensityFunc")
local initSampleDistribution = require("threadCode.common.initSampleDistribution")

local consts = require("consts")

local game = {}

local decodeShapeSubtypeScratchTable = {}
function game:decodeShapeSubtypeIntoScratchTable(type, subtypeId)
	assert(subtypeId < type.subtypeCount, "Shape subtype id is too large")

	for i = 1, #decodeShapeSubtypeScratchTable do
		decodeShapeSubtypeScratchTable[i] = nil
	end

	local temp = subtypeId
	for parameterIndex, parameter in ipairs(type.parameters) do
		local stepThisParam = temp % parameter.steps
		local lerpI = stepThisParam / (parameter.steps - 1)
		local valueThisParam = parameter.rangeMin + (parameter.rangeMax - parameter.rangeMin) * lerpI
		decodeShapeSubtypeScratchTable[parameterIndex] = valueThisParam
		temp = math.floor(temp / parameter.steps)
	end
	return decodeShapeSubtypeScratchTable
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

			local info = require(itemPath:gsub("/", ".") .. ".info")

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

			local subtypeCount = 1
			for _, parameter in ipairs(shapeType.parameters) do
				assert(math.floor(parameter.steps) == parameter.steps and parameter.steps >= 2, "Parameter step count must be an int and must be at least 2")
				subtypeCount = subtypeCount * parameter.steps
			end
			shapeType.subtypeCount = subtypeCount
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
	local sampleDistribution = initSampleDistribution(consts.pointLayerShapeTypeAmountIntegralSteps, consts.pointLayerShapeTypeAmountIntegralMaxThreads)

	local bytesPerFloat = 4
	local valueNoiseData = love.data.newByteData(bytesPerFloat * maxRequiredNoiseValues)
	local valueNoiseDataFFI = ffi.cast("float*", valueNoiseData:getFFIPointer())

	local alreadyDoneNoiseless = false
	for averagingIteration = 0, consts.pointLayerShapeTypeAmountIntegralAverageRepeatCount - 1 do
		-- Init noise for the integrals. They are allowed to use the same value data
		self:seedCelestialRNG(self:getShapeIntegralNoiseSeed(averagingIteration)) -- The code in there is TOOD
		for i = 0, maxRequiredNoiseValues - 1 do
			valueNoiseDataFFI[i] = self:celestialRandom()
		end

		for id = 0, count - 1 do
			local shapeType = pointLayerShapeTypes[id]

			if shapeType.attenuation then
				goto continue
			end

			if not shapeType.noiseInfo and alreadyDoneNoiseless then
				goto continue
			end

			local subtypeBaseObjectAmounts = shapeType.subtypeBaseObjectAmounts or {}
			for subtypeId = 0, shapeType.subtypeCount - 1 do
				if shapeType.needsTrueRatio then
					subtypeBaseObjectAmounts[subtypeId] = {}
					for zScaleStep = 0, shapeType.zScaleRatioSamples - 1 do
						local ratioX = 1
						local ratioY = 1
						local lerpFactor = zScaleStep / (shapeType.zScaleRatioSamples - 1)
						local ratioZ = shapeType.zScaleRatioMin + lerpFactor * (shapeType.zScaleRatioMax - shapeType.zScaleRatioMin)
						local result = self:getShapeTypeBaseObjectAmount(sampleDistribution, integralThreads, shapeType, subtypeId, valueNoiseData, ratioX, ratioY, ratioZ)
						subtypeBaseObjectAmounts[subtypeId][zScaleStep] = (subtypeBaseObjectAmounts[subtypeId][zScaleStep] or 0) + result
					end
				else
					local result = self:getShapeTypeBaseObjectAmount(sampleDistribution, integralThreads, shapeType, subtypeId, valueNoiseData, nil, nil, nil)
					subtypeBaseObjectAmounts[subtypeId] = (subtypeBaseObjectAmounts[subtypeId] or 0) + result
				end
			end
			shapeType.subtypeBaseObjectAmounts = subtypeBaseObjectAmounts

		    ::continue::
		end

		alreadyDoneNoiseless = true
	end

	-- Divide down the averaging sums for the shape types with noise
	for id = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[id]

		if shapeType.attenuation then
			goto continue
		end

		if shapeType.noiseInfo then
			-- subtypeBaseObjectAmounts' entries will have been added to multiple times to get an average
			if shapeType.needsTrueRatio then
				for subtypeId = 0, shapeType.subtypeCount - 1 do
					local zSamples = shapeType.subtypeBaseObjectAmounts[subtypeId]
					for i = 0, shapeType.zScaleRatioSamples - 1 do
						zSamples[i] = zSamples[i] / consts.pointLayerShapeTypeAmountIntegralAverageRepeatCount
					end
				end
			else
				for subtypeId = 0, shapeType.subtypeCount - 1 do
					shapeType.subtypeBaseObjectAmounts[subtypeId] = shapeType.subtypeBaseObjectAmounts[subtypeId] /
						consts.pointLayerShapeTypeAmountIntegralAverageRepeatCount
				end
			end
		end

	    ::continue::
	end

	-- Get all needed shader combinations
	local shapeVolumeShaders = {}
	for i = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[i]
		if shapeType.attenuation then
			goto continue
		end
		shapeVolumeShaders[shapeType.name] = shapeVolumeShaders[shapeType.name] or {}
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

			shapeVolumeShaders[shapeType.name][otherShapeType.name] = love.graphics.newComputeShader(
				"#pragma language glsl4\n" ..
				"#line 1\n" .. love.filesystem.read("shaders/include/lib/random.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/include/structs.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/include/trilinearMix.glsl") ..
				emissionNoiseString ..
				attenuationNoiseString ..
				"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
				table.concat(includeStrings) ..
				shapeTypeCode ..
				"#line 1\n" .. love.filesystem.read("shaders/drawing/layerVolumetrics.glsl"),
				{
					debugname = "Vol. Shader for Emi. " .. shapeType.name .. ", Att. " .. otherShapeType.name,
					defines = {
						MAX_ADDITIONS = consts.volumetricMaxPixelAdditions
					}
				}
			)
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

	self.pointLayerShapeTypes = pointLayerShapeTypes
	self.shapeVolumeShaders = shapeVolumeShaders

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
