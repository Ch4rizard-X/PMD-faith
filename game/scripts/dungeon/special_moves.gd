class_name SpecialMoves
extends RefCounted
## The moves behind Red's Orbs (item_data.json moveID) and the weather moves: their effects from
## move_orb_actions_*.c, blow_away.c, hurl_orb.c, pounce_orb.c, trawl_orb.c, drought_orb.c, one_room_orb.c,
## switcher_orb.c and warp_target.c. Status moves come through Dungeon._status_move (run), the few
## damaging ones through Dungeon.do_attack (fixed_damage / after_hit).

const WEATHER_MOVES := {"Hail": "hail", "Sunny Day": "sunny", "Rain Dance": "rain", "Sandstorm": "sandstorm"}
const WEATHER_TURNS := 20             # gMoveWeatherDuration
const BLOW_AWAY_DMG := 5              # gBlowAwayDmgValue
const HURL_DMG := 10                  # gHurlOrbDmgValue
const WEATHER_TEXT := {"hail": "It started to hail!", "sunny": "The sunlight got bright!",
	"rain": "It started to rain!", "sandstorm": "A sandstorm kicked up!"}

## Orb item id -> the move it uses (Red item_data.json moveID).
const ORB_MOVES := {"hailorb": "Hail", "sunnyorb": "Sunny Day", "rainyorb": "Rain Dance", "evasionorb": "Double Team",
	"sandyorb": "Sandstorm", "rockyorb": "Rock Tomb", "snatchorb": "Snatch", "seetraporb": "See-Trap",
	"mugorb": "Takeaway", "reboundorb": "Rebound", "loborb": "Bloop Slash", "switcherorb": "Switcher",
	"blowbackorb": "Blowback", "warporb": "Warp", "transferorb": "Transfer", "sloworb": "Slow Down",
	"quickorb": "Speed Boost", "luminousorb": "Searchlight", "petrifyorb": "Petrify", "stayawayorb": "Stay Away",
	"pounceorb": "Pounce", "trawlorb": "Trawl", "cleanseorb": "Cleanse", "observerorb": "Observer",
	"decoyorb": "Decoy Maker", "slumberorb": "Siesta", "totterorb": "Totter", "twoedgeorb": "Two-Edge",
	"silenceorb": "No-Move", "escapeorb": "Escape", "scannerorb": "Scan", "radarorb": "Power-Ears",
	"droughtorb": "Drought", "trapbustorb": "Trap Buster", "rollcallorb": "Wild Call", "invisifyorb": "Invisify",
	"oneshotorb": "One-Shot", "identifyorb": "HP Gauge", "shockerorb": "Shocker", "sizebustorb": "Echo",
	"oneroomorb": "One-Room", "fillinorb": "Fill-In", "trapperorb": "Trapper", "itemizerorb": "Itemize",
	"hurlorb": "Hurl", "mobileorb": "Mobile", "stairsorb": "See Stairs", "longtossorb": "Long Toss",
	"pierceorb": "Pierce"}
## Damaging-category moves whose whole effect is special (no damage formula).
const FORCE_STATUS := ["Hurl", "Blowback"]
## Orbs that only work while held (Reviver Orb, Possess Orb) or do nothing when used.
const HELD_ONLY_ORBS := ["reviverorb", "possessorb"]
const NO_EFFECT_ORBS := ["tossorb", "beatuporb"]

## Moves whose targets this module picks itself (ranges the generic targeting doesn't cover).
const SELF_TARGETED := ["See-Trap", "Searchlight", "Trawl", "Cleanse", "Escape", "Scan", "Power-Ears", "Drought",
	"Trap Buster", "One-Room", "Fill-In", "Trapper", "See Stairs", "Pounce", "Wild Call", "HP Gauge",
	"Hail", "Sunny Day", "Rain Dance", "Sandstorm"]

