class_name Combat
extends RefCounted
## Pokémon Mystery Dungeon: Red Rescue Team combat math, ported 1:1 from the pret/pmd-red decomp.
##
## Sources (pret/pmd-red):
##   src/dungeon_damage.c   CalcDamage, sub_806E100 (type/ability/weather multiplier),
##                          ApplyAtkDefStatBoosts, HandleDealingDamageInternal_Async (absorb/frozen/messages)
##   src/dungeon_move_util.c AccuracyCalc
##   src/dungeon_move.c     HandleDamagingMove / TryHitTarget_Async (damage first, then ACCURACY_2 roll),
##                          MOVE_REGULAR_ATTACK uses modifier 0.5
##   src/dungeon_config.c   stage tables, type chart, effectiveness combine table, status damage values
##   src/dungeon_data.c     held-item boosts, physical/special split by type
##   src/math.c             s24_8 / s48_16 fixed point (ported below with integer ops so rounding matches)
##
## Notes on Red quirks reproduced here:
##   * Red has NO true type immunity. Chart value 0 ("IMMUNE") multiplies damage by 0.5 and prints
##     "It has little effect...". Per defender type: 0 -> x0.5, 1 -> x0.9, 2 -> x1, 3 -> x1.5 (multiplied
##     for both types). The displayed effectiveness comes from the `combine` table instead.
##   * Normal/Fighting vs an unexposed Ghost counts as "IMMUNE" (x0.5) — the chart itself says neutral.
##   * Enemies never land critical hits by themselves (their crit odds are 0); only Focus Energy,
##     Scope Lens (attacker) or Patsy Band (target) give them crits.
##   * Burn does NOT halve attack in Red's damage formula (it is only 5 HP every 20 turns).
##   * Team members use level*2/3 as the "level" term; enemies use (their raw attack stat after
##     ability modifiers)/3 instead.
##   * Stat stages use Red's 0..20 index (10 neutral).
##
## Explorers of Sky add-on IQ skills (pret/pmd-sky overlay_29_0230BBAC.c / type_effectiveness.c; only
## active on team members that have them switched on, so Red's numbers are untouched otherwise):
##   Aggressor / Defender / Practice Swinger / Cheerleader (offense stage), Counter Basher / Aggressor /
##   Defender (defense stage), Sharpshooter (+15 crit odds), Critical Dodger (no crits taken),
##   Erratic Player (type multipliers 0.25/0.5/1/1.7), Concentrator (+1 acc / -1 eva stage),
##   Clutch Performer (+2 eva stage at HP <= 1/4).

# ------------------------------------------------------------------ data
static var moves: Dictionary = {}
static var chart: Dictionary = {}
static var combine: Array = []
static var type_names: Array = []
static var _loaded := false

static func load_data() -> void:
	if _loaded:
		return
	moves = _read_json("res://data/moves.json")
	var t := _read_json("res://data/types.json")
	chart = t.get("chart", {})
	combine = t.get("combine", [[0, 0, 0, 1], [0, 1, 1, 2], [0, 1, 2, 3], [1, 2, 3, 3]])
	type_names = t.get("types", [])
	_loaded = true

static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Combat: missing " + path)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func move(name: String) -> Dictionary:
	load_data()
	return moves.get(name, {})

## Red's plain attack (MOVE_REGULAR_ATTACK): type None, power 1, crit 12, acc 125/125, and damage
## modifier 0.5 (dungeon_move.c). calc_damage applies the 0.5 automatically for it.
static func regular_attack() -> Dictionary:
	load_data()
	return moves.get("Regular Attack", {"id": 0, "name": "Attack", "t": "None", "p": 1, "pp": 0,
		"a1": 125, "a2": 125, "crit": 12, "hits": 1, "r": "front", "c": "P"})

# ------------------------------------------------------------------ constants (dungeon_config.c / dungeon_data.c)
## s24_8 stage multipliers, index 0..20 (10 = neutral). Values are IntToF248(x) = (int)(x*256), as in the ROM.
const ATK_STAGE := [64, 69, 74, 79, 84, 89, 102, 115, 128, 179, 256, 332, 384, 409, 422, 435, 448, 460, 473, 486, 512]
const DEF_STAGE := [64, 69, 74, 79, 84, 89, 102, 140, 179, 222, 256, 332, 384, 409, 422, 435, 448, 460, 473, 486, 512]
const ACC_STAGE := [84, 89, 94, 102, 110, 115, 140, 153, 179, 204, 256, 320, 384, 409, 422, 435, 448, 460, 473, 486, 512]
const EVA_STAGE := [512, 486, 473, 460, 448, 435, 422, 409, 384, 345, 256, 204, 179, 153, 128, 102, 89, 76, 64, 51, 38]

const PHYSICAL_TYPES := ["None", "Normal", "Fighting", "Poison", "Ground", "Flying", "Bug", "Rock", "Ghost", "Steel"]

