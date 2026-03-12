local bm = require("bigmaths")
local mapm = bm.mapm
local mathsies = require("lib.mathsies")

local consts = require("consts")
local util = require("util")

local game = {}

function game:initCelestial()
	-- Basic init
	self.celestialTime = mapm.number(0) -- Will be used for celestial simulation, so it's arbitrary precision
	self:initCelestialRNG()

	self:initPointLayers() -- Mix of graphics and non-graphics

	-- Graphics init

	self.pointIndirectDrawArgsBuffer = love.graphics.newBuffer(consts.indirectDrawBufferFormat, 1, {
		shaderstorage = true,
		indirectarguments = true,
		debugname = "Point Indirect Draw Args"
	})
	self.pointDiskMesh = util.generatePointDiskMesh(consts.diskMeshVertices)
	self.pointDrawablesShader = love.graphics.newShader("shaders/drawing/pointDrawables.glsl", {defines = {INSTANCED = true}})

	local width, height = love.graphics.getDimensions()
	self.screenCanvasses.celestialOutputCanvas = love.graphics.newCanvas(width, height, {
		format = "rgba16f",
		debugname = "Celestial Output Canvas"
	})

	-- Place ship
	self.ship = {
		position = bm.vec3(0, 0, 0), -- Arbitrary precision, used to define position with enough information at each size scale
		orientation = mathsies.quat(),
		verticalFOV = math.rad(80)
	}
end

return game
