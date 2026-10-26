extends Node
## Town smoke test (run: godot --path . -- --towntest). Walks the leader around Pokémon Square to every
## stall, checks the interact / exit signals, visits the other town maps, saves screenshots to user://.

var main: Node
var log_i: Array = []
var log_e: Array = []
var shot_n := 0

func _ready() -> void:
	main = get_parent()
	_run.call_deferred()

func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var path := "user://town_%02d_%s.png" % [shot_n, name]
	shot_n += 1
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func _hook() -> void:
	var t: Town = main.town
	if not t.interact.is_connected(_on_i):
		t.interact.connect(_on_i.bind(t.map_key))
		t.exit.connect(_on_e.bind(t.map_key))

func _on_i(id: String, mk: String) -> void:
	log_i.append("%s:%s" % [mk, id])
	print("INTERACT ", mk, " ", id)

func _on_e(to: String, mk: String) -> void:
	log_e.append("%s->%s" % [mk, to])
	print("EXIT ", mk, " -> ", to)

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

## Close the placeholder dialog boxes the stub handlers open.
func _dismiss() -> void:
	for k in 4:
		var any := false
		for c in main.root.get_children():
			if c is Dialog and c.panel.visible:
				c._finish_typing()
				c._advance.emit()
				any = true
		if not any:
			return
		await get_tree().process_frame

func _walk_idle(timeout := 15.0) -> bool:
	var t := 0.0
	await _wait(0.1)
	while t < timeout:
		var tw: Town = main.town
		if not is_instance_valid(tw) or tw.is_idle():
			return true
		await _wait(0.1)
		t += 0.1
	return false

func _visit(id: String, shot := false) -> void:
	var tw: Town = main.town
	var n0 := log_i.size()
	if not tw.walk_to_target(id):
		print("FAIL no path to ", id)
		return
	await _walk_idle()
	await _wait(0.25)
	if shot:
		await _shot(id)
	print("  at ", main.town.pos.round(), " ", "OK" if log_i.size() > n0 else "FAIL (no interact)", " ", id)
	await _dismiss()
	await _wait(0.4)

func _go_exit(to: String) -> void:
	var tw: Town = main.town
	for ex in tw.M.exits:
		if ex.to == to:
			var r: Array = ex.r
			tw.walk_to(Vector2((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0))
			print("  go_exit ", to, " from ", tw.pos, " path ", tw.path)
			var t := 0.0
			var n0 := log_e.size()
			while t < 15.0 and log_e.size() == n0:
				await _wait(0.1)
				t += 0.1
				if log_e.size() == n0 and is_instance_valid(tw) and tw.is_inside_tree() and tw.is_idle() and not tw.busy:
					# path ends at the edge: keep pushing into the exit with the keys
					var c := Vector2((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0)
					tw.walk_to(c + (c - tw.pos).normalized() * 12)
			if log_e.size() == n0:
				print("FAIL exit ", to, " not reached, at ", tw.pos)
			await _wait(0.9)
			await _dismiss()
			return
	print("FAIL no exit ", to)

func _run() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Test")
	Game.settings.zoom = 1.25
	Game.money = 1234
	main.start_town("square")
	_hook()
	await _wait(0.8)
	await _shot("square_spawn")
	# free walking with the keys: down a bit, then right
	Input.action_press("move_down")
	await _wait(0.6)
	Input.action_release("move_down")
	Input.action_press("move_left")
	await _wait(1.0)
	Input.action_release("move_left")
	await _wait(0.2)
	await _shot("square_walked")
	for id in ["kecleon_shop", "kecleon_wares", "persian_bank", "wigglytuff", "gulpin_shop", "kangaskhan_storage"]:
		await _visit(id, id in ["kecleon_shop", "persian_bank", "kangaskhan_storage", "gulpin_shop"])
	# tap on Persian from far away (touch path)
	main.town.pos = Vector2(520, 356)
	await _wait(0.2)
	main.town._tap(Vector2(658, 260))
	await _walk_idle()
	await _wait(0.3)
	await _dismiss()
	await _wait(0.3)
	# menu
	main.town.menu.emit()
	await _wait(0.3)
	await _dismiss()
	# walk west to the team base
	await _go_exit("base")
	_hook()
	await _wait(0.8)
	await _shot("base_arrive")
	await _visit("mailbox")
	await _visit("bed", true)
	await _go_exit("world_map")
	await _wait(0.5)
	await _shot("base_after_world_map")
	await _go_exit("square")
	_hook()
	await _wait(0.6)
	await _go_exit("post_office")
	_hook()
	await _wait(0.8)
	await _shot("post_office")
	await _visit("pelipper_board")
	await _go_exit("square")
	_hook()
	await _wait(0.5)
	await _go_exit("whiscash")
	_hook()
	await _wait(0.8)
	await _visit("whiscash", true)
	main.town.anim_layer.visible = false
	await _shot("whiscash_noanim")
	main.town.anim_layer.visible = true
	await _shot("whiscash_anim")
	await _go_exit("square")
	_hook()
	await _wait(0.5)
	await _go_exit("dojo")
	_hook()
	await _wait(0.8)
	await _visit("makuhita_dojo", true)
	# other bases
	for sp in ["0001", "0007", "0025", "0155", "0258", "0066"]:
		Game.team[0].sp = sp
		main.start_town("base")
		await _wait(0.7)
		await _shot("base_" + sp)
	print("TOWNTEST interacts: ", log_i)
	print("TOWNTEST exits: ", log_e)
	get_tree().quit()
