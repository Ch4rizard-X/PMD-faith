class_name TurnRules
extends RefCounted
## Per-turn dungeon rules ported from pret/pmd-red:
##   dungeon_turn_effects.c  DoEndOfTurnEffects_Async (belly, weather, status damage) and
##                           TickStatusAndHealthRegen (HP regen, status timers)
##   dungeon_engine.c        gSpeedTurns / RunFractionalTurn_Async (speed system, 24 sub-turns per turn)
##   dungeon_wild_mon_spawn.c TrySpawnWildMonster, dungeon_range.c sub_8083660 (spawn tile)
##   dungeon_wind.c          UpdateWindTurns (turn limit)
##   dungeon_config.c        every tuning constant below (same names, "g" dropped)
##   dungeon_random.c        CalculateStatusTurns / DungeonRandRange
##
## Status timers live in Mon.status (turns left, 0 = none). INFINITE (0x7F) never counts down
## (sub_80838EC). Extra keys this file adds to Mon.status at runtime: "<kind>_cd" damage countdowns
## (burn_cd, poison_cd, wrapped_cd, constriction_cd, ingrain_cd, curse_cd, leech_seed_cd).
## Leech Seed's drainer is Mon meta "leech_seed_by" (uid).

const INFINITE := 0x7F

# ---------------------------------------------------------------- status turn ranges (dungeon_config.c)
## kind -> [low, high, factorCurerSkills, plus_one]. Rolled with DungeonRandRange(low, high), i.e.
## low + rand(high - low) (high EXCLUSIVE unless low == high), then +1 when the C setter adds 1.
const STATUS_TURN_RANGES := {
	"frozen": [3, 5, true, true],          # gFreezeTurnRange       (FrozenStatusTarget)
	"burn": [0x7F, 0x7F, true, true],      # gBurnTurnRange
	"poison": [0x7F, 0x7F, true, true],    # gPoisonTurnRange
	"badpoison": [0x7F, 0x7F, true, true], # gBadPoisonTurnRange
	"cringe": [1, 1, true, true],          # gCringeTurnRange
	"fast": [8, 10, false, true],          # gSpeedRaiseTurnRange   (one speedUpCounters slot)
	"slow": [6, 8, true, true],            # gSpeedLowerTurnRange   (one speedDownCounters slot)
	"confused": [6, 12, true, true],       # gConfusionTurnRange
	"para": [1, 2, true, true],            # gParalysisTurnRange (=> always 2 turns)
	"shadow_hold": [2, 5, true, true],     # gShadowHoldTurnRange
	"constriction": [3, 6, true, true],    # gConstrictionTurnRange
	"wrapped": [2, 5, true, true],         # gWrapTurnRange
	"wrapping": [2, 5, true, true],        # gWrapTurnRange (the wrapper)
	"ingrain": [15, 30, true, true],       # gIngrainTurnRange
	"paused": [1, 1, true, false],         # gPauseTurnRange
	"sleep": [3, 7, true, false],          # gSleepTurnRange (SleepStatusTarget, no +1)
	"nightmare": [4, 8, true, false],      # gNightmareTurnRange
	"sleepless": [10, 12, false, true],    # gSleeplessTurnRange
	"reflect": [10, 12, false, true],      # gReflectTurnRange
	"light_screen": [10, 12, false, true], # gLightScreenTurnRange
	"safeguard": [15, 20, false, true],    # gSafeguardTurnRange
	"mist": [10, 14, false, true],         # gMistTurnRange
	"magic_coat": [10, 12, false, true],   # gMagicCoatTurnRange
	"napping": [2, 4, false, false],       # gNappingTurnRange (Rest)
	"counter": [6, 12, false, true],       # gCounterTurnRange
	"bide": [3, 5, false, true],           # gBideTurnRange
	"enraged": [4, 10, false, true],       # gEnragedTurnRange
	"curse": [3, 5, true, true],           # gCurseTurnRange
	"snatch": [3, 5, false, true],         # gSnatchTurnRange
	"mud_water_sport": [10, 12, false, false], # gMudWaterSportTurnRange
	"leech_seed": [10, 12, true, true],    # gLeechSeedTurnRange
	"wish": [10, 12, false, true],         # gWishTurnRange
	"sure_shot": [10, 12, false, false],   # gSureShotTurnRange
	"petrified_leader": [20, 30, true, true], # gPetrifiedLeaderTurnRange
	"petrified": [0x7F, 0x7F, true, true], # gPetrifiedTurnRange
	"set_damage": [2, 4, false, true],     # gSetDamageTurnRange
	"focus_energy": [2, 4, false, true],   # gFocusEnergyTurnRange
	"cowering": [10, 12, true, true],      # gCowerTurnRange
	"decoy": [20, 50, true, true],         # gDecoyTurnRange
	"protect": [2, 6, false, true],        # gProtectTurnRange
	"taunt": [10, 12, true, true],         # gTauntTurnRange
	"whiffer": [1, 6, true, false],        # gWhifferTurnRange
	"observer_paused": [10, 12, true, false], # gObserverOrbPausedTurnRange
	"invisible": [10, 20, false, true],    # gInvisibleTurnRange
	"mirror_coat": [10, 12, false, true],  # gMirrorCoatTurnRange
	"perish": [3, 3, false, true],         # gPerishSongTurnRange
	"destiny_bond": [10, 10, true, true],  # gDestinyBondTurnRange
	"encore": [10, 10, true, true],        # gEncoreTurnRange
	"enduring": [3, 5, false, true],       # gEnduringTurnRange
	"transformed": [0x7F, 0x7F, true, true], # gTransformedTurnRange
	"infatuated": [4, 6, true, true],      # gInfatuatedTurnRange
	"mobile": [0x7F, 0x7F, false, true],   # gMobileTurnRange
	"blinker": [10, 10, true, true],       # gBlinkerTurnRange
	"cross_eyed": [10, 10, true, true],    # gCrossEyedTurnRange
	"eyedrops": [0x7F, 0x7F, false, true], # gEyedropsTurnRange
	"mirror_move": [2, 5, false, true],    # gMirrorMoveTurnRange
	"muzzled": [10, 10, true, true],       # gMuzzledTurnRange
	"conversion2": [10, 10, false, true],  # gConversion2TurnRange
	"vital_throw": [15, 20, false, true],  # gVitalThrowTurnRange
	"yawn": [2, 2, true, true],            # gYawnTurnRange
	"sleep_from_yawn": [4, 8, true, true], # gSleepFromYawnTurnRange
	"terrified": [3, 3, false, false],     # gStenchTerrifiedTurnsNo (fixed)
	# Mon keys with no Red range of their own:
	"spawn_asleep": [0x7F, 0x7F, false, false],   # SpawnWildMon: sub_8075BF4(entity, 0x7F)
}

