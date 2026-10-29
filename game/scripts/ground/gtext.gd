class_name GText
extends Control
## The ground scripts' textbox (textbox.c): typed messages with speaker names and portraits, messages on a
## black background, choice menus, and "special text" (shops, naming, dungeon list...) handed to the game.
## The script engine polls it: is_open() for lock 0, result() -> [done, value] for menus / special text.

enum { T_INSTANT, T_QUIET, T_NPC, T_LETTER, T_OVERHEARD }
const COLORS := {"YELLOW_D": "#ffdc4a", "YELLOW": "#ffdc4a", "YELLOW_N": "#ffdc4a", "YELLOW_C": "#ffdc4a",
	"CYAN": "#7fe0ff", "CYAN_M": "#7fe0ff", "GREEN_I": "#7fff7f", "GREEN": "#7fff7f", "GREEN_H": "#7fff7f",
	"RED_W": "#ff8070", "RED": "#ff8070"}
const PLACE_X := [2, 12, 2, 23, 7, 18, 13, 2, 23, 7, 18, 12, 2, 23, 7, 18, 13, 2, 23, 7, 18]
const PLACE_Y := [8, 5, 8, 8, 8, 8, 5, 8, 8, 8, 8, 1, 2, 2, 1, 1, 1, 2, 2, 1, 1]
const PLACE_FLIP := [false, false, false, true, false, true, true, true, false, true, false, false, false, true, false, true, true, true, false, true, false]

var G
var panel: PanelContainer
var label: RichTextLabel
var bg_label: RichTextLabel
var bg_dim: ColorRect
var port_frame: PanelContainer
var port_tex: TextureRect

var portraits: Array = []       # slot -> {kind, species, show, sprite, place, delta, name, mon}
var names: Array = []           # gFormatBuffer_Names
var mons: Array = []            # gFormatBuffer_Monsters
var format_args: Array = []     # gFormatArgs ({VALUE_n})
var items: Array = ["", ""]     # gFormatBuffer_Items ({MOVE_ITEM_n})
var friend_area_name := ""
var name_buffer := ""

var _pages: Array = []
var _page := 0
var _typing := false
var _chars := 0.0
var _open := false              # waiting for the player to read (lock 0 holds)
static var spam := 0            # test (--spam): presses per frame, like hammering the screen
var _instant := false
var _auto_end := -1
var _auto_mid := -1
var _auto_t := 0
var _on_bg := false
var _bg_auto := false
var _bg_auto_t := 0
var _overheard_t := 0

var _menu: ListMenu
var _done := true
var _value := -1
var _busy_special := false
var auto := false                # tests: advance by itself

func _init(ground) -> void:
	G = ground

func _ready() -> void:
	theme = UITheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_dim = ColorRect.new()
	bg_dim.color = Color(0, 0, 0, 0)
	bg_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_dim)
	bg_label = RichTextLabel.new()
	bg_label.bbcode_enabled = true
	bg_label.scroll_active = false
	bg_label.fit_content = true
	bg_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bg_label.offset_left = -220
	bg_label.offset_right = 220
	bg_label.offset_top = -50
	bg_label.offset_bottom = 50
	bg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_label.visible = false
	add_child(bg_label)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 4 * UITheme.PX
	panel.offset_right = -4 * UITheme.PX
	panel.offset_top = -(3 * UITheme.LINE + 10 * UITheme.PX)
	panel.offset_bottom = -2 * UITheme.PX
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_panel_input)
	panel.visible = false
	add_child(panel)
	label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	port_frame = PanelContainer.new()
	var sb := UITheme.box()
	sb.content_margin_left = UITheme.PX
	sb.content_margin_right = UITheme.PX
	sb.content_margin_top = UITheme.PX
	sb.content_margin_bottom = UITheme.PX
	port_frame.add_theme_stylebox_override("panel", sb)
	port_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port_frame.visible = false
	add_child(port_frame)
	port_tex = TextureRect.new()
	port_tex.custom_minimum_size = Vector2(40, 40) * UITheme.PX
	port_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	port_tex.stretch_mode = TextureRect.STRETCH_SCALE
	port_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	port_frame.add_child(port_tex)
	reset_all()

