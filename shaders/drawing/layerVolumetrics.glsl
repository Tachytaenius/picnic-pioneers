uniform uint maxRaySteps;

uniform vec3 baseEmission;
uniform float attenuationMultiplier;

uniform vec3 shapeRadii;

uniform float brightnessMultiplier;
uniform ivec2 size;

#ifndef INTENSITY_PRECALC
uniform layout(RESULT_CANVAS_FORMAT) image2D resultCanvas;
uniform layout(rgba16f) image2D resultTransmittanceCanvas;

uniform vec3 cameraPosition;

uniform layout(r8ui) uimage2D additionCountCanvas;

uniform vec3[4] preNormaliseCornerDirs;

uniform uint raySeed;
uniform float rayStepVariance;

uniform float fadeInRadius;
uniform float fadeOutRadius;
uniform float fadeExponent;
#else
uniform layout(RESULT_CANVAS_FORMAT) image2DArray resultCanvas;
uniform layout(rgba16f) image2DArray resultTransmittanceCanvas;
uniform int directionGroup;
uniform float samplingDiskRadius;

DIRECTION_CONST_ARRAY

COSINE_CONST_ARRAY

#endif

VolumetricSample sampleVolumetrics(vec3 samplePosition) {
	vec3 samplePositionTrueRatio = samplePosition * shapeRadii / max(shapeRadii.x, max(shapeRadii.y, shapeRadii.z));
	float emissionDensity = sampleEmissionShapeDensity(samplePosition, samplePositionTrueRatio);
	vec3 attenuationSample = sampleAttenuationShape(samplePosition, samplePositionTrueRatio);
#ifdef INTENSITY_PRECALC
#ifdef AVG_ATT_SPECTRUM_FOR_PRECALC
	attenuationSample = vec3((attenuationSample.r + attenuationSample.g + attenuationSample.b) / 3.0);
#endif
#endif
	return VolumetricSample (
		attenuationMultiplier * attenuationSample,
		baseEmission * emissionDensity
	);
}

ColourTransmittance getRayColourAndTransmittance(vec3 rayPosition, vec3 rayDirection, float sampleLerp) {
	vec3 totalRayRadiance = vec3(0.0);
	vec3 totalTransmittance = vec3(1.0);
	// Ray moves backwards from end to camera
	// We increase detail towards camera
	// Sample in the middle of each ray segment

	ConvexRaycastResult result = ellipsoidRaycast(vec3(0.0), shapeRadii, rayPosition, rayDirection);
	if (!result.hit || result.t2 <= 0.0) {
		return ColourTransmittance (totalRayRadiance, totalTransmittance);
	}

	float rayOffset = max(0.0, result.t1);
	float rayLength = result.t2 - rayOffset;

	// float maxRayLength = 2.0 * max(max(shapeRadii.x, shapeRadii.y), shapeRadii.z); // A whole diameter
	// uint rayStepCount = clamp(uint(
	// 	rayLength / maxRayLength * maxRaySteps
	// ), 2, maxRaySteps);
	uint rayStepCount = maxRaySteps;

	float segmentStart = result.t2;
	for (uint rayStep = 0u; rayStep < rayStepCount; rayStep++) {
		float t = 1.0 - float(rayStep + 1) / float(rayStepCount);
		t = t * t; // Increase detail towards camera (without using pow)
		float segmentEnd = rayOffset + rayLength * t;
		float rayStepSize = segmentStart - segmentEnd;
		float sampleT = mix(segmentEnd, segmentStart, sampleLerp);
		vec3 samplePosition = (rayPosition + rayDirection * sampleT) / shapeRadii;

#ifndef INTENSITY_PRECALC
		float emissionFadeMultiplier = 1.0 - pow(clamp(
			(sampleT - fadeInRadius) / (fadeOutRadius - fadeInRadius),
			0.0, 1.0
		), fadeExponent);
#else
		float emissionFadeMultiplier = 1.0;
#endif

		vec3 transmittanceThisStep = vec3(1.0);

		VolumetricSample volumetricSample = sampleVolumetrics(samplePosition);
		vec3 attenuation = volumetricSample.attenuation;
		transmittanceThisStep *= exp(-attenuation * rayStepSize);

		vec3 rayRadianceThisStep = rayStepSize * volumetricSample.emission * emissionFadeMultiplier;
		totalRayRadiance = totalRayRadiance * transmittanceThisStep + rayRadianceThisStep;
		totalTransmittance *= transmittanceThisStep;

		segmentStart = segmentEnd;
	}
	return ColourTransmittance (totalRayRadiance, totalTransmittance);
}

