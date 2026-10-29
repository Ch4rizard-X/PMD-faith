class_name MainMenu
extends Control
## Red's main menu / file select (main_loops.c GameLoop_Async + main_menu1.c / main_menu2.c).
##
##   await MainMenu.run(main)     # main.gd: shows the menu and starts New Game / Continue / the quicksave
##
## Background: one of the three titlen paintings (assets/ui/menu_artwork_1..3.png = titlen0..2) faded in from
## black over 32 frames, music 008 (MUS_FILE_SELECT). Window 0 at (2,2) lists the entries for the save state
## (SetMainMenuItems): New Game / Adventure Log without a save, else Continue / Delete Save Data /
## Adventure Log / Friend Rescue / Trade Items / Wonder Mail. The description window at (2,15) explains the
## highlighted entry (SetMainMenuText). Holding L hides the windows to show the painting.
## Continue goes through main.gd's load screen ("Resuming saved adventure." / "Resuming from quicksave.").

const DESCRIPTIONS := {
	"New Game": ["Start an entirely new adventure.", "  "],
	"Adventure Log": ["Check your career as an adventurer.", "  "],
	"Continue": ["Resume your adventure from where", "you last saved.  "],
	"Delete Save Data": ["This will delete your saved game data.", "[color=#ff8070]Beware[/color]! This will delete it forever!"],
	"Friend Rescue": ["Using a Game Link cable or", "passwords, friends may rescue each other."],
	"Trade Items": ["Using a Game Link cable, you can", "trade stored items with a friend."],
	"Wonder Mail": ["Using passwords, you can", "receive Wonder Mail."],
	"Awaiting Rescue": ["You are awaiting rescue by a friend.", "You can give up waiting for rescue."],
	"Revive Team": ["Resume your adventure from where", "you last saved.  "],
}

var host                          # main.gd
var bg: TextureRect
var windows: Control              # list + description (hidden while L is held)
var desc: RichTextLabel
var desc_panel: PanelContainer
var _l_hidden := false
var _last := 0                    # cursor kept between visits (sUnknown_203B350)

static func run(h) -> void:
	var mm := MainMenu.new()
	mm.host = h
	h.root.add_child(mm)
	await mm._main()

func _ready() -> void:
	theme = UITheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg = TextureRect.new()
	bg.texture = DB.tex("res://assets/ui/menu_artwork_%d.png" % (randi() % 3 + 1))     # LoadTitleScreen: RandInt(3)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.modulate = Color.BLACK
	add_child(bg)
	var ver := Label.new()                     # remake: the running version (+ "patch" when a script patch is mounted)
	ver.text = "v%s%s" % [Patcher.version_name(), " (patch)" if Patcher.is_patched() else ""]
	ver.add_theme_font_size_override("font_size", 9 * UITheme.PX)
	ver.add_theme_color_override("font_color", Color.WHITE)
	ver.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	ver.add_theme_constant_override("shadow_offset_x", UITheme.PX)
	ver.add_theme_constant_override("shadow_offset_y", UITheme.PX)
	ver.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.position += Vector2(-3, 1) * UITheme.PX
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)
	windows = Control.new()
	windows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	windows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(windows)

## Red px -> UI px inside the 240 x 135 area (centred); y >= 80 is kept relative to the bottom edge.
func _red(p: Vector2) -> Vector2:
	var vs := get_viewport_rect().size / UITheme.PX
	var x := floorf((vs.x - 240) / 2) + p.x
	var y := floorf((vs.y - 135) / 2) + p.y if p.y < 80 else vs.y - (160 - p.y)
	return Vector2(x, y) * UITheme.PX

func _process(_dt: float) -> void:
	# main_loops.c: L pressed hides BG0/BG1 (the windows) until it is released
	var l := Input.is_action_pressed("gp_l") or Input.is_action_pressed("act_log")
	if l != _l_hidden:
		_l_hidden = l
		windows.visible = not l

