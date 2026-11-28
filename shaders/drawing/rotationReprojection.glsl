uniform mat4 reproject;
uniform uint maxAdditions;
uniform float additionsMultiplier;
uniform uint minMultipliedAdditions;
uniform ivec2 size;

uniform sampler2D radianceIn;
uniform sampler2D transmittanceIn;
uniform usampler2D additionsIn;
uniform layout(rgba32f) image2D radianceOut;
uniform layout(rgba16f) image2D transmittanceOut;
uniform layout(r8ui) uimage2D additionsOut;

vec3 perspectiveDivide(vec4 v) {
	return v.xyz / v.w;
}

vec4 get(sampler2D tex, ivec2[4] clampedOutTexelCoords, vec4 additionsClamped, vec2 texelLerp) {
	vec4 tex00 = texelFetch(tex, clampedOutTexelCoords[0], 0);
	vec4 tex10 = texelFetch(tex, clampedOutTexelCoords[1], 0);
	vec4 tex01 = texelFetch(tex, clampedOutTexelCoords[2], 0);
	vec4 tex11 = texelFetch(tex, clampedOutTexelCoords[3], 0);

	return mix(
		mix(
			additionsClamped[0] == 0.0 ? vec4(0.0) : (tex00 / additionsClamped[0]),
			additionsClamped[1] == 0.0 ? vec4(0.0) : (tex10 / additionsClamped[1]),
			texelLerp.x
		),
		mix(
			additionsClamped[2] == 0.0 ? vec4(0.0) : (tex01 / additionsClamped[2]),
			additionsClamped[3] == 0.0 ? vec4(0.0) : (tex11 / additionsClamped[3]),
			texelLerp.x
		),
		texelLerp.y
	);
}

layout (local_size_x = 8, local_size_y = 8) in;
void computemain() {
	ivec2 inTexelCoord = ivec2(love_GlobalThreadID.xy);
	if (any(greaterThanEqual(inTexelCoord, size))) {
		return;
	}
	vec2 inClip = vec2(inTexelCoord) / vec2(size) * 2.0 - 1.0;
	vec2 outClip = perspectiveDivide(reproject * vec4(inClip, -1.0, 1.0)).xy;
	vec2 outTexelCoordSmooth = vec2((outClip * 0.5 + 0.5) * vec2(size));
	ivec2 outTexelCoord = ivec2(outTexelCoordSmooth);
	vec2 texelLerp = mod(outTexelCoordSmooth, vec2(1.0));

	ivec2 outTexelCoords[] = ivec2[](
		outTexelCoord + ivec2(0, 0),
		outTexelCoord + ivec2(1, 0),
		outTexelCoord + ivec2(0, 1),
		outTexelCoord + ivec2(1, 1)
	);

	ivec2 clampedOutTexelCoords[] = ivec2[](
		clamp(outTexelCoords[0], ivec2(0), size - 1),
		clamp(outTexelCoords[1], ivec2(0), size - 1),
		clamp(outTexelCoords[2], ivec2(0), size - 1),
		clamp(outTexelCoords[3], ivec2(0), size - 1)
	);

	vec4 additionsClamped = vec4(
		texelFetch(additionsIn, clampedOutTexelCoords[0], 0).r,
		texelFetch(additionsIn, clampedOutTexelCoords[1], 0).r,
		texelFetch(additionsIn, clampedOutTexelCoords[2], 0).r,
		texelFetch(additionsIn, clampedOutTexelCoords[3], 0).r
	);

	bool allUnclampedAdditions0 = all(equal(uvec4(
		texelFetch(additionsIn, outTexelCoords[0], 0).r,
		texelFetch(additionsIn, outTexelCoords[1], 0).r,
		texelFetch(additionsIn, outTexelCoords[2], 0).r,
		texelFetch(additionsIn, outTexelCoords[3], 0).r
	), uvec4(0)));

	float newAdditions = (additionsClamped[0] + additionsClamped[1] + additionsClamped[2] + additionsClamped[3]) / 4.0;
	float multipliedAdditions = floor(newAdditions * additionsMultiplier);
	if (multipliedAdditions > float(minMultipliedAdditions)) {
		newAdditions = multipliedAdditions;
	} else {
		newAdditions = floor(newAdditions);
	}
	newAdditions = min(float(maxAdditions), newAdditions);

	vec4 radianceWrite;
	vec4 transmittanceWrite;
	uvec4 addWrite;

	if (allUnclampedAdditions0) {
		radianceWrite = vec4(0.0);
		transmittanceWrite = vec4(0.0);
		addWrite = uvec4(0);
	} else {
		radianceWrite = newAdditions * get(radianceIn, clampedOutTexelCoords, additionsClamped, texelLerp);
		transmittanceWrite = newAdditions * get(transmittanceIn, clampedOutTexelCoords, additionsClamped, texelLerp);
		addWrite = uvec4(newAdditions, 0, 0, 0);
	}

	imageStore(radianceOut, inTexelCoord, radianceWrite);
	imageStore(transmittanceOut, inTexelCoord, transmittanceWrite);
	imageStore(additionsOut, inTexelCoord, addWrite);
}
