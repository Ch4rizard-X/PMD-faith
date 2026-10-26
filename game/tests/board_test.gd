extends Control
## Visual check for scripts/ui/board.gd and Missions.complete_rewards (no main.gd needed).
## Run: xvfb-run -a -s "-screen 0 1440x810x24" godot --path . --rendering-driver opengl3 --resolution 1440x810 res://tests/board_test.tscn
## Opens the board on this Control, drives it with simulated input, saves screenshots to user://board_*.png
## and quits. The real save file is backed up and restored.

var shot_n := 0
var _backup := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.25, 0.15)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if FileAccess.file_exists(Game.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(Game.SAVE_PATH)
	_setup()
	_drive.call_deferred()

func _setup() -> void:
	Game.team_name = "Poképals"
	Game.team = [{"sp": "0025", "name": "Pikachu"}, {"sp": "0004", "name": "Charmander"}]
	Game.cleared = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm", "mt_thunder", "great_canyon", "lapis_cave"]
	Game.unlocked = Game.cleared.duplicate()
	Game.rank_points = 40
	Game.jobs = []
	Game.board = []
	Game.board_day = -1
	Game.day = 7
	Game.bag = []
	Game.money = 0
	Game.flags = {}
	Game.friends = []
	for a in ["act_attack", "act_menu", "act_run", "act_wait", "act_auto", "act_bag", "act_diag", "act_map", "act_moves", "act_turn", "move_up", "move_down", "move_left", "move_right", "move_ul", "move_ur", "move_dl", "move_dr"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	Game.board = Missions.make_board(rng)
	while Game.board.size() < 8:
		Game.board.append(Missions.gen_job(rng, Missions.make_context(Game.board)))
	Game.board_day = Game.day

func _shot(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var path := "user://board_%02d_%s.png" % [shot_n, name]
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
		for k in 3:
			await get_tree().process_frame

func _drive() -> void:
	Board.open(self)
	await _shot("menu")
	await _press("ui_accept")                 # Bulletin Board
	await _shot("board_p1")
	await _press("ui_down", 2)
	await _shot("board_sel3")
	await _press("ui_right")
	await _shot("board_p2")
	await _press("ui_left")
	await _press("ui_accept")                 # -> Accept / Info
	await _shot("board_menu")
	await _press("ui_down")
	await _press("ui_accept")                 # Info
	await _shot("info")
	await _press("ui_accept")                 # close info
	await _press("ui_accept")                 # menu again
	await _press("ui_accept")                 # Accept
	await _shot("accepted")
	await _press("ui_down")
	await _press("ui_accept")
	await _press("ui_accept")                 # accept a second job
	await _press("ui_cancel")                 # back to the top menu
	await _press("ui_down")
	await _press("ui_accept")                 # Job List
	await _shot("joblist")
	await _press("ui_accept")                 # Take Job / Delete / Info
	await _shot("joblist_menu")
	await _press("ui_accept")                 # Take Job
	await _shot("joblist_taken")
	await _press("ui_cancel")
	await _press("ui_cancel")                 # exit
	await _shot("closed")
	# long texts: show the Info page of every board job once
	for j in Game.board:
		Board.show_info(self, j)
		await _shot("info_" + str(j.kind))
		await _press("ui_accept")
	# rewards scene: finish the first accepted job
	var j: Dictionary = Game.jobs[0]
	j.state = "done"
	j.reward = {"type": "money_extra", "money": 300, "item": "oran", "item_n": 1, "extra": 0, "rank_points": 20, "friend_area": ""}
	Missions.complete_rewards(self)
	var k := 0
	while not Missions.pending_rewards().is_empty() or k < 2:
		await get_tree().create_timer(1.5).timeout
		await _shot("reward_%d" % k)
		await _press("ui_accept")
		k += 1
		if k > 20:
			break
	print("money ", Game.money, " rank ", Game.rank_points, " ", Missions.rank_name(Game.rank_points), " jobs ", Game.jobs.size())
	# mailbox
	Board.open_mailbox(self)
	await _shot("mailbox")
	await _press("ui_cancel")
	await _press("ui_accept")
	await _dungeon_check()
	# restore the real save
	if _backup != "":
		var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	elif FileAccess.file_exists(Game.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	print("BOARD_TEST_DONE")
	get_tree().quit()


## Dungeon hooks without touching dungeon.gd: start Tiny Woods, call Missions.on_floor_built like the lead
## will, walk the client next to the leader, then answer the rescue prompts.
var _result := ""
func _dungeon_check() -> void:
	Game.team = [Game._entry("0025", "Pikachu", 10), Game._entry("0004", "Charmander", 10)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var j: Dictionary = {}
	while j.is_empty() or j.kind != "rescue":
		Game.cleared = ["tiny_woods"]
		j = Missions.gen_job(rng, Missions.make_context())
	j.floor = 1
	Missions.describe(j)
	Game.jobs = []
	Missions.accept(j)
	Missions.take(Game.jobs[0])
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var hud := Hud.new()
	ui.add_child(hud)
	var d := Dungeon.new()
	add_child(d)
	d.hud = hud
	d.ui_root = ui
	d.finished.connect(func(r): _result = r)
	await d.start("tiny_woods", Game.team)
	Missions.on_floor_built(d)
	var client: Mon = null
	for m in d.fs.mons:
		if Missions.is_client(m):
			client = m
	print("client on floor: ", client.name if client else "NONE", " side ", client.side if client else "")
	if client:
		var p := d.fs.free_tile_near(d.fs.leader.pos, client, 1)
		if p.x >= 0:
			client.pos = p
			client.visual.position = d._px(p)
		await _shot("dungeon_client")
		Missions.on_leader_step(d)
		for i in 14:
			await get_tree().create_timer(0.5).timeout
			await _shot("dungeon_talk_%d" % i)
			if _result != "":
				break
			await _press("ui_accept")
	print("dungeon result: ", _result)
	Missions.on_dungeon_end("tiny_woods", _result)
	print("job state after return: ", Game.jobs[0].state if not Game.jobs.is_empty() else "none")
	d.queue_free()
	layer.queue_free()
