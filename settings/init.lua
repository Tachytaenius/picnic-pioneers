local love = require("love")
local json = require("lib.json")

--- Controls is a map of in-game actions to single characters that represent a keyboard key pressed.
---@class Controls
---@field moveRight string
---@field moveLeft string
---@field moveUp string
---@field moveDown string
---@field moveForwards string
---@field moveBackwards string
---@field pitchDown string
---@field pitchUp string
---@field yawRight string
---@field yawLeft string
---@field rollAnticlockwise string
---@field rollClockwise string

---@class Settings
---@field load fun(self: Settings)
---@field save fun(self: Settings)
---@field string fun(self: Settings): string
---@field controls Controls
local settings = {}

---@type Settings
local defaultConfig = {
    controls = {
        moveRight = "d",
		moveLeft = "a",
		moveUp = "e",
		moveDown = "q",
		moveForwards = "w",
		moveBackwards = "s",
		pitchDown = "k",
		pitchUp = "i",
		yawRight = "l",
		yawLeft = "j",
		rollAnticlockwise = "u",
		rollClockwise = "o"
    },
    load = settings.load,
    save = settings.save,
    string = settings.string,
}

---applyDefaultConfig sets every required field missing from config to its corresponding value in defaultConfig, returning the result.
---@param config Settings
local function applyDefaultConfig(config)
    for k, v in pairs(defaultConfig) do
        if k == "load" or k == "save" then
            goto continue
        end

        if not config[k] then
            config[k] = v
        end

        ::continue::
    end

    for k, v in pairs(defaultConfig.controls) do
        if not config.controls[k] then
            config.controls[k] = v
        end
    end
end

--- load reads settings from config.json and adds it to the table.
function settings:load()
    local contents, err = love.filesystem.read("config.json")
    if not contents then
        print("error loading config: "..err)
        applyDefaultConfig(self)
        return
    end

    local ok, settingsTable = pcall(json.decode, contents)
    if not ok then
        print("error loading config: "..settingsTable)
        applyDefaultConfig(self)
        return
    end

    for k, v in pairs(settingsTable) do
        self[k] = v
    end

    applyDefaultConfig(self)
end

--- @return string value the JSON representation of settings.
function settings:string()
	local load, save, string = self.load, self.save, self.string

	--- very silly way to prevent json.encode from complaining about functions on settings
	self.load, self.save, self.string = nil, nil, nil
	local str = json.encode(settings)
	self.load, self.save, self.string = load, save, string

	return str
end

--- save writes settings in the table back to config.json.
function settings:save()
    local settingsJSON = self:string()
    love.filesystem.write("config.json", settingsJSON)
end

return settings