func _fade(to_white: bool) -> void:
	var tree := get_tree()
	for i in 32:                                    # sTitleBrightness 0..32, one step per frame
		var b := float(i + 1) / 32.0 if to_white else 1.0 - float(i + 1) / 32.0
		bg.modulate = Color(b, b, b)
		await tree.process_frame

## SetMainMenuItems
func entries() -> Array:
	if not Game.has_save():
		return ["New Game", "Adventure Log"]
	return ["Continue", "Delete Save Data", "Adventure Log", "Friend Rescue", "Trade Items", "Wonder Mail"]

func _main() -> void:
	Audio.play_music("008")
	await _fade(true)
	Patcher.boot_ok()
	while true:
		if Patcher.pending != "" and not ListMenu.auto:
			await _offer_update()
		var opts := entries()
		var pick := await _choose(opts)
		var what: String = opts[pick]
		match what:
			"New Game":
				await _leave()
				host.new_game()
				return
			"Continue":
				windows.visible = false
				var go: bool = await host._load_screen()
				if go:
					await _leave()
					if DungeonSave.has_suspend():
						host.resume_dungeon()
					else:
						host.continue_story()
					return
			"Delete Save Data":
				windows.visible = false
				if await host._load_screen("Your saved data will be\ndeleted. Is that OK?") \
						and await host._load_screen("Are you sure you want to\ndelete all of your saved data?"):
					await SaveUI.delete_menu(host.root)
					_last = 0
			"Adventure Log":
				windows.visible = false
				await AdventureLog.open(host.root)
			"Friend Rescue":
				windows.visible = false
				await FriendRescue.counter(host.root)      # Get Help / Go Rescue by password (scripts/town/friend_rescue.gd)
				Game.save_game()
			"Trade Items":
				windows.visible = false
				await TradeItems.open(host.root)
			"Wonder Mail":
				windows.visible = false
				var job: Dictionary = await WonderMailUI.enter_code(host.root)
				if not job.is_empty():
					await Dialog.say(host.root, "Your adventure will be saved.")
					await SaveUI.save_menu(host.root)
		windows.visible = not _l_hidden
		if ListMenu.auto:
			return

## A script patch finished downloading (scripts/core/patcher.gd): restart into it now or on the next start.
func _offer_update() -> void:
	var v := Patcher.pending
	windows.visible = false
	var yes := await Dialog.ask(host.root, "Version %s has been downloaded.\nRestart now to update?" % v, ["Yes", "No"]) == 0
	if yes:
		if OS.get_name() == "Android":
			await Dialog.say(host.root, "The game will close now.\nOpen it again to play version %s." % v)
		Patcher.restart()
		return
	Patcher.pending = ""                  # still applied the next time the game starts
	await Dialog.say(host.root, "The update will be used the next\ntime you start the game.")
	windows.visible = not _l_hidden

func _leave() -> void:
	for c in windows.get_children():
		c.queue_free()
	await _fade(false)
	queue_free()

## The list window + the description window; returns the picked index (B does nothing on this screen).
func _choose(opts: Array) -> int:
	for c in windows.get_children():
		c.queue_free()
	var lm := ListMenu.make("", opts, false)
	lm.custom_minimum_size.x = (88 + 12) * UITheme.PX
	windows.add_child(lm)
	lm.position = _red(Vector2(16 - 6, 8 - 3))
	desc_panel = PanelContainer.new()
	desc_panel.add_theme_stylebox_override("panel", UITheme.frame())
	desc_panel.custom_minimum_size = Vector2(208 + 12, 24 + 6) * UITheme.PX
	desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc = RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.scroll_active = false
	desc.fit_content = true
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	desc_panel.add_child(desc)
	windows.add_child(desc_panel)
	desc_panel.position = _red(Vector2(16 - 6, 120 - 3))
	lm.on_select = func(i):
		var d: Array = DESCRIPTIONS.get(str(opts[i]), ["", ""])
		desc.text = "%s\n%s" % [d[0], d[1]]
	var start := clampi(_last, 0, opts.size() - 1)
	await get_tree().process_frame
	if is_instance_valid(lm):
		lm._set_sel(start)
	var i := await lm.choose()
	_last = i
	return i
