uniform sampler2D absorptionLUT;
uniform sampler2D scatteringLUT;
uniform sampler2D emissionLUT;

VolumetricSample sampleVolumetrics(vec3 samplePosition) {
	float dist = length(samplePosition);
	float proportion = dist / bodyRadius;
	vec2 coord = vec2(proportion, 0.5);
	return VolumetricSample (
		texture(absorptionLUT, coord).rgb + texture(scatteringLUT, coord).rgb,
		texture(emissionLUT, coord).rgb
	);
}

ColourTransmittance sampleBody(vec3 cameraPosition, vec3 direction, vec3 surfaceNormal, vec3 rayStartPos, vec3 surfaceExitPos) { // Positions are relative to body centre
	vec3 totalRayRadiance = vec3(0.0);
	vec3 totalTransmittance = vec3(1.0);
	uint rayStepCount = 20;
	float rayOffset = distance(cameraPosition, rayStartPos);
	float segmentStart = distance(cameraPosition, surfaceExitPos);
	float rayLength = distance(rayStartPos, surfaceExitPos);
	for (uint rayStep = 0u; rayStep < rayStepCount; rayStep++) {
		float t = 1.0 - float(rayStep + 1) / float(rayStepCount);
		t = t * t; // Increase detail towards camera (without using pow)
		float segmentEnd = rayOffset + rayLength * t;
		float rayStepSize = segmentStart - segmentEnd;
		float sampleT = mix(segmentEnd, segmentStart, 0.5);
		vec3 samplePosition = (rayStartPos + direction * sampleT);

		vec3 transmittanceThisStep = vec3(1.0);

		VolumetricSample volumetricSample = sampleVolumetrics(samplePosition);
		vec3 attenuation = volumetricSample.attenuation;
		transmittanceThisStep *= exp(-attenuation * rayStepSize);

		vec3 rayRadianceThisStep = rayStepSize * volumetricSample.emission;
		totalRayRadiance = totalRayRadiance * transmittanceThisStep + rayRadianceThisStep;
		totalTransmittance *= transmittanceThisStep;

		segmentStart = segmentEnd;
	}
	return ColourTransmittance (totalRayRadiance, totalTransmittance);
}