const POWER_BAND_BOOST := 12
const SPECIAL_BAND_BOOST := 12
const DEF_SCARF_BOOST := 8
const ZINC_BAND_BOOST := 8
const MUNCH_BELT_BOOST := 8
const CRIT_ODDS_SCOPE_LENS_PATSY_BAND := 40
const CRIT_ODDS_IQ_ADVANTAGE_MASTER := 40
const DETECT_BAND_ACC_DEBUFF := 30
const IQ_QUICK_DODGER_ACC_DEBUFF := 30
const SET_DAMAGE_VALUE := 35
## Sky add-on (pmd-sky overlay 10 data)
const CRIT_ODDS_SHARPSHOOTER := 15        # SCOPE_LENS_CRIT_RATE_BOOST (Sky's Scope Lens / Sharpshooter)
## MATCHUP_*_MULTIPLIER_ERRATIC_PLAYER as s48_16: 0x40, 0x80, 0x100, 0x1B3 (s24_8) -> 0.25, 0.5, 1, ~1.7
const EFF_MUL_FP_ERRATIC := [0x4000, 0x8000, 0x10000, 0x1B300]

# Residual damage (dungeon_config.c + dungeon_turn_effects.c). The countdown starts at 0 when the
# status is inflicted, so the first tick happens on the first turn-end, then every `interval` turns.
const BURN_DMG := 5
const BURN_INTERVAL := 20
const POISON_DMG := 4
const POISON_INTERVAL := 10
const BAD_POISON_INTERVAL := 2
const BAD_POISON_DMG_BY_TURN := [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]
const CONSTRICTION_DMG := 5
const CONSTRICTION_INTERVAL := 2
const WRAP_DMG := 6
const WRAP_INTERVAL := 2
const NIGHTMARE_DMG := 8
const HAIL_SANDSTORM_DMG := 5
const CURSE_INTERVAL := 10
const LEECH_SEED_INTERVAL := 2

## {dmg, interval} for a residual status: "burn", "poison", "badpoison", "constriction", "wrap".
static func status_damage(kind: String, bad_poison_count := 0) -> Dictionary:
	match kind:
		"burn": return {"dmg": BURN_DMG, "interval": BURN_INTERVAL}
		"poison": return {"dmg": POISON_DMG, "interval": POISON_INTERVAL}
		"badpoison": return {"dmg": bad_poison_dmg(bad_poison_count), "interval": BAD_POISON_INTERVAL}
		"constriction": return {"dmg": CONSTRICTION_DMG, "interval": CONSTRICTION_INTERVAL}
		"wrap": return {"dmg": WRAP_DMG, "interval": WRAP_INTERVAL}
	return {"dmg": 0, "interval": 0}

## Bad poison damage for the n-th tick (0-based). Always 6 in Red, but kept table-driven like the ROM.
static func bad_poison_dmg(n: int) -> int:
	return BAD_POISON_DMG_BY_TURN[clampi(n, 0, BAD_POISON_DMG_BY_TURN.size() - 1)]

# ------------------------------------------------------------------ fixed point (src/math.c)
# s24_8 is a plain int (256 = 1.0). s48_16 is represented as a 64-bit int holding value*65536
# (the C struct is {s32 hi; u32 lo} = the high/low halves of exactly that 64-bit number).
const F16_ONE := 0x10000

static func f248(x: float) -> int:      # IntToF248: (int)(x * 0x100), truncation toward zero
	return int(x * 256.0)

static func f248_to_int(x: int) -> int:  # F248ToInt: C division, truncation toward zero
	return int(x / 256) if x >= 0 else -int(-x / 256)

static func s24_8_mul(x: int, y: int) -> int:
	if x == 0 or y == 0:
		return 0
	var neg := (x < 0) != (y < 0)
	var p := absi(x) * absi(y)
	var r := ((p >> 8) + ((p >> 7) & 1)) & 0xFFFFFFFF
	return -r if neg else r

static func fp_from_s32(src: int) -> int:  # FP48_16_FromS32, including its sign-extension bug
	var u := src & 0xFFFFFFFF
	var hi := (u >> 16) & 0xFFFF
	var lo := (u & 0xFFFF) << 16
	if u & 0x8000:
		hi |= 0xFFFF0000
	if hi & 0x80000000:
		hi -= 0x100000000
	return hi * 0x100000000 + lo

static func fp_to_s32(v: int) -> int:      # FP48_16_ToS32: rounds half up via bit 15
	var hi := v >> 32
	var lo := v & 0xFFFFFFFF
	var r := ((hi & 0xFFFF) << 16) | (lo >> 16)
	if lo & 0x8000:
		r += 1
	r &= 0xFFFFFFFF
	if r & 0x80000000:
		r -= 0x100000000
	return r

static func fp_from_f248(b: int) -> int:
	return b << 8

