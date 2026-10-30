// 3D dungeon view: outline (next pass): the figure grown a little and drawn inside-out in ink. Neon packs
// make the ink glow.
shader_type spatial;
render_mode unshaded, cull_front;
uniform float grow = 0.15;
uniform vec4 ink : source_color = vec4(0.04, 0.03, 0.06, 1.0);
uniform float neon = 0.0;
uniform float push_c = 8.0;      // depth pull toward the camera (voxel_view._fig_push)
uniform float push_k = 0.8;      // more per unit of height (the leaning top)
uniform float push_floor = 2.0;  // more per unit under the floor
void vertex() {
	float wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	vec3 vv = VERTEX + NORMAL * grow;
	vec4 v = MODELVIEW_MATRIX * vec4(vv, 1.0);
	v.z += push_c + max(VERTEX.y, 0.0) * push_k + max(1.1 - wy, 0.0) * push_floor;
	POSITION = PROJECTION_MATRIX * v;
}
void fragment() {
	ALBEDO = ink.rgb * (1.0 + neon * 3.0);
}