## A status move with a special effect. Returns true when handled here.
static func run(d, m: Mon, mv: Dictionary, targets: Array) -> bool:
	var nm := str(mv.get("name", ""))
	var fs: FloorState = d.fs
	if WEATHER_MOVES.has(nm):
		set_weather(d, WEATHER_MOVES[nm], WEATHER_TURNS)
		return true
	match nm:
		"See-Trap":
			var r := fs.room_at(m.pos)
			var n := 0
			for p in fs.traps:
				if (r != 255 and fs.room_at(p) == r) or FloorState.cheb(p, m.pos) <= 2:
					if not fs.traps[p].get("seen", false):
						n += 1
					fs.traps[p].seen = true
			d._msg("Hidden traps were revealed!" if n > 0 else "There were no hidden traps.")
			_redraw(d)
		"Searchlight":
			for i in fs.explored.size():
				if fs.explored[i] == 0 and fs.terrain[i] != 0:
					fs.explored[i] = 2
			d._msg("The entire floor was revealed!")
			_redraw(d)
		"See Stairs":
			if fs.stairs.x >= 0:
				var i := fs.idx(fs.stairs)
				if fs.explored[i] == 0:
					fs.explored[i] = 2
			d._msg("The location of the stairs was revealed!")
			_redraw(d)
		"Scan":
			fs.set_meta("scanner", true)
			d._msg("The items on the floor were revealed!")
			_redraw(d)
		"Power-Ears":
			fs.set_meta("radar", true)
			d._msg("The foes on the floor were revealed!")
			_redraw(d)
		"HP Gauge":
			var who: Array = []
			for o in fs.mons:
				if o.hp > 0 and not o.is_team() and o.held != "":
					who.append(d._nm(o))
			d._msg(("Holding items: " + ", ".join(who)) if not who.is_empty() else "No Pokémon on this floor is holding an item.")
		"Trawl":
			_trawl(d, m)
		"Cleanse":
			var n := 0
			for b in Game.bag:
				if b.get("sticky", false):
					b.sticky = false
					n += 1
			for t in fs.team():
				if t.get_meta("held_sticky", false):
					t.set_meta("held_sticky", false)
					n += 1
			d._msg("The team's items were cleansed!" if n > 0 else "There were no sticky items.")
		"Escape":
			if bool(d.get_meta("shoplifted", false)):
				d._msg("%s can't escape!" % d._nm(m))
			elif m.is_team():
				d._msg("%s escaped!" % d._nm(m))
				await d.get_tree().create_timer(0.5).timeout
				d._end("escaped")
			else:
				d._msg("%s escaped!" % d._nm(m))
				d.cs_remove(m)
		"Drought":
			if fs.get_meta("fixed_floor", false):
				d._msg("But nothing happened.")
			else:
				var n2 := 0
				for i in fs.terrain.size():
					if fs.terrain[i] == 2:
						fs.terrain[i] = 1
						n2 += 1
				d._msg("All the %s dried up!" % ("magma" if fs.secondary == "lava" else "water") if n2 > 0 else "But nothing happened.")
				if n2 > 0:
					_rebuild_terrain(d)
		"Trap Buster":
			var r2 := fs.room_at(m.pos)
			var gone: Array = []
			for p in fs.traps:
				if (r2 != 255 and fs.room_at(p) == r2) or FloorState.cheb(p, m.pos) <= 1:
					gone.append(p)
			for p in gone:
				fs.traps.erase(p)
			d._msg("The traps in the room were destroyed!" if not gone.is_empty() else "There were no traps.")
			_redraw(d)
		"One-Room":
			if fs.get_meta("fixed_floor", false):
				d._msg("But nothing happened.")
			else:
				for y in range(1, fs.h - 1):
					for x in range(1, fs.w - 1):
						var i3 := fs.idx(Vector2i(x, y))
						if fs.terrain[i3] == 0:
							fs.terrain[i3] = 1
						fs.room[i3] = 0
				fs.rooms = [Rect2i(1, 1, fs.w - 2, fs.h - 2)]
				fs.red_reset_cache()
				d._msg("The floor turned into one big room!")
				_rebuild_terrain(d)
		"Fill-In":
			var q: Vector2i = m.pos + DB.DIRS[m.facing]
			if fs.inb(q) and fs.terrain_at(q) == 2:
				fs.terrain[fs.idx(q)] = 1
				d._msg("The %s was filled in!" % ("magma" if fs.secondary == "lava" else "water"))
				_rebuild_terrain(d)
			else:
				d._msg("But nothing happened.")
		"Trapper":
			if fs.room_at(m.pos) == 255 or fs.traps.has(m.pos) or m.pos == fs.stairs or fs.items.has(m.pos):
				d._msg("A trap can't be set here.")
			else:
				var kinds := ["trip", "mud", "sticky", "grimy", "summon", "warp", "gust", "spin", "slumber", "slow", "seal", "poison", "selfdestruct", "explosion", "ppzero", "pokemon", "spiked"]
				fs.traps[m.pos] = {"id": kinds[fs.rng.randi() % kinds.size()], "seen": true}
				d._msg("A trap was laid!")
				_redraw(d)
		"Pounce":
			_pounce(d, m)
		"Wild Call":
			var n4 := 0
			for o in fs.mons:
				if o != m and o.hp > 0 and o.is_team() == m.is_team() and not fs.is_foe(m, o):
					var q2: Vector2i = fs.free_tile_near(m.pos, o, 3)
					if q2.x >= 0:
						move_to(d, o, q2)
						n4 += 1
			d._msg("The team gathered around %s!" % d._nm(m) if n4 > 0 else "But nothing happened.")
		_:
			return await run_on_targets(d, m, mv, targets)
	d._update_hud()
	return true

