class_name EosItems
extends RefCounted
## Explorers of Sky / PMD: Explorers Remixed items (data/items.json entries with "eos_added").
## Held items carry "eos": [effects]; exclusive items carry "excl": {for: [species], types: [types], eff: [effects]}
## and, as in EoS, work while they sit in the Treasure Bag for the team members they are made for.
## The effects come from the item descriptions (gen_eos_items.py); this file is what they do.

const STAT_BOOST := 6                 # "slightly boosts" (Red's bands give +12; EoS exclusives are smaller)
const HIT_CHANCE := 12                # "may ..." when attacked
const MAXHP_BOOST := 5

static var fs: FloorState = null      # the current floor (weather checks); set by the dungeon each turn
static var _cache := {}               # mon uid -> [frame, effects]

## Every effect working for m right now: its held item's, plus the exclusive items in the Treasure Bag for it.
static func effects(m: Mon) -> Array:
	if m == null:
		return []
	var f := "%d|%s|%d" % [Engine.get_process_frames(), m.held, Game.bag.size()]
	var c = _cache.get(m.uid)
	if c != null and str(c[0]) == f:
		return c[1]
	var out: Array = []
	if m.held != "":
		var I: Dictionary = DB.items.get(m.held, {})
		for e in I.get("eos", []):
			out.append(e)
	if m.is_team():
		var base := m.sp.substr(0, 4)
		for b in Game.bag:
			var J: Dictionary = DB.items.get(str(b.id), {})
			var x = J.get("excl")
			if x == null:
				continue
			var ok: bool = base in x.get("for", [])
			if not ok:
				for t in x.get("types", []):
					if t in m.types:
						ok = true
			if ok:
				for e in x.get("eff", []):
					out.append(e)
	_cache[m.uid] = [f, out]
	return out

static func has(m: Mon, key: String) -> bool:
	for e in effects(m):
		if e.has(key):
			return true
	return false

static func value(m: Mon, key: String, default = null):
	for e in effects(m):
		if e.has(key):
			return e[key]
	return default

## Stat boost to add to m's attack / defense side for this stat ("atk", "def", "spa", "spd").
static func stat(m: Mon, k: String) -> int:
	var n := 0
	for e in effects(m):
		if e.has("stat"):
			n += int(e.stat.get(k, 0)) * STAT_BOOST
	return n

## Floor start: max HP from exclusives, a full heal / 1 PP back on a new floor, Mobile for Spirit Veil.
static func floor_start(d, m: Mon) -> void:
	var hp_up := 0
	for e in effects(m):
		if e.has("maxhp"):
			hp_up += MAXHP_BOOST
	var had := int(m.get_meta("eos_hp_up", 0))
	if hp_up != had:
		m.max_hp += hp_up - had
		m.hp = clampi(m.hp + maxi(0, hp_up - had), 1, m.max_hp)
		m.set_meta("eos_hp_up", hp_up)
	if has(m, "floor_heal"):
		m.hp = m.max_hp
	if has(m, "floor_pp"):
		for mv in m.moves:
			mv.pp = mini(int(mv.get("max_pp", mv.pp)), int(mv.pp) + 1)
	if has(m, "mobile"):
		m.status.mobile = 0x7F

## Statuses the items keep away. Returns a message or "".
static func blocks_status(t: Mon, key: String) -> String:
	for e in effects(t):
		if e.has("protect"):
			var w = e.get("weather")
			if w != null and fs != null and str(fs.weather) != str(w):
				continue
			var lst: Array = e.protect
			if "all" in lst or key in lst or (key == "badpoison" and "poison" in lst):
				return "%s's item protected it!"
		if e.has("weather_protect") and fs != null and str(fs.weather) == str(e.weather_protect):
			return "%s's item protected it!"
	return ""

## Absorbs (heals) or is immune to a move type. Returns "absorb", "immune" or "".
static func type_guard(t: Mon, move_type: String) -> String:
	for e in effects(t):
		if str(e.get("absorb", "")) == move_type:
			return "absorb"
		if str(e.get("immune", "")) == move_type:
			return "immune"
	return ""

