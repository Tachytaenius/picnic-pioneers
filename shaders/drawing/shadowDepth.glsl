#ifdef VERTEX

uniform mat4 modelToWorld;

#ifdef OMNIDIRECTIONAL
	uniform mat4[6] worldToClipCubemap;
#else
	uniform mat4 worldToClip;
#endif

layout (location = 0) in vec3 VertexPosition;
layout (location = 1) in vec2 VertexTexCoord;

out vec3 fragmentPosition;
out vec2 fragmentTexCoord;

void vertexmain() {
#ifdef OMNIDIRECTIONAL
	gl_Layer = gl_InstanceID;
	mat4 worldToClip = worldToClipCubemap[gl_InstanceID];
#endif
	fragmentPosition = (modelToWorld * vec4(VertexPosition, 1.0)).xyz;
	fragmentTexCoord = VertexTexCoord;
	gl_Position = worldToClip * vec4(fragmentPosition, 1.0);
}

#endif

#ifdef PIXEL

in vec3 fragmentPosition;
in vec2 fragmentTexCoord;

uniform float lightRadius;
uniform vec3 lightPosition;

uniform uint randomSeed;
uniform sampler2D windowTransmittanceTexture;

out vec4 fragmentColour;

ivec4 bvecToIvec(bvec4 v) {
	return ivec4(
		v.x ? 1 : 0,
		v.y ? 1 : 0,
		v.z ? 1 : 0,
		v.w ? 1 : 0
	);
}

void pixelmain() {
	float depth = distance(fragmentPosition, lightPosition) / lightRadius;

	vec4 surfaceTransmittance = vec4(texture(windowTransmittanceTexture, fragmentTexCoord).rgb, 1.0);
	ivec2 coord = ivec2(love_PixelCoord.xy);
	vec4 rand = hash43(uvec3(coord, randomSeed)); // Has colour noise
	// vec4 rand = vec4(hash13(uvec3(coord, randomSeed)));
	fragmentColour = max(vec4(depth), vec4(bvecToIvec(lessThan(rand, surfaceTransmittance))));

	gl_FragDepth = depth;
}

#endif
