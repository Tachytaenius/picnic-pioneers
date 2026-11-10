struct NoiseLayer {
	int valueStart;
	ivec3 valueSize;
};

struct VolumetricSample {
	vec3 attenuation;
	vec3 emission;
};

struct ColourTransmittance {
	vec3 colour;
	vec3 transmittance;
};
