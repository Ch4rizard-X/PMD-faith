class_name PokedexUI
extends RefCounted
## The Pokédex screen from the base menu: filter menu -> species list (8 per page, sprite preview) ->
## entry page (portrait, types, Friend Area, recruit rate, dungeons + floors where it appears).
##
##   await PokedexUI.open(root)
##
## List: Up/Down move, Left/Right flip pages, Accept opens the entry, Cancel goes back.
## Entry: Left/Right flip its pages, Up/Down show the previous / next species of the list.

const PER_PAGE := 8
const FILTERS := ["All", "Seen", "Recruited", "By dungeon", "By Friend Area"]

static func open(root: Control) -> void:
	var fsel := 0
	while true:
		var c := Pokedex.counts()
		var lm := ListMenu.make("Pokédex  %d seen · %d recruited" % [c.seen, c.recruited], FILTERS + ["Close"])
		root.add_child(lm)
		lm.position = Vector2(8, 8)
		lm._set_sel(fsel)
		var f := await lm.choose()
		if f < 0 or f >= FILTERS.size():
			return
		fsel = f
		var list: Array = []
		var title: String = FILTERS[f]
		match f:
			0:
				list = Pokedex.species_list()
			1:
				list = Pokedex.species_list().filter(func(k): return Pokedex.is_seen(k))
			2:
				list = Pokedex.species_list().filter(func(k): return Pokedex.is_recruited(k))
			3:
				var dks: Array = Pokedex.dungeon_keys().filter(func(k): return k in Game.unlocked)
				if dks.is_empty():
					await Dialog.say(root, "You haven't been to any dungeons yet.")
					continue
				var names: Array = dks.map(func(k): return Services.dname(k))
				var di := await IQ.paged_choose(root, "Which dungeon?", names)
				if di < 0:
					continue
				title = Services.dname(dks[di])
				list = Pokedex.species_in(dks[di])
			4:
				var areas: Array = Services.fa().get("areas", {}).keys()
				areas.sort_custom(func(a, b): return Services.area_name(a) < Services.area_name(b))
				var names2: Array = areas.map(func(k): return ("%s (owned)" if k in Game.friend_areas else "%s") % Services.area_name(k))
				var ai := await IQ.paged_choose(root, "Which Friend Area?", names2)
				if ai < 0:
					continue
				title = Services.area_name(areas[ai])
				list = Pokedex.species_in_area(areas[ai])
		if list.is_empty():
			await Dialog.say(root, "No Pokémon to show here yet.")
			continue
		await browse(root, list, title)

## List view + entry pages for a list of species keys.
static func browse(root: Control, list: Array, title: String, start := 0) -> void:
	var v := DexList.new()
	v.list = list
	v.title = title
	v.sel = start
	root.add_child(v)
	while true:
		var i: int = await v.choose()
		if i < 0:
			break
		v.sel = await entry(root, list, i)
		v.refresh()
	v.queue_free()

## Shows the entry for list[i]; returns the index shown last (Up/Down move through the list).
static func entry(root: Control, list: Array, i: int) -> int:
	var cur := i
	var pg := 0
	while true:
		var e := DexEntry.new()
		e.sp = list[cur]
		e.page = pg
		e.list_pos = "%d/%d" % [cur + 1, list.size()]
		root.add_child(e)
		var r: String = await e.closed
		e.queue_free()
		match r:
			"prev":
				cur = (cur - 1 + list.size()) % list.size(); pg = 0
			"next":
				cur = (cur + 1) % list.size(); pg = 0
			"left":
				pg = (e.page - 1 + e.pages) % e.pages
			"right":
				pg = (e.page + 1) % e.pages
			_:
				return cur
	return cur

## Red's Pokémon list colours (code_8023144.c): white = you don't have its Friend Area yet, green = you have
## the Friend Area but haven't recruited it, cyan = recruited.
const LIST_GREEN := Color8(0x7f, 0xff, 0x7f)
const LIST_CYAN := Color8(0x7f, 0xe0, 0xff)

static func list_color(sp: String) -> Color:
	if Pokedex.is_recruited(sp):
		return LIST_CYAN
	if Services.area_of(sp) in Game.friend_areas:
		return LIST_GREEN
	return UITheme.INK

static func num(sp: String) -> String:
	return "#%03d" % int(sp.substr(0, 4))

static func dex_name(sp: String) -> String:
	return str(DB.species.get(sp, {}).get("name", "???")) if Pokedex.is_seen(sp) else "?????"

