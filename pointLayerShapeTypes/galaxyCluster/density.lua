return function(x, y, z)
	-- TODO
	-- if math.sqrt(x^2+y^2+z^2) > 1 then
	-- 	return 0
	-- end
	-- return 1
	return math.max(0, 1 - math.sqrt(x^2+y^2+z^2))
end