# ---------------------------------------------------------------- residual damage (dungeon_config.c)
const BURN_DMG_COUNTDOWN := 20          # gBurnDmgCountdown
const POISON_DMG_COUNTDOWN := 10        # gPoisonDmgCountdown
const BAD_POISON_DMG_COUNTDOWN := 2     # gBadPoisonDmgCountdown
const CONSTRICTION_DMG_COUNTDOWN := 2   # gConstrictionDmgCountdown
const WRAP_DMG_COUNTDOWN := 2           # gWrapDmgCountdown
const INGRAIN_HEAL_COUNTDOWN := 5       # gIngrainHealCountdown
const CURSE_DMG_COUNTDOWN := 10         # gCurseDmgCountdown
const LEECH_SEED_DMG_COUNTDOWN := 2     # gLeechSeedDmgCountdown
const BURN_DMG := 5                     # gBurnDmgValue
const POISON_DMG := 4                   # gPoisonDmgValue
const CONSTRICTION_DMG := 5             # gConstrictionDmgValue
const WRAP_DMG := 6                     # gWrapDmgValue
const NIGHTMARE_DMG := 8                # gNightmareDmgValue (when a Nightmare ends by itself)
const NAPPING_HEAL := 999               # gNappingHpHealValue (Rest wake-up)
const HAIL_SANDSTORM_DMG := 5           # gHailSandstormDmgValue
const INGRAIN_HEAL := 10                # gIngrainHealValue
const LEECH_SEED_HEAL := 10             # gLeechSeedHealValue (also the damage)
const PERISH_SONG_DMG := 9999
const BAD_POISON_DMG_BY_TURN := [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]  # gBadPoisonDmgValuesByTurn
const WEATHER_DAMAGE_PERIOD := 10       # weatherDamageCounter cycles 9..0 (weather.c), damage on 0

