#ifndef QUANTISE_LIGHTING
#define QUANTISE_LIGHTING 0
#endif

#ifdef PIXEL

uniform sampler2D entityTexture;

uniform sampler2D transmittanceCanvas;

in vec2 fragmentTexCoord;
in vec3 fragmentNormal;
in vec3 fragmentPosition;

out vec4 fragmentColourWrite;

uniform int pointLightCount;
uniform vec3[MAX_POINT_LIGHTS] lightRadiantIntensities;
uniform vec3[MAX_POINT_LIGHTS] lightPositions;
uniform float[MAX_POINT_LIGHTS] lightRadii;
uniform samplerCube[MAX_POINT_LIGHTS] shadowColourMaps;
uniform uint randomSeed;

ivec3 bvecToIvec(bvec3 v) {
	return ivec3(
		v.x ? 1 : 0,
		v.y ? 1 : 0,
		v.z ? 1 : 0
	);
}

void pixelmain() {
	vec3 albedo = texture(entityTexture, fragmentTexCoord).rgb;

	vec3 fragmentColour = vec3(0.0);

	vec2 texScreenDelta = screen_delta(fragmentTexCoord, entityTexture);

#if QUANTISE_LIGHTING
	vec3 fragmentPositionQuantised = texel_snap(fragmentPosition, texScreenDelta);
#else
	vec3 fragmentPositionQuantised = fragmentPosition;
#endif

	for (int i = 0; i < pointLightCount; i++) {
		vec3 lightToFragment = lightPositions[i] - fragmentPositionQuantised;
		float dist = length(lightToFragment);
		float cosTheta = max(0.0, dot(normalize(fragmentNormal), normalize(lightToFragment)));
		float bias = max(0.01 * (1.0 - cosTheta), 0.001);

		// Percentage-closer filtering
		vec3 shadow = vec3(0.0);
		ivec3 samples = ivec3(PCF_SAMPLES);
		int sampleId = 0;
		for (int xi = 0; xi < samples.x; xi++) {
			for (int yi = 0; yi < samples.y; yi++) {
				for (int zi = 0; zi < samples.z; zi++) {
					vec3 jitter = hash33(uvec3(love_PixelCoord.xy, sampleId ^ randomSeed));
					vec3 offset = ((vec3(xi, yi, zi) + jitter) * 2.0 - 1.0) * PCF_OFFSET;
					vec3 depthSample = texture(shadowColourMaps[i], -lightToFragment + offset).rgb;
					shadow += vec3(bvecToIvec(greaterThan((depthSample + bias) * lightRadii[i], vec3(dist))));
					sampleId += 1;
				}
			}
		}
		shadow /= float(samples.x * samples.y * samples.z);

		float dist2 = dist * dist;
		fragmentColour += albedo * lightRadiantIntensities[i] / dist2 * cosTheta * shadow;
	}

	fragmentColourWrite = vec4(fragmentColour, 0.0);
}

#endif
