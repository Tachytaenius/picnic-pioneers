local mathsies = require("lib.mathsies")
local bm = require("bigmaths")
local consts = require("consts")

local game = {}

function game:drawCelestial(POVEntity)
	local outputCanvas = self.screenCanvasses.outputCanvas
	love.graphics.setCanvas(outputCanvas)

	local aspectRatio = outputCanvas:getWidth() / outputCanvas:getHeight()

	local radianceMultiplier = consts.celestialRadianceMultiplier

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

	local cameraPositionFull = self.ship.position
	local cameraOrientation = self.ship.orientation
	local cameraVerticalFOV = POVEntity.verticalFOV
	local diagonalFOV = 2 * math.atan(math.sqrt(1 ^ 2 + aspectRatio ^ 2) * math.tan(cameraVerticalFOV / 2))

	local vertexZAtFurthestAngle = math.cos(diagonalFOV / 2)
	local cameraToClip = mathsies.mat4.perspectiveLeftHanded(
		aspectRatio,
		cameraVerticalFOV,
		-- 1, -- Only a point disk vertex right in the centre of the screen has any chance of being clipped, and it will just be pushed slightly away from the centre. I don't see how any holes could form.
		1.01, -- But whatever lol
		-- vertexZAtFurthestAngle
		vertexZAtFurthestAngle * 0.99
	)

	local cameraForwards, cameraUp, cameraRight, worldToCameraStationary, skyToClip, clipToSky, cornerDirs

	local function setupCameraVars(layerOrientation)
		local layerTotalOrientation = layerOrientation * cameraOrientation

		cameraForwards = mathsies.vec3.rotate(consts.forwardVector, layerTotalOrientation)
		cameraUp = mathsies.vec3.rotate(consts.upVector, layerTotalOrientation)
		cameraRight = mathsies.vec3.rotate(consts.rightVector, layerTotalOrientation)
		worldToCameraStationary = mathsies.mat4.camera(mathsies.vec3(), layerTotalOrientation)
		skyToClip = cameraToClip * worldToCameraStationary
		clipToSky = mathsies.mat4.inverse(skyToClip)

		cornerDirs = {}
		for y = 1, -1, -2 do
			for x = -1, 1, 2 do
				local clipSpacePos = mathsies.vec3(x, y, -1) -- -1 for near plane but it makes no difference once everything is normalised in the compute shader(s). It may need to be consistent per-corner, though
				local result = clipToSky * clipSpacePos
				table.insert(cornerDirs, {mathsies.vec3.components(result)})
			end
		end
	end

	-- local vec = mathsies.vec3(1, 1, 1) -- 1, 1 for top right. Z doesn't matter because of normalisation below.
	-- vec = clipToSky * vec
	-- local angle = math.acos(mathsies.vec3.dot(mathsies.vec3.normalise(vec), mathsies.vec3(0, 0, 1)))
	-- print(angle - diagonalFOV / 2) -- Very very very close to 0. This feels like confirmation that the diagonal FOV calculation is correct.

	local function drawLayer(pointLayer, pointMode)
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

		if not pointMode then
			-- Volumetrics

			if pointLayer.volumetricCanvasCameraInfo then
				if
					pointLayer.volumetricCanvasCameraInfo.position ~= cameraPositionFull or
					pointLayer.volumetricCanvasCameraInfo.orientation ~= cameraOrientation or
					pointLayer.volumetricCanvasCameraInfo.verticalFOV ~= cameraVerticalFOV or
					pointLayer.volumetricCanvasCameraInfo.brightnessMultiplier ~= radianceMultiplier
				then
					-- TODO: Reprojection
					local original = love.graphics.getCanvas()
					love.graphics.setCanvas(pointLayer.volumetricCanvas)
					love.graphics.clear()
					love.graphics.setCanvas(pointLayer.volumetricAddCountCanvas)
					love.graphics.clear()
					love.graphics.setCanvas(original)
				end
			end
			pointLayer.volumetricCanvasCameraInfo = {
				position = bm.vec3.clone(cameraPositionFull),
				orientation = mathsies.quat.clone(cameraOrientation),
				verticalFOV = cameraVerticalFOV,
				brightnessMultiplier = radianceMultiplier
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

			volumetricShader:send("brightnessMultiplier", radianceMultiplier)
			volumetricShader:send("preNormaliseCornerDirs", unpack(cornerDirs))
			volumetricShader:send("size", {pointLayer.volumetricCanvas:getDimensions()})
			volumetricShader:send("resultCanvas", pointLayer.volumetricCanvas)
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
			volumetricShader:send("maxRaySteps", consts.volumetricMaxRaySteps)
			volumetricShader:send("shapeRadii", {mathsies.vec3.components(distanceUnitScale * parentObjectRadii)})
			if volumetricShader:hasUniform("baseEmission") then
				volumetricShader:send("baseEmission", {
					-- Density's distance dimension is -3, intensity's is 2 (from the m^2 in the W), so the unit scale is raised to the -1
					distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageRadiantIntensityRPerPoint,
					distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageRadiantIntensityGPerPoint,
					distanceUnitScale ^ -1 * pointLayer.maxPointDensity * pointLayer.averageRadiantIntensityBPerPoint
				})
			end
			if volumetricShader:hasUniform("baseAttenuation") then
				volumetricShader:send("baseAttenuation", attenuationMultiplier / distanceUnitScale)
			end
			local w, h = volumetricShader:getLocalThreadgroupSize()
			love.graphics.dispatchThreadgroups(volumetricShader,
				math.ceil(pointLayer.volumetricCanvas:getWidth() / w),
				math.ceil(pointLayer.volumetricCanvas:getHeight() / h)
			)

			love.graphics.setShader(self.drawVolumetricShader)
			love.graphics.setBlendMode("alpha", "premultiplied")
			love.graphics.setColorMask(true, true, true, false)
			self.drawVolumetricShader:send("additions", pointLayer.volumetricAddCountCanvas)
			self.drawVolumetricShader:send("scale", consts.volumetricCanvasScale)
			love.graphics.draw(pointLayer.volumetricCanvas, 0, 0, 0, 1 / consts.volumetricCanvasScale)
			love.graphics.setColorMask()
		else
			love.graphics.setBlendMode("add")
			love.graphics.setCanvas(outputCanvas) -- Drawing after volumetrics and solid bodies etc

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
				if pointAttenuationShader:hasUniform("baseAttenuation") then
					pointAttenuationShader:send("baseAttenuation", attenuationMultiplier / distanceUnitScale)
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

			self.pointIndirectDrawArgsBuffer:setArrayData({
				self.pointDiskMesh:getVertexCount(),
				0, -- This gets incremented (on the GPU)
				0,
				0
			})

			local diskDistanceToSphere = 1 - math.cos(consts.pointAngularRadius) -- Unit sphere spherical cap height from angular radius
			local diskSolidAngle = consts.tau * diskDistanceToSphere
			local scaleToGetAngularRadius = math.tan(consts.pointAngularRadius)
			local radianceCalcConst = radianceMultiplier * pointOutputMultiplier / diskSolidAngle

			local maxAngleFromCentre = diagonalFOV / 2 + consts.pointAngularRadius
			local minDot = math.cos(maxAngleFromCentre)
			local currentObjectInfo = pointLayer.currentObject or pointLayer.currentPotentialObject
			local skipIndex =
				currentObjectInfo and (
					currentObjectInfo.chunkBufferIndex * pointLayer.maxPointsPerChunk + currentObjectInfo.pointId
				) or pointLayer.maxPoints -- Use unreachable skip index
			if pointLayer.currentPotentialObject and not pointLayer.currentObject then
				-- Draw in a CPU-calculated direction to fix precision issues when on the approach to small galaxies
				local object = pointLayer.currentPotentialObject
				local x, y, z = pointLayer:getPointVars(object.chunkBufferIndex, object.pointId, "position", "float", 3)
				local position = bm.vec3(object.chunkX + x, object.chunkY + y, object.chunkZ + z)
				local difference =
					position -
					bm.vec3.rotate(
						cameraPositionFullRelative / pointLayer.chunkSize,
						parentOrientation
					)
				local distance = bm.vec3.length(difference)
				if distance == 0 then
					skipIndex = pointLayer.maxPoints -- Use unreachable skip index
				else
					local direction = difference / distance
					direction = bm.vec3.toMathsiesVec3(direction)
					distance = bm.mapm.tonumber(distance)
					local r, g, b = pointLayer:getPointVars(object.chunkBufferIndex, object.pointId, "radiantIntensity", "float", 3)
					local radiance = mathsies.vec3(r, g, b) / distance ^ 2 * radianceCalcConst
					self.individualPointShader:send("pointAttenuationTexture", pointAttenuationTexture) -- Might be the clear texture
					local clipSpacePos = skyToClip * direction -- "Perspective divide" is already done (xyz is divided by w, and w isn't even stored since these are vec3s)
					self.individualPointShader:send("attenuationTextureCoords", {
						clipSpacePos.x * 0.5 + 0.5,
						clipSpacePos.y * 0.5 + 0.5,
						distance / fullyVolumetricRadius
					})
					self.individualPointShader:send("totalTransmittanceCanvas", self.screenCanvasses.pointTotalTransmittanceCanvas)

					-- self.individualPointShader:send("angularRadius", consts.pointAngularRadius)
					self.individualPointShader:send("fadeExponent", consts.pointDiskFadeExponent)
					self.individualPointShader:send("diskDistanceToSphere", diskDistanceToSphere)
					self.individualPointShader:send("scale", scaleToGetAngularRadius)
					self.individualPointShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
					self.individualPointShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
					self.individualPointShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
					self.individualPointShader:send("direction", {mathsies.vec3.components(direction)})
					self.individualPointShader:send("radiance", {mathsies.vec3.components(radiance)})
					love.graphics.setShader(self.individualPointShader)
					love.graphics.draw(self.pointDiskMesh)
				end
			end

			local preparationShader = pointLayer.pointPreparationShader
			preparationShader:send("totalTransmittanceCanvas", self.screenCanvasses.pointTotalTransmittanceCanvas)
			preparationShader:send("pointAttenuationTexture", pointAttenuationTexture)
			preparationShader:send("radianceCalcConst", radianceCalcConst)
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
			preparationShader:send("cameraForwards", {mathsies.vec3.components(cameraForwards)})
			preparationShader:send("fadeInRadius", fullyPointRadius)
			preparationShader:send("fadeOutRadius", fullyVolumetricRadius)
			preparationShader:send("fadeExponent", consts.pointFadeExponent)
			preparationShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
			preparationShader:send("skipIndex", skipIndex)
			preparationShader:send("maxPointsPerChunk", pointLayer.maxPointsPerChunk)
			preparationShader:send("IndirectDrawBuffer", self.pointIndirectDrawArgsBuffer)
			preparationShader:send("Points", pointLayer.pointBuffer)
			preparationShader:send("PointDrawables", self.pointDrawableBuffer)
			preparationShader:send("ChunkPointCounts", pointLayer.chunkPointCountBuffer)
			local threadgroupCount = math.ceil(pointLayer.maxPoints / preparationShader:getLocalThreadgroupSize())
			love.graphics.dispatchThreadgroups(preparationShader, threadgroupCount)

			local drawShader = self.pointDrawablesShader
			love.graphics.setShader(drawShader)
			drawShader:send("PointDrawables", self.pointDrawableBuffer)
			-- drawShader:send("angularRadius", consts.pointAngularRadius)
			drawShader:send("fadeExponent", consts.pointDiskFadeExponent)
			drawShader:send("diskDistanceToSphere", diskDistanceToSphere)
			drawShader:send("scale", scaleToGetAngularRadius)
			drawShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
			drawShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})
			drawShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
			-- current shader should be drawShader
			love.graphics.drawIndirect(self.pointDiskMesh, self.pointIndirectDrawArgsBuffer, 1)
		end

		love.graphics.setShader()
		love.graphics.setBlendMode("alpha")
	end

	local function drawStarSystem()
		love.graphics.setCanvas(outputCanvas)

		setupCameraVars(mathsies.quat())

		local lastPointLayer = self.pointLayers[#self.pointLayers]
		local starSystemPointLayerObject = lastPointLayer.currentObject
		if not starSystemPointLayerObject then
			return
		end
		local bodies = starSystemPointLayerObject.bodies

		local cameraPositionRelative = bm.vec3.toMathsiesVec3(cameraPositionFull - starSystemPointLayerObject.position)

		local diskDistanceToSphere = 1 - math.cos(consts.pointAngularRadius) -- Unit sphere spherical cap height from angular radius
		local diskSolidAngle = consts.tau * diskDistanceToSphere
		local scaleToGetAngularRadius = math.tan(consts.pointAngularRadius)
		local radianceCalcConst = pointOutputMultiplier / diskSolidAngle

		-- self.individualPointShader:send("angularRadius", consts.pointAngularRadius)
		self.individualPointShader:send("fadeExponent", consts.pointDiskFadeExponent)
		self.individualPointShader:send("diskDistanceToSphere", diskDistanceToSphere)
		self.individualPointShader:send("scale", scaleToGetAngularRadius)
		self.individualPointShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
		self.individualPointShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
		self.individualPointShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})

		local bodiesToDrawWhole = {} -- Gets sorted so that the furthest of these bodies is drawn first
		local bodiesToDrawAsPoints = {} -- All of these are drawn (in whatever order) after the total transmittance canvas has been multiplied down by the presence of celestial bodies (and their atmospheres) so that they may be properly attenuated.
		for _, body in ipairs(bodies) do
			local difference = body.position - cameraPositionRelative
			local distance = #difference
			local resolvable = distance <= self:getSphereResolvableDistance(body.radius)

			table.insert(resolvable and bodiesToDrawWhole or bodiesToDrawAsPoints, body)
		end
		table.sort(bodiesToDrawWhole, function(a, b)
			-- If A is further than B, then it is drawn first
			return mathsies.vec3.distance(cameraPositionRelative, a.position) > mathsies.vec3.distance(cameraPositionRelative, b.position)
		end)
		for _, body in ipairs(bodiesToDrawWhole) do
			local bodyShader
			if body.type == "star" then
				bodyShader = self.starShader
				local surfaceArea = 2 * consts.tau * body.radius ^ 2
				local surfaceRadiantExitance = body.radiantFlux / surfaceArea
				local surfaceRadiance = surfaceRadiantExitance / (consts.tau / 2) -- Lambertian emitter (TEMP)
				bodyShader:send("surfaceRadiance", {mathsies.vec3.components(surfaceRadiance)})
			end
			love.graphics.setShader(bodyShader)
			bodyShader:send("preNormaliseCornerDirs", unpack(cornerDirs))
			bodyShader:send("size", {outputCanvas:getDimensions()})
			bodyShader:send("outputMultiplier", radianceMultiplier)
			bodyShader:send("bodyPosition", {mathsies.vec3.components(body.position)}) -- TEMP
			bodyShader:send("bodyRadius", body.radius)
			-- bodyShader:send("clipToSky", {mathsies.mat4.components(clipToSky)})
			bodyShader:send("cameraPosition", {mathsies.vec3.components(cameraPositionRelative)}) -- TEMP
			bodyShader:send("totalTransmittanceCanvas", self.screenCanvasses.pointTotalTransmittanceCanvas)
			bodyShader:send("outputCanvas", outputCanvas)

			local w, h = bodyShader:getLocalThreadgroupSize()
			love.graphics.dispatchThreadgroups(bodyShader,
				math.ceil(outputCanvas:getWidth() / w),
				math.ceil(outputCanvas:getHeight() / h)
			)
		end
		for _, body in ipairs(bodiesToDrawAsPoints) do
			local difference = body.position - cameraPositionRelative
			local distance = #difference
			local direction = difference / distance

			love.graphics.setBlendMode("add")
			local radiance
			if body.type == "star" then -- TODO: Calculate radiance of distant planets (when we even have any)
				radiance = body.radiantIntensity / distance ^ 2 * radianceCalcConst
			end
			self.individualPointShader:send("direction", {mathsies.vec3.components(direction)})
			self.individualPointShader:send("radiance", {mathsies.vec3.components(radiance * radianceMultiplier)})
			love.graphics.setShader(self.individualPointShader)
			love.graphics.draw(self.pointDiskMesh)
			love.graphics.setBlendMode("alpha")
		end
		love.graphics.setShader()
	end

	-- TODO: Reorganise and reconsolidate graphics state changes!

	-- NOTE: Since attenuation coefficients are expected to be much much lower in larger layers than they are in smaller layers,
	-- and objects (and so raymarching path lengths) in smaller layers are expected to be much much smaller than they are in larger layers,
	-- any inaccuracies around not considering the adding of attenuation coefficients where layer attenuations intersect are considered negligible.

	local smallestActiveLayer = self.pointLayers[1]
	for _, pointLayer in ipairs(self.pointLayers) do
		if pointLayer.parentPointLayer and not pointLayer.parentPointLayer.currentObject then
			break -- Outside of any objects below this scale
		end
		smallestActiveLayer = pointLayer
		drawLayer(pointLayer, false)
	end

	love.graphics.setShader(self.transmittanceOutputMultiplierShader)
	love.graphics.setBlendMode("multiply", "premultiplied")
	love.graphics.setCanvas(outputCanvas)
	love.graphics.draw(self.screenCanvasses.pointTotalTransmittanceCanvas) -- At this point the only thing that will have drawn into this is the entities on the ship

	love.graphics.setCanvas()
	love.graphics.setShader()
	love.graphics.setBlendMode("alpha")

	drawStarSystem()

	if #self.pointLayers > 0 then
		for i = smallestActiveLayer.index, 1, -1 do
			local pointLayer = self.pointLayers[i]
			drawLayer(pointLayer, true) -- Sets canvas to output canvas
			love.graphics.setCanvas(self.screenCanvasses.pointTotalTransmittanceCanvas)
			love.graphics.setBlendMode("multiply", "premultiplied")
			love.graphics.setShader(self.attenuationAccumulationShader) -- Outputs alpha into red after dividing by additions
			self.attenuationAccumulationShader:send("additionCanvas", pointLayer.volumetricAddCountCanvas)
			self.attenuationAccumulationShader:send("canvasSize", {pointLayer.volumetricCanvas:getDimensions()})
			love.graphics.draw(pointLayer.volumetricCanvas, 0, 0, 0, 1 / consts.volumetricCanvasScale)
			love.graphics.setShader()
		end
	end
	love.graphics.setShader()
	love.graphics.setCanvas()
	love.graphics.setBlendMode("alpha")
end

return game
