shader_type canvas_item;
render_mode blend_premul_alpha;
// Red's ground weather layer (ground_weather.c): a BG layer alpha-blended with the map by BLDALPHA
// (gUnknown_2026E4E). The map is the first target (coefficient eva), the weather the second (evb):
// result = map * eva + weather * evb over the weather's opaque pixels. Optional BPL palette animation
// as in ground_palette.gdshader.
uniform float eva = 1.0;
uniform float evb = 1.0;
uniform sampler2D idx_tex : filter_nearest, repeat_enable;
uniform sampler2D pal_tex : filter_nearest;
uniform int anim_rows = 0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (anim_rows != 0) {
		int idx = int(round(texture(idx_tex, UV).r * 255.0));
		int row = idx / 16;
		int col = idx - row * 16;
		if (col != 0 && ((anim_rows >> row) & 1) == 1) {
			c.rgb = texelFetch(pal_tex, ivec2(col, row), 0).rgb;
		}
	}
	float a = c.a;
	COLOR = vec4(c.rgb * evb * a, (1.0 - eva) * a);
}
