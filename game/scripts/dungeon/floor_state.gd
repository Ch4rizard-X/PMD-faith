class_name FloorState
extends RefCounted
## Everything about the current floor that game logic and AI query.
## Coordinates are tile positions (Vector2i). Map is w x h (Red: 56 x 32).

var w := 56
var h := 32
var terrain := PackedByteArray()     # 0 wall, 1 floor, 2 water/lava (secondary), 3 chasm
var room := PackedByteArray()        # room index, 255 = corridor
var flags := PackedInt32Array()      # see DungeonGen flag bits
var explored := PackedByteArray()    # 1 = seen by the team (minimap)
var rooms: Array = []                # Array[Rect2i]
var stairs := Vector2i(-1, -1)
var items: Dictionary = {}           # Vector2i -> {id: String, n: int, sticky: bool, price: int}
var traps: Dictionary = {}           # Vector2i -> {id: String, seen: bool}
var mons: Array = []                 # Array[Mon], everyone alive on the floor
var leader: Mon = null
var secondary := "water"             # what terrain 2 is on this floor: "water" | "lava"
var visibility := 0                  # Red visibilityRange (0 = normal rooms lit)
var weather := "clear"
var turn := 0
var floor_no := 1
var dungeon_key := ""
var monster_house_room := -1
var rng := RandomNumberGenerator.new()

func setup(gen: Dictionary) -> void:
	w = gen.w
	h = gen.h
	terrain = gen.terrain
	room = gen.room
	flags = gen.flags
	rooms = gen.get("rooms", [])
	stairs = gen.stairs
	monster_house_room = gen.get("monster_house_room", -1)
	explored = PackedByteArray()
	explored.resize(w * h)

