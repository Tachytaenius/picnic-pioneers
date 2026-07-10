float sampleShapeDensity(vec3 samplePosition) {
	float len = length(samplePosition);
	return len > 1.0 ? 0.0 : 1.0;
}
