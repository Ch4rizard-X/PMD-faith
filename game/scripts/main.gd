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
	if OS.get_cmdline_user_args().has("--poketest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(2.0).timeout
			var d := dungeon
			var w: Mon = null
			for m in d.fs.mons:
				if not m.is_team():
					w = m
					break
			if w == null:
				print("POKETEST no wild"); get_tree().quit(); return
			for k in w.status.keys():
				if w.status[k] is int:
					w.status[k] = 0
			w.held = ""
			d.fs.items[w.pos] = {"id": "poke", "n": 50}
			var mem := {}
			var acts := []
			for i in 3:
				var r := AI.decide(w, d.fs, mem)
				acts.append(str(r.get("type", "")) + ":" + str(r.get("action", r.get("dir", ""))))
			print("POKETEST wild_actions=", acts, " pickup_any=", acts.any(func(x): return x.begins_with("item:pickup")))
			var pt: Mon = d.fs.mons.filter(func(x): return x.is_team() and not x.is_leader)[0]
			pt.held = ""
			var bag0 := Game.bag.size()
			d.fs.items[pt.pos] = {"id": "oranberry", "n": 1}
			await d.execute(pt, {"type": "item", "action": "pickup"})
			print("POKETEST partner held=", pt.held, " bag ", bag0, "->", Game.bag.size(), " item_left=", d.fs.items.has(pt.pos))
			get_tree().quit()).call_deferred()
	if OS.get_cmdline_user_args().has("--steptest"):
		(func():
			# Holding a direction with other Pokémon on the floor (some asleep far away): count the frames the
			# hero stands still between steps.
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Engine.max_fps = 60
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
			var L: Mon = d.fs.leader
			_qplace(L, cor[0])
			var nfoe := 0
			for y in d.fs.h:
				for x in d.fs.w:
					var p := Vector2i(x, y)
					if nfoe < 5 and d.fs.room_at(p) != 255 and d.fs.walkable(p, null) and d.fs.mon_at(p) == null and FloorState.cheb(p, L.pos) > 12:
						var f := _qfoe(p)
						f.status["sleep"] = 99
						nfoe += 1
			await get_tree().create_timer(0.3).timeout
			var act: String = {0: "move_down", 2: "move_right", 4: "move_up", 6: "move_left"}.get(int(cor[1]), "move_right")
			Input.action_press(act)
			var last: Vector2 = L.visual.position
			var stalls := 0
			var frames := 0
			var p0 := L.pos
			while frames < 120 and L.pos.distance_to(Vector2(p0)) < 6:
				await get_tree().process_frame
				frames += 1
				if L.visual.position.distance_to(last) < 0.01 and frames > 2:
					stalls += 1
					print("  stall partner=%s on=%s view=%s f=%d pos=%s busy=%s menu=%s walkers=%d dt=%.3f msgs=%d log=%s" % [d.fs.team()[1].pos, d._on_screen(d.fs.team()[1].pos), d.get_viewport_rect().size / d.cam.zoom / 24.0, frames, L.pos, d.busy, d.menu_open, d._walkers.size(), get_process_delta_time(), d.hud.msg_count, str(d.hud.log_all.back()).left(80) if not d.hud.log_all.is_empty() else ""])
				last = L.visual.position
			Input.action_release(act)
			print("STEPTEST foes=%d tiles=%d frames=%d stall_frames=%d" % [nfoe, int(L.pos.distance_to(Vector2(p0))), frames, stalls])
			get_tree().quit()).call_deferred()
	if OS.get_cmdline_user_args().has("--meaniestest"):
		(func():
			# Lose the Team Meanies fight the way the story enters it, then report where the game went.
			Dialog.auto = true
			ListMenu.auto = true
			Ground.turbo = 6
			Game.load_game()
			GData.load_all()
			var key := "sinister_woods"
			var did: int = DB.dungeons.get("dungeons", {}).keys().find(key)
			var sd := -1
			for i in GData.extra.dungeons.size():
				var inf: Dictionary = GData.dungeon_info(i)
				if int(inf.dungeon) == did and int(inf.get("u11", 1)) == 0:
					sd = i
			print("MEANIES scen=%s sd=%d leader=%s base_kind=%d base_level=%d" % [str(GVars.scenario(GVars.SCENARIO_MAIN)), sd, Game.team[0].sp, GVars.get_val(null, GVars.BASE_KIND), GVars.get_val(null, GVars.BASE_LEVEL)])
			GVars.set_val(null, GVars.DUNGEON_ENTER, sd)
			for a2 in OS.get_cmdline_user_args():
				if a2.begins_with("--basekind="):
					GVars.set_val(null, GVars.BASE_KIND, int(a2.substr(11)))
			Dungeon.test_invincible = false
			_on_ground_finished(7)
			for i in 30:
				await get_tree().create_timer(0.5).timeout
				if is_instance_valid(dungeon) and dungeon.fs and not dungeon.busy and i > 6:
					break
			print("MEANIES in dungeon=%s floor=%d" % [dungeon.dkey if is_instance_valid(dungeon) else "-", dungeon.floor_i if is_instance_valid(dungeon) else -1])
			dungeon._end("defeated")
			for i in 60:
				await get_tree().create_timer(1.0).timeout
				if is_instance_valid(ground):
					ground.text.auto = true
				if i % 10 == 9:
					print("MEANIES t=%d where=%s" % [i, ("town:" + town.map_key) if is_instance_valid(town) else (("ground:%d" % ground.vis_map) if is_instance_valid(ground) else "?")])
			get_viewport().get_texture().get_image().save_png("user://meanies_after.png")
			var where := "town:" + town.map_key if is_instance_valid(town) else ("ground:%d" % ground.vis_map if is_instance_valid(ground) else "?")
			print("MEANIES after: where=%s scen=%s postgame=%s shop_fa=%d story_vars=%s base_level=%d leader=%s" % [where, str(GVars.scenario(GVars.SCENARIO_MAIN)), RedShops.postgame(), RedShops.shop_areas().size(), Game.story.has("vars"), GVars.get_val(null, GVars.BASE_LEVEL), Game.team[0].sp])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--partnertest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Game.story.erase("cutscene_flags")
			await start_dungeon("thunderwave_cave")
			await get_tree().create_timer(2.0).timeout
			var d: Dungeon = dungeon
			d.auto_answer = true
			d.test_invincible = true
			var fs: FloorState = d.fs
			var L: Mon = fs.leader
			var P: Mon = null
			for m in fs.team():
				if m != L and P == null:
					P = m
			var tally := {"ok": 0, "bad": 0}
			var check := func(what: String, ok: bool, info := ""):
				tally["ok" if ok else "bad"] += 1
				print("PARTNERTEST %s %s %s" % ["ok " if ok else "BAD", what, info])
			# an open spot: the middle of the biggest room, carved out to 11 x 11 floor with no traps (test only)
			var big: Rect2i = fs.rooms[0]
			for rr in fs.rooms:
				if rr.get_area() > big.get_area(): big = rr
			var c := big.get_center()
			c.x = clampi(c.x, 7, fs.w - 8)
			c.y = clampi(c.y, 7, fs.h - 8)
			for dy in range(-5, 6):
				for dx in range(-5, 6):
					var q := c + Vector2i(dx, dy)
					fs.terrain[fs.idx(q)] = 1
					fs.traps.erase(q)
			print("PARTNERTEST open spot ", c)
			var P_moves := P.moves.duplicate(true)
			var reset := func(lp: Vector2i, pp: Vector2i):
				for m in fs.mons.duplicate():
					if not m.is_team():
						if m.visual: m.visual.queue_free()
						fs.mons.erase(m)
					elif m != L and m != P:
						fs.mons.erase(m)
				L.pos = lp
				P.pos = pp
				fs.items.clear()
				P.hp = P.max_hp
				P.moves = P_moves.duplicate(true)
				for k in P.status:
					if P.status[k] is int: P.status[k] = 0
				d.mem.erase(P.uid)
				L.remove_meta("last_target_uid")
			var foe := func(sp: String, p: Vector2i, lv := 5) -> Mon:
				var f: Mon = DB.make_mon(sp, lv, "enemy")
				f.pos = p
				fs.mons.append(f)
				return f
			var mv_of := func(names: Array) -> Array:
				var out: Array = []
				for n in names:
					out.append({"name": n, "pp": 20, "max_pp": 20, "on": true, "linked": false})
				return out
			var step_to := func(a: Dictionary) -> Vector2i:
				return P.pos + DB.DIRS[int(a.dir)] if str(a.get("type", "")) == "move" else P.pos
			for mode in [1, 0]:
				Game.settings["qol_partner_ai"] = mode
				var tag := "Smarter" if mode == 1 else "Red    "
				# 1) a foe 3 tiles from the leader, partner on the other side
				reset.call(c, c + Vector2i(-1, 0))
				var f1: Mon = foe.call("0019", c + Vector2i(3, 0))
				var a1 := d._decide(P)
				var closer := FloorState.cheb(step_to.call(a1), f1.pos) < FloorState.cheb(P.pos, f1.pos)
				if mode == 1: check.call("goes for a foe 3 tiles away", closer, str(a1))
				else: print("PARTNERTEST info Red: goes for a foe 3 tiles away = %s %s" % [closer, a1])
				# 2) protects the leader: the foe next to the leader before another next to the partner
				reset.call(c, c + Vector2i(1, 1))
				var fa: Mon = foe.call("0019", c + Vector2i(1, 0))
				var fb: Mon = foe.call("0019", c + Vector2i(2, 2))
				var a2 := d._decide(P)
				var at_a := str(a2.get("type", "")) == "attack" and int(a2.dir) == AI.dir_toward(P.pos, fa.pos)
				if mode == 1: check.call("hits the foe next to the leader first", at_a, str(a2))
				else: print("PARTNERTEST info Red: hits the foe next to the leader = %s %s" % [at_a, a2])
				# 3) a line move at a foe 3 tiles away in a straight line
				reset.call(c, c + Vector2i(-1, 0))
				P.moves = mv_of.call(["Flamethrower"])
				var f3: Mon = foe.call("0019", c + Vector2i(-1, -3))
				var a3 := d._decide(P)
				if mode == 1: check.call("uses a line move from range", str(a3.get("move", "")) == "Flamethrower", str(a3))
				else: print("PARTNERTEST info Red: line move from range: %s" % a3)
				# 4) lines up for the line move instead of walking next to the foe
				reset.call(c, c + Vector2i(-1, 0))
				P.moves = mv_of.call(["Flamethrower"])
				var f4: Mon = foe.call("0019", c + Vector2i(0, -3))
				var a4 := d._decide(P)
				var np: Vector2i = step_to.call(a4)
				var lined: bool = d.partner_ai._can_hit_from(np, f4, d.partner_ai._ranged(P)) or str(a4.get("move", "")) == "Flamethrower"
				if mode == 1: check.call("lines up for a ranged move", lined, str(a4))
				# 5) no Electric move on a Ground foe
				var no_imm := true
				for i in 10:
					reset.call(c, c + Vector2i(-1, 0))
					P.moves = mv_of.call(["Thundershock", "Tackle"])
					foe.call("0074", c + Vector2i(-2, 0))
					var a5 := d._decide(P)
					if str(a5.get("move", "")) == "Thundershock": no_imm = false
				if mode == 1: check.call("never uses a move the foe is immune to", no_imm)
				else: print("PARTNERTEST info Red: avoided the immune move = %s" % no_imm)
				# 6) no paralysis move on a paralysed foe
				var no_dup := true
				for i in 20:
					reset.call(c, c + Vector2i(-1, 0))
					P.moves = mv_of.call(["Thunder Wave"])
					var f6: Mon = foe.call("0019", c + Vector2i(-2, 0))
					f6.status["para"] = 9
					var a6 := d._decide(P)
					if str(a6.get("move", "")) == "Thunder Wave": no_dup = false
				if mode == 1: check.call("no status move on a foe that already has it", no_dup)
				else: print("PARTNERTEST info Red: skipped the useless status move = %s" % no_dup)
				# 7) leaves a recruitable foe to the leader
				Game.settings["qol_recruit"] = 1
				reset.call(c, c + Vector2i(-1, 1))
				var f7: Mon = foe.call("0019", c + Vector2i(-2, 1))
				f7.recruit_ok = true
				f7.hp = maxi(1, f7.max_hp / 6)
				if not Services.has_area_for("0019"): Game.friend_areas.append(Services.area_of("0019"))
				var a7 := d._decide(P)
				var hit7 := str(a7.get("type", "")) == "attack" and int(a7.dir) == AI.dir_toward(P.pos, f7.pos)
				if mode == 1: check.call("leaves a recruitable foe to the leader", not hit7 and d.recruit_candidate(f7), str(a7))
				else: print("PARTNERTEST info Red: left the recruit to the leader = %s" % (not hit7))
				# 8) a hurt partner stays back
				reset.call(c, c + Vector2i(-1, 0))
				P.hp = maxi(1, P.max_hp / 5)
				var f8: Mon = foe.call("0019", c + Vector2i(3, 0))
				var a8 := d._decide(P)
				var stays := FloorState.cheb(step_to.call(a8), f8.pos) >= FloorState.cheb(P.pos, f8.pos)
				if mode == 1: check.call("stays back when hurt", stays, str(a8))
				# 9) finds its way around a wall to the leader
				reset.call(c, c + Vector2i(4, 0))
				var walls := [c + Vector2i(2, -1), c + Vector2i(2, 0), c + Vector2i(2, 1), c + Vector2i(2, -2), c + Vector2i(2, 2)]
				for wq in walls: fs.terrain[fs.idx(wq)] = 0
				var steps := 0
				for i in 10:
					if FloorState.cheb(P.pos, L.pos) <= 1: break
					var a9 := d._decide(P)
					if str(a9.get("type", "")) == "move" and fs.can_step(P.pos, int(a9.dir), P) and fs.mon_at(P.pos + DB.DIRS[int(a9.dir)]) == null:
						P.pos += DB.DIRS[int(a9.dir)]
					steps += 1
				for wq in walls: fs.terrain[fs.idx(wq)] = 1
				var got := FloorState.cheb(P.pos, L.pos) <= 1
				if mode == 1: check.call("walks around a wall back to the leader", got, "in %d turns" % steps)
				else: print("PARTNERTEST info Red: around the wall = %s in %d turns" % [got, steps])
				# 10) a foe far away (6 tiles from the leader): stays with the leader
				reset.call(c, c + Vector2i(-1, 0))
				var f10: Mon = foe.call("0019", c + Vector2i(4, 4))
				var a10 := d._decide(P)
				if mode == 1: check.call("doesn't wander off after far foes", FloorState.cheb(step_to.call(a10), L.pos) <= 1, str(a10))
			Game.settings["qol_partner_ai"] = 1
			# 11) timing: decisions per partner per turn
			reset.call(c, c + Vector2i(-1, 0))
			foe.call("0019", c + Vector2i(3, 2))
			foe.call("0019", c + Vector2i(-3, 3))
			var t0 := Time.get_ticks_usec()
			for i in 200:
				d.mem.erase(P.uid)
				d._decide(P)
			var us := (Time.get_ticks_usec() - t0) / 200.0
			var pa: PartnerAI = d.partner_ai
			for part in ["foes", "bfs", "attack", "target"]:
				var t1 := Time.get_ticks_usec()
				for i in 100:
					match part:
						"foes": pa._foes(P)
						"bfs": pa._bfs(P, PartnerAI.NEAR_DEPTH)
						"attack": pa.best_attack(P, pa._foes(P))
						"target": pa.pick_target(P, pa._foes(P))
				print("PARTNERTEST part %s %.0f us" % [part, (Time.get_ticks_usec() - t1) / 100.0])
			check.call("decision time under 4 ms", us < 4000.0, "%.0f us" % us)
			# 12) controller L + A/B/X/Y = moves 1-4
			reset.call(c, c + Vector2i(-3, 0))
			L.moves = mv_of.call(["Scratch", "Growl", "Ember", "Smokescreen"])
			var btns := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
			Input.action_press("gp_l")
			var evl := InputEventJoypadButton.new()
			evl.button_index = JOY_BUTTON_LEFT_SHOULDER
			evl.pressed = true
			d._pad_event(evl)
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png("user://l_moves.png")
			check.call("holding L shows the move window", d._lmoves != null)
			for k in 4:
				Input.action_press("gp_l")
				var ev := InputEventJoypadButton.new()
				ev.button_index = btns[k]
				ev.pressed = true
				d.busy = false
				d.menu_open = false
				d._pad_event(ev)
				await get_tree().create_timer(1.5).timeout
				Input.action_release("gp_l")
				var ev2 := InputEventJoypadButton.new()
				ev2.button_index = btns[k]
				ev2.pressed = false
				d._pad_event(ev2)
				check.call("L+%s uses move %d" % [["A", "B", "X", "Y"][k], k + 1], L.last_move == str(L.moves[k].name), "last=" + L.last_move)
			print("PARTNERTEST summary ok=%d bad=%d" % [tally.ok, tally.bad])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--recruittest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Game.story.erase("cutscene_flags")      # a fresh adventure: no story events done yet
			Game.settings["qol_recruit"] = 0         # Red recruiting first; DX further down
			await start_dungeon("thunderwave_cave")
			await get_tree().create_timer(2.0).timeout
			var d := dungeon
			d.auto_answer = true
			var L: Mon = d.fs.leader
			var tally := {"ok": 0, "bad": 0}
			var check := func(what: String, got, want):
				tally["ok" if got == want else "bad"] += 1
				print("RECRUITTEST %s %s: got %s, want %s" % ["ok " if got == want else "BAD", what, got, want])
			# --- the rate (Red: species rate + Friend Bow 100 + gRecruitRateByLevel[leader level], out of 1000)
			var t := DB.make_mon("0019", 5, "enemy")
			var base := int(DB.species["0019"].recruit)
			for lv in [5, 29, 30, 45, 55, 65, 75, 85, 95]:
				L.level = lv
				var want: int = base + int({5: 0, 29: 0, 30: 50, 45: 75, 55: 100, 65: 125, 75: 150, 85: 175, 95: 240}[lv])
				check.call("rate Rattata, leader Lv%d" % lv, d.recruit_rate(L, t), want)
			L.level = 5
			L.held = "friendbow"
			check.call("rate with Friend Bow", d.recruit_rate(L, t), base + 100)
			L.held = ""
			# --- rules
			var mk := func(sp: String) -> Mon:
				var m := DB.make_mon(sp, 10, "enemy")
				m.recruit_ok = true
				return m
			check.call("Gengar before Team Meanies", d.recruit_allowed(mk.call("0094")), false)
			check.call("Skarmory before Mt. Steel", d.recruit_allowed(mk.call("0227")), false)
			check.call("Mankey before Uproar Forest", d.recruit_allowed(mk.call("0056")), false)
			check.call("Zapdos before its fight", d.recruit_allowed(mk.call("0145")), false)
			check.call("Regirock before the Regi item", d.recruit_allowed(mk.call("0377")), false)
			BossScene.set_flag("CUTSCENE_FLAG_MT_STEEL_COMPLETE")
			BossScene.set_flag("CUTSCENE_FLAG_UPROAR_FOREST_COMPLETE")
			check.call("Skarmory after Mt. Steel", d.recruit_allowed(mk.call("0227")), true)
			check.call("Mankey after Uproar Forest", d.recruit_allowed(mk.call("0056")), true)
			check.call("Latias never", d.recruit_allowed(mk.call("0380")), false)
			check.call("Latios never", d.recruit_allowed(mk.call("0381")), false)
			check.call("Rattata always", d.recruit_allowed(mk.call("0019")), true)
			check.call("Tiny Woods allows recruiting (Red: no)", DB.dungeons.dungeons["tiny_woods"].get("recruit", true), false)
			# --- end to end: knock out a wild Pokémon next to the leader
			var setup := func(sp: String, area: bool, rate: int) -> Mon:
				for m in dungeon.fs.mons.duplicate():
					if not m.is_team():
						if m.visual: m.visual.queue_free()
						dungeon.fs.mons.erase(m)
				var a := Services.area_of(sp)
				Game.friend_areas.erase(a)
				if area: Game.friend_areas.append(a)
				DB.species[sp].recruit = rate
				var p := Vector2i(-1, -1)
				for dv in DB.DIRS:
					var q: Vector2i = dungeon.fs.leader.pos + dv
					if dungeon.fs.walkable(q, null) and dungeon.fs.mon_at(q) == null:
						p = q
						break
				var w: Mon = dungeon._spawn_wild(p)
				print("RECRUITTEST spawned %s at %s (leader %s) recruit_ok=%s" % [w.sp, w.pos, dungeon.fs.leader.pos, w.recruit_ok])
				return w
			var orig := int(DB.species["0019"].recruit)
			# a) no Friend Area: never joins
			var w1: Mon = setup.call("0019", false, 999)
			var sp1 := w1.sp
			DB.species[sp1].recruit = 999
			Game.friend_areas.erase(Services.area_of(sp1))
			w1.hp = 1
			var r1: bool = await d.try_recruit(L, w1)
			check.call("joins without its Friend Area", r1, false)
			# b) Friend Area owned, rate certain: joins, and is in the team
			Game.friend_areas.append(Services.area_of(sp1))
			var r2: bool = await d.try_recruit(L, w1)
			check.call("joins with its Friend Area", r2, true)
			check.call("joined Pokémon is on the team", w1.is_team(), true)
			# c) full team: no more joins
			var p3 := Vector2i(-1, -1)
			for dv in DB.DIRS:
				if d.fs.walkable(L.pos + dv, null) and d.fs.mon_at(L.pos + dv) == null:
					p3 = L.pos + dv
					break
			var w3: Mon = d._spawn_wild(p3)
			DB.species[w3.sp].recruit = 999
			Game.friend_areas.append(Services.area_of(w3.sp))
			while d.fs.team().size() < Services.PARTY_MAX:
				var extra: Mon = DB.make_mon("0019", 5, "team")
				d.fs.mons.append(extra)
			var r3: bool = await d.try_recruit(L, w3)
			check.call("joins when the team is full", r3, false)
			# d) the roll: rate 100 at Lv5 joins about 10% of the time
			DB.species[sp1].recruit = 100
			var hits := 0
			for i in 4000:
				if d.fs.rng.randi_range(0, 999) < d.recruit_rate(L, w3) - int(DB.species[w3.sp].recruit) + 100:
					hits += 1
			print("RECRUITTEST roll: rate 100 -> %.1f%% (Red: 10%%)" % [hits / 40.0])
			# e) kept only when the team gets home
			var friends0 := Game.friends.size()
			d._end("cleared")
			await get_tree().create_timer(0.5).timeout
			check.call("recruit kept after clearing", Game.friends.size() - friends0 >= 1, true)
			DB.species["0019"].recruit = orig
			# f) a lost expedition loses its recruit (Red keeps recruits only when you get home)
			await start_dungeon("thunderwave_cave")
			await get_tree().create_timer(2.0).timeout
			d = dungeon
			d.auto_answer = true
			L = d.fs.leader
			var w5: Mon = setup.call("0019", true, 999)
			DB.species[w5.sp].recruit = 999
			if not Services.has_area_for(w5.sp):
				Game.friend_areas.append(Services.area_of(w5.sp))
			var n5 := Game.friends.filter(func(f): return str(f.sp) == w5.sp).size()
			var r5: bool = await d.try_recruit(L, w5)
			d._end("defeated")
			await get_tree().create_timer(0.5).timeout
			check.call("recruit lost when the team faints", r5 and Game.friends.filter(func(f): return str(f.sp) == w5.sp).size() == n5, true)
			# h) DX recruiting: joins for the dungeon from 2 tiles without a Friend Area; choice at the exit
			Game.settings["qol_recruit"] = 1
			await start_dungeon("thunderwave_cave")
			await get_tree().create_timer(2.0).timeout
			d = dungeon
			d.auto_answer = true
			L = d.fs.leader
			var spawn_at := func(dist: int, sp: String, area: bool) -> Mon:
				var dd: Dungeon = dungeon
				var LL: Mon = dd.fs.leader
				for m in dd.fs.mons.duplicate():
					if not m.is_team():
						if m.visual: m.visual.queue_free()
						dd.fs.mons.erase(m)
				var p := Vector2i(-1, -1)
				for dv in DB.DIRS:
					var q: Vector2i = LL.pos + dv * dist
					var mid: Vector2i = LL.pos + dv
					if dd.fs.walkable(q, null) and dd.fs.mon_at(q) == null and dd.fs.walkable(mid, null) and dd.fs.can_see(LL, q):
						p = q
						break
				if p.x < 0:
					return null
				var w: Mon = dd._spawn_wild(p)
				w.sp = sp
				w.recruit_ok = true
				DB.species[sp].recruit = 999
				Game.friend_areas.erase(Services.area_of(sp))
				if area: Game.friend_areas.append(Services.area_of(sp))
				return w
			var areas_keep: Array = Game.friend_areas.duplicate()
			Game.friend_areas.clear()
			var w0: Mon = spawn_at.call(1, "0019", false)
			Game.friend_areas.clear()
			if w0: check.call("DX: no recruiting before the first Friend Area", await d.try_recruit(L, w0), false)
			Game.friend_areas.append_array(areas_keep)
			var money0 := Game.money
			var f0 := Game.friends.size()
			var wx: Mon = spawn_at.call(3, "0019", false)
			if wx: check.call("DX: no join from 3 tiles", await d.try_recruit(L, wx), false)
			var wn: Mon = spawn_at.call(1, "0016", false)
			if wn: check.call("DX: no join without its Friend Area", await d.try_recruit(L, wn), false)
			var wa: Mon = spawn_at.call(2, "0016", true)
			var ra: bool = wa != null and await d.try_recruit(L, wa)
			check.call("DX: joins from 2 tiles with its Friend Area", ra, true)
			check.call("DX: it's a temporary member", ra and wa.is_team() and Dungeon.is_temp(wa), true)
			if ra:
				var e0 := wa.exp
				await d._give_ko_exp([wa], DB.make_mon("0019", 20, "enemy"))
				check.call("DX: temporary members gain no Exp.", wa.exp, e0)
				check.call("DX: temporary members can't hold items", d._cant_hold(wa), true)
			var wb: Mon = spawn_at.call(1, "0019", true)
			var sp_b := wb.sp if wb else ""
			var rb: bool = wb != null and await d.try_recruit(L, wb)
			check.call("DX: second temporary member", rb, true)
			while d.fs.team().size() < Dungeon.DX_TEAM_MAX:
				var extra2: Mon = DB.make_mon("0019", 5, "team")
				d.fs.mons.append(extra2)
			var wc: Mon = spawn_at.call(1, "0019", true)
			if wc: check.call("DX: no join with 8 on the team", await d.try_recruit(L, wc), false)
			var nb := Game.friends.filter(func(f): return str(f.sp) == sp_b).size()
			d._end("cleared")
			await get_tree().create_timer(1.0).timeout
			check.call("DX: both temporary members stay (answered yes)", Game.friends.size() - f0, 2)
			check.call("DX: ...including the right one", Game.friends.filter(func(f): return str(f.sp) == sp_b).size(), nb + 1)
			# lost expedition: temporary members don't stay
			await start_dungeon("thunderwave_cave")
			await get_tree().create_timer(2.0).timeout
			d = dungeon
			d.auto_answer = true
			L = d.fs.leader
			var wd: Mon = spawn_at.call(1, "0019", true)
			var f1 := Game.friends.size()
			var rd: bool = wd != null and await d.try_recruit(L, wd)
			d._end("defeated")
			await get_tree().create_timer(0.5).timeout
			check.call("DX: temporary member lost when the team faints", rd and Game.friends.size() == f1, true)
			Game.settings["qol_recruit"] = 0
			GData.load_all()
			# g) story joins: Latios (special 0x25) unlocks his Friend Area; the base visitor (0x29 / 0x2C)
			var ts := GDScript.new()
			ts.source_code = "extends RefCounted\nvar name_buffer := \"\"\nvar friend_area_name := \"\"\nvar names := [\"\", \"\", \"\", \"\"]\n"
			ts.reload()
			var gs := GDScript.new()
			gs.source_code = "extends RefCounted\nvar text\n"
			gs.reload()
			var G = gs.new()
			G.text = ts.new()
			Game.friend_areas.erase(Services.area_of("0381"))
			G.text.name_buffer = "Latios"
			Story.special_func(G, null, 0x25, 0, 0)
			check.call("Latios joins through the story", Story._has_mon("0381"), true)
			check.call("Latios's Friend Area unlocked", Services.has_area_for("0381"), true)
			var res29: int = Story.special_func(G, null, 0x29, 0, 0)
			var vsp := GData.species_of_red(GVars.get_val(null, GVars.NEW_FRIEND_KIND))
			check.call("a visitor is chosen (0x29)", res29 in [1, 2] and vsp != "", true)
			G.text.name_buffer = ""
			var had := Story._has_mon(vsp)
			Story.special_func(G, null, 0x2C, 1, 0)
			check.call("the visitor joins (0x2C) and its area opens", Story._has_mon(vsp) and Services.has_area_for(vsp) and not had, true)
			print("RECRUITTEST visitor was %s (%s), area %s" % [vsp, DB.species.get(vsp, {}).get("name", "?"), Services.area_of(vsp)])
			print("RECRUITTEST summary ok=%d bad=%d" % [tally.ok, tally.bad])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--touchaudit"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			await get_tree().create_timer(0.5).timeout
			var click := func(ctrl: Control, at: Vector2, down: bool):
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = down
				ev.position = at
				ev.global_position = ctrl.get_global_transform() * at
				ctrl.gui_input.emit(ev)
			var find_btn := func(n: Node, txt: String) -> Button:
				var st := [n]
				while not st.is_empty():
					var x: Node = st.pop_back()
					if x is Button and (x as Button).text == txt and (x as Button).is_visible_in_tree():
						return x
					st.append_array(x.get_children())
				return null
			# 1. ListMenu: a release with no press on the backdrop (the finger that opened it) is ignored
			var lm := ListMenu.make("Test", ["One", "Two"])
			root.add_child(lm)
			var r1 := {"v": -9}
			var go := func(): r1.v = await lm.choose()
			go.call()
			await get_tree().process_frame
			await get_tree().process_frame
			var bd: Control = lm._backdrop
			click.call(bd, Vector2(5, 5), false)
			await get_tree().process_frame
			var survived: bool = r1.v == -9
			click.call(bd, Vector2(5, 5), true)
			click.call(bd, Vector2(5, 5), false)
			await get_tree().create_timer(0.2).timeout
			print("TOUCHAUDIT listmenu: stray release ignored=%s, tap outside cancels=%s" % [survived, r1.v == -1])
			# 2. Number picker: tap outside cancels
			var r2 := {"v": -9}
			var go2 := func(): r2.v = await RedShops.pick_number(root, "How much?", 500)
			ListMenu.auto = false
			go2.call()
			await get_tree().create_timer(0.3).timeout
			var bd2: Control = null
			for c in root.get_children():
				if c is Control and c.get_class() == "Control" and c.mouse_filter == Control.MOUSE_FILTER_STOP:
					bd2 = c
			if bd2:
				click.call(bd2, Vector2(5, 5), true)
				click.call(bd2, Vector2(5, 5), false)
			await get_tree().create_timer(0.2).timeout
			print("TOUCHAUDIT number picker: tap outside cancels=%s" % [r2.v == -1])
			# 3. Wonder Mail pick list: Back
			var r3 := {"v": 1, "done": false}
			var go3 := func():
				r3.v = await WonderMailUI._pick(root, "Pick", [{"text": "A", "value": 1}, {"text": "B", "value": 2}])
				r3.done = true
			go3.call()
			await get_tree().create_timer(0.3).timeout
			var b3: Button = find_btn.call(root, "Back")
			if b3: b3.pressed.emit()
			await get_tree().create_timer(0.2).timeout
			print("TOUCHAUDIT wonder mail list: back=%s closed=%s value=%s" % [b3 != null, r3.done, r3.v])
			# 4. Wonder Mail code page: Done
			var r4 := {"v": "", "done": false}
			var go4 := func():
				r4.v = await WonderMailUI._show_result(root, {})
				r4.done = true
			go4.call()
			await get_tree().create_timer(0.4).timeout
			var b4: Button = find_btn.call(root, "Done")
			if b4: b4.pressed.emit()
			await get_tree().create_timer(0.2).timeout
			print("TOUCHAUDIT wonder mail code page: done=%s closed=%s out=%s" % [b4 != null, r4.done, r4.v])
			# 5. dungeon: Moves screen shift buttons, pad run, tap own tile to turn
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(2.0).timeout
			var d := dungeon
			var L: Mon = d.fs.leader
			var names0 := (TeamScreens.moves_of(L) as Array).map(func(mv): return str(mv.name))
			var go5 := func(): await d.open_moves()
			go5.call()
			await get_tree().create_timer(0.4).timeout
			var mm = TeamScreens._stack.back()
			mm._finish({"act": "shift_down"})
			await get_tree().create_timer(0.3).timeout
			var names1 := (TeamScreens.moves_of(L) as Array).map(func(mv): return str(mv.name))
			mm = TeamScreens._stack.back()
			mm._finish({"act": "cancel"})
			await get_tree().create_timer(0.3).timeout
			print("TOUCHAUDIT moves shift: before=%s after=%s" % [names0, names1])
			var f0 := L.facing
			d.qol.tap(d.qol.tile_to_screen(L.pos))
			await get_tree().create_timer(0.2).timeout
			print("TOUCHAUDIT tap own tile turns: %s (%d -> %d)" % [L.facing != f0, f0, L.facing])
			_qclear()
			var cor := _qcorridor(7)
			if not cor.is_empty():
				_qplace(L, cor[0])
				await get_tree().create_timer(0.3).timeout
				var p0 := L.pos
				d.hud.pad_dir = int(cor[1])
				d.hud.pad_run = true
				await get_tree().create_timer(0.15).timeout
				d.hud.pad_dir = -1
				d.hud.pad_run = false
				await get_tree().create_timer(2.0).timeout
				print("TOUCHAUDIT pad run: moved %d tiles from one push" % [FloorState.cheb(p0, L.pos)])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--backtest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Game.friend_areas = ["beauplains"]
			await get_tree().create_timer(0.5).timeout
			var find_back := func(n: Node) -> Button:
				var st := [n]
				while not st.is_empty():
					var x: Node = st.pop_back()
					if x is Button and (x as Button).text == "Back" and (x as Button).is_visible_in_tree():
						return x
					st.append_array(x.get_children())
				return null
			# job board
			var res := {"done": false}
			var go1 := func():
				res.v = await Board.open_board(root)
				res.done = true
			go1.call()
			await get_tree().create_timer(0.1).timeout
			print("BACKTEST dbg done=%s kids=%s" % [res.done, root.get_children().map(func(c): return c.get_class() + ":" + str(c.name))])
			await get_tree().create_timer(0.5).timeout
			var btns := []
			var st0 := [root]
			while not st0.is_empty():
				var x0: Node = st0.pop_back()
				if x0 is Button:
					btns.append("%s vis=%s" % [(x0 as Button).text, (x0 as Button).is_visible_in_tree()])
				st0.append_array(x0.get_children())
			print("BACKTEST dbg2 done=%s buttons=%s" % [res.done, btns])
			var b: Button = find_back.call(root)
			var had_b := b != null
			if b: b.pressed.emit()
			await get_tree().create_timer(0.4).timeout
			print("BACKTEST board: back=%s closed=%s" % [had_b, res.done])
			# Pokédex list
			var res2 := {"done": false}
			var go2 := func():
				await PokedexUI.browse(root, DB.species.keys().slice(0, 30), "All")
				res2.done = true
			go2.call()
			await get_tree().create_timer(0.6).timeout
			var b2: Button = find_back.call(root)
			var had_b2 := b2 != null
			if b2: b2.pressed.emit()
			await get_tree().create_timer(0.4).timeout
			print("BACKTEST pokedex: back=%s closed=%s" % [had_b2, res2.done])
			# Friend Area map
			var res3 := {"done": false}
			var go3 := func():
				res3.v = await WorldMap.friend_areas(root, "")
				res3.done = true
			go3.call()
			await get_tree().create_timer(3.0).timeout
			var b3: Button = find_back.call(root)
			var had_b3 := b3 != null
			if b3: b3.pressed.emit()
			await get_tree().create_timer(3.0).timeout
			print("BACKTEST friend map: back=%s closed=%s result='%s'" % [had_b3, res3.done, res3.get("v", "?")])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--clearmarkshot"):
		(func():
			GData.load_all()
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Game.settings["qol_clearmark"] = true
			Game.cleared = ["tiny_woods", "thunderwave_cave", "mt_steel", "eos_beach_cave", "eos_drenched_bluff"]
			Game.jobs.append({"id": "t1", "dungeon": "mt_steel", "floor": 3, "state": "taken", "kind": "rescue"})
			var ui := CanvasLayer.new()
			add_child(ui)
			var r0 := Control.new()
			r0.set_anchors_preset(Control.PRESET_FULL_RECT)
			ui.add_child(r0)
			var rid := func(n): return GData.rescue_id("RESCUE_DUNGEON_" + n)
			DungeonList.pick(r0, ["Tiny Woods", "Thunderwave Cave", "Mt. Steel", "Sinister Woods", "Explorers of Sky dungeons (4)"],
				[rid.call("TINY_WOODS"), rid.call("THUNDERWAVE_CAVE"), rid.call("MT_STEEL"), rid.call("SINISTER_WOODS"), -100])
			await get_tree().create_timer(0.6).timeout
			get_viewport().get_texture().get_image().save_png("user://clear_a.png")
			for c in r0.get_children(): c.queue_free()
			var ek := ["eos_beach_cave", "eos_drenched_bluff", "eos_mt_bristle", "eos_waterfall_cave"]
			DungeonList.pick(r0, ["Beach Cave  [Lv 1]", "Drenched Bluff  [Lv 2]", "Mt. Bristle  [Lv 4]", "Waterfall Cave  [Lv 6]"], [-1, -1, -1, -1], "Explorers of Sky", ["", "", "ENVELOPE_OPEN", ""], ek)
			await get_tree().create_timer(0.6).timeout
			get_viewport().get_texture().get_image().save_png("user://clear_b.png")
			for c in r0.get_children(): c.queue_free()
			WorldMap.force_visible = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm"]
			WorldMap.trip_red(r0, "sinister_woods")
			await get_tree().create_timer(2.0).timeout
			get_viewport().get_texture().get_image().save_png("user://clear_c.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--debugnpctest"):
		(func():
			Game.load_game()
			Game.settings["qol_debugnpc"] = true
			continue_story()
			for i in 60:
				await get_tree().create_timer(0.5).timeout
				if is_instance_valid(ground) and ground.lives[0].kind_id != -1 and ground.vis_map >= 0 and i > 6:
					break
			ground.select_map(GData.map_id("MAP_TEAM_BASE"), true)
			ground.lives_select(0, 1)
			var dk := -1
			for i in ground.N_LIVES:
				if ground.lives[i].kind_id == GData.debug_kind:
					dk = i
			print("DEBUGNPC map=%d slot=%d" % [ground.vis_map, dk])
			if dk >= 0:
				ground.camera.follow(1, dk)
			await get_tree().create_timer(1.2).timeout
			get_viewport().get_texture().get_image().save_png("user://debugnpc_base.png")
			print("DEBUGNPC flags: ", DebugNpc.flags_text().replace("\n", " | "))
			DebugNpc.jump_to(7)
			print("DEBUGNPC after jump 7: ", DebugNpc.flags_text().replace("\n", " | "), " cleared=", Game.cleared.slice(0, 8))
			print("DEBUGNPC side story mankey: ", DebugNpc.run_setup_script("s_script_EVENT_S01E01A_START"), " ", DebugNpc.flags_text().replace("\n", " | "))
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--basekindtest"):
		(func():
			Game.load_game()
			GData.load_all()
			print("BASEKIND before=%d hero=%s" % [GVars.get_val(null, GVars.BASE_KIND), Story.hero_species()])
			Story.sync_base_kind()
			print("BASEKIND after=%d talk=%d" % [GVars.get_val(null, GVars.BASE_KIND), GVars.get_val(null, GVars.PARTNER_TALK_KIND)])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--eoslisttest"):
		(func():
			Game.load_game()
			GData.load_all()
			print("EOSLIST scen=%s post=%s team=%s" % [str(GVars.scenario(GVars.SCENARIO_MAIN)), GVars.after(GVars.SCENARIO_MAIN, 17, -1), str(Game.team.map(func(e): return int(e.level)))])
			var L := Story.eos_unlocked()
			print("EOSLIST %d: %s" % [L.size(), str(L.filter(func(k): return k.contains("zero") or k.contains("destiny")))])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--fatest3"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			GData.load_all()
			Game.friend_areas = ["wildplains", "boulderquarry"]
			var res := ["?"]
			var run := func():
				res[0] = await WorldMap.friend_areas(root, "")
			run.call()
			var press := func(act: String):
				var ev := InputEventAction.new()
				ev.action = act
				ev.pressed = true
				Input.parse_input_event(ev)
				await get_tree().create_timer(0.1).timeout
				var ev2 := InputEventAction.new()
				ev2.action = act
				ev2.pressed = false
				Input.parse_input_event(ev2)
			await get_tree().create_timer(2.0).timeout
			get_viewport().get_texture().get_image().save_png("user://fa3_a.png")
			await press.call("ui_accept")
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png("user://fa3_b.png")
			await press.call("ui_accept")
			for w in 20:
				await get_tree().create_timer(0.5).timeout
				print("FATEST3 t=%.1f res=%s" % [w * 0.5, str(res[0])])
				if str(res[0]) != "?": break
			print("FATEST3 result=%s map=%d" % [str(res[0]), Story.map_of_fa_key(str(res[0]))])
			get_viewport().get_texture().get_image().save_png("user://fa3_c.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--fatest2"):
		(func():
			Game.load_game()
			GData.load_all()
			var m := Story.map_of_fa_key("wildplains")
			if not "wildplains" in Game.friend_areas:
				Game.friend_areas.append("wildplains")
			print("FATEST2 wild plains map=%d fa=%d unlocked=%s areas=%s" % [m, GData.fa_of_map(m), Story.friend_area_unlocked(GData.fa_of_map(m)), str(Game.friend_areas)])
			GVars.set_val(null, GVars.GROUND_ENTER, m)
			GVars.set_val(null, GVars.GROUND_ENTER_LINK, 0)
			Dialog.auto = true
			start_story(Ground.STARTMODE_GROUND)
			for i in 30:
				await get_tree().create_timer(0.5).timeout
				if is_instance_valid(ground) and ground.vis_map >= 0 and i > 6:
					break
			print("FATEST2 now vis_map=%d cur_map=%d lives0=%d genter=%d" % [ground.vis_map, ground.cur_map, ground.lives[0].kind_id, GVars.get_val(null, GVars.GROUND_ENTER)])
			get_viewport().get_texture().get_image().save_png("user://fatest2.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--fatest"):
		(func():
			GData.load_all()
			var bad := []
			var n := 0
			var wm_keys := []
			for L in WorldMap.data().get("friend_locations", []):
				for k in L.get("keys", []):
					if str(k) != "":
						wm_keys.append(str(k))
			for k in wm_keys:
				n += 1
				var m := Story.map_of_fa_key(k)
				if m < 0:
					bad.append(k)
			print("FATEST map keys=%d unmapped=%s" % [n, str(bad)])
			var fa_keys: Array = []
			for v in GData.extra.enums.friend_areas:
				fa_keys.append(Story.fa_key(int(v)))
			print("FATEST enum keys sample=%s" % str(fa_keys.slice(0, 12)))
			print("FATEST map keys sample=%s" % str(wm_keys.slice(0, 12)))
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--mgtest"):
		(func():
			Dialog.auto = true
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Dungeon.test_invincible = true
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(0.5).timeout
			var L: Mon = dungeon.fs.leader
			var mi := 0
			for k in L.moves.size():
				if MoveGrowth.grows(str(L.moves[k].name)):
					mi = k
					break
			var mvn := str(L.moves[mi].name)
			for mv0 in L.moves:
				print("MGTEST move ", mv0.name, " grows=", MoveGrowth.grows(str(mv0.name)), " pp ", mv0.pp, "/", mv0.max_pp)
			var base: Dictionary = DB.moves[mvn]
			print("MGTEST %s base p=%d a1=%s info0=%s" % [mvn, int(base.p), str(base.get("a1")), str(MoveGrowth.info(mvn))])
			var foe: Mon = null
			for x in dungeon.fs.mons:
				if not x.is_team():
					foe = x
					break
			for i in 40:
				if foe:
					foe.pos = L.pos + Vector2i(1, 0)
					foe.hp = foe.max_hp
				L.moves[mi].pp = 30
				await dungeon.do_attack(L, mvn, 2)
			print("MGTEST after 40 uses: exp=%d info=%s slot pp=%d/%d mg_pp=%s" % [MoveGrowth.exp_of(mvn), str(MoveGrowth.info(mvn)), int(L.moves[mi].pp), int(L.moves[mi].max_pp), str(L.moves[mi].get("mg_pp"))])
			var ap := MoveGrowth.apply(L, mvn, base)
			print("MGTEST applied p=%d a1=%s (base p=%d)" % [int(ap.p), str(ap.get("a1")), int(base.p)])
			await dungeon._item_effect(L, L, "ginseng", false)
			print("MGTEST after ginseng: exp=%d info=%s" % [MoveGrowth.exp_of(mvn), str(MoveGrowth.info(mvn))])
			Game.flags.move_exp[mvn] = 99999
			MoveGrowth.sync_all(dungeon)
			print("MGTEST maxed: info=%s slot pp=%d/%d" % [str(MoveGrowth.info(mvn)), int(L.moves[mi].pp), int(L.moves[mi].max_pp)])
			Game.settings.qol_movegrowth = false
			MoveGrowth.sync_all(dungeon)
			print("MGTEST off: slot pp=%d/%d applied p=%d" % [int(L.moves[mi].pp), int(L.moves[mi].max_pp), int(MoveGrowth.apply(L, mvn, base).p)])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--hardlist"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			for hard in [false, true]:
				Difficulty.set_hard(hard)
				for k in ["tiny_woods", "mt_steel", "sinister_woods", "magma_cavern", "sky_tower_summit", "uproar_forest", "wish_cave", "eos_zero_isle_east"]:
					print("HARDLIST hard=%s %s rec %d range %s" % [hard, k, Pokedex.recommended_level(k), str(Pokedex.level_range(k))])
			for k in ["tiny_woods", "eos_beach_cave", "eos_beach_cave_pit", "eos_dusk_forest", "eos_star_cave", "eos_zero_isle_east", "eos_zero_isle_north", "eos_destiny_tower", "eos_deep_concealed_ruins", "eos_regice_chamber"]:
				print("RECRUIT %s %s" % [k, Dungeon.can_recruit_in(k)])
			for l in Pokedex.locations("0004"):
				print("DEXLOC %s known=%s hard=%s red=%d-%d" % [l.dkey, Pokedex.dungeon_known(str(l.dkey)), str(Difficulty.species_levels(str(l.dkey), "0004")), l.lv_min, l.lv_max])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--hardtest"):
		(func():
			Dialog.auto = true
			var cases := [["tiny_woods", 0], ["mt_steel", 0], ["mt_steel", 8], ["sinister_woods", 12], ["silent_chasm", 0],
				["mt_thunder_peak", 2], ["magma_cavern", 22], ["magma_cavern_pit", 2], ["sky_tower_summit", 0], ["sky_tower_summit", 8],
				["uproar_forest", 0], ["wish_cave", 0], ["wish_cave", 98], ["northern_range", 10], ["eos_zero_isle_east", 0]]
			for lvl in [20, 60]:
				Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
				Difficulty.set_hard(true)
				for e in Game.team:
					e.level = lvl
					e.exp = DB.exp_at(str(e.sp), lvl)
				Dungeon.test_invincible = true
				for c in cases:
					if not DB.dungeons.dungeons.has(c[0]):
						print("HARDTEST missing ", c[0])
						continue
					await start_dungeon(c[0], c[1])
					await get_tree().create_timer(0.2).timeout
					var wl := []
					for m in dungeon.fs.mons:
						if not m.is_team() and m.side != "client":
							wl.append("%s%d%s" % [m.name.substr(0, 5), m.level, "*" if m.has_meta("boss") or m.has_meta("behavior") else ""])
					print("HARDTEST team=%d %s F%d target=%d: %s" % [lvl, c[0], int(c[1]) + 1, Difficulty.floor_target(dungeon), " ".join(wl)])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--linktest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Test")
			var z: Dictionary = Game._entry("0041", "Zubat", 8)
			z["area"] = "x"
			Game.friends.append(z)
			Game.team.append(z)                 # Zubat on the team and living in its area (shared dict)
			Game.save_game(true)
			Game.load_game()                    # old split: team Zubat and area Zubat are now two dicts
			Game.team[2].exp = int(Game.team[2].exp) + 500
			Game.team.append(Game.friends[Game.friends.size() - 1])   # the "clone": stale area copy added again
			var z2: Dictionary = Game._entry("0041", "Zubat", 3)   # a second, real Zubat in the area (different moves)
			z2["area"] = "x"
			z2.moves = [{"name": "Supersonic", "pp": 20, "max_pp": 20, "linked": false, "on": true}]
			Game.friends.push_front(z2)
			var sz: Dictionary = Game._entry("0145", "Zapdos", 40)
			sz["area"] = "y"
			Game.team.append(sz)
			var sz2: Dictionary = Game._entry("0145", "Zapdos", 30)
			sz2["area"] = "y"
			sz2["shiny"] = true
			Game.friends.append(sz2)
			for e in Game.team + Game.friends:
				e.erase("uid")                  # pretend it's a save from before ids
			Game.save_game(true)
			Game.load_game()
			var names := []
			for e in Game.team:
				names.append("%s:%d" % [e.name, int(e.exp)])
			var fn := []
			for e in Game.friends:
				fn.append("%s:%d same=%s" % [e.name, int(e.exp), str(Game.team.any(func(t): return is_same(t, e)))])
			print("LINKTEST team=", names, " friends=", fn)
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--autosavetest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Game.money = 100
			Game.save_game(true)
			Game.settings["qol_autosave"] = false
			Game.money = 999
			Game.settings["msg_speed"] = 2
			Game.save_game()
			var d = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
			var ok1: bool = int(d.money) == 100 and int(d.settings.msg_speed) == 2 and not bool(d.settings.qol_autosave)
			Game.save_game(true)
			d = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
			var ok2: bool = int(d.money) == 999
			print("AUTOSAVETEST %s off-keeps-progress+saves-settings=%s explicit-save=%s" % ["ok" if ok1 and ok2 else "BAD", ok1, ok2])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--swapshot"):
		(func():
			Game.load_game()
			Game.settings["second_screen"] = "window"
			BottomScreen.instance.refresh_mode()
			continue_story()
			for i in 60:
				await get_tree().create_timer(0.5).timeout
				if is_instance_valid(ground) and ground.lives[0].kind_id != -1 and ground.vis_map >= 0 and i > 6:
					break
			var ids := {}
			for k in DB.items:
				ids[str(DB.items[k].get("name", ""))] = k
			Game.bag_add(ids["Bulba-Claw"])
			Game.bag_add(ids["Bulba-Fang"])
			Game.money = max(Game.money, 500)
			ground.select_map(SwapShop.MAP, true)
			ground.lives_select_map(SwapShop.MAP, 1, 0)
			var ck := -1
			for i in ground.N_LIVES:
				if ground.lives[i].kind_id == GData.croagunk_kind:
					ck = i
			if ground.lives[0].kind_id == -1:
				ground.lives_add(-1, {"kind": 0, "u1": 4, "pos": [50, 38, 0, 2], "scripts": [null, null, null, null]}, 0, 0)
			var L = ground.lives[0]
			var c: Vector2i = ground.lives[ck].get_center() + Vector2i(0, 16 << 8)
			L.p144 = c - L.half
			L.p14C = c + L.half
			L.direction1 = 4
			L.dir_dirty = true
			await get_tree().create_timer(0.8).timeout
			print("SWAPSHOT lives0=", ground.lives[0].kind_id, " ck=", ck)
			print("SWAPSHOT talk=", ground.lives_player_talk(0, ck))
			await get_tree().create_timer(1.5).timeout
			get_viewport().get_texture().get_image().save_png("user://swap_a.png")
			# a Swap list with the cursor on an exclusive item: the second screen shows its info
			var rows: Array = []
			for nm in ["Grass-Guard", "Leafy Tie", "Flash Tag"]:
				rows.append({"text": "%s %s" % [nm, SwapShop.star_text(ids[nm])], "icon": TeamScreens.item_icon(ids[nm]), "item": ids[nm], "right": "Set"})
			var m := TeamScreens.menu("Swap", rows, 22 * 8 * UITheme.PX)
			m.sel = 1
			TeamScreens.run_menu(ground.ui_root, m, Vector2(2 * 8 * UITheme.PX, 2 * 8 * UITheme.PX))
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png("user://swap_b.png")
			BottomScreen.instance.screenshot(OS.get_user_data_dir() + "/swap_bottom.png")
			TeamScreens.item_info(ground.ui_root, ids["Leafy Tie"])
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png("user://swap_c.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--swaptest"):
		(func():
			Game.new_game("0001", "Bulbasaur", "0004", "Charmander", "Q")
			Game.money = 1000
			var ids := {}
			for k in DB.items:
				ids[str(DB.items[k].get("name", ""))] = k
			Game.bag_add(ids["Bulba-Claw"])
			Game.bag_add(ids["Bulba-Fang"])
			Game.storage[ids["Shinx Claw"]] = 2
			Game.storage[ids["Sky Silk"]] = 1
			var res := []
			var st := SwapShop.stock()
			res.append(["stock has Grass-Guard (set owned)", ids["Grass-Guard"] in st])
			res.append(["stock size >= 8", st.size() >= 8])
			var team_ok := 0
			for id in st.slice(0, 8):
				for e in Game.team:
					if SwapShop.usable_by(e, id):
						team_ok += 1
						break
			res.append(["most of the daily stock fits the team (%d/8)" % team_ok, team_ok >= 4])
			res.append(["owned counts storage (5)", SwapShop.owned().size() == 5])
			Dialog.auto = true
			ListMenu.auto = true
			var own := SwapShop.owned()
			var give := own.filter(func(o): return o.id in [ids["Bulba-Claw"], ids["Bulba-Fang"]])
			await SwapShop._do_swap(root, ids["Grass-Guard"], give)
			res.append(["got Grass-Guard", Game.bag.any(func(b): return str(b.id) == ids["Grass-Guard"])])
			res.append(["set used up", not Game.bag.any(func(b): return str(b.id) == ids["Bulba-Claw"])])
			res.append(["fee paid (850)", Game.money == 850])
			# generic: 2 storage items for a 1-star
			var own2 := SwapShop.owned().filter(func(o): return o.where == "storage").slice(0, 2)
			await SwapShop._do_swap(root, ids["Vulpix Tail"] if ids.has("Vulpix Tail") else ids["Shinx Fang"], own2)
			res.append(["storage items taken", int(Game.storage.get(ids["Shinx Claw"], 0)) + int(Game.storage.get(ids["Sky Silk"], 0)) == 1])
			var d := TeamScreens.item_desc(ids["Leafy Tie"])
			print("SWAPTEST desc: ", d.substr(0, 400))
			res.append(["star marks in the info text", d.contains("STAR") or d.contains("glyphs.png")])
			var bad := 0
			for r in res:
				print("SWAPTEST %s  %s" % ["ok " if r[1] else "BAD", r[0]])
				if not r[1]: bad += 1
			print("SWAPTEST summary ok=%d bad=%d" % [res.size() - bad, bad])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--croashot"):
		(func():
			var spots: Array = []
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--spots="):
					for sp in a.substr(8).split(";"):
						var xy := sp.split(",")
						spots.append([int(xy[0]), int(xy[1]), 0, 2])
			Game.load_game()
			continue_story()
			for i in 60:
				await get_tree().create_timer(0.5).timeout
				if is_instance_valid(ground) and ground.lives[0].kind_id != -1 and ground.vis_map >= 0 and i > 6:
					break
			for k in spots.size():
				SwapShop.spot_override = spots[k]
				ground.select_map(SwapShop.MAP, true)
				ground.lives_select_map(SwapShop.MAP, 1, 0)
				var ck := -1
				for i in ground.N_LIVES:
					if ground.lives[i].kind_id == GData.croagunk_kind:
						ck = i
				print("CROASHOT spot=%s croagunk slot=%d" % [str(spots[k]), ck])
				if ck >= 0:
					ground.camera.follow(1, ck)
				await get_tree().create_timer(1.2).timeout
				get_viewport().get_texture().get_image().save_png("user://croashot_%d.png" % k)
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--groundpad"):
		(func():
			Game.load_game()
			continue_story()
			for i in 40:
				await get_tree().create_timer(0.5).timeout
				if is_instance_valid(ground) and ground.lives[0].kind_id != -1 and not ground.text.is_open() and ground.vis_map >= 0 and i > 8:
					break
			var h: Hud = ground.hud
			h.touch_ui = true
			h.set_touch_visible(true)
			for k2 in h._btns:
				if k2 != "attack" and k2 != "menu":
					h._btns[k2].visible = false
			var p0: Vector2i = ground.lives[0].p144
			h.pad_dir = 2                                   # hold right on the pad
			await get_tree().create_timer(1.0).timeout
			h.pad_dir = -1
			await get_tree().create_timer(0.3).timeout
			print("GROUNDPAD map=%d moved=%s (from %s to %s)" % [ground.vis_map, ground.lives[0].p144 != p0, p0 / 2048, ground.lives[0].p144 / 2048])
			h.pad_dir = 4
			await get_tree().create_timer(0.3).timeout
			get_viewport().get_texture().get_image().save_png("user://groundpad.png")
			h.pad_dir = -1
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--marktest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			await get_tree().create_timer(0.5).timeout
			var labels := ["Oran Berry", "Apple", "Pecha Berry", "Sleep Seed", "Blast Seed", "Stick", "Chesto Berry", "Rawst Berry", "Sitrus Berry", "Joy Seed"]
			var marks := {}
			var res := {}
			var run := func():
				res.merge(await RedShops._multi_list(root, "", labels, marks, 0, [], ["oran", "apple", "pecha", "sleepseed", "blastseed", "stick", "chesto", "rawst", "sitrus", "joyseed"]))
			run.call()
			await get_tree().create_timer(0.4).timeout
			var tap := func(ctrl: Control, down: bool):
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = down
				ev.position = ctrl.size / 2.0
				ev.global_position = ctrl.get_global_transform() * ev.position
				ctrl.gui_input.emit(ev)
			var m = _top_mark_menu()
			tap.call(m._rows[2], true)                     # hold row 2
			await get_tree().create_timer(0.7).timeout
			if is_instance_valid(m):
				tap.call(m._rows[2], false)
			await get_tree().create_timer(0.3).timeout
			print("MARKTEST after hold: marks=%s" % [marks.keys()])
			get_viewport().get_texture().get_image().save_png("user://marktest.png")
			m = _top_mark_menu()
			tap.call(m._rows[4], true)                     # quick tap row 4: toggles in marking mode
			tap.call(m._rows[4], false)
			await get_tree().create_timer(0.3).timeout
			print("MARKTEST after tap: marks=%s" % [marks.keys()])
			m = _top_mark_menu()
			m._finish({"act": "done"})                     # the Done button
			await get_tree().create_timer(0.3).timeout
			print("MARKTEST result: %s" % [res])
			# sortable list: Select sorts, L still marks
			var marks2 := {}
			var res2 := {}
			var run2 := func():
				res2.merge(await RedShops._multi_list(root, "", labels, marks2, 0, [], [], true))
			run2.call()
			await get_tree().create_timer(0.3).timeout
			var evl := InputEventAction.new()
			evl.action = "gp_l"
			evl.pressed = true
			Input.parse_input_event(evl)
			await get_tree().create_timer(0.3).timeout
			var evu := InputEventAction.new()
			evu.action = "gp_l"
			evu.pressed = false
			Input.parse_input_event(evu)
			await get_tree().create_timer(0.3).timeout
			print("MARKTEST L marks: %s" % [marks2.keys()])
			var evs := InputEventAction.new()
			evs.action = "act_map"
			evs.pressed = true
			Input.parse_input_event(evs)
			await get_tree().create_timer(0.4).timeout
			print("MARKTEST Select gives: %s" % [res2.get("act", "-")])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--bagshot"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			for id in ["oran", "apple", "pecha", "reviverseed", "sleepseed", "blastseed", "gravelrock", "ironthorn", "stick", "chesto", "rawst", "sitrus", "maxelixir", "escapeorb", "warpseed", "heal seed", "joyseed", "geoorb"]:
				if DB.items.has(id):
					Game.bag_add(id)
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(2.0).timeout
			dungeon.open_bag()
			await get_tree().create_timer(1.0).timeout
			get_viewport().get_texture().get_image().save_png("user://bag_dungeon.png")
			var m = TeamScreens._stack.back()
			var tap := func(ctrl: Control, at: Vector2, down: bool):
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = down
				ev.position = at
				ev.global_position = ctrl.get_global_transform() * at
				ctrl.gui_input.emit(ev)
			# swipe up on the list: it should scroll down by a row or more
			var row0: Control = m._rows[3]
			var c := row0.size / 2.0
			tap.call(row0, c, true)
			for k in 6:
				var mv := InputEventMouseMotion.new()
				mv.button_mask = MOUSE_BUTTON_MASK_LEFT
				mv.position = c - Vector2(0, 12 * k)
				mv.global_position = row0.get_global_transform() * (c - Vector2(0, 12 * k))
				row0.gui_input.emit(mv)
			tap.call(row0, c - Vector2(0, 60), false)
			print("BAGTEST after swipe: top=%d finished=%s" % [m.top, m.finished])
			m._scroll_by(5)
			print("BAGTEST after arrow: top=%d (max %d)" % [m.top, m.rows.size() - m.max_rows])
			m._finish({"act": "select"})      # the Sort button's action
			await get_tree().create_timer(0.8).timeout
			print("BAGTEST sorted first=%s" % [Game.bag[0].id])
			var m2 = TeamScreens._stack.back()
			# a tap (press + release, no movement) opens the item's commands
			tap.call(m2._rows[1], m2._rows[1].size / 2.0, true)
			tap.call(m2._rows[1], m2._rows[1].size / 2.0, false)
			print("BAGTEST tap picked: finished=%s act=%s i=%s" % [m2.finished, m2.result.get("act", ""), m2.result.get("i", "")])
			for k in ["set", "star", "sticky", "blank", "heart_r3"]:
				var tx: Texture2D = TeamScreens.icon(k)
				print("BAGTEST icon %s size=%s rom=%s" % [k, tx.get_size() if tx else "null", TeamScreens._rom_icon(k) != null])
			get_tree().quit()).call_deferred()
		return
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
	if OS.get_cmdline_user_args().has("--drawprobe"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(3.0).timeout
			var d := dungeon
			var measure := func(tag: String):
				var t0 := Time.get_ticks_usec()
				for i in 30:
					await get_tree().process_frame
				var ms := (Time.get_ticks_usec() - t0) / 30000.0
				print("DRAWPROBE %-28s %.1f ms/frame  draws=%d objs=%d prims=%d nodes=%d" % [tag, ms, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
			await measure.call("baseline")
			var hide := func(n: Node):
				if n is CanvasItem: n.visible = false
				elif n is CanvasLayer: n.visible = false
			var tops := []
			for c in d.get_children():
				tops.append(c)
			for c in d.get_children():
				print("DRAWPROBE child ", c.name, " ", c.get_class(), " kids=", c.get_child_count())
			for c in tops:
				var was = c.visible if "visible" in c else null
				if was == null: continue
				c.visible = false
				await measure.call("hide " + str(c.name))
				c.visible = was
			for c in root.get_children():
				if c != d and "visible" in c:
					var was2 = c.visible
					c.visible = false
					await measure.call("hide root/" + str(c.name))
					c.visible = was2
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--sleeptest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(1.5).timeout
			var d: Dungeon = dungeon
			d.auto_answer = true
			var L: Mon = d.fs.leader
			L.status["sleep"] = 3
			var t0: int = d.fs.turn
			var e0: int = -1
			var last_move0 := L.last_move
			d.leader_action({"type": "attack", "move": "", "dir": L.facing})
			await get_tree().create_timer(0.5).timeout
			print("SLEEPTEST %s attack while asleep becomes a wait (last move %s)" % ["ok " if L.last_move == last_move0 else "BAD", L.last_move])
			await get_tree().create_timer(3.0).timeout
			print("SLEEPTEST %s turns pass by themselves: %d -> %d, asleep now %d" % ["ok " if d.fs.turn > t0 + 1 else "BAD", t0, d.fs.turn, int(L.status.get("sleep", 0))])
			print("SLEEPTEST log: ", d.hud.log_all.slice(maxi(0, d.hud.log_all.size() - 4)))
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--shoptest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Dungeon.test_invincible = true
			var tally := {"ok": 0, "bad": 0}
			var check := func(what: String, good: bool, info := ""):
				tally["ok" if good else "bad"] += 1
				print("SHOPTEST %s %s %s" % ["ok " if good else "BAD", what, info])
			# 1) real floors make shops with a Kecleon: try floors until one has a shop
			Dialog.auto = true
			var found := false
			var mix := {"red": 0, "eos": 0}
			for key in ["mt_steel", "sinister_woods", "silent_chasm", "mt_thunder", "great_canyon", "lapis_cave", "mt_blaze", "frosty_forest", "mt_freeze", "magma_cavern", "sky_tower", "uproar_forest", "howling_forest", "stormy_sea", "silver_trench", "meteor_cave", "fiery_field", "lightning_field", "northwind_field", "mt_faraway", "western_cave", "northern_range", "pitfall_valley", "buried_relic", "wish_cave", "murky_cave", "desert_region", "southern_cavern", "wyvern_hill", "solar_cave", "darknight_relic", "grand_sea", "waterfall_pond", "unown_relic", "joyous_tower", "far_off_sea", "purity_forest"]:
				if found or not DB.dungeons.dungeons.has(key): continue
				var nfl: int = DB.dungeons.dungeons[key].floors.size()
				for fi in range(0, nfl - 1):
					await start_dungeon(key, fi)
					await get_tree().create_timer(0.3).timeout
					if is_instance_valid(dungeon) and dungeon.shop and dungeon.shop.active():
						found = true
						break
				if found:
					var d0: Dungeon = dungeon
					var k0: Array = d0.shop.keepers()
					check.call("a generated shop has its Kecleon", k0.size() == 1, "%s F%d rect %s" % [key, d0.floor_i + 1, d0.shop.rect()])
					var wares := 0
					for p in d0.fs.items:
						var it: Dictionary = d0.fs.items[p]
						if int(it.get("price", 0)) > 0:
							wares += 1
							mix["eos" if DB.items.get(str(it.id), {}).get("eos_added", 0) else "red"] += 1
					check.call("the shop has priced wares", wares > 0, "%d wares, value %d" % [wares, d0.shop_base])
					if k0.size() > 0:
						check.call("Kecleon is level 90 and won't move", k0[0].level == 90 and AI.decide(k0[0], d0.fs, {}).get("type", "") == "wait")
			print("SHOPTEST ware mix: ", mix)
			if not found:
				check.call("a generated shop was found", false)
			# 2) scripted shop on a known room
			Dialog.auto = false
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(1.0).timeout
			var d: Dungeon = dungeon
			d.auto_answer = true
			var fs: FloorState = d.fs
			var L: Mon = fs.leader
			var room: Rect2i = fs.rooms[0]
			for rr in fs.rooms:
				if rr.get_area() > room.get_area(): room = rr
			for m in fs.mons.duplicate():
				if not m.is_team():
					if m.visual: m.visual.queue_free()
					fs.mons.erase(m)
			fs.items.clear()
			var inner := Rect2i(room.position + Vector2i(1, 1), room.size - Vector2i(2, 2))
			var w1 := inner.position
			var w2 := inner.position + Vector2i(1, 0)
			fs.items[w1] = {"id": "oran", "n": 1, "price": KecleonShop.buy_price("oran", 1)}
			fs.items[w2] = {"id": "pecha", "n": 1, "price": KecleonShop.buy_price("pecha", 1)}
			var gen := {"shop": inner, "kecleon": inner.get_center()}
			d.shop.on_floor_built(gen)
			var k: Mon = d.shop.keepers()[0]
			var outside := Vector2i(room.position.x, room.position.y)
			if inner.has_point(outside): outside = room.position
			L.pos = outside
			d.shop.prev_in_shop = false
			# step in
			L.pos = w1 + Vector2i(0, 1)
			await d.shop.on_leader_step()
			check.call("stepping in: inside the shop", d.shop.prev_in_shop)
			d.obj_layer.queue_redraw()
			if L.visual: L.visual.position = d._px(L.pos)
			await get_tree().create_timer(0.6).timeout
			get_viewport().get_texture().get_image().save_png("user://shop_floor.png")
			check.call("attacks ignore the shopkeeper", not d.fs.is_foe(L, k) and not d.targets_for(L, DB.moves.get("Regular Attack", {"r": "front"}), AI.dir_toward(L.pos, k.pos)).has(k) or FloorState.cheb(L.pos, k.pos) > 1)
			# pick up a ware (unpaid)
			var price1 := int(fs.items[w1].price)
			var lp := L.pos
			L.pos = w1
			await d._after_leader_step_i()          # stepping on a ware picks it up, unpaid (Red)
			L.pos = lp
			check.call("stepping on a ware picks it up unpaid", not fs.items.has(w1) and Game.bag.any(func(b): return str(b.id) == "oran" and int(b.get("price", 0)) == price1))
			check.call("owed after taking a ware", d.shop.owed() == price1, "owed %d" % d.shop.owed())
			# leave own item for sale
			fs.items[w1] = {"id": "apple", "n": 1, "price": 0}
			check.call("offer for a left item", d.shop.offer() == KecleonShop.sell_price("apple", 1), "offer %d" % d.shop.offer())
			# step out with money: sells, then pays
			Game.money = 1000
			var m0 := Game.money
			L.pos = outside
			await d.shop.on_leader_step()
			var bag_paid: bool = Game.bag.filter(func(b): return int(b.get("price", 0)) > 0).is_empty()
			check.call("stepping out: paid and the ware is ours", bag_paid and d.shop.owed() == 0 and not d.shop_stole, "money %d -> %d" % [m0, Game.money])
			check.call("the money adds up", Game.money == m0 + KecleonShop.sell_price("apple", 1) - price1)
			check.call("the left item is now a ware", int(fs.items[w1].get("price", 0)) > 0)
			# take another ware without money: thief
			Game.money = 0
			L.pos = w2 + Vector2i(0, 1)
			await d.shop.on_leader_step()
			Game.bag.append({"id": "pecha", "n": 1, "price": int(fs.items[w2].price)})
			fs.items.erase(w2)
			L.pos = outside
			await d.shop.on_leader_step()
			check.call("no money: thief", d.shop_stole)
			check.call("Kecleon turns hostile", not k.has_meta("shopkeeper"))
			check.call("prices cleared after the theft", Game.bag.filter(func(b): return int(b.get("price", 0)) > 0).is_empty())
			var n0 := fs.mons.filter(func(m): return m.sp == "0352").size()
			for i in 12:
				await d.end_of_turn_i()
			var n1 := fs.mons.filter(func(m): return m.sp == "0352").size()
			check.call("Kecleon keep coming after the thief", n1 > n0, "%d -> %d" % [n0, n1])
			print("SHOPTEST summary ok=%d bad=%d" % [tally.ok, tally.bad])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--partnersoak"):
		(func():
			var key := "mt_steel"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--dungeon="): key = a.substr(10)
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			var size := 3
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--size="): size = int(a.substr(7))
			var extra_sp := ["0025", "0152", "0158", "0133", "0063", "0066"]
			var extra_nm := ["Pikachu", "Chikorita", "Totodile", "Eevee", "Abra", "Machop"]
			while Game.team.size() < mini(size, 4):
				var k2 := Game.team.size() - 2
				Game.team.append(Game._entry(extra_sp[k2], extra_nm[k2], 10))
			for e in Game.team:
				e.level = 20
				e.exp = DB.exp_at(str(e.sp), 20)
			PartnerAI.debug = true
			PartnerAI.stats = {}
			Dungeon.test_invincible = true
			await start_dungeon(key)
			# beyond 4: DX temporary recruits (up to 8), as try_recruit makes them
			for k3 in range(4, mini(size, 8)):
				var t: Mon = DB.make_mon(extra_sp[k3 - 2], 20, "team")
				t.side = "team"
				t.set_meta("recruited", true)
				t.set_meta("temp_recruit", true)
				t.set_meta("tactic", "lets_go_together")
				t.set_meta("entry", {"sp": t.sp, "name": t.name, "level": t.level, "exp": t.exp, "moves": t.moves.duplicate(true), "iq": 0, "held": "", "bonus": {}})
				t.pos = dungeon.fs.free_tile_near(dungeon.fs.leader.pos, null, 4)
				dungeon.fs.mons.append(t)
				dungeon.team_mons.append(t)
				dungeon._add_sprite(t)
			print("PARTNERSOAK team size %d" % dungeon.fs.team().size())
			dungeon.auto_answer = true
			dungeon.set_autoplay(true)
			var t := 0.0
			while t < 240.0 and is_instance_valid(dungeon) and not dungeon.result_sent:
				await get_tree().create_timer(0.5).timeout
				t += 0.5
				if not dungeon.autoplay and not dungeon.result_sent: dungeon.set_autoplay(true)
				if int(t * 2) % 60 == 0:
					for nm in PartnerAI.stats:
						var st0: Dictionary = PartnerAI.stats[nm]
						print("PARTNERSTAT t=%d %s turns=%d avg_dist=%.2f far(>4)=%d%% max_dist=%d longest_still=%d" % [int(t), nm, st0.n, float(st0.d) / maxi(1, st0.n), 100 * st0.far / maxi(1, st0.n), st0.max, st0.still_max])
			print("PARTNERSOAK done t=%.0f floor=%d" % [t, dungeon.floor_i + 1 if is_instance_valid(dungeon) else -1])
			for nm in PartnerAI.stats:
				var st: Dictionary = PartnerAI.stats[nm]
				print("PARTNERSTAT %s turns=%d avg_dist=%.2f far(>4)=%d%% max_dist=%d longest_still=%d" % [nm, st.n, float(st.d) / maxi(1, st.n), 100 * st.far / maxi(1, st.n), st.max, st.still_max])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--msgshot"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(1.5).timeout
			for i in 3:
				Game.settings["qol_msgsize"] = i
				hud.msg("Charmander used [color=#7fe0ff]Scratch[/color]!")
				hud.msg("Pidgey took [color=#ffdc4a]16[/color] damage!")
				await get_tree().create_timer(0.4).timeout
				get_viewport().get_texture().get_image().save_png("user://msg_%d.png" % i)
			Game.settings["qol_msgsize"] = 0
			dungeon.open_log()
			await get_tree().create_timer(0.6).timeout
			get_viewport().get_texture().get_image().save_png("user://msg_log_small.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--heldstacktest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			await start_dungeon("tiny_woods")
			await get_tree().create_timer(1.0).timeout
			dungeon.auto_answer = true
			var P: Mon = dungeon.fs.team()[1]
			TeamScreens.set_held(P, "ironthorn", 7)
			print("HELD set: %s x%d entry=%s" % [P.held, P.held_n, str(P.get_meta("entry", {}).get("held_n", "?"))])
			print("HELD name: ", TeamScreens.held_name(P))
			await dungeon.execute(P, {"type": "throw", "held": true, "dir": 0})
			print("HELD after throw: %s x%d" % [P.held, P.held_n])
			var ok1 := P.held == "ironthorn" and P.held_n == 6
			Game.bag.clear()
			Game.bag_add(TeamScreens.held_of(P), TeamScreens.held_n_of(P))
			TeamScreens.set_held(P, "")
			var ok2 := Game.bag.size() == 1 and int(Game.bag[0].n) == 6
			print("HELDSTACK %s throw-one=%s take-all=%s" % ["ok" if ok1 and ok2 else "BAD", ok1, ok2])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--eosmarkshot"):
		(func():
			GData.load_all()
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Game.jobs.append({"id": "t1", "dungeon": "eos_beach_cave", "floor": 2, "state": "taken", "kind": "rescue"})
			print("EOSMARK any=%s beach=%d" % [DungeonList._eos_jobs_any(), DungeonList.jobs_in_key("eos_beach_cave")])
			var ui := CanvasLayer.new()
			add_child(ui)
			var root := Control.new()
			root.set_anchors_preset(Control.PRESET_FULL_RECT)
			ui.add_child(root)
			DungeonList.pick(root, ["Tiny Woods", "Explorers of Sky dungeons (3)"], [0, -100])
			await get_tree().create_timer(0.6).timeout
			get_viewport().get_texture().get_image().save_png("user://eosmark_a.png")
			for c in root.get_children(): c.queue_free()
			DungeonList.pick(root, ["Beach Cave  [Lv 1]", "Drenched Bluff  [Lv 2]"], [-1, -1], "Explorers of Sky", ["ENVELOPE_OPEN", ""])
			await get_tree().create_timer(0.6).timeout
			get_viewport().get_texture().get_image().save_png("user://eosmark_b.png")
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--eosjobtest"):
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			for k in ["tiny_woods", "thunderwave_cave", "mt_steel", "eos_beach_cave", "eos_drenched_bluff", "eos_mt_bristle", "eos_apple_woods", "eos_foggy_forest"]:
				if not k in Game.cleared: Game.cleared.append(k)
				if not k in Game.unlocked: Game.unlocked.append(k)
			print("EOSJOB job dungeons: ", Missions.job_dungeons())
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var counts := {}
			var sample := {}
			for i in 60:
				for j in Missions.make_board(rng):
					counts[j.dungeon] = int(counts.get(j.dungeon, 0)) + 1
					if str(j.dungeon).begins_with("eos_") and not sample.has(j.kind):
						sample[j.kind] = j
			print("EOSJOB counts: ", counts)
			for k in sample:
				var j: Dictionary = sample[k]
				print("EOSJOB sample %s: %s F%d diff=%s reward=%s | %s" % [k, j.dungeon, int(j.floor), j.get("difficulty", "?"), Missions.reward_text(j), str(j.get("title", ""))])
			var eos_n := 0
			for k in counts:
				if str(k).begins_with("eos_"): eos_n += int(counts[k])
			print("EOSJOB %s" % ("ok  Explorers of Sky jobs on the board (%d)" % eos_n if eos_n > 0 else "BAD no Explorers of Sky jobs"))
			# take one and enter its floor
			var jj: Dictionary = sample.values()[0] if sample.size() > 0 else {}
			if not jj.is_empty():
				Missions.accept(jj)
				for k2 in Game.jobs:
					if str(k2.id) == str(jj.id): Missions.take(k2)
				start_dungeon(str(jj.dungeon), int(jj.floor) - 1)
				for i in 30:
					await get_tree().create_timer(0.5).timeout
					if i > 4 and not dungeon.busy: break
				var here := dungeon.fs.mons.filter(func(m): return Missions.is_client(m) or m.has_meta("job_id") or m.get_meta("client", false))
				print("EOSJOB %s" % ("ok  job target is on its floor (%s F%d)" % [jj.dungeon, int(jj.floor)] if here.size() > 0 or str(jj.kind) in ["find", "deliver"] else "BAD job target missing (kind %s)" % jj.kind))
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--flytest"):
		(func():
			var g := GSprite.new()
			root.add_child(g)
			g.position = Vector2(200, 300)
			g.set_species("0227")
			g.play(0x100E, 0)                 # Skarmory's "flee" (event anim 23 -> Red group 14)
			var log := []
			var busy_frames := 0
			for i in 80:
				g.tick()
				await get_tree().process_frame
				if g.anim_busy(): busy_frames += 1
				if i % 4 == 0: log.append(int(g._track_offset().y))
			print("FLYTEST track frames=%d busy for %d frames, y offsets: %s" % [g._track_total, busy_frames, log])
			print("FLYTEST %s" % ("ok  flies off the top" if g._track_offset().y <= -100 else "BAD stays put"))
			for pl in [0, 4, 1, 5, 3]:
				print("FLYTEST portrait place %d x on 1440: %.0f (Red's own: %d)" % [pl, GText.portrait_x(pl, 0, 1440.0), int(GText.PLACE_X[pl]) * 8 * UITheme.PX])
			var g2 := GSprite.new()
			root.add_child(g2)
			g2.set_species("0025")
			g2.play(0x807, 0)
			print("FLYTEST %s" % ("ok  normal idle has no track" if g2._track.is_empty() else "BAD idle got a track"))
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--bosswin"):
		(func():
			var key := "mt_steel"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--boss="):
					key = a.substr(7)
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			for e in Game.team:
				e.level = 40
				e.exp = DB.exp_at(str(e.sp), 40)
			Game.story.erase("cutscene_flags")
			Dialog.auto = true
			var n: int = DB.dungeons.dungeons[key].floors.size()
			start_dungeon(key, n - 1)
			for i in 60:
				await get_tree().create_timer(0.5).timeout
				if i > 6 and not dungeon.busy: break
			Dialog.auto = false
			dungeon.auto_answer = true
			var d: Dungeon = dungeon
			var L: Mon = d.fs.leader
			var b: Mon = null
			for m in d.fs.mons:
				if not m.is_team() and str(m.get_meta("behavior", "")) != "" and str(m.get_meta("behavior", "")) != "BEHAVIOR_FIXED_ENEMY" and m.visual and m.visual.fade > 0.5 and not m.get_meta("cs_hidden", false):
					if b == null or m.max_hp > b.max_hp: b = m
			print("BOSSWIN boss=%s at %s leader %s" % [b.name if b else "-", b.pos if b else "-", L.pos])
			# put the boss next to the leader and finish it
			for dv in DB.DIRS:
				if d.fs.walkable(L.pos + dv, b) and d.fs.mon_at(L.pos + dv) == null and d.fs.can_attack_dir(L.pos, DB.DIRS.find(dv)):
					b.pos = L.pos + dv
					b.visual.position = d._px(b.pos)
					break
			b.hp = 1
			var dir := AI.dir_toward(L.pos, b.pos)
			var shots := {"i": 0}
			var t := Timer.new()
			t.wait_time = 0.1
			add_child(t)
			t.timeout.connect(func():
				if shots.i < 40:
					get_viewport().get_texture().get_image().save_png("user://bosswin_%02d.png" % shots.i)
					if is_instance_valid(b) and b.visual:
						print("BOSSWIN frame %d anim=%s fade=%.2f pos=%s vis=%s" % [shots.i, b.visual.anim, b.visual.fade, b.visual.position, b.visual.visible])
					shots.i += 1)
			t.start()
			d.leader_action({"type": "attack", "move": "", "dir": dir})
			await get_tree().create_timer(5.0).timeout
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--bossresume"):
		(func():
			var key := "sinister_woods"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--boss="):
					key = a.substr(7)
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			Dialog.auto = true
			var n: int = DB.dungeons.dungeons[key].floors.size()
			var ok := {"ok": 0, "bad": 0}
			var check := func(what: String, good: bool, info := ""):
				ok["ok" if good else "bad"] += 1
				print("BOSSRESUME %s %s %s" % ["ok " if good else "BAD", what, info])
			# a normal floor: a quicksave there resumes mid-floor, as before
			start_dungeon(key, n - 2)
			for i in 40:
				await get_tree().create_timer(0.5).timeout
				if i > 4 and not dungeon.busy: break
			var lpos: Vector2i = dungeon.fs.leader.pos
			DungeonSave.save(dungeon)
			var raw: Dictionary = DungeonSave._read_raw()
			check.call("normal floor saves the floor itself", not bool(JSON.to_native(raw.state).get("fresh", false)))
			# the boss floor: the save is the floor's start
			start_dungeon(key, n - 1)
			for i in 60:
				await get_tree().create_timer(0.5).timeout
				if i > 6 and not dungeon.busy: break
			check.call("boss floor built", dungeon.boss != null or dungeon.fixed_no != 0, "fixed=%d" % dungeon.fixed_no)
			var hp_before: int = dungeon.fs.leader.hp
			dungeon.fs.leader.hp = maxi(1, dungeon.fs.leader.hp - 5)     # changes during the fight aren't kept
			DungeonSave.save(dungeon)
			raw = DungeonSave._read_raw()
			check.call("boss floor saves the floor's start", bool(JSON.to_native(raw.state).get("fresh", false)))
			var foes0: int = dungeon.fs.mons.filter(func(m): return not m.is_team()).size()
			await resume_dungeon()
			for i in 60:
				await get_tree().create_timer(0.5).timeout
				if i > 6 and not dungeon.busy: break
			check.call("resumed on the boss floor", dungeon.floor_i == n - 1, "floor_i=%d" % dungeon.floor_i)
			check.call("boss scene rebuilt", dungeon.boss != null or dungeon.fixed_no != 0)
			var foes1: int = dungeon.fs.mons.filter(func(m): return not m.is_team()).size()
			check.call("bosses are back", foes1 == foes0 and foes1 > 0, "%d vs %d" % [foes1, foes0])
			check.call("leader HP from the floor's start", dungeon.fs.leader.hp == hp_before, "%d vs %d" % [dungeon.fs.leader.hp, hp_before])
			get_viewport().get_texture().get_image().save_png("user://bossresume.png")
			print("BOSSRESUME summary ok=%d bad=%d" % [ok.ok, ok.bad])
			get_tree().quit()).call_deferred()
		return
	if OS.get_cmdline_user_args().has("--bossfight"):
		(func():
			var key := "sinister_woods"
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--boss="):
					key = a.substr(7)
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			for e in Game.team:
				e.level = 30
				e.exp = DB.exp_at(str(e.sp), 30)
			Dialog.auto = true
			var n: int = DB.dungeons.dungeons[key].floors.size()
			start_dungeon(key, n - 1)
			var d := dungeon
			for i in 60:
				await get_tree().create_timer(0.5).timeout
				if i > 6 and not d.busy:
					break
			var info := func(tag: String):
				var out := []
				for m in d.fs.mons:
					out.append("%s@%s hp%d hid=%s side=%s beh=%s" % [m.name, m.pos, m.hp, m.get_meta("cs_hidden", false), m.side, m.get_meta("behavior", "")])
				print("BOSSFIGHT %s turn=%d busy=%s menu=%s music=%s playing=%s : %s" % [tag, d.fs.turn, d.busy, d.menu_open, Audio.current, Audio.music.playing, " | ".join(out)])
			info.call("after scene")
			get_viewport().get_texture().get_image().save_png("user://bossfight_%s_1.png" % key)
			if OS.get_cmdline_user_args().has("--probe"):
				# Boss check: the team only waits (and is healed every turn); did each boss move or hit someone?
				var start := {}
				var nen := 0
				for m in d.fs.mons:
					if not m.is_team():
						start[m] = m.pos
						nen += 1
						m.max_hp = 9999         # so the partner can't end the fight before we see the bosses act
						m.hp = 9999
					else:
						m.max_hp = 9999         # and the team can't faint (that would switch to the defeat music)
						m.hp = 9999
				var dmg := 0
				var turns := 0
				for t in 10:
					if d.fs == null or d.result_sent:
						break
					var hp0 := 0
					for m in d.fs.mons:
						if m.is_team():
							hp0 += m.hp
					await d.leader_action({"type": "wait"})
					await get_tree().create_timer(0.3).timeout
					turns += 1
					if d.fs == null:
						break
					var hp1 := 0
					for m in d.fs.mons:
						if m.is_team():
							hp1 += m.hp
							m.hp = m.max_hp
					dmg += maxi(0, hp0 - hp1)
				var moved := 0
				for m in start:
					if is_instance_valid(m) and m.pos != start[m]:
						moved += 1
				print("BOSSPROBE %s music=%s playing=%s enemies=%d moved=%d team_dmg=%d turns=%d" % [key, Audio.current, Audio.music.playing, nen, moved, dmg, turns])
				var lg: Array = d.hud.log_all
				for i in range(maxi(0, lg.size() - 16), lg.size()):
					print("BOSSLOG ", str(lg[i]).left(160))
				get_tree().quit()
				return
			for t in 6:
				await d.leader_action({"type": "wait"})
				await get_tree().create_timer(0.4).timeout
			info.call("after 6 turns")
			var lg: Array = d.hud.log_all
			for i in range(maxi(0, lg.size() - 14), lg.size()):
				print("BOSSLOG ", lg[i])
			for m in d.fs.mons:
				if not m.is_team():
					var st := {}
					for k in m.status:
						if m.status[k] is int and int(m.status[k]) > 0:
							st[k] = m.status[k]
					var mem2 := {}
					AI._init_memory(m, mem2)
					print("BOSSFIGHT dbg ", m.name, " status=", st, " pre=", AI._status_prevents_acting(m, d.fs, mem2), " move=", AI.choose_ai_move(m, d.fs, mem2), " canmove=", AI.species_can_move(m), " walk=", AI.ai_movement(m, d.fs, mem2, true), " see=", AI.can_see_target(d.fs, m, d.fs.leader), " treat=", AI.treatment(m, d.fs.leader, false, true), " run=", AI.should_run_away(m, mem2), " patient=", AI.tactic_set(m, "be_patient", mem2), " wait_there=", AI.tactic_set(m, "wait_there", mem2), " target=", AI._choose_target_position(m, d.fs, mem2), " mem=", mem2, " dm=", AI._decide_movement(m, d.fs, mem2), " walk9=", d.fs.walkable(m.pos + Vector2i(0, 1), m), " tactic=", m.get_meta("tactic", "-"), " cam=", AI.can_ai_move(d.fs, m, 0), " flag=", d.fs.flags[d.fs.idx(m.pos + Vector2i(0, 1))], " step=", d.fs.can_step(m.pos, 0, m))
			get_viewport().get_texture().get_image().save_png("user://bossfight_%s_2.png" % key)
			get_tree().quit()).call_deferred()
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
	if OS.get_cmdline_user_args().has("--allmaps"):      # every ground map, whole map in view: user://allmaps/
		(func():
			Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
			_clear()
			Story.host = self
			ground = Ground.new()
			ground.host = self
			ground.ui_root = root
			add_child(ground)
			if ground.hud:
				ground.hud.visible = false
			await get_tree().process_frame
			DirAccess.make_dir_recursive_absolute("user://allmaps")
			var from := 0
			var to: int = GData.common.map_conv.size()
			for a1 in OS.get_cmdline_user_args():
				if a1.begins_with("--from="): from = int(a1.substr(7))
				if a1.begins_with("--to="): to = int(a1.substr(5))
			for mi in range(from, to):
				ground._load_map(mi)
				var info: Dictionary = ground.map_info
				var mw := float(info.get("w_px", info.get("w", 240))) if info.get("dungeon_map", false) else float(info.get("w", 240))
				var mh := float(info.get("h_px", info.get("h", 160))) if info.get("dungeon_map", false) else float(info.get("h", 160))
				var vs := get_viewport().get_visible_rect().size
				ground.zoom = minf(vs.x / mw, vs.y / mh) * UITheme.ui_scale()
				for f in 120:
					ground._scroll_update()
				await get_tree().create_timer(0.25).timeout
				get_viewport().get_texture().get_image().save_png("user://allmaps/m%03d_%s.png" % [mi, ground.map_file])
			print("ALLMAPS done")
			get_tree().quit()).call_deferred()
		return
	for a0 in OS.get_cmdline_user_args():
		if a0.begins_with("--mapshot="):              # ground map render check: --mapshot=186
			(func():
				Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
				_clear()
				Story.host = self
				ground = Ground.new()
				ground.host = self
				ground.ui_root = root
				add_child(ground)
				await get_tree().process_frame
				ground._load_map(int(a0.substr(10)))
				for a1 in OS.get_cmdline_user_args():
					if a1.begins_with("--zoom="): ground.set_ground_zoom(float(a1.substr(7)))
				for i in 3:
					await get_tree().create_timer(0.6).timeout
					get_viewport().get_texture().get_image().save_png("user://mapshot_%s_%d.png" % [a0.substr(10), i])
					for f in 240:
						ground._scroll_update()      # 4 s of drift between shots (ticks don't run outside a scene)
				get_tree().quit()).call_deferred()
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
	if dungeon.has_meta("resume_fresh"):
		dungeon.remove_meta("resume_fresh")
		await dungeon.build_floor()            # boss / fixed floor: built again, its cutscene plays again
	else:
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
	if not keep and not Dialog.auto and not ListMenu.auto:
		await choose_difficulty()

## New adventure: Normal or Hard (either can be changed any time in Game Options -> Dungeon -> Difficulty).
func choose_difficulty() -> void:
	var dm := ListMenu.make("Choose a difficulty (you can change it later in Game Options)", ["Normal", "Hard"], false)
	_center(dm)
	Difficulty.set_hard(await dm.choose() == 1)

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
	var job_exit: bool = is_instance_valid(dungeon) and dungeon.has_meta("job_exit")
	if res == "boss_next" and Game.story.has("vars"):
		# Red's split story dungeons (Mt. Steel, Sinister Woods): reaching the boss arena's floor is not a clear.
		# No results, no "You cleared ...!", nothing unlocked: the ground cutscene (script3) runs, then the arena.
		_clear()
		Game.save_game()
		story_dungeon = false
		start_story(Ground.STARTMODE_DUNGEON_WON)
		return
	if res == "boss_next":
		res = "cleared"
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
		# Red (run_dungeon.c): only reaching the end is DUNGEON_WON; leaving early (a finished job's "leave now?",
		# an Escape Orb) is STARTMODE_10, so the dungeon's script doesn't carry on to its boss arena
		var mode := Ground.STARTMODE_DUNGEON_LOST
		if ok:
			mode = Ground.STARTMODE_10 if (res == "escaped" or job_exit) else Ground.STARTMODE_DUNGEON_WON
		start_story(mode)
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
	if OS.get_cmdline_user_args().has("--megashot"):
		var T2: Mon = dungeon.fs.mons[1]
		T2.pos = L.pos + Vector2i(1, 0)
		T2.visual.position = dungeon._px(T2.pos)
		dungeon.set_zoom(2.0)
		var style := 2
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--style="):
				style = int(a.substr(8))
		Awaken.fx_style = style
		T2.sp = "0006"
		T2.visual.set_species("0006")
		await get_tree().create_timer(0.3).timeout
		Awaken.awaken(dungeon, T2)
		var times := [0.1, 0.35, 0.5, 0.75, 1.2] if style == 2 else [0.1, 0.25, 0.45, 0.65, 1.2]
		var prev := 0.0
		for i in times.size():
			await get_tree().create_timer(times[i] - prev).timeout
			prev = times[i]
			get_viewport().get_texture().get_image().save_png("user://mega%d_%d.png" % [style, i])
			print("MEGA ", i, " ", T2.sp, " ", T2.visual.man.get("name", T2.visual.man.keys().slice(0, 4)))
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--beamshot"):
		var T2: Mon = dungeon.fs.mons[1]
		T2.pos = L.pos + Vector2i(1, 0)
		T2.visual.position = dungeon._px(T2.pos)
		dungeon.set_zoom(2.0)
		await get_tree().create_timer(0.3).timeout
		Missions._remove_mon(dungeon, T2)
		dungeon.rescue_beam([T2])
		for i in 4:
			await get_tree().create_timer(0.12).timeout
			get_viewport().get_texture().get_image().save_png("user://beam_%d.png" % i)
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
func _top_mark_menu():
	for i in range(TeamScreens._stack.size() - 1, -1, -1):
		var x = TeamScreens._stack[i]
		if is_instance_valid(x) and x.get("mark_touch") == true and not x.finished:
			return x
	return null

func _walktest() -> void:
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	Dungeon.perf_log = OS.get_cmdline_user_args().has("--perf")
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
	var defeat_at := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--defeatat="):
			defeat_at = a.substr(11)     # lose this dungeon once (the boss floor), then report the state after
	if defeat_at != "":
		var snap := func(tag: String):
			print("DEFEATAT %s leader=%s team=%s scen=%s sub1=%s postgame=%s shop_fa=%d owned_fa=%d cleared=%s rank=%d flag_kind=%d" % [tag,
				str(Game.team[0].get("sp", "?")) if Game.team.size() > 0 else "-", str(Game.team.map(func(e): return str(e.get("sp", "")))),
				str(GVars.scenario(GVars.SCENARIO_MAIN)) if Game.story.has("vars") else "-", str(GVars.scenario(GVars.SCENARIO_SUB1)) if Game.story.has("vars") else "-",
				RedShops.postgame(), RedShops.shop_areas().size(), Game.friend_areas.size(), str(Game.cleared), Game.rank_points,
				GVars.get_val(null, GVars.FLAG_KIND) if Game.story.has("vars") else -1])
		var take_timer := Timer.new()
		take_timer.wait_time = 2.0
		take_timer.autostart = true
		add_child(take_timer)
		take_timer.timeout.connect(func():
			# reach the story job in that dungeon: take any board job there (the story one included)
			if Game.story.has("vars") and GVars.quest(GVars.QUEST_CAN_ACCESS_JOBS):
				Missions.refresh_board_if_new_day()
				for j in Game.board.duplicate():
					if str(j.get("dungeon", "")) == defeat_at and not Missions.in_job_list(j):
						if Missions.accept(j):
							for k in Game.jobs:
								if str(k.id) == str(j.id):
									Missions.take(k)
							print("  TEST took %s job in %s story=%s" % [j.get("kind", ""), defeat_at, j.has("story")]))
		get_tree().process_frame.connect(func():
			if is_instance_valid(dungeon) and dungeon.dkey == defeat_at and not has_meta("defeat_done") and dungeon.floor_i >= DB.dungeons.dungeons[defeat_at].floors.size() - 1 and dungeon.fs != null:
				set_meta("defeat_done", true)
				snap.call("before")
				Dungeon.test_invincible = false
				(func():
					await get_tree().create_timer(2.0).timeout
					if is_instance_valid(dungeon):
						dungeon._end("defeated")
					for i in 40:
						await get_tree().create_timer(1.0).timeout
						if i in [10, 25, 39]:
							snap.call("after%d" % i)
					get_tree().quit()).call())
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
			if _st_same > 0 and _st_same % 90 == 0:
				_ap_counts.clear()          # no story progress for a while: try every target again (test autopilot only)
				print("  TEST autopilot: no progress for %ds, retrying every target" % _st_same)
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
