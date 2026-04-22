local consts = require("consts")

local pointLayerShapeTypes = {} -- Passing string gives id, passing id gives string

-- Multiply by object's real radii to estimate object count
-- densityFunction should return 0 when the inputs are further from the origin than 1
-- densityFunction return values should be within [0, 1]
function pointLayerShapeTypes.getBaseObjectAmount(densityFunction)
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
				total = total + sampleVolume * densityFunction(x, y, z)
			end
		end
	end
	return total
end

function pointLayerShapeTypes.load()
	local path = "pointLayerShapeTypes/"
	for _, itemName in ipairs(love.filesystem.getDirectoryItems(path)) do
		local itemPath = path .. itemName
		if love.filesystem.getInfo(itemPath, "directory") then
			local shapeType = {}
			pointLayerShapeTypes[itemName] = shapeType
			table.insert(pointLayerShapeTypes, shapeType)
			shapeType.name = itemName
			shapeType.getDensity = require(itemPath:gsub("/", ".") .. ".density")
			shapeType.densityShaderCode = love.filesystem.read(itemPath .. "/") -- Does not include prepended "#line 1\n"
			shapeType.baseObjectAmount = pointLayerShapeTypes.getBaseObjectAmount(shapeType.getDensity)
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
end

return pointLayerShapeTypes