# ---------------------------------------------------------------- belly (DoEndOfTurnEffects_Async)
const BELLY_BASE_DECREMENT := 0.1       # baseBellyDecrementValue (6554 / 65536)
## gBellyGoDownValues; index 10 normal, Tight Belt -> 0, Stamina Band/Energy Saver -1, Diet Ribbon /
## Heal Ribbon / Munch Belt +1.
const BELLY_GO_DOWN_VALUES := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.10001, 0.25, 0.5, 0.75, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0, 128.0, 128.0]
const LINKED_MOVES_BELLY_GO_DOWN := [1, 1, 1, 2, 4]   # gLinkedMovesBellyGoDownValues (extra, when > 1 linked move used)
const STARVATION_DMG := 1               # DealDamageToEntity_Async(entity, 1, RESIDUAL_DAMAGE_HUNGER)
const BELLY_HUNGRY := 19                # crossing <= 19: "Getting hungry..."
const BELLY_DIZZY := 9                  # crossing <= 9: "Getting dizzy from hunger..."
const MSG_HUNGRY := "Getting hungry..."                       # gUnknown_80FD594
const MSG_DIZZY := "Getting dizzy from hunger..."             # gUnknown_80FD5B8
const MSG_EMPTY := "Oh, no! Your Belly's empty!"              # gUnknown_80FD5DC (1st empty turn)
const MSG_HURRY := "Hurry! You've got to eat something!"      # gUnknown_80FD608 (2nd)
const MSG_FAINT := "You'll faint from hunger!"                # gUnknown_80FD628 (3rd)

# ---------------------------------------------------------------- HP regen (TickStatusAndHealthRegen)
const HEAL_RIBBON_REGEN := -100         # gHealRibbonRegenValue
const WISH_REGEN := -220                # gWishRegenValue
const RAIN_DISH_REGEN := -150           # gRainDishRegenValue
const REGEN_MIN := 30
const REGEN_MAX := 500

# ---------------------------------------------------------------- speed (dungeon_engine.c)
const MAX_SPEED_STAGE := 4
const NUM_SPEED_COUNTERS := 5
const FRACTIONAL_TURNS := 24
## gSpeedTurns[stage][fractionalTurn]: non-zero = the Pokémon acts in that sub-turn. Stage 1 (normal)
## acts 6 times per 24 sub-turns, i.e. once per "turn"; 0 = every other turn, 2/3/4 = 2x/3x/4x.
const SPEED_TURNS := [
	[0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 3, 0],
	[0, 0, 0, 4, 0, 0, 0, 5, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0, 8, 0, 0, 0, 9, 0],
	[0, 10, 0, 11, 0, 12, 0, 13, 0, 14, 0, 15, 0, 16, 0, 17, 0, 18, 0, 19, 0, 20, 0, 21, 0],
	[0, 22, 23, 24, 0, 25, 26, 27, 0, 28, 29, 30, 0, 31, 32, 33, 0, 34, 35, 36, 0, 37, 38, 39, 0],
	[40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64],
]
const SUBTURNS_PER_TURN := 4            # sub-turns between two actions of a normal-speed leader
const SPEED_BOOST_ACTIVATION := 250     # gSpeedBoostActivationFrame (ability Speed Boost)

# ---------------------------------------------------------------- wild spawns (dungeon_wild_mon_spawn.c)
const WILD_SPAWN_INTERVAL := 36         # gWildSpawnIntervalFrames: counted once per normal-speed turn
const KECLEON_SPAWN_INTERVAL := 5       # gKecleonSpawnIntervalFrames (after stealing from Kecleon)
## Cap check in TrySpawnWildMonster, as written in Red: monsterHouseRoom == CORRIDOR_ROOM (no house)
## -> gMaxWildMonsInMonsterHouse (10); floor WITH a Monster House -> gMaxWildMonsInRoom (4).
const MAX_WILD_MONS_IN_MONSTER_HOUSE := 10
const MAX_WILD_MONS_IN_ROOM := 4
## Remake Hard mode: wild Pokémon keep arriving up to 20 on a normal floor, one every 24 turns.
const HARD_MAX_WILD := 20
const HARD_SPAWN_INTERVAL := 24
const SPAWN_MIN_LEADER_DISTANCE := 6    # sub_8083660 first pass: |dx| >= 6 or |dy| >= 6 from the leader
const MONSTER_HOUSE_MIN_MONS := 8       # gMonsterHouseMinMons
const MONSTER_HOUSE_MAX_MONS := 12      # gMonsterHouseMaxMons

# ---------------------------------------------------------------- turn limit (dungeon_wind.c)
## windTurns starts at the dungeon's turnLimit (data/dungeons.json "turn_limit") and drops by one per
## leader action; a message is shown the first time it falls below each threshold.
const WIND_STIRRING := 250              # "Something's stirring..."        (windPhase 0 -> 1, windTurns < 0xFA)
const WIND_APPROACHING := 150           # "Something's approaching..."     (1 -> 2, < 0x96)
const WIND_CLOSER := 50                 # "It's getting closer!"           (2 -> 3, < 0x32)
const WIND_WARNINGS := [250, 150, 50]
const MSG_WIND := ["Something's stirring...", "Something's approaching...", "It's getting closer!",
	"It's right nearby! It's gusting hard!"]

# ======================================================================== data access
static func _species(m: Mon) -> Dictionary:
	return AI.species_data(m.sp)

