local firstSample, lastSample, stepCount = ...

local processShapeNoiseLayerInfo = require("threadCode.common.processShapeNoiseLayerInfo")
local setValueNoiseForShapeTypeDensityFunc = require("threadCode.common.setValueNoiseForShapeTypeDensityFunc")
local setValueNoiseFunctionVars = require("threadCode.common.setValueNoiseFunctionVars")

local ffi = require("ffi")

local shapeTypes = {}
local path = "pointLayerShapeTypes/"
for _, itemName in ipairs(love.filesystem.getDirectoryItems(path)) do
	local itemPath = path .. itemName
	if love.filesystem.getInfo(itemPath, "directory") then
		local info = require(itemPath:gsub("/", ".") .. ".info")
		local new = {
			name = itemName,
			getDensity = info.getDensity
		}
		processShapeNoiseLayerInfo(new, info)
		setValueNoiseForShapeTypeDensityFunc(new)
		table.insert(shapeTypes, new)
	end
end
-- Must match sorting in shapeTypes.lua
table.sort(shapeTypes, function (a, b)
	return a.name < b.name
end)
for i = 1, #shapeTypes do
	shapeTypes[i - 1], shapeTypes[i] = shapeTypes[i], nil
end

local axisLength = 2
local stepSize = axisLength / stepCount
local sampleVolume = stepSize ^ 3

local floor = math.floor
local function getSampleRangeTotal(densityFunction, ...)
	local rangeTotal = 0
	for sampleI = firstSample, lastSample do
		local xi = sampleI % stepCount
		local yi = floor(sampleI / stepCount) % stepCount
		local zi = floor(floor(sampleI / stepCount) / stepCount)
		local x = -1 + stepSize * (xi + 0.5)
		local y = -1 + stepSize * (yi + 0.5)
		local z = -1 + stepSize * (zi + 0.5)
		rangeTotal = rangeTotal + sampleVolume * densityFunction(x, y, z, ...)
	end
	return rangeTotal
end

while true do
	local info = love.thread.getChannel("shapeAmountIntegralInfo"):demand()
	local shapeType = shapeTypes[info.shapeTypeId]
	local currentNoiseLayers = shapeType.noiseInfo and shapeType.noiseInfo.layers
	if currentNoiseLayers then
		local valueNoiseDataFFI = ffi.cast("float*", info.valueNoiseData:getFFIPointer())
		setValueNoiseFunctionVars(currentNoiseLayers, valueNoiseDataFFI)
	end
	local densityFunction = shapeType.getDensity
	local rangeTotal = getSampleRangeTotal(densityFunction, unpack(info.params))
	love.thread.getChannel("shapeAmountIntegralResult"):push({firstSample = firstSample, rangeTotal = rangeTotal})
end
