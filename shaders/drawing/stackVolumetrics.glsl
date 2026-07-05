uniform sampler2DArray canvas;
uniform uint count;
uniform float multiplier;

out vec4 outColour;

void pixelmain() {
	vec3 sum = vec3(0.0);
	for (uint i = 0u; i < count; i++) {
		sum += texelFetch(canvas, ivec3(love_PixelCoord.xy, i), 0).rgb;
	}
	outColour = vec4(multiplier * sum, 1.0);
}
