extends SceneTree
## Headless test for res://scripts/core/ai.gd and turn_rules.gd.
## Run: godot --headless --path . --script tests/test_ai.gd
## The DB autoload (needed by floor_state.gd's DB.DIRS) only exists once the SceneTree is initialised, so
## the work happens in _initialize(); AI / FloorState / TurnRules are loaded at runtime (not referenced
## statically) so this script compiles before the autoload exists.

const DIRS := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1)]

var AIc
var TRc
var FSc
var dbn
var fs
var fails := 0
var checks := 0
var mem := {}
var log_lines: Array = []

func _init() -> void:
	pass

func _initialize() -> void:
	dbn = root.get_node_or_null("DB")
	if dbn == null:
		dbn = load("res://scripts/core/db.gd").new()
		dbn._ready()
	elif dbn.moves.is_empty():
		dbn._ready()
	AIc = load("res://scripts/core/ai.gd")
	TRc = load("res://scripts/core/turn_rules.gd")
	FSc = load("res://scripts/dungeon/floor_state.gd")
	AIc.db = dbn
	_test_turn_rules()
	_test_attack_choice()
	_test_movement_rules()
	_test_simulation()
	print("")
	print("test_ai: %d checks, %d failures" % [checks, fails])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("  FAIL: ", what)

# ------------------------------------------------------------------ map
## Two rooms joined by a corridor with a bend (tests corner rules):
##  room A x2..11 y2..9, corridor (12..18, 6) -> (18, 7..10) -> (19..25, 10), room B x26..35 y4..13,
##  plus a dead-end side corridor from room B going down (30, 14..17).
func make_floor():
	var f = FSc.new()
	f.w = 40
	f.h = 20
	f.terrain = PackedByteArray()
	f.terrain.resize(f.w * f.h)
	f.room = PackedByteArray()
	f.room.resize(f.w * f.h)
	f.room.fill(255)
	f.flags = PackedInt32Array()
	f.flags.resize(f.w * f.h)
	f.explored = PackedByteArray()
	f.explored.resize(f.w * f.h)
	f.rooms = [Rect2i(2, 2, 10, 8), Rect2i(26, 4, 10, 10)]
	for r in 2:
		var rect: Rect2i = f.rooms[r]
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				f.terrain[y * f.w + x] = 1
				f.room[y * f.w + x] = r
	var cor: Array = []
	for x in range(12, 19):
		cor.append(Vector2i(x, 6))
	for y in range(7, 11):
		cor.append(Vector2i(18, y))
	for x in range(19, 26):
		cor.append(Vector2i(x, 10))
	for y in range(14, 18):
		cor.append(Vector2i(30, y))
	for p in cor:
		f.terrain[p.y * f.w + p.x] = 1
	# natural junctions: room tiles next to a corridor
	for p in [Vector2i(11, 6), Vector2i(26, 10), Vector2i(30, 13)]:
		f.flags[p.y * f.w + p.x] |= 2
	for x in f.w:
		f.flags[x] |= 1
		f.flags[(f.h - 1) * f.w + x] |= 1
	for y in f.h:
		f.flags[y * f.w] |= 1
		f.flags[y * f.w + f.w - 1] |= 1
	f.stairs = Vector2i(34, 12)
	f.rng.seed = 12345
	return f

func mk(sp: String, lv: int, side: String, pos: Vector2i, hp := 0) -> Mon:
	var m: Mon = dbn.make_mon(sp, lv, side)
	m.pos = pos
	if hp > 0:
		m.max_hp = hp
		m.hp = hp
	fs.mons.append(m)
	return m

