#ifdef VERTEX

uniform mat4 clipToSky;

layout (location = 0) in vec4 VertexPosition;
layout (location = 1) in vec4 VertexTexCoord;

out vec3 directionPreNormalise;

void vertexmain() {
	directionPreNormalise = (
		clipToSky * vec4(
#ifdef FLIP_Y
			(VertexTexCoord.xy * 2.0 - 1.0) * vec2(1.0, -1.0),
#else
			(VertexTexCoord.xy * 2.0 - 1.0),
#endif
			-1.0,
			1.0
		)
	).xyz;
	gl_Position = vec4(VertexTexCoord.xy * 2.0 - 1.0, 1.0, 1.0);
}

#endif
