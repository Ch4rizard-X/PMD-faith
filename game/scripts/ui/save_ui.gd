class_name SaveUI
extends RefCounted
## Red's save messages and the blinking saving icon (fontsp OBJ tiles 0x3FC-0x3FF, a yellow warning triangle).
##
##   await SaveUI.save_ground(root)        # save_write.c (team base bed, SPECIAL_TEXT_SAVE_1/2, base menu)
##   await SaveUI.quicksave_done(root)     # quick_save_write.c, after the dungeon's Quicksave command
##   await SaveUI.save_menu(root)          # save_menu.c window used by the main menu (Wonder Mail ...)
##   await SaveUI.delete_menu(root)        # save_menu.c MENU_DELETE_SAVE: deletes save + quicksave
##
## The icon blinks every 16 frames (sprite.c BlinkSavingIcon) at Red's spots: (200,128) for the text-box saves
## (sub_80140DC) and (188,64) for the main-menu save window (sub_80140F8). Red's 160 px screen is mapped to
## the 135 px UI by keeping the distance to the bottom edge.

const ICON_TEXTBOX := Vector2(200, 128)
const ICON_WINDOW := Vector2(188, 64)

## Red px (240x160 screen) -> UI px, centred horizontally, bottom-aligned vertically.
static func _gba(root: Control, p: Vector2) -> Vector2:
	var vs := root.get_viewport_rect().size / UITheme.PX
	return Vector2(floorf((vs.x - 240) / 2) + p.x, vs.y - (160 - p.y)) * UITheme.PX

