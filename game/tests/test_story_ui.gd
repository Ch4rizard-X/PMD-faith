extends Node
## --storyui=<case>[,<case>...] : visual checks for the "story" agent's screens (ornaments, emotes, weather,
## Luminous Cave, dojo, credits, thank-you, toolbox, personality reveal). Screenshots go to user://storyui_*.png.
## Run with your own XDG_DATA_HOME (never the default user dir).

var main

func _ready() -> void:
	main = get_parent()
	_run.call_deferred()

func shot(name: String) -> void:
	if is_instance_valid(main.ground):
		var G = main.ground
		print("  ground map=%s fade=%s text=%s" % [G.map_file, G.fadeA.lvl, G.text.is_open()])
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://storyui_%s.png" % name)
	print("STORYUI shot ", name)

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

## Let the map's scripts run on their own (auto text) until the player has control.
func wait_idle(max_sec := 30.0) -> void:
	var t := 0.0
	Dialog.auto = true
	ListMenu.auto = true
	while t < max_sec:
		await wait(0.25)
		t += 0.25
		var G = main.ground
		if not is_instance_valid(G):
			continue
		G.text.auto = true
		if G.fadeA.lvl >= 256 and not G.text.is_open() and G.lives[0].kind_id != -1 and G.lives[0].ctrl_mode() == 1 and not G.any_locked:
			break
	Dialog.auto = false
	ListMenu.auto = false
	if is_instance_valid(main.ground):
		main.ground.text.auto = false
	await wait(0.5)

func _cases() -> Array:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--storyui="):
			return a.substr(10).split(",")
	return ["base"]

func _setup_game() -> void:
	Game.new_game("0025", "Pika", "0004", "Char", "Testers")
	GData.load_all()
	GVars.reset_all()

func _ground(map_name: String, scen := Vector2i(-1, -1)) -> void:
	if scen.x >= 0:
		GVars.scenario_calc(GVars.SCENARIO_MAIN, scen.x, scen.y)
	GVars.set_val(null, GVars.GROUND_ENTER, GData.map_id(map_name))
	GVars.set_val(null, GVars.GROUND_ENTER_LINK, 0)
	main.start_story(Ground.STARTMODE_GROUND)

## Show a map directly (no entry scripts): map + its default lives / objects, camera at 'cam' (GBA px).
func show_map(map_name: String, cam := Vector2i(-1, -1)) -> void:
	var G: Ground = main.ground
	G.select_map(GData.map_id(map_name), true)
	G.objects_select(0, 0)
	G.effects_select(0, 0)
	if cam.x >= 0:
		G.camera.reset()
		G.lives[0].kind_id = -1
	await wait(0.6)

func case_cave() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Testers")
	Game.team = [Game.hero]
	Game.hero.level = 20
	var a := Services.area_of("0005")
	if a != "" and not a in Game.friend_areas:
		Game.friend_areas.append(a)
	_ground("MAP_TEAM_BASE", Vector2i(18, 0))
	await wait_idle()
	main.ground.ground_request(GData.map_id("MAP_WHISCASH_POND"), 0, 30)
	await wait(1.0)
	await wait_idle()
	Dialog.auto = true
	ListMenu.auto = true
	main.ground.ground_request(GData.map_id("MAP_LUMINOUS_CAVE"), 0, 30)
	for i in 40:
		await wait(0.3)
		if is_instance_valid(main.ground):
			main.ground.text.auto = true
		await shot("cave_%02d" % i)
	print("  hero now ", Game.hero.sp, " ", Game.hero.name, " evo_levels=", Game.hero.get("evo_levels"))


func press(act: String) -> void:
	var e := InputEventAction.new()
	e.action = act
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var e2 := InputEventAction.new()
	e2.action = act
	e2.pressed = false
	Input.parse_input_event(e2)
	await wait(0.25)

## Text boxes type out: press A until no Dialog box is visible or n presses.
func advance(n := 1) -> void:
	for i in n:
		await press("ui_accept")
		await wait(0.15)

