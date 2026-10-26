class_name DungeonFx
extends Node2D
## Red's screen-wide dungeon effects, drawn in the world canvas above the floor and the Pokémon:
##  - darkness (window_buffer.c CopyWindowBgBuffer, dungeon_tilemap.c sub_803F7BC): on floors with
##    visibilityRange 1/2 everything outside the lit room is dimmed (rounded corners, sRoomCornerDim), and in
##    corridors only a circle around the leader stays lit (sCorridorDim1 / sCorridorDim2). The dim is BG1
##    blended at BLDALPHA 0x808, i.e. half black.
##  - weather colour ramp (weather.c sub_807E698): every colour channel goes through the weather's 256-entry
##    ramp from 'colvec', reached in steps of 10 per frame.
##  - weather animation (sub_8042818 -> effect_data.c): the efbg full-screen animation of rain (efbg004),
##    hail (efbg002), sandstorm (efbg006) or snow (efbg007), played once when the weather starts / the floor
##    begins, alpha-blended at 10/16 + 10/16 (gUnknown_2026E4E = 2570).

const WEATHER_INDEX := {"clear": 0, "sunny": 1, "sandstorm": 2, "cloudy": 3, "rain": 4, "hail": 5, "fog": 6, "snow": 7}
const DIM := Color(0, 0, 0, 0.5)
const ROOM_CORNER := [16, 12, 9, 7, 6, 5, 4, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0]
const CORRIDOR_DIM1 := [0x846C, 0x8967, 0x8C64, 0x8E62, 0x9060, 0x915F, 0x935D, 0x945C, 0x955B, 0x965A, 0x965A, 0x9759,
	0x9858, 0x9858, 0x9957, 0x9957, 0x9A56, 0x9A56, 0x9A56, 0x9B55, 0x9B55, 0x9B55, 0x9B55, 0x9B55, 0x9C55, 0x9C54,
	0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54,
	0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9C54, 0x9B55, 0x9B55, 0x9B55, 0x9B55, 0x9B55, 0x9A56, 0x9A56,
	0x9A56, 0x9957, 0x9957, 0x9858, 0x9858, 0x9759, 0x965A, 0x965A, 0x955B, 0x945C, 0x935D, 0x915F, 0x9060, 0x8E62,
	0x8C64, 0x8967, 0x846C]          # screen rows 48..118 (all other rows fully dim)
const CORRIDOR_DIM1_Y0 := 48
const CORRIDOR_DIM2 := [0x8071, 0x866B, 0x8A67, 0x8D64, 0x8F62, 0x9160, 0x935E, 0x955C, 0x975A, 0x9958, 0x9A57, 0x9B56,
	0x9D54, 0x9E53, 0xA051, 0xA051, 0xA150, 0xA24F, 0xA44D, 0xA54C, 0xA54C, 0xA64B, 0xA74A, 0xA849, 0xA948, 0xA948,
	0xAA47, 0xAA47, 0xAB46, 0xAC45, 0xAC45, 0xAD44, 0xAD44, 0xAE43, 0xAE43, 0xAF42, 0xAF42, 0xB041, 0xB041, 0xB140,
	0xB140, 0xB140, 0xB23F, 0xB23F, 0xB23F, 0xB23F, 0xB33E, 0xB33E, 0xB33E, 0xB33E, 0xB33E, 0xB33E, 0xB43D, 0xB43D,
	0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB43D, 0xB33E,
	0xB33E, 0xB33E, 0xB33E, 0xB33E, 0xB33E, 0xB23F, 0xB23F, 0xB23F, 0xB23F, 0xB140, 0xB140, 0xB140, 0xB041, 0xB041,
	0xAF42, 0xAF42, 0xAE43, 0xAE43, 0xAD44, 0xAD44, 0xAC45, 0xAC45, 0xAB46, 0xAA47, 0xAA47, 0xA948, 0xA948, 0xA849,
	0xA74A, 0xA64B, 0xA54C, 0xA54C, 0xA44D, 0xA24F, 0xA150, 0xA051, 0xA051, 0x9E53, 0x9D54, 0x9B56, 0x9A57, 0x9958,
	0x975A, 0x955C, 0x935E, 0x9160, 0x8F62, 0x8D64, 0x8A67, 0x866B, 0x8071]   # screen rows 24..136
