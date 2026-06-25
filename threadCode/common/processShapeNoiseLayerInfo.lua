return function(shapeType, loadedInfo)
	if not loadedInfo.valueNoiseInfo then
		return 0
	end

	local currentStart = 0
	shapeType.noiseInfo = {}
	local layers = {}
	shapeType.noiseInfo.layers = layers
	for i, layerInfo in ipairs(loadedInfo.valueNoiseInfo) do
		local count = layerInfo.countX * layerInfo.countY * layerInfo.countZ
		layers[i] = {
			start = currentStart,
			count = count,
			countX = layerInfo.countX,
			countY = layerInfo.countY,
			countZ = layerInfo.countZ
		}
		currentStart = currentStart + count
	end
	shapeType.noiseInfo.requiredValueCount = currentStart -- Sum of all layers' counts
	return currentStart
end
