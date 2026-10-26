class_name IQSky
extends RefCounted
## Explorers of Sky add-on IQ skills: the effects that need the dungeon controller (or a team entry),
## as static hooks the dungeon / town code calls. Data: the "sky": true skills of res://data/iq.json
## (gen_iq_sky.py). Effects that are pure combat / turn math live in combat.gd and turn_rules.gd.
##
## Values marked "decomp" come from pret/pmd-sky (overlay 10 / arm9 data); "chosen" ones are not in the
## decompiled code yet and follow the in-game description.
##
## `dungeon` is the Dungeon node (public members used: fs, team_mons, obj_layer, _msg, _hurt, faint,
## _px, _reveal, _pick_item, ddata, floor_i). Every hook is a no-op unless a team member has the skill on,
## so Red's behaviour is unchanged without Sky skills.

const COIN_WATCHER_NUM := 6               # x1.2 (GetMoneyQuantity, decomp)
const COIN_WATCHER_DEN := 5
const EXP_ELITE_PCT := 10                 # EXP_ELITE_EXP_BOOST (decomp)
const FAST_FRIEND_BOOST := 50             # FRIEND_BOW_FAST_FRIEND_BOOST, per 1000 (decomp)
const PP_SAVER_PCT := 30                  # chosen
const INTIMIDATOR_PCT := 32               # INTIMIDATOR_ACTIVATION_CHANCE (decomp)
const TRAP_BUSTER_PCT := 30               # TRAP_BUSTER_ACTIVATION_CHANCE (decomp)
const COUNTER_BASHER_PCT := 10            # ov10_022C44C0 (decomp): reflects 4/4 of the damage
const COUNTER_HITTER_PCT := 24            # ov10_022C4464 (decomp): reflects 1/4 of the damage
const HIT_AND_RUNNER_PCT := 33            # ov10_022C442C (decomp): attacker ignores counters
const EXTRA_STRIKER_PCT := 33             # chosen
const WISE_HEALER_PCT := 15               # WISE_HEALER_PERCENTAGE (decomp)
const POWER_PITCHER_MUL := 1.5            # POWER_PITCHER_DAMAGE_MULTIPLIER (decomp)
const SURVIVALIST_MUL := 1.5              # chosen
const GRIMY_RESIST_PCT := 50              # ApplyGrimyFoodEffect (decomp)
const DEEP_BREATHER_PP := 2               # chosen
const BRICK_TOUGH_HP := 10                # _020A1870 (decomp)
const MULTITALENT_PP := 5                 # MULTITALENT_PP_BOOST_AMOUNT (decomp)
const HAGGLER_BUY := 0.8                  # chosen
const HAGGLER_SELL := 1.2                 # chosen
const COLLECTOR_PCT := 10                 # chosen (Sky raises treasure-box drops; Red has none)
const MAX_PP := 99
## Item kinds whose effect Nature Gifter spreads to the team (healing Berries / Seeds).
const NATURE_GIFTER_KINDS := ["heal", "sitrus", "cure"]

## The floor in play (set by on_floor_start; also copied to Combat.sky_floor for Cheerleader).
static var fs: FloorState = null
static var rng := RandomNumberGenerator.new()

# ------------------------------------------------------------------ queries
## Skill switched on? Mon: its active list (m.iq_skills, like Combat.has_iq); team entry: IQ.has.
static func has(m, id: String) -> bool:
	if m == null:
		return false
	if m is Dictionary:
		return not m.is_empty() and IQ.has(m, id)
	if m is Mon:
		return Combat.has_iq(m, id)
	return false

static func _floor(d) -> FloorState:
	if d is FloorState:
		return d
	if d != null and d is Object and "fs" in d:
		return d.fs
	return fs

static func _team(d) -> Array:
	var f := _floor(d)
	if f != null:
		return f.team()
	if d != null and d is Object and "team_mons" in d:
		return d.team_mons
	return []

## First living team member with the skill on, or null (GetTeamMemberWithIqSkill).
static func team_member_with(d, id: String) -> Mon:
	for m in _team(d):
		if m.hp > 0 and has(m, id):
			return m
	return null