static func fp_mul(a: int, b: int) -> int:  # F48_16_SMul (sign-magnitude, UMul rounds on bit 15)
	if a == 0 or b == 0:
		return 0
	var neg := (a < 0) != (b < 0)
	var p := absi(a) * absi(b)
	var r := (p >> 16) + ((p >> 15) & 1)
	return -r if neg else r

static func fp_div(a: int, b: int) -> int:  # F48_16_SDiv: quotient of ((|a|<<16) | 0x8000) / |b|
	if b == 0:
		return 0x7FFFFFFFFFFFFFFF
	if a == 0:
		return 0
	var neg := (a < 0) != (b < 0)
	var n := (absi(a) << 16) | 0x8000
	var q := int(n / absi(b))
	return -q if neg else q

# ------------------------------------------------------------------ type effectiveness
static func _type_at(types: Array, i: int) -> String:
	return String(types[i]) if i < types.size() and types[i] != null and String(types[i]) != "" else "None"

static func _chart(atk_type: String, def_type: String) -> int:
	var row: Dictionary = chart.get(atk_type, {})
	return int(row.get(def_type, 2))

## Displayed effectiveness 0..3 (0 "little effect", 1 "not very effective", 2 neutral, 3 super), as Red
## stores it in DamageStruct.typeEffectiveness: per-type chart values merged through `combine`.
## `exposed` = the defender's Foresight/Odor Sleuth flag (Normal/Fighting vs Ghost rule).
static func type_eff(move_type: String, def_types: Array, exposed := false) -> int:
	load_data()
	var e := [2, 2]
	for i in 2:
		var dt := _type_at(def_types, i)
		if (move_type == "Normal" or move_type == "Fighting") and dt == "Ghost" and not exposed:
			e[i] = 0
		else:
			e[i] = _chart(move_type, dt)
	return int(combine[e[0]][e[1]])

## Red's per-defender-type damage multiplier for a chart value (sub_806E100's local_48 table:
## 0x8000, 0xE666, 0x10000, 0x18000). It is applied once per defender type and multiplied.
const EFF_MUL_FP := [0x8000, 0xE666, 0x10000, 0x18000]
static func eff_multiplier(eff: int) -> float:
	return EFF_MUL_FP[clampi(eff, 0, 3)] / 65536.0

## Total type multiplier Red would apply for move_type vs def_types (product over both types).
static func type_multiplier(move_type: String, def_types: Array, exposed := false) -> float:
	load_data()
	var m := F16_ONE
	for i in 2:
		var dt := _type_at(def_types, i)
		var e := _chart(move_type, dt)
		if (move_type == "Normal" or move_type == "Fighting") and dt == "Ghost" and not exposed:
			e = 0
		if e != 2:
			m = fp_mul(m, EFF_MUL_FP[e])
	return m / 65536.0

static func is_physical(t: String) -> bool:
	return PHYSICAL_TYPES.has(t)

# ------------------------------------------------------------------ helpers mirroring Red's checks
static func _norm(s: String) -> String:
	var r := s.to_lower().replace("_", "-").replace(" ", "-")
	match r:
		"compoundeyes": return "compound-eyes"
		"lightningrod": return "lightning-rod"
	return r

static func has_ability(m: Mon, a: String) -> bool:  # AbilityIsActive: either ability slot
	if m == null:
		return false
	var want := _norm(a)
	return _norm(m.ability) == want or _norm(m.ability2) == want

static func holds(m: Mon, item_id: String) -> bool:   # HasHeldItem (sticky items don't count)
	if m == null or m.held != item_id:
		return false
	var sticky = m.get("held_sticky")
	return not (sticky != null and bool(sticky))

static func has_iq(m: Mon, skill: String) -> bool:
	if m == null:
		return false
	var want := skill.to_lower().replace("-", "").replace("_", "").replace(" ", "")
	for s in m.iq_skills:
		if String(s).to_lower().replace("-", "").replace("_", "").replace(" ", "") == want:
			return true
	return false

static func is_type(m: Mon, t: String) -> bool:        # MonsterIsType: TYPE_NONE never matches
	if t == "None" or t == "":
		return false
	return _type_at(m.types, 0) == t or _type_at(m.types, 1) == t

static func _st(m: Mon, k: String) -> int:
	return int(m.status.get(k, 0))

## MonsterHasNegativeStatus (dungeon_logic.c) — used by Guts and Marvel Scale.
static func has_negative_status(m: Mon) -> bool:
	for k in ["sleep", "nightmare", "yawn",
			"burn", "poison", "badpoison", "para",              # whole burn class
			"frozen", "wrapped", "wrapping", "petrified", "shadow_hold", "constriction",  # frozen class minus Ingrain
			"cringe", "confused", "paused", "cowering", "taunt", "encore", "infatuated",  # whole cringe class
			"curse", "decoy", "leech_seed", "whiffer", "blinker", "cross_eyed", "muzzled",
			"perish", "slow"]:                                   # slow = speedDownCounters
		if _st(m, k) > 0:
			return true
	if m.exposed:
		return true
	for mv in m.moves:
		if mv is Dictionary and mv.get("sealed", false):
			return true
	return false

