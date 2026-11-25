#ifdef PIXEL

uniform sampler2D windowTransmittanceTexture;

uniform sampler2D transmittanceCanvas;

in vec2 fragmentTexCoord;
in vec3 fragmentNormal;
in vec3 fragmentPosition;

layout(location = 0) out vec4 fragmentColourWrite;
layout(location = 1) out vec4 fragmentOpacityWrite;

void pixelmain() {
	vec3 transmittanceUpToSurface = texture(transmittanceCanvas, love_PixelCoord.xy / love_ScreenSize.xy).rgb;
	vec3 surfaceTransmittance = texture(windowTransmittanceTexture, fragmentTexCoord).rgb;
	vec3 radiance = vec3(0.0);
	fragmentColourWrite = vec4(transmittanceUpToSurface * radiance, 0.0);
	fragmentOpacityWrite = vec4(1.0) - vec4(surfaceTransmittance, 1.0);
}

#endif
