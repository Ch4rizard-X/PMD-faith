class_name AbilityFx
extends RefCounted
## Red's abilities outside the damage formula (Combat has the damage ones: Levitate, Guts, Huge/Pure Power,
## Intimidate, Thick Fat, Wonder Guard, Flash Fire, Volt/Water Absorb, the pinch abilities, Battle/Shell
## Armor, Sand Veil, Hustle, Compoundeyes, Marvel Scale, Plus/Minus).
## Sources: dungeon_damage.c (contact abilities, Sturdy), dungeon_move_util.c (their effects, Serene Grace,
## Shield Dust), move_orb_effects_1/2.c (status immunities, Early Bird, Synchronize, Hyper Cutter, Keen Eye,
## Clear Body/White Smoke via dungeon_logic.c), dungeon_turn_effects.c (Shed Skin, Speed Boost),
## dungeon_logic.c (Swift Swim, Chlorophyll), dungeon_misc.c (weather abilities, Trace, Color Change, Truant,
## Forecast), dungeon_move.c (Pressure, Soundproof, Illuminate), explosion.c (Damp), blow_away.c and the
## warp / switcher / hurl / pounce code (Suction Cups), move_orb_actions_2.c (Rock Head).

const CONTACT_CHANCE := 12            # gStatic/PoisonPoint/EffectSpore/FlameBody/CuteCharm/Stench/ArenaTrap/ShadowTag/MagnetPull
const SHED_SKIN_CHANCE := 50          # gShedSkinActivateChance
const SPEED_BOOST_TURNS := 250        # gSpeedBoostActivationFrame
const STENCH_TURNS := 3               # gStenchTerrifiedTurnsNo
const SOUND_MOVES := ["Growl", "Roar", "Metal Sound", "Sing", "Grasswhistle", "Supersonic", "Perish Song",
	"Screech", "Hyper Voice", "Snore", "Heal Bell"]
const EXPLOSION_MOVES := ["Selfdestruct", "Explosion"]

static func has(m: Mon, a: String) -> bool:
	return m != null and AI.ability_is(m, a)

## A status this Pokémon's ability keeps away. Returns the message ("%s" = its name) or "".
static func blocks_status(t: Mon, key: String) -> String:
	match key:
		"sleep", "yawn", "nightmare", "napping":
			if has(t, "insomnia"):
				return "%s's Insomnia prevents sleep!"
			if has(t, "vital spirit"):
				return "%s's Vital Spirit prevents sleep!"
		"para":
			if has(t, "limber"):
				return "%s's Limber prevents paralysis!"
		"confused":
			if has(t, "own tempo"):
				return "%s's Own Tempo prevents confusion!"
		"infatuated":
			if has(t, "oblivious"):
				return "%s's Oblivious prevents infatuation!"
		"poison", "badpoison":
			if has(t, "immunity"):
				return "%s's Immunity prevents poisoning!"
		"frozen":
			if has(t, "magma armor"):
				return "%s's Magma Armor prevents freezing!"
		"burn":
			if has(t, "water veil"):
				return "%s's Water Veil prevents burns!"
		"cringe":
			if has(t, "inner focus"):
				return "%s's Inner Focus prevents cringing!"
	return ""

## A stat drop the ability stops (Flower Veil is checked by the caller with the floor). Returns the message or "".
static func blocks_stat_drop(t: Mon, k: String) -> String:
	if has(t, "clear body") or has(t, "white smoke"):
		return "%s's stats can't be lowered!"
	if k == "atk" and has(t, "hyper cutter"):
		return "%s's Hyper Cutter prevents its Attack from dropping!"
	if k == "acc" and has(t, "keen eye"):
		return "%s's Keen Eye prevents its accuracy from dropping!"
	return ""

## Early Bird: sleep lasts half as long (at least 1 turn).
static func sleep_turns(t: Mon, turns: int) -> int:
	if has(t, "early bird") and turns < 0x7F:
		return maxi(1, turns / 2)
	return turns

