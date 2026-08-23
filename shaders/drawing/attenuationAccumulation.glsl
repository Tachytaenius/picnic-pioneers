uniform vec2 canvasSize;
uniform usampler2D additionCanvas;

vec4 effect(vec4 loveColour, sampler2D image, vec2 textureCoords, vec2 windowCoords) {
	ivec2 coord = ivec2(textureCoords * canvasSize);
	return vec4(
		1.0 - texelFetch(image, coord, 0).g / float(texture(additionCanvas, coord, 0).r),
		0.0, 0.0, 1.0
	);
}
