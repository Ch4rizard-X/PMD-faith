class_name AI
extends RefCounted
## Dungeon AI ported from pret/pmd-red: dungeon_ai.c (RunMonsterAI), dungeon_ai_attack.c (ChooseAIMove,
## AIConsiderMove, TargetRegularAttack), dungeon_ai_movement.c (AIMovement, ChooseTargetPosition,
## DecideMovement, AvoidEnemies, Wander), dungeon_logic.c / dungeon_util.c / dungeon_range.c helpers and
## move_checks.c (Status Checker).
##
## AI.decide(m, fs, memory) returns ONE action:
##   {type:"move",   dir:int}                       walk one tile (always a legal step when returned)
##   {type:"attack", move:"", dir:int}              regular attack (ACTION_REGULAR_ATTACK)
##   {type:"attack", move:"Name", dir:int, chain:[names]}   ACTION_USE_MOVE_AI; chain = the whole link chain
##                                                  starting at that move (caller spends PP for each)
##   {type:"attack", move:"Struggle", dir:int}       ACTION_STRUGGLE (no PP left on any move)
##   {type:"item", action:"pickup"}                  ACTION_PICK_UP_AI (standing on an item, hands free)
##   {type:"wait"}                                   ACTION_PASS_TURN / ACTION_NOTHING.
##        Optional extra keys: dir (face this way), ally_skip:true (team member blocked by a Pokémon:
##        Red re-runs its AI after the others have moved, nearest-to-leader first, up to 3 passes, with
##        memory.recalculate_follow = true -- see sub_8044574_Async in dungeon_engine.c).
## The leader (m.is_leader) is never decided for: decide() returns {type:"wait"} for it.
##
## memory (per Pokémon, owned by the caller, keyed by uid) -- Red's EntityInfo.aiTarget & friends:
##   objective: "" | "chase" | "chase_remembered" | "roam" | "leave_room" | "run_away" | "stand_still" | "take_item"
##   target_pos: Vector2i        aiTargetPos
##   target_uid: int             aiTarget (+ spawnGenID): -1 = none
##   move_randomly: bool         EntityInfo.moveRandomly (set at spawn from the dungeon's randomMovementChance)
##   targeting_enemy, turning_around, not_next_to_target, ally_skip, waiting: bool (aiTarget flags)
##   recalculate_follow: bool    set by the CALLER for the ally re-run pass (Red: recalculateFollow)
##   tactic: String              optional override of the mon's tactic (else m meta "tactic"; team default
##                               "lets_go_together", wild always "go_after_foes" per LoadIQSkills)
## Other per-mon state read from Mon metadata (optional): "prev_pos" (Array of 4 Vector2i, maintained by
## AI.on_moved), "tactic", "belly" (allies), "boss", "shopkeeper".

const DIRS := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1)]
## gFaceDirectionIncrements (dungeon_pos_data.c), first half.
const FACE_INC := [0, 1, -1, 2, -2, 3, -3, 4]
const TURN_LEFT_45 := 1
const TURN_RIGHT_45 := 2
const TURN_LEFT_90 := 3
const TURN_RIGHT_90 := 4
const TURN_LEFT_135 := 5
const INFINITY := 999                       # dungeon_ai_movement.c
const INFINITY_2 := 999999
const CHECK_VISIBILITY_DISTANCE := 5
const CORRIDOR_VISIBILITY := 2
const NUM_PREV_POS := 4                     # structs/dungeon_entity.h
const RANGED_ATTACK_RANGE := 10             # dungeon_ai_attack.h
const REGULAR_ATTACK_INDEX := 4
const AI_REGULAR_ATTACK_WEIGHTS := [100, 20, 30, 40, 50]   # gAiRegularAttackWeights (dungeon_config.c)
const AI_CONFUSED_ATTACK_CHANCE := 70       # gAIConfusedAttackChance
const IQ_ITEM_MASTER_MIN_WILD_LEVEL := 16   # gIqItemMasterMinWildLevel
const MAX_STAT_STAGE := 20
const DEFAULT_STAT_STAGE := 10
const MAX_SPEED_STAGE := 4
const MAX_STOCKPILE_STAGE := 3
const STAT_MULTIPLIER_THRESHOLD := 64       # F248 0.25 (STAT_MULTIPLIER_THRESHOLD)

# targeting flags (constants/move.h)
const T_OTHER := 0x00
const T_FRONTAL_CONE := 0x10
const T_AROUND := 0x20
const T_ROOM := 0x30
const T_2_TILES := 0x40
const T_LINE := 0x50
const T_FLOOR := 0x60
const T_SELF := 0x70
const T_CUT_CORNERS := 0x80
const TARGET_ENEMIES := 0
const TARGET_PARTY := 1
const TARGET_ALL := 2
const TARGET_USER := 3
const TARGET_ENEMIES_AFTER_CHARGING := 4
const TARGET_ALL_EXCEPT_USER := 5
const TARGET_TEAMMATES := 6
const AI_CONDITION_RANDOM := 0x100
const AI_CONDITION_HP_25 := 0x200
const AI_CONDITION_STATUS := 0x300
const AI_CONDITION_ASLEEP := 0x400
const AI_CONDITION_HP_25_OR_STATUS := 0x500
const AI_CONDITION_GHOST := 0x600

const TREAT_ALLY := 0
const TREAT_ENEMY := 1
const TREAT_IGNORE := 2

## gTacticsTargetLeader (dungeon_data.c): TRUE = the tactic makes allies stick to the leader instead of
## going after foes they can see.
const TACTICS_TARGET_LEADER := {
	"lets_go_together": true, "go_the_other_way": false, "go_after_foes": false, "avoid_the_first_hit": false,
	"all_for_one": true, "group_safety": true, "avoid_trouble": true, "be_patient": true,
	"keep_your_distance": true, "wait_there": false, "get_away": true, "unused": false,
}
## gReqTacticLvls (dungeon_data.c)
const TACTIC_LEVELS := {
	"lets_go_together": 1, "go_the_other_way": 25, "go_after_foes": 1, "avoid_the_first_hit": 1,
	"all_for_one": 999, "group_safety": 999, "avoid_trouble": 35, "be_patient": 40,
	"keep_your_distance": 20, "wait_there": 15, "get_away": 10, "unused": 999,
}

## Fallback AI targeting for moves that are not in Red's move table (later-generation moves in data/moves.json):
## derived from the move's player range "r". Red-native moves always use RED_AI_MOVES below.
const R_TO_AI_FLAGS := {
	"front": 0x00, "wall": 0x00, "front_corners": 0x80, "front_spread": 0x10, "adjacent": 0x20,
	"room": 0x30, "room_all": 0x35, "two_tiles": 0x40, "line": 0x50, "floor": 0x60, "floor_foes": 0x60,
	"floor_all": 0x65, "user": 0x73, "items": 0x73, "team_room": 0x31, "team_floor": 0x61, "special": 0xFF,
}

## Set by the dungeon around each AI.decide call: PartnerAI.decide (the "Partner AI: Smarter" option).
static var partner_hook: Callable

## Data source: set AI.db = <db.gd instance> in tests; otherwise the "DB" autoload is used.
static var db: Object = null

static func _db() -> Object:
	if db != null:
		return db
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		db = (ml as SceneTree).root.get_node_or_null("DB")
	return db

static func move_data(n: String) -> Dictionary:
	var d := _db()
	if d == null:
		return {}
	var mv = d.get("moves")
	if mv is Dictionary:
		return mv.get(n, {})
	return {}

static func species_data(sp: String) -> Dictionary:
	var d := _db()
	if d == null:
		return {}
	var s = d.get("species")
	if s is Dictionary:
		var e = s.get(sp, null)
		if e == null and sp.length() > 4:
			e = s.get(sp.substr(0, 4), null)
		return e if e is Dictionary else {}
	return {}

# ======================================================================== small utilities
static func _rand(fs: FloorState, n: int) -> int:       # DungeonRandInt
	if n <= 0:
		return 0
	return fs.rng.randi_range(0, n - 1)

static func _rand_outcome(fs: FloorState, pct: int) -> bool:   # DungeonRandOutcome
	return _rand(fs, 100) < pct

static func dir_toward(from: Vector2i, to: Vector2i) -> int:   # GetDirectionTowardsPosition (position_util.c)
	var d := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	if d == Vector2i.ZERO:
		return 0   # DIRECTION_SOUTH
	return DIRS.find(d)

static func cheb(a: Vector2i, b: Vector2i) -> int:          # GetDistance
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func _norm(s: String) -> String:
	return s.to_lower().replace("-", "").replace("_", "").replace(" ", "").replace("'", "")

static func st(m: Mon, k: String) -> int:
	return int(m.status.get(k, 0))

static func ability_is(m: Mon, a: String) -> bool:           # AbilityIsActive (no Gastro Acid in Red)
	var want := _norm(a)
	if _norm(m.ability) == want:
		return true
	var a2 = m.get("ability2")
	return a2 != null and _norm(String(a2)) == want

static func is_type(m: Mon, t: String) -> bool:              # MonsterIsType
	return t in m.types

static func holds(m: Mon, item: String) -> bool:             # HasHeldItem
	return _norm(m.held) == _norm(item)

## IqSkillIsEnabled. Wild Pokémon get Status Checker, PP Checker, Item Catcher, Self-Curer (bosses) and
## Item Master (Lv >= 16) -- LoadIQSkills (dungeon_logic.c). Team members use m.iq_skills.
static func iq(m: Mon, skill: String) -> bool:
	var want := _norm(skill)
	if not m.is_team():
		match want:
			"statuschecker", "ppchecker", "itemcatcher":
				return true
			"selfcurer":
				return bool(m.get_meta("boss", false))
			"itemmaster":
				return m.level >= IQ_ITEM_MASTER_MIN_WILD_LEVEL
		return false
	for s in m.iq_skills:
		if _norm(String(s)) == want:
			return true
	return false

static func tactic_of(m: Mon, memory: Dictionary = {}) -> String:
	if not m.is_team():
		return "go_after_foes"      # LoadIQSkills: wild Pokémon always TACTIC_GO_AFTER_FOES
	var t = memory.get("tactic", m.get_meta("tactic", "lets_go_together"))
	return String(t).to_lower().replace(" ", "_").replace("'", "")

