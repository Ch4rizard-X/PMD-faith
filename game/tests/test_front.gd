extends Node
## --fronttest : boot demos, main menu, load screen, Delete Save Data, Adventure Log, Trade Items, naming screen,
## password entry, save windows, window colours and text glyphs (agent "front"). Screenshots: user://front_*.png.
## Optional: --frontpart=boot|menu|ui to run one part. Run with your own XDG_DATA_HOME.

var main
var part := ""

func _ready() -> void:
	main = get_parent()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--frontpart="):
			part = a.substr(12)
	_run.call_deferred()

func shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://front_%s.png" % name)
	print("FRONT shot ", name)

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func press(action: String, hold := 0.0) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	if hold > 0:
		await wait(hold)
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame

func _run() -> void:
	if part == "" or part == "boot":
		await _boot()
	if part == "" or part == "menu":
		await _menu()
	if part == "" or part == "ui":
		await _ui()
	print("FRONTTEST done")
	get_tree().quit()

func _boot() -> void:
	GData.load_all()
	GVars.reset_all()
	var t0 := Time.get_ticks_msec()
	_go(1, false)
	await wait(1.5)
	await shot("boot1_warning")
	await wait(3.5)
	print("FRONT fps ", Engine.get_frames_per_second())
	for i in 4:
		await shot("boot1_warning_b%d" % i)
		await wait(0.13)
	await press_ok("ui_accept")
	await wait(0.3)
	await press_ok("ui_accept")
	while main.ground != null and is_instance_valid(main.ground) and main.ground.demo:
		await wait(0.2)
		if Time.get_ticks_msec() - t0 > 90000:
			break
	print("FRONT demo1 ended after ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	await wait(0.2)
	t0 = Time.get_ticks_msec()
	_go(2, false)
	for i in 5:
		await wait(1.2)
		await shot("boot2_company_%d" % i)
	while is_instance_valid(main.ground) and main.ground != null and main.ground.demo and Time.get_ticks_msec() - t0 < 30000:
		await wait(0.2)
	print("FRONT demo2 ended after ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	await wait(0.2)
	t0 = Time.get_ticks_msec()
	_go(3, true)
	for i in 8:
		await wait(2.5)
		await shot("boot3_intro_%d" % i)
	await press_ok("ui_accept")
	while is_instance_valid(main.ground) and main.ground != null and main.ground.demo and Time.get_ticks_msec() - t0 < 60000:
		await wait(0.2)
	print("FRONT demo3 ended after ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	await wait(0.2)
	_go(4, true)
	for i in 6:
		await wait(1.0)
		await shot("boot4_title_%d" % i)
	await wait(0.13)
	await shot("boot4_title_b")
	await press_ok("ui_accept")
	await wait(1.5)

func _menu() -> void:
	# no save: New Game / Adventure Log
	SaveUI.delete_all()
	main.title()
	await wait(3.0)
	await shot("menu_nosave")
	main._clear()
	await wait(0.2)
	# with a save + a quicksave
	Game.new_game("0025", "Pikachu", "0004", "Charmander", "Team")
	Game.story_set("team_name", "Poképals")
	Game.flags["adventures"] = 7
	Game.flags["aa"] = 0b1000001000000000000000000000111
	Game.flags["aa_floors"] = 42
	Game.flags["aa_joined"] = 3
	Game.save_game()
	main.title()
	await wait(3.0)
	await shot("menu_save")
	await press_ok("ui_down")
	await wait(0.2)
	await shot("menu_save_delete")
	Input.action_press("gp_l")
	await wait(0.3)
	await shot("menu_l_hidden")
	Input.action_release("gp_l")
	await wait(0.2)
	# Adventure Log
	await press_ok("ui_down")
	await press_ok("ui_accept")
	await wait(0.6)
	await shot("adventure_log_p1")
	await press_ok("ui_right")
	await wait(0.3)
	await shot("adventure_log_p2")
	await press_ok("ui_cancel")
	await wait(0.4)
	# Trade Items
	await press_ok("ui_down")
	await press_ok("ui_down")
	await press_ok("ui_accept")
	await wait(0.5)
	await shot("trade_items")
	await press_ok("ui_down")
	await press_ok("ui_accept")      # Receive item
	await wait(1.0)
	await press_ok("ui_accept")
	await wait(0.3)
	await shot("trade_link_prompt")
	await press_ok("ui_accept")      # Yes
	await wait(0.6)
	await shot("trade_in_comm")
	await wait(2.0)
	await shot("trade_error")
	for i in 6:
		await press_ok("ui_accept")
		await wait(0.4)
	await press_ok("ui_cancel")
	await wait(0.6)
	# Delete Save Data -> load screen prompt (fresh menu: cursor on Continue)
	main._clear()
	await wait(0.2)
	main.title()
	await wait(2.0)
	await press_ok("ui_down")
	await press_ok("ui_accept")
	await wait(0.6)
	await shot("delete_prompt")
	await press_ok("ui_down")
	await press_ok("ui_accept")      # No
	await wait(0.6)
	# Continue -> load screen (cursor kept on Delete Save Data)
	await press_ok("ui_up")
	await press_ok("ui_accept")
	await wait(0.6)
	await shot("load_screen")
	await press_ok("ui_down")
	await press_ok("ui_accept")      # No
	await wait(0.6)
	# Friend Rescue (cursor on Continue)
	for i in 3:
		await press_ok("ui_down")
	await press_ok("ui_accept")
	await wait(0.8)
	await shot("friend_rescue")
	await press_ok("ui_cancel")
	await wait(0.6)
	await shot("menu_back")
	main._clear()

func _ui() -> void:
	var root: Control = main.root
	main._clear()
	if not Game.has_save():
		Game.new_game("0025", "Pikachu", "0004", "Charmander", "Team")
	_bg(root)
	# naming screen: hero name
	var r := [""]
	var f := func(): r[0] = await NamingScreen.ask(root, NamingScreen.SELF, "Pikachu")
	f.call()
	await wait(0.5)
	await press_ok("ui_right")
	await press_ok("ui_down")
	await press_ok("ui_accept")
	await wait(0.3)
	await shot("naming_self")
	await press("act_menu")       # Start -> END
	await wait(0.2)
	await shot("naming_self_end")
	await press_ok("ui_accept")
	await wait(0.5)
	await shot("naming_confirm")
	await press_ok("ui_accept")
	await wait(0.4)
	print("FRONT name = ", r[0])
	# team name
	f = func(): r[0] = await NamingScreen.ask(root, NamingScreen.TEAM, "")
	f.call()
	await wait(0.4)
	await shot("naming_team")
	await press_ok("ui_cancel")
	main._clear()
	_bg(root)
	await wait(0.2)
	# password entry (Wonder Mail)
	f = func(): r[0] = await NamingScreen.ask(root, NamingScreen.PASSWORD2, "", true)
	f.call()
	await wait(0.4)
	for i in 5:
		await press_ok("ui_right")
		await press_ok("ui_accept")
	await press_ok("ui_down")
	await press_ok("ui_accept")
	await wait(0.2)
	await shot("naming_password2")
	main._clear()
	_bg(root)
	f = func(): r[0] = await NamingScreen.ask(root, NamingScreen.PASSWORD1, "", true)
	f.call()
	await wait(0.4)
	await shot("naming_password1")
	main._clear()
	_bg(root)
	# save windows
	var g := func(): await SaveUI.save_ground(root)
	g.call()
	await wait(0.3)
	await shot("save_ground_a")
	await wait(0.8)
	await shot("save_ground_b")
	await press_ok("ui_accept")
	await wait(0.3)
	g = func(): await SaveUI.save_menu(root)
	g.call()
	await wait(0.3)
	await shot("save_menu_a")
	await wait(0.8)
	await shot("save_menu_b")
	await press_ok("ui_accept")
	await wait(0.3)
	# glyphs + window colours
	for ci in 3:
		Game.settings["window_color"] = ci
		var lm := ListMenu.make("Window %d" % ci, ["Items", "Team"])
		root.add_child(lm)
		lm.position = Vector2(300, 20)
		var d := Dialog.get_box(root)
		d._show(UITheme.red_text("Glyphs: {POKE} 100 {STAR_BULLET} {ICON_GO} {ICON_NEWS} {ENVELOPE_OPEN} {ENVELOPE_CLOSED}\n{A_BUTTON} {B_BUTTON} {L_BUTTON} {R_BUTTON} {START_BUTTON} {SELECT_BUTTON} {DPAD} {TM} {ORB}"), "0025", "Normal", "")
		d._finish_typing()
		await wait(0.3)
		await shot("window_color_%d" % ci)
		lm.queue_free()
		d.hide_box()
	Game.settings["window_color"] = 0

func _bg(root: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.3, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

## press with a pause after it (menus here react on the next frames; xvfb runs slowly)
func press_ok(action: String) -> void:
	await press(action)
	await wait(0.25)

func _go(n: int, c: bool) -> void:
	(func(): await main._demo(n, c)).call()