# ------------------------------------------------------------------ TurnRules unit checks
func _test_turn_rules() -> void:
	print("== TurnRules")
	fs = make_floor()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# status_turns ranges (DungeonRandRange high-exclusive, +1 where the C setter adds it)
	var seen := {}
	for i in 400:
		var t: int = TRc.status_turns("sleep", rng)
		seen[t] = true
		ok(t >= 3 and t <= 6, "sleep turns in 3..6 (got %d)" % t)
	ok(seen.size() == 4, "sleep turns cover 3..6")
	ok(TRc.status_turns("para", rng) == 2, "paralysis = 2 turns ({1,2} range +1)")
	ok(TRc.status_turns("burn", rng) == 128, "burn = 0x7F + 1")
	ok(TRc.status_turns("cringe", rng) == 2, "cringe = 1 + 1")
	for i in 100:
		var c: int = TRc.status_turns("confused", rng)
		ok(c >= 7 and c <= 12, "confusion 7..12 (got %d)" % c)
	ok(TRc.status_turns("nonsense", rng) == 0, "unknown status -> 0")
	# regen: team only, acc += maxHP, 1 HP per regenSpeed
	var a: Mon = mk("0001", 5, "team", Vector2i(3, 3))
	var w: Mon = mk("0016", 5, "enemy", Vector2i(5, 5))
	var spd := int(dbn.species["0001"].get("regen", 0))
	a.max_hp = 50
	a.hp = 10
	a.regen_acc = 0
	var healed := 0
	for i in 20:
		healed += TRc.regen(a)
	ok(healed == (50 * 20) / clampi(spd, 30, 500), "regen 20 turns: %d HP (speed %d)" % [healed, spd])
	w.hp = 1
	ok(TRc.regen(w) == 0 and w.hp == 1, "wild Pokemon do not regenerate")
	a.status.poison = 5
	ok(TRc.regen(a) == 0, "no regen while poisoned")
	a.status.poison = 0
	# burn: damage on the first tick then every 20
	a.hp = 50
	a.status.burn = 128
	var dmg_turns: Array = []
	for i in 45:
		var before := a.hp
		TRc.tick_status(a, fs)
		if a.hp < before:
			dmg_turns.append(i)
	ok(dmg_turns == [0, 20, 40], "burn damage turns %s" % [dmg_turns])
	ok(a.hp == 35, "burn 3x5 damage")
	a.status.burn = 0
	a.status.erase("burn_cd")
	# badly poisoned: 6 every 2 turns
	a.hp = 50
	a.status.badpoison = 128
	for i in 4:
		TRc.tick_status(a, fs)
	ok(a.hp == 50 - 12, "bad poison 6 HP every 2 turns (hp %d)" % a.hp)
	a.status.badpoison = 0
	# timers count down, 0x7F never does; yawn -> sleep
	a.status.confused = 3
	a.status.sleep = 0x7F
	TRc.tick_status(a, fs)
	ok(a.status.confused == 2 and a.status.sleep == 0x7F, "timers tick, 0x7F is infinite")
	a.status.sleep = 0
	a.status.yawn = 1
	TRc.tick_status(a, fs)
	ok(int(a.status.sleep) >= 5 and int(a.status.sleep) <= 8, "yawn ends -> sleep 4..7(+1) turns")
	a.status.sleep = 0
	a.status.confused = 0
	# speed
	var counts := [0, 0, 0, 0, 0]
	for stage in 5:
		var tot := 0
		for start in range(0, 24, 4):
			for t in 4:
				if int(TRc.SPEED_TURNS[stage][(start + t) % 24]) != 0:
					tot += 1
		counts[stage] = tot
	ok(counts == [3, 6, 12, 18, 24], "gSpeedTurns actions per 24 sub-turns %s" % [counts])
	var n := 0
	a.turn_energy = 0
	for i in 6:
		n += TRc.actions_this_turn(a)
	ok(n == 6, "normal speed: 1 action per turn")
	a.status.fast = 10
	n = 0
	for i in 6:
		n += TRc.actions_this_turn(a)
	ok(n == 12, "speed up: 2 actions per turn")
	a.status.fast = 0
	a.status.para = 5
	n = 0
	for i in 6:
		n += TRc.actions_this_turn(a)
	ok(n == 3, "paralysis slows to every other turn")
	a.status.para = 0
	# belly
	a.is_leader = true
	ok(is_equal_approx(TRc.belly_loss(a), 0.1), "leader belly -0.1/turn")
	a.is_leader = false
	ok(TRc.belly_loss(a) == 0.0, "only the leader's belly drops")
	a.is_leader = true
	var bs := {"belly": 0.05, "empty_alert": 0}
	var r1: Dictionary = TRc.belly_tick(a, bs)
	var r2: Dictionary = TRc.belly_tick(a, bs)
	ok(r1.damage == 1 and r1.message == TRc.MSG_EMPTY and r2.message == TRc.MSG_HURRY, "starvation: 1 HP + alerts")
	a.is_leader = false
	# wind
	var ws := {"turns": 300, "phase": 0}
	var msgs := {}
	var blown_at := -1
	for i in 400:
		var r: Dictionary = TRc.wind_tick(ws)
		if r.message != "":
			msgs[r.message] = int(ws.turns)
		if r.blown_out:
			blown_at = i
			break
	ok(msgs.get(TRc.MSG_WIND[0], -1) == 249 and msgs.get(TRc.MSG_WIND[1], -1) == 149 and msgs.get(TRc.MSG_WIND[2], -1) == 49, "wind warnings at <250/<150/<50: %s" % [msgs])
	ok(blown_at == 299, "blown out when the limit runs out (step %d)" % blown_at)
	# spawns
	ok(TRc.spawn_interval(fs) == 36, "spawn every 36 turns")
	fs.leader = a
	a.pos = Vector2i(4, 4)
	for i in 50:
		var p: Vector2i = TRc.spawn_position(fs)
		ok(p.x >= 0 and fs.room_at(p) != 255 and (absi(p.x - 4) >= 6 or absi(p.y - 4) >= 6), "spawn tile %s: room, >= 6 from leader" % p)
	fs.mons.clear()