## Damage factor from the attacker's and the target's items.
static func damage_factor(att: Mon, def: Mon, physical: bool, move_name: String) -> float:
	var f := 1.0
	f *= float(value(att, "dmg_mult", 1.0))
	f *= float(value(def, "dmg_taken", 1.0))
	if physical and has(def, "half_physical"):
		f *= 0.5
	if not physical and has(def, "half_special"):
		f *= 0.5
	if move_name in AbilityFx.EXPLOSION_MOVES:
		f *= float(value(def, "explosion", 1.0))
	if has(att, "ignore_screens") and ((physical and int(def.status.get("reflect", 0)) > 0) or (not physical and int(def.status.get("light_screen", 0)) > 0)):
		f *= 2.0
	return f

## When m's attack damaged t: the target's items strike back (status 12%, counter, sealed move, PP back,
## Exp. on hit, Invisible / speed when hit, warp at low HP).
static func after_damaged(d, m: Mon, t: Mon, dmg: int, physical: bool, move_name: String) -> void:
	if m == null or t == null or m == t or dmg <= 0:
		return
	var rng: RandomNumberGenerator = d.fs.rng
	var adjacent := FloorState.cheb(m.pos, t.pos) <= 1
	for e in effects(t):
		if e.has("on_hit") and adjacent and m.hp > 0 and rng.randi_range(0, 99) < int(e.get("ch", HIT_CHANCE)):
			var lst: Array = e.on_hit
			var key: String = lst[rng.randi() % lst.size()]
			if key == "slow":
				m.status.slow = TurnRules.red_turns("slow", rng, m, 8)
				d._msg("%s slowed down!" % d._nm(m))
			elif HeldItems.blocks_status(m, key) == "" and not m.has_status(key):
				m.status[key] = TurnRules.red_turns(key, rng, m, {"blinker": 10, "infatuated": 6, "nightmare": 5}.get(key, 10))
				d._msg("%s's item gave %s a status problem!" % [d._nm(t), d._nm(m)])
		if e.has("counter") and physical and adjacent and m.hp > 0:
			var back := maxi(1, int(dmg * float(e.counter)))
			d._hurt(m, back, t, true)
			d._msg("%s counterstruck for %d damage!" % [d._nm(t), back])
			if m.hp <= 0:
				await d.faint(m, t)
				return
		if e.has("seal_on_hit") and move_name != "" and rng.randi_range(0, 99) < HIT_CHANCE:
			var slot: Dictionary = m.move_by_name(move_name)
			if not slot.is_empty():
				slot.disabled = 5
				d._msg("%s's %s was sealed!" % [d._nm(m), move_name])
		if e.has("pp_on_hit") and t.hp > 0 and rng.randi_range(0, 99) < HIT_CHANCE * 2:
			var low: Dictionary = {}
			for mv in t.moves:
				if low.is_empty() or int(mv.pp) < int(low.pp):
					low = mv
			if not low.is_empty():
				low.pp = mini(int(low.get("max_pp", low.pp)), int(low.pp) + 3)
		if e.has("exp_on_hit") and t.hp > 0 and t.is_team():
			t.set_meta("joy_exp", int(t.get_meta("joy_exp", 0)) + dmg)
		if e.has("invis_on_hit") and t.hp > 0 and rng.randi_range(0, 99) < HIT_CHANCE * 2:
			t.status.invisible = TurnRules.red_turns("invisible", rng, t, 10)
			d._msg("%s turned invisible!" % d._nm(t))
		if e.has("speed_on_hit") and t.hp > 0 and rng.randi_range(0, 99) < HIT_CHANCE * 2:
			t.status.fast = TurnRules.red_turns("fast", rng, t, 8)
		if e.has("warp_low") and t.hp > 0 and t.hp * 4 <= t.max_hp and rng.randi_range(0, 99) < 50:
			SpecialMoves.warp(d, t)
			d._msg("%s warped away!" % d._nm(t))

## "May prevent fainting": 20% to survive with 1 HP.
static func endure(t: Mon, rng: RandomNumberGenerator) -> bool:
	return has(t, "endure") and rng.randi_range(0, 99) < 20

