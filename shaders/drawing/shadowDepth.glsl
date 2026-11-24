#pragma language glsl4

#ifdef VERTEX

uniform mat4 modelToWorld;

#ifdef OMNIDIRECTIONAL
	uniform mat4[6] worldToClipCubemap;
#else
	uniform mat4 worldToClip;
#endif

layout (location = 0) in vec3 VertexPosition;

out vec3 fragmentPosition;

void vertexmain() {
#ifdef OMNIDIRECTIONAL
	gl_Layer = gl_InstanceID;
	mat4 worldToClip = worldToClipCubemap[gl_InstanceID];
#endif
	fragmentPosition = (modelToWorld * vec4(VertexPosition, 1.0)).xyz;
	gl_Position = worldToClip * vec4(fragmentPosition, 1.0);
}

#endif

#ifdef PIXEL

in vec3 fragmentPosition;

uniform float lightRadius;
uniform vec3 lightPosition;

void pixelmain() {
	gl_FragDepth = distance(fragmentPosition, lightPosition) / lightRadius;
}

#endif
