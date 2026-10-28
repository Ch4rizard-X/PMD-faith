class_name GAutopilot
extends RefCounted
## Test driver for the ground engine (--storytest): when the player is free to walk, it walks to event
## triggers and talks to people/objects, preferring whatever it has used least (BFS over the 8px
## collision grid), so the story can run unattended. Never used in normal play.

var G
var counts := {}         # target key -> times used (shared across maps / grounds by the caller)
var target := {}         # {kind:"event"/"talk", key, rect:[a,b] tiles}
var path: Array = []
var stuck := 0
var idle := 0
var last_pos := Vector2i(-1, -1)
var _map := -1
var target_t := 0
var _talk_seq := 0
var _talk_face := -1
var _came_from := ""     # event we arrived on (avoid walking straight back out)

func _init(ground) -> void:
	G = ground

func _player():
	for L in G.lives:
		if L.kind_id != -1 and (L.flags & 0x800):
			return L
	return null

func _tile_box(L) -> Array:
	var a: Vector2i = L.p144
	var b: Vector2i = L.p14C
	var t0 := Vector2i(a.x >> 11, a.y >> 11)
	var t1 := Vector2i((b.x - 1) >> 11, (b.y - 1) >> 11)
	return [t0, t1 - t0 + Vector2i.ONE]

var _blockers: Array = []    # [a, b] tile rects of other solid lives

func _free(p: Vector2i, sz: Vector2i) -> bool:
	if G.map_collide(p, sz, 0x80):
		return false
	for r in _blockers:
		if p.x < r[1].x and p.x + sz.x > r[0].x and p.y < r[1].y and p.y + sz.y > r[0].y:
			return false
	return true

func _collect_blockers() -> void:
	_blockers = []
	var P = _player()
	for M in G.lives:
		if M != P and M.kind_id != -1 and (M.flags & 4):
			var tb := _tile_box(M)
			_blockers.append([tb[0], tb[0] + tb[1]])
	for T in G.objects:
		if T.kind != -1 and (T.flags & 4):
			_blockers.append([Vector2i(T.p124.x >> 11, T.p124.y >> 11), Vector2i((T.p12C.x - 1) >> 11, (T.p12C.y - 1) >> 11) + Vector2i.ONE])

func _bump(key: String, n := 1) -> void:
	counts[key] = int(counts.get(key, 0)) + n

const NO_INPUT := {"dir": -1, "a_pressed": false, "b_held": false, "b_pressed": false, "menu_pressed": false, "up": false, "down": false}

## Called every tick from Ground._poll_input; returns an input dict or {} to leave input alone.
func drive() -> Dictionary:
	if G.vis_map != _map:
		_map = G.vis_map
		target = {}
		path = []
		idle = 0
		_came_from = "?"
	var L = _player()
	if L == null or G.text.is_open() or G.text._menu != null or G.any_locked:
		idle = 0
		return {}
	if L.ctrl_mode() != 1:
		idle = 0
		return {}
	# talking: face the target for a few frames, then press A on its own frame
	if _talk_seq > 0:
		_talk_seq -= 1
		var ot := NO_INPUT.duplicate()
		if _talk_seq >= 2:
			ot.dir = _talk_face
		elif _talk_seq == 0:
			ot.a_pressed = true
		return ot
	idle += 1
	if idle < 20:
		return {}
	var tb := _tile_box(L)
	var pos: Vector2i = tb[0]
	var sz: Vector2i = tb[1]
	# plan with the nominal footprint (the live box can straddle an extra tile mid-step)
	var nominal := Vector2i(maxi(1, (L.size.x + 2047) >> 11), maxi(1, (L.size.y + 2047) >> 11))
	sz = Vector2i(mini(sz.x, nominal.x), mini(sz.y, nominal.y))
	if _came_from == "?":
		_came_from = ""
		for i in G.events.size():
			var e: Dictionary = G.events[i]
			if e.used and (int(e.flags) & 0x20):
				var a := Vector2i(e.a.x >> 11, e.a.y >> 11)
				var b := Vector2i(e.b.x >> 11, e.b.y >> 11)
				if (a - pos).length_squared() < 64 or (pos.x + sz.x >= a.x - 2 and pos.x <= b.x + 2 and pos.y + sz.y >= a.y - 2 and pos.y <= b.y + 2):
					_came_from = _ekey(i, e)
	if target.is_empty():
		_pick_target(L, pos, sz)
		if target.is_empty():
			return {}
		path = []
		stuck = 0
		target_t = 0
	target_t += 1
	var r: Array = target.rect
	if target.kind == "talk":
		var spot := _talk_spot(pos, sz, r)
		if spot >= 0 and (spot == int(target.side) or path.is_empty() == false and path.size() <= 1):
			var face := GDir.vec_dir8([Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)][spot])
			_log("autopilot: talk %s" % target.key)
			target = {}
			idle = 0
			_talk_face = face
			_talk_seq = 5
			return {}
	else:
		if pos.x < r[1].x and pos.x + sz.x > r[0].x and pos.y < r[1].y and pos.y + sz.y > r[0].y:
			target = {}
			idle = 0
			return {}
	if pos == last_pos:
		stuck += 1
	else:
		stuck = 0
	last_pos = pos
	if stuck > 90 or target_t > 900:
		# keep pushing into the goal a little (doors behind solid tiles), then give up
		_log("autopilot: gave up on %s at %s" % [target.key, pos])
		_stuck_at = int(_stuck_at) + 1 if pos == _stuck_pos else 1
		_stuck_pos = pos
		if _stuck_at >= 3 and _hop_near(L, sz, r):
			_stuck_at = 0
		_bump(target.key, 0 if target.kind == "talk" else 3)
		target = {}
		return {}
	if path.is_empty() or G._frame % 16 == 0:
		path = _bfs(pos, sz, r, int(target.side) if target.kind == "talk" else -1)
		if path.is_empty():
			_log("autopilot: no path to %s rect=%s side=%s pos=%s sz=%s" % [target.key, target.rect, target.get("side", -1), pos, sz])
			_stuck_at = int(_stuck_at) + 1 if pos == _stuck_pos else 1
			_stuck_pos = pos
			if _stuck_at >= 6 and _hop_near(L, sz, r):
				_stuck_at = 0
			_bump(target.key, 0 if target.kind == "talk" else 5)   # talk: the pick already moved it to the next side
			target = {}
			return {}
	while not path.is_empty() and path[0] == pos:
		path.pop_front()
	if path.is_empty():
		return {}
	# steer the real (sub-tile) hitbox onto the next cell so it doesn't snag on corridor corners
	var want := Vector2i(path[0].x << 11, path[0].y << 11)
	var dv: Vector2i = want - L.p144
	var o2 := NO_INPUT.duplicate()
	o2.dir = GDir.vec_dir8(Vector2i(signi(dv.x) if absi(dv.x) > 0x80 else 0, signi(dv.y) if absi(dv.y) > 0x80 else 0))
	if o2.dir == -1:
		var step: Vector2i = path[0] - pos
		o2.dir = GDir.vec_dir8(Vector2i(signi(step.x), signi(step.y)))
	return o2

