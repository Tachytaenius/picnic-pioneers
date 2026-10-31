float SHAPE_DENSITY_SAMPLE_TYPE(vec3 samplePosition, vec3 samplePositionTrueRatio) {
	return
		(PARAM(noiseFlatness) + (1.0 - PARAM(noiseFlatness)) * VALUE_NOISE(1, samplePositionTrueRatio)) *
		pow(max(0.0, 1.0 - length(samplePosition)), PARAM(densityExponent));
}