static func _rand(rng: RandomNumberGenerator, n: int) -> int:
	if n <= 0:
		return 0
	return rng.randi_range(0, n - 1)

## DungeonRandRange(low, high): low + DungeonRandInt(high - low) (high exclusive), order-insensitive.
static func rand_range(rng: RandomNumberGenerator, low: int, high: int) -> int:
	if low == high:
		return low
	if low < high:
		return _rand(rng, high - low) + low
	return _rand(rng, low - high) + high

# ======================================================================== status durations
## Turns to store in Mon.status[kind] when the status is applied. CalculateStatusTurns + the setter's +1.
## Pass the target as m to apply Self-Curer (halves) and Natural Cure (caps at 5) where Red does.
## Returns 0 for an unknown kind.
static func status_turns(kind: String, rng: RandomNumberGenerator, m: Mon = null) -> int:
	var k := kind
	match kind:
		"confuse": k = "confused"
		"toxic": k = "badpoison"
		"freeze": k = "frozen"
		"paralysis", "paralyze": k = "para"
		"infatuate": k = "infatuated"
		"petrify": k = "petrified"
	if not STATUS_TURN_RANGES.has(k):
		return 0
	var r: Array = STATUS_TURN_RANGES[k]
	if FADING_STATUS.has(k) and bool(DungeonQoL.opt("qol_statusfade")):
		r = FADING_STATUS[k]          # QoL: they wear off, as in the later PMD games
	var n := rand_range(rng, int(r[0]), int(r[1]))
	if m != null and bool(r[2]):
		if AI.iq(m, "self-curer") and n != INFINITE:
			n /= 2
		if AI.ability_is(m, "natural cure") and n != INFINITE and n > 4:
			n = 5
	if n < 1:
		n = 1
	if bool(r[3]):
		n += 1
	return n

## Red's turn count for a status set by an item, trap, orb or ability (the same tables the moves use);
## `fallback` only for statuses Red has no range for. Petrified: the leader gets the shorter leader range.
static func red_turns(key: String, rng: RandomNumberGenerator, m: Mon, fallback: int) -> int:
	var k := key
	if k == "petrified" and m != null and m.is_leader:
		k = "petrified_leader"
	var n := status_turns(k, rng, m)
	return n if n > 0 else fallback

## "Burn/poison wear off" option: turn ranges instead of Red's until-cured 0x7F.
const FADING_STATUS := {"poison": [4, 7, true, true], "badpoison": [4, 7, true, true], "burn": [4, 7, true, true]}      # 5-7 turns

# ======================================================================== speed
## CalcSpeedStage (dungeon_logic.c): species movementSpeed + speed-up counters - speed-down counters
## - 1 if paralysed (+1 Ice types in snow), clamped to 0..4. Counters: Mon meta "speed_up_counters" /
## "speed_down_counters" (Arrays of turns, up to 5 each); the plain status timers "fast"/"slow" count as
## one counter each.
static func speed_stage(m: Mon) -> int:
	var s := 0
	for c in m.get_meta("speed_up_counters", []):
		if int(c) > 0:
			s += 1
	for c in m.get_meta("speed_down_counters", []):
		if int(c) > 0:
			s -= 1
	if int(m.status.get("fast", 0)) > 0:
		s += 1
	s += int(m.get_meta("weather_speed", 0))      # Swift Swim in rain / Chlorophyll in sun (AbilityFx)
	if int(m.status.get("slow", 0)) > 0:
		s -= 1
	if int(m.status.get("para", 0)) > 0:
		s -= 1
	s += int(_species(m).get("speed", 1))
	if m.is_team() and AI.iq(m, "time tripper"):
		s += 1  # Sky add-on: Time Tripper (CalcSpeedStage)
	# TODO(red): apparent weather "snow" for Ice types needs GetApparentWeather; Deoxys-Speed; angry Kecleon.
	return clampi(s, 0, MAX_SPEED_STAGE)

## Number of actions m gets during one normal-speed leader turn (4 of Red's 24 sub-turns), counted with
## gSpeedTurns. Uses fs.turn as the shared sub-turn phase when fs is given, otherwise m.turn_energy
## (advanced by 4 per call). Stage 0 alternates 0/1, stage 1 always 1, stage 2/3/4 give 2/3/4.
## TODO(red): a fast/slow LEADER changes how many sub-turns pass per leader action.
static func actions_this_turn(m: Mon, fs: FloorState = null) -> int:
	var stage := speed_stage(m)
	var start := 0
	if fs != null:
		start = (fs.turn * SUBTURNS_PER_TURN) % FRACTIONAL_TURNS
	else:
		start = m.turn_energy % FRACTIONAL_TURNS
		m.turn_energy = (m.turn_energy + SUBTURNS_PER_TURN) % FRACTIONAL_TURNS
	var n := 0
	for t in SUBTURNS_PER_TURN:
		if int(SPEED_TURNS[stage][(start + t) % FRACTIONAL_TURNS]) != 0:
			n += 1
	return n