func root_ui() -> Control:
	return main.root

func case_emote() -> void:
	_ground("MAP_TEAM_BASE", Vector2i(18, 0))
	await wait_idle()
	var G: Ground = main.ground
	for e in [88, 89, 90, 91, 92, 93, 94]:
		G.lives[0].f38(e, 0)
		await wait(0.2)
		await shot("emote%d" % e)
		await wait(0.6)

## Press A through text boxes until a menu (ListMenu / TeamScreens menu) is on screen.
func until_menu(max_presses := 30) -> bool:
	for i in max_presses:
		await wait(0.3)
		for c in root_ui().get_children():
			if c is ListMenu or (c.get_script() != null and c.has_method("refresh_rows")):
				await wait(0.3)
				return true
		await press("ui_accept")
	return false

func backdrop() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.25, 0.2, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui().add_child(bg)
	return bg

func case_dojo() -> void:
	var bg := backdrop()
	GVars.set_arr(null, GVars.TRAINING_CONQUEST_LIST, 4, 1)     # Electric Maze cleared: green + star
	var res := [-99]
	var run := func(): res[0] = await Dojo.enter(root_ui())
	run.call()
	await until_menu()
	await shot("dojo_menu")
	await press("ui_accept")          # Go Train
	await until_menu()
	await shot("dojo_courses")
	await press("ui_down")
	await press("ui_accept")
	await wait(1.0)
	await shot("dojo_go")
	await advance(4)
	await wait(0.5)
	print("  DOJO enter -> ", res[0])
	# result talks (auto text)
	Dialog.auto = true
	ListMenu.auto = true
	await Dojo.result(root_ui(), "success")
	await Dojo.result(root_ui(), "failure")
	Dialog.auto = false
	ListMenu.auto = false
	# all cleared with a full Toolbox -> Bonsly Doll + Ginseng full-toolbox menu
	while Game.bag.size() < Game.BAG_MAX:
		Game.bag.append({"id": "apple", "n": 1})
	Game.storage["ginseng"] = 999        # storage full too -> Red's "Your Toolbox is full" menu
	var run2 := func(): await Dojo.result(root_ui(), "all")
	run2.call()
	await wait(0.5)
	await shot("dojo_all")
	await until_menu(40)
	await shot("dojo_fullbox")
	await press("ui_accept")          # Trash Toolbox Item
	await until_menu()
	await shot("dojo_fullbox_pick")
	await press("ui_accept")          # first item
	await wait(0.6)
	await shot("dojo_fullbox_sub")
	await press("ui_accept")          # Storage
	await wait(0.8)
	await shot("dojo_fullbox_done")
	await advance(8)
	print("  bag has ginseng: ", Game.bag.any(func(b): return b.id == "ginseng"), " storage apple ", Game.storage.get("apple", 0), " ginseng ", Game.storage.get("ginseng", 0))
	bg.queue_free()

func case_maze() -> void:
	Game.team = [Game.hero, Game.partner]
	for i in [0, 2, 10, 22]:
		GVars.set_val(null, GVars.DUNGEON_ENTER, 82)
		GVars.set_val(null, GVars.DUNGEON_ENTER_INDEX, Dojo.FIRST_SCRIPT + i)
		main._on_ground_finished(10)
		await wait(4.0)
		await shot("maze_%02d" % i)
		print("  maze ", i, " key=", main.last_dungeon, " name=", main.dungeon.ddata.get("name"), " floors=", main.dungeon.ddata.floors.size())

func case_credits() -> void:
	_ground("MAP_TEAM_BASE", Vector2i(18, 0))
	await wait_idle()
	for pg in [0, 1, 5, 12, 23]:
		var b := RedCredits.make_page(pg)
		var cl := CanvasLayer.new()
		cl.layer = 30
		root_ui().add_child(cl)
		cl.add_child(b)
		await wait(0.3)
		await shot("credits_%02d" % pg)
		cl.queue_free()
	Dialog.auto = true
	await RedCredits.show(root_ui(), 2, 10)
	Dialog.auto = false

