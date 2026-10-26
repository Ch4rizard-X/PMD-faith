class_name WonderMailUI
extends RefCounted
## Wonder Mail screens (PMD Red: wonder_mail_main_menu.c password entry + naming_screen.c NAMING_PASSWORD2).
##
##   await WonderMailUI.enter_code(root)   # Red's password screen: 24 slots in two rows of 12, symbol grid
##   await WonderMailUI.maker(root)        # "Make Wonder Mail": build a mission and get its 24-symbol code
##
## Both work with touch (tap symbols / rows / buttons), keyboard (type the symbols, arrows, Enter, Backspace,
## Esc, Ctrl+V) and gamepad (D-pad, A, B). Layout fits the 480x270 UI at Red's 22 px font.

const CYAN := "#7fe0ff"
## Symbol grid of the entry screen: digits, letters, then the other symbols (all 32 of WonderMail.CHARSET).
const GRID := "12345678" + "90CFHJKM" + "NPQRSTWX" + "Y?!+-…♂♀"
const GRID_COLS := 8
const CMDS := ["Del", "Paste", "Cancel", "End"]
const KIND_NAMES := {"rescue": "Rescue client", "target": "Rescue target", "escort": "Escort client", "find": "Find item", "deliver": "Deliver item"}

# ============================================================================ entry
## Password entry. On a correct password the mail is shown and added to the Job List (Red's checks: already in
## the list, already completed, list full). Returns the received job ({} if none).
static func enter_code(root: Control) -> Dictionary:
	# Red: "Please enter the Wonder Mail password." -> naming screen in password mode (NAMING_PASSWORD2,
	# scripts/ui/naming_screen.gd) -> "This password is incorrect. Would you like to enter it again?"
	var got := {}
	var code := ""
	await Dialog.say(root, "Please enter the\n[color=%s]Wonder Mail password[/color]." % CYAN)
	while true:
		code = await NamingScreen.ask(root, NamingScreen.PASSWORD2, code, true)
		if code == "":
			break
		var r: Dictionary = WonderMail.decode(code)
		if not r.ok:
			Audio.sfx("error")
			var again := await Dialog.ask(root, str(r.error) + "\nWould you like to enter it again?", ["Yes", "No"])
			if again == 0:
				continue
			break
		var job: Dictionary = r.job
		await Board.show_info(root, job)
		var why := WonderMail.receive(job)
		if why == "":
			Audio.sfx("join")
			await Dialog.say(root, WonderMail.MSG_RECEIVED)
			await Dialog.say(root, WonderMail.MSG_ADDED)
			got = Missions.find_job(str(job.id))
		else:
			Audio.sfx("error")
			await Dialog.say(root, why)
		break
	return got

## The previous custom entry panel (typing / paste); kept for reference, enter_code() uses NamingScreen now.
static func enter_code_panel(root: Control) -> Dictionary:
	var got := {}
	var v := CodeEntry.new()
	root.add_child(v)
	while true:
		var code: String = await v.choose()
		if code == "":
			break
		var r: Dictionary = WonderMail.decode(code)
		v.active = false
		if not r.ok:
			Audio.sfx("error")
			var again := await Dialog.ask(root, str(r.error) + "\nWould you like to enter it again?", ["Yes", "No"])
			if again == 0:
				continue
			break
		v.visible = false
		var job: Dictionary = r.job
		await Board.show_info(root, job)
		var why := WonderMail.receive(job)
		if why == "":
			Audio.sfx("join")
			await Dialog.say(root, WonderMail.MSG_RECEIVED)
			await Dialog.say(root, WonderMail.MSG_ADDED)
			got = Missions.find_job(str(job.id))
		else:
			Audio.sfx("error")
			await Dialog.say(root, why)
		break
	v.queue_free()
	return got

# ============================================================================ maker
## Make Wonder Mail: job type -> dungeon -> floor -> client -> target / item -> reward -> code.
## Cancel on any step goes back one step.
static func maker(root: Control) -> void:
	var st := {"step": 0, "all": false, "kind": "", "d": -1, "floor": 0, "client": "", "target": "", "item": "",
		"rtype": "", "ritem": "", "area": ""}
	var steps := ["kind", "dungeon", "floor", "client", "target", "item", "reward", "ritem", "area", "result"]
	var back: Array = []
	var i := 0
	while i >= 0 and i < steps.size():
		var s: String = steps[i]
		var res = await _maker_step(root, s, st)
		if res == null:                    # cancelled -> previous step
			if back.is_empty():
				return
			i = back.pop_back()
		elif res is String and res == "skip":
			i += 1
		elif res is String and res == "again":
			pass
		elif res is String and res == "exit":
			return
		else:
			back.append(i)
			i += 1