## Serene Grace doubles a secondary effect's chance; Shield Dust on the target blocks it.
static func secondary_chance(m: Mon, ch: float) -> float:
	return minf(1.0, ch * 2.0) if has(m, "serene grace") else ch

static func blocks_secondary(m: Mon, t: Mon) -> bool:
	return t != m and has(t, "shield dust")

## Rock Head: no recoil.
static func no_recoil(m: Mon) -> bool:
	return has(m, "rock head")

## Soundproof against a sound move.
static func soundproof(t: Mon, move_name: String) -> bool:
	return move_name in SOUND_MOVES and has(t, "soundproof")

## Damp anywhere on the floor stops Selfdestruct / Explosion (and explosion traps).
static func damp_on_floor(fs: FloorState) -> bool:
	for m in fs.mons:
		if m.hp > 0 and has(m, "damp"):
			return true
	return false

## Suction Cups: can't be blown away, warped, switched or hurled.
static func anchored(t: Mon) -> bool:
	return has(t, "suction cups")

## Sturdy blocks one-hit KO damage (9999 / One-Shot Orb).
static func sturdy(t: Mon, dmg: int) -> bool:
	return dmg >= 9999 and has(t, "sturdy")

## Pressure: a move that reaches a foe with Pressure costs 1 more PP.
static func pressure_extra(m: Mon, targets: Array, fs: FloorState) -> int:
	for t in targets:
		if t != m and t.hp > 0 and fs.is_foe(m, t) and has(t, "pressure"):
			return 2 if EosItems.has(t, "pressure_boost") else 1
	return 0

## After m's attack dealt dmg to t (dungeon_damage.c, attacker next to target): Rough Skin, Mini Counter
## (Rebound Orb), Arena Trap / Shadow Tag / Magnet Pull, Static, Poison Point, Effect Spore, Flame Body,
## Cute Charm, Stench (12% each), then Trace and Color Change on the target.
static func after_damaged(d, m: Mon, t: Mon, dmg: int, physical: bool, move_type: String) -> void:
	var fs: FloorState = d.fs
	if m == null or t == null or m == t or m.hp <= 0:
		return
	if dmg > 0 and t.hp > 0 and has(t, "berserk") and t.hp * 2 < t.max_hp and (t.hp + dmg) * 2 >= t.max_hp:
		t.stages.spa = mini(20, int(t.stages.get("spa", 10)) + 1)
		d._msg("%s's Berserk raised its Sp. Atk!" % d._nm(t))
	var adjacent := FloorState.cheb(m.pos, t.pos) <= 1
	if adjacent and dmg > 0:
		var ret := 0
		if int(t.status.get("rebound", 0)) > 0 and physical:
			ret += 1
		if has(t, "rough skin"):
			ret += 2
		if ret > 0:
			var back := maxi(1, dmg * ret / 4)
			d._msg("%s was hurt by the counterattack!" % d._nm(m))
			d._hurt(m, back, t, true)
			d._msg("%s took %d damage!" % [d._nm(m), back])
			if m.hp <= 0:
				await d.faint(m, t)
				return
		var roll := func() -> bool: return fs.rng.randi_range(0, 99) < CONTACT_CHANCE
		if has(t, "arena trap") and not AI.is_type(m, "Flying") and not has(m, "levitate") and roll.call():
			_status(d, m, "shadow_hold", 10, "Arena Trap prevents movement!")
		if has(t, "shadow tag") and roll.call():
			_status(d, m, "shadow_hold", 10, "Shadow Tag prevents movement!")
		if has(t, "magnet pull") and AI.is_type(m, "Steel") and roll.call():
			_status(d, m, "shadow_hold", 10, "Magnet Pull prevents movement!")
		if has(t, "static") and physical and roll.call():
			_status(d, m, "para", 20, "Static caused paralysis!")
		if has(t, "poison point") and roll.call():
			_status(d, m, "poison", 20, "Poison Point struck!")
		if has(t, "effect spore") and physical and roll.call():
			match fs.rng.randi_range(0, 2):
				0: _status(d, m, "poison", 20, "Effect Spore scattered spores!")
				1: _status(d, m, "para", 20, "Effect Spore scattered spores!")
				2: _status(d, m, "sleep", sleep_turns(m, fs.rng.randi_range(3, 6)), "Effect Spore scattered spores!")
		if has(t, "flame body") and roll.call():
			_status(d, m, "burn", 20, "Flame Body caused a burn!")
		if has(t, "cute charm") and physical and roll.call():
			_status(d, m, "infatuated", 10, "Cute Charm caused infatuation!")
		if has(t, "stench") and roll.call():
			m.status.terrified = STENCH_TURNS
			d._msg("A horrid stench billowed out!")
	if t.hp > 0:
		if has(t, "trace") and str(t.ability).to_lower().replace("-", " ") == "trace":
			var pool: Array = [m.ability]
			var a2 = m.get("ability2")
			if a2 != null and str(a2) != "":
				pool.append(str(a2))
			pool = pool.filter(func(x): return str(x) != "" and str(x).to_lower() != "trace")
			if not pool.is_empty():
				t.ability = str(pool[fs.rng.randi() % pool.size()])
				d._msg("%s traced %s's %s!" % [d._nm(t), d._nm(m), t.ability.capitalize().replace("-", " ")])
		if has(t, "color change") and dmg > 0 and move_type != "" and move_type != "None" and not (move_type in t.types):
			t.types = [move_type]
			d._msg("%s's Color Change made it the %s type!" % [d._nm(t), move_type])
		if has(t, "illuminate"):
			d.spawn_timer = 9999                   # wildMonSpawnFrames = 999: a wild Pokémon appears soon

