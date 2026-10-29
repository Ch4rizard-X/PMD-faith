class_name Pokedex
extends RefCounted
## Pokédex / recruit tracker data (the screen is scripts/ui/pokedex_ui.gd).
##
##   Pokedex.mark_seen(sp)        # a wild Pokémon came into the team's view (saved in Game.flags.seen)
##   Pokedex.see_visible(dungeon) # mark every wild Pokémon the team can see right now (hook for Dungeon._reveal)
##   Pokedex.is_seen(sp) / is_recruited(sp) / recruited_count(sp)
##   Pokedex.locations(sp)        # [{dkey, floors: [1, 2, ...], lv_min, lv_max}] from data/dungeons.json floors[].pk
##   Pokedex.recommended_level(dkey) / level_range(dkey)
##
## Species keys are Red's 4-digit keys; forms ("0006MX") count as their base species.

static var _loc: Dictionary = {}           # sp -> Array of location dicts
static var _species: Array = []

static func base(sp: String) -> String:
	return sp.substr(0, 4)

static func seen_dict() -> Dictionary:
	if not Game.flags.get("seen") is Dictionary:
		Game.flags["seen"] = {}
	return Game.flags["seen"]

## Returns true the first time the species is seen.
static func mark_seen(sp: String) -> bool:
	var k := base(sp)
	if k == "" or not DB.species.has(k):
		return false
	var s := seen_dict()
	if s.has(k):
		return false
	s[k] = true
	return true

## Every wild (or client) Pokémon a team member can see on the current floor.
static func see_visible(d) -> void:
	if d == null or d.fs == null:
		return
	var team: Array = d.fs.team()
	for m in d.fs.mons:
		if m.hp <= 0 or m.is_team():
			continue
		for t in team:
			if d.fs.can_see(t, m.pos):
				mark_seen(m.sp)
				break

static func recruited_count(sp: String) -> int:
	var k := base(sp)
	var n := 0
	var counted: Array = []
	for e in Game.friends + Game.team:
		if base(str(e.get("sp", ""))) == k and not counted.any(func(x): return is_same(x, e)):
			counted.append(e)
			n += 1
	return n

static func is_recruited(sp: String) -> bool:
	return recruited_count(sp) > 0

static func is_seen(sp: String) -> bool:
	return seen_dict().has(base(sp)) or is_recruited(sp)

## Red's species (the ones with "red": 1), sorted by number.
static func species_list() -> Array:
	if _species.is_empty():
		for k in DB.species:
			if str(k).length() == 4 and int(DB.species[k].get("red", 0)) == 1 and (load("res://scripts/core/launcher_cfg.gd").mon_on(str(k)) or is_recruited(str(k))):
				_species.append(str(k))
		_species.sort()
	return _species

static func counts() -> Dictionary:
	var s := 0
	var r := 0
	for k in species_list():
		if is_recruited(k):
			r += 1
			s += 1
		elif is_seen(k):
			s += 1
	return {"seen": s, "recruited": r, "total": species_list().size()}

## Red's internal dungeon slots (boss rooms, "D50"-style placeholders, Autopilot) aren't places to visit.
static func is_listed(dk: String) -> bool:
	var r := RegEx.create_from_string("^(boss\\d+|d\\d+|autopilot)$")
	return r.search(dk) == null and load("res://scripts/core/launcher_cfg.gd").dungeon_on(dk)

## A floor where wild Pokémon actually appear: not an Explorers of Sky boss arena or one of Red's floor-wide
## boss rooms (their spawn lists are never used: Labyrinth Cave's B10F lists Lv 35 dragons that never come).
static func wild_floor(f: Dictionary) -> bool:
	if int(f.get("eos_fixed", 0)) > 0:
		return false
	var pr: Array = f.get("props", [])
	return not (pr.size() > 18 and BossScene.is_floorwide(int(pr[18])))

static func _build() -> void:
	if not _loc.is_empty():
		return
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	for dk in dd:
		if not is_listed(str(dk)):
			continue
		var floors: Array = dd[dk].get("floors", [])
		for fi in floors.size():
			if not wild_floor(floors[fi]):
				continue
			for e in floors[fi].get("pk", []):
				if int(e[2]) <= 0:
					continue
				var k := base(str(e[0]))
				if not _loc.has(k):
					_loc[k] = []
				var rec: Dictionary = {}
				for x in _loc[k]:
					if x.dkey == dk:
						rec = x
				if rec.is_empty():
					rec = {"dkey": str(dk), "floors": [], "lv_min": 999, "lv_max": 0}
					_loc[k].append(rec)
				if not (fi + 1) in rec.floors:
					rec.floors.append(fi + 1)
				rec.lv_min = mini(int(rec.lv_min), int(e[1]))
				rec.lv_max = maxi(int(rec.lv_max), int(e[1]))
	for k in _loc:
		_loc[k].sort_custom(func(a, b): return _dorder(a.dkey) < _dorder(b.dkey))

