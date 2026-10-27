class_name PartnerAI
extends RefCounted
## Smarter "Let's go together!" (Game Options -> Partner AI: Smarter; "Red" keeps Red's AI untouched).
## Only partners on Let's go together! use it; other tactics, wild Pokémon and clients run Red's AI (core/ai.gd).
##
##   - Fights foes near the team: a foe within ENGAGE tiles of the leader or the partner is attacked, as long as
##     the partner stays within LEASH tiles of the leader; then it comes back.
##   - Target order: a foe next to the leader, the foe the leader is fighting, then the weakest; sleeping foes
##     are left alone unless the leader picks a fight with them.
##   - Moves are chosen by their estimated damage (Combat.calc_damage, type effectiveness included): no moves the
##     foe is immune to, a KO with the regular attack saves PP, status moves only on foes without that status.
##   - Lines up line / 2-tile moves instead of walking up to the foe.
##   - A foe the leader could recruit (low HP, leader close by) is left for the leader's final hit.
##   - Real pathfinding (BFS) around walls, the leader and teammates; follows the leader out of sight;
##     partners swap places in corridors; known traps are walked around.
##   - Below 1/4 HP it stays behind the leader unless a foe is right next to it.

const ENGAGE := 3
const LEASH := 4
const SEARCH := 2400           # BFS node limit (a whole floor is ~56 x 32)
const NEAR_DEPTH := 8          # the usual search: 8 steps around the partner
const STATUS_CHANCE := 30      # % of turns a useful status move is picked over a weak hit

var dg                         # Dungeon (untyped: no class cycle)
var _occ := {}                 # Vector2i -> Mon, rebuilt each decision (fs.mon_at scans every Pokémon)
var _tc := {}                  # Vector2i -> can step there (this decision)
var _mobile := false
var _floats := false
var _swims := false
var _fire := false
var _lava_evader := false
var _house_avoider := false
var _relaxed := false              # second search: known traps and Monster House rooms don't block

func _init(d) -> void:
	dg = d

static func enabled() -> bool:
	return int(DungeonQoL.opt("qol_partner_ai")) == 1

func applies(m: Mon, mem: Dictionary) -> bool:
	if not enabled() or m == null or not m.is_team() or m.is_leader:
		return false
	if m.side == "client" or m.get_meta("story_npc", false) or m.get_meta("no_attack", false) or m.get_meta("escort", false):
		return false
	if Missions.is_client(m):
		return false
	return AI.tactic_of(m, mem) == "lets_go_together"

static var debug := false             # tests: print partners that stand still away from the leader

## Called from AI.decide after Red's status / item checks. {} = let Red's AI decide.
func decide(m: Mon, mem: Dictionary) -> Dictionary:
	var r := _decide(m, mem)
	if debug and applies(m, mem):
		var L: Mon = dg.fs.leader
		var still := str(r.get("type", "")) == "wait" or r.is_empty()
		var k := "dbg_still"
		mem[k] = int(mem.get(k, 0)) + 1 if still else 0
		if int(mem[k]) >= 5 and FloorState.cheb(m.pos, L.pos) > 2:
			print("PARTNERDBG %s still %d turns at %s leader %s dist %d goal=%s act=%s room=%d" % [m.name, int(mem[k]), m.pos, L.pos, FloorState.cheb(m.pos, L.pos), str(mem.get("last_goal", "?")), str(r), dg.fs.room_at(m.pos)])
	return r

