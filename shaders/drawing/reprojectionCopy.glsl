uniform ivec2 size;

uniform sampler2D radianceIn;
uniform sampler2D transmittanceIn;
uniform usampler2D additionsIn;
uniform layout(rgba32f) image2D radianceOut;
uniform layout(rgba16f) image2D transmittanceOut;
uniform layout(r8ui) uimage2D additionsOut;

layout (local_size_x = 8, local_size_y = 8) in;
void computemain() {
	ivec2 inTexelCoord = ivec2(love_GlobalThreadID.xy);
	if (any(greaterThanEqual(inTexelCoord, size))) {
		return;
	}

	imageStore(radianceOut, inTexelCoord, texelFetch(radianceIn, inTexelCoord, 0));
	imageStore(transmittanceOut, inTexelCoord, texelFetch(transmittanceIn, inTexelCoord, 0));
	imageStore(additionsOut, inTexelCoord, texelFetch(additionsIn, inTexelCoord, 0));
}
