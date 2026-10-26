shader_type canvas_item;
// Shiny Pokémon: swaps each normal colour of the SpriteCollab sheet for its shiny colour (data/shiny.json).
uniform int n = 0;
uniform vec3 src[16];
uniform vec3 dst[16];
varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec3 o = c.rgb;
	for (int i = 0; i < 16; i++) {
		if (i >= n) {
			break;
		}
		if (distance(c.rgb, src[i]) < 0.003) {
			o = dst[i];
			break;
		}
	}
	COLOR = vec4(o, c.a) * vcol;
}
