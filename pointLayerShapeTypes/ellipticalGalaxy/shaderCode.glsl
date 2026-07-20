float SHAPE_DENSITY_SAMPLE_TYPE(vec3 samplePosition, vec3 samplePositionTrueRatio) {
	return pow(VALUE_NOISE(1, samplePositionTrueRatio) * max(0.0, 1.0 - length(samplePosition)), PARAM(densityExponent));
}
