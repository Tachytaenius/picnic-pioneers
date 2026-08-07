return function(path, scale)
	local original = love.image.newImageData(path)
	local scaled = love.image.newImageData(
		original:getWidth() * scale,
		original:getHeight() * scale
	)
	scaled:mapPixel(function(x, y)
		local sourceX = math.floor(x / scale)
		local sourceY = math.floor(y / scale)
		return original:getPixel(sourceX, sourceY)
	end)
	return scaled
end
