class_name TeamScreens
extends RefCounted
## PMD Red's team screens (dungeon_menu_team.c, dungeon_menu_moves.c, pokemon_summary_window.c),
## shared by the dungeon and the town. Every screen takes either a dungeon Mon or a team-entry
## Dictionary ({sp, name, level, exp, moves, iq, held, bonus, ...}).
##
##   await TeamScreens.summary(root, m)                       # Stats / Status / Features / Info pages
##   var a := await TeamScreens.moves_menu(root, m, true, dungeon)   # {use, chain, user} when the leader picks Use
##   await TeamScreens.move_info(root, "Ember")
##   await TeamScreens.item_info(root, "oran")
##   await TeamScreens.tactics_menu(root, m)
##   await TeamScreens.iq_menu(root, m)
##   var a := await TeamScreens.team_menu(root, members, in_dungeon, dungeon)  # {use, ...} or {}
##
## Generic Red windows used by the dungeon menus too:
##   RedMenu (cursor list: pages with Left/Right, Shift+Up/Down, Select key, tap, tap-outside = cancel)
##   InfoPage (text window with pages: Left/Right or tap flips, A/B closes)
##   run_menu(root, menu, at) / run_page(root, page, at) / ask(root, text, opts) / say(root, text)

const IQ_PATH := "res://scripts/core/iq.gd"
const TEXT_PATH := "res://data/menu_text.json"
const P := UITheme.PX
const WIN_X := 16.0                # Red's windows sit 2 tiles in; 16 px keeps 2x windows inside 480 px
const WIN_Y := 22.0                # just under the dungeon HUD line
const ARROW_L := ""          # Red font's arrows (private-use glyphs in pmd_red_text.ttf)
const ARROW_R := ""
const ARROW_U := ""
const ARROW_D := ""
const YELLOW := "#ffdc4a"
const CYAN := "#7fe0ff"
const GREEN := "#7fff7f"
const RED := "#ff8070"

static var _text: Dictionary = {}
static var _icons: Dictionary = {}
static var _stack: Array = []      # open screens; only the top one takes input
static var _auto_last := ""
static var _auto_rep := 0