#ifndef Z_SIZE
#define Z_SIZE 1
#endif

layout (local_size_x = 8, local_size_y = 8, local_size_z = Z_SIZE) in;
void computemain() {
	ivec2 coord = ivec2(love_GlobalThreadID.xy);
	if (any(greaterThanEqual(coord, size))) {
		return;
	}

#ifdef INTENSITY_PRECALC
	uint curLayer = love_GlobalThreadID.z;
	if (curLayer >= LAYERS) {
		return;
	}
#endif

#ifndef INTENSITY_PRECALC
	vec2 mixFactor = (vec2(coord) + 0.5) / vec2(size);
	vec3 direction = normalize(
		mix (
			mix(preNormaliseCornerDirs[0], preNormaliseCornerDirs[1], mixFactor.x),
			mix(preNormaliseCornerDirs[2], preNormaliseCornerDirs[3], mixFactor.x),
			mixFactor.y
		)
	);

	uint currentCount = imageLoad(additionCountCanvas, ivec2(coord)).r;
	if (currentCount >= MAX_ADDITIONS) {
		return;
	}
	imageStore(additionCountCanvas, ivec2(coord), uvec4(currentCount + 1, 0, 0, 1));

	int x = coord.x;
	int y = coord.y;
	int w = size.x;
	int h = size.y;
	uint pixelId = uint(x + y * w);
	// uint chanceSeed = pixelId ^ raySeed;
	// if (rayChance == 1.0 || hash11(chanceSeed) < rayChance) {
		uint variationSeed = (pixelId + w * h) ^ raySeed;
		float stepVariation = (hash11(variationSeed) - 0.5) * rayStepVariance + 0.5;
#else
		vec3 rand = hash33(ivec3(coord, directionGroup * LAYERS + curLayer));
		vec2 posOnDisk = (vec2(coord) + rand.xy) / vec2(size) * 2.0 - 1.0;
		float stepVariation = rand.z;
		if (length(posOnDisk) > 1.0) {
			return;
		}

		vec3 cameraForwards = directions[curLayer * 3 + 0];
		vec3 cameraUp = directions[curLayer * 3 + 1];
		vec3 cameraRight = directions[curLayer * 3 + 2];

		vec3 direction = cameraForwards;
		vec3 cameraPosition = samplingDiskRadius * (-cameraForwards + cameraRight * posOnDisk.x + cameraUp * posOnDisk.y);
#endif
		ColourTransmittance colourTransmittance = getRayColourAndTransmittance(cameraPosition, direction, stepVariation);
		vec3 colour = colourTransmittance.colour;
		vec3 transmittance = colourTransmittance.transmittance;

		colour *= brightnessMultiplier;

#ifdef INTENSITY_PRECALC
		ivec3 writeCoord = ivec3(coord, curLayer);
		vec4 inColour = vec4(0.0);
		vec4 inTransmittance = vec4(0.0); // Assume 0 initially
#else
		ivec2 writeCoord = coord;
		vec4 inColour = imageLoad(resultCanvas, writeCoord);
		vec4 inTransmittance = imageLoad(resultTransmittanceCanvas, writeCoord);
#endif

		vec4 toWrite = vec4(colour + inColour.rgb, 0.0);
		imageStore(resultCanvas, writeCoord, toWrite);

		vec4 transmittanceToWrite = vec4(transmittance, 1.0) + inTransmittance;
		imageStore(resultTransmittanceCanvas, writeCoord, transmittanceToWrite);
	// }
}
