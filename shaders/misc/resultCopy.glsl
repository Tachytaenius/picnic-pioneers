uniform uint directionGroup;
writeonly buffer Results {
	vec3 results[];
};
uniform sampler2DArray readCanvas;

layout (local_size_x = LAYERS) in;
void computemain() {
	uint i = love_GlobalThreadID.x;
	results[directionGroup * LAYERS + i] = texelFetch(readCanvas, ivec3(0, 0, i), LOD).rgb;
}