## A teammate (not m itself) within 1 tile has the skill (NearbyAllyIqSkillIsEnabled).
static func nearby_ally_has(m: Mon, id: String, on_floor = null) -> bool:
	return Combat.nearby_ally_has_iq(m, id, on_floor if on_floor != null else fs)

static func _roll(r: RandomNumberGenerator, pct: int) -> bool:
	return (r if r != null else rng).randi_range(0, 99) < pct

static func _say(d, key: String, subs := {}) -> void:
	var s := str(IQ.data().get("sky_messages", {}).get(key, ""))
	for k in subs:
		s = s.replace("{%s}" % k, str(subs[k]))
	if s != "" and d != null and d is Object and d.has_method("_msg"):
		d._msg(s)

static func _nm(d, m: Mon) -> String:
	if d != null and d is Object and d.has_method("_nm"):
		return d._nm(m)
	return m.name if m != null else "?"

# ------------------------------------------------------------------ passives (called by IQ.apply)
## Brick-Tough: max HP +10 (via a copy of the "bonus" meta, so DB.recalc keeps it after level-ups and the
## team entry is untouched). Multitalent: every move +5 max PP (tracked per move as "iq_pp_bonus" so it
## comes off again when the skill is gone). No-op for a Pokémon that never had either.
static func apply_passives(m: Mon) -> void:
	if m == null or not m.is_team():
		return
	var hp_b := BRICK_TOUGH_HP if has(m, "brick_tough") else 0
	var old_hp_b := int(m.get_meta("iq_hp_bonus", 0))
	if hp_b != old_hp_b:
		# base = the entry's own bonus (or the meta minus what Brick-Tough added before)
		var e: Dictionary = m.get_meta("entry", {})
		var bonus: Dictionary = (e.get("bonus", {}) if not e.is_empty() else m.get_meta("bonus", {})).duplicate()
		if e.is_empty():
			bonus.hp = int(bonus.get("hp", 0)) - old_hp_b
		bonus.hp = int(bonus.get("hp", 0)) + hp_b
		var was_alive := m.hp > 0
		m.set_meta("bonus", bonus)
		m.set_meta("iq_hp_bonus", hp_b)
		DB.recalc(m)
		if was_alive:
			m.hp = clampi(m.hp, 1, m.max_hp)
	var pp_b := MULTITALENT_PP if has(m, "multitalent") else 0
	for mv in m.moves:
		if not (mv is Dictionary) or not mv.has("max_pp"):
			continue
		var old_b := int(mv.get("iq_pp_bonus", 0))
		if old_b == pp_b:
			continue
		var base := int(mv.max_pp) - old_b
		mv.max_pp = mini(MAX_PP, base + pp_b)
		if pp_b > 0:
			mv.iq_pp_bonus = mv.max_pp - base
		else:
			mv.erase("iq_pp_bonus")
		mv.pp = mini(int(mv.get("pp", 0)), int(mv.max_pp))

# ------------------------------------------------------------------ floor start
## New floor: Stair Sensor, Map Surveyor, Acute Sniffer, Deep Breather. Also remembers the floor for
## Cheerleader. Returns the messages (also sent to dungeon._msg).
static func on_floor_start(d) -> Array:
	var f := _floor(d)
	fs = f
	Combat.sky_floor = f      # Cheerleader in damage calc
	var out: Array = []
	if f == null:
		return out
	var say := func(key: String, subs := {}):
		var s := str(IQ.data().get("sky_messages", {}).get(key, ""))
		for k in subs:
			s = s.replace("{%s}" % k, str(subs[k]))
		out.append(s)
		if d != null and d is Object and d.has_method("_msg"):
			d._msg(s)
	var changed := false
	var ms := team_member_with(d, "map_surveyor")
	if ms:
		# whole layout; the stairs tile itself is left to Stair Sensor / exploring
		for y in f.h:
			for x in f.w:
				var p := Vector2i(x, y)
				if f.terrain_at(p) != 0 and p != f.stairs:
					f.explored[f.idx(p)] = 1
		changed = true
		say.call("map_surveyor", {"0": _nm(d, ms)})
	if team_member_with(d, "stair_sensor") and f.inb(f.stairs):
		f.explored[f.idx(f.stairs)] = 1
		f.set_meta("stairs_sensed", true)
		changed = true
		say.call("stair_sensor")
	if team_member_with(d, "acute_sniffer"):
		say.call("acute_sniffer", {"n": f.items.size()})
	for m in _team(d):
		if m.hp > 0 and has(m, "deep_breather"):
			var any := false
			for mv in m.moves:
				if mv is Dictionary and mv.has("pp") and int(mv.pp) < int(mv.get("max_pp", 0)):
					mv.pp = mini(int(mv.max_pp), int(mv.pp) + DEEP_BREATHER_PP)
					any = true
			if any:
				say.call("deep_breather", {"0": _nm(d, m)})
	if changed and d != null and d is Object and d.has_method("_reveal"):
		d._reveal()     # redraws the minimap when it is open
	return out

