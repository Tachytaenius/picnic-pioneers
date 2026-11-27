// Fragment shader
#ifdef PIXEL

// Inputs
in vec2 fragmentTexCoord;
in vec3 fragmentNormal;
in vec3 fragmentPosition;

// Outputs
#if TRANSLUCENT
layout(location = 0) out vec4 fragmentColourWrite;
layout(location = 1) out vec4 fragmentOpacityWrite;
#else
out vec4 fragmentColourWrite;
#endif

// Uniforms
uniform sampler2D entityAlbedo;
#if TRANSLUCENT
uniform sampler2D transmittanceCanvas;
uniform sampler2D entityTransmittance;
#endif
uniform int pointLightCount;
uniform vec3[MAX_POINT_LIGHTS] lightRadiantIntensities;
uniform vec3[MAX_POINT_LIGHTS] lightPositions;
uniform float[MAX_POINT_LIGHTS] lightRadii;
uniform samplerCube[MAX_POINT_LIGHTS] shadowColourMaps;
uniform uint randomSeed;

// Utilities
ivec3 bvecToIvec(bvec3 v) {
	return ivec3(
		v.x ? 1 : 0,
		v.y ? 1 : 0,
		v.z ? 1 : 0
	);
}

// Main
void pixelmain() {
	vec3 radiance = vec3(0.0);

	vec3 albedo = texture(entityAlbedo, fragmentTexCoord).rgb;
#if TRANSLUCENT
	// NOTE: Because
	// transmittedLight + absorbedLight + reflectedLight = incomingLight,
	// transmittance + albedo <= 1
	// We may take from transmittance to ensure this
	vec3 surfaceTransmittance = texture(entityTransmittance, fragmentTexCoord).rgb;
	vec3 sum = surfaceTransmittance + albedo;
	surfaceTransmittance -= max(vec3(0.0), sum - 1.0);
	// Unsure if this maths is right: could alternatively multiply transmittance by (1.0 - albedo) to assume that the transmittance texture = transmitted / absorbed instead of transmitted / incoming;
	vec3 transmittanceUpToSurface = texture(transmittanceCanvas, love_PixelCoord.xy / love_ScreenSize.xy).rgb;
#else
	vec3 transmittanceUpToSurface = vec3(1.0);
#endif

	vec2 texScreenDelta = screen_delta(fragmentTexCoord, entityAlbedo);
#if QUANTISE_LIGHTING
	vec3 fragmentPositionQuantised = texel_snap(fragmentPosition, texScreenDelta);
#else
	vec3 fragmentPositionQuantised = fragmentPosition;
#endif

	for (int i = 0; i < pointLightCount; i++) {
		vec3 lightToFragment = lightPositions[i] - fragmentPositionQuantised;
		float dist = length(lightToFragment);
		float cosTheta = max(0.0, dot(normalize(fragmentNormal), normalize(lightToFragment)));
		float bias = mix(BIAS_MIN, BIAS_MAX, 1.0 - cosTheta);

		// Percentage-closer filtering
		vec3 shadow = vec3(0.0);
		ivec3 samples = ivec3(PCF_SAMPLES);
		int sampleId = 0;
		for (int xi = 0; xi < samples.x; xi++) {
			for (int yi = 0; yi < samples.y; yi++) {
				for (int zi = 0; zi < samples.z; zi++) {
					vec3 jitter = hash33(uvec3(love_PixelCoord.xy, sampleId ^ randomSeed)) * JITTER_SIZE * 2.0 - 1.0;
					vec3 offset = ((vec3(xi, yi, zi) + 0.5) * 2.0 - 1.0 + jitter) * PCF_OFFSET;
					vec3 depthSample = texture(shadowColourMaps[i], -lightToFragment + offset).rgb;
					shadow += vec3(bvecToIvec(greaterThan((depthSample + bias) * lightRadii[i], vec3(dist))));
					sampleId += 1;
				}
			}
		}
		shadow /= float(samples.x * samples.y * samples.z);

		float dist2 = dist * dist;
		radiance += albedo * lightRadiantIntensities[i] / dist2 * cosTheta * shadow;
	}

	fragmentColourWrite = vec4(transmittanceUpToSurface * radiance, 0.0);
#if TRANSLUCENT
	fragmentOpacityWrite = vec4(1.0) - vec4(surfaceTransmittance, 1.0);
#endif
}

#endif
