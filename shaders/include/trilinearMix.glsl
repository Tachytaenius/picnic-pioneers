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