# ------------------------------------------------------------------ attack AI checks
func _test_attack_choice() -> void:
	print("== ChooseAIMove / AIConsiderMove")
	fs = make_floor()
	var L: Mon = mk("0001", 10, "team", Vector2i(5, 5), 999)
	L.is_leader = true
	fs.leader = L
	var e: Mon = mk("0019", 5, "enemy", Vector2i(6, 5), 50)
	e.moves = [{"name": "Tackle", "pp": 20, "max_pp": 20, "on": true, "linked": false},
		{"name": "Growl", "pp": 20, "max_pp": 20, "on": true, "linked": false}]
	var kinds := {}
	for i in 300:
		var a: Dictionary = AIc.decide(e, fs, {})
		kinds[String(a.get("move", "?"))] = int(kinds.get(String(a.get("move", "?")), 0)) + 1
		ok(a.type == "attack" and a.dir == 6, "adjacent enemy attacks west (%s)" % [a])
	print("  move picks adjacent (Tackle ai25, Growl ai10, regular w30): ", kinds)
	ok(kinds.has("") and kinds.has("Tackle"), "uses both regular attack and moves")
	# Growl is TARGET_2_TILES_AHEAD in Red's AI data: usable from 2 tiles in a line
	e.pos = Vector2i(7, 5)
	e.moves = [{"name": "Growl", "pp": 20, "max_pp": 20, "on": true, "linked": false}]
	var r: Dictionary = AIc.consider_move(e, fs, "Growl")
	ok(r.ok and r.dir == 6, "Growl targets 2 tiles ahead (%s)" % [r])
	L.stages.atk = 0
	r = AIc.consider_move(e, fs, "Growl")
	ok(not r.ok, "Status Checker: no Growl on Attack stage 0")
	L.stages.atk = 10
	# PP checker: no PP -> Struggle
	e.pos = Vector2i(6, 5)
	e.moves = [{"name": "Tackle", "pp": 0, "max_pp": 20, "on": true, "linked": false}]
	var a2: Dictionary = AIc.decide(e, fs, {})
	ok(a2.type == "attack" and a2.move == "Struggle", "all PP gone -> Struggle (%s)" % [a2])
	# Sleeping enemy does nothing
	e.moves = [{"name": "Tackle", "pp": 10, "max_pp": 20, "on": true, "linked": false}]
	e.status.sleep = 0x7F
	ok(AIc.decide(e, fs, {}).type == "wait", "asleep -> wait")
	e.status.sleep = 0
	# paralysis: cannot attack -> moves instead (here: stays, target adjacent so wait)
	e.status.para = 3
	var a3: Dictionary = AIc.decide(e, fs, {})
	ok(a3.type != "attack", "paralysed Pokemon do not attack (%s)" % [a3])
	e.status.para = 0
	# diagonal across a wall corner: no regular attack (Red's corner rule)
	L.pos = Vector2i(11, 6)        # room A junction
	e.pos = Vector2i(12, 6)        # corridor mouth: straight adjacency
	ok(AIc.decide(e, fs, {}).type == "attack", "attack along the corridor mouth")
	e.pos = Vector2i(12, 7)        # wall at (12,7)? -> not walkable, use corner case below
	fs.mons.erase(e)
	var e2: Mon = mk("0019", 5, "enemy", Vector2i(12, 6), 50)
	e2.moves = []
	L.pos = Vector2i(11, 7)        # diagonal SW of e2 with wall at (12,7): corner cut forbidden
	var a4: Dictionary = AIc.decide(e2, fs, {})
	ok(a4.type != "attack", "no regular attack across a wall corner (%s)" % [a4])
	fs.mons.clear()

