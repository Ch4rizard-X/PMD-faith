class_name ListMenu
extends PanelContainer
## A Red-style pick-one menu. Await `choose()` for the picked index (-1 = cancelled).
## Works with keyboard (arrows / Enter / Esc / X), gamepad and touch.

signal picked(i: int)

var options: Array = []          # [{text, disabled?, hint?}]
var sel := 0
var _vbox: VBoxContainer
var _rows: Array = []
var _cursor: Label
var _title := ""
var allow_cancel := true
var _done := false
var on_select: Callable          # optional: called with index when the cursor moves
var _scroll: ScrollContainer
var _list: VBoxContainer
var remember := true             # come back to the row picked last time this menu was open (Yes/No prompts never do)

static var auto := false          # automated tests: menus pick their first enabled option
static var _auto_last := ""
static var _auto_rep := 0
static var _auto_burst := 0
static var _auto_t := 0
static var _cur_img: ImageTexture
static var _blank_img: ImageTexture
static var _mem := {}            # menu key -> last row (this run of the game)

## Menu memory, shared with TeamScreens.RedMenu. A menu is known by its title and rows with the numbers taken
## out (so "Job List (2/8)" is the same row as "Job List (3/8)"); when the rows changed (an item list after
## using an item) the title alone is used.
static func _mem_keys(title: String, texts: Array) -> Array:
	var rx := RegEx.create_from_string("[0-9]+|\\[[^\\]]*\\]")
	var t := rx.sub(title, "", true)
	var rows := []
	for x in texts:
		rows.append(rx.sub(str(x), "", true))
	var out := [t + "|" + "|".join(rows)]
	if t.strip_edges() != "":
		out.append(t + "|#")
	return out

static func _mem_ok(texts: Array) -> bool:
	return not texts.is_empty() and not ("Yes" in texts and "No" in texts)

static func recall(title: String, texts: Array) -> int:
	if not _mem_ok(texts):
		return -1
	for k in _mem_keys(title, texts):
		if _mem.has(k):
			return clampi(int(_mem[k]), 0, texts.size() - 1)
	return -1

static func memorize(title: String, texts: Array, i: int) -> void:
	if _mem_ok(texts) and i >= 0:
		for k in _mem_keys(title, texts):
			_mem[k] = i

func _texts() -> Array:
	return options.map(func(o): return str(o.get("text", "")))

## Red's green arrow, drawn at the UI pixel scale.
static func _cursor_icon() -> Texture2D:
	if _cur_img == null:
		var src: Image = load("res://assets/ui/cursors.png").get_image()
		if src.is_compressed():
			src.decompress()
		var im := src.get_region(Rect2i(40, 0, 8, 8))
		im.resize(8 * UITheme.PX, 8 * UITheme.PX, Image.INTERPOLATE_NEAREST)
		_cur_img = ImageTexture.create_from_image(im)
	return _cur_img

static func _blank_icon() -> Texture2D:
	if _blank_img == null:
		var im := Image.create(8 * UITheme.PX, 8 * UITheme.PX, false, Image.FORMAT_RGBA8)
		_blank_img = ImageTexture.create_from_image(im)
	return _blank_img

static func make(title: String, opts: Array, cancel := true) -> ListMenu:
	var m := ListMenu.new()
	m._title = title
	for o in opts:
		m.options.append(o if o is Dictionary else {"text": str(o)})
	m.allow_cancel = cancel
	return m

