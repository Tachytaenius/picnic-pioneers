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
		position = mathsies.vec3(),
		cameraOffset = mathsies.vec3(0, 2, 1),
		orientation = mathsies.quat(),
		verticalFOV = math.rad(70),
		mesh = util.loadObj("art/mrTestFace/mesh.obj"),
		texture = love.graphics.newImage("art/mrTestFace/texture.png")
	}
	self.players[1] = player1
	table.insert(self.entities, player1)
	-- table.insert(self.entities, {
	-- 	position = mathsies.vec3(0.5, 0, 9),
	-- 	cameraOffset = mathsies.vec3(0, 1, 0.5),
	-- 	orientation = mathsies.quat.fromAxisAngle(mathsies.vec3(0, 4, 0)),
	-- 	verticalFOV = math.rad(70),
	-- 	mesh = util.loadObj("art/mrTestFace/mesh.obj"),
	-- 	texture = love.graphics.newImage("art/mrTestFace/texture.png")
	-- })

	-- Graphics init
	self.entityShader = love.graphics.newShader("shaders/drawing/entity.glsl")
end

return game
