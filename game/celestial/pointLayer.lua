-- There are lots of different coordinate systems in this file...
-- In general, anything that needs to be both large and precise has either been avoided (e.g. by scaling down), or arbitrary precision numbers have been used

--- PointLayerFunctions are the functions implemented by every PointLayer.
---@class PointLayerFunctions
---@field generateChunkCommon fun(realX: number, realY: number, realZ: number, chunkId: number, chunkBufferIndex: number)
---@field getBoundingBoxChunks fun(self: any): (minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number)
---@field getChunkPointCount fun(chunkBufferIndex: number): number
---@field getClosestPointIn2x2x2 fun(self: any, referencePosition: any)
---@field getDensity fun(self: any, realX: number, realY: number, realZ: number): number -- The position is in units where 1 is the side length of a chunk. Returned density is a proportion from 0 to 1, where 1 is the point layer's max density
---@field getPointVars fun(chunkBufferIndex: number, pointId: number, name: string, type: string, count: number): ...
--- Actions are "prepare" (when near to an object but not close enough to need the results yet),
--- "expect" (when the results are needed), and
--- "cancel" (when there is no longer an object nearby or the point layer is not active)
--- RNG should be be seeded appropriately for value noise if action == "prepare".
--- action being prepare or expect means the the other two arguments are needed.
---@field handleThreadedShapeInit fun(self: any, action: string)
---@field prepareValueNoiseFunction fun(self: any) -- This is per shape type, so in case multiple layers use the same shape type this must be set before every use of the density function
---@field randomiseValueNoise fun(self: any, type: string): ...
---@field setChunkEmpty fun(self: any, chunkBufferIndex: number)
---@field setChunkPointCount fun(self: any, chunkBufferIndex: number, count: number)
---@field setPoint fun(self: any, chunkBufferIndex: number, pointId: number, ...)
--- some of these need to be changed from "..." to ...<type> or <type>..., but I dunno what the types are yet

--- PointLayer holds world and rendering data/state for elements at a particular scale (e.g. stars, galaxies).
---@class PointLayer : PointLayerFunctions
---@field public volumetricCanvas love.Canvas
---@field public volumetricAddCountCanvas love.Canvas
---@field public volumetricCanvasCameraInfo table
---@field public debugName string
---@field chunkBufferSideLength number
---@field chunkBufferTotalSize number
---@field chunkExtraInfo table
---@field chunkPointCountBuffer love.GraphicsBuffer
---@field chunkPointCountData love.ByteData
---@field chunkPointCountDataFFI ffi.cdata*
---@field chunkSize number
---@field chunkVolume number
---@field ffiDataTypeFromPointVarIndex table
---@field hasNoiseAttenuation boolean
---@field hasNoiseEmission boolean
---@field parentPointLayer PointLayer|nil
---@field index number
---@field childPointLayer PointLayer|nil
---@field gameObject Gamestate self-proclaimed "HACK" :3
--- not all fields added here yet...

require("table.clear")
local ffi = require("ffi")
local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local setValueNoiseFunctionVars = require("threadCode.common.setValueNoiseFunctionVars")
local initSampleDistribution = require("threadCode.common.initSampleDistribution")

local util = require("util")
local consts = require("consts")

local game = {}

local function getBoundingBoxChunksForSize(chunkSize, x, y, z)
	-- TODO: I think this and the code using it breaks (slightly) when size[x/y/z] / chunkSize is an integer
	local minX, maxX = math.floor(-x / chunkSize), math.floor(x / chunkSize)
	local minY, maxY = math.floor(-y / chunkSize), math.floor(y / chunkSize)
	local minZ, maxZ = math.floor(-z / chunkSize), math.floor(z / chunkSize)
	return minX, maxX, minY, maxY, minZ, maxZ
end

local galaxyPointLayerInfo = {
	chunkObjectType = "galaxyChunk",
	pointObjectType = "galaxy",
	fixedParentObject = {
		position = consts.galaxyGroupPosition,
		radii = consts.galaxyGroupScale * mathsies.vec3(1, 1, consts.galaxyGroupZScaleRatio),
		orientation = consts.galaxyGroupOrientation,
		shapeTypeName = consts.galaxyGroupShapeTypeName,
		shapeSubtypeId = 0, -- TODO: Allow selecting from closest subtype to given parameters...?
		attenuationShapeTypeName = consts.galaxyGroupAttenuationShapeName,
		attenuationShapeSubtypeId = 0,
		attenuationMultiplier = consts.galaxyGroupAttenuationMultiplier
	}
}

galaxyPointLayerInfo.features = {
	-- "sent" means present on both CPU and GPU, "unsent" means only present on CPU, nil means not present
	shapeTypeSubtypeIds = "unsent",
	attenuationShapeTypeSubtypeIds = "unsent",
	attenuationMultiplier = "unsent",
	radii = "unsent",
	orientation = "unsent",
	mass = "unsent",

	shapeTypeSet = {
		{
			name = "ellipticalGalaxy",
			weight = 1,
			scaleMin = 7.5e18,
			scaleMax = 1e19,
			attenuationShapeTypes = {
				{
					name = "genericNebulae",
					weight = 1,
					-- 2.5 * 10^-20 metres^-1 in the middle, converted from "1.8 magnitudes per kiloparsec" attenuation coefficient measurement near the sun
					mulRangeMin = 2.5e-20 * 0.1,
					mulRangeMax = 2.5e-20 * 1.9
				}
			}
		},
		{
			name = "spiralGalaxy",
			weight = 7,
			scaleMin = 3e19,
			scaleMax = 7.5e20,
			attenuationShapeTypes = {
				{
					name = "genericNebulae",
					weight = 1,
					mulRangeMin = 2.5e-20 * 0.1,
					mulRangeMax = 2.5e-20 * 1.9
				}
			}
		}
	}
}

function galaxyPointLayerInfo:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count)
	local randomChoice = util.weightedRandomChoice
	local shapeTypeSet = self.features.shapeTypeSet

	local extraInfo = self.chunkExtraInfo[chunkBufferIndex]
	local radiiInfo = extraInfo.radii
	local massInfo = extraInfo.mass
	local shapeTypeSubtypeIdInfo = extraInfo.shapeTypeSubtypeIds
	local attenuationShapeTypeSubtypeIdInfo = extraInfo.attenuationShapeTypeSubtypeIds
	local attenuationMultiplierInfo = extraInfo.attenuationMultiplier
	local orientationInfo = extraInfo.orientation

	local nextLayerMaxDensity = self.childPointLayer.maxPointDensity
	local nextLayerAverageMassPerPoint = self.childPointLayer.averageMassPerPoint
	local nextLayerAverageRadiantIntensityRPerPoint = self.childPointLayer.averageRadiantIntensityRPerPoint
	local nextLayerAverageRadiantIntensityGPerPoint = self.childPointLayer.averageRadiantIntensityGPerPoint
	local nextLayerAverageRadiantIntensityBPerPoint = self.childPointLayer.averageRadiantIntensityBPerPoint
	local radiantIntensityScale = self.chunkSize ^ -2
	for i = 0, count - 1 do
		local x = self.gameObject:celestialRandom()
		local y = self.gameObject:celestialRandom()
		local z = self.gameObject:celestialRandom()

		local choice = self.gameObject:celestialRandomChoice(shapeTypeSet)
		local shapeType = self.gameObject.pointLayerShapeTypes[choice.name]
		local shapeTypeId = shapeType.id
		local shapeSubtypeId = self.gameObject:celestialRandomRangeInt(0, shapeType.subtypeCount)

		local attenuationChoice = choice.attenuationShapeTypes and self.gameObject:celestialRandomChoice(choice.attenuationShapeTypes)
		local attenuationType = self.gameObject.pointLayerShapeTypes[attenuationChoice and attenuationChoice.name or consts.noAttenuationShapeTypeName]
		local attenuationShapeTypeId = attenuationType.id
		local attenuationShapeSubtypeId = self.gameObject:celestialRandomRangeInt(0, attenuationType.subtypeCount)

		attenuationMultiplierInfo[i] = self.gameObject:celestialRandomRange(attenuationChoice.mulRangeMin, attenuationChoice.mulRangeMax)

		local scale = self.gameObject:celestialRandomRange(choice.scaleMin, choice.scaleMax)
		local zScaleRatio = self.gameObject:celestialRandomRange(shapeType.zScaleRatioMin, shapeType.zScaleRatioMax)

		local xRadius = scale
		local yRadius = scale
		local zRadius = scale * zScaleRatio
		radiiInfo[i * 3] = xRadius
		radiiInfo[i * 3 + 1] = yRadius
		radiiInfo[i * 3 + 2] = zRadius

		-- Get orientation
		local ox, oy, oz, ow = self.gameObject:celestialRandomOrientation()
		orientationInfo[i * 4] = ox
		orientationInfo[i * 4 + 1] = oy
		orientationInfo[i * 4 + 2] = oz
		orientationInfo[i * 4 + 3] = ow

		local baseAmount
		if shapeType.needsTrueRatio then
			baseAmount = self.gameObject:getSubtypeBaseAmountWithSamples(shapeType, shapeSubtypeId, zScaleRatio)
		else
			baseAmount = self.gameObject:getSubtypeBaseAmountWithSamples(shapeType, shapeSubtypeId)
		end
		local amountWithin = baseAmount * xRadius * yRadius * zRadius * nextLayerMaxDensity -- Estimate
		massInfo[i] = amountWithin * nextLayerAverageMassPerPoint

		local r = amountWithin * nextLayerAverageRadiantIntensityRPerPoint * radiantIntensityScale
		local g = amountWithin * nextLayerAverageRadiantIntensityGPerPoint * radiantIntensityScale
		local b = amountWithin * nextLayerAverageRadiantIntensityBPerPoint * radiantIntensityScale

		shapeTypeSubtypeIdInfo[2 * i], shapeTypeSubtypeIdInfo[2 * i + 1] = shapeTypeId, shapeSubtypeId
		attenuationShapeTypeSubtypeIdInfo[2 * i], attenuationShapeTypeSubtypeIdInfo[2 * i + 1] = attenuationShapeTypeId, attenuationShapeSubtypeId

		self:setPoint(chunkBufferIndex, i, x, y, z, r, g, b)
	end
