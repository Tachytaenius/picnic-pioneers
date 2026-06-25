readonly buffer NoiseValues {
	float noiseValues[];
};

float trilinearMix(
	// n is negative, p is positive
	float nnn, float nnp, float npn, float npp,
	float pnn, float pnp, float ppn, float ppp,
	vec3 mixFactor
) {
	return mix( // z mix
		mix( // y mix for -z
			mix( // x mix for -y -z
				nnn,
				pnn,
				mixFactor.x
			),
			mix( // x mix for +y -z
				npn,
				ppn,
				mixFactor.x
			),
			mixFactor.y
		),
		mix( // y mix for +z
			mix( // x mix for -y +z
				nnp,
				pnp,
				mixFactor.x
			),
			mix( // x mix for +y +z
				npp,
				ppp,
				mixFactor.x
			),
			mixFactor.y
		),
		mixFactor.z
	);
}

float getValue(int start, ivec3 size, ivec3 pos) {
	int index = start + pos.x + pos.y * size.x + pos.z * size.x * size.y;
	return noiseValues[index];
}

float valueNoise(int layerIndex, vec3 pos) {
	// Must give an average value of 0.5 (TODO: check!)
	// TODO: since noise (by itself before any further processing) is considered to have a consistent average value of 0.5, allow making the noise be isotropic in scale even if the object is squished

	pos = pos * 0.5 + 0.5; // Input pos axes range from -1 to 1 as they are generally intended to cover the entire shape type.

	NoiseLayer layer = noiseLayers[layerIndex - 1]; // Subtract one to match Lua-side code
	int start = layer.valueStart;
	ivec3 size = layer.valueSize;

	vec3 cellSize = 1.0 / vec3(size - 1);
	vec3 mixFactor = mod(pos, cellSize) / cellSize;
	ivec3 cell = ivec3(pos / cellSize);
	cell = clamp(cell, ivec3(0), size - 2);
	return trilinearMix(
		getValue(start, size, cell + ivec3(0, 0, 0)),
		getValue(start, size, cell + ivec3(0, 0, 1)),
		getValue(start, size, cell + ivec3(0, 1, 0)),
		getValue(start, size, cell + ivec3(0, 1, 1)),
		getValue(start, size, cell + ivec3(1, 0, 0)),
		getValue(start, size, cell + ivec3(1, 0, 1)),
		getValue(start, size, cell + ivec3(1, 1, 0)),
		getValue(start, size, cell + ivec3(1, 1, 1)),
		mixFactor
	);
}
