// https://en.wikipedia.org/wiki/Limb_darkening#Calculation_of_limb_darkening
const int limbCoefficientsLength = 3;
const float limbCoefficients[limbCoefficientsLength] = float[](0.3, 0.93, -0.23); // For the sun, at 550 nm

uniform vec3 surfaceRadiance;

ColourTransmittance sampleBody(vec3 cameraPosition, vec3 direction, vec3 surfaceNormal, vec3 surfaceEnterPos, vec3 surfaceExitPos) { // Positions are relative to body centre
	// This is based on uniforms only so should be optimised?
	float averageLimbFactor = 0.0;
	for (int k = 0; k < limbCoefficientsLength; k++) {
		averageLimbFactor += limbCoefficients[k] / (float(k) + 2.0);
	}
	averageLimbFactor *= 2.0;

	// TODO: Compensate for change in output radiance correctly. Do I just divide by averageLimbFactor like so?
	vec3 centralRadiance = surfaceRadiance / averageLimbFactor;

	float angle = acos(clamp(dot(normalize(cameraPosition - surfaceEnterPos), surfaceNormal), -1.0, 1.0));

	float limbFactor = 0.0;
	for (int k = 0; k < limbCoefficientsLength; k++) {
		limbFactor += limbCoefficients[k] * pow(cos(angle), float(k));
	}

	vec3 colour = centralRadiance * limbFactor;
	return ColourTransmittance (colour, vec3(0.0));
}
