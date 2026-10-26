extends SceneTree
## Headless test for res://scripts/dungeon/dungeon_gen.gd
## cd game && godot --headless --path . --script tests/run_gen.gd

const Gen := preload("res://scripts/dungeon/dungeon_gen.gd")
const SEEDS := 300

# [label, 28-byte FloorProperties hex, overrides]
var CASES := [
	["TinyWoods F1", "01 05 0e 01 00 0f 04 00 00 00 00 00 00 00 00 02 00 01 00 05 00 00 00 01 01 00 00 00", {}],
	["TinyWoods F2", "01 06 0e 01 00 0f 04 00 00 00 00 00 00 00 00 02 00 02 00 05 00 00 00 01 01 00 00 00", {}],
	["TinyWoods F3", "01 06 0e 01 00 0f 04 00 00 00 00 00 00 00 00 02 00 03 00 05 00 00 00 01 01 00 00 00", {}],
	["FrostyForest F4 (shop, sec)", "0b 06 24 0a 00 14 03 07 00 00 00 01 00 01 00 04 03 04 00 0f 00 28 00 02 06 00 00 00", {}],
	["MagmaCavern F8 (lava, MH)", "00 08 3b 0c 00 14 07 00 08 00 00 00 00 01 00 04 04 08 00 0f 00 00 02 07 07 00 00 00", {}],
	["SilverTrench F5 (sec, MH, ss10)", "01 12 00 05 00 28 05 00 07 00 00 00 0a 01 01 04 08 05 00 0f 00 1e 00 02 07 00 00 00", {}],
	["SilverTrench F45 (sec, MH, maze, ss10)", "01 08 31 0b 00 14 05 00 07 01 00 01 0a 01 01 04 08 2d 00 0f 00 1e 02 05 07 00 00 00", {}],
	["SilverTrench F6 (beetle, MH)", "09 14 00 05 00 1e 05 00 07 01 00 01 00 00 00 04 08 06 00 0f 00 14 00 02 07 00 00 00", {}],
	["SilverTrench F15 (one-room MH, sec)", "02 08 00 05 00 14 05 00 07 01 00 01 00 01 01 06 08 0f 00 0f 00 1e 00 02 07 00 00 00", {}],
	["SkyTower F3 (chasm, MH)", "00 05 23 0d 00 32 04 00 05 00 00 01 00 01 00 03 04 03 00 00 00 00 00 08 07 00 00 00", {}],
	["MtThunder F7 (outer ring)", "03 05 2a 06 00 14 06 00 00 00 00 00 00 00 00 05 03 07 00 0f 00 0a 00 05 04 00 00 00", {}],
	["MtThunder F8 (crossroads)", "04 09 2a 06 00 14 06 00 00 00 00 00 00 00 00 05 03 08 00 23 00 0a 00 05 04 00 00 00", {}],
	["MtSteel F4 (layout 8)", "08 08 27 03 00 0c 06 00 00 00 00 00 00 00 00 04 03 04 00 00 00 0b 00 03 03 00 00 00", {}],
	["GreatCanyon F8 (layout 13, sec)", "0d 06 2c 07 00 14 07 00 00 00 00 00 00 01 00 04 03 08 00 0f 00 0a 00 07 05 00 00 00", {}],
	# Synthetic variants to exercise the remaining layouts / flags
	["synthetic: two rooms + MH", "01 06 0e 01 00 0f 04 00 00 00 00 00 00 00 00 02 00 01 00 05 00 00 00 01 01 00 00 00", {"layout": 5}],
	["synthetic: line", "01 06 0e 01 00 0f 04 05 05 00 00 00 00 01 00 02 02 01 00 05 00 00 00 01 01 00 00 00", {"layout": 6}],
	["synthetic: cross", "01 06 0e 01 00 0f 04 05 05 00 00 00 00 00 00 02 02 01 00 05 00 00 00 01 01 00 00 00", {"layout": 7}],
	["synthetic: outer rooms (sec)", "01 06 0e 01 00 0f 04 05 05 00 00 00 05 01 00 02 02 01 00 05 00 00 00 01 01 00 00 00", {"layout": 10}],
	["synthetic: imperfections, high MH, no dead ends", "00 06 0e 01 00 14 06 00 50 00 00 00 00 05 00 04 04 01 00 0f 04 05 00 01 01 00 00 00", {}],
	["synthetic: shop 100%", "0b 06 24 0a 00 14 03 64 00 00 00 01 00 00 00 03 03 01 00 0f 00 28 00 02 06 00 00 00", {}],
	["synthetic: fixed room -> standard", "01 06 0e 01 00 0f 04 00 00 00 00 00 00 00 00 02 00 01 05 05 00 00 00 01 01 00 00 00", {}],
]

