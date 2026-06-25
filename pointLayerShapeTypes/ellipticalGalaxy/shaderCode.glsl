uniform float shape_densityExponent;

float sampleShapeDensity(vec3 samplePosition) {
	return pow(valueNoise(1, samplePosition) * max(0.0, 1.0 - length(samplePosition)), shape_densityExponent);
}
