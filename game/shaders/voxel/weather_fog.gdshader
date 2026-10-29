// 3D dungeon view: a layer of drifting fog (or blowing sand) over the floor, following the camera.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec3 col = vec3(0.8);
uniform float amount = 0.5;
uniform vec2 wind = vec2(6.0, 2.0);
uniform float scale = 0.012;
varying vec3 wpos;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz * scale + wind * TIME * scale;
	float v = n(p) * 0.55 + n(p * 2.3 + 11.0) * 0.3 + n(p * 5.1 - TIME * 0.05) * 0.15;
	ALBEDO = col;
	ALPHA = clamp(smoothstep(0.3, 0.85, v) * amount, 0.0, 0.85);
}
