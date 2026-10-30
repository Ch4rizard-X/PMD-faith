// 3D dungeon view: a Pokémon figure (vertex colours from its sprite). mod = the 2D sprite's modulate
// (hit flash > 1, fading out < 1 alpha); glow = Awakened / neon emission.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform vec4 mod_col = vec4(1.0);
uniform vec3 glow_col = vec3(0.0);
uniform vec3 lead_pos = vec3(0.0);
uniform float torch = 0.0;
uniform vec3 torch_col = vec3(1.0);
uniform int toon = 0;
uniform float wrap = 0.0;
varying vec3 wpos;
uniform float push_c = 8.0;      // depth pull toward the camera (voxel_view._fig_push)
uniform float push_k = 0.8;      // more per unit of height (the leaning top)
uniform float push_floor = 2.0;  // more per unit under the floor
uniform float wet = 0.0;
vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.z += push_c + max(VERTEX.y, 0.0) * push_k + max(1.1 - wpos.y, 0.0) * push_floor;
	POSITION = PROJECTION_MATRIX * v;
}
void fragment() {
	vec3 c = to_lin(COLOR.rgb) * mod_col.rgb;
	if (torch > 0.0) {
		float d = length(wpos.xz - lead_pos.xz);
		float k = 1.0 - smoothstep(torch * 0.55, torch * 1.15, d);
		c *= mix(vec3(0.07), torch_col, k);
	}
	ALBEDO = c;
	EMISSION = glow_col + max(mod_col.rgb - vec3(1.0), vec3(0.0)) * to_lin(COLOR.rgb);
	// fading out: screen-door dither (stays in the opaque pipeline, so it still casts a shadow)
	if (mod_col.a < 0.99 && fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453) > mod_col.a) {
		discard;
	}
	ROUGHNESS = mix(0.8, 0.45, wet);
}
void light() {
	float nl = dot(NORMAL, LIGHT);
	nl = max((nl + wrap) / (1.0 + wrap), 0.0);
	if (toon > 0) {
		nl = floor(nl * float(toon) + 0.5) / float(toon);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * nl / PI;
}