## IsTacticSet: the leader only "has" Go the Other Way.
static func tactic_set(m: Mon, t: String, memory: Dictionary = {}) -> bool:
	if m.is_leader:
		return t == "go_the_other_way"
	return tactic_of(m, memory) == t

## TargetLeader (dungeon_ai_leader.c)
static func targets_leader(m: Mon, memory: Dictionary) -> bool:
	if not m.is_team():
		return false
	return bool(TACTICS_TARGET_LEADER.get(tactic_of(m, memory), false))

# ======================================================================== status predicates
static func is_sleeping(m: Mon) -> bool:                     # IsMonsterSleeping
	return st(m, "sleep") > 0 or st(m, "napping") > 0 or st(m, "nightmare") > 0

static func has_quarter_hp(m: Mon) -> bool:                  # MonsterHasQuarterHp
	return m.hp <= m.max_hp / 4

## MonsterHasNegativeStatus (dungeon_logic.c)
static func has_negative_status(m: Mon) -> bool:
	for k in ["sleep", "nightmare", "yawn", "burn", "poison", "badpoison", "para",
			"frozen", "wrapped", "wrapping", "petrified", "shadow_hold", "constriction",
			"confused", "cowering", "cringe", "infatuated", "paused", "taunt", "encore", "torment",
			"curse", "decoy", "leech_seed", "whiffer", "blinker", "cross_eyed", "muzzled", "perish", "slow"]:
		if st(m, k) > 0:
			return true
	if bool(m.get("exposed")):
		return true
	var sdc = m.get_meta("speed_down_counters", [])
	for c in sdc:
		if int(c) > 0:
			return true
	return false

## ShouldMonsterRunAway (dungeon_logic.c)
static func should_run_away(m: Mon, memory: Dictionary = {}) -> bool:
	if st(m, "terrified") > 0:
		return true
	if m.is_leader:
		return false
	if ability_is(m, "run away") and m.hp < m.max_hp / 2:
		return true
	if tactic_set(m, "get_away", memory) or (tactic_set(m, "avoid_trouble", memory) and m.hp <= m.max_hp / 2):
		return true
	return false

## CannotAttack(pokemon, skipSleep = FALSE)
static func cannot_attack(m: Mon, memory: Dictionary = {}) -> bool:
	if st(m, "sleep") > 0 or st(m, "nightmare") > 0 or st(m, "napping") > 0:
		return true
	for k in ["frozen", "wrapping", "wrapped", "petrified", "cringe", "paused", "infatuated", "para"]:
		if st(m, k) > 0:
			return true
	return should_run_away(m, memory)

## CheckVariousConditions (no item pick-up / held item use while any of these)
static func _various_conditions(m: Mon, memory: Dictionary) -> bool:
	if not m.is_leader and should_run_away(m, memory):
		return true
	if is_sleeping(m) or st(m, "paused") > 0 or st(m, "infatuated") > 0 or st(m, "petrified") > 0 or st(m, "terrified") > 0:
		return true
	if st(m, "yawn") > 0 or st(m, "frozen") > 0 or st(m, "bide") > 0:
		return true
	return String(m.status.get("charge_move", "")) != ""

static func can_see_invisible(m: Mon) -> bool:                # CanSeeInvisibleMonsters
	return st(m, "eyedrops") > 0 or holds(m, "goggle_specs") or holds(m, "Goggle Specs")

## CanSeeTarget (dungeon_util.c) -> IsPositionActuallyInSight
static func can_see_target(fs: FloorState, a: Mon, b: Mon) -> bool:
	if b == null or b.hp <= 0:
		return false
	if st(b, "invisible") > 0 and not can_see_invisible(a):
		return false
	if st(a, "blinker") > 0:
		return false
	return fs.red_actually_in_sight(a.pos, b.pos)

## CanTargetEntity (dungeon_util.c) -> IsPositionInSight
static func can_target_entity(fs: FloorState, a: Mon, b: Mon) -> bool:
	if b == null or b.hp <= 0:
		return false
	if st(b, "invisible") > 0 and not can_see_invisible(a):
		return false
	if st(a, "blinker") > 0:
		return false
	return fs.red_in_sight(a.pos, b.pos)

## GetTreatmentBetweenMonsters (dungeon_logic.c), decoys not modelled (TODO(red): Decoy/Substitute).
static func treatment(a: Mon, b: Mon, ignore_invisible := false, check_petrified := false) -> int:
	if a == b:
		return TREAT_ALLY
	if bool(a.get_meta("shopkeeper", false)) or bool(b.get_meta("shopkeeper", false)):
		return TREAT_IGNORE
	if a.side == "client" or b.side == "client":   # rescue-job clients are neutral
		return TREAT_IGNORE
	if check_petrified and a.is_team() and st(b, "petrified") > 0:
		return TREAT_IGNORE
	if not ignore_invisible and st(b, "invisible") > 0 and not can_see_invisible(a):
		return TREAT_IGNORE
	return TREAT_ENEMY if a.side != b.side else TREAT_ALLY

## GetCanMoveFlag (species "move")
static func species_can_move(m: Mon) -> bool:
	return bool(species_data(m.sp).get("move", true))

# ======================================================================== entry point
## RunMonsterAI (dungeon_ai.c) for one non-leader Pokémon. See the header for formats.
static func decide(m: Mon, fs: FloorState, memory: Dictionary) -> Dictionary:
	if m == null or fs == null or m.hp <= 0 or m.is_leader:
		return {"type": "wait"}
	_init_memory(m, memory)
	var pre := _status_prevents_acting(m, fs, memory)
	if not pre.is_empty():
		return pre
	if bool(m.get_meta("rescue_target", false)):          # BEHAVIOR_RESCUE_TARGET: random shuffle
		return _walk_or_face(m, fs, _rand(fs, 8))
	# AIDecideUseItem runs before moves (RunMonsterAI). Ported: throwing a held throwing item.
	# TODO(red): eating held berries / using orbs (dungeon_ai_item_weight.c) is not ported yet.
	var it := decide_throw_item(m, fs)
	if not it.is_empty():
		return it
	# Remake option: the smarter "Let's go together!" (dungeon/partner_ai.gd); {} = Red's AI as below.
	if partner_hook.is_valid():
		var sm: Dictionary = partner_hook.call(m, memory)
		if not sm.is_empty():
			return sm
	if not iq(m, "dedicated traveler"):
		var a := choose_ai_move(m, fs, memory)
		if not a.is_empty():
			return _finalize_attack(m, fs, a)
		if st(m, "confused") > 0:
			return _confused_walk(m, fs)
		if not species_can_move(m):
			return {"type": "wait"}
		return ai_movement(m, fs, memory, true)
	# IQ_DEDICATED_TRAVELER: movement first, attack only when it has nowhere to go.
	if st(m, "confused") > 0:
		return _confused_walk(m, fs)
	var mv := {"type": "wait"}
	if species_can_move(m):
		mv = ai_movement(m, fs, memory, true)
	if mv.type == "move" or mv.type == "item":
		return mv
	var b := choose_ai_move(m, fs, memory)
	if b.is_empty():
		return mv
	memory.not_next_to_target = false
	memory.ally_skip = false
	memory.waiting = false
	return _finalize_attack(m, fs, b)

# ======================================================================== items
## Thrown items GetAIUseItemProbability gives 70 against a foe (dungeon_ai_item_weight.c).
const AI_THROWN_ITEMS := ["stick", "ironthorn", "silverspike", "goldfang", "cacneaspike", "corsolatwig", "gravelerock", "geopebble"]
const AI_THROWN_WEIGHT := 70
const ARC_RANGE := 10

## AIDecideUseItem (dungeon_ai_items.c), the IQ_ITEM_MASTER branch for a held throwing item: a straight
## thrower (Iron Thorn...) picks a foe it can see in one of the 8 lines within 10 tiles and throws with
## a 70% roll per direction; an arc thrower (Gravelerock, Geo Pebble) picks any visible foe within 10 tiles
## (70% roll each) and lobs it over everything. Only the leader may use the Toolbox, so allies throw what
## they hold. Returns {type: "throw", dir, held: true[, target]} or {}.
static func decide_throw_item(m: Mon, fs: FloorState) -> Dictionary:
	if m.held == "" or not iq(m, "item master"):
		return {}
	if _various_conditions(m, {}):
		return {}
	var id := _norm(m.held)
	if not id in AI_THROWN_ITEMS:
		return {}
	var cat := str(_db().items.get(m.held, {}).get("red_cat", ""))
	if cat == "thrown_arc":
		var targets: Array = []
		for t in fs.mons:
			if t == m or t.hp <= 0 or not can_see_target(fs, m, t) or treatment(m, t, false, true) != TREAT_ENEMY:
				continue
			if cheb(m.pos, t.pos) <= ARC_RANGE and _rand_outcome(fs, AI_THROWN_WEIGHT):
				targets.append(t.pos)
		if targets.is_empty():
			return {}
		var tp: Vector2i = targets[_rand(fs, targets.size())]
		return {"type": "throw", "dir": dir_toward(m.pos, tp), "held": true, "target": tp}
	# GetPossibleAIThrownItemDirections + TargetThrownItem
	var dirs: Array = []
	var used := {}
	for t in fs.mons:
		if t == m or t.hp <= 0 or treatment(m, t, false, true) != TREAT_ENEMY or not can_see_target(fs, m, t):
			continue
		var dx := absi(m.pos.x - t.pos.x)
		var dy := absi(m.pos.y - t.pos.y)
		if st(m, "long_toss") <= 0 and maxi(dx, dy) > RANGED_ATTACK_RANGE:
			continue
		if not (dx == dy or dx == 0 or dy == 0):
			continue
		var d := dir_toward(m.pos, t.pos)
		if used.has(d) or not _in_range(fs, m, t, d, RANGED_ATTACK_RANGE):
			continue
		used[d] = true
		dirs.append(d)
	for d in dirs:
		if _rand_outcome(fs, AI_THROWN_WEIGHT):
			return {"type": "throw", "dir": d, "held": true}
	return {}

