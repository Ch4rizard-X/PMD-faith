extends Node
## Top-level flow: title -> new game (quiz or free pick) -> dungeon -> result.

const RED_STARTERS := ["0001", "0004", "0007", "0025", "0052", "0054", "0066", "0104", "0133", "0152", "0155", "0158", "0252", "0255", "0258", "0300"]

var ui: CanvasLayer
var root: Control
var dungeon: Dungeon
var hud: Hud

func _ready() -> void:
	_setup_input()
	get_viewport().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	UITheme.apply_ui_scale()        # Game Options > Others > Menu size
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	root = Control.new()
	root.theme = UITheme.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	BottomScreen.setup(self)      # AYN Thor second screen / desktop preview window (scripts/ui/bottom_screen.gd)
	if OS.get_cmdline_user_args().has("--thortest"):
		_thortest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--qoltest"):
		_qoltest.call_deferred()
	if OS.get_cmdline_user_args().has("--walktest"):
		_walktest.call_deferred()
	if OS.get_cmdline_user_args().has("--perftest"):
		_perftest.call_deferred()
	if OS.get_cmdline_user_args().has("--bosspos"):
		_bosspos.call_deferred()
	if OS.get_cmdline_user_args().has("--nametest"):
		(func():
			var ns := NamingScreen.new()
			ns.mode = 0
			ns._setup("")
			root.add_child(ns)
			await get_tree().create_timer(1.0).timeout
			for i in [3, 4, 5, 3]:
				var L: Array = NamingScreen.LAYOUT[i + 3]
				var p: Vector2 = get_viewport().get_final_transform() * ns._p(ns._input_win().position + Vector2(L[4] + 3, L[5] + 4))
				for pr in [true, false]:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = pr
					ev.position = p
					ev.global_position = p
					Input.parse_input_event(ev)
				await get_tree().create_timer(0.3).timeout
			print("NAMETEST typed by tapping: '%s'" % ns.value())
			get_viewport().get_texture().get_image().save_png("user://nametest.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--opttest"):
		(func():
			var tap := func(c: Control, local: Vector2) -> void:
				var p: Vector2 = get_viewport().get_final_transform() * (c.get_global_transform() * local)
				for pr in [true, false]:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = pr
					ev.position = p
					ev.global_position = p
					Input.parse_input_event(ev)
			GameOptions.page(root, "Dungeon")
			await get_tree().create_timer(1.0).timeout
			var m: TeamScreens.RedMenu = TeamScreens._stack.back()
			print("OPTTEST before: ", m.rows[0].right)
			var hb: Control = m._rows[0]
			var r: Control = hb.get_child(4)
			tap.call(hb, Vector2(r.position.x + r.size.x * 0.8, hb.size.y / 2))      # right half of the value: forward
			await get_tree().create_timer(0.5).timeout
			m = TeamScreens._stack.back()
			print("OPTTEST after forward tap: ", m.rows[0].right)
			hb = m._rows[0]
			r = hb.get_child(4)
			tap.call(hb, Vector2(r.position.x + 2, hb.size.y / 2))                    # left half: back
			await get_tree().create_timer(0.5).timeout
			m = TeamScreens._stack.back()
			print("OPTTEST after back tap: ", m.rows[0].right, " | page still open: ", not m.finished)
			get_viewport().get_texture().get_image().save_png("user://opttest.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--taptest") and not OS.get_cmdline_user_args().has("--notap"):
		(func():
			for i in 40:
				await get_tree().create_timer(1.5).timeout
				if OS.get_cmdline_user_args().has("--bottomtap"):
					BottomScreen.instance.inject(Vector2(100, 100), true)     # the Thor plugin's touch path
					BottomScreen.instance.inject(Vector2(100, 100), false)
				else:
					var ev := InputEventScreenTouch.new()
					ev.pressed = true
					ev.position = Vector2(200, 200)
					Input.parse_input_event(ev)
					var ev2 := InputEventScreenTouch.new()
					ev2.pressed = false
					ev2.position = Vector2(200, 200)
					Input.parse_input_event(ev2)
				print("TAPTEST tap at %.1f s" % (Time.get_ticks_msec() / 1000.0))).call_deferred()
	if OS.get_cmdline_user_args().has("--eostest"):
		_eostest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--legendtest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			start_dungeon("tiny_woods", 0)
			await get_tree().create_timer(3.0).timeout
			var d := dungeon
			var z := Game._entry("0145", "", 50)
			Game.friends.append(z)
			var w := DB.make_mon("0145", 50, "enemy")
			print("LEGENDTEST normal Zapdos blocked (have normal): ", d.legend_owned(w))
			w.set_meta("shiny", true)
			print("LEGENDTEST shiny Zapdos blocked (have normal): ", d.legend_owned(w))
			z["shiny"] = true
			print("LEGENDTEST shiny Zapdos blocked (have shiny): ", d.legend_owned(w))
			z["shiny"] = false
			var bs := BossScene.new()
			RedShops.force_asleep = false
			Game.flags["postgame"] = false
			print("LEGENDTEST story: Zapdos counts as recruited: ", bs._recruited("MONSTER_ZAPDOS"))
			Game.flags["postgame"] = true
			print("LEGENDTEST postgame, normal owned: counts as recruited (no rematch): ", bs._recruited("MONSTER_ZAPDOS"))
			z["shiny"] = true
			print("LEGENDTEST postgame, shiny owned: counts as recruited: ", bs._recruited("MONSTER_ZAPDOS"))
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--statustest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			start_dungeon("tiny_woods", 0)
			await get_tree().create_timer(3.0).timeout
			var d := dungeon
			Dialog.auto = true
			d.auto_answer = true
			var L: Mon = d.fs.leader
			for k in ["sleep", "para", "confused", "slow", "burn", "poison", "frozen", "cringe", "blinker", "cross_eyed", "petrified", "infatuated"]:
				var res := []
				for trial in 5:
					d._reset_floor_status(L)
					L.hp = L.max_hp
					d._set_item_status(L, k, 99, "%s")
					var t0 := int(L.status.get(k, 0))
					var n := 0
					while int(L.status.get(k, 0)) > 0 and n < 200:
						TurnRules.tick_status(L, d.fs)
						L.hp = L.max_hp
						n += 1
					res.append(n if n < 200 else "never")
				print("STATUSTEST %-11s turns: %s" % [k, res])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--shinyground"):
		(func():
			var bg := ColorRect.new()
			bg.color = Color(0.3, 0.5, 0.3)
			bg.size = Vector2(1440, 810)
			root.add_child(bg)
			var i := 0
			for sp_ in ["0025", "0025*", "0006MX", "0006MX*", "0382P", "0382P*", "0384M", "0384M*"]:
				var g := GSprite.new()
				g.set_species(sp_)
				print("SHINYGROUND ", sp_, " material ", g.material != null, " species ", g.species)
				g.free()
				var mm := DB.make_mon(sp_.trim_suffix("*"), 10, "enemy")
				if sp_.ends_with("*"):
					mm.set_meta("shiny", true)
				var ms := MonSprite.new()
				ms.setup(mm)
				ms.position = Vector2(80 + i * 80, 120)
				ms.scale = Vector2(2, 2)
				root.add_child(ms)
				i += 1
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png("user://shiny_ground.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--shinytest"):
		_shinytest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--megatest"):
		_megatest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--boxtest"):
		_boxtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--abtest"):
		_abtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--heldtest"):
		_heldtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--itemtest"):
		_itemtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--promptest"):
		_promptest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--throwtest"):
		_throwtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--jobfloor"):
		_jobfloor.call_deferred()
	if OS.get_cmdline_user_args().has("--movetest"):
		_movetest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--autotest"):
		_autotest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--usemove"):
		_usemove.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--fxtest"):
		_fxtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--dgtest"):      # agent "dungeon": scripts/dungeon/dungeon_test.gd
		(func(): load("res://scripts/dungeon/dungeon_test.gd").run(self)).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--menutest"):
		_menutest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--padtest"):
		_padtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--wmtest"):
		_wmtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--flowtest"):
		_flowtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--iqtest"):
		_iqtest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--towntest"):
		add_child(load("res://tests/test_town.gd").new())
		return
	if OS.get_cmdline_user_args().has("--storytest"):
		_storytest.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--townmenutest"):
		add_child(load("res://tests/test_townmenus.gd").new())     # agent town's menus (tests/test_townmenus.gd)
		return
	if OS.get_cmdline_user_args().has("--towntest2"):
		_towntest2.call_deferred()
		return
	if OS.get_cmdline_user_args().has("--quiztest"):
		Quiz.autotest.call_deferred(root, pick_species)
		return
	if OS.get_cmdline_user_args().has("--wmaptest"):      # world map / Friend Areas map (tests/test_world_map.gd)
		add_child(load("res://tests/test_world_map.gd").new())
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--storyui"):          # story screens visual checks (tests/test_story_ui.gd)
			add_child(load("res://tests/test_story_ui.gd").new())
			return
	if OS.get_cmdline_user_args().has("--fronttest"):     # boot / main menu / naming / save screens (agent "front")
		add_child(load("res://tests/test_front.gd").new())
		return
	boot()

func _clear() -> void:
	for c in root.get_children():
		root.remove_child(c)      # detach now so nothing reuses a node that's about to be freed
		c.queue_free()
	if dungeon:
		dungeon.queue_free()
		dungeon = null
	if is_instance_valid(ground):
		ground.queue_free()
		ground = null

# ------------------------------------------------------------------ boot + title
## Red's boot (main_loops.c GameLoop_Async): STARTMODE_14..17 run the ground demos DEMO_01 (health & safety),
## DEMO_02 (company screens), DEMO_03 (Post Office demo, intro, title) and, unless DEMO_03 was left with a
## button press, DEMO_04 (title, "Press Start"); then the main menu. Start with --noboot to skip.
func boot() -> void:
	if OS.get_cmdline_user_args().has("--noboot"):
		title()
		return
	GData.load_all()
	if not Game.story.has("vars"):
		GVars.reset_all()                      # ThoroughlyResetScriptVars (no save)
	# Red can't skip the logos or a first boot's intro; here any button or a screen tap skips all of them
	await _demo(1, true)
	await _demo(2, true)
	GVars.clear_arr(null, GVars.EVENT_LOCAL)
	await _demo(3, true)
	if GVars.get_val(null, GVars.EVENT_LOCAL) == 0:
		await _demo(4, true)
	title()

## One boot demo through the ground engine (Ground.start_demo); returns 15 (ended) or 16 (cancelled).
func _demo(n: int, cancel_ok: bool) -> int:
	_clear()
	Story.host = self
	ground = Ground.new()
	ground.host = self
	ground.ui_root = root
	add_child(ground)
	ground.start_demo(n, cancel_ok)
	var t0 := Time.get_ticks_msec()
	var code: int = await ground.finished
	if OS.get_cmdline_user_args().has("--taptest"):
		print("TAPTEST demo %d cancel_ok=%s code=%d took %.1f s" % [n, cancel_ok, code, (Time.get_ticks_msec() - t0) / 1000.0])
	if is_instance_valid(ground):
		ground.queue_free()
	ground = null
	return code

## The main menu (scripts/ui/main_menu.gd: Red's file select with the description window).
func title() -> void:
	if OS.get_cmdline_user_args().has("--taptest"):
		print("TAPTEST title reached at %.1f s" % (Time.get_ticks_msec() / 1000.0))
		get_tree().quit()
	_clear()
	await MainMenu.run(self)

## ground_place.c sGroundPlaceNames ($t = team name)
const GROUND_PLACE_NAMES := ["Square", "Square", "Pokémon Square", "Whiscash Pond", "Pelipper Post Office",
	"Pelipper Post Office", "Makuhita Dojo", "Makuhita Dojo", "Luminous Cave", "Friend Areas", "$t Team Base",
	"$t Team Base", "Dungeon", "Tiny Woods", "Thunderwave Cave", "Mt. Steel", "Sinister Woods", "Silent Chasm",
	"Mt. Thunder", "Mt. Thunder Mid", "Great Canyon", "Hill of the Ancients", "Lapis Cave", "Lapis Cave Exit",
	"Mt. Blaze", "Mt. Blaze Mid", "Frosty Forest", "Frosty Clearing", "Mt. Freeze", "Mt. Freeze Mid", "Magma Cavern",
	"Magma Cavern Mid", "Sky Tower", "Sky Tower Mid", "Western Cave"]
## load_screen.c order = clmkpat icon index
const LEGEND_QUESTS := ["QUEST_LEGEND_ZAPDOS", "QUEST_LEGEND_MOLTRES", "QUEST_LEGEND_ARTICUNO", "QUEST_LEGEND_GROUDON",
	"QUEST_LEGEND_RAYQUAZA", "QUEST_LEGEND_KYOGRE", "QUEST_LEGEND_MEW", "QUEST_LEGEND_HO_OH", "QUEST_LEGEND_CELEBI",
	"QUEST_LEGEND_LUGIA", "QUEST_LEGEND_MEWTWO", "QUEST_LEGEND_DEOXYS"]

## Red's load screen (load_screen.c): Team / Name / Location / Play time / Adventures / Helper, the legendary
## quest icons, then "Resuming saved adventure. Is that OK?". Returns false on No.
## With a quicksave (dungeon suspend file) the location is the dungeon floor and the prompt is
## "Resuming from quicksave." (IsQuickSave). prompt: the Delete Save Data texts (MENU_DELETE_SAVE_*).
func _load_screen(prompt := "") -> bool:
	var quick := DungeonSave.has_suspend()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.frame())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	panel.add_child(vb)
	var place := "Location unknown."
	var pid := GVars.get_val(null, GVars.GROUND_PLACE) if Game.story.has("vars") else -1
	if pid >= 0 and pid < GROUND_PLACE_NAMES.size():
		place = str(GROUND_PLACE_NAMES[pid]).replace("$t", Game.team_name)
	if quick:
		var qi := DungeonSave.info()
		place = ("%s %s" % [str(qi.get("dname", "")), str(qi.get("label", ""))]).strip_edges()
	var secs := int(float(Game.flags.get("play_secs", 0.0)))
	var tname: String = Game.team_name if GVars.quest(GVars.QUEST_SET_TEAM_NAME) or Game.team_name != "" else "????"
	var leader: String = str(Game.team[0].get("name", "???")) if Game.team.size() > 0 else "???"
	var rows := [["Team:", tname], ["Name:", leader], ["Location:", place],
		["Play time:", "%d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]],
		["Adventures:", str(int(Game.flags.get("adventures", 0)))], ["Helper:", "-----"]]
	for r in rows:
		var hb := HBoxContainer.new()
		hb.custom_minimum_size.y = 10 * UITheme.PX
		var a := Label.new()
		a.text = r[0]
		a.custom_minimum_size.x = 50 * UITheme.PX
		a.add_theme_constant_override("line_spacing", 0)
		a.add_theme_font_size_override("font_size", 9 * UITheme.PX)
		var b := Label.new()
		b.text = r[1]
		b.add_theme_font_size_override("font_size", 9 * UITheme.PX)
		hb.add_child(a)
		hb.add_child(b)
		vb.add_child(hb)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 0)
	var cm: Dictionary = (GVars as Script).get_script_constant_map()
	for li in LEGEND_QUESTS.size():
		var qid = cm.get(str(LEGEND_QUESTS[li]))
		if qid != null and GVars.quest(int(qid)):
			var at := AtlasTexture.new()
			at.atlas = DB.tex("res://assets/ui/legend_icons.png")
			at.region = Rect2(li * 16, 0, 16, 16)
			var tr := TextureRect.new()
			tr.texture = at
			tr.custom_minimum_size = Vector2(16, 16) * UITheme.PX
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icons.add_child(tr)
	if icons.get_child_count() > 0:
		vb.add_child(icons)
	root.add_child(panel)
	panel.position = Vector2(16, 6) * UITheme.PX
	panel.custom_minimum_size.x = 208 * UITheme.PX
	if prompt == "":
		prompt = "Resuming from quicksave.\nIs that OK?" if quick else "Resuming saved adventure.\nIs that OK?"
	var c := await Dialog.ask(root, prompt, ["Yes", "No"])
	panel.queue_free()
	return c == 0

## Title "Resume": rebuild the suspended dungeon run (the suspend file is deleted once loaded - Red rule).
func resume_dungeon() -> void:
	_clear()
	hud = Hud.new()
	root.add_child(hud)
	dungeon = Dungeon.new()
	add_child(dungeon)
	dungeon.hud = hud
	dungeon.ui_root = root
	hud.button.connect(dungeon.on_hud_button)
	dungeon.finished.connect(_on_dungeon_finished)
	Dojo.ensure_mazes()                    # a suspended training maze run needs its maze_NN dungeon entry
	if not DungeonSave.load_into(dungeon):
		await Dialog.say(root, "The suspended adventure couldn't be loaded.")
		DungeonSave.clear()
		title()
		return
	last_dungeon = dungeon.dkey
	await dungeon._floor_banner()
	if is_instance_valid(dungeon):
		dungeon.busy = false

## Called (deferred) by DungeonSave.save_and_quit() after the dungeon's Quicksave command.
func quicksave_exit() -> void:
	await SaveUI.quicksave_done(root)      # quick_save_write.c texts + saving icon
	title()

# ------------------------------------------------------------------ new game
func new_game() -> void:
	_clear()
	GData.load_all()
	GVars.reset_all()
	Game.story = {}
	Game.team = []
	Game.hero = {}
	Game.partner = {}
	start_story(Ground.STARTMODE_NEW_GAME)

## Personality test (Red's SPECIAL_TEXT_PERSONALITY_QUIZ): quiz or free pick, then the team is formed.
func story_choose_team() -> void:
	var keep := Game.team.size() >= 2
	var opts := ["Take the personality quiz", "Choose freely"]
	if keep:
		opts.push_front("Keep my current team")
	var how := ListMenu.make("How do you want to choose your Pokémon?", opts, false)
	_center(how)
	var h := await how.choose()
	if keep and h == 0:
		return
	if keep:
		h -= 1
	var hero := ""
	set_meta("quiz_result", {})
	if h == 0:
		hero = await quiz()
	var took_quiz := hero != ""
	if hero == "":
		hero = await pick_species("Who will you be?", RED_STARTERS, "")
	var partner := ""
	if took_quiz:
		await Quiz.partner_prompt(root)
		partner = await Quiz.partner_pick(root, hero)       # Red's "Pokémon" list + portrait window
	else:
		partner = await pick_species("Choose your partner", RED_STARTERS, hero)
	var keep_story := Game.story.duplicate()
	Game.new_game(hero, DB.species[hero].name, partner, DB.species[partner].name, "Team")
	Game.story = keep_story
	var qr: Dictionary = get_meta("quiz_result", {})
	Game.nature = str(qr.get("nature", ""))
	Game.gender = str(qr.get("gender", ""))
	if took_quiz:
		await Quiz.end_text(root)

# ------------------------------------------------------------------ story (Red's ground scripts)
var ground: Ground

## SPECIAL_TEXT_LUMINOUS_CAVE (scripts/ground/luminous_cave.gd)
func luminous_cave() -> void:
	await LuminousCave.run(root, ground)

## SPECIAL_TEXT_THANK_YOU_MAIL / FRIEND_RESCUE / UNK_1D: the Wonder Mail password screen (scripts/ui/wonder_mail_ui.gd).
func wonder_mail_menu() -> void:
	if Dialog.auto or ListMenu.auto:
		return
	await WonderMailUI.enter_code(root)

func continue_story() -> void:
	GData.load_all()
	if not Game.story.has("vars"):
		GVars.reset_all()
		start_story(Ground.STARTMODE_NEW_GAME)
		return
	start_story(Ground.STARTMODE_CONTINUE_GAME)

func start_story(mode: int) -> void:
	_clear()
	if is_instance_valid(town):
		town.queue_free()
	if is_instance_valid(ground):
		ground.queue_free()
	Story.host = self
	ground = Ground.new()
	ground.host = self
	ground.ui_root = root
	add_child(ground)
	ground.finished.connect(_on_ground_finished)
	ground.start(mode)

func _on_ground_finished(code: int) -> void:
	AdventureLog.update()                  # UpdateAdventureAchievements (ground_main.c runs it each ground loop)
	Game.save_game()
	match code:
		5:
			# tests never wander into Friend Areas (the auto menu would keep picking the first one)
			var k := "" if ListMenu.auto else await WorldMap.friend_areas(root, WorldMap.current_fa_key())
			var m := -1
			if k != "":
				m = Story.map_of_fa_key(k)
			if m < 0:
				m = GData.map_id("MAP_TEAM_BASE")     # cancelled: back home
			GVars.set_val(null, GVars.GROUND_ENTER, m)
			GVars.set_val(null, GVars.GROUND_ENTER_LINK, 0)
			start_story(Ground.STARTMODE_GROUND)
		6:
			var sd := GVars.get_val(null, GVars.DUNGEON_SELECT)
			var did := int(GData.dungeon_info(sd).dungeon) if sd >= 0 else -1
			var keys: Array = DB.dungeons.get("dungeons", {}).keys()
			if did < 0 or did >= keys.size():
				start_story(Ground.STARTMODE_GROUND)
				return
			var go: bool = await WorldMap.trip_red(root, keys[did])        # Red's world map trip + entry rules
			if go and WorldMap.want_prepare():
				go = await PrepareScreen.run(root, keys[did])
			if not go:
				start_story(Ground.STARTMODE_GROUND)
				return
			GVars.set_val(null, GVars.DUNGEON_ENTER, sd)
			start_story(Ground.STARTMODE_DUNGEON_FROM_WORLD_MAP)
		7, 8, 10:
			var sd2 := GAction._s16(GVars.get_val(null, GVars.DUNGEON_ENTER))
			if sd2 == 81 or sd2 == 82:
				sd2 = GAction._s16(GVars.get_val(null, GVars.DUNGEON_ENTER_INDEX))
			var info2: Dictionary = GData.dungeon_info(sd2)
			var did2 := int(info2.dungeon)
			var key2 := DB.dungeon_key(clampi(did2, 0, 63))
			if Dojo.is_maze_script(sd2):
				key2 = Dojo.maze_key(sd2 - Dojo.FIRST_SCRIPT)     # Makuhita Dojo training maze (scripts/ground/dojo.gd)
			# Red splits story dungeons with a boss arena into two script dungeons: the floors up to the
			# arena, then (u11 == 0) the arena itself, entered after a ground cutscene (NEXT_DUNGEON).
			var boss_f := _boss_floor(key2)
			var first := 0
			var stop := -1
			if int(info2.get("u11", 1)) == 0 and boss_f > 0:
				first = boss_f
			elif boss_f > 0 and sd2 + 1 < GData.extra.dungeons.size():
				var nx: Dictionary = GData.dungeon_info(sd2 + 1)
				if int(nx.dungeon) == did2 and int(nx.get("u11", 1)) == 0:
					stop = boss_f
			story_dungeon = true
			start_dungeon(key2, first, stop)
		9:
			story_dungeon = true
			start_dungeon(last_dungeon if last_dungeon != "" else "tiny_woods")
		16:
			# an Explorers of Sky dungeon from the dungeon list: back home afterwards like a finished job
			var ek := Story.eos_pick
			var go2: bool = ek != "" and await WorldMap.trip_eos(root, ek)
			if go2 and WorldMap.want_prepare():
				go2 = await PrepareScreen.run(root, ek)
			if not go2:
				start_story(Ground.STARTMODE_GROUND)
				return
			GVars.set_val(null, GVars.DUNGEON_ENTER, 81)
			GVars.set_val(null, GVars.DUNGEON_ENTER_INDEX, GData.rescue_to_script(GData.rescue_id("RESCUE_DUNGEON_TINY_WOODS")))
			GVars.set_val(null, GVars.START_MODE, 7)
			GVars.set_val(null, GVars.DUNGEON_RESULT, 7)
			story_dungeon = true
			start_dungeon(ek)
		_:
			title()

var story_dungeon := false

## First floor (index > 0) of a dungeon that is a fixed-room arena, or -1.
func _boss_floor(key: String) -> int:
	var fl: Array = DB.dungeons.get("dungeons", {}).get(key, {}).get("floors", [])
	for i in range(1, fl.size()):
		var pr: Array = fl[i].get("props", [])
		if pr.size() > 18 and int(pr[18]) != 0 and int(pr[18]) < 50:   # floor-wide arenas only
			return i
	return -1

func _fa_enum_name(k: String) -> String:
	for v in GData.extra.enums.friend_areas:
		var n: String = GData.extra.enums.friend_areas[v]
		if n.trim_prefix("FRIEND_AREA_").to_lower().replace("_", "") == k:
			return n.trim_prefix("FRIEND_AREA_")
	return ""

## --storytest post-game helper: HMs, the Friend Areas the side stories check, and the legendaries they need recruited.
func _test_postgame_grants() -> void:
	# the test save's team was reset to Lv30-ish by an old boss test: bring it to a normal post-game level
	for e in Game.team:
		if int(e.level) < 55:
			e.level = 55
			e.exp = DB.exp_at(str(e.sp), 55)
			print("  TEST team level ", e.name, " -> 55")
	# Red's entry check (GetItemPossessionCount) counts the Toolbox and held items, not storage
	for it in ["surf", "dive"]:
		if not Game.bag.any(func(b): return str(b.get("id", "")) == it):
			if Game.bag.size() >= Game.BAG_MAX:
				Game.bag.pop_back()
			Game.bag_add(it, 1)
			print("  TEST grant item (Toolbox) ", it)
	for fa in ["skyblueplains", "southernisland", "legendaryisland", "serenesea", "furnacedesert", "bouldercave", "dragoncave", "secretiveforest", "agedchamberan", "agedchambero"]:
		if not fa in Game.friend_areas:
			Game.friend_areas.append(fa)
			print("  TEST grant friend area ", fa)
	var S2 := GVars.SCENARIO_SUB2
	var want: Array = []
	if not GVars.before(GVars.SCENARIO_SUB6, 0x30, 0):
		want.append_array(["0144", "0145", "0146"])     # Articuno, Zapdos, Moltres (beaten in the story; recruited on re-fights)
	if not GVars.before(S2, 0x23, 0):
		want.append("0249")                              # Lugia (Silver Trench)
	if not GVars.before(GVars.SCENARIO_SUB4, 0x2b, 0):
		want.append("0250")                              # Ho-Oh (Mt. Faraway)
	for sp in want:
		if not Story._recruited(sp):
			Story.add_friend(sp, "", 40, [])
			print("  TEST grant recruit ", sp)

## The ground menu (B button / SPECIAL_TEXT_FRIEND_MENU). Returns Red's menu result (0 = closed).
func ground_menu(_g, mon: Dictionary = {}) -> int:
	return await _on_town_menu(mon)     # 2: Exit (Friend Areas map), 3: visit, 4: formation changed -> FORMATION_HERO

## Red's personality test (scripts/ui/quiz.gd). Returns the hero species key, or "" to pick freely.
## The nature / gender are kept in the "quiz_result" meta for new_game() to store after Game.new_game().
func quiz() -> String:
	var r: Dictionary = await Quiz.run(root)
	set_meta("quiz_result", r)
	return str(r.get("hero", ""))

func pick_species(title_txt: String, keys: Array, exclude: String) -> String:
	var list: Array = []
	for k in keys:
		if k != exclude and DB.species.has(k):
			if exclude != "" and DB.species[k].types[0] == DB.species[exclude].types[0]:
				continue
			list.append(k)
	var opts: Array = []
	for k in list:
		opts.append(DB.species[k].name)
	var lm := ListMenu.make(title_txt, opts, false)
	var preview := MonPreview.new()
	root.add_child(preview)
	preview.position = Vector2(root.get_viewport_rect().size.x * 0.68, root.get_viewport_rect().size.y * 0.5)
	lm.on_select = func(i): preview.show_species(list[i])
	root.add_child(lm)
	lm.position = Vector2(20, 10)
	preview.show_species(list[0])
	var i := await lm.choose()
	preview.queue_free()
	Audio.sfx("join")
	return list[i]

func _center(c: Control, off := Vector2.ZERO) -> void:
	root.add_child(c)
	await get_tree().process_frame
	if not is_instance_valid(c):
		return
	c.position = (root.get_viewport_rect().size - c.size) / 2 + off

# ------------------------------------------------------------------ dungeon
func start_dungeon(key: String, first_floor := 0, stop := -1) -> void:
	Game.flags["adventures"] = int(Game.flags.get("adventures", 0)) + 1
	AdventureLog.add("floors")             # the first floor (dungeon.next_floor counts the rest)
	if Game.team.size() > 0:
		AdventureLog.mark_leader(str(Game.team[0].get("sp", "")))
	_clear()
	last_dungeon = key
	hud = Hud.new()
	root.add_child(hud)
	dungeon = Dungeon.new()
	add_child(dungeon)
	dungeon.hud = hud
	dungeon.ui_root = root
	hud.button.connect(dungeon.on_hud_button)
	dungeon.finished.connect(_on_dungeon_finished)
	# Red: everyone starts each expedition at full HP/PP
	for e in Game.team:
		for mv in e.moves:
			mv.pp = int(mv.max_pp)
	dungeon.start_floor = first_floor
	dungeon.stop_floor = stop
	await dungeon.start(key, Game.team)

var last_dungeon := ""

func _on_dungeon_finished(res: String) -> void:
	var ok := res != "defeated"
	Audio.play_music("052" if ok else "051")
	if dungeon and dungeon.has_method("show_last_outing"):
		await dungeon.show_last_outing(root, res)      # Red's "The Last Outing" window
	var lines: Array = []
	if res == "cleared":
		lines.append("[color=#ffdc4a]You cleared %s![/color]" % Services.dname(last_dungeon))
		for k in Services.on_cleared(last_dungeon):
			lines.append("A new place opened up: [color=#7fe0ff]%s[/color]!" % Services.dname(k))
	elif res == "rescued":
		lines.append("[color=#ffdc4a]The rescue was a success![/color]")
	elif res == "escaped":
		lines.append("The team escaped from the dungeon.")      # Escape Orb: nothing is lost
	elif Dojo.is_maze_key(last_dungeon):
		lines.append("[color=#ff8070]The team was defeated...[/color]")     # training mazes keep money and items
	else:
		# Red: fainting in a dungeon costs all money and some of your items
		lines.append("[color=#ff8070]The team was defeated...[/color]")
		lines.append("You lost your money and some items.")
		Game.money = 0
		var keep: Array = []
		for b2 in Game.bag:
			if randf() < 0.5:
				keep.append(b2)
		Game.bag = keep
	if dungeon:
		for n in dungeon.recruited_names:
			lines.append("%s is now living in its Friend Area." % n)
	for e in Game.team:
		lines.append("%s  Lv %d" % [e.name, int(e.level)])
	if not ok:
		FriendRescue.on_defeated(last_dungeon, dungeon.floor_i if dungeon else 0)    # an SOS Mail can be sent
	Missions.on_dungeon_end(last_dungeon, res)
	Game.save_game()
	await Dialog.talk(root, ["\n".join(lines)])
	_clear()
	for j in Game.jobs:
		if j.get("wonder_mail", false) and str(j.get("state", "")) in ["done_pending", "done"]:
			WonderMail.note_completed(j)
	var finished_jobs: int = 0 if Story.thank_you_in_ground(ok) else Missions.pending_rewards().size()
	if not Story.thank_you_in_ground(ok):
		await Missions.complete_rewards(root)      # (story job runs: the clients thank the team at the Post Office, SP_UNK_22/23)
	if finished_jobs > 0 and Game.story.has("vars"):
		# Red counts finished rescue jobs in CLEAR_COUNT (SPECIAL_TEXT_UNK_23); the story checks it
		var cc := GVars.var_id("CLEAR_COUNT")
		GVars.set_val(null, cc, mini(100, GVars.get_val(null, cc) + finished_jobs))
		GVars.set_val(null, 0x39, 1)
	Game.save_game()
	if story_dungeon or Game.story.has("vars"):
		story_dungeon = false
		start_story(Ground.STARTMODE_DUNGEON_WON if ok else Ground.STARTMODE_DUNGEON_LOST)
		return
	start_town("base", "world_map")

## Missions / Board / WonderMailUI are optional at compile time (added in parallel); call them dynamically.
func _missions_call(fn: String, args: Array) -> Variant:
	if not ResourceLoader.exists("res://scripts/core/missions.gd"):
		return null
	var M = load("res://scripts/core/missions.gd")
	if M.has_method(fn) or true:
		return await M.callv(fn, args)
	return null

# ------------------------------------------------------------------ town (Pokémon Square, team base, ...)
var town: Town

## Open a walkable town map: "square", "base", "post_office", "dojo", "whiscash".
## arrive_at = the map (or exit id) we come from, so the team appears at the right doorway.
func start_town(map_key := "square", arrive_at := "") -> void:
	_clear()
	if is_instance_valid(town):
		town.queue_free()
	town = Town.new()
	add_child(town)
	town.interact.connect(_on_town_interact)
	town.exit.connect(_on_town_exit)
	town.menu.connect(_on_town_menu)
	town.start(map_key, root, arrive_at)

func _on_town_interact(id: String) -> void:
	if is_instance_valid(town):
		town.set_paused(true)
	match id:
		"kecleon_shop", "kecleon_wares":
			Audio.play_music("017")
			await Services.kecleon(root, id == "kecleon_wares")
			Audio.play_music("007")
		"persian_bank":
			await Services.bank(root)
		"wigglytuff":
			await Services.wigglytuff(root)
		"kangaskhan_storage":
			await Services.storage(root)
		"pelipper_board":
			await post_office()
		"gulpin_shop":
			await Gulpin.shop(root)
		"makuhita_dojo":
			await Dialog.say(root, "Makuhita: Hoh! The Dojo's training mazes open soon. Train hard till then!", "0296")
		"whiscash":
			await Dialog.say(root, "Whiscash: ...Hmm. The world has been shaking a lot lately...", "0340")
		"bed":
			await Services.sleep(root)
			Missions.refresh_board_if_new_day()
		"mailbox":
			Missions.refresh_mailbox_if_new_day()
			await Board.open_mailbox(root)
		"nohome":
			await Dialog.say(root, "Nobody seems to be home.")
		_:
			await Dialog.say(root, "...")
	if is_instance_valid(town):
		town.set_paused(false)

func post_office() -> void:
	var P := "0279"
	Missions.refresh_board_if_new_day()
	while true:
		var c := await Dialog.ask(root, "Pelipper: Welcome to the Pelipper Post Office! What can I do for you?", ["Bulletin Board", "Job List", "Wonder Mail", "Make Wonder Mail", "Guide", "Friend Rescue", "Leave"], P)
		match c:
			0, 1:
				if ResourceLoader.exists("res://scripts/ui/board.gd"):
					var B = load("res://scripts/ui/board.gd")
					if c == 0:
						await B.open_board(root)
					else:
						await B.open_job_list(root)
			2:
				if ResourceLoader.exists("res://scripts/ui/wonder_mail_ui.gd"):
					await load("res://scripts/ui/wonder_mail_ui.gd").enter_code(root)
			3:
				if ResourceLoader.exists("res://scripts/ui/wonder_mail_ui.gd"):
					await load("res://scripts/ui/wonder_mail_ui.gd").maker(root)
			4:
				await PostOffice.help_counter(root)
			5:
				await FriendRescue.counter(root)
			_:
				await Dialog.say(root, "Pelipper: Good luck out there!", P)
				Game.save_game()
				return

func _on_town_exit(to: String) -> void:
	if to in Town.TOWN_MAPS:
		start_town(to, town.map_key if is_instance_valid(town) else "")
		return
	if is_instance_valid(town):
		town.set_paused(true)
	if to == "world_map":
		while true:
			var k := await Services.world_map(root)
			if k.begins_with("fa:"):
				await Services.visit_area(root, k.substr(3))
			elif k != "":
				# Red's world map trip first (scripts/ui/world_map.gd), then the remake's Prepare screen
				var trip_ok := true
				if not ListMenu.auto:
					if k.begins_with("eos_"):
						trip_ok = await WorldMap.trip_eos(root, k)
					else:
						trip_ok = await WorldMap.trip_red(root, k)
				if not trip_ok:
					continue
				# Prepare for dungeon: team / Toolbox / jobs / dungeon info, then Set out or Cancel (back to the map)
				if await PrepareScreen.run(root, k):
					DungeonSave.clear()          # a stale suspend file must not outlive a new expedition
					start_dungeon(k)
					return
				if ListMenu.auto:
					break
				continue
			break
	elif to == "friend_areas":
		if Game.friend_areas.is_empty():
			await Dialog.say(root, "You don't have any Friend Areas yet. Wigglytuff in Pokémon Square sells them!")
		else:
			var fk := await Services.pick_friend_area(root)
			if fk != "":
				await Services.visit_area(root, fk)
	if is_instance_valid(town):
		town.set_paused(false)

func _on_town_menu(mon: Dictionary = {}) -> int:
	# Red's base menu (code_801D014.c): Items / Team / Job List / Others with the place / rank / money windows,
	# Friend / Items / Info / Exit in a Friend Area (scripts/town/base_menu.gd). Others keeps the remake's
	# Pokédex, Save and Title screen; Game Options holds Red's options plus Hunger / Controls / Second screen.
	if is_instance_valid(town):
		town.set_paused(true)
	if is_instance_valid(ground):
		ground.set_process(false)
	var r := await BaseMenu.open(self, root, mon)
	if is_instance_valid(town):
		town.set_paused(false)
	if is_instance_valid(ground):
		ground.set_process(true)
	return r

# ------------------------------------------------------------------ input map
func _setup_input() -> void:
	Controls.apply()     # keyboard + controller bindings (changeable in Settings → Controls)

# ------------------------------------------------------------------ automated smoke test (desktop only)
func _movetest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Test")
	await start_dungeon("tiny_woods")
	await get_tree().create_timer(1.0).timeout
	for i in 12:
		var dirs := [0, 2, 4, 6, 1, 3, 5, 7]
		var t0 := Time.get_ticks_usec()
		var d: int = dirs[i % 8]
		await dungeon.leader_action({"type": "move", "dir": d})
		var t1 := Time.get_ticks_usec()
		print("MOVE ", i, " ms=", (t1 - t0) / 1000.0, " pos=", dungeon.fs.leader.pos)
	get_tree().quit()

func _fxtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Test")
	Game.settings.zoom = 2.0
	await start_dungeon("tiny_woods")
	dungeon.auto_answer = true
	await get_tree().create_timer(1.0).timeout
	var L: Mon = dungeon.fs.mons[0]
	var foe: Mon = null
	for x in dungeon.fs.mons:
		if not x.is_team():
			foe = x
			break
	if foe:
		foe.pos = L.pos + Vector2i(3, 0)
		foe.visual.position = dungeon._px(foe.pos)
		foe.hp = 999
	if OS.get_cmdline_user_args().has("--scaletest"):
		for sc in [0.8, 1.3]:
			Game.settings.ui_scale = sc
			UITheme.apply_ui_scale()
			dungeon.set_zoom(2.0)
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png("user://scale_%d.png" % int(sc * 100))
		dungeon.auto_answer = false
		dungeon._option_page("Others", ["ui_scale", "touch"])
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("user://scale_opt.png")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--edgetest"):
		dungeon.set_zoom(0.75)
		dungeon.cam.position = Vector2(0, 0)
		await get_tree().create_timer(0.2).timeout
		dungeon.cam.position = Vector2(0, 0)
		set_process(false)
		dungeon.set_process(false)
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("user://edge_dg.png")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--dmgtest"):
		var T2: Mon = dungeon.fs.mons[1]
		dungeon.red_number(L, -23)
		dungeon.red_number(T2, 9999)
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png("user://dmg_a.png")
		dungeon.red_number(L, 15)
		dungeon.red_number(T2, -105)
		await get_tree().create_timer(0.35).timeout
		get_viewport().get_texture().get_image().save_png("user://dmg_b.png")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--loadtest"):
		_clear()
		Game.load_game()
		_load_screen()
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png("user://load_screen.png")
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--modetest"):
		dungeon._set_rotate(true)
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("user://mode_rot.png")
		dungeon._set_rotate(false)
		Input.action_press("act_diag")
		await get_tree().create_timer(0.2).timeout
		get_viewport().get_texture().get_image().save_png("user://mode_diag.png")
		Input.action_release("act_diag")
		get_tree().quit()
		return
	var mvs := ["Ember", "Water Gun", "Thunderbolt", "Psychic", "Razor Leaf", "Moonblast", "Hyper Beam", "Shadow Ball"]
	var i := 0
	for mv in mvs:
		dungeon.do_attack(L, mv, 2)
		for k in 6:
			await get_tree().create_timer(0.12).timeout
			get_viewport().get_texture().get_image().save_png("user://fx_%02d_%d.png" % [i, k])
		await get_tree().create_timer(1.2).timeout
		if foe:
			foe.hp = 999
		i += 1
	print("FXTEST done")
	get_tree().quit()

func _autotest() -> void:
	var shots := OS.get_cmdline_user_args().has("--shots")
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Test")
	Game.settings.zoom = 1.25
	await start_dungeon("tiny_woods")
	dungeon.auto_answer = true
	await get_tree().create_timer(1.5).timeout
	if shots:
		get_viewport().get_texture().get_image().save_png("user://shot_floor.png")
		dungeon.hud.msg("Charmander used [color=#7fe0ff]Scratch[/color]!")
		dungeon.hud.msg("Pidgey took [color=#ffdc4a]16[/color] damage!")
		dungeon.auto_answer = false
		dungeon.open_main_menu()
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png("user://shot_menu.png")
		for c in root.get_children():
			if c is ListMenu: c._finish(-1)
		await get_tree().create_timer(0.3).timeout
		dungeon.open_moves()
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png("user://shot_moves.png")
		for c in root.get_children():
			if c is ListMenu: c._finish(-1)
		await get_tree().create_timer(0.3).timeout
		dungeon.auto_answer = true
	dungeon.set_autoplay(true)
	var t := 0.0
	var shot_i := 0
	var last_floor := -1
	while t < 240.0 and dungeon and not dungeon.result_sent:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if not dungeon.autoplay and not dungeon.result_sent:
			print("autoplay stopped at t=", t, " hp=", dungeon.fs.leader.hp)
			dungeon.set_autoplay(true)
		if dungeon.floor_i != last_floor:
			last_floor = dungeon.floor_i
			print("floor ", dungeon.floor_i + 1, " at t=", t, " turn=", dungeon.fs.turn)
		if OS.get_cmdline_user_args().has("--fightshots") and int(t * 2) % 2 == 0 and t < 30:
			get_viewport().get_texture().get_image().save_png("user://fight_%02d.png" % int(t))
		if shots and int(t * 2) % 30 == 0:
			get_viewport().get_texture().get_image().save_png("user://shot_%d.png" % shot_i)
			shot_i += 1
	for l in hud.log_all.slice(maxi(0, hud.log_all.size() - 25)):
		print("  LOG ", l)
	if dungeon:
		print("AUTOTEST done t=", t, " floor=", dungeon.floor_i + 1, " result_sent=", dungeon.result_sent, " team=", Game.team.map(func(e): return "%s Lv%d" % [e.name, int(e.level)]))
	get_tree().quit()


# ------------------------------------------------------------------ end-to-end flow test (desktop only)
func _shot(n: String) -> void:
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png("user://flow_%s.png" % n)

func _flowtest() -> void:
	Dialog.auto = true
	ListMenu.auto = true
	Game.new_game("0258", "Mudkip", "0255", "Torchic", "Flow")
	Game.money = 2000
	Game.cleared = ["tiny_woods"]
	Game.unlocked = ["tiny_woods", "thunderwave_cave"]
	start_town("base")
	await get_tree().create_timer(1.5).timeout
	await _shot("1_base")
	# buy a Friend Area, visit the shops through the real service code
	await Services.wigglytuff(root)
	print("friend areas: ", Game.friend_areas, " money ", Game.money)
	print("kecleon stock: ", Services.shop_stock())
	Game.bag_add("oran"); Game.bag_add("apple")
	# board: accept and take a job
	Game.board_day = -1
	Missions.refresh_board_if_new_day()
	print("board jobs: ", Game.board.size())
	for j in Game.board:
		if j.dungeon in Game.unlocked and j.kind in ["rescue", "target", "deliver"]:
			Missions.accept(j)
			for k in Game.jobs:
				if k.id == j.id:
					Missions.take(k)
			print("took job: ", j.kind, " ", j.dungeon, " F", j.floor, " ", j.get("title", ""))
			break
	start_town("post_office", "square")
	await get_tree().create_timer(1.0).timeout
	await _shot("2_post")
	# (board UI is covered by tests/board_test.tscn)
	# go to the first job's dungeon with Autoplay
	var dk: String = Game.jobs[0].dungeon if Game.jobs.size() > 0 else "thunderwave_cave"
	await start_dungeon(dk)
	dungeon.auto_answer = true
	dungeon.set_autoplay(true)
	var t := 0.0
	while t < 200.0 and dungeon and not dungeon.result_sent:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if dungeon and not dungeon.autoplay and not dungeon.result_sent:
			dungeon.set_autoplay(true)
		if int(t) == 20 and fmod(t, 1.0) == 0.0:
			await _shot("3_dungeon")
	print("dungeon done t=", t, " jobs=", Game.jobs.map(func(j): return "%s:%s" % [j.kind, j.state]))
	await get_tree().create_timer(6.0).timeout
	await _shot("4_back")
	print("FLOWTEST rank_points=", Game.rank_points, " money=", Game.money, " cleared=", Game.cleared, " unlocked=", Game.unlocked, " friends=", Game.friends.size())
	get_tree().quit()


func _wmtest() -> void:
	Dialog.auto = true
	ListMenu.auto = true
	var cont := OS.get_cmdline_user_args().has("--continue")
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "WM")
	var code := WonderMail.encode({"kind": "rescue", "dungeon": "tiny_woods", "floor": 2, "client": "0025", "target": "0025", "reward_type": 0})
	print("code ", code)
	var r := WonderMail.decode(code)
	print("decode ok=", r.ok, " err=", r.error)
	print("receive: '", WonderMail.receive(r.job), "'")
	for j in Game.jobs:
		Missions.take(j)
	print("jobs ", Game.jobs.map(func(j): return "%s %s F%d %s" % [j.kind, j.dungeon, int(j.floor), j.state]))
	await start_dungeon("tiny_woods")
	dungeon.auto_answer = not cont
	var t := 0.0
	var talked := false
	while t < 150.0 and dungeon and not dungeon.result_sent:
		await get_tree().create_timer(0.3).timeout
		t += 0.3
		if dungeon == null or dungeon.result_sent:
			break
		if dungeon.busy or dungeon.menu_open:
			continue
		var fs := dungeon.fs
		if not talked:
			for m in fs.mons:
				if Missions.is_client(m):
					var p := fs.free_tile_near(m.pos, fs.leader, 2)
					fs.leader.pos = p
					fs.leader.visual.position = dungeon._px(p)
					print("client found on floor ", dungeon.floor_i + 1, " at ", m.pos)
					talked = true
					dungeon.busy = true
					dungeon.auto_answer = cont        # with --continue: choose to keep exploring
					await Missions.on_talk(dungeon, m)
					dungeon.busy = false
					print("after talk: result_sent=", dungeon.result_sent, " jobs=", Game.jobs.map(func(j): return j.state))
					break
		if not dungeon.result_sent and not dungeon.autoplay:
			dungeon.set_autoplay(true)
	print("dungeon over t=", t)
	await get_tree().create_timer(8.0).timeout
	print("scene: town=", is_instance_valid(town), " jobs=", Game.jobs.map(func(j): return j.state), " rank=", Game.rank_points, " money=", Game.money, " wm_done=", Game.flags.get("wm_done", []))
	get_tree().quit()


# ------------------------------------------------------------------ IQ / Link Shop / base menu UI test
func _iqshot(n: String) -> void:
	await get_tree().create_timer(0.35).timeout
	get_viewport().get_texture().get_image().save_png("user://iq_%s.png" % n)

func _iqtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "IQ")
	Game.money = 1000
	Game.team[0].iq = 120
	Game.team[0].moves = DB.default_moves("0004", 30)
	Game.team[0].level = 30
	Game.team[1].moves = DB.default_moves("0007", 12)
	Game.team[1].level = 12
	Game.bag_add("redgummi"); Game.bag_add("bluegummi"); Game.bag_add("oran")
	start_town("base")
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(town):
		town.set_paused(true)
	# static screens (menus left open for a screenshot, then closed)
	var lm := ListMenu.make("", ["Team", "Items", "Job List", "Settings", "Save", "Title screen", "Close"])
	root.add_child(lm); lm.position = Vector2(8, 8)
	await _iqshot("1_base_menu"); lm.queue_free()
	var mv := ListMenu.make("Charmander's moves", Gulpin.move_rows(Game.team[0], true))
	IQ.link(Game.team[0].moves, 0)
	var mv2 := ListMenu.make("Charmander's moves", Gulpin.move_rows(Game.team[0], true))
	root.add_child(mv2); mv2.position = Vector2(8, 8)
	await get_tree().process_frame
	var sm := ListMenu.make("", ["Deselect", "Link", "Delink", "Forget", "Shift up", "Info"])
	root.add_child(sm); sm.position = Vector2(250, 8)
	await _iqshot("2_link_moves"); mv2.queue_free(); sm.queue_free(); mv.free()
	IQ.delink(Game.team[0].moves, 0)
	await Gulpin._show_money(root)
	var d := Dialog.get_box(root)
	d._show(Gulpin.pages(0)[0], "0316", "Normal", "")
	d._finish_typing()
	await _iqshot("3_gulpin_greet"); d.hide_box(); Gulpin._hide_money()
	# check IQ screen
	Dialog.auto = true
	ListMenu.auto = false
	IQ.check_iq_ui(root, Game.team[0])
	await _iqshot("4_check_iq")
	for c in root.get_children():
		if c is ListMenu:
			c._finish(-1)
	await get_tree().create_timer(0.2).timeout
	Game.team[0].level = 60
	Game.team[0].moves = DB.default_moves("0004", 60)
	var rl := ListMenu.make("Remember which move?", IQ.rememberable(Game.team[0]).slice(0, 8) + ["More... (1/2)"])
	root.add_child(rl); rl.position = Vector2(8, 8)
	await _iqshot("5_remember"); rl.queue_free()
	# automated runs through the real flows
	ListMenu.auto = true
	print("IQTEST gulpin shop")
	await Gulpin.shop(root)
	print("IQTEST money after shop ", Game.money, " moves ", Game.team[0].moves.map(func(m): return "%s%s" % ["+" if m.linked else "", m.name]))
	print("IQTEST town menu")
	await _on_town_menu()
	print("IQTEST gummi")
	var r := IQ.eat_gummi(Game.team[0], "redgummi", false)
	print("IQTEST ", r)
	print("IQTEST done")
	get_tree().quit()


