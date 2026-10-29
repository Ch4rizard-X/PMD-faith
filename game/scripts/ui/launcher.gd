extends CanvasLayer
## The launcher (public builds, before the game): Play, Pokémon, Dungeons, Difficulty.
##   Pokémon    which Pokémon are in the game: presets, one tab per generation, a switch per Pokémon
##   Dungeons   which Explorers of Sky dungeons are on the dungeon list (a dungeon in several parts counts once)
##   Difficulty Easy / Normal / Hard and sliders (scripts/core/launcher_cfg.gd applies them in the game)
## Everything is saved in user://launcher.json on Play / Back and applies to every save file.
## main.gd shows it when wanted() and waits for play_pressed. Loaded by path (no class_name).

signal play_pressed

const LC := preload("res://scripts/core/launcher_cfg.gd")
const SMALL := 11
const BIG := 22
const GOLD := Color(1.0, 0.86, 0.29)
const DIM := Color(0.55, 0.6, 0.72)
const OFF_TINT := Color(0.32, 0.34, 0.42)
const BG_TOP := Color(0.05, 0.08, 0.2)
const BG_BOT := Color(0.02, 0.03, 0.09)
const GEN_PRESETS := {"Red only": [1, 2, 3], "Gen 1-4": [1, 2, 3, 4], "All": [1, 2, 3, 4, 5, 6, 7, 8, 9]}

var cfg: Dictionary
var _page: Control
var _bg: Control
var _gen := 1
var _mons_by_gen := {}
var _tex_cache := {}

## Shown in public builds (the game's data built from the player's ROMs), or with --launcher.
static func wanted() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--launcher") or args.has("--launchershot"):
		return true
	if not args.is_empty():
		return false
	var p = Engine.get_main_loop().root.get_node_or_null("/root/Patcher")
	return p != null and bool(p.get("romdata_mounted"))

func _ready() -> void:
	layer = 40
	DisplayServer.window_set_title("MD-Recomp")
	cfg = LC.cfg().duplicate(true)
	for k in DB.species:
		var s := str(k)
		if s.length() == 4 and s.is_valid_int():
			var g := LC.gen_of(int(s))
			if not _mons_by_gen.has(g):
				_mons_by_gen[g] = []
			_mons_by_gen[g].append(s)
	for g in _mons_by_gen:
		_mons_by_gen[g].sort()
	_bg = Control.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.theme = UITheme.theme()
	_bg.draw.connect(_draw_bg)
	add_child(_bg)
	_load_backdrop()
	_show_main()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--launchershot"):
			_shots.call_deferred()

# ------------------------------------------------------------------ backdrop
## Red's title artwork (built from the player's ROM: assets/ui/menu_artwork_*.png) slowly panning and
## cross-fading, darkened behind the pages, with a few Pokémon walking along the bottom of the main page.
const ART_TIME := 9.0
const FADE_TIME := 1.6
var _arts: Array = []
var _t := 0.0
var _walkers: Array = []          # [{sp, x, speed, anim}]
var _dark := 0.35                 # backdrop dimming (more behind the sub pages)
var _dark_to := 0.35

func _load_backdrop() -> void:
	for i in [1, 2, 3]:
		var t: Texture2D = DB.tex("res://assets/ui/menu_artwork_%d.png" % i)
		if t:
			_arts.append(t)
	var pool: Array = ["0004", "0001", "0007", "0025", "0152", "0155", "0158", "0252", "0255", "0258", "0133", "0052"]
	pool = pool.filter(func(s): return DB.sprites.has(s) and (DB.sprites[s].get("anims", {}) as Dictionary).has("Walk"))
	pool.shuffle()
	for i in mini(4, pool.size()):
		_walkers.append({"sp": pool[i], "x": 230.0 - i * 46.0, "speed": 22.0})

func _process(dt: float) -> void:
	_t += dt
	_dark = move_toward(_dark, _dark_to, dt * 1.5)
	for w in _walkers:
		w.x += w.speed * dt
		if w.x > _bg.size.x + 40.0:
			w.x -= _bg.size.x + 40.0 + 46.0 * _walkers.size()
	_bg.queue_redraw()

