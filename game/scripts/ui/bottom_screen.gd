class_name BottomScreen
extends Node
## Second-screen UI (AYN Thor bottom screen / desktop preview window) in Explorers of Sky's bottom-screen
## style: floor map, team panel, Belly, money, message log and big touch buttons in a dungeon; team, money,
## rank and day in town.
##
## Everything is drawn into one SubViewport (`sub`) at a small logical resolution that matches the target
## display's aspect (Thor bottom panel 1240x1080 -> 413x360 at 3x; integer scale so pixels stay crisp).
## Where that picture goes depends on the mode:
##   "window"  - desktop (Windows/Linux): a native second OS window shows the SubViewport texture;
##               mouse clicks on it are mapped back into the SubViewport.
##   "android" - the ThorScreen Android plugin (addons/thor_screen) shows the frames on the secondary
##               display via DisplayManager + Presentation; touches come back as plugin signals.
##   ""        - off (default on phones without a second display, or when the plugin is missing).
## Both modes feed input through inject(), so testing the window on PC exercises the Android input path.
##
##   BottomScreen.setup(main)          - once, from main.gd _ready(); finds main.dungeon / main.town itself
##   BottomScreen.cycle_setting()      - Settings entry ("Second screen: Auto / PC window / Off")

const SETTING := "second_screen"            # Game.settings key: "auto" | "window" | "off"
const PREVIEW_SIZE := Vector2i(1240, 1080)   # AYN Thor bottom panel, used for the desktop preview
const TARGET_H := 384.0                     # logical height to aim for (DS bottom screen 192 at 2x)
const PUSH_FPS := 30.0
const REDRAW_FPS := 20.0
const P := 2                                # UI pixel scale on this viewport (same as UITheme.PX)
const FS := UITheme.FONT_SIZE               # 22: Red's font at 2x
const FS_SMALL := 11                        # Red's font at 1x

# Explorers of Sky palette: deep navy/teal windows with a pale frame
const BG_TOP := Color("0a1a3c")
const BG_BOT := Color("040a1c")
const WIN := Color(0.055, 0.15, 0.34, 0.95)
const WIN_HI := Color(0.12, 0.29, 0.56, 0.97)
const EDGE := Color(0.82, 0.93, 1.0)
const EDGE_IN := Color(0.33, 0.56, 0.86, 0.75)
const OUTLINE := Color(0.02, 0.05, 0.16)
const INK := Color(1, 1, 1)
const DIM := Color(0.62, 0.70, 0.86)
const GOLD := Color(1.0, 0.86, 0.29)
const TEAL := Color(0.45, 0.92, 0.95)
const GOOD_C := Color(0.45, 1.0, 0.5)

static var instance: BottomScreen
static var hover := ""                # item under the cursor in the open menu: its description is shown here
static var dh_row := 0                # dungeon hover: first portrait row shown (the list scrolls when it's long)
var _dh_rows_max := 0                 # rows that don't fit
var _drag_y := -1.0                   # touch / mouse drag on the second screen (scrolls the dungeon list)
var _dh_drag_acc := 0.0
var _stick_t := 0.0
var hover_label: RichTextLabel

var main: Node
var mode := ""                    # "", "window", "android"
var sub: SubViewport
var ui: Control                   # root Control inside the SubViewport (draws the panels)
var map_view: Control             # minimap (clips its contents)
var log_label: RichTextLabel
var buttons: Dictionary = {}      # key -> Button
var logical := Vector2i(413, 360)
var target_size := PREVIEW_SIZE   # physical size of the display we draw for
var map_zoom := false

var plugin: Object = null         # Engine singleton "ThorScreen" (Android)
var win: Window = null            # desktop preview window
var view: TextureRect = null

var _scene := "?"                 # "dungeon" | "town" | "" (title, menus)
var _scene_obj: Object = null
var _town_mons: Array = []
var _town_sig := ""

func _team_sig() -> String:
	var a := PackedStringArray()
	for e in Game.team:
		a.append("%s:%s:%d:%s" % [str(e.get("sp", "")), str(e.get("name", "")), int(e.get("level", 0)), str(e.get("shiny", false))])
	return ",".join(a)
var _push_t := 0.0
var _redraw_t := 0.0
var _last_hash := 0
var _last_key := ""
var _needs_render := true
var _pushing := false
var _log_key := ""
var _hudfont: Texture2D
var _stairs_tex: Texture2D
var _busy_btn := false
var frames_pushed := 0            # for tests / debugging
var taps := 0

# ------------------------------------------------------------------ public API
## Menus call this as the cursor moves ("" = no item under the cursor / menu closed).
## Bulletin Board / Job List: the job under the cursor ({} = none).
static var _job: Dictionary = {}
static func hover_job(j: Dictionary) -> void:
	_job = j
	if j.is_empty():
		if hover.begins_with("job:"):
			hover_item("")
		return
	hover_item("job:%d" % hash([j.get("title", ""), j.get("client", ""), j.get("place", ""), j.get("state", ""), j.get("dungeon", ""), j.get("floor", 0)]))

static func hover_item(id: String) -> void:
	if id == hover:
		return
	hover = id
	dh_row = 0
	if instance and instance.ui:
		instance._refresh()

static func setup(m: Node) -> void:
	if is_instance_valid(instance):
		return
	var b := BottomScreen.new()
	b.name = "BottomScreen"
	b.main = m
	instance = b
	m.add_child.call_deferred(b)

static func setting() -> String:
	var s := str(Game.settings.get(SETTING, "auto"))
	return s if s in ["auto", "window", "off"] else "auto"

static func setting_label() -> String:
	match setting():
		"off": return "Off"
		"window": return "Auto" if OS.has_feature("android") else "PC window"
	return "Auto"

## Next value for the Settings entry. Android: Auto <-> Off. Desktop: Auto (nothing) -> PC window -> Off.
static func cycle_setting() -> void:
	var order := ["auto", "off"] if OS.has_feature("android") else ["auto", "window", "off"]
	var i := order.find(setting())
	Game.settings[SETTING] = order[(i + 1) % order.size()]
	Game.save_game()
	if is_instance_valid(instance):
		instance.refresh_mode()

func is_active() -> bool:
	return mode != ""

func _ready() -> void:
	_hudfont = load("res://assets/ui/hudfont.png")
	_stairs_tex = DB.tex("res://assets/ui/stairs.png")
	refresh_mode()

func _exit_tree() -> void:
	_stop()
	if instance == self:
		instance = null

## Decide where (if anywhere) the second screen goes, from the setting and the hardware.
func refresh_mode() -> void:
	var want := ""
	var size := PREVIEW_SIZE
	var s := setting()
	if s != "off":
		if OS.has_feature("android"):
			var pl := _android_plugin()
			if pl:
				var n := int(pl.call("displayCount"))
				var ds = pl.call("secondaryDisplaySize")
				if n > 1 and ds != null and ds.size() >= 2 and int(ds[0]) > 0 and int(ds[1]) > 0:
					want = "android"
					size = Vector2i(int(ds[0]), int(ds[1]))
		elif s == "window" and DisplayServer.get_name() != "headless":
			want = "window"
	if want == mode and size == target_size:
		return
	_stop()
	if want == "":
		return
	target_size = size
	_build_viewport()
	if want == "android":
		if not bool(plugin.call("start")):
			_stop()
			return
	else:
		_open_window()
	mode = want
	_scene = "?"