func reset_all() -> void:
	portraits.clear()
	names.clear()
	mons.clear()
	format_args.clear()
	for i in 10:
		portraits.append({"kind": -1, "species": "", "show": false, "sprite": -1, "place": 0, "delta": Vector2i.ZERO})
		names.append("")
		mons.append("")
		format_args.append(0)
	_auto_end = -1
	_auto_mid = -1
	clear()

# ------------------------------------------------------------------ portraits / names (0x2D, 0x2E, 0x2F)
func reset_portrait(slot: int) -> void:
	portraits[slot] = {"kind": -1, "species": "", "show": false, "sprite": -1, "place": 0, "delta": Vector2i.ZERO}

func portrait_from_kind(slot: int, kind: int, mode: int) -> void:
	var sp: String = G.species_of_kind(kind)
	var show := sp != ""
	var por_sp := sp + ("*" if show and G.shiny_of_resolved(int(G.resolve_kind(kind)[0])) else "")
	portraits[slot] = {"kind": kind, "species": por_sp, "show": show, "sprite": -1, "place": 0, "delta": Vector2i.ZERO}
	var spname: String = DB.species.get(sp, {}).get("name", "???") if sp != "" else "???"
	mons[slot] = "[color=#7fe0ff]%s[/color]" % spname
	match mode:
		0:
			names[slot] = ""
		1:
			names[slot] = mons[slot]
		2:
			names[slot] = G.lives_name_by_kind(kind)

func set_portrait(slot: int, sprite_id: int, place: int) -> void:
	var p: Dictionary = portraits[slot]
	if p.species == "" or sprite_id == -1:
		p.sprite = -1
		return
	if place != 21:
		p.place = place
		p.delta = Vector2i.ZERO
	p.sprite = sprite_id

func set_portrait_delta(slot: int, d: Vector2i) -> void:
	portraits[slot].delta = d

# ------------------------------------------------------------------ text formatting
func format(s) -> String:
	var t := str(s) if s != null else ""
	t = t.replace("[", "(").replace("]", ")")
	var re := RegEx.new()
	re.compile("\\{([A-Z_]+)(?: (\\w+))?(?:_(\\d+))?\\}")
	var out := ""
	var last := 0
	for m in re.search_all(t):
		out += t.substr(last, m.get_start() - last)
		last = m.get_end()
		var tag := m.get_string(0)
		out += _tag(tag)
	out += t.substr(last)
	return out

func _tag(tag: String) -> String:
	var inner := tag.substr(1, tag.length() - 2)
	if inner.begins_with("COLOR "):
		return "[color=%s]" % COLORS.get(inner.substr(6), "#ffffff")
	if inner == "RESET":
		return "[/color]"
	if inner == "CENTER_ALIGN":
		return "\u0001"
	if inner == "WAIT_PRESS":
		return "\u0002"
	if inner == "TEAM_NAME":
		return "[color=#ffdc4a]%s[/color]" % str(Game.story_get("team_name", "Team"))
	if inner == "SPEECH_BUBBLE":
		return UITheme.glyph(inner)
	if inner == "FRIEND_AREA":
		return "[color=#7fff7f]%s[/color]" % friend_area_name
	var n := inner.rfind("_")
	if n > 0:
		var head := inner.substr(0, n)
		var idx := int(inner.substr(n + 1))
		match head:
			"NAME":
				return names[idx] if idx < names.size() else ""
			"POKEMON":
				return mons[idx] if idx < mons.size() else ""
			"VALUE":
				return str(format_args[idx]) if idx < format_args.size() else "0"
			"MOVE_ITEM":
				return "[color=#7fff7f]%s[/color]" % (items[idx] if idx < items.size() else "")
	return UITheme.glyph(inner)      # Red's icon characters ({POKE}, {A_BUTTON} ...), "" for anything else

## Split into pages at {WAIT_PRESS} and \n\n-ish breaks (Red shows 3 lines per box).
func _paginate(t: String) -> Array:
	var pages: Array = []
	for part in t.split("\u0002"):
		var lines: Array = part.split("\n")
		while lines.size() > 0 and lines[0] == "" and pages.size() > 0:
			lines.pop_front()
		var chunk: Array = []
		for l in lines:
			chunk.append(l)
			if chunk.size() == 3:
				pages.append(chunk)
				chunk = []
		if chunk.size() > 0:
			pages.append(chunk)
	var out: Array = []
	for p in pages:
		var ls: Array = []
		for l in p:
			var s: String = l
			if s.begins_with("\u0001") or s.find("\u0001") >= 0:
				s = "[center]" + s.replace("\u0001", "") + "[/center]"
			ls.append(s)
		out.append("\n".join(ls))
	return out

