local game = {}

local function recurse(path)
	for _, itemName in ipairs(love.filesystem.getDirectoryItems(path)) do
		local itemPath = path .. itemName
		if itemPath ~= "game/init.lua" then
			if love.filesystem.getInfo(itemPath, "directory") then
				recurse(itemPath .. "/")
			elseif love.filesystem.getInfo(itemPath, "file") then
				if itemName:match("%.lua$") then
					local modulePath = itemPath:gsub("%.lua", ""):gsub("/", ".")
					local module = require(modulePath)
					assert(type(module) == "table", "Module at " .. modulePath .. " did not return a table")
					for k, v in pairs(module) do
						assert(not game[k], "Duplicate field in game module \"" .. k .. "\"")
						game[k] = v
					end
				end
			end
		end
	end
end

recurse("game/")

return game