end

function galaxyPointLayerInfo:generateRemainingCurrentObjectInfo()
	local currentObject = self.currentObject
end

local starSystemPointLayerInfo = {
	chunkObjectType = "starChunk",
	pointObjectType = "starSystem"
}

starSystemPointLayerInfo.features = {
	mass = "unsent",
	starParams = "unsent",
	bodies = true, -- Final layer, treated differently
	pointStarCountWeights = {1000, 50, 15, 1}
}

local starParamsScratch = {}
function starSystemPointLayerInfo:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count)
	local extraInfo = self.chunkExtraInfo[chunkBufferIndex]
	local massInfo = extraInfo.mass
	local starParamInfo = extraInfo.starParams
	local radiantIntensityScale = self.chunkSize ^ -2
	local starProbabilites = self.features.pointStarCountCumulativeProbability
	for i = 0, count - 1 do
		local x = self.gameObject:celestialRandom()
		local y = self.gameObject:celestialRandom()
		local z = self.gameObject:celestialRandom()

		local massSum = 0
		local rSum, gSum, bSum = 0, 0, 0
		local starsThisSystemChooser = self.gameObject:celestialRandom()
		local starsThisSystem
		for num, probability in ipairs(starProbabilites) do
			if starsThisSystemChooser < probability then
				starsThisSystem = num
				break
			end
		end
		starsThisSystem = starsThisSystem or 1 -- Shouldn't happen tbh
		assert(1 <= starsThisSystem and starsThisSystem <= consts.maxStarsPerSystem, "Invalid system star count " .. starsThisSystem)

		for starIndex = 1, starsThisSystem do
			for paramIndex = 1, consts.starParamCount do
				local param = self.gameObject:celestialRandom()
				starParamsScratch[paramIndex] = param
				starParamInfo[consts.maxStarsPerSystem * consts.starParamCount * i + (starIndex - 1) * consts.starParamCount + paramIndex - 1] = param
			end

			local radius, mass, radiantFlux = self.gameObject:generateStar(unpack(starParamsScratch))
			massSum = massSum + mass
			rSum = rSum + radiantFlux / (consts.tau * 2)
			gSum = gSum + radiantFlux / (consts.tau * 2)
			bSum = bSum + radiantFlux / (consts.tau * 2)
		end
		if starsThisSystem < consts.maxStarsPerSystem then
			starParamInfo[consts.maxStarsPerSystem * consts.starParamCount * i + starsThisSystem * consts.starParamCount] = consts.invalidStarParam
		end
		local otherBodiesMass = 0 -- TODO
		massSum = massSum + otherBodiesMass
		massInfo[i] = massSum

		local r = rSum * radiantIntensityScale
		local g = gSum * radiantIntensityScale
		local b = bSum * radiantIntensityScale
		self:setPoint(chunkBufferIndex, i, x, y, z, r, g ,b)
	end
end

function starSystemPointLayerInfo:generateRemainingCurrentObjectInfo()
	local currentObject = self.currentObject
	self.gameObject:generateStarSystem(currentObject)
end

function game:initPointLayers()
	local loadInfo = self.loadInfo

	self.pointLayers = {}

	self.slowdownSampleDistribution = initSampleDistribution(consts.shapeSlowdownIntegralHighestStepCount, consts.pointLayerShapeTypeAmountIntegralMaxThreads)

	-- Topmost layer is treated specially
	-- TODO: Allow it to collapse to a point when sufficiently far away. Since that's just one point there's no need for optimisations like chunks etc. Would definitely be easier if the topmost point layer has a semi-functioning parent point layer for this purpose
	local topLayer = self:newPointLayer("galaxies", "Galaxies", consts.galaxyLayerChunkSize, consts.maxGalacticDensity, 7, galaxyPointLayerInfo)
	self:newPointLayer("starSystems", "Star Systems", consts.starLayerChunkSize, consts.maxStellarDensity, 13, starSystemPointLayerInfo)

	self.valueNoiseDataReusableForPointLayers = nil -- If no point layers took this then it now no longer will be used

	self:seedCelestialRNG(self:getGlobalCelestialObjectIdNumbers(
		consts.idObjectTypes.universe,
		consts.objectGenerationStages.noiseValues
	))
	topLayer:handleThreadedShapeInit("prepare")
	topLayer:handleThreadedShapeInit("expect")

	local highestMaxPoints
	for _, pointLayer in ipairs(self.pointLayers) do
		self.pointLayers[pointLayer.name] = pointLayer
		highestMaxPoints = highestMaxPoints and math.max(highestMaxPoints, pointLayer.maxPoints) or pointLayer.maxPoints
	end
	if highestMaxPoints then
		self.pointDrawableBuffer = love.graphics.newBuffer(consts.pointDrawableBufferFormat, highestMaxPoints, {
			shaderstorage = true,
			debugname = "Point Drawable Buffer"
		})
	end

	-- Checks

	local topLayerShapeType = self.pointLayerShapeTypes[topLayer.fixedParentObject.shapeTypeName]
	if topLayerShapeType.needsTrueRatio then
		assert(topLayer.fixedParentObject.radii.x == topLayer.fixedParentObject.radii.y,
			"Bad radii for top point layer. x and y must be the same for shape types that have needsTrueRatio. Objects with those shape types can only be lengthened/shortened relative to other axes on the z axis for now. Spheres or oblate/prolate spheroids, no triaxial ellipsoids."
		)
		local xyScale = topLayer.fixedParentObject.radii.x -- x equals y was asserted
		local zScaleRatio = topLayer.fixedParentObject.radii.z / xyScale
		if not (topLayerShapeType.zScaleRatioMin <= zScaleRatio and zScaleRatio <= topLayerShapeType.zScaleRatioMax) then
			error("Top point layer's z scale ratio is " .. zScaleRatio .. " but must be between " .. topLayerShapeType.zScaleRatioMin .. " and " .. topLayerShapeType.zScaleRatioMax)
		end
	end

	for i, pointLayer in ipairs(self.pointLayers) do
		local assertMessage = "All point layers must have shape types and not bodies except the last one"
		if i < #self.pointLayers then
			assert(pointLayer.features.shapeTypeSet and not pointLayer.features.bodies, assertMessage)
		elseif i == #self.pointLayers then
			assert(not pointLayer.features.shapeTypeSet and pointLayer.features.bodies, assertMessage)
		end
	end

	local finalLayer = self.pointLayers[#self.pointLayers]
	local countWeights = finalLayer.features.pointStarCountWeights
	assert(#countWeights == consts.maxStarsPerSystem, "Wrong number of count weights. Must match max stars per system const (" .. consts.maxStarsPerSystem .. ")")
	local totalWeight = 0
	local weightSums = {}
	for i, weight in ipairs(countWeights) do
		totalWeight = totalWeight + weight
		weightSums[i] = totalWeight
	end
	local cumulativeProbability = {}
	for i, weightSum in ipairs(weightSums) do
		cumulativeProbability[i] = weightSum / totalWeight
	end
	finalLayer.features.pointStarCountCumulativeProbability = cumulativeProbability

	local averageStarCountPerPoint = 0
	for i, weight in ipairs(countWeights) do
		averageStarCountPerPoint = averageStarCountPerPoint + i * weight
	end
	averageStarCountPerPoint = averageStarCountPerPoint / totalWeight

	coroutine.yield()
	local axisSamples = consts.starAxisSamples
	loadInfo.starPrecalcSamplesRequired = axisSamples ^ consts.starParamCount
	loadInfo.starPrecalcSamplesDone = 0
	local sumMass = 0
	local sumFluxR = 0
	local sumFluxG = 0
	local sumFluxB = 0
	local count = 0
	for i = 1, axisSamples do
		local param1 = (i - 0.5) / axisSamples
		for j = 1, axisSamples do
			local param2 = (j - 0.5) / axisSamples
			-- for k = 1, axisSamples do
			-- 	local param3 = (k - 0.5) / axisSamples

				local radius, mass, radiantFlux = self:generateStar(param1, param2)--, param3)
				sumMass = sumMass + mass
				sumFluxR = sumFluxR + radiantFlux
				sumFluxG = sumFluxG + radiantFlux
				sumFluxB = sumFluxB + radiantFlux

				count = count + 1
			-- end
		end
		loadInfo.starPrecalcSamplesDone = count
		coroutine.yield()
	end
	-- Here star is used to mean both individual stars and also star system points... sorry.
	local averageOtherBodiesMass = 0 -- TODO
	local starAverageMass = sumMass / count * averageStarCountPerPoint + averageOtherBodiesMass
	local starAverageRadiantIntensityR = sumFluxR / count * averageStarCountPerPoint / (consts.tau * 2)
	local starAverageRadiantIntensityG = sumFluxG / count * averageStarCountPerPoint / (consts.tau * 2)
	local starAverageRadiantIntensityB = sumFluxB / count * averageStarCountPerPoint / (consts.tau * 2)
	loadInfo.starPrecalcSamplesRequired = nil
	loadInfo.starPrecalcSamplesDone = nil
	coroutine.yield()

	-- Radiant fluxes here ignore attenuation
	for i = #self.pointLayers, 1, -1 do
		local pointLayer = self.pointLayers[i]
		if i == #self.pointLayers then
			pointLayer.averageMassPerPoint = starAverageMass
			pointLayer.averageUnattenuatedRadiantIntensityRPerPoint = starAverageRadiantIntensityR
			pointLayer.averageUnattenuatedRadiantIntensityGPerPoint = starAverageRadiantIntensityG
			pointLayer.averageUnattenuatedRadiantIntensityBPerPoint = starAverageRadiantIntensityB
		else
			local childPointLayer = pointLayer.childPointLayer
			local totalWeight = 0
			local averageAmountPreDivide = 0
			for _, shapeTypeInfo in ipairs(pointLayer.features.shapeTypeSet) do
				-- NOTE: If a factor is added to make the distribution of scales non-uniform, ensure that the per-layer average mass estimates are changed accordingly
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name] -- shapeTypeInfo is the point layer's usage of the shape, shapeType is the shape type itself
				local minS, maxS = shapeTypeInfo.scaleMin, shapeTypeInfo.scaleMax
				local minZR, maxZR = shapeType.zScaleRatioMin, shapeType.zScaleRatioMax
				local averageBaseObjectAmountMultiplier = (minS + maxS) * (minS ^ 2 + maxS ^ 2) / 4

				local total = 0
				assert(not shapeType.attenuation, "Attenuation shape types cannot be used for point density")
				for samplingId = 0, shapeType.sampleCount - 1 do
					local sample
					if shapeType.needsTrueRatio then
						sample = 0
						for zSample = 0, shapeType.zScaleRatioSamples - 1 do
							local zScaleRatio = shapeType.zScaleRatioMin + zSample / (shapeType.zScaleRatioSamples - 1) * (shapeType.zScaleRatioMax - shapeType.zScaleRatioMin)
							sample = sample + shapeType.sampleBaseObjectAmounts[samplingId][zSample] * zScaleRatio
						end
					else
						sample = shapeType.sampleBaseObjectAmounts[samplingId] * (minZR + maxZR) / 2
					end
					total = total +
						sample *
						averageBaseObjectAmountMultiplier *
						childPointLayer.maxPointDensity
				end
				local countMultiplier = shapeType.needsTrueRatio and shapeType.zScaleRatioSamples or 1
				local countThisShapeInfo = shapeType.sampleCount * countMultiplier
				local averageAmountThisShapeTypeInfo = total / countThisShapeInfo

				averageAmountPreDivide = averageAmountPreDivide + averageAmountThisShapeTypeInfo * shapeTypeInfo.weight
				totalWeight = totalWeight + shapeTypeInfo.weight
			end
			local averageAmount = averageAmountPreDivide / totalWeight
			pointLayer.averageMassPerPoint = averageAmount * childPointLayer.averageMassPerPoint
			pointLayer.averageUnattenuatedRadiantIntensityRPerPoint = averageAmount * childPointLayer.averageUnattenuatedRadiantIntensityRPerPoint
			pointLayer.averageUnattenuatedRadiantIntensityGPerPoint = averageAmount * childPointLayer.averageUnattenuatedRadiantIntensityGPerPoint
			pointLayer.averageUnattenuatedRadiantIntensityBPerPoint = averageAmount * childPointLayer.averageUnattenuatedRadiantIntensityBPerPoint
		end
	end

	self:getPointLayerIntensities()

	-- Ensure no objects could be too big for the celestal id system to work on its contained points or to smoothly transition between resolvable and unresolved
	for i = 1, #self.pointLayers do
		local layer = self.pointLayers[i]
		if not layer.features.shapeTypeSet then
			goto continue
		end
		for j, shapeTypeInfo in ipairs(layer.features.shapeTypeSet) do
			local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
			local identifier = "point layer " .. i .. ", shape type info " .. j
			assert(shapeTypeInfo.scaleMin <= shapeTypeInfo.scaleMax, "Scale min and max are flipped for " .. identifier)
			local largestX = shapeTypeInfo.scaleMax
			local largestY = shapeTypeInfo.scaleMax
			local largestZ = shapeTypeInfo.scaleMax * shapeType.zScaleRatioMax
			local minX, maxX, minY, maxY, minZ, maxZ = getBoundingBoxChunksForSize(layer.chunkSize, largestX, largestY, largestZ)
			local widthChunks = maxX - minX + 1
			local heightChunks = maxY - minY + 1
			local depthChunks = maxZ - minZ + 1
			local largestChunkCount = widthChunks * heightChunks * depthChunks
			local maximumChunks = 2 ^ 36
			if largestChunkCount >= maximumChunks then -- 36 bits as per getGlobalCelestialObjectIdNumbers
				error("Too many chunks possible for " .. identifier .. ". Must be at most " .. maximumChunks)
			end

			local maxAllowedResolvableDistance = layer.chunkSize * consts.pointMinDistanceInChunk / 2 / consts.pointAsyncSetupDistanceMultiplier
			local maxAllowedRadius = self:getSphereRadiusFromResolvableDistance(maxAllowedResolvableDistance)
			local largestRadius = math.max(largestX, largestY, largestZ)
			-- local largestResolvableDistance = self:getSphereResolvableDistance(largestRadius)
			if largestRadius > maxAllowedRadius then
				error("Maximum size of " .. identifier .. " (" .. largestRadius .. ") is too high, must be at most " .. maxAllowedRadius)
			end
		end
	    ::continue::
	end
	-- TODO: Check universe size too (but really it should be its own point layer that only ever has one point?)
