readonly buffer ChunkPointCounts {
	int chunkPointCounts[];
};
uniform int maxPointsPerChunk;

struct PointDrawable {
	vec3 direction;
	vec3 radiance;
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
uniform sampler3D pointAttenuationTexture; // Only considering the current layer and only up to the point end distance.
uniform sampler2D totalTransmittanceCanvas; // Same as above. Has no depth information. Is multiplied down by closer nebulae from layers smaller than the current one. Essentially the "starting point" for the above texture.
uniform int chunkBufferSideLength;
uniform vec3 viewMinPosInChunkBuffer;
uniform float radianceCalcConst;

uniform float fadeInRadius;
uniform float fadeOutRadius;
uniform float fadeExponent;

uniform vec3 cameraForwards;
uniform float minDot;

shared uint writeCount;
shared uint writeOffset;

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
	bool isFirst = love_LocalThreadID.x == 0;
	if (isFirst) {
		writeCount = 0;
	}
	barrier();

	uint i = love_GlobalThreadID.x;
	bool isSkip = i == skipIndex;
	int chunkIndex = int(i) / maxPointsPerChunk;
	bool isPastChunkEnd = int(i) % maxPointsPerChunk >= chunkPointCounts[chunkIndex]; 
	bool isPastAllEnd = i >= POINT_COUNT;

	// Can't use early return syntax since the first thread has work to do after point drawables are acquired
	bool write = false;
	uint indexThisThreadgroup;
	PointDrawable pointDrawable;
	if (!isSkip && !isPastChunkEnd && !isPastAllEnd) {
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
		bool outsideFOV = dotResult < minDot;
		if (!outsideFOV) {
			float pointFadeMultiplier = pow(clamp(
				1.0 - (dist - fadeInRadius) / (fadeOutRadius - fadeInRadius),
				0.0, 1.0
			), fadeExponent);
			float dist2 = dist * dist;
			vec3 radiance = point.radiantIntensity / dist2 * radianceCalcConst;
			// Radiance calculation constant is (ignoring overall brightness multiplier and the factor for drawing the disks with even brightness at any fade exponent) equal to 1 / diskSolidAngle.
			// When dividing the intensity by dist^2 we get irradiance from this light source at that distance. (I believe there are factors of 4pi both above and below that cancel out. One from within the area in the denominator and one from a solid angle. This leaves us with just a dist^2 denominator.)
			// We imagine the irradiance to blur out into a region on a spherical surface around the camera (specifically, it blurs out into a spherical cap) and then direct all its light straight into the centre of the camera sphere.
			// The average radiance from the perspective of the centre of the camera sphere is then equal to the irradiance divided by the solid angle of the spherical cap.

			vec3 clipSpacePos = perspectiveDivide(skyToClip * vec4(direction, 1.0));
			vec3 textureSamplePos = vec3(
				clipSpacePos.xy * 0.5 + 0.5,
				dist / fadeOutRadius
			);
			vec2 totalTransmittanceCoord = vec2(textureSamplePos.x, 1.0 - textureSamplePos.y); // TODO: Why did this (and pointDrawables' version) need to y flip???
			float transmittance =
				texture(pointAttenuationTexture, textureSamplePos).r *
				texture(totalTransmittanceCanvas, totalTransmittanceCoord).r;

			pointDrawable = PointDrawable (
				direction,
				transmittance * radiance * pointFadeMultiplier
			);
			write = true;
			indexThisThreadgroup = atomicAdd(writeCount, 1);
		}
	}

	barrier();
	if (isFirst) {
		writeOffset = atomicAdd(indirectDrawBuffer[0].instanceCount, writeCount);
	}
	barrier();

	if (write) {
		pointDrawables[writeOffset + indexThisThreadgroup] = pointDrawable;
	}
}
