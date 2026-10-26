extends SceneTree
## Headless test for res://scripts/dungeon/dungeon_save.gd (Quicksave / floor autosave).
## Run: godot --headless --path . --script tests/test_dungeon_save.gd
## Builds a real Dungeon, plays a few turns, saves, loads into a fresh Dungeon and compares the whole
## state field by field; then checks RNG continuity, visuals, the Red delete-on-resume rule and that the
## resumed run keeps playing. The real save file is backed up and restored.

var fails := 0
var G: Node
var G2: Node
var DS
var DUN
var HUD
var checks := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	_run.call_deferred()

func _enc(v) -> String:
	return JSON.stringify(JSON.from_native(DS._plain(v)))

func _make(ui: Control):
	var hud = HUD.new()
	ui.add_child(hud)
	var d = DUN.new()
	root.add_child(d)
	d.hud = hud
	d.ui_root = ui
	hud.button.connect(d.on_hud_button)
	return d

func _run() -> void:
	G = root.get_node("Game")
	G2 = root.get_node("DB")
	var db = G2
	DS = load("res://scripts/dungeon/dungeon_save.gd")
	DUN = load("res://scripts/dungeon/dungeon.gd")
	HUD = load("res://scripts/ui/hud.gd")
	load("res://scripts/core/controls.gd").apply()
	if db.species.is_empty():
		db._ready()
	var backup := FileAccess.get_file_as_string("user://save.json") if FileAccess.file_exists("user://save.json") else ""
	var sus_backup: String = FileAccess.get_file_as_string(DS.PATH) if DS.has_suspend() else ""
	DS.clear()
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cl := CanvasLayer.new()
	root.add_child(cl)
	cl.add_child(ui)
	load("res://scripts/ui/dialog.gd").auto = true
	load("res://scripts/ui/list_menu.gd").auto = true
	G.new_game("0004", "Charmander", "0007", "Squirtle", "Save")
	G.bag_add("oran"); G.bag_add("stick", 7); G.money = 123
	G.flags["seen"] = {"0016": true}
	# a taken job in this dungeon so a client Pokémon is on the floor
	G.jobs = [{"id": "t1", "kind": "rescue", "dungeon": "thunderwave_cave", "floor": 1, "client": "0025", "target": "0025", "state": "taken",
		"reward": {"money": 100}, "item": "", "special": 0, "seed": 1, "title": "Help", "difficulty": "E"}]
	var d1 = _make(ui)
	await d1.start("thunderwave_cave", G.team)
	d1.auto_answer = true
	# play a few turns so AI memory, positions, belly and turn counters move
	for i in 6:
		await d1.leader_action({"type": "wait"})
	var L = d1.fs.leader
	L.status.poison = 3
	L.stages.atk = 12
	L.set_meta("prev_pos", [L.pos, L.pos, L.pos, L.pos])
	d1.fs.items[Vector2i(2, 2)] = {"id": "apple", "n": 1, "price": 0}
	d1.fs.traps[Vector2i(3, 2)] = {"id": "mud", "seen": true}
	d1.fs.weather = "rain"
	d1.fs.explored[10] = 1
	d1.fs.set_meta("stairs_sensed", true)
	d1.belly_state.belly = 77.5
	d1.belly = 77.5
	d1.spawn_timer = 9
	d1.mem[L.uid] = {"target_uid": 5, "pos": Vector2i(4, 4)}
	var has_client: bool = d1.fs.mons.any(func(m): return m.side == "client")
	ok(has_client, "the job's client is on floor 1 (Missions hook ran)")
	DS.save(d1)                          # (stores team progress into Game.team first)
	var st1: Dictionary = DS._state(d1)
	ok(DS.has_suspend(), "save writes the suspend file")
	var inf: Dictionary = DS.info()
	ok(inf.get("dkey", "") == "thunderwave_cave" and int(inf.get("floor", -1)) == 0 and not inf.has("state"), "info() header")
	var r1 := [d1.rng.randi(), d1.fs.rng.randi()]
	# wipe Game to prove the snapshot restores it
	var team_before := _enc(G.team)
	var bag_before := _enc(G.bag)
	var jobs_before := _enc(G.jobs)
	G.bag = []
	G.money = 0
	G.jobs = []
	# fresh dungeon (the old one is gone, as after quitting the game)
	var d1_team_n: int = d1.team_mons.size()
	var d1_leader_pos: Vector2i = L.pos
	d1.hud.queue_free()
	d1.queue_free()
	await process_frame
	var d2 = _make(ui)
	var loaded: bool = DS.load_into(d2)
	ok(loaded, "load_into returns true")
	ok(not DS.has_suspend(), "suspend file is deleted on resume (Red rule)")
	ok(not DS.load_into(_make(ui)), "a second resume is impossible")
	var st2: Dictionary = DS._state(d2)
	for k in st1:
		if k in ["uid_next"]:
			continue
		if k == "fs":
			for fk in st1.fs:
				ok(_enc(st1.fs[fk]) == _enc(st2.fs.get(fk)), "floor field %s" % fk)
		elif k == "mons":
			ok(st1.mons.size() == st2.mons.size(), "same number of Pokémon")
			for i in mini(st1.mons.size(), st2.mons.size()):
				for mk in st1.mons[i]:
					ok(_enc(st1.mons[i][mk]) == _enc(st2.mons[i].get(mk)), "mon %s field %s" % [st1.mons[i].name, mk])
		elif k == "game":
			for gk in st1.game:
				ok(_enc(st1.game[gk]) == _enc(st2.game.get(gk)), "game field %s" % gk)
		elif k == "rng":
			pass
		else:
			ok(_enc(st1[k]) == _enc(st2.get(k)), "dungeon field %s" % k)
	ok(_enc(G.team) == team_before and _enc(G.bag) == bag_before and _enc(G.jobs) == jobs_before and G.money == 123, "Game team / bag / jobs / money restored")
	ok([d2.rng.randi(), d2.fs.rng.randi()] == r1, "dungeon and floor RNG continue exactly")
	ok(d2.fs.leader != null and d2.fs.leader.is_leader and d2.fs.leader.pos == d1_leader_pos, "leader restored")
	ok(d2.fs.leader.get_meta("entry") == G.team[0] and is_same(d2.fs.leader.get_meta("entry"), G.team[0]), "team entry relinked to G.team")
	ok(d2.fs.mons.all(func(m): return is_instance_valid(m.visual) and m.visual.mon == m), "every Pokémon has a sprite")
	ok(d2.team_mons.size() == d1_team_n and d2.team_mons.all(func(m): return m in d2.fs.mons or m.hp <= 0), "team_mons restored")
	ok(d2.fs.items.has(Vector2i(2, 2)) and d2.fs.traps.has(Vector2i(3, 2)) and d2.fs.weather == "rain", "items / traps / weather")
	ok(d2.fs.get_meta("stairs_sensed", false), "floor metas")
	ok(d2.fs.mons.any(func(m): return m.side == "client" and m.get_meta("job_id", "") == "t1"), "client keeps its job_id")
	ok(G2._uid > d2.fs.mons.map(func(m): return m.uid).max(), "uid counter moved past restored Pokémon")
	ok(d2.terrain_view != null and d2.terrain_view.is_inside_tree() and d2.mon_layer.get_child_count() >= d2.fs.mons.size(), "terrain view + sprite layer built")
	# the resumed run keeps playing
	d2.busy = false
	d2.auto_answer = true
	var t0: int = d2.fs.turn
	for i in 3:
		await d2.leader_action({"type": "wait"})
	ok(d2.fs.turn == t0 + 3 or d2.result_sent, "resumed run plays turns (turn %d -> %d, busy %s, result_sent %s, leader hp %d)" % [t0, d2.fs.turn, d2.busy, d2.result_sent, d2.fs.leader.hp])
	# Pokédex hook
	load("res://scripts/core/pokedex.gd").see_visible(d2)
	ok(G.flags.seen.has("0016"), "Pokédex seen dict survives")
	# restore the real files
	DS.clear()
	if backup != "":
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	if sus_backup != "":
		var f2 := FileAccess.open(DS.PATH, FileAccess.WRITE)
		f2.store_string(sus_backup)
		f2.close()
	print("DUNGEON SAVE TEST: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)