end

local pointLayerFunctions = {}

function pointLayerFunctions:getDensity(realX, realY, realZ) -- The position is in units where 1 is the side length of a chunk. Returned density is a proportion from 0 to 1, where 1 is the point layer's max density
	-- Position must be already in the object's own local reference frame (i.e. rotated by orientation)
	local currentObject
	if self.parentPointLayer then
		currentObject = self.parentPointLayer.currentObject
		assert(currentObject, "Should not be calling getDensity on a point layer if its parent doesn't have a current object")
	else
		currentObject = self.fixedParentObject
	end
	local shapeTypeName = currentObject.shapeTypeName
	local shapeSubtypeId = currentObject.shapeSubtypeId
	local size = currentObject.radii

	local shapeType = self.gameObject.pointLayerShapeTypes[shapeTypeName]
	local densityFunction = shapeType.getDensity
	local densityParametersScratchTable = self.gameObject:decodeShapeSubtypeIntoScratchTable(shapeType, shapeSubtypeId)
	self:prepareValueNoiseFunction()
	if shapeType.needsTrueRatio then
		local sizeRatios = size / math.max(size.x, size.y, size.z)
		local x = realX / size.x * self.chunkSize
		local y = realY / size.y * self.chunkSize
		local z = realZ / size.z * self.chunkSize
		return densityFunction(
			x, y, z,
			x * sizeRatios.x, y * sizeRatios.y, z * sizeRatios.z,
			unpack(densityParametersScratchTable)
		)
	else
		return densityFunction(
			realX / size.x * self.chunkSize,
			realY / size.y * self.chunkSize,
			realZ / size.z * self.chunkSize,
			unpack(densityParametersScratchTable)
		)
	end
end

-- Expects RNG to be seeded appropriately
function pointLayerFunctions:randomiseValueNoise(type)
	local suffix = type == "attenuation" and "Attenuation" or type == "emission" and "Emission"
	local relevantShapeTypeName
	if type == "emission" then
		relevantShapeTypeName =
			(self.parentPointLayer and (
				self.parentPointLayer.currentObject or
				self.parentPointLayer.currentPotentialObject
			) or self.fixedParentObject).shapeTypeName
	elseif type == "attenuation" then
		relevantShapeTypeName =
			(self.parentPointLayer and (
				self.parentPointLayer.currentObject or
				self.parentPointLayer.currentPotentialObject
			) or self.fixedParentObject).attenuationShapeTypeName
	end
	if not relevantShapeTypeName then
		return
	end
	local shapeType = self.gameObject.pointLayerShapeTypes[relevantShapeTypeName]
	if not shapeType.noiseInfo then
		-- Won't be used, can safely leave it as it is
		return
	end
	-- This layer will have a noise buffer/data if its parent can have a shape type that has noise.
	self:randomiseValueNoiseCore(suffix, shapeType.noiseInfo.requiredValueCount)
end
function pointLayerFunctions:randomiseValueNoiseCore(suffix, count)
	local buffer = self["valueNoiseBuffer" .. suffix]
	local data = self["valueNoiseData" .. suffix]
	local dataFFI = self["valueNoiseDataFFI" .. suffix]
	for i = 0, count - 1 do
		dataFFI[i] = self.gameObject:celestialRandom()
	end
	buffer:setArrayData(data, 1, 1, count)
end

function pointLayerFunctions:prepareValueNoiseFunction() -- This is per shape type, so in case multiple layers use the same shape type this must be set before every use of the density function
	-- For point density (emission) only, not for attenuation
	local relevantShapeTypeName =
		self.parentPointLayer and self.parentPointLayer.currentObject.shapeTypeName
		or self.fixedParentObject.shapeTypeName
	local shapeType = self.gameObject.pointLayerShapeTypes[relevantShapeTypeName]
	if not shapeType.noiseInfo then
		return
	end
	local layers = shapeType.noiseInfo.layers
	local dataFFI = self.valueNoiseDataFFIEmission
	setValueNoiseFunctionVars(layers, dataFFI)
end

function pointLayerFunctions:getBoundingBoxChunks()
	local size
	if self.parentPointLayer then
		local currentObject = self.parentPointLayer.currentObject
		assert(currentObject, "Should not be calling getBoundingBoxChunks on a point layer if its parent doesn't have a current object")
		size = currentObject.radii
	else
		size = self.fixedParentObject.radii
	end
	return getBoundingBoxChunksForSize(self.chunkSize, mathsies.vec3.components(size))
