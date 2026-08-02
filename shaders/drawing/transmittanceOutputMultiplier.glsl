uniform sampler2D MainTex;

out vec4 outColour;

void pixelmain() {
	outColour = texture(MainTex, love_PixelCoord.xy / love_ScreenSize.xy).rrra;
}