static func _init_memory(m: Mon, mem: Dictionary) -> void:
	if not mem.has("objective"):
		mem.objective = ""
		mem.target_pos = m.pos
		mem.target_uid = -1
	if not mem.has("move_randomly"):
		mem.move_randomly = bool(m.get_meta("move_randomly", false))
	for k in ["targeting_enemy", "turning_around", "not_next_to_target", "ally_skip", "waiting", "recalculate_follow"]:
		if not mem.has(k):
			mem[k] = false

## AI.on_moved: keep Red's EntityInfo.prevPos[4] (sub_80694C0 in dungeon_misc.c). Call after a Pokémon's
## position changes; warped = true for teleports/warps/new floor (all four set to the new position).
static func on_moved(m: Mon, old_pos: Vector2i, warped := false) -> void:
	var prev: Array = m.get_meta("prev_pos", [])
	if warped or prev.size() != NUM_PREV_POS:
		m.set_meta("prev_pos", [m.pos, m.pos, m.pos, m.pos])
		if warped:
			return
		prev = m.get_meta("prev_pos")
	var np := [prev[0], prev[0], prev[1], prev[2]]
	if st(m, "invisible") == 0:
		np[0] = old_pos
	m.set_meta("prev_pos", np)

static func _prev_positions(t: Mon) -> Array:
	var prev: Array = t.get_meta("prev_pos", [])
	if prev.size() != NUM_PREV_POS:
		return [t.pos, t.pos, t.pos, t.pos]   # Red initialises prevPos to the spawn position
	return prev

static func _mon_by_uid(fs: FloorState, uid: int) -> Mon:
	if uid < 0:
		return null
	for o in fs.mons:
		if o.uid == uid and o.hp > 0:
			return o
	return null

## HasStatusThatPreventsActing (status_checks.c). Returns {} when the Pokémon may act normally.
static func _status_prevents_acting(m: Mon, fs: FloorState, mem: Dictionary) -> Dictionary:
	if st(m, "sleep") > 0 or st(m, "nightmare") > 0 or st(m, "napping") > 0:
		return {"type": "wait"}
	for k in ["frozen", "wrapping", "wrapped", "petrified", "paused", "infatuated", "bide"]:
		if st(m, k) > 0:
			return {"type": "wait"}
	if st(m, "decoy") > 0:
		return _walk_or_face(m, fs, _rand(fs, 8))
	if bool(m.get_meta("shopkeeper", false)):
		return {"type": "wait"}
	if st(m, "blinker") > 0:
		if _can_move_in_direction(fs, m, m.facing):
			return {"type": "move", "dir": m.facing}
		if _rand(fs, 2) != 0:
			return _walk_or_face(m, fs, _rand(fs, 8))
		var a := choose_ai_move(m, fs, mem)
		return _finalize_attack(m, fs, a) if not a.is_empty() else {"type": "wait"}
	if st(m, "cross_eyed") > 0:
		return _walk_or_face(m, fs, _rand(fs, 8))
	return {}

## SetActionPassTurnOrWalk with a fixed direction: walks if possible, otherwise just turns.
static func _walk_or_face(m: Mon, fs: FloorState, d: int) -> Dictionary:
	if species_can_move(m) and _can_move_in_direction(fs, m, d):
		return {"type": "move", "dir": d}
	return {"type": "wait", "dir": d}

## Confused Pokémon that did not attack walk; sub_8075BA4 then randomises the direction.
static func _confused_walk(m: Mon, fs: FloorState) -> Dictionary:
	if not species_can_move(m):
		return {"type": "wait"}
	return _walk_or_face(m, fs, _rand(fs, 8))

## sub_8075BA4 (dungeon_ai.c) applied to attacks: Cowering turns the attack around, Confusion randomises it.
static func _finalize_attack(m: Mon, fs: FloorState, a: Dictionary) -> Dictionary:
	if a.get("type", "") != "attack":
		return a
	if st(m, "cowering") > 0:
		a.dir = (int(a.dir) + 4) & 7
	elif st(m, "confused") > 0:
		a.dir = _rand(fs, 8)
	return a

## CanMoveInDirection (dungeon_logic.c): terrain + corner rule + nobody standing there.
static func _can_move_in_direction(fs: FloorState, m: Mon, d: int) -> bool:
	if st(m, "shadow_hold") > 0:          # immobilized (Arena Trap, Shadow Tag, Magnet Pull, Grimy Food)
		return false
	var to: Vector2i = m.pos + DIRS[d]
	if not fs.inb(to) or fs.mon_at(to) != null:
		return false
	return fs.can_step(m.pos, d, m)

## CanAIMonsterMoveInDirection (dungeon_logic.c). Returns [can_move, pokemon_in_front].
static func can_ai_move(fs: FloorState, m: Mon, d: int) -> Array:
	d &= 7
	var to: Vector2i = m.pos + DIRS[d]
	if not fs.inb(to):
		return [false, false]
	var fl := 0
	if fs.flags.size() == fs.w * fs.h:
		fl = fs.flags[fs.idx(to)]
	if fl & 1:                                   # TERRAIN_TYPE_IMPASSABLE_WALL
		return [false, false]
	if (fl & 8) and not bool(fs.get_meta("monster_house_triggered", false)) and iq(m, "house avoider"):
		return [false, false]
	if fs.traps.has(to) and iq(m, "trap avoider"):
		var tr: Dictionary = fs.traps[to]
		if bool(tr.get("seen", false)) or st(m, "eyedrops") > 0:
			return [false, false]
	if fs.terrain_at(to) == 2 and fs.secondary == "lava" and iq(m, "lava evader"):
		return [false, false]
	if not fs.can_step(m.pos, d, m):
		return [false, false]
	if fs.mon_at(to) != null:
		return [false, true]
	return [true, false]

## IsAtJunction (dungeon_logic.c): T- or +-shaped cardinal openings with no diagonal exits.
static func is_at_junction(fs: FloorState, m: Mon) -> bool:
	var mask := fs.red_walk_mask(m.pos, m)
	return mask == 0x54 or mask == 0x51 or mask == 0x45 or mask == 0x15 or mask == 0x55

# ======================================================================== movement (dungeon_ai_movement.c)
## AIMovement
static func ai_movement(m: Mon, fs: FloorState, mem: Dictionary, show_run_away := true) -> Dictionary:
	mem.not_next_to_target = false
	mem.targeting_enemy = false
	mem.turning_around = false
	if tactic_set(m, "be_patient", mem) and m.hp <= m.max_hp / 2:
		return {"type": "wait"}
	if tactic_set(m, "wait_there", mem):
		return {"type": "wait"}
	if not m.is_leader and m.has_meta("belly") and int(m.get_meta("belly")) <= 0:
		return {"type": "wait"}
	var has_action := false
	if should_run_away(m, mem):
		has_action = _avoid_enemies(m, fs, mem)
	elif _can_take_item(m, fs, mem):
		return {"type": "item", "action": "pickup"}
	else:
		has_action = _choose_target_position(m, fs, mem)
	if not has_action:
		return {"type": "wait"}
	return _decide_movement(m, fs, mem)

## CanTakeItem
static func _can_take_item(m: Mon, fs: FloorState, mem: Dictionary) -> bool:
	if _various_conditions(m, mem):
		return false
	if not fs.items.has(m.pos) or m.is_leader or m.held != "":
		return false
	var it: Dictionary = fs.items[m.pos]
	if int(it.get("price", 0)) > 0:          # ITEM_FLAG_IN_SHOP
		return false
	if str(it.get("id", "")) == "poke" and not m.is_team():   # wild Pokémon can't take Poké: walk on instead of
		return false                                           # trying (and failing) to pick it up every turn
	if fs.is_wall(m.pos) and not m.is_team():
		return false
	return true

static func _target_pool(m: Mon, fs: FloorState) -> Array:
	# gDungeon->teamPokemon for wild Pokémon, gDungeon->wildPokemon for the team (decoys: TODO(red)).
	var out: Array = []
	for o in fs.mons:
		if o.hp > 0 and o != m and o.side != m.side and o.side != "client" and m.side != "client":
			out.append(o)
	return out

static func _leader_if_visible(m: Mon, fs: FloorState) -> Mon:      # GetLeaderIfVisible
	if not m.is_team():
		return null
	var L := fs.leader
	if L == null or L.hp <= 0 or L == m or st(L, "decoy") > 0:
		return null
	if treatment(m, L) != TREAT_ALLY:
		return null
	return L if can_target_entity(fs, m, L) else null

static func _can_see_teammate(m: Mon, fs: FloorState) -> bool:     # CanSeeTeammate
	if not m.is_team():
		return false
	for o in fs.mons:
		if o != m and o.hp > 0 and o.is_team() and can_see_target(fs, m, o):
			return true
	return false

## ChooseTargetPosition
static func _choose_target_position(m: Mon, fs: FloorState, mem: Dictionary) -> bool:
	if not targets_leader(m, mem):
		var best: Mon = null
		var best_d := INFINITY
		for t in _target_pool(m, fs):
			if m.is_team() and st(t, "petrified") > 0:
				continue
			if bool(t.get_meta("shopkeeper", false)):
				continue
			# TODO(red): CanCrossWalls (Ghost/Mobile) uses CHECK_VISIBILITY_DISTANCE instead of sight.
			if not can_target_entity(fs, m, t):
				continue
			var d := cheb(m.pos, t.pos)
			if best_d > d:
				best_d = d
				best = t
				if best_d < 2:
					break
		if best != null:
			mem.objective = "chase"
			mem.target_pos = best.pos
			mem.target_uid = best.uid
			mem.targeting_enemy = true
			mem.move_randomly = false
			if tactic_set(m, "keep_your_distance", mem) and not _can_see_teammate(m, fs):
				if cheb(m.pos, best.pos) <= 1:
					mem.turning_around = true
			return true
	if not tactic_set(m, "go_the_other_way", mem):
		if m.is_team():
			var L := _leader_if_visible(m, fs)
			if L != null:
				mem.objective = "chase"
				mem.target_pos = L.pos
				mem.target_uid = L.uid
				mem.move_randomly = false
				return true
	# (Red's leader item-targeting branch is unreachable: the leader is never AI-controlled.)
	if mem.objective == "chase" or mem.objective == "chase_remembered":
		if int(mem.target_uid) >= 0:
			var t := _mon_by_uid(fs, int(mem.target_uid))
			if t != null:
				for p in _prev_positions(t):
					if fs.red_in_sight(m.pos, p):     # CanTargetPosition
						mem.objective = "chase_remembered"
						mem.target_pos = p
						mem.move_randomly = false
						return true
			else:
				mem.objective = "stand_still"
				mem.target_uid = -1
	_wander(m, fs, mem)
	return true

