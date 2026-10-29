class_name Difficulty
extends RefCounted
## Remake option: Hard mode (Game.flags.hard_mode; picked at New Game, changeable any time in
## Game Options -> Dungeon -> Difficulty). AI, items, hunger, rescues and recruiting stay Red's.
##
## Levels follow a planned curve instead of Red's:
##   - Story dungeons: CURVE gives the wild level on the first and last floor (in between it rises evenly)
##     and the boss level; the story ends with Rayquaza at Lv 70. Red's spread between the species of a
##     floor is kept (a floor at 30 has Pokémon at 28 and 32 where Red had 18 and 22 around 20).
##   - Side dungeons that open during the story, Makuhita Dojo's mazes (and EoS dungeons that open by team
##     level): Red's level mapped onto the story curve (RED_TO_HARD).
##   - Post-game dungeons (and EoS post-game ones): Lv 70 on the first floor, +1 every 3 floors, up to 100;
##     bosses there at least Lv 75 (or the floor + 5).
##   - Backstop: a team 10+ levels above a floor's level raises its Pokémon by half of the difference past 10.
##   - Lv 1 dungeons (level_reset) and Kecleon / other Lv 90 Pokémon are never changed.
## Also on Hard: wild Pokémon keep arriving up to 20 per floor, one every 24 turns (TurnRules.HARD_*).

const MAX_LEVEL := 100
## dungeon key -> [first floor, last floor, boss]
const CURVE := {
	"tiny_woods": [3, 4, 0], "thunderwave_cave": [5, 7, 0], "mt_steel": [8, 11, 14], "sinister_woods": [12, 18, 20],
	"silent_chasm": [19, 22, 0], "mt_thunder": [22, 26, 0], "mt_thunder_peak": [27, 29, 32], "great_canyon": [30, 33, 0],
	"lapis_cave": [33, 37, 0], "mt_blaze": [37, 40, 0], "mt_blaze_peak": [41, 43, 46], "frosty_forest": [43, 46, 0],
	"frosty_grotto": [46, 48, 50], "mt_freeze": [48, 52, 0], "mt_freeze_peak": [53, 55, 0], "magma_cavern": [55, 60, 0],
	"magma_cavern_pit": [60, 62, 65], "sky_tower": [62, 67, 0], "sky_tower_summit": [67, 69, 70],
}
## Side dungeons open during the story; everything else outside CURVE is post-game.
const STORY_SIDE := ["uproar_forest", "howling_forest"]
## Red level -> Hard level (the story curve: Red's typical level of each stage against its Hard level).
const RED_TO_HARD := [[1, 3], [3, 6], [6, 10], [11, 15], [11, 24], [15, 32], [16, 36], [16, 40], [18, 45],
	[18, 50], [20, 54], [25, 58], [24, 65], [30, 68], [35, 70]]
const BOSS_BONUS := 3
const POST_START := 70
const POST_BOSS_MIN := 75
const BACKSTOP_MARGIN := 10

static func hard() -> bool:
	return load("res://scripts/core/launcher_cfg.gd").hard(bool(Game.flags.get("hard_mode", false)))

static func set_hard(on: bool) -> void:
	Game.flags["hard_mode"] = on

## The team's level: the average of the team members on the floor (temporary recruits don't count).
static func team_level(dg) -> int:
	var n := 0
	var tot := 0
	for m in dg.team_mons:
		if m == null or dg.is_temp(m):
			continue
		tot += int(m.level)
		n += 1
	return int(round(tot / float(n))) if n > 0 else 1

## Red's usual wild level on this floor: the spawn-weighted average of the floor's list.
static func floor_level(dg) -> int:
	return floor_level_of(dg.ddata, int(dg.floor_i))

