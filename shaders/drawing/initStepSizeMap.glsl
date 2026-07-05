uniform layout (r16f) image3D map;
uniform vec3 radii;

shared uint maxGradientFixed;
// shared float densities[THREADGROUP_SIZE + 2][THREADGROUP_SIZE + 2][THREADGROUP_SIZE + 2]; // TODO?: Reduce unnecessary sampling by sharing samples across threads

const uint fixedFloatToInt = 0x40000000;
const float minStepSize = 0.0001;
const float maxStepSize = 1.0 / float(IMAGE_SIZE) * 0.99 * 2.0; // Don't skip over any cells when raymarching...? (Is there some better way?)

layout (local_size_x = THREADGROUP_SIZE, local_size_y = THREADGROUP_SIZE, local_size_z = THREADGROUP_SIZE) in;
void computemain() {
	ivec3 outCoord = ivec3(love_ThreadGroupID);
	// Threadgroup count will completely match the range of output coordinates

	bool isMainWorker = all(equal(love_LocalThreadID, ivec3(0)));
	if (isMainWorker) {
		maxGradientFixed = 0;
	}
	barrier();

	uvec3 totalSize = love_ThreadGroupCount * love_ThreadGroupSize;
	vec3 samplePos = (vec3(love_GlobalThreadID) + 0.5) / vec3(totalSize) * 2.0 - 1.0;
	vec3 d = 1.0 / vec3(totalSize) * 2.0; // Was going to be called nextSampleOffset

	vec3 gradient = vec3(
		(sampleShapeDensity(samplePos + vec3(d.x, 0, 0)) - sampleShapeDensity(samplePos - vec3(d.x, 0, 0))) / (2.0 * d.x * radii.x),
		(sampleShapeDensity(samplePos + vec3(0, d.y, 0)) - sampleShapeDensity(samplePos - vec3(0, d.y, 0))) / (2.0 * d.y * radii.y),
		(sampleShapeDensity(samplePos + vec3(0, 0, d.z)) - sampleShapeDensity(samplePos - vec3(0, 0, d.z))) / (2.0 * d.z * radii.z)
	);
	float gradientMagnitude = length(gradient);
	uint gradientFixed = uint(fixedFloatToInt * gradientMagnitude);
	atomicMax(maxGradientFixed, gradientFixed);

	barrier();
	if (!isMainWorker) {
		return;
	}
	float gradientMagnitudeDecoded = float(maxGradientFixed) / float(fixedFloatToInt);
	float stepSize = clamp(STEP_SIZE_MUL / gradientMagnitudeDecoded, minStepSize, maxStepSize); // clamp should handle any inf
	imageStore(map, outCoord, vec4(stepSize, 0.0, 0.0, 1.0));
}