## Wander
static func _wander(m: Mon, fs: FloorState, mem: Dictionary) -> bool:
	var room := fs.room_at(m.pos)
	if room == 255:
		var facing := m.facing
		var opposite := (facing + 4) & 7
		var at_junction := false
		if is_at_junction(fs, m):
			facing = _rand(fs, 8)
			at_junction = true
		for i in 8:
			var d: int = (facing + FACE_INC[i]) & 7
			if at_junction and d == opposite:
				continue
			if not can_ai_move(fs, m, d)[0]:
				continue
			mem.objective = "roam"
			mem.target_pos = m.pos + DIRS[d]
			return true
	else:
		var exits := fs.red_room_exits(room)
		if bool(mem.move_randomly):
			var rd := _rand(fs, 8)
			mem.objective = "stand_still"
			mem.target_pos = m.pos + DIRS[rd]
			return true
		if mem.objective != "leave_room":
			if exits.is_empty():
				var rd2 := _rand(fs, 8)
				mem.objective = "stand_still"
				mem.target_pos = m.pos + DIRS[rd2]
				return true
			for i in 10:
				var k := _rand(fs, exits.size())
				if exits[k] != m.pos:
					mem.objective = "leave_room"
					mem.target_pos = exits[k]
					return true
			# picked the exit it stands on 10 times: leaves the way it came (falls through)
		if fs.red_is_junction(m.pos):
			var d2 := _rand(fs, 8)
			for i in 8:
				d2 &= 7
				var fwd: Vector2i = m.pos + DIRS[d2]
				if fs.room_at(fwd) == 255 and can_ai_move(fs, m, d2)[0]:
					mem.objective = "roam"
					mem.target_pos = fwd
					return true
				d2 += 1
		return true
	var rd3 := _rand(fs, 8)
	mem.objective = "stand_still"
	mem.target_pos = m.pos + DIRS[rd3]
	return true

## AvoidEnemies
static func _avoid_enemies(m: Mon, fs: FloorState, mem: Dictionary) -> bool:
	var room := fs.room_at(m.pos)
	var closest: Mon = null
	var closest_d := INFINITY_2
	var closest_room := 255
	for t in _target_pool(m, fs):
		if not can_see_target(fs, m, t):
			continue
		var d := cheb(m.pos, t.pos)
		if closest_d > d:
			closest_d = d
			closest = t
			closest_room = fs.room_at(t.pos)
			mem.target_pos = t.pos
	if closest == null:
		return _wander(m, fs, mem)
	if room == closest_room and room != 255:
		if fs.red_is_junction(m.pos):
			var found := -1
			for d in 8:
				var adj: Vector2i = m.pos + DIRS[d]
				if fs.room_at(adj) != room and can_ai_move(fs, m, d)[0]:
					found = d
					break
			if found < 0:
				var rd := _rand(fs, 8)
				mem.objective = "stand_still"
				mem.target_pos = m.pos + DIRS[rd]
				return true
			mem.objective = "run_away"
			mem.target_pos = m.pos + DIRS[found]
			return true
		var exits := fs.red_room_exits(room)
		var best_i := 0
		var best_dist := -INFINITY_2
		var me_to_foe := cheb(closest.pos, m.pos)
		for i in exits.size():
			var e: Vector2i = exits[i]
			var foe_to_exit := cheb(closest.pos, e)
			var step := Vector2i(clampi(e.x - m.pos.x, -1, 1), clampi(e.y - m.pos.y, -1, 1))
			var adj_to_foe := cheb(closest.pos, m.pos + step)
			# BUG (kept): >= lets it step toward an exit while staying at the same distance.
			if adj_to_foe >= me_to_foe and best_dist < foe_to_exit:
				best_i = i
				best_dist = foe_to_exit
		if best_dist >= 0:
			mem.objective = "run_away"
			mem.target_pos = exits[best_i]
			return true
	mem.objective = "run_away"
	mem.target_pos = m.pos - (closest.pos - m.pos)
	return true

## ShouldAvoidFirstHit
static func _should_avoid_first_hit(m: Mon, mem: Dictionary, force: bool) -> bool:
	return tactic_set(m, "avoid_the_first_hit", mem) and force

## DecideMovement
static func _decide_movement(m: Mon, fs: FloorState, mem: Dictionary) -> Dictionary:
	var tp: Vector2i = mem.target_pos
	if m.pos == tp:
		return {"type": "wait"}
	var dir := dir_toward(m.pos, tp)
	if _should_avoid_first_hit(m, mem, bool(mem.targeting_enemy)):
		if mem.objective == "chase" and fs.red_within_two_tiles(m.pos, tp):
			var dist := cheb(m.pos, tp)
			if dist == 2:
				return {"type": "wait"}
			elif dist < 2:
				dir = (dir + 4) & 7
	elif bool(mem.turning_around):
		dir = (dir + 4) & 7
	var r := can_ai_move(fs, m, dir)
	if r[0]:
		return {"type": "move", "dir": dir}
	elif r[1]:
		if m.is_team() and not bool(mem.recalculate_follow):
			mem.not_next_to_target = true
			mem.ally_skip = true
			mem.waiting = true
			return {"type": "wait", "ally_skip": true}
		if m.pos + DIRS[dir] == tp:
			mem.waiting = true
			return {"type": "wait"}
		mem.not_next_to_target = true
	var try_turn := [true, true, true, true, true, true]
	if m.is_team() and (dir & 1) != 0:
		var dx := absi(m.pos.x - tp.x)
		var dy := absi(m.pos.y - tp.y)
		if dx <= 2 and dy <= 2 and dx != dy:
			if (dir & 2) != 0:
				if dx < dy:
					try_turn[TURN_RIGHT_45] = false
				else:
					try_turn[TURN_LEFT_45] = false
			else:
				if dx < dy:
					try_turn[TURN_LEFT_45] = false
				else:
					try_turn[TURN_RIGHT_45] = false
	var limit := TURN_LEFT_90
	if should_run_away(m, mem) or bool(mem.turning_around):
		limit = TURN_LEFT_135
	var dirs := [0, 0, 0, 0, 0, 0]
	var res := [[], [], [], [], [], []]
	for i in range(TURN_LEFT_45, limit):
		dirs[i] = (FACE_INC[i] + dir) & 7
		res[i] = can_ai_move(fs, m, dirs[i])
		if not res[i][0] and not res[i][1]:
			try_turn[TURN_LEFT_45] = true
			try_turn[TURN_RIGHT_45] = true
	for i in range(TURN_LEFT_45, limit):
		if res[i][0] and try_turn[i]:
			return {"type": "move", "dir": dirs[i]}
		if res[i][1]:
			mem.not_next_to_target = true
	mem.waiting = true
	if bool(mem.not_next_to_target):
		mem.ally_skip = true
		if m.is_team():
			return {"type": "wait", "ally_skip": true}
	return {"type": "wait"}

# ======================================================================== attacks (dungeon_ai_attack.c)
static func _move_exists(mv) -> bool:
	return mv is Dictionary and String(mv.get("name", "")) != ""

static func _move_linked(mv) -> bool:            # MOVE_FLAG_SUBSEQUENT_IN_LINK_CHAIN
	return _move_exists(mv) and bool(mv.get("linked", false))

static func _move_on(mv) -> bool:                # MOVE_FLAG_ENABLED_FOR_AI
	return bool(mv.get("on", true))

## GetMoveTargetAndRange(move, isAI = TRUE)
static func ai_flags(name: String) -> int:
	if RED_AI_MOVES.has(name):
		return int(RED_AI_MOVES[name][0])
	var md := move_data(name)
	return int(R_TO_AI_FLAGS.get(String(md.get("r", "front")), 0))

## GetMoveAccuracyOrAiChance(move, ACCURACY_AI_CONDITION_RANDOM_CHANCE)
static func ai_chance(name: String) -> int:
	if RED_AI_MOVES.has(name):
		return int(RED_AI_MOVES[name][1])
	return 100

## MoveIgnoresTaunted
static func ignores_taunt(name: String) -> bool:
	if RED_AI_MOVES.has(name):
		return int(RED_AI_MOVES[name][2]) != 0
	return int(move_data(name).get("p", 0)) > 0

static func ai_weight(name: String) -> int:     # GetMoveAIWeight
	return int(move_data(name).get("ai", 0))

## CanMonsterUseMove (dungeon_move_util.c)
static func _can_monster_use_move(m: Mon, mv: Dictionary, pp_checker: bool) -> bool:
	if String(mv.name) == "attack" or String(mv.name) == "Regular Attack":
		return true
	if bool(mv.get("disabled", false)) or bool(mv.get("sealed", false)):
		return false
	if pp_checker:
		if int(mv.get("pp", 0)) == 0:
			return false
		if st(m, "taunt") > 0 and not ignores_taunt(String(mv.name)):
			return false
		if st(m, "encore") > 0 and String(mv.name) != m.last_move:
			return false
	return true

## CanAIUseMove (dungeon_move_util.c)
static func _can_ai_use_move(m: Mon, i: int, pp_checker: bool) -> bool:
	var mv = m.moves[i]
	if not _move_exists(mv):
		return false
	if _move_linked(mv) or bool(mv.get("disabled", false)) or bool(mv.get("sealed", false)):
		return false
	var j := i
	while j < m.moves.size():
		if _can_monster_use_move(m, m.moves[j], pp_checker):
			return true
		j += 1
		if j >= m.moves.size() or not _move_linked(m.moves[j]):
			break
	return false

static func _chain_from(m: Mon, i: int) -> Array:
	var out: Array = [String(m.moves[i].name)]
	var j := i + 1
	while j < m.moves.size() and _move_linked(m.moves[j]):
		out.append(String(m.moves[j].name))
		j += 1
	return out

