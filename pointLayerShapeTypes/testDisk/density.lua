return function(x, y, z)
	return math.sqrt(x^2+y^2+z^2) < 1 and math.abs(z) < 0.05 and 1 or 0
end
