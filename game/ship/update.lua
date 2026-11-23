local mathsies = require("lib.mathsies")

local game = {}

function game:updateShip(dt)
	self:handlePlayerMovement(dt)

	self.shipTime = self.shipTime + dt

	-- for i = 2, #self.entities do
	-- 	local e = self.entities[i]
	-- 	if e.windowInfo then
	-- 		goto continue
	-- 	end
	-- 	e.orientation = mathsies.quat.normalise(e.orientation * mathsies.quat.fromAxisAngle(mathsies.vec3(0, 0.5, 0) * dt))
	--     ::continue::
	-- end
end

return game
