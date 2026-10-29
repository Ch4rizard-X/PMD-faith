// 3D dungeon view: terrain. Faces with UV >= 0 take the floor's tile picture, the others their vertex colour;
// vertex alpha is the corner shading. Dark floors light only a circle around the team (torch). Shader packs
// set toon bands, wrap ("clay") lighting and the rest through uniforms.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert;
uniform sampler2D map : filter_nearest, source_color;
uniform vec3 lead_pos = vec3(0.0);
uniform float torch = 0.0;            // radius in world units, 0 = lit floor
uniform vec3 torch_col = vec3(1.0);
uniform float ao = 0.35;
uniform int toon = 0;
uniform float wrap = 0.0;
varying vec3 wpos;
uniform float wet = 0.0;            // weather: rain soaks surfaces (darker, shinier)
uniform float snow = 0.0;           // weather: snow / hail settles on top faces
float whash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float wnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(whash(i), whash(i + vec2(1, 0)), f.x), mix(whash(i + vec2(0, 1)), whash(i + vec2(1, 1)), f.x), f.y);
}
vec3 to_lin(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 c = UV.x < 0.0 ? to_lin(COLOR.rgb) : texture(map, UV).rgb * to_lin(COLOR.rgb);
	c *= mix(1.0, COLOR.a, ao);
	if (torch > 0.0) {
		float d = length(wpos.xz - lead_pos.xz);
		float k = 1.0 - smoothstep(torch * 0.55, torch * 1.15, d);
		c *= mix(vec3(0.07), torch_col, k);
	}
	vec3 wn = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	if (snow > 0.0 && wn.y > 0.7) {
		float n = wnoise(wpos.xz * 0.07) * 0.75 + whash(floor(wpos.xz)) * 0.25;   // drifts, a little grain
		float cover = snow * (wpos.y > 8.0 ? 1.15 : 0.8);       // wall tops gather more than the floor
		if (n < cover) {
			c = mix(c, vec3(0.92, 0.95, 1.0), smoothstep(0.0, 0.25, cover - n));
		}
	}
	float r = 0.9;
	if (wet > 0.0) {
		c *= mix(1.0, 0.72, wet);
		r = mix(0.9, 0.25, wet);
		SPECULAR = 0.5 * wet;
	}
	ALBEDO = c;
	ROUGHNESS = r;
}
void light() {
	float nl = dot(NORMAL, LIGHT);
	nl = (nl + wrap) / (1.0 + wrap);
	nl = max(nl, 0.0);
	if (toon > 0) {
		nl = floor(nl * float(toon) + 0.5) / float(toon);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * nl / PI;
	if (wet > 0.0) {
		vec3 hv = normalize(LIGHT + VIEW);
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * pow(max(dot(NORMAL, hv), 0.0), 40.0) * wet * 0.6;
	}
}