func _draw_art(t: Texture2D, a: float, k: float) -> void:
	var sz := _bg.size
	var ts := t.get_size()
	var sc := maxf(sz.x / ts.x, sz.y / ts.y) * 1.03
	var ds := ts * sc
	var off := (sz - ds) * Vector2(0.5 + 0.5 * sin(k * 0.7), 0.5 + 0.5 * cos(k * 0.5))     # slow drift
	_bg.draw_texture_rect(t, Rect2(off, ds), false, Color(1, 1, 1, a))

func _draw_bg() -> void:
	var sz := _bg.size
	_bg.draw_rect(Rect2(Vector2.ZERO, sz), BG_BOT)
	if not _arts.is_empty():
		var n := _arts.size()
		var cyc := _t / ART_TIME
		var i := int(cyc) % n
		var f := fmod(_t, ART_TIME)
		_draw_art(_arts[i], 1.0, cyc)
		if f > ART_TIME - FADE_TIME:
			_draw_art(_arts[(i + 1) % n], (f - (ART_TIME - FADE_TIME)) / FADE_TIME, cyc + 1.0)
	_bg.draw_rect(Rect2(Vector2.ZERO, sz), Color(BG_BOT, _dark))
	# a soft band behind the logo and the menu
	var steps := 16
	for k in steps:
		var y := sz.y * k / steps
		_bg.draw_rect(Rect2(0, y, sz.x, sz.y / steps + 1), Color(BG_BOT, 0.35 * (k / float(steps)) * _dark / 0.35))
	if _page and not _page.get_meta("sub", false):
		_draw_walkers()

func _draw_walkers() -> void:
	var y := _bg.size.y - 14.0
	for w in _walkers:
		var man: Dictionary = DB.sprites[w.sp]
		var A: Dictionary = man.anims.Walk
		var tex := DB.tex("res://assets/sp/" + str(A.get("s", man.sheet)))
		if tex == null:
			continue
		var dur: Array = A.dur
		var total := 0
		for d in dur:
			total += int(d)
		var tt := posmod(int(_t * 60.0), maxi(1, total))
		var f := 0
		var acc := 0
		while f < dur.size():
			acc += int(dur[f])
			if tt < acc:
				break
			f += 1
		f = mini(f, dur.size() - 1)
		var wdt := int(A.w)
		var hgt := int(A.h)
		var row := mini(2, int(A.rows) - 1)        # facing right
		var src := Rect2(int(A.get("x", 0)) + f * wdt, int(A.y) + row * hgt, wdt, hgt)
		var gnd := 4.0                               # sprite centre -> feet (as MonSprite)
		var shd: Array = man.get("shd", [])
		if shd.size() > 0:
			gnd = float(shd[mini(2, shd.size() - 1)][1])
		_bg.draw_set_transform(Vector2(w.x, y), 0.0, Vector2(1.0, 0.45))
		_bg.draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.4))
		_bg.draw_set_transform(Vector2(w.x, y - gnd), 0.0, Vector2.ONE)
		_bg.draw_texture_rect_region(tex, Rect2(-wdt / 2.0, -hgt / 2.0 - 2.0, wdt, hgt), src)
		_bg.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## A Red window (the game's frame) around page content.
func _window(child: Control, alpha := 1.0) -> PanelContainer:
	var p := PanelContainer.new()
	if alpha < 1.0:
		var sb: StyleBox = UITheme.frame(alpha).duplicate()
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		p.add_theme_stylebox_override("panel", sb)
	p.add_child(child)
	return p

func _input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and _page and _page.get_meta("sub", false):
		get_viewport().set_input_as_handled()
		_save()
		_show_main()

# ------------------------------------------------------------------ small builders
func _lbl(t: String, size := SMALL, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l

func _btn(t: String, cb: Callable, size := SMALL) -> Button:
	var b := Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_constant_override("shadow_offset_x", 1)
	b.add_theme_constant_override("shadow_offset_y", 1)
	b.focus_mode = Control.FOCUS_ALL
	var foc := UITheme.box(0.95)
	foc.bg_color = Color(0.16, 0.26, 0.62, 0.95)
	foc.border_color = GOLD
	b.add_theme_stylebox_override("focus", foc)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)
	if size == SMALL:
		_tight(b)
	b.pressed.connect(cb)
	return b