func _android_plugin() -> Object:
	if plugin:
		return plugin
	if not Engine.has_singleton("ThorScreen"):
		return null
	plugin = Engine.get_singleton("ThorScreen")
	if plugin == null:
		return null
	for sg in [["touch", _on_plugin_touch], ["drag", _on_plugin_drag], ["display_changed", _on_display_changed]]:
		if plugin.has_signal(sg[0]) and not plugin.is_connected(sg[0], sg[1]):
			plugin.connect(sg[0], sg[1])
	return plugin

func _stop() -> void:
	if mode == "android" and plugin:
		plugin.call("stop")
	if is_instance_valid(win):
		win.queue_free()
	win = null
	view = null
	if is_instance_valid(sub):
		sub.queue_free()
	sub = null
	ui = null
	map_view = null
	log_label = null
	buttons.clear()
	mode = ""
	_scene = "?"
	_last_hash = 0

## Logical resolution: the display divided by the integer scale that brings its height closest to 384.
static func logical_for(size: Vector2i) -> Vector2i:
	var sc := maxi(1, int(round(minf(size.x, size.y) / TARGET_H)))
	return Vector2i(maxi(160, size.x / sc), maxi(120, size.y / sc))

func _build_viewport() -> void:
	logical = logical_for(target_size)
	sub = SubViewport.new()
	sub.name = "BottomScreenViewport"
	sub.size = logical
	sub.transparent_bg = false
	sub.disable_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE    # re-rendered only when its content changes (_render)
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sub.gui_embed_subwindows = true
	add_child(sub)
	ui = Control.new()
	ui.name = "BottomUI"
	ui.theme = UITheme.theme()
	ui.size = Vector2(logical)
	ui.mouse_filter = Control.MOUSE_FILTER_PASS
	ui.draw.connect(_draw_ui)
	sub.add_child(ui)

func _open_window() -> void:
	win = Window.new()
	win.visible = false                     # force_native can only change while hidden
	win.title = "PMD Red - Second screen"
	win.size = logical * 2
	win.min_size = logical
	win.transient = false
	win.wrap_controls = false
	if "force_native" in win:
		win.set("force_native", true)        # a real OS window even though the main viewport embeds subwindows
	else:
		main.get_viewport().gui_embed_subwindows = false
	win.close_requested.connect(func(): _stop())
	view = TextureRect.new()
	view.texture = sub.get_texture()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(_on_view_input)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(bg)
	win.add_child(view)
	# place it under the main window (like the Thor), or to its right when there's no room below
	var mw := main.get_window()
	var mpos := DisplayServer.window_get_position()
	var msz := DisplayServer.window_get_size()
	var scr := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var below := Vector2i(mpos.x + (msz.x - win.size.x) / 2, mpos.y + msz.y + 32)
	if below.y + win.size.y > scr.end.y:
		below = Vector2i(mpos.x + msz.x + 8, mpos.y)
	win.position = below
	add_child(win)
	win.show()
	if mw:
		mw.grab_focus.call_deferred()      # keep the keyboard / pad on the game window

# ------------------------------------------------------------------ input
## A tap / click in SubViewport pixels. Every input source ends up here.
func inject(pos: Vector2, pressed: bool) -> void:
	_drag_y = pos.y if pressed else -1.0
	_dh_drag_acc = 0.0
	# a tap on the second screen also skips the boot intro (those taps never reach the main window)
	if pressed and main != null and is_instance_valid(main.get("ground")) and main.ground.demo and main.ground.demo_cancel_ok:
		main.ground._demo_tap = true
	if sub == null:
		return
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if not pressed else 0
	sub.push_input(mm, true)
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
	mb.global_position = pos
	mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	sub.push_input(mb, true)

func inject_drag(pos: Vector2) -> void:
	if sub == null:
		return
	if hover != "" and _drag_y >= 0.0:
		_dh_drag_acc += _drag_y - pos.y                  # drag up = scroll down
		_drag_y = pos.y
		var step := 30.0 * P
		while absf(_dh_drag_acc) >= step:
			scroll_dungeon(1 if _dh_drag_acc > 0 else -1)
			_dh_drag_acc -= step * signf(_dh_drag_acc)
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.global_position = pos
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	sub.push_input(mm, true)

func _on_plugin_touch(x: int, y: int, pressed: bool) -> void:
	inject(Vector2(x, y), pressed)

func _on_plugin_drag(x: int, y: int) -> void:
	inject_drag(Vector2(x, y))

func _on_display_changed(_count: int) -> void:
	refresh_mode.call_deferred()

## Desktop window: map the TextureRect's local mouse position to SubViewport pixels.
func view_to_sub(local: Vector2) -> Vector2:
	var sz := view.size
	var sc := minf(sz.x / logical.x, sz.y / logical.y)
	var off := (sz - Vector2(logical) * sc) / 2
	return (local - off) / sc

## Scroll the dungeon list by whole portrait rows.
func scroll_dungeon(d: int) -> void:
	var n := clampi(dh_row + d, 0, _dh_rows_max)
	if n != dh_row:
		dh_row = n