var _stuck_at := 0
var _stuck_pos := Vector2i(-1, -1)

## Tests only: boxed in by a crowd of actors with nowhere to go (Pokémon Square at 15,8): hop the leader onto the
## free tile nearest the target so the story can go on.
func _hop_near(L, sz: Vector2i, r: Array) -> bool:
	_collect_blockers()
	var best := Vector2i(-1, -1)
	var bd := 1 << 30
	var c: Vector2i = (r[0] + r[1]) / 2
	for y in range(c.y - 8, c.y + 9):
		for x in range(c.x - 8, c.x + 9):
			var p := Vector2i(x, y)
			if p.x < r[1].x + 1 and p.x + sz.x > r[0].x - 1 and p.y < r[1].y + 1 and p.y + sz.y > r[0].y - 1:
				continue
			if not _free(p, sz):
				continue
			var d := (p - c).length_squared()
			if d < bd:
				bd = d
				best = p
	if best.x < 0:
		return false
	_log("autopilot: boxed in, hop to %s" % best)
	var dv: Vector2i = Vector2i(best.x << 11, best.y << 11) - L.p144
	L.p144 += dv
	L.p14C += dv
	return true

func _ekey(i: int, e: Dictionary) -> String:
	return "%d:e%d,%d" % [G.vis_map, e.a.x >> 11, e.a.y >> 11]