## Small buttons: thin padding (the theme's window boxes are padded for 22 px text).
func _tight(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var sb: StyleBox = b.get_theme_stylebox(st if st != "hover_pressed" else "pressed")
		if sb == null:
			continue
		sb = sb.duplicate()
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		b.add_theme_stylebox_override(st, sb)

func _new_page(sub: bool) -> VBoxContainer:
	if _page:
		_page.queue_free()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 12)
	for s in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 8)
	m.set_meta("sub", sub)
	_bg.add_child(m)
	_page = m
	_dark_to = 0.72 if sub else 0.3
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	if sub:
		var w := _window(v, 0.86)
		m.add_child(w)
	else:
		m.add_child(v)
	return v

func _top_bar(v: VBoxContainer, title: String, info: String) -> Label:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var back := _btn("  < Back  ", func(): _save(); _show_main())
	h.add_child(back)
	h.add_child(_lbl(title, BIG, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	var il := _lbl(info, SMALL, DIM)
	il.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(il)
	back.grab_focus.call_deferred()
	return il

func _save() -> void:
	LC.save(cfg)

# ------------------------------------------------------------------ main
func _show_main() -> void:
	var v := _new_page(false)
	var h := HBoxContainer.new()
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	# left: Red's logo and the version
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	h.add_child(left)
	var logo_tex: Texture2D = DB.tex("res://assets/ui/logo_transparent.png")
	if logo_tex:
		var logo := TextureRect.new()
		logo.texture = logo_tex
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(200, 124)
		logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		left.add_child(logo)
	else:
		left.add_child(_lbl("MD-Recomp", 33, GOLD))
	var P = get_node_or_null("/root/Patcher")
	var ver := _lbl("MD-Recomp  -  v%s" % (P.version_name() if P else "?"), SMALL, Color(1, 1, 1, 0.85))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver.custom_minimum_size.x = 200
	ver.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(ver)
	# right: the menu in a Red window
	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 3)
	var win := _window(menu)
	win.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	win.custom_minimum_size.x = 196
	h.add_child(win)
	var rows := [["Play", _play, "Start the adventure"],
		["Pokémon", _show_mons, _mons_summary()],
		["Dungeons", _show_dungeons, _dungeons_summary()],
		["Difficulty", _show_difficulty, _difficulty_summary()]]
	var first: Button = null
	for r in rows:
		var b := _btn(str(r[0]), r[1], BIG)
		b.custom_minimum_size = Vector2(176, 30)
		menu.add_child(b)
		var l := _lbl("  " + str(r[2]), SMALL, Color(0.78, 0.84, 1.0))
		menu.add_child(l)
		if first == null:
			first = b
			b.add_theme_color_override("font_color", GOLD)
	first.grab_focus.call_deferred()

func _play() -> void:
	_save()
	play_pressed.emit()

func _mons_summary() -> String:
	var on: int = 0
	var tot := 0
	for g in _mons_by_gen:
		for s in _mons_by_gen[g]:
			tot += 1
			if not s in cfg.mons_off:
				on += 1
	return "%d of %d Pokémon" % [on, tot]

func _dungeons_summary() -> String:
	var heads := _eos_heads()
	var on: int = heads.filter(func(k): return not k in cfg.dungeons_off).size()
	return "Explorers of Sky: %d of %d on" % [on, heads.size()]

func _difficulty_summary() -> String:
	return str(cfg.get("preset", "Normal")) + (" (Hard level curve)" if cfg.get("hard", false) and cfg.get("preset", "") != "Hard" else "")

# ------------------------------------------------------------------ Pokémon
var _mon_info: Label
var _gen_btns := {}
var _grid: GridContainer
var _gen_head: Label

func _show_mons() -> void:
	var v := _new_page(true)
	_mon_info = _top_bar(v, "Pokémon", "")
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 4)
	v.add_child(pr)
	pr.add_child(_lbl("Presets", SMALL, DIM))
	for nm in GEN_PRESETS:
		pr.add_child(_btn(" %s " % nm, _preset_gens.bind(GEN_PRESETS[nm])))
	var sp0 := Control.new()
	sp0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pr.add_child(sp0)
	_hover_lbl = _lbl("", SMALL)
	_hover_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(_hover_lbl)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 3)
	v.add_child(tabs)
	_gen_btns = {}
	tabs.add_child(_lbl("Gen", SMALL, DIM))
	for g in range(1, 10):
		var b := _btn(" %d " % g, _pick_gen.bind(g))
		b.toggle_mode = true
		tabs.add_child(b)
		_gen_btns[g] = b
	_gen_head = _lbl("", SMALL, GOLD)
	_gen_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gen_head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gen_head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(_gen_head)
	tabs.add_child(_btn(" All on ", _set_gen.bind(true)))
	tabs.add_child(_btn(" All off ", _set_gen.bind(false)))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	v.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 9
	_grid.add_theme_constant_override("h_separation", 2)
	_grid.add_theme_constant_override("v_separation", 2)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_grid)
	_pick_gen(_gen)

