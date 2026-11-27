local mathsies = require("lib.mathsies")

local game = {}

function game:updateShip(dt)
	self:handlePlayerMovement(dt)

	for i = 1, #self.entities do
		local e = self.entities[i]
		if e.windowInfo then
			goto continue
		end
		if e.pointLightInfo then
			local t = self.shipTime * i / 8
			e.position.x = math.cos(t * 1) * i / 2 + i * 0.9
			e.position.y = math.sin(t * 4) * i / 2 * 0.05 + 3
			e.position.z = math.sin(t * 1) * i / 2 + i * 0.2
		end
		-- e.orientation = mathsies.quat.normalise(e.orientation * mathsies.quat.fromAxisAngle(mathsies.vec3(0, 0.5, 0) * dt))
	    ::continue::
	end

	self.shipTime = self.shipTime + dt
end

return game
