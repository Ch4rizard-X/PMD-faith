// 3D dungeon view: the shader pack's screen pass (over the 3D view and the floor overlay, under the menus):
// saturation, contrast, brightness, tint, palette limit, black and white / sepia, tilt-shift or background
// blur, dream haze, paper, film grain, vignette, scanlines, colour fringe.
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float sat = 1.0;
uniform float contrast = 1.0;
uniform float bright = 1.0;
uniform vec3 tint = vec3(1.0);
uniform float tint_amt = 0.0;
uniform float palette = 0.0;
uniform int mono = 0;
uniform int dof = 0;
uniform float dof_amt = 0.0;
uniform float haze = 0.0;
uniform float paper = 0.0;
uniform float grain = 0.0;
uniform float vignette = 0.0;
uniform float scan = 0.0;
uniform float ca = 0.0;
uniform int fog = 0;                 // 1 distance (the top of the screen is farther), 2 a low haze over everything
uniform float fog_amt = 0.0;
uniform vec3 fog_col = vec3(0.5);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 blur(vec2 uv, float r, vec2 px) {
	vec3 s = vec3(0.0);
	float tot = 0.0;
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			vec2 o = vec2(float(i), float(j)) * r * px;
			s += textureLod(screen, uv + o, r * 0.25).rgb;
			tot += 1.0;
		}
	}
	return s / tot;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 c;
	if (ca > 0.0) {
		vec2 o = (uv - 0.5) * 0.004 * ca;
		c = vec3(texture(screen, uv + o).r, texture(screen, uv).g, texture(screen, uv - o).b);
	} else {
		c = texture(screen, uv).rgb;
	}
	if (dof > 0 && dof_amt > 0.0) {
		float k = dof == 1 ? smoothstep(0.18, 0.5, abs(uv.y - 0.55)) : smoothstep(0.45, 0.0, uv.y);
		if (k > 0.01) {
			c = mix(c, blur(uv, 3.0 * k * dof_amt, SCREEN_PIXEL_SIZE), clamp(k * 1.2, 0.0, 1.0));
		}
	}
	if (haze > 0.0) {
		vec3 b = blur(uv, 4.0, SCREEN_PIXEL_SIZE);
		c = mix(c, max(c, b), haze);
		c += b * haze * 0.08;
	}
	if (fog > 0 && fog_amt > 0.0) {
		float f = fog == 1 ? smoothstep(0.75, 0.0, uv.y) : 0.6;
		c = mix(c, fog_col, clamp(f * fog_amt * 1.6, 0.0, 0.85));
	}
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, sat);
	c = (c - 0.5) * contrast + 0.5;
	c *= bright;
	c = mix(c, c * tint, tint_amt * 3.0);
	if (mono == 1) {
		c = vec3(dot(c, vec3(0.299, 0.587, 0.114)));
	} else if (mono == 2) {
		float m = dot(c, vec3(0.299, 0.587, 0.114));
		c = vec3(m * 1.07, m * 0.88, m * 0.66);
	}
	if (palette > 1.0) {
		float lv = pow(palette, 1.0 / 3.0);
		c = floor(c * lv + 0.5) / lv;
	}
	if (paper > 0.0) {
		float f = hash(floor(uv * vec2(420.0, 240.0))) * 0.5 + hash(floor(uv * vec2(60.0, 900.0))) * 0.5;
		c = mix(c, c * (0.88 + 0.12 * f) + vec3(0.04, 0.03, 0.0), paper);
	}
	if (grain > 0.0) {
		c += (hash(uv * 911.0 + fract(TIME * 7.0)) - 0.5) * grain;
	}
	if (vignette > 0.0) {
		vec2 d = uv - 0.5;
		c *= 1.0 - vignette * smoothstep(0.25, 0.75, dot(d, d) * 2.2);
	}
	if (scan > 0.0) {
		c *= 1.0 - scan * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