const CORRIDOR_DIM2_Y0 := 24

var dg                                   # Dungeon
var dark_on := true                      # tests / cutscenes can switch the dimming off
var _dark: Node2D
var _lut_node: Node2D
var _lut_img: Image
var _lut_tex: ImageTexture
var _ramp := PackedInt32Array()          # current ramp: 256 x (r, g, b)
var _target := PackedInt32Array()
var _ramps: Image                        # colvec: 8 rows x 256
var _weather := ""
var _ramp_moving := false
var _ramp_acc := 0.0
var _efbg: Node2D
var _efbg_play: Dictionary = {}          # {w, sheet, frames, i, left, a08, a0c, fade}
var _efbg_acc := 0.0

func _ready() -> void:
	z_index = 40
	_dark = Node2D.new()
	_dark.draw.connect(_draw_dark)
	add_child(_dark)
	_lut_node = Node2D.new()
	_lut_node.z_index = 5
	_lut_node.z_as_relative = true
	_lut_node.draw.connect(_draw_view_rect.bind(_lut_node))
	add_child(_lut_node)
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D lut : filter_nearest;
void fragment() {
	vec3 s = texture(screen_tex, SCREEN_UV).rgb;
	float r = texture(lut, vec2((floor(s.r * 255.0 + 0.5) + 0.5) / 256.0, 0.5)).r;
	float g = texture(lut, vec2((floor(s.g * 255.0 + 0.5) + 0.5) / 256.0, 0.5)).g;
	float b = texture(lut, vec2((floor(s.b * 255.0 + 0.5) + 0.5) / 256.0, 0.5)).b;
	COLOR = vec4(r, g, b, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	_lut_node.material = mat
	_lut_img = Image.create(256, 1, false, Image.FORMAT_RGBA8)
	_ramp.resize(768)
	_target.resize(768)
	for i in 256:
		for c in 3:
			_ramp[i * 3 + c] = i
	_write_lut()
	_lut_tex = ImageTexture.create_from_image(_lut_img)
	mat.set_shader_parameter("lut", _lut_tex)
	var rt := DungeonGfx.tex("colvec.png")
	if rt:
		_ramps = rt.get_image()
		if _ramps.is_compressed():
			_ramps.decompress()
		_ramps.convert(Image.FORMAT_RGBA8)
	_efbg = Node2D.new()
	_efbg.z_index = 6
	_efbg.z_as_relative = true
	_efbg.draw.connect(_draw_efbg)
	var sh2 := Shader.new()
	sh2.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float bright = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a < 0.5) discard;
	vec3 s = texture(screen_tex, SCREEN_UV).rgb;
	COLOR = vec4(min(c.rgb * bright * 0.625 + s * 0.625, vec3(1.0)), 1.0);
}
"""
	var m2 := ShaderMaterial.new()
	m2.shader = sh2
	_efbg.material = m2
	add_child(_efbg)

## Called when a floor starts (after the banner): the ramp restarts from identity and fades to the weather's.
func floor_start() -> void:
	for i in 256:
		for c in 3:
			_ramp[i * 3 + c] = i
	_weather = ""
	_write_lut()
	if _lut_tex:
		_lut_tex.update(_lut_img)
	check_weather(true)

## Weather changed (or floor start): sub_807E698 - play the weather animation, then move the ramp.
func check_weather(force := false) -> void:
	if dg == null or dg.fs == null:
		return
	var w := str(dg.fs.weather)
	if w == _weather and not force:
		return
	_weather = w
	var wi := int(WEATHER_INDEX.get(w, 0))
	if _ramps:
		for i in 256:
			var c := _ramps.get_pixel(i, wi)
			_target[i * 3] = int(round(c.r * 255.0))
			_target[i * 3 + 1] = int(round(c.g * 255.0))
			_target[i * 3 + 2] = int(round(c.b * 255.0))
		_ramp_moving = true
	_start_efbg(wi)

func _start_efbg(wi: int) -> void:
	var e: Dictionary = DungeonGfx.data().get("weather", {}).get(str(wi), {})
	if e.is_empty():
		_efbg_play = {}
		_efbg.queue_redraw()
		return
	var tx := DungeonGfx.tex(str(e.sheet))
	if tx == null:
		return
	_efbg_play = {"tex": tx, "cols": int(e.cols), "frames": e.frames, "i": -1, "left": 0, "a08": 3100, "a0c": 0, "fade": false}
	_efbg_acc = 0.0
	_efbg_next()

## effect_main.c sub_800DE8C: show frame i for its duration; frames with fade/speed set the palette fade.
func _efbg_next() -> void:
	var p := _efbg_play
	p.i = int(p.i) + 1
	var frames: Array = p.frames
	if int(p.i) >= frames.size():
		_efbg_play = {}
		_efbg.queue_redraw()
		return
	var fr: Array = frames[int(p.i)]
	p.left = maxi(1, int(fr[0]))
	if int(fr[1]) != 0:
		p.fade = true
		p.a08 = 0
		p.a0c = 0
	var sp := int(fr[2])
	if sp != 0:
		if sp == 99:
			p.a08 = 3100
			p.a0c = 0
		elif sp > 0:
			p.a08 = 3100 / sp
			p.a0c = 3100 / sp
		else:
			p.a08 = 3100
			p.a0c = int(3100.0 / sp)
	var m: ShaderMaterial = _efbg.material
	var b := 1.0
	if p.fade:
		b = clampf((int(p.a08) / 100) / 32.0, 0.0, 1.0)
		p.a08 = clampi(int(p.a08) + int(p.a0c), 0, 3100)
	m.set_shader_parameter("bright", b)
	_efbg.queue_redraw()

func _process(dt: float) -> void:
	if dg == null or dg.fs == null:
		return
	check_weather()
	if _ramp_moving:
		_ramp_acc += dt * 60.0
		while _ramp_acc >= 1.0 and _ramp_moving:
			_ramp_acc -= 1.0
			_step_ramp()
	if not _efbg_play.is_empty():
		_efbg_acc += dt * 60.0
		while _efbg_acc >= 1.0 and not _efbg_play.is_empty():
			_efbg_acc -= 1.0
			_efbg_play.left = int(_efbg_play.left) - 1
			if int(_efbg_play.left) <= 0:
				_efbg_next()
		_efbg.queue_redraw()
	_dark.queue_redraw()
	_lut_node.queue_redraw()

func _step_ramp() -> void:
	var moving := false
	for i in 768:
		var c := _ramp[i]
		var t := _target[i]
		if absi(c - t) < 10:
			_ramp[i] = t
		else:
			moving = true
			_ramp[i] = c + (10 if c < t else -10)
	_ramp_moving = moving
	_write_lut()
	_lut_tex.update(_lut_img)

func _write_lut() -> void:
	for i in 256:
		_lut_img.set_pixel(i, 0, Color8(clampi(_ramp[i * 3], 0, 255), clampi(_ramp[i * 3 + 1], 0, 255), clampi(_ramp[i * 3 + 2], 0, 255)))

## World rectangle the camera shows.
func _view_rect() -> Rect2:
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var vs := vp.get_visible_rect().size
	var a: Vector2 = inv * Vector2.ZERO
	var b: Vector2 = inv * vs
	return Rect2(a, b - a).grow(4)

func _draw_view_rect(n: Node2D) -> void:
	n.draw_rect(_view_rect(), Color.WHITE)

## Red's screen origin for the leader: the camera puts the leader's pixel position (x*24+12, y*24+16) at
## screen (120, 96).
func _screen_origin() -> Vector2:
	var L: Mon = dg.fs.leader
	var p: Vector2i = L.pos if L else Vector2i.ZERO
	return Vector2(p.x * 24 + 12 - 120, p.y * 24 + 16 - 96)

func _draw_dark() -> void:
	if not dark_on or dg == null or dg.fs == null or dg.fs.leader == null:
		return
	var vis := int(dg.fs.visibility) & 3
	if vis == 0 or bool(dg.fs.get_meta("all_revealed", false)):
		return
	var vr := _view_rect()
	var o := _screen_origin()
	var L: Mon = dg.fs.leader
	var r: int = dg.fs.room_at(L.pos)
	var y0 := floorf(vr.position.y)
	var y1 := ceilf(vr.end.y)
	if r == 255 or r >= dg.fs.rooms.size():
		var tbl: Array = CORRIDOR_DIM2 if vis == 2 else CORRIDOR_DIM1
		var t0: int = CORRIDOR_DIM2_Y0 if vis == 2 else CORRIDOR_DIM1_Y0
		var top := o.y + t0
		var bot := top + tbl.size()
		if y0 < top:
			_rect(Rect2(vr.position.x, y0, vr.size.x, top - y0), DIM)
		if bot < y1:
			_rect(Rect2(vr.position.x, bot, vr.size.x, y1 - bot), DIM)
		for i in tbl.size():
			var v: int = tbl[i]
			_dim_row(vr, top + i, o.x + float(v & 0xFF), o.x + float(v >> 8))
		return
	# in a room: dim outside the room (one tile of wall included), rounded corners
	var rc: Rect2i = dg.fs.rooms[r]
	var X0 := float((rc.position.x - 1) * 24)
	var Y0 := float((rc.position.y - 1) * 24)
	var X1 := float((rc.end.x + 1) * 24)
	var Y1 := float((rc.end.y + 1) * 24)
	if y0 < Y0:
		_rect(Rect2(vr.position.x, y0, vr.size.x, Y0 - y0), DIM)
	if Y1 < y1:
		_rect(Rect2(vr.position.x, Y1, vr.size.x, y1 - Y1), DIM)
	var yy := maxf(Y0, y0)
	while yy < minf(Y1, y1):
		var k := int(yy - Y0)
		var kb := int(Y1 - yy)
		var cut := 0
		if k < 16:
			cut = ROOM_CORNER[k]
		elif kb < 16:
			cut = ROOM_CORNER[kb]
		if cut == 0:
			# plain rows: one rectangle on each side for the whole run
			var run_end := minf(minf(Y1, y1), Y1 - 15.0)
			if run_end <= yy:
				run_end = yy + 1.0
			_rect(Rect2(vr.position.x, yy, X0 - vr.position.x, run_end - yy), DIM)
			_rect(Rect2(X1, yy, vr.end.x - X1, run_end - yy), DIM)
			yy = run_end
			continue
		_dim_row(vr, yy, X0 + cut, X1 - cut)
		yy += 1.0

func _rect(r: Rect2, c: Color) -> void:
	if r.size.x > 0.0 and r.size.y > 0.0:
		_dark.draw_rect(r, c)

## Dim one pixel row except [lit_l, lit_r).
func _dim_row(vr: Rect2, y: float, lit_l: float, lit_r: float) -> void:
	if lit_r <= lit_l:
		_rect(Rect2(vr.position.x, y, vr.size.x, 1), DIM)
		return
	if lit_l > vr.position.x:
		_rect(Rect2(vr.position.x, y, lit_l - vr.position.x, 1), DIM)
	if lit_r < vr.end.x:
		_rect(Rect2(lit_r, y, vr.end.x - lit_r, 1), DIM)

func _draw_efbg() -> void:
	if _efbg_play.is_empty():
		return
	var p := _efbg_play
	var i := int(p.i)
	var cols := int(p.cols)
	var src := Rect2((i % cols) * 240, (i / cols) * 160, 240, 160)
	var vr := _view_rect()
	# the effect sits on a screen BG layer: tile it across the view, anchored to Red's screen origin
	var o := _screen_origin()
	var sx := o.x + floorf((vr.position.x - o.x) / 240.0) * 240.0
	var sy := o.y + floorf((vr.position.y - o.y) / 160.0) * 160.0
	var y := sy
	while y < vr.end.y:
		var x := sx
		while x < vr.end.x:
			_efbg.draw_texture_rect_region(p.tex, Rect2(x, y, 240, 160), src)
			x += 240.0
		y += 160.0