# ------------------------------------------------------------------ movement unit checks
func _test_movement_rules() -> void:
	print("== AIMovement rules")
	fs = make_floor()
	var L: Mon = mk("0001", 10, "team", Vector2i(13, 6), 999)
	L.is_leader = true
	fs.leader = L
	var e: Mon = mk("0016", 5, "enemy", Vector2i(15, 6), 50)
	e.moves = []
	for m in fs.mons:
		AIc.on_moved(m, m.pos, true)
	var em := {}
	var a: Dictionary = AIc.decide(e, fs, em)
	ok(em.objective == "chase" and a.type == "move" and a.dir == 6, "corridor: chase a target 2 tiles away (%s %s)" % [em.objective, a])
	# leader walks off into room A: (13,6)->(12,6)->(11,6)->(10,5)
	for p in [Vector2i(12, 6), Vector2i(11, 6), Vector2i(10, 5)]:
		var old := L.pos
		L.pos = p
		AIc.on_moved(L, old)
	a = AIc.decide(e, fs, em)
	ok(em.objective == "chase_remembered" and em.target_pos == Vector2i(13, 6) and a.type == "move" and a.dir == 6,
		"lost sight -> heads for the target's last seen position prevPos (%s %s %s)" % [em.objective, em.target_pos, a])
	# Run Away ability under half HP: flees instead of attacking
	e.pos = Vector2i(11, 5)
	L.pos = Vector2i(10, 5)
	e.ability = "run_away"
	e.hp = 10
	a = AIc.decide(e, fs, em)
	ok(a.type != "attack" and em.objective == "run_away", "Run Away + low HP -> flees (%s %s)" % [em.objective, a])
	e.ability = ""
	e.hp = 50
	# ally tactics: Let's Go Together ignores visible foes; Go After Foes chases them
	var al: Mon = mk("0004", 10, "team", Vector2i(4, 4), 999)
	L.pos = Vector2i(3, 8)
	e.pos = Vector2i(9, 3)
	var amem := {}
	AIc.decide(al, fs, amem)
	ok(int(amem.target_uid) == L.uid, "Let's Go Together: follows the leader")
	amem = {"tactic": "go_after_foes"}
	AIc.decide(al, fs, amem)
	ok(int(amem.target_uid) == e.uid, "Go After Foes: chases the visible foe")
	amem = {"tactic": "wait_there"}
	ok(AIc.decide(al, fs, amem).type == "wait", "Wait There: stays")
	# wild Pokemon pick up an item underfoot when its hands are free
	fs.mons.erase(al)
	e.pos = Vector2i(30, 8)
	e.held = ""
	fs.items[e.pos] = {"id": "apple", "n": 1, "sticky": false, "price": 0}
	a = AIc.decide(e, fs, {})
	ok(a.type == "item" and a.action == "pickup", "item underfoot -> pick up (%s)" % [a])
	fs.items.clear()
	# room wander: heads for one of the room's exits
	var wm := {}
	AIc.decide(e, fs, wm)
	ok(wm.objective == "leave_room" and wm.target_pos in fs.red_room_exits(1), "wanders toward a room exit (%s %s)" % [wm.objective, wm.target_pos])
	# corridor junction detection (IsAtJunction): a T in the corridor
	var jm: Mon = mk("0016", 5, "enemy", Vector2i(18, 8), 30)
	ok(not AIc.is_at_junction(fs, jm), "straight corridor is not a junction")
	# confused: random walk, always legal
	e.status.confused = 10
	e.pos = Vector2i(28, 6)
	for i in 50:
		var c: Dictionary = AIc.decide(e, fs, {})
		if c.type == "move":
			ok(fs.can_step(e.pos, int(c.dir), e) and fs.mon_at(e.pos + DIRS[int(c.dir)]) == null, "confused walk is legal")
	e.status.confused = 0
	# spawn init: chance asleep -> sleep 0x7F
	var sm: Mon = mk("0016", 5, "enemy", Vector2i(30, 12), 30)
	var r2 := RandomNumberGenerator.new()
	var asleep := 0
	for i in 200:
		sm.status.sleep = 0
		TRc.init_spawned(sm, r2, 0)
		if sm.status.sleep == 0x7F:
			asleep += 1
	var ch := int(dbn.species["0016"].get("asleep", 0))
	print("  spawn asleep: %d/200 (chanceAsleep %d%%)" % [asleep, ch])
	ok(absi(asleep - ch * 2) <= 30, "spawn-asleep rate matches chanceAsleep")
	fs.mons.clear()

