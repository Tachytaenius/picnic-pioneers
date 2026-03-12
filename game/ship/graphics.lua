local game = {}

function game:drawShip()
	local outputCanvas = self.screenCanvasses.shipOutputCanvas
	love.graphics.setCanvas(outputCanvas)
	love.graphics.clear(0, 0, 0, 1)

	love.graphics.setCanvas()
end

return game
