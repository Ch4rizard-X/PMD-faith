extends RefCounted
## --dgtest[=part,part] screenshots for the Red dungeon presentation (agent "dungeon"). Parts:
## banner, status, weather, dark, map, anim, arena, levelup, recruit, outing (default: all).
## Pictures go to user://dg_*.png.

static func _shot(main: Node, name: String) -> void:
	await main.get_tree().process_frame
	main.get_viewport().get_texture().get_image().save_png("user://dg_%s.png" % name)
	print("DGTEST shot ", name)

static func _press(main: Node) -> void:
	var d = main.dungeon
	if d and d.ui_root:
		var menu := false
		for c in d.ui_root.get_children():
			if c is ListMenu or c is NamingScreen:
				menu = true
		if not menu:
			for c in d.ui_root.get_children():
				if c is Dialog and c.panel.visible:
					c._finish_typing()
					c._press()
					await main.get_tree().process_frame
					return
	var e := InputEventAction.new()
	e.action = "ui_accept"
	e.pressed = true
	Input.parse_input_event(e)
	await main.get_tree().process_frame
	var e2 := InputEventAction.new()
	e2.action = "ui_accept"
	e2.pressed = false
	Input.parse_input_event(e2)
	await main.get_tree().process_frame

static func _wait(main: Node, s: float) -> void:
	await main.get_tree().create_timer(s).timeout

