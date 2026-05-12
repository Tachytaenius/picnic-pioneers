local consts = require("consts")

local game = {}

-- Multiply by object's real radii to estimate object count
-- densityFunction should return 0 when the inputs are further from the origin than 1
-- densityFunction return values should be within [0, 1]
function game:getShapeTypeBaseObjectAmount(densityFunction, ...)
	local stepCount = consts.pointLayerShapeTypeAmountIntegralSteps
	local axisLength = 2
	local stepSize = axisLength / stepCount
	local sampleVolume = stepSize ^ 3
	local total = 0
	for xi = 0, stepCount - 1 do
		for yi = 0, stepCount - 1 do
			for zi = 0, stepCount - 1 do
				local x = -1 + stepSize * (xi + 0.5)
				local y = -1 + stepSize * (yi + 0.5)
				local z = -1 + stepSize * (zi + 0.5)
				total = total + sampleVolume * densityFunction(x, y, z, ...)
			end
		end
	end
	return total
end

local function averageValueNoise(noiseLayerIndex, x, y, z)
	return 0.5
end

function game:setValueNoiseForShapeTypeDensityFunc(shapeType, valueNoise)
	valueNoise = valueNoise or function() error("valueNoise function not set for shape type " .. shapeType.name) end
	local environment = {valueNoise = valueNoise}
	setmetatable(environment, {__index = _G})
	setfenv(shapeType.getDensity, environment)
end

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

function game:loadShapeTypes()
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

			local subtypeCount = 1
			for _, parameter in ipairs(shapeType.parameters) do
				assert(math.floor(parameter.steps) == parameter.steps and parameter.steps >= 2, "Parameter step count must be an int and must be at least 2")
				subtypeCount = subtypeCount * parameter.steps
			end
			shapeType.subtypeCount = subtypeCount

			local subtypeBaseObjectAmounts = {}
			self:setValueNoiseForShapeTypeDensityFunc(shapeType, averageValueNoise)
			for subtypeId = 0, subtypeCount - 1 do
				local scratchTable = self:decodeShapeSubtypeIntoScratchTable(shapeType, subtypeId)
				subtypeBaseObjectAmounts[subtypeId] = self:getShapeTypeBaseObjectAmount(info.getDensity, unpack(scratchTable))
			end
			self:setValueNoiseForShapeTypeDensityFunc(shapeType, nil)
			shapeType.subtypeBaseObjectAmounts = subtypeBaseObjectAmounts

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

			if info.valueNoiseInfo then
				local currentStart = 0
				shapeType.noiseInfo = {}
				local layers = {}
				shapeType.noiseInfo.layers = layers
				for i, layerInfo in ipairs(info.valueNoiseInfo) do
					local count = layerInfo.countX * layerInfo.countY * layerInfo.countZ
					layers[i] = {
						start = currentStart,
						count = count,
						countX = layerInfo.countX,
						countY = layerInfo.countY,
						countZ = layerInfo.countZ
					}
					currentStart = currentStart + count
				end
				shapeType.noiseInfo.requiredValueCount = currentStart -- Sum of all layers' counts
			end

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
	table.sort(pointLayerShapeTypes, function (a, b)
		return a.name < b.name
	end)
	for i, v in ipairs(pointLayerShapeTypes) do
		v.id = i - 1
	end
	for i = 0, #pointLayerShapeTypes do
		pointLayerShapeTypes[i - 1], pointLayerShapeTypes[i] = pointLayerShapeTypes[i], nil
	end

	self.pointLayerShapeTypes = pointLayerShapeTypes
end

return game
