const float noise1Exponent = 10.0;
const float noise2Exponent = 10.0;
const float distExponent = 2.0;

float sampleShapeDensity(vec3 samplePosition) {
	float len = length(samplePosition);
	float noise1Value = pow(max(0.0, 1.0 - abs(valueNoise(1, samplePosition) * 2.0 - 1.0)), noise1Exponent);
	float noise2Value = pow(max(0.0, 1.0 - abs(valueNoise(2, samplePosition) * 2.0 - 1.0)), noise2Exponent);
	float densityMultiplier = pow(max(0.0, 1.0 - len), distExponent);
	return densityMultiplier * noise1Value * noise2Value;
}
