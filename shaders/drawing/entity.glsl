#ifdef VERTEX

uniform mat4 modelToClip;

layout (location = 0) in vec3 VertexPosition;
layout (location = 1) in vec2 VertexTexCoord;
layout (location = 2) in vec3 VertexNormal;

out vec2 fragmentTexCoord;
out vec3 fragmentNormal;

void vertexmain() {
	fragmentTexCoord = VertexTexCoord;
	fragmentNormal = VertexNormal;
	gl_Position = modelToClip * vec4(VertexPosition, 1.0);
}

#endif

#ifdef PIXEL

uniform sampler2D entityTexture;

in vec2 fragmentTexCoord;
in vec3 fragmentNormal;

layout(location = 0) out vec4 fragmentColour;
layout(location = 1) out vec4 transmittanceWrite;

void pixelmain() {
	fragmentColour = texture(entityTexture, fragmentTexCoord);
	transmittanceWrite = vec4(0.0, 0.0, 0.0, 1.0);
}

#endif