static func _status(d, m: Mon, key: String, turns: int, text: String) -> void:
	var why := blocks_status(m, key)
	if why == "":
		why = HeldItems.blocks_status(m, key)
	if why != "" or m.has_status(key):
		return
	d._msg(text)
	m.status[key] = TurnRules.red_turns(key, d.fs.rng, m, turns)
	if key == "sleep" and m.visual:
		m.visual.play("Idle")

## Synchronize (move_orb_effects_1.c): when t is burned / poisoned / paralyzed, Pokémon next to it that
## treat it as an enemy get the same status.
static func synchronize(d, t: Mon, key: String, turns: int) -> void:
	if not key in ["burn", "poison", "badpoison", "para"] or not has(t, "synchronize"):
		return
	var fs: FloorState = d.fs
	for k in 8:
		var o := fs.mon_at(t.pos + DB.DIRS[k])
		if o and o != t and o.hp > 0 and fs.is_foe(t, o) and not o.has_status(key) \
				and blocks_status(o, key) == "" and HeldItems.blocks_status(o, key) == "":
			o.status[key] = turns
			d._msg("%s's Synchronize shared the status with %s!" % [d._nm(t), d._nm(o)])

## Start of a floor and end of every turn: weather from abilities (Drizzle / Sand Stream / Drought; Air Lock
## and Cloud Nine nullify it), Forecast, Swift Swim / Chlorophyll speed, Shed Skin, Speed Boost.
static func end_of_turn(d) -> void:
	var fs: FloorState = d.fs
	update_weather(d)
	await end_of_turn_gen4(d)
	for m in fs.mons.duplicate():
		if m.hp <= 0:
			continue
		if has(m, "shed skin") and fs.rng.randi_range(0, 99) < SHED_SKIN_CHANCE:
			var any := false
			for k in ["poison", "badpoison", "burn", "para", "sleep", "confused", "frozen"]:
				if int(m.status.get(k, 0)) > 0:
					m.status[k] = 0
					any = true
			if any and (m.is_team() or fs.can_see(fs.leader, m.pos)):
				d._msg("%s's Shed Skin cured its status!" % d._nm(m))
		if has(m, "speed boost"):
			var n := int(m.get_meta("speed_boost_turns", 0)) + 1
			if n >= SPEED_BOOST_TURNS:
				n = 0
				m.status.fast = 0x7F
				if m.is_team() or fs.can_see(fs.leader, m.pos):
					d._msg("%s's Speed Boost raised its speed!" % d._nm(m))
			m.set_meta("speed_boost_turns", n)

