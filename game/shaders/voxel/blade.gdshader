// 3D dungeon view: a grass blade / seaweed frond / flower (one box per blade, MultiMesh). Darker at the
// root, lighter at the tip; a flower (INSTANCE_CUSTOM.g = 1) has a green stem and its colour on top.
// Leans with the wind, more toward the tip.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform float sway = 0.55;
uniform float speed = 1.6;
uniform vec3 lead_pos = vec3(0.0);
uniform float torch = 0.0;
uniform vec3 torch_col = vec3(1.0);
uniform int toon = 0;
varying vec3 wpos;
uniform float wet = 0.0;            // weather: rain soaks surfaces (darker, shinier)
uniform float snow = 0.0;           // weather: snow / hail settles on top faces
float whash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
varying float t;
varying float flower;
void vertex() {
	t = VERTEX.y + 0.5;
	flower = INSTANCE_CUSTOM.g;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float hgt = length(MODEL_MATRIX[1].xyz);
	float ph = w.x * 0.21 + w.z * 0.17;
	float s = sin(TIME * speed + ph) + 0.4 * sin(TIME * speed * 2.3 + ph * 1.7);
	vec3 off = vec3(s, 0.0, 0.6 * cos(TIME * speed * 0.8 + ph)) * sway * t * hgt * 0.22;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	wpos = w + off;
}
void fragment() {
	vec3 col = to_lin(COLOR.rgb);
	vec3 c = col;
	if (flower > 0.5) {
		c = t > 0.66 ? col : to_lin(vec3(0.3, 0.6, 0.18)) * (0.7 + 0.3 * t);
	} else {
		c = mix(col * 0.6, col * 1.25, t);
	}
	if (torch > 0.0) {
		float d = length(wpos.xz - lead_pos.xz);
		float k = 1.0 - smoothstep(torch * 0.55, torch * 1.15, d);
		c *= mix(vec3(0.07), torch_col, k);
	}
	if (snow > 0.0 && t > 0.8 && whash(floor(wpos.xz)) < snow) {
		c = vec3(0.92, 0.95, 1.0);
	}
	c *= mix(1.0, 0.8, wet);
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
void light() {
	float nl = max(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0);
	if (toon > 0) {
		nl = floor(nl * float(toon) + 0.5) / float(toon);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * nl / PI;
}
