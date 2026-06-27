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

local workType
local stepSize
local sampleVolume
local firstSample
local lastSample
local stepCount
-- For gravity slowdown:
local scaleX, scaleY, scaleZ
local referencePosX, referencePosY, referencePosZ
local exponent
local cutRegionStartX, cutRegionEndX
local cutRegionStartY, cutRegionEndY
local cutRegionStartZ, cutRegionEndZ
local densityMultiplier
-- For mass data write:
local shapeMassDataFFI

local floor = math.floor
local min = math.min
local max = math.max

local function getSampleRangeTotalBaseAmount(densityFunction, ...)
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

local function getSampleRangeTotalGravitySlowdown(densityFunction, ...)
	local rangeTotal = 0
	local fullSampleVolume = sampleVolume * scaleX * scaleY * scaleZ
	local fullStepSizeX = stepSize * scaleX
	local fullStepSizeY = stepSize * scaleY
	local fullStepSizeZ = stepSize * scaleZ
	for sampleI = firstSample, lastSample do
		local xi = sampleI % stepCount
		local yi = floor(sampleI / stepCount) % stepCount
		local zi = floor(floor(sampleI / stepCount) / stepCount)
		local sampleX = -1 + stepSize * (xi + 0.5)
		local sampleY = -1 + stepSize * (yi + 0.5)
		local sampleZ = -1 + stepSize * (zi + 0.5)
		local sampleDensity = densityMultiplier * densityFunction(sampleX, sampleY, sampleZ, ...)
		local sampleCutStartX = max(-scaleX + fullStepSizeX * xi, cutRegionStartX)
		local sampleCutEndX = min(-scaleX + fullStepSizeX * (xi + 1), cutRegionEndX)
		local sampleCutStartY = max(-scaleY + fullStepSizeY * yi, cutRegionStartY)
		local sampleCutEndY = min(-scaleY + fullStepSizeY * (yi + 1), cutRegionEndY)
		local sampleCutStartZ = max(-scaleZ + fullStepSizeZ * zi, cutRegionStartZ)
		local sampleCutEndZ = min(-scaleZ + fullStepSizeZ * (zi + 1), cutRegionEndZ)
		local cutVolume =
			max(0, sampleCutEndX - sampleCutStartX) *
			max(0, sampleCutEndY - sampleCutStartY) *
			max(0, sampleCutEndZ - sampleCutStartZ)
		local sampleMass = sampleDensity * max(0, fullSampleVolume - cutVolume)

		local sampleXFull = sampleX * scaleX
		local sampleYFull = sampleY * scaleY
		local sampleZFull = sampleZ * scaleZ
		local deltaX = sampleXFull - referencePosX
		local deltaY = sampleYFull - referencePosY
		local deltaZ = sampleZFull - referencePosZ
		local dist = math.sqrt(deltaX ^ 2 + deltaY ^ 2 + deltaZ ^ 2)

		if dist > 0 then
			local valueThisSample = sampleMass * dist ^ exponent
			rangeTotal = rangeTotal + valueThisSample
		end
	end
	return rangeTotal
end

local function writeBaseAmountToMassData(writeOffset, densityFunction, ...)
	for sampleI = firstSample, lastSample do
		local xi = sampleI % stepCount
		local yi = floor(sampleI / stepCount) % stepCount
		local zi = floor(floor(sampleI / stepCount) / stepCount)
		local x = -1 + stepSize * (xi + 0.5)
		local y = -1 + stepSize * (yi + 0.5)
		local z = -1 + stepSize * (zi + 0.5)
		local mass = sampleVolume * densityFunction(x, y, z, ...)
		shapeMassDataFFI[writeOffset + sampleI] = mass
	end
end

local function writeToLowerLevelOfMassDataDetail(writeOffset, readOffset)
	for sampleI = firstSample, lastSample do
		local xi = sampleI % stepCount
		local yi = floor(sampleI / stepCount) % stepCount
		local zi = floor(floor(sampleI / stepCount) / stepCount)

		local readXIndex = xi * 2
		local readYIndex = yi * 2
		local readZIndex = zi * 2

		local xAdd = 1
		local yAdd = (2 * stepCount)
		local zAdd = (2 * stepCount) ^ 2

		local base = readOffset + readXIndex * xAdd + readYIndex * yAdd + readZIndex * zAdd
		shapeMassDataFFI[writeOffset + sampleI] =
			shapeMassDataFFI[base] +
			shapeMassDataFFI[base + xAdd] +
			shapeMassDataFFI[base + yAdd] +
			shapeMassDataFFI[base + xAdd + yAdd] +
			shapeMassDataFFI[base + zAdd] +
			shapeMassDataFFI[base + zAdd + xAdd] +
			shapeMassDataFFI[base + zAdd + yAdd] +
			shapeMassDataFFI[base + zAdd + xAdd + yAdd]
	end
end

while true do
	local info = love.thread.getChannel("shapeAmountsInfo"):demand()

	workType = info.type
	firstSample = info.firstSample
	lastSample = info.lastSample
	stepCount = info.stepCount
	stepSize = axisLength / stepCount
	sampleVolume = stepSize ^ 3

	exponent = info.exponent
	referencePosX = info.referencePosX
	referencePosY = info.referencePosY
	referencePosZ = info.referencePosZ
	scaleX, scaleY, scaleZ = info.scaleX, info.scaleY, info.scaleZ
	cutRegionStartX, cutRegionEndX = info.cutRegionStartX, info.cutRegionEndX
	cutRegionStartY, cutRegionEndY = info.cutRegionStartY, info.cutRegionEndY
	cutRegionStartZ, cutRegionEndZ = info.cutRegionStartZ, info.cutRegionEndZ
	densityMultiplier = info.sampleDensityMultiplier

	shapeMassDataFFI = info.shapeMassData and ffi.cast("float*", info.shapeMassData:getFFIPointer())
	local massDataStartOffsets = info.massDataStartOffsets
	local lodToWriteTo = info.lodToWriteTo

	local shapeType = shapeTypes[info.shapeTypeId]
	local currentNoiseLayers = shapeType.noiseInfo and shapeType.noiseInfo.layers
	if currentNoiseLayers then
		local valueNoiseDataFFI = ffi.cast("float*", info.valueNoiseData:getFFIPointer())
		setValueNoiseFunctionVars(currentNoiseLayers, valueNoiseDataFFI)
	end
	local densityFunction = shapeType.getDensity
	if workType == "massWrite" then
		if lodToWriteTo == #massDataStartOffsets then
			writeBaseAmountToMassData(massDataStartOffsets[lodToWriteTo], densityFunction, unpack(info.params))
		else
			writeToLowerLevelOfMassDataDetail(massDataStartOffsets[lodToWriteTo], massDataStartOffsets[lodToWriteTo + 1])
		end
		love.thread.getChannel("shapeAmountsResult"):push("finished")
		goto continue
	end
	local func =
		workType == "baseAmount" and getSampleRangeTotalBaseAmount or
		workType == "gravitySlowdown" and getSampleRangeTotalGravitySlowdown
	local rangeTotal = func(densityFunction, unpack(info.params))
	love.thread.getChannel("shapeAmountsResult"):push({firstSample = firstSample, rangeTotal = rangeTotal})
    ::continue::
end
