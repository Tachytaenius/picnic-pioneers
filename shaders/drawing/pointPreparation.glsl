// TODO: Per-layer ifdef features

readonly buffer ChunkPointCounts {
	int chunkPointCounts[];
};
uniform int maxPointsPerChunk;

struct Point {
#ifdef FEATURE_POSITION
	vec3 position;
#endif
#ifdef FEATURE_LUMINOUS_FLUX
	vec3 luminousFlux;
#endif
#ifdef FEATURE_SHAPE_TYPE_SUBTYPE
	uvec2 shapeTypeSubtypeIds;
#endif
};
readonly buffer Points {
	Point points[];
};

struct PointDrawable {
	vec3 direction;
	vec3 luminance;
};
writeonly buffer PointDrawables {
	PointDrawable pointDrawables[];
};

struct IndirectDrawArgs {
	uint vertexCount;
	uint instanceCount;
	uint baseVertex;
	uint baseInstance;
};
buffer IndirectDrawBuffer {
	IndirectDrawArgs indirectDrawBuffer[];
};

uniform uint skipIndex;
uniform vec3 cameraPosition;
uniform mat4 skyToClip;
// uniform sampler3D pointAttenuationTexture; // TODO
uniform int chunkBufferSideLength;
uniform vec3 viewMinPosInChunkBuffer;
uniform float luminanceCalcConst;

uniform float fadeInRadius;
uniform float fadeOutRadius;

uniform vec3 cameraForwards;
uniform float minDot;

vec3 perspectiveDivide(vec4 v) {
	return v.xyz / v.w;
}

ivec3 bvecToIvec(bvec3 v) {
	return ivec3(
		v.x ? 1 : 0,
		v.y ? 1 : 0,
		v.z ? 1 : 0
	);
}

layout(local_size_x = THREADGROUP_SIZE, local_size_y = 1, local_size_z = 1) in;
void computemain() {
	uint i = love_GlobalThreadID.x;
	if (i >= POINT_COUNT) {
		return;
	}

	if (i == skipIndex) {
		return;
	}

	int chunkIndex = int(i) / maxPointsPerChunk;
	if (int(i) % maxPointsPerChunk >= chunkPointCounts[chunkIndex]) {
		return;
	}

	ivec3 chunkBufferPos = ivec3(
		chunkIndex % chunkBufferSideLength,
		(chunkIndex / chunkBufferSideLength) % chunkBufferSideLength,
		(chunkIndex / chunkBufferSideLength) / chunkBufferSideLength
	);

	Point point = points[i];
	ivec3 chunkPos = chunkBufferPos + chunkBufferSideLength * bvecToIvec(lessThan(chunkBufferPos + 0.5, viewMinPosInChunkBuffer));
	vec3 pointPosition = chunkPos + point.position;
	vec3 difference = pointPosition - cameraPosition;

	float dist = length(difference);
	vec3 direction = difference / dist;

	float dotResult = dot(cameraForwards, direction);
	if (dotResult < minDot) {
		return;
	}

	float pointFadeMultiplier = clamp(
		1.0 - (dist - fadeInRadius) / (fadeOutRadius - fadeInRadius),
		0.0, 1.0
	);
	float dist2 = dist * dist;
	vec3 luminance = point.luminousFlux / dist2 * luminanceCalcConst; // Luminance within the light source's spherical cap on the celestial sphere. All combined, it should be flux / (dist^2 * 4pi * diskSolidAngle), where flux / (dist^2 * 4pi) takes it from luminous flux to luminous exitance and then the exitance divided by the disk solid angle gets you the luminance. Should be right, even if some of the names are wrong. TODO: We have learned more, so make sure this is true!
	vec3 clipSpacePos = perspectiveDivide(skyToClip * vec4(direction, 1.0));
	vec3 textureSamplePos = clipSpacePos;
	textureSamplePos.xy = textureSamplePos.xy * 0.5 + 0.5;
	textureSamplePos.z = dist / fadeOutRadius;
	// float transmittance = Texel(starAttenuationTexture, textureSamplePos).r;
	float transmittance = 1.0; // TEMP/TODO

	PointDrawable pointDrawable = PointDrawable (
		direction,
		transmittance * luminance * pointFadeMultiplier
	);
	uint index = atomicAdd(indirectDrawBuffer[0].instanceCount, 1);
	pointDrawables[index] = pointDrawable;
}
