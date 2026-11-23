uniform layout(rgba16f) image2D tempOpacityCanvas;
uniform layout(rgba16f) image2D transmittanceCanvas;

layout (local_size_x = 8, local_size_y = 8) in;
void computemain() {
	ivec2 size = imageSize(transmittanceCanvas); // Expected to be same as tempOpacityCanvas' size
	ivec2 coord = ivec2(love_GlobalThreadID.xy);
	if (any(greaterThanEqual(coord, size))) {
		return;
	}

	imageStore(transmittanceCanvas, coord,
		imageLoad(transmittanceCanvas, coord) *
		(vec4(1.0) - imageLoad(tempOpacityCanvas, coord))
	);
	imageStore(tempOpacityCanvas, coord, vec4(0.0));
}
