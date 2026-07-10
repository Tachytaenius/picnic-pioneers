local info = {}

function info.getDensity(x, y, z)
	local len = math.sqrt(x^2+y^2+z^2)

	return len > 1 and 0 or 1
end

return info