## Effects aimed at the move's targets (room / front / user). Returns false for moves this module doesn't know.
static func run_on_targets(d, m: Mon, mv: Dictionary, targets: Array) -> bool:
	var nm := str(mv.get("name", ""))
	var fs: FloorState = d.fs
	var kinds := {"Slow Down": "slow", "Petrify": "petrified", "Siesta": "sleep", "Totter": "confused",
		"Observer": "paused", "Decoy Maker": "decoy", "No-Move": "muzzled", "Shocker": "cowering"}
	var selfs := {"Invisify": "invisible", "Mobile": "mobile", "Long Toss": "long_toss", "Pierce": "pierce",
		"Snatch": "snatch", "Rebound": "rebound"}
	if not (kinds.has(nm) or selfs.has(nm) or nm in ["Warp", "Transfer", "Stay Away", "Speed Boost", "Switcher", "Blowback", "Itemize", "Hurl"]):
		return false
	if selfs.has(nm):
		var k: String = selfs[nm]
		m.status[k] = TurnRules.red_turns(k, d.fs.rng, m, {"mobile": 0x7F, "long_toss": 0x7F, "pierce": 0x7F, "rebound": 10}.get(k, 10))
		var txt := {"invisible": "%s turned invisible!", "mobile": "%s became mobile! It can move through walls!",
			"long_toss": "%s can now throw items far!", "pierce": "Items thrown by %s will pierce through!",
			"snatch": "%s readied to snatch moves!", "rebound": "%s readied a counter!"}
		d._msg(txt[k] % d._nm(m))
		d._update_hud()
		return true
	if targets.is_empty():
		d._msg("But nothing happened.")
		return true
	for t in targets:
		if t.hp <= 0:
			continue
		match nm:
			"Speed Boost":
				t.status.fast = TurnRules.red_turns("fast", d.fs.rng, t, 8)
				d._msg("%s sped up!" % d._nm(t))
			"Warp":
				warp(d, t)
				d._msg("%s was warped!" % d._nm(t))
			"Stay Away":
				t.status.petrified = TurnRules.red_turns("petrified", d.fs.rng, t, 20)
				warp(d, t, true)
				d._msg("%s was petrified and sent away!" % d._nm(t))
			"Transfer":
				_transfer(d, m, t)
			"Switcher":
				if AbilityFx.anchored(t):
					d._msg("%s's Suction Cups kept it in place!" % d._nm(t))
					continue
				var a := m.pos
				move_to(d, m, t.pos)
				move_to(d, t, a)
				d._msg("%s swapped places with %s!" % [d._nm(m), d._nm(t)])
			"Blowback":
				await blow_away(d, m, t, m.facing)
			"Itemize":
				if t.is_team() or t.get_meta("boss", false) or Missions.is_client(t):
					d._msg("%s couldn't be turned into an item!" % d._nm(t))
				else:
					var p: Vector2i = t.pos
					var pool := ["oran", "apple", "ironthorn", "pecha", "sleepseed", "blastseed", "gravelerock", "reviver", "warpseed", "plainseed"]
					d.cs_remove(t)
					if not fs.items.has(p):
						fs.items[p] = {"id": pool[fs.rng.randi() % pool.size()], "n": 1, "price": 0}
					d._msg("%s turned into an item!" % t.name)
					_redraw(d)
			"Hurl":
				await _hurl(d, m, t)
			_:
				var key: String = kinds[nm]
				var why := HeldItems.blocks_status(t, key)
				if why != "":
					d._msg(why % d._nm(t))
					continue
				if t.has_status(key):
					d._msg("%s is already affected." % d._nm(t))
					continue
				t.status[key] = TurnRules.red_turns("observer_paused" if key == "paused" else key, fs.rng, t, 10)
				var txt2 := {"slow": "%s slowed down!", "petrified": "%s was petrified!", "sleep": "%s fell asleep!",
					"confused": "%s became confused!", "paused": "%s was paused!", "decoy": "%s became a decoy!",
					"muzzled": "%s was muzzled!", "cowering": "%s is cowering!"}
				d._msg(txt2[key] % d._nm(t))
	d._update_hud()
	return true

