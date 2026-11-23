uniform layout(FORMAT) image2DArray canvas;
uniform layout(rgba16f) image2DArray transmittanceCanvas;

layout (local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
void computemain() {
	ivec3 coord = ivec3(love_GlobalThreadID.xyz);
	if (any(greaterThanEqual(coord, imageSize(canvas)))) {
		return;
	}

	imageStore(canvas, coord, vec4(0.0));
	imageStore(transmittanceCanvas, coord, vec4(0.0)); // Store 0 initially
}