# ======================================================================== belly
## Belly lost by the LEADER per turn (only the leader's belly drops in Red). 0 for anyone else.
## linked_moves_used: usedLinkedMovesCounter this turn (adds gLinkedMovesBellyGoDownValues when > 1).
static func belly_loss(m: Mon, linked_moves_used := 0) -> float:
	if m == null or not m.is_leader:
		return 0.0
	var i := 10
	if AI.holds(m, "tight_belt") or AI.holds(m, "Tight Belt"):
		i = 0
	if AI.holds(m, "stamina_band") or AI.holds(m, "Stamina Band"):
		i -= 1
	if AI.iq(m, "energy saver"):
		i -= 1
	if AI.holds(m, "diet_ribbon") or AI.holds(m, "Diet Ribbon"):
		i += 1
	if AI.holds(m, "heal_ribbon") or AI.holds(m, "Heal Ribbon"):
		i += 1
	if AI.holds(m, "munch_belt") or AI.holds(m, "Munch Belt"):
		i += 1
	i = clampi(i, 0, BELLY_GO_DOWN_VALUES.size() - 1)
	var loss: float = BELLY_BASE_DECREMENT * float(BELLY_GO_DOWN_VALUES[i])
	if linked_moves_used > 1:
		loss += float(LINKED_MOVES_BELLY_GO_DOWN[mini(linked_moves_used, 4)])
	var lc = load("res://scripts/core/launcher_cfg.gd")
	if lc.active():
		loss *= lc.f("hunger")                           # launcher: Hunger speed
	return loss

## Full belly step for the leader. state = {"belly": float, "empty_alert": int} (caller-owned).
## Returns {belly, damage (starvation HP to deal), message (String or ""), empty: bool}.
static func belly_tick(m: Mon, state: Dictionary, linked_moves_used := 0) -> Dictionary:
	var before := float(state.get("belly", 100.0))
	var after := maxf(0.0, before - belly_loss(m, linked_moves_used))
	var msg := ""
	if int(before) > BELLY_HUNGRY and int(after) <= BELLY_HUNGRY:
		msg = MSG_HUNGRY
	if int(before) > BELLY_DIZZY and int(after) <= BELLY_DIZZY:
		msg = MSG_DIZZY
	var dmg := 0
	var empty := int(after) == 0
	if empty:
		after = 0.0
		var alert := mini(int(state.get("empty_alert", 0)) + 1, 3)
		state.empty_alert = alert
		match alert:
			1: msg = MSG_EMPTY
			2: msg = MSG_HURRY
			3: msg = MSG_FAINT
		dmg = STARVATION_DMG
	else:
		state.empty_alert = 0
	state.belly = after
	return {"belly": after, "damage": dmg, "message": msg, "empty": empty}

# ======================================================================== HP regen
## TickStatusAndHealthRegen HP part. Wild Pokémon never regenerate (regenSpeed 0 when isNotTeamMember);
## no regen while poisoned / badly poisoned or on a turn the leader starved (belly_empty).
## Each turn regen_acc += maxHP; every regenSpeed points restore 1 HP. Returns HP restored.
static func regen(m: Mon, belly_empty := false, weather := "clear") -> int:
	if m == null or m.hp <= 0 or belly_empty:
		return 0
	if int(m.status.get("poison", 0)) > 0 or int(m.status.get("badpoison", 0)) > 0:
		return 0
	if not m.is_team():
		return 0
	var speed := int(_species(m).get("regen", 0))
	if speed == 0:
		return 0
	if AI.holds(m, "heal_ribbon") or AI.holds(m, "Heal Ribbon") or EosItems.has(m, "regen"):
		speed += HEAL_RIBBON_REGEN
	if int(m.status.get("wish", 0)) > 0:
		speed += WISH_REGEN
	if AI.ability_is(m, "rain dish") and weather == "rain":
		speed += RAIN_DISH_REGEN
	if AI.iq(m, "quick healer"):
		speed = int(speed / 2.0)  # Sky add-on: Quick Healer regenerates twice as fast
	speed = clampi(speed, REGEN_MIN, REGEN_MAX)
	var before := m.hp
	m.regen_acc += m.max_hp
	while m.regen_acc >= speed:
		m.hp += 1
		m.regen_acc -= speed
	if m.hp >= m.max_hp:
		m.hp = m.max_hp
	return m.hp - before