func _decide(m: Mon, mem: Dictionary) -> Dictionary:
	if not applies(m, mem):
		return {}
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	if L == null or L.hp <= 0 or AI.st(m, "confused") > 0:
		return {}
	var foes := _foes(m)
	var low := m.hp * 4 <= m.max_hp
	mem.waiting = false
	mem.ally_skip = false
	mem.not_next_to_target = false
	# 1) attack, if something worth hitting is in reach
	if not AI.cannot_attack(m, mem):
		var a := best_attack(m, foes)
		if not a.is_empty():
			return a
	if not AI.species_can_move(m):
		return {"type": "wait"}
	if AI.st(m, "shadow_hold") > 0:
		return {"type": "wait"}
	if AI._can_take_item(m, fs, mem):
		return {"type": "item", "action": "pickup"}
	# 2) where to go
	var tgt := pick_target(m, foes)
	if low and tgt != null and FloorState.cheb(tgt.pos, m.pos) > 1:
		tgt = null
	if tgt == null and FloorState.cheb(m.pos, L.pos) <= 1 and not (low and not foes.is_empty()):
		return {"type": "wait"}               # next to the leader with nothing to do: no search needed
	_occ.clear()
	for o in fs.mons:
		if o.hp > 0:
			_occ[o.pos] = o
	var plan := _bfs(m, NEAR_DEPTH)
	var need_far := FloorState.cheb(m.pos, L.pos) >= NEAR_DEPTH - 2
	var goal := Vector2i(-1, -1)
	if tgt != null:
		goal = _attack_spot(m, tgt, plan)
		mem.last_goal = "foe"
	if goal.x < 0:
		goal = _follow_spot(m, L, foes, low, plan)
		mem.last_goal = "leader"
		if need_far and (goal.x < 0 or FloorState.cheb(goal, L.pos) > 1):
			plan = _bfs(m, SEARCH)              # the leader is far or out of sight: search the whole floor
			goal = _follow_spot(m, L, foes, low, plan)
			if goal.x < 0 or FloorState.cheb(goal, L.pos) > 2:
				_relaxed = true                     # blocked by a known trap / Monster House room: go through it
				plan = _bfs(m, SEARCH)
				_relaxed = false
				goal = _follow_spot(m, L, foes, low, plan)
		if FloorState.cheb(m.pos, L.pos) > 2 and (goal.x < 0 or goal == m.pos):
			return {}                               # no way to the leader found: Red's own following this turn
	if goal.x < 0 or goal == m.pos:
		if tgt != null:
			m.facing = AI.dir_toward(m.pos, tgt.pos)
		return {"type": "wait"}
	var step := _first_step(plan, m.pos, goal)
	if step < 0:
		return {}
	var to: Vector2i = m.pos + DB.DIRS[step]
	var o := fs.mon_at(to)
	if o != null:
		if o.is_team() and not o.is_leader and not Missions.is_client(o) and not o.get_meta("story_npc", false) \
				and not _busy(o):
			return {"type": "move", "dir": step, "swap": true}
		mem.ally_skip = true
		return {"type": "wait", "ally_skip": true}
	return {"type": "move", "dir": step}

# ------------------------------------------------------------------ foes and targets
func _foes(m: Mon) -> Array:
	var fs: FloorState = dg.fs
	var out: Array = []
	for o in fs.mons:
		if o.hp <= 0 or o == m:
			continue
		if AI.treatment(m, o, false, true) != AI.TREAT_ENEMY:
			continue
		if bool(o.get_meta("shopkeeper", false)):
			continue
		if AI.can_target_entity(fs, m, o) or AI.can_target_entity(fs, fs.leader, o):
			out.append(o)
	return out

func _leader_target(L: Mon) -> int:
	return int(L.get_meta("last_target_uid", -1))

## The foe this partner should go for, or null.
func pick_target(m: Mon, foes: Array) -> Mon:
	var L: Mon = dg.fs.leader
	var lt := _leader_target(L)
	var best: Mon = null
	var best_key := []
	for o in foes:
		var dl := FloorState.cheb(o.pos, L.pos)
		var dm := FloorState.cheb(o.pos, m.pos)
		if dl > ENGAGE and dm > ENGAGE:
			continue
		if dl > LEASH + 1:
			continue
		if dg.recruit_candidate(o):
			continue
		var prio := 2
		if dl <= 1:
			prio = 0
		elif o.uid == lt:
			prio = 1
		if prio == 2 and AI.is_sleeping(o) and dm > 1:
			continue                             # let sleeping foes lie
		var key := [prio, float(o.hp) / maxf(1.0, o.max_hp), dm]
		if best == null or _less(key, best_key):
			best = o
			best_key = key
	return best

static func _less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] < b[i]:
			return true
		if a[i] > b[i]:
			return false
	return false

## Is this partner in the middle of a fight (a foe next to it)? Then it isn't pushed aside.
func _busy(o: Mon) -> bool:
	for d in 8:
		var x: Mon = dg.fs.mon_at(o.pos + DB.DIRS[d])
		if x != null and dg.fs.is_foe(o, x):
			return true
	return false

