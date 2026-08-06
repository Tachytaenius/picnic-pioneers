-- Thanks Jasper :3

table.clear = require("table.clear")

local mixed = {}
local function mixN(i, ...)
	local currentI = table.remove(i)
	if not currentI then
		return mixed[1]
	end
	table.clear(mixed)

	for idx = 1, select("#", ...), 2 do
		local a = select(idx, ...)
		local b = select(idx + 1, ...)
		local c = a + currentI * (b - a)

		table.insert(mixed, c)
	end

	return mixN(i, unpack(mixed))
end

return mixN