# ------------------------------------------------------------------ messages
func say(ttype: int, speaker: int, text) -> bool:
	if auto and text != null and str(text) != "":
		print("  SAY[%d] %s" % [speaker, str(text).replace("\n", " ").left(70)])
	if text == null:
		clear()
		return false
	if str(text) == "":
		clear2()
		return false
	_on_bg = false
	bg_label.visible = false
	var body := format(text)
	if ttype == T_NPC:
		var nm := ""
		if speaker >= 0 and speaker < names.size():
			nm = names[speaker]
		if nm != "":
			body = "[color=#ffdc4a]%s[/color]:%s" % [_strip_bb(nm), body]
	_pages = _paginate(body)
	_page = 0
	_instant = ttype == T_INSTANT
	_overheard_t = 90 if ttype == T_OVERHEARD else 0
	_show_portrait(speaker)
	_start_page()
	return true

func _strip_bb(s: String) -> String:
	var r := RegEx.new()
	r.compile("\\[/?color[^\\]]*\\]")
	return r.sub(s, "", true)

func say_on_bg(text, auto_close: bool) -> bool:
	if text == null or str(text) == "":
		clear()
		return false
	_on_bg = true
	_bg_auto = auto_close
	_bg_auto_t = 0
	panel.visible = false
	port_frame.visible = false
	_pages = _paginate(format(text))
	_page = 0
	_instant = auto_close
	_start_page()
	return true

func _start_page() -> void:
	var txt: String = _pages[_page] if _page < _pages.size() else ""
	var lbl := bg_label if _on_bg else label
	if _on_bg:
		bg_label.visible = true
		bg_label.text = "[center]" + txt.replace("[center]", "").replace("[/center]", "") + "[/center]"
	else:
		panel.visible = true
		label.text = txt
	_open = true
	_auto_t = 0
	if _instant:
		lbl.visible_characters = -1
		_typing = false
	else:
		lbl.visible_characters = 0
		_chars = 0.0
		_typing = true

func _show_portrait(speaker: int) -> void:
	port_frame.visible = false
	if speaker < 0 or speaker >= portraits.size():
		return
	var p: Dictionary = portraits[speaker]
	if p.species == "" or not p.show:
		return
	if int(p.sprite) == -2:
		return
	var spr := maxi(int(p.sprite), 0)
	var place := int(p.place) if int(p.sprite) >= 0 else 0
	var tex: Texture2D = G.portrait_tex(p.species, spr)
	if tex == null:
		return
	port_tex.texture = tex
	port_tex.flip_h = PLACE_FLIP[place]
	var x := portrait_x(place, int(p.delta.x), size.x if size.x > 0 else get_viewport_rect().size.x)
	var y := int((PLACE_Y[place] * 8 + int(p.delta.y)) * 1.55)
	port_frame.position = Vector2(x - UITheme.PX, y)
	port_frame.visible = true

## Red places portraits on its 240 px screen (PLACE_X tiles + the scene's delta). On a wider screen each
## keeps its side: left places (x 2, 7) stay put, right places (18, 23) keep their distance from the right
## edge, centre places (12, 13) stay centred.
const GBA_W := 240

static func portrait_x(place: int, dx: int, screen_w: float) -> float:
	var gx: int = int(PLACE_X[place]) * 8 + dx
	var px := float(gx * UITheme.PX)
	var t := int(PLACE_X[place])
	if t >= 18:
		return screen_w - float((GBA_W - gx) * UITheme.PX)
	if t == 12 or t == 13:
		return screen_w / 2.0 - float((GBA_W / 2 - gx) * UITheme.PX)
	return px

func is_open() -> bool:
	return _open

func clear() -> void:
	_open = false
	_typing = false
	_pages = []
	if panel:
		panel.visible = false
		port_frame.visible = false
		bg_label.visible = false
	_on_bg = false