end

function pointLayerFunctions:setChunkPointCount(chunkBufferIndex, count)
	self.chunkPointCountDataFFI[chunkBufferIndex] = count
end

function pointLayerFunctions:getChunkPointCount(chunkBufferIndex)
	return self.chunkPointCountDataFFI[chunkBufferIndex]
end

function pointLayerFunctions:setPoint(chunkBufferIndex, pointId, ...) -- First two args start at 0.
	local index = chunkBufferIndex * self.maxPointsPerChunk + pointId
	assert(index >= 0 and index < self.maxPoints, "chunkBufferIndex and pointId given to setPoint exceed point buffer capacity")
	assert(select("#", ...) == self.pointFormatVarCount, "Incorrect number of point variables given to setPoint")
	local curAddr = index * self.pointBuffer:getElementStride() / consts.bytesPerGPUVar
	for i = 1, self.pointFormatVarCount do
		local property = select(i, ...)
		self.ffiDataTypeFromPointVarIndex[i - 1][curAddr + self.pointDataIndexMap[i - 1]] = property -- Casts from double to float
	end
end

function pointLayerFunctions:getPointVars(chunkBufferIndex, pointId, name, type, count)
	local index = chunkBufferIndex * self.maxPointsPerChunk + pointId
	assert(index >= 0 and index < self.maxPoints, "chunkBufferIndex and pointId given to setPoint exceed point buffer capacity")
	local index = index * self.pointBuffer:getElementStride() / consts.bytesPerGPUVar
	local index = index + self.pointFormatOffsets[name]

	local ffiData =
		type == "float" and self.pointDataFFIFloat or
		type == "int32" and self.pointDataFFIInt or
		type == "uint32" and self.pointDataFFIUint

	if count == 1 or not count then
		return ffiData[index]
	elseif count == 2 then
		return ffiData[index], ffiData[index + 1]
	elseif count == 3 then
		return ffiData[index], ffiData[index + 1], ffiData[index + 2]
	elseif count == 4 then
		return ffiData[index], ffiData[index + 1], ffiData[index + 2], ffiData[index + 3]
	else
		error("Invalid count " .. count .. " to getPointVars")
	end
end

function pointLayerFunctions:generateChunkCommon(realX, realY, realZ, chunkId, chunkBufferIndex)
	self.gameObject:seedCelestialRNG(self.gameObject:getGlobalCelestialObjectIdNumbers(
		self:getGlobalCelestialObjectIdParameters(consts.objectGenerationStages.main, chunkId)
	))

	local density = self:getDensity(
		-- Density is sampled in middle of chunk
		realX + 0.5,
		realY + 0.5,
		realZ + 0.5
	)
	local amount = density * self.maxPointDensity * self.chunkVolume
	local count = math.floor(amount)
	if self.gameObject:celestialRandom() < amount % 1 then -- Use fractional part of amount as a probability
		count = count + 1
	end
	count = math.min(self.maxPointsPerChunk, count) -- Just in case

	self:generateChunk(realX, realY, realZ, chunkId, chunkBufferIndex, count) -- Specified per layer

	self:setChunkPointCount(chunkBufferIndex, count)
	if count > 0 then
		local pointIdStart = chunkBufferIndex * self.maxPointsPerChunk
		self.pointBuffer:setArrayData(self.pointData, pointIdStart + 1, pointIdStart + 1, count)
	end
end

function pointLayerFunctions:setChunkEmpty(chunkBufferIndex)
	local chunk = self.chunkExtraInfo[chunkBufferIndex]
	chunk.x = nil
	chunk.y = nil
	chunk.z = nil
	self:setChunkPointCount(chunkBufferIndex, 0)
end

function pointLayerFunctions:getClosestPointIn2x2x2(positionRelative)
	local closestChunkX
	local closestChunkY
	local closestChunkZ
	local closestIdInChunk
	local closestDistance = math.huge

	local temp = mathsies.vec3() -- No need to generate tons of new vec3s
	for x = math.floor(positionRelative.x - 0.5), math.floor(positionRelative.x + 0.5) do
		for y = math.floor(positionRelative.y - 0.5), math.floor(positionRelative.y + 0.5) do
			for z = math.floor(positionRelative.z - 0.5), math.floor(positionRelative.z + 0.5) do
				local xInChunkBuffer = x % self.chunkBufferSideLength
				local yInChunkBuffer = y % self.chunkBufferSideLength
				local zInChunkBuffer = z % self.chunkBufferSideLength
				local chunkBufferIndex = xInChunkBuffer + yInChunkBuffer * self.chunkBufferSideLength + zInChunkBuffer * self.chunkBufferSideLength * self.chunkBufferSideLength
				local chunkExtraInfo = self.chunkExtraInfo[chunkBufferIndex]
				if not (
					chunkExtraInfo.x == x and
					chunkExtraInfo.y == y and
					chunkExtraInfo.z == z
				) then
					goto continue
				end
				for pointId = 0, self:getChunkPointCount(chunkBufferIndex) - 1 do
					temp.x, temp.y, temp.z = self:getPointVars(chunkBufferIndex, pointId, "position", "float", 3)
					temp.x = temp.x + x
					temp.y = temp.y + y
					temp.z = temp.z + z
					local distance = mathsies.vec3.distance(positionRelative, temp)
					if distance < closestDistance then
						closestChunkX = x
						closestChunkY = y
						closestChunkZ = z
						closestIdInChunk = pointId
						closestDistance = distance
					end
				end
				::continue::
			end
		end
	end

	return closestChunkX, closestChunkY, closestChunkZ, closestIdInChunk, closestDistance
end

-- Actions are "prepare" (when near to an object but not close enough to need the results yet),
-- "expect" (when the results are needed), and
-- "cancel" (when there is no longer an object nearby or the point layer is not active)
-- RNG should be be seeded appropriately for value noise if action == "prepare".
-- action being prepare or expect means the the other two arguments are needed.
function pointLayerFunctions:handleThreadedShapeInit(action)
	if action == "prepare" then
		if self.threadedShapeInitWorkInfo then
			if not self.threadedShapeInitWorkInfo.completed then -- Not strictly necessary since the result is also popped on expect (or cleared on cancel). But if completion status is needed pre-expect, then this code would help.
				local result = love.thread.getChannel("shapeAmountDataStageManagerResult" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):pop()
				if not result then
					self.gameObject:checkThreadsForErrors()
				else
					self.threadedShapeInitWorkInfo.completed = true
				end
			end
			return
		end

		self:randomiseValueNoise("emission")
		self:randomiseValueNoise("attenuation")

		self.threadedShapeInitWorkInfo = {
			completed = false,
			resultChannelSuffix = "Layer" .. self.index
		}

		local currentObject
		if self.parentPointLayer then
			currentObject = self.parentPointLayer.currentObject or self.parentPointLayer.currentPotentialObject
		else
			currentObject = self.fixedParentObject
		end
		local shapeTypeName = currentObject.shapeTypeName
		local shapeSubtypeId = currentObject.shapeSubtypeId
		local radii = currentObject.radii

		local shapeType = self.gameObject.pointLayerShapeTypes[shapeTypeName]
		local scratch = self.gameObject:decodeShapeSubtypeIntoScratchTable(shapeType, shapeSubtypeId)

		local scaledRadii = radii / math.max(radii.x, radii.y, radii.z)
		local infoTable = {
			shapeTypeId = shapeType.id,
			params = scratch,
			valueNoiseData = self.valueNoiseDataEmission,
			type = "massWrite",
			shapeMassData = self.shapeMassData,
			massDataStartOffsets = consts.shapeSlowdownIntegralDataStarts,
			resultChannelSuffix = self.threadedShapeInitWorkInfo.resultChannelSuffix,
			ratioX = shapeType.needsTrueRatio and scaledRadii.x,
			ratioY = shapeType.needsTrueRatio and scaledRadii.y,
			ratioZ = shapeType.needsTrueRatio and scaledRadii.z
		}
		love.thread.getChannel("shapeAmountDataStageManagerInfo"):push(infoTable)
	elseif action == "expect" then
		-- Ideally we want it to be finished by the time we get here, due to the time it takes to fly up to a galaxy
		if self.threadedShapeInitWorkInfo and not self.threadedShapeInitWorkInfo.completed then
			local result
			while not result do
				result = love.thread.getChannel("shapeAmountDataStageManagerResult" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):demand(consts.shapeIntegralThreadTimeout)
				if not result then
					self.gameObject:checkThreadsForErrors()
				end
			end
			self.threadedShapeInitWorkInfo.completed = true
		end
	elseif action == "cancel" then
		if self.threadedShapeInitWorkInfo and not self.threadedShapeInitWorkInfo.completed then
			love.thread.getChannel("shapeAmountDataStageManagerCancel" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):supply("cancel") -- TODO: Timeout

			love.thread.getChannel("shapeAmountDataStageManagerInfo" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):clear() -- This clear shouldn't be necessary
			love.thread.getChannel("shapeAmountDataStageManagerResult" .. self.threadedShapeInitWorkInfo.resultChannelSuffix):clear() -- This one might be sometimes
		end
		self.threadedShapeInitWorkInfo = nil
	else
		error("Unknown handleThreadedShapeInit action " .. action)
	end
end

local paramScratch = {}
function pointLayerFunctions:getGlobalCelestialObjectIdParameters(stage, thisLayerCurrentObject)
	table.clear(paramScratch)

	local objectType = consts.idObjectTypes[
		type(thisLayerCurrentObject) == "number" and self.chunkObjectType or self.pointObjectType
	]
	for _, pointLayer in ipairs(self.gameObject.pointLayers) do
		if pointLayer == self then
			break
		end
		table.insert(paramScratch, pointLayer.currentObject.chunkId)
		table.insert(paramScratch, pointLayer.currentObject.pointId)
	end
	if type(thisLayerCurrentObject) == "number" then
		table.insert(paramScratch, thisLayerCurrentObject)
	else
		table.insert(paramScratch, thisLayerCurrentObject.chunkId)
		table.insert(paramScratch, thisLayerCurrentObject.pointId)
	end
	return objectType, stage, unpack(paramScratch)
