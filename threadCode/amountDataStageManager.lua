local detail, maxThreads = ...

local extutils = require("lib.extutils")
extutils.ensureRoundingMode()

local initSampleDistribution = require("threadCode.common.initSampleDistribution")

local distributions = {} -- 0-indexed
for i = 0, detail do
	distributions[i] = initSampleDistribution(2 ^ i, maxThreads)
end

while true do
	local info = love.thread.getChannel("shapeAmountDataStageManagerInfo"):demand() -- This is also passable to the shape amounts threads as a base setup (once filled in)

	local cancelled = false
	for lod = detail, 0, -1 do
		local sampleDistribution = distributions[lod]

		for i = 1, #sampleDistribution do
			info.lodToWriteTo = lod
			info.firstSample = sampleDistribution[i].firstSample
			info.lastSample = sampleDistribution[i].lastSample
			info.stepCount = sampleDistribution.stepCount
			love.thread.getChannel("shapeAmountsInfo"):push(info)
		end

		for _=1, #sampleDistribution do
			love.thread.getChannel("shapeAmountsResult" .. info.resultChannelSuffix):demand()
		end

		if love.thread.getChannel("shapeAmountDataStageManagerCancel" .. info.resultChannelSuffix):pop() then
			cancelled = true
			break
		end
	end

	if not cancelled then
		love.thread.getChannel("shapeAmountDataStageManagerResult" .. info.resultChannelSuffix):push("finished")
	end
end