func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		scroll_dungeon(-1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		view.accept_event()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		inject(view_to_sub(e.position), e.pressed)
		view.accept_event()
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		inject_drag(view_to_sub(e.position))
		view.accept_event()

## Tests: tap a button by key the way a real tap would arrive (through the window when there is one).
func test_tap(key: String) -> bool:
	var b: Button = buttons.get(key)
	if b == null or sub == null:
		return false
	var c := b.get_global_rect().get_center()
	if is_instance_valid(view):
		var sz := view.size
		var sc := minf(sz.x / logical.x, sz.y / logical.y)
		var off := (sz - Vector2(logical) * sc) / 2
		var wp := off + c * sc
		for pressed in [true, false]:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = pressed
			mb.position = wp
			mb.global_position = wp
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
			win.push_input(mb)
	else:
		inject(c, true)
		inject(c, false)
	return true

# ------------------------------------------------------------------ per frame
func _process(dt: float) -> void:
	if mode == "" or sub == null:
		return
	if hover != "":   # right stick up / down scrolls a long dungeon list / item text
		var ay := 0.0
		for dev in Input.get_connected_joypads():
			var v := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
			if absf(v) > absf(ay):
				ay = v
		if absf(ay) > 0.5:
			_stick_t -= dt
			if _stick_t <= 0.0:
				_stick_t = 0.18
				scroll_dungeon(1 if ay > 0 else -1)
		else:
			_stick_t = 0.0
	_track_scene()
	_redraw_t -= dt
	if _redraw_t <= 0.0:
		_redraw_t = 1.0 / REDRAW_FPS
		var k := _state_key()
		if k != _last_key:
			_last_key = k
			_refresh()
		if _needs_render:
			_needs_render = false
			_render()

## Performance: the second screen used to re-render every frame and copy itself GPU -> CPU 30 times a second
## (a pipeline stall each time). Now it renders once when something on it changed, and on Android the frame is
## read back after that frame has been drawn.
func _render() -> void:
	sub.render_target_update_mode = SubViewport.UPDATE_ONCE
	if mode == "android" and not _pushing:
		_pushing = true
		await RenderingServer.frame_post_draw
		if is_instance_valid(sub) and mode == "android":
			_push_frame()
		_pushing = false

## What the second screen shows, as a cheap string: when it changes, the screen is redrawn.
func _state_key() -> String:
	var d := _dungeon() if _scene == "dungeon" else null
	if d:
		var parts := PackedStringArray([str(d.fs.turn), str(d.hud.msg_count), str(Game.money), str(int(d.belly)),
			str(d.autoplay), str(d.busy), str(d.menu_open), str(d.result_sent), str(map_zoom), str(d.floor_i)])
		for m in d.fs.mons:
			parts.append("%d,%d,%d,%d" % [m.uid, m.pos.x, m.pos.y, m.hp])
		parts.append(hover + str(dh_row))
		return "|".join(parts)
	var t := _town() if _scene == "town" else null
	if t:
		return "town|%s|%d|%s|%s%d|%d|%d" % [str(Vector2i(t.pos)), Game.money, str(map_zoom), hover, dh_row, Game.jobs.size(), _play_min()] + "|" + _team_sig()
	if _scene == "town":
		var place := str(main.call("place_name")) if main and main.has_method("place_name") else ""
		return "ground|%s|%d|%s%d|%d|%d|%s" % [place, Game.money, hover, dh_row, Game.jobs.size(), _play_min(), _team_sig()]
	return _scene + "|" + hover + str(dh_row)

func _push_frame() -> void:
	var img := sub.get_texture().get_image()
	if img == null or img.is_empty():
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var hsh := hash(data)
	if hsh == _last_hash:
		return
	_last_hash = hsh
	plugin.call("pushFrame", data, img.get_width(), img.get_height())
	frames_pushed += 1

func _dungeon() -> Dungeon:
	var d = main.get("dungeon") if main else null
	if is_instance_valid(d) and d is Dungeon and d.fs != null and is_instance_valid(d.hud):
		return d
	return null

func _town() -> Town:
	var t = main.get("town") if main else null
	if is_instance_valid(t) and t is Town and not t.is_queued_for_deletion():
		return t
	return null

## Red's story ground (base, Pokémon Square, Friend Areas, cutscenes) outside the title demo.
func _play_min() -> int:
	return int(float(Game.flags.get("play_secs", 0.0))) / 60

func _ground() -> Ground:
	var g = main.get("ground") if main else null
	if is_instance_valid(g) and g is Ground and not g.is_queued_for_deletion() and not g._done and not g.demo:
		return g
	return null

func _track_scene() -> void:
	var d := _dungeon()
	var t: Town = _town() if d == null else null
	var gr: Ground = _ground() if d == null and t == null else null
	var kind := "dungeon" if d else ("town" if t or gr else "")
	var obj: Object = d if d else (t if t else gr)
	if kind == _scene and obj == _scene_obj:
		return
	_scene = kind
	_scene_obj = obj
	_build_scene()
	if mode == "android" and d and not d.hud.has_meta("bs_touch_hidden"):
		d.hud.set_meta("bs_touch_hidden", true)
		d.hud.touch_device = false          # the bottom screen has the controls now
		d.hud.set_touch_visible(false)

# ------------------------------------------------------------------ layout
var R := {}                       # named rects for the current layout

func _build_scene() -> void:
	for c in ui.get_children():
		ui.remove_child(c)
		c.queue_free()
	buttons.clear()
	map_view = null
	log_label = null
	_log_key = ""
	R.clear()
	var W := float(logical.x)
	var H := float(logical.y)
	var g := 3.0
	R.header = Rect2(g, g, W - 2 * g, 28)
	match _scene:
		"dungeon":
			var bh := 36.0
			var rows := [[["Moves", "moves"], ["Items", "bag"], ["Team", "team"], ["Others", "others"]],
				[["Map", "zoom"], ["Auto", "auto"], ["Wait", "wait"], ["Fight", "mode"]]]      # mode: Autoplay Fight / Stairs
			var by := H - 2 * bh - 2 * g
			_button_rows(rows, by, bh, g)
			var log_h := 2.0 * UITheme.LINE + 10
			R.log = Rect2(g, by - g - log_h, W - 2 * g, log_h)
			var mid_y: float = R.header.end.y + g
			var mid_h: float = R.log.position.y - g - mid_y
			# room for the whole 56x32 floor at 4 px per tile, the team panel gets the rest
			var tw := clampf(W - 3 * g - (56 * 4 + 6), 160.0, 260.0)
			R.map = Rect2(g, mid_y, W - tw - 3 * g, mid_h)
			R.team = Rect2(R.map.end.x + g, mid_y, tw, mid_h)
			map_view = Control.new()
			map_view.clip_contents = true
			map_view.mouse_filter = Control.MOUSE_FILTER_STOP
			var inner: Rect2 = R.map.grow(-3)
			inner.size.y -= 22                      # Belly row under the map
			map_view.position = inner.position
			map_view.size = inner.size
			map_view.draw.connect(_draw_map)
			map_view.gui_input.connect(func(e):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					_on_button("zoom"))
			ui.add_child(map_view)
			log_label = _make_log(R.log)
		"town":
			var bh := 40.0
			_button_rows([[["Menu", "menu"], ["Job List", "jobs"]]], H - bh - g, bh, g)
			R.info = Rect2(g, H - bh - 2 * g - 34 - UITheme.LINE, W - 2 * g, 34 + UITheme.LINE)
			R.team = Rect2(g, R.header.end.y + g, W - 2 * g, R.info.position.y - g - R.header.end.y - g)
			_town_mons.clear()
			_town_sig = _team_sig()
			for e in Game.team:
				_town_mons.append(Game.mon_from_entry(e))
		_:
			pass
	hover_label = TeamScreens._rtl("")
	hover_label.fit_content = false
	hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_label.scroll_active = false
	hover_label.clip_contents = true
	hover_label.visible = false
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hover_label)
	_refresh()

## Where the hovered item's description goes: over the map + team (dungeon), the team (town), or the middle.
func _hover_rect() -> Rect2:
	var W := float(logical.x)
	var H := float(logical.y)
	if R.has("map") and R.has("team"):
		return Rect2(R.map.position, Vector2(R.team.end.x - R.map.position.x, R.team.end.y - R.map.position.y))
	if R.has("team"):
		if R.has("info"):                     # town: over the team and the info panel (down to the buttons)
			return Rect2(R.team.position, Vector2(R.team.size.x, R.info.end.y - R.team.position.y))
		return R.team
	return Rect2(6, 6, W - 12, H - 12)

func _button_rows(rows: Array, y: float, bh: float, g: float) -> void:
	var W := float(logical.x)
	for row in rows:
		var n: int = row.size()
		var bw := floorf((W - g * (n + 1)) / n)
		var x := g
		for spec in row:
			var b := _make_button(spec[0], spec[1])
			b.position = Vector2(x, y)
			b.size = Vector2(bw, bh)
			x += bw + g
		y += bh + g

func _btn_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(P)
	s.set_corner_radius_all(4 * P)
	s.shadow_color = OUTLINE
	s.shadow_size = P
	s.anti_aliasing = false
	s.content_margin_left = 2
	s.content_margin_right = 2
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	return s

func _make_button(label: String, key: String) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", FS)
	var accent := key == "attack" or key == "mode"
	var fill := Color(0.36, 0.17, 0.08, 0.96) if accent else Color(0.09, 0.22, 0.47, 0.96)
	var fill_p := Color(0.62, 0.32, 0.12, 1.0) if accent else Color(0.22, 0.45, 0.82, 1.0)
	var edge := Color(1.0, 0.82, 0.45) if accent else EDGE
	var normal := _btn_box(fill, edge)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)        # synthetic taps leave the "mouse" on top
	b.add_theme_stylebox_override("pressed", _btn_box(fill_p, Color.WHITE))
	b.add_theme_stylebox_override("hover_pressed", _btn_box(fill_p, Color.WHITE))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(0.06, 0.1, 0.2, 0.9), Color(0.4, 0.47, 0.6)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.pressed.connect(_on_button.bind(key))
	ui.add_child(b)
	buttons[key] = b
	return b

