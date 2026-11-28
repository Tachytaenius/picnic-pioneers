local consts = require("consts")
local mathsies = require("lib.mathsies")
local bm = require("bigmaths")
local util = require("util")

local game = {}

function game:draw()
	local POVEntity = self.players[1]
	self:drawCelestialAndShip(POVEntity)

	love.graphics.setCanvas()
	love.graphics.setShader(self.spectralToRGBShader)
	self.spectralToRGBShader:send("spectralToRGB", self.spectralToRGBMatrix3x3)
	love.graphics.draw(self.screenCanvasses.lightCanvas)
	love.graphics.setShader()
end

function game:drawCelestialAndShip(POVEntity)
	local tempOpacityCanvas = self.screenCanvasses.tempOpacityCanvas
	love.graphics.setCanvas(tempOpacityCanvas)
	love.graphics.clear(0, 0, 0, 0) -- Gets added to per-object

	local transmittanceCanvas = self.screenCanvasses.transmittanceCanvas
	love.graphics.setCanvas(transmittanceCanvas)
	love.graphics.clear(1, 1, 1, 1)

	local lightCanvas = self.screenCanvasses.lightCanvas
	love.graphics.setCanvas(lightCanvas)
	love.graphics.clear(0, 0, 0, 0)

	local aspectRatio = lightCanvas:getWidth() / lightCanvas:getHeight()

	self.pointIndirectDrawArgsBuffer:setArrayData({
		self.pointDiskMesh:getVertexCount(),
		0, -- This gets incremented (on the GPU)
		0,
		0
	})

	local pointOutputMultiplier = self:getPointOutputMultiplier()

	-- Get (and send) other information for points
	local diskDistanceToSphere = 1 - math.cos(consts.pointAngularRadius) -- Unit sphere spherical cap height from angular radius
	local diskSolidAngle = consts.tau * diskDistanceToSphere
	local scaleToGetAngularRadius = math.tan(consts.pointAngularRadius)
	local pointRadianceCalcConst = pointOutputMultiplier / diskSolidAngle
	self.pointDrawablesShader:send("fadeExponent", consts.pointDiskFadeExponent)
	self.pointDrawablesShader:send("diskDistanceToSphere", diskDistanceToSphere)
	self.pointDrawablesShader:send("scale", scaleToGetAngularRadius)

	-- Camera info
	local cameraPositionFull = self.ship.position + bm.vec3( -- NOTE: Position of POV entity is assumed to be relative to ship
		POVEntity.position.x,
		POVEntity.position.y,
		POVEntity.position.z
	)
	local cameraOrientation = self.ship.orientation * POVEntity.orientation
	local cameraVerticalFOV = POVEntity.verticalFOV
	local diagonalFOV = 2 * math.atan(math.sqrt(1 ^ 2 + aspectRatio ^ 2) * math.tan(cameraVerticalFOV / 2))

	-- Layer mode lerping info
	local layerObjectMultipliers = {}
	layerObjectMultipliers.fixedParent = 1 -- Draw universe volumetric fully (if fading it to points then change this number)
	for plIndex, pointLayer in ipairs(self.pointLayers) do
		local object = pointLayer.currentObject or pointLayer.currentPotentialObject
		if plIndex == #self.pointLayers or not object then
			break
		elseif object then
			local distance = bm.mapm.tonumber(bm.vec3.distance(object.position, cameraPositionFull))
			layerObjectMultipliers[pointLayer] = 1 - self:getLerpFromBodyToPoint(distance, math.max(object.radii.x, object.radii.y, object.radii.z))
		end
	end

	-- More camera info

	local vertexZAtFurthestAngle = math.cos(diagonalFOV / 2)
	local cameraToClip, cameraForwards, cameraUp, cameraRight, worldToCameraStationary, skyToClip, clipToSky, cornerDirs, worldToCameraDirection
	local function setupCameraVars(layerOrientation, far, near, overallOrientationOverride)
		local layerTotalOrientation = overallOrientationOverride or (layerOrientation * cameraOrientation)

		cameraToClip = mathsies.mat4.perspectiveLeftHanded(
			aspectRatio,
			cameraVerticalFOV,
			-- 1, -- Only a point disk vertex right in the centre of the screen has any chance of being clipped, and it will just be pushed slightly away from the centre. I don't see how any holes could form.
			far or 1.01, -- But whatever lol
			-- vertexZAtFurthestAngle
			near or (vertexZAtFurthestAngle * 0.99)
		)
		cameraForwards = mathsies.vec3.rotate(consts.forwardVector, layerTotalOrientation)
		cameraUp = mathsies.vec3.rotate(consts.upVector, layerTotalOrientation)
		cameraRight = mathsies.vec3.rotate(consts.rightVector, layerTotalOrientation)
		worldToCameraStationary = mathsies.mat4.camera(mathsies.vec3(), layerTotalOrientation)
		skyToClip = cameraToClip * worldToCameraStationary
		clipToSky = mathsies.mat4.inverse(skyToClip)

		local m = worldToCameraStationary
		worldToCameraDirection = {
			m._00, m._01, m._02,
			m._10, m._11, m._12,
			m._20, m._21, m._22
		}

		cornerDirs = {}
		for y = 1, -1, -2 do
			for x = -1, 1, 2 do
				local clipSpacePos = mathsies.vec3(x, y, -1) -- -1 for near plane but it makes no difference once everything is normalised in the compute shader(s). It may need to be consistent per-corner, though
				local result = clipToSky * clipSpacePos
				table.insert(cornerDirs, {mathsies.vec3.components(result)})
			end
		end
	end

	local smallestActiveLayer = self.pointLayers[1]
	for _, pointLayer in ipairs(self.pointLayers) do
		if pointLayer.parentPointLayer and not pointLayer.parentPointLayer.currentObject then
			break -- Outside of any objects below this scale
		end
		smallestActiveLayer = pointLayer
	end

	local function drawLayer(pointLayer)
		-- Volumetrics output to the layer's radiance and transmittance accumulation canvasses
		-- Points output to the point drawable buffer

		local currentObject
		if not pointLayer.parentPointLayer then
			currentObject = pointLayer.fixedParentObject
		elseif pointLayer.parentPointLayer.currentObject then
			currentObject = pointLayer.parentPointLayer.currentObject
		end
		local parentOrigin = currentObject.position
		local parentObjectShapeTypeName = currentObject.shapeTypeName
		local parentObjectShapeSubtypeId = currentObject.shapeSubtypeId
		local parentObjectRadii = currentObject.radii
		local parentOrientation = currentObject.orientation
		local attenuationShapeTypeName = currentObject.attenuationShapeTypeName
		local attenuationShapeSubtypeId = currentObject.attenuationShapeSubtypeId
		local attenuationMultiplier = currentObject.attenuationMultiplier or 0

		local cameraPositionFullRelative = cameraPositionFull - parentOrigin
		local cameraPosition = mathsies.vec3.rotate(bm.vec3.toMathsiesVec3( -- Chunk sides have a length of 1
			cameraPositionFullRelative / pointLayer.chunkSize
		), parentOrientation)
		setupCameraVars(parentOrientation)

		-- Fade in/out roles are swapped between volumetric and point
		local fullyPointRadius = (pointLayer.chunkBufferSideLength / 2 - 0.5) * consts.pointFadeStart
		local fullyVolumetricRadius = pointLayer.chunkBufferSideLength / 2 - 0.5
		-- In terms of proper units and not chunks
		local fullyPointRadiusProperUnits = fullyPointRadius * pointLayer.chunkSize
		local fullyVolumetricRadiusProperUnits = fullyVolumetricRadius * pointLayer.chunkSize

		local distanceUnitScale = 1 / math.max(parentObjectRadii.x, parentObjectRadii.y, parentObjectRadii.z)
		local shapeType = self.pointLayerShapeTypes[parentObjectShapeTypeName]
		local attenuationShapeType = self.pointLayerShapeTypes[attenuationShapeTypeName]
		local volumetricShader = self.shapeVolumeShaders[parentObjectShapeTypeName][attenuationShapeTypeName or consts.noAttenuationShapeTypeName]

		-- Volumetrics

		if pointLayer.volumetricCanvasCameraInfo then
			if
				pointLayer.volumetricCanvasCameraInfo.position ~= cameraPositionFull or
				-- pointLayer.volumetricCanvasCameraInfo.orientation ~= cameraOrientation or
				pointLayer.volumetricCanvasCameraInfo.verticalFOV ~= cameraVerticalFOV or
				pointLayer.volumetricCanvasCameraInfo.brightnessMultiplier ~= consts.celestialRadianceMultiplier
			then
				-- TODO: Figure out what to do when translating
				local original = love.graphics.getCanvas()
				love.graphics.setCanvas(pointLayer.volumetricCanvas)
				love.graphics.clear(0, 0, 0, 0)
				love.graphics.setCanvas(pointLayer.volumetricTransmittanceCanvas)
				love.graphics.clear(0, 0, 0, 0) -- Start at 0 for averaging since there are no additions yet
				love.graphics.setCanvas(pointLayer.volumetricAddCountCanvas)
				love.graphics.clear(0, 0, 0, 0)
				love.graphics.setCanvas(original)
			else
				if pointLayer.volumetricCanvasCameraInfo.orientation ~= cameraOrientation then
					self.reprojectionCopyShader:send("radianceIn", pointLayer.volumetricCanvas)
					self.reprojectionCopyShader:send("transmittanceIn", pointLayer.volumetricTransmittanceCanvas)
					self.reprojectionCopyShader:send("additionsIn", pointLayer.volumetricAddCountCanvas)
					self.reprojectionCopyShader:send("radianceOut", self.screenCanvasses.tempVolumetricRadianceCanvas)
					self.reprojectionCopyShader:send("transmittanceOut", self.screenCanvasses.tempVolumetricTransmittanceCanvas)
					self.reprojectionCopyShader:send("additionsOut", self.screenCanvasses.tempVolumetricAddCountCanvas)
					self.reprojectionCopyShader:send("size", {self.volumetricCanvasWidth, self.volumetricCanvasHeight})
					local w, h = self.reprojectionCopyShader:getLocalThreadgroupSize()
					love.graphics.dispatchThreadgroups(self.reprojectionCopyShader,
						math.ceil(self.volumetricCanvasWidth / w),
						math.ceil(self.volumetricCanvasHeight / h)
					)

					local first = mathsies.mat4.transform(mathsies.vec3(), mathsies.quat(), mathsies.vec3(1, -1, 1)) -- Why is this needed...
					local reproject = mathsies.mat4.inverse(first) * pointLayer.volumetricCanvasCameraInfo.skyToClip * clipToSky * first
					self.rotationReprojectionShader:send("reproject", {mathsies.mat4.components(reproject)})
					self.rotationReprojectionShader:send("maxAdditions", consts.volumetricMaxPixelAdditions)
					self.rotationReprojectionShader:send("additionsMultiplier", consts.volCamRotReprojAdditionsMul)
					self.rotationReprojectionShader:send("minMultipliedAdditions", consts.volCamRotReprojMinAdditions)

					self.rotationReprojectionShader:send("radianceIn", self.screenCanvasses.tempVolumetricRadianceCanvas)
					self.rotationReprojectionShader:send("transmittanceIn", self.screenCanvasses.tempVolumetricTransmittanceCanvas)
					self.rotationReprojectionShader:send("additionsIn", self.screenCanvasses.tempVolumetricAddCountCanvas)
					self.rotationReprojectionShader:send("radianceOut", pointLayer.volumetricCanvas)
					self.rotationReprojectionShader:send("transmittanceOut", pointLayer.volumetricTransmittanceCanvas)
					self.rotationReprojectionShader:send("additionsOut", pointLayer.volumetricAddCountCanvas)
					self.rotationReprojectionShader:send("size", {self.volumetricCanvasWidth, self.volumetricCanvasHeight})
					local w, h = self.rotationReprojectionShader:getLocalThreadgroupSize()
					love.graphics.dispatchThreadgroups(self.rotationReprojectionShader,
						math.ceil(self.volumetricCanvasWidth / w),
						math.ceil(self.volumetricCanvasHeight / h)
					)
				end
			end
		end
		pointLayer.volumetricCanvasCameraInfo = {
			position = bm.vec3.clone(cameraPositionFull),
			orientation = mathsies.quat.clone(cameraOrientation),
			verticalFOV = cameraVerticalFOV,
			brightnessMultiplier = consts.celestialRadianceMultiplier,

			skyToClip = skyToClip,
			clipToSky = clipToSky
		}

		-- Send shape params for point density (aka emission)
		local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(shapeType, parentObjectShapeSubtypeId)
		for i, parameter in ipairs(shapeType.parameters) do
			volumetricShader:send("emissionShape_" .. parameter.name, densityParametersScratchTable[i])
		end
		-- And for attenuation
		local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(attenuationShapeType, attenuationShapeSubtypeId)
		for i, parameter in ipairs(attenuationShapeType.parameters) do
			volumetricShader:send("attenuationShape_" .. parameter.name, densityParametersScratchTable[i])
		end

		if pointLayer.hasNoiseEmission and shapeType.noiseInfo then
			volumetricShader:send("EmissionNoiseValues", pointLayer.valueNoiseBufferEmission)
		end
		if pointLayer.hasNoiseAttenuation and attenuationShapeType.noiseInfo then
			volumetricShader:send("AttenuationNoiseValues", pointLayer.valueNoiseBufferAttenuation)
		end

		local layerMul = layerObjectMultipliers[pointLayer.parentPointLayer or "fixedParent"]
		volumetricShader:send("brightnessMultiplier", consts.celestialRadianceMultiplier * layerMul)
		volumetricShader:send("preNormaliseCornerDirs", unpack(cornerDirs))
		volumetricShader:send("size", {pointLayer.volumetricCanvas:getDimensions()})
		volumetricShader:send("resultCanvas", pointLayer.volumetricCanvas)
		volumetricShader:send("resultTransmittanceCanvas", pointLayer.volumetricTransmittanceCanvas)
		volumetricShader:send("additionCountCanvas", pointLayer.volumetricAddCountCanvas)
		volumetricShader:send("rayStepVariance", 1)
		volumetricShader:send("raySeed", love.math.random(0, 2 ^ 32 - 1))
		volumetricShader:send("fadeInRadius", fullyVolumetricRadiusProperUnits * distanceUnitScale)
		volumetricShader:send("fadeOutRadius", fullyPointRadiusProperUnits * distanceUnitScale)
		volumetricShader:send("fadeExponent", consts.pointFadeExponent)
		-- volumetricShader:send("clipToSky", {mathsies.mat4.components(clipToSky)})
		volumetricShader:send("cameraPosition", {mathsies.vec3.components(
			mathsies.vec3.rotate(
				bm.vec3.toMathsiesVec3(cameraPositionFullRelative * distanceUnitScale),
				parentOrientation
			)
		)})
		volumetricShader:send("additionCountToGetMin", consts.volumetricPixelAdditionsToGetMinSteps)
		volumetricShader:send("rayStepsMin", consts.volumetricMinSteps)
		volumetricShader:send("rayStepsNoAdditions", consts.volumetricMaxSteps)
		volumetricShader:send("shapeRadii", {mathsies.vec3.components(distanceUnitScale * parentObjectRadii)})
		if volumetricShader:hasUniform("baseEmission") then
			volumetricShader:send("baseEmission", {
				-- Density's distance dimension is -3, intensity's is 2 (from the m^2 in the W), so the unit scale is raised to the -1
				distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageRadiantIntensityRPerPoint,
				distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageRadiantIntensityGPerPoint,
				distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageRadiantIntensityBPerPoint
			})
		end
		if volumetricShader:hasUniform("attenuationMultiplier") then
			volumetricShader:send("attenuationMultiplier", attenuationMultiplier / distanceUnitScale)
		end
		local w, h = volumetricShader:getLocalThreadgroupSize()
		love.graphics.dispatchThreadgroups(volumetricShader,
			math.ceil(pointLayer.volumetricCanvas:getWidth() / w),
			math.ceil(pointLayer.volumetricCanvas:getHeight() / h)
		)

		-- Draw the object as a point, fading between the two
		-- This call happens before the transmittance canvas is written to by this point layer, so a galaxy will not attenuate its own light when drawn as a point and volumetric simultaneously
		-- NOTE: The distances are assumed to be low enough that the point attenuation texture needn't be sampled. It would need to be calculated for the layer above, which is handled after this one.
		if layerMul ~= 1 then
			local dist = bm.mapm.tonumber(bm.vec3.length(cameraPositionFullRelative))
			local pointMul = 1 - layerMul
			local radiance = {mathsies.vec3.components(currentObject.radiantIntensity / dist ^ 2 * pointRadianceCalcConst * consts.celestialRadianceMultiplier * pointMul)}
			local direction = mathsies.vec3.rotate(mathsies.vec3.normalise(-bm.vec3.toMathsiesVec3(cameraPositionFullRelative)), mathsies.quat.inverse(cameraOrientation))
			self:addMiscPointWithCurrentTransmittanceCanvas(direction, radiance, cameraToClip)
		end

		-- Point attenuation

		local pointAttenuationTexture
		if attenuationShapeType.name == consts.noAttenuationShapeTypeName then
			pointAttenuationTexture = self.clearPointAttenuationTexture
		else
			pointAttenuationTexture = self.pointAttenuationTexture
			local pointAttenuationShader = attenuationShapeType.pointAttenuationShader

			local densityParametersScratchTable = self:decodeShapeSubtypeIntoScratchTable(attenuationShapeType, attenuationShapeSubtypeId)
			for i, parameter in ipairs(attenuationShapeType.parameters) do
				pointAttenuationShader:send("attenuationShape_" .. parameter.name, densityParametersScratchTable[i])
			end

			if pointLayer.hasNoiseAttenuation and attenuationShapeType.noiseInfo then
				pointAttenuationShader:send("AttenuationNoiseValues", pointLayer.valueNoiseBufferAttenuation)
			end

			pointAttenuationShader:send("shapeRadii", {mathsies.vec3.components(distanceUnitScale * parentObjectRadii)})
			if pointAttenuationShader:hasUniform("attenuationMultiplier") then
				pointAttenuationShader:send("attenuationMultiplier", attenuationMultiplier / distanceUnitScale)
			end
			pointAttenuationShader:send("rayLength", fullyVolumetricRadiusProperUnits * distanceUnitScale)
			pointAttenuationShader:send("textureSize", {
				pointAttenuationTexture:getWidth(),
				pointAttenuationTexture:getHeight(),
				pointAttenuationTexture:getDepth()
			})
			pointAttenuationShader:send("clipToSky", {mathsies.mat4.components(clipToSky)})
			pointAttenuationShader:send("cameraPosition", {mathsies.vec3.components(
				mathsies.vec3.rotate(
					bm.vec3.toMathsiesVec3(cameraPositionFullRelative * distanceUnitScale),
					parentOrientation
				)
			)})
			pointAttenuationShader:send("resultTexture", pointAttenuationTexture)

			local xSize, ySize = pointAttenuationShader:getLocalThreadgroupSize()
			local w, h = pointAttenuationTexture:getDimensions()
			local xCount = math.ceil(w / xSize)
			local yCount = math.ceil(h / ySize)
			love.graphics.dispatchThreadgroups(pointAttenuationShader, xCount, yCount, 1)
		end

		-- Points

		local maxAngleFromCentre = diagonalFOV / 2 + consts.pointAngularRadius
		local minDot = math.cos(maxAngleFromCentre)
		local currentObjectInfo = pointLayer.currentObject or pointLayer.currentPotentialObject
		local currentIndex =
			currentObjectInfo and (
				currentObjectInfo.chunkBufferIndex * pointLayer.maxPointsPerChunk + currentObjectInfo.pointId
			) or pointLayer.maxPoints -- Use unreachable current index
		local preparationShader = pointLayer.pointPreparationShader
		local currentDirection
		local skipCurrent = false
		if pointLayer.currentObject then
			-- Too close, let other code paths handle the object
			skipCurrent = true
		elseif pointLayer.currentPotentialObject then
			-- Draw in a CPU-calculated direction to fix precision issues when on the approach to small galaxies
			local object = pointLayer.currentPotentialObject or pointLayer.currentObject
			local x, y, z = pointLayer:getPointVars(object.chunkBufferIndex, object.pointId, "position", "float", 3)
			local position = bm.vec3(object.chunkX + x, object.chunkY + y, object.chunkZ + z)
			local difference =
				position -
				bm.vec3.rotate(
					cameraPositionFullRelative / pointLayer.chunkSize,
					parentOrientation
				)
			local distance = bm.vec3.length(difference)
			local direction = difference / distance
			currentDirection = bm.vec3.toMathsiesVec3(direction)
		end
		preparationShader:send("currentIndex", currentIndex)
		preparationShader:send("skipCurrent", skipCurrent)
		preparationShader:send("currentDirection", currentDirection and {mathsies.vec3.components(currentDirection)} or {0, 0, 1})
		preparationShader:send("worldToCameraDirection", worldToCameraDirection)
		preparationShader:send("totalTransmittanceCanvas", transmittanceCanvas)
		preparationShader:send("pointAttenuationTexture", pointAttenuationTexture)
		preparationShader:send("radianceCalcConst", pointRadianceCalcConst * consts.celestialRadianceMultiplier)
		preparationShader:send("chunkBufferSideLength", pointLayer.chunkBufferSideLength)
		preparationShader:send("viewMinPosInChunkBuffer", {
			(cameraPosition.x - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength,
			(cameraPosition.y - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength,
			(cameraPosition.z - pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength
		})
		preparationShader:send("cameraPosition", {
			(cameraPosition.x + pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength + pointLayer.chunkBufferSideLength / 2,
			(cameraPosition.y + pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength + pointLayer.chunkBufferSideLength / 2,
			(cameraPosition.z + pointLayer.chunkBufferSideLength / 2) % pointLayer.chunkBufferSideLength + pointLayer.chunkBufferSideLength / 2
		})
		preparationShader:send("minDot", minDot)
		preparationShader:send("cameraForwards", {mathsies.vec3.components(consts.forwardVector)})
		preparationShader:send("fadeInRadius", fullyPointRadius)
		preparationShader:send("fadeOutRadius", fullyVolumetricRadius)
		preparationShader:send("fadeExponent", consts.pointFadeExponent)
		preparationShader:send("cameraToClip", {mathsies.mat4.components(cameraToClip)})
		preparationShader:send("IndirectDrawBuffer", self.pointIndirectDrawArgsBuffer)
		preparationShader:send("Points", pointLayer.pointBuffer)
		preparationShader:send("PointDrawables", self.pointDrawableBuffer)
		preparationShader:send("ChunkPointCounts", pointLayer.chunkPointCountBuffer)
		local threadgroupCount = math.ceil(pointLayer.maxPoints / preparationShader:getLocalThreadgroupSize())
		love.graphics.dispatchThreadgroups(preparationShader, threadgroupCount)
	end

	local function drawShip()
		setupCameraVars(mathsies.quat(), consts.POVFarDistance, consts.POVNearDistance, POVEntity.orientation)
		local worldToCamera = mathsies.mat4.camera(POVEntity.position, POVEntity.orientation)
		local worldToClip = cameraToClip * worldToCamera

		local opaqueEntities = {}
		local windowsAndPointLights = {}
		for _, entity in ipairs(self.entities) do
			if entity.pointLightInfo or entity.windowInfo then
				table.insert(windowsAndPointLights, entity)
			else
				table.insert(opaqueEntities, entity)
			end
		end
		local function dist(e)
			if not e.windowInfo then
				return mathsies.vec3.distance(e.position, POVEntity.position)
			else
				local entityToCameraLocal = mathsies.vec3.rotate(POVEntity.position - e.position, mathsies.quat.inverse(e.orientation))
				local planeX = math.max(-e.windowInfo.width / 2, math.min(e.windowInfo.width / 2, entityToCameraLocal.x))
				local planeY = math.max(-e.windowInfo.height / 2, math.min(e.windowInfo.height / 2, entityToCameraLocal.y))
				local windowRight = mathsies.vec3.rotate(consts.rightVector, e.orientation)
				local windowUp = mathsies.vec3.rotate(consts.upVector, e.orientation)
				local newClosest = e.position + planeX * windowRight + planeY * windowUp
				return mathsies.vec3.distance(POVEntity.position, newClosest)
			end
		end
		table.sort(windowsAndPointLights, function(a, b)
			-- Closer is drawn first
			return dist(a) < dist(b)
		end)

		-- Point lights with shadows
		local pointLightsToDraw = {}
		for _, light in ipairs(windowsAndPointLights) do
			if not light.pointLightInfo then
				goto continue
			end

			table.insert(pointLightsToDraw, light)
			local pointLightIndex = #pointLightsToDraw

			local lightRadius = self:getPointLightRadius(light.pointLightInfo.radiantIntensity)
			love.graphics.setCanvas({
				self.shadowColourCubemaps[pointLightIndex],
				depthstencil = self.shadowCubemap,
				shaderlayer = true
			})
			love.graphics.clear({1, 1, 1, 1}, false, true) -- Clear colour and depth
			local lightToClip = mathsies.mat4.perspectiveLeftHanded(
				1,
				consts.tau / 4,
				lightRadius,
				consts.shadowCubemapNearDistance
			)
			self.shadowDepthShader:send("lightRadius", lightRadius)
			self.shadowDepthShader:send("lightPosition", {mathsies.vec3.components(light.position)})

			local worldToClipArray = {}
			local clipToSkyArray = {}
			for i, cubemapOrientation in ipairs(consts.cubemapOrientationsYFlip) do -- TODO: Why was y-flipping needed...?
				local worldToLight = mathsies.mat4.camera(light.position, cubemapOrientation)
				local worldToClip = lightToClip * worldToLight
				worldToClipArray[i] = {mathsies.mat4.components(worldToClip)}

				local clipToSky = mathsies.mat4.inverse(lightToClip * mathsies.mat4.camera(mathsies.vec3(), cubemapOrientation))
				clipToSkyArray[i] = {mathsies.mat4.components(clipToSky)}
			end
			self.shadowDepthShader:send("worldToClipCubemap", unpack(worldToClipArray))
			self.shadowDepthToColourShader:send("clipToSkyCubemap", unpack(clipToSkyArray))

			love.graphics.setColorMask(false, false, false, false)
			love.graphics.setDepthMode("lequal", true)
			love.graphics.setFrontFaceWinding("ccw")
			love.graphics.setMeshCullMode("front")
			love.graphics.setShader(self.shadowDepthShader)
			for _, entity in ipairs(opaqueEntities) do
				if not entity.mesh then
					goto continue
				end

				local modelToWorld = mathsies.mat4.transform(
					entity.position,
					entity.orientation,
					entity.scale
				)
				self.shadowDepthShader:send("modelToWorld", {mathsies.mat4.components(modelToWorld)})

				love.graphics.drawInstanced(entity.mesh, 6)

			    ::continue::
			end

			-- self.shadowDepthToColourShader:send("shadowCubemap", self.shadowCubemap)
			-- self.shadowDepthToColourShader:send("shadowColourCubemap", self.shadowColourCubemaps[pointLightIndex])
			-- local w, h, d = self.shadowDepthToColourShader:getLocalThreadgroupSize()
			-- love.graphics.dispatchThreadgroups(self.shadowDepthToColourShader,
			-- 	math.ceil(consts.shadowCubemapSideLength / w),
			-- 	math.ceil(consts.shadowCubemapSideLength / h),
			-- 	math.ceil(6 / d)
			-- )

			love.graphics.setCanvas({
				self.shadowColourCubemaps[pointLightIndex],
				shaderlayer = true
			})
			love.graphics.setColorMask()
			love.graphics.setDepthMode("always", false)
			love.graphics.setMeshCullMode("none")
			love.graphics.setBlendMode("replace", "premultiplied")
			love.graphics.setShader(self.shadowDepthToColourShader)
			self.shadowDepthToColourShader:send("shadowCubemap", self.shadowCubemap)
			love.graphics.drawInstanced(self.dummyMesh, 6)

			love.graphics.setCanvas({
				self.shadowColourCubemaps[pointLightIndex],
				depthstencil = self.shadowCubemap,
				shaderlayer = true
			})
			love.graphics.setDepthMode("lequal", false)
			love.graphics.setBlendState("min", "one", "one")
			love.graphics.setShader(self.shadowDepthShader)
			for _, entity in ipairs(windowsAndPointLights) do
				if not entity.windowInfo then
					goto continue
				end

				local meshWidth, meshHeight = 2, 2
				local modelToWorld = mathsies.mat4.transform(
					entity.position,
					entity.orientation,
					mathsies.vec3(entity.windowInfo.width / meshWidth, entity.windowInfo.height / meshHeight, 1)
				)
				self.shadowDepthShader:send("modelToWorld", {mathsies.mat4.components(modelToWorld)})
				-- self.shadowDepthShader:send("modelToWorldNormal", {util.normalMatrix(modelToWorld)})
				self.shadowDepthShader:send("randomSeed", love.math.random(0, 2 ^ 32 - 1))
				self.shadowDepthShader:send("windowAlbedoTexture", entity.albedo)
				self.shadowDepthShader:send("windowTransmittanceTexture", entity.windowInfo.transmittanceTexture)

				love.graphics.drawInstanced(self.windowMesh, 6)

				::continue::
			end

			if #pointLightsToDraw >= consts.maxPointLights then
				break
			end

			::continue::
		end

		-- Draw opaque objects to light canvas and depth canvas
		love.graphics.setCanvas({self.screenCanvasses.opaqueObjectLightCanvas, depthstencil = self.screenCanvasses.shipDepthCanvas})
		love.graphics.setDepthMode("lequal", true)
		love.graphics.clear({0, 0, 0, 0}, false, true) -- Clear opaque object light and depth
		love.graphics.setBlendMode("replace", "premultiplied") -- dst.rgba = src.rgba
		love.graphics.setShader(self.entityShader)
		love.graphics.setMeshCullMode("back")
		self.entityShader:send("randomSeed", love.math.random(0, 2 ^ 32 - 1))
		local function sendToShaders(var, ...)
			self.entityShader:send(var, ...)
			self.windowShader:send(var, ...)
		end
		sendToShaders("pointLightCount", #pointLightsToDraw)
		if #pointLightsToDraw > 0 then
			local intensities, radii, positions = {}, {}, {}
			for i = 1, consts.maxPointLights do
				local light = pointLightsToDraw[i]
				if not light then
					goto continue
				end
				intensities[i] = {mathsies.vec3.components(light.pointLightInfo.radiantIntensity)}
				radii[i] = self:getPointLightRadius(light.pointLightInfo.radiantIntensity)
				positions[i] = {mathsies.vec3.components(light.position)}
				::continue::
			end
			sendToShaders("lightRadiantIntensities", unpack(intensities))
			sendToShaders("lightRadii", unpack(radii))
			sendToShaders("lightPositions", unpack(positions))
			sendToShaders("shadowColourMaps", unpack(self.shadowColourCubemaps))
		end
		for _, entity in ipairs(opaqueEntities) do
			if entity.mesh then
				local modelToWorld = mathsies.mat4.transform(
					entity.position,
					entity.orientation,
					entity.scale
				)
				local modelToClip = worldToClip * modelToWorld
				self.entityShader:send("modelToClip", {mathsies.mat4.components(modelToClip)})
				self.entityShader:send("modelToWorld", {mathsies.mat4.components(modelToWorld)})
				self.entityShader:send("modelToWorldNormal", {util.normalMatrix(modelToWorld)})
				self.entityShader:send("entityAlbedo", entity.albedo)
				love.graphics.draw(entity.mesh)
			end
		end

		-- Draw translucent objects
		love.graphics.setMeshCullMode("none")
		love.graphics.setBlendState("add", "one", "one") -- dst.rgba = src.rgba + dst.rgba
		love.graphics.setCanvas({lightCanvas, tempOpacityCanvas, depthstencil = self.screenCanvasses.shipDepthCanvas})
		love.graphics.setDepthMode("lequal", false)
		love.graphics.setShader(self.windowShader)
		self.windowShader:send("transmittanceCanvas", transmittanceCanvas)
		self.windowShader:send("cameraPosition", {mathsies.vec3.components(POVEntity.position)})
		for _, entity in ipairs(windowsAndPointLights) do
			if entity.pointLightInfo then
				local difference = worldToCamera * entity.position
				local distance = #difference
				local direction = difference / distance
				local radiantIntensity = entity.pointLightInfo.radiantIntensity
				local radiance = radiantIntensity / distance ^ 2 * pointRadianceCalcConst
				local radianceTable = {mathsies.vec3.components(radiance)}
				self:addMiscPointWithCurrentTransmittanceCanvas(direction, radianceTable, cameraToClip, false, nil, true, consts.POVFarDistance, consts.POVNearDistance, difference.z)
			else
				local meshWidth, meshHeight = 2, 2
				local modelToWorld = mathsies.mat4.transform(
					entity.position,
					entity.orientation,
					mathsies.vec3(entity.windowInfo.width / meshWidth, entity.windowInfo.height / meshHeight, 1)
				)
				local modelToClip = worldToClip * modelToWorld
				self.windowShader:send("modelToClip", {mathsies.mat4.components(modelToClip)})
				self.windowShader:send("modelToWorld", {mathsies.mat4.components(modelToWorld)})
				self.windowShader:send("modelToWorldNormal", {util.normalMatrix(modelToWorld)})
				self.windowShader:send("entityTransmittance", entity.windowInfo.transmittanceTexture)
				self.windowShader:send("entityAlbedo", entity.albedo)
				love.graphics.draw(self.windowMesh)
				self:handleObjectTransmittance()
			end
		end

		love.graphics.setShader()
		-- Multiply down light from opaque objects behind translucent ones
		love.graphics.setBlendMode("multiply", "premultiplied")
		love.graphics.setCanvas(self.screenCanvasses.opaqueObjectLightCanvas)
		love.graphics.draw(transmittanceCanvas)
		-- Add multiplied-down light from opaque objects to light currently hitting camera
		love.graphics.setBlendState("add", "one", "one")
		love.graphics.setCanvas(lightCanvas)
		love.graphics.draw(self.screenCanvasses.opaqueObjectLightCanvas)

		love.graphics.setBlendMode("replace", "premultiplied") -- dst.rgba = src.rgba
		love.graphics.setDepthMode("always", false)
		love.graphics.setCanvas(transmittanceCanvas)
		love.graphics.setShader(self.opaqueFromDepthShader)
		love.graphics.draw(self.screenCanvasses.shipDepthCanvas)
		love.graphics.setShader()
		love.graphics.setBlendMode("alpha")
	end

	local function drawStarSystem()
		setupCameraVars(mathsies.quat())

		local lastPointLayer = self.pointLayers[#self.pointLayers]
		local starSystemPointLayerObject = lastPointLayer.currentObject
		if not starSystemPointLayerObject then
			return
		end
		local bodies = starSystemPointLayerObject.bodies

		local cameraPositionRelative = bm.vec3.toMathsiesVec3(cameraPositionFull - starSystemPointLayerObject.position)

		local bodiesToDraw = {}
		for _, body in ipairs(bodies) do
			local difference = body.position - cameraPositionRelative
			local distance = #difference
			local lerpFromBodyToPoint = self:getLerpFromBodyToPoint(distance, body.radius)

			table.insert(bodiesToDraw, {
				body = body,
				fullMul = 1 - lerpFromBodyToPoint,
				pointMul = lerpFromBodyToPoint
			})
		end
		table.sort(bodiesToDraw, function(a, b)
			-- If A is closer than B, then it is drawn first
			return mathsies.vec3.distance(cameraPositionRelative, a.body.position) < mathsies.vec3.distance(cameraPositionRelative, b.body.position)
		end)
		for _, bodyInfo in ipairs(bodiesToDraw) do
			local fullMul = bodyInfo.fullMul
			local pointMul = bodyInfo.pointMul
			local body = bodyInfo.body

			-- Draw as point (must be done first, before transmittance from full rendering is applied)
			if pointMul ~= 0 then
				local difference = body.position - cameraPositionRelative
				local distance = #difference
				local direction = difference / distance
				local radiantIntensity
				if body.type == "star" then -- TODO: Calculate radiance of distant planets (when we even have any)
					radiantIntensity = body.radiantIntensity
				end
				local radiance = radiantIntensity / distance ^ 2 * consts.celestialRadianceMultiplier * pointMul * pointRadianceCalcConst
				local radianceTable = {mathsies.vec3.components(radiance)}
				self:addMiscPointWithCurrentTransmittanceCanvas(worldToCameraStationary * direction, radianceTable, cameraToClip)
			end

			-- Draw fully
			if fullMul ~= 0 then
				local bodyShader
				if body.type == "star" then
					bodyShader = self.starShader
					-- TODO: Ensure the overall radiant intensity of stars is correct across all size scales still
					bodyShader:send("surfaceRadiance", {mathsies.vec3.components(body.radiantFlux / (4 * consts.pi * body.radius ^ 2) / consts.pi)})
					-- local set = self.starSystemLookupInfoSet[body.systemStarNumber]
					-- bodyShader:send("absorptionLUT", set.absorptionLUTCanvas)
					-- bodyShader:send("scatteringLUT", set.scatteringLUTCanvas)
					-- bodyShader:send("emissionLUT", set.emissionLUTCanvas)
				end
				bodyShader:send("preNormaliseCornerDirs", unpack(cornerDirs))
				bodyShader:send("size", {lightCanvas:getDimensions()})
				bodyShader:send("outputMultiplier", consts.celestialRadianceMultiplier * fullMul)
				bodyShader:send("bodyPosition", {mathsies.vec3.components(body.position)})
				bodyShader:send("bodyRadius", body.radius)
				bodyShader:send("cameraPosition", {mathsies.vec3.components(cameraPositionRelative)})
				bodyShader:send("transmittanceCanvas", transmittanceCanvas)
				bodyShader:send("lightCanvas", lightCanvas)

				local w, h = bodyShader:getLocalThreadgroupSize()
				love.graphics.dispatchThreadgroups(bodyShader,
					math.ceil(lightCanvas:getWidth() / w),
					math.ceil(lightCanvas:getHeight() / h)
				)
			end
		end
	end

	drawShip()

	drawStarSystem()

	if #self.pointLayers > 0 then
		-- NOTE: Since attenuation coefficients are expected to be much much lower in larger layers than they are in smaller layers,
		-- and objects (and so raymarching path lengths) in smaller layers are expected to be much much smaller than they are in larger layers,
		-- any inaccuracies around not considering the adding of attenuation coefficients where layer attenuations intersect are considered negligible.
		-- However, if needed, the attenuation coefficient from a large layer at the position of an object within that layer could be added when raymarching.

		for i = smallestActiveLayer.index, 1, -1 do
			local pointLayer = self.pointLayers[i]
			drawLayer(pointLayer) -- Writes to its own radiance/transmittance accumulation canvasses and also writes points to the point drawable buffer
			love.graphics.setCanvas({lightCanvas, tempOpacityCanvas})
			love.graphics.setBlendState("add", "one", "one") -- dst.rgba = src.rgba + dst.rgba
			love.graphics.setShader(self.drawVolumetricShader)
			self.drawVolumetricShader:send("transmittanceCanvas", transmittanceCanvas)
			self.drawVolumetricShader:send("objectTransmittanceCanvas", pointLayer.volumetricTransmittanceCanvas)
			self.drawVolumetricShader:send("additions", pointLayer.volumetricAddCountCanvas)
			self.drawVolumetricShader:send("scale", consts.volumetricCanvasScale)
			love.graphics.draw(pointLayer.volumetricCanvas, 0, 0, 0, 1 / consts.volumetricCanvasScale)
			love.graphics.setShader()

			self:handleObjectTransmittance()
		end
	end

	-- Finally draw any point light sources as blurred-out disks
	love.graphics.setBlendState("add", "one", "one")
	love.graphics.setCanvas(lightCanvas)
	setupCameraVars(mathsies.quat())
	local drawShader = self.pointDrawablesShader
	love.graphics.setShader(drawShader)
	drawShader:send("PointDrawables", self.pointDrawableBuffer)
	drawShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
	drawShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
	drawShader:send("cameraToClip", {mathsies.mat4.components(cameraToClip)})
	love.graphics.drawIndirect(self.pointDiskMesh, self.pointIndirectDrawArgsBuffer, 1)

	love.graphics.setBlendMode("alpha")
	love.graphics.setShader()
	love.graphics.setCanvas()
end

function game:handleObjectTransmittance()
	-- Assumes canvas is {lightCanvas, tempOpacityCanvas}
	local w, h = self.applyTempTransmittanceShader:getLocalThreadgroupSize()
	self.applyTempTransmittanceShader:send("tempOpacityCanvas", self.screenCanvasses.tempOpacityCanvas)
	self.applyTempTransmittanceShader:send("transmittanceCanvas", self.screenCanvasses.transmittanceCanvas)
	love.graphics.dispatchThreadgroups(self.applyTempTransmittanceShader,
		math.ceil(self.screenCanvasses.transmittanceCanvas:getWidth() / w),
		math.ceil(self.screenCanvasses.transmittanceCanvas:getHeight() / h)
	)
end

function game:getPointOutputMultiplier()
	-- The below calculation gets pointOutputMultiplier, which is used to keep the integral over the disk a point light occupies the same as it is if light on in the disk is always 1.
	-- Not analytical because of the use of pow, it seems
	local integralSteps = 20
	local stepSize = consts.pointAngularRadius / integralSteps
	local diskStarlightIntegral = 0
	for angle = 0, consts.pointAngularRadius, stepSize do
		local fade = angle / consts.pointAngularRadius
		local shape = (1 - fade) ^ consts.pointDiskFadeExponent -- Must match pointDrawables.glsl's shape variable
		local integralHere = math.sin(angle) * shape
		diskStarlightIntegral = diskStarlightIntegral + integralHere * stepSize
	end
	local integralForFlatDiskStarlight = 1 - math.cos(consts.pointAngularRadius)
	local pointOutputMultiplier = integralForFlatDiskStarlight / diskStarlightIntegral -- Used to ensure the integral across the spherical cap remains the same as if output shape was constant 1
	return pointOutputMultiplier
end

function game:addMiscPointWithCurrentTransmittanceCanvas(cameraSpaceDir, radiance, cameraToClip, usePointTransmittance, distanceInFadeoutRadii, useShipDepthCanvas, far, near, pointZ)
	if not usePointTransmittance and not distanceInFadeoutRadii then
		distanceInFadeoutRadii = 0 -- Won't have any effect
	end
	local shader = self.miscPointAddShader
	shader:send("PointDrawables", self.pointDrawableBuffer)
	shader:send("IndirectDrawBuffer", self.pointIndirectDrawArgsBuffer)
	local clipSpace = cameraToClip * cameraSpaceDir
	local textureCoordX = clipSpace.x * 0.5 + 0.5
	local textureCoordY = clipSpace.y * 0.5 + 0.5
	shader:send("direction", {mathsies.vec3.components(cameraSpaceDir)})
	shader:send("unattenuatedRadiance", radiance)
	shader:send("pointAttenuationTexture", usePointTransmittance and self.pointAttenuationTexture or self.clearPointAttenuationTexture)
	shader:send("attenuationTextureCoords", {textureCoordX, textureCoordY, distanceInFadeoutRadii}) -- Will sample from transmittance even if point attenuation isn't sampled
	shader:send("useDepthCanvas", not not useShipDepthCanvas)
	if useShipDepthCanvas then
		shader:send("shipDepthCanvas", self.screenCanvasses.shipDepthCanvas)
		shader:send("far", far)
		shader:send("near", near)
		shader:send("pointZ", pointZ)
	end
	shader:send("totalTransmittanceCanvas", self.screenCanvasses.transmittanceCanvas)
	love.graphics.dispatchThreadgroups(shader, 1)
end

function game:drawPointBuffer(buffer, argsIndex, cameraUp, cameraRight, skyToClip)
	local drawShader = self.pointDrawablesShader
	love.graphics.setShader(drawShader)
	drawShader:send("PointDrawables", buffer)
	drawShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
	drawShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
	drawShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
	love.graphics.drawIndirect(self.pointDiskMesh, self.pointIndirectDrawArgsBuffer, argsIndex)
end

function game:getLerpFromBodyToPoint(distance, radius)
	local resolvableDistance = self:getSphereResolvableDistance(radius)
	local shouldDrawBody = distance <= resolvableDistance * consts.bodyToPointLerpEnd
	if not shouldDrawBody then
		return 1
	end
	local lerpFromBodyToPoint
	if consts.bodyToPointLerpStart == consts.bodyToPointLerpEnd then
		lerpFromBodyToPoint = 0 -- No transition fade
	else
		lerpFromBodyToPoint = math.max(0, math.min(1,
			(distance / resolvableDistance - consts.bodyToPointLerpStart) /
			(consts.bodyToPointLerpEnd - consts.bodyToPointLerpStart)
		))
	end
	return lerpFromBodyToPoint
end

function game:getPointLightRadius(radiantIntensity)
	return math.max(
		math.sqrt(radiantIntensity.x / consts.pointLightCutoffRadiance),
		math.sqrt(radiantIntensity.y / consts.pointLightCutoffRadiance),
		math.sqrt(radiantIntensity.z / consts.pointLightCutoffRadiance)
	)
end

function game:newSpectralImageFromRGB(path)
	local currentColour = mathsies.vec3()
	local whiteSpectral = self:rgbToSpectralRadiance(mathsies.vec3(1, 1, 1))
	local data = love.image.newImageData(path)
	data:mapPixel(function(x, y, r, g, b, a)
		-- TODO: Opacity data
		currentColour.x = r
		currentColour.y = g
		currentColour.z = b
		local binR, binG, binB = mathsies.vec3.components(self:rgbToSpectralRadiance(currentColour) / whiteSpectral)
		return binR, binG, binB, 0
	end)
	return love.graphics.newImage(data, {linear = true})
end

function game:rgbToSpectralRadiance(rgb)
	local bins = self.rgbToSpectralMatrix * rgb
	-- Disallow negatives. Negatives can happen due to stimulus responses overlapping within spectral bins.
	-- Eg if you wanted to convert pure RGB green to the 3 spectral bins (reddish, greenish, and blueish),
	-- then the reddish bin is made negative to compensate for the perceptual red that comes from the
	-- greenish bin. Except, negative spectral radiances are impossible, so... we clamp them out. This
	-- means that pure RGB green is unattainable in this bins-based renderer, despite being a perfectly
	-- physically-representable colour.
	bins.x = math.max(0, bins.x)
	bins.y = math.max(0, bins.y)
	bins.z = math.max(0, bins.z)
	return bins
end

function game:lightIntensityFromRGBAtDist(rgb, dist)
	return self:rgbToSpectralRadiance(rgb) * dist ^ 2
end

return game