## Damage that ignores the normal formula (One-Shot, Two-Edge, Sizebust/Echo). -1: use the formula.
static func fixed_damage(d, m: Mon, t: Mon, nm: String) -> int:
	match nm:
		"One-Shot":
			if AbilityFx.has(t, "sturdy"):
				d._msg("%s's Sturdy blocked the one-hit KO!" % d._nm(t))
				return 0
			return t.hp
		"Two-Edge":
			return maxi(0, t.hp - 1)
		"Echo":
			return int(DB.species.get(t.sp, DB.species.get(t.sp.substr(0, 4), {})).get("rsize", 10))
	return -1

## After a damaging special move connected (Takeaway: take the held item; Two-Edge: halve the user's HP).
static func after_hit(d, m: Mon, t: Mon, nm: String) -> void:
	match nm:
		"Two-Edge":
			if m.hp > 0:
				d._hurt(m, m.hp / 2, null, false)
				d._msg("%s's HP was halved!" % d._nm(m))
		"Takeaway":
			if t.hp <= 0:
				return
			if AI.ability_is(t, "sticky hold"):
				return
			if t.held == "alertspecs":
				d._msg("%s was protected by its Specs!" % d._nm(t))
			elif m.held != "":
				d._msg("%s has an item already!" % d._nm(m))
			elif t.held == "":
				d._msg("%s doesn't have anything!" % d._nm(t))
			else:
				m.held = t.held
				t.held = ""
				d._msg("Got %s's item!" % d._nm(t))

# ------------------------------------------------------------------ helpers
static func set_weather(d, w: String, turns: int) -> void:
	var fs: FloorState = d.fs
	if not fs.has_meta("base_weather"):
		fs.set_meta("base_weather", fs.weather)
	fs.weather = w
	fs.set_meta("weather_turns", turns)
	d._msg(WEATHER_TEXT.get(w, "The weather changed!"))
	if d.has_method("_apply_weather_fx"):
		d._apply_weather_fx()