var failures := 0


func _init() -> void:
	var total_floors := 0
	var total_ms := 0.0
	var worst_ms := 0.0
	for c in CASES:
		var props: Dictionary = Gen.props_from_bytes(hex_to_bytes(c[1]))
		for k in c[2]:
			props[k] = c[2][k]
		var stats := {"ok": 0, "fail": 0, "fallback": 0, "mh": 0, "shop": 0, "maze": 0, "sec": 0,
			"rooms_min": 999, "rooms_max": 0, "enemies": 0, "items": 0, "traps": 0, "mh_enemy_on_stairs": 0, "player_on_stairs": 0}
		var case_ms := 0.0
		var case_worst := 0.0
		for s in SEEDS:
			var t0 := Time.get_ticks_usec()
			var f: Dictionary = Gen.generate(props, s)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			case_ms += ms
			case_worst = maxf(case_worst, ms)
			var errs := validate(f, stats)
			if errs.is_empty():
				stats.ok += 1
			else:
				stats.fail += 1
				failures += 1
				if stats.fail <= 3:
					print("  FAIL %s seed %d: %s" % [c[0], s, ", ".join(errs)])
					print(ascii(f))
		total_floors += SEEDS
		total_ms += case_ms
		worst_ms = maxf(worst_ms, case_worst)
		print("%-48s ok %3d/%d  avg %.1f ms  max %.1f ms  rooms %d-%d  fallback %d  MH %d  shop %d  maze %d  sec %d  avg enemies %.1f items %.1f traps %.1f%s%s" % [
			c[0], stats.ok, SEEDS, case_ms / SEEDS, case_worst, stats.rooms_min, stats.rooms_max,
			stats.fallback, stats.mh, stats.shop, stats.maze, stats.sec,
			float(stats.enemies) / SEEDS, float(stats.items) / SEEDS, float(stats.traps) / SEEDS,
			("  [forced-MH enemy on stairs: %d]" % stats.mh_enemy_on_stairs) if stats.mh_enemy_on_stairs else "",
			("  [player on stairs: %d]" % stats.player_on_stairs) if stats.player_on_stairs else ""])

	# Determinism
	var pa: Dictionary = Gen.props_from_bytes(hex_to_bytes(CASES[5][1]))
	var a: Dictionary = Gen.generate(pa, 1234)
	var b: Dictionary = Gen.generate(pa, 1234)
	if a.terrain != b.terrain or a.stairs != b.stairs or a.enemies != b.enemies:
		print("FAIL: same seed produced different floors")
		failures += 1

	# s8 decoding
	var neg := hex_to_bytes("00 fb 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00")
	if Gen.props_from_bytes(neg).roomDensity != -5:
		print("FAIL: roomDensity s8 decoding")
		failures += 1

	print("\n=== Sample maps ===")
	for idx in [0, 2]:
		var props: Dictionary = Gen.props_from_bytes(hex_to_bytes(CASES[idx][1]))
		for s in [1, 2]:
			print("%s seed %d" % [CASES[idx][0], s])
			print(ascii(Gen.generate(props, s)))
	for idx in [5, 8, 9, 11, 17]:
		var props: Dictionary = Gen.props_from_bytes(hex_to_bytes(CASES[idx][1]))
		for k in CASES[idx][2]:
			props[k] = CASES[idx][2][k]
		print("%s seed 7" % CASES[idx][0])
		print(ascii(Gen.generate(props, 7)))

	print("\nTOTAL floors %d, avg %.2f ms, worst %.1f ms, failures %d" % [total_floors, total_ms / total_floors, worst_ms, failures])
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)


func hex_to_bytes(s: String) -> PackedByteArray:
	var b := PackedByteArray()
	for part in s.split(" ", false):
		b.append(part.hex_to_int())
	return b


