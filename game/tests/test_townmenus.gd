extends Node
## Visual check of agent "town"'s screens (run: xvfb-run -a godot --rendering-driver opengl3 -- --townmenutest).
## Opens each menu with simulated input and saves screenshots to user://tm_*.png: base menu + side windows,
## Toolbox, Team list + commands, Others, Game Options pages, Hints, a red window colour, Kecleon (items /
## wares, awake / asleep), Felicity Bank number entry, Kangaskhan storage, Wigglytuff + Friend Area info,
## mailbox / news, Pelipper guide, Friend Rescue + passwords, the dungeon list and a Friend Area party menu.
## The save file is backed up and restored.

var main: Node
var root: Control
var shot_n := 0
var _backup := ""
var fails := 0

func _ready() -> void:
	main = get_parent()
	root = main.root
	_run.call_deferred()

func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1

func _shot(n: String) -> void:
	await get_tree().create_timer(0.4).timeout
	var path := "user://tm_%02d_%s.png" % [shot_n, n]
	shot_n += 1
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func _p(a: String, n := 1) -> void:
	for i in n:
		await main._mt_press(a)

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

## Finish typing and advance until a menu window (RedMenu / ListMenu) is on top.
func _to_menu(limit := 12) -> void:
	for i in limit:
		await _wait(0.12)
		if not TeamScreens._stack.is_empty() and TeamScreens._stack.back() is TeamScreens.RedMenu:
			return
		await _p("ui_accept")

func _close_all(limit := 14) -> void:
	for i in limit:
		await _wait(0.1)
		var d := Dialog.get_box(root)
		if TeamScreens._stack.is_empty() and not d.panel.visible:
			return
		if d.panel.visible and (TeamScreens._stack.is_empty() or not TeamScreens._stack.back() is Control):
			await _p("ui_accept")
		else:
			await _p("ui_cancel")

