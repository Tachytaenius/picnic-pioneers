-- mapm = require("lib.mapm") -- ./lib/mapm.so: undefined symbol: luaopen_lib_mapm
-- But this works:
local requirePath = love.filesystem.getCRequirePath()
local newPath = "lib/??"
love.filesystem.setCRequirePath(requirePath .. ";" .. newPath)
local mapm = require("mapm")
love.filesystem.setCRequirePath(requirePath)

mapm.digits(32)

-- Some of the code below is based on my Mathsies library

local vec3, shaders

local function isNumber(x)
	return type(x) == "number" or type(x) == "userdata" -- Make assumption that userdata is mapm bignumber, not sure how else to do it
end

do -- vec3
	local vec3Metatable

	local number, sqrt, sin, cos, mapmTostring = mapm.number, mapm.sqrt, mapm.sin, mapm.cos, mapm.tostring

	local function new(x, y, z)
		x = x and number(x) or number(0)
		y = y and number(y) or x
		z = z and number(z) or y
		return setmetatable({type = "vec3", x = x, y = y, z = z}, vec3Metatable)
	end

	local function length(v)
		local x, y, z = v.x, v.y, v.z
		return sqrt(x * x + y * y + z * z)
	end

	local function length2(v)
		local x, y, z = v.x, v.y, v.z
		return x * x + y * y + z * z
	end

	local function distance(a, b)
		local x, y, z = b.x - a.x, b.y - a.y, b.z - a.z
		return sqrt(x * x + y * y + z * z)
	end

	local function distance2(a, b)
		local x, y, z = b.x - a.x, b.y - a.y, b.z - a.z
		return x * x + y * y + z * z
	end

	local function dot(a, b)
		return a.x * b.x + a.y * b.y + a.z * b.z
	end

	local function cross(a, b)
		return new(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
	end

	local function normalise(v)
		return v / length(v)
	end

	local function reflect(incident, normal)
		return incident - 2 * dot(normal, incident) * normal
	end

	local function refract(incident, normal, eta)
		local ndi = dot(normal, incident)
		local k = 1 - eta * eta * (1 - ndi * ndi)
		if k < 0 then
			return new(0)
		else
			return eta * incident - (eta * ndi + sqrt(k)) * normal
		end
	end

	local function rotate(v, q)
		local qxyz = new(q.x, q.y, q.z)
		local uv = cross(qxyz, v)
		local uuv = cross(qxyz, uv)
		return v + ((uv * q.w) + uuv) * 2
	end

	local function fromAngles(theta, phi)
		local st, sp, ct, cp = sin(theta), sin(phi), cos(theta), cos(phi)
		return new(st * sp, ct, st * cp)
	end

	local function components(v)
		return v.x, v.y, v.z
	end

	local function clone(v)
		return new(v.x, v.y, v.z)
	end

	vec3Metatable = {
		__add = function(a, b)
			if isNumber(a) then
				return new(a + b.x, a + b.y, a + b.z)
			elseif isNumber(b) then
				return new(a.x + b, a.y + b, a.z + b)
			else
				return new(a.x + b.x, a.y + b.y, a.z + b.z)
			end
		end,
		__sub = function(a, b)
			if isNumber(a) then
				return new(a - b.x, a - b.y, a - b.z)
			elseif isNumber(b) then
				return new(a.x - b, a.y - b, a.z - b)
			else
				return new(a.x - b.x, a.y - b.y, a.z - b.z)
			end
		end,
		__unm = function(v)
			return new(-v.x, -v.y, -v.z)
		end,
		__mul = function(a, b)
			if isNumber(a) then
				return new(a * b.x, a * b.y, a * b.z)
			elseif isNumber(b) then
				return new(a.x * b, a.y * b, a.z * b)
			else
				return new(a.x * b.x, a.y * b.y, a.z * b.z)
			end
		end,
		__div = function(a, b)
			if isNumber(a) then
				return new(a / b.x, a / b.y, a / b.z)
			elseif isNumber(b) then
				return new(a.x / b, a.y / b, a.z / b)
			else
				return new(a.x / b.x, a.y / b.y, a.z / b.z)
			end
		end,
		__mod = function(a, b)
			if isNumber(a) then
				return new(a % b.x, a % b.y, a % b.z)
			elseif isNumber(b) then
				return new(a.x % b, a.y % b, a.z % b)
			else
				return new(a.x % b.x, a.y % b.y, a.z % b.z)
			end
		end,
		__eq = function(a, b)
			local isVec3 = b.type == "vec3"
			return isVec3 and a.x == b.x and a.y == b.y and a.z == b.z
		end,
		__len = length,
		__tostring = function(v)
			return string.format("vec3(%s, %s, %s)", mapmTostring(v.x), mapmTostring(v.y), mapmTostring(v.z))
		end
	}

	vec3 = setmetatable({
		new = new,
		length = length,
		length2 = length2,
		distance = distance,
		distance2 = distance2,
		dot = dot,
		cross = cross,
		normalise = normalise,
		normalize = normalise,
		reflect = reflect,
		refract = refract,
		rotate = rotate,
		fromAngles = fromAngles,
		components = components,
		clone = clone
	}, {
		__call = function(_, x, y, z)
			return new(x, y, z)
		end
	})
end

do -- shaders
	shaders = {}

	-- Will lose a lot of precision, still useful when small

	function shaders.sendNum(shader, name, x)
		shader:send(name, mapm.tonumber(x))
	end

	local vec3Send = {}
	function shaders.sendVec3(shader, name, v)
		vec3Send[1] = mapm.tonumber(v.x)
		vec3Send[2] = mapm.tonumber(v.y)
		vec3Send[3] = mapm.tonumber(v.z)
		shader:send(name, vec3Send)
	end
end

return {
	mapm = mapm,
	vec3 = vec3,
	shaders = shaders
}
