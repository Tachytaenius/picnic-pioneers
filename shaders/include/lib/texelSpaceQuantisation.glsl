#ifdef PIXEL

// https://godotshaders.com/shader/texel-space-quantization/

// Calculate screen-space displacement from the center of the current texel
vec2 screen_delta(vec2 uv, sampler2D tex) {
	vec2 tex_size = vec2(textureSize(tex, 0));
	vec2 texel_center = (floor(uv * tex_size) + 0.5) / tex_size;
	vec2 offset = texel_center - uv;
	mat2 screen_to_uv = mat2(dFdx(uv), dFdy(uv));
	mat2 uv_to_screen = inverse(screen_to_uv);
	return uv_to_screen * offset;
}

// Snap vec_type to extrapolated value at the center of the current texel
float texel_snap(float v, vec2 delta) {
	return v + dFdx(v) * delta.x + dFdy(v) * delta.y;
}

vec2 texel_snap(vec2 v, vec2 delta) {
	return v + dFdx(v) * delta.x + dFdy(v) * delta.y;
}

vec3 texel_snap(vec3 v, vec2 delta) {
	return v + dFdx(v) * delta.x + dFdy(v) * delta.y;
}

vec4 texel_snap(vec4 v, vec2 delta) {
	return v + dFdx(v) * delta.x + dFdy(v) * delta.y;
}

#endif
