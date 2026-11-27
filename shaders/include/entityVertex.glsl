#ifdef VERTEX

uniform mat4 modelToClip;
uniform mat4 modelToWorld;
uniform mat3 modelToWorldNormal;
uniform vec3 cameraPosition;

layout (location = 0) in vec3 VertexPosition;
layout (location = 1) in vec2 VertexTexCoord;
layout (location = 2) in vec3 VertexNormal;

out vec2 fragmentTexCoord;
out vec3 fragmentNormal;
out vec3 fragmentPosition;

void vertexmain() {
	fragmentTexCoord = VertexTexCoord;
	fragmentPosition = (modelToWorld * vec4(VertexPosition, 1.0)).xyz;

	fragmentNormal = normalize(modelToWorldNormal * VertexNormal); // Is this normalisation required, or just the one in pixelmain?
#if DOUBLE_SIDED_NORMAL
	if (dot(cameraPosition - fragmentPosition, fragmentNormal) < 0.0) {
		fragmentNormal = -fragmentNormal;
	}
#endif

	gl_Position = modelToClip * vec4(VertexPosition, 1.0);
}

#endif
