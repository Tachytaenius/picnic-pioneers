local info = {}

info.shaderIncludes = {
	"lib/simplex3d"
}

function info.getDensity(x, y, z)
	-- TODO: Match shader code
	return math.sqrt(x^2+y^2+z^2) <= 1 and 0.2 or 0
end

return info
