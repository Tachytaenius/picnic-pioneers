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
uniform samplerCube[MAX_POINT_LIGHTS] shadowMaps;

void pixelmain() {
	vec3 albedo = texture(entityTexture, fragmentTexCoord).rgb;

	vec3 fragmentColour = vec3(0.0);

	vec2 texScreenDelta = screen_delta(fragmentTexCoord, entityTexture);

	vec3 fragmentPositionQuantised = texel_snap(fragmentPosition, texScreenDelta);

	for (int i = 0; i < pointLightCount; i++) {
		vec3 lightToFragment = lightPositions[i] - fragmentPositionQuantised;
		float dist = length(lightToFragment);
		float cosTheta = max(0.0, dot(normalize(fragmentNormal), normalize(lightToFragment)));
		float bias = max(0.01 * (1.0 - cosTheta), 0.001);

		// Percentage-closer filtering
		float shadow = 0.0;		
		float offset = 0.05;
		ivec3 samples = ivec3(PCF_SAMPLES);
		for (int xi = 0; xi < samples.x; xi++) {
			for (int yi = 0; yi < samples.y; yi++) {
				for (int zi = 0; zi < samples.z; zi++) {
					vec3 offset = (vec3(xi, yi, zi) * 2.0 - 1.0) * offset;
					float depthSample = texture(shadowMaps[i], -lightToFragment + offset).r;
					shadow += (depthSample + bias) * lightRadii[i] >= dist ? 1.0 : 0.0;
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