end

function game:clearPointLayers(startIndex)
	for i = startIndex, #self.pointLayers do
		local pointLayer = self.pointLayers[i]
		pointLayer.currentObject = nil
		if pointLayer.parentPointLayer and not pointLayer.parentPointLayer.currentPotentialObject then
			pointLayer:handleThreadedShapeInit("cancel")
		end
		pointLayer.currentPotentialObject = nil
	end
end

---@param name string
---@param debugName string
---@param chunkSize number
---@param maxPointDensity number
---@param chunkBufferSideLength number
---@param layerInfo table<string, any>
function game:newPointLayer(name, debugName, chunkSize, maxPointDensity, chunkBufferSideLength, layerInfo)
	local new = {}

	for k, v in pairs(pointLayerFunctions) do
		new[k] = v
	end
	for k, v in pairs(layerInfo) do -- Should include features
		new[k] = v
	end

	new.parentPointLayer = self.pointLayers[#self.pointLayers]
	if new.parentPointLayer then
		new.parentPointLayer.childPointLayer = new
	end
	table.insert(self.pointLayers, new)
	new.index = #self.pointLayers
	new.gameObject = self -- HACK...

	new.name = name
	new.debugName = debugName
	new.chunkSize = chunkSize
	new.maxPointDensity = maxPointDensity
	new.chunkBufferSideLength = chunkBufferSideLength

	new.chunkVolume = chunkSize ^ 3
	new.chunkBufferTotalSize = chunkBufferSideLength ^ 3
	new.maxPointsPerChunk = math.ceil(new.chunkVolume * new.maxPointDensity)
	new.maxPoints = new.chunkBufferTotalSize * new.maxPointsPerChunk

	-- Add features to the following two tables
	new.pointBufferFormat = {}
	local defines = {
		THREADGROUP_SIZE = consts.pointPreparationThreadgroupSize,
		POINT_COUNT = new.maxPoints
	}
	local unsentFeatureNames = {}
	local function tryFeature(name, format, defineName, forcePresence, disallowSending)
		local presence = forcePresence or layerInfo.features[name]
		if not presence then
			return
		end

		if disallowSending then
			assert(presence == "unsent", "\"" .. name .. "\" feature cannot be \"sent\"")
		end

		assert(presence == "sent" or presence == "unsent", "\"" .. name .. "\" feature must be either \"sent\" to GPU or \"unsent\", \"" .. presence .. "\" is invalid")

		if presence == "sent" then
			table.insert(new.pointBufferFormat, {name = name, format = format})
			if defineName then
				defines["FEATURE_" .. defineName] = true
			end
		elseif presence == "unsent" then
			unsentFeatureNames[name] = true -- For use in chunk extra data
		end
	end
	tryFeature("position", "floatvec3", "POSITION", "sent")
	tryFeature("radiantIntensity", "floatvec3", "RADIANT_INTENSITY", "sent")
	tryFeature("shapeTypeSubtypeIds", "uint32vec2", "SHAPE_TYPE_SUBTYPE")
	tryFeature("attenuationShapeTypeSubtypeIds", "uint32vec2", "ATTENUATION_SHAPE_TYPE_SUBTYPE")
	tryFeature("attenuationMultiplier", "float", "ATTENUATION_MULTIPLIER")
	tryFeature("radii", "floatvec3", "RADII")
	tryFeature("orientation", "floatvec4", "ORIENTATION")
	tryFeature("mass", "float", "MASS")
	tryFeature("starParams", nil, nil, nil, true)

	new.pointBuffer = love.graphics.newBuffer(new.pointBufferFormat, new.maxPoints, {
		shaderstorage = true,
		debugname = debugName .. " Points"
	})

	assert((new.pointBuffer:getElementStride() / consts.bytesPerGPUVar) % 1 == 0, "Something has gone terribly wrong!")

	new.pointData = love.data.newByteData(new.pointBuffer:getElementStride() * new.maxPoints)
	new.pointDataFFIFloat = ffi.cast("float*", new.pointData:getFFIPointer())
	new.pointDataFFIInt = ffi.cast("int32_t*", new.pointData:getFFIPointer())
	new.pointDataFFIUint = ffi.cast("uint32_t*", new.pointData:getFFIPointer())

	new.pointFormatVarCount = 0 -- Considers vec3 as 3 variables etc
	new.ffiDataTypeFromPointVarIndex = {} -- Determines how to interpret each number
	new.pointFormatOffsets = {} -- Maps the start of a variable (float, vec3, etc) to its offset in the FFI data array(s)
	new.pointDataIndexMap = {}
	local dataTypeMap = {
		float = new.pointDataFFIFloat,
		int32 = new.pointDataFFIInt,
		uint32 = new.pointDataFFIUint
	}
	for _, variable in ipairs(new.pointBuffer:getFormat()) do
		local num, type
		if variable.format == "float" or variable.format == "int32" or variable.format == "uint32" then
			num = 1
			type = variable.format
		else
			local _, _, typeString, numString = variable.format:find("^(.*)vec([0-9]*)$")
			type = typeString
			num = numString and tonumber(numString) or 1
		end
		new.pointFormatOffsets[variable.name] = variable.offset / consts.bytesPerGPUVar
		for i = 0, num - 1 do
			new.pointDataIndexMap[new.pointFormatVarCount] = variable.offset / consts.bytesPerGPUVar + i
			new.ffiDataTypeFromPointVarIndex[new.pointFormatVarCount] = dataTypeMap[type]
			new.pointFormatVarCount = new.pointFormatVarCount + 1
		end
	end

	new.pointPreparationShader = love.graphics.newComputeShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/points.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/pointPreparation.glsl"),
		{
			defines = defines
		}
	)

	new.chunkPointCountBuffer = love.graphics.newBuffer(consts.intBufferFormat, new.chunkBufferTotalSize, {
		shaderstorage = true,
		debugname = debugName .. " Chunk Point Counts"
	})
	new.chunkPointCountData = love.data.newByteData(new.chunkPointCountBuffer:getElementStride() * new.chunkBufferTotalSize)
	new.chunkPointCountDataFFI = ffi.cast("int32_t*", new.chunkPointCountData:getFFIPointer())

	local maxNoiseValuesEmission = 0
	local maxNoiseValuesAttenuation = 0
	local hasNoiseEmission = false
	local hasNoiseAttenuation = false
	local relevantShapeTypeSet = new.parentPointLayer and new.parentPointLayer.features.shapeTypeSet
	if not relevantShapeTypeSet then
		assert(new.index == 1, "Only the top layer should not have a parent layer")
		local shapeType = self.pointLayerShapeTypes[new.fixedParentObject.shapeTypeName]
		if shapeType.noiseInfo then
			hasNoiseEmission = true
			maxNoiseValuesEmission = math.max(maxNoiseValuesEmission, shapeType.noiseInfo.requiredValueCount)
		end

		local shapeType = self.pointLayerShapeTypes[new.fixedParentObject.attenuationShapeTypeName]
		if shapeType and shapeType.noiseInfo then
			hasNoiseAttenuation = true
			maxNoiseValuesAttenuation = math.max(maxNoiseValuesAttenuation, shapeType.noiseInfo.requiredValueCount)
		end
	else
		for _, shapeTypeInfo in ipairs(relevantShapeTypeSet) do
			local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
			if shapeType.noiseInfo then
				hasNoiseEmission = true
				maxNoiseValuesEmission = math.max(maxNoiseValuesEmission, shapeType.noiseInfo.requiredValueCount)
			end
			if not shapeTypeInfo.attenuationShapeTypes then
				goto continue
			end
			for _, shapeTypeInfo in ipairs(shapeTypeInfo.attenuationShapeTypes) do
				local shapeType = self.pointLayerShapeTypes[shapeTypeInfo.name]
				if shapeType.noiseInfo then
					hasNoiseAttenuation = true
					maxNoiseValuesAttenuation = math.max(maxNoiseValuesAttenuation, shapeType.noiseInfo.requiredValueCount)
				end
			end
			::continue::
		end
	end
	new.hasNoiseAttenuation = hasNoiseAttenuation
	new.hasNoiseEmission = hasNoiseEmission
	local function addNoiseData(type, maxNoiseValues)
		local capitalised = type == "emission" and "Emission" or type == "attenuation" and "Attenuation"
		new["maxNoiseValues" .. capitalised] = maxNoiseValues

		new["valueNoiseBuffer" .. capitalised] = love.graphics.newBuffer(consts.floatBufferFormat, new["maxNoiseValues" .. capitalised], {
			shaderstorage = true,
			debugname = debugName .. " " .. capitalised .. " Noise Values"
		})
		local requiredSize = new["valueNoiseBuffer" .. capitalised]:getElementStride() * new["maxNoiseValues" .. capitalised]
		if
			self.valueNoiseDataReusableForPointLayers and
			self.valueNoiseDataReusableForPointLayers:getSize() == requiredSize
		then
			new["valueNoiseData" .. capitalised] = self.valueNoiseDataReusableForPointLayers
			self.valueNoiseDataReusableForPointLayers = nil
		else
			new["valueNoiseData" .. capitalised] = love.data.newByteData(requiredSize)
		end
		new["valueNoiseDataFFI" .. capitalised] = ffi.cast("float*", new["valueNoiseData" .. capitalised]:getFFIPointer())
	end
	if hasNoiseAttenuation then
		addNoiseData("attenuation", maxNoiseValuesAttenuation)
	end
	if hasNoiseEmission then
		addNoiseData("emission", maxNoiseValuesEmission)
	end

	new.chunkExtraInfo = {}
	for x = 0, new.chunkBufferSideLength - 1 do
		for y = 0, new.chunkBufferSideLength - 1 do
			for z = 0, new.chunkBufferSideLength - 1 do
				local extraInfo = {
					x = nil,
					y = nil,
					z = nil
				}
				for name in pairs(unsentFeatureNames) do
					extraInfo[name] = {}
				end
				local chunkBufferIndex = x + y * new.chunkBufferSideLength + z * new.chunkBufferSideLength * new.chunkBufferSideLength
				new.chunkExtraInfo[chunkBufferIndex] = extraInfo
			end
		end
	end

	local bytesPerFloat = 4
	new.shapeMassData = love.data.newByteData(bytesPerFloat * consts.shapeSlowdownIntegralDataCount)
	new.shapeMassDataFFI = ffi.cast("float*", new.shapeMassData:getFFIPointer())

	-- volumetricCanvas and volumetricAddCountCanvas are added after initPointLayers in resizeGameScreen (called by initCelestial)

	return new
