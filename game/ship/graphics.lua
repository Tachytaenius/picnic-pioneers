local mathsies = require("lib.mathsies")

local consts = require("consts")

local game = {}

function game:drawPlayerPOV(player)
	local shipCanvas = self.screenCanvasses.shipCanvas
	local aspectRatio = shipCanvas:getWidth() / shipCanvas:getHeight()

	local cameraPosition = player.position
	local cameraOrientation = player.orientation
	local cameraVerticalFOV = player.verticalFOV
	local worldToCamera = mathsies.mat4.camera(
		cameraPosition + mathsies.vec3.rotate(player.cameraOffset, player.orientation),
		cameraOrientation
	)
	local cameraToClip = mathsies.mat4.perspectiveLeftHanded(
		aspectRatio,
		cameraVerticalFOV,
		consts.POVFarDistance,
		consts.POVNearDistance
	)
	local worldToClip = cameraToClip * worldToCamera

	local bugGone = false -- There's a bug in love.graphics.clear on Vulkan.
	if bugGone then
		error("Then clean up this code!")
		love.graphics.setCanvas({
			self.screenCanvasses.shipCanvas,
			self.screenCanvasses.pointTotalTransmittanceCanvas,
			depth = true
		})
		love.graphics.clear(
			{0, 0, 0, 0}, -- Clear ship canvas to transparent black
			{1, 0, 0, 1}, -- Clear point total transmittance canvas to white
			false, true -- Ignore stencil, clear depth
		)
	else
		love.graphics.setCanvas(self.screenCanvasses.shipCanvas)
		love.graphics.clear(0, 0, 0, 0)
		love.graphics.setCanvas(self.screenCanvasses.pointTotalTransmittanceCanvas)
		love.graphics.clear(1, 0, 0, 1)
		love.graphics.setCanvas({
			self.screenCanvasses.shipCanvas,
			self.screenCanvasses.pointTotalTransmittanceCanvas,
			depth = true
		})
		love.graphics.clear(false, false, true)
	end

	love.graphics.setDepthMode("lequal", true)

	love.graphics.setShader(self.entityShader)
	for _, entity in ipairs(self.entities) do
		local modelToWorld = mathsies.mat4.transform(
			entity.position,
			entity.orientation
		)
		local modelToClip = worldToClip * modelToWorld
		self.entityShader:send("modelToClip", {mathsies.mat4.components(modelToClip)})
		self.entityShader:send("entityTexture", entity.texture)
		love.graphics.draw(entity.mesh)
	end
	love.graphics.setShader()

	love.graphics.setDepthMode("always", false)
	love.graphics.setCanvas()
end

return game