static func _dorder(dk: String) -> int:
	var i := Services.STORY_ORDER.find(dk)
	if i >= 0:
		return i
	return 100 + int(DB.dungeons.get("dungeons", {}).get(dk, {}).get("index", 0))

## A dungeon the player knows: opened, cleared, or an Explorers of Sky dungeon that's open now.
static func dungeon_known(dk: String) -> bool:
	return dk in Game.unlocked or dk in Game.cleared or Story.eos_chain_head(dk) in Story.eos_unlocked()

static func locations(sp: String) -> Array:
	_build()
	return _loc.get(base(sp), [])

## "B1-3F" / "5-9F" / "B2F, B4F" style floor list.
static func floors_text(dk: String, floors: Array) -> String:
	var up: bool = DB.dungeons.get("dungeons", {}).get(dk, {}).get("up", false)
	var pre := "" if up else "B"
	var f := floors.duplicate()
	f.sort()
	var parts: Array = []
	var i := 0
	while i < f.size():
		var j := i
		while j + 1 < f.size() and int(f[j + 1]) == int(f[j]) + 1:
			j += 1
		parts.append(("%s%d" % [pre, f[i]]) if i == j else ("%s%d-%d" % [pre, f[i], f[j]]))
		i = j + 1
	return ", ".join(parts) + "F"

## Species that live in a dungeon (any floor), in number order.
static func species_in(dk: String) -> Array:
	var out: Array = []
	for k in species_list():
		for l in locations(k):
			if l.dkey == dk:
				out.append(k)
				break
	return out

static func species_in_area(area: String) -> Array:
	var out: Array = []
	for k in species_list():
		if Services.area_of(k) == area:
			out.append(k)
	return out

## Dungeons that have wild Pokémon, story order first.
## An Explorers of Sky dungeon in several parts is one trip (Story.EOS_CHAINS): its parts, or just dk.
static func trip_parts(dk: String) -> Array:
	var c := Story.eos_chain_of(dk)
	return c if not c.is_empty() else [dk]

## Every species met on the whole trip (all parts of a chained EoS dungeon), first part first.
static func trip_species(dk: String) -> Array:
	var out: Array = []
	for p in trip_parts(dk):
		for sp in species_in(str(p)):
			if not sp in out:
				out.append(sp)
	return out

## [lowest, highest] wild level over the whole trip.
static func trip_level_range(dk: String) -> Array:
	var lo := 999
	var hi := 0
	for p in trip_parts(dk):
		var r := level_range(str(p))
		if int(r[1]) > 0:
			lo = mini(lo, int(r[0]))
			hi = maxi(hi, int(r[1]))
	return [lo if hi > 0 else 0, hi]

## Recommended level for the whole trip: the parts' levels weighted by their floors.
static func trip_recommended_level(dk: String) -> int:
	var tot := 0.0
	var w := 0.0
	for p in trip_parts(dk):
		var n := float((DB.dungeons.get("dungeons", {}).get(str(p), {}).get("floors", []) as Array).size())
		tot += recommended_level(str(p)) * n
		w += n
	return int(round(tot / w)) if w > 0.0 else recommended_level(dk)

