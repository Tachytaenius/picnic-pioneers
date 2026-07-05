#ifdef PIXEL

in vec3 directionPreNormalise;

out vec4 fragmentColour;

uniform vec3 cameraPosition;
uniform uint maxRaySteps;

uniform float fadeInRadius;
uniform float fadeOutRadius;
uniform float fadeExponent;

uniform vec3 baseEmission;

uniform vec3 shapeRadii;

uniform float rayChance;
uniform uint raySeed;
uniform float rayStepVariance;

VolumetricSample sampleVolumetrics(vec3 samplePosition) {
	float density = sampleShapeDensity(samplePosition);
	return VolumetricSample (
		0.0,
		baseEmission * density
	);
}

vec3 getRayColour(vec3 rayPosition, vec3 rayDirection, float sampleLerp) {
	vec3 totalRayLuminance = vec3(0.0);
	float totalTransmittance = 1.0;
	// Ray moves backwards from end to camera
	// We increase detail towards camera
	// Sample in the middle of each ray segment

	ConvexRaycastResult result = ellipsoidRaycast(vec3(0.0), shapeRadii, rayPosition, rayDirection);
	if (!result.hit || result.t2 <= 0.0) {
		return vec3(0.0);
	}

	float rayOffset = max(0.0, result.t1);
	float rayLength = result.t2 - rayOffset;

	float maxRayLength = 2.0 * max(max(shapeRadii.x, shapeRadii.y), shapeRadii.z); // A whole diameter
	uint rayStepCount = max(maxRaySteps, uint(max(0.0, rayLength / maxRayLength) * (maxRaySteps - 1) + 1.0));

	float segmentStart = result.t2;
	for (uint rayStep = 0u; rayStep < rayStepCount; rayStep++) {
		float t = 1.0 - float(rayStep) / float(rayStepCount);
		t = t * t; // Increase detail towards camera (without using pow)
		float segmentEnd = rayOffset + rayLength * t;
		float rayStepSize = segmentStart - segmentEnd; // Start is greater than end
		float sampleT = mix(segmentEnd, segmentStart, sampleLerp);
		vec3 samplePosition = (rayPosition + rayDirection * sampleT) / shapeRadii;

		float emissionFadeMultiplier = pow(clamp(
			1.0 - (sampleT - fadeInRadius) / (fadeOutRadius - fadeInRadius),
			0.0, 1.0
		), fadeExponent);

		float transmittanceThisStep = 1.0;

		VolumetricSample volumetricSample = sampleVolumetrics(samplePosition);
		float attenuation = volumetricSample.attenuation; // TODO: Make attenuation nonzero and work out how to keep it working across all the drawcalls etc
		transmittanceThisStep *= exp(-attenuation * rayStepSize);

		vec3 rayLuminanceThisStep = rayStepSize * volumetricSample.emission * emissionFadeMultiplier;
		totalRayLuminance = totalRayLuminance * transmittanceThisStep + rayLuminanceThisStep;
		totalTransmittance *= transmittanceThisStep;

		segmentStart = segmentEnd;
	}
	return totalRayLuminance;
}

void pixelmain() {
	uint x = uint(love_PixelCoord.x);
	uint y = uint(love_PixelCoord.y);
	uint w = uint(love_ScreenSize.x);
	uint h = uint(love_ScreenSize.y);
	uint pixelId = x + y * w;
	uint chanceSeed = pixelId ^ raySeed;
	if (rayChance == 1.0 || hash11(chanceSeed) < rayChance) {
		vec3 direction = normalize(directionPreNormalise);
		uint variationSeed = (pixelId + w * h) ^ raySeed;
		float stepVariation = (hash11(variationSeed) - 0.5) * rayStepVariance + 0.5;
		vec3 outColour = getRayColour(cameraPosition, direction, stepVariation);
		fragmentColour = vec4(outColour, 1.0);
		return;
	}
	fragmentColour = vec4(vec3(0.0), 1.0);
}


#endif
