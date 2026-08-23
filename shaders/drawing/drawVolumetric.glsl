uniform sampler2D MainTex;
uniform usampler2D additions;
uniform float scale;

out vec4 fragmentColour;

void pixelmain() {
	ivec2 coord = ivec2(love_PixelCoord.xy * scale);
	uint count = texelFetch(additions, coord, 0).r;
	if (count == 0u) {
		discard;
	}
	fragmentColour = texelFetch(MainTex, coord, 0).rrrg / float(count);
}