## The bosses of a trip: [[species, level], ...] from the Explorers of Sky arenas (eos_fixed.json) and Red's
## floor-wide boss rooms (their Pokémon on the floor's spawn list, BossScene.level_for), in floor order. Levels
## follow Hard mode when it's on. Story helpers and other non-hostile room Pokémon are left out.
static func trip_bosses(dk: String) -> Array:
	var out: Array = []
	var seen := {}
	var boss_sp := {}                      # species that appear in Red's rooms as a story boss (BEHAVIOR_SKARMORY ...)
	for e in BossScene.load_data().get("entities", []):
		var bh := str(e.get("behavior", ""))
		if bh != "" and not bh in BossScene.NEUTRAL and not bh in ["BEHAVIOR_ALLY", "BEHAVIOR_MAZE_BOSS", "BEHAVIOR_FIXED_ENEMY"]:
			boss_sp[str(e.get("sp", ""))] = true
	for p in trip_parts(dk):
		var dd: Dictionary = DB.dungeons.get("dungeons", {}).get(str(p), {})
		var fls: Array = dd.get("floors", [])
		for fi in fls.size():
			var f: Dictionary = fls[fi]
			var list: Array = []
			if int(f.get("eos_fixed", 0)) > 0:
				for m in Dungeon.eos_fixed_data().get(str(int(f.eos_fixed)), {}).get("mons", []):
					list.append([str(m.sp), int(m.get("level", 1))])
			else:
				var pr: Array = f.get("props", [])
				if pr.size() > 18 and BossScene.is_floorwide(int(pr[18])):
					var lv: Dictionary = BossScene.load_data().get("levels", {}).get(str(p), {}).get(str(fi), {})
					for sp in lv:
						if boss_sp.has(str(sp)) and int(lv[sp]) < 90:
							list.append([str(sp), int(lv[sp])])
			for b in list:
				if not DB.species.has(str(b[0])) or seen.has(str(b[0])):
					continue
				seen[str(b[0])] = true
				out.append([str(b[0]), Difficulty.boss_level_of(str(p), dd, fi, int(b[1]))])
	return out

## Floors over the whole trip.
static func trip_floors(dk: String) -> int:
	var n := 0
	for p in trip_parts(dk):
		n += (DB.dungeons.get("dungeons", {}).get(str(p), {}).get("floors", []) as Array).size()
	return n

static func dungeon_keys() -> Array:
	var out: Array = []
	for dk in DB.dungeons.get("dungeons", {}):
		var any := false
		for f in DB.dungeons.dungeons[dk].get("floors", []):
			if not f.get("pk", []).is_empty():
				any = true
				break
		if any and is_listed(str(dk)):
			out.append(str(dk))
	out.sort_custom(func(a, b): return _dorder(a) < _dorder(b))
	return out

## Base recruit rate in per mille (Red's species value; -999 = can't be recruited).
static func recruit_rate(sp: String) -> int:
	return int(DB.species.get(base(sp), {}).get("recruit", 0))

## Rate with the current leader's level bonus (Dungeon.RECRUIT_BY_LEVEL), per mille, 0..1000.
static func recruit_now(sp: String) -> int:
	var r := recruit_rate(sp)
	if r == -999:
		return 0
	var lv := int(Game.team[0].get("level", 1)) if not Game.team.is_empty() else 1
	for e in Dungeon.RECRUIT_BY_LEVEL:
		if lv >= int(e[0]):
			r += int(e[1])
			break
	return clampi(r, 0, 1000)

static func recruit_text(sp: String) -> String:
	var r := recruit_rate(sp)
	if r == -999:
		return "Can't be recruited"
	var now := recruit_now(sp)
	if now == r:
		return "%.1f%%" % (r / 10.0)
	return "%.1f%%  (now %.1f%%)" % [r / 10.0, now / 10.0]

## Enemy level range in a dungeon: [min, max].
static func level_range(dk: String) -> Array:
	var hl := Difficulty.dungeon_levels(dk)      # Hard mode: the planned curve
	if not hl.is_empty():
		return [hl[0], hl[1]]
	var lo := 999
	var hi := 0
	for f in DB.dungeons.get("dungeons", {}).get(dk, {}).get("floors", []):
		if not wild_floor(f):
			continue
		for e in f.get("pk", []):
			if int(e[2]) > 0 and int(e[1]) > 0:
				lo = mini(lo, int(e[1]))
				hi = maxi(hi, int(e[1]))
	return [lo if hi > 0 else 0, hi]

## Red's typical enemy level: spawn-weighted mean level over all floors (rounded).
static func recommended_level(dk: String) -> int:
	var hl := Difficulty.dungeon_levels(dk)      # Hard mode: the planned curve
	if not hl.is_empty():
		return int(hl[2])
	var tot := 0.0
	var w := 0.0
	for f in DB.dungeons.get("dungeons", {}).get(dk, {}).get("floors", []):
		if not wild_floor(f):
			continue
		for e in f.get("pk", []):
			if int(e[2]) > 0 and int(e[1]) > 0:
				tot += float(e[1]) * float(e[2])
				w += float(e[2])
	return int(round(tot / w)) if w > 0 else 1