func passable(f: Dictionary, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= f.w or y >= f.h:
		return false
	var i: int = y * f.w + x
	return f.terrain[i] == 1 or (f.flags[i] & Gen.FLAG_ISLAND_MOAT) != 0


func validate(f: Dictionary, stats: Dictionary) -> Array:
	var errs := []
	var w: int = f.w
	var h: int = f.h
	var terrain: PackedByteArray = f.terrain
	var st: Vector2i = f.stairs
	var pl: Vector2i = f.player
	if st.x < 0 or terrain[st.y * w + st.x] != 1:
		errs.append("stairs not on floor %s" % st)
	if pl.x < 0 or terrain[pl.y * w + pl.x] != 1:
		errs.append("player not on floor %s" % pl)
	if pl == st:
		stats.player_on_stairs += 1  # Red's leader-spawn filter does not exclude the stairs tile
	if not errs.is_empty():
		return errs
	# Reachability from player: 8-dir, no corner cutting past non-passable tiles.
	var seen := PackedByteArray()
	seen.resize(w * h)
	var q := PackedInt32Array([pl.y * w + pl.x])
	seen[q[0]] = 1
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % w
		var y := i / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := x + dx
				var ny := y + dy
				if not passable(f, nx, ny):
					continue
				if dx != 0 and dy != 0 and (not passable(f, nx, y) or not passable(f, x, ny)):
					continue
				var j := ny * w + nx
				if seen[j]:
					continue
				seen[j] = 1
				q.append(j)
	var unreachable := 0
	for i in w * h:
		if terrain[i] == 1 and not seen[i]:
			unreachable += 1
	if unreachable > 0:
		errs.append("%d floor tiles unreachable" % unreachable)
	var forced_mh: bool = f.layout in [-1, 2, 5]
	var occupied := {}
	for it in f.items:
		var p: Vector2i = it.pos
		var t: int = terrain[p.y * w + p.x]
		if it.kind == "buried":
			if t != 0:
				errs.append("buried item not in wall %s" % p)
		elif t != 1:
			errs.append("item %s not on floor %s" % [it.kind, p])
		if p == st:
			errs.append("item on stairs")
		occupied[p] = true
	for p in f.traps:
		if terrain[p.y * w + p.x] != 1:
			errs.append("trap not on floor %s" % p)
		if p == st:
			errs.append("trap on stairs")
		if occupied.has(p):
			errs.append("trap on item %s" % p)
	for p in f.enemies:
		if terrain[p.y * w + p.x] != 1:
			errs.append("enemy not on floor %s" % p)
		if p == pl:
			errs.append("enemy on player")
		if p == st:
			if forced_mh:
				stats.mh_enemy_on_stairs += 1  # Red allows this for forced monster houses
			else:
				errs.append("enemy on stairs")
	var nrooms := 0
	for r in f.rooms:
		if r.size.x > 0:
			nrooms += 1
	if f.layout == -1:
		stats.fallback += 1
	elif nrooms < 2 and f.layout != 2:
		errs.append("only %d rooms" % nrooms)
	if nrooms > 32:
		errs.append("too many rooms %d" % nrooms)
	stats.rooms_min = mini(stats.rooms_min, nrooms)
	stats.rooms_max = maxi(stats.rooms_max, nrooms)
	if f.monster_house_room >= 0: stats.mh += 1
	if f.shop.size.x > 0: stats.shop += 1
	var has_maze := false
	var has_sec := false
	for i in w * h:
		if f.flags[i] & Gen.FLAG_MAZE: has_maze = true
		if terrain[i] >= 2: has_sec = true
	if has_maze: stats.maze += 1
	if has_sec: stats.sec += 1
	stats.enemies += f.enemies.size()
	stats.items += f.items.size()
	stats.traps += f.traps.size()
	return errs


func ascii(f: Dictionary) -> String:
	var w: int = f.w
	var h: int = f.h
	var rows := []
	var marks := {}
	for it in f.items:
		marks[it.pos] = "i"
	for p in f.traps:
		marks[p] = "t"
	for p in f.enemies:
		marks[p] = "e"
	if f.kecleon.x >= 0:
		marks[f.kecleon] = "K"
	marks[f.stairs] = ">"
	marks[f.player] = "@"
	for y in h:
		var line := ""
		for x in w:
			var pos := Vector2i(x, y)
			var i := y * w + x
			var t: int = f.terrain[i]
			if marks.has(pos) and (t != 0 or marks[pos] != "i"):
				line += marks[pos]
			elif t == 0:
				line += "#"
			elif t == 1:
				if f.flags[i] & Gen.FLAG_SHOP:
					line += ","
				else:
					line += "."
			elif t == 2:
				line += "~"
			else:
				line += " "
		rows.append(line)
	return "\n".join(rows) + "\nlayout %d  rooms %d  MH room %d  shop %s  items %d  traps %d  enemies %d  gen_attempts %d spawn_attempts %d" % [
		f.layout, f.rooms.size(), f.monster_house_room, f.shop, f.items.size(), f.traps.size(), f.enemies.size(), f.gen_attempts, f.spawn_attempts]
