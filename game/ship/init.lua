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
		-- albedo = self:newSpectralImageFromRGB("art/mrTestFace/texture.png")
	}
	self.players[1] = player1
	table.insert(self.entities, player1)

	table.insert(self.entities, {
		position = mathsies.vec3(0, -1, 0),
		orientation = mathsies.quat(),
		scale = 12,
		mesh = util.loadObj("art/shipTest/mesh.obj"),
		albedo = self:newSpectralImageFromRGB("art/shipTest/texture.png")
	})

	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(2, 0, 3),
	-- 	orientation = mathsies.quat(),
	-- 	mesh = util.loadObj("art/mrTestFace/mesh.obj"),
	-- 	albedo = self:newSpectralImageFromRGB("art/mrTestFace/texture.png")
	-- })
	table.insert(self.entities, {
		position = mathsies.vec3(-2.5, 3, -1),
		orientation = mathsies.quat(),
		mesh = util.loadObj("art/the2/mesh.obj"),
		albedo = self:newSpectralImageFromRGB("art/the2/texture.png")
	})

	table.insert(self.entities, {
		position = mathsies.vec3(3, 2.5, -3),
		orientation = mathsies.quat(),
		mesh = util.loadObj("art/the2/mesh.obj"),
		albedo = self:newSpectralImageFromRGB("art/the2/texture.png")
	})

	table.insert(self.entities, {
		position = mathsies.vec3(0, 15, 12.2),
		orientation = mathsies.quat(),
		windowInfo = {
			-- width = 24,
			width = 10,
			height = 18,
			transmittanceTexture = self:newSpectralImageFromRGB("art/windowTransmittance.png")
		},
		albedo = self:newSpectralImageFromRGB("art/windowAlbedo.png")
	})
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(1.5, -1, 9),
	-- 	orientation = mathsies.quat(),
	-- 	windowInfo = {
	-- 		width = 6,
	-- 		height = 5,
	-- 		transmittanceTexture = self:newSpectralImageFromRGB("art/windowTransmittance.png")
	-- 	}
	-- })
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(-4, 0, 9),
	-- 	orientation = mathsies.quat.fromAxisAngle(mathsies.vec3(0.0, 0.0, -consts.tau / 4)),
	-- 	windowInfo = {
	-- 		width = 9,
	-- 		height = 4,
	-- 		transmittanceTexture = self:newSpectralImageFromRGB("art/windowTransmittance.png")
	-- 	}
	-- })
	table.insert(self.entities, {
		position = mathsies.vec3(2, 1.5, 0),
		pointLightInfo = {
			radiantIntensity = self:lightIntensityFromRGBAtDist(mathsies.vec3(1, 1, 1), 10)
		}
	})
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(),
	-- 	pointLightInfo = {
	-- 		radiantIntensity = mathsies.vec3(3e9, 0, 0)
	-- 	}
	-- })
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(),
	-- 	pointLightInfo = {
	-- 		radiantIntensity = mathsies.vec3(0, 1e8, 0)
	-- 	}
	-- })
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(),
	-- 	pointLightInfo = {
	-- 		radiantIntensity = mathsies.vec3(0, 0, 1e8)
	-- 	}
	-- })

	table.insert(self.entities, {
		position = mathsies.vec3(-2, 3, 3),
		orientation = mathsies.quat.fromAxisAngle(mathsies.vec3(0, 1.5, 0)),
		windowInfo = {
			width = 5,
			height = 5,
			transmittanceTexture = self:newSpectralImageFromRGB("art/windowTransmittance.png")
		},
		albedo = self:newSpectralImageFromRGB("art/windowAlbedo.png")
	})

	-- Graphics init

	local sideLength = consts.shadowCubemapSideLength
	self.shadowCubemap = love.graphics.newCanvas(sideLength, sideLength, {
		type = "cube",
		format = "depth32f",
		readable = true,
		debugname = "Shadow Cubemap"
	})
	self.shadowColourCubemaps = {}
	for i = 1, consts.maxPointLights do
		self.shadowColourCubemaps[i] = love.graphics.newCanvas(sideLength, sideLength, {
			type = "cube",
			format = consts.shadowColourCubemapFormat,
			computewrite = true,
			debugname = "Shadow Colour Cubemap " .. i
		})
	end

	local defines = {
		MAX_POINT_LIGHTS = consts.maxPointLights,
		QUANTISE_LIGHTING = false,
		PCF_SAMPLES = 3,
		PCF_OFFSET = 0.05,
		BIAS_MIN = 0.001,
		BIAS_MAX = 0.01,
		JITTER_SIZE = 1
	}
	self.entityShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/random.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/texelSpaceQuantisation.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/entityVertex.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/entityFragment.glsl"),
		{defines = defines}
	)
	defines.TRANSLUCENT = true
	defines.DOUBLE_SIDED_NORMAL = true
	self.windowShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/random.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/texelSpaceQuantisation.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/entityVertex.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/include/entityFragment.glsl"),
		{defines = defines}
	)
	self.shadowDepthShader = love.graphics.newShader(
		"#pragma language glsl4\n" ..
		"#line 1\n" .. love.filesystem.read("shaders/include/lib/random.glsl") ..
		"#line 1\n" .. love.filesystem.read("shaders/drawing/shadowDepth.glsl"),
		{defines = {
			OMNIDIRECTIONAL = true
		}
	})
	self.opaqueFromDepthShader = love.graphics.newShader("shaders/drawing/opaqueFromDepth.glsl")

	self.shadowDepthToColourShader = love.graphics.newShader("shaders/drawing/shadowDepthToColour.glsl") -- Should also add code for omnidirectional

	self.windowMesh = util.loadObj("art/windowMesh.obj")
end

return game
