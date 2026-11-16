uniform float outputMultiplier;
uniform vec3 bodyPosition;
uniform mat4 clipToSky;
uniform vec3 cameraPosition;
uniform vec3[4] preNormaliseCornerDirs;

uniform layout(rgba16f) image2D totalTransmittanceCanvas;
uniform layout(rgba32f) image2D outputCanvas;
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
	// 	discard;
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

	// Read
	vec3 transmittance = imageLoad(totalTransmittanceCanvas, coord).rgb; // Transmittance between body and camera
	vec3 currentOut = imageLoad(outputCanvas, coord).rgb; // Get current colour
	vec3 transmittanceThisBody = bodySample.transmittance;
	// Modify
	vec3 newOut = currentOut * transmittanceThisBody + outputMultiplier * bodySample.colour;
	transmittance *= transmittanceThisBody; // Let body contribute to blocking everything that comes after it
	// Write
	imageStore(totalTransmittanceCanvas, coord, vec4(transmittance, 1.0));
	imageStore(outputCanvas, coord, vec4(newOut, 1.0));
}
