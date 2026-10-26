extends Node
## --wmaptest : world map trips (Red + Explorers of Sky) and the Friend Areas map (scripts/ui/world_map.gd).
## Screenshots go to user://wmap_*.png. Run with your own XDG_DATA_HOME.

var main

func _ready() -> void:
	main = get_parent()
	_run.call_deferred()

func shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://wmap_%s.png" % name)
	print("WMAP shot ", name)

func wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func press(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := InputEventAction.new()
	r.action = action
	r.pressed = false
	Input.parse_input_event(r)

var _done := false
var _res = null

func _trip(kind: String, key: String) -> void:
	_done = false
	if kind == "red":
		_res = await WorldMap.trip_red(main.root, key)
	elif kind == "eos":
		_res = await WorldMap.trip_eos(main.root, key)
	else:
		_res = await WorldMap.friend_areas(main.root, key)
	_done = true

func _wm() -> WorldMap:
	for c in main.root.get_children():
		if c is WorldMap:
			return c
	return null

## waits (max limit s) until the trip's dungeon / area name window is up
func _wait_name(limit := 12.0) -> void:
	var t := 0.0
	while t < limit and not _done:
		var w := _wm()
		if w and is_instance_valid(w.name_box):
			return
		await get_tree().process_frame
		t += get_process_delta_time()

func _wait_done(limit := 20.0) -> void:
	var t := 0.0
	while not _done and t < limit:
		await wait(0.1)
		t += 0.1

func _run() -> void:
	Game.new_game("0025", "Pika", "0004", "Char", "Testers")
	GData.load_all()
	GVars.reset_all()
	WorldMap.force_visible = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm", "mt_thunder", "great_canyon", "sky_tower"]
	var fail := 0
	print("WMAP prepare option ", GameOptions.ROWS.has("prepare_screen"), " value=", GameOptions.value("prepare_screen"), " want=", WorldMap.want_prepare())
	# 0) Game Options > Others: the remake's "Prepare screen" row
	GameOptions.page.call(main.root, "Others")
	await wait(0.5); await shot("options_others")
	await press("ui_cancel")
	await wait(0.5)
	# 1) Red: Tiny Woods (no rules -> straight in)
	_trip.call("red", "tiny_woods")
	await wait(0.6); await shot("red_tiny_start")
	await _wait_name(); await shot("red_tiny_name")
	await _wait_done()
	print("WMAP red tiny_woods -> ", _res)
	if _res != true: fail += 1
	# 2) Red: Sky Tower, far away: mid-walk + name
	_trip.call("red", "sky_tower")
	await wait(1.6); await shot("red_sky_walk")
	await _wait_name(); await shot("red_sky_name")
	await _wait_done()
	print("WMAP red sky_tower -> ", _res)
	# 3) Red: Joyous Tower with money -> rules prompt (Yes / No)
	Game.money = 120
	_trip.call("red", "joyous_tower")
	var t := 0.0
	while t < 12.0 and not _done:
		await wait(0.2); t += 0.2
		if main.root.find_children("*", "ListMenu", true, false).size() > 0:
			break
	await shot("red_purity_prompt")
	await press("ui_up")
	await wait(0.1)
	await press("ui_accept")
	await _wait_done()
	print("WMAP red joyous_tower (Yes) -> ", _res)
	if _res != true: fail += 1
	# 4) Red: too many members -> refusal text
	Game.money = 0
	var extra := Game._entry("0001", "Bulba", 5)
	Game.team.append(extra)
	Game.team.append(Game._entry("0007", "Squirt", 5))
	_trip.call("red", "tiny_woods")
	await wait(2.8); await shot("red_fail_text")
	for i in 6:
		await press("ui_accept"); await wait(0.2)
	await _wait_done()
	print("WMAP red tiny_woods with 4 -> ", _res)
	if _res != false: fail += 1
	Game.team.resize(2)
	# 5) EoS dungeons
	for k in ["eos_beach_cave", "eos_temporal_tower", "eos_dark_hill", "eos_spring_cave", "eos_side_path"]:
		if not DB.dungeons.dungeons.has(k):
			print("WMAP missing ", k)
			continue
		_trip.call("eos", k)
		await wait(1.2); await shot("eos_%s_walk" % k.substr(4))
		await _wait_name(); await shot("eos_%s_name" % k.substr(4))
		await _wait_done()
		print("WMAP eos ", k, " -> ", _res)
	# 6) Friend Areas map
	Game.friend_areas = ["beauplains", "mistrise", "bountifulsea", "mtdeepgreen", "safari", "turtleshellpond"]
	_trip.call("fa", "")
	await wait(1.0); await shot("fa_base")
	Input.action_press("ui_up")
	await wait(0.15)
	Input.action_release("ui_up")
	await wait(1.2); await shot("fa_moved")
	await press("ui_accept")
	await wait(0.4); await shot("fa_menu")
	await press("ui_accept")
	await _wait_done()
	print("WMAP friend areas -> ", _res)
	print("WMAP done fails=", fail)
	get_tree().quit()
