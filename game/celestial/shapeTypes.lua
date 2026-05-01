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

			local subtypeCount = 1
			for _, parameter in ipairs(shapeType.parameters) do
				assert(math.floor(parameter.steps) == parameter.steps and parameter.steps >= 2, "Parameter step count must be an int and must be at least 2")
				subtypeCount = subtypeCount * parameter.steps
			end
			shapeType.subtypeCount = subtypeCount

			local subtypeBaseObjectAmounts = {}
			for subtypeId = 0, subtypeCount - 1 do
				local scratchTable = self:decodeShapeSubtypeIntoScratchTable(shapeType, subtypeId)
				subtypeBaseObjectAmounts[subtypeId] = self:getShapeTypeBaseObjectAmount(info.getDensity, unpack(scratchTable))
			end
			shapeType.subtypeBaseObjectAmounts = subtypeBaseObjectAmounts

			shapeType.getDensity = info.getDensity
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
			shapeType.volumetricShader = love.graphics.newShader(
				"#pragma language glsl4\n" ..
				"#line 1\n" .. love.filesystem.read("shaders/include/structs.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/include/raycasts.glsl") ..
				table.concat(includeStrings) ..
				"#line 1\n" .. love.filesystem.read(itemPath .. "/shaderCode.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/include/skyDirection.glsl") ..
				"#line 1\n" .. love.filesystem.read("shaders/drawing/layerVolumetrics.glsl")
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