func _pick_target(L, pos: Vector2i, sz: Vector2i) -> void:
	var cands: Array = []
	for i in G.events.size():
		var e: Dictionary = G.events[i]
		if not e.used or not (int(e.flags) & 0x20):
			continue
		var key := _ekey(i, e)
		var a := Vector2i(e.a.x >> 11, e.a.y >> 11)
		var b := Vector2i(e.b.x >> 11, e.b.y >> 11)
		if pos.x < b.x and pos.x + sz.x > a.x and pos.y < b.y and pos.y + sz.y > a.y:
			continue
		var pen := 2 if key == _came_from else 0
		cands.append({"kind": "event", "key": key, "rect": [a, b], "n": int(counts.get(key, 0)) + pen})
	# story hint: holding a peeled Chestnut for the Mankey gang (SCENARIO_SUB1 30) -> talk to the base's residents first
	var hint := GVars.scenario(GVars.SCENARIO_SUB1).x == 30 and Game.bag.any(func(b): return str(b.get("id", "")) == "chestnut")
	for M in G.lives:
		if M == L or M.kind_id == -1 or not (M.flags & 0xC0 or hint):
			continue
		var key := "%d:t%d" % [G.vis_map, M.kind_id]
		var tb := _tile_box(M)
		var n1 := int(counts.get(key, 0))
		# chatting with townsfolk rarely moves the story: try doors / objects first
		cands.append({"kind": "talk", "key": key, "rect": [tb[0], tb[0] + tb[1]], "n": n1 + (-3 if hint else 2), "side": n1 % 4})
	for T in G.objects:
		if T.kind == -1 or T.action == null:
			continue
		var info = T.action.predefined_info(2)
		if info.ptr == GData.NULL_PTR:
			continue
		var key := "%d:o%d,%d" % [G.vis_map, T.p124.x >> 11, T.p124.y >> 11]
		var a := Vector2i(T.p124.x >> 11, T.p124.y >> 11)
		var b := Vector2i((T.p12C.x - 1) >> 11, (T.p12C.y - 1) >> 11) + Vector2i.ONE
		var n2 := int(counts.get(key, 0))
		cands.append({"kind": "talk", "key": key, "rect": [a, b], "n": n2, "side": n2 % 4})
	if cands.is_empty():
		return
	cands.sort_custom(func(x, y):
		if x.n != y.n:
			return x.n < y.n
		return (x.rect[0] - pos).length_squared() < (y.rect[0] - pos).length_squared())
	target = cands[0]
	_bump(target.key)
	_log("autopilot: -> %s (n=%d)" % [target.key, target.n])

## Standing next to rect r on the given side (0 below, 1 right, 2 left, 3 above), overlapping it along the other axis.
## A spot from which A-button talk can reach rect r: lined up with it on one axis, at most four tiles
## away on the other (the game's _talk_ahead decides whether a counter in between is OK). Returns the
## facing direction index (0 up-facing from below, 1 from the right, 2 from the left, 3 from above) or -1.
func _talk_spot(p: Vector2i, sz: Vector2i, r: Array) -> int:
	# our centre must be inside the target's span (the game probes a narrow box straight ahead)
	var cx := p.x * 2 + sz.x
	var cy := p.y * 2 + sz.y
	var ox: bool = cx > r[0].x * 2 and cx < r[1].x * 2
	var oy: bool = cy > r[0].y * 2 and cy < r[1].y * 2
	# the game's probe reaches about a tile; farther only across collision bit 0x10 (shop counters, the
	# pond's water: sub_80AA3F8 keeps probing up to 0x600 + 0x2000 + 0x800 px ahead, ~7 tiles)
	for g in 8:
		if ox and p.y == r[1].y + g and (g <= 1 or G.map_collide(Vector2i(p.x, r[1].y), Vector2i(sz.x, g), 0x10)):
			return 0
		if oy and p.x == r[1].x + g and (g <= 1 or G.map_collide(Vector2i(r[1].x, p.y), Vector2i(g, sz.y), 0x10)):
			return 1
		if oy and p.x + sz.x + g == r[0].x and (g <= 1 or G.map_collide(Vector2i(p.x + sz.x, p.y), Vector2i(g, sz.y), 0x10)):
			return 2
		if ox and p.y + sz.y + g == r[0].y and (g <= 1 or G.map_collide(Vector2i(p.x, p.y + sz.y), Vector2i(sz.x, g), 0x10)):
			return 3
	return -1

func _talk_goal(p: Vector2i, sz: Vector2i, r: Array, side: int) -> bool:
	return _talk_spot(p, sz, r) == side

func _bfs(start: Vector2i, sz: Vector2i, r: Array, side: int) -> Array:
	_collect_blockers()
	var goal_test := func(p: Vector2i) -> bool:
		if side >= 0:
			return _talk_goal(p, sz, r, side)
		# stand fully inside the trigger along any axis it is wide enough for (doors sit between walls)
		var okx: bool = (p.x >= r[0].x and p.x + sz.x <= r[1].x) if r[1].x - r[0].x >= sz.x else (p.x < r[1].x and p.x + sz.x > r[0].x)
		var oky: bool = (p.y >= r[0].y and p.y + sz.y <= r[1].y) if r[1].y - r[0].y >= sz.y else (p.y < r[1].y and p.y + sz.y > r[0].y)
		return okx and oky
	var prev := {start: start}
	var q: Array = [start]
	var qi := 0
	var dirs := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
	var found = null
	while qi < q.size() and qi < 40000:
		var p: Vector2i = q[qi]
		qi += 1
		if goal_test.call(p):
			found = p
			break
		for d in dirs:
			var n: Vector2i = p + d
			if prev.has(n):
				continue
			if not _free(n, sz):
				continue
			prev[n] = p
			q.append(n)
	if found == null:
		return []
	var out: Array = []
	var c: Vector2i = found
	while c != start:
		out.push_front(c)
		c = prev[c]
	return out

func _log(s: String) -> void:
	print("  ", s)
