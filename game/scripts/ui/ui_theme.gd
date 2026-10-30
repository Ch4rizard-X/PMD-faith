class_name UITheme
extends RefCounted
## PMD Red look: Red's text font at 2x its native pixel size (crisp), Red's dark-blue windows with the
## light frame, grey text shadow, and the green arrow cursor from Red's cursor sheet.

const FONT_PATH := "res://assets/ui/pmd_red_text.ttf"
const PX := 2                      # UI pixel scale (Red's 11 px font -> 22)
const FONT_SIZE := 11 * PX
const LINE := 12 * PX              # Red's line height
const INK := Color(1, 1, 1)
const INK_DIM := Color(0.62, 0.66, 0.78)
const GOLD := Color(1.0, 0.9, 0.35)
const FOE := Color(1.0, 0.55, 0.45)
const ALLY := Color(0.55, 0.85, 1.0)
const GOOD := Color(0.45, 1.0, 0.5)
const SHADOW := Color(0.235, 0.235, 0.235)
const WIN_BG := Color(22 / 255.0, 30 / 255.0, 104 / 255.0, 0.93)
const WIN_EDGE := Color(223 / 255.0, 231 / 255.0, 1.0)
const WIN_OUT := Color(11 / 255.0, 18 / 255.0, 64 / 255.0)

static var _font: Font
static var _theme: Theme
static var _cursor: AtlasTexture

static func font() -> Font:
	if _font == null:
		var f = load(FONT_PATH)
		if f is FontFile and not (f.data as PackedByteArray).is_empty():
			# a fresh font from the raw TTF bytes: a font saved into the player's game pack (public builds) could
			# carry a glyph cache that drew some capitals wrong on Windows (C as OE, B as C, L as U)
			var nf := FontFile.new()
			nf.data = f.data
			nf.disable_embedded_bitmaps = true
			nf.allow_system_fallback = false
			f = nf
		if f is FontFile:
			f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
			f.hinting = TextServer.HINTING_NONE
			f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			f.fixed_size = 11
			f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
		_font = f
	return _font

## The text font allowed to scale by non-whole steps (the Message size option's Small text); the normal
## font only scales 1x / 2x / 3x so it stays pixel-sharp.
static var _font_free: Font
const FONT_FREE_PATH := "user://font_free_scale.res"

static func font_free_scale() -> Font:
	if _font_free == null:
		var f = font()
		if f is FontFile:
			# a separate font from the same TTF bytes, not f.duplicate(): a duplicate shares the glyph cache's
			# images with the normal font, and both drawing their letters into them garbled capitals on Windows
			# (A as 7, B as A, W as Ty on the dungeon buttons once the message log had drawn text)
			var c := FontFile.new()
			c.data = f.data
			c.disable_embedded_bitmaps = true
			c.allow_system_fallback = false
			c.antialiasing = f.antialiasing
			c.hinting = f.hinting
			c.subpixel_positioning = f.subpixel_positioning
			c.fixed_size = f.fixed_size
			c.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
			_font_free = c
			ResourceSaver.save(c, FONT_FREE_PATH)       # for BBCode [font=...] (the message log)
		else:
			_font_free = f
	return _font_free

## Red's menu cursor (green arrow), 8x8 in the cursor sheet.
static func cursor() -> AtlasTexture:
	if _cursor == null:
		_cursor = AtlasTexture.new()
		_cursor.atlas = load("res://assets/ui/cursors.png")
		_cursor.region = Rect2(40, 0, 8, 8)
	return _cursor

static func box(alpha := 0.93) -> StyleBoxFlat:
	# flat stand-in for callers that tweak a StyleBoxFlat; coloured like Red's window (frame() is the real one)
	var s := StyleBoxFlat.new()
	var wc := window_bg()
	s.bg_color = Color(wc.r, wc.g, wc.b, alpha)
	s.border_color = FRAME_MID
	s.set_border_width_all(2 * PX)
	s.set_corner_radius_all(3 * PX)
	s.content_margin_left = 6 * PX
	s.content_margin_right = 6 * PX
	s.content_margin_top = 3 * PX
	s.content_margin_bottom = 3 * PX
	s.shadow_color = FRAME_LIGHT
	s.shadow_size = 0
	s.anti_aliasing = false
	return s