# ------------------------------------------------------------------ attacks
## Estimated damage of md from att to tgt (one Combat.calc_damage run, side effects undone); -1 = immune.
func est_damage(att: Mon, tgt: Mon, md: Dictionary, regular: bool) -> int:
	var vis_a = att.get_meta("red_vis", 0)
	var vis_d = tgt.get_meta("red_vis", 0)
	var practice := att.has_meta("practice_swinger")
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	var ctx := {"weather": dg.fs.weather, "is_regular_attack": regular, "att_is_team": att.is_team(), "skip_accuracy2": true}
	var r: Dictionary = Combat.calc_damage(att, tgt, md, rng, ctx)
	att.set_meta("red_vis", vis_a)
	tgt.set_meta("red_vis", vis_d)
	if practice:
		att.set_meta("practice_swinger", true)
	if bool(r.get("missed_by_type", false)) or int(r.get("eff", 2)) == 0:
		return -1
	if int(r.get("heal", 0)) > 0 or bool(r.get("absorbed", false)):
		return -1
	return int(r.get("dmg", 0))

## The best attack this turn, or {}. Regular attack = move "".
func best_attack(m: Mon, foes: Array) -> Dictionary:
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	var held_back := {}
	for o in foes:
		if dg.recruit_candidate(o):
			held_back[o.uid] = true
	var options: Array = []          # [score, action]
	var n := mini(m.moves.size(), 4)
	var status_opts: Array = []
	for i in n + 1:
		var name := ""
		var md: Dictionary
		var chain: Array = []
		if i == n:
			if AI.iq(m, "exclusive move-user") or AI.iq(m, "exclusive move user"):
				continue
			md = DB.moves.get("Regular Attack", {"name": "Attack", "t": "None", "p": 1, "c": "P", "r": "front"})
		else:
			var mv = m.moves[i]
			if not AI._move_exists(mv) or AI._move_linked(mv):
				continue
			if not AI._move_on(mv) or not AI._can_ai_use_move(m, i, true):
				continue
			if AI.st(m, "taunt") > 0 and not AI.ignores_taunt(String(mv.name)):
				continue
			name = String(mv.name)
			md = DB.moves.get(name, {})
			if md.is_empty():
				continue
			chain = AI._chain_from(m, i)
		var r := str(md.get("r", "front"))
		var damaging := str(md.get("c", "P")) != "X" and int(md.get("p", 0)) > 0
		if not damaging:
			if name != "" and chain.size() <= 1:
				var c := AI.consider_move(m, fs, name)
				if c.ok and _status_useful(m, name, int(c.dir), held_back):
					status_opts.append({"type": "attack", "move": name, "dir": int(c.dir) & 7})
			continue
		var dirs: Array = [m.facing] if r in ["room", "room_all", "floor_all", "floor_foes", "user", "team_room", "team_floor", "floor", "special"] else range(8)
		for d in dirs:
			var targets: Array = dg.targets_for(m, md, d)
			if targets.is_empty():
				continue
			var score := 0.0
			var bad := false
			var any_foe := false
			for t in targets:
				if t == m:
					continue
				if not fs.is_foe(m, t):
					if r == "room_all" or r == "floor_all":
						bad = true                   # would hit a teammate
						break
					continue
				if held_back.has(t.uid):
					bad = true
					break
				var dmg := est_damage(m, t, md, name == "")
				if dmg < 0:
					continue
				any_foe = true
				var dealt := mini(dmg, t.hp)
				var s := float(dealt) / maxf(1.0, t.max_hp) * 100.0
				if dmg >= t.hp:
					s += 60.0                         # a KO
				if FloorState.cheb(t.pos, L.pos) <= 1:
					s += 15.0                         # protects the leader
				if t.uid == _leader_target(L):
					s += 8.0
				if AI.is_sleeping(t) and t.uid != _leader_target(L) and FloorState.cheb(t.pos, L.pos) > 1:
					s -= 40.0
				score += s
			if bad or not any_foe or score <= 0.0:
				continue
			if name == "":
				score += 2.0                          # ties (and KOs both can make) go to the PP-free attack
			var act := {"type": "attack", "move": name, "dir": int(d) & 7}
			if chain.size() > 1:
				act.chain = chain
			options.append([score, act])
	options.sort_custom(func(a, b): return a[0] > b[0])
	if not status_opts.is_empty():
		var weak: bool = options.is_empty() or float(options[0][0]) < 34.0
		if weak and dg.fs.rng.randi_range(0, 99) < STATUS_CHANCE:
			return status_opts[dg.fs.rng.randi_range(0, status_opts.size() - 1)]
	if options.is_empty():
		return {}
	return options[0][1]

