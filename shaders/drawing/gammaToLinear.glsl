uniform sampler2D MainTex;

out vec4 outColour;

void pixelmain() {
	vec3 texSample = texture(MainTex, love_PixelCoord.xy / textureSize(MainTex, 0)).rgb;
	outColour = vec4(gammaToLinear(texSample), 1.0);
}