func _pick_gen(g: int) -> void:
	_gen = g
	for k in _gen_btns:
		_gen_btns[k].set_pressed_no_signal(k == g)
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for s in _mons_by_gen.get(g, []):
		var b := Button.new()
		b.custom_minimum_size = Vector2(47, 52)
		b.icon = _portrait(s)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = str(DB.species[s].name)
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 8)
		b.add_theme_color_override("font_focus_color", GOLD)
		b.add_theme_constant_override("shadow_offset_x", 1)
		b.add_theme_constant_override("shadow_offset_y", 1)
		b.add_theme_constant_override("icon_max_width", 34)
		var foc := StyleBoxFlat.new()
		foc.bg_color = Color(0, 0, 0, 0)
		foc.border_color = GOLD
		foc.set_border_width_all(1)
		b.add_theme_stylebox_override("focus", foc)
		_tight(b)
		b.add_theme_stylebox_override("focus", foc)
		b.tooltip_text = "#%d %s" % [int(s), DB.species[s].name]
		b.pressed.connect(_toggle_mon.bind(s, b))
		b.set_meta("sp", s)
		b.focus_entered.connect(_hover_mon.bind(s))
		b.mouse_entered.connect(_hover_mon.bind(s))
		_grid.add_child(b)
		_style_mon(b, s)
	_refresh_mon_counts()

var _hover_lbl: Label

func _hover_mon(s: String) -> void:
	if _hover_lbl:
		_hover_lbl.text = "#%d %s%s" % [int(s), DB.species[s].name, "" if not s in cfg.mons_off else "  (off)"]

func _portrait(s: String) -> Texture2D:
	if _tex_cache.has(s):
		return _tex_cache[s]
	var t: Texture2D = Dialog.portrait_tex(s)
	_tex_cache[s] = t
	return t

func _style_mon(b: Button, s: String) -> void:
	var on: bool = not s in cfg.mons_off
	b.modulate = Color.WHITE if on else OFF_TINT

func _toggle_mon(s: String, b: Button) -> void:
	if s in cfg.mons_off:
		cfg.mons_off.erase(s)
	else:
		cfg.mons_off.append(s)
	_style_mon(b, s)
	_refresh_mon_counts()

func _set_gen(on: bool) -> void:
	for s in _mons_by_gen.get(_gen, []):
		if on:
			cfg.mons_off.erase(s)
		elif not s in cfg.mons_off:
			cfg.mons_off.append(s)
	for b in _grid.get_children():
		if b.has_meta("sp"):
			_style_mon(b, str(b.get_meta("sp")))
	_refresh_mon_counts()

func _preset_gens(gens: Array) -> void:
	cfg.mons_off = []
	for g in _mons_by_gen:
		if not int(g) in gens:
			cfg.mons_off.append_array(_mons_by_gen[g])
	_pick_gen(_gen)

func _refresh_mon_counts() -> void:
	_mon_info.text = _mons_summary()
	var lst: Array = _mons_by_gen.get(_gen, [])
	var on: int = lst.filter(func(s): return not s in cfg.mons_off).size()
	_gen_head.text = "%d / %d on" % [on, lst.size()]
	for g in _gen_btns:
		var l2: Array = _mons_by_gen.get(g, [])
		var o2: int = l2.filter(func(s): return not s in cfg.mons_off).size()
		_gen_btns[g].modulate = Color.WHITE if o2 > 0 else OFF_TINT