func _run() -> void:
	if FileAccess.file_exists(Game.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(Game.SAVE_PATH)
	Dialog.auto = false
	ListMenu.auto = false
	Game.new_game("0258", "Mudkip", "0255", "Torchic", "Poffins")
	Game.money = 4321
	Game.bank = 1500
	Game.rank_points = 620
	Game.friend_areas = ["flyaway", "jungle", "beautifulsea"]
	var pid := {"sp": "0016", "name": "Pidgey", "level": 6, "exp": DB.exp_at("0016", 6), "moves": DB.default_moves("0016", 6), "iq": 0, "held": "oran", "bonus": {}, "area": Services.area_of("0016")}
	Game.friends = [pid]
	Game.team.append(pid)
	Game.flags["seen"] = {"0016": true, "0191": true, "0265": true, "0081": true, "0025": true, "0258": true}
	for id in ["oran", "apple", "apple", "pecha", "sleepseed", "blastseed", "whitegummi"]:
		Game.bag_add(id)
	Game.bag_add("stick", 9)
	Game.storage = {"oran": 3, "gravelerock": 30, "reviver": 1, "apple": 2}
	main.start_town("base")
	await _wait(1.5)
	await _base_menu()
	await _shops()
	await _mail_post()
	await _friend_rescue()
	await _story_bits()
	_finish()

# ------------------------------------------------------------------ base menu
func _base_menu() -> void:
	main._on_town_menu()
	await _shot("base_menu")
	await _p("ui_accept")                    # Items
	await _shot("toolbox")
	await _p("ui_accept")
	await _shot("toolbox_cmds")
	await _p("ui_cancel", 2)
	await _p("ui_down")                      # Team
	await _p("ui_accept")
	await _p("ui_down", 2)
	await _p("ui_accept")
	await _shot("team_member_cmds")
	await _p("ui_cancel")
	await _p("ui_cancel")
	await _p("ui_down", 2)                   # Others
	await _p("ui_accept")
	await _shot("others")
	await _p("ui_accept")                    # Game Options
	await _shot("game_options")
	await _p("ui_accept")                    # Dungeon page
	await _p("ui_down", 4)
	await _p("ui_right")                     # Map Clear -> Shade
	await _shot("options_dungeon")
	await _p("ui_cancel")
	await _wait(0.2)
	await _shot("options_change_prompt")
	await _p("ui_accept")                    # Yes
	ok(int(Game.settings.get("map_mode", -1)) == 2, "Map option stored as map_mode = 2 (Shade)")
	await _p("ui_down")                      # Others page
	await _p("ui_accept")
	await _p("ui_right")                     # Windows Blue -> Red
	await _shot("options_others")
	await _p("ui_cancel")
	await _wait(0.2)
	await _p("ui_accept")
	ok(int(Game.settings.get("window_color", -1)) == 1, "Windows option stored as window_color = 1 (Red)")
	await _p("ui_cancel")                    # back to Others
	await _p("ui_down")                      # Hints
	await _p("ui_accept")
	await _shot("hints")
	await _p("ui_accept")
	await _shot("hint_page")
	await _p("ui_cancel")
	await _p("ui_cancel")
	await _p("ui_cancel")
	await _wait(0.3)
	main._on_town_menu()
	await _shot("base_menu_red_windows")
	await _close_all()
	Game.settings.window_color = 0
	Game.settings.map_mode = 1
	UITheme.sync_window_color()

# ------------------------------------------------------------------ shops
func _shops() -> void:
	Services.kecleon(root, false)
	await _to_menu()
	await _shot("kecleon_items_menu")
	await _p("ui_accept")                    # Buy
	await _to_menu()
	await _shot("kecleon_items_buy")
	await _close_all()
	Services.kecleon(root, true)
	await _to_menu()
	await _p("ui_accept")
	await _to_menu()
	await _shot("kecleon_wares_buy")
	await _close_all()
	RedShops.force_asleep = true
	Services.kecleon(root, false)
	await _wait(0.6)
	await _p("ui_accept")
	await _shot("kecleon_asleep")
	await _close_all()
	RedShops.force_asleep = false
	Services.bank(root)
	await _to_menu()
	await _shot("bank_menu")
	await _p("ui_accept")                    # Store
	for i in 4:
		await _wait(0.2)
		if not TeamScreens._stack.is_empty() and TeamScreens._stack.back() is RedShops.NumberPicker:
			break
		await _p("ui_accept")
	await _p("ui_left")
	await _p("ui_down")
	await _shot("bank_number")
	await _close_all()
	Services.storage(root)
	await _to_menu()
	await _p("ui_down")                      # Take
	await _p("ui_accept")
	await _to_menu()
	await _p("act_map")                      # mark (Select)
	await _shot("storage_take_list")
	await _close_all()
	Services.wigglytuff(root)
	await _to_menu()
	await _shot("wigglytuff_menu")
	await _p("ui_accept")
	await _to_menu()
	await _shot("wigglytuff_buy")
	await _p("ui_accept")
	await _wait(0.2)
	await _p("ui_down")                      # Info
	await _p("ui_accept")
	await _shot("friend_area_info")
	await _close_all()

# ------------------------------------------------------------------ mailbox / post office
func _mail_post() -> void:
	Game.flags.erase("news_mail")
	Game.flags["news_received"] = [1, 2]
	Board.open_mailbox(root)
	await _wait(0.4)
	await _shot("mailbox_menu")
	await _p("ui_accept")
	await _shot("mailbox_check_mail")
	await _p("ui_cancel")
	await _p("ui_down", 2)
	await _p("ui_accept")
	await _shot("news_list")
	await _p("ui_accept")
	await _shot("news_letter")
	await _close_all()
	PostOffice.help_counter(root)
	await _to_menu()
	await _shot("pelipper_guide")
	await _p("ui_down", 3)
	await _p("ui_accept")
	await _to_menu()
	await _shot("pelipper_friend_rescue_guide")
	await _close_all()

func _friend_rescue() -> void:
	FriendRescue.on_defeated("mt_steel", 4)
	var s := FriendRescue.state()
	var sos: Dictionary = s.sos
	var code := FriendRescue.encode({"mail_type": 1, "dungeon": sos.dungeon, "floor": sos.floor, "seed": sos.seed, "client": sos.client,
		"mail_id": sos.mail_id, "name": sos.name, "rescues": 10})
	var back := FriendRescue.decode(code)
	ok(code.length() == 54 and int(back.get("mail_id", -1)) == int(sos.mail_id) and str(back.get("name", "")) == "Poffins", "SOS password round trip (%s)" % code)
	FriendRescue.counter(root)
	await _to_menu()
	await _shot("friend_rescue_menu")
	await _p("ui_down")
	await _p("ui_accept")                    # Get Help
	await _to_menu()
	await _p("ui_accept")                    # Send SOS Mail
	for i in 6:
		await _wait(0.2)
		if not TeamScreens._stack.is_empty() and TeamScreens._stack.back() is TeamScreens.RedMenu:
			break
		await _p("ui_accept")
	await _p("ui_accept")                    # Yes
	for i in 6:
		await _wait(0.2)
		if not TeamScreens._stack.is_empty() and TeamScreens._stack.back() is TeamScreens.InfoPage:
			break
		await _p("ui_accept")
	await _shot("sos_password")
	await _close_all()
	var j := FriendRescue.make_job(back, code)
	ok(not j.is_empty() and str(j.dungeon) == "mt_steel", "SOS mail becomes a rescue job (%s)" % str(j.get("title", "")))

# ------------------------------------------------------------------ story: dungeon list, Friend Area menus
func _story_bits() -> void:
	GVars.init()
	GVars.reset_all()
	GVars.scenario_calc(GVars.SCENARIO_MAIN, 6, 0)
	for n in ["TINY_WOODS", "THUNDERWAVE_CAVE", "MT_STEEL", "SINISTER_WOODS"]:
		GVars.rescue_set_conquered(GData.rescue_id("RESCUE_DUNGEON_" + n), true)
	GVars.rescue_set_job(GData.rescue_id("RESCUE_DUNGEON_SINISTER_WOODS"), true)
	Game.story["vars"] = GVars.save_b64()
	Game.jobs = [{"id": "x", "kind": "rescue", "dungeon": "mt_steel", "floor": 3, "state": "taken", "title": "t", "place": "p", "difficulty": "E"}]
	var opts: Array = ["Tiny Woods", "Thunderwave Cave", "Mt. Steel", "Sinister Woods", "Explorers of Sky dungeons (3)"]
	var ids: Array = []
	for n in ["TINY_WOODS", "THUNDERWAVE_CAVE", "MT_STEEL", "SINISTER_WOODS"]:
		ids.append(GData.rescue_id("RESCUE_DUNGEON_" + n))
	ids.append(-100)
	DungeonList.pick(root, opts, ids)
	await _wait(0.4)
	await _shot("dungeon_list")
	await _close_all()
	Game.jobs = []
	BaseMenu.party_menu(main, root, Game.friends[0], true)
	await _wait(0.4)
	await _shot("party_menu")
	await _close_all()
	RedShops.fa_info_screen(root, "flyaway")
	await _wait(0.4)
	await _shot("fa_info")
	await _close_all()
	RedShops.fa_info_screen(root, "thundermeadow")     # more than 15 base species: a second page
	await _wait(0.4)
	await _p("ui_right")
	await _shot("fa_info_page2")
	await _close_all()
	# the base menu in a Friend Area: Friend / Items / Info / Exit, then Friend's list
	BaseMenu.force_fa = "flyaway"
	var fr := Game.friends.duplicate()
	var pid2 := {"sp": "0021", "name": "Spearow", "level": 4, "exp": DB.exp_at("0021", 4), "moves": DB.default_moves("0021", 4), "iq": 0, "held": "", "bonus": {}, "area": "flyaway"}
	Game.friends.append(pid2)
	main._on_town_menu()
	await _wait(0.4)
	await _shot("fa_base_menu")
	await _p("ui_accept")                    # Friend
	await _wait(0.3)
	await _p("ui_down")
	await _p("ui_accept")
	await _shot("fa_friend_cmds")
	await _close_all()
	BaseMenu.force_fa = ""
	Game.friends = fr
	# Friend Rescue: Go Rescue -> Receive SOS Mail opens Red's password naming screen
	FriendRescue.receive_sos(root)
	await _wait(0.3)
	for i in 6:
		await _wait(0.15)
		if root.get_children().any(func(c): return c is NamingScreen):
			break
		await _p("ui_accept")
	await _wait(0.4)
	ok(root.get_children().any(func(c): return c is NamingScreen), "Receive SOS Mail opens the password naming screen")
	await _shot("sos_password_entry")
	await _close_all(20)

func _finish() -> void:
	Game.story = {}
	if _backup != "":
		var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
	print("TOWNMENUTEST done fails=", fails)
	get_tree().quit()