# ------------------------------------------------------------------ money / exp / recruiting / shops
## Coin Watcher: Poké picked up x1.2 (the Pokémon picking it up).
static func money_pickup(m, n: int) -> int:
	if has(m, "coin_watcher"):
		return n * COIN_WATCHER_NUM / COIN_WATCHER_DEN
	return n

## Exp. Elite: +10% of the base Exp.
static func exp_gain(m, n: int) -> int:
	if has(m, "exp_elite"):
		return n + n * EXP_ELITE_PCT / 100
	return n

## Fast Friend on the leader: +50 to the recruit rate (per 1000). Pass the leader (Mon), a team Array
## (its first member is the leader) or the dungeon.
static func recruit_bonus(team) -> int:
	var leader = team
	if team is Array:
		leader = team[0] if team.size() > 0 else null
	elif team != null and team is Object and "fs" in team:
		leader = team.fs.leader if team.fs else null
	return FAST_FRIEND_BOOST if has(leader, "fast_friend") else 0

## Haggler on the leader: price multiplier for buying (0.8) / selling (1.2). Sky: Kecleon shops in dungeons.
static func shop_price_mult(leader, buying: bool) -> float:
	if not has(leader, "haggler"):
		return 1.0
	return HAGGLER_BUY if buying else HAGGLER_SELL

static func shop_price(leader, price: int, buying: bool) -> int:
	var mul := shop_price_mult(leader, buying)
	if mul == 1.0:
		return price
	return maxi(1, int(round(price * mul))) if price > 0 else price

# ------------------------------------------------------------------ attacks
## How many times a regular attack strikes: Quick Striker always 2, Extra Striker 1/3 of the time 2.
static func regular_attack_hits(m: Mon, r: RandomNumberGenerator = null) -> int:
	if has(m, "quick_striker"):
		return 2
	if has(m, "extra_striker") and _roll(r, EXTRA_STRIKER_PCT):
		return 2
	return 1

## PP a move use costs: PP Saver 30% -> 0 (with Sky's message); No-Charger on a two-turn move -> 2.
static func pp_cost(m: Mon, move_name: String, r: RandomNumberGenerator = null, d = null) -> int:
	if move_name == "":
		return 0
	if has(m, "pp_saver") and _roll(r, PP_SAVER_PCT):
		_say(d, "pp_saver", {"0": _nm(d, m)})
		return 0
	if skips_charge(m, move_name):
		return 2
	return 1

## No-Charger: the two-turn move fires on the first turn (the caller skips the charging turn).
static func skips_charge(m: Mon, move_name: String) -> bool:
	return has(m, "no_charger") and IQ.is_charge_move(move_name)

