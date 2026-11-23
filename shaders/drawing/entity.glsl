#ifdef PIXEL

uniform sampler2D entityTexture;

uniform sampler2D transmittanceCanvas;

in vec2 fragmentTexCoord;
in vec3 fragmentNormal;
in vec3 fragmentPosition;

out vec4 fragmentColourWrite;

void pixelmain() {
	vec3 albedo = texture(entityTexture, fragmentTexCoord).rgb;
	// float dist = distance(lightPos, fragmentPosition);
	// float dist2 = dist * dist;
	// float cosTheta = max(0.0, dot(normalize(fragmentNormal), lightPos - fragmentPosition));
	// vec3 fragmentColour = albedo * lightRadiantIntensity / dist2 * cosTheta;
	vec3 fragmentColour = albedo * 1e6;
	fragmentColourWrite = vec4(fragmentColour, 0.0);
}

#endif