# ============================================================================ data helpers
static func text() -> Dictionary:
	if _text.is_empty():
		var f := FileAccess.open(TEXT_PATH, FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_text = v
	return _text

static func iq_script() -> Variant:
	if ResourceLoader.exists(IQ_PATH):
		return load(IQ_PATH)
	return null

static func auto_on() -> bool:
	return ListMenu.auto

## A Mon to read stats from. Team entries get a temporary Mon whose moves array IS the entry's,
## so move edits made through it land in the entry.
static func as_mon(x) -> Mon:
	if x is Mon:
		return x
	var e: Dictionary = x
	var m: Mon = Game.mon_from_entry(e)
	if e.has("moves"):
		m.moves = e.moves
	m.held = str(e.get("held", ""))
	m.is_leader = Game.team.size() > 0 and is_same(Game.team[0], e)
	return m

static func moves_of(x) -> Array:
	if x is Mon:
		return x.moves
	var e: Dictionary = x
	if not e.has("moves"):
		e.moves = []
	return e.moves

static func name_of(x) -> String:
	if x is Mon:
		return x.name
	var n := str(x.get("name", ""))
	return n if n.strip_edges() != "" else str(DB.species.get(str(x.get("sp", "")), {}).get("name", "???"))

static func held_of(x) -> String:
	if x is Mon:
		return x.held
	return str(x.get("held", ""))

static func set_held(x, id: String) -> void:
	if x is Mon:
		x.held = id
		var e: Dictionary = x.get_meta("entry", {})
		if not e.is_empty():
			e.held = id
	else:
		x.held = id

static var leader_changed := false

## Make Leader (party_list_menu.c PARTY_LIST_MENU_MAKE_LEADER): the chosen member leads the team.
static func make_leader(x) -> void:
	var i := Game.team.find(x)
	if i <= 0:
		return
	Game.team.remove_at(i)
	Game.team.insert(0, x)
	leader_changed = true
	Game.save_game()

static func is_leader(x, dungeon = null) -> bool:
	if x is Mon:
		return x.is_leader
	return Game.team.size() > 0 and is_same(Game.team[0], x)

static func move_desc(n: String) -> Dictionary:
	return text().get("moves", {}).get(n, {})

## Red's verb for using an item (gActions[GetItemActionType]); "" = no use command (thrown/held/Poké).
static func item_verb(id: String) -> String:
	var I: Dictionary = DB.items.get(id, {})
	match str(I.get("action", "")):
		"throwable", "rocks", "ribbons", "specs", "scarfs":
			return ""
		"food":
			return "Eat"
		"healing":
			return "Ingest"
		"chestnut":
			return "Peel"
		"money_wish_stone":
			return "" if id == "poke" else "Use"
		"misc", "tm", "link_box", "orbs":
			return "Use"
	var k := str(I.get("kind", ""))
	if k in ["held", "red_ribbons", "red_scarfs", "red_specs", "line", "arc", "pierce", "red_throwable", "valuable", "money"] or I.get("throwable", false):
		return ""
	if k in ["drink", "elixir", "ether", "vitamin"]:
		return "Ingest"
	if k in ["food", "red_food", "heal", "sitrus", "cure", "reviver", "sleep", "blast", "iqgummi", "red_healing", "quick", "warp", "blind", "life", "eyedrop", "confuse", "doom", "petrify", "joy", "grimy"]:
		return "Eat"
	return "Use"

## Thrown with Set/Deselect + the quick throw (CATEGORY_THROWN_LINE / THROWN_ARC).
static func is_thrown(id: String) -> bool:
	var I: Dictionary = DB.items.get(id, {})
	return str(I.get("red_cat", "")) in ["thrown_line", "thrown_arc"] or (I.get("throwable", false) and I.get("stack", false))

static func item_label(id: String, n := 1) -> String:
	var I: Dictionary = DB.items.get(id, {})
	return str(I.get("name", id))

# ============================================================================ icons
const _STAR := ["...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", ".#...#."]
const _HEART := [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."]
const _SET := ["#######", "#.....#", "#.###.#", "#.#...#", "#.###.#", "#.#...#", "#######"]

static func _pix(rows: Array, fill: Color, outline: Color, fill_rows := 99) -> ImageTexture:
	var w: int = str(rows[0]).length()
	var h: int = rows.size()
	var im := Image.create(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	im.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if str(rows[y])[x] == "#":
				for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var q: Vector2i = Vector2i(x + 1, y + 1) + d
					if im.get_pixelv(q).a == 0:
						im.set_pixelv(q, outline)
	for y in h:
		for x in w:
			if str(rows[y])[x] == "#":
				var filled := y >= h - fill_rows
				im.set_pixel(x + 1, y + 1, fill if filled else Color(0.12, 0.12, 0.2))
	im.resize((w + 2) * P, (h + 2) * P, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(im)

## "star" (Red's STAR_BULLET), "set" (ICON_SET), "heart_r0".."heart_r3" / "heart_y0".."heart_y3"
## (HEART_*_TINY..LARGE: HP quarters), "blank".
static func icon(kind: String) -> Texture2D:
	if _icons.has(kind):
		return _icons[kind]
	var t: Texture2D
	if kind == "star":
		t = _pix(_STAR, Color("f8e040"), Color("583000"))
	elif kind == "set":
		t = _pix(_SET, Color("60f0a0"), Color("003018"))
	elif kind.begins_with("heart_"):
		var col := Color("f85050") if kind[6] == "r" else Color("f8d030")
		t = _pix(_HEART, col, Color("401010"), [2, 3, 5, 6][int(kind.right(1))])
	else:
		var im := Image.create(9 * P, 9 * P, false, Image.FORMAT_RGBA8)
		t = ImageTexture.create_from_image(im)
	_icons[kind] = t
	return t

static func heart_for(hp: int, max_hp: int, yellow := false) -> Texture2D:
	var q := 3
	if hp <= max_hp / 4:
		q = 0
	elif hp <= (max_hp / 4) * 2:
		q = 1
	elif hp <= (max_hp / 4) * 3:
		q = 2
	return icon(("heart_y%d" if yellow else "heart_r%d") % q)

## Red's IQ stars (gUnknown_8115718: index IQ / 10).
static func iq_stars(iq: int) -> int:
	var i := clampi(iq / 10, 0, 99)
	if i == 0:
		return 1
	if i < 5:
		return 2
	if i < 10:
		return 3
	if i < 15:
		return 4
	if i < 20:
		return 5
	if i < 70:
		return 6 + (i - 20) / 10
	return 11

# ============================================================================ RedMenu
## Red's cursor window. Each row: {text (BBCode), right, icon (Texture2D), disabled, skip, indent, color}.
## run_menu() returns {act: "pick"|"cancel"|"left"|"right"|"shift"|"select", i, dir}.
class RedMenu extends PanelContainer:
	signal done(res: Dictionary)
	var title := ""
	var rows: Array = []
	var sel := 0
	var top := 0
	var max_rows := 8
	var min_w := 0.0
	var page := 0
	var pages := 0                  # > 1: header arrows, Left/Right return left/right
	var lr := false                 # Left/Right return left/right even on one page (option rows)
	var allow_cancel := true
	var shift_keys := false         # Shift + Up/Down returns shift (Red: R + Up/Down)
	var select_key := false         # act_map (Tab / Select) returns select (Red: Select)
	var line_h := UITheme.LINE
	var keep_on_pick := false       # stay on screen after a pick (a command sub-window follows; submenu() closes it)
	var on_select: Callable
	var mark_touch := false         # touch: hold a row to mark it; while anything is marked a tap toggles (multi-select lists)
	var footer: Array = []          # touch buttons under the list: [[label, act], ...]; act "" = a hint line
	var header_buttons: Array = []  # touch buttons in the title line: [[label, act], ...]
	var _scroll_up: Button
	var _scroll_dn: Button
	var finished := false
	var _press_i := -1              # touch / mouse: row pressed, where, and whether it became a swipe
	var _press_pos := Vector2.ZERO
	var _dragged := false
	var _press_token := 0
	var result: Dictionary = {}
	var _box: VBoxContainer
	var _rows: Array = []

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size.x = min_w
		TeamScreens._stack.append(self)
		tree_exiting.connect(func(): TeamScreens._stack.erase(self))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		var scrolls := rows.size() > max_rows
		if title != "" or pages > 1 or not header_buttons.is_empty() or scrolls:
			var hb := HBoxContainer.new()
			hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_theme_constant_override("separation", 3 * P)
			vb.add_child(hb)
			var t := TeamScreens._rtl("[color=%s]%s[/color]" % [TeamScreens.YELLOW, title])
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(t)
			for f in header_buttons:
				var act := str(f[1])
				hb.add_child(TeamScreens._arrow(str(f[0]), func(): _finish({"act": act})))
			if scrolls:
				# touch: more rows than fit; tap to scroll (or swipe the list)
				_scroll_up = TeamScreens._arrow(TeamScreens.ARROW_U, func(): _scroll_by(-1))
				_scroll_dn = TeamScreens._arrow(TeamScreens.ARROW_D, func(): _scroll_by(1))
				hb.add_child(_scroll_up)
				hb.add_child(_scroll_dn)
			if pages > 1:
				hb.add_child(TeamScreens._arrow(TeamScreens.ARROW_L, func(): _finish({"act": "left"})))
				var pl := Label.new()
				pl.text = "%d/%d" % [page + 1, pages]
				hb.add_child(pl)
				hb.add_child(TeamScreens._arrow(TeamScreens.ARROW_R, func(): _finish({"act": "right"})))
		_box = VBoxContainer.new()
		_box.add_theme_constant_override("separation", 0)
		_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(_box)
		for k in mini(rows.size(), max_rows):
			_rows.append(_make_row(k))
		if not footer.is_empty():
			var fb := HBoxContainer.new()
			fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fb.add_theme_constant_override("separation", 8 * P)
			vb.add_child(fb)
			for f in footer:
				var act := str(f[1])
				if act == "":
					var hint := Label.new()
					hint.text = str(f[0])
					hint.add_theme_color_override("font_color", UITheme.INK_DIM)
					fb.add_child(hint)
				else:
					var btn := TeamScreens._arrow(str(f[0]), func(): _finish({"act": act}))
					fb.add_child(btn)
		sel = clampi(sel, 0, maxi(0, rows.size() - 1))
		if rows.size() > 0 and rows[sel].get("skip", false):
			sel = _step(sel, 1)
		_scroll_to(sel)
		_refresh()
		if TeamScreens.auto_on():
			_auto_pick.call_deferred()

	func _auto_pick() -> void:
		var pick := -1
		for i in rows.size():
			if not rows[i].get("disabled", false) and not rows[i].get("skip", false):
				pick = i
				break
		var sig := title + "|" + str(rows.size())
		TeamScreens._auto_rep = TeamScreens._auto_rep + 1 if sig == TeamScreens._auto_last else 0
		TeamScreens._auto_last = sig
		if pick < 0 or TeamScreens._auto_rep >= 2:
			_finish({"act": "cancel"})
		else:
			sel = pick
			_finish({"act": "pick", "i": pick})

	func _make_row(k: int) -> HBoxContainer:
		var hb := HBoxContainer.new()
		hb.custom_minimum_size = Vector2(0, line_h)
		hb.add_theme_constant_override("separation", P)
		hb.mouse_filter = Control.MOUSE_FILTER_STOP
		var cur := TextureRect.new()
		cur.texture = ListMenu._blank_icon()
		cur.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(cur)
		var ind := Control.new()
		ind.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ind)
		var ic := TextureRect.new()
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(ic)
		var t := TeamScreens._rtl("")
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(t)
		var r := TeamScreens._rtl("")
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(r)
		hb.gui_input.connect(_row_input.bind(k))
		hb.draw.connect(_draw_mark.bind(k))
		hb.mouse_entered.connect(func():
			var i: int = top + k
			if i < rows.size() and not rows[i].get("skip", false) and i != sel:
				sel = i
				_refresh())
		_box.add_child(hb)
		return hb

	## Red's marked row (sub_8007B7C): a bar in font colour 14 behind the item name, from the text to the
	## window's right edge, 10 px tall (kecleon_bros4.c sub_801A9E0 / Kangaskhan Storage multi-select).
	func _draw_mark(k: int) -> void:
		var i: int = top + k
		if i >= rows.size() or not bool(rows[i].get("marked", false)):
			return
		var hb: HBoxContainer = _rows[k]
		var x0: float = hb.get_child(3).position.x
		if hb.get_child(2).visible:
			x0 = hb.get_child(2).position.x
		var hgt := 10.0 * P
		hb.draw_rect(Rect2(x0, (hb.size.y - hgt) / 2.0, hb.size.x - x0, hgt), UITheme.FRAME_MID)

	func _refresh() -> void:
		for k in _rows.size():
			_rows[k].queue_redraw()
			var i: int = top + k
			var hb: HBoxContainer = _rows[k]
			var row: Dictionary = rows[i] if i < rows.size() else {}
			var cur: TextureRect = hb.get_child(0)
			cur.texture = ListMenu._cursor_icon() if i == sel else ListMenu._blank_icon()
			var ind: Control = hb.get_child(1)
			ind.custom_minimum_size.x = 5 * P if row.get("indent", false) else 0
			var ic: TextureRect = hb.get_child(2)
			ic.texture = row.get("icon", null)
			ic.visible = row.has("icon")
			var t: RichTextLabel = hb.get_child(3)
			t.text = str(row.get("text", ""))
			var dis: bool = row.get("disabled", false)
			t.add_theme_color_override("default_color", UITheme.INK_DIM if dis else row.get("color", UITheme.INK))
			var r: RichTextLabel = hb.get_child(4)
			r.text = str(row.get("right", ""))
			r.visible = r.text != ""
			r.add_theme_color_override("default_color", UITheme.INK_DIM if dis else UITheme.INK)
		if _scroll_up:
			_scroll_up.modulate.a = 1.0 if top > 0 else 0.3
			_scroll_dn.modulate.a = 1.0 if top + max_rows < rows.size() else 0.3
		if on_select.is_valid() and rows.size() > 0:
			on_select.call(sel)

	func refresh_rows(new_rows: Array) -> void:
		rows = new_rows
		_refresh()

	func _scroll_to(i: int) -> void:
		if i < top:
			top = i
		elif i >= top + max_rows:
			top = i - max_rows + 1
		top = clampi(top, 0, maxi(0, rows.size() - max_rows))

	func _step(from: int, d: int) -> int:
		var n := rows.size()
		var i := from
		for _k in n:
			i = (i + d + n) % n
			if not rows[i].get("skip", false):
				return i
		return from

	func set_sel(i: int) -> void:
		sel = clampi(i, 0, maxi(0, rows.size() - 1))
		_scroll_to(sel)
		_refresh()

	func _is_top() -> bool:
		return not TeamScreens._stack.is_empty() and TeamScreens._stack.back() == self

	func _finish(r: Dictionary) -> void:
		if finished:
			return
		finished = true
		result = r
		if not r.has("i"):
			r.i = sel
		match str(r.get("act", "")):
			"pick", "select":
				Audio.sfx("confirm")
			"cancel":
				Audio.sfx("cancel")
			_:
				Audio.sfx("cursor")
		done.emit(r)

	func pick_current() -> void:
		if rows.is_empty():
			return
		if rows[sel].get("disabled", false):
			Audio.sfx("error")
			return
		_finish({"act": "pick", "i": sel})

	func cancel() -> void:
		if allow_cancel:
			_finish({"act": "cancel"})

	## Touch / mouse: a tap acts on release, so a finger can swipe the list first (up/down scrolls,
	## left/right turns the page). In multi-select lists, holding a row marks it.
	func _row_input(e: InputEvent, k: int) -> void:
		if finished or not _is_top():
			return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			var i: int = top + k
			if e.pressed:
				_press_i = i
				_press_pos = e.global_position
				_dragged = false
				_press_token += 1
				if i < rows.size() and not rows[i].get("skip", false):
					sel = i
					_refresh()
					if mark_touch:
						var tok := _press_token
						get_tree().create_timer(0.45).timeout.connect(func():
							if tok == _press_token and _press_i == i and not _dragged and not finished:
								_press_i = -1
								_finish({"act": "select", "i": i}))
			elif _press_i >= 0:
				var pi := _press_i
				_press_i = -1
				if not _dragged and pi < rows.size() and not rows[pi].get("skip", false):
					sel = pi
					if mark_touch and _any_marked():
						_finish({"act": "select", "i": pi})       # marking mode: a tap toggles the mark
					elif lr and pages <= 1:
						# option rows: a tap changes the value instead of closing the page; the left half of
						# the value steps back, anything else steps forward (tap outside the window to finish)
						var r: Control = _rows[k].get_child(4)
						var back: bool = r.visible and e.position.x >= r.position.x and e.position.x < r.position.x + r.size.x * 0.5
						_finish({"act": "left" if back else "right", "i": pi})
					else:
						pick_current()
			accept_event()
		elif e is InputEventMouseMotion and _press_i >= 0 and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			var d: Vector2 = e.global_position - _press_pos
			var lh := float(line_h) * get_global_transform().get_scale().y
			if pages > 1 and absf(d.x) > 40.0 * P * get_global_transform().get_scale().x and absf(d.x) > absf(d.y) * 1.5:
				_dragged = true
				_press_i = -1
				_finish({"act": "right" if d.x < 0 else "left"})
			elif rows.size() > max_rows and absf(d.y) >= lh:
				_dragged = true
				var step := -1 if d.y > 0 else 1                       # drag up = scroll down, like a phone list
				var nt := clampi(top + step, 0, rows.size() - max_rows)
				_press_pos.y += lh * signf(d.y)
				if nt != top:
					top = nt
					sel = clampi(sel, top, top + max_rows - 1)
					_refresh()
			elif d.length() > 12.0 * P:
				_dragged = true
			accept_event()

	func _scroll_by(d: int) -> void:
		var nt := clampi(top + d, 0, maxi(0, rows.size() - max_rows))
		if nt != top:
			top = nt
			sel = clampi(sel, top, top + max_rows - 1)
			Audio.sfx("cursor")
			_refresh()

	func _any_marked() -> bool:
		for r in rows:
			if r is Dictionary and bool(r.get("marked", false)):
				return true
		return false

	func _gui_input(e: InputEvent) -> void:
		if finished or not _is_top():
			return
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_RIGHT:
				cancel()
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and rows.size() > 0:
				set_sel(_step(sel, 1))
			elif e.button_index == MOUSE_BUTTON_WHEEL_UP and rows.size() > 0:
				set_sel(_step(sel, -1))
			accept_event()

	func _unhandled_input(e: InputEvent) -> void:
		if finished or not is_visible_in_tree() or not _is_top():
			return
		var vp := get_viewport()
		var shift := Input.is_action_pressed("act_run")
		if e.is_action_pressed("ui_down", true) or e.is_action_pressed("move_down", true):
			if shift_keys and shift:
				_finish({"act": "shift", "dir": 1})
			elif rows.size() > 0:
				set_sel(_step(sel, 1))
				Audio.sfx("cursor")
		elif e.is_action_pressed("ui_up", true) or e.is_action_pressed("move_up", true):
			if shift_keys and shift:
				_finish({"act": "shift", "dir": -1})
			elif rows.size() > 0:
				set_sel(_step(sel, -1))
				Audio.sfx("cursor")
		elif (e.is_action_pressed("ui_left") or e.is_action_pressed("move_left")) and (pages > 1 or lr):
			_finish({"act": "left"})
		elif (e.is_action_pressed("ui_right") or e.is_action_pressed("move_right")) and (pages > 1 or lr):
			_finish({"act": "right"})
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			pick_current()
		elif select_key and (e.is_action_pressed("act_map") or e.is_action_pressed("gp_l") or e.is_action_pressed("gp_r") \
				or (e is InputEventKey and e.pressed and not e.echo and e.keycode in [KEY_Q, KEY_E])):
			_finish({"act": "select"})      # mark several (Select, L or R; Q / E on a keyboard)
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			cancel()
		else:
			return
		vp.set_input_as_handled()

# ============================================================================ InfoPage
## Red's description / summary window: a header with page arrows and a text body.
## builder.call(i) -> {title: String, parts: Array}; parts are BBCode strings, Texture2Ds and
## {table: n, cells: [parts or String, ...]} dictionaries.
class InfoPage extends PanelContainer:
	signal done(res: Dictionary)
	var builder: Callable
	var count := 1
	var page := 0
	var width := 416.0
	var line_sep := -2
	var finished := false
	var result: Dictionary = {}
	var _title: RichTextLabel
	var _pip: Label
	var _body: RichTextLabel

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		custom_minimum_size.x = width
		TeamScreens._stack.append(self)
		tree_exiting.connect(func(): TeamScreens._stack.erase(self))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", P)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(hb)
		_title = TeamScreens._rtl("")
		_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(_title)
		if count > 1:
			hb.add_child(TeamScreens._arrow(TeamScreens.ARROW_L, func(): flip(-1)))
			_pip = Label.new()
			hb.add_child(_pip)
			hb.add_child(TeamScreens._arrow(TeamScreens.ARROW_R, func(): flip(1)))
		_body = TeamScreens._rtl("")
		_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.custom_minimum_size.x = width - 12 * P
		_body.add_theme_constant_override("line_separation", line_sep)
		vb.add_child(_body)
		_show()
		if TeamScreens.auto_on():
			(func(): _finish({"act": "close"})).call_deferred()

	func _show() -> void:
		var d: Dictionary = builder.call(page)
		_title.text = "[color=%s]%s[/color]" % [TeamScreens.YELLOW, str(d.get("title", ""))]
		if _pip:
			_pip.text = "%d/%d" % [page + 1, count]
		_body.clear()
		TeamScreens.fill(_body, d.get("parts", []))
		reset_size.call_deferred()

	func flip(d: int) -> void:
		if count <= 1:
			return
		page = (page + d + count) % count
		Audio.sfx("cursor")
		_show()

	func _is_top() -> bool:
		return not TeamScreens._stack.is_empty() and TeamScreens._stack.back() == self

	func _finish(r: Dictionary) -> void:
		if finished:
			return
		finished = true
		result = r
		done.emit(r)

	func close() -> void:
		Audio.sfx("cancel")
		_finish({"act": "close"})

	func _gui_input(e: InputEvent) -> void:
		if finished or not _is_top():
			return
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				if count > 1:
					flip(1)
				else:
					close()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				close()
			accept_event()

	func _unhandled_input(e: InputEvent) -> void:
		if finished or not is_visible_in_tree() or not _is_top():
			return
		var vp := get_viewport()
		if e.is_action_pressed("ui_left") or e.is_action_pressed("move_left"):
			flip(-1)
		elif e.is_action_pressed("ui_right") or e.is_action_pressed("move_right"):
			flip(1)
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack") or e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			close()
		else:
			return
		vp.set_input_as_handled()

# ============================================================================ window plumbing
static func _rtl(t: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = t
	return r

static func _arrow(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_color_override("font_color", UITheme.GOLD)
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(10 * P, UITheme.LINE)
	b.pressed.connect(cb)
	return b

## Touch: a "Back" button for full-screen views that otherwise only close with B / right-click.
static func back_button(cb: Callable) -> Button:
	var b := _arrow("Back", cb)
	b.custom_minimum_size = Vector2(28 * P, UITheme.LINE)
	return b

## Append parts to a RichTextLabel (see InfoPage).
static func fill(r: RichTextLabel, parts: Array) -> void:
	for p in parts:
		if p is Texture2D:
			r.add_image(p)
		elif p is Dictionary and p.has("table"):
			r.push_table(int(p.table))
			r.set_table_column_expand(0, false)
			for c in p.cells:
				r.push_cell()
				fill(r, c if c is Array else [str(c)])
				r.pop()
			r.pop()
			r.append_text("\n")
		else:
			r.append_text(str(p))

## A transparent full-screen catcher behind a window: tapping outside the window cancels it (Red's B).
static func _backdrop(root: Control, target: Control) -> Control:
	var bd := Control.new()
	bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bd.mouse_filter = Control.MOUSE_FILTER_STOP
	bd.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and is_instance_valid(target):
			if not TeamScreens._stack.is_empty() and TeamScreens._stack.back() == target:
				if target is RedMenu:
					target.cancel()
				elif target is InfoPage:
					target.close())
	root.add_child(bd)
	return bd

static func _drop(c: Node) -> void:
	if c and is_instance_valid(c):
		if c.get_parent():
			c.get_parent().remove_child(c)
		c.queue_free()

static func _clamp_into(root: Control, c: Control) -> void:
	await root.get_tree().process_frame
	if not is_instance_valid(c):
		return
	var vs := root.get_viewport_rect().size
	c.reset_size()
	c.position.x = clampf(c.position.x, 2, maxf(2, vs.x - c.size.x - 2))
	c.position.y = clampf(c.position.y, 2, maxf(2, vs.y - c.size.y - 2))

static func run_menu(root: Control, m: RedMenu, at: Vector2) -> Dictionary:
	var bd := _backdrop(root, m)
	root.add_child(m)
	m.position = at
	_clamp_into(root, m)
	var r: Dictionary = m.result if m.finished else await m.done
	_drop(bd)
	if not (m.keep_on_pick and r.get("act", "") == "pick"):
		_drop(m)
	return r

static func run_page(root: Control, pg: InfoPage, at := Vector2(WIN_X, WIN_Y)) -> void:
	var bd := _backdrop(root, pg)
	root.add_child(pg)
	pg.position = at
	_clamp_into(root, pg)
	if not pg.finished:
		await pg.done
	_drop(pg)
	_drop(bd)

static func menu(title: String, rows: Array, min_w := 0.0) -> RedMenu:
	var m := RedMenu.new()
	m.title = title
	for r in rows:
		m.rows.append(r if r is Dictionary else {"text": str(r)})
	m.min_w = min_w
	return m

## Red's sub-window of commands, opened beside the window it belongs to. Returns the picked label or "".
static func submenu(root: Control, beside: Control, opts: Array, row := 0) -> String:
	var rows: Array = []
	for o in opts:
		rows.append(o if o is Dictionary else {"text": str(o)})
	var m := menu("", rows)
	var at := Vector2(WIN_X + 200, WIN_Y)
	if beside and is_instance_valid(beside):
		at = Vector2(beside.position.x + beside.size.x + 2 * P, beside.position.y + UITheme.LINE * (row + 1))
	var r := await run_menu(root, m, at)
	if beside is RedMenu and beside.keep_on_pick:
		_drop(beside)
	if r.act != "pick":
		return ""
	return str(rows[r.i].get("id", rows[r.i].text))

static func page(title: String, parts: Array, width := 416.0) -> InfoPage:
	var pg := InfoPage.new()
	pg.width = width
	pg.builder = func(_i): return {"title": title, "parts": parts}
	return pg

static func show_text(root: Control, title: String, body: String, width := 416.0) -> void:
	await run_page(root, page(title, [UITheme.red_text(body)], width))

## A Red message box (dialogue window) that blocks the windows underneath until it is dismissed.
static func say(root: Control, msg: String, speaker := "") -> void:
	var token := RefCounted.new()
	_stack.append(token)
	await Dialog.say(root, msg, speaker)
	_stack.erase(token)

## Red's yes/no style question: the message box plus a small command window. Returns the index or -1.
static func ask(root: Control, msg: String, opts: Array, default_i := 0) -> int:
	var d := Dialog.get_box(root)
	d._show(msg, "", "Normal", "")
	d._finish_typing()
	var m := menu("", opts)
	m.sel = default_i
	await root.get_tree().process_frame
	var vs := root.get_viewport_rect().size
	var at := Vector2(vs.x - 120, d.panel.position.y - (opts.size() * UITheme.LINE + 20))
	var r := await run_menu(root, m, at)
	d.hide_box()
	return r.i if r.act == "pick" else -1

# ============================================================================ move info
static func _move_parts(n: String) -> Array:
	var d: Dictionary = DB.moves.get(n, {})
	var t := move_desc(n)
	var desc := str(t.get("desc", ""))
	if desc.begins_with("*"):
		desc = desc.substr(1)
	if desc == "":
		desc = "No description."
	var rng := str(t.get("range", ""))
	if rng == "":
		rng = {"front": "Foe in front", "front_corners": "Foe in front, cuts corners", "line": "Straight line", "room": "Foes in room",
			"user": "User", "two_tiles": "Foe up to 2 tiles ahead", "team_room": "Allies in room", "room_all": "All Pokémon in room",
			"adjacent": "Foes within 1-tile range", "floor_all": "Pokémon on floor", "team_floor": "Members on floor", "floor_foes": "Foes on floor",
			"front_spread": "3 tiles diagonally and in front", "wall": "Wall", "items": "Items", "special": "Special", "floor": "Floor"}.get(str(d.get("r", "front")), "Special")
	var pw := int(d.get("p", 0))
	var acc := int(d.get("a1", 100))
	var parts: Array = [UITheme.red_text(desc), "\n\n"]
	parts.append({"table": 2, "cells": ["Range  ", rng, "Type", "[color=%s]%s[/color]" % [CYAN, str(d.get("t", "Normal"))],
		"Power", str(pw) if pw > 0 and str(d.get("c", "P")) != "X" else "--", "Accuracy  ", "--" if acc >= 100 else "%d%%" % acc]})
	return parts

## Red's move description (ShowMovesInfoWindow): Left/Right walks a linked chain.
static func move_info(root: Control, move_name: String) -> void:
	await move_info_chain(root, [move_name])

static func move_info_chain(root: Control, names: Array) -> void:
	if names.is_empty():
		return
	var pg := InfoPage.new()
	pg.count = names.size()
	pg.builder = func(i): return {"title": str(names[i]), "parts": TeamScreens._move_parts(str(names[i]))}
	await run_page(root, pg)

## Red's item description window (InitItemDescriptionWindow).
static func item_info(root: Control, id: String) -> void:
	var I: Dictionary = DB.items.get(id, {})
	var desc := str(I.get("desc", ""))
	await run_page(root, page(str(I.get("name", id)), [UITheme.red_text(desc if desc != "" else "No description.")]))

# ============================================================================ summary
const STATUS_INDEX := {"sleep": "1", "nightmare": "2", "yawn": "3", "napping": "4", "burn": "6", "poison": "7", "badpoison": "8",
	"para": "9", "frozen": "12", "wrapping": "15", "wrapped": "16", "paused": "18", "cowering": "19", "taunt": "20", "infatuated": "21",
	"bide": "22", "charging": "32", "reflect": "34", "safeguard": "35", "light_screen": "36", "counter": "37", "magic_coat": "38",
	"protect": "40", "mirror_coat": "41", "enduring": "42", "mist": "46", "curse": "48", "decoy": "49", "leech_seed": "50",
	"destiny_bond": "51", "invisible": "55", "blinker": "58", "cross_eyed": "59", "eyedrops": "60", "muzzled": "61", "cringe": "62",
	"petrified": "63", "sure_shot": "64", "focus_energy": "65", "confused": "67", "encore": "68", "snatch": "70", "fast": "81",
	"slow": "82", "stockpile": "83", "radar": "84", "grudge": "86", "terrified": "88", "perish": "89"}

static func _stat_cells(m: Mon) -> Array:
	var cells: Array = []
	var nxt := DB.exp_at(m.sp, m.level + 1) - m.exp
	cells.append_array(["Level:", str(m.level), "Exp. Pts.:", str(m.exp)])
	if m.level < 100:
		cells.append_array(["To next level:", str(maxi(0, nxt))])
	cells.append_array(["HP:", "%d/%d" % [m.hp, m.max_hp], "Attack/Defense:", "%d/%d" % [m.atk, m.def],
		"Sp. Atk./Sp. Def.:", "%d/%d" % [m.spa, m.spd]])
	var held := m.held
	cells.append_array(["Item:", item_label(held) if held != "" else "None"])
	return cells

static func _summary_page(x, m: Mon, i: int, in_town: bool) -> Dictionary:
	var parts: Array = []
	match i:
		0:
			var cells := _stat_cells(m)
			var stars: Array = []
			for _k in iq_stars(int(m.iq)):
				stars.append(icon("star"))
			cells.append_array(["IQ:", stars])
			if not is_leader(x):
				var IQS = iq_script()
				var tn := "Let's go together"
				if IQS:
					tn = IQS.tactic_name(IQS.tactic_of(x))
				cells.append_array(["Tactics:", tn])
			parts.append({"table": 2, "cells": cells})
			return {"title": "Stats", "parts": parts}
		1:
			var lst: Array = []
			if m.hp > 0 and m.hp <= m.max_hp / 4:
				lst.append("5")
			for k in STATUS_INDEX:
				if m.status.get(k, 0) is int and int(m.status.get(k, 0)) > 0:
					lst.append(STATUS_INDEX[k])
			var st: Dictionary = text().get("statuses", {})
			if lst.is_empty():
				parts.append("No status problems")
			else:
				var names: Array = []
				for s in lst:
					names.append("[color=%s]%s[/color]" % [CYAN, st.get(s, {}).get("name", s)])
				parts.append("\n".join(names))
			return {"title": "Status", "parts": parts}
		2:
			var ts: Array = []
			for t in m.types:
				ts.append("[color=%s]%s[/color]" % [CYAN, t])
			parts.append({"table": 2, "cells": ["Type:  ", "  ".join(ts)]})
			parts.append("Special Abilities:\n")
			var ab: Dictionary = text().get("abilities", {})
			for a in [m.ability, m.ability2]:
				if str(a) == "":
					continue
				var key := str(a).to_lower().replace("-", "").replace("_", "").replace(" ", "")
				var d: Dictionary = ab.get(key, {})
				parts.append(UITheme.red_text(str(d.get("desc", "{color RED}%s{reset}" % str(a).capitalize()))).replace("\n", " ") + "\n")
			return {"title": "Features", "parts": parts}
		_:
			var S: Dictionary = DB.species.get(m.sp, {})
			var area := str(S.get("friend", ""))
			if area == "" or true:
				area = Services.area_name(Services.area_of(m.sp)) if Services.area_of(m.sp) != "" else "----"
			var e: Dictionary = m.get_meta("entry", {}) if not (x is Dictionary) else x
			var joined := str(e.get("joined", e.get("joined_at", "")))
			if joined == "":
				joined = "----"
			var cat := str(text().get("categories", {}).get(m.sp.substr(0, 4), ""))
			var size := int(S.get("size", 1))
			var size_icons: Array = []
			for _k in clampi(size, 1, 5):
				size_icons.append(icon("star"))
			parts.append({"table": 2, "cells": ["Species:  ", "[color=%s]%s[/color]" % [YELLOW, S.get("name", m.sp)],
				"Friend Area:", "", " ", "[color=%s]%s[/color]" % [GREEN, area]]})
			parts.append("Joined rescue team at:\n  [color=%s]%s[/color]\n" % [CYAN, joined])
			if cat != "":
				parts.append("[color=%s]%s Pokémon[/color]\n" % [CYAN, cat])
			parts.append("Size:  ")
			parts.append_array(size_icons)
			if in_town:
				var ev := "No more"
				var evo: Array = DB.evo.get(m.sp, [])
				if evo.size() > 0:
					ev = "Not now"
					for x2 in evo:
						if int(x2[1]) > 0 and m.level >= int(x2[1]):
							ev = "Possible"
				parts.append("\nEvolution:  %s" % ev)
			return {"title": "Info", "parts": parts}

## Red's Summary (ShowDungeonSummaryOrIQMenu without IQ): Stats, Status, Features, Info.
static func summary(root: Control, x, start_page := 0) -> void:
	var m := as_mon(x)
	var in_town := not (x is Mon)
	var pg := InfoPage.new()
	pg.count = 4
	pg.page = start_page
	pg.width = 416.0
	pg.builder = func(i):
		var d := TeamScreens._summary_page(x, m, i, in_town)
		d.title = "%s  %s" % [d.title, TeamScreens.name_of(x)]
		return d
	await run_page(root, pg, Vector2(WIN_X, 4))

# ============================================================================ moves
static func _iq_link(fn: String, moves: Array, i: int) -> bool:
	var IQS = iq_script()
	if IQS:
		return bool(IQS.call(fn, moves, i))
	match fn:
		"can_link":
			return i + 1 < moves.size()
		"link":
			for j in range(i + 1, moves.size()):
				if not moves[j].get("linked", false):
					moves[j].linked = true
					return true
			return false
		"can_delink":
			return i + 1 < moves.size() and moves[i + 1].get("linked", false)
		"delink":
			var did := false
			for j in range(i + 1, moves.size()):
				if moves[j].get("linked", false):
					moves[j].linked = false
					did = true
				else:
					break
			return did
	return false

static func chain_from(moves: Array, i: int) -> Array:
	var out := [i]
	var j := i + 1
	while j < moves.size() and bool(moves[j].get("linked", false)):
		out.append(j)
		j += 1
	return out

static func _chains(moves: Array) -> Array:
	var out: Array = []
	for i in moves.size():
		if i == 0 or not bool(moves[i].get("linked", false)):
			out.append([i])
		else:
			out[-1].append(i)
	return out

static func _fix(moves: Array) -> void:
	if moves.size() > 0:
		moves[0].linked = false
	for c in _chains(moves):
		var head: Dictionary = moves[c[0]]
		for j in c:
			moves[j].on = bool(head.get("on", true))
			moves[j].set = bool(head.get("set", false))

## R + Up/Down: move the chain holding move i up or down past its neighbouring chain.
static func shift_chain(moves: Array, i: int, dir: int) -> int:
	var cs := _chains(moves)
	var k := -1
	for n in cs.size():
		if i in cs[n]:
			k = n
	var o := k + dir
	if k < 0 or o < 0 or o >= cs.size():
		return i
	var obj: Dictionary = moves[i]
	var a: Array = cs[mini(k, o)]
	var b: Array = cs[maxi(k, o)]
	var blk: Array = []
	for j in b:
		blk.append(moves[j])
	for j in a:
		blk.append(moves[j])
	for n in blk.size():
		moves[a[0] + n] = blk[n]
	_fix(moves)
	for j in moves.size():
		if is_same(moves[j], obj):
			return j
	return i

static func toggle_set(moves: Array, i: int) -> bool:
	var was := bool(moves[i].get("set", false))
	for mv in moves:
		mv.set = false
	for j in chain_from(moves, i):
		moves[j].set = not was
	_fix(moves)
	return not was

static func toggle_on(moves: Array, i: int) -> bool:
	var v := not bool(moves[i].get("on", true))
	for j in chain_from(moves, i):
		moves[j].on = v
	_fix(moves)
	return v

static func _move_rows(x, leader: bool) -> Array:
	var rows: Array = []
	var mv := moves_of(x)
	for i in mv.size():
		var d: Dictionary = mv[i]
		var pp := int(d.get("pp", 0))
		var linked := i > 0 and bool(d.get("linked", false))
		var nm := str(d.name)
		var row := {"text": ("[color=%s]%s[/color]" % [RED, nm]) if pp <= 0 else nm, "right": "%2d/%2d" % [pp, int(d.get("max_pp", pp))],
			"indent": linked, "skip": linked}
		if leader:
			row.icon = icon("set") if bool(d.get("set", false)) else icon("blank")
		else:
			row.icon = icon("star") if bool(d.get("on", true)) else icon("blank")
		rows.append(row)
	return rows

static func _help_box(root: Control, at: Vector2, w: float, t: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme = UITheme.theme()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.custom_minimum_size.x = w
	var r := _rtl(t)
	r.add_theme_constant_override("line_separation", -2)
	pc.add_child(r)
	root.add_child(pc)
	pc.position = at
	return pc

## Red's Moves window (ShowDungeonMovesMenu). Left/Right: other team members; Shift + Up/Down: shift
## moves (R + Up/Down); Tab / Select: Set (leader) or Switch (others). Leader commands: Use, Set /
## Deselect, Info; other members: Switch (may the AI use it), Info; with allow_link also Link / Delink
## (Gulpin's Link Shop / Link Box). Returns {use: head move, chain: [names], user} when Use is picked.
static func moves_menu(root: Control, x, in_dungeon := false, dungeon = null, members: Array = [], allow_link := false) -> Dictionary:
	var list: Array = members.duplicate()
	if list.is_empty() and dungeon != null:
		list = dungeon.fs.team()
	if list.is_empty():
		list = [x]
	var cur := 0
	for k in list.size():
		if is_same(list[k], x):
			cur = k
	var sel := 0
	while true:
		var who = list[cur]
		var moves := moves_of(who)
		var leader := is_leader(who, dungeon)
		if moves.is_empty():
			await say(root, "%s doesn't know any moves." % name_of(who))
			return {}
		var m := menu("%s's moves" % name_of(who), _move_rows(who, leader), 288)
		m.max_rows = 4
		m.pages = list.size()
		m.page = cur
		m.shift_keys = true
		m.select_key = true
		m.keep_on_pick = true
		m.sel = sel
		var help := _help_box(root, Vector2(WIN_X, WIN_Y + 150), 288,
			"Shift+%s%s: Shift moves\nTab: %s" % [ARROW_U, ARROW_D, "Switch set moves" if leader else "Switch moves"])
		var prev := _preview_box(root, m, who, moves, in_dungeon, dungeon)
		var r := await run_menu(root, m, Vector2(WIN_X, WIN_Y))
		_drop(help)
		_drop(prev)
		sel = int(r.get("i", 0))
		match str(r.act):
			"cancel":
				return {}
			"left":
				cur = (cur - 1 + list.size()) % list.size()
				sel = 0
				continue
			"right":
				cur = (cur + 1) % list.size()
				sel = 0
				continue
			"shift":
				var ns := shift_chain(moves, sel, int(r.dir))
				Audio.sfx("cursor" if ns != sel else "error")
				sel = ns
				continue
			"select":
				_set_or_switch(who, moves, sel, leader, dungeon)
				continue
		# picked a move: Red's command window
		var chain := chain_from(moves, sel)
		var names: Array = []
		var all_pp := true
		for j in chain:
			names.append(str(moves[j].name))
			if int(moves[j].get("pp", 0)) <= 0:
				all_pp = false
		var opts: Array = []
		if leader:
			if in_dungeon:
				opts.append({"text": "Use", "disabled": not all_pp or (who is Mon and who.hp <= 0)})
			opts.append("Deselect" if bool(moves[sel].get("set", false)) else "Set")
		else:
			opts.append("Switch")
		if allow_link:
			opts.append({"text": "Link", "disabled": not _iq_link("can_link", moves, sel)})
			opts.append({"text": "Delink", "disabled": not _iq_link("can_delink", moves, sel)})
		opts.append("Info")
		var c := await submenu(root, m, opts, sel)
		match c:
			"Use":
				return {"use": names[0], "chain": names, "user": who}
			"Set", "Deselect", "Switch":
				_set_or_switch(who, moves, sel, leader, dungeon)
			"Link":
				var before := names.size()
				if _iq_link("link", moves, sel):
					_fix(moves)
					var nm2 := str(moves[chain_from(moves, sel)[before]].name) if chain_from(moves, sel).size() > before else ""
					_note(root, dungeon, "The move %s was linked with %s." % [names[0], nm2])
			"Delink":
				if _iq_link("delink", moves, sel):
					_fix(moves)
					_note(root, dungeon, "The move %s was delinked." % names[0])
				else:
					_note(root, dungeon, "The linked moves were left unchanged.")
			"Info":
				await move_info_chain(root, names)
	return {}

## QoL damage preview beside the Moves window: estimated damage, type matchup and hit chance of the move
## under the cursor against the foe the user faces (or the nearest one in sight). Text from dungeon.move_preview.
static func _preview_box(root: Control, m: RedMenu, who, moves: Array, in_dungeon: bool, dungeon) -> PanelContainer:
	if not in_dungeon or dungeon == null or not (who is Mon) or not dungeon.has_method("move_preview"):
		return null
	var pc := _help_box(root, Vector2(WIN_X + 288 + 2 * P, WIN_Y), 120, "")
	var r: RichTextLabel = pc.get_child(0)
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc.visible = false
	var place := func():
		# right of the Moves window (its width depends on the names), as wide as the screen allows
		await root.get_tree().process_frame
		if not is_instance_valid(pc) or not is_instance_valid(m):
			return
		var vs := root.get_viewport_rect().size
		var x := m.position.x + m.size.x + P
		var w := maxf(150.0, vs.x - x - 2 * P)
		pc.position = Vector2(minf(x, vs.x - w - 2 * P), m.position.y)
		pc.custom_minimum_size.x = w
		r.custom_minimum_size.x = w - 12 * P
		pc.reset_size()
	m.on_select = func(i: int):
		if not is_instance_valid(pc) or i < 0 or i >= moves.size():
			return
		var t: String = dungeon.move_preview(who, str(moves[i].name))
		r.text = t
		pc.visible = t != ""
		place.call()
	return pc

static func _note(_root: Control, dungeon, msg: String) -> void:
	if dungeon != null and dungeon.has_method("_msg"):
		dungeon._msg(msg)

static func _set_or_switch(who, moves: Array, i: int, leader: bool, dungeon) -> void:
	var nm := str(moves[i].name)
	if leader:
		var on := toggle_set(moves, i)
		_note(null, dungeon, ("The move [color=%s]%s[/color] was set." if on else "The move [color=%s]%s[/color] was deselected.") % [CYAN, nm])
	else:
		toggle_on(moves, i)
	Audio.sfx("confirm")
	if who is Mon:
		var e: Dictionary = who.get_meta("entry", {})
		if not e.is_empty():
			e.moves = who.moves.duplicate(true)

# ============================================================================ tactics / IQ
## Red's Tactics window (ShowDungeonTacticsMenu): ★ marks the current one; Switch / Info.
static func tactics_menu(root: Control, x) -> void:
	var IQS = iq_script()
	if IQS == null:
		await show_text(root, "Tactics", "Coming soon!")
		return
	var sel := 0
	while true:
		var list: Array = IQS.tactics_for(x)
		var rows: Array = []
		for t in list:
			rows.append({"text": str(t.name), "icon": icon("star") if t.on else icon("blank")})
		var m := menu("Tactics", rows, 288)
		m.keep_on_pick = true
		m.sel = sel
		var r := await run_menu(root, m, Vector2(WIN_X, WIN_Y))
		if r.act != "pick":
			return
		sel = r.i
		var t: Dictionary = list[r.i]
		var c := await submenu(root, m, ["Switch", "Info"], r.i - m.top)
		if c == "Switch":
			IQS.set_tactic(x, str(t.id))
			Audio.sfx("confirm")
		elif c == "Info":
			await show_text(root, str(t.name), str(t.desc))
		if auto_on():
			return

## Red's Check IQ window (SUB_WINDOW_IQ): the unlocked IQ skills, ★ = switched on; Switch / Info.
static func iq_menu(root: Control, x) -> void:
	var IQS = iq_script()
	if IQS == null:
		await show_text(root, "IQ Skills", "Coming soon!")
		return
	var sel := 0
	while true:
		var list: Array = []
		for s in IQS.skills_for(x):
			if s.unlocked:
				list.append(s)
		if list.is_empty():
			await show_text(root, "IQ Skills", "No IQ")
			return
		var rows: Array = []
		for s in list:
			rows.append({"text": str(s.name), "icon": icon("star") if s.on else icon("blank")})
		var m := menu("IQ Skills", rows, 288)
		m.keep_on_pick = true
		m.sel = sel
		var r := await run_menu(root, m, Vector2(WIN_X, WIN_Y))
		if r.act != "pick":
			return
		sel = r.i
		var s: Dictionary = list[r.i]
		var c := await submenu(root, m, ["Switch", "Info"], r.i - m.top)
		if c == "Switch":
			IQS.set_skill(x, str(s.id), not bool(s.on))
			Audio.sfx("confirm")
		elif c == "Info":
			await show_text(root, str(s.name), str(s.desc))
		if auto_on():
			return

# ============================================================================ team
## Red's Talk (sub_806A3D4 picks a line by HP: healthy / hurt / low). Approximated lines.
static func talk(root: Control, x) -> void:
	var m := as_mon(x)
	var hp_state := 0
	if m.hp <= m.max_hp / 4:
		hp_state = 2
	elif m.hp <= m.max_hp * 6 / 10:
		hp_state = 1
	var line: String = ["I'm doing fine! Let's keep going!", "Ow... That hurt. But I can keep going.", "I'm... in bad shape... Please help me..."][hp_state]
	await say(root, "%s: %s" % [name_of(x), line], m.sp)

## Red's Team window: ★ marks the leader, the heart shows the HP quarter. Commands: Summary, Moves,
## Talk (others, in a dungeon), Check IQ, Tactics (others). Loops until B. Returns {use, chain, user}
## when the leader's Moves -> Use was picked.
static func team_menu(root: Control, members: Array, in_dungeon := false, dungeon = null) -> Dictionary:
	if members.is_empty():
		return {}
	var sel := 0
	while true:
		var rows: Array = []
		for x in members:
			var m := as_mon(x)
			var guest: bool = x is Mon and (x.get_meta("escort", false) or x.side == "client")
			rows.append({"text": name_of(x), "icon": icon("star") if is_leader(x, dungeon) else icon("blank"),
				"right_icon": true, "right": "", "hp": [m.hp, m.max_hp, guest]})
		var tname := Game.team_name if Game.team_name != "" else "Team"
		var m2 := menu(tname, rows, 200)
		m2.sel = sel
		m2.max_rows = 6
		m2.keep_on_pick = true
		var hearts: Array = []
		m2.ready.connect(func():
			for k in m2._rows.size():
				var hb: HBoxContainer = m2._rows[k]
				var hp: Array = rows[k].hp
				var tr := TextureRect.new()
				tr.texture = TeamScreens.heart_for(int(hp[0]), int(hp[1]), bool(hp[2]))
				tr.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hb.add_child(tr)
				hearts.append(tr))
		var r := await run_menu(root, m2, Vector2(WIN_X, WIN_Y))
		if r.act != "pick":
			return {}
		sel = r.i
		var x = members[r.i]
		var lead := is_leader(x, dungeon)
		var opts: Array = ["Summary", "Moves"]
		if not lead and in_dungeon:
			opts.append("Talk")
		opts.append("Check IQ")
		if not lead:
			opts.append("Tactics")
		# Red post-game (QUEST_CAN_CHANGE_LEADER): pick another team member to lead
		if not lead and not in_dungeon and x in Game.team and Game.story.has("vars") and GVars.quest(GVars.QUEST_CAN_CHANGE_LEADER):
			opts.append("Make Leader")
		var c := await submenu(root, m2, opts, r.i)
		match c:
			"Summary":
				await summary(root, x)
			"Moves":
				var a := await moves_menu(root, x, in_dungeon, dungeon, members)
				if not a.is_empty():
					return a
			"Talk":
				await talk(root, x)
			"Check IQ":
				await iq_menu(root, x)
			"Tactics":
				await tactics_menu(root, x)
			"Make Leader":
				make_leader(x)
				Audio.sfx("join")
				await Dialog.say(root, "%s became the leader." % name_of(x))
				return {"leader_changed": true}
		if auto_on():
			return {}
	return {}

## Red's "Which?" window (ShowDungeonToWhichMonMenu): pick a team member. Returns the index or -1.
static func which_member(root: Control, members: Array, title := "Which?", disabled: Array = []) -> int:
	var rows: Array = []
	for k in members.size():
		var x = members[k]
		rows.append({"text": name_of(x), "icon": icon("star") if is_leader(x) else icon("blank"), "disabled": k in disabled})
	var m := menu(title, rows, 200)
	var r := await run_menu(root, m, Vector2(WIN_X + 40, WIN_Y + 24))
	return r.i if r.act == "pick" else -1
