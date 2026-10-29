// 3D dungeon view: terrain. Faces with UV >= 0 take the floor's tile picture, the others their vertex colour;
// vertex alpha is the corner shading. Dark floors light only a circle around the team (torch). Shader packs
// set toon bands, wrap ("clay") lighting and the rest through uniforms.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
uniform sampler2D map : filter_nearest, source_color;
uniform vec3 lead_pos = vec3(0.0);
uniform float torch = 0.0;            // radius in world units, 0 = lit floor
uniform vec3 torch_col = vec3(1.0);
uniform float ao = 0.35;
uniform int toon = 0;
uniform float wrap = 0.0;
varying vec3 wpos;
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
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
void light() {
	float nl = dot(NORMAL, LIGHT);
	nl = (nl + wrap) / (1.0 + wrap);
	nl = max(nl, 0.0);
	if (toon > 0) {
		nl = floor(nl * float(toon) + 0.5) / float(toon);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * nl / PI;
}
