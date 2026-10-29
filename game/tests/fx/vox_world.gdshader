// Voxel terrain / Pokémon: instance colour, plus the dungeon's darkness as light falloff around the team.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec3 lead_pos = vec3(0.0);
uniform float vis_radius = 0.0;      // 0: lit floor
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 c = COLOR.rgb;
	if (vis_radius > 0.0) {
		float d = length(wpos.xz - lead_pos.xz);
		c *= mix(1.0, 0.08, smoothstep(vis_radius * 0.55, vis_radius * 1.15, d));
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
}
