uniform uint index;
writeonly buffer Results {
	vec3 results[];
};
uniform sampler2D readCanvas;

layout (local_size_x = 1) in;
void computemain() {
	results[index] = texelFetch(readCanvas, ivec2(0, 0), LOD).rgb;
}