## One step; returns null (back), "skip" (not needed), "again" (redo) or a value.
static func _maker_step(root: Control, s: String, st: Dictionary) -> Variant:
	match s:
		"kind":
			var items: Array = []
			for k in WonderMail.KINDS:
				items.append({"text": KIND_NAMES[k], "value": k})
			var v = await _pick(root, "Make Wonder Mail: job type", items, items.map(func(x): return x.value).find(st.kind))
			if v != null:
				st.kind = v
			return v
		"dungeon":
			var items: Array = []
			var cur := 0
			for d in WonderMail.wm_dungeons():
				var key := WonderMail.dungeon_key(d)
				if not st.all and not key in Game.unlocked:
					continue
				if not st.kind in WonderMail.wm_kinds(d):
					continue
				if d == st.d:
					cur = items.size()
				var fl: Array = WonderMail.wm_floors(d)
				items.append({"text": Missions.dungeon_name(key), "value": d, "hint": "%d-%dF" % [fl.front(), fl.back()]})
			var tog := "All dungeons: %s" % ("On" if st.all else "Off")
			if items.is_empty() and not st.all:
				items.append({"text": "(no unlocked dungeon fits)", "value": -1, "disabled": true})
			var v = await _pick(root, "Dungeon", items, cur, false, tog)
			if v is String and v == PickList.TOGGLE:
				st.all = not st.all
				return "again"
			if v != null:
				st.d = int(v)
			return v
		"floor":
			var items: Array = []
			var cur := 0
			var key := WonderMail.dungeon_key(st.d)
			for fl in WonderMail.wm_floors(st.d):
				if fl == st.floor:
					cur = items.size()
				var diff := WonderMail.mission_difficulty(st.d, fl, WonderMail.kind_index(st.kind))
				items.append({"text": Missions.floor_label(key, fl), "value": fl, "hint_bb": Missions.difficulty_bb(WonderMail.DIFF_LETTERS[WonderMail.letter_index(diff)])})
			var v = await _pick(root, Missions.dungeon_name(key), items, cur)
			if v != null:
				st.floor = int(v)
			return v
		"client":
			var v = await _pick_species(root, "Client", st.client)
			if v != null:
				st.client = v
			return v
		"target":
			if st.kind != "target" and st.kind != "escort":
				st.target = ""
				return "skip"
			var v = await _pick_species(root, "Target (who to save)" if st.kind == "target" else "Escort to", st.target)
			if v != null:
				st.target = v
			return v
		"item":
			if st.kind != "find" and st.kind != "deliver":
				st.item = ""
				return "skip"
			var v = await _pick_item(root, "Item to find" if st.kind == "find" else "Item to deliver", WonderMail.wm_target_items(st.d, st.kind), st.item)
			if v != null:
				st.item = v
			return v
		"reward":
			var diff := WonderMail.mission_difficulty(st.d, st.floor, WonderMail.kind_index(st.kind))
			var li := WonderMail.letter_index(diff)
			var m1 := (li + 1) * 100
			var m2 := (li + 1) * 200
			var items := [
				{"text": "%d Poké" % m1, "value": "money"},
				{"text": "%d Poké + ?" % m1, "value": "money_extra"},
				{"text": "Item", "value": "item"},
				{"text": "Item + ?", "value": "item_extra"},
				{"text": "%d Poké" % m2, "value": "money1", "hint": "mailbox"},
				{"text": "%d Poké + ?" % m2, "value": "money1_extra", "hint": "mailbox"},
				{"text": "Item", "value": "item1", "hint": "mailbox"},
				{"text": "Item + ? + ?", "value": "item1_extra", "hint": "mailbox"},
			]
			var fa_ok := not WonderMail.wm_friend_areas(st.d, st.floor, st.kind).is_empty()
			items.append({"text": "Friend Area", "value": "friend_area", "disabled": not fa_ok, "hint": "" if fa_ok else "needs D+"})
			var cur: int = maxi(0, items.map(func(x): return x.value).find(st.rtype))
			var v = await _pick(root, "Reward  (%s, %d pts)" % [WonderMail.DIFF_LETTERS[li], WonderMail.RANK_POINTS[diff]], items, cur)
			if v != null:
				st.rtype = v
			return v
		"ritem":
			if not st.rtype in ["money_extra", "item", "item_extra", "money1_extra", "item1", "item1_extra"]:
				st.ritem = ""
				return "skip"
			var v = await _pick_item(root, "Reward item", WonderMail.wm_reward_items(), st.ritem)
			if v != null:
				st.ritem = v
			return v
		"area":
			if st.rtype != "friend_area":
				st.area = ""
				return "skip"
			var items: Array = []
			for a in WonderMail.wm_friend_areas(st.d, st.floor, st.kind):
				items.append({"text": Missions._area_name(a), "value": a, "hint": "owned" if a in Game.friend_areas else ""})
			var v = await _pick(root, "Friend Area", items, maxi(0, items.map(func(x): return x.value).find(st.area)))
			if v != null:
				st.area = v
			return v
		"result":
			var fields := {"kind": st.kind, "dungeon": st.d, "floor": st.floor, "client": st.client, "target": st.target,
				"item": st.item, "reward": {"type": st.rtype, "item": st.ritem, "friend_area": st.area}}
			var r := await _show_result(root, fields)
			return null if r == "back" else "exit"
	return null

