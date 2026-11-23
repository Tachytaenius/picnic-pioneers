// Currently writing to: output radiance and temp transmittance

uniform sampler2D transmittanceCanvas; // For the whole scene. Everything from camera up to (but excluding) the current layer

uniform sampler2D MainTex; // Radiance from layer (given by love.graphics.draw)
uniform sampler2D objectTransmittanceCanvas; // Transmittance from layer
uniform usampler2D additions;
uniform float scale;

layout(location = 0) out vec4 fragmentColour;
layout(location = 1) out vec4 fragmentOpacity;

void pixelmain() {
	ivec2 coord = ivec2(love_PixelCoord.xy * scale);
	uint count = texelFetch(additions, coord, 0).r;
	if (count == 0u) {
		fragmentColour = vec4(0.0);
		fragmentOpacity = vec4(0.0);
		return;
	}
	vec4 transmittanceInFront = texture(transmittanceCanvas, love_PixelCoord.xy / love_ScreenSize.xy);
	fragmentColour = transmittanceInFront * texelFetch(MainTex, coord, 0) / float(count);
	fragmentOpacity = vec4(1.0) - texelFetch(objectTransmittanceCanvas, coord, 0) / float(count);
}
