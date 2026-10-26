class_name RedText
extends RefCounted
## Red's own text for the town services, taken from the decomp (src/data/locale/*_usa.h and the menu
## data headers, extracted into data/red_town_text.json). Icon tags ({POKE}, {ICON_GO}, envelopes, buttons)
## use the ROM glyph sheet through UITheme.glyph().
##
##   RedText.get_text("KEC_ITEMS_AWAKE_DLG_00")                    # raw Red string
##   var pages := RedText.fmt(raw, {"mon6": "Kecleon", "item0": "Apple", "value0": 50})
##   await RedText.say(root, "FEL_AWAKE_WELCOME", "Felicity", "0053", vars)     # speaker name + portrait
##   var i := await RedText.ask(root, "KEC_ITEMS_AWAKE_DLG_05", "Kecleon", "0352", ["Yes", "No"], vars)

const PATH := "res://data/red_town_text.json"
const COLORS := {"YELLOW": "#ffdc4a", "CYAN": "#7fe0ff", "GREEN": "#7fff7f", "RED": "#ff8070", "DEFAULT": "#ffffff", "WHITE": "#ffffff"}
const BUTTONS := {"A_BUTTON": "A", "B_BUTTON": "B", "L_BUTTON": "L", "R_BUTTON": "R", "START_BUTTON": "START", "SELECT_BUTTON": "SELECT", "DPAD": "+Control Pad"}
## characters pmd_red_text.ttf only has as private-use glyphs
const FONT_MAP := {"〜": "\uE0EF", "♪": "\uE10F", "♂": "\uE101", "♀": "\uE102", "×": "\uE0FC", "→": "\uE10B"}

static var _data: Dictionary = {}
static var _tex: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_data = v
	return _data

static func get_text(key: String) -> String:
	return str(data().get(key, ""))

static func has(key: String) -> bool:
	return data().has(key)

## Inline BBCode for one of Red's glyphs by charmap name ("POKE", "ICON_GO", "A_BUTTON" ...): agent front's
## ROM glyph sheet (UITheme.glyph).
static func glyph_bb(name: String) -> String:
	return UITheme.glyph(name)

## A glyph as a texture at the UI scale (for menu row icons).
static func glyph_tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var meta := UITheme._glyph_meta()
	var src: Texture2D = load("res://assets/ui/front/glyphs.png")
	if src == null or not meta.has(name):
		return null
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	var g: Array = meta[name]
	var im := img.get_region(Rect2i(int(g[0]), 0, int(g[1]), mini(12, img.get_height())))
	im.resize(im.get_width() * UITheme.PX, im.get_height() * UITheme.PX, Image.INTERPOLATE_NEAREST)
	var t := ImageTexture.create_from_image(im)
	_tex[name] = t
	return t

static func poke() -> String:
	var g := UITheme.glyph("POKE")
	return g if g != "" else "Poké"

## Red markup -> BBCode pages ({EXTRA_MSG} starts a new box). vars: mon0..mon9, item0/item1, value0..,
## friend_area, team, name0... ("%d" / "%s" printf slots are filled from vars.args in order).
static func fmt(s: String, vars: Dictionary = {}) -> Array:
	var args: Array = vars.get("args", [])
	if not args.is_empty():
		var out_s := ""
		var ai := 0
		var k := 0
		while k < s.length():
			if s[k] == "%" and k + 1 < s.length() and s[k + 1] in ["d", "s"]:
				out_s += str(args[ai]) if ai < args.size() else ""
				ai += 1
				k += 2
				continue
			out_s += s[k]
			k += 1
		s = out_s
	s = s.replace("[", "(").replace("]", ")")
	for ch in FONT_MAP:
		s = s.replace(ch, FONT_MAP[ch])
	var re := RegEx.new()
	re.compile("\\{([^}]*)\\}")
	var out := ""
	var last := 0
	for m in re.search_all(s):
		out += s.substr(last, m.get_start() - last)
		last = m.get_end()
		out += _tag(m.get_string(1), vars)
	out += s.substr(last)
	var pages: Array = []
	for p in out.split("\u0003"):
		var lines: Array = []
		for l in p.split("\n"):
			if l.find("\u0001") >= 0:
				l = "[center]" + l.replace("\u0001", "") + "[/center]"
			lines.append(l)
		var t := "\n".join(lines)
		if t.strip_edges() != "":
			pages.append(t)
	return pages