## A status / self move: only when it would do something (the target doesn't already have it, the user isn't
## already boosted to the cap), and never aimed at a foe the leader is about to recruit.
func _status_useful(m: Mon, name: String, d: int, held_back: Dictionary) -> bool:
	var fs: FloorState = dg.fs
	if not AI.can_use_on_self_sc(m, fs, name):
		return false
	var md: Dictionary = DB.moves.get(name, {})
	var r := str(md.get("r", "front"))
	if r in ["user", "team_room", "team_floor", "floor", "special"]:
		return not _foes(m).is_empty()            # buffs only make sense with a foe around
	var hit := false
	for t in dg.targets_for(m, md, d):
		if t == m or not fs.is_foe(m, t):
			continue
		if held_back.has(t.uid) or not AI.can_use_on_target_sc(m, t, name):
			return false
		hit = true
	return hit

## Ranged damaging moves this partner can use: [[move dict, range kind]].
func _ranged(m: Mon) -> Array:
	var out: Array = []
	for i in mini(m.moves.size(), 4):
		var mv = m.moves[i]
		if not AI._move_exists(mv) or not AI._move_on(mv) or not AI._can_ai_use_move(m, i, true):
			continue
		var md: Dictionary = DB.moves.get(String(mv.name), {})
		var r := str(md.get("r", ""))
		if (r == "line" or r == "two_tiles") and str(md.get("c", "P")) != "X" and int(md.get("p", 0)) > 0:
			out.append(md)
	return out

# ------------------------------------------------------------------ movement
## Breadth-first search from m over tiles it can walk (Red's corner rule, impassable flags, known traps,
## House Avoider / Lava Evader). Teammates don't block the plan (they move or swap); foes and the leader do.
func _bfs(m: Mon, max_depth: int) -> Dictionary:
	_prep_walk(m)
	var fs: FloorState = dg.fs
	var w := fs.w
	var n := fs.w * fs.h
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(n)
	var start := fs.idx(m.pos)
	dist[start] = 0
	parent[start] = start
	var order: Array = [m.pos]
	var qi := 0
	while qi < order.size() and qi < SEARCH:
		var p: Vector2i = order[qi]
		qi += 1
		var pi := p.y * w + p.x
		var pd := dist[pi]
		if pd >= max_depth:
			continue
		var o0: Mon = _occ.get(p)
		if o0 != null and o0 != m and (not o0.is_team() or o0.is_leader or Missions.is_client(o0)):
			continue                              # reachable as a goal next to, but not through
		for d in 8:
			var to: Vector2i = p + DB.DIRS[d]
			if not fs.inb(to):
				continue
			var ti := to.y * w + to.x
			if dist[ti] >= 0 or not _edge_ok(m, p, d):
				continue
			dist[ti] = pd + 1
			parent[ti] = pi
			order.append(to)
	return {"order": order, "dist": dist, "parent": parent, "w": w}

static func _pd(plan: Dictionary, p: Vector2i) -> int:
	return plan.dist[p.y * int(plan.w) + p.x]

func _edge_ok(m: Mon, from: Vector2i, d: int) -> bool:
	var dv: Vector2i = DB.DIRS[d]
	if not _tile_ok(m, from + dv):
		return false
	if dv.x != 0 and dv.y != 0 and not _mobile:              # Red's corner rule (FloorState.can_step)
		var fs: FloorState = dg.fs
		if fs.terrain_at(Vector2i(from.x + dv.x, from.y)) == 0 or fs.terrain_at(Vector2i(from.x, from.y + dv.y)) == 0:
			return false
	return true

## Can m step onto p (FloorState.walkable + Red's AI tile checks)? Cached per decision.
func _tile_ok(m: Mon, p: Vector2i) -> bool:
	var c = _tc.get(p)
	if c != null:
		return c
	var fs: FloorState = dg.fs
	var ok := fs.inb(p)
	if ok and fs.flags.size() == fs.w * fs.h:
		var fl: int = fs.flags[fs.idx(p)]
		if fl & 1:
			ok = false
		elif (fl & 8) and not bool(fs.get_meta("monster_house_triggered", false)) and _house_avoider and not _relaxed:
			ok = false
	if ok and fs.traps.has(p) and not _relaxed:
		var tr: Dictionary = fs.traps[p]
		if bool(tr.get("seen", false)) or AI.st(m, "eyedrops") > 0:
			ok = false
	if ok:
		var t := fs.terrain_at(p)
		if t == 1:
			ok = true
		elif _mobile:
			ok = p.x >= 1 and p.y >= 1 and p.x < fs.w - 1 and p.y < fs.h - 1
		elif t == 0:
			ok = false
		elif _floats:
			ok = true
		elif t == 2 and fs.secondary == "water":
			ok = _swims
		elif t == 2 and fs.secondary == "lava":
			ok = _fire and not _lava_evader
		else:
			ok = false
	_tc[p] = ok
	return ok

