local ffi = require("ffi")

local processShapeNoiseLayerInfo = require("threadCode.common.processShapeNoiseLayerInfo")
local setValueNoiseForShapeTypeDensityFunc = require("threadCode.common.setValueNoiseForShapeTypeDensityFunc")

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
function game:getShapeTypeBaseObjectAmount(integralThreads, shapeType, subtypeId, valueNoiseData)
	self:decodeShapeSubtypeIntoScratchTable(shapeType, subtypeId)
	local infoTable = {shapeTypeId = shapeType.id, params = decodeShapeSubtypeScratchTable, valueNoiseData = valueNoiseData}

	-- Set threads going
	for i, thread in ipairs(integralThreads) do
		local err = thread:getError()
		assert(not err, err)
		love.thread.getChannel("shapeAmountIntegralInfo"):push(infoTable)
	end

	-- Gather up results
	local results = {}
	for i, thread in ipairs(integralThreads) do
		local err = thread:getError()
		assert(not err, err)
		-- The sum is sorted by thread id. This makes it [a little closer to being] deterministic.
		-- It's floats, so order can matter. Also, the thread count could make a difference, though I'm sure there are ways to make it a setting that does not affect a single bit of the final float by distributing the additions in a particular way.
		table.insert(results, love.thread.getChannel("shapeAmountIntegralResult"):demand())
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
			shapeType.parameters = info.parameters or {}
			shapeType.getDensity = info.getDensity
			setValueNoiseForShapeTypeDensityFunc(shapeType)

			local subtypeCount = 1
			for _, parameter in ipairs(shapeType.parameters) do
				assert(math.floor(parameter.steps) == parameter.steps and parameter.steps >= 2, "Parameter step count must be an int and must be at least 2")
				subtypeCount = subtypeCount * parameter.steps
			end
			shapeType.subtypeCount = subtypeCount

			local includeStrings = {}
			if info.shaderIncludes then
				for _, includePath in ipairs(info.shaderIncludes) do
					local filePath = "shaders/include/" .. includePath .. ".glsl"
					local fileCode = love.filesystem.read(filePath)
					if not fileCode then
						error("Can't find file " .. filePath .. " for shape type " .. itemName)
					end
					table.insert(includeStrings, "#line 1\n" .. fileCode)
				end
			end

			local amount = processShapeNoiseLayerInfo(shapeType, info) -- Adds info to shapeType
			maxRequiredNoiseValues = math.max(amount, maxRequiredNoiseValues) -- Amount might be 0

			local shaderDefines = {}
			local noiseString
			if not shapeType.noiseInfo then
				noiseString = ""
			else
				local layerCodeLines = {}
				for _, layer in ipairs(shapeType.noiseInfo.layers) do
					table.insert(layerCodeLines,
						"NoiseLayer (" .. layer.start .. ", ivec3(" .. table.concat({layer.countX, layer.countY, layer.countZ}, ", ") .. "))"
					)
				end
				local constCode = "const int noiseLayerCount = " .. #shapeType.noiseInfo.layers .. ";\n" .. "const NoiseLayer noiseLayers[noiseLayerCount] = {" .. table.concat(layerCodeLines, ", ") .. "};\n"
				noiseString =
					"#line 1\n" .. constCode ..
					"#line 1\n" .. love.filesystem.read("shaders/include/valueNoise.glsl")

				-- Alternatively instead of using constCode use preprocessor defines
				-- for i, layer in ipairs(shapeType.noiseInfo.layers) do
				-- 	local defineName = "NOISE_LAYER_" .. i
				-- 	shaderDefines[defineName] = layer.start .. ", ivec3(" .. table.concat({layer.countX, layer.countY, layer.countZ}, ", ") .. ")"
				-- end
			end
			shapeType.volumetricShader = love.graphics.newShader(
				"#pragma language glsl4\n" ..
				"#line 1\n" .. love.filesystem.read("shaders/include/structs.glsl") ..
				noiseString ..
				"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
				table.concat(includeStrings) ..
				"#line 1\n" .. love.filesystem.read(itemPath .. "/shaderCode.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/include/skyDirection.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/drawing/layerVolumetrics.glsl"),
				{
					defines = shaderDefines
				}
			)
		end
	end
	-- Must match sorting in shapeAmountIntegral.lua
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

	-- Start threads
	local integralThreads = {}
	local threadCount = consts.pointLayerShapeTypeAmountIntegralMaxThreads
	local stepCount = consts.pointLayerShapeTypeAmountIntegralSteps
	local totalSamples = stepCount ^ 3
	local samplesPerThread = math.floor(totalSamples / threadCount)
	local firstSample = 0
	for i = 1, threadCount do
		-- Should have a thread for every sample, can also drop threads if there aren't enough samples to go around
		local lastSample = math.min(totalSamples - 1, firstSample + samplesPerThread - 1)
		if i == threadCount then
			lastSample = totalSamples - 1
		end

		integralThreads[i] = love.thread.newThread("threadCode/shapeAmountIntegral.lua")
		integralThreads[i]:start(firstSample, lastSample, stepCount)
		local err = integralThreads[i]:getError()
		assert(not err, err)

		if lastSample >= totalSamples - 1 then
			break
		end

		firstSample = lastSample + 1
	end

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

			if not shapeType.noiseInfo and alreadyDoneNoiseless then
				goto continue
			end

			local subtypeBaseObjectAmounts = shapeType.subtypeBaseObjectAmounts or {}
			for subtypeId = 0, shapeType.subtypeCount - 1 do
				local result = self:getShapeTypeBaseObjectAmount(integralThreads, shapeType, subtypeId, valueNoiseData)
				subtypeBaseObjectAmounts[subtypeId] = (subtypeBaseObjectAmounts[subtypeId] or 0) + result
			end
			shapeType.subtypeBaseObjectAmounts = subtypeBaseObjectAmounts

		    ::continue::
		end

		alreadyDoneNoiseless = true
	end

	-- Divide down the averaging sums for the shape types with noise
	for id = 0, count - 1 do
		local shapeType = pointLayerShapeTypes[id]

		if shapeType.noiseInfo then
			-- subtypeBaseObjectAmounts' entries will have been added to multiple times to get an average
			for subtypeId = 0, shapeType.subtypeCount - 1 do
				shapeType.subtypeBaseObjectAmounts[subtypeId] = shapeType.subtypeBaseObjectAmounts[subtypeId] /
					consts.pointLayerShapeTypeAmountIntegralAverageRepeatCount
			end
		end
	end

	self.pointLayerShapeTypes = pointLayerShapeTypes
end

return game