static func _pick(root: Control, title: String, items: Array, cur := 0, search := false, toggle := "") -> Variant:
	var p := PickList.new()
	p.title = title
	p.items = items
	p.sel = maxi(cur, 0)
	p.search = search
	p.toggle_text = toggle
	root.add_child(p)
	var v = await p.choose()
	p.queue_free()
	return v

static func _pick_species(root: Control, title: String, cur: String) -> Variant:
	var items: Array = []
	var ci := 0
	for k in WonderMail.wm_species():
		if k == cur:
			ci = items.size()
		items.append({"text": "%s %s" % [k.substr(1), Missions.sp_name(k)], "value": k})
	return await _pick(root, title, items, ci, true)

static func _pick_item(root: Control, title: String, keys: Array, cur: String) -> Variant:
	var items: Array = []
	var ci := 0
	for k in keys:
		if k == cur:
			ci = items.size()
		items.append({"text": DB.item_name(k), "value": k})
	return await _pick(root, title, items, ci, true)

## The code page. Returns "back" (edit the mission again) or "done".
static func _show_result(root: Control, fields: Dictionary) -> String:
	var v := ResultView.new()
	v.fields = fields
	root.add_child(v)
	var out := "done"
	while true:
		var a: String = await v.choose()
		match a:
			"add":
				var why := WonderMail.receive(v.job)
				if why == "":
					Audio.sfx("join")
					await Dialog.say(root, WonderMail.MSG_ADDED)
					v.added = true
				else:
					Audio.sfx("error")
					await Dialog.say(root, why)
				v.refresh_buttons()
			"copy":
				DisplayServer.clipboard_set(v.code)
				Audio.sfx("confirm")
				v.flash_copied()
			"new":
				v.reroll()
			"back":
				out = "back"
				break
			_:
				break
	v.queue_free()
	return out

static func _blocked_by_overlay(me: Control) -> bool:
	if not me.is_visible_in_tree():
		return true
	var p := me.get_parent()
	if p == null:
		return true
	var after := false
	for c in p.get_children():
		if c == me:
			after = true
			continue
		if c is ListMenu or c is Board.InfoView:
			return true
		if c is Dialog and c.panel and c.panel.visible:
			return true
		if after and (c is PickList or c is CodeEntry or c is ResultView) and c.visible:
			return true
	return false

static func _style_sel() -> StyleBoxFlat:
	var s := UITheme.box(0.95)
	s.bg_color = Color(0.2, 0.32, 0.72, 0.95)
	s.set_content_margin_all(0)
	return s

static func _style_cell() -> StyleBoxFlat:
	var s := UITheme.box(0.5)
	s.set_content_margin_all(0)
	s.border_color = Color(UITheme.WIN_EDGE.r, UITheme.WIN_EDGE.g, UITheme.WIN_EDGE.b, 0.35)
	s.shadow_size = 0
	return s

static func _full_panel(p: Control) -> void:
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 3 * UITheme.PX
	p.offset_right = -3 * UITheme.PX
	p.offset_top = 3 * UITheme.PX
	p.offset_bottom = -3 * UITheme.PX