static func _tile(t: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/ui/front/fontsp.png")
	at.region = Rect2(t * 8, 0, 8, 8)
	return at

## The 16x16 saving icon (tiles 12, 13 / 14, 15 of fontsp) as a blinking node.
class SavingIcon extends Control:
	var t := 0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 60
		size = Vector2(16, 16) * UITheme.PX
		for i in 4:
			var tr := TextureRect.new()
			tr.texture = SaveUI._tile(12 + i)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.size = Vector2(8, 8) * UITheme.PX
			tr.position = Vector2((i % 2) * 8, (i / 2) * 8) * UITheme.PX
			add_child(tr)
	func _process(_dt: float) -> void:
		t += 1
		visible = (t & 16) == 0

static func show_icon(root: Control, red_pos: Vector2) -> Control:
	var ic := SavingIcon.new()
	root.add_child(ic)
	ic.position = _gba(root, red_pos)
	return ic

## A text box that stays up (no key wait) while something happens.
static func _box(root: Control, msg: String) -> Dialog:
	var d := Dialog.get_box(root)
	d._show(msg, "", "Normal", "")
	d._finish_typing()
	return d

static func _center(lines: String) -> String:
	return "[center]" + lines + "[/center]"

## save_write.c: "Saving your adventure..." with the saving icon, the write, then "Save completed!".
static func save_ground(root: Control) -> bool:
	var d := _box(root, _center("Saving your adventure...\nPlease don't turn off the power."))
	var ic := show_icon(root, ICON_TEXTBOX)
	await root.get_tree().create_timer(0.6).timeout
	var ok := _write()
	ic.queue_free()
	d.hide_box()
	await Dialog.say(root, _center("Save completed!" if ok else "Save failed."))
	return ok

## quick_save_write.c (unkC == 0): the texts after the dungeon's Quicksave (the file is already written).
static func quicksave_done(root: Control) -> void:
	var d := _box(root, _center("Quicksaving your adventure...\nPlease don't turn off the power."))
	var ic := show_icon(root, ICON_TEXTBOX)
	await root.get_tree().create_timer(0.6).timeout
	ic.queue_free()
	d.hide_box()
	await Dialog.talk(root, [_center("Your adventure has been saved.\nWhen you resume play, the quicksave\ndata will be deleted."),
		_center("When you are shutting down the game,\nsave your progress in your team base,\nor quicksave in a dungeon.")])

## save_menu.c window (5,8) 21x5: three centred lines; returns when A / B closes the result.
static func _window(root: Control, lines: Array) -> Array:
	var panel := PanelContainer.new()
	panel.theme = UITheme.theme()
	panel.add_theme_stylebox_override("panel", UITheme.frame())
	panel.custom_minimum_size = Vector2(21 * 8, 5 * 8) * UITheme.PX
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.custom_minimum_size = Vector2(21 * 8 - 12, 0) * UITheme.PX
	panel.add_child(rt)
	root.add_child(panel)
	panel.position = _gba(root, Vector2(5 * 8, 8 * 8))
	_set_lines(rt, lines)
	return [panel, rt]

static func _set_lines(rt: RichTextLabel, lines: Array) -> void:
	rt.text = "[center]" + "\n".join(PackedStringArray(lines)) + "[/center]"

static func _wait_key(root: Control, panel: Control) -> void:
	var arrow := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/ui/front/fontsp.png")
	at.region = Rect2(0, 0, 16, 8)        # OBJ tile 0x3F0, 16x8 (sub_8038830 at 112,104)
	arrow.texture = at
	arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_SCALE
	arrow.size = Vector2(16, 8) * UITheme.PX
	arrow.z_index = 60
	root.add_child(arrow)
	arrow.position = _gba(root, Vector2(112, 104))
	var tree := root.get_tree()
	var f := 0
	if ListMenu.auto or Dialog.auto:
		await tree.create_timer(0.2).timeout
	else:
		await release_keys(tree)
		var keys := KeyCatch.new()
		panel.add_child(keys)
		while true:
			await tree.process_frame
			f += 1
			arrow.visible = (f & 8) != 0
			if keys.pop() in ["a", "b", "tap"]:
				Audio.sfx("text")
				break
	arrow.queue_free()
	panel.queue_free()

static func save_menu(root: Control) -> bool:
	var w := _window(root, ["[color=#ff8070]Beware![/color]", "Saving your adventure!", "Don't turn off the power."])
	var ic := show_icon(root, ICON_WINDOW)
	await root.get_tree().create_timer(0.6).timeout
	var ok := _write()
	ic.queue_free()
	if ok:
		_set_lines(w[1], ["[color=#7fe0ff]Success![/color]", "Your adventure so far", "has been saved."])
	else:
		_set_lines(w[1], ["[color=#ff8070]Save failed![/color]", "Your adventure could not be saved.", "Please try again."])
	await _wait_key(root, w[0])
	return ok

static func delete_menu(root: Control) -> bool:
	var w := _window(root, ["[color=#ff8070]Beware![/color]", "Deleting your adventure!", "Don't turn off the power."])
	var ic := show_icon(root, ICON_WINDOW)
	await root.get_tree().create_timer(0.6).timeout
	var ok := delete_all()
	ic.queue_free()
	if ok:
		_set_lines(w[1], ["[color=#7fe0ff]Success![/color]", "Your adventure has been deleted.", " "])
	else:
		_set_lines(w[1], ["[color=#ff8070]Deletion failed![/color]", "Your adventure could not be deleted.", "Please try again."])
	await _wait_key(root, w[0])
	return ok

static func _write() -> bool:
	Game.save_game(true)
	return FileAccess.file_exists(Game.SAVE_PATH)

## Deletes the adventure (save.json's game data + the dungeon suspend file) and resets the loaded game
## (sub_80122A8 + the write). Settings (volume, controls, window colour ...) are kept.
static func delete_all() -> bool:
	DungeonSave.clear()
	if FileAccess.file_exists(Game.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	Game.team_name = "Team"
	Game.team = []
	Game.hero = {}
	Game.partner = {}
	Game.story = {}
	Game.flags = {}
	Game.friends = []
	Game.friend_areas = []
	Game.bag = []
	Game.storage = {}
	Game.jobs = []
	Game.board = []
	Game.board_day = -1
	Game.day = 0
	Game.money = 0
	Game.bank = 0
	Game.rank_points = 0
	Game.unlocked = ["tiny_woods"]
	Game.cleared = []
	Game.nature = ""
	Game.gender = ""
	GVars.reset_all()
	Game.save_game(true)      # keeps Game.settings; with no team there is no save to continue
	return not Game.has_save()

## Collects key presses from input events (polling is_action_just_pressed misses quick taps): pop() returns
## "a", "b", "left", "right", "up", "down", "tap" or "".
class KeyCatch extends Node:
	var q: Array = []
	func pop() -> String:
		return "" if q.is_empty() else str(q.pop_front())
	func _unhandled_input(e: InputEvent) -> void:
		var k := ""
		if e.is_action_pressed("ui_right") or e.is_action_pressed("move_right"):
			k = "right"
		elif e.is_action_pressed("ui_left") or e.is_action_pressed("move_left"):
			k = "left"
		elif e.is_action_pressed("ui_up") or e.is_action_pressed("move_up"):
			k = "up"
		elif e.is_action_pressed("ui_down") or e.is_action_pressed("move_down"):
			k = "down"
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			k = "a"
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_run") or e.is_action_pressed("act_menu"):
			k = "b"
		elif e is InputEventMouseButton and e.pressed:
			k = "tap" if e.button_index == MOUSE_BUTTON_LEFT else ("b" if e.button_index == MOUSE_BUTTON_RIGHT else "")
		if k != "":
			q.append(k)
			get_viewport().set_input_as_handled()

## Waits until A / B / Start are released (so the press that opened a screen doesn't also close it).
static func release_keys(tree: SceneTree) -> void:
	await tree.process_frame
	for i in 120:
		var held := false
		for a in ["ui_accept", "ui_cancel", "act_attack", "act_run", "act_menu"]:
			if InputMap.has_action(a) and Input.is_action_pressed(a):
				held = true
		if not held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return
		await tree.process_frame