# ======================================================================== status ticking
static func _nm(m: Mon) -> String:
	return m.name if m.name != "" else "It"

static func _hurt(m: Mon, dmg: int) -> void:
	m.hp = maxi(0, m.hp - dmg)

## Countdown helper matching "damageCountdown == 0 || --damageCountdown == 0".
static func _countdown(m: Mon, key: String, reset: int) -> bool:
	var cd := int(m.status.get(key, 0))
	if cd == 0:
		m.status[key] = reset
		return true
	cd -= 1
	if cd == 0:
		m.status[key] = reset
		return true
	m.status[key] = cd
	return false

## Keys of Mon.status that are not turn timers.
const _NOT_TIMERS := ["badpoison_n", "charge_move", "stockpile", "burn_cd", "poison_cd", "badpoison_cd",
	"wrapped_cd", "constriction_cd", "ingrain_cd", "curse_cd", "leech_seed_cd"]

## One Pokémon's per-turn status processing, applied in Red's order: first the after-action part of
## DoEndOfTurnEffects_Async (weather, burn/poison/bad poison, constriction/wrap/ingrain, curse, leech seed,
## perish song), then TickStatusAndHealthRegen's timer countdown (HP regen is separate: regen()).
## Mutates m.hp / m.status; returns log messages. The caller handles fainting.
static func tick_status(m: Mon, fs: FloorState) -> Array[String]:
	var out: Array[String] = []
	if m == null or m.hp <= 0:
		return out
	var s := m.status
	var n := _nm(m)
	# Weather damage once every 10 turns (weatherDamageCounter == 0).
	if fs != null and (fs.turn % WEATHER_DAMAGE_PERIOD) == WEATHER_DAMAGE_PERIOD - 1:
		var weather_proof := AI.ability_is(m, "overcoat") or AI.ability_is(m, "magic guard") or EosItems.has(m, "weather_proof")
		if weather_proof:
			pass
		elif fs.weather == "hail" and not AI.is_type(m, "Ice") and not AI.ability_is(m, "ice body") and not AI.ability_is(m, "snow cloak"):
			_hurt(m, HAIL_SANDSTORM_DMG)
			out.append("%s is buffeted by the hail!" % n)
		elif fs.weather == "sandstorm" and not (AI.is_type(m, "Ground") or AI.is_type(m, "Rock") or AI.is_type(m, "Steel") or AI.ability_is(m, "sand rush") or AI.ability_is(m, "sand veil")):
			_hurt(m, HAIL_SANDSTORM_DMG)
			out.append("%s is buffeted by the sandstorm!" % n)
		if m.hp <= 0:
			return out
	# TODO(red): Shed Skin (50%), Speed Boost (every 250 turns), Warp Scarf -- ability/item hooks.
	var no_residual := AI.ability_is(m, "magic guard") or AI.ability_is(m, "poison heal")      # EoS / Remixed
	if int(s.get("burn", 0)) > 0 and not AI.ability_is(m, "magic guard"):
		if _countdown(m, "burn_cd", BURN_DMG_COUNTDOWN):
			_hurt(m, BURN_DMG)
			out.append("%s is hurt by its burn!" % n)
		if m.hp <= 0:
			return out
	if no_residual:
		pass
	elif int(s.get("poison", 0)) > 0:
		if _countdown(m, "poison_cd", POISON_DMG_COUNTDOWN):
			_hurt(m, POISON_DMG)
			out.append("%s is hurt by poison!" % n)
		if m.hp <= 0:
			return out
	elif int(s.get("badpoison", 0)) > 0:
		if _countdown(m, "badpoison_cd", BAD_POISON_DMG_COUNTDOWN):
			var k := mini(int(s.get("badpoison_n", 0)), BAD_POISON_DMG_BY_TURN.size() - 1)
			s.badpoison_n = mini(int(s.get("badpoison_n", 0)) + 1, BAD_POISON_DMG_BY_TURN.size() - 1)
			_hurt(m, int(BAD_POISON_DMG_BY_TURN[k]))
			out.append("%s is hurt by poison!" % n)
		if m.hp <= 0:
			return out
	if int(s.get("constriction", 0)) > 0:
		if _countdown(m, "constriction_cd", CONSTRICTION_DMG_COUNTDOWN):
			_hurt(m, CONSTRICTION_DMG)
			out.append("%s is hurt by the constriction!" % n)
		if m.hp <= 0:
			return out
	elif int(s.get("wrapped", 0)) > 0:
		if _countdown(m, "wrapped_cd", WRAP_DMG_COUNTDOWN):
			_hurt(m, WRAP_DMG)
			out.append("%s is squeezed!" % n)
		if m.hp <= 0:
			return out
	elif int(s.get("ingrain", 0)) > 0:
		if _countdown(m, "ingrain_cd", INGRAIN_HEAL_COUNTDOWN):
			m.hp = mini(m.max_hp, m.hp + INGRAIN_HEAL)
	if int(s.get("curse", 0)) > 0:
		if _countdown(m, "curse_cd", CURSE_DMG_COUNTDOWN):
			_hurt(m, maxi(1, m.max_hp / 4))
			out.append("%s is hurt by the curse!" % n)
		if m.hp <= 0:
			return out
	if int(s.get("leech_seed", 0)) > 0:
		if _countdown(m, "leech_seed_cd", LEECH_SEED_DMG_COUNTDOWN):
			var src: Mon = null
			if fs != null:
				src = AI._mon_by_uid(fs, int(m.get_meta("leech_seed_by", -1)))
			if src == null:
				s.leech_seed = 0       # seeder gone: status cleared
			elif int(s.get("frozen", 0)) == 0:
				_hurt(m, LEECH_SEED_HEAL)
				out.append("%s's health is sapped by Leech Seed!" % n)
				if AI.ability_is(m, "liquid ooze"):
					_hurt(src, LEECH_SEED_HEAL)
				else:
					src.hp = mini(src.max_hp, src.hp + LEECH_SEED_HEAL)
		if m.hp <= 0:
			return out
	if int(s.get("perish", 0)) > 0 and int(s.get("perish", 0)) != INFINITE:
		s.perish = int(s.perish) - 1
		if int(s.perish) == 0:
			out.append("%s's Perish Song count reached 0!" % n)
			if int(s.get("protect", 0)) > 0:
				out.append("Protect saved it!")
			else:
				_hurt(m, PERISH_SONG_DMG)
			if m.hp <= 0:
				return out
	# TODO(red): Bide release (MOVE_BIDE_2) when the Bide timer ends needs combat.gd; Enraged just ends.
	# ---- TickStatusAndHealthRegen: count every timer down (0x7F never moves)
	for k in s.keys():
		if k in _NOT_TIMERS or k == "perish":
			continue
		var v = s[k]
		if not (v is int) or v <= 0 or v == INFINITE:
			continue
		s[k] = v - 1
		if s[k] == 0:
			_on_status_end(m, String(k), fs, out)
	for key in ["speed_up_counters", "speed_down_counters"]:
		if m.has_meta(key):
			var arr: Array = m.get_meta(key)
			for i in arr.size():
				if int(arr[i]) > 0 and int(arr[i]) != INFINITE:
					arr[i] = int(arr[i]) - 1
			m.set_meta(key, arr)
	return out

