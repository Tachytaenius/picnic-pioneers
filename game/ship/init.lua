local consts = require("consts")
local mathsies = require("lib.mathsies")

local util = require("util")

local game = {}

function game:initShip()
	-- Basic init
	self.shipTime = 0

	-- Create entities (including players)
	self.players = {}
	self.entities = {}
	local player1 = {
		position = mathsies.vec3(0, 1, -2),
		cameraOffset = mathsies.vec3(0, 2, 1),
		orientation = mathsies.quat(),
		verticalFOV = 70 * consts.tau / 360,
		maxSpeed = 5,
		maxAngularSpeed = 1.5
		-- mesh = util.loadObj("art/mrTestFace/mesh.obj"),
		-- texture = love.graphics.newImage("art/mrTestFace/texture.png")
	}
	self.players[1] = player1
	table.insert(self.entities, player1)

	table.insert(self.entities, {
		position = mathsies.vec3(0, -1, 0),
		orientation = mathsies.quat(),
		scale = 12,
		mesh = util.loadObj("art/shipTest/mesh.obj"),
		texture = love.graphics.newImage("art/shipTest/texture.png")
	})

	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(2, 0, 3),
	-- 	orientation = mathsies.quat(),
	-- 	mesh = util.loadObj("art/mrTestFace/mesh.obj"),
	-- 	texture = love.graphics.newImage("art/mrTestFace/texture.png")
	-- })
	table.insert(self.entities, {
		position = mathsies.vec3(-2.5, 3, -1),
		orientation = mathsies.quat(),
		mesh = util.loadObj("art/the2/mesh.obj"),
		texture = love.graphics.newImage("art/the2/texture.png")
	})

	table.insert(self.entities, {
		position = mathsies.vec3(3, 2.5, -3),
		orientation = mathsies.quat(),
		mesh = util.loadObj("art/the2/mesh.obj"),
		texture = love.graphics.newImage("art/the2/texture.png")
	})

	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(0, 0, 8.25),
	-- 	orientation = mathsies.quat(),
	-- 	windowInfo = {
	-- 		width = 9,
	-- 		height = 3,
	-- 		transmittanceTexture = love.graphics.newImage("art/windowTransmittance.png")
	-- 	}
	-- })
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(1.5, -1, 9),
	-- 	orientation = mathsies.quat(),
	-- 	windowInfo = {
	-- 		width = 6,
	-- 		height = 5,
	-- 		transmittanceTexture = love.graphics.newImage("art/windowTransmittance.png")
	-- 	}
	-- })
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(-4, 0, 9),
	-- 	orientation = mathsies.quat.fromAxisAngle(mathsies.vec3(0.0, 0.0, -consts.tau / 4)),
	-- 	windowInfo = {
	-- 		width = 9,
	-- 		height = 4,
	-- 		transmittanceTexture = love.graphics.newImage("art/windowTransmittance.png")
	-- 	}
	-- })
	table.insert(self.entities, {
		position = mathsies.vec3(2, 1.5, 0),
		pointLightInfo = {
			radiantIntensity = mathsies.vec3(3e7, 3e7, 3e7)
		}
	})
	table.insert(self.entities, {
		position = mathsies.vec3(),
		pointLightInfo = {
			radiantIntensity = mathsies.vec3(1e8, 0, 0)
		}
	})
	table.insert(self.entities, {
		position = mathsies.vec3(),
		pointLightInfo = {
			radiantIntensity = mathsies.vec3(0, 1e8, 0)
		}
	})
	table.insert(self.entities, {
		position = mathsies.vec3(),
		pointLightInfo = {
			radiantIntensity = mathsies.vec3(0, 0, 1e8)
		}
	})

	-- Graphics init

	self.shadowCubemaps = {}
	local sideLength = consts.shadowCubemapSideLength
	for i = 1, consts.maxPointLights do
		self.shadowCubemaps[i] = love.graphics.newCanvas(sideLength, sideLength, {
			type = "cube",
			format = "depth32f",
			readable = true,
			debugname = "Shadow Cubemap " .. i
		})
	end

	self.entityShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/texelSpaceQuantisation.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/entityVertex.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/entity.glsl"),
		{defines = {
			MAX_POINT_LIGHTS = consts.maxPointLights,
			PCF_SAMPLES = 3
		}}
	)
	self.windowShader = love.graphics.newShader(
		"#line 1\n" .. love.filesystem.read("shaders/include/entityVertex.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/window.glsl")
	)
	self.shadowDepthShader = love.graphics.newShader("shaders/drawing/shadowDepth.glsl", {defines = {
		OMNIDIRECTIONAL = true
	}})
	self.opaqueFromDepthShader = love.graphics.newShader("shaders/drawing/opaqueFromDepth.glsl")

	self.windowMesh = util.loadObj("art/windowMesh.obj")
end

return game
