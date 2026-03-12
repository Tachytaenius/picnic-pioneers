local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local util = require("util")
local consts = require("consts")

local game = {}

function game:handleShipMovement(dt)
	local translation = mathsies.vec3()
	if love.keyboard.isDown(consts.controls.moveRight) then
		translation = translation + consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.moveLeft) then
		translation = translation - consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.moveUp) then
		translation = translation + consts.upVector
	end
	if love.keyboard.isDown(consts.controls.moveDown) then
		translation = translation - consts.upVector
	end
	if love.keyboard.isDown(consts.controls.moveForwards) then
		translation = translation + consts.forwardVector
	end
	if love.keyboard.isDown(consts.controls.moveBackwards) then
		translation = translation - consts.forwardVector
	end
	local speed = (love.keyboard.isDown("lshift") and consts.starLayerChunkSize or consts.galaxyLayerChunkSize) * 2 * (love.keyboard.isDown("lctrl") and 0.1 or 1) -- TODO
	local displacement = mathsies.vec3.rotate(util.normaliseOrZero(translation), self.ship.orientation) * speed * dt
	self.ship.position = self.ship.position + displacement

	local rotation = mathsies.vec3()
	if love.keyboard.isDown(consts.controls.pitchDown) then
		rotation = rotation + consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.pitchUp) then
		rotation = rotation - consts.rightVector
	end
	if love.keyboard.isDown(consts.controls.yawRight) then
		rotation = rotation + consts.upVector
	end
	if love.keyboard.isDown(consts.controls.yawLeft) then
		rotation = rotation - consts.upVector
	end
	if love.keyboard.isDown(consts.controls.rollAnticlockwise) then
		rotation = rotation + consts.forwardVector
	end
	if love.keyboard.isDown(consts.controls.rollClockwise) then
		rotation = rotation - consts.forwardVector
	end
	local angularSpeed = 2 -- TODO
	local rotationQuat = mathsies.quat.fromAxisAngle(util.limitVectorLength(rotation, angularSpeed * dt))
	self.ship.orientation = mathsies.quat.normalise(self.ship.orientation * rotationQuat) -- Normalise to prevent numeric drift
end

return game