## End-of-status side effects (EndSleepClassStatus / EndBurnClassStatus / ... in move_orb_effects_5.c).
static func _on_status_end(m: Mon, k: String, fs: FloorState, out: Array[String]) -> void:
	var n := _nm(m)
	match k:
		"sleep":
			out.append("%s woke up!" % n)
		"nightmare":
			out.append("%s woke up from its nightmare!" % n)
			_hurt(m, NIGHTMARE_DMG)
		"napping":
			out.append("%s woke up refreshed!" % n)
			m.hp = mini(m.max_hp, m.hp + NAPPING_HEAL)
			# TODO(red): Rest also cures the burn class (sub_8079F20) -- done here for the common cases.
			for c in ["burn", "poison", "badpoison", "para"]:
				m.status[c] = 0
		"yawn":
			if fs != null:
				m.status.sleep = status_turns("sleep_from_yawn", fs.rng, m)
				out.append("%s fell asleep!" % n)
		"burn", "poison", "badpoison":
			m.status.erase(k + "_cd")
			if k == "badpoison":
				m.status.badpoison_n = 0
			out.append("%s's %s faded." % [n, "burn" if k == "burn" else "poisoning"])
		"para":
			out.append("%s is no longer paralyzed." % n)
		"frozen":
			out.append("%s thawed out!" % n)
		"confused":
			out.append("%s is no longer confused." % n)
		"wrapped", "constriction", "ingrain", "curse", "leech_seed":
			m.status.erase(k + "_cd")
		"terrified":
			out.append("%s's fear was waved off." % n)

# ======================================================================== wild spawns
## Turns between wild spawn attempts (gWildSpawnIntervalFrames; Kecleon chase: 5).
static func spawn_interval(fs: FloorState) -> int:
	if fs != null and bool(fs.get_meta("stole_from_kecleon", false)):
		return KECLEON_SPAWN_INTERVAL
	if Difficulty.hard():
		return HARD_SPAWN_INTERVAL
	return WILD_SPAWN_INTERVAL

