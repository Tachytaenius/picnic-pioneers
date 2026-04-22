local bm = require("bigmaths")
local mathsies = require("lib.mathsies")

local util = require("util")
local consts = require("consts")

local game = {}

function game:getGravityWellSlowdownFactor()
	local result = self.pointLayerGravityWellSlowdownFactor
	-- TEMP: Individual bodies (stars, planets, etc) should be defined elsewhere
	local lastPointLayer = self.pointLayers[#self.pointLayers]
	if lastPointLayer.currentObject then
		local obj = lastPointLayer.currentObject
		local dist = #bm.vec3.toMathsiesVec3(
			self.ship.position - obj.position
		)
		if dist > 0 then
			print(dist)
			local mass = lastPointLayer.chunkExtraInfo[obj.chunkBufferIndex].mass[obj.pointId]
			result = result + mass * dist ^ consts.slowdownDistanceExponent
			-- print(mass, dist, mass * dist ^ consts.slowdownDistanceExponent)
		end
	end
	return result -- TODO: Planets etc
end

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
	local rate = self.ship.gravityMovementRate
	local factor = self:getGravityWellSlowdownFactor()
	if factor > 0 then
		-- loads of TEMP crap :D
		-- local speed = rate / (factor / consts.gravitySlowdownResultDivisor) ^ consts.gravitySlowdownResultExponent
		-- local speed = 1.86046e17*factor^-0.89566
		-- local speed = 1e16 / factor^0.75
		local speed = 1e11 / factor ^ (1/3)
		-- local speed = 1e16 / factor ^ 0.5
		-- print(speed / 1e22, speed / 1e17)
		local speed = (love.keyboard.isDown("lshift") and 0.025 or 1) * speed
		if love.keyboard.isDown("lctrl") then speed = 1.497e11 / dt end

		local displacement = mathsies.vec3.rotate(util.normaliseOrZero(translation), self.ship.orientation) * speed * dt
		self.ship.position = self.ship.position + displacement
		print("this (" .. self:getGravityWellSlowdownFactor() ..")", speed)
		print()
	end

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
	local angularSpeed = 1 -- TODO
	local rotationQuat = mathsies.quat.fromAxisAngle(util.limitVectorLength(rotation, angularSpeed * dt))
	self.ship.orientation = mathsies.quat.normalise(self.ship.orientation * rotationQuat) -- Normalise to prevent numeric drift
end

return game
