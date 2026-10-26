class_name Awaken
extends RefCounted
## Rescue Team DX's Empowerment Seed. The Pokémon that eats it becomes Awakened for the rest of the floor:
## its Attack, Sp. Atk, Defense and Sp. Def go up, its linked moves always land critical hits and type
## disadvantages no longer weaken its moves. A Pokémon that can Mega Evolve takes its Mega form (Kyogre and
## Groudon their Primal form) while it lasts; it changes back when the team leaves the floor.

const STAT_BOOST := 1.5
## Two Megas for one Pokémon: the one DX uses.
const PREFER := {"0006": "0006MX", "0150": "0150MY"}
static var _megas := {}

static func mega_of(sp: String) -> String:
	if _megas.is_empty():
		for k in DB.species:
			var b = DB.species[k].get("megaBase")
			if b == null:
				continue
			if not _megas.has(b) or PREFER.get(b, "") == k:
				_megas[str(b)] = k
	return str(_megas.get(sp.substr(0, 4), ""))

static func is_awake(m: Mon) -> bool:
	return m != null and int(m.status.get("awakened", 0)) > 0

static func boost(m: Mon, v: int) -> int:
	return int(v * STAT_BOOST) if is_awake(m) else v

## Eating (or being hit by) an Empowerment Seed.
static func awaken(d, m: Mon) -> void:
	if is_awake(m):
		d._msg("But nothing happened.")
		return
	m.status["awakened"] = 0x7F
	await _flash(d, m)
	var mk := mega_of(m.sp) if m.mega == "" else ""
	if mk != "" and DB.species.has(mk):
		m.set_meta("awk_prev", {"sp": m.sp, "types": m.types.duplicate(), "ab": m.ability, "ab2": m.ability2})
		var S: Dictionary = DB.species[mk]
		m.mega = mk
		m.sp = mk
		m.types = S.get("types", m.types).duplicate()
		var ab: Array = S.get("ab", [])
		m.ability = str(ab[0]) if ab.size() > 0 else ""
		m.ability2 = str(ab[1]) if ab.size() > 1 else ""
		DB.recalc(m)
		if m.visual:
			m.visual.set_species(mk)
		if str(S.get("name", "")).begins_with("Primal"):
			d._msg("[color=#ffdc4a]%s underwent Primal Reversion![/color]" % d._nm(m))
		else:
			d._msg("[color=#ffdc4a]%s Mega Evolved into %s![/color]" % [d._nm(m), S.get("name", "")])
		AbilityFx.update_weather(d)
	else:
		d._msg("[color=#ffdc4a]%s became Awakened![/color]" % d._nm(m))
	d._msg("%s's stats rose sharply!" % d._nm(m))

static func _flash(d, m: Mon) -> void:
	if m.visual == null or not is_instance_valid(m.visual):
		return
	var tw: Tween = d.create_tween()
	for i in 3:
		tw.tween_property(m.visual, "flash", 1.5, 0.08)
		tw.tween_property(m.visual, "flash", 0.0, 0.08)
	await tw.finished

## Back to normal (leaving the floor, the end of the expedition).
static func revert(m: Mon) -> void:
	if not is_awake(m) and m.mega == "":
		return
	m.status["awakened"] = 0
	if m.mega != "":
		var p: Dictionary = m.get_meta("awk_prev", {})
		m.sp = str(p.get("sp", DB.species.get(m.mega, {}).get("megaBase", m.sp)))
		m.types = (p.get("types", DB.species.get(m.sp, {}).get("types", m.types)) as Array).duplicate()
		m.ability = str(p.get("ab", m.ability))
		m.ability2 = str(p.get("ab2", m.ability2))
		m.mega = ""
		m.remove_meta("awk_prev")
		DB.recalc(m)
		if m.visual and is_instance_valid(m.visual):
			m.visual.set_species(m.sp)

## Primordial Sea / Desolate Land: Fire (Water) moves fizzle while the Primal Pokémon is on the floor.
static func primal_block(d, t: String) -> String:
	for m in d.fs.mons:
		if m.hp <= 0:
			continue
		if t == "Fire" and AbilityFx.has(m, "primordial sea"):
			return "The Fire-type attack fizzled out in the heavy rain!"
		if t == "Water" and AbilityFx.has(m, "desolate land"):
			return "The Water-type attack evaporated in the harsh sunlight!"
	return ""

## Empowerment Seeds in the dungeons: only once the story is done (as in DX), rare.
static func can_drop() -> bool:
	return RedShops.postgame()
