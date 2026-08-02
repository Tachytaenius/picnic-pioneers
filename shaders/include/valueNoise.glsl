readonly buffer BUFFER_NAME {
	float ARRAY_NAME[];
};

float GET_FUNCTION_NAME(int start, ivec3 size, ivec3 pos) {
	int index = start + pos.x + pos.y * size.x + pos.z * size.x * size.y;
	return ARRAY_NAME[index];
}

float NOISE_FUNCTION_NAME(int layerIndex, vec3 pos) {
	// TODO: since noise (by itself before any further processing) is considered to have a consistent average value of 0.5, allow making the noise be isotropic in scale even if the object is squished

	pos = pos * 0.5 + 0.5; // Input pos axes range from -1 to 1 as they are generally intended to cover the entire shape type.

	NoiseLayer layer = NOISE_LAYERS_NAME[layerIndex - 1]; // Subtract one to match Lua-side code
	int start = layer.valueStart;
	ivec3 size = layer.valueSize;

	vec3 cellSize = 1.0 / vec3(size - 1);
	vec3 cellFloat = floor(pos / cellSize);
	vec3 mixFactor = pos / cellSize - cellFloat;
	// Previous code would get mixFactor as mod(pos, cellSize) / cellSize,
	// but doing it this way avoids a (usually) extremely rare float imprecision bug
	// where the modulo result is near 1 but the cell position doesn't match,
	// causing sampling from a whole cell away.
	// Though rare, the bug manifested all the way across the middle of the screen in certain circumstances, leading to the fix.
	ivec3 cell = ivec3(cellFloat);
	cell = clamp(cell, ivec3(0), size - 2);
	return trilinearMix(
		GET_FUNCTION_NAME(start, size, cell + ivec3(0, 0, 0)),
		GET_FUNCTION_NAME(start, size, cell + ivec3(0, 0, 1)),
		GET_FUNCTION_NAME(start, size, cell + ivec3(0, 1, 0)),
		GET_FUNCTION_NAME(start, size, cell + ivec3(0, 1, 1)),
		GET_FUNCTION_NAME(start, size, cell + ivec3(1, 0, 0)),
		GET_FUNCTION_NAME(start, size, cell + ivec3(1, 0, 1)),
		GET_FUNCTION_NAME(start, size, cell + ivec3(1, 1, 0)),
		GET_FUNCTION_NAME(start, size, cell + ivec3(1, 1, 1)),
		mixFactor
	);
}