# ------------------------------------------------------------------ dungeon menu screenshots (desktop only)
func _mt_press(a: String) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var e2 := InputEventAction.new()
	e2.action = a
	e2.pressed = false
	Input.parse_input_event(e2)
	await get_tree().create_timer(0.15).timeout

func _mt_shot(n: String) -> void:
	await get_tree().create_timer(0.35).timeout
	get_viewport().get_texture().get_image().save_png("user://menu_%s.png" % n)
	print("shot ", n)

func _mt_close() -> void:
	for i in 12:
		if TeamScreens._stack.is_empty():
			break
		await _mt_press("ui_accept" if not (TeamScreens._stack.back() is Control) else "ui_cancel")
	await get_tree().create_timer(0.3).timeout

func _menutest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Ember")
	Game.settings.zoom = 1.25
	Game.money = 340
	Game.bag_add("oran"); Game.bag_add("apple"); Game.bag_add("stick", 10); Game.bag_add("sleepseed"); Game.bag_add("bluegummi")
	Game.team[1].held = "pecha"
	await start_dungeon("tiny_woods")
	await get_tree().create_timer(2.0).timeout
	var d := dungeon
	var L: Mon = d.fs.leader
	var P: Mon = d.fs.team()[1] if d.fs.team().size() > 1 else L
	d.hud.msg("Charmander used [color=#7fe0ff]Scratch[/color]!")
	d.open_main_menu()
	await _mt_shot("main")
	await _mt_press("ui_accept")
	await _mt_shot("moves")
	await _mt_press("ui_accept")
	await _mt_shot("moves_cmd")
	await _mt_press("ui_down"); await _mt_press("ui_down"); await _mt_press("ui_accept")
	await _mt_shot("move_info")
	await _mt_close()
	d.open_bag()
	await _mt_shot("items")
	await _mt_press("ui_accept")
	await _mt_shot("items_cmd")
	await _mt_close()
	d.open_team()
	await _mt_shot("team")
	await _mt_press("ui_down"); await _mt_press("ui_accept")
	await _mt_shot("team_cmd")
	await _mt_close()
	for pg in 4:
		TeamScreens.summary(root, P, pg)
		await _mt_shot("summary_%d" % pg)
		await _mt_close()
	TeamScreens.iq_menu(root, P)
	await _mt_shot("iq")
	await _mt_close()
	TeamScreens.tactics_menu(root, P)
	await _mt_shot("tactics")
	await _mt_close()
	d.open_main_menu()
	await get_tree().create_timer(0.3).timeout
	for k in 3:
		await _mt_press("ui_down")
	await _mt_press("ui_accept")
	await _mt_shot("others")
	await _mt_press("ui_accept")
	await _mt_press("ui_accept")
	await _mt_shot("options")
	await _mt_press("ui_right")
	await _mt_shot("options_changed")
	await _mt_close()
	d.menu_open = true
	d._hints_menu()
	await _mt_press("ui_accept")
	await _mt_shot("hint")
	await _mt_close()
	d._mission_objectives()
	await _mt_shot("objectives")
	await _mt_close()
	d.open_log()
	await _mt_shot("log")
	await _mt_close()
	d.menu_open = false
	d.open_ground()
	await _mt_shot("ground")
	await _mt_close()
	d.menu_open = true
	d._stairs_menu()
	await _mt_press("ui_accept")
	await _mt_shot("stairs")
	await _mt_close()
	d.menu_open = false
	TeamScreens.team_menu(root, Game.team, false)
	await _mt_shot("town_team")
	await _mt_close()
	TeamScreens.summary(root, Game.team[0], 3)
	await _mt_shot("town_summary")
	await _mt_close()
	TeamScreens.move_info(root, "Ember")
	await _mt_shot("ember")
	await _mt_close()
	# linked chain: link the leader's first two moves and use them with one command
	if L.moves.size() >= 2:
		L.moves[1].linked = true
		var pp0 := [int(L.moves[0].pp), int(L.moves[1].pp)]
		var b0: float = d.belly_state.belly
		await d.leader_action({"type": "attack", "move": L.moves[0].name, "dir": L.facing, "chain": [L.moves[0].name, L.moves[1].name]})
		print("LINK pp before ", pp0, " after ", [int(L.moves[0].pp), int(L.moves[1].pp)], " belly ", b0, " -> ", d.belly_state.belly)
	await _mt_shot("after_link")
	print("MENUTEST done stack=", TeamScreens._stack.size(), " menu_open=", d.menu_open)
	get_tree().quit()



