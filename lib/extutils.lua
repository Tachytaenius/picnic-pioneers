local ffi = require("ffi")

local extutils = ffi.load("lib/extutils.so")

ffi.cdef([[
	int ensureRoundingMode(void);
]])

return extutils
