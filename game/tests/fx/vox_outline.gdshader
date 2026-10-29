// Pokémon outline (next pass): the cubes grown a little and drawn inside-out in dark ink.
shader_type spatial;
render_mode unshaded, cull_front;
uniform float grow = 0.22;
uniform vec4 ink : source_color = vec4(0.04, 0.03, 0.06, 1.0);
void vertex() {
	VERTEX += NORMAL * grow;
}
void fragment() {
	ALBEDO = ink.rgb;
}