func case_reveal() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_ui().add_child(bg)
	var pv := PortraitWin.make("0004", "Happy", true)
	root_ui().add_child(pv)
	pv.at_tile(12, 6)
	pv.keep_above_textbox(root_ui())
	var d := Dialog.get_box(root_ui())
	d._show("[center]\nThe Pokémon [color=#7fe0ff]Charmander[/color]![/center]", "", "Normal", "")
	d._finish_typing()
	await wait(0.4)
	await shot("reveal")
	d.hide_box()
	pv.queue_free()
	var res := [""]
	var run := func(): res[0] = await Quiz.partner_pick(root_ui(), "0004")
	run.call()
	await wait(0.6)
	await shot("partner_a")
	await press("ui_down")
	await press("ui_down")
	await wait(0.3)
	await shot("partner_b")
	await press("ui_accept")
	await wait(0.3)
	print("  partner -> ", res[0])
	bg.queue_free()

func case_toolbox() -> void:
	_ground("MAP_TEAM_BASE", Vector2i(18, 0))
	await wait_idle()
	Game.bag = [{"id": "oranberry" if DB.items.has("oranberry") else "apple", "n": 1}, {"id": "apple", "n": 1}, {"id": "stick" if DB.items.has("stick") else "apple", "n": 5}]
	var res := [0]
	var run := func(): res[0] = await RedReward.toolbox_feed(root_ui(), main.ground)
	run.call()
	await wait(0.6)
	await shot("toolbox")
	await press("ui_down")
	await press("ui_accept")
	await wait(0.3)
	print("  toolbox feed -> ", res[0], " item0=", main.ground.text.items[0], " bag=", Game.bag.map(func(b): return b.id))

func case_thanks() -> void:
	Game.team = [Game.hero, Game.partner]
	_ground("MAP_TEAM_BASE", Vector2i(18, 0))
	await wait_idle()
	var j := {"id": "t1", "client": "0039", "target": "0025", "kind": "target", "item": "", "dungeon": "tiny_woods", "floor": 2,
		"diff": 1, "state": "done", "reward": {"money": 100, "item": "apple", "extra": 0, "rank_points": 10}}
	Game.jobs = [j]
	GVars.set_val(null, GVars.DUNGEON_ENTER, 81)
	GVars.set_val(null, GVars.DUNGEON_ENTER_INDEX, GData.rescue_to_script(GData.rescue_id("RESCUE_DUNGEON_TINY_WOODS")))
	print("  thank_you_in_ground ", Story.thank_you_in_ground(true))
	main.start_story(Ground.STARTMODE_DUNGEON_WON)
	for i in 50:
		await wait(0.35)
		await shot("thanks_%02d" % i)
		if Game.jobs.is_empty() and i > 30:
			break
		if i % 2 == 1:
			await press("ui_accept")
	print("  jobs left ", Game.jobs.size(), " money ", Game.money)

func case_orn() -> void:
	var bg := backdrop()
	var holder := Node2D.new()
	holder.scale = Vector2(2, 2)
	root_ui().add_child(holder)
	var names := ["flag00p", "flag05p", "flag100p", "npc01p", "npc02p", "npc03p", "npc04p", "item01p", "statue", "titleop1", "titleop2", "titlebg1"]
	var i := 0
	for n in names:
		var sp := GSprite.new()
		sp.set_ornament(n)
		sp.play(0x800, 0)
		sp.position = Vector2(20 + (i % 6) * 38, 30 + (i / 6) * 60)
		holder.add_child(sp)
		print("  orn ", n, " anims=", (sp.orn.get("anims", []) as Array).size(), " poses=", (sp.orn.get("poses", []) as Array).size())
		i += 1
	for t in 20:
		for c in holder.get_children():
			c.tick()
		await get_tree().process_frame
	await shot("orn")
	holder.queue_free()
	bg.queue_free()