## Weather as seen by `m` (GetApparentWeather: a held Weather Band makes it clear).
## ctx.weather: "clear" | "sunny" | "sandstorm" | "cloudy" | "rain" | "hail" | "fog" | "snow".
## TODO(red): Cloud Nine / Air Lock are applied by the weather system setting the floor weather, not here.
static func apparent_weather(m: Mon, ctx: Dictionary) -> String:
	if m != null and holds(m, "weatherband"):
		return "clear"
	var w := String(ctx.get("weather", "clear")).to_lower()
	match w:
		"sun", "sunny", "harsh sunlight": return "sunny"
		"rain", "rainy": return "rain"
	return w

static func _team(m: Mon) -> bool:
	return m.side == "team"

## SetVisualFlags: Red only prints an ability-activation message on the turn the effect switches on.
## Stored as Object metadata so mon.gd needs no extra field.
static func _vis(m: Mon, flag: int, on: bool) -> bool:
	var cur: int = m.get_meta("red_vis", 0)
	var prev_on := (cur & flag) != 0
	cur = (cur | flag) if on else (cur & ~flag)
	m.set_meta("red_vis", cur)
	return on and not prev_on

static func _vis_clear(m: Mon, flag: int) -> void:
	m.set_meta("red_vis", int(m.get_meta("red_vis", 0)) & ~flag)

static func _rand(rng: RandomNumberGenerator, n: int) -> int:  # DungeonRandInt(n): 0..n-1
	return rng.randi_range(0, n - 1)

static func _is_regular(mv: Dictionary, ctx: Dictionary) -> bool:
	return bool(ctx.get("is_regular_attack", false)) or int(mv.get("id", -1)) == 0 or mv.get("name", "") == "Regular Attack"

# ------------------------------------------------------------------ accuracy (AccuracyCalc)
## One AccuracyCalc roll. ctx.acc_type: 1 = accuracy1 (rolled for every move, every target, in the move
## loop) or 2 = accuracy2 (rolled for damaging moves after damage is calculated; calc_damage does this one
## itself unless ctx.skip_accuracy2). ctx.self_always_hits (default true) makes att == def always hit.
static func accuracy_hits(att: Mon, def: Mon, mv: Dictionary, rng: RandomNumberGenerator, ctx := {}) -> bool:
	var rand := _rand(rng, 100)   # Red draws the roll before any early-outs
	if att != null and def != null and (has_ability(att, "no guard") or has_ability(def, "no guard")):
		return true                # EoS No Guard
	var hit := rand < accuracy_threshold(att, def, mv, ctx)
	if not hit and att != null and att != def and has_iq(att, "Practice Swinger"):
		att.set_meta("practice_swinger", true)    # Sky: next attack gets +1 offense stage
	return hit

## The number AccuracyCalc compares DungeonRandInt(100) against (hit if roll < value).
## Auto-hit returns 1000, auto-miss (Whiffer) returns 0. Equals the hit chance in percent.
static func accuracy_threshold(att: Mon, def: Mon, mv: Dictionary, ctx := {}) -> int:
	var acc_type := int(ctx.get("acc_type", 1))
	var accuracy := int(mv.get("a1" if acc_type == 1 else "a2", 100))
	if bool(ctx.get("self_always_hits", true)) and att == def:
		return 1000
	if _is_regular(mv, ctx) and has_iq(att, "Sure-Hit Attacker"):
		return 1000
	if _st(att, "sure_shot") > 0:
		return 1000
	if _st(att, "whiffer") > 0:
		return 0
	if accuracy > 100:
		return 1000
	if holds(def, "detectband"):
		accuracy -= DETECT_BAND_ACC_DEBUFF
	if has_iq(def, "Quick Dodger"):
		accuracy -= IQ_QUICK_DODGER_ACC_DEBUFF

	var acc_stage := int(att.stages.get("acc", 10))
	if has_ability(att, "compound-eyes"):
		acc_stage += 2
	if has_iq(att, "Concentrator"):
		acc_stage += 1                 # Sky add-on
	if mv.get("name", "") == "Thunder":
		var w := apparent_weather(att, ctx)
		if w == "rain":
			return 1000
		elif w == "sunny":
			acc_stage -= 2
	acc_stage = clampi(acc_stage, 0, 20)
	accuracy = _cdiv(accuracy * ACC_STAGE[acc_stage], 256)

	var eva_stage := int(def.stages.get("eva", 10))
	if def.exposed:
		eva_stage = 10
	if apparent_weather(def, ctx) == "sandstorm" and has_ability(def, "sand-veil"):
		eva_stage += 2
	if apparent_weather(def, ctx) == "hail" and has_ability(def, "snow cloak"):
		eva_stage += 2
	if EosItems.weather_eva(def, apparent_weather(def, ctx)):       # EoS exclusive items
		eva_stage += 2
	if has_ability(att, "keen eye") and eva_stage > 10:            # Remixed Keen Eye ignores evasion boosts
		eva_stage = 10
	# Hustle checks the move's listed type (GetMoveType), not Hidden Power's.
	if has_ability(att, "hustle") and is_physical(String(mv.get("t", "None"))):
		eva_stage += 2
	if not def.exposed:                # Sky add-on (exposed ignores evasion, as above)
		if has_iq(def, "Concentrator"):
			eva_stage -= 1
		if has_iq(def, "Clutch Performer") and def.hp <= def.max_hp / 4:
			eva_stage += 2
	eva_stage = clampi(eva_stage, 0, 20)
	return _cdiv(accuracy * EVA_STAGE[eva_stage], 256)