# ------------------------------------------------------------------ Red's window frame + window colour
## Window background colours of the Windows option (game_options.c SetWindowBGColor): Blue, Red, Green.
const WINDOW_COLORS := [Color8(0x20, 0x48, 0x68), Color8(0x80, 0x38, 0x20), Color8(0x28, 0x80, 0x48)]
const FRAME_LIGHT := Color8(175, 199, 231)      # fontpal 15/14/13: the frame's three shades
const FRAME_MID := Color8(103, 135, 255)
const FRAME_DARK := Color8(79, 39, 255)
static var _frame_tex := {}                     # colour index -> ImageTexture (Red's 24x24 nine-patch at PX)
static var _frame_style: StyleBoxTexture        # shared by the theme: recoloured in place when the option changes
static var _frame_col := -1

## Game.settings.window_color (set by the Options menu): 0/1/2 or "Blue"/"Red"/"Green".
static func window_color_index() -> int:
	var v = Game.settings.get("window_color", 0) if Game else 0
	if v is String:
		match str(v).to_lower():
			"red":
				return 1
			"green":
				return 2
			_:
				return 0
	return clampi(int(v), 0, 2)

static func window_bg() -> Color:
	return WINDOW_COLORS[window_color_index()]

## Red's tiled window frame (font tiles 0x2D8-0x2DB from the ROM, assets/ui/front/window.png) in a colour.
static func frame_texture(ci := -1) -> Texture2D:
	if ci < 0:
		ci = window_color_index()
	if _frame_tex.has(ci):
		return _frame_tex[ci]
	var src: Texture2D = load("res://assets/ui/front/window.png")
	if src == null:
		return null
	var im: Image = src.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var wc: Color = WINDOW_COLORS[ci]
	for y in im.get_height():
		for x in im.get_width():
			var c := im.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.9 and c.b > 0.9 and c.g < 0.1:      # magenta = palette index 1 (window colour)
				im.set_pixel(x, y, wc)
	im.resize(im.get_width() * PX, im.get_height() * PX, Image.INTERPOLATE_NEAREST)
	var t := ImageTexture.create_from_image(im)
	_frame_tex[ci] = t
	return t

## A StyleBox with Red's window frame. The 7 px frame is drawn partly outside the control (expand margin) so
## content margins stay those of box(): layouts built for the flat box keep their size.
static func frame(alpha := 1.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = frame_texture()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		s.set_texture_margin(side, 8 * PX)
		s.set_expand_margin(side, 4 * PX)
	s.content_margin_left = 6 * PX
	s.content_margin_right = 6 * PX
	s.content_margin_top = 3 * PX
	s.content_margin_bottom = 3 * PX
	s.modulate_color = Color(1, 1, 1, alpha)
	return s

## Re-applies the window colour option to the shared theme frame (cheap; called by theme()).
static func sync_window_color() -> void:
	var ci := window_color_index()
	if ci == _frame_col or _frame_style == null:
		return
	_frame_col = ci
	_frame_style.texture = frame_texture(ci)

static func theme() -> Theme:
	if _theme:
		sync_window_color()
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = FONT_SIZE
	_frame_style = frame()
	_frame_col = window_color_index()
	t.set_stylebox("panel", "PanelContainer", _frame_style)
	t.set_stylebox("panel", "Panel", _frame_style)
	var btn := box(0.82)
	var btn_h := box(0.95)
	btn_h.bg_color = Color(0.16, 0.26, 0.62, 0.95)
	for k in ["normal", "disabled"]:
		t.set_stylebox(k, "Button", btn)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_h)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for c in ["Button", "Label"]:
		t.set_color("font_color", c, INK)
		t.set_color("font_shadow_color", c, SHADOW)
		t.set_constant("shadow_offset_x", c, PX)
		t.set_constant("shadow_offset_y", c, PX)
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_color("font_shadow_color", "RichTextLabel", SHADOW)
	t.set_constant("shadow_offset_x", "RichTextLabel", PX)
	t.set_constant("shadow_offset_y", "RichTextLabel", PX)
	t.set_constant("line_separation", "RichTextLabel", LINE - FONT_SIZE)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	_theme = t
	return t

## Red's text uses {color X}...{reset}; convert to BBCode.
static func red_text(s: String) -> String:
	var r := RegEx.new()
	r.compile("\\{color (\\w+)\\}")
	s = r.sub(s, "[color=$1]", true)
	s = s.replace("{reset}", "[/color]").replace("YELLOW", "#ffdc4a").replace("CYAN", "#7fe0ff").replace("RED", "#ff8070").replace("GREEN", "#7fff7f")
	s = glyph_tags(s)
	var r2 := RegEx.new()
	r2.compile("\\{[^}]*\\}")
	return r2.sub(s, "", true)