static func update_weather(d) -> void:
	var fs: FloorState = d.fs
	if not fs.has_meta("weather_turns"):         # a weather move's weather wins while it lasts
		if not fs.has_meta("natural_weather"):
			fs.set_meta("natural_weather", fs.weather)
		var w := str(fs.get_meta("natural_weather"))
		for m in fs.mons:
			if m.hp <= 0:
				continue
			if has(m, "snow warning"):
				w = "hail"
			elif has(m, "drizzle"):
				w = "rain"
			elif has(m, "sand stream"):
				w = "sandstorm"
			elif has(m, "drought"):
				w = "sunny"
		for m in fs.mons:                         # Primal weather beats the others
			if m.hp > 0 and has(m, "primordial sea"):
				w = "rain"
			elif m.hp > 0 and has(m, "desolate land"):
				w = "sunny"
		for m in fs.mons:
			if m.hp > 0 and (has(m, "air lock") or has(m, "cloud nine") or has(m, "delta stream")):
				w = "clear"
		fs.weather = w
	for m in fs.mons:
		var fast := 0
		if (has(m, "swift swim") and fs.weather == "rain") or (has(m, "chlorophyll") and fs.weather == "sunny"):
			fast = 1
		m.set_meta("weather_speed", fast)
		if has(m, "forecast"):
			var ty: String = {"sunny": "Fire", "rain": "Water", "hail": "Ice"}.get(fs.weather, "Normal")
			if m.types != [ty]:
				m.types = [ty]

# ======================================================================== Explorers of Sky / Remixed abilities
## The added Pokémon carry the abilities PMD: Explorers Remixed 2.3 gives them (its monster.md). EoS's Gen 4
## abilities and Remixed's custom ones are done here from their in-game descriptions (Remixed's text_e.str);
## a few with no dungeon meaning (Frisk, Honey Gather, Run Away-like ones) only have their name.

const PUNCH_MOVES := ["Comet Punch", "Mega Punch", "Fire Punch", "Ice Punch", "Thunderpunch", "Dizzy Punch",
	"Mach Punch", "Dynamicpunch", "Focus Punch", "Meteor Mash", "Shadow Punch", "Sky Uppercut", "Hammer Arm",
	"Bullet Punch", "Drain Punch", "Power-Up Punch"]
const BITE_MOVES := ["Bite", "Crunch", "Fire Fang", "Ice Fang", "Thunder Fang", "Poison Fang", "Hyper Fang",
	"Super Fang", "Psychic Fangs", "Jaw Lock"]
const PULSE_MOVES := ["Water Pulse", "Dark Pulse", "Dragon Pulse", "Aura Sphere", "Heal Pulse", "Origin Pulse"]
const POWDER_MOVES := ["Sleep Powder", "Stun Spore", "Poisonpowder", "Spore", "Powder", "Rage Powder", "Cotton Spore"]
const TYPE_SKINS := {"pixilate": "Fairy", "refrigerate": "Ice", "aerilate": "Flying", "galvanize": "Electric", "dragonize": "Dragon"}

## The type a move really has for this user (Normalize, the -ate abilities, Wyrmweave, Liquid Voice) and the
## power factor that goes with it. Returns [type, factor].
static func move_type(m: Mon, move_name: String, t: String) -> Array:
	if has(m, "normalize") and move_name != "":
		return ["Normal", 1.0]
	for a in TYPE_SKINS:
		if t == "Normal" and move_name != "" and has(m, a):
			return [TYPE_SKINS[a], 1.2]
	if t == "Psychic" and has(m, "wyrmweave"):
		return ["Dragon", 1.2]
	if move_name in SOUND_MOVES and has(m, "liquid voice"):
		return ["Water", 1.0]
	return [t, 1.0]

## Protean: the user turns into its move's type before using it.
static func protean(d, m: Mon, t: String) -> void:
	if has(m, "protean") and t != "" and t != "None" and m.types != [t]:
		m.types = [t]
		d._msg("%s's Protean made it become the %s type!" % [d._nm(m), t])

