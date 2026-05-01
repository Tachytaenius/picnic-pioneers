// Noise number has nothing to do with dimensions

const float noise1Scale = 2.0;
const float noise1GradientMagShape = 0.125;
const float noise2Scale = 5.0;
const float noise2Exponent = 4.0;
// const float noise3Scale = 10.0;
const float distExponent = 2.0;

// Couldn't be shape type parameters, simply just constants:
const float noise1DerivativeOffset = 0.01;

float sampleShapeDensity(vec3 samplePosition) {
	float len = length(samplePosition);

	vec3 noise1Gradient = (vec3( // Anisotropic!
		0.0, // snoise((samplePosition + vec3(noise1DerivativeOffset, 0.0, 0.0)) * noise1Scale),
		0.0, // snoise((samplePosition + vec3(0.0, noise1DerivativeOffset, 0.0)) * noise1Scale),
		snoise((samplePosition + vec3(0.0, 0.0, noise1DerivativeOffset)) * noise1Scale)
	) - snoise(samplePosition * noise1Scale)) / noise1DerivativeOffset;
	float noise1GradientMagnitude = length(noise1Gradient);
	float noise1Value = noise1GradientMagShape / (noise1GradientMagnitude + noise1GradientMagShape);

	// vec3 noise2SamplePos = samplePosition + noise1Gradient * 0.01;
	vec3 noise2SamplePos = samplePosition;
	float noise2Value = pow(max(0.0, 1.0 - abs(snoise(noise2SamplePos * noise2Scale))), noise2Exponent);

	// float noise3Value = 1.0 - abs(snoise(samplePosition * noise3Scale));

	float densityMultiplier = pow(max(0.0, 1.0 - len), distExponent);
	// return densityMultiplier * noise1Value * noise2Value * noise3Value;
	return densityMultiplier * noise1Value * noise2Value;
	// return densityMultiplier *
	// 	(1.0 - abs(noise1Gradient.x)) *
	// 	(1.0 - abs(noise1Gradient.y)) *
	// 	(1.0 - abs(noise1Gradient.z));
}