static func floor_level_of(dd: Dictionary, fi: int) -> int:
	var tot := 0.0
	var w := 0.0
	var fls: Array = dd.get("floors", [])
	if fi < 0 or fi >= fls.size():
		return 0
	for e in fls[fi].get("pk", []):
		var p := float(e[2])
		if p <= 0.0 or int(e[1]) >= 90:          # Kecleon (Lv 90) and other 0-weight entries don't count
			continue
		tot += float(e[1]) * p
		w += p
	return int(round(tot / w)) if w > 0.0 else 0

static func _red_to_hard(lv: int) -> int:
	var best := -1
	for pt in RED_TO_HARD:                      # the highest stage whose Red level the floor reaches
		if lv >= int(pt[0]):
			best = maxi(best, int(pt[1]))
	if best < 0:
		return lv
	if lv > 35:
		best += (lv - 35) * 2                   # beyond Rayquaza's level (EoS dungeons): keep climbing
	return best

static func _post_game(dg) -> bool:
	return post_game_key(str(dg.dkey), dg.ddata)

static func post_game_key(k: String, dd: Dictionary) -> bool:
	if CURVE.has(k) or k in STORY_SIDE or k.begins_with("maze_"):      # Makuhita's mazes follow the story curve
		return false
	if bool(dd.get("eos", false)):
		return k in Story.EOS_POSTGAME
	return true

static func _scaled(dg) -> bool:
	return hard() and not bool(dg.ddata.get("level_reset", false))

## The Hard level of the current floor (the curve's value before the backstop).
static func floor_target(dg) -> int:
	return floor_target_of(str(dg.dkey), dg.ddata, int(dg.floor_i))

static func floor_target_of(k: String, dd: Dictionary, fi: int) -> int:
	var n: int = maxi(1, (dd.get("floors", []) as Array).size())
	if CURVE.has(k):
		var c: Array = CURVE[k]
		var t := 0.0 if n <= 1 else float(fi) / float(n - 1)
		return int(round(lerpf(float(c[0]), float(c[1]), clampf(t, 0.0, 1.0))))
	if post_game_key(k, dd):
		return mini(MAX_LEVEL, POST_START + fi / 3)
	return _red_to_hard(maxi(1, floor_level_of(dd, fi)))

## For the Prepare screen / Pokédex: [lowest, highest, spawn-weighted mean] of a dungeon's wild levels on Hard
## (the curve before the backstop). Empty when Hard is off or the dungeon keeps Red's levels (Lv 1 dungeons).
static func dungeon_levels(k: String) -> Array:
	var dd: Dictionary = DB.dungeons.get("dungeons", {}).get(k, {})
	if not hard() or dd.is_empty() or bool(dd.get("level_reset", false)):
		return []
	var lo := 999
	var hi := 0
	var tot := 0.0
	var w := 0.0
	var fls: Array = dd.get("floors", [])
	for fi in fls.size():
		if not Pokedex.wild_floor(fls[fi]):
			continue                                # boss arenas: their lists never spawn
		var target := floor_target_of(k, dd, fi)
		var fl := floor_level_of(dd, fi)
		for e in fls[fi].get("pk", []):
			if int(e[2]) <= 0 or int(e[1]) <= 0 or int(e[1]) >= 90:
				continue
			var lv := clampi(target + (int(e[1]) - fl if fl > 0 else 0), 1, MAX_LEVEL)
			lo = mini(lo, lv)
			hi = maxi(hi, lv)
			tot += lv * float(e[2])
			w += float(e[2])
	if hi <= 0:
		return []
	return [lo, hi, int(round(tot / w))]

static func _backstop(dg, target: int) -> int:
	var over := team_level(dg) - target - BACKSTOP_MARGIN
	return target + (over / 2 if over > 0 else 0)

static func wild_level(dg, lv: int) -> int:
	return load("res://scripts/core/launcher_cfg.gd").level_offset(_wild_level(dg, lv))     # launcher: Enemy level