## End of each turn: a move's weather wears off, timed statuses from this module count down.
static func tick(d) -> void:
	var fs: FloorState = d.fs
	if fs.has_meta("weather_turns"):
		var n := int(fs.get_meta("weather_turns")) - 1
		if n <= 0:
			fs.remove_meta("weather_turns")
			fs.weather = str(fs.get_meta("base_weather", "clear"))
			fs.remove_meta("base_weather")
			d._msg("The weather returned to normal.")
			if d.has_method("_apply_weather_fx"):
				d._apply_weather_fx()
		else:
			fs.set_meta("weather_turns", n)
	for m in fs.mons:
		for k in ["rebound"]:          # the others count down in TurnRules
			var v := int(m.status.get(k, 0))
			if v > 0 and v < 0x7F:
				m.status[k] = v - 1

## WarpTarget: a random free floor tile (near_stairs: next to the stairs, Stayaway Orb).
static func warp(d, t: Mon, near_stairs := false) -> void:
	var fs: FloorState = d.fs
	if AbilityFx.anchored(t):
		d._msg("%s's Suction Cups kept it in place!" % d._nm(t))
		return
	var q := Vector2i(-1, -1)
	if near_stairs and fs.stairs.x >= 0:
		q = fs.free_tile_near(fs.stairs, t, 3)
	if q.x < 0:
		q = d._random_floor_tile()
	move_to(d, t, q)

static func move_to(d, t: Mon, q: Vector2i) -> void:
	var old: Vector2i = t.pos
	t.pos = q
	AI.on_moved(t, old, true)
	if t.visual:
		t.visual.position = d._px(q)
		d._walkers.erase(t.visual)
	if t.is_leader:
		d._reveal()
	_redraw(d)

## BlowAwayTarget: flies up to 10 tiles; hitting a wall or a Pokémon costs it (and that Pokémon) 5 HP.
static func blow_away(d, m: Mon, t: Mon, dir: int) -> void:
	var fs: FloorState = d.fs
	if AbilityFx.anchored(t):
		d._msg("%s's Suction Cups kept it in place!" % d._nm(t))
		return
	var dv: Vector2i = DB.DIRS[dir]
	var p: Vector2i = t.pos
	var bumped: Mon = null
	var hit_wall := false
	for i in 10:
		var q := p + dv
		if not fs.inb(q) or fs.is_wall(q):
			hit_wall = true
			break
		var o := fs.mon_at(q)
		if o and o != t:
			bumped = o
			break
		p = q
	d._msg("%s was blown away!" % d._nm(t))
	move_to(d, t, p)
	if hit_wall or bumped:
		d._hurt(t, BLOW_AWAY_DMG, m, true)
		d._msg("%s took %d damage!" % [d._nm(t), BLOW_AWAY_DMG])
		if bumped:
			d._hurt(bumped, BLOW_AWAY_DMG, m, true)
			d._msg("%s took %d damage!" % [d._nm(bumped), BLOW_AWAY_DMG])
			if bumped.hp <= 0:
				await d.faint(bumped, m)
		if t.hp <= 0:
			await d.faint(t, m)

## HandleHurlOrb: the target is thrown next to another visible foe; both take 10 damage.
static func _hurl(d, m: Mon, t: Mon) -> void:
	var fs: FloorState = d.fs
	if AbilityFx.anchored(t):
		d._msg("%s's Suction Cups kept it in place!" % d._nm(t))
		return
	if t.get_meta("boss", false) or not t.is_team() and int(DB.species.get(t.sp, {}).get("size", 1)) > 1:
		d._msg("%s couldn't be thrown!" % d._nm(t))
		return
	var other: Mon = null
	for o in fs.foes_of(m):
		if o != t and o.hp > 0 and fs.can_see(m, o.pos):
			other = o
			break
	if other == null:
		await blow_away(d, m, t, m.facing)
		return
	var q := fs.free_tile_near(other.pos, t, 1)
	if q.x >= 0:
		move_to(d, t, q)
	d._msg("%s was hurled at %s!" % [d._nm(t), d._nm(other)])
	for x in [t, other]:
		d._hurt(x, HURL_DMG, m, true)
		d._msg("%s took %d damage!" % [d._nm(x), HURL_DMG])
	for x in [other, t]:
		if x.hp <= 0:
			await d.faint(x, m)