## Talk to Makuhita in the square -> Courses -> a maze -> clear it -> back at the dojo (DOJO_SUCCESS).
func case_dojoflow() -> void:
	Game.team = [Game.hero, Game.partner]
	_ground("MAP_TEAM_BASE", Vector2i(18, 0))
	await wait_idle()
	main.ground.ground_request(GData.map_id("MAP_MAKUHITA_DOJO"), 0, 30)
	await wait(1.0)
	await wait_idle()
	print("  UNK10 ", GVars.quest(GVars.QUEST_UNK10), " map ", main.ground.map_file)
	var G: Ground = main.ground
	var mk := -1
	for i in G.lives.size():
		if G.lives[i].kind_id != -1:
			print("  live ", i, " ", G.lives[i].species)
			if str(G.lives[i].species).begins_with("0296"):
				mk = i
	await shot("dojoflow_square")
	if mk < 0:
		print("  no Makuhita on the map")
		return
	Dojo.test_pick = 3
	Dialog.auto = true
	ListMenu.auto = true
	G.text.auto = true
	G.lives_player_talk(0, mk)
	for i in 60:
		await wait(0.25)
		if is_instance_valid(main.dungeon) and main.dungeon.is_inside_tree():
			break
	await wait(3.0)
	await shot("dojoflow_maze")
	print("  in dungeon: ", main.last_dungeon, " ", main.dungeon.ddata.get("name") if is_instance_valid(main.dungeon) else "-")
	if is_instance_valid(main.dungeon):
		main.dungeon._end("cleared")
	for i in 80:
		await wait(0.25)
		if is_instance_valid(main.ground):
			main.ground.text.auto = true
	await shot("dojoflow_back")
	print("  maze 3 conquered: ", Dojo.maze_done(3), " map=", main.ground.map_file if is_instance_valid(main.ground) else "-")
	Dialog.auto = false
	ListMenu.auto = false

func _run() -> void:
	_setup_game()
	for c in _cases():
		print("STORYUI case ", c)
		match c:
			"base":
				GVars.set_val(null, GVars.BASE_LEVEL, 2)
				_ground("MAP_TEAM_BASE", Vector2i(18, 0))
				await wait_idle()
				await shot("base_in")
				await show_map("MAP_TEAM_BASE")
				await shot("base")
				# emotes on the leader
				var G: Ground = main.ground
				for e in [88, 89, 90, 91, 92, 93, 94]:
					G.lives[0].f38(e, 0)
					await wait(0.12)
					await shot("emote%d" % e)
			"square":
				_ground("MAP_TEAM_BASE", Vector2i(18, 0))
				await wait_idle()
				await show_map("MAP_POKEMON_SQUARE")
				await shot("square_a")
				await wait(3.0)
				await shot("square_b")
			"statue":
				_ground("MAP_TEAM_BASE", Vector2i(18, 0))
				await wait_idle()
				await show_map("MAP_FRIEND_AREA_FURNACE_DESERT")
				await shot("furnace")
			"map":
				var mname := ""
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--map="):
						mname = a.substr(6)
				_ground("MAP_TEAM_BASE", Vector2i(18, 0))
				await wait_idle()
				await show_map(mname)
				for a2 in OS.get_cmdline_user_args():
					if a2.begins_with("--gzoom="):
						main.ground.zoom = float(a2.substr(8))
					if a2.begins_with("--mapcam="):
						var v2 := a2.substr(9).split(",")
						main.ground.camera.follow(0, -1)
						main.ground.camera.set_target(Vector2i(int(v2[0]) << 8, int(v2[1]) << 8))
				await wait(0.3)
				await shot("map_" + mname.to_lower())
			_:
				var fn: String = "case_" + c
				if has_method(fn):
					await call(fn)
	print("STORYUI done")
	get_tree().quit()
