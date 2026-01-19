return function(t)
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = v
	end
	for k, v in pairs(t) do
		assert(not copy[v], "Can't make table bidirectional, duplicate values")
		copy[v] = k
	end
	return copy
end