func _make_log(r: Rect2) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.scroll_active = false
	l.fit_content = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_contents = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_constant_override("line_separation", 0)
	l.position = r.position + Vector2(6 * P, 4)
	l.size = r.size - Vector2(10 * P, 6)
	ui.add_child(l)
	return l

# ------------------------------------------------------------------ actions
func _on_button(key: String) -> void:
	taps += 1
	Audio.sfx("cursor")
	if _scene == "dungeon":
		var d := _dungeon()
		if d == null:
			return
		match key:
			"mode":                          # Autoplay's mode, switchable any time (also while it runs)
				Game.settings.auto_mode = 1 - Dungeon.auto_mode()
				d._msg("Autoplay mode: %s." % Dungeon.AUTO_MODES[Dungeon.auto_mode()])
			"zoom":
				map_zoom = not map_zoom
				if map_view:
					map_view.queue_redraw()
			"moves", "bag", "wait", "attack", "auto", "menu", "map":
				d.on_hud_button(key)
			"team", "others":
				if d.busy or d.menu_open or d.result_sent:
					return
				if d.autoplay:
					d.set_autoplay(false)
				if key == "team" and d.has_method("open_team"):
					d.open_team()
				elif key == "others" and d.has_method("_others_menu"):
					d.menu_open = true
					await d._others_menu()
					if is_instance_valid(d):
						d.menu_open = false
						if not d.result_sent:
							d._update_hud()
				else:
					d.on_hud_button("menu")
	elif _scene == "town" and _town() == null:
		var gr := _ground()
		if gr == null or _busy_btn or gr.text.is_open() or gr.text._menu != null or not TeamScreens._stack.is_empty() \
				or gr.lives[0].kind_id == -1 or gr.lives[0].ctrl_mode() != 1:
			return                                       # only while the player walks freely
		match key:
			"menu":
				gr._touch_menu = true                    # the ground's own menu, as the on-screen Menu button
			"jobs":
				_busy_btn = true
				gr.set_process(false)
				await Board.open_job_list(main.root)
				_busy_btn = false
				if is_instance_valid(gr):
					gr.set_process(true)
	elif _scene == "town":
		var t := _town()
		if t == null or _busy_btn or not t.has_method("_can_act") or not t._can_act():
			return
		match key:
			"menu":
				t.menu.emit()
			"jobs":
				_busy_btn = true
				t.set_paused(true)
				await Board.open_job_list(main.root)
				_busy_btn = false
				if is_instance_valid(t):
					t.set_paused(false)
	_refresh()

# ------------------------------------------------------------------ drawing
func _refresh() -> void:
	if ui == null:
		return
	_needs_render = true
	ui.queue_redraw()
	if map_view:
		map_view.queue_redraw()
	var d := _dungeon() if _scene == "dungeon" else null
	if d and log_label:
		var L: Array = d.hud.log_all
		var key := "%d|%s" % [L.size(), str(L.back()) if L.size() > 0 else ""]
		if key != _log_key:
			_log_key = key
			log_label.text = "\n".join(L.slice(maxi(0, L.size() - 2)))
	if d and buttons.has("auto"):
		buttons.auto.text = "Auto" if not d.autoplay else "Auto ON"
		buttons.auto.modulate = Color(0.6, 1, 0.65) if d.autoplay else Color.WHITE
		var locked: bool = d.busy or d.menu_open or d.result_sent
		if buttons.has("mode"):
			buttons.mode.text = Dungeon.AUTO_MODES[Dungeon.auto_mode()]
		for k in ["moves", "bag", "team", "others", "wait", "attack"]:
			if buttons.has(k):
				buttons[k].modulate = Color(1, 1, 1, 0.55) if (locked and not d.autoplay) else Color.WHITE
	if buttons.has("zoom"):
		buttons.zoom.text = "Map +" if not map_zoom else "Map -"

func _font() -> Font:
	return UITheme.font()

func _text(ci: CanvasItem, pos: Vector2, s: String, col := INK, size := FS, width := -1.0, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var f := _font()
	var base := pos + Vector2(0, f.get_ascent(size))
	var sh := float(P) if size >= FS else 1.0
	ci.draw_string(f, base + Vector2(sh, sh), s, align, width, size, UITheme.SHADOW)
	ci.draw_string(f, base, s, align, width, size, col)

func _text_w(s: String, size := FS) -> float:
	return _font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

func _panel(r: Rect2, hi := false) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = WIN_HI if hi else WIN
	s.border_color = EDGE
	s.set_border_width_all(P)
	s.set_corner_radius_all(4 * P)
	s.shadow_color = OUTLINE
	s.shadow_size = P
	s.anti_aliasing = false
	ui.draw_style_box(s, r)
	# EoS's inner bevel line
	ui.draw_rect(Rect2(r.position + Vector2(2 * P + 1, 2 * P + 1), r.size - Vector2(4 * P + 2, 4 * P + 2)), EDGE_IN, false, 1.0)

func _background() -> void:
	var W := float(logical.x)
	var H := float(logical.y)
	var steps := 16
	for i in steps:
		ui.draw_rect(Rect2(0, H * i / steps, W, H / steps + 1), BG_TOP.lerp(BG_BOT, float(i) / (steps - 1)))
	# the faint diagonal weave of EoS's lower screen
	var c := Color(0.35, 0.6, 1.0, 0.05)
	var x := -H
	while x < W:
		ui.draw_line(Vector2(x, H), Vector2(x + H, 0), c, 1.0)
		x += 12.0
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.4, 0.65, 1.0, 0.25), false, 1.0)

## Red's HUD lettering (hudfont.png): 0 F, 1 L, 2 v, 3 H, 4 P, 5 /, 6 B, 7..16 digits.
func _glyph(i: int, x: float, y: float, w := 8, sc := P) -> float:
	ui.draw_texture_rect_region(_hudfont, Rect2(x, y, w * sc, 8 * sc), Rect2(i * 8, 0, w, 8))
	return x + w * sc

func _num(n: int, x: float, y: float, sc := P) -> float:
	for ch in str(maxi(0, n)):
		var dd := int(ch)
		x = _glyph(16 if dd == 9 else 7 + dd, x, y, 8, sc) - sc
	return x + sc

func _num_w(n: int, sc := P) -> float:
	return str(maxi(0, n)).length() * 7 * sc + sc

func _bar(r: Rect2, frac: float, fill: Color, empty: Color) -> void:
	ui.draw_rect(r, Color.BLACK)
	var inner := Rect2(r.position + Vector2(0, P), Vector2(r.size.x, r.size.y - 2 * P))
	ui.draw_rect(inner, empty)
	var fw: float = round(r.size.x * clampf(frac, 0, 1) / P) * P
	ui.draw_rect(Rect2(inner.position, Vector2(fw, inner.size.y)), fill)
	ui.draw_rect(Rect2(r.position.x, r.end.y - P, r.size.x, P), Color(1, 1, 1, 0.85))

