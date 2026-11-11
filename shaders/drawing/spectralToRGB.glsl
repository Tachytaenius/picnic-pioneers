const mat3 xyzToRGB = mat3(
	// Column-major
	+3.2406255, -0.9689307, +0.0557101,
	-1.5372080, +1.8757561, -0.2040211,
	-0.4986286, +0.0415175, +1.0569959
);

uniform mat3 spectralToXYZ;

uniform sampler2D MainTex;

out vec4 rgb; // Linear sRGB

void pixelmain() {
	vec3 spectral = texelFetch(MainTex, ivec2(love_PixelCoord.xy), 0).rgb;
	vec3 xyz = spectralToXYZ * spectral;
	rgb = vec4(xyzToRGB * xyz, 1.0);
}