## Multi-hit moves (hits 0 in moves.json): 2 to 5 hits; Skill Link always 5.
static func multi_hits(m: Mon, rng: RandomNumberGenerator) -> int:
	if has(m, "skill link"):
		return 5
	return [2, 2, 3, 3, 4, 5][rng.randi() % 6]

## Damage changes after the formula. Returns the new damage.
static func modify_damage(d, att: Mon, def: Mon, mv: Dictionary, move_name: String, t: String, dmg: int, res: Dictionary, skin: float) -> int:
	if dmg <= 0:
		return dmg
	var f := skin
	var fs: FloorState = d.fs
	var p := int(mv.get("p", 0))
	var physical := bool(res.get("physical", true))
	var eff := int(res.get("eff", 2))
	if has(att, "technician") and p > 0 and p <= 6:
		f *= 1.5
	if has(att, "iron fist") and move_name in PUNCH_MOVES:
		f *= 1.2
	if has(att, "adaptability") and t in att.types:
		f *= 4.0 / 3.0                          # STAB x2 instead of x1.5
	if has(att, "reckless") and mv.has("recoil"):
		f *= 1.2
	if has(att, "tinted lens") and eff == 1:
		f *= 2.0
	if (has(def, "solid rock") or has(def, "filter")) and eff == 3:
		f *= 0.75
	if has(att, "sniper") and bool(res.get("crit", false)):
		f *= 1.5
	if has(att, "solar power") and not physical and fs.weather == "sunny":
		f *= 1.5
	if has(att, "protosynthesis") and fs.weather == "sunny":
		f *= 1.3
	if has(def, "heatproof") and t == "Fire":
		f *= 0.5
	if has(def, "dry skin") and t == "Fire":
		f *= 1.25
	if has(att, "sheer force") and mv.has("eff"):
		f *= 1.3
	if has(att, "slow start") and fs.turn < 5:
		f *= 0.5
	if has(att, "infiltrator") and ((physical and int(def.status.get("reflect", 0)) > 0) or (not physical and int(def.status.get("light_screen", 0)) > 0)):
		f *= 2.0                                # undo the halving
	if t == "Electric" and int(att.get_meta("electromorph", 0)) > 0:
		f *= 2.0
		att.set_meta("electromorph", 0)
	if has(att, "rivalry"):
		f *= 1.0                                # no gender in dungeons here
	# Mega abilities
	if has(att, "tough claws") and physical:
		f *= 1.3
	if has(att, "strong jaw") and move_name in BITE_MOVES:
		f *= 1.5
	if has(att, "mega launcher") and move_name in PULSE_MOVES:
		f *= 1.5
	if has(att, "sand force") and fs.weather == "sandstorm" and t in ["Rock", "Ground", "Steel"]:
		f *= 1.3
	if t == "Fairy" and (has(att, "fairy aura") or has(def, "fairy aura")):
		f *= 4.0 / 3.0
	if has(att, "parental bond") and int(att.get_meta("pb_hit", 0)) == 1:
		f *= 0.25                               # the second, weaker strike
	return maxi(1, int(round(dmg * f)))

## Moves that are absorbed instead of hurting (Motor Drive, Storm Drain, Sap Sipper, Dry Skin with Water).
## Returns true when absorbed (and applies the boost / heal).
static func absorbs(d, def: Mon, t: String, dmg: int) -> bool:
	var what := ""
	if t == "Electric" and has(def, "lightning rod"):
		def.stages.spa = mini(20, int(def.stages.get("spa", 10)) + 1)
		what = "%s's Lightning Rod absorbed it and raised its Sp. Atk!"
	elif t == "Electric" and has(def, "motor drive"):
		def.status.fast = 0x7F
		what = "%s's Motor Drive absorbed it and raised its speed!"
	elif t == "Water" and has(def, "storm drain"):
		def.stages.spa = mini(20, int(def.stages.get("spa", 10)) + 1)
		what = "%s's Storm Drain absorbed it and raised its Sp. Atk!"
	elif t == "Grass" and has(def, "sap sipper"):
		def.stages.atk = mini(20, int(def.stages.get("atk", 10)) + 1)
		what = "%s's Sap Sipper absorbed it and raised its Attack!"
	elif t == "Water" and has(def, "dry skin"):
		def.hp = mini(def.max_hp, def.hp + maxi(1, def.max_hp / 4))
		what = "%s's Dry Skin absorbed it and restored HP!"
	if what == "":
		return false
	d._msg(what % d._nm(def))
	return true