# ============================================================================ code display
## 24 symbols in two rows of 12, grouped 4 white / 4 yellow / 4 white like Red's password window.
class CodeView extends Control:
	var code := ""
	var scale_px := 2              # font pixel scale: 2 -> 22 px, 3 -> 33 px
	var cursor := -1               # entry slot cursor (-1 = none)
	var cell_w := 22
	var group_gap := 8
	var row_h := 28
	signal slot_tapped(i: int)

	func _init(px := 2) -> void:
		scale_px = px
		cell_w = 11 * px
		group_gap = 4 * px
		row_h = 13 * px
		custom_minimum_size = Vector2(12 * cell_w + 2 * group_gap, 2 * row_h + 2 * px)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func set_code(c: String) -> void:
		code = c
		queue_redraw()

	func _slot_pos(i: int) -> Vector2:
		var r := i / 12
		var c := i % 12
		var x := (size.x - custom_minimum_size.x) / 2.0 + c * cell_w + (c / 4) * group_gap
		var y := r * row_h + (scale_px if (c / 4) == 1 else 0)
		return Vector2(x, y)

	func _draw() -> void:
		var f := UITheme.font()
		var fs := 11 * scale_px
		for i in 24:
			var p := _slot_pos(i)
			var col := UITheme.GOLD if (i % 12) / 4 == 1 else UITheme.INK
			if i == cursor:
				draw_rect(Rect2(p + Vector2(scale_px, 0), Vector2(cell_w - 2 * scale_px, row_h - scale_px)), Color(0.25, 0.4, 0.85, 0.85))
			# Red's double underscore under every slot
			draw_rect(Rect2(p + Vector2(scale_px, row_h - 3 * scale_px), Vector2(cell_w - 2 * scale_px, scale_px)), Color(col.r, col.g, col.b, 0.75))
			if i < code.length():
				var g := WonderMail.font_glyph(code[i])
				var w := f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var base := p + Vector2((cell_w - w) / 2.0, row_h - 4 * scale_px)
				draw_string(f, base + Vector2(1, 1) * scale_px, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.SHADOW)
				draw_string(f, base, g, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for i in 24:
				if Rect2(_slot_pos(i), Vector2(cell_w + 2, row_h)).has_point(e.position):
					slot_tapped.emit(i)
					accept_event()
					return

# ============================================================================ entry screen
class CodeEntry extends PanelContainer:
	signal entered(code: String)
	var text: Array = []           # 24 slots ("" = empty)
	var pos := 0                   # slot cursor
	var sel := 0                   # focused cell: 0..31 symbols, 32.. commands
	var active := false
	var _view: CodeView
	var _cells: Array = []
	var _count: Label
	var _st_sel: StyleBoxFlat
	var _st_cell: StyleBoxFlat

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		WonderMailUI._full_panel(self)
		text.resize(24)
		text.fill("")
		_st_sel = WonderMailUI._style_sel()
		_st_cell = WonderMailUI._style_cell()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", UITheme.PX)
		add_child(vb)
		var head := HBoxContainer.new()
		vb.add_child(head)
		var t := Board.rich("Please enter the [color=%s]Wonder Mail password[/color]." % WonderMailUI.CYAN)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		_count = Board.label("0/24", UITheme.INK_DIM)
		head.add_child(_count)
		_view = CodeView.new(2)
		_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_view.slot_tapped.connect(func(i):
			if _blocked(): return
			pos = mini(i, _len())
			Audio.sfx("cursor")
			_refresh())
		vb.add_child(_view)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4 * UITheme.PX)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_child(hb)
		var grid := GridContainer.new()
		grid.columns = WonderMailUI.GRID_COLS
		grid.add_theme_constant_override("h_separation", UITheme.PX)
		grid.add_theme_constant_override("v_separation", UITheme.PX)
		hb.add_child(grid)
		for i in WonderMailUI.GRID.length():
			var b := _cell(WonderMailUI.GRID[i], Vector2(15, 12) * UITheme.PX, i)
			b.text = WonderMail.font_glyph(WonderMailUI.GRID[i])
			grid.add_child(b)
		var cmd := VBoxContainer.new()
		cmd.add_theme_constant_override("separation", UITheme.PX)
		hb.add_child(cmd)
		for k in WonderMailUI.CMDS.size():
			var b := _cell(WonderMailUI.CMDS[k], Vector2(34, 12) * UITheme.PX, 32 + k)
			b.text = WonderMailUI.CMDS[k]
			cmd.add_child(b)
		var hint := Board.label("Type or tap the symbols. Enter = End.", UITheme.INK_DIM)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(hint)
		_refresh()

	func _cell(_t: String, sz: Vector2, idx: int) -> Button:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = sz
		b.add_theme_constant_override("h_separation", 0)
		b.pressed.connect(func():
			if _blocked(): return
			sel = idx
			_press())
		_cells.append(b)
		return b

	func choose() -> String:
		active = true
		visible = true
		var c: String = await entered
		active = false
		return c

	func _len() -> int:
		var n := 0
		for s in text:
			if s != "":
				n += 1
		return n

	func code() -> String:
		return "".join(PackedStringArray(text))

	func _refresh() -> void:
		_view.set_code(code())
		_view.cursor = pos if pos < 24 else -1
		_view.queue_redraw()
		_count.text = "%d/24" % _len()
		for i in _cells.size():
			var b: Button = _cells[i]
			var st := _st_sel if i == sel else _st_cell
			for k in ["normal", "hover", "pressed", "disabled"]:
				b.add_theme_stylebox_override(k, st)
			if i == 35:
				b.add_theme_color_override("font_color", UITheme.GOLD if _len() == 24 else UITheme.INK_DIM)

	func _put(ch: String) -> void:
		if pos >= 24:
			Audio.sfx("error")
			return
		text[pos] = ch
		pos += 1
		Audio.sfx("cursor")
		if _len() == 24:
			sel = 35               # Red moves the cursor to END when the last slot is filled
		_refresh()

	## Backspace: removes the symbol left of the cursor (or under it at slot 1) and closes the gap.
	func _del() -> void:
		if pos > 0:
			pos -= 1
		elif text[0] == "":
			Audio.sfx("error")
			return
		var rest: Array = text.slice(pos + 1)
		for k in range(pos, 24):
			text[k] = rest[k - pos] if k - pos < rest.size() else ""
		Audio.sfx("cancel")
		_refresh()

	func _paste() -> void:
		var s := WonderMail.normalize(DisplayServer.clipboard_get())
		var n := 0
		for ch in s:
			if WonderMail.symbol_value(ch) >= 0 or ch == "*" or ch == "/":
				if pos < 24:
					text[pos] = ch
					pos += 1
					n += 1
		if n == 0:
			Audio.sfx("error")
		else:
			Audio.sfx("confirm")
			if _len() == 24:
				sel = 35
		_refresh()

	func set_text(s: String) -> void:
		text.fill("")
		pos = 0
		for ch in WonderMail.normalize(s):
			if pos < 24:
				text[pos] = ch
				pos += 1
		_refresh()

	func _press() -> void:
		if sel < 32:
			_put(WonderMailUI.GRID[sel])
			return
		match WonderMailUI.CMDS[sel - 32]:
			"Del": _del()
			"Paste": _paste()
			"Cancel": _finish("")
			"End": _end()

	func _end() -> void:
		if _len() != 24:
			Audio.sfx("error")       # Red: END only works with all 24 symbols
			return
		_finish(code())

	func _finish(c: String) -> void:
		if not active:
			return
		active = false
		Audio.sfx("confirm" if c != "" else "cancel")
		entered.emit(c)

	func _blocked() -> bool:
		return not active or WonderMailUI._blocked_by_overlay(self)

	func _move(dx: int, dy: int) -> void:
		var cols := WonderMailUI.GRID_COLS
		if sel < 32:
			var r := sel / cols
			var c := sel % cols
			if dx != 0:
				c += dx
				if c >= cols:
					sel = 32 + r
				elif c < 0:
					sel = 32 + r
				else:
					sel = r * cols + c
			else:
				sel = ((r + dy + 4) % 4) * cols + c
		else:
			var k := sel - 32
			if dx > 0:
				sel = k * cols
			elif dx < 0:
				sel = k * cols + cols - 1
			else:
				sel = 32 + (k + dy + 4) % 4
		Audio.sfx("cursor")
		_refresh()

	func _unhandled_input(e: InputEvent) -> void:
		if _blocked():
			return
		if e is InputEventKey and e.pressed:
			var k: InputEventKey = e
			if k.keycode == KEY_BACKSPACE:
				_del()
				get_viewport().set_input_as_handled()
				return
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				if _len() == 24:
					_end()
				else:
					_press()
				get_viewport().set_input_as_handled()
				return
			if k.keycode == KEY_V and (k.ctrl_pressed or k.meta_pressed):
				_paste()
				get_viewport().set_input_as_handled()
				return
			if k.unicode > 32 and not k.echo:
				var ch := WonderMail.normalize(char(k.unicode))
				if ch.length() == 1 and (WonderMail.symbol_value(ch) >= 0 or ch == "*" or ch == "/"):
					_put(ch)
				else:
					Audio.sfx("error")
				get_viewport().set_input_as_handled()
				return
		if e.is_action_pressed("ui_right"):
			_move(1, 0)
		elif e.is_action_pressed("ui_left"):
			_move(-1, 0)
		elif e.is_action_pressed("ui_down"):
			_move(0, 1)
		elif e.is_action_pressed("ui_up"):
			_move(0, -1)
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			_press()
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			if _len() > 0:
				_del()                 # Red: B deletes, B on an empty password leaves
			else:
				_finish("")
		else:
			return
		get_viewport().set_input_as_handled()