end

function game:finishHandlingPointLayers(pointLayer)
	pointLayer.currentObject = nil
	self:clearPointLayers(pointLayer.index + 1)
end

function game:handlePointLayers()
	local remakeAll = false
	for pointLayerIndex, pointLayer in ipairs(self.pointLayers) do
		local updateChunkCountBuffer = false

		local parentOrigin, parentOrientation
		if not pointLayer.parentPointLayer then
			parentOrigin = pointLayer.fixedParentObject.position
			parentOrientation = pointLayer.fixedParentObject.orientation
		else
			assert(pointLayer.parentPointLayer.currentObject, "handlePointLayers loop has run into a point layer that shouldn't be being handled")
			parentOrigin = pointLayer.parentPointLayer.currentObject.position
			parentOrientation = pointLayer.parentPointLayer.currentObject.orientation
		end
		local positionRelative = mathsies.vec3.rotate(bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
			(self.ship.position - parentOrigin) / pointLayer.chunkSize
		), parentOrientation)

		local minX, maxX, minY, maxY, minZ, maxZ = pointLayer:getBoundingBoxChunks()
		local widthChunks = maxX - minX + 1
		local heightChunks = maxY - minY + 1
		local depthChunks = maxZ - minZ + 1

		local chunkBufferStartRealX = math.floor((positionRelative.x - pointLayer.chunkBufferSideLength / 2) / pointLayer.chunkBufferSideLength) * pointLayer.chunkBufferSideLength
		local chunkBufferStartRealY = math.floor((positionRelative.y - pointLayer.chunkBufferSideLength / 2) / pointLayer.chunkBufferSideLength) * pointLayer.chunkBufferSideLength
		local chunkBufferStartRealZ = math.floor((positionRelative.z - pointLayer.chunkBufferSideLength / 2) / pointLayer.chunkBufferSideLength) * pointLayer.chunkBufferSideLength

		local viewMinXInChunkBuffer = (positionRelative.x - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength
		local viewMinYInChunkBuffer = (positionRelative.y - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength
		local viewMinZInChunkBuffer = (positionRelative.z - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength

		for x = 0, pointLayer.chunkBufferSideLength - 1 do
			for y = 0, pointLayer.chunkBufferSideLength - 1 do
				for z = 0, pointLayer.chunkBufferSideLength - 1 do
					local realX = x + chunkBufferStartRealX + (x + 0.5 < viewMinXInChunkBuffer and pointLayer.chunkBufferSideLength or 0)
					local realY = y + chunkBufferStartRealY + (y + 0.5 < viewMinYInChunkBuffer and pointLayer.chunkBufferSideLength or 0)
					local realZ = z + chunkBufferStartRealZ + (z + 0.5 < viewMinZInChunkBuffer and pointLayer.chunkBufferSideLength or 0)

					local chunkBufferIndex = x + y * pointLayer.chunkBufferSideLength + z * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength

					local currentChunk = pointLayer.chunkExtraInfo[chunkBufferIndex]
					if
						remakeAll or
						currentChunk.x ~= realX or
						currentChunk.y ~= realY or
						currentChunk.z ~= realZ
					then
						currentChunk.x = realX
						currentChunk.y = realY
						currentChunk.z = realZ
						updateChunkCountBuffer = true

						if
							minX <= realX and realX <= maxX and
							minY <= realY and realY <= maxY and
							minZ <= realZ and realZ <= maxZ
						then
							local x2, y2, z2 = realX - minX, realY - minY, realZ - minZ
							local chunkId = x2 + y2 * widthChunks + z2 * widthChunks * heightChunks

							pointLayer:generateChunkCommon(realX, realY, realZ, chunkId, chunkBufferIndex, x, y, z)
						else
							pointLayer:setChunkEmpty(chunkBufferIndex)
						end
					end
				end
			end
		end

		if updateChunkCountBuffer then
			pointLayer.chunkPointCountBuffer:setArrayData(pointLayer.chunkPointCountData, 1, 1, pointLayer.chunkBufferTotalSize)
		end

		if not pointLayer.parentPointLayer then
			if
				math.abs(positionRelative.x) > widthChunks + pointLayer.chunkBufferSideLength / 2 or
				math.abs(positionRelative.y) > heightChunks + pointLayer.chunkBufferSideLength / 2 or
				math.abs(positionRelative.z) > depthChunks + pointLayer.chunkBufferSideLength / 2
			then
				pointLayer.topLayerOutOfRange = true
				pointLayer.currentObject = nil
				pointLayer.currentPotentialObject = nil
				self:clearPointLayers(pointLayerIndex + 1)
				break
			else
				pointLayer.topLayerOutOfRange = false
			end
		end
		local closestChunkX, closestChunkY, closestChunkZ, closestIdInChunk, closestDistance = pointLayer:getClosestPointIn2x2x2(positionRelative)
		if closestIdInChunk and closestDistance < consts.pointMinDistanceInChunk / 2 then
			local x2, y2, z2 = closestChunkX - minX, closestChunkY - minY, closestChunkZ - minZ
			local chunkId = x2 + y2 * widthChunks + z2 * widthChunks * heightChunks

			local chunkBufferX = closestChunkX % pointLayer.chunkBufferSideLength
			local chunkBufferY = closestChunkY % pointLayer.chunkBufferSideLength
			local chunkBufferZ = closestChunkZ % pointLayer.chunkBufferSideLength
			local chunkBufferIndex = chunkBufferX + chunkBufferY * pointLayer.chunkBufferSideLength + chunkBufferZ * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength

			local chunkExtraInfo = pointLayer.chunkExtraInfo[chunkBufferIndex]

			-- Some early feature getting
			local shapeTypeId, shapeSubtypeId
			if pointLayer.features.shapeTypeSubtypeIds then
				if pointLayer.features.shapeTypeSubtypeIds == "sent" then
					shapeTypeId, shapeSubtypeId = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "shapeTypeSubtypeIds", "uint32", 2)
				elseif pointLayer.features.shapeTypeSubtypeIds == "unsent" then
					shapeTypeId, shapeSubtypeId = chunkExtraInfo.shapeTypeSubtypeIds[closestIdInChunk * 2], chunkExtraInfo.shapeTypeSubtypeIds[closestIdInChunk * 2 + 1]
				end
			end
			local xRadius, yRadius, zRadius
			if pointLayer.features.radii == "sent" then
				xRadius, yRadius, zRadius = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "radii", "float", 3)
			elseif pointLayer.features.radii == "unsent" then
				xRadius = chunkExtraInfo.radii[closestIdInChunk * 3]
				yRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 1]
				zRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 2]
			end
			local attenuationShapeTypeName, attenuationShapeSubtypeId
			if pointLayer.features.attenuationShapeTypeSubtypeIds then
				local attenuationShapeTypeId
				if pointLayer.features.attenuationShapeTypeSubtypeIds == "sent" then
					attenuationShapeTypeId, attenuationShapeSubtypeId = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "attenuationShapeTypeSubtypeIds", "uint32", 2)
				elseif pointLayer.features.attenuationShapeTypeSubtypeIds == "unsent" then
					attenuationShapeTypeId, attenuationShapeSubtypeId = chunkExtraInfo.attenuationShapeTypeSubtypeIds[closestIdInChunk * 2], chunkExtraInfo.attenuationShapeTypeSubtypeIds[closestIdInChunk * 2 + 1]
				end
				attenuationShapeTypeName = self.pointLayerShapeTypes[attenuationShapeTypeId].name
			end

			if pointLayer.childPointLayer then
				if
					pointLayer.currentPotentialObject and
					(
						pointLayer.currentPotentialObject.chunkId ~= chunkId or
						pointLayer.currentPotentialObject.pointId ~= closestIdInChunk
					)
				then
					pointLayer.currentPotentialObject = nil
					pointLayer.childPointLayer:handleThreadedShapeInit("cancel")
				end

				pointLayer.currentPotentialObject = pointLayer.currentPotentialObject or {
					chunkId = chunkId,
					pointId = closestIdInChunk,
					chunkBufferIndex = chunkBufferIndex,

					chunkX = closestChunkX,
					chunkY = closestChunkY,
					chunkZ = closestChunkZ,

					shapeTypeName = self.pointLayerShapeTypes[shapeTypeId].name,
					shapeSubtypeId = shapeSubtypeId,
					radii = xRadius and mathsies.vec3(xRadius, yRadius, zRadius) or nil,

					attenuationShapeTypeName = attenuationShapeTypeName,
					attenuationShapeSubtypeId = attenuationShapeSubtypeId
				}
				self:seedCelestialRNG(self:getGlobalCelestialObjectIdNumbers(
					pointLayer:getGlobalCelestialObjectIdParameters(consts.objectGenerationStages.noiseValues, pointLayer.currentPotentialObject)
				))
				pointLayer.childPointLayer:handleThreadedShapeInit("prepare")
			end

			local resolvable
			if not pointLayer.features.radii then
				resolvable = true
			else
				if pointLayer.features.radii == "sent" then
					xRadius, yRadius, zRadius = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "radii", "float", 3)
				elseif pointLayer.features.radii == "unsent" then
					xRadius = chunkExtraInfo.radii[closestIdInChunk * 3]
					yRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 1]
					zRadius = chunkExtraInfo.radii[closestIdInChunk * 3 + 2]
				end
				assert(xRadius and yRadius and zRadius, "Missing radii")
				local maxRadius = math.max(xRadius, yRadius, zRadius)
				local trueDistance = pointLayer.chunkSize * closestDistance
				resolvable = trueDistance <= self:getSphereResolvableDistance(maxRadius)
			end

			if not resolvable then
				self:finishHandlingPointLayers(pointLayer)
				break
			end

			if not (
				pointLayer.currentObject and
				pointLayer.currentObject.chunkId == chunkId and
				pointLayer.currentObject.pointId == closestIdInChunk
			) then
				if pointLayer.childPointLayer then
					pointLayer.childPointLayer:handleThreadedShapeInit("expect")
				end

				pointLayer.currentObject = {
					chunkId = chunkId,
					chunkBufferIndex = chunkBufferIndex, -- Won't change for the same object
					pointId = closestIdInChunk,

					-- chunkX = closestChunkX,
					-- chunkY = closestChunkY,
					-- chunkZ = closestChunkZ
				}
				local currentObject = pointLayer.currentObject
				-- Features with consistent ways of calculating
				local x, y, z = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "position", "float", 3)
				local objectPosition = parentOrigin + pointLayer.chunkSize * bm.vec3(mathsies.vec3.components(
					mathsies.vec3.rotate(
						mathsies.vec3(closestChunkX + x, closestChunkY + y, closestChunkZ + z),
						mathsies.quat.inverse(parentOrientation)
					)
				))
				currentObject.position = objectPosition
				if pointLayer.features.shapeTypeSubtypeIds then
					currentObject.shapeTypeName = self.pointLayerShapeTypes[shapeTypeId].name
					currentObject.shapeSubtypeId = shapeSubtypeId
				end
				currentObject.attenuationShapeTypeName = attenuationShapeTypeName
				currentObject.attenuationShapeSubtypeId = attenuationShapeSubtypeId
				if pointLayer.features.radii then
					currentObject.radii = mathsies.vec3(xRadius, yRadius, zRadius)
				end
				if pointLayer.features.orientation then
					local ox, oy, oz, ow
					if pointLayer.features.radii == "sent" then
						ox, oy, oz, ow = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "orientation", "float", 4)
					elseif pointLayer.features.radii == "unsent" then
						ox = chunkExtraInfo.orientation[closestIdInChunk * 4]
						oy = chunkExtraInfo.orientation[closestIdInChunk * 4 + 1]
						oz = chunkExtraInfo.orientation[closestIdInChunk * 4 + 2]
						ow = chunkExtraInfo.orientation[closestIdInChunk * 4 + 3]
					end
					currentObject.orientation = mathsies.quat(ox, oy, oz, ow)
				end
				if pointLayer.features.mass then
					local mass
					if pointLayer.features.mass == "sent" then
						mass = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "mass", "float", 1)
					elseif pointLayer.features.mass == "unsent" then
						mass = chunkExtraInfo.mass[closestIdInChunk]
					end
					currentObject.mass = mass
				end
				if pointLayer.features.attenuationMultiplier then
					local attenuationMultiplier
					if pointLayer.features.attenuationMultiplier == "sent" then
						attenuationMultiplier = pointLayer:getPointVars(chunkBufferIndex, closestIdInChunk, "attenuationMultiplier", "float", 1)
					elseif pointLayer.features.attenuationMultiplier == "unsent" then
						attenuationMultiplier = chunkExtraInfo.attenuationMultiplier[closestIdInChunk]
					end
					currentObject.attenuationMultiplier = attenuationMultiplier
				end
				if pointLayer.features.starParams then
					currentObject.starParams = {}
					local offset = closestIdInChunk * consts.maxStarsPerSystem * consts.starParamCount
					for starId = 0, consts.maxStarsPerSystem - 1 do
						local params = {}
						currentObject.starParams[starId + 1] = params
						local offset = offset + starId * consts.starParamCount
						for param = 1, consts.starParamCount do
							params[param] = chunkExtraInfo.starParams[offset + param - 1]
						end
					end
				end
				-- Remaining features are generated (or fetched from extra info) in possibly layer-specific ways
				self:seedCelestialRNG(self:getGlobalCelestialObjectIdNumbers(
					pointLayer:getGlobalCelestialObjectIdParameters(consts.objectGenerationStages.main, currentObject)
				))
				pointLayer:generateRemainingCurrentObjectInfo()

				remakeAll = true
			end
		else
			pointLayer.currentPotentialObject = nil
			self:finishHandlingPointLayers(pointLayer)
			break
		end
	end

	-- Calculate once per tick, while we know that everything is consistent with the position of the ship when this function was called
	self.pointLayerGravityWellSlowdownFactor = self:getPointLayerGravityWellSlowdownFactor()