## Remixed's No Guard: every move by or against it hits.
static func sure_hit(att: Mon, def: Mon) -> bool:
	return has(att, "no guard") or has(def, "no guard")

static func crit_bonus(att: Mon) -> int:
	return 12 if has(att, "super luck") else 0

## Stat changes: Simple doubles, Contrary flips (Remixed). Returns the new change.
static func stat_change(t: Mon, stv: int) -> int:
	if has(t, "simple"):
		stv *= 2
	if has(t, "contrary"):
		stv = -stv
	return stv

## After a foe lowered t's stat: Defiant (+2 Attack), Competitive (+2 Sp. Atk).
static func after_stat_drop(d, by: Mon, t: Mon) -> void:
	if by == t or by == null:
		return
	if has(t, "defiant"):
		t.stages.atk = mini(20, int(t.stages.get("atk", 10)) + 2)
		d._msg("%s's Defiant sharply raised its Attack!" % d._nm(t))
	if has(t, "competitive"):
		t.stages.spa = mini(20, int(t.stages.get("spa", 10)) + 2)
		d._msg("%s's Competitive sharply raised its Sp. Atk!" % d._nm(t))

## Flower Veil: Grass-type allies in the room of a Flower Veil Pokémon keep their stats.
static func flower_veil(fs: FloorState, t: Mon) -> bool:
	if not "Grass" in t.types:
		return false
	for o in fs.mons:
		if o.hp > 0 and has(o, "flower veil") and not fs.is_foe(o, t) and FloorState.cheb(o.pos, t.pos) <= 10:
			return true
	return false

## Gen 4 / Remixed status rules: Leaf Guard in sun, Overcoat vs powder moves, Corrosion lets Poison hit anything.
static func blocks_status_gen4(d, t: Mon, key: String) -> String:
	if has(t, "leaf guard") and d.fs.weather == "sunny" and key in ["sleep", "para", "burn", "poison", "badpoison", "frozen"]:
		return "%s's Leaf Guard protects it in the sunlight!"
	return ""

static func powder_immune(t: Mon, move_name: String) -> bool:
	return move_name in POWDER_MOVES and (has(t, "overcoat") or "Grass" in t.types and false)

## When the user's attack lands: Magician steals, Toxic Chain badly poisons (30%), Stench (Remixed: 10% cringe
## is Red's terrify here), Cursed Body on the target (30%: the attacker's last move is disabled for 3 turns),
## Electromorphosis charges, Aftermath / Moxie on KOs are handled by the faint hooks.
static func after_hit_gen4(d, m: Mon, t: Mon, move_name: String, dmg: int, t_type: String) -> void:
	var fs: FloorState = d.fs
	if dmg <= 0 or m == t:
		return
	if has(m, "magician") and m.held == "" and t.held != "" and t.held != "alertspecs" and not has(t, "sticky hold"):
		m.held = t.held
		t.held = ""
		d._msg("%s's Magician stole an item!" % d._nm(m))
	if has(m, "toxic chain") and t.hp > 0 and fs.rng.randi_range(0, 99) < 30:
		_status(d, t, "badpoison", 20, "Toxic Chain badly poisoned the target!")
	if t.hp > 0 and has(t, "electromorphosis"):
		t.set_meta("electromorph", 1)
		d._msg("%s's Electromorphosis charged it with power!" % d._nm(t))
	if t.hp > 0 and has(t, "cursed body") and move_name != "" and fs.rng.randi_range(0, 99) < 30:
		var slot: Dictionary = m.move_by_name(move_name)
		if not slot.is_empty() and not EosItems.has(m, "no_disable"):
			slot.disabled = 3
			d._msg("%s's Cursed Body disabled %s!" % [d._nm(t), move_name])
	if t.hp > 0 and has(t, "anger point") and false:
		pass

