class_name Hud
extends Control
## Dungeon HUD: Red's top status line, the message box, and on-screen controls for touch.

signal button(name: String)

var top_draw: Control
var _hudfont: Texture2D
var _floor_txt := ""
var _lv := 1
var _hp := 1
var _maxhp := 1
var _belly := 100
var msg_panel: PanelContainer
var msg_text: RichTextLabel
var lines: Array = []
var _msg_t := 0.0
var pad: Control
var pad_dir := -1
var pad_run := false               # touch: the finger pushed past the pad's ring = run (Red's B)
var _pad_touch := -1
var _btns: Dictionary = {}
var touch_ui := false
var touch_device := false
var log_all: Array = []
var msg_count := 0                 # messages shown so far (run mode stops on new ones)
var low_hp := false                # leader at <= 1/4 HP: the HP bar blinks (QoL option)
var _blink_t := 0.0

func _ready() -> void:
	theme = UITheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_draw = Control.new()
	top_draw.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_draw.custom_minimum_size = Vector2(0, 40)
	top_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_draw.draw.connect(_draw_top)
	add_child(top_draw)
	_hudfont = load("res://assets/ui/hudfont.png")
	msg_panel = PanelContainer.new()
	msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	msg_panel.offset_left = 4 * UITheme.PX
	msg_panel.offset_right = -4 * UITheme.PX
	msg_panel.offset_top = -(2 * UITheme.LINE + 10 * UITheme.PX)
	msg_panel.offset_bottom = -2 * UITheme.PX
	add_child(msg_panel)
	msg_text = RichTextLabel.new()
	msg_text.bbcode_enabled = true
	msg_text.scroll_active = false
	msg_text.fit_content = false
	msg_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_text.add_theme_constant_override("line_separation", 0)
	msg_panel.add_child(msg_text)
	msg_panel.visible = false
	touch_device = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	touch_ui = touch_device and Input.get_connected_joypads().is_empty()
	_build_touch()
	# a controller plugged in hides the on-screen buttons; unplugging it brings them back
	Input.joy_connection_changed.connect(func(_dev, _connected):
		var want := touch_device and Input.get_connected_joypads().is_empty()
		if want != touch_ui:
			touch_ui = want
			set_touch_visible(want))

func set_status(floor_txt: String, m: Mon, belly: int) -> void:
	if m == null:
		return
	_floor_txt = floor_txt
	_lv = m.level
	_hp = m.hp
	_maxhp = m.max_hp
	_belly = belly
	top_draw.queue_redraw()

const P := UITheme.PX
const BAR_MAX := 200         # full width at 200 max HP (Red stops at 96; raised so it keeps growing)
func _glyph(i: int, x: float, y: float, w := 8) -> float:
	top_draw.draw_texture_rect_region(_hudfont, Rect2(x, y, w * P, 8 * P), Rect2(i * 8, 0, w, 8))
	return x + w * P

func _num(n: int, x: float, y: float) -> float:
	for c in str(n):
		var d := int(c)
		x = _glyph(16 if d == 9 else 7 + d, x, y) - P
	return x + P

## Red's dungeon HUD: "B1F  Lv5  HP 30/30" in Red's HUD lettering, then the HP bar to the right edge.
func _draw_top() -> void:
	if _hudfont == null:
		return
	var y := float(P)
	var x := 2.0 * P
	var fl := _floor_txt
	var up := not fl.begins_with("B")
	if not up:
		x = _glyph(6, x, y) - P
	x = _num(int(fl.replace("B", "").replace("F", "")), x, y)
	x = _glyph(0, x, y) + 5 * P
	x = _glyph(1, x, y)
	x = _glyph(2, x, y, 4) + P
	x = _num(_lv, x, y) + 5 * P
	x = _glyph(3, x, y)
	x = _glyph(4, x, y) - P
	x = _num(maxi(0, _hp), x, y)
	x = _glyph(5, x - P, y) - P
	x = _num(_maxhp, x, y) + 2 * P
	# Like Red (dungeon_tilemap.c sub_803FA4C) the bar's length follows the max HP, so it grows as the leader
	# levels up; Red caps it at 96 max HP, here it reaches the full width at BAR_MAX.
	var room := minf(get_viewport_rect().size.x, 360.0 * P) - x - 2 * P
	var bw: float = maxf(2.0, round(room * float(clampi(_maxhp, 1, BAR_MAX)) / BAR_MAX / P)) * P   # BAR_MAX+ max HP reaches the edge
	if bw >= 2 * P:
		var by := y + P
		var fw: float = round(bw * clampf(float(_hp) / maxf(1, _maxhp), 0, 1) / P) * P
		top_draw.draw_rect(Rect2(x, by, bw, 6 * P), Color.BLACK)
		top_draw.draw_rect(Rect2(x, by + P, bw, 3 * P), Color("7a2a22"))
		if not (low_hp and fmod(_blink_t, 0.5) >= 0.25):
			top_draw.draw_rect(Rect2(x, by + P, fw, 3 * P), Color("2cff34") if not low_hp else Color("ffd030"))
		top_draw.draw_rect(Rect2(x, by + 5 * P, bw, P), Color.WHITE)
	if _belly < 20:   # Red only shows the Belly when it's getting low
		var f := UITheme.font()
		var lab := "Belly"
		var col := Color("ff5a4a") if _belly < 1 else Color("ff875f")
		var bx := 2.0 * P
		var byy := y + 10 * P + UITheme.FONT_SIZE * 0.8
		top_draw.draw_string(f, Vector2(bx + P, byy + P), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE, UITheme.SHADOW)
		top_draw.draw_string(f, Vector2(bx, byy), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE, col)
		_num(maxi(0, _belly), bx + f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE).x + 3 * P, y + 10 * P)