# ------------------------------------------------------------------ Dungeons
var _dun_info: Label
var _dun_rows := {}

func _eos_heads() -> Array:
	var out: Array = []
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	for k in dd:
		if not bool(dd[k].get("eos", false)):
			continue
		if Story.eos_chain_head(str(k)) != str(k):
			continue
		out.append(str(k))
	out.sort_custom(func(a, b): return _need(a) < _need(b) if _need(a) != _need(b) else str(dd[a].name) < str(dd[b].name))
	return out

func _need(k: String) -> int:
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	if bool(dd[k].get("level_reset", false)) or k in Story.EOS_POSTGAME:
		return 1000
	var n := int(dd[k].get("eos_level", 1))
	for ck in Story.eos_chain_of(k):
		if (dd.get(ck, {}).get("floors", []) as Array).size() > 1:
			n = maxi(n, int(dd[ck].get("eos_level", 1)))
	return n

func _show_dungeons() -> void:
	var v := _new_page(true)
	_dun_info = _top_bar(v, "Dungeons", "")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	var l := _lbl("Explorers of Sky dungeons on the dungeon list. Red's own dungeons are always there.", SMALL, DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	h.add_child(_btn(" All on ", _set_all_dungeons.bind(true)))
	h.add_child(_btn(" All off ", _set_all_dungeons.bind(false)))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	v.add_child(sc)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 2)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	_dun_rows = {}
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	for k in _eos_heads():
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 20
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", SMALL)
		b.add_theme_constant_override("shadow_offset_x", 1)
		b.add_theme_constant_override("shadow_offset_y", 1)
		var foc := UITheme.box(0.95)
		foc.border_color = GOLD
		b.add_theme_stylebox_override("focus", foc)
		var parts := Story.eos_chain_of(k).size()
		var need := _need(k)
		var tag := ("after the story" if need >= 1000 else "Lv %d" % need) + ("  -  %d parts" % parts if parts > 1 else "")
		b.set_meta("tag", tag)
		b.set_meta("name", str(dd[k].name))
		b.pressed.connect(_toggle_dungeon.bind(k))
		g.add_child(b)
		_dun_rows[k] = b
		_style_dungeon(k)
	_refresh_dun_count()

func _style_dungeon(k: String) -> void:
	var b: Button = _dun_rows[k]
	var on: bool = not k in cfg.dungeons_off
	b.text = "%s  %s   %s" % ["On " if on else "Off", str(b.get_meta("name")), str(b.get_meta("tag"))]
	b.add_theme_color_override("font_color", Color.WHITE if on else DIM)
	b.add_theme_color_override("font_hover_color", Color.WHITE if on else DIM)
	b.add_theme_color_override("font_focus_color", Color.WHITE if on else DIM)

func _toggle_dungeon(k: String) -> void:
	if k in cfg.dungeons_off:
		cfg.dungeons_off.erase(k)
	else:
		cfg.dungeons_off.append(k)
	_style_dungeon(k)
	_refresh_dun_count()

func _set_all_dungeons(on: bool) -> void:
	cfg.dungeons_off = [] if on else _eos_heads()
	for k in _dun_rows:
		_style_dungeon(k)
	_refresh_dun_count()

func _refresh_dun_count() -> void:
	_dun_info.text = _dungeons_summary()

# ------------------------------------------------------------------ Difficulty
var _diff_info: Label
var _sliders := {}
var _preset_btns := {}
var _curve_btn: Button

