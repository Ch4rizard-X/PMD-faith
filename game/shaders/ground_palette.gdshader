shader_type canvas_item;
// Red's BPL palette animation on a pre-rendered ground layer: idx_tex holds palette_row*16 + colour per
// native pixel; rows whose bit is set in anim_rows take their colour from the live 16x16 palette texture.
uniform sampler2D idx_tex : filter_nearest, repeat_enable;
uniform sampler2D pal_tex : filter_nearest;
uniform int anim_rows = 0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	int idx = int(round(texture(idx_tex, UV).r * 255.0));
	int row = idx / 16;
	int col = idx - row * 16;
	if (col != 0 && ((anim_rows >> row) & 1) == 1) {
		vec4 p = texelFetch(pal_tex, ivec2(col, row), 0);
		COLOR = vec4(p.rgb, c.a);
	} else {
		COLOR = c;
	}
}