static func _cdiv(a: int, b: int) -> int:  # C integer division (truncates toward zero)
	var q := int(absi(a) / absi(b))
	return -q if (a < 0) != (b < 0) else q

# ------------------------------------------------------------------ Sky add-on stage modifiers
## Offense stage change from Sky IQ skills (overlay_29_0230BBAC.c): Aggressor +1, Defender -1, Practice
## Swinger +1 after a miss, +1 when a teammate within 1 tile has Cheerleader (NearbyAllyIqSkillIsEnabled).
## The floor for the Cheerleader check is ctx.fs, else Combat.sky_floor (set by IQSky.on_floor_start).
static var sky_floor = null

static func _sky_offense_stage(att: Mon, practice: bool, ctx: Dictionary) -> int:
	var n := 0
	if has_iq(att, "Aggressor"):
		n += 1
	if has_iq(att, "Defender"):
		n -= 1
	if practice and has_iq(att, "Practice Swinger"):
		n += 1
	if att.is_team() and nearby_ally_has_iq(att, "Cheerleader", ctx.get("fs", sky_floor)):
		n += 1
	return n

## NearbyAllyIqSkillIsEnabled: a living teammate (not m) within 1 tile has the skill. `floor_state` is a
## FloorState (only its `mons` list is read); null -> false.
static func nearby_ally_has_iq(m: Mon, skill: String, floor_state) -> bool:
	if floor_state == null or m == null:
		return false
	for o in floor_state.mons:
		if o != m and o.hp > 0 and o.side == m.side and maxi(absi(o.pos.x - m.pos.x), absi(o.pos.y - m.pos.y)) <= 1 \
				and has_iq(o, skill):
			return true
	return false

## Defense stage change: Counter Basher -1 (physical only), Aggressor -1, Defender +1.
static func _sky_defense_stage(def: Mon, physical: bool) -> int:
	var n := 0
	if physical and has_iq(def, "Counter Basher"):
		n -= 1
	if has_iq(def, "Aggressor"):
		n -= 1
	if has_iq(def, "Defender"):
		n += 1
	return n

# ------------------------------------------------------------------ damage
## ApplyAtkDefStatBoosts. Returns [atk, def]. `msgs` collects activation messages (or null).
static func _atk_def_boosts(att: Mon, def: Mon, physical: bool, atk: int, dfn: int, rand: int, ctx: Dictionary, msgs) -> Array:
	var am := 1
	var ad := 1
	var dm := 1
	var dd := 1
	if has_ability(att, "guts"):
		var on := has_negative_status(att)
		if on:
			am = 2
		if _vis(att, 0x1, on) and msgs != null:
			msgs.append("Guts boosted its power!")
	if has_ability(att, "huge-power") or has_ability(att, "pure-power"):
		var on := rand < 33 and physical
		if on:
			am *= 3
			ad *= 2
		if _vis(att, 0x100, on) and msgs != null:
			msgs.append("Its special ability boosted Attack!")
	if has_ability(att, "hustle") and physical:
		am *= 3
		ad *= 2
	# gDungeon->plusIsActive/minusIsActive[side]: whether an ally on the attacker's side has Plus/Minus.
	if has_ability(att, "plus") and not physical and bool(ctx.get("minus_active", false)):
		am *= 15
		ad *= 10
	if has_ability(att, "minus") and not physical and bool(ctx.get("plus_active", false)):
		am *= 15
		ad *= 10
	if has_ability(def, "intimidate") and physical:
		am *= 4
		ad *= 5
	if has_ability(def, "marvel-scale") and physical:
		var on := has_negative_status(def)
		if on:
			dm *= 3
			dd *= 2
		if _vis(def, 0x8, on) and msgs != null:
			msgs.append("Marvel Scale boosted its Defense!")
	atk *= am
	dfn *= dm
	if ad != 1:
		atk = _cdiv(atk, ad)
	if dd != 1:
		dfn = _cdiv(dfn, dd)
	return [atk, dfn]