func _prep_walk(m: Mon) -> void:
	var fs: FloorState = dg.fs
	_tc.clear()
	_mobile = fs.is_mobile(m)
	_floats = "Flying" in m.types or m.ability == "levitate" or "Ghost" in m.types
	_swims = "Water" in m.types or int(m.status.get("slip", 0)) > 0
	_fire = "Fire" in m.types
	_lava_evader = AI.iq(m, "lava evader")
	_house_avoider = AI.iq(m, "house avoider")

## Is tile p free to stand on (nobody there, or m itself)?
func _free(m: Mon, p: Vector2i) -> bool:
	var o: Mon = _occ.get(p)
	return o == null or o == m

## Nearest reachable tile from which a regular attack or a ranged move hits tgt.
func _attack_spot(m: Mon, tgt: Mon, plan: Dictionary) -> Vector2i:
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	var ranged := _ranged(m)
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	for p in plan.order:
		var dd := _pd(plan, p)
		if dd >= bd or not _free(m, p):
			continue
		if FloorState.cheb(p, L.pos) > LEASH:
			continue
		if _can_hit_from(p, tgt, ranged):
			best = p
			bd = dd
	return best

func _can_hit_from(p: Vector2i, tgt: Mon, ranged: Array) -> bool:
	var fs: FloorState = dg.fs
	var dx := tgt.pos.x - p.x
	var dy := tgt.pos.y - p.y
	var dist := maxi(absi(dx), absi(dy))
	if dist == 0:
		return false
	if not (dx == 0 or dy == 0 or absi(dx) == absi(dy)):
		return false
	var d := AI.dir_toward(p, tgt.pos)
	if dist == 1:
		return fs.can_attack_dir(p, d)
	for md in ranged:
		var rng := 2 if str(md.r) == "two_tiles" else Dungeon.LINE_RANGE
		if dist > rng:
			continue
		var clear := true
		var q := p
		for i in dist - 1:
			q += DB.DIRS[d]
			if fs.is_wall(q) or _occ.has(q):
				clear = false
				break
		if clear and fs.can_attack_dir(p, d):
			return true
	return false

## Where to stand when not fighting: next to the leader (behind it, away from foes, when hurt). Stays put if
## already close enough and not in the way.
func _follow_spot(m: Mon, L: Mon, foes: Array, low: bool, plan: Dictionary) -> Vector2i:
	var dcur := FloorState.cheb(m.pos, L.pos)
	var near_foe: Mon = null
	var nfd := 1 << 30
	for o in foes:
		var k := FloorState.cheb(o.pos, L.pos)
		if k < nfd:
			nfd = k
			near_foe = o
	if dcur <= 1 and not (low and near_foe != null):
		return m.pos
	var best := Vector2i(-1, -1)
	var best_key := []
	for d in 8:
		var p: Vector2i = L.pos + DB.DIRS[d]
		if not dg.fs.inb(p) or _pd(plan, p) < 0 or not _free(m, p):
			continue
		var away := 0
		if low and near_foe != null:
			away = -FloorState.cheb(p, near_foe.pos)
		var key := [away, _pd(plan, p)]
		if best.x < 0 or _less(key, best_key):
			best = p
			best_key = key
	if best.x >= 0:
		return best
	if dcur <= 2:
		return m.pos                              # every spot next to the leader is taken: close is fine
	# leader boxed in or out of reach: the reachable tile closest to it
	var bd := 1 << 30
	for p in plan.order:
		if not _free(m, p):
			continue
		var k := FloorState.cheb(p, L.pos) * 100 + _pd(plan, p)
		if k < bd:
			bd = k
			best = p
	return best

func _first_step(plan: Dictionary, from: Vector2i, goal: Vector2i) -> int:
	var fs: FloorState = dg.fs
	if not fs.inb(goal) or _pd(plan, goal) < 0:
		return -1
	var w := int(plan.w)
	var parent: PackedInt32Array = plan.parent
	var fi := from.y * w + from.x
	var pi := goal.y * w + goal.x
	var guard := 0
	while parent[pi] != fi and guard < SEARCH:
		pi = parent[pi]
		guard += 1
	if parent[pi] != fi:
		return -1
	var dv := Vector2i(pi % w, pi / w) - from
	for d in 8:
		if DB.DIRS[d] == dv:
			return d
	return -1