## End of turn: Flame Orb / Toxic Orb hurt their holder with a status.
static func end_of_turn(d) -> void:
	fs = d.fs
	for m in d.fs.mons:
		if m.hp <= 0:
			continue
		var s = value(m, "holder_status")
		if s != null and not m.has_status(str(s)) and not m.has_status("burn") and not m.has_status("poison") and not m.has_status("badpoison"):
			if HeldItems.blocks_status(m, str(s)) == "":
				m.status[str(s)] = 20
				d._msg("%s was %s by its %s!" % [d._nm(m), "burned" if s == "burn" else "badly poisoned", DB.item_name(m.held)])

## Weather-based speed / evasion from items (folded into the meta AbilityFx sets each turn).
static func weather_speed(m: Mon, weather: String) -> bool:
	return str(value(m, "weather_speed", "")) == weather and weather != ""

static func weather_eva(m: Mon, weather: String) -> bool:
	return str(value(m, "weather_eva", "")) == weather and weather != ""

## A wild Pokémon fainted to the team: Amulet Coin / money exclusives may drop Poké.
static func on_ko(d, t: Mon, killer: Mon) -> void:
	if t.is_team() or killer == null:
		return
	var any := false
	for m in d.fs.team():
		if has(m, "money"):
			any = true
	if any and d.fs.rng.randi_range(0, 99) < 50 and not d.fs.items.has(t.pos):
		d.fs.items[t.pos] = {"id": "poke", "n": 10 * (d.floor_i + 1) + d.fs.rng.randi_range(0, 40), "price": 0}
		d.obj_layer.queue_redraw()

# ======================================================================== where the new items turn up
## Not cosmetic key items (story treasures, instruments, Unown stones, tickets, boxes that need Xatu).
const NO_DROP := ["wonderegg", "prizeticket", "silverticket", "goldticket", "prismticket", "mysterypart", "secretslab",
	"gracidea", "skygift", "lostloot", "coronetrock", "mossyrock"]
const TREASURES := ["goldenmask", "ambertear", "icyflute", "fierydrum", "terracymbal", "aquamonica", "rockhorn",
	"grasscornet", "skymelodica", "goldthorn", "rarefossil", "goldenapple"]
## Held by the leader: easier recruiting (EoS treasures). Instruments only for their type.
const RECRUIT_ITEMS := {"goldenmask": ["", 150], "ambertear": ["", 200], "icyflute": ["Ice", 150], "fierydrum": ["Fire", 150],
	"terracymbal": ["Ground", 150], "aquamonica": ["Water", 150], "rockhorn": ["Rock", 150], "grasscornet": ["Grass", 150],
	"skymelodica": ["Flying", 150]}

static func recruit_bonus(r: Mon, t: Mon) -> int:
	if r == null or not r.is_leader or not RECRUIT_ITEMS.has(r.held):
		return 0
	var e: Array = RECRUIT_ITEMS[r.held]
	if str(e[0]) != "" and not (str(e[0]) in t.types):
		return 0
	return int(e[1])
const RARITY_WEIGHT := {1: 6, 2: 2, 3: 1}

# ======================================================================== treasure boxes
## EoS boxes (Xatu appraises them for 150 Poké). Here the Kecleon shop opens them.
const BOXES := ["gorgeousbox", "heavybox", "shinybox", "niftybox", "daintybox", "glitterybox", "prettybox", "deluxebox",
	"lightbox", "cutebox", "hardbox", "sinisterbox"]
const APPRAISE_FEE := 150
const BOX_RARE := ["goldenseed", "joyseed", "goldribbon", "rainbowgummi", "dxgummi", "wandergummi", "amuletcoin",
	"goldenmask", "ambertear", "goldenapple", "rarefossil", "empowerseed", "empowerseed"]

static func is_box(id: String) -> bool:
	return id in BOXES

