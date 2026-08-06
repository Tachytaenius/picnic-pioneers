local json = require("lib.json")

return function(str)
	local success, result = pcall(json.decode, str)
	if success then
		return result
	end
	return nil
end
