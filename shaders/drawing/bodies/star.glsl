uniform vec3 surfaceLuminance; // A sphere that is a lambertian emitter (such as a star) has a contant luminance. Limb darkening is not considered yet (TODO: realistic star rendering!! NOTE: If limb darkening affects overall brightness at a distance, account for that.)

vec4 sampleBody(vec3 surfaceEnterPos, vec3 surfaceExitPos, vec3 direction) { // In/out positions are relative to body centre
	return vec4(surfaceLuminance, 0.0);
}