## sub_806E100: type effectiveness + ability + STAB + weather multiplier (s48_16).
## Returns {mul, eff, super, zeroed (unkE), wonder_guard_zero}.
static func _type_mod(att: Mon, def: Mon, t: String, ctx: Dictionary, msgs: Array) -> Dictionary:
	var mul := F16_ONE
	var normal_or_fighting := t == "Normal" or t == "Fighting"
	var wonder_guard := has_ability(def, "wonder-guard") and t != "None"
	var erratic := has_iq(att, "Erratic Player") or has_iq(def, "Erratic Player")   # Sky add-on
	var e := [2, 2]
	for i in 2:
		var dt := _type_at(def.types, i)
		var eff: int
		if normal_or_fighting and dt == "Ghost" and not def.exposed and not EosItems.has(att, "ghost_hit") and not has_ability(att, "scrappy"):
			eff = 0
		else:
			eff = _chart(t, dt)
			if eff == 0 and t == "Psychic" and dt == "Dark" and EosItems.has(att, "dark_hit"):
				eff = 2
		if eff != 2:
			mul = fp_mul(mul, EFF_MUL_FP_ERRATIC[eff] if erratic else EFF_MUL_FP[eff])
		e[i] = eff
	var res := {"eff": int(combine[e[0]][e[1]]), "zeroed": false, "wonder_guard_zero": false}
	var is_super: bool = res.eff == 3
	if not is_super and wonder_guard:
		mul = 0
		res.wonder_guard_zero = true

	if (t == "Fire" or t == "Ice") and has_ability(def, "thick-fat"):
		mul = fp_mul(mul, 0x8000)
	if t == "Fire" and has_ability(def, "flash-fire"):
		mul = 0
		res.eff = 0
		res.zeroed = true
		is_super = false
	if t == "Ground" and has_ability(def, "levitate"):
		mul = 0
		res.eff = 0
		res.zeroed = true
		is_super = false
	var pinch := att.max_hp / 4 >= att.hp
	for pair in [["Water", "torrent", 0x80, "Torrent"], ["Grass", "overgrow", 0x2, "Overgrow"],
			["Bug", "swarm", 0x10, "Swarm"], ["Fire", "blaze", 0x20, "Blaze"]]:
		if t == pair[0] and has_ability(att, pair[1]):
			if pinch:
				mul = fp_mul(mul, 0x20000)
			if _vis(att, pair[2], pinch):
				msgs.append("%s boosted its power!" % pair[3])
	if mul != 0 and is_type(att, t):
		mul = fp_mul(mul, 0x18000)    # STAB x1.5
	var w := apparent_weather(att, ctx)
	if w == "sunny":
		if t == "Fire":
			mul = fp_mul(mul, 0x18000)
		elif t == "Water":
			mul = fp_mul(mul, 0x8000)
	if w == "rain":
		if t == "Fire":
			mul = fp_mul(mul, 0x8000)
		elif t == "Water":
			mul = fp_mul(mul, 0x18000)
	if w == "cloudy" and t != "Normal":   # note: also hits type-None (regular attack) in Red
		mul = fp_mul(mul, 0xC000)
	if (bool(ctx.get("mud_sport", false)) or w == "fog") and t == "Electric":
		mul = fp_mul(mul, 0x8000)
	if bool(ctx.get("water_sport", false)) and t == "Fire":
		mul = fp_mul(mul, 0x8000)
	# bideClassStatus == STATUS_CHARGING (the move Charge)
	if t == "Electric" and (bool(ctx.get("charged", false)) or _st(att, "charge") > 0):
		mul = fp_mul(mul, 0x20000)
	res.mul = mul
	res.super = is_super
	return res

