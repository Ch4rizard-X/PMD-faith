// Grass blades / seaweed: each cube leans with the wind, more the higher it is above its root
// (INSTANCE_CUSTOM.r = root height), every blade a little out of step.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform float strength = 0.55;
uniform float speed = 1.6;
uniform vec3 lead_pos = vec3(0.0);
uniform float vis_radius = 0.0;
varying vec3 wpos;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float above = max(0.0, w.y - INSTANCE_CUSTOM.r);
	float ph = w.x * 0.21 + w.z * 0.17;
	float s = sin(TIME * speed + ph) + 0.4 * sin(TIME * speed * 2.3 + ph * 1.7);
	vec3 off = vec3(s, 0.0, 0.6 * cos(TIME * speed * 0.8 + ph)) * strength * above * 0.22;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
	wpos = w + off;
}
void fragment() {
	vec3 c = COLOR.rgb;
	if (vis_radius > 0.0) {
		float d = length(wpos.xz - lead_pos.xz);
		c *= mix(1.0, 0.08, smoothstep(vis_radius * 0.55, vis_radius * 1.15, d));
	}
	ALBEDO = c;
	ROUGHNESS = 0.85;
}