# ------------------------------------------------------------------ 250-turn simulation
var stats := {"wall": 0, "occupied": 0, "corner": 0, "adj_no_attack": 0, "moves": 0, "attacks": 0, "waits": 0,
	"pickups": 0, "spawned": 0, "fainted": 0, "ally_reruns": 0}

func _test_simulation() -> void:
	print("== 250-turn simulation")
	fs = make_floor()
	mem = {}
	var L: Mon = mk("0001", 10, "team", Vector2i(4, 4), 9999)
	L.name = "Leader"
	L.is_leader = true
	fs.leader = L
	var ally: Mon = mk("0004", 10, "team", Vector2i(3, 5), 9999)
	ally.name = "Ally"
	var e1: Mon = mk("0019", 4, "enemy", Vector2i(32, 7), 40)
	e1.name = "Rattata"
	var e2: Mon = mk("0016", 4, "enemy", Vector2i(28, 12), 40)
	e2.name = "Pidgey"
	fs.items[Vector2i(33, 10)] = {"id": "oran_berry", "n": 1, "sticky": false, "price": 0}
	for m in fs.mons:
		AIc.on_moved(m, m.pos, true)
	# leader script: idle in room A, walk to room B, then back to room A
	var legs := [[0, Vector2i(4, 4)], [30, Vector2i(30, 8)], [150, Vector2i(5, 7)]]
	var leg_goal := Vector2i(4, 4)
	var first_chase := {}
	var wandered_before := {}
	var ally_in_corridor := false
	var ally_in_b := false
	var ally_back_in_a := false
	var ally_max_gap := 0
	var stuck := 0
	var max_stuck := 0
	var last_ally_pos := ally.pos
	var remembered := 0
	var spawn_timer := 0
	for turn in 250:
		fs.turn = turn
		for lg in legs:
			if turn >= int(lg[0]):
				leg_goal = lg[1]
		# --- leader (player) acts: walk toward the goal, swapping with allies like Red
		var foe_dir := -1
		for d in 8:
			var o2: Mon = fs.mon_at(L.pos + DIRS[d])
			if o2 != null and not o2.is_team() and fs.can_attack_dir(L.pos, d):
				foe_dir = d
		if foe_dir >= 0:
			var tgt: Mon = fs.mon_at(L.pos + DIRS[foe_dir])
			L.facing = foe_dir
			tgt.hp = maxi(0, tgt.hp - 8)
			if tgt.hp <= 0:
				stats.fainted += 1
				fs.mons.erase(tgt)
		elif L.pos != leg_goal:
			var d: int = fs.path_dir(L, leg_goal, 2000, true)
			if d >= 0:
				var to: Vector2i = L.pos + DIRS[d]
				var o: Mon = fs.mon_at(to)
				if o == null:
					_step(L, d)
				elif o.is_team():
					var old := L.pos
					L.pos = to
					o.pos = old
					AIc.on_moved(L, old)
					AIc.on_moved(o, to)
		# --- everyone else
		var order: Array = []
		for m in fs.mons:
			if m.hp > 0 and not m.is_leader:
				order.append(m)
		order.sort_custom(func(a, b): return int(a.is_team()) > int(b.is_team()))
		var skipped: Array = []
		for m in order:
			if m.hp <= 0:
				continue
			for i in TRc.actions_this_turn(m, fs):
				var a: Dictionary = _act(m)
				if a.get("ally_skip", false):
					skipped.append(m)
		# ally re-run passes (sub_8044574_Async): up to 3, nearest-to-leader first
		for p in 3:
			if skipped.is_empty():
				break
			skipped.sort_custom(func(a, b): return mini(2, FSc.cheb(a.pos, L.pos)) < mini(2, FSc.cheb(b.pos, L.pos)))
			var again: Array = []
			for m in skipped:
				if m.hp <= 0:
					continue
				stats.ally_reruns += 1
				var mm: Dictionary = mem.get(m.uid, {})
				mm.recalculate_follow = true
				var a: Dictionary = _act(m)
				mm.recalculate_follow = false
				if a.get("ally_skip", false):
					again.append(m)
			skipped = again
		# --- end of turn
		for m in fs.mons.duplicate():
			if m.hp <= 0:
				continue
			TRc.regen(m)
			for s in TRc.tick_status(m, fs):
				log_lines.append(s)
			if m.hp <= 0:
				stats.fainted += 1
				fs.mons.erase(m)
		for m in fs.mons.duplicate():
			if m.hp <= 0:
				stats.fainted += 1
				fs.mons.erase(m)
		spawn_timer += 1
		if spawn_timer >= TRc.spawn_interval(fs):
			spawn_timer = 0
			if TRc.can_spawn(fs):
				var sp_pos: Vector2i = TRc.spawn_position(fs)
				if sp_pos.x >= 0:
					var nm: Mon = mk("0019", 3, "enemy", sp_pos, 30)
					nm.name = "Spawn%d" % turn
					TRc.init_spawned(nm, fs.rng, 20)
					AIc.on_moved(nm, nm.pos, true)
					stats.spawned += 1
		# --- observations
		for m in fs.mons:
			if m.is_team():
				continue
			var mm: Dictionary = mem.get(m.uid, {})
			var obj := String(mm.get("objective", ""))
			if obj == "chase" and not first_chase.has(m.uid):
				first_chase[m.uid] = turn
			if obj in ["roam", "leave_room", "stand_still"] and not first_chase.has(m.uid):
				wandered_before[m.uid] = true
			if obj == "chase_remembered":
				remembered += 1
		if OS.get_environment("AI_TRACE") != "":
			print("t", turn, " L", L.pos, " A", ally.pos, " ", mem.get(ally.uid, {}).get("objective"), " ", mem.get(ally.uid, {}).get("target_pos"), " foes:", fs.mons.filter(func(o): return not o.is_team()).map(func(o): return o.pos))
		if ally.hp > 0:
			if fs.room_at(ally.pos) == 255:
				ally_in_corridor = true
			if turn < 150 and fs.room_at(ally.pos) == 1:
				ally_in_b = true
			if turn >= 150 and ally_in_b and fs.room_at(ally.pos) == 0:
				ally_back_in_a = true
			var gap: int = FSc.cheb(ally.pos, L.pos)
			ally_max_gap = maxi(ally_max_gap, gap)
			if ally.pos == last_ally_pos and gap > 2:
				stuck += 1
				max_stuck = maxi(max_stuck, stuck)
			else:
				stuck = 0
			last_ally_pos = ally.pos
	print("  stats: ", stats)
	print("  first chase turn per enemy uid: ", first_chase, "  wandered first: ", wandered_before.keys())
	print("  chase_remembered decisions: ", remembered, "   ally max gap ", ally_max_gap, ", longest stall ", max_stuck)
	print("  final: leader ", L.pos, " ally ", ally.pos, "  sample log: ", log_lines.slice(0, 3))
	ok(stats.wall == 0, "nobody walked into a wall")
	ok(stats.corner == 0, "nobody cut a corner")
	ok(stats.occupied == 0, "nobody walked into another Pokemon")
	ok(stats.adj_no_attack == 0, "adjacent foes were always attacked (%d misses)" % stats.adj_no_attack)
	ok(first_chase.has(e1.uid) or first_chase.has(e2.uid), "an original enemy started chasing")
	ok(wandered_before.has(e1.uid) and wandered_before.has(e2.uid), "both enemies wandered before seeing anyone")
	ok(stats.attacks > 0, "attacks happened")
	ok(ally_in_corridor and ally_in_b, "ally followed the leader through the corridor into room B")
	ok(ally_back_in_a, "ally followed the leader back to room A")
	ok(max_stuck <= 12, "ally never stalled long while the leader was away (%d)" % max_stuck)
	ok(FSc.cheb(ally.pos, L.pos) <= 3, "ally ends next to the leader (%s vs %s)" % [ally.pos, L.pos])

