#pragma language glsl4

#ifdef VERTEX

layout (location = 0) in vec2 VertexPosition;

uniform mat4[6] clipToSkyCubemap;

out vec3 directionPreNormalise;

void vertexmain() {
	vec4 pos = vec4(VertexPosition.xy, 0.0, 1.0);
	directionPreNormalise = (clipToSkyCubemap[gl_InstanceID] * pos).xyz;
	gl_Layer = gl_InstanceID;
	gl_Position = pos;
}

#endif

#ifdef PIXEL

in vec3 directionPreNormalise;

uniform samplerCube shadowCubemap;

out vec4 fragmentColour;

void pixelmain() {
	fragmentColour = Texel(shadowCubemap, directionPreNormalise).rrrr;
}

#endif

/*
uniform samplerCube shadowCubemap;
uniform layout (COLOUR_FORMAT) imageCube shadowColourCubemap;

vec3 generateCubemapCoord(in vec2 txc, in int face)
{
	vec3 v;
	switch(face)
	{
		case 0: v = vec3( 1.0, -txc.x, txc.y); break; // +X
		case 1: v = vec3(-1.0,  txc.x, txc.y); break; // -X
		case 2: v = vec3( txc.x,  1.0, txc.y); break; // +Y
		case 3: v = vec3(-txc.x, -1.0, txc.y); break; // -Y
		case 4: v = vec3(txc.x, -txc.y,  1.0); break; // +Z
		case 5: v = vec3(txc.x,  txc.y, -1.0); break; // -Z
	}
	return normalize(v);
}

layout (local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
void computemain() {
	ivec3 coord = ivec3(love_GlobalThreadID.xyz);
	ivec3 size = ivec3(imageSize(shadowColourCubemap), 6);
	if (any(greaterThanEqual(coord, size))) {
		return;
	}
	
	imageStore(shadowColourCubemap, coord, texture(shadowCubemap, generateCubemapCoord(vec2(-1.0, 1.0) * (vec2(coord.yx) / vec2(size.xy) * 2.0 - 1.0), coord.z)).rrrr);
}
*/
