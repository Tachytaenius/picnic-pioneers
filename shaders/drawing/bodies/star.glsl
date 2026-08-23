uniform float surfaceRadiance; // A sphere that is a lambertian emitter has a contant radiance. Limb darkening is not considered yet (TODO: realistic star rendering!! NOTE: If limb darkening affects overall brightness at a distance, account for that.)

vec2 sampleBody(vec3 surfaceEnterPos, vec3 surfaceExitPos, vec3 direction) { // In/out positions are relative to body centre
	return vec2(surfaceRadiance, 0.0);
}
