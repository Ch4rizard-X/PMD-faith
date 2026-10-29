// 3D dungeon view: water surface over the darker bed. See-through, small moving waves and glints.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_lambert, specular_schlick_ggx;
uniform sampler2D map : filter_nearest, source_color;
uniform vec4 deep : source_color = vec4(0.05, 0.15, 0.35, 1.0);
uniform float alpha = 0.72;
uniform float waves = 1.0;
uniform vec3 lead_pos = vec3(0.0);
uniform float torch = 0.0;
uniform vec3 torch_col = vec3(1.0);
varying vec3 wpos;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wpos = w;
}
void fragment() {
	float r1 = sin(TIME * 1.3 * waves + wpos.x * 0.18 + wpos.z * 0.07);
	float r2 = sin(TIME * 2.1 * waves + wpos.z * 0.23 - wpos.x * 0.05);
	float ripple = 0.5 + 0.25 * (r1 + r2);
	vec3 c = mix(texture(map, UV).rgb, deep.rgb, 0.25) + vec3(0.07) * ripple * waves;
	if (torch > 0.0) {
		float d = length(wpos.xz - lead_pos.xz);
		float k = 1.0 - smoothstep(torch * 0.55, torch * 1.15, d);
		c *= mix(vec3(0.07), torch_col, k);
	}
	ALBEDO = c;
	NORMAL_MAP = normalize(vec3(r1 * 0.15 * waves, r2 * 0.15 * waves, 1.0)) * 0.5 + 0.5;
	ALPHA = alpha;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
}