static func run(main: Node) -> void:
	var parts := ["banner", "status", "weather", "dark", "map", "anim", "arena", "levelup", "recruit", "outing"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dgtest="):
			parts = Array(a.substr(9).split(","))
	Game.new_game("0025", "Pikachu", "0004", "Charmander", "Test")
	Game.settings.zoom = 2.0
	if "banner" in parts:
		main.start_dungeon("tiny_woods")
		await _wait(main, 0.5)
		await _shot(main, "banner")
		await _wait(main, 0.75)
		await _shot(main, "banner_fade")
	else:
		await main.start_dungeon("tiny_woods")
	await _wait(main, 1.5)
	var d = main.dungeon
	d.auto_answer = true
	var L: Mon = d.fs.leader
	if "status" in parts:
		var team: Array = d.fs.team()
		L.status.sleep = 3
		L.status.poison = 5
		if team.size() > 1:
			team[1].status.burn = 4
			team[1].status.reflect = 5
			team[1].hp = 1
		var foe: Mon = null
		for m in d.fs.mons:
			if not m.is_team():
				foe = m
				break
		if foe:
			foe.pos = L.pos + Vector2i(2, 0)
			foe.visual.position = d._px(foe.pos)
			foe.status.confused = 5
			foe.status.frozen = 5
			foe.stages.atk = 8
		d._reveal()
		await _wait(main, 0.4)
		await _shot(main, "status_a")
		await _wait(main, 1.1)
		await _shot(main, "status_b")
		for m in d.fs.mons:
			for k in m.status:
				if m.status[k] is int:
					m.status[k] = 0
			m.stages.atk = 10
		if team.size() > 1:
			team[1].hp = team[1].max_hp
	if "weather" in parts:
		for w in ["rain", "sandstorm", "hail", "snow", "fog", "cloudy", "sunny"]:
			d.fs.weather = w
			await _wait(main, 0.35)
			await _shot(main, "weather_%s" % w)
			await _wait(main, 1.0)
		d.fs.weather = "clear"
		await _wait(main, 1.2)
	if "dark" in parts:
		d.fs.visibility = 1
		await _wait(main, 0.2)
		await _shot(main, "dark_room")
		var cp := _corridor_tile(d)
		if cp.x >= 0:
			L.pos = cp
			d._snap_visuals()
			d._reveal()
			await _wait(main, 0.3)
			await _shot(main, "dark_corridor1")
			d.fs.visibility = 2
			await _wait(main, 0.2)
			await _shot(main, "dark_corridor2")
		d.fs.visibility = 0
	if "map" in parts:
		for y in d.fs.h:
			for x in d.fs.w:
				if d.fs.terrain[y * d.fs.w + x] != 0 and (x + y) % 3 != 0:
					d.fs.explored[y * d.fs.w + x] = 1
		Game.settings.map_mode = 1
		d._update_hud()
		await _wait(main, 0.2)
		await _shot(main, "map_clear")
		Game.settings.map_mode = 2
		d._update_hud()
		await _wait(main, 0.2)
		await _shot(main, "map_shade")
		d._toggle_map()
		await _wait(main, 0.2)
		await _shot(main, "map_full")
		d._toggle_map()
		Game.settings.map_mode = 1
	if "levelup" in parts:
		d.auto_answer = false
		Dialog.auto = false
		d.gain_exp(L, DB.exp_at(L.sp, L.level + 2) - L.exp)
		for i in 5:
			await _wait(main, 0.5)
			await _shot(main, "levelup_%d" % i)
			await _press(main)
		Dialog.auto = true
		d.auto_answer = true
		await _wait(main, 0.5)
	if "recruit" in parts:
		var foe2: Mon = null
		for m in d.fs.mons:
			if not m.is_team():
				foe2 = m
				break
		if foe2:
			d.auto_answer = false
			Dialog.auto = false
			var askf := func(): return await Dialog.ask(d.ui_root, "Yes! [color=#7fe0ff]%s[/color] wants to join the team!\nAccept [color=#7fe0ff]%s[/color] as a team member?" % [foe2.name, foe2.name], ["Yes", "No"], "", "Normal", false)
			askf.call()
			await _wait(main, 0.5)
			await _shot(main, "recruit_ask")
			await _press(main)
			await _wait(main, 0.3)
			Dialog.auto = true
			d.auto_answer = true
			d._msg("[color=#7fe0ff]%s[/color] went away..." % foe2.name)
			await _wait(main, 0.2)
			await _shot(main, "recruit_log")
			# the join sequence: nickname question -> naming screen -> "joined ... to go on adventures!"
			Dialog.auto = false
			d.auto_answer = false
			d._join_sequence(foe2)
			await _wait(main, 3.4)
			await _shot(main, "recruit_nick_ask")
			await _press(main)
			await _wait(main, 0.6)
			await _shot(main, "recruit_naming")
			for n in d.ui_root.get_children():
				if n is NamingScreen:
					n._done.emit("Sunny")
			await _wait(main, 0.5)
			await _shot(main, "recruit_confirm")
			await _press(main)
			await _wait(main, 0.6)
			await _shot(main, "recruit_joined")
			Dialog.auto = true
			d.auto_answer = true
	if "anim" in parts:
		for e in [["stormy_sea", 0], ["magma_cavern_pit", 0]]:
			await _start(main, e[0], e[1])
			d = main.dungeon
			d.auto_answer = true
			var wp := _water_tile(d)
			print("DGTEST water tile ", e[0], " ", wp)
			if wp.x >= 0:
				d.fs.leader.pos = wp
				d._snap_visuals()
			d.fs.visibility = 0
			await _wait(main, 0.5)
			for i in 3:
				await _shot(main, "anim_%s_%d" % [e[0], i])
				await _wait(main, 0.2)
	if "arena" in parts:
		for e in [["mt_steel", 8], ["mt_blaze_peak", 2], ["sky_tower_summit", 8], ["frosty_grotto", 4]]:
			await _start(main, e[0], e[1])
			main.dungeon.auto_answer = true
			await _wait(main, 0.4)
			await _shot(main, "arena_%s" % e[0])
	if "outing" in parts:
		d = main.dungeon
		d.exit_summary = LastOuting.summary("move", d.fs.leader, d.fs.mons[d.fs.mons.size() - 1], "Thunderbolt")
		Dialog.auto = false
		d.show_last_outing(d.ui_root, "defeated")
		await _wait(main, 0.1)
		await _shot(main, "outing_slide")
		await _wait(main, 0.6)
		await _shot(main, "outing")
		await _press(main)
		Dialog.auto = true
	print("DGTEST done")
	main.get_tree().quit()

static func _start(main: Node, key: String, fl: int) -> void:
	Dialog.auto = true
	main.start_dungeon(key, fl)
	await _wait(main, 2.6)

static func _corridor_tile(d) -> Vector2i:
	var L: Mon = d.fs.leader
	var best := Vector2i(-1, -1)
	var bd := 9999
	for y in d.fs.h:
		for x in d.fs.w:
			var p := Vector2i(x, y)
			if d.fs.terrain_at(p) == 1 and d.fs.room_at(p) == 255 and d.fs.mon_at(p) == null:
				var dd := absi(p.x - L.pos.x) + absi(p.y - L.pos.y)
				if dd < bd:
					bd = dd
					best = p
	return best

static func _water_tile(d) -> Vector2i:
	for y in range(2, d.fs.h - 2):
		for x in range(2, d.fs.w - 2):
			var p := Vector2i(x, y)
			if d.fs.terrain_at(p) == 1 and d.fs.terrain_at(p + Vector2i(1, 0)) == 2 and d.fs.mon_at(p) == null:
				return p
	return Vector2i(-1, -1)