# ------------------------------------------------------------------ special text glyphs (kanji_a icons)
## Red's icon characters ({POKE}, {STAR_BULLET}, envelopes, {ICON_GO}, button glyphs ...) taken from the ROM's
## font (assets/ui/front/glyphs.png, see gen_front_assets.py). Multi-character icons are listed in order.
const GLYPH_PARTS := {"POKE": ["POKE_PO", "POKE_KE"], "START_BUTTON": ["START_BUTTON_1", "START_BUTTON_2"],
	"SELECT_BUTTON": ["SELECT_BUTTON_1", "SELECT_BUTTON_2"]}
static var _glyphs := {}

static func _glyph_meta() -> Dictionary:
	if _glyphs.is_empty():
		var f := FileAccess.open("res://assets/ui/front/glyphs.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_glyphs = d
	return _glyphs

## BBCode for one of Red's icon characters by its charmap name ("POKE", "A_BUTTON" ...), "" if unknown.
static func glyph(name: String) -> String:
	var meta := _glyph_meta()
	var parts: Array = GLYPH_PARTS.get(name, [name])
	var out := ""
	for p in parts:
		if not meta.has(p):
			return ""
		var g: Array = meta[p]
		out += "[img=%dx%d region=%d,0,%d,12]res://assets/ui/front/glyphs.png[/img]" % [int(g[1]) * PX, 12 * PX, int(g[0]), int(g[1])]
	return out

## Replaces {NAME} icon tags in a string with glyph images (other tags are left alone).
static func glyph_tags(s: String) -> String:
	if not s.contains("{"):
		return s
	var r := RegEx.new()
	r.compile("\\{([A-Z_]+)\\}")
	var out := ""
	var last := 0
	for m in r.search_all(s):
		var g := glyph(m.get_string(1))
		if g == "":
			continue
		out += s.substr(last, m.get_start() - last) + g
		last = m.get_end()
	return out + s.substr(last)

# ------------------------------------------------------------------ menu size (Game Options slider)
## Game.settings.ui_scale 0.70..1.50 in 0.05 steps, applied as the window's content_scale_factor (every menu,
## window and HUD scales; the dungeon/town/ground cameras divide their zoom by it so the map keeps its size).
const UI_SCALE_MIN := 0.7
const UI_SCALE_STEP := 0.05
const UI_SCALE_STEPS := 16

static func ui_scale() -> float:
	return clampf(float(Game.settings.get("ui_scale", 1.0)), UI_SCALE_MIN, UI_SCALE_MIN + UI_SCALE_STEP * UI_SCALE_STEPS)

static func ui_scale_index() -> int:
	return clampi(roundi((ui_scale() - UI_SCALE_MIN) / UI_SCALE_STEP), 0, UI_SCALE_STEPS)

static func set_ui_scale_index(i: int) -> void:
	Game.settings["ui_scale"] = snappedf(UI_SCALE_MIN + UI_SCALE_STEP * clampi(i, 0, UI_SCALE_STEPS), 0.01)
	apply_ui_scale()

## Keeps a window placed when the game window changes size or shape: layout(vs) positions / sizes `c` for the
## visible screen size vs. Called now (once `c` has its size) and again on every resize while `c` exists.
static func fit(c: Control, layout: Callable) -> void:
	c.set_meta("ui_fit", layout)
	c.add_to_group("ui_fit")
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if not tree.root.size_changed.is_connected(_refit_all):
		tree.root.size_changed.connect(_refit_all)
	if c.is_inside_tree():
		layout.call(c.get_viewport_rect().size)

static func _refit_all() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for pass_i in 2:                       # again a frame later, once containers have their new sizes
		for c in tree.get_nodes_in_group("ui_fit"):
			if is_instance_valid(c) and c.is_inside_tree() and c.has_meta("ui_fit"):
				(c.get_meta("ui_fit") as Callable).call(c.get_viewport_rect().size)
		if pass_i == 0:
			await tree.process_frame

static func apply_ui_scale() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.content_scale_factor = ui_scale()

## "◀ ▮▮▮▮▯▯▯ 100% ▶" built from two tiny slider segment images (the Red font has no block glyphs)
static func slider_text(i: int) -> String:
	var on := "[img width=%d height=%d]res://assets/ui/slider_on.png[/img]" % [3 * PX, 8 * PX]
	var off := "[img width=%d height=%d]res://assets/ui/slider_off.png[/img]" % [3 * PX, 8 * PX]
	var bar := ""
	for n in UI_SCALE_STEPS:
		bar += on if n < i else off
	var pct := roundi((UI_SCALE_MIN + UI_SCALE_STEP * i) * 100.0)
	return "%s %s [color=#ffdc4a]%d%%[/color] %s" % [TeamScreens.ARROW_L, bar, pct, TeamScreens.ARROW_R]
