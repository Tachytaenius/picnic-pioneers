local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local settings = require("settings")
local util = require("util")
local consts = require("consts")

local game = {}

function game:getGravityWellSlowdownFactor()
	local result = self.pointLayerGravityWellSlowdownFactor
	local lastPointLayer = self.pointLayers[#self.pointLayers]
	if lastPointLayer.currentObject then
		local obj = lastPointLayer.currentObject
		local shipPosRelative = bm.vec3.toMathsiesVec3(self.ship.position - obj.position)
		if not obj.bodies then
			local dist = #shipPosRelative
			if dist > 0 then
				local mass = lastPointLayer.chunkExtraInfo[obj.chunkBufferIndex].mass[obj.pointId]
				result = result + mass * dist ^ consts.slowdownDistanceExponent
			end
		else
			for _, body in ipairs(obj.bodies) do
				local dist = mathsies.vec3.distance(shipPosRelative, body.position)
				if dist > 0 then
					result = result + body.mass * dist ^ consts.slowdownDistanceExponent
				end
			end
		end
	end
	return consts.gravitationalConstant * result
end

function game:getMaxMovementSpeed()
	local factor = self:getGravityWellSlowdownFactor()
	if factor > 0 then
		return consts.gravityMovementRate / factor ^ consts.gravityFactorExponent
	end
	return 0 -- TODO: Appropriate minimum factor (for appropriate maximum speed)
end

function game:handleShipMovement(dt)
	local controls = settings.controls

	local translation = mathsies.vec3()
	if love.keyboard.isDown(controls.moveRight) then
		translation = translation + consts.rightVector
	end
	if love.keyboard.isDown(controls.moveLeft) then
		translation = translation - consts.rightVector
	end
	if love.keyboard.isDown(controls.moveUp) then
		translation = translation + consts.upVector
	end
	if love.keyboard.isDown(controls.moveDown) then
		translation = translation - consts.upVector
	end
	if love.keyboard.isDown(controls.moveForwards) then
		translation = translation + consts.forwardVector
	end
	if love.keyboard.isDown(controls.moveBackwards) then
		translation = translation - consts.forwardVector
	end
	local maxSpeed = self:getMaxMovementSpeed()
	-- TEMP. Consider how velocity would work with this system?
	local speed = (love.keyboard.isDown("lshift") and 25 or 1) * maxSpeed
	if love.keyboard.isDown("lctrl") then
		speed = 1e27
	end
	local displacement = mathsies.vec3.rotate(util.normaliseOrZero(translation), self.ship.orientation) * speed * dt
	self.ship.position = self.ship.position + displacement

	local rotation = mathsies.vec3()
	if love.keyboard.isDown(controls.pitchDown) then
		rotation = rotation + consts.rightVector
	end
	if love.keyboard.isDown(controls.pitchUp) then
		rotation = rotation - consts.rightVector
	end
	if love.keyboard.isDown(controls.yawRight) then
		rotation = rotation + consts.upVector
	end
	if love.keyboard.isDown(controls.yawLeft) then
		rotation = rotation - consts.upVector
	end
	if love.keyboard.isDown(controls.rollAnticlockwise) then
		rotation = rotation + consts.forwardVector
	end
	if love.keyboard.isDown(controls.rollClockwise) then
		rotation = rotation - consts.forwardVector
	end
	local angularSpeed = 1 -- TODO
	local rotationQuat = mathsies.quat.fromAxisAngle(util.limitVectorLength(rotation, angularSpeed * dt))
	self.ship.orientation = mathsies.quat.normalise(self.ship.orientation * rotationQuat) -- Normalise to prevent numeric drift
end

return game
