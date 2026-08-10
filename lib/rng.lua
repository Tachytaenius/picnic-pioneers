local ffi = require("ffi")

local rng = ffi.load("lib/rng.so")
ffi.cdef([[
	uint64_t next(void);
	double nextDouble();
	void seedRNG(uint64_t seedLow, uint64_t seedHigh);

	typedef union {
		uint64_t large[2];
		uint32_t small[4];
	} seedInitialiser;
]])

-- a, b, c, and d are plain Lua numbers (i.e. doubles).
-- 4 of them treated as 32 bit uints represents 128 bits
local seedInitialiser = ffi.new("seedInitialiser")
local function seedRNGLua(a, b, c, d)
	seedInitialiser.small[0] = a
	seedInitialiser.small[1] = b
	seedInitialiser.small[2] = c
	seedInitialiser.small[3] = d
	rng.seedRNG(
		seedInitialiser.large[0],
		seedInitialiser.large[1]
	)
end

return {
	seedRNGLua = seedRNGLua,
	rng = rng
}
