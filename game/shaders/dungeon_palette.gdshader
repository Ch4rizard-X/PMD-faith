shader_type canvas_item;
// Red's dungeon palette animation (bNNcanm, UpdateAnimatedColors on BG colours 160..191) applied to the
// baked floor image (1x Red art or the upscaled HD art). idx_tex holds, per native pixel, 0 (static) or
// 1 + animated colour slot. pal_tex row 0 = the slot's current colour, row 1 = its colour in the baked art;
// the difference is added so the upscaled art keeps its shading.
uniform sampler2D idx_tex : filter_nearest;
uniform sampler2D pal_tex : filter_nearest;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	int k = int(round(texture(idx_tex, UV).r * 255.0));
	if (k > 0) {
		vec3 cur = texelFetch(pal_tex, ivec2(k - 1, 0), 0).rgb;
		vec3 base = texelFetch(pal_tex, ivec2(k - 1, 1), 0).rgb;
		c.rgb = clamp(c.rgb + cur - base, 0.0, 1.0);
	}
	COLOR = c;
}