func _show_difficulty() -> void:
	var v := _new_page(true)
	_diff_info = _top_bar(v, "Difficulty", "")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	v.add_child(h)
	h.add_child(_lbl("Presets", SMALL, DIM))
	_preset_btns = {}
	for nm in LC.PRESET_ORDER:
		var b := _btn(" %s " % nm, _apply_preset.bind(nm))
		b.toggle_mode = true
		h.add_child(b)
		_preset_btns[nm] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_curve_btn = _btn("", _toggle_curve)
	h.add_child(_curve_btn)
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 3)
	v.add_child(g)
	_sliders = {}
	for k in LC.SLIDER_ORDER:
		var d: Array = LC.SLIDERS[k]
		var l := _lbl(str(d[0]), SMALL)
		l.custom_minimum_size.x = 96
		g.add_child(l)
		var s := HSlider.new()
		s.min_value = float(d[1])
		s.max_value = float(d[2])
		s.step = float(d[3])
		s.custom_minimum_size = Vector2(80, 18)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value = float(cfg.d.get(k, d[4]))
		_style_slider(s)
		g.add_child(s)
		var vl := _lbl("", SMALL, GOLD)
		vl.custom_minimum_size.x = 38
		g.add_child(vl)
		_sliders[k] = [s, vl]
		s.value_changed.connect(_slider_moved.bind(k))
	var note := _lbl("Hard level curve: wild Pokémon follow a planned curve to Lv 70 by the end of the story, and keep up with a strong team. Story Pokémon and bosses always stay in the game.", SMALL, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	_refresh_diff()

func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.1, 0.13, 0.3)
	track.border_color = Color(0.4, 0.5, 0.9)
	track.set_border_width_all(1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.5, 1.0)
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var foc := StyleBoxFlat.new()
	foc.bg_color = Color(0, 0, 0, 0)
	foc.border_color = GOLD
	foc.set_border_width_all(1)
	s.add_theme_stylebox_override("focus", foc)

func _fmt(k: String, v: int) -> String:
	var d: Array = LC.SLIDERS[k]
	if str(d[5]) == "lv":
		return ("+%d" % v) if v > 0 else ("%d" % v if v < 0 else "0")
	if k == "hunger" and v == 0:
		return "Off"
	return "%d%%" % v

func _slider_moved(val: float, k: String) -> void:
	cfg.d[k] = int(val)
	cfg.preset = _match_preset()
	_refresh_diff(false)

func _apply_preset(nm: String) -> void:
	var p: Dictionary = LC.PRESETS[nm]
	cfg.hard = bool(p.get("hard", false))
	for k in LC.SLIDERS:
		cfg.d[k] = int(p.get(k, LC.SLIDERS[k][4]))
	cfg.preset = nm
	_refresh_diff()

func _toggle_curve() -> void:
	cfg.hard = not bool(cfg.get("hard", false))
	cfg.preset = _match_preset()
	_refresh_diff(false)

func _match_preset() -> String:
	for nm in LC.PRESET_ORDER:
		var p: Dictionary = LC.PRESETS[nm]
		if bool(p.get("hard", false)) != bool(cfg.get("hard", false)):
			continue
		var same := true
		for k in LC.SLIDERS:
			if int(cfg.d.get(k, 0)) != int(p.get(k, LC.SLIDERS[k][4])):
				same = false
				break
		if same:
			return nm
	return "Custom"

func _refresh_diff(move_sliders := true) -> void:
	for k in _sliders:
		var s: HSlider = _sliders[k][0]
		if move_sliders:
			s.set_value_no_signal(float(cfg.d.get(k, LC.SLIDERS[k][4])))
		(_sliders[k][1] as Label).text = _fmt(k, int(s.value))
	for nm in _preset_btns:
		_preset_btns[nm].set_pressed_no_signal(nm == str(cfg.preset))
	_curve_btn.text = " Level curve: %s " % ("Hard" if cfg.get("hard", false) else "Red's")
	_diff_info.text = "Preset: " + str(cfg.preset)

# ------------------------------------------------------------------ test shots (--launchershot)
func _shots() -> void:
	var tree := get_tree()
	var dir := "user://launcher_shots/"
	DirAccess.make_dir_recursive_absolute(dir)
	await tree.create_timer(0.6).timeout
	var snap := func(n: String):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(dir + n + ".png")
	await snap.call("1_main")
	_show_mons()
	_pick_gen(5)
	_toggle_mon(str(_mons_by_gen[5][3]), _grid.get_child(3))
	await tree.create_timer(0.5).timeout
	await snap.call("2_pokemon")
	_show_dungeons()
	_toggle_dungeon(_eos_heads()[2])
	await tree.create_timer(0.3).timeout
	await snap.call("3_dungeons")
	_show_difficulty()
	_apply_preset("Easy")
	await tree.create_timer(0.3).timeout
	await snap.call("4_difficulty")
	cfg = LC.defaults()
	_show_main()
	await tree.create_timer(0.3).timeout
	await snap.call("5_main_after")
	print("LAUNCHERSHOT done")
	tree.quit()
