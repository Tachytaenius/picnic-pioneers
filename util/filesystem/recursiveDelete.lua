local function remove(item)
	assert(love.filesystem.remove(item), "Failed to delete \"" .. item .. "\"")
end

local function recursiveDelete(item)
	if love.filesystem.getInfo(item, "directory") then
		for _, child in ipairs(love.filesystem.getDirectoryItems(item)) do
			recursiveDelete(item .. "/" .. child)
		end
	else
		remove(item)
	end
end

return recursiveDelete