func _draw_ui() -> void:
	_background()
	match _scene:
		"dungeon": _draw_dungeon()
		"town": _draw_town()
		_: _draw_idle()
	_draw_hover()

## The item under the menu cursor: its sprite, name and description (EoS shows item info on the lower screen).
func _draw_hover() -> void:
	if hover_label == null:
		return
	if hover.begins_with("dungeon:"):
		_draw_dungeon_hover(hover.substr(8))
		return
	if hover.begins_with("fa:"):
		_draw_area_hover(hover.substr(3))
		return
	if hover.begins_with("job:"):
		_draw_job_hover(_job)
		return
	var I: Dictionary = DB.items.get(hover, {}) if hover != "" else {}
	if I.is_empty():
		hover_label.visible = false
		return
	var r := _hover_rect()
	_panel(r, true)
	var x := r.position.x + 6 * P
	var y := r.position.y + 4 * P
	var ic: Texture2D = TeamScreens.item_icon(hover)
	if ic:
		ui.draw_texture(ic, Vector2(x, y + 2))
		x += ic.get_width() + 3 * P
	_text(ui, Vector2(x, y), _fit(DB.item_name(hover), r.end.x - x - 6 * P), GOLD)
	var price := int(I.get("price", 0))
	if price > 0 and str(I.get("kind", "")) != "exclusive":
		var ps := "%d P" % price
		_text(ui, Vector2(r.end.x - 6 * P - _text_w(ps), y), ps, DIM)
	hover_label.visible = true
	hover_label.position = Vector2(r.position.x + 6 * P, y + UITheme.LINE + 2 * P)
	hover_label.size = Vector2(r.size.x - 20 * P, r.end.y - hover_label.position.y - 4 * P)
	hover_label.text = TeamScreens.item_desc(hover)
	# a long description scrolls (drag, right stick, mouse wheel) one line at a time, like the dungeon lists
	hover_label.scroll_active = true
	var vb := hover_label.get_v_scroll_bar()
	vb.modulate.a = 0.0
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_scroll.call_deferred(hover)
	if _dh_rows_max > 0:
		var mx := r.end.x - 8 * P
		var ty := hover_label.position.y
		if dh_row > 0:
			ui.draw_colored_polygon(PackedVector2Array([Vector2(mx - 4 * P, ty + 4 * P), Vector2(mx + 4 * P, ty + 4 * P), Vector2(mx, ty - 1 * P)]), GOLD)
		if dh_row < _dh_rows_max:
			var by := r.end.y - 6 * P
			ui.draw_colored_polygon(PackedVector2Array([Vector2(mx - 4 * P, by - 4 * P), Vector2(mx + 4 * P, by - 4 * P), Vector2(mx, by + 1 * P)]), GOLD)

## A job under the cursor on the Bulletin Board / Job List: Red's Rescue Description (client portrait, title,
## the request text, client / objective / place / difficulty / reward). Long text scrolls like item text.
func _draw_job_hover(j: Dictionary) -> void:
	if j.is_empty():
		hover_label.visible = false
		return
	var r := _hover_rect()
	_panel(r, true)
	var x := r.position.x + 6 * P
	var y := r.position.y + 4 * P
	var ps := 2 * UITheme.LINE
	var tex: Texture2D = Dialog.portrait_tex(str(j.get("client", "")))
	if tex:
		var pr := Rect2(r.end.x - 6 * P - ps, y, ps, ps)
		ui.draw_rect(pr.grow(P), OUTLINE)
		ui.draw_texture_rect(tex, pr, false)
	var st := Board.status_text(j)
	var head := "[color=#ffdc4a]%s[/color]" % str(j.get("title", ""))
	if st != "":
		head += "  [color=#%s]%s[/color]" % [Board.status_color(j).to_html(false), st]
	var rw := (TeamScreens.item_icon_bb(str(j.get("reward", {}).get("item", ""))) if str(j.get("reward", {}).get("type", "")).begins_with("item") else "") + Missions.reward_text(j)
	var lines := [head, str(j.get("text", "")), ""]
	for row in [[Missions.txt("client"), "[color=%s]%s[/color]" % [Missions.HL, Missions.sp_name(str(j.get("client", "")))]],
			[Missions.txt("objective"), str(j.get("objective", ""))], [Missions.txt("place"), str(j.get("place", ""))],
			[Missions.txt("difficulty_label"), Missions.difficulty_bb(str(j.get("difficulty", "E")))], [Missions.txt("reward"), rw]]:
		if str(row[1]).strip_edges() != "":
			lines.append("[color=#a0a8c8]%s[/color]  %s" % [str(row[0]), str(row[1])])
	hover_label.visible = true
	hover_label.position = Vector2(x, y)
	hover_label.size = Vector2(r.size.x - 20 * P - (ps + 4 * P if tex else 0), r.end.y - y - 4 * P)
	hover_label.text = "\n".join(lines)
	hover_label.scroll_active = true
	var vb := hover_label.get_v_scroll_bar()
	vb.modulate.a = 0.0
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_scroll.call_deferred(hover)
	if _dh_rows_max > 0:
		var mx := r.end.x - 8 * P
		if dh_row > 0:
			ui.draw_colored_polygon(PackedVector2Array([Vector2(mx - 4 * P, y + ps + 8 * P), Vector2(mx + 4 * P, y + ps + 8 * P), Vector2(mx, y + ps + 3 * P)]), GOLD)
		if dh_row < _dh_rows_max:
			var by := r.end.y - 6 * P
			ui.draw_colored_polygon(PackedVector2Array([Vector2(mx - 4 * P, by - 4 * P), Vector2(mx + 4 * P, by - 4 * P), Vector2(mx, by + 1 * P)]), GOLD)

## Item text: how many lines are below the window, and scroll to dh_row (after the label has laid out).
func _item_scroll(for_hover: String) -> void:
	if hover != for_hover or hover_label == null or not hover_label.visible:
		return
	var step := float(UITheme.LINE)
	var over := hover_label.get_content_height() - hover_label.size.y
	var mx := maxi(0, ceili(over / step)) if over > 1.0 else 0
	var changed := mx != _dh_rows_max
	_dh_rows_max = mx
	dh_row = clampi(dh_row, 0, _dh_rows_max)
	hover_label.get_v_scroll_bar().value = dh_row * step
	if changed:
		_refresh()
	else:
		_needs_render = true

