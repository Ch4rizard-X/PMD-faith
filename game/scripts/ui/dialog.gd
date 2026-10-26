class_name Dialog
extends Control
## Red-style talk box at the bottom of the screen, with an optional speaker portrait (40x40 from the
## species' sprite sheet) and typewriter text. One instance lives under the UI root (see Dialog.get_box()).
##
##   await Dialog.say(root, "Hello!", "0054")            # speaker species key, "" = no portrait
##   var i := await Dialog.ask(root, "Go in?", ["Yes", "No"], "0039")   # -1 if cancelled
##
## Text supports BBCode ([color=#ffdc4a]...[/color]). Tap / Space / Enter / the A button advances.

signal _advance

static var auto := false          # automated tests: text boxes advance by themselves

var panel: PanelContainer
var text: RichTextLabel
var portrait: TextureRect
var port_frame: PanelContainer
var name_label: Label
var _typing := false
var _visible_chars := 0.0
const CPS := 60.0                 # characters per second

static func get_box(root: Control) -> Dialog:
	for c in root.get_children():
		if c is Dialog and not c.is_queued_for_deletion():
			return c
	var d := Dialog.new()
	root.add_child(d)
	return d

static func say(root: Control, msg: String, speaker := "", emotion := "Normal", speaker_name := "") -> void:
	var d := get_box(root)
	await d._say(msg, speaker, emotion, speaker_name)
	d.hide_box()

## Several lines in a row without closing the box between them.
static func talk(root: Control, lines: Array, speaker := "", emotion := "Normal", speaker_name := "") -> void:
	var d := get_box(root)
	for l in lines:
		await d._say(str(l), speaker, emotion, speaker_name)
	d.hide_box()

static func ask(root: Control, msg: String, options: Array, speaker := "", emotion := "Normal", cancel := true) -> int:
	var d := get_box(root)
	d._show(msg, speaker, emotion, "")
	d._finish_typing()
	var lm := ListMenu.make("", options, cancel)
	root.add_child(lm)
	await root.get_tree().process_frame
	var vs := root.get_viewport_rect().size
	lm.position = Vector2(vs.x - lm.size.x - 8, d.panel.position.y - lm.size.y - 4)
	var i := await lm.choose()
	d.hide_box()
	return i

func _ready() -> void:
	theme = UITheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 4 * UITheme.PX
	panel.offset_right = -4 * UITheme.PX
	panel.offset_top = -(3 * UITheme.LINE + 10 * UITheme.PX)
	panel.offset_bottom = -2 * UITheme.PX
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(_panel_input)
	add_child(panel)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(text)
	port_frame = PanelContainer.new()
	port_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UITheme.box()
	sb.content_margin_left = UITheme.PX
	sb.content_margin_right = UITheme.PX
	sb.content_margin_top = UITheme.PX
	sb.content_margin_bottom = UITheme.PX
	port_frame.add_theme_stylebox_override("panel", sb)
	add_child(port_frame)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(40, 40) * UITheme.PX
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	port_frame.add_child(portrait)
	name_label = Label.new()
	name_label.add_theme_color_override("font_color", UITheme.GOLD)
	add_child(name_label)
	hide_box()

func hide_box() -> void:
	panel.visible = false
	port_frame.visible = false
	name_label.visible = false

static func portrait_tex(sp: String, emotion := "Normal") -> Texture2D:
	if sp.ends_with("*"):                    # shiny
		var base := sp.substr(0, sp.length() - 1)
		var t0 := portrait_tex(base, emotion)
		return Shiny.portrait(t0, base) if t0 is AtlasTexture else t0
	var man: Dictionary = DB.sprites.get(sp, {})
	var por: Dictionary = man.get("por", {})
	if por.is_empty():
		return null
	var r: Array = por.get(emotion, por.get("Normal", por.values()[0]))
	var at := AtlasTexture.new()
	at.atlas = DB.tex("res://assets/sp/" + (str(r[4]) if r.size() > 4 else str(man.sheet)))
	at.region = Rect2(r[0], r[1], r[2], r[3])
	return at

func _show(msg: String, speaker: String, emotion: String, speaker_name: String) -> void:
	panel.visible = true
	text.text = msg
	text.visible_characters = 0
	_visible_chars = 0.0
	_typing = true
	var tex: Texture2D = portrait_tex(speaker, emotion) if speaker != "" else null
	port_frame.visible = tex != null
	if tex:
		portrait.texture = tex
		await get_tree().process_frame
		port_frame.position = Vector2(4 * UITheme.PX, panel.position.y - port_frame.size.y - 2 * UITheme.PX)
	var nm := speaker_name
	if nm == "" and speaker != "" and DB.species.has(speaker):
		nm = DB.species[speaker].name
	name_label.visible = false   # Red shows the name in the text itself ("Name: ...")

func _finish_typing() -> void:
	_typing = false
	text.visible_characters = -1

func _say(msg: String, speaker: String, emotion: String, speaker_name: String) -> void:
	_show(msg, speaker, emotion, speaker_name)
	if auto:
		print("  DIALOG ", msg.replace("\n", " | ").left(160))
		await get_tree().create_timer(0.15).timeout
		return
	await _advance

func _process(dt: float) -> void:
	if _typing:
		_visible_chars += dt * [30.0, CPS, 240.0][clampi(int(Game.settings.get("msg_speed", 1)), 0, 2)]
		text.visible_characters = int(_visible_chars)
		if text.visible_characters >= text.get_total_character_count():
			_finish_typing()

var _press_frame := -1

## One tap arrives as a touch AND an emulated mouse click (or a click plus an emulated touch on
## desktop) in the same frame: count it once, or a single tap would finish the text and close it.
func _press() -> void:
	if not panel.visible:
		return
	if Engine.get_process_frames() == _press_frame:
		return
	_press_frame = Engine.get_process_frames()
	if _typing:
		_finish_typing()
	else:
		Audio.sfx("text")
		_advance.emit()

func _panel_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_press()
		accept_event()

func _unhandled_input(e: InputEvent) -> void:
	if not panel.visible:
		return
	if e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack") or e.is_action_pressed("ui_cancel") or (e is InputEventScreenTouch and e.pressed):     # Red: B advances text too
		# a menu open on top handles its own input
		for c in get_parent().get_children():
			if c is ListMenu:
				return
		_press()
		get_viewport().set_input_as_handled()
