local game = {}

function game:initShip()
	local width, height = love.graphics.getDimensions()
	self.screenCanvasses.shipOutputCanvas = love.graphics.newCanvas(width, height)
end

return game