func _act(m: Mon) -> Dictionary:
	if m.hp <= 0:
		return {"type": "wait"}
	var mm: Dictionary = mem.get(m.uid, {})
	mem[m.uid] = mm
	var adj := false
	if m.status.sleep == 0 and m.status.para == 0:
		for d in 8:
			var o: Mon = fs.mon_at(m.pos + DIRS[d])
			if o != null and o.side != m.side and fs.can_attack_dir(m.pos, d):
				adj = true
	var a: Dictionary = AIc.decide(m, fs, mm)
	if adj and a.type != "attack" and not AIc.should_run_away(m, mm):
		stats.adj_no_attack += 1
		print("  adjacent but no attack: ", m.name, " ", m.pos, " ", a, " moves=", m.moves, " status=", _active(m), " mem=", mm)
	match String(a.type):
		"move":
			stats.moves += 1
			_step(m, int(a.dir))
		"attack":
			stats.attacks += 1
			var d: int = int(a.dir)
			m.facing = d
			var mv := String(a.get("move", ""))
			if mv != "" and mv != "Struggle":
				for x in m.moves:
					if x.name == mv:
						x.pp = maxi(0, int(x.pp) - 1)
			var t: Mon = fs.mon_at(m.pos + DIRS[d])
			if t != null and t.side != m.side:
				t.hp = maxi(0, t.hp - (6 if m.is_team() else 1))
				if t.hp <= 0:
					stats.fainted += 1
					fs.mons.erase(t)
		"item":
			stats.pickups += 1
			if fs.items.has(m.pos):
				m.held = String(fs.items[m.pos].id)
				fs.items.erase(m.pos)
		_:
			stats.waits += 1
			if a.has("dir"):
				m.facing = int(a.dir)
	return a

func _active(m: Mon) -> Dictionary:
	var o := {}
	for k in m.status:
		if typeof(m.status[k]) == TYPE_INT and m.status[k] != 0:
			o[k] = m.status[k]
	return o

func _step(m: Mon, d: int) -> void:
	ok(d >= 0 and d < 8, "valid direction")
	var to: Vector2i = m.pos + DIRS[d]
	if fs.is_wall(to) or not fs.walkable(to, m):
		stats.wall += 1
		print("  WALL: ", m.name, " ", m.pos, " -> ", to)
		return
	var dv: Vector2i = DIRS[d]
	if dv.x != 0 and dv.y != 0 and (fs.is_wall(Vector2i(m.pos.x + dv.x, m.pos.y)) or fs.is_wall(Vector2i(m.pos.x, m.pos.y + dv.y))):
		stats.corner += 1
		print("  CORNER: ", m.name, " ", m.pos, " -> ", to)
		return
	if fs.mon_at(to) != null:
		stats.occupied += 1
		print("  OCCUPIED: ", m.name, " ", m.pos, " -> ", to)
		return
	var old := m.pos
	m.pos = to
	m.facing = d
	AIc.on_moved(m, old)