func _pad(btn: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = down
	Input.parse_input_event(e)

func _tap(btn: int) -> void:
	_pad(btn, true)
	await get_tree().create_timer(0.08).timeout
	_pad(btn, false)
	await get_tree().create_timer(0.4).timeout

func _padtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Pad")
	await start_dungeon("tiny_woods")
	await get_tree().create_timer(2.0).timeout
	var L := dungeon.fs.leader
	var p0 := L.pos
	await _tap(JOY_BUTTON_B)
	var menu_seen := false
	for c in root.get_children():
		if c.get_class() != "Control" or true:
			if str(c.name).length() > 0 and (c is ListMenu or c.get_script() != null and str(c.get_script().resource_path).contains("team_screens")):
				menu_seen = true
	print("tap B opened a menu: ", dungeon.menu_open or menu_seen)
	_pad(JOY_BUTTON_B, true); _pad(JOY_BUTTON_B, false)        # close it (B = cancel)
	await get_tree().create_timer(0.6).timeout
	print("menu closed: ", not dungeon.menu_open)
	var t0 := dungeon.fs.turn
	await _tap(JOY_BUTTON_A)
	await get_tree().create_timer(0.6).timeout
	print("A attacked (turn advanced): ", dungeon.fs.turn > t0)
	_pad(JOY_BUTTON_START, true); _pad(JOY_BUTTON_START, false)
	await get_tree().create_timer(0.3).timeout
	print("Start -> turn-in-place mode: ", dungeon._rotate)
	_pad(JOY_BUTTON_DPAD_RIGHT, true)
	await get_tree().create_timer(0.5).timeout
	_pad(JOY_BUTTON_DPAD_RIGHT, false)
	print("rotate: faced right without moving: ", L.facing == 2 and L.pos == p0)
	await _tap(JOY_BUTTON_START)
	print("rotate off: ", not dungeon._rotate)
	_pad(JOY_BUTTON_RIGHT_SHOULDER, true)
	_pad(JOY_BUTTON_DPAD_RIGHT, true)
	await get_tree().create_timer(0.5).timeout
	_pad(JOY_BUTTON_DPAD_RIGHT, false)
	_pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	await get_tree().create_timer(0.4).timeout
	print("hold R + Right: no straight move: ", L.pos == p0)
	var t1 := dungeon.fs.turn
	_pad(JOY_BUTTON_A, true); _pad(JOY_BUTTON_B, true)
	await get_tree().create_timer(0.1).timeout
	_pad(JOY_BUTTON_A, false); _pad(JOY_BUTTON_B, false)
	await get_tree().create_timer(0.8).timeout
	print("A+B waited a turn: ", dungeon.fs.turn > t1)
	Controls.set_pad("gp_a", JOY_BUTTON_B)
	print("swap A/B: A action now ", Controls.pad_name(Controls.pad_for("gp_a")), ", B action now ", Controls.pad_name(Controls.pad_for("gp_b")))
	Controls.reset()
	print("PADTEST done")
	get_tree().quit()


# ------------------------------------------------------------------ second screen test (desktop only)
func _thor_shot(n: String) -> void:
	await get_tree().create_timer(0.4).timeout
	var bs := BottomScreen.instance
	bs.screenshot("user://thor_%s_sub.png" % n)
	if is_instance_valid(bs.win):
		bs.win.get_texture().get_image().save_png("user://thor_%s_win.png" % n)
	get_viewport().get_texture().get_image().save_png("user://thor_%s_main.png" % n)
	print("thor shot ", n)

func _thortest() -> void:
	Dialog.auto = true
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "T")
	Game.money = 340
	var old_setting = Game.settings.get("second_screen", "auto")
	Game.settings["second_screen"] = "window"
	await get_tree().process_frame
	var bs := BottomScreen.instance
	bs.refresh_mode()
	print("THORTEST mode=", bs.mode, " logical=", bs.logical, " for ", bs.target_size, " native_window=", is_instance_valid(bs.win) and not bs.win.is_embedded())
	start_dungeon("tiny_woods")
	await get_tree().create_timer(2.5).timeout
	await _thor_shot("dungeon")
	var L := dungeon.fs.leader
	var t0 := dungeon.fs.turn
	print("tap wait: ", bs.test_tap("wait"))
	await get_tree().create_timer(0.8).timeout
	print("wait advanced the turn: ", dungeon.fs.turn > t0, " (", t0, " -> ", dungeon.fs.turn, ")")
	bs.test_tap("zoom")
	await _thor_shot("zoom")
	bs.test_tap("zoom")
	bs.test_tap("moves")
	await get_tree().create_timer(0.5).timeout
	print("moves menu opened: ", dungeon.menu_open)
	await _thor_shot("moves")
	for i in 8:
		if not dungeon.menu_open:
			break
		await _mt_press("ui_cancel")
	await get_tree().create_timer(0.3).timeout
	print("menu closed: ", not dungeon.menu_open)
	bs.test_tap("auto")
	await get_tree().create_timer(0.3).timeout
	print("autoplay on: ", dungeon.autoplay)
	dungeon.auto_answer = true
	await get_tree().create_timer(8.0).timeout
	await _thor_shot("auto")
	bs.test_tap("auto")
	await get_tree().create_timer(0.5).timeout
	print("autoplay off: ", not dungeon.autoplay, " leader at ", L.pos, " floor ", dungeon.floor_i + 1, " taps=", bs.taps)
	Game.team[0].held = "oran"
	Game.jobs = [{"kind": "rescue", "dungeon": "tiny_woods", "floor": 3, "state": "taken"}, {"kind": "deliver", "dungeon": "thunderwave_cave", "floor": 2, "state": "done"}]
	start_town("base")
	await get_tree().create_timer(2.0).timeout
	await _thor_shot("town")
	Game.jobs = []
	bs.test_tap("menu")
	await get_tree().create_timer(0.6).timeout
	await _thor_shot("town_menu")
	Game.settings["second_screen"] = old_setting
	print("THORTEST done")
	get_tree().quit()