func inb(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h

func idx(p: Vector2i) -> int:
	return p.y * w + p.x

func terrain_at(p: Vector2i) -> int:
	return terrain[idx(p)] if inb(p) else 0

func room_at(p: Vector2i) -> int:
	if not inb(p):
		return 255
	return room[idx(p)]

func in_room(p: Vector2i) -> bool:
	return room_at(p) != 255

func is_wall(p: Vector2i) -> bool:
	return terrain_at(p) == 0

## Can mon m stand on p (terrain only; ignores other Pokémon)? Water/lava need the right type/ability.
func walkable(p: Vector2i, m: Mon = null) -> bool:
	var t := terrain_at(p)
	if t == 1:
		return true
	if m != null and is_mobile(m):
		return p.x >= 1 and p.y >= 1 and p.x < w - 1 and p.y < h - 1     # Mobile: walls, water, lava (not the edge)
	if t == 0:
		return false
	if m == null:
		return false
	if "Flying" in m.types or m.ability == "levitate" or "Ghost" in m.types:
		return true
	if t == 2 and secondary == "water":
		return "Water" in m.types or int(m.status.get("slip", 0)) > 0      # Slip Seed
	if t == 2 and secondary == "lava":
		return "Fire" in m.types
	return false

## Mobile status (Mobile Orb) or a Mobile Scarf: moves through walls, water and lava.
func is_mobile(m: Mon) -> bool:
	return int(m.status.get("mobile", 0)) > 0 or m.held == "mobilescarf" or EosItems.has(m, "mobile")

func mon_at(p: Vector2i) -> Mon:
	for m in mons:
		if m.hp > 0 and m.pos == p:
			return m
	return null

## Red forbids diagonal steps that cut a wall corner.
func can_step(from: Vector2i, d: int, m: Mon = null) -> bool:
	var dv: Vector2i = DB.DIRS[d]
	var to := from + dv
	if not walkable(to, m):
		return false
	if dv.x != 0 and dv.y != 0 and not (m != null and is_mobile(m)):
		if is_wall(Vector2i(from.x + dv.x, from.y)) or is_wall(Vector2i(from.x, from.y + dv.y)):
			return false
	return true

## Can an attack go from 'from' in direction d (same corner rule as walking, but water doesn't block)?
func can_attack_dir(from: Vector2i, d: int) -> bool:
	var dv: Vector2i = DB.DIRS[d]
	if is_wall(from + dv):
		return false
	if dv.x != 0 and dv.y != 0:
		if is_wall(Vector2i(from.x + dv.x, from.y)) or is_wall(Vector2i(from.x, from.y + dv.y)):
			return false
	return true

func is_foe(a: Mon, b: Mon) -> bool:
	if a.side == "client" or b.side == "client":   # rescue-job clients are neutral
		return false
	if a.has_meta("shopkeeper") or b.has_meta("shopkeeper"):   # Red: the shopkeeper is ignored (TREATMENT_IGNORE)
		return false
	return a.side != b.side

func foes_of(m: Mon) -> Array:
	var out: Array = []
	for o in mons:
		if o.hp > 0 and is_foe(m, o):
			out.append(o)
	return out

func allies_of(m: Mon) -> Array:
	var out: Array = []
	for o in mons:
		if o.hp > 0 and o != m and not is_foe(m, o):
			out.append(o)
	return out

func team() -> Array:
	var out: Array = []
	for o in mons:
		if o.hp > 0 and o.is_team():
			out.append(o)
	return out

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## Red's sight: inside a lit room you see the whole room plus its border ring; in corridors, 1 tile around you
## (2 in Red when visibility is normal). 'visibility' > 0 limits room sight to that radius (dark floors).
func can_see(a: Mon, target_pos: Vector2i) -> bool:
	var ra := room_at(a.pos)
	if visibility > 0:
		return cheb(a.pos, target_pos) <= visibility
	if ra != 255:
		if room_at(target_pos) == ra:
			return true
		# tiles bordering the room (doorways) are visible from inside
		var r: Rect2i = rooms[ra] if ra < rooms.size() else Rect2i()
		if r.size != Vector2i.ZERO and r.grow(1).has_point(target_pos):
			return true
	return cheb(a.pos, target_pos) <= 2

func adjacent_foes(m: Mon) -> Array:
	var out: Array = []
	for d in 8:
		var o := mon_at(m.pos + DB.DIRS[d])
		if o and is_foe(m, o) and can_attack_dir(m.pos, d):
			out.append(o)
	return out

func free_tile_near(p: Vector2i, m: Mon = null, radius := 3) -> Vector2i:
	for r in range(0, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var q := p + Vector2i(dx, dy)
				if walkable(q, m) and mon_at(q) == null:
					return q
	return Vector2i(-1, -1)

## Breadth-first path step from 'from' toward 'to' for mon m. Returns direction index or -1.
## Other Pokémon block unless pass_allies is true (team members can swap with each other).
func path_dir(m: Mon, to: Vector2i, max_nodes := 900, pass_allies := false) -> int:
	if m.pos == to:
		return -1
	var prev := {}
	var q: Array = [m.pos]
	prev[m.pos] = m.pos
	var head := 0
	var found := false
	while head < q.size() and head < max_nodes:
		var c: Vector2i = q[head]
		head += 1
		if c == to:
			found = true
			break
		for d in 8:
			if not can_step(c, d, m):
				continue
			var n: Vector2i = c + DB.DIRS[d]
			if prev.has(n):
				continue
			var o := mon_at(n)
			if o and n != to and not (pass_allies and not is_foe(m, o) and not o.is_leader):
				continue
			prev[n] = c
			q.append(n)
	if not found:
		return -1
	var cur := to
	while prev[cur] != m.pos:
		cur = prev[cur]
	return DB.dir_index(cur - m.pos)

# ------------------------------------------------------------------ AI helpers (appended for ai.gd; Red refs inline)
var _red_exits_cache: Dictionary = {}   # room index -> Array[Vector2i]

## gDungeon->naturalJunctionList[room] (built by sub_804EB30, dungeon_generation.c): every tile with
## TERRAIN_TYPE_NATURAL_JUNCTION in that room, scanned x-major then y, at most MAX_ROOM_COUNT (32) entries.
func red_room_exits(r: int) -> Array:
	if r == 255 or r < 0:
		return []
	if _red_exits_cache.is_empty():
		for x in w:
			for y in h:
				var p := Vector2i(x, y)
				if not red_is_junction(p):
					continue
				var rr := room_at(p)
				if rr == 255:
					continue
				if not _red_exits_cache.has(rr):
					_red_exits_cache[rr] = []
				if _red_exits_cache[rr].size() < 32:
					_red_exits_cache[rr].append(p)
		_red_exits_cache[-1] = []   # marks the cache as built even on floors without junctions
	return _red_exits_cache.get(r, [])

## Call after changing terrain/flags (e.g. a new floor reusing this object).
func red_reset_cache() -> void:
	_red_exits_cache = {}

## TERRAIN_TYPE_NATURAL_JUNCTION (DungeonGen.FLAG_JUNCTION = 2).
func red_is_junction(p: Vector2i) -> bool:
	if not inb(p) or flags.size() != w * h:
		return false
	return (flags[idx(p)] & 2) != 0

## Tile.walkableNeighborFlags for mon m at p: bit d set when m could step from p in direction d
## (terrain + Red's no-corner-cutting rule; Pokémon are ignored, like the real flags).
func red_walk_mask(p: Vector2i, m: Mon = null) -> int:
	var mask := 0
	for d in 8:
		if can_step(p, d, m):
			mask |= 1 << d
	return mask

## IsPositionWithinTwoTiles (dungeon_range.c): Chebyshev <= 1, or exactly 2 with both 2-step walks
## (from each end toward the other) staying on non-wall tiles.
func red_within_two_tiles(a: Vector2i, b: Vector2i) -> bool:
	if absi(a.x - b.x) < 2 and absi(a.y - b.y) < 2:
		return true
	if cheb(a, b) != 2:
		return false
	var c := a
	for i in 2:
		c += Vector2i(signi(b.x - c.x), signi(b.y - c.y))
		if is_wall(c):
			return false
	c = b
	for i in 2:
		c += Vector2i(signi(a.x - c.x), signi(a.y - c.y))
		if is_wall(c):
			return false
	return true

func _red_room_has(r: int, p: Vector2i) -> bool:
	if r < 0 or r >= rooms.size():
		return false
	var rect: Rect2i = rooms[r]
	if rect.size == Vector2i.ZERO:
		return false
	return rect.grow(1).has_point(p)   # roomData min-1 <= p < (max+1)+1

## IsPositionInSight (dungeon_range.c) — used by CanTargetEntity / CanTargetPosition (AI targeting):
## whole room plus its border ring when standing in a room, otherwise within 2 tiles (2 needs a clear line).
func red_in_sight(origin: Vector2i, target: Vector2i) -> bool:
	var r := room_at(origin)
	if r != 255 and _red_room_has(r, target):
		return true
	var d := cheb(origin, target)
	if d > 2:
		return false
	if d == 2:
		return red_within_two_tiles(origin, target)
	return true

## GetVisibilityRange (dungeon_range.h): visibilityRange, 0 meaning 2.
func red_visibility_range() -> int:
	return 2 if visibility == 0 else visibility

## IsPositionActuallyInSight (dungeon_range.c) — used by CanSeeTarget: in a corridor, a square of
## GetVisibilityRange(); in a room, only the room plus its border ring.
func red_actually_in_sight(origin: Vector2i, target: Vector2i) -> bool:
	var r := room_at(origin)
	if r == 255:
		var v := red_visibility_range()
		return absi(origin.x - target.x) <= v and absi(origin.y - target.y) <= v
	return _red_room_has(r, target)
