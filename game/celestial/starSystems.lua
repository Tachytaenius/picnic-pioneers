local util = require("util")
local consts = require("consts")
local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local game = {}

function game:generateStarSystem(layerObject)
	local remainingMass = layerObject.mass

	local bodies = {}

	-- All heavily TODO

	local starMass = remainingMass
	remainingMass = 0
	local starDensity = 1408
	local starVolume = starMass / starDensity
	local star = {
		type = "star",
		mass = starMass,
		radius = (starVolume / (2 / 3 * consts.tau)) ^ (1 / 3),
		luminousFlux = layerObject.luminousFlux,
		position = mathsies.vec3(0, 0, 0) -- TODO: Kepler orbits
	}
	table.insert(bodies, star)

	layerObject.bodies = bodies
end

function game:drawStarSystem()
	-- TODO: Don't copy so much from drawPointLayers! Maybe just unify into a function like drawCelestial...?

	local lastPointLayer = self.pointLayers[#self.pointLayers]
	local starSystemPointLayerObject = lastPointLayer.currentObject
	if not starSystemPointLayerObject then
		return
	end
	local bodies = starSystemPointLayerObject.bodies

	local cameraPositionFull = self.ship.position
	local cameraPositionRelative = bm.vec3.toMathsiesVec3(self.ship.position - starSystemPointLayerObject.position)

	local cameraOrientation = self.ship.orientation
	local cameraVerticalFOV = self.ship.verticalFOV
	local outputCanvas = love.graphics.getCanvas()
	local aspectRatio = outputCanvas:getWidth() / outputCanvas:getHeight()

	local cameraForwards = mathsies.vec3.rotate(consts.forwardVector, cameraOrientation)
	local cameraUp = mathsies.vec3.rotate(consts.upVector, cameraOrientation)
	local cameraRight = mathsies.vec3.rotate(consts.rightVector, cameraOrientation)
	local cameraToClip = mathsies.mat4.perspectiveLeftHanded(
		aspectRatio,
		cameraVerticalFOV,
		2,
		0.5
	)
	local worldToCameraStationary = mathsies.mat4.camera(mathsies.vec3(), cameraOrientation)
	local skyToClip = cameraToClip * worldToCameraStationary
	local clipToSky = mathsies.mat4.inverse(skyToClip)

	local diskDistanceToSphere = 1 - math.cos(consts.pointAngularRadius) -- Unit sphere spherical cap height from angular radius
	local diskSolidAngle = consts.tau * diskDistanceToSphere
	local scaleToGetAngularRadius = math.tan(consts.pointAngularRadius)
	local luminanceCalcConst = 1 / (diskSolidAngle * 2 * consts.tau)

	self.individualPointShader:send("diskDistanceToSphere", diskDistanceToSphere)
	self.individualPointShader:send("scale", scaleToGetAngularRadius)
	self.individualPointShader:send("skyToClip", {mathsies.mat4.components(skyToClip)})
	self.individualPointShader:send("cameraUp", {mathsies.vec3.components(cameraUp)})
	self.individualPointShader:send("cameraRight", {mathsies.vec3.components(cameraRight)})

	for _, body in ipairs(bodies) do
		local difference = body.position - cameraPositionRelative
		local distance = #difference
		local direction = difference / distance
		local resolvable = distance <= self:getSphereResolvableDistance(body.radius)

		if not resolvable then
			love.graphics.setBlendMode("add")
			local luminance
			if body.type == "star" then
				luminance = body.luminousFlux / distance ^ 2 * luminanceCalcConst
			end
			self.individualPointShader:send("direction", {mathsies.vec3.components(direction)})
			self.individualPointShader:send("luminance", {mathsies.vec3.components(luminance)})
			love.graphics.setShader(self.individualPointShader)
			love.graphics.draw(self.pointDiskMesh)
			love.graphics.setBlendMode("alpha")
		else
			if body.type == "star" then
				love.graphics.setShader(self.starShader)
				local surfaceArea = 2 * consts.tau * body.radius ^ 2
				local surfaceLuminousExitance = body.luminousFlux / surfaceArea
				local surfaceLuminance = surfaceLuminousExitance / (consts.tau / 2) -- Lambertian emitter
				self.starShader:send("surfaceLuminance", {mathsies.vec3.components(surfaceLuminance)})
				self.starShader:send("bodyPosition", {mathsies.vec3.components(body.position)}) -- TEMP
				self.starShader:send("bodyRadius", body.radius)
				self.starShader:send("clipToSky", {mathsies.mat4.components(clipToSky)})
				self.starShader:send("cameraPosition", {mathsies.vec3.components(cameraPositionRelative)}) -- TEMP
				love.graphics.draw(self.dummyTexture, 0, 0, 0, outputCanvas:getDimensions())
			end
		end
	end
	love.graphics.setShader()
end

return game