# ------------------------------------------------------------------ town QoL test (desktop only): prepare screen,
# Pokédex, bank / storage / Kecleon bulk actions, board bulk accept, quicksave -> resume (tests/test_town2.gd)
func _towntest2() -> void:
	add_child(load("res://tests/test_town2.gd").new())


# ------------------------------------------------------------------ dungeon QoL test (desktop only): --qoltest
func _qshot(n: String) -> void:
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png("user://qol_%s.png" % n)
	print("QOLTEST shot qol_%s.png" % n)

func _qcheck(what: String, ok: bool, extra := "") -> void:
	print("QOLTEST %s %s %s" % ["PASS" if ok else "FAIL", what, extra])

func _qact(a: String, down: bool) -> void:
	var e := InputEventAction.new()
	e.action = a
	e.pressed = down
	Input.parse_input_event(e)

func _qwin(vp: Vector2) -> Vector2:          # viewport (480x270) position -> window position for parse_input_event
	return get_tree().root.get_final_transform() * vp

func _qtouch(vp: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = _qwin(vp)
	e.pressed = down
	Input.parse_input_event(e)

func _qwait_idle(limit := 8.0) -> void:
	var t := 0.0
	while t < limit and (dungeon.qol.is_moving() or dungeon.busy):
		await get_tree().create_timer(0.1).timeout
		t += 0.1
	await get_tree().create_timer(0.2).timeout

func _qplace(m: Mon, p: Vector2i) -> void:
	m.pos = p
	if m.visual:
		m.visual.position = dungeon._px(p)
	dungeon._reveal()

func _qclear() -> void:
	var fs := dungeon.fs
	for m in fs.mons.duplicate():
		if not m.is_team():
			if m.visual:
				m.visual.queue_free()
				m.visual = null
			fs.mons.erase(m)
	fs.items.clear()
	fs.traps.clear()
	dungeon.obj_layer.queue_redraw()

func _qfoe(p: Vector2i) -> Mon:
	var m := dungeon._spawn_wild(p)
	if m:
		m.visual.position = dungeon._px(p)
		m.status.sleep = 0x7F          # napping: stays put
	return m

const _QACT := {0: "move_down", 2: "move_right", 4: "move_up", 6: "move_left"}

## A straight corridor of n tiles (no junctions) from p in direction d: [p, d] or [].
func _qcorridor(n: int) -> Array:
	var fs := dungeon.fs
	var q = dungeon.qol
	for y in fs.h:
		for x in fs.w:
			var p := Vector2i(x, y)
			if fs.room_at(p) != 255 or not fs.walkable(p, fs.leader):
				continue
			for d in [0, 2, 4, 6]:
				var dv: Vector2i = DB.DIRS[d]
				var ok := true
				for k in range(1, n + 1):
					var t: Vector2i = p + dv * k
					if fs.room_at(t) != 255 or not fs.can_step(p + dv * (k - 1), d, fs.leader):
						ok = false
						break
					if k < n and q._next_dir(t, t - dv, d) != d:
						ok = false
						break
				if ok and fs.walkable(p - dv, fs.leader):
					return [p, d]
	return []

## Tiles of the biggest room whose 8 neighbours are all in that room (sorted top-left first).
func _qinner_room_tiles() -> Array:
	var fs := dungeon.fs
	var by := {}
	for y in fs.h:
		for x in fs.w:
			var p := Vector2i(x, y)
			var r := fs.room_at(p)
			if r == 255 or not fs.walkable(p, fs.leader):
				continue
			var ok := true
			for k in 8:
				var n: Vector2i = p + DB.DIRS[k]
				if fs.room_at(n) != r or not fs.walkable(n, fs.leader):
					ok = false
			if ok:
				if not by.has(r):
					by[r] = []
				by[r].append(p)
	var best: Array = []
	for r in by:
		if by[r].size() > best.size():
			best = by[r]
	return best

func _qsettle() -> void:
	for i in 60:
		await get_tree().process_frame
		if dungeon.cam.position.distance_to(dungeon.fs.leader.visual.position) < 0.5:
			break
	await get_tree().create_timer(0.1).timeout

## --movetest=<species>,<move>: a wild Pokémon next to the leader uses the move on it; logs HP and messages
func _usemove() -> void:
	var sp := "0307"
	var mvn := "Confusion"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--usemove="):
			var v := a.substr(10).split(",")
			sp = v[0]
			mvn = v[1]
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	var L: Mon = d.fs.leader
	for m in d.fs.mons.duplicate():
		if not m.is_team():
			d.cs_remove(m)
	var q := d.fs.free_tile_near(L.pos + Vector2i(1, 0), null, 2)
	var w := d._spawn_wild(q)
	w.moves = [{"name": mvn, "pp": 20, "max_pp": 20}]
	var dir := DB.dir_index(L.pos - w.pos)
	for i in 4:
		var hl := L.hp
		var hw := w.hp
		await d.do_attack(w, mvn, dir)
		print("MOVETEST %s used %s dir=%d: leader %d->%d  user %d->%d  user status=%s" % [w.name, mvn, dir, hl, L.hp, hw, w.hp, str(w.status)])
	print("MOVETEST log: ", d.hud.get("msgs") if d.hud else "")
	get_tree().quit()

## --throwtest: Autoplay throws Toolbox Iron Thorns / Gravelerocks at a foe 3 tiles away; a partner with
## Item Master throws its held Iron Thorn (Red's AIDecideUseItem)
func _throwtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	var line_spot := func(from: Mon) -> Vector2i:
		for k in 8:
			var ok := true
			for n in range(1, 4):
				var q: Vector2i = from.pos + DB.DIRS[k] * n
				if not d.fs.walkable(q) or d.fs.mon_at(q) != null:
					ok = false
			if ok:
				return from.pos + DB.DIRS[k] * 3
		return Vector2i(-1, -1)
	for item in ["ironthorn", "gravelerock"]:
		for m in d.fs.mons.duplicate():
			if not m.is_team():
				d.cs_remove(m)
		Game.bag.clear()
		Game.bag.append({"id": item, "n": 3})
		var L: Mon = d.fs.leader
		var p: Vector2i = line_spot.call(L)
		var w = d._spawn_wild(p)
		w.hp = 99
		w.max_hp = 99
		var h0: int = w.hp
		d.autoplay = true
		await d.autoplay_step()
		await get_tree().create_timer(1.5).timeout
		d.autoplay = false
		print("THROWTEST autoplay %s: foe hp %d -> %d, bag now %s" % [item, h0, w.hp, str(Game.bag)])
	for m in d.fs.mons.duplicate():
		if not m.is_team():
			d.cs_remove(m)
	var P: Mon = null
	for m in d.fs.team():
		if not m.is_leader:
			P = m
	P.iq_skills = ["Item Master"]
	P.held = "ironthorn"
	var w2 = d._spawn_wild(line_spot.call(P))
	w2.hp = 99
	w2.max_hp = 99
	var thrown := false
	for i in 6:
		var a := AI.decide(P, d.fs, d.mem.get(P.uid, {}))
		if a.get("type", "") == "throw":
			await d.execute(P, a)
			thrown = true
			break
	print("THROWTEST partner with Item Master: threw=%s held now '%s' foe hp %d" % [str(thrown), P.held, w2.hp])
	P.iq_skills = []
	P.held = "ironthorn"
	var a2 := AI.decide(P, d.fs, d.mem.get(P.uid, {}))
	print("THROWTEST partner without Item Master: action=%s" % a2.get("type", ""))
	get_tree().quit()

## --promptest: Team item prompts -- a low ally is offered the Oran Berry, a poisoned one the Pecha Berry,
## a fainting one the Reviver Seed (the test answers each question with its first choice)
func _promptest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	for m in d.fs.mons.duplicate():
		if not m.is_team():
			d.cs_remove(m)
	var P: Mon = null
	for m in d.fs.team():
		if not m.is_leader:
			P = m
	var answer := func():
		for i in 120:
			await get_tree().process_frame
			if not TeamScreens._stack.is_empty():
				var mm = TeamScreens._stack.back()
				print("PROMPTEST asked: ", d.hud.get("msgs") if false else "", mm.rows.map(func(r): return r.text if r is Dictionary else str(r)))
				await get_tree().create_timer(0.3).timeout
				mm.pick_current()
				return
	Game.bag.clear()
	Game.bag.append({"id": "oran", "n": 1})
	Game.bag.append({"id": "pecha", "n": 1})
	Game.bag.append({"id": "reviver", "n": 1})
	P.hp = 3
	answer.call()
	await d._team_item_prompts()
	print("PROMPTEST low: partner hp now %d/%d, bag %s" % [P.hp, P.max_hp, str(Game.bag.map(func(b): return b.id))])
	P.status.poison = 5
	answer.call()
	await d._team_item_prompts()
	print("PROMPTEST poison: status poison=%d, bag %s" % [int(P.status.get("poison", 0)), str(Game.bag.map(func(b): return b.id))])
	P.hp = 0
	answer.call()
	await d.faint(P, null)
	print("PROMPTEST faint: partner hp %d alive=%s, bag %s" % [P.hp, str(d.fs.mons.has(P)), str(Game.bag.map(func(b): return b.id))])
	get_viewport().get_texture().get_image().save_png("user://promptest.png")
	get_tree().quit()

## --itemtest: every Red Orb, seed, berry and food is used once (plus a few thrown) in a dungeon with foes
## around; prints what happened and catches script errors
func _itemtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	Dungeon.test_invincible = true
	Dialog.auto = true
	ListMenu.auto = true
	d.auto_answer = true
	var L: Mon = d.fs.leader
	var ids: Array = []
	for k in DB.items:
		var I: Dictionary = DB.items[k]
		if I.get("red", 0) and str(I.get("red_cat", "")) in ["orbs", "berries_seeds_vitamins", "food_gummies"]:
			ids.append(k)
	ids.erase("escapeorb")
	ids.append("escapeorb")
	var n_ok := 0
	for id in ids:
		if d.result_sent:
			print("ITEMTEST dungeon ended at ", id)
			break
		# fresh foes: one in front of the leader, one elsewhere in the room
		for m in d.fs.mons.duplicate():
			if not m.is_team():
				d.cs_remove(m)
		var front: Vector2i = L.pos + DB.DIRS[L.facing]
		if not d.fs.walkable(front):
			for k in 8:
				if d.fs.walkable(L.pos + DB.DIRS[k]) and d.fs.mon_at(L.pos + DB.DIRS[k]) == null:
					L.facing = k
					front = L.pos + DB.DIRS[k]
					break
		if d.fs.mon_at(front) == null:
			var w = d._spawn_wild(front)
			if w:
				w.held = "oran"
		var q := d.fs.free_tile_near(L.pos + Vector2i(3, 0), null, 3)
		if q.x >= 0:
			d._spawn_wild(q)
		d.hud.log_all.clear()
		var log0 := 0
		Game.bag.clear()
		Game.bag.append({"id": id, "n": 1})
		await d.use_item(L, 0)
		await get_tree().process_frame
		var lines: Array = d.hud.log_all.slice(log0) if d.hud and "log_all" in d.hud else []
		print("ITEMTEST %-14s %s" % [id, " | ".join(lines.map(func(x): return str(x).substr(0, 60)))])
		n_ok += 1
		L.status.clear()
		L.hp = L.max_hp
		if L.pos.x < 0:
			break
	# throws
	for id in ["sleepseed", "blastseed", "oran", "stunseed", "ironthorn"]:
		for m in d.fs.mons.duplicate():
			if not m.is_team():
				d.cs_remove(m)
		var w2 = null
		for k in 8:
			var ok := true
			for i in range(1, 3):
				if not d.fs.walkable(L.pos + DB.DIRS[k] * i) or d.fs.mon_at(L.pos + DB.DIRS[k] * i):
					ok = false
			if ok:
				L.facing = k
				w2 = d._spawn_wild(L.pos + DB.DIRS[k] * 2)
				break
		d.hud.log_all.clear()
		var log1 := 0
		Game.bag.clear()
		Game.bag.append({"id": id, "n": 1})
		await d.throw_item(L, 0)
		print("ITEMTEST threw %-10s %s" % [id, " | ".join(d.hud.log_all.slice(log1).map(func(x): return str(x).substr(0, 60)))])
	print("ITEMTEST done %d items" % n_ok)
	get_tree().quit()

## --heldtest: Red's held items outside the damage formula
func _heldtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	Dungeon.test_invincible = true
	Dialog.auto = true
	d.auto_answer = true
	var L: Mon = d.fs.leader
	var res := []
	L.held = "persimband"; d._apply_eff(L, L, {"status": "confused"}, true); res.append("persim blocks confusion: %s" % str(int(L.status.get("confused", 0)) == 0))
	L.held = "pechascarf"; d._apply_eff(L, L, {"status": "poison"}, true); res.append("pecha scarf blocks poison: %s" % str(int(L.status.get("poison", 0)) == 0))
	L.held = "insomniscope"; d._apply_eff(L, L, {"status": "sleep"}, true); res.append("insomniscope blocks sleep: %s" % str(int(L.status.get("sleep", 0)) == 0))
	L.held = "twistband"; d._apply_eff(L, L, {"tgt": "atk", "st": -1}, true); res.append("twist band keeps attack: %s" % str(int(L.stages.get("atk", 10)) == 10))
	L.held = "joyribbon"; var e0 := L.exp; d._hurt(L, 5, null, false); await d.end_of_turn(); res.append("joy ribbon exp +%d" % (L.exp - e0))
	L.held = "trapscarf"; d.fs.traps[L.pos] = {"id": "warp", "seen": false}; var p0 := L.pos; await d.trigger_trap(L, L.pos); res.append("trap scarf: stayed=%s" % str(L.pos == p0))
	d.fs.traps.erase(L.pos)
	L.held = "warpscarf"; var p1 := L.pos; var warped := false
	for i in 25:
		await d.end_of_turn()
		if L.pos != p1:
			warped = true
			break
	res.append("warp scarf warped within 25 turns: %s" % str(warped))
	L.held = "mobilescarf"; var wallp := Vector2i(-1, -1)
	for y in range(2, d.fs.h - 2):
		for x in range(2, d.fs.w - 2):
			if wallp.x < 0 and d.fs.is_wall(Vector2i(x, y)):
				wallp = Vector2i(x, y)
	res.append("mobile scarf can enter wall %s (leader %s, size %dx%d): %s" % [wallp, L.pos, d.fs.w, d.fs.h, str(wallp.x >= 0 and d.fs.walkable(wallp, L))])
	L.held = ""
	# throws: dodge scarf target never hit, pierce band hits two
	for m in d.fs.mons.duplicate():
		if not m.is_team():
			d.cs_remove(m)
	var dir := -1
	for k in 8:
		var ok := true
		for i in range(1, 4):
			if not d.fs.walkable(L.pos + DB.DIRS[k] * i) or d.fs.mon_at(L.pos + DB.DIRS[k] * i):
				ok = false
		if ok:
			dir = k
			break
	L.facing = dir
	var w1 = d._spawn_wild(L.pos + DB.DIRS[dir] * 1); w1.hp = 99; w1.max_hp = 99
	var w2 = d._spawn_wild(L.pos + DB.DIRS[dir] * 3); w2.hp = 99; w2.max_hp = 99
	w1.held = "dodgescarf"
	var dodged := 0
	for i in 5:
		Game.bag = [{"id": "ironthorn", "n": 1}]
		L.facing = dir
		await d.throw_item(L, 0)
		if w1.hp == 99:
			dodged += 1
	res.append("dodge scarf dodged %d/5" % dodged)
	w1.held = ""
	L.held = "pierceband"
	L.facing = dir
	Game.bag = [{"id": "ironthorn", "n": 1}]
	var h1: int = w1.hp
	var h2: int = w2.hp
	L.held = "pierceband"
	await d.throw_item(L, 0)
	res.append("pierce band hits: first %s second %s" % [str(w1.hp < h1), str(w2.hp < h2)])
	for r in res:
		print("HELDTEST ", r)
	get_tree().quit()

## --abtest: abilities in action (Red's, EoS's and Remixed's)
func _abtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	Dungeon.test_invincible = true
	Dialog.auto = true
	d.auto_answer = true
	var L: Mon = d.fs.leader
	var res: Array = []
	var fresh := func() -> Mon:
		for m in d.fs.mons.duplicate():
			if not m.is_team():
				d.cs_remove(m)
		var dir := -1
		for k in 8:
			if d.fs.walkable(L.pos + DB.DIRS[k]) and d.fs.mon_at(L.pos + DB.DIRS[k]) == null and d.fs.can_attack_dir(L.pos, k):
				dir = k
				break
		L.facing = dir
		var w = d._spawn_wild(L.pos + DB.DIRS[dir])
		w.hp = 200
		w.max_hp = 200
		w.facing = (dir + 4) % 8
		L.status.clear()
		w.status.clear()
		L.hp = L.max_hp
		return w
	var w: Mon
	# Static (12%): attack 40 times
	w = fresh.call(); w.ability = "static"; var paras := 0
	for i in 40:
		L.status.para = 0
		await d.do_attack(L, "", L.facing)
		if int(L.status.get("para", 0)) > 0:
			paras += 1
		w.hp = 200
	res.append("Static paralysed the attacker %d/40 times (Red: 12%%)" % paras)
	# Rough Skin
	w = fresh.call(); w.ability = "rough-skin"; var h0 := L.hp
	await d.do_attack(L, "", L.facing)
	res.append("Rough Skin: attacker HP %d -> %d" % [h0, L.hp])
	# Insomnia vs Sleep Seed thrown
	w = fresh.call(); w.ability = "insomnia"
	d._apply_eff(L, w, {"status": "sleep"}, true)
	res.append("Insomnia blocks sleep: %s" % str(int(w.status.get("sleep", 0)) == 0))
	# Sturdy vs One-Shot Orb
	w = fresh.call(); w.ability = "sturdy"
	Game.bag = [{"id": "oneshotorb", "n": 1}]
	for i in 6:
		Game.bag = [{"id": "oneshotorb", "n": 1}]
		await d.use_item(L, 0)
	res.append("Sturdy survives One-Shot: hp %d" % w.hp)
	# Pixilate turns Tackle into Fairy
	L.ability = "pixilate"
	var mt: Array = AbilityFx.move_type(L, "Tackle", "Normal")
	res.append("Pixilate Tackle -> %s x%.1f" % [mt[0], mt[1]])
	# Protean
	L.ability = "protean"
	w = fresh.call()
	L.moves[0].pp = 10
	await d.do_attack(L, L.moves[0].name, L.facing)
	res.append("Protean: leader types now %s after %s" % [str(L.types), L.moves[0].name])
	L.ability = "blaze"
	# Drizzle weather
	w = fresh.call(); w.ability = "drizzle"
	AbilityFx.update_weather(d)
	res.append("Drizzle weather: %s" % d.fs.weather)
	w.ability = "cloud-nine"
	AbilityFx.update_weather(d)
	res.append("Cloud Nine weather: %s" % d.fs.weather)
	# Clear Body
	w = fresh.call(); w.ability = "clear-body"
	d._apply_eff(L, w, {"tgt": "atk", "st": -1}, true)
	res.append("Clear Body keeps Attack: %s" % str(int(w.stages.get("atk", 10)) == 10))
	# Defiant
	w = fresh.call(); w.ability = "defiant"
	d._apply_eff(L, w, {"tgt": "def", "st": -1}, true)
	res.append("Defiant raised Attack to stage %d" % int(w.stages.get("atk", 10)))
	# Technician damage factor
	L.ability = "technician"
	w = fresh.call()
	var dm := AbilityFx.modify_damage(d, L, w, {"p": 4}, "Quick Attack", "Normal", 10, {"physical": true}, 1.0)
	res.append("Technician 10 dmg -> %d" % dm)
	L.ability = "blaze"
	for r in res:
		print("ABTEST ", r)
	get_tree().quit()

## --shinytest: shiny wild Pokémon / team members
func _shinytest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	Game.team[1].shiny = true
	start_dungeon("eos_beach_cave", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	Dialog.auto = true
	d.auto_answer = true
	var L: Mon = d.fs.leader
	print("SHINYTEST partner shiny: ", Shiny.is_shiny(d.fs.team()[1]), " material: ", d.fs.team()[1].visual.material != null)
	var p := L.pos
	for dv in DB.DIRS:
		var q: Vector2i = L.pos + Vector2i(dv) * 2
		if d.fs.walkable(q) and d.fs.mon_at(q) == null:
			p = q
			break
	var w := DB.make_mon("0025", 5, "enemy")
	w.set_meta("shiny", true)
	w.pos = p
	d.fs.mons.append(w)
	d._add_sprite(w)
	d._shiny_check()
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("user://shiny_1.png")
	var n := 0
	var rng := RandomNumberGenerator.new()
	for i in 20000:
		if Shiny.roll(rng):
			n += 1
	print("SHINYTEST rolls: ", n, " / 20000")
	var t0 = Dialog.portrait_tex("0007")
	var img0: Image = t0.atlas.get_image()
	var c0 := img0.get_pixel(int(t0.region.position.x) + 20, int(t0.region.position.y) + 20)
	print("SHINYTEST por atlas ", t0 is AtlasTexture, " ", t0.region, " fmt ", img0.get_format(), " px ", c0.r8, ",", c0.g8, ",", c0.b8, " rows ", Shiny.data().get("0007", {}).get("p", []).slice(0, 2))
	var t := Dialog.portrait_tex("0007*")
	print("SHINYTEST shiny por class ", t.get_class())
	t.get_image().save_png("user://shiny_por.png")
	Dialog.portrait_tex("0007").get_image().save_png("user://normal_por.png")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()

## --megatest: Empowerment Seed / Awakened / Mega Evolution
func _megatest() -> void:
	Game.new_game("0006", "Charizard", "0115", "Kangaskhan", "Q")
	Game.team[0].level = 40
	Game.team[1].level = 40
	start_dungeon("eos_beach_cave", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	Dialog.auto = true
	d.auto_answer = true
	var L: Mon = d.fs.leader
	var P: Mon = d.fs.team()[1]
	print("MEGATEST before: ", L.sp, " ", L.types, " ", L.ability, " atk ", L.atk, " def ", L.def, " hp ", L.hp, "/", L.max_hp)
	Game.bag = [{"id": "empowerseed", "n": 1}, {"id": "empowerseed", "n": 1}]
	await d.use_item(L, 0)
	await get_tree().create_timer(1.0).timeout
	print("MEGATEST after: ", L.sp, " ", L.name, " ", L.types, " ", L.ability, " atk ", L.atk, " def ", L.def, " hp ", L.hp, "/", L.max_hp, " awake ", Awaken.is_awake(L))
	get_viewport().get_texture().get_image().save_png("user://mega_1.png")
	var foe := DB.make_mon("0074", 20, "enemy")      # Geodude: Rock/Ground resists Fire
	var r1 := Combat.calc_damage(L, foe, DB.move_data("Ember"), d.fs.rng, {"move_type": "Fire"})
	print("MEGATEST Ember vs Geodude eff (2 = no disadvantage): ", r1.eff)
	L.set_meta("linked_hit", true)
	var crits := 0
	for i in 20:
		if Combat.calc_damage(L, foe, DB.move_data("Scratch"), d.fs.rng, {}).crit:
			crits += 1
	L.remove_meta("linked_hit")
	print("MEGATEST linked crits: ", crits, "/20")
	await d.use_item(P, 0)
	print("MEGATEST partner: ", P.name, " ", P.sp, " ", P.ability)
	print("MEGATEST parental bond: ", AbilityFx.has(P, "parental bond"))
	var k := DB.make_mon("0382", 50, "enemy")
	d.fs.mons.append(k)
	await Awaken.awaken(d, k)
	print("MEGATEST kyogre: ", k.sp, " ", k.ability, " weather ", d.fs.weather, " fire blocked: ", Awaken.primal_block(d, "Fire"))
	d.fs.mons.erase(k)
	get_viewport().get_texture().get_image().save_png("user://mega_2.png")
	await d.next_floor()
	await get_tree().create_timer(1.5).timeout
	print("MEGATEST next floor: ", L.sp, " ", L.types, " ", L.ability, " atk ", L.atk, " awake ", Awaken.is_awake(L), " entry sp ", Game.team[0].sp, " partner ", P.sp)
	get_tree().quit()

## --boxtest: treasure boxes opened at the Kecleon shop
func _boxtest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var tiers := {}
	var mine := 0
	var rare := 0
	for i in 2000:
		var x := EosItems.open_box(rng)
		var I: Dictionary = DB.items.get(x, {})
		if I.get("excl") == null:
			rare += 1
			continue
		tiers[int(I.get("rarity", 0))] = int(tiers.get(int(I.get("rarity", 0)), 0)) + 1
		var x2 = I.excl
		if "0004" in x2.get("for", []) or "0007" in x2.get("for", []) or "Fire" in x2.get("types", []) or "Water" in x2.get("types", []):
			mine += 1
	print("BOXTEST tiers ", tiers, " rare ", rare, " for my team ", mine)
	print("BOXTEST boxes in drop pool: ", EosItems._drop_pool().filter(func(e): return EosItems.is_box(str(e[0]))).map(func(e): return "%s lv%d" % [e[0], e[2]]))
	Game.bag = [{"id": "oranberry", "n": 1}, {"id": "lightbox", "n": 1}, {"id": "deluxebox", "n": 1}]
	Game.money = 500
	var keys := func(seq: Array) -> void:
		var i := 0
		for k in seq:
			await get_tree().create_timer(0.9).timeout
			get_viewport().get_texture().get_image().save_png("user://box_%02d.png" % i)
			i += 1
			for pr in [true, false]:
				var ev := InputEventAction.new()
				ev.action = k
				ev.pressed = pr
				Input.parse_input_event(ev)
				await get_tree().process_frame
	keys.call(["ui_down", "ui_down", "ui_down", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_accept", "ui_cancel", "ui_cancel", "ui_cancel", "ui_accept", "ui_accept"])
	await RedShops.kecleon(root, false)
	print("BOXTEST bag after: ", Game.bag.map(func(b): return DB.item_name(str(b.id))), " money ", Game.money)
	get_tree().quit()

## --eostest: Explorers of Sky / Remixed items (exclusives in the bag, held effects) and a Remixed dungeon floor
func _eostest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	start_dungeon("eos_beach_cave", 0)
	await get_tree().create_timer(3.0).timeout
	var d := dungeon
	Dialog.auto = true
	d.auto_answer = true
	var L: Mon = d.fs.leader
	print("EOSTEST beach cave spawns: ", d.ddata.floors[0].pk.map(func(e): return DB.species.get(str(e[0]), {}).get("name", e[0])))
	print("EOSTEST wild now: ", d.fs.mons.filter(func(m): return not m.is_team()).map(func(m): return m.name))
	Game.bag = [{"id": "charclaw", "n": 1}, {"id": "heatarmlet", "n": 1}]
	print("EOSTEST Char-Claw atk bonus for leader: ", EosItems.stat(L, "atk"), "  partner: ", EosItems.stat(d.fs.team()[1], "atk"))
	var hp0 := L.max_hp
	EosItems.floor_start(d, L)
	print("EOSTEST Heat Armlet max HP %d -> %d" % [hp0, L.max_hp])
	L.held = "flameorb"
	EosItems.end_of_turn(d)
	print("EOSTEST Flame Orb burned holder: ", int(L.status.get("burn", 0)) > 0)
	L.held = ""
	L.status.burn = 0
	Game.bag = [{"id": "allmachorb", "n": 1}]
	await d.use_item(L, 0)
	print("EOSTEST All-Mach Orb: leader fast=", int(L.status.get("fast", 0)))
	Game.bag = [{"id": "goldenseed", "n": 1}]
	var lv := L.level
	await d.use_item(L, 0)
	print("EOSTEST Golden Seed: level %d -> %d" % [lv, L.level])
	var got := {}
	for i in 3000:
		var x := d._pick_item(int(d.ddata.floors[0].items))
		if DB.items.get(x, {}).get("eos_added", 0):
			got[x] = int(got.get(x, 0)) + 1
	print("EOSTEST 3000 item rolls on Beach Cave 1F gave %d EoS/Remixed items: %s" % [got.values().reduce(func(a, b): return a + b, 0), str(got.keys().map(func(k): return DB.items[k].name).slice(0, 12))])
	get_tree().quit()

## --jobfloor: a taken rescue job on Tiny Woods 1F: the arrival line shows (+ screenshot)
func _jobfloor() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	Game.jobs.append({"id": "t1", "state": "taken", "dungeon": "tiny_woods", "floor": 1, "kind": "rescue", "client": "0025", "target": "0025", "item": ""})
	start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png("user://jobfloor.png")
	get_tree().quit()

## --bosspos: where the team and the boss stand when each story boss floor starts (+ screenshot)
func _bosspos() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--boss="):
			only = a.substr(7)
	for key in ["mt_steel", "sinister_woods", "mt_thunder_peak", "great_canyon", "mt_blaze_peak", "frosty_grotto", "mt_freeze_peak", "magma_cavern_pit", "sky_tower_summit"]:
		if only != "" and key != only:
			continue
		var n: int = DB.dungeons.dungeons[key].floors.size()
		start_dungeon(key, n - 1)
		await get_tree().create_timer(3.0).timeout
		var d := dungeon
		var out := []
		for m in d.fs.mons:
			out.append("%s%s@%s" % [m.name, "(boss)" if m.get_meta("boss", false) or str(m.get_meta("behavior", "")) != "" else "", m.pos])
		print("BOSSPOS %s floor %d spawn=%s fixed=%d : %s" % [key, n, d.fs.leader.pos if d.fs.leader else Vector2i(-1, -1), d.fixed_no, ", ".join(out)])
		get_viewport().get_texture().get_image().save_png("user://bosspos_%s.png" % key)
		d.queue_free()
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()

## --perftest=<dungeon>: Autoplay on a busy floor, reporting how long the game logic takes per frame
func _perftest() -> void:
	var key := "magma_cavern"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perftest="):
			key = a.substr(11)
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	for e in Game.team:
		e.level = 40
		e.exp = DB.exp_at(str(e.sp), 40)
	Dungeon.perf_log = true
	print("PERFTEST start ", key)
	start_dungeon(key, 5)
	await get_tree().create_timer(4.0).timeout
	print("PERFTEST in dungeon floor ", dungeon.floor_i if dungeon else -1)
	dungeon.auto_answer = true
	dungeon.set_autoplay(true)
	var f0: int = dungeon.floor_i
	for k in 12:
		await get_tree().create_timer(10.0).timeout
		if not is_instance_valid(dungeon):
			break
		print("PERFTEST t=%ds floor %d->%d autoplay=%s turn=%d" % [(k + 1) * 10, f0 + 1, dungeon.floor_i + 1, dungeon.autoplay, dungeon.fs.turn])
	get_tree().quit()

## --walktest: hold a direction down a corridor and log the leader's per-frame motion (stalls = clunky walking)
func _walktest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	for k in DungeonQoL.DEFAULTS:
		Game.settings[k] = DungeonQoL.DEFAULTS[k]
	await start_dungeon("tiny_woods")
	await get_tree().create_timer(2.0).timeout
	var d := dungeon
	var cor: Array = []
	for tries in 8:
		_qclear()
		cor = _qcorridor(7)
		if not cor.is_empty():
			break
		d.busy = true
		await d.build_floor()
		await get_tree().create_timer(0.3).timeout
	if cor.is_empty():
		print("WALKTEST no corridor"); get_tree().quit(); return
	var L: Mon = d.fs.leader
	_qplace(L, cor[0])
	L.visual.position = d._px(L.pos)
	await get_tree().create_timer(0.3).timeout
	var act: String = {0: "move_down", 2: "move_right", 4: "move_up", 6: "move_left"}.get(int(cor[1]), "move_right")
	for run in [false, true]:
		if run:
			Input.action_press("act_run")
		Input.action_press(act)
		var last: Vector2 = L.visual.position
		var stalls := 0
		var frames := 0
		var p_start := L.pos
		var t0 := Time.get_ticks_msec()
		while frames < 60 and L.pos.distance_to(Vector2(p_start)) < 6:
			await get_tree().process_frame
			var mv: float = L.visual.position.distance_to(last)
			last = L.visual.position
			frames += 1
			if mv < 0.01 and frames > 2:
				stalls += 1
		Input.action_release(act)
		Input.action_release("act_run")
		print("WALKTEST run=%s tiles=%d frames=%d ms=%d stall_frames=%d" % [run, int(L.pos.distance_to(Vector2(p_start))), frames, Time.get_ticks_msec() - t0, stalls])
		await get_tree().create_timer(0.5).timeout
		_qplace(L, cor[0]); L.visual.position = d._px(L.pos)
		await get_tree().create_timer(0.3).timeout
	# partner pickup (MonTryPickUpItem)
	var P: Mon = d.fs.team()[1]
	var dir: int = int(cor[1])
	_qplace(P, cor[0] + DB.DIRS[dir] * 2)
	var spot: Vector2i = P.pos + DB.DIRS[dir]
	d.fs.items[spot] = {"id": "oranberry", "n": 1}
	var bag0 := Game.bag.size()
	await d.do_move(P, dir)
	print("WALKTEST pickup partner_at=%s item_left=%s bag %d->%d" % [P.pos, d.fs.items.has(spot), bag0, Game.bag.size()])
	get_tree().quit()

func _qoltest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	Game.settings.zoom = 1.25
	for k in DungeonQoL.DEFAULTS:
		Game.settings[k] = DungeonQoL.DEFAULTS[k]
	await start_dungeon("tiny_woods")
	await get_tree().create_timer(2.0).timeout
	var d := dungeon
	var q = d.qol
	var L: Mon = d.fs.leader
	var P: Mon = d.fs.team()[1]
	# ---- find a floor with a long straight corridor
	var cor: Array = []
	for tries in 8:
		_qclear()
		cor = _qcorridor(7)
		if not cor.is_empty():
			break
		d.busy = true
		await d.build_floor()
		await get_tree().create_timer(0.3).timeout
	_qcheck("found corridor", not cor.is_empty(), str(cor))
	var fs := d.fs
	L = fs.leader
	P = fs.team()[1]
	if not cor.is_empty():
		var p0: Vector2i = cor[0]
		var dir: int = cor[1]
		var dv: Vector2i = DB.DIRS[dir]
		# ---- run mode: hold Run, tap a direction, the leader keeps going
		_qplace(P, p0 - dv)
		_qplace(L, p0)
		await get_tree().create_timer(0.6).timeout
		_qact("act_run", true)
		_qact(_QACT[dir], true)
		await get_tree().create_timer(0.12).timeout
		_qact(_QACT[dir], false)
		await _qwait_idle()
		_qact("act_run", false)
		_qcheck("run mode walks on its own", q.steps >= 3 and L.pos != p0, "steps=%d stop=%s from %s to %s" % [q.steps, q.last_stop, p0, L.pos])
		await _qshot("run")
		# ---- run mode stops the moment a new foe comes into view
		_qplace(L, p0)
		_qplace(P, p0 - dv)
		var foe := _qfoe(p0 + dv * 6)
		await get_tree().create_timer(0.5).timeout
		_qact("act_run", true)
		_qact(_QACT[dir], true)
		await get_tree().create_timer(0.12).timeout
		_qact(_QACT[dir], false)
		await _qwait_idle()
		_qact("act_run", false)
		var dist := FloorState.cheb(L.pos, foe.pos) if foe else -1
		_qcheck("run stops on a new foe", q.last_stop == "foe" and dist >= 2, "stop=%s steps=%d dist=%d" % [q.last_stop, q.steps, dist])
		await _qshot("run_foe")
	# ---- tap-to-walk inside a room
	_qclear()
	d.spawn_timer = -100000                  # no new wild Pokémon during the rest of the test
	var inner := _qinner_room_tiles()
	var a: Vector2i = inner[0]
	var b: Vector2i = inner[0]
	for t in inner:
		if FloorState.cheb(t, a) > FloorState.cheb(b, a) and FloorState.cheb(t, a) <= 7:
			b = t
	var pt: Vector2i = fs.free_tile_near(a + Vector2i(0, 1), P, 3)
	_qplace(P, pt if pt != b and pt.x >= 0 else a + Vector2i(0, 1))
	_qplace(L, a)
	await _qsettle()
	var sp: Vector2 = q.tile_to_screen(b)
	_qcheck("tile->screen->tile", q.screen_to_tile(sp) == b, "%s -> %s -> %s" % [b, sp, q.screen_to_tile(sp)])
	_qtouch(sp, true)
	await get_tree().create_timer(0.08).timeout
	_qtouch(sp, false)
	await get_tree().create_timer(0.2).timeout
	await _qwait_idle()
	_qcheck("tap-to-walk reaches the tile", L.pos == b, "at %s goal %s stop=%s steps=%d" % [L.pos, b, q.last_stop, q.steps])
	await _qshot("tap_walk")
	# ---- tap an adjacent foe: attack it
	var fdir := 6
	for k in [6, 2, 0, 4]:
		if fs.walkable(L.pos + DB.DIRS[k], L) and fs.mon_at(L.pos + DB.DIRS[k]) == null:
			fdir = k
			break
	var fp: Vector2i = L.pos + DB.DIRS[fdir]
	var foe2 := _qfoe(fp)
	await _qsettle()
	var t0 := fs.turn
	sp = q.tile_to_screen(fp)
	_qtouch(sp, true)
	await get_tree().create_timer(0.08).timeout
	_qtouch(sp, false)
	await get_tree().create_timer(1.2).timeout
	await _qwait_idle()
	_qcheck("tap adjacent foe attacks", fs.turn > t0 and L.facing == fdir, "turn %d->%d facing=%d" % [t0, fs.turn, L.facing])
	if foe2 == null or foe2.hp <= 0 or not fs.mons.has(foe2):
		foe2 = _qfoe(fp)
	foe2.hp = foe2.max_hp
	foe2.status.poison = 5
	L.facing = fdir
	# ---- long-press a Pokémon: info window
	await get_tree().create_timer(0.3).timeout
	sp = q.tile_to_screen(fp)
	_qtouch(sp, true)
	await get_tree().create_timer(0.75).timeout
	_qcheck("long-press shows info", q.info_visible(), q.info_text(foe2).replace("\n", " | "))
	await _qshot("info")
	_qtouch(sp, false)
	await get_tree().create_timer(0.3).timeout
	_qcheck("long-press release doesn't walk", not q.is_moving() and L.pos == b)
	# a key press closes it; mouse hover opens it again (PC)
	_qact("ui_cancel", true); _qact("ui_cancel", false)
	await get_tree().create_timer(0.2).timeout
	var mm := InputEventMouseMotion.new()
	mm.position = _qwin(sp)
	mm.device = 0
	Input.parse_input_event(mm)
	await get_tree().create_timer(0.6).timeout
	_qcheck("hover shows info", q.info_visible())
	var mm2 := InputEventMouseMotion.new()
	mm2.position = _qwin(q.tile_to_screen(L.pos + Vector2i(2, 2)))
	mm2.device = 0
	Input.parse_input_event(mm2)
	await get_tree().create_timer(0.3).timeout
	_qcheck("moving off hides info", not q.info_visible())
	# ---- damage preview in the Moves window
	var mv0: Dictionary = DB.moves.get(str(L.moves[0].name), {})
	var pv: String = d.move_preview(L, str(L.moves[0].name))
	_qcheck("damage preview text", pv.contains("Dmg") or pv.contains("Status"), pv.replace("\n", " | "))
	if int(mv0.get("p", 0)) > 0:
		var rr := DungeonQoL.damage_range(L, foe2, mv0, {"weather": fs.weather, "att_is_team": true})
		var rng := RandomNumberGenerator.new()
		var outside := 0
		for i in 300:
			var res := Combat.calc_damage(L, foe2, mv0, rng, {"weather": fs.weather, "att_is_team": true, "skip_accuracy2": true})
			if not res.crit and (int(res.dmg) < int(rr.min) or int(res.dmg) > int(rr.max)):
				outside += 1
		_qcheck("damage range covers real rolls", outside <= 6, "range %d-%d, %d/300 outside" % [rr.min, rr.max, outside])
	ListMenu.auto = false
	d.open_moves()
	await get_tree().create_timer(0.5).timeout
	await _qshot("preview")
	await _mt_press("ui_down")
	await _qshot("preview2")
	await _mt_close()
	await get_tree().create_timer(0.3).timeout
	# ---- full map and corner minimap
	fs.items[b + Vector2i(-2, 0)] = {"id": "apple", "n": 1, "price": 0}
	fs.traps[b + Vector2i(-3, -1)] = {"id": "poison", "seen": true}
	d.obj_layer.queue_redraw()
	d._toggle_map()
	await _qshot("map")
	d._toggle_map()
	Game.settings.qol_minimap = true
	d._update_hud()
	await get_tree().create_timer(0.3).timeout
	_qcheck("corner minimap shown", q._mini != null and q._mini.visible)
	await _qshot("minimap")
	# ---- low-HP warning
	var f0: int = q.low_flashes
	L.hp = maxi(1, L.max_hp / 5)
	d._update_hud()
	await get_tree().create_timer(0.16).timeout
	get_viewport().get_texture().get_image().save_png("user://qol_lowhp.png")
	_qcheck("low-HP warning fires", q.low_flashes == f0 + 1 and d.hud.low_hp)
	d._update_hud()
	_qcheck("low-HP warning only once per drop", q.low_flashes == f0 + 1)
	L.hp = L.max_hp
	d._update_hud()
	_qcheck("HP bar stops blinking", not d.hud.low_hp)
	# ---- auto-pickup filter
	Game.settings.qol_minimap = false
	for m in fs.mons.duplicate():
		if not m.is_team():
			m.visual.queue_free(); m.visual = null; fs.mons.erase(m)
	fs.items.clear()
	fs.traps.clear()
	var A: Vector2i = inner[0]
	var B := A + Vector2i(1, 0)
	_qplace(P, b)
	_qplace(L, A)
	var cases := [[3, "apple", false], [1, "stick", false], [1, "apple", true], [2, "oran", true], [2, "stick", false], [0, "stick", true]]
	var allok := true
	var detail: Array = []
	for c in cases:
		Game.settings.qol_pickup = int(c[0])
		fs.items.clear()
		fs.items[B] = {"id": str(c[1]), "n": 1, "price": 0}
		var n0 := Game.bag.size()
		await d.leader_action({"type": "move", "dir": 2})
		var got := not fs.items.has(B)
		detail.append("%s/%s:%s" % [DungeonQoL.PICKUP_NAMES[int(c[0])], c[1], "took" if got else "left"])
		if got != bool(c[2]) or (got and Game.bag.size() == n0 and str(c[1]) != "stick"):
			allok = false
		await d.leader_action({"type": "move", "dir": 6})
	_qcheck("auto-pickup filter", allok, ", ".join(detail))
	Game.settings.qol_pickup = 0
	# ---- the options page
	d.menu_open = true
	d._option_page("Others", ["touch"] + DungeonQoL.KEYS)
	await get_tree().create_timer(0.4).timeout
	for i in 6:
		await _mt_press("ui_down")
	await _mt_press("ui_right")
	await _qshot("options")
	await _mt_close()
	await _mt_close()
	d.menu_open = false
	_qcheck("options unchanged after cancel", int(Game.settings.qol_pickup) == 0)
	print("QOLTEST done")
	get_tree().quit()

# ------------------------------------------------------------------ story test
var _ap_counts := {}
var _st_sig := ""
var _st_same := 0

func _storytest() -> void:
	Dialog.auto = true
	ListMenu.auto = true
	Quiz.auto = true
	Ground.turbo = 6
	GAction.trace = OS.get_cmdline_user_args().has("--trace")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--spam="):
			GText.spam = int(a.substr(7))
	Game.settings.hunger = false
	Dungeon.test_invincible = not OS.get_cmdline_user_args().has("--force=defeated")
	get_tree().process_frame.connect(func():
		if is_instance_valid(dungeon) and dungeon.fs and dungeon.fs.leader:
			for m in dungeon.fs.team():
				if m.hp * 3 < m.max_hp * 2:
					m.hp = m.max_hp)
	var secs := 60
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = int(a.substr(7))
	var force := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--force="):
			force = a.substr(8)          # cleared / defeated: end every dungeon at once
	if force != "":
		get_tree().process_frame.connect(func():
			if is_instance_valid(dungeon) and not dungeon.has_meta("forced"):
				dungeon.set_meta("forced", true)
				(func(): await get_tree().create_timer(1.0).timeout; if is_instance_valid(dungeon): dungeon.finished.emit(force)).call())
	if OS.get_cmdline_user_args().has("--continue"):
		GData.load_all()
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--scen="):
				var v := a.substr(7).split(",")
				GVars.scenario_calc(GVars.SCENARIO_MAIN, int(v[0]), int(v[1]))
		continue_story()
	else:
		new_game()
	var t := 0
	while t < secs:
		await get_tree().create_timer(1.0).timeout
		t += 1
		if is_instance_valid(ground):
			ground.text.auto = true
			# post-game side stories (test only): give what a player would collect on their own so each story can start
			if Game.story.has("vars") and GVars.after(GVars.SCENARIO_MAIN, 17, -1):
				_test_postgame_grants()
			# post-game tutorial (19,1): the story waits for the player to pick a new leader (Make Leader)
			if Game.story.has("vars") and GVars.scenario(GVars.SCENARIO_MAIN) == Vector2i(19, 1) and Game.team.size() > 1 \
					and ground.is_processing() and not ground.any_locked and not has_meta("made_leader"):
				set_meta("made_leader", true)
				TeamScreens.make_leader(Game.team[1])
				print("  TEST Make Leader -> ", Game.team[0].get("sp", "?") if Game.team[0] is Dictionary else Game.team[0])
				ground.map_execute_event(GData.fn_id("FORMATION_HERO"), false)
			# story items: the Mankey gang wants a peeled Chestnut (Uproar Forest B9F) before they rebuild the base
			var want := ""
			if Game.story.has("vars") and GVars.scenario(GVars.SCENARIO_SUB1).x == 30 and not Game.bag.any(func(b): return str(b.get("id", "")) == "chestnut"):
				want = "chestnut"
			Dungeon.test_want = want
			if want != "" and Game.bag.size() >= Game.BAG_MAX - 1:
				Game.bag.pop_back()
			# like a player would: keep a couple of board jobs taken (the story counts finished jobs)
			if GVars.quest(GVars.QUEST_CAN_ACCESS_JOBS) and Game.jobs.filter(func(j): return j.state == "taken").size() < 2:
				Missions.refresh_board_if_new_day()
				for j in Game.board.duplicate():
					if j.dungeon in Game.unlocked and j.kind in ["rescue", "target", "deliver"] and not j.has("story") and not Missions.in_job_list(j) and Story._job_doable(j):
						if Missions.accept(j):
							for k in Game.jobs:
								if str(k.id) == str(j.id):
									Missions.take(k)
							print("  TEST took job in ", j.dungeon)
							break
			for a in OS.get_cmdline_user_args():
				var tv := a.substr(9).split(",") if a.begins_with("--talkat=") else PackedStringArray()
				if tv.size() == 4 and ground.vis_map == int(tv[0]) and not has_meta("talked") and ground.autopilot != null:
					set_meta("talked", true)
					var v := tv.slice(1)
					var L0 = ground.lives[0]
					L0.move_real(Vector2i(int(v[0]) << 11, int(v[1]) << 11) + L0.half)
					print("  TEST teleported to ", L0.p144 / 2048, " box ", L0.p14C / 2048)
					ground.autopilot._talk_face = int(v[2])
					ground.autopilot._talk_seq = 5
			if ground.autopilot == null:
				ground.autopilot = GAutopilot.new(ground)
				ground.autopilot.counts = _ap_counts
			var sc := GVars.scenario(GVars.SCENARIO_MAIN)
			var s1 := GVars.scenario(GVars.SCENARIO_SUB1)
			var sig := "%d/%d/%d/%d.%d.%d" % [ground.vis_map, sc.x, sc.y, s1.x, s1.y, int(Game.bag.any(func(b): return str(b.get("id", "")) == "chestnut"))]
			if sig == _st_sig:
				_st_same += 1
			else:
				_st_same = 0
				if sig.get_slice("/", 1) + sig.get_slice("/", 2) + sig.get_slice("/", 3) != _st_sig.get_slice("/", 1) + _st_sig.get_slice("/", 2) + _st_sig.get_slice("/", 3):
					_ap_counts.clear()      # new story step: everything is worth trying again
				_st_sig = sig
			if _st_same == 25 or (_st_same > 0 and _st_same % 120 == 0) or ("--dumpat=%d" % t) in OS.get_cmdline_user_args():
				ground.dump_actions()
			print("STORY t=%d map=%d(%s) scen=%d,%d req=%d f=%d p=%s lives=%d" % [t, ground.vis_map, ground.map_file, sc.x, sc.y, ground.req, ground._frame, ground.is_processing(),
				ground.lives.filter(func(L): return L.kind_id != -1).size()])
			if OS.get_cmdline_user_args().has("--lives"):
				for L in ground.lives:
					if L.kind_id != -1:
						print("    L%d kind=%d g%d s%d pos=%s flags=%x ctrl=%s" % [L.id, L.kind_id, L.group, L.sector, L.p144 / 2048, L.flags, L.ctrl])
		elif is_instance_valid(dungeon):
			if not dungeon.autoplay:
				dungeon.set_autoplay(true)
			dungeon.auto_answer = true
			if dungeon.fs and dungeon.fs.leader:
				for m in dungeon.fs.team():
					if m.hp * 2 < m.max_hp:
						m.hp = m.max_hp
			print("DUNGEON t=%d %s floor=%d" % [t, dungeon.dkey, dungeon.floor_i])
		if t % 5 == 0:
			if true:
				var img := get_viewport().get_texture().get_image()
				img.save_png("user://story_%03d.png" % t)
	get_tree().quit()
