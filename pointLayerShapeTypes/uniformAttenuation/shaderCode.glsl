vec3 SHAPE_DENSITY_SAMPLE_TYPE(vec3 samplePosition, vec3 samplePositionTrueRatio) {
	float len = length(samplePosition);
	return vec3(len > 1.0 ? 0.0 : 1.0);
}