## ChooseAIMove. Returns {} when the AI decides not to attack (then it moves).
static func choose_ai_move(m: Mon, fs: FloorState, mem: Dictionary) -> Dictionary:
	if cannot_attack(m, mem) or should_run_away(m, mem) or tactic_set(m, "keep_your_distance", mem):
		return {}
	if st(m, "confused") > 0 and _rand_outcome(fs, AI_CONFUSED_ATTACK_CHANCE):
		return {}
	# Two-turn move in progress (bideClassStatus + moveSlot): keep using it, facing forward.
	var cm := String(m.status.get("charge_move", ""))
	if cm != "":
		for i in m.moves.size():
			if _move_exists(m.moves[i]) and String(m.moves[i].name) == cm:
				var k := i
				while k > 0 and _move_linked(m.moves[k]):
					k -= 1
				return {"type": "attack", "move": String(m.moves[k].name), "dir": m.facing, "chain": _chain_from(m, k)}
	var n := mini(m.moves.size(), 4)
	var total := 0
	var usable := 0
	for i in n:
		var mv = m.moves[i]
		if _move_exists(mv):
			if _move_on(mv):
				usable += 1
			total += int(mv.get("pp", 0))
	if total == 0:
		var sr := consider_move(m, fs, "Struggle")
		if sr.ok:
			return {"type": "attack", "move": "Struggle", "dir": int(sr.dir) & 7}
		return {}
	var weak := iq(m, "weak-type picker") or iq(m, "weak type picker")
	var pp_checker := iq(m, "pp checker")
	var keep := [true, true, true, true]
	if pp_checker:
		# Linked chains would unlink when any member hits 0 PP: avoid chains with a member at <= 1 PP.
		var min_pp := 99
		var start := 0
		var i := 0
		while i < n:
			var mv = m.moves[i]
			if not _move_exists(mv):
				break
			if i != 0 and not _move_linked(mv):
				if start + 1 < i and min_pp <= 1:
					for j in range(start, i):
						keep[j] = false
				min_pp = int(mv.get("pp", 0))
				start = i
			else:
				min_pp = mini(min_pp, int(mv.get("pp", 0)))
			i += 1
		if start + 1 < i and min_pp <= 1:
			for j in range(start, i):
				keep[j] = false
	var ok := [false, false, false, false, false]
	var w := [0, 0, 0, 0, 0]
	total = 0
	for i in n:
		var mv = m.moves[i]
		if _move_exists(mv) and keep[i] and _can_ai_use_move(m, i, pp_checker) and _move_on(mv):
			ok[i] = true
			# TODO(red): STATUS_CHARGING (move Charge) weights: Electric moves keep aiWeight, others 1.
			if weak:
				w[i] = int(consider_move(m, fs, String(mv.name)).weight)
			else:
				w[i] = ai_weight(String(mv.name))
			total += w[i]
	if not iq(m, "exclusive move-user") and not iq(m, "exclusive move user"):
		ok[REGULAR_ATTACK_INDEX] = true
		w[REGULAR_ATTACK_INDEX] = 2 if weak else int(AI_REGULAR_ATTACK_WEIGHTS[mini(usable, 4)])
		total += w[REGULAR_ATTACK_INDEX]
	if weak:
		var mx := 0
		for i in 5:
			if not ok[i]:
				w[i] = 0
			elif mx < w[i]:
				mx = w[i]
		total = 0
		for i in 5:
			if ok[i]:
				if w[i] != mx:
					w[i] = 0
				total += w[i]
	if total == 0:
		return {}
	var roll := _rand(fs, total)
	var counter := 0
	var reg := [false, 0]
	if ok[REGULAR_ATTACK_INDEX]:
		reg = target_regular_attack(m, fs, true)
	for i in 5:
		if ok[i] and w[i] != 0:
			counter += w[i]
			if counter >= roll:   # sic: >=, as in Red
				if i == REGULAR_ATTACK_INDEX:
					if reg[0]:
						return {"type": "attack", "move": "", "dir": int(reg[1]) & 7}
					return {}
				var r := consider_move(m, fs, String(m.moves[i].name))
				if r.ok:
					return {"type": "attack", "move": String(m.moves[i].name), "dir": int(r.dir) & 7, "chain": _chain_from(m, i)}
				break
	if reg[0]:
		return {"type": "attack", "move": "", "dir": int(reg[1]) & 7}
	return {}

## AIConsiderMove. Returns {ok: bool, dir: int, weight: int}.
static func consider_move(m: Mon, fs: FloorState, name: String) -> Dictionary:
	var flags := ai_flags(name)
	var sc := iq(m, "status checker")
	var out := {"ok": false, "dir": m.facing, "weight": 1}
	if (st(m, "taunt") > 0 and not ignores_taunt(name)) or (sc and not can_use_on_self_sc(m, fs, name)):
		return out
	var rf := flags & 0xF0
	var used := {}
	var cands: Array = []     # [dir, weight]
	if rf == T_OTHER or rf == T_FRONTAL_CONE or rf == T_AROUND:
		if st(m, "blinker") > 0:
			cands.append([m.facing, 99])
		else:
			for d in 8:
				var t := fs.mon_at(m.pos + DIRS[d])
				if t == null:
					continue
				if rf != T_FRONTAL_CONE and rf != T_AROUND and not fs.can_attack_dir(m.pos, d):
					continue
				_try_add(cands, used, flags, m, fs, t, name, sc)
	elif rf == T_ROOM:
		for t in fs.mons:
			if t.hp > 0 and (t == m or can_see_target(fs, m, t)):
				_try_add(cands, used, flags, m, fs, t, name, sc)
	elif rf == T_2_TILES:
		for d in 8:
			if not fs.can_attack_dir(m.pos, d):
				continue
			var t1 := fs.mon_at(m.pos + DIRS[d])
			if t1 != null:
				var before := cands.size()
				_try_add(cands, used, flags, m, fs, t1, name, sc)
				if cands.size() != before:
					continue
			var t2 := fs.mon_at(m.pos + DIRS[d] * 2)
			if t2 != null:
				_try_add(cands, used, flags, m, fs, t2, name, sc)
	elif rf == T_LINE or rf == T_CUT_CORNERS:
		var max_range := 10 if rf == T_LINE else 1
		for t in fs.mons:
			if t.hp <= 0 or t == m:
				continue
			var d := dir_toward(m.pos, t.pos)
			if not used.has(d) and can_see_target(fs, m, t) and _in_line_range(m, t, max_range) \
					and _eligible(flags, m, t, name, sc, fs) and _in_range(fs, m, t, d, max_range):
				used[d] = true
				cands.append([d, _weight_move(m, flags, t)])
	elif rf == T_FLOOR:
		for t in fs.mons:
			if t.hp > 0:
				_try_add(cands, used, flags, m, fs, t, name, sc)
	elif rf == T_SELF:
		_try_add(cands, used, flags, m, fs, m, name, sc)
	if cands.is_empty():
		return out
	var mx := 0
	for c in cands:
		mx = maxi(mx, int(c[1]))
	var tot := 0
	for c in cands:
		if int(c[1]) != mx:
			c[1] = 0
		tot += int(c[1])
	var roll := _rand(fs, tot)
	var pick := 0
	for i in cands.size():
		roll -= int(cands[i][1])
		pick = i
		if roll < 0:
			break
	out.ok = true
	out.dir = int(cands[pick][0])
	out.weight = mx
	return out

## TryAddTargetToAITargetList
static func _try_add(cands: Array, used: Dictionary, flags: int, m: Mon, fs: FloorState, t: Mon, name: String, sc: bool) -> void:
	var rf := flags & 0xF0
	var d: int
	if t.pos == m.pos or rf == T_ROOM or rf == T_FLOOR or rf == T_SELF:
		d = m.facing
	else:
		d = dir_toward(m.pos, t.pos)
	if not used.has(d) and _eligible(flags, m, t, name, sc, fs):
		used[d] = true
		cands.append([d, _weight_move(m, flags, t)])

## IsTargetInLineRange: straight or diagonal line, within RANGED_ATTACK_RANGE and the move's range.
static func _in_line_range(m: Mon, t: Mon, rng: int) -> bool:
	var dx := absi(m.pos.x - t.pos.x)
	var dy := absi(m.pos.y - t.pos.y)
	var dist := maxi(dx, dy)
	if dist > RANGED_ATTACK_RANGE or dist > rng:
		return false
	return dx == dy or dx == 0 or dy == 0

## IsTargetInRange. BUG (kept): without Course Checker it is always TRUE.
static func _in_range(fs: FloorState, m: Mon, t: Mon, d: int, n: int) -> bool:
	if not iq(m, "course checker"):
		return true
	var eff := mini(cheb(m.pos, t.pos), n)
	var p := m.pos
	for i in eff + 1:
		p += DIRS[d]
		if p.x < 1 or p.y < 1 or p.x >= fs.w - 1 or p.y >= fs.h - 1:
			break
		if fs.is_wall(p):
			return false
		var o := fs.mon_at(p)
		if o == t:
			return true
		if o != null:
			return false
	return false

## IsAITargetEligible
static func _eligible(flags: int, m: Mon, t: Mon, name: String, check_all: bool, fs: FloorState) -> bool:
	var tg := flags & 0xF
	var has := false
	match tg:
		TARGET_ENEMIES:
			has = treatment(m, t, false, true) == TREAT_ENEMY
		TARGET_PARTY:
			has = treatment(m, t, false, true) == TREAT_ALLY
		TARGET_ALL:
			if bool(t.get_meta("shopkeeper", false)) or bool(t.get_meta("rescue_target", false)):
				return false
			has = true
		TARGET_ALL_EXCEPT_USER:
			if m == t or bool(t.get_meta("shopkeeper", false)) or bool(t.get_meta("rescue_target", false)):
				return false
			has = true
		TARGET_TEAMMATES:
			if m == t:
				return false
			has = treatment(m, t, false, true) == TREAT_ALLY
		TARGET_USER, TARGET_ENEMIES_AFTER_CHARGING:
			has = true
	if not has:
		return false
	var cond := flags & 0xF00
	if check_all:
		if not can_use_on_target_sc(m, t, name):
			return false
		match cond:
			AI_CONDITION_RANDOM:
				if _rand(fs, 100) >= ai_chance(name):
					return false
			AI_CONDITION_HP_25:
				if not has_quarter_hp(t):
					return false
			AI_CONDITION_STATUS:
				if not has_negative_status(t):
					return false
			AI_CONDITION_ASLEEP:
				if not is_sleeping(t):
					return false
			AI_CONDITION_GHOST:
				if not is_type(t, "Ghost") or bool(t.get("exposed")):
					return false
			AI_CONDITION_HP_25_OR_STATUS:
				if not has_negative_status(t) and not has_quarter_hp(t):
					return false
	elif cond == AI_CONDITION_RANDOM:
		if _rand(fs, 100) >= ai_chance(name):
			return false
	return true

