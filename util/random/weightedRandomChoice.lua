return function(choices, rng)
	local random = rng and rng:random() or love.math.random()
	local weightSum = 0
	for _, choice in ipairs(choices) do
		weightSum = weightSum + choice.weight
	end
	local x = random * weightSum
	for _, choice in ipairs(choices) do
		if x < choice.weight then
			-- return choice.value
			return choice
		end
		x = x - choice.weight
	end
	return nil
end
