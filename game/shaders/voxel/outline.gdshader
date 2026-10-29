// 3D dungeon view: outline (next pass): the figure grown a little and drawn inside-out in ink. Neon packs
// make the ink glow.
shader_type spatial;
render_mode unshaded, cull_front;
uniform float grow = 0.15;
uniform vec4 ink : source_color = vec4(0.04, 0.03, 0.06, 1.0);
uniform float neon = 0.0;
void vertex() {
	VERTEX += NORMAL * grow;
}
void fragment() {
	ALBEDO = ink.rgb * (1.0 + neon * 3.0);
}