end

function game:getPointLayerGravityWellSlowdownFactor()
	local total = 0
	local referencePosition = self.ship.position

	local exponent = consts.slowdownDistanceExponent

	for pointLayerIndex, pointLayer in ipairs(self.pointLayers) do
		local massSent
		if pointLayer.features.mass == "sent" then
			massSent = true
		elseif pointLayer.features.mass == "unsent" then
			massSent = false
		else
			goto continue
		end

		local currentObject
		if not pointLayer.parentPointLayer then
			currentObject = pointLayer.fixedParentObject
		elseif pointLayer.parentPointLayer.currentObject then
			currentObject = pointLayer.parentPointLayer.currentObject
		else
			break
		end
		local parentOrigin = currentObject.position
		local parentRadii = currentObject.radii
		local parentOrientation = currentObject.orientation
		local parentShapeTypeName = currentObject.shapeTypeName
		local parentShapeSubtypeId = currentObject.shapeSubtypeId

		local positionRelativeFull = mathsies.vec3.rotate(bm.vec3.toMathsiesVec3(referencePosition - parentOrigin), parentOrientation)
		local positionRelative = positionRelativeFull / pointLayer.chunkSize

		local totalThisLayer = 0

		local temp = mathsies.vec3() -- No need to generate tons of new vec3s
		local xLower = math.floor(positionRelative.x - 0.5)
		local yLower = math.floor(positionRelative.y - 0.5)
		local zLower = math.floor(positionRelative.z - 0.5)
		local xUpper = xLower + 1
		local yUpper = yLower + 1
		local zUpper = zLower + 1
		local sampledChunksWidth = xUpper - xLower + 1
		local sampledChunksHeight = yUpper - yLower + 1
		local sampledChunksDepth = zUpper - zLower + 1
		for x = xLower, xUpper do
			for y = yLower, yUpper do
				for z = zLower, zUpper do
					local xInChunkBuffer = x % pointLayer.chunkBufferSideLength
					local yInChunkBuffer = y % pointLayer.chunkBufferSideLength
					local zInChunkBuffer = z % pointLayer.chunkBufferSideLength
					local chunkBufferIndex = xInChunkBuffer + yInChunkBuffer * pointLayer.chunkBufferSideLength + zInChunkBuffer * pointLayer.chunkBufferSideLength * pointLayer.chunkBufferSideLength
					local chunkExtraInfo = pointLayer.chunkExtraInfo[chunkBufferIndex]
					if not (
						chunkExtraInfo.x == x and
						chunkExtraInfo.y == y and
						chunkExtraInfo.z == z
					) then
						goto continue
					end
					for pointId = 0, pointLayer:getChunkPointCount(chunkBufferIndex) - 1 do
						if not (
							pointLayer.currentObject and
							pointLayer.currentObject.chunkBufferIndex == chunkBufferIndex and
							pointLayer.currentObject.pointId == pointId
						) then
							temp.x, temp.y, temp.z = pointLayer:getPointVars(chunkBufferIndex, pointId, "position", "float", 3)
							temp.x = temp.x + x
							temp.y = temp.y + y
							temp.z = temp.z + z
							local distance = mathsies.vec3.distance(positionRelative, temp)

							local mass
							if massSent then
								mass = pointLayer:getPointVars(chunkBufferIndex, pointId, "mass", "float", 1)
							else
								mass = chunkExtraInfo.mass[pointId]
							end

							if distance * pointLayer.chunkSize > 0 then
								totalThisLayer = totalThisLayer + mass * (distance * pointLayer.chunkSize) ^ exponent
							end
						end
					end
					::continue::
				end
			end
		end

		local doLods = true
		if doLods then
			local gridIters = 0
			local samples = 0
			local dataVolumeToRealVolume = parentRadii.x * parentRadii.y * parentRadii.z
			local function gravity(mass, x, y, z)
				local finalX = x * parentRadii.x
				local finalY = y * parentRadii.y
				local finalZ = z * parentRadii.z
				local finalMass = mass * pointLayer.averageMassPerPoint * pointLayer.maxPointDensity * dataVolumeToRealVolume
				local distance = math.sqrt(
					(finalX - positionRelativeFull.x) ^ 2 +
					(finalY - positionRelativeFull.y) ^ 2 +
					(finalZ - positionRelativeFull.z) ^ 2
				)
				if distance > 0 then
					totalThisLayer = totalThisLayer + finalMass * distance ^ exponent
				end
			end
			local massData = pointLayer.shapeMassDataFFI
			local range = consts.lodBoxRange
			local posX = positionRelativeFull.x / parentRadii.x * 0.5 + 0.5
			local posY = positionRelativeFull.y / parentRadii.y * 0.5 + 0.5
			local posZ = positionRelativeFull.z / parentRadii.z * 0.5 + 0.5
			local cutRegionStartX = xLower * pointLayer.chunkSize / parentRadii.x
			local cutRegionStartY = yLower * pointLayer.chunkSize / parentRadii.y
			local cutRegionStartZ = zLower * pointLayer.chunkSize / parentRadii.z
			local cutRegionEndX = (xUpper + 1) * pointLayer.chunkSize / parentRadii.x
			local cutRegionEndY = (yUpper + 1) * pointLayer.chunkSize / parentRadii.y
			local cutRegionEndZ = (zUpper + 1) * pointLayer.chunkSize / parentRadii.z
			local nextLodStartX = 0
			local nextLodStartY = 0
			local nextLodStartZ = 0
			local nextLodEndX = 1
			local nextLodEndY = 1
			local nextLodEndZ = 1
			for lod = 0, consts.shapeSlowdownIntegralDetail do -- Go from lowest detail to highest, leaving gaps for the next lod
				local lodStepCount = 2 ^ lod
				local lodReadOffset = consts.shapeSlowdownIntegralDataStarts[lod]
				local isHighestDetailLod = lod == consts.shapeSlowdownIntegralDetail
				local posXThisLod = math.floor(posX * lodStepCount)
				local posYThisLod = math.floor(posY * lodStepCount)
				local posZThisLod = math.floor(posZ * lodStepCount)
				local thisLodStartX = nextLodStartX
				local thisLodStartY = nextLodStartY
				local thisLodStartZ = nextLodStartZ
				local thisLodEndX = nextLodEndX
				local thisLodEndY = nextLodEndY
				local thisLodEndZ = nextLodEndZ
				nextLodStartX = math.huge
				nextLodStartY = math.huge
				nextLodStartZ = math.huge
				nextLodEndX = -math.huge
				nextLodEndY = -math.huge
				nextLodEndZ = -math.huge
				for x = thisLodStartX, thisLodEndX - 1 do
					for y = thisLodStartY, thisLodEndY - 1 do
						for z = thisLodStartZ, thisLodEndZ - 1 do
							gridIters = gridIters + 1
							if
								math.abs(x - posXThisLod) <= range and
								math.abs(y - posYThisLod) <= range and
								math.abs(z - posZThisLod) <= range and
								not isHighestDetailLod -- For the highest detail lod, read from the whole range without leaving a gap
							then
								-- Leave to next lod (which is higher detail)
								nextLodStartX = math.min(nextLodStartX, x * 2)
								nextLodStartY = math.min(nextLodStartY, y * 2)
								nextLodStartZ = math.min(nextLodStartZ, z * 2)
								nextLodEndX = math.max(nextLodEndX, (x + 1) * 2)
								nextLodEndY = math.max(nextLodEndY, (y + 1) * 2)
								nextLodEndZ = math.max(nextLodEndZ, (z + 1) * 2)
							else
								samples = samples + 1
								local sampleI = lodReadOffset + x + y * lodStepCount + z * lodStepCount ^ 2

								local sampleStartX = x / lodStepCount * 2 - 1 -- *2-1 because shape types' coordinates go from -1 to 1
								local sampleStartY = y / lodStepCount * 2 - 1
								local sampleStartZ = z / lodStepCount * 2 - 1
								local sampleEndX = (x + 1) / lodStepCount * 2 - 1
								local sampleEndY = (y + 1) / lodStepCount * 2 - 1
								local sampleEndZ = (z + 1) / lodStepCount * 2 - 1
								local sampleCentreX = (sampleStartX + sampleEndX) / 2
								local sampleCentreY = (sampleStartY + sampleEndY) / 2
								local sampleCentreZ = (sampleStartZ + sampleEndZ) / 2
								local sampleVolume =
									(sampleEndX - sampleStartX) *
									(sampleEndY - sampleStartY) *
									(sampleEndZ - sampleStartZ)
								local sampleMass = massData[sampleI]
								if sampleMass == 0 then
									-- Early return
									goto continue
								end

								local sampleCutStartX = math.max(sampleStartX, cutRegionStartX)
								local sampleCutEndX = math.min(sampleEndX, cutRegionEndX)
								local sampleCutStartY = math.max(sampleStartY, cutRegionStartY)
								local sampleCutEndY = math.min(sampleEndY, cutRegionEndY)
								local sampleCutStartZ = math.max(sampleStartZ, cutRegionStartZ)
								local sampleCutEndZ = math.min(sampleEndZ, cutRegionEndZ)
								local cutCentreX = (sampleCutStartX + sampleCutEndX) / 2
								local cutCentreY = (sampleCutStartY + sampleCutEndY) / 2
								local cutCentreZ = (sampleCutStartZ + sampleCutEndZ) / 2
								local cutVolume =
									math.max(0, sampleCutEndX - sampleCutStartX) *
									math.max(0, sampleCutEndY - sampleCutStartY) *
									math.max(0, sampleCutEndZ - sampleCutStartZ)

								if cutVolume == 0 then
									-- Usually this branch is taken
									gravity(sampleMass, sampleCentreX, sampleCentreY, sampleCentreZ)
								else
									-- This branch is only taken if the current sample AABB intersects with the AABB of chunks whose points have been iterated over.

									-- Split up AABB that has had other AABB removed from it into (at most) 3^3-1 smaller AABBs. We miss out the removed AABB to avoid errors where the distance is far lower than it should be and the calculation goes wrong.

									local density = sampleMass / sampleVolume
									-- Since this branch is rarely taken, we are OK to use some tables.
									local xCoords = {sampleStartX, sampleCutStartX, sampleCutEndX, sampleEndX}
									local yCoords = {sampleStartY, sampleCutStartY, sampleCutEndY, sampleEndY}
									local zCoords = {sampleStartZ, sampleCutStartZ, sampleCutEndZ, sampleEndZ}

									for xi = 1, 3 do
										for yi = 1, 3 do
											for zi = 1, 3 do
												if xi == 2 and yi == 2 and zi == 2 then
													-- Skip centre as it's the cut AABB where the points were checked
													goto continue
												end

												local startX = xCoords[xi]
												local endX = xCoords[xi + 1]
												local startY = yCoords[yi]
												local endY = yCoords[yi + 1]
												local startZ = zCoords[zi]
												local endZ = zCoords[zi + 1]

												local volume =
													(endX - startX) *
													(endY - startY) *
													(endZ - startZ)

												local centreX = (startX + endX) / 2
												local centreY = (startY + endY) / 2
												local centreZ = (startZ + endZ) / 2

												local mass = volume * density -- May be 0

												gravity(mass, centreX, centreY, centreZ)

											    ::continue::
											end
										end
									end
								end
							end
						    ::continue::
						end
					end
				end
			end
		else
			local shapeType = self.pointLayerShapeTypes[parentShapeTypeName]
			local ratioX, ratioY, ratioZ
			if shapeType.needsTrueRatio then
				ratioX, ratioY, ratioZ = mathsies.vec3.components(parentRadii / math.max(parentRadii.x, parentRadii.y, parentRadii.z))
			end
			local scratch = self:decodeShapeSubtypeIntoScratchTable(shapeType, parentShapeSubtypeId)
			for i = 1, #self.slowdownSampleDistribution do
				local infoTable = {
					shapeTypeId = shapeType.id,
					params = scratch,
					valueNoiseData = pointLayer.valueNoiseData,
					type = "gravitySlowdown",
					firstSample = self.slowdownSampleDistribution[i].firstSample,
					lastSample = self.slowdownSampleDistribution[i].lastSample,
					stepCount = self.slowdownSampleDistribution.stepCount,

					exponent = exponent,
					-- From radius 1 (as in the shape type density function) to full object radii
					scaleX = parentRadii.x,
					scaleY = parentRadii.y,
					scaleZ = parentRadii.z,
					-- For shape types that need this information (their density function signatures are different)
					ratioX = ratioX,
					ratioY = ratioY,
					ratioZ = ratioZ,
					-- These all work in full positions
					referencePosX = positionRelativeFull.x,
					referencePosY = positionRelativeFull.y,
					referencePosZ = positionRelativeFull.z,
					cutRegionStartX = xLower * pointLayer.chunkSize,
					cutRegionStartY = yLower * pointLayer.chunkSize,
					cutRegionStartZ = zLower * pointLayer.chunkSize,
					cutRegionEndX = (xUpper + 1) * pointLayer.chunkSize,
					cutRegionEndY = (yUpper + 1) * pointLayer.chunkSize,
					cutRegionEndZ = (zUpper + 1) * pointLayer.chunkSize,
					sampleDensityMultiplier = pointLayer.averageMassPerPoint * pointLayer.maxPointDensity
				}
				love.thread.getChannel("shapeAmountsInfo"):push(infoTable)
			end
			local results = {}
			for _=1, #self.slowdownSampleDistribution do
				local result
				while not result do
					result = love.thread.getChannel("shapeAmountsResult"):demand(consts.shapeIntegralThreadTimeout)
					if not result then
						self:checkThreadsForErrors()
					end
				end
				table.insert(results, result)
			end
			table.sort(results, function(a, b) -- Sort for determinism
				return a.firstSample < b.firstSample
			end)
			for _, v in ipairs(results) do
				totalThisLayer = totalThisLayer + v.rangeTotal
			end
		end

		total = total + totalThisLayer
		::continue::
	end

	return total
end

return game