## The dungeon under the cursor in a dungeon list: its wild Pokémon as portraits with their names in the
## Pokédex colours (white = no Friend Area yet, green = Friend Area owned, cyan = recruited); a Pokémon not seen
## yet is a dark silhouette named ???. Level range in the corner, "No recruiting here" where it applies.
func _draw_dungeon_hover(dk: String) -> void:
	hover_label.visible = false
	var r := _hover_rect()
	_panel(r, true)
	var x0 := r.position.x + 6 * P
	var y := r.position.y + 4 * P
	_text(ui, Vector2(x0, y), _fit(Services.dname(dk), r.end.x - x0 - 60 * P), GOLD)
	var rng := Pokedex.trip_level_range(dk)          # a chained EoS dungeon: the whole trip
	if int(rng[1]) > 0:
		var info := "Lv %d-%d" % [int(rng[0]), int(rng[1])]
		_text(ui, Vector2(r.end.x - 6 * P - _text_w(info), y), info, DIM)
	y += UITheme.LINE + 2 * P
	if not Dungeon.can_recruit_in(dk):
		_text(ui, Vector2(x0, y), "No recruiting here", Color8(0xff, 0x80, 0x70), FS_SMALL)
		y += FS_SMALL + 3 * P
	var sps := Pokedex.trip_species(dk)
	var bosses := Pokedex.trip_bosses(dk)
	if sps.is_empty() and bosses.is_empty():
		_text(ui, Vector2(x0, y), "No wild Pokémon.", DIM)
		return
	var cells := []
	for sp in sps:
		var seen := Pokedex.is_seen(sp)
		cells.append({"sp": sp, "dark": not seen, "col": PokedexUI.list_color(sp) if seen else DIM,
			"name": str(DB.species.get(sp, {}).get("name", sp)) if seen else "???"})
	# bosses after the wild ones: a red "Boss" line under the name with their level
	for b in bosses:
		var bsp := str(b[0])
		var bseen := Pokedex.is_seen(bsp)
		cells.append({"sp": bsp, "dark": not bseen, "col": PokedexUI.list_color(bsp) if bseen else DIM,
			"name": str(DB.species.get(bsp, {}).get("name", bsp)) if bseen else "???",
			"sub": "Boss Lv%d" % int(b[1]), "sub_col": Color8(0xff, 0x80, 0x70)})
	_draw_portrait_grid(r, y, cells)

## A Friend Area under the cursor (the Friend Areas lists: world map, Pelipper / Kangaskhan visits): the Pokémon
## living there, portrait + name + level ("" = the team base: the team).
func _draw_area_hover(k: String) -> void:
	hover_label.visible = false
	var r := _hover_rect()
	_panel(r, true)
	var x0 := r.position.x + 6 * P
	var y := r.position.y + 4 * P
	var mons: Array = []
	var title := ""
	var info := ""
	if k == "":
		title = "%s Team Base" % Game.team_name if Game.team_name != "" else "Team Base"
		mons = Game.team
		info = "Team %d" % mons.size()
	else:
		title = Services.area_name(k)
		for f in Game.friends:
			if str(f.get("area", "")) == k:
				mons.append(f)
		var cap := int(Services.fa().get("areas", {}).get(k, {}).get("cap", 0))
		info = "%d/%d" % [mons.size(), cap] if cap > 0 else str(mons.size())
	_text(ui, Vector2(x0, y), _fit(title, r.end.x - x0 - 50 * P), GOLD)
	_text(ui, Vector2(r.end.x - 6 * P - _text_w(info), y), info, DIM)
	y += UITheme.LINE + 2 * P
	if mons.is_empty():
		_text(ui, Vector2(x0, y), "Nobody lives here yet.", DIM)
		return
	var cells := []
	for e in mons:
		var sp := str(e.get("sp", ""))
		var nm := str(e.get("name", "")).strip_edges()
		if nm == "":
			nm = str(DB.species.get(sp, {}).get("name", sp))
		cells.append({"sp": sp + ("*" if bool(e.get("shiny", false)) else ""), "dark": false, "col": INK,
			"name": nm, "sub": "Lv %d" % int(e.get("level", 1))})
	_draw_portrait_grid(r, y, cells)

## Portrait cells under a header (dungeon hover / Friend Area hover), scrolled by dh_row.
## cell = {sp, name, col, dark (silhouette), sub (optional second line)}
func _draw_portrait_grid(r: Rect2, y: float, cells: Array) -> void:
	var x0 := r.position.x + 6 * P
	var two := cells.any(func(c): return c.has("sub"))
	var avail := r.size.x - 12 * P
	var cols := maxi(1, int(avail / (30 * P)))
	var cw := avail / cols
	var ps := mini(int(cw) - 4 * P, 24 * P)           # portrait size
	var ch := ps + FS_SMALL + 4 * P + (FS_SMALL + P if two else 0)
	var rows := maxi(1, int((r.end.y - 4 * P - y) / ch))
	var total_rows := ceili(cells.size() / float(cols))
	_dh_rows_max = maxi(0, total_rows - rows)
	dh_row = clampi(dh_row, 0, _dh_rows_max)
	var first := dh_row * cols
	var shown := mini(cells.size() - first, cols * rows)
	for j in shown:
		var c: Dictionary = cells[first + j]
		var cx := x0 + (j % cols) * cw
		var cy := y + (j / cols) * ch
		var tex: Texture2D = Dialog.portrait_tex(str(c.sp))
		var pr := Rect2(cx + (cw - ps) / 2.0, cy, ps, ps)
		ui.draw_rect(pr.grow(P), OUTLINE)
		if tex:
			ui.draw_texture_rect(tex, pr, false, Color(0.05, 0.05, 0.12) if c.get("dark", false) else Color.WHITE)
		var nm := _fit(str(c.name), cw - 2 * P, FS_SMALL)
		_text(ui, Vector2(cx + (cw - _text_w(nm, FS_SMALL)) / 2.0, cy + ps + 2 * P), nm, c.col, FS_SMALL)
		if c.has("sub"):
			var sb := str(c.sub)
			_text(ui, Vector2(cx + (cw - _text_w(sb, FS_SMALL)) / 2.0, cy + ps + 3 * P + FS_SMALL), sb, c.get("sub_col", DIM), FS_SMALL)
	if _dh_rows_max > 0:                                # scroll marks: more above / below
		var mx := r.end.x - 8 * P
		if dh_row > 0:
			ui.draw_colored_polygon(PackedVector2Array([Vector2(mx - 4 * P, y + 4 * P), Vector2(mx + 4 * P, y + 4 * P), Vector2(mx, y - 1 * P)]), GOLD)
		if dh_row < _dh_rows_max:
			var by := r.end.y - 6 * P
			ui.draw_colored_polygon(PackedVector2Array([Vector2(mx - 4 * P, by - 4 * P), Vector2(mx + 4 * P, by - 4 * P), Vector2(mx, by + 1 * P)]), GOLD)

