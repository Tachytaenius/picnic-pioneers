uniform float outputMultiplier;
uniform vec3 bodyPosition;
uniform vec3 cameraPosition;
uniform vec3[4] preNormaliseCornerDirs;

uniform layout(rgba16f) image2D transmittanceCanvas;
uniform layout(rgba32f) image2D lightCanvas;
uniform ivec2 size;

layout (local_size_x = 16, local_size_y = 16) in;
void computemain() {
	ivec2 coord = ivec2(love_GlobalThreadID.xy);
	if (any(greaterThanEqual(coord, size))) {
		return;
	}

	vec2 mixFactor = (vec2(coord) + 0.5) / vec2(size);
	vec3 direction = normalize(
		mix (
			mix(preNormaliseCornerDirs[0], preNormaliseCornerDirs[1], mixFactor.x),
			mix(preNormaliseCornerDirs[2], preNormaliseCornerDirs[3], mixFactor.x),
			mixFactor.y
		)
	);

	ConvexRaycastResult result = sphereRaycast(bodyPosition, bodyRadius, cameraPosition, direction);
	if (!result.hit) {
		return;
	}
	if (result.t2 < 0.0) {
		// Body is behind us
		return;
	}
	// if (result.t1 <= 0.0) {
	// 	// Inside body
	// 	return;
	// }

	vec3 startHitPosRelative = cameraPosition + direction * max(0.0, result.t1) - bodyPosition;
	vec3 surfaceNormal = normalize(startHitPosRelative); // For sphere. If we change it to an ellipsoid, though...

	ColourTransmittance bodySample = sampleBody( // Radiance in RGB and transmittance in A
		cameraPosition - bodyPosition,
		direction,
		surfaceNormal,
		startHitPosRelative,
		cameraPosition + direction * result.t2 - bodyPosition
	);

	vec4 transmittanceThisBody = vec4(bodySample.transmittance, 1.0);
	vec4 radianceThisBody = vec4(bodySample.colour, 0.0) * outputMultiplier;

	// Read
	vec4 transmittanceBeforeBody = imageLoad(transmittanceCanvas, coord); // From camera up to but excluding body
	vec4 currentRadiance = imageLoad(lightCanvas, coord); // Radiance currently reaching the camera

	// Modify
	vec4 newRadiance = currentRadiance + radianceThisBody * transmittanceBeforeBody;
	vec4 transmittanceIncludingBody = transmittanceThisBody * transmittanceBeforeBody;

	// Write
	imageStore(transmittanceCanvas, coord, transmittanceIncludingBody);
	imageStore(lightCanvas, coord, newRadiance);
}