# ============================================================================ scrolling pick list
class PickList extends PanelContainer:
	const TOGGLE := "__toggle__"
	signal done(v: Variant)
	var title := ""
	var items: Array = []          # [{text, value, hint?, hint_bb?, disabled?}]
	var search := false
	var toggle_text := ""
	var sel := 0
	var _shown: Array = []         # indices into items after the filter
	var _rows: Array = []
	var _box: VBoxContainer
	var _scroll: ScrollContainer
	var _filter: LineEdit
	var _count: Label
	var _done := false
	var _press_pos := Vector2.ZERO
	var _st_sel: StyleBoxFlat

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		WonderMailUI._full_panel(self)
		_st_sel = WonderMailUI._style_sel()
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", UITheme.PX)
		add_child(vb)
		var head := HBoxContainer.new()
		vb.add_child(head)
		var t := Board.label(title, UITheme.GOLD)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		head.add_child(t)
		_count = Board.label("", UITheme.INK_DIM)
		head.add_child(_count)
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 3 * UITheme.PX)
		if search or toggle_text != "":
			vb.add_child(bar)
		if search:
			_filter = LineEdit.new()
			_filter.placeholder_text = "Search (type a name or number)"
			_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_filter.custom_minimum_size.y = UITheme.LINE + 2 * UITheme.PX
			var sb := UITheme.box(0.6)
			sb.content_margin_top = 0
			sb.content_margin_bottom = 0
			sb.shadow_size = 0
			_filter.add_theme_stylebox_override("normal", sb)
			_filter.add_theme_stylebox_override("focus", sb)
			_filter.add_theme_color_override("font_placeholder_color", UITheme.INK_DIM)
			_filter.add_theme_font_size_override("font_size", UITheme.FONT_SIZE)
			_filter.text_changed.connect(func(_s): _apply_filter())
			_filter.text_submitted.connect(func(_s): _pick_sel())
			bar.add_child(_filter)
		if toggle_text != "":
			var b := Button.new()
			b.text = toggle_text
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size.y = UITheme.LINE + 2 * UITheme.PX
			b.pressed.connect(func(): _finish(TOGGLE))
			bar.add_child(b)
			var hint := Board.label("(Tab)", UITheme.INK_DIM)
			bar.add_child(hint)
		var sep := ColorRect.new()
		sep.color = UITheme.WIN_EDGE
		sep.custom_minimum_size = Vector2(0, UITheme.PX)
		vb.add_child(sep)
		_scroll = ScrollContainer.new()
		_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.scroll_deadzone = 6
		vb.add_child(_scroll)
		_box = VBoxContainer.new()
		_box.add_theme_constant_override("separation", 0)
		_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(_box)
		_apply_filter(sel)

	func choose() -> Variant:
		var v = await done
		return v

	func _apply_filter(want := -1) -> void:
		var q := _filter.text.strip_edges().to_lower() if _filter else ""
		var keep_item: int = _shown[sel] if want < 0 and sel < _shown.size() else want
		_shown.clear()
		for i in items.size():
			if q == "" or str(items[i].text).to_lower().contains(q) or str(items[i].get("value", "")).to_lower().contains(q):
				_shown.append(i)
		for r in _rows:
			r.queue_free()
		_rows.clear()
		for n in _shown.size():
			_rows.append(_make_row(items[_shown[n]], n))
		sel = maxi(0, _shown.find(keep_item))
		_count.text = "%d" % _shown.size() if _shown.size() != items.size() else "%d" % items.size()
		_update_sel()

	func _make_row(it: Dictionary, n: int) -> Control:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.custom_minimum_size.y = UITheme.LINE
		row.gui_input.connect(_row_input.bind(n))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2 * UITheme.PX)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hb)
		var cur := TextureRect.new()
		cur.texture = ListMenu._cursor_icon()
		cur.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cur.custom_minimum_size = Vector2(8 * UITheme.PX, UITheme.LINE)
		cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta("cur", cur)
		hb.add_child(cur)
		var l := Board.label(str(it.text), UITheme.INK_DIM if it.get("disabled", false) else UITheme.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		hb.add_child(l)
		if it.has("hint_bb"):
			var h := Board.rich("[right]%s[/right]" % it.hint_bb, 20 * UITheme.PX)
			hb.add_child(h)
		elif str(it.get("hint", "")) != "":
			hb.add_child(Board.label(str(it.hint), UITheme.INK_DIM))
		var pad := Control.new()           # keep clear of the scroll bar
		pad.custom_minimum_size.x = 5 * UITheme.PX
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(pad)
		_box.add_child(row)
		return row

	func _update_sel() -> void:
		for n in _rows.size():
			var r: Control = _rows[n]
			(r.get_meta("cur") as Control).modulate.a = 1.0 if n == sel else 0.0
			r.add_theme_stylebox_override("panel", _st_sel if n == sel else StyleBoxEmpty.new())
		if sel < _rows.size():
			_scroll.ensure_control_visible.call_deferred(_rows[sel])

	func _move(d: int) -> void:
		if _shown.is_empty():
			return
		var n := _shown.size()
		if absi(d) == 1:
			sel = (sel + d + n) % n
		else:
			sel = clampi(sel + d, 0, n - 1)
		Audio.sfx("cursor")
		_update_sel()

	func _pick_sel() -> void:
		if sel >= _shown.size():
			Audio.sfx("error")
			return
		var it: Dictionary = items[_shown[sel]]
		if it.get("disabled", false):
			Audio.sfx("error")
			return
		_finish(it.get("value"))

	func _finish(v: Variant) -> void:
		if _done:
			return
		_done = true
		Audio.sfx("cancel" if v == null else "confirm")
		done.emit(v)

	func _blocked() -> bool:
		return _done or WonderMailUI._blocked_by_overlay(self)

	func _row_input(e: InputEvent, n: int) -> void:
		if _blocked():
			return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_press_pos = e.global_position
			elif e.global_position.distance_to(_press_pos) < 8 * UITheme.PX:
				sel = n
				_update_sel()
				_pick_sel()
		elif e is InputEventMouseMotion and e.button_mask == 0 and n != sel and _rows.size() < 40:
			sel = n
			_update_sel()

	func _unhandled_input(e: InputEvent) -> void:
		if _blocked():
			return
		if e is InputEventKey and e.pressed:
			var k: InputEventKey = e
			if k.keycode == KEY_TAB and toggle_text != "":
				_finish(TOGGLE)
				get_viewport().set_input_as_handled()
				return
			if _filter and not _filter.has_focus():
				if k.keycode == KEY_BACKSPACE and _filter.text != "":
					_filter.text = _filter.text.substr(0, _filter.text.length() - 1)
					_apply_filter()
					get_viewport().set_input_as_handled()
					return
				if k.unicode > 32 and not (k.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]):
					_filter.text += char(k.unicode)
					_apply_filter()
					get_viewport().set_input_as_handled()
					return
		if e.is_action_pressed("ui_down", true):
			_move(1)
		elif e.is_action_pressed("ui_up", true):
			_move(-1)
		elif e.is_action_pressed("ui_right", true) or e.is_action_pressed("ui_page_down", true):
			_move(8)
		elif e.is_action_pressed("ui_left", true) or e.is_action_pressed("ui_page_up", true):
			_move(-8)
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			_pick_sel()
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			if _filter and _filter.text != "":
				_filter.text = ""
				_filter.release_focus()
				_apply_filter()
			else:
				_finish(null)
		else:
			return
		get_viewport().set_input_as_handled()

	func _gui_input(e: InputEvent) -> void:
		if not _blocked() and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_finish(null)
			accept_event()