## A Pokémon fainted: Aftermath hurts a next-to-it attacker (1/4 HP); Moxie may raise the killer's Attack.
static func on_faint(d, t: Mon, killer: Mon) -> void:
	if killer == null or killer == t or killer.hp <= 0:
		return
	if has(t, "aftermath") and FloorState.cheb(t.pos, killer.pos) <= 1:
		var n := maxi(1, killer.max_hp / 4)
		d._msg("%s was caught in the Aftermath!" % d._nm(killer))
		d._hurt(killer, n, null, false)
	if has(killer, "moxie") and d.fs.rng.randi_range(0, 99) < 50:
		killer.stages.atk = mini(20, int(killer.stages.get("atk", 10)) + 1)
		d._msg("%s's Moxie raised its Attack!" % d._nm(killer))

## Critical hit taken: Anger Point maxes Attack.
static func on_crit_taken(d, t: Mon) -> void:
	if has(t, "anger point") and t.hp > 0:
		t.stages.atk = 20
		d._msg("%s's Anger Point maxed its Attack!" % d._nm(t))

## Status move rules from Remixed: Magic Bounce sends status moves back, Prankster's moves fail on Dark types.
static func bounce(t: Mon, m: Mon) -> bool:
	return t != m and has(t, "magic bounce")

static func prankster_fails(m: Mon, t: Mon) -> bool:
	return t != m and has(m, "prankster") and AI.is_type(t, "Dark")

## Gen 4 per-turn effects: Ice Body / Rain Dish-like heals, Dry Skin, Hydration, Poison Heal, Bad Dreams,
## Snow Warning weather, Sand Rush / Slush Rush / Quick Feet speed, Unburden. Called from end_of_turn.
static func end_of_turn_gen4(d) -> void:
	var fs: FloorState = d.fs
	for m in fs.mons.duplicate():
		if m.hp <= 0:
			continue
		if has(m, "ice body") and fs.weather == "hail":
			m.hp = mini(m.max_hp, m.hp + maxi(1, m.max_hp / 16))
		if has(m, "regenerator") and fs.turn % 5 == 0:
			m.hp = mini(m.max_hp, m.hp + maxi(1, m.max_hp / 12))
		if has(m, "dry skin"):
			if fs.weather == "rain":
				m.hp = mini(m.max_hp, m.hp + maxi(1, m.max_hp / 8))
			elif fs.weather == "sunny":
				d._hurt(m, maxi(1, m.max_hp / 8), null, false)
		if has(m, "hydration") and fs.weather == "rain":
			for k in ["poison", "badpoison", "burn", "para", "sleep", "frozen"]:
				m.status[k] = 0
		if has(m, "poison heal") and (int(m.status.get("poison", 0)) > 0 or int(m.status.get("badpoison", 0)) > 0):
			m.hp = mini(m.max_hp, m.hp + maxi(1, m.max_hp / 8))
		if has(m, "bad dreams"):
			for o in fs.mons:
				if o.hp > 0 and fs.is_foe(m, o) and int(o.status.get("sleep", 0)) > 0 and fs.can_see(m, o.pos):
					d._hurt(o, maxi(1, o.max_hp / 8), m, false)
					if o.hp <= 0:
						await d.faint(o, m)
		var extra := int(m.get_meta("weather_speed", 0))
		if (has(m, "sand rush") and fs.weather == "sandstorm") or (has(m, "slush rush") and fs.weather == "hail"):
			extra = 1
		if has(m, "quick feet") and HeldItems.has_bad_status(m):
			extra = 1
		if EosItems.weather_speed(m, str(fs.weather)):
			extra = 1
		m.set_meta("weather_speed", extra)
		for mv in m.moves:
			if int(mv.get("disabled", 0)) > 0:
				mv.disabled = int(mv.disabled) - 1