## Wild-Pokémon cap checked by TrySpawnWildMonster (see the constants' note).
static func max_wild(fs: FloorState) -> int:
	if fs != null and bool(fs.get_meta("stole_from_kecleon", false)):
		return 9999
	if fs == null or fs.monster_house_room < 0 or fs.monster_house_room == 255:
		return HARD_MAX_WILD if Difficulty.hard() else MAX_WILD_MONS_IN_MONSTER_HOUSE
	return MAX_WILD_MONS_IN_ROOM

## Whether a spawn may happen now (wild count excludes Pokémon standing on unbreakable tiles).
static func can_spawn(fs: FloorState) -> bool:
	var n := 0
	for o in fs.mons:
		if o.hp > 0 and not o.is_team():
			var fl := 0
			if fs.flags.size() == fs.w * fs.h:
				fl = fs.flags[fs.idx(o.pos)]
			if (fl & 2048) == 0:          # TrySpawnWildMonster skips Pokémon on TERRAIN_TYPE_UNBREAKABLE tiles
				n += 1
	return n < max_wild(fs)

## sub_8083660: random floor tile for a new wild Pokémon. Pass 1: room tile, no item/trap/Pokémon, at
## least 6 tiles from the leader on some axis; pass 2: drop the distance rule; pass 3: corridors too.
## Returns Vector2i(-1, -1) if nothing fits.
static func spawn_position(fs: FloorState) -> Vector2i:
	var L := fs.leader
	for pass_i in 3:
		var cand: Array = []
		for y in fs.h:
			for x in fs.w:
				var p := Vector2i(x, y)
				if fs.terrain_at(p) != 1 or fs.items.has(p) or fs.traps.has(p) or fs.mon_at(p) != null:
					continue
				if pass_i < 2 and fs.room_at(p) == 255:
					continue
				if pass_i == 0 and L != null and absi(L.pos.x - x) < SPAWN_MIN_LEADER_DISTANCE and absi(L.pos.y - y) < SPAWN_MIN_LEADER_DISTANCE:
					continue
				cand.append(p)
		if not cand.is_empty():
			return cand[_rand(fs.rng, cand.size())]
	return Vector2i(-1, -1)

## SpawnWildMon: spawn asleep with chance species "asleep" (chanceAsleep, %) -> sleep 0x7F (until woken),
## and moveRandomly with the dungeon's randomMovementChance (%). Apply to a freshly made wild Mon.
## TODO(red): randomMovementChance per dungeon (gDungeons[].randomMovementChance) is not in dungeons.json.
static func init_spawned(m: Mon, rng: RandomNumberGenerator, random_movement_chance := 0) -> void:
	m.set_meta("move_randomly", _rand(rng, 100) < random_movement_chance)
	if _rand(rng, 100) < int(_species(m).get("asleep", 0)):
		m.status.sleep = INFINITE

# ======================================================================== turn limit
## UpdateWindTurns, once per leader action. state = {"turns": int (init = turn_limit), "phase": int (0)}.
## Returns {message: String ("" if none), blown_out: bool}.
static func wind_tick(state: Dictionary) -> Dictionary:
	var turns := int(state.get("turns", 1000))
	var phase := int(state.get("phase", 0))
	var msg := ""
	var blown := false
	if turns <= 0:
		phase = 3
	else:
		turns -= 1
		if turns < 1:
			phase = 3
	if phase == 0:
		if turns < WIND_STIRRING:
			msg = MSG_WIND[0]
			phase = 1
	elif phase == 1:
		if turns < WIND_APPROACHING:
			msg = MSG_WIND[1]
			phase = 2
	elif phase == 2:
		if turns < WIND_CLOSER:
			msg = MSG_WIND[2]
			phase = 3
	elif phase == 3:
		if turns < 1:
			msg = MSG_WIND[3]
			phase = 4
			blown = true      # HandleFaint_Async(leader, DUNGEON_EXIT_BLOWN_OUT_UNSEEN_FORCE)
	state.turns = turns
	state.phase = phase
	return {"message": msg, "blown_out": blown}

# ======================================================================== fainting
## What Red does when a wild Pokémon knocks out a team member (dungeon_damage.c HandleFaint): wild
## Pokémon gain no Exp.; in dungeons with enemiesEvolveWhenKOed they evolve instead (EnemyEvolution).
## Returns true if the attacker should evolve. (A fainted leader ends the expedition; fainted allies just
## leave the floor.)  TODO(red): DoEnemiesEvolveWhenKOed per-dungeon flag is not in dungeons.json.
static func enemy_evolves_on_ko(attacker: Mon, victim: Mon, dungeon_flag := false) -> bool:
	return attacker != null and victim != null and not attacker.is_team() and victim.is_team() and dungeon_flag
