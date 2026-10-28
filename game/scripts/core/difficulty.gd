class_name Difficulty
extends RefCounted
## Remake option: Hard mode. Only enemy and boss levels change (AI, items, hunger, rescues and recruiting
## stay Red's). Stored per adventure in Game.flags.hard_mode; picked at New Game, changeable any time in
## Game Options -> Dungeon -> Difficulty.
##
## Scaling: when the team out-levels a floor, its Pokémon rise by the difference, keeping Red's spread
## between them; on top of that every enemy is a few levels higher. Bosses (story and EoS) do the same
## against their own level and their HP grows with their level. A team below Red's levels meets Red's
## Pokémon plus the flat bonus only, so Hard never makes a floor easier.

const WILD_BONUS := 3        # levels added to every wild Pokémon
const BOSS_BONUS := 3        # levels added to every boss
const MAX_LEVEL := 100

static func hard() -> bool:
	return bool(Game.flags.get("hard_mode", false))

static func set_hard(on: bool) -> void:
	Game.flags["hard_mode"] = on

## The team's level for scaling: the average of the team members on the floor (Lv 1 dungeons: their level there).
static func team_level(dg) -> int:
	var n := 0
	var tot := 0
	for m in dg.team_mons:
		if m == null or dg.is_temp(m):
			continue
		tot += int(m.level)
		n += 1
	return int(round(tot / float(n))) if n > 0 else 1

## The floor's usual wild level: the spawn-weighted average of Red's list for this floor.
static func floor_level(dg) -> int:
	var tot := 0.0
	var w := 0.0
	for e in dg.ddata.floors[dg.floor_i].get("pk", []):
		var p := float(e[2])
		if p <= 0.0 or int(e[1]) >= 90:          # Kecleon (Lv 90) and other 0-weight entries don't count
			continue
		tot += float(e[1]) * p
		w += p
	return int(round(tot / w)) if w > 0.0 else 0

static func wild_level(dg, lv: int) -> int:
	if not hard() or lv >= 90:
		return lv
	var fl := floor_level(dg)
	var up := maxi(0, team_level(dg) - fl) if fl > 0 else 0
	return clampi(lv + up + WILD_BONUS, 1, MAX_LEVEL)

static func boss_level(dg, lv: int) -> int:
	if not hard() or lv >= 90:
		return lv
	return clampi(maxi(lv, team_level(dg)) + BOSS_BONUS, 1, MAX_LEVEL)

## A boss's fixed HP (Red's boss HP / EoS arena HP), grown in step with its level.
static func boss_hp(hp: int, base_lv: int, new_lv: int) -> int:
	if not hard() or hp <= 0 or base_lv <= 0 or new_lv <= base_lv:
		return hp
	return int(round(hp * float(new_lv) / float(base_lv)))
