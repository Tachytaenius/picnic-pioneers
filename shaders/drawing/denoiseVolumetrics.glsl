uniform sampler2D MainTex;

uniform ivec2 size;
uniform ivec2 destinationSize;

out vec4 outColour;

void pixelmain() {
	vec2 textureCoords = love_PixelCoord.xy / love_ScreenSize.xy;
	outColour = texture(MainTex, textureCoords);
	// outColour = smartDeNoise(MainTex, textureCoords, 0.1, 30.0, 0.025);
}
