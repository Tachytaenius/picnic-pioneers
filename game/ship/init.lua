local game = {}

function game:initShip()
	self.screenWidth, self.screenHeight = love.graphics.getDimensions()
	self.screenCanvasses.shipOutputCanvas = love.graphics.newCanvas(self.screenWidth, self.screenHeight)

	self.shipTime = 0
end

return game
