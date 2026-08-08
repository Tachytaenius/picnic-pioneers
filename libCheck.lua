local prefix = "lib/"
local suffix = ".so"
local names = {
	"mapm",
	"rng"
}
for _, name in ipairs(names) do
	if not love.filesystem.getInfo(prefix .. name .. suffix) then
		error(
			"\n\nMissing library \"" .. name .. "\"!\n" ..
			"Did you run make?\n" ..
			"If it fails on the sources...\n" ..
			"Did you initialise submodules?\n" ..
			"Do you need a dependency?",
			0
		)
	end
end