func set_low_hp(on: bool) -> void:
	if on != low_hp:
		low_hp = on
		_blink_t = 0.0
		top_draw.queue_redraw()

func msg(t: String) -> void:
	msg_count += 1
	lines.append(t)
	log_all.append(t)
	if log_all.size() > 80:
		log_all.pop_front()
	while lines.size() > 2:
		lines.pop_front()
	msg_text.text = "\n".join(lines)
	msg_panel.visible = true
	_msg_t = 3.5

func clear_msgs() -> void:
	lines.clear()
	msg_panel.visible = false

func _process(dt: float) -> void:
	if low_hp:
		var was := fmod(_blink_t, 0.5) >= 0.25
		_blink_t += dt
		if was != (fmod(_blink_t, 0.5) >= 0.25):
			top_draw.queue_redraw()
	if _msg_t > 0:
		_msg_t -= dt
		if _msg_t <= 0:
			lines.clear()
			msg_panel.visible = false

# ------------------------------------------------------------- touch controls
func _build_touch() -> void:
	pad = Control.new()
	pad.custom_minimum_size = Vector2(84, 84)
	pad.size = Vector2(84, 84)
	pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pad.position = Vector2(8, 270 - 92)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.draw.connect(_draw_pad)
	add_child(pad)
	var specs := [["A", "attack"], ["Moves", "moves"], ["Bag", "bag"], ["Menu", "menu"], ["Wait", "wait"], ["Map", "map"], ["Auto", "auto"]]
	for sp in specs:
		var b := Button.new()
		b.text = sp[0]
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.custom_minimum_size = Vector2(72, 44) if sp[1] == "attack" else Vector2(72, 28)
		b.add_theme_font_size_override("font_size", UITheme.FONT_SIZE)
		for st in ["normal", "hover", "pressed"]:
			var sb: StyleBoxFlat = UITheme.box(0.82 if st == "normal" else 0.95).duplicate()
			sb.content_margin_left = 2
			sb.content_margin_right = 2
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			b.add_theme_stylebox_override(st, sb)
		b.size = b.custom_minimum_size
		b.modulate = Color(1, 1, 1, 0.8)
		var key: String = sp[1]
		b.pressed.connect(func(): button.emit(key))
		add_child(b)
		_btns[key] = b
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	set_touch_visible(touch_ui)

const BTN_POS := {   # top-left offsets from the bottom-right corner
	"attack": Vector2(-76, -50), "bag": Vector2(-76, -82), "map": Vector2(-76, -114),
	"moves": Vector2(-152, -32), "menu": Vector2(-152, -64), "auto": Vector2(-152, -96), "wait": Vector2(-228, -32)}

func _relayout() -> void:
	var vs := get_viewport_rect().size
	pad.position = Vector2(8, vs.y - 92)
	for k in _btns:
		_btns[k].position = vs + BTN_POS[k]

func set_auto(on: bool) -> void:
	if _btns.has("auto"):
		_btns["auto"].text = "Auto"
		_btns["auto"].modulate = Color(0.6, 1, 0.6, 0.95) if on else Color(1, 1, 1, 0.8)

func set_touch_visible(v: bool) -> void:
	pad.visible = v
	for k in _btns:
		_btns[k].visible = v
	msg_panel.offset_left = 100 if v else 4 * UITheme.PX
	msg_panel.offset_right = -236 if v else -4 * UITheme.PX

func _draw_pad() -> void:
	var c := pad.size / 2
	pad.draw_circle(c, 40, Color(0.05, 0.1, 0.3, 0.45))
	pad.draw_arc(c, 40, 0, TAU, 32, Color(1, 0.86, 0.3, 0.95) if pad_run else Color(0.7, 0.8, 1, 0.6), 2.0 if pad_run else 1.0)
	for d in 8:
		var v: Vector2 = Vector2(DB.DIRS[d]).normalized()
		var col := Color(1, 0.86, 0.3, 0.95) if d == pad_dir else Color(0.8, 0.88, 1, 0.55)
		pad.draw_circle(c + v * 27, 6 if d % 2 == 0 else 4, col)

func _input(e: InputEvent) -> void:
	if not pad.visible:
		return
	var p := Vector2.ZERO
	var idx := -1
	var pressed := false
	var is_ev := false
	if e is InputEventScreenTouch:
		p = e.position; idx = e.index; pressed = e.pressed; is_ev = true
	elif e is InputEventScreenDrag:
		p = e.position; idx = e.index; pressed = true; is_ev = true
	if not is_ev:
		return
	var local := get_global_transform_with_canvas().affine_inverse() * p
	var c := pad.position + pad.size / 2
	var dist := local.distance_to(c)
	if pressed and (dist < 52 or idx == _pad_touch):
		if _pad_touch == -1 and not (e is InputEventScreenTouch) and idx != _pad_touch:
			return
		_pad_touch = idx
		var v := local - c
		pad_run = v.length() > 46
		if v.length() < 8:
			pad_dir = -1
		else:
			var a := atan2(v.y, v.x)   # 0 = right
			var octant := int(round(a / (PI / 4))) % 8   # 0 right,1 down-right,2 down,...
			octant = (octant + 8) % 8
			var map := [2, 1, 0, 7, 6, 5, 4, 3]   # screen octant -> Red direction index
			pad_dir = map[octant]
		pad.queue_redraw()
		get_viewport().set_input_as_handled()
	elif not pressed and idx == _pad_touch:
		_pad_touch = -1
		pad_dir = -1
		pad_run = false
		pad.queue_redraw()
