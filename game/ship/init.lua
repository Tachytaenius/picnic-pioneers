local game = {}

function game:initShip()
	self.screenCanvasses.shipOutputCanvas = love.graphics.newCanvas(self.screenWidth, self.screenHeight)

	self.shipTime = 0
end

return game
