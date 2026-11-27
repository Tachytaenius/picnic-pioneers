uniform mat3 spectralToRGB;

uniform sampler2D MainTex;

out vec4 rgb; // Linear sRGB

void pixelmain() {
	vec3 spectral = texelFetch(MainTex, ivec2(love_PixelCoord.xy), 0).rgb;
	rgb = vec4(spectralToRGB * spectral, 1.0);
}
