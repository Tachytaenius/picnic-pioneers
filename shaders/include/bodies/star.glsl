uniform vec3 surfaceRadiance;

// From Allen's Astrophysical Quantities
struct LimbSample { // For a particular wavelength
	float A, B, C;
	vec3 weights; // How much to contribute to each spectral bin, since the data isn't perfectly aligned
};
const LimbSample limbSamples[] = LimbSample[] (
	LimbSample (0.42, 0.68, -0.40, vec3(0.0, 0.0, 1.0)), // 370
	LimbSample (0.26, 0.78, -0.20, vec3(0.0, 0.0, 1.0)), // 380
	LimbSample (0.20, 0.81, -0.10, vec3(0.0, 0.0, 1.0)), // 400
	LimbSample (0.54, 0.60, -0.44, vec3(0.0, 0.5, 0.5)), // 450
	LimbSample (0.68, 0.49, -0.56, vec3(0.0, 1.0, 0.0)), // 500
	LimbSample (0.74, 0.43, -0.56, vec3(0.0, 1.0, 0.0)), // 550
	LimbSample (0.78, 0.39, -0.57, vec3(0.5, 0.5, 0.0)), // 600
	LimbSample (0.92, 0.25, -0.56, vec3(1.0, 0.0, 0.0))  // 800
);

ColourTransmittance sampleBody(vec3 cameraPosition, vec3 direction, vec3 surfaceNormal, vec3 surfaceEnterPos, vec3 surfaceExitPos) { // Positions are relative to body centre
	float cosAngle = dot(normalize(cameraPosition - surfaceEnterPos), surfaceNormal);
	float secAngle = 1.0 / cosAngle;

	vec3 edgeLimbFactor = vec3(0.0);
	vec3 averageLimbFactor = vec3(0.0);
	vec3 limbFactor = vec3(0.0);
	vec3 weightTotal = vec3(0.0);
	for (int i = 0; i < limbSamples.length(); i++) {
		LimbSample limbSample = limbSamples[i];
		float A = limbSample.A;
		float B = limbSample.B;
		float C = limbSample.C;
		vec3 weights = limbSample.weights;
		edgeLimbFactor += weights * (A + C);
		averageLimbFactor += weights * (A + C + 2.0 / 3.0 * B - 2.0 * C * (2.0 / 3.0 * log(2.0) - 1.0 / 6.0));
		limbFactor += weights * (A + B * cosAngle + C * (1.0 - cosAngle * log(1.0 + secAngle)));
		weightTotal += weights;
	}
	averageLimbFactor /= weightTotal;
	edgeLimbFactor /= weightTotal;
	limbFactor /= weightTotal;

	vec3 colour = surfaceRadiance * limbFactor / averageLimbFactor; // The average value of limbFactor / averageLimbFactor is 1, so the average output value is still surfaceRadiance
	return ColourTransmittance (colour, vec3(0.0));
}
