// 3D dungeon view: lava. The tile picture with bright veins drifting across it; glows (with the pack's glow).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D map : filter_nearest, source_color;
uniform float glow = 1.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz * 0.09 + vec2(TIME * 0.12, TIME * 0.07);
	float v = sin(p.x * 3.1 + sin(p.y * 2.3)) * sin(p.y * 2.7 + sin(p.x * 1.9 + TIME * 0.4));
	float vein = smoothstep(0.35, 0.95, v);
	vec3 base = texture(map, UV).rgb;
	vec3 hot = mix(base, vec3(1.0, 0.85, 0.35), vein);
	ALBEDO = hot * 0.6;
	EMISSION = hot * (0.6 + 1.3 * vein) * glow;
}