func _draw_idle() -> void:
	var W := float(logical.x)
	var H := float(logical.y)
	var r := Rect2(W * 0.12, H * 0.36, W * 0.76, 2 * UITheme.LINE + 20)
	_panel(r)
	_text(ui, r.position + Vector2(0, 8), "Pokémon Mystery Dungeon", GOLD, FS, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_text(ui, r.position + Vector2(0, 8 + UITheme.LINE), "Red Rescue Team", INK, FS, r.size.x, HORIZONTAL_ALIGNMENT_CENTER)

# ---- dungeon
func _draw_dungeon() -> void:
	var d := _dungeon()
	if d == null:
		return
	# header: floor + dungeon name, money
	var h: Rect2 = R.header
	_panel(h, true)
	var fl: String = d._floor_label()
	var x := h.position.x + 6 * P
	var ty := h.position.y + 3
	_text(ui, Vector2(x, ty), fl, GOLD)
	x += _text_w(fl) + 5 * P
	var money := "%d P" % Game.money
	var mw := _text_w(money)
	var name_w := h.end.x - 6 * P - mw - 8 * P - x
	_text(ui, Vector2(x, ty), _fit(d._display_name(), name_w), INK)
	_text(ui, Vector2(h.end.x - 6 * P - mw, ty), money, GOLD)
	# map panel + Belly row
	_panel(R.map)
	var br := Rect2(R.map.position.x + 5, R.map.end.y - 5 - 20, R.map.size.x - 10, 20)
	var bl := "Belly"
	_text(ui, Vector2(br.position.x + 2, br.position.y - 1), bl, Color(1.0, 0.75, 0.45))
	var bx := br.position.x + _text_w(bl) + 4 * P
	var bmax := maxi(1, int(d.belly_max))
	var bv := int(ceil(d.belly))
	var nw := _num_w(bv) + 8 * P + _num_w(bmax)
	var bar_w := br.end.x - bx - nw - 4 * P
	if bar_w > 12:
		var bcol := Color("ffb040") if bv * 5 >= bmax else Color("ff5a4a")
		_bar(Rect2(bx, br.position.y + 6, bar_w, 6 * P), float(bv) / bmax, bcol, Color("4a2410"))
		bx += bar_w + 3 * P
	var nx := _num(bv, bx, br.position.y + 4)
	nx = _glyph(5, nx - P, br.position.y + 4) - P
	_num(bmax, nx, br.position.y + 4)
	# team
	_panel(R.team)
	var mons: Array = d.team_mons
	_draw_team_rows(R.team, mons, true)
	# log
	_panel(R.log)

func _fit(s: String, w: float, size := FS) -> String:
	if _text_w(s, size) <= w:
		return s
	while s.length() > 1 and _text_w(s + ".", size) > w:
		s = s.substr(0, s.length() - 1)
	return s + "."

func _status_tag(m: Mon) -> Array:
	var st: Dictionary = m.status
	var order := [["sleep", "SLP", "8fb0ff"], ["napping", "SLP", "8fb0ff"], ["nightmare", "SLP", "8fb0ff"], ["frozen", "FRZ", "9ff0ff"],
		["para", "PAR", "ffe060"], ["burn", "BRN", "ff8a50"], ["badpoison", "PSN", "d080ff"], ["poison", "PSN", "d080ff"],
		["confused", "CNF", "ffb0e0"], ["petrified", "STN", "c0c0c0"], ["cringe", "CRG", "ffffff"], ["slow", "SLW", "80c0ff"],
		["fast", "FST", "80ffa0"], ["infatuated", "LOV", "ff90c0"], ["leech_seed", "SEED", "90ff80"], ["wrapped", "WRAP", "e0c080"]]
	for o in order:
		if typeof(st.get(o[0], 0)) == TYPE_INT and int(st.get(o[0], 0)) > 0:
			return [o[1], Color(o[2])]
	return []

## Team list: portrait, name, Lv + HP numbers in Red's HUD lettering, HP bar, status tag.
func _draw_team_rows(r: Rect2, mons: Array, in_dungeon: bool) -> void:
	var n := mini(4, mons.size())
	if n == 0:
		return
	var pad := 4.0
	var row_h := floorf((r.size.y - 2 * pad) / maxi(n, 3 if in_dungeon else 4))
	row_h = minf(row_h, 54.0)
	var y := r.position.y + pad
	for i in n:
		var m: Mon = mons[i]
		var rr := Rect2(r.position.x + pad, y, r.size.x - 2 * pad, row_h - 2)
		var alive := m.hp > 0
		if m.is_leader and in_dungeon:
			ui.draw_rect(rr, Color(1, 0.86, 0.3, 0.10))
		elif i % 2 == 1:
			ui.draw_rect(rr, Color(1, 1, 1, 0.035))
		# portrait (40x40, Red's portrait size)
		var ps := minf(40.0, rr.size.y - 4)
		var pr := Rect2(rr.position.x + 1, rr.position.y + (rr.size.y - ps) / 2, ps, ps)
		ui.draw_rect(pr.grow(1), EDGE)
		ui.draw_rect(pr, Color(0.1, 0.18, 0.36))
		var tex := Dialog.portrait_tex(Shiny.por_key(m.sp, Shiny.is_shiny(m)))
		if tex:
			ui.draw_texture_rect(tex, pr, false, Color.WHITE if alive else Color(0.4, 0.4, 0.5))
		var tx := pr.end.x + 2 * P
		var avail := rr.end.x - tx
		var tag := _status_tag(m) if in_dungeon else []
		var tag_w := (_text_w(tag[0], FS_SMALL) + 6) if tag.size() > 0 else 0.0
		var ncol := (GOLD if m.is_leader and in_dungeon else INK) if alive else DIM
		_text(ui, Vector2(tx, rr.position.y), _fit(m.name, avail - tag_w), ncol)
		if tag.size() > 0:
			var tr := Rect2(rr.end.x - tag_w + 1, rr.position.y + 4, tag_w - 2, 14)
			ui.draw_rect(tr, Color(0, 0, 0, 0.55))
			ui.draw_rect(tr, tag[1], false, 1.0)
			_text(ui, Vector2(tr.position.x + 3, tr.position.y + 1), tag[0], tag[1], FS_SMALL)
		# "Lv5  18/20"
		var gy := rr.position.y + UITheme.LINE - 2
		var gx := _glyph(1, tx, gy)
		gx = _glyph(2, gx, gy, 4) + P
		gx = _num(m.level, gx, gy) + 3 * P
		# HP right-aligned; Red's 2x lettering when it fits, 1x otherwise (3-digit HP in a narrow panel)
		var hsc := P
		var hp_w := _num_w(m.hp) + 6 * P + _num_w(m.max_hp)
		if gx + hp_w > rr.end.x:
			hsc = 1
			hp_w = _num_w(m.hp, 1) + 6 + _num_w(m.max_hp, 1)
		var hy := gy + (8 * P - 8 * hsc) / 2.0
		var hx := maxf(gx, rr.end.x - hp_w - 1)
		hx = _num(m.hp, hx, hy, hsc)
		hx = _glyph(5, hx - hsc, hy, 8, hsc) - hsc
		hx = _num(m.max_hp, hx, hy, hsc)
		gx = hx
		if not in_dungeon and m.held != "":
			var it: String = TeamScreens.held_name(m)
			var iw := minf(_text_w(it), rr.size.x * 0.4)
			_text(ui, Vector2(rr.end.x - iw - 2, rr.position.y), _fit(it, iw), TEAL)
		# HP bar under it (or beside it when the row is short)
		var by := gy + 8 * P + 2
		var bw := rr.end.x - tx - 2
		if by + 6 * P > rr.end.y + 2:
			by = gy + P
			tx = gx + 3 * P
			bw = rr.end.x - tx - 2
		if bw > 10:
			var frac := float(m.hp) / maxf(1, m.max_hp)
			var col := Color("2cff34") if frac > 0.5 else (Color("ffd030") if frac > 0.25 else Color("ff4a3a"))
			_bar(Rect2(tx, by, bw, 6 * P), frac, col, Color("7a2a22"))
		y += row_h

func _draw_map() -> void:
	var d := _dungeon()
	if d == null or map_view == null:
		return
	var fs: FloorState = d.fs
	var vs := map_view.size
	map_view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.10, 0.85))
	var s := floorf(minf(vs.x / fs.w, vs.y / fs.h))
	s = maxf(s, 1.0)
	var off := ((vs - Vector2(fs.w, fs.h) * s) / 2).floor()
	if map_zoom:
		s = maxf(s * 2, 8.0)
		var c := Vector2(fs.leader.pos) + Vector2(0.5, 0.5) if fs.leader else Vector2(fs.w, fs.h) / 2
		off = (vs / 2 - c * s).floor()
	var floor_c := Color(0.16, 0.36, 0.74)
	var water_c := Color(0.10, 0.22, 0.55)
	var edge_c := Color(0.62, 0.84, 1.0)
	var ex: PackedByteArray = fs.explored
	var tr: PackedByteArray = fs.terrain
	var x0 := maxi(0, int(floor(-off.x / s)))
	var y0 := maxi(0, int(floor(-off.y / s)))
	var x1 := mini(fs.w, int(ceil((vs.x - off.x) / s)) + 1)
	var y1 := mini(fs.h, int(ceil((vs.y - off.y) / s)) + 1)
	var lw := 1.0 if s < 8 else float(P)
	for y in range(y0, y1):
		for x in range(x0, x1):
			var i := y * fs.w + x
			if ex[i] == 0 or tr[i] == 0:
				continue
			var p := off + Vector2(x, y) * s
			map_view.draw_rect(Rect2(p, Vector2(s, s)), floor_c if tr[i] == 1 else water_c)
			# light outline where the floor meets wall / unexplored ground (EoS map edges)
			if s >= 3:
				if y == 0 or tr[i - fs.w] == 0 or ex[i - fs.w] == 0:
					map_view.draw_rect(Rect2(p, Vector2(s, lw)), edge_c)
				if y == fs.h - 1 or tr[i + fs.w] == 0 or ex[i + fs.w] == 0:
					map_view.draw_rect(Rect2(p + Vector2(0, s - lw), Vector2(s, lw)), edge_c)
				if x == 0 or tr[i - 1] == 0 or ex[i - 1] == 0:
					map_view.draw_rect(Rect2(p, Vector2(lw, s)), edge_c)
				if x == fs.w - 1 or tr[i + 1] == 0 or ex[i + 1] == 0:
					map_view.draw_rect(Rect2(p + Vector2(s - lw, 0), Vector2(lw, s)), edge_c)
	# stairs
	if fs.stairs.x >= 0 and ex[fs.idx(fs.stairs)] == 1:
		var sp := off + Vector2(fs.stairs) * s
		if map_zoom and _stairs_tex:
			map_view.draw_texture_rect(_stairs_tex, Rect2(sp, Vector2(s, s)), false)
		else:
			map_view.draw_rect(Rect2(sp, Vector2(s, s)), Color.WHITE)
			map_view.draw_rect(Rect2(sp + Vector2(s * 0.25, s * 0.25), Vector2(s * 0.5, s * 0.5)), Color(0.2, 0.5, 1.0))
	# traps (seen) and items
	for p in fs.traps:
		if fs.traps[p].get("seen", false) and ex[fs.idx(p)] == 1:
			var tp := off + Vector2(p) * s
			map_view.draw_rect(Rect2(tp + Vector2(s * 0.15, s * 0.15), Vector2(s * 0.7, s * 0.7)), Color(1.0, 0.45, 0.6))
	for p in fs.items:
		if ex[fs.idx(p)] == 1:
			var ip := off + (Vector2(p) + Vector2(0.5, 0.5)) * s
			var rad := maxf(1.2, s * 0.32)
			map_view.draw_circle(ip, rad + 0.8, Color(0.3, 0.2, 0.0))
			map_view.draw_circle(ip, rad, GOLD)
	# Pokémon: foes the team can see, then the team on top, the leader last
	var team: Array = fs.team()
	var order: Array = []
	for m in fs.mons:
		if m.hp <= 0:
			continue
		if m.is_team():
			continue
		for t in team:
			if fs.can_see(t, m.pos):
				order.append(m)
				break
	for m in fs.mons:
		if m.hp > 0 and m.is_team() and not m.is_leader:
			order.append(m)
	if fs.leader and fs.leader.hp > 0:
		order.append(fs.leader)
	for m in order:
		var c := off + (Vector2(m.pos) + Vector2(0.5, 0.5)) * s
		var rad := maxf(1.5, s * 0.45)
		var col := Color(1.0, 0.9, 0.25) if m.is_leader else (Color(0.4, 1.0, 0.55) if m.is_team() else (Color(0.7, 0.9, 1.0) if m.side == "client" else Color(1.0, 0.32, 0.32)))
		map_view.draw_circle(c, rad + 1.0, OUTLINE)
		map_view.draw_circle(c, rad, col)

