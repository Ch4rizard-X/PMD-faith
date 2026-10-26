extends Control
## Visual check for scripts/ui/wonder_mail_ui.gd (password entry + Wonder Mail maker).
## Run: xvfb-run -a -s "-screen 0 1440x810x24" godot --path . --rendering-driver opengl3 --resolution 1440x810 res://tests/wm_test.tscn
## Types a real Red password with simulated key presses, drives the maker with simulated input, saves
## screenshots to user://wm_*.png and quits. The real save file is backed up and restored.

const CODE := "6?2Y5!+?45N7-!?FK4F5!R?W"    # Friend Area: Mt. Moonview (deliver job, Sinister Woods 7F)
var shot_n := 0
var _backup := ""
var _had_save := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.25, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_had_save = FileAccess.file_exists(Game.SAVE_PATH)
	if _had_save:
		_backup = FileAccess.get_file_as_string(Game.SAVE_PATH)
	Game.team_name = "Poképals"
	Game.team = [{"sp": "0025", "name": "Pikachu"}, {"sp": "0004", "name": "Charmander"}]
	Game.unlocked = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm", "mt_thunder"]
	Game.jobs = []
	Game.flags = {}
	for a in ["act_attack", "act_menu"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	_drive.call_deferred()

func _shot(name: String) -> void:
	for i in 4:
		await get_tree().process_frame
	var path := "user://wm_%02d_%s.png" % [shot_n, name]
	shot_n += 1
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func _press(action: String, times := 1) -> void:
	for i in times:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = true
		Input.parse_input_event(e)
		await get_tree().process_frame
		var r := InputEventAction.new()
		r.action = action
		r.pressed = false
		Input.parse_input_event(r)
		for k in 2:
			await get_tree().process_frame

func _key(code: Key, uni := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.unicode = uni
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame

func _type(s: String) -> void:
	for ch in s:
		await _key(KEY_NONE, ch.unicode_at(0))

func _find(cls) -> Node:
	for c in get_children():
		if is_instance_of(c, cls):
			return c
	return null

func _drive() -> void:
	# ---------------------------------------------------------------- wrong password, then the real one
	WonderMailUI.enter_code(self)
	await _shot("entry_empty")
	await _type("F?4N+WT??+6N")
	await _shot("entry_half")
	await _type("FR?JF?6685?X")                 # last symbol wrong
	await _shot("entry_full")
	await _key(KEY_ENTER)
	await _shot("entry_wrong")
	await _press("ui_accept")                    # "Yes" (enter it again)
	for i in 24:
		await _key(KEY_BACKSPACE)
	await _press("ui_down")
	await _press("ui_right", 3)
	await _shot("entry_cleared_nav")
	await _type(CODE.substr(0, 15))
	await _type("♂")                             # wrong on purpose, then Backspace
	await _key(KEY_BACKSPACE)
	await _type(CODE.substr(15))
	await _shot("entry_code")
	await _key(KEY_ENTER)
	await _shot("entry_info")
	await _press("ui_accept")                    # close info
	await _shot("entry_received")
	for i in 6:
		await _press("ui_accept")
	await _shot("entry_done")
	print("jobs after entry: ", Game.jobs.size(), " ", Game.jobs[0].title if Game.jobs.size() > 0 else "-")

	# ---------------------------------------------------------------- maker
	WonderMailUI.maker(self)
	await _shot("maker_kind")
	await _press("ui_down")                      # Rescue target
	await _press("ui_accept")
	await _shot("maker_dungeon")
	await _key(KEY_TAB)                          # all dungeons
	await _shot("maker_dungeon_all")
	await _press("ui_right", 2)
	await _shot("maker_dungeon_scrolled")
	await _key(KEY_TAB)                          # back to unlocked only
	await _press("ui_down", 5)                   # Mt. Thunder
	await _press("ui_accept")
	await _shot("maker_floor")
	await _press("ui_down", 4)
	await _press("ui_accept")
	await _shot("maker_client")
	await _type("pika")
	await _shot("maker_client_search")
	await _key(KEY_ENTER)
	await _shot("maker_target")
	await _press("ui_right", 3)
	await _press("ui_accept")
	await _shot("maker_reward")
	await _press("ui_up")                        # Friend Area (last row)
	await _press("ui_accept")
	await _shot("maker_area")
	await _press("ui_down")
	await _press("ui_accept")
	await _shot("maker_result")
	await _press("ui_right")
	await _press("ui_accept")                    # Copy code
	await _shot("maker_copied")
	print("clipboard: ", DisplayServer.clipboard_get())
	await _press("ui_left")
	await _press("ui_accept")                    # Add to Job List
	await _shot("maker_added_msg")
	await _press("ui_accept")
	await _press("ui_accept")
	await _shot("maker_added")
	await _press("ui_right", 3)
	await _press("ui_accept")                    # Edit -> back to the Friend Area list
	await _shot("maker_back")
	await _press("ui_cancel")                    # reward list
	await _press("ui_up", 2)
	await _press("ui_accept")                    # Item + ? + ?
	await _shot("maker_ritem")
	await _press("ui_accept")
	await _shot("maker_result2")
	await _press("ui_cancel")
	await _shot("maker_closed")
	print("jobs after maker: ", Game.jobs.size())
	for j in Game.jobs:
		print("  ", j.code, " ", j.kind, " ", j.dungeon, " ", j.floor, " ", j.title, " / ", Missions.reward_text(j))

	if _had_save:
		var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	elif FileAccess.file_exists(Game.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	print("WM_TEST_DONE")
	get_tree().quit()
