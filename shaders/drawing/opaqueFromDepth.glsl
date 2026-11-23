uniform sampler2D MainTex;

out vec4 transmittance;

void pixelmain() {
	float depth = texelFetch(MainTex, ivec2(love_PixelCoord.xy), 0).r;
	if (depth == 1.0) {
		discard;
	}
	transmittance = vec4(0.0);
}