## What a box holds: mostly an exclusive item (1★ 50%, 2★ 35%, 3★ 15%), usually one a Pokémon on the team
## or in a Friend Area can use; sometimes a rare item instead.
static func open_box(rng: RandomNumberGenerator) -> String:
	if rng.randi_range(0, 99) < 20:
		var rare: Array = BOX_RARE.filter(func(k): return DB.items.has(k))
		if not rare.is_empty():
			return str(rare[rng.randi_range(0, rare.size() - 1)])
	var r := rng.randi_range(0, 99)
	var tier := 1 if r < 50 else (2 if r < 85 else 3)
	var sp := {}
	var types := {}
	for e in Game.team + Game.friends:
		var s := str(e.get("sp", "")).substr(0, 4)
		sp[s] = true
		for t in DB.species.get(s, {}).get("types", []):
			types[t] = true
	var mine: Array = []
	var any: Array = []
	for k in DB.items:
		var x = DB.items[k].get("excl")
		if x == null or x.get("eff", []).is_empty() or int(DB.items[k].get("rarity", 3)) != tier:
			continue
		any.append(k)
		for s2 in x.get("for", []):
			if sp.has(s2):
				mine.append(k)
		for t2 in x.get("types", []):
			if types.has(t2):
				mine.append(k)
	var pool := mine if not mine.is_empty() and rng.randi_range(0, 99) < 75 else any
	if pool.is_empty():
		return "goldenseed"
	return str(pool[rng.randi_range(0, pool.size() - 1)])
static var _pool := []                # [id, weight, min_level]

static func _drop_pool() -> Array:
	if not _pool.is_empty():
		return _pool
	for k in DB.items:
		var I: Dictionary = DB.items[k]
		if not I.get("eos_added", 0) or I.get("kind", "") == "exclusive" or k in NO_DROP:
			continue
		var nm := str(I.get("name", ""))
		if nm.ends_with("Stone") and nm.length() <= 7:
			continue
		var cat := str(I.get("red_cat", ""))
		var w := 10
		var lv := 1
		match cat:
			"tms_hms":
				w = 3
				lv = 20
			"orbs":
				w = 8
				lv = 10
			"held_items":
				w = 6
				lv = 8
			"berries_seeds_vitamins":
				w = 8
			"food_gummies":
				w = 6
			"other":
				w = 2
		if k in ["goldenseed", "amuletcoin", "wonderchest", "miraclechest", "iqbooster", "spaceglobe"]:
			w = 1
			lv = 25
		if k in TREASURES:                     # very rare treasures, deep floors only
			w = 1
			lv = 35
		if k in BOXES:                         # treasure boxes, opened by Kecleon
			w = 2
			lv = 15
		_pool.append([k, w, lv])
	return _pool

## A floor item roll in any dungeon: 3% of the time an Explorers of Sky item suited to the floor's level,
## 3% an exclusive item for one of the Pokémon living on this floor (rarer the more stars it has).
static func floor_pick(d, rng: RandomNumberGenerator) -> String:
	var fl: Dictionary = d.ddata.floors[mini(d.floor_i, d.ddata.floors.size() - 1)] if d.ddata.has("floors") else {}
	var pk: Array = fl.get("pk", [])
	var lv := 1
	if not pk.is_empty():
		var lvs: Array = pk.map(func(e): return int(e[1]))
		lvs.sort()
		lv = int(lvs[lvs.size() / 2])
	var r := rng.randi_range(0, 99)
	if r < 3:
		var pool: Array = _drop_pool().filter(func(p): return lv >= int(p[2]))
		return str(d._pick_weighted(pool)) if not pool.is_empty() else ""
	if r < 6 and not pk.is_empty():
		var sp := {}
		var types := {}
		for e in pk:
			var s := str(e[0]).substr(0, 4)
			sp[s] = true
			for t in DB.species.get(s, {}).get("types", []):
				types[t] = true
		var cands: Array = []
		for k in DB.items:
			var x = DB.items[k].get("excl")
			if x == null or x.get("eff", []).is_empty():
				continue
			var ok := false
			for s2 in x.get("for", []):
				if sp.has(s2):
					ok = true
			for t2 in x.get("types", []):
				if types.has(t2):
					ok = true
			if ok:
				cands.append([k, int(RARITY_WEIGHT.get(int(DB.items[k].get("rarity", 3)), 1))])
		if not cands.is_empty():
			return str(d._pick_weighted(cands))
	return ""