# ============================================================================ result (code) page
class ResultView extends PanelContainer:
	signal chosen(a: String)
	var fields: Dictionary = {}
	var job: Dictionary = {}
	var code := ""
	var added := false
	var sel := 0
	var active := false
	var _view: CodeView
	var _info: RichTextLabel
	var _title: RichTextLabel
	var _btns: Array = []
	var _acts := ["add", "copy", "new", "back"]
	var _st_sel: StyleBoxFlat
	var _st_cell: StyleBoxFlat

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		WonderMailUI._full_panel(self)
		_st_sel = WonderMailUI._style_sel()
		_st_cell = WonderMailUI._style_cell()
		for st in [_st_sel, _st_cell]:
			st.content_margin_left = 4 * UITheme.PX
			st.content_margin_right = 4 * UITheme.PX
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", UITheme.PX)
		add_child(vb)
		_title = Board.rich("")
		vb.add_child(_title)
		var sep := ColorRect.new()
		sep.color = UITheme.WIN_EDGE
		sep.custom_minimum_size = Vector2(0, UITheme.PX)
		vb.add_child(sep)
		_info = Board.rich("")
		_info.custom_minimum_size.y = 3 * UITheme.LINE
		vb.add_child(_info)
		_view = CodeView.new(3)
		_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(_view)
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 3 * UITheme.PX)
		vb.add_child(hb)
		var names := ["Add to Job List", "Copy code", "New code", "Edit"]
		for i in names.size():
			var b := Button.new()
			b.text = names[i]
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size.y = UITheme.LINE + 2 * UITheme.PX
			b.pressed.connect(func():
				if _blocked(): return
				sel = i
				_press())
			hb.add_child(b)
			_btns.append(b)
		_build()

	func _build() -> void:
		var e: Dictionary = WonderMail.encode_ex(fields)
		if not e.ok:
			code = ""
			job = {}
			_title.text = "[color=#ff8070]Red would refuse this mail:[/color]"
			_info.text = str(e.error)
			_view.set_code("")
			refresh_buttons()
			return
		code = e.code
		fields["seed"] = int(e.raw.seed)
		job = WonderMail.decode(code).job
		added = false
		_title.text = "[color=%s]%s[/color]  %s" % [Missions.HL, str(job.title), Missions.difficulty_bb(str(job.difficulty))]
		var who := "[color=%s]%s[/color]" % [Missions.HL, Missions.sp_name(str(job.client))]
		var obj := str(job.get("objective", ""))
		_info.text = "%s  %s\n%s\nReward: %s  (+%d pts)" % [who, str(job.place), obj, Missions.reward_text(job), int(job.reward.rank_points)]
		_view.set_code(code)
		refresh_buttons()

	func reroll() -> void:
		fields["seed"] = randi() & 0xffffff
		Audio.sfx("confirm")
		_build()

	func refresh_buttons() -> void:
		for i in _btns.size():
			var b: Button = _btns[i]
			var dis := code == "" and i < 3
			if i == 0:
				dis = dis or added
				b.text = "Added" if added else "Add to Job List"
			b.add_theme_color_override("font_color", UITheme.INK_DIM if dis else UITheme.INK)
			for k in ["normal", "hover", "pressed", "disabled"]:
				b.add_theme_stylebox_override(k, _st_sel if i == sel else _st_cell)

	func flash_copied() -> void:
		var b: Button = _btns[1]
		b.text = "Copied!"
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(b):
			b.text = "Copy code"

	func choose() -> String:
		active = true
		var a: String = await chosen
		active = false
		return a

	func _press() -> void:
		if not active:
			return
		if (code == "" and sel < 3) or (sel == 0 and added):
			Audio.sfx("error")
			return
		active = false
		chosen.emit(_acts[sel])

	func _blocked() -> bool:
		return not active or WonderMailUI._blocked_by_overlay(self)

	func _unhandled_input(e: InputEvent) -> void:
		if _blocked():
			return
		if e.is_action_pressed("ui_right") or e.is_action_pressed("ui_down"):
			sel = (sel + 1) % _btns.size()
			Audio.sfx("cursor")
			refresh_buttons()
		elif e.is_action_pressed("ui_left") or e.is_action_pressed("ui_up"):
			sel = (sel - 1 + _btns.size()) % _btns.size()
			Audio.sfx("cursor")
			refresh_buttons()
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			_press()
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			active = false
			Audio.sfx("cancel")
			chosen.emit("done")
		elif e is InputEventKey and e.pressed and e.keycode == KEY_C and (e.ctrl_pressed or e.meta_pressed):
			sel = 1
			_press()
		else:
			return
		get_viewport().set_input_as_handled()