static func _wild_level(dg, lv: int) -> int:
	if lv < 90 and str(dg.dkey).begins_with("maze_") and not bool(dg.ddata.get("level_reset", false)):
		return maze_level(dg, lv)
	if not _scaled(dg) or lv >= 90:
		return lv
	var target := floor_target(dg)
	var fl := floor_level(dg)
	var spread := lv - fl if fl > 0 else 0
	return clampi(_backstop(dg, target) + spread, 1, MAX_LEVEL)

## Remake: Makuhita Dojo's mazes match the team (Normal and Hard), so training there always pays: the floor's
## average is set to the team's level + MAZE_BONUS, keeping Red's spread between the species of the floor.
const MAZE_BONUS := 1

static func maze_level(dg, lv: int) -> int:
	var fl := floor_level(dg)
	var spread := clampi(lv - fl, -3, 3) if fl > 0 else 0
	return clampi(team_level(dg) + MAZE_BONUS + spread, 1, MAX_LEVEL)

## Story Pokémon and bosses (fixed rooms, EoS arenas).
static func boss_level(dg, lv: int) -> int:
	if not _scaled(dg) or lv >= 90:
		return lv
	var k := str(dg.dkey)
	var target := floor_target(dg)
	var want := target + BOSS_BONUS
	if CURVE.has(k) and int(CURVE[k][2]) > 0 and int(dg.floor_i) >= int(dg.ddata.floors.size()) - 1:
		want = int(CURVE[k][2])                 # the dungeon's boss on its last floor
	elif _post_game(dg):
		want = maxi(POST_BOSS_MIN, target + 5)
	var bs := _backstop(dg, target)
	if bs > target:                             # a team far above the curve: bosses keep up too
		want = maxi(want, bs + BOSS_BONUS)
	return clampi(want, 1, MAX_LEVEL)

## For the Pokédex: [lowest, highest] Hard level of one species in a dungeon (empty when Hard is off / Lv 1 dungeon).
static func species_levels(k: String, sp: String) -> Array:
	var dd: Dictionary = DB.dungeons.get("dungeons", {}).get(k, {})
	if not hard() or dd.is_empty() or bool(dd.get("level_reset", false)):
		return []
	var lo := 999
	var hi := 0
	var fls: Array = dd.get("floors", [])
	for fi in fls.size():
		if not Pokedex.wild_floor(fls[fi]):
			continue
		var target := -1
		var fl := 0
		for e in fls[fi].get("pk", []):
			if str(e[0]).substr(0, 4) != sp.substr(0, 4) or int(e[2]) <= 0 or int(e[1]) >= 90:
				continue
			if target < 0:
				target = floor_target_of(k, dd, fi)
				fl = floor_level_of(dd, fi)
			var lv := clampi(target + (int(e[1]) - fl if fl > 0 else 0), 1, MAX_LEVEL)
			lo = mini(lo, lv)
			hi = maxi(hi, lv)
	return [lo, hi] if hi > 0 else []

## For the Pokédex / second screen: a boss's level on Hard without a team (boss_level before the backstop).
static func boss_level_of(k: String, dd: Dictionary, fi: int, lv: int) -> int:
	if not hard() or bool(dd.get("level_reset", false)) or lv >= 90:
		return lv
	var target := floor_target_of(k, dd, fi)
	var want := target + BOSS_BONUS
	if CURVE.has(k) and int(CURVE[k][2]) > 0 and fi >= (dd.get("floors", []) as Array).size() - 1:
		want = int(CURVE[k][2])
	elif post_game_key(k, dd):
		want = maxi(POST_BOSS_MIN, target + 5)
	return clampi(want, 1, MAX_LEVEL)

## A boss's fixed HP (Red's boss HP / EoS arena HP), grown in step with its level.
static func boss_hp(hp: int, base_lv: int, new_lv: int) -> int:
	if not hard() or hp <= 0 or base_lv <= 0 or new_lv <= base_lv:
		return hp
	return int(round(hp * float(new_lv) / float(base_lv)))
