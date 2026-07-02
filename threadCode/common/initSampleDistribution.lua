return function(stepCount, maxThreads)
	local totalSamples = stepCount ^ 3
	local samplesPerThread = math.floor(totalSamples / maxThreads)
	local firstSample = 0
	local sampleDistribution = {
		stepCount = stepCount,
		totalSamples = totalSamples
	}
	for i = 1, maxThreads do
		local lastSample = math.max(0, math.min(totalSamples - 1, firstSample + samplesPerThread - 1))
		if i == maxThreads then
			lastSample = totalSamples - 1
		end

		sampleDistribution[i] = {
			firstSample = firstSample,
			lastSample = lastSample
		}

		if lastSample >= totalSamples - 1 then
			break
		end

		firstSample = lastSample + 1
	end
	return sampleDistribution
end