## WeightMove
static func _weight_move(m: Mon, flags: int, t: Mon) -> int:
	if t.is_team():
		return 1
	if (flags & 0xF) != TARGET_ENEMIES:
		return 1
	if iq(m, "exp. go-getter") or iq(m, "exp go-getter"):
		return 1   # TODO(red): gDungeon->expYieldRankings[target species] (and its inverted-priority bug)
	if iq(m, "efficiency expert"):
		var w := (500 - t.hp) & 0xFF   # u8 weight, as in Red
		return 1 if w == 0 else w
	if iq(m, "weak-type picker") or iq(m, "weak type picker"):
		return 2   # TODO(red): WeightWeakTypePicker(user, target, moveType) + 1 needs the type chart
	return 1

## TargetRegularAttack. Returns [ok, dir].
static func target_regular_attack(m: Mon, fs: FloorState, check_petrified := true) -> Array:
	var d := m.facing
	var limit := 1 if st(m, "blinker") > 0 else 8
	var targeting_iq := iq(m, "exp. go-getter") or iq(m, "exp go-getter") or iq(m, "efficiency expert")
	var sc := iq(m, "status checker")
	var cands: Array = []
	for i in limit:
		d &= 7
		var t := fs.mon_at(m.pos + DIRS[d])
		if t != null and fs.can_attack_dir(m.pos, d) and treatment(m, t, false, check_petrified) == TREAT_ENEMY \
				and (not sc or st(t, "frozen") == 0):
			if not targeting_iq:
				return [true, d]
			cands.append([d, _weight_move(m, T_OTHER, t)])
		d += 1
	if cands.is_empty():
		return [false, 0]
	var mx := 0
	for c in cands:
		mx = maxi(mx, int(c[1]))
	var tot := 0
	for c in cands:
		if int(c[1]) != mx:
			c[1] = 0
		tot += int(c[1])
	var roll := _rand(fs, tot)
	var pick := 0
	for i in cands.size():
		roll -= int(cands[i][1])
		pick = i
		if roll < 0:
			break
	return [true, int(cands[pick][0])]

# ======================================================================== Status Checker (move_checks.c)
static func _stage(m: Mon, k: String) -> int:
	return int(m.stages.get(k, DEFAULT_STAT_STAGE))

static func _mult(m: Mon, k: String) -> int:
	var sm = m.get("stat_mult")
	if sm is Dictionary:
		return int(sm.get(k, 256))
	return 256

static func _move_flag(m: Mon, flag: String) -> bool:
	for mv in m.moves:
		if _move_exists(mv) and bool(mv.get(flag, false)):
			return true
	return false

## CanUseOnSelfWithStatusChecker
static func can_use_on_self_sc(m: Mon, fs: FloorState, name: String) -> bool:
	var w := fs.weather
	match _norm(name):
		"hail":
			return w != "hail"
		"rage":
			return st(m, "enraged") == 0
		"counter", "pursuit":
			return st(m, "counter") == 0
		"mirrormove":
			return st(m, "mirror_move") == 0
		"howl", "meditate", "sharpen", "swordsdance":
			return _stage(m, "atk") < MAX_STAT_STAGE
		"bellydrum":
			return _stage(m, "atk") < MAX_STAT_STAGE and int(m.get_meta("belly", 100)) > 0
		"acidarmor", "barrier", "defensecurl", "harden", "irondefense", "withdraw":
			return _stage(m, "def") < MAX_STAT_STAGE
		"amnesia":
			return _stage(m, "spd") < MAX_STAT_STAGE
		"bide", "revenge":
			return st(m, "bide") == 0
		"agility":
			return TurnRules.speed_stage(m) < MAX_SPEED_STAGE
		"lockon", "mindreader":
			return st(m, "sure_shot") == 0
		"cosmicpower":
			return not (_stage(m, "def") >= MAX_STAT_STAGE and _stage(m, "spd") >= MAX_STAT_STAGE)
		"endure":
			return st(m, "enduring") == 0
		"charge":
			return st(m, "charging") == 0
		"mist":
			return st(m, "mist") == 0
		"lightscreen":
			return st(m, "light_screen") == 0
		"minimize", "doubleteam":
			return _stage(m, "eva") < MAX_STAT_STAGE
		"ingrain":
			return st(m, "ingrain") == 0 and not (m.max_hp / 2 < m.hp)
		"swallow":
			return m.hp < m.max_hp and st(m, "stockpile") > 0
		"spitup":
			return st(m, "stockpile") > 0
		"doomdesire", "futuresight":
			return st(m, "set_damage") == 0
		"bulkup":
			return not (_stage(m, "atk") >= MAX_STAT_STAGE and _stage(m, "def") >= MAX_STAT_STAGE)
		"camouflage":
			return true   # TODO(red): gDungeonCamouflageTypes[tileset]
		"tailglow", "growth":
			return _stage(m, "spa") < MAX_STAT_STAGE
		"destinybond":
			return st(m, "destiny_bond") == 0
		"mirrorcoat":
			return st(m, "mirror_coat") == 0
		"reflect":
			return st(m, "reflect") == 0
		"dragondance":
			return not (_stage(m, "atk") >= MAX_STAT_STAGE and TurnRules.speed_stage(m) >= MAX_SPEED_STAGE)
		"magiccoat":
			return st(m, "magic_coat") == 0
		"detect", "protect":
			return st(m, "protect") == 0
		"raindance":
			return w != "rain"
		"sandstorm":
			return w != "sandstorm"
		"sunnyday":
			return w != "sunny"
		"safeguard":
			return st(m, "safeguard") == 0
		"invisify":
			return st(m, "invisible") == 0
		"focusenergy":
			return st(m, "focus_energy") == 0
		"takeaway":
			return m.held == ""
		"rest":
			return has_quarter_hp(m) or has_negative_status(m)
		"dive":
			return fs.terrain_at(m.pos) == 2 and fs.secondary == "water"    # IsTileGround -> can't dive
		"dig":
			return fs.terrain_at(m.pos) == 1
		"trapbuster":
			return fs.traps.has(m.pos)
		"mudsport", "watersport":
			return true   # TODO(red): gDungeon->weather.mud/waterSportTurns
		"grudge":
			return st(m, "grudge") == 0
		"decoymaker", "followme", "substitute":
			return true   # TODO(red): gDungeon->decoyIsActive
		"stockpile":
			return st(m, "stockpile") < MAX_STOCKPILE_STAGE
		"cleanse":
			return m.held == "" or bool(m.get("held_sticky"))
		"wish":
			return m.is_team() and st(m, "wish") == 0
		"transform":
			return st(m, "transformed") == 0
		"spikes":
			return not fs.traps.has(m.pos) and not fs.items.has(m.pos) and fs.room_at(m.pos) != 255   # ~CanLayTrap
		"calmmind":
			return not (_stage(m, "spa") >= MAX_STAT_STAGE and _stage(m, "spd") >= MAX_STAT_STAGE)
		"snatch":
			return st(m, "snatch") == 0
		"conversion2":
			return st(m, "conversion2") == 0
		"helpinghand":
			for o in fs.mons:
				if o.hp > 0 and o != m and o.side == m.side and can_see_target(fs, m, o):
					if _stage(o, "atk") >= MAX_STAT_STAGE:
						continue
					if _stage(o, "spa") < MAX_STAT_STAGE:
						return true
			return false
	# Beat Up, Roar, Whirlwind, Teleport, ...: only blocked in floor-wide fixed rooms (TODO(red): fixed rooms).
	return true

## CanUseOnTargetWithStatusChecker
static func can_use_on_target_sc(m: Mon, t: Mon, name: String) -> bool:
	if st(t, "frozen") > 0 and int(move_data(name).get("nofrozen", 0)) != 0:
		return false
	match _norm(name):
		"grasswhistle", "hypnosis", "lovelykiss", "sing", "sleeppowder", "spore":
			return not is_sleeping(t)
		"yawn":
			return st(t, "yawn") == 0 and not is_sleeping(t)
		"nightmare":
			return st(t, "nightmare") == 0
		"sweetscent":
			return _stage(t, "eva") > 0
		"charm":
			return _mult(t, "atk") >= STAT_MULTIPLIER_THRESHOLD
		"encore":
			return st(t, "encore") == 0 and t.last_move != ""
		"superfang", "falseswipe":
			return t.hp > 1
		"painsplit":
			return t.hp > m.hp
		"torment":
			return not _move_flag(t, "disabled") and t.last_move != ""
		"cottonspore", "scaryface", "stringshot":
			return TurnRules.speed_stage(t) > 0
		"screech":
			return _mult(t, "def") >= STAT_MULTIPLIER_THRESHOLD
		"faketears", "metalsound":
			return _stage(t, "spd") > 0
		"spite":
			var lm = t.move_by_name(t.last_move)
			return not (lm is Dictionary and not lm.is_empty() and int(lm.get("pp", 1)) == 0)
		"smokescreen":
			return st(t, "whiffer") == 0
		"memento":
			return not (_mult(t, "atk") < STAT_MULTIPLIER_THRESHOLD and _mult(t, "spa") < STAT_MULTIPLIER_THRESHOLD)
		"willowisp":
			return st(t, "burn") == 0
		"foresight", "odorsleuth":
			if is_type(t, "Ghost") and not bool(t.get("exposed")):
				return true
			return _stage(t, "eva") > DEFAULT_STAT_STAGE
		"disable", "glare", "stunspore", "thunderwave":
			return st(t, "para") == 0
		"endeavor":
			return t.hp - m.hp > 0
		"leer", "tailwhip":
			return _stage(t, "def") > 0
		"tickle":
			return not (_stage(t, "atk") <= 0 and _stage(t, "def") <= 0)
		"block", "meanlook", "spiderweb":
			return st(t, "shadow_hold") == 0
		"haze":
			for k in ["atk", "spa", "def", "spd", "acc", "eva"]:
				if _stage(t, k) < DEFAULT_STAT_STAGE:
					return true
			for k in ["atk", "spa", "def", "spd"]:
				if _mult(t, k) < 256:
					return true
			return false
		"uproar":
			return st(t, "sleepless") == 0
		"psychup":
			for k in ["atk", "spa", "def", "spd", "acc", "eva"]:
				if _stage(m, k) < _stage(t, k):
					return true
			return false
		"flash", "kinesis", "sandattack":
			return _stage(t, "acc") > 0
		"taunt":
			return st(t, "taunt") == 0
		"trick":
			return m.held != "" and t.held != ""
		"knockoff":
			return t.held != ""
		"featherdance", "growl":
			return _stage(t, "atk") > 0
		"roleplay":
			return not (m.ability == t.ability and String(m.get("ability2")) == String(t.get("ability2")))
		"curse":
			if is_type(m, "Ghost"):
				return st(t, "curse") == 0
			return not (_stage(m, "atk") >= MAX_STAT_STAGE and _stage(m, "def") >= MAX_STAT_STAGE)
		"imprison", "observer":
			return st(t, "paused") == 0
		"leechseed":
			return st(t, "leech_seed") == 0
		"perishsong":
			return st(t, "perish") == 0
		"mimic", "sketch":
			return t.last_move != ""
		"attract":
			return st(t, "infatuated") == 0
		"wrap":
			return st(t, "wrapping") == 0 and st(t, "wrapped") == 0
		"toxic":
			return st(t, "badpoison") == 0
		"poisongas", "poisonpowder":
			return st(t, "poison") == 0 and st(t, "badpoison") == 0
		"confuseray", "flatter", "supersonic", "swagger", "sweetkiss", "teeterdance", "totter":
			return st(t, "confused") == 0
	return true