## Full Red damage calculation (CalcDamage) plus the parts of TryHitTarget/HandleDealingDamageInternal
## that decide the final number: the accuracy2 roll, Set Damage, frozen targets, Volt/Water Absorb.
## ctx keys:
##   weather (String), is_regular_attack (bool), power_bonus (int, Ginseng; also read from move.ginseng),
##   modifier (float, the move's s24_8 power modifier: 2.0 Solar Beam/Fly/Dig/Facade..., default 1.0;
##            regular attack is forced to 0.5), from_move (bool, Red's arg_10: true for normal move use —
##            enables Def. Scarf/Zinc Band, Reflect/Light Screen, Flash Fire boost; default true),
##   att_belly_empty (bool; a non-leader with 0 belly always deals 1), mud_sport, water_sport, charged,
##   plus_active / minus_active (bool, an ally on the attacker's side has Plus / Minus),
##   move_type (String override, e.g. Hidden Power / Weather Ball), skip_accuracy2 (bool).
## Returns {dmg, eff, crit, missed_by_type, missed, msg, heal, absorbed, type, physical}.
static func calc_damage(att: Mon, def: Mon, mv: Dictionary, rng: RandomNumberGenerator, ctx := {}) -> Dictionary:
	load_data()
	var t := String(ctx.get("move_type", mv.get("t", "None")))
	# TODO(red): Hidden Power uses the monster's own hiddenPower type/base power (GetMoveTypeForMonster /
	# GetMovePower); pass ctx.move_type and ctx.power_bonus until Mon stores them.
	var physical := is_physical(t)
	var split_atk := "atk" if physical else "spa"
	var split_def := "def" if physical else "spd"
	var regular := _is_regular(mv, ctx)
	var from_move := bool(ctx.get("from_move", true))
	var power := int(mv.get("p", 0)) + int(mv.get("ginseng", 0)) + int(ctx.get("power_bonus", 0))
	var crit_chance := int(mv.get("crit", 0))
	var modifier := f248(0.5) if regular else f248(float(ctx.get("modifier", 1.0)))
	var out := {"dmg": 0, "eff": 2, "crit": false, "missed_by_type": false, "missed": false,
		"msg": [] as Array[String], "heal": 0, "absorbed": false, "type": t, "physical": physical}
	var msgs: Array[String] = []
	var practice := bool(att.get_meta("practice_swinger", false))
	if practice:
		att.remove_meta("practice_swinger")       # Sky: the boost lasts for one attack

	var unk_e := false
	if (not att.is_leader and bool(ctx.get("att_belly_empty", false))) or (regular and has_ability(def, "wonder-guard")):
		out.dmg = 1     # SetDamageOne
		out.eff = 2
	else:
		# --- attack stat
		var atk_stage := int(att.stages.get(split_atk, 10))
		if from_move and t == "Fire":
			atk_stage += _st(att, "flash_fire")   # flashFireBoost (0..2)
		# TODO(red): Deoxys Attack/Defense/Speed forms shift atk stage +2/-2/-2 and def stage -2/+2/-2
		# (apparentID). Mon has no form id yet; pass ctx.att_deoxys_form / ctx.def_deoxys_form = "attack"|"defense"|"speed".
		match String(ctx.get("att_deoxys_form", "")):
			"attack": atk_stage += 2
			"defense", "speed": atk_stage -= 2
		atk_stage += _sky_offense_stage(att, practice, ctx)
		atk_stage = clampi(atk_stage, 0, 20)
		var sc := s24_8_mul((att.stat(split_atk) + power) * 256, ATK_STAGE[atk_stage])
		sc = s24_8_mul(sc, int(att.stat_mult.get(split_atk, 256)))
		var atk_stat := f248_to_int(sc)

		# --- defense stat
		var def_stage := int(def.stages.get(split_def, 10))
		if physical and _st(def, "charging") > 0 and def.status.get("charge_move", "") == "Skull Bash":
			def_stage += 1
		match String(ctx.get("def_deoxys_form", "")):
			"attack", "speed": def_stage -= 2
			"defense": def_stage += 2
		def_stage += _sky_defense_stage(def, physical)
		def_stage = clampi(def_stage, 0, 20)
		sc = s24_8_mul(def.stat(split_def) * 256, DEF_STAGE[def_stage])
		sc = s24_8_mul(sc, int(def.stat_mult.get(split_def, 256)))
		var def_stat := f248_to_int(sc)

		var rand := _rand(rng, 100)
		if physical:
			if holds(att, "powerband"): atk_stat += POWER_BAND_BOOST
			if holds(att, "munchbelt"): atk_stat += MUNCH_BELT_BOOST
			if from_move and holds(def, "defscarf"): def_stat += DEF_SCARF_BOOST
		else:
			if from_move and holds(def, "zincband"): def_stat += ZINC_BAND_BOOST
			if holds(att, "specialband"): atk_stat += SPECIAL_BAND_BOOST
			if holds(att, "munchbelt"): atk_stat += MUNCH_BELT_BOOST
		atk_stat += EosItems.stat(att, split_atk)        # EoS exclusive items
		if from_move:
			def_stat += EosItems.stat(def, split_def)
		atk_stat = clampi(Awaken.boost(att, atk_stat), 0, 999)    # DX: Awakened
		def_stat = Awaken.boost(def, def_stat)

		_vis_clear(att, 0x100)
		var ad := _atk_def_boosts(att, def, physical, atk_stat, def_stat, rand, ctx, msgs)
		atk_stat = ad[0]
		def_stat = ad[1]

		var sp1 := fp_div(fp_from_s32(atk_stat - def_stat), fp_from_s32(8))
		var sp2: int
		if _team(att):
			sp2 = fp_mul(fp_from_s32(att.level), 0xAAAA)     # level * 2/3
		else:
			var ad2 := _atk_def_boosts(att, def, physical, att.stat(split_atk), 1, rand, ctx, null)
			sp2 = fp_div(fp_from_s32(ad2[0]), fp_from_s32(3)) # raw attack / 3
		var sp4 := sp1 + sp2
		var sp5 := fp_mul(fp_mul(sp4, sp4), 0xCCC)            # ((A-D)/8 + L)^2 / 20 (0xCCC ~= 0.05)
		var sp7 := fp_mul(sp4, fp_from_s32(2)) - fp_from_s32(def_stat) + fp_from_s32(10)
		var sp8 := sp5 + sp7
		if sp8 > 999 * F16_ONE:
			sp8 = 999 * F16_ONE
		if sp8 < F16_ONE:
			sp8 = F16_ONE

		var tm := _type_mod(att, def, t, ctx, msgs)
		var sp9: int = tm.mul
		out.eff = tm.eff
		unk_e = tm.zeroed
		if int(out.eff) < 2 and not tm.zeroed and not tm.wonder_guard_zero and Awaken.is_awake(att):
			sp9 = F16_ONE                                   # DX: no type disadvantages while Awakened
			out.eff = 2
		if int(out.eff) == 3 and has_ability(def, "delta-stream") and "Flying" in def.types:
			sp9 = F16_ONE                                   # Delta Stream
			out.eff = 2
		out.missed_by_type = tm.zeroed or tm.wonder_guard_zero
		if t == "Fire" and has_ability(def, "flash-fire") and from_move:
			# TODO(red): Red shows this once per move use (targetInfo->unk152) and raises the target's
			# flashFireBoost via ActivateFlashFire in the move code; the caller should bump status.flash_fire.
			msgs.append("Fire moves won't become stronger!" if _st(def, "flash_fire") >= 2 else "%s used Flash Fire to absorb fire!" % def.name)
		if from_move:
			if physical and _st(def, "reflect") > 0:
				sp9 = fp_mul(sp9, 0x8000)
			if not physical and _st(def, "light_screen") > 0:
				sp9 = fp_mul(sp9, 0x8000)

		# --- critical hit
		if not has_ability(def, "battle-armor") and not has_ability(def, "shell-armor") and not has_iq(def, "Critical Dodger") and not EosItems.has(def, "no_crit"):
			var odds := crit_chance if _team(att) else 0
			if _st(att, "focus_energy") > 0:
				odds = 999
			else:
				if holds(att, "scopelens"): odds += CRIT_ODDS_SCOPE_LENS_PATSY_BAND
				if has_ability(att, "super luck"): odds += 12          # EoS Super Luck
				if has_iq(att, "Sharpshooter"): odds += CRIT_ODDS_SHARPSHOOTER   # Sky add-on
				if holds(def, "patsyband"): odds += CRIT_ODDS_SCOPE_LENS_PATSY_BAND
				if tm.super and has_iq(att, "Type-Advantage Master"):
					odds = CRIT_ODDS_IQ_ADVANTAGE_MASTER
			if bool(att.get_meta("linked_hit", false)) and Awaken.is_awake(att):
				odds = 999                                  # DX: an Awakened Pokémon's linked moves always crit
			if _rand(rng, 100) < odds:
				sp9 = fp_mul(sp9, 0x18000)
				out.crit = true
		if unk_e:
			out.crit = false

		sp8 = fp_mul(sp8, sp9)
		sp8 = fp_mul(sp8, fp_from_f248(modifier))
		sp8 = fp_mul(sp8, 0xE000 + _rand(rng, 0x4000))      # random x0.875 .. x1.125
		out.dmg = fp_to_s32(sp8)
		out.dmg = load("res://scripts/core/launcher_cfg.gd").scale_damage(int(out.dmg), _team(att), _team(def))   # launcher sliders
		if out.dmg == 0:
			out.crit = false

	# --- TryHitTarget_Async: accuracy2 is rolled after the damage numbers are drawn
	if not bool(ctx.get("skip_accuracy2", false)):
		var c2 := ctx.duplicate()
		c2["acc_type"] = 2
		c2["self_always_hits"] = true
		if not accuracy_hits(att, def, mv, rng, c2):
			out.missed = true
			out.dmg = 0
			out.crit = false
			out.msg = [("%s took no damage!" % def.name)] as Array[String]
			return out

	# --- HandleDealingDamageInternal_Async
	if _st(att, "set_damage") > 0 and not unk_e:
		out.dmg = SET_DAMAGE_VALUE
	if _st(def, "frozen") > 0:
		msgs.append("%s is frozen!" % def.name)
		out.dmg = 0
		out.msg = msgs
		return out
	if (has_ability(def, "volt-absorb") and t == "Electric") or (has_ability(def, "water-absorb") and t == "Water"):
		out.heal = out.dmg
		out.dmg = 0
		out.absorbed = true
		out.msg = msgs
		return out
	if out.crit:
		msgs.append("A critical hit!")
	match int(out.eff):
		0: msgs.append("It has little effect...")
		1: msgs.append("It's not very effective...")
		3: msgs.append("It's super effective!")
	if out.dmg == 0:
		msgs.append("%s took no damage!" % def.name)
	# TODO(red): Sturdy only blocks 9999 (one-hit KO) damage; Endure/False Swipe leave 1 HP; Counter,
	# Mirror Coat, Rough Skin return damage; Joy Ribbon EXP — all part of damage application, not here.
	out.msg = msgs
	return out
