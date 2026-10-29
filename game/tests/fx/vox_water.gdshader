// Water: a see-through surface with small moving waves and highlights; the tile art shows through.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_lambert, specular_schlick_ggx;
uniform vec4 deep : source_color = vec4(0.05, 0.15, 0.35, 1.0);
uniform float alpha = 0.72;
varying vec3 wpos;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (VERTEX.y > 0.0) {
		float wave = sin(TIME * 1.3 + w.x * 0.18 + w.z * 0.07) * 0.35 + sin(TIME * 2.1 + w.z * 0.23) * 0.2;
		VERTEX.y += wave / max(0.01, length(MODEL_MATRIX[1].xyz));
		w.y += wave;
	}
	wpos = w;
}
void fragment() {
	float ripple = 0.5 + 0.5 * sin(wpos.x * 0.6 + wpos.z * 0.4 + TIME * 2.0);
	ALBEDO = mix(COLOR.rgb, deep.rgb, 0.25) + vec3(0.06) * ripple;
	ALPHA = alpha;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}