## Generated from pret/pmd-red data/move/move_data.json: name -> [aiTargetingFlags, aiConditionRandomChance, ignoresTaunted].
const RED_AI_MOVES := {
	"Iron Tail": [0, 75, 1],
	"Ice Ball": [128, 75, 1],
	"Yawn": [0, 75, 0],
	"Lovely Kiss": [32, 75, 0],
	"Nightmare": [0, 75, 0],
	"Morning Sun": [609, 75, 0],
	"Vital Throw": [0, 75, 0],
	"Dig": [0, 75, 1],
	"Thrash": [0, 75, 1],
	"Sweet Scent": [48, 75, 0],
	"Charm": [0, 75, 0],
	"Rain Dance": [48, 75, 0],
	"Confuse Ray": [0, 75, 0],
	"Hail": [48, 75, 0],
	"Aromatherapy": [817, 75, 0],
	"Bubble": [80, 75, 1],
	"Encore": [0, 75, 0],
	"Cut": [0, 75, 1],
	"Rage": [0, 75, 0],
	"Super Fang": [0, 75, 1],
	"Pain Split": [0, 75, 0],
	"Torment": [0, 75, 0],
	"String Shot": [80, 75, 0],
	"Swagger": [0, 75, 0],
	"Snore": [255, 75, 1],
	"Heal Bell": [817, 75, 0],
	"Rock Throw": [0, 75, 1],
	"Rock Smash": [255, 75, 1],
	"Rock Slide": [0, 75, 1],
	"Weather Ball": [80, 75, 1],
	"Whirlpool": [0, 75, 1],
	"Fake Tears": [0, 75, 0],
	"Sing": [128, 75, 0],
	"Spite": [0, 75, 0],
	"Air Cutter": [128, 75, 1],
	"Smokescreen": [128, 75, 0],
	"Pursuit": [0, 75, 0],
	"Doubleslap": [0, 75, 1],
	"Mirror Move": [0, 75, 0],
	"Overheat": [32, 75, 1],
	"Aurora Beam": [80, 75, 1],
	"Memento": [48, 75, 0],
	"Octazooka": [80, 75, 1],
	"Flatter": [0, 75, 0],
	"Astonish": [0, 75, 1],
	"Will-O-Wisp": [128, 75, 0],
	"Return": [0, 75, 1],
	"Grudge": [0, 75, 0],
	"Strength": [0, 75, 0],
	"Counter": [0, 75, 0],
	"Flame Wheel": [128, 75, 1],
	"Flamethrower": [80, 75, 1],
	"Odor Sleuth": [48, 75, 0],
	"Sharpen": [0, 75, 0],
	"Double Team": [48, 75, 0],
	"Gust": [0, 75, 1],
	"Harden": [32, 75, 0],
	"Disable": [0, 75, 0],
	"Razor Wind": [128, 75, 1],
	"Bide": [0, 75, 0],
	"Crunch": [0, 75, 1],
	"Thunderpunch": [0, 75, 1],
	"Endeavor": [0, 75, 1],
	"Facade": [0, 75, 1],
	"Karate Chop": [0, 75, 1],
	"Clamp": [0, 75, 1],
	"Withdraw": [0, 75, 0],
	"Constrict": [0, 75, 1],
	"Brick Break": [0, 75, 1],
	"Rock Tomb": [0, 75, 1],
	"Focus Energy": [0, 75, 0],
	"Focus Punch": [0, 75, 1],
	"Giga Drain": [0, 75, 1],
	"Reversal": [0, 75, 1],
	"Smellingsalt": [0, 75, 1],
	"Spore": [48, 75, 0],
	"Leech Life": [0, 75, 1],
	"Slash": [0, 75, 1],
	"Silver Wind": [48, 75, 1],
	"Metal Sound": [128, 75, 0],
	"Grasswhistle": [128, 75, 0],
	"Tickle": [0, 75, 0],
	"Spider Web": [128, 75, 0],
	"Crabhammer": [0, 75, 1],
	"Haze": [49, 75, 0],
	"Mean Look": [0, 75, 0],
	"Cross Chop": [0, 75, 1],
	"Outrage": [0, 75, 1],
	"Low Kick": [0, 75, 1],
	"Ancientpower": [0, 75, 1],
	"Synthesis": [627, 75, 0],
	"Agility": [48, 75, 0],
	"Rapid Spin": [0, 75, 1],
	"Icy Wind": [80, 75, 1],
	"Mind Reader": [0, 75, 0],
	"Cosmic Power": [0, 75, 0],
	"Sky Attack": [128, 75, 1],
	"Powder Snow": [0, 75, 1],
	"Follow Me": [48, 75, 0],
	"Meteor Mash": [80, 75, 1],
	"Endure": [0, 75, 0],
	"Rollout": [0, 75, 1],
	"Scary Face": [0, 75, 0],
	"Psybeam": [80, 75, 1],
	"Psywave": [80, 75, 1],
	"Psychic": [0, 75, 1],
	"Psycho Boost": [0, 75, 1],
	"Uproar": [48, 75, 0],
	"Water Spout": [0, 75, 1],
	"Signal Beam": [80, 75, 1],
	"Psych Up": [2, 75, 0],
	"Submission": [0, 75, 1],
	"Recover": [627, 75, 0],
	"Earthquake": [0, 75, 1],
	"Nature Power": [0, 75, 1],
	"Lick": [0, 75, 1],
	"Flail": [0, 75, 1],
	"Tail Whip": [0, 75, 0],
	"Selfdestruct": [0, 75, 1],
	"Stun Spore": [32, 75, 0],
	"Bind": [0, 75, 1],
	"Shadow Punch": [0, 75, 1],
	"Shadow Ball": [80, 75, 1],
	"Charge": [0, 75, 0],
	"Thunderbolt": [32, 75, 1],
	"Mist": [0, 75, 0],
	"Fissure": [0, 75, 1],
	"Extremespeed": [64, 75, 1],
	"Extrasensory": [0, 75, 1],
	"Safeguard": [48, 75, 0],
	"Absorb": [0, 75, 1],
	"Sky Uppercut": [0, 75, 1],
	"Skill Swap": [0, 75, 0],
	"Sketch": [0, 75, 0],
	"Headbutt": [0, 75, 1],
	"Double-Edge": [0, 75, 1],
	"Sandstorm": [48, 20, 0],
	"Sand-Attack": [128, 75, 0],
	"Sand Tomb": [0, 75, 1],
	"Spark": [0, 75, 1],
	"Swift": [128, 75, 1],
	"Kinesis": [0, 75, 0],
	"Smog": [0, 75, 1],
	"Growth": [48, 75, 0],
	"Sacred Fire": [0, 75, 1],
	"Sheer Cold": [0, 75, 1],
	"Solarbeam": [128, 75, 1],
	"Sonicboom": [80, 75, 1],
	"Fly": [0, 75, 1],
	"Tackle": [0, 75, 1],
	"Explosion": [64, 75, 1],
	"Dive": [0, 75, 1],
	"Fire Blast": [128, 75, 1],
	"Waterfall": [0, 75, 1],
	"Muddy Water": [0, 75, 1],
	"Stockpile": [0, 75, 0],
	"Slam": [0, 75, 1],
	"Twister": [0, 75, 1],
	"Bullet Seed": [80, 75, 1],
	"Twineedle": [80, 75, 1],
	"Softboiled": [561, 75, 0],
	"Egg Bomb": [128, 75, 1],
	"Faint Attack": [0, 75, 1],
	"Barrage": [128, 75, 1],
	"Minimize": [0, 75, 0],
	"Seismic Toss": [0, 75, 1],
	"Supersonic": [128, 75, 0],
	"Taunt": [0, 75, 0],
	"Peck": [0, 75, 1],
	"Horn Attack": [0, 75, 1],
	"Horn Drill": [0, 75, 1],
	"Wing Attack": [0, 75, 1],
	"Aerial Ace": [0, 75, 1],
	"Icicle Spear": [128, 75, 1],
	"Swords Dance": [48, 20, 0],
	"Vine Whip": [0, 75, 1],
	"Conversion": [0, 75, 0],
	"Conversion 2": [0, 75, 0],
	"Helping Hand": [48, 75, 0],
	"Iron Defense": [0, 75, 0],
	"Teleport": [0, 75, 0],
	"Thundershock": [0, 75, 1],
	"Shock Wave": [80, 75, 1],
	"Quick Attack": [64, 75, 1],
	"Sweet Kiss": [0, 75, 0],
	"Thunder Wave": [0, 75, 0],
	"Zap Cannon": [80, 75, 1],
	"Block": [0, 75, 0],
	"Howl": [0, 75, 0],
	"Toxic": [0, 75, 0],
	"Poison Fang": [0, 75, 1],
	"Poisonpowder": [0, 75, 0],
	"Poison Sting": [128, 75, 1],
	"Spike Cannon": [80, 75, 1],
	"Acid Armor": [0, 75, 0],
	"Take Down": [0, 75, 1],
	"Jump Kick": [0, 75, 1],
	"Hi Jump Kick": [0, 75, 1],
	"Tri Attack": [128, 75, 1],
	"Dragon Claw": [0, 75, 1],
	"Trick": [0, 75, 0],
	"Triple Kick": [0, 75, 1],
	"Drill Peck": [0, 75, 1],
	"Mud Sport": [48, 75, 0],
	"Mud-Slap": [128, 75, 1],
	"Thief": [0, 75, 1],
	"Amnesia": [0, 75, 0],
	"Night Shade": [32, 75, 1],
	"Growl": [64, 75, 0],
	"Slack Off": [627, 75, 0],
	"Surf": [0, 75, 1],
	"Role Play": [0, 75, 0],
	"Needle Arm": [0, 75, 1],
	"Double Kick": [0, 75, 1],
	"Sunny Day": [48, 75, 0],
	"Leer": [0, 75, 0],
	"Fake Out": [64, 75, 1],
	"Sleep Talk": [255, 75, 0],
	"Pay Day": [0, 75, 1],
	"Assist": [0, 75, 1],
	"Heat Wave": [48, 75, 1],
	"Sleep Powder": [32, 75, 0],
	"Rest": [0, 75, 0],
	"Ingrain": [0, 75, 0],
	"Confusion": [0, 75, 1],
	"Body Slam": [0, 75, 1],
	"Curse": [0, 75, 0],
	"Frenzy Plant": [128, 75, 1],
	"Hydro Cannon": [80, 75, 1],
	"Hydro Pump": [80, 75, 1],
	"Hyper Voice": [128, 75, 1],
	"Hyper Beam": [80, 75, 1],
	"Steel Wing": [0, 75, 1],
	"Spit Up": [0, 75, 1],
	"Dynamicpunch": [0, 75, 1],
	"Guillotine": [0, 75, 1],
	"Vicegrip": [0, 75, 1],
	"Knock Off": [0, 75, 0],
	"Pound": [0, 75, 1],
	"Razor Leaf": [80, 75, 1],
	"Baton Pass": [50, 75, 0],
	"Petal Dance": [0, 75, 1],
	"Splash": [0, 75, 0],
	"Bubblebeam": [80, 75, 1],
	"Doom Desire": [0, 75, 0],
	"Belly Drum": [0, 75, 0],
	"Light Screen": [0, 75, 0],
	"Scratch": [0, 75, 1],
	"Hyper Fang": [0, 75, 1],
	"Ember": [128, 75, 1],
	"Secret Power": [0, 75, 1],
	"Dizzy Punch": [0, 75, 1],
	"Bulk Up": [0, 75, 0],
	"Imprison": [0, 75, 0],
	"Featherdance": [0, 75, 0],
	"Whirlwind": [0, 75, 0],
	"Beat Up": [0, 75, 0],
	"Blizzard": [128, 75, 1],
	"Stomp": [0, 75, 1],
	"Blast Burn": [32, 75, 1],
	"Flash": [0, 75, 0],
	"Teeter Dance": [98, 75, 0],
	"Crush Claw": [0, 75, 1],
	"Blaze Kick": [0, 75, 1],
	"Present": [128, 75, 1],
	"Sludge Bomb": [80, 75, 1],
	"Glare": [0, 75, 0],
	"Poison Tail": [0, 75, 1],
	"Roar": [0, 75, 0],
	"Bone Rush": [128, 75, 1],
	"Camouflage": [0, 75, 0],
	"Covet": [0, 75, 1],
	"Tail Glow": [0, 75, 0],
	"Bone Club": [0, 75, 1],
	"Bonemerang": [80, 75, 1],
	"Fire Spin": [0, 75, 1],
	"Fire Punch": [0, 75, 1],
	"Perish Song": [48, 75, 0],
	"Wrap": [0, 75, 0],
	"Magnitude": [0, 75, 1],
	"Magical Leaf": [128, 75, 1],
	"Magic Coat": [0, 75, 0],
	"Mud Shot": [128, 75, 1],
	"Mach Punch": [64, 75, 1],
	"Protect": [0, 75, 0],
	"Defense Curl": [0, 75, 0],
	"Rolling Kick": [0, 75, 1],
	"Substitute": [0, 75, 0],
	"Detect": [0, 75, 0],
	"Pin Missile": [80, 75, 1],
	"Water Sport": [48, 75, 0],
	"Water Gun": [128, 75, 1],
	"Mist Ball": [128, 75, 1],
	"Water Pulse": [80, 75, 1],
	"Fury Attack": [0, 75, 1],
	"Fury Swipes": [0, 75, 1],
	"Destiny Bond": [128, 75, 0],
	"False Swipe": [0, 75, 1],
	"Foresight": [0, 75, 0],
	"Mirror Coat": [0, 75, 0],
	"Future Sight": [0, 75, 0],
	"Milk Drink": [609, 75, 0],
	"Calm Mind": [48, 75, 0],
	"Mega Drain": [0, 75, 1],
	"Mega Kick": [0, 75, 1],
	"Mega Punch": [0, 75, 1],
	"Megahorn": [128, 75, 1],
	"Hidden Power": [0, 75, 1],
	"Metal Claw": [0, 75, 1],
	"Attract": [128, 75, 0],
	"Mimic": [0, 75, 0],
	"Frustration": [0, 75, 1],
	"Leech Seed": [128, 75, 0],
	"Metronome": [0, 75, 1],
	"Dream Eater": [1024, 75, 1],
	"Acid": [128, 75, 1],
	"Snatch": [48, 75, 0],
	"Luster Purge": [0, 75, 1],
	"Leaf Blade": [0, 75, 1],
	"Recycle": [255, 75, 0],
	"Reflect": [0, 75, 0],
	"Refresh": [817, 75, 0],
	"Revenge": [0, 75, 0],
	"Dragon Rage": [128, 75, 1],
	"Dragonbreath": [80, 75, 1],
	"Dragon Dance": [0, 75, 0],
	"Ice Punch": [0, 75, 1],
	"Ice Beam": [80, 75, 1],
	"Fury Cutter": [0, 75, 1],
	"Comet Punch": [0, 75, 1],
	"Skull Bash": [0, 75, 1],
	"Lock-On": [0, 75, 0],
	"Rock Blast": [128, 75, 1],
	"Cotton Spore": [0, 75, 0],
	"Struggle": [0, 75, 1],
	"Aeroblast": [80, 75, 1],
	"Volt Tackle": [80, 75, 1],
	"attack": [0, 75, 1],
	"ようすをみる": [0, 75, 1],
	"がまん": [0, 75, 1],
	"-": [255, 75, 0],
	"Wide Slash": [0, 75, 1],
	"Excavate": [255, 75, 1],
	"Spin Slash": [0, 75, 1],
	"See-Trap": [48, 75, 0],
	"Takeaway": [0, 75, 1],
	"Rebound": [0, 75, 0],
	"Bloop Slash": [64, 75, 1],
	"Switcher": [82, 75, 0],
	"Blowback": [80, 75, 0],
	"Warp": [48, 75, 0],
	"Transfer": [128, 75, 0],
	"Slow Down": [48, 75, 0],
	"Speed Boost": [48, 75, 0],
	"Searchlight": [255, 75, 0],
	"Petrify": [48, 75, 0],
	"Stay Away": [128, 75, 0],
	"Pounce": [255, 75, 0],
	"Trawl": [255, 75, 0],
	"Cleanse": [255, 20, 0],
	"Observer": [128, 75, 0],
	"Decoy Maker": [128, 75, 0],
	"Siesta": [48, 75, 0],
	"Totter": [48, 75, 0],
	"Two-Edge": [48, 75, 0],
	"No-Move": [0, 75, 0],
	"Escape": [255, 75, 0],
	"Scan": [255, 75, 0],
	"Power-Ears": [255, 75, 0],
	"Drought": [255, 75, 0],
	"Trap Buster": [48, 75, 0],
	"Wild Call": [0, 75, 0],
	"Invisify": [0, 75, 0],
	"One-Shot": [0, 75, 1],
	"HP Gauge": [255, 75, 0],
	"Vacuum-Cut": [48, 75, 0],
	"Reviver": [255, 75, 0],
	"Shocker": [0, 75, 1],
	"Echo": [0, 75, 1],
	"Famish": [48, 75, 0],
	"One-Room": [48, 75, 0],
	"Fill-In": [255, 75, 0],
	"Trapper": [48, 75, 0],
	"Possess": [0, 75, 0],
	"Itemize": [128, 75, 0],
	"Hurl": [0, 75, 1],
	"Mobile": [48, 75, 0],
	"Item-Toss": [255, 75, 0],
	"See Stairs": [255, 75, 0],
	"Long Toss": [48, 75, 0],
	"Pierce": [48, 75, 0],
	"Screech": [128, 75, 0],
	"Bite": [0, 75, 1],
	"Sludge": [128, 75, 1],
	"Hypnosis": [128, 75, 0],
	"Vise Grip": [0, 75, 1],
	"Thunder": [0, 75, 1],
	"High Jump Kick": [0, 75, 1],
	"Poison Gas": [0, 75, 0],
	"Transform": [96, 75, 0],
	"Moonlight": [561, 75, 0],
	"Swallow": [0, 75, 0],
	"Wish": [48, 75, 0],
	"Superpower": [0, 75, 1],
	"Eruption": [128, 75, 1],
	"Arm Thrust": [0, 75, 1],
	"Bounce": [0, 75, 1],
}