func _ready() -> void:
	theme = UITheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 0)
	add_child(_vbox)
	if _title != "":
		var t := Label.new()
		t.text = _title
		t.modulate = UITheme.GOLD
		_vbox.add_child(t)
	# long lists scroll: the rows sit in a ScrollContainer that is fitted to the screen and follows the cursor
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_vbox.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i].text)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.icon = _blank_icon()
		b.expand_icon = false
		b.add_theme_constant_override("h_separation", 2 * UITheme.PX)
		b.add_theme_color_override("font_color", UITheme.INK_DIM if options[i].get("disabled", false) else UITheme.INK)
		b.add_theme_color_override("font_hover_color", UITheme.INK)
		b.add_theme_color_override("font_pressed_color", UITheme.GOLD)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		b.custom_minimum_size = Vector2(0, UITheme.LINE)
		b.pressed.connect(_click.bind(i))
		b.mouse_entered.connect(func(): _set_sel(i))
		_list.add_child(b)
		_rows.append(b)
	_scroll.custom_minimum_size.y = options.size() * UITheme.LINE
	var start := sel
	if start == 0 and remember and not auto:
		var r := recall(_title, _texts())
		if r >= 0 and not options[r].get("disabled", false):
			start = r
	_set_sel(start)
	_fit_to_screen.call_deferred()
	get_viewport().size_changed.connect(_fit_to_screen)
	if allow_cancel:
		_add_backdrop.call_deferred()
	if auto:
		var pick := -1
		for i in options.size():
			if not options[i].get("disabled", false):
				pick = i
				break
		var sig := _title + "|" + str(options.size())
		var now := Time.get_ticks_msec()
		# the same menu straight back again within a moment = a loop; minutes apart is just a revisit
		_auto_rep = _auto_rep + 1 if (sig == _auto_last and now - _auto_t < 4000) else 0
		_auto_last = sig
		# a burst of menus with no break (shop / bank sub-menus cycling): back out
		_auto_burst = _auto_burst + 1 if now - _auto_t < 1500 else 0
		_auto_t = now
		if pick < 0 or _auto_rep >= 2 or _auto_burst >= 6:      # all disabled, or looping: back out
			pick = -1 if allow_cancel else options.size() - 1
			_auto_rep = 0       # backed out once: the next menu starts fresh
			_auto_burst = 0
			_auto_last = ""
		print("  MENU ", _title, " -> ", options[pick].text if pick >= 0 else "(cancel)")
		(func(): _finish(pick)).call_deferred()

## Touch: a transparent layer right behind the menu; tapping outside the menu cancels it (Red's B).
var _backdrop: Control
func _add_backdrop() -> void:
	var par := get_parent()
	if par == null or _done or not is_inside_tree():
		return
	_backdrop = Control.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var armed := [false]           # only a tap that starts on the backdrop (not the finger that opened the menu)
	_backdrop.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				armed[0] = true
			elif armed[0] and not _done:
				_finish(-1))
	par.add_child(_backdrop)
	par.move_child(_backdrop, get_index())
	tree_exiting.connect(func():
		if is_instance_valid(_backdrop):
			_backdrop.queue_free())

## Taller than the screen: the row area shrinks to fit (from the menu's top to the screen's bottom edge) and scrolls.
func _fit_to_screen() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var vh := get_viewport_rect().size.y
	var full := options.size() * UITheme.LINE
	var title_h := UITheme.LINE if _title != "" else 0
	var margin := 8.0 * UITheme.PX
	if global_position.y + title_h + full + margin > vh:
		if global_position.y + title_h + full + margin > vh and full + title_h + 2 * margin > vh:
			position.y = margin - (global_position.y - position.y)       # as high as it goes
		var avail := vh - global_position.y - title_h - margin * 2
		_scroll.custom_minimum_size.y = maxf(UITheme.LINE * 3, minf(full, avail))
		size.y = 0
	else:
		_scroll.custom_minimum_size.y = full
	_follow()

func _follow() -> void:
	if _scroll and sel >= 0 and sel < _rows.size():
		_scroll.ensure_control_visible(_rows[sel])

func _set_sel(i: int) -> void:
	if _rows.is_empty():
		return
	sel = clampi(i, 0, _rows.size() - 1)
	for j in _rows.size():
		_rows[j].icon = _cursor_icon() if j == sel else _blank_icon()
	_follow.call_deferred()
	if on_select.is_valid():
		on_select.call(sel)

func _click(i: int) -> void:
	if i < 0 or i >= options.size():
		return
	if options[i].get("disabled", false):
		Audio.sfx("error")
		return
	_set_sel(i)
	_finish(i)

var _result := -2

func _finish(i: int) -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_backdrop):
		_backdrop.queue_free()
	_result = i
	if remember and not auto:
		memorize(_title, _texts(), sel)
	Audio.sfx("confirm" if i >= 0 else "cancel")
	picked.emit(i)

func choose() -> int:
	var i: int = _result
	if not _done:
		i = await picked
	queue_free()
	return i

func _unhandled_input(e: InputEvent) -> void:
	if _done or not is_visible_in_tree():
		return
	if e.is_action_pressed("ui_down"):
		_set_sel((sel + 1) % _rows.size()); Audio.sfx("cursor")
	elif e.is_action_pressed("ui_up"):
		_set_sel((sel - 1 + _rows.size()) % _rows.size()); Audio.sfx("cursor")
	elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
		_click(sel)
	elif allow_cancel and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu")):
		_finish(-1)
	else:
		return
	get_viewport().set_input_as_handled()

func _gui_input(e: InputEvent) -> void:
	# tap outside the rows (on the panel's edge) does nothing; right click cancels
	if allow_cancel and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_finish(-1)
