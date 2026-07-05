local game = {}

function game:initShip()
	local width, height = self.screenWidth, self.screenHeight
	self.screenCanvasses.shipOutputCanvas = love.graphics.newCanvas(width, height)

	self.shipTime = 0
end

return game