static func _blocked(self_node: Control) -> bool:
	if not self_node.is_visible_in_tree():
		return true
	var p := self_node.get_parent()
	if p == null:
		return true
	var after := false
	for c in p.get_children():
		if c == self_node:
			after = true
			continue
		if c is ListMenu or (c is Dialog and c.panel.visible) or (after and (c is DexEntry or c is DexList)):
			return true
	return false

static func _lbl(t: String, col := UITheme.INK) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

static func _rich(bb: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bb
	return r

static func _full(p: Control) -> void:
	p.theme = UITheme.theme()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.offset_left = 3 * UITheme.PX
	p.offset_right = -3 * UITheme.PX
	p.offset_top = 3 * UITheme.PX
	p.offset_bottom = -3 * UITheme.PX

static func _sep() -> ColorRect:
	var s := ColorRect.new()
	s.color = UITheme.WIN_EDGE
	s.custom_minimum_size = Vector2(0, UITheme.PX)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

# ============================================================================ list
class DexList extends PanelContainer:
	signal picked(i: int)
	var list: Array = []
	var title := ""
	var sel := 0
	var active := false
	var _rows: Array = []
	var _body: VBoxContainer
	var _page_lbl: Label
	var _stage: Control
	var _spr: MonSprite
	var _info: RichTextLabel
	var _auto_done := false

	func _ready() -> void:
		PokedexUI._full(self)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(head)
		var t := PokedexUI._lbl("Pokédex: %s" % title, UITheme.GOLD)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		head.add_child(t)
		_page_lbl = PokedexUI._lbl("")
		_page_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		_page_lbl.gui_input.connect(_page_tap)
		head.add_child(_page_lbl)
		head.add_child(TeamScreens.back_button(func(): if active: _emit(-1)))      # touch: leave the Pokédex
		vb.add_child(PokedexUI._sep())
		var hb := HBoxContainer.new()
		hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(hb)
		_body = VBoxContainer.new()
		_body.add_theme_constant_override("separation", 0)
		_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(_body)
		var right := VBoxContainer.new()
		right.custom_minimum_size.x = 160
		right.add_theme_constant_override("separation", 0)
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(right)
		_stage = Control.new()
		_stage.custom_minimum_size = Vector2(160, 104)
		_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(_stage)
		_info = PokedexUI._rich("")
		_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info.custom_minimum_size.x = 160
		right.add_child(_info)
		refresh()

	func page() -> int:
		return sel / PokedexUI.PER_PAGE

	func pages() -> int:
		return maxi(1, ceili(list.size() / float(PokedexUI.PER_PAGE)))

	func refresh() -> void:
		if _body == null:
			return
		sel = clampi(sel, 0, maxi(0, list.size() - 1))
		for c in _body.get_children():
			_body.remove_child(c)
			c.queue_free()
		_rows.clear()
		_page_lbl.text = ("%d/%d" % [page() + 1, pages()]) if pages() > 1 else ""
		var start := page() * PokedexUI.PER_PAGE
		for k in range(start, mini(start + PokedexUI.PER_PAGE, list.size())):
			var sp: String = list[k]
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", UITheme.PX * 2)
			row.custom_minimum_size.y = UITheme.LINE
			row.mouse_filter = Control.MOUSE_FILTER_STOP
			row.gui_input.connect(_row_input.bind(k))
			var cur := TextureRect.new()
			cur.texture = ListMenu._cursor_icon()
			cur.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			cur.custom_minimum_size = Vector2(8 * UITheme.PX, UITheme.LINE)
			cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cur.name = "Cursor"
			row.add_child(cur)
			var seen := Pokedex.is_seen(sp)
			var rec := Pokedex.is_recruited(sp)
			var col := PokedexUI.list_color(sp) if seen else UITheme.INK_DIM
			var n := PokedexUI._lbl(PokedexUI.num(sp), col)
			n.custom_minimum_size.x = 48
			row.add_child(n)
			var nm := PokedexUI._lbl(PokedexUI.dex_name(sp), col)
			row.add_child(nm)
			var mark := TextureRect.new()
			mark.texture = TeamScreens.icon("star") if rec else null
			mark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			mark.custom_minimum_size = Vector2(9 * UITheme.PX, UITheme.LINE)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(mark)
			var pad := Control.new()
			pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(pad)
			_body.add_child(row)
			_rows.append(row)
		_update_cursor()

	func _update_cursor() -> void:
		for j in _rows.size():
			_rows[j].get_node("Cursor").modulate.a = 1.0 if j == sel % PokedexUI.PER_PAGE else 0.0
		_preview()

	func _preview() -> void:
		if list.is_empty() or _stage == null:
			return
		var sp: String = list[sel]
		if _spr:
			_spr.queue_free()
			_spr = null
		var seen := Pokedex.is_seen(sp)
		var m := DB.make_mon(sp, 5, "team")
		_spr = MonSprite.new()
		_spr.scale = Vector2(2, 2)
		_stage.add_child(_spr)
		_spr.setup(m)
		_spr.position = Vector2(80, 78)
		if not seen:
			_spr.modulate = Color(0, 0, 0, 0.85)
		var S: Dictionary = DB.species.get(sp, {})
		var st := "[color=#ffdc4a]Recruited ×%d[/color]" % Pokedex.recruited_count(sp) if Pokedex.is_recruited(sp) else ("Seen" if seen else "[color=#9ea8c7]Not seen yet[/color]")
		_info.text = "[center]%s\n%s\n%s[/center]" % [PokedexUI.dex_name(sp), "/".join(S.get("types", [])) if seen else "", st]

	func _move(to: int) -> void:
		if list.is_empty():
			return
		var old := page()
		sel = (to + list.size()) % list.size()
		Audio.sfx("cursor")
		if page() != old:
			refresh()
		else:
			_update_cursor()

	func choose() -> int:
		active = true
		if ListMenu.auto:
			var pick := -1 if _auto_done else sel
			_auto_done = true
			(func(): _emit(pick)).call_deferred()
		var i: int = await picked
		active = false
		return i

	func _emit(i: int) -> void:
		if not active:
			return
		active = false
		Audio.sfx("confirm" if i >= 0 else "cancel")
		picked.emit.call_deferred(i)

	func _unhandled_input(e: InputEvent) -> void:
		if not active or PokedexUI._blocked(self):
			return
		var P := PokedexUI.PER_PAGE
		if e.is_action_pressed("ui_down"):
			_move(sel + 1)
		elif e.is_action_pressed("ui_up"):
			_move(sel - 1)
		elif e.is_action_pressed("ui_right"):
			if pages() > 1:
				_move(mini(list.size() - 1, (page() + 1) * P + sel % P) if page() + 1 < pages() else sel % P)
		elif e.is_action_pressed("ui_left"):
			if pages() > 1:
				_move((page() - 1) * P + sel % P if page() > 0 else mini(list.size() - 1, (pages() - 1) * P + sel % P))
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			_emit(sel)
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			_emit(-1)
		else:
			return
		get_viewport().set_input_as_handled()

	func _row_input(e: InputEvent, idx: int) -> void:
		if not active or PokedexUI._blocked(self):
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if sel == idx:
				_emit(idx)
			else:
				sel = idx
				Audio.sfx("cursor")
				_update_cursor()
			accept_event()

	func _page_tap(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and pages() > 1 and active:
			_move(((page() + 1) % pages()) * PokedexUI.PER_PAGE)
			accept_event()

	func _gui_input(e: InputEvent) -> void:
		if active and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_emit(-1)
			accept_event()

# ============================================================================ entry
class DexEntry extends PanelContainer:
	signal closed(r: String)
	var sp := "0001"
	var page := 0
	var pages := 1
	var list_pos := ""
	var _done := false
	const LOC_PER_PAGE := 6

	func _ready() -> void:
		PokedexUI._full(self)
		z_index = 5
		var seen := Pokedex.is_seen(sp)
		var locs: Array = Pokedex.locations(sp) if seen else []
		pages = 1 + ceili(locs.size() / float(LOC_PER_PAGE))
		page = clampi(page, 0, pages - 1)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(head)
		var t := PokedexUI._lbl("%s %s" % [PokedexUI.num(sp), PokedexUI.dex_name(sp)], UITheme.GOLD)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		head.add_child(PokedexUI._lbl(("%s  %d/%d" % [list_pos, page + 1, pages]) if pages > 1 else list_pos, UITheme.INK_DIM))
		vb.add_child(PokedexUI._sep())
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6 * UITheme.PX)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(hb)
		# portrait (silhouette while unseen)
		var frame := PanelContainer.new()
		var sb := UITheme.box()
		sb.set_content_margin_all(UITheme.PX)
		frame.add_theme_stylebox_override("panel", sb)
		frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(frame)
		var pr := TextureRect.new()
		pr.custom_minimum_size = Vector2(40, 40) * UITheme.PX
		pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pr.stretch_mode = TextureRect.STRETCH_SCALE
		pr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pr.texture = Dialog.portrait_tex(sp) if seen else null
		frame.add_child(pr)
		if not seen or pr.texture == null:
			var q := PokedexUI._lbl("?", UITheme.INK_DIM)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			pr.add_child(q)
		var body := PokedexUI._rich(_page_text(locs) if page > 0 else _summary(seen))
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(body)
		var A := TeamScreens.ARROW_L + TeamScreens.ARROW_R
		var UD := TeamScreens.ARROW_U + TeamScreens.ARROW_D
		var foot := PokedexUI._lbl(("%s pages   %s species" % [A, UD]) if pages > 1 else ("%s species" % UD), UITheme.INK_DIM)
		foot.size_flags_vertical = Control.SIZE_EXPAND_FILL
		foot.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		vb.add_child(foot)
		if ListMenu.auto:
			(func(): _close("back")).call_deferred()

	func _summary(seen: bool) -> String:
		var S: Dictionary = DB.species.get(sp, {})
		var lines: Array = []
		var area := Services.area_of(sp)
		var own := area in Game.friend_areas
		if seen:
			lines.append("[color=#9ea8c7]Type[/color]  %s" % "/".join(S.get("types", [])))
		else:
			lines.append("[color=#9ea8c7]Not seen yet.[/color]")
		lines.append("[color=#9ea8c7]Area[/color]  %s%s" % [Services.area_name(area) if area != "" else "-", "  [color=#7fff7f]owned[/color]" if own else ""])
		lines.append("[color=#9ea8c7]Recruit[/color]  %s" % Pokedex.recruit_text(sp))
		var rc := Pokedex.recruited_count(sp)
		lines.append("[color=#9ea8c7]Status[/color]  %s" % (("[color=#ffdc4a]Recruited ×%d[/color]" % rc) if rc > 0 else ("Seen" if seen else "-")))
		if seen:
			var locs := Pokedex.locations(sp)
			if locs.is_empty():
				lines.append("[color=#9ea8c7]Found[/color]  not in the wild")
			else:
				var l: Dictionary = locs[0]
				lines.append("[color=#9ea8c7]Found[/color]  %s%s" % [Services.dname(l.dkey), " +%d more" % (locs.size() - 1) if locs.size() > 1 else ""])
		return "\n".join(lines)

	func _page_text(locs: Array) -> String:
		var lines: Array = ["[color=#9ea8c7]Where it appears[/color]"]
		var start := (page - 1) * LOC_PER_PAGE
		for i in range(start, mini(start + LOC_PER_PAGE, locs.size())):
			var l: Dictionary = locs[i]
			var known: bool = l.dkey in Game.unlocked
			var lv := ("Lv%d" % l.lv_min) if int(l.lv_min) == int(l.lv_max) else ("Lv%d-%d" % [l.lv_min, l.lv_max])
			lines.append("%s%s[/color] %s %s" % ["[color=#ffffff]" if known else "[color=#9ea8c7]", Services.dname(l.dkey) if known else "???", Pokedex.floors_text(l.dkey, l.floors), lv])
		return "\n".join(lines)

	func _close(r: String) -> void:
		if _done:
			return
		_done = true
		Audio.sfx("cancel" if r == "back" else "cursor")
		closed.emit.call_deferred(r)

	func _unhandled_input(e: InputEvent) -> void:
		if _done or PokedexUI._blocked(self):
			return
		if e.is_action_pressed("ui_left"):
			if pages > 1: _close("left")
		elif e.is_action_pressed("ui_right"):
			if pages > 1: _close("right")
		elif e.is_action_pressed("ui_up"):
			_close("prev")
		elif e.is_action_pressed("ui_down"):
			_close("next")
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			_close("right" if pages > 1 and page + 1 < pages else "back")
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			_close("back")
		else:
			return
		get_viewport().set_input_as_handled()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			var x: float = e.position.x
			if e.button_index == MOUSE_BUTTON_RIGHT:
				_close("back")
			elif pages > 1 and x > size.x * 0.75:
				_close("right")
			elif pages > 1 and x < size.x * 0.25:
				_close("left")
			else:
				_close("back")
			accept_event()
