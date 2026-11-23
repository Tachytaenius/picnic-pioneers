#ifdef VERTEX

uniform mat4 modelToClip;
uniform mat4 modelToWorld;
uniform mat3 modelToWorldNormal;

layout (location = 0) in vec3 VertexPosition;
layout (location = 1) in vec2 VertexTexCoord;
layout (location = 2) in vec3 VertexNormal;

out vec2 fragmentTexCoord;
out vec3 fragmentNormal;
out vec3 fragmentPosition;

void vertexmain() {
	fragmentTexCoord = VertexTexCoord;
	fragmentNormal = normalize(modelToWorldNormal * VertexNormal); // Is this normalisation required, or just the one in pixelmain?
	fragmentPosition = (modelToWorld * vec4(VertexPosition, 1.0)).xyz;
	gl_Position = modelToClip * vec4(VertexPosition, 1.0);
}

#endif
