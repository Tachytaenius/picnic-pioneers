local ffi = require("ffi")

-- :)
-- 100% bit-for-bit exact, which is probably what we want.
-- Maybe hex floats (%a) have some nasty surprises wrt determinism. Denormal numbers?
ffi.cdef([=[
    typedef struct {
        uint32_t lo;
        uint32_t hi;
    } intPair;
    typedef union {
        double x;
        intPair raw;
    } numConverter;
]=])
local converter = ffi.new("numConverter")
local funcs = {}
function funcs.encodeDouble(x)
    converter.x = x
    return string.format("%08x%08x", converter.raw.hi, converter.raw.lo)
end
function funcs.decodeDouble(code)
    local hiStr = string.sub(code, 1, 8)
    local loStr = string.sub(code, 9, 16)
    converter.raw.hi = tonumber(hiStr, 16)
    converter.raw.lo = tonumber(loStr, 16)
    return converter.x
end
function funcs.checkCode(code)
	if type(code) ~= "string" then
		return false
	end
	if #code ~= 16 then
		return false
	end
	if string.match(code, "[^%x]") then -- If there are any non-hexadecimal chars
		return false
	end
	return true
end

return funcs