# ---- town
func _draw_town() -> void:
	var h: Rect2 = R.header
	_panel(h, true)
	var ty := h.position.y + 3
	var tn := "Team %s" % Game.team_name
	_text(ui, Vector2(h.position.x + 6 * P, ty), tn, INK)
	var rk := Missions.rank_title(Game.rank_points)
	_text(ui, Vector2(h.end.x - 6 * P - _text_w(rk), ty), rk, GOLD)
	_panel(R.team)
	var sig := _team_sig()
	if sig != _town_sig:                                 # the team changed (formation, a new member)
		_town_sig = sig
		_town_mons.clear()
		for e in Game.team:
			_town_mons.append(Game.mon_from_entry(e))
	# entries carry no HP in town: everyone is rested
	_draw_team_rows(R.team, _town_mons, false)
	_draw_town_jobs(R.team)
	var ir: Rect2 = R.info
	_panel(ir)
	var y := ir.position.y + 4
	var x := ir.position.x + 6 * P
	# EoS: where you are and the play time
	var secs := int(float(Game.flags.get("play_secs", 0.0)))
	var pt := "%d:%02d" % [secs / 3600, (secs / 60) % 60]
	var place := str(main.call("place_name")) if main and main.has_method("place_name") else ""
	_text(ui, Vector2(x, y), _fit(place if place != "" else "-", ir.size.x - 18 * P - _text_w(pt)), INK)
	_text(ui, Vector2(ir.end.x - 6 * P - _text_w(pt), y), pt, DIM)
	y += UITheme.LINE
	_text(ui, Vector2(x, y), "%d P" % Game.money, GOLD)
	var mid := "Day %d" % (Game.day + 1)
	_text(ui, Vector2(ir.position.x, y), mid, INK, FS, ir.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var jobs := "Jobs %d/8" % Game.jobs.size()
	_text(ui, Vector2(ir.end.x - 6 * P - _text_w(jobs), y), jobs, TEAL)

## Accepted jobs (Job List) in the space under the team rows.
func _draw_town_jobs(r: Rect2) -> void:
	var used := 5.0 + mini(4, _town_mons.size()) * minf(54.0, floorf((r.size.y - 10) / 4.0))
	var y := r.position.y + used + 4
	var x := r.position.x + 6 * P
	if Game.jobs.is_empty() or y + 2 * UITheme.LINE > r.end.y:
		return
	ui.draw_rect(Rect2(r.position.x + 5, y - 2, r.size.x - 10, P), EDGE_IN)
	_text(ui, Vector2(x, y), "Job List", GOLD)
	y += UITheme.LINE
	for j in Game.jobs:
		if y + UITheme.LINE > r.end.y - 4:
			break
		var dk := str(j.get("dungeon", ""))
		var fl := int(j.get("floor", 0))
		var line := "%s %dF  %s" % [Services.dname(dk), fl, str(j.get("kind", "")).capitalize()]
		var col := GOOD_C if str(j.get("state", "")) in ["done", "done_pending"] else INK
		_text(ui, Vector2(x, y), _fit(line, r.size.x - 12 * P), col)
		y += UITheme.LINE

## Tests: the SubViewport picture (what the Thor's bottom screen shows).
func screenshot(path: String) -> void:
	if sub:
		var img := sub.get_texture().get_image()
		if img:
			img.save_png(path)