## HandlePounceOrb: the user leaps forward until the tile before a Pokémon or a wall.
static func _pounce(d, m: Mon) -> void:
	var fs: FloorState = d.fs
	var dv: Vector2i = DB.DIRS[m.facing]
	var p: Vector2i = m.pos
	for i in 30:
		var q := p + dv
		if not fs.walkable(q, m) or fs.mon_at(q) != null:
			break
		p = q
	if p == m.pos:
		d._msg("But nothing happened.")
		return
	d._msg("%s pounced!" % d._nm(m))
	move_to(d, m, p)

## HandleTrawlOrb: every item on the floor flies to the tiles around the user (shop items count as stolen).
static func _trawl(d, m: Mon) -> void:
	var fs: FloorState = d.fs
	var spots: Array = []
	for r in range(0, 6):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if maxi(absi(x), absi(y)) != r:
					continue
				var q: Vector2i = m.pos + Vector2i(x, y)
				if fs.inb(q) and fs.terrain_at(q) == 1 and q != fs.stairs and not fs.traps.has(q):
					spots.append(q)
	var moved := 0
	var keys: Array = fs.items.keys()
	keys.sort_custom(func(a, b): return FloorState.cheb(a, m.pos) < FloorState.cheb(b, m.pos))
	var taken := {}
	for p in keys:
		if FloorState.cheb(p, m.pos) <= 5 and spots.has(p):
			taken[p] = true
	var out := {}
	for p in keys:
		if taken.has(p):
			out[p] = fs.items[p]
			continue
		for q in spots:
			if not taken.has(q):
				taken[q] = true
				var it: Dictionary = fs.items[p]
				if int(it.get("price", 0)) > 0:
					d.set_meta("shoplifted", true)
				out[q] = it
				moved += 1
				break
	fs.items = out
	d._msg("Items were pulled in!" if moved > 0 else "But nothing happened.")
	_redraw(d)

## TransferOrbAction: a wild Pokémon turns into another species of this floor with the same body size.
static func _transfer(d, m: Mon, t: Mon) -> void:
	if t.is_team() or t.get_meta("boss", false) or Missions.is_client(t):
		d._msg("%s couldn't be transformed!" % d._nm(t))
		return
	var fl: Dictionary = d.ddata.floors[d.floor_i] if d.floor_i < d.ddata.floors.size() else {}
	var size := int(DB.species.get(t.sp, {}).get("size", 1))
	var pool: Array = []
	for e in fl.get("pk", []):
		var sp := str(e[0])
		if sp != t.sp and DB.species.has(sp) and int(DB.species[sp].get("size", 1)) == size:
			pool.append(sp)
	if pool.is_empty():
		d._msg("%s couldn't be transformed!" % d._nm(t))
		return
	var sp2: String = pool[d.fs.rng.randi() % pool.size()]
	var nw: Mon = DB.make_mon(sp2, t.level, t.side, {})
	var old_name: String = d._nm(t)
	t.sp = nw.sp
	t.name = nw.name
	t.types = nw.types
	t.ability = nw.ability
	t.moves = nw.moves
	t.max_hp = nw.max_hp
	t.hp = mini(t.hp, t.max_hp)
	t.atk = nw.atk
	t.def = nw.def
	t.spa = nw.spa
	t.spd = nw.spd
	if d.has_method("_refresh_mon_visual"):
		d._refresh_mon_visual(t)
	d._msg("%s transformed into %s!" % [old_name, t.name])

static func _redraw(d) -> void:
	if d.obj_layer:
		d.obj_layer.queue_redraw()
	if d.red_map:
		d.red_map.refresh()

static func _rebuild_terrain(d) -> void:
	if d.has_method("_redraw_terrain"):
		d._redraw_terrain()
	_redraw(d)