## Called per target before the hit. Returns the Mon that takes the hit: a Bodyguard teammate next to a
## low-HP target steps in; or null when Intimidator (32%) makes the adjacent attacker cringe and not
## attack. Otherwise the target itself.
static func before_hit(d, attacker: Mon, target: Mon) -> Mon:
	var f := _floor(d)
	if attacker == null or target == null or attacker == target or f == null:
		return target
	if not f.is_foe(attacker, target):
		return target
	if FloorState.cheb(attacker.pos, target.pos) <= 1 and has(target, "intimidator") and _roll(f.rng, INTIMIDATOR_PCT):
		attacker.status["cringe"] = maxi(1, int(attacker.status.get("cringe", 0)))
		_say(d, "intimidator", {"0": _nm(d, target), "1": _nm(d, attacker)})
		return null
	if target.hp <= target.max_hp / 4:
		for o in f.mons:
			if o != target and o != attacker and o.hp > 0 and o.side == target.side \
					and FloorState.cheb(o.pos, target.pos) <= 1 and has(o, "bodyguard"):
				_say(d, "bodyguard", {"0": _nm(d, o), "1": _nm(d, target)})
				return o
	return target

## After `target` took `dmg` from `attacker` (counterattacks, ov29_02308FBC.c): physical hits from an
## adjacent attacker are reflected -- Counter Basher 10% for all the damage, Counter Hitter 24% for 1/4
## (dmg * n / 4); Hit-and-Runner on the attacker skips this 33% of the time. Async (may faint the attacker).
static func after_hit(d, attacker: Mon, target: Mon, dmg: int, physical := true) -> void:
	var f := _floor(d)
	if attacker == null or target == null or attacker == target or dmg <= 0 or not physical:
		return
	if attacker.hp <= 0 or target.hp <= 0 or FloorState.cheb(attacker.pos, target.pos) > 1:
		return
	if not has(target, "counter_basher") and not has(target, "counter_hitter"):
		return
	var r: RandomNumberGenerator = f.rng if f else rng
	if has(attacker, "hit_and_runner") and _roll(r, HIT_AND_RUNNER_PCT):
		return
	var n := 0
	if has(target, "counter_basher") and _roll(r, COUNTER_BASHER_PCT):
		n += 4
	if has(target, "counter_hitter") and _roll(r, COUNTER_HITTER_PCT):
		n += 1
	if n == 0:
		return
	var cd := maxi(1, dmg * n / 4)
	if d != null and d is Object and d.has_method("_hurt"):
		d._hurt(attacker, cd, target, true)
	else:
		attacker.hp = maxi(0, attacker.hp - cd)
	_say(d, "counter", {"1": _nm(d, attacker), "n": cd})
	if attacker.hp <= 0 and d != null and d is Object and d.has_method("faint"):
		await d.faint(attacker, target)

## Wary Fighter: after missing, step one tile back from the target (if that tile is free).
static func after_miss(d, attacker: Mon, target: Mon) -> bool:
	var f := _floor(d)
	if f == null or attacker == null or target == null or attacker.hp <= 0 or not has(attacker, "wary_fighter"):
		return false
	var away := Vector2i(signi(attacker.pos.x - target.pos.x), signi(attacker.pos.y - target.pos.y))
	if away == Vector2i.ZERO:
		return false
	for dv in [away, Vector2i(away.x, 0), Vector2i(0, away.y)]:
		if dv == Vector2i.ZERO:
			continue
		var to: Vector2i = attacker.pos + dv
		if f.inb(to) and f.walkable(to, attacker) and f.mon_at(to) == null:
			var old := attacker.pos
			attacker.pos = to
			AI.on_moved(attacker, old)
			if attacker.visual and d != null and d is Object and d.has_method("_px"):
				attacker.visual.position = d._px(to)
			_say(d, "wary_fighter", {"0": _nm(d, attacker)})
			return true
	return false

## Gap Prober: line moves / thrown items pass through teammates (only with Course Checker off).
static func passes_through(m: Mon, o: Mon) -> bool:
	if m == null or o == null or o.side != m.side:
		return false
	return has(m, "gap_prober") and not has(m, "course_checker")

