extends CanvasLayer
## First launch of a public build (no game data inside): builds the game's graphics, music and data into
## the player's storage (scripts/core/romdata.gd), then restarts into the game.
## For now the source is a folder holding assets/ and data/, made from the player's ROMs by the setup tools
## (SETUP.md); picking the ROMs directly comes next. Uses Godot's default look: the game's own font and
## windows are part of what is being set up. Loaded by path (no class_name).

const ROMDATA := preload("res://scripts/core/romdata.gd")

var _box: VBoxContainer
var _info: Label
var _status: Label
var _bar: ProgressBar
var _pick: Button
var _here: Button
var _start: Button
var _builder = null

func _ready() -> void:
	layer = 50
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(_box)
	var title := Label.new()
	title.text = "PMD-faith: first-time setup"
	title.add_theme_font_size_override("font_size", 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 8)
	_info.text = "This game ships without any of the original games' graphics, music or text. They are made " + \
		"from your own ROMs with the setup tools (see SETUP.md on the project page). Pick the game folder they " + \
		"made (the one holding \"assets\" and \"data\") and the game copies what it needs into its own storage. " + \
		"This takes a minute or two and is only needed once."
	_box.add_child(_info)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_box.add_child(row)
	_pick = Button.new()
	_pick.text = "  Choose the game folder...  "
	_pick.pressed.connect(_choose)
	_pick.add_theme_font_size_override("font_size", 9)
	row.add_child(_pick)
	var near := _nearby()
	if near != "":
		_here = Button.new()
		_here.text = "  Use %s  " % near
		_here.pressed.connect(_begin.bind(near))
		_here.add_theme_font_size_override("font_size", 9)
		row.add_child(_here)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(300, 8)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.visible = false
	_box.add_child(_bar)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 8)
	_box.add_child(_status)
	_start = Button.new()
	_start.text = "  Start the game  "
	_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_start.visible = false
	_start.pressed.connect(_restart)
	_start.add_theme_font_size_override("font_size", 9)
	_box.add_child(_start)
	if ROMDATA.installed() and not ROMDATA.present():
		_status.text = "The game data in storage couldn't be loaded. Pick the folder again to rebuild it."
	if OS.get_cmdline_user_args().has("--setupshot"):
		(func():
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png("user://setup.png")
			get_tree().quit()).call_deferred()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--setup-from="):             # tests / scripted setup
			_begin.call_deferred(a.substr(13))

## A game folder next to the program (or the folder the program is in), if it has what's needed.
func _nearby() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var cands: Array = []
	var d := exe_dir
	for k in 4:                                      # next to the program, or a few folders up (a project checkout)
		cands.append(d + "/game")
		cands.append(d)
		d = d.get_base_dir()
	for c in cands:
		if ROMDATA.check_source(c) == "":
			return c
	return ""

func _choose() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		_status.text = "No folder picker on this device. Put the folder named \"game\" next to the program and restart."
		return
	DisplayServer.file_dialog_show("Choose the game folder (with assets and data)", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
		"", false, DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, PackedStringArray(),
		func(ok: bool, paths: PackedStringArray, _filter: int):
			if ok and paths.size() > 0:
				_begin(paths[0]))

func _begin(src: String) -> void:
	var err := ROMDATA.check_source(src)
	if err != "":
		_status.text = err
		return
	_builder = ROMDATA.Builder.new()
	err = _builder.start(src)
	if err != "":
		_status.text = err
		_builder = null
		return
	_pick.disabled = true
	if _here:
		_here.disabled = true
	_bar.visible = true
	_status.text = "Preparing..."

func _process(_dt: float) -> void:
	if _builder == null:
		return
	var finished: bool = _builder.step(40)
	_bar.value = _builder.progress() * 100.0
	_status.text = "%d / %d  %s" % [_builder.i, _builder.files.size(), _builder.current()]
	if not finished:
		return
	if _builder.error != "":
		_status.text = "Setup stopped: " + _builder.error
		_pick.disabled = false
		if _here:
			_here.disabled = false
		_builder = null
		return
	var st: Dictionary = _builder.stats
	_status.text = "Done in %.0f s: %d images, %d sounds, %d data files (%.0f MB)." % [_builder.seconds(), st.img, st.audio, st.raw, st.bytes / 1048576.0]
	_builder = null
	_start.visible = true
	if OS.get_cmdline_user_args().has("--setup-quit"):
		get_tree().quit()

func _restart() -> void:
	if OS.get_name() in ["Windows", "Linux", "macOS"]:
		OS.set_restart_on_exit(true, OS.get_cmdline_args())
		get_tree().quit()
	else:
		_status.text = "Close the game and open it again to play."