func clear2() -> void:
	clear()

func set_auto_press(end_frames: int, mid_frames: int) -> void:
	_auto_end = end_frames
	_auto_mid = mid_frames

func window_flags_set(_f: int) -> void:
	pass

func window_flags_clear(_f: int) -> void:
	pass

func press() -> void:
	if not _open:
		return
	var lbl := bg_label if _on_bg else label
	if _typing:
		_typing = false
		lbl.visible_characters = -1
		return
	if _page + 1 < _pages.size():
		_page += 1
		Audio.sfx("text")
		_start_page()
		return
	_open = false
	if _on_bg and _bg_auto:
		bg_label.visible = false
	G.lock_jump_zero(0)

## Called once per game frame by the ground loop.
func tick() -> void:
	for _k in spam:
		if _menu == null:
			press()
	if _open:
		var lbl := bg_label if _on_bg else label
		if _typing:
			_chars += [0.5, 1.0, 4.0][clampi(int(Game.settings.get("msg_speed", 1)), 0, 2)]
			lbl.visible_characters = int(_chars)
			if lbl.visible_characters >= lbl.get_total_character_count():
				_typing = false
				lbl.visible_characters = -1
		else:
			_auto_t += 1
			var last := _page + 1 >= _pages.size()
			if _on_bg and _bg_auto and _auto_t >= 32:
				press()
			elif _overheard_t > 0 and _auto_t >= _overheard_t:
				press()
			elif _auto_end >= 0 and last and _auto_t >= _auto_end:
				press()
			elif _auto_mid >= 0 and not last and _auto_t >= _auto_mid:
				press()
			elif auto and _auto_t >= 6:
				press()

func handle_input(e: InputEvent) -> bool:
	if _menu != null:
		return false
	if not _open:
		return false
	if e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack") or e.is_action_pressed("ui_cancel") \
			or (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		_tap_press()
		return true
	if (e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed:
		return true         # the release of a tap that pressed the text isn't a tap on the map
	return false

func _panel_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_tap_press()
		accept_event()

var _press_frame := -1

## One tap arrives as a touch AND an emulated mouse click (or a click plus an emulated touch on
## desktop) in the same frame: count it once, or a single tap would finish the text and close it.
func _tap_press() -> void:
	if Engine.get_process_frames() == _press_frame:
		return
	_press_frame = Engine.get_process_frames()
	press()

# ------------------------------------------------------------------ menus
func ask(choices: Array, cancel_val: int, _flag: bool, ttype: int, speaker: int, text: String) -> void:
	if text != "":
		say(ttype, speaker, text)
		_typing = false
		label.visible_characters = -1
	_done = false
	_value = cancel_val
	var opts: Array = []
	for c in choices:
		opts.append(_strip_bb(format(c)))
	_open_menu(opts, cancel_val, true)

func ask_yes_no(_flag: bool, _a1: int, speaker: int, text) -> void:
	ask(["Yes", "No"], 2, false, T_NPC if speaker >= 0 else T_INSTANT, speaker, str(text) if text != null else "")

func _open_menu(opts: Array, cancel_val: int, can_cancel: bool) -> void:
	_menu = ListMenu.make("", opts, can_cancel)
	_menu.remember = false
	add_child(_menu)
	await get_tree().process_frame
	if _menu == null or not is_instance_valid(_menu):
		return
	var vs := get_viewport_rect().size
	_menu.position = Vector2(vs.x - _menu.size.x - 8, (panel.position.y if panel.visible else vs.y) - _menu.size.y - 4)
	var i: int = await _menu.choose()
	_menu = null
	_value = (i + 1) if i >= 0 else cancel_val
	_done = true
	_open = false
	G.lock(1, _value)

func result() -> Array:
	return [_done, _value]

# ------------------------------------------------------------------ special text (shops, naming, lists...)
func special(kind: int, a1: int, a2: int, s) -> bool:
	_done = false
	_value = -1
	_run_special(kind, a1, a2, s)
	return true

func _run_special(kind: int, a1: int, a2: int, s) -> void:
	await get_tree().process_frame
	var v: int = await G.special_text(kind, a1, a2, s)
	_value = v
	_done = true
	G.lock(1, v)