static func _tag(inner: String, vars: Dictionary) -> String:
	var up := inner.to_upper()
	if up.begins_with("COLOR "):
		var c := up.substr(6)
		if c.begins_with("CENTER_ALIGN "):
			c = c.substr(13)
		for k in COLORS:
			if c.begins_with(k):
				return "[color=%s]" % COLORS[k]
		return "[color=#ffffff]"
	if up.begins_with("CENTER_ALIGN COLOR "):
		var c2 := up.substr(19)
		for k in COLORS:
			if c2.begins_with(k):
				return "\u0001[color=%s]" % COLORS[k]
		return "\u0001[color=#ffffff]"
	match up:
		"RESET":
			return "[/color]"
		"CENTER_ALIGN":
			return "\u0001"
		"EXTRA_MSG":
			return "\u0003"
		"WAIT_PRESS", "SPEECH_BUBBLE":
			return ""
		"POKE":
			return poke()
		"FRIEND_AREA":
			return str(vars.get("friend_area", ""))
		"TEAM_NAME":
			return "[color=#ffdc4a]%s[/color]" % str(vars.get("team", Game.team_name))
	var g := UITheme.glyph(up)
	if g != "":
		return g
	if BUTTONS.has(up):
		return str(BUTTONS[up])
	if up.begins_with("MOVE_X_POSITION_BY_"):
		return "\t"
	var n := up.rfind("_")
	if n > 0:
		var head := up.substr(0, n)
		var idx := up.substr(n + 1)
		match head:
			"POKEMON":
				return str(vars.get("mon" + idx, ""))
			"MOVE_ITEM":
				return str(vars.get("item" + idx, ""))
			"VALUE":
				return str(vars.get("value" + idx, "0"))
			"NAME":
				return str(vars.get("name" + idx, ""))
	return ""

## One plain line of Red text (menus, headers): no pages, no centring.
static func line(key_or_text: String, vars: Dictionary = {}) -> String:
	var raw := get_text(key_or_text) if has(key_or_text) else key_or_text
	var p := fmt(raw, vars)
	return str(p[0]).replace("[center]", "").replace("[/center]", "") if p.size() > 0 else ""

static func _speaker_prefix(speaker_name: String) -> String:
	return "[color=#ffdc4a]%s[/color]:" % speaker_name if speaker_name != "" else ""

## Show a Red text (key or raw string) box by box. speaker_name prefixes the first line of every box
## ("Kecleon: ..."), as Red does for NPC talk; sp is the portrait species ("" = none, e.g. asleep).
static func say(root: Control, key_or_text: String, speaker_name := "", sp := "", vars: Dictionary = {}, emotion := "Normal") -> void:
	var raw := get_text(key_or_text) if has(key_or_text) else key_or_text
	var token := RefCounted.new()
	TeamScreens._stack.append(token)
	var d := Dialog.get_box(root)
	for p in fmt(raw, vars):
		await d._say(_speaker_prefix(speaker_name) + str(p), sp, emotion, "")
	d.hide_box()
	TeamScreens._stack.erase(token)

## Red's CreateMenuDialogueBoxAndPortrait: earlier boxes are shown first, the last one stays up with a
## command window beside it. Returns the picked index or -1 (B). opts may hold {text, disabled}.
static func ask(root: Control, key_or_text: String, speaker_name: String, sp: String, opts: Array, vars: Dictionary = {}, default_i := 0, emotion := "Normal") -> int:
	var raw := get_text(key_or_text) if has(key_or_text) else key_or_text
	var pages := fmt(raw, vars)
	if pages.is_empty():
		pages = [""]
	var d := Dialog.get_box(root)
	var token := RefCounted.new()
	TeamScreens._stack.append(token)
	for k in pages.size() - 1:
		await d._say(_speaker_prefix(speaker_name) + str(pages[k]), sp, emotion, "")
	TeamScreens._stack.erase(token)
	d._show(_speaker_prefix(speaker_name) + str(pages[-1]), sp, emotion, "")
	d._finish_typing()
	var rows: Array = []
	for o in opts:
		rows.append(o if o is Dictionary else {"text": str(o)})
	var m := TeamScreens.menu("", rows)
	m.sel = default_i
	await root.get_tree().process_frame
	var vs := root.get_viewport_rect().size
	var at := Vector2(vs.x - 8, d.panel.position.y - 4)
	var bd := TeamScreens._backdrop(root, m)
	root.add_child(m)
	await root.get_tree().process_frame
	if is_instance_valid(m):
		m.position = Vector2(at.x - m.size.x, at.y - m.size.y)
	var r: Dictionary = m.result if m.finished else await m.done
	TeamScreens._drop(bd)
	TeamScreens._drop(m)
	d.hide_box()
	return int(r.i) if r.act == "pick" else -1
