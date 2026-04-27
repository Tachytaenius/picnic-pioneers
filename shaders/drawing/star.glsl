#ifdef PIXEL

in vec3 directionPreNormalise;

uniform vec3 surfaceLuminance; // A sphere that is a lambertian emitter (such as a star) has a contant luminance. Limb darkening is not considered yet (TODO: realistic star rendering!! NOTE: If limb darkening affects overall brightness at a distance, account for that.)
uniform vec3 bodyPosition;
uniform float bodyRadius;
uniform mat4 clipToSky;
uniform vec3 cameraPosition;

out vec4 fragColour;

void pixelmain() {
	vec3 direction = normalize(directionPreNormalise);
	ConvexRaycastResult result = sphereRaycast(bodyPosition, bodyRadius, cameraPosition, direction);
	if (!result.hit) {
		discard;
	}
	if (result.t2 <= 0.0) {
		// Body is behind us
		discard;
	}
	// if (result.t1 <= 0.0) {
	// 	// Inside body
	// 	discard;
	// }

	vec3 outColour = surfaceLuminance;
	fragColour = vec4(outColour, 1.0);
}

#endif