## Path of an item thrown by m in direction d: {"hits": [Mon...], "end": Vector2i (where a miss lands)}.
## Normal: stops at a wall, hits the first Pokémon. Gap Prober: flies past teammates. Pierce Hurler:
## flies through walls and Pokémon to the end of its range, hitting everyone on the line.
static func throw_path(d, m: Mon, dir: int, max_range := 10) -> Dictionary:
	var f := _floor(d)
	var dv: Vector2i = DB.DIRS[dir]
	var p := m.pos
	var end := m.pos
	var hits: Array = []
	var pierce := has(m, "pierce_hurler")
	for k in max_range:
		p += dv
		if not f.inb(p):
			break
		if f.is_wall(p):
			if pierce:
				continue
			break
		end = p
		var o := f.mon_at(p)
		if o and o != m:
			if passes_through(m, o):
				continue
			hits.append(o)
			if not pierce:
				break
	return {"hits": hits, "end": end}

## Power Pitcher: thrown item damage x1.5.
static func thrown_damage(m: Mon, dmg: int) -> int:
	if dmg > 0 and has(m, "power_pitcher"):
		return int(ceil(dmg * POWER_PITCHER_MUL))
	return dmg

# ------------------------------------------------------------------ traps / items / drops
## Trap Buster: 30% the trap breaks instead of going off.
static func trap_breaks(m: Mon, r: RandomNumberGenerator = null) -> bool:
	return has(m, "trap_buster") and _roll(r, TRAP_BUSTER_PCT)

## One-line form for Dungeon.trigger_trap: removes the trap and logs it; true = skip the trap effect.
static func try_bust_trap(d, m: Mon, p: Vector2i) -> bool:
	var f := _floor(d)
	if f == null or not f.traps.has(p) or not trap_breaks(m, f.rng):
		return false
	f.traps.erase(p)
	_say(d, "trap_buster", {"0": _nm(d, m)})
	if d != null and d is Object and "obj_layer" in d and d.obj_layer:
		d.obj_layer.queue_redraw()
	return true

## Survivalist: Belly filled by food x1.5.
static func food_bonus(m, amount: float) -> float:
	return amount * SURVIVALIST_MUL if has(m, "survivalist") else amount

## Survivalist: 50% Grimy Food does nothing bad.
static func grimy_resists(m, r: RandomNumberGenerator = null) -> bool:
	return has(m, "survivalist") and _roll(r, GRIMY_RESIST_PCT)

## Wise Healer: HP healed by moves / items +15%.
static func heal_amount(m, amount: int) -> int:
	if amount > 0 and has(m, "wise_healer"):
		return amount + amount * WISE_HEALER_PCT / 100
	return amount

## Nature Gifter (leader only): the other living teammates that also get the effect of the healing
## Berry / Seed the leader just ate. Logs Sky's line once. Empty for everyone else.
static func nature_gifter_targets(d, m: Mon, item_id: String) -> Array:
	if m == null or not m.is_leader or not has(m, "nature_gifter"):
		return []
	if not str(DB.items.get(item_id, {}).get("kind", "")) in NATURE_GIFTER_KINDS:
		return []
	var out: Array = []
	for o in _team(d):
		if o != m and o.hp > 0:
			out.append(o)
	if not out.is_empty():
		_say(d, "nature_gifter")
	return out

## Collector: a foe the Pokémon defeats drops an item 10% of the time (if it held none). Picks from the
## floor's item table through dungeon._pick_item.
static func collector_drop(d, killer: Mon, victim: Mon) -> bool:
	var f := _floor(d)
	if f == null or killer == null or victim == null or victim.is_team() or not killer.is_team():
		return false
	if not has(killer, "collector") or victim.held != "" or f.items.has(victim.pos):
		return false
	if not _roll(f.rng, COLLECTOR_PCT):
		return false
	var id := ""
	if d != null and d is Object and d.has_method("_pick_item"):
		var table := 0
		if "ddata" in d and "floor_i" in d:
			table = int(d.ddata.get("floors", [])[d.floor_i].get("items", 0)) if d.floor_i < d.ddata.get("floors", []).size() else 0
		id = str(d._pick_item(table))
	if id == "" or id == "poke":
		id = "oran"
	f.items[victim.pos] = {"id": id, "n": 1, "price": 0}
	_say(d, "collector", {"1": _nm(d, victim)})
	if "obj_layer" in d and d.obj_layer:
		d.obj_layer.queue_redraw()
	return true
