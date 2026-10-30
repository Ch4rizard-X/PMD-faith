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
	var mk := mega_of(m.sp) if m.mega == "" else ""
	if mk != "" and DB.species.has(mk):
		await _mega_fx(d, m, mk)
	else:
		await _flash(d, m)
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

## How Mega Evolution looks: 0 = white flashes, 1 = the job-client light beam (effect 318 + sound 850),
## 2 = DX-style: the Pokémon glows white inside a burst of light and sparkles, changes form, the glow fades.
static var fx_style := 2

static func _mega_fx(d, m: Mon, mk: String) -> void:
	if m.visual == null or not is_instance_valid(m.visual):
		return
	var vis = m.visual
	match fx_style:
		1:
			d.rescue_beam([m])                       # not awaited: the form changes while the beam shines
			await d.get_tree().create_timer(0.3).timeout
			vis.set_species(mk)
			await d.get_tree().create_timer(0.4).timeout
		2:
			Audio.sfx("evolve")
			var g := MegaGlow.new()
			g.position = MonSprite.fig_point(vis, Vector2(0, -6))
			g.z_index = 6
			d.fx_layer.add_child(g)
			var tw: Tween = d.create_tween()
			tw.tween_property(vis, "flash", 3.0, 0.45)
			await tw.finished
			vis.set_species(mk)
			g.burst()
			await d.get_tree().create_timer(0.25).timeout
			var tw2: Tween = d.create_tween()
			tw2.tween_property(vis, "flash", 0.0, 0.4)
			await tw2.finished
		_:
			await _flash(d, m)


## DX-style Mega Evolution light: a pulsing ring with rainbow-tinted sparkles drawn in, then a burst outward.
class MegaGlow extends Node2D:
	var t := 0.0
	var bt := -1.0
	func burst() -> void:
		bt = 0.0
	func _process(dt: float) -> void:
		t += dt
		if bt >= 0.0:
			bt += dt
			if bt > 0.6:
				queue_free()
				return
		queue_redraw()
	func _draw() -> void:
		var hues := [0.0, 0.12, 0.3, 0.5, 0.62, 0.8]
		if bt < 0.0:
			var k := minf(t / 0.45, 1.0)
			draw_circle(Vector2.ZERO, 6.0 + 10.0 * k, Color(1, 1, 1, 0.25 * k))
			draw_arc(Vector2.ZERO, 30.0 - 14.0 * k, 0.0, TAU, 40, Color(1, 1, 0.8, 0.8 * k), 2.0)
			for i in 12:
				var a := TAU * i / 12.0 + t * 4.0
				var r := 34.0 * (1.0 - k) + 8.0
				_star(Vector2(cos(a), sin(a)) * r, Color.from_hsv(hues[i % 6], 0.45, 1.0, k), 2.5)
		else:
			var e := bt / 0.6
			draw_circle(Vector2.ZERO, 14.0 + 30.0 * e, Color(1, 1, 1, 0.55 * (1.0 - e)))
			draw_arc(Vector2.ZERO, 16.0 + 40.0 * e, 0.0, TAU, 48, Color(1, 0.95, 0.6, 1.0 - e), 3.0)
			for i in 16:
				var a := TAU * i / 16.0
				_star(Vector2(cos(a), sin(a)) * (12.0 + 46.0 * e), Color.from_hsv(hues[i % 6], 0.45, 1.0, 1.0 - e), 3.0)
	func _star(p: Vector2, c: Color, s: float) -> void:
		draw_line(p - Vector2(s, 0), p + Vector2(s, 0), c, 1.0)
		draw_line(p - Vector2(0, s), p + Vector2(0, s), c, 1.0)
		draw_rect(Rect2(p - Vector2(0.75, 0.75), Vector2(1.5, 1.5)), Color(1, 1, 1, c.a))

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
