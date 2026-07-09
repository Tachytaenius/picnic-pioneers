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
	vec3 outColour = texelFetch(MainTex, coord, 0).rgb / float(count);
	fragmentColour = vec4(outColour, 1.0);
}
