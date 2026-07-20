float SHAPE_DENSITY_SAMPLE_TYPE(vec3 samplePosition, vec3 samplePositionTrueRatio) {
	float len = length(samplePosition);
	float noise1Value = pow(max(0.0, 1.0 - abs(VALUE_NOISE(1, samplePosition) * 2.0 - 1.0)), PARAM(noise1Exponent));
	float noise2Value = pow(max(0.0, 1.0 - abs(VALUE_NOISE(2, samplePosition) * 2.0 - 1.0)), PARAM(noise2Exponent));
	float densityMultiplier = pow(max(0.0, 1.0 - len), PARAM(distExponent));
	return densityMultiplier * noise1Value * noise2Value;
}
