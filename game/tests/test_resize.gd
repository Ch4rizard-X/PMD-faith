extends Node
## --resizetest: opens screens, changes the window's shape, and saves user://resize_<screen>_<n>.png for each
## size, to check that windows follow the new screen size.
var m
## the visible area a window of that shape gives (stretch aspect expand on 480 x 270)
const SIZES := [Vector2i(480, 270), Vector2i(480, 450), Vector2i(712, 270), Vector2i(480, 270)]

func _ready() -> void:
	m = get_parent()
	Dialog.auto = true
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	await m.start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(2.0).timeout
	var d = m.dungeon
	Dialog.auto = false
	# dungeon main menu (with the name and team info windows)
	d.open_main_menu()
	await _cycle("dmenu")
	Input.action_press("ui_cancel"); await get_tree().process_frame; Input.action_release("ui_cancel")
	await get_tree().create_timer(0.4).timeout
	# a message box with Yes / No
	Dialog.ask(m.root, "Do you want to test resizing the window?", ["Yes", "No"])
	await _cycle("ask")
	Input.action_press("ui_cancel"); await get_tree().process_frame; Input.action_release("ui_cancel")
	await get_tree().create_timer(0.4).timeout
	# Game Options
	GameOptions.page(m.root, "Dungeon")
	await _cycle("options")
	print("RESIZETEST done")
	get_tree().quit()

func _cycle(tag: String) -> void:
	for i in SIZES.size():
		get_tree().root.content_scale_size = SIZES[i]
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("user://resize_%s_%d.png" % [tag, i])
		print("RESIZETEST ", tag, " ", i, " window=", DisplayServer.window_get_size(), " view=", get_viewport().get_visible_rect().size)
