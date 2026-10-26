extends SceneTree
## Headless checks for scripts/core/combat.gd (Red damage/accuracy port).
## Run: godot --headless --path . --script tests/test_combat.gd

var species: Dictionary
var growth: Dictionary
var fails := 0
const STAT_KEYS := ["hp", "atk", "spa", "def", "spd"]

func _init() -> void:
	Combat.load_data()
	species = Combat._read_json("res://data/species.json")
	growth = Combat._read_json("res://data/growth.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	_fixed_point()
	_effectiveness()

	var charm := _mk("0004", 5, "team")
	var pidgey := _mk("0016", 3, "enemy")
	var rattata := _mk("0019", 2, "enemy")
	print("\n== Mons (Red stats from growth table) ==")
	for m in [charm, pidgey, rattata]:
		print("  %s Lv%d %s hp%d atk%d def%d spa%d spd%d ab=%s" % [m.name, m.level, m.side, m.max_hp, m.atk, m.def, m.spa, m.spd, m.ability])

	print("\n== Damage distributions (2000 rolls each, accuracy2 skipped) ==")
	_dist("Charmander Scratch -> Pidgey", charm, pidgey, Combat.move("Scratch"), rng)
	_dist("Charmander Tackle -> Pidgey", charm, pidgey, Combat.move("Tackle"), rng)
	_dist("Charmander Ember -> Pidgey", charm, pidgey, Combat.move("Ember"), rng)
	_dist("Charmander Attack -> Pidgey", charm, pidgey, Combat.regular_attack(), rng)
	_dist("Charmander Scratch -> Rattata Lv2", charm, rattata, Combat.move("Scratch"), rng)
	_dist("Pidgey Gust -> Charmander", pidgey, charm, Combat.move("Gust"), rng)
	_dist("Pidgey Tackle -> Charmander", pidgey, charm, Combat.move("Tackle"), rng)
	_dist("Pidgey Attack -> Charmander", pidgey, charm, Combat.regular_attack(), rng)
	_dist("Ember in sun", charm, pidgey, Combat.move("Ember"), rng, {"weather": "sunny"})
	_dist("Ember in rain", charm, pidgey, Combat.move("Ember"), rng, {"weather": "rain"})
	charm.held = "powerband"
	_dist("Scratch w/ Power Band", charm, pidgey, Combat.move("Scratch"), rng)
	charm.held = ""
	charm.stages.atk = 12
	_dist("Scratch at Atk +2", charm, pidgey, Combat.move("Scratch"), rng)
	charm.stages.atk = 10
	pidgey.status.reflect = 5
	_dist("Scratch vs Reflect", charm, pidgey, Combat.move("Scratch"), rng)
	pidgey.status.reflect = 0
	var hp := charm.hp
	charm.hp = 4
	_dist("Ember with Blaze (pinch)", charm, pidgey, Combat.move("Ember"), rng)
	charm.hp = hp
	var cat := _mk("0010", 5, "team")   # High level comparisons
	var big := _mk("0004", 30, "team")
	var big_foe := _mk("0019", 25, "enemy")
	_dist("Lv30 Charmander Ember -> Lv25 Rattata", big, big_foe, Combat.move("Ember"), rng)
	_dist("Lv25 Rattata Tackle -> Lv30 Charmander", big_foe, big, Combat.move("Tackle"), rng)

	print("\n== Ghost / immunity quirks ==")
	var gastly := _mk("0092", 10, "enemy")
	print("  Gastly types ", gastly.types, " abilities ", gastly.ability, "/", gastly.ability2)
	_dist("Charmander Scratch -> Gastly (unexposed)", charm, gastly, Combat.move("Scratch"), rng)
	gastly.exposed = true
	_dist("Charmander Scratch -> Gastly (exposed)", charm, gastly, Combat.move("Scratch"), rng)
	gastly.exposed = false
	_dist("Charmander Attack (type None) -> Gastly", charm, gastly, Combat.regular_attack(), rng)
	var r := Combat.calc_damage(charm, gastly, Combat.move("Scratch"), rng, {"skip_accuracy2": true})
	print("  msgs vs Gastly: ", r.msg)
	var onix := _mk("0095", 10, "enemy")
	_dist("Charmander Ember -> Onix (Rock/Ground)", charm, onix, Combat.move("Ember"), rng)
	gastly.ability = "levitate"
	r = Combat.calc_damage(charm, gastly, Combat.move("Mud-Slap") if not Combat.move("Mud-Slap").is_empty() else Combat.move("Dig"), rng, {"skip_accuracy2": true})
	print("  Ground move vs Levitate: dmg=%d eff=%d missed_by_type=%s msg=%s" % [r.dmg, r.eff, r.missed_by_type, r.msg])
	var sq := _mk("0007", 5, "enemy")
	sq.ability = "water-absorb"
	r = Combat.calc_damage(charm, sq, Combat.move("Water Gun"), rng, {"skip_accuracy2": true})
	print("  Water Gun vs Water Absorb: dmg=%d heal=%d absorbed=%s" % [r.dmg, r.heal, r.absorbed])
	var shed := _mk("0292", 10, "enemy")
	shed.ability = "wonder-guard"
	r = Combat.calc_damage(charm, shed, Combat.move("Scratch"), rng, {"skip_accuracy2": true})
	print("  Scratch vs Wonder Guard: dmg=%d msg=%s" % [r.dmg, r.msg])
	r = Combat.calc_damage(charm, shed, Combat.move("Ember"), rng, {"skip_accuracy2": true})
	print("  Ember vs Wonder Guard (Bug/Ghost): dmg=%d eff=%d msg=%s" % [r.dmg, r.eff, r.msg])
	r = Combat.calc_damage(charm, shed, Combat.regular_attack(), rng, {"skip_accuracy2": true})
	print("  Regular attack vs Wonder Guard: dmg=%d" % r.dmg)

	print("\n== Crit rate (20000 trials) ==")
	_crit("team Charmander Scratch (crit 12)", charm, pidgey, rng)
	_crit("enemy Pidgey Tackle (Red: enemies don't crit)", pidgey, charm, rng)
	charm.held = "scopelens"
	_crit("team + Scope Lens", charm, pidgey, rng)
	charm.held = ""
	pidgey.held = "scopelens"
	_crit("enemy + Scope Lens", pidgey, charm, rng)
	pidgey.held = ""
	charm.status.focus_energy = 3
	_crit("team + Focus Energy", charm, pidgey, rng)
	charm.status.focus_energy = 0
	pidgey.ability = "battle-armor"
	_crit("vs Battle Armor", charm, pidgey, rng)
	pidgey.ability = "keen-eye"

	print("\n== Accuracy (20000 trials, acc_type 1 then 2) ==")
	var tackle := Combat.move("Tackle")
	for st in [0, 4, 8, 10, 12, 16, 20]:
		charm.stages.acc = st
		print("  Tackle a1=%d a2=%d  acc stage %2d: a1 %5.1f%%  a2 %5.1f%%   eva-stage-%2d a2 %5.1f%%" % [tackle.a1, tackle.a2, st,
			_acc(charm, pidgey, tackle, rng, 1), _acc(charm, pidgey, tackle, rng, 2), st, _acc_eva(charm, pidgey, tackle, rng, st)])
	charm.stages.acc = 10
	print("  Regular attack (125): %5.1f%%" % _acc(charm, pidgey, Combat.regular_attack(), rng, 2))
	pidgey.held = "detectband"
	print("  Tackle a2 vs Detect Band: %5.1f%%" % _acc(charm, pidgey, tackle, rng, 2))
	pidgey.held = ""
	charm.ability = "compound-eyes"
	print("  Tackle a2 w/ Compound Eyes: %5.1f%%" % _acc(charm, pidgey, tackle, rng, 2))
	charm.ability = "hustle"
	print("  Tackle a2 w/ Hustle: %5.1f%%   Ember a2 w/ Hustle: %5.1f%%" % [_acc(charm, pidgey, tackle, rng, 2), _acc(charm, pidgey, Combat.move("Ember"), rng, 2)])
	charm.ability = "blaze"
	pidgey.ability = "sand-veil"
	print("  Tackle a2 vs Sand Veil in sandstorm: %5.1f%%" % _acc(charm, pidgey, tackle, rng, 2, {"weather": "sandstorm"}))
	pidgey.ability = "keen-eye"
	var full := 0
	for i in 5000:
		if not Combat.calc_damage(charm, pidgey, tackle, rng).missed:
			full += 1
	print("  calc_damage() built-in a2 hit rate for Tackle: %5.1f%%" % (full * 100.0 / 5000))

	print("\n== Status damage ==")
	print("  burn ", Combat.status_damage("burn"), " poison ", Combat.status_damage("poison"), " badpoison ", Combat.status_damage("badpoison", 5))

	# ---- sanity assertions
	var s := _stats(charm, pidgey, Combat.move("Scratch"), rng)
	# Independent float version of Red's formula: x = (A-D)/8 + L*2/3 ; base = x^2/20 + 2x - D + 10
	var A := charm.atk + int(Combat.move("Scratch").p)
	var x := (A - pidgey.def) / 8.0 + charm.level * 2.0 / 3.0
	var base := x * x / 20.0 + 2.0 * x - pidgey.def + 10.0
	_check(absf(s.avg - base) < 0.6, "Scratch avg %.2f matches float reference %.2f (Fire user, no STAB)" % [s.avg, base])
	_check(s.min >= floori(base * 0.875) and s.max <= ceili(base * 1.125), "Scratch range %d..%d within x0.875..x1.125" % [s.min, s.max])
	_check(Combat.type_eff("Normal", ["Ghost"]) == 0, "Normal vs Ghost = little effect")
	_check(Combat.type_eff("Normal", ["Ghost"], true) == 2, "Normal vs exposed Ghost = neutral")
	_check(Combat.type_eff("Electric", ["Ground", "Water"]) == 1, "Electric vs Ground/Water = resist via combine")
	_check(Combat.type_eff("Fire", ["Rock", "Bug"]) == 2, "Fire vs Rock/Bug = neutral")
	_check(Combat.type_eff("Ice", ["Grass", "Flying"]) == 3, "Ice vs Grass/Flying = super")
	_check(absf(Combat.type_multiplier("Fire", ["Rock", "Bug"]) - 1.35) < 0.001, "Fire vs Rock/Bug = x0.9*x1.5")
	print("\n%s (%d failures)" % ["ALL OK" if fails == 0 else "FAILURES", fails])
	quit(1 if fails else 0)

func _check(c: bool, what: String) -> void:
	print(("  [ok] " if c else "  [FAIL] ") + what)
	if not c:
		fails += 1

func _mk(sp: String, lv: int, side: String) -> Mon:
	var m := Mon.new()
	var S: Dictionary = species.get(sp, {})
	m.sp = sp
	m.name = S.get("name", sp)
	m.side = side
	m.level = lv
	var st: Dictionary = _stats_at(sp, lv)
	m.max_hp = st.hp
	m.hp = st.hp
	m.atk = st.atk
	m.def = st.def
	m.spa = st.spa
	m.spd = st.spd
	m.types = S.get("types", []).duplicate()
	var ab: Array = S.get("ab", [])
	m.ability = ab[0] if ab.size() > 0 else ""
	m.ability2 = ab[1] if ab.size() > 1 else ""
	return m

## Red level-up stats from data/growth.json (same layout as DB.stats_at; DB itself is an autoload).
func _stats_at(sp: String, L: int) -> Dictionary:
	var d = growth.get("mon", {}).get(sp)
	var out := {}
	if d == null:
		var b: Array = species.get(sp, {}).get("b", [50, 50, 50, 50, 50, 50])
		out.hp = int(floor(2 * b[0] * L / 100.0)) + L + 10
		var keys := ["atk", "def", "spa", "spd"]
		for i in 4:
			out[keys[i]] = int(floor(2 * b[i + 1] * L / 100.0)) + 5
		return out
	if d[5] is String:
		var gs: String = d[5]
		for j in 5:
			var v := int(d[j])
			for l in range(2, L + 1):
				v += gs.unicode_at(j * 99 + l - 2) - 48
			out[STAT_KEYS[j]] = v
	else:
		var curve: Array = growth.curve
		for j in 5:
			out[STAT_KEYS[j]] = int(round(float(d[j]) + (float(d[5][j]) - float(d[j])) * float(curve[j][L - 1])))
	return out

func _stats(a: Mon, d: Mon, mv: Dictionary, rng: RandomNumberGenerator, ctx := {}, n := 2000) -> Dictionary:
	var c := ctx.duplicate()
	c["skip_accuracy2"] = true
	var hist := {}
	var lo := 99999
	var hi := -1
	var sum := 0
	var eff := 2
	for i in n:
		var r := Combat.calc_damage(a, d, mv, rng, c)
		if r.crit:
			continue
		hist[r.dmg] = hist.get(r.dmg, 0) + 1
		lo = mini(lo, r.dmg)
		hi = maxi(hi, r.dmg)
		sum += r.dmg
		eff = r.eff
	var cnt := 0
	for k in hist:
		cnt += hist[k]
	return {"min": lo, "max": hi, "avg": float(sum) / maxi(cnt, 1), "hist": hist, "eff": eff}

func _dist(label: String, a: Mon, d: Mon, mv: Dictionary, rng: RandomNumberGenerator, ctx := {}) -> void:
	var s := _stats(a, d, mv, rng, ctx)
	var keys: Array = s.hist.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%d:%d" % [k, s.hist[k]])
	print("  %-42s non-crit %d..%d avg %.2f eff %d  {%s}" % [label, s.min, s.max, s.avg, s.eff, ", ".join(parts)])

func _crit(label: String, a: Mon, d: Mon, rng: RandomNumberGenerator) -> void:
	var c := 0
	var n := 20000
	var mv := Combat.move("Scratch") if a.is_team() else Combat.move("Tackle")
	for i in n:
		if Combat.calc_damage(a, d, mv, rng, {"skip_accuracy2": true}).crit:
			c += 1
	print("  %-46s %5.2f%%" % [label, c * 100.0 / n])

func _acc(a: Mon, d: Mon, mv: Dictionary, rng: RandomNumberGenerator, t: int, ctx := {}) -> float:
	var c := ctx.duplicate()
	c["acc_type"] = t
	var h := 0
	for i in 20000:
		if Combat.accuracy_hits(a, d, mv, rng, c):
			h += 1
	return h * 100.0 / 20000

func _acc_eva(a: Mon, d: Mon, mv: Dictionary, rng: RandomNumberGenerator, eva: int) -> float:
	var sa: int = a.stages.acc
	a.stages.acc = 10
	d.stages.eva = eva
	var v := _acc(a, d, mv, rng, 2)
	d.stages.eva = 10
	a.stages.acc = sa
	return v

func _fixed_point() -> void:
	print("== Fixed point ==")
	_check(Combat.fp_to_s32(Combat.fp_from_s32(-7)) == -7, "s48_16 round trip negative")
	_check(Combat.fp_to_s32(Combat.fp_div(Combat.fp_from_s32(-3), Combat.fp_from_s32(8))) == 0, "-3/8 rounds to 0 (-0.375)")
	_check(Combat.fp_to_s32(Combat.fp_div(Combat.fp_from_s32(-5), Combat.fp_from_s32(8))) == -1, "-5/8 rounds to -1")
	_check(Combat.s24_8_mul(20 * 256, 332) == 6640, "20 * 1.2969(332) = 25.9375 in 24.8")
	_check(Combat.fp_mul(Combat.fp_from_s32(5), 0xAAAA) == 218450, "5 * 0xAAAA")

func _effectiveness() -> void:
	print("\n== Type effectiveness (displayed eff / total multiplier) ==")
	for p in [["Normal", ["Ghost"]], ["Fighting", ["Normal", "Ghost"]], ["Ghost", ["Normal"]], ["Electric", ["Ground"]],
			["Electric", ["Ground", "Flying"]], ["Ground", ["Flying", "Fire"]], ["Fire", ["Rock", "Bug"]], ["Fire", ["Grass", "Bug"]],
			["Water", ["Fire", "Rock"]], ["Grass", ["Fire", "Flying"]], ["Psychic", ["Dark"]], ["Flying", ["Grass"]], ["None", ["Ghost"]]]:
		print("  %-9s vs %-18s eff %d  x%.4f" % [p[0], "/".join(p[1]), Combat.type_eff(p[0], p[1]), Combat.type_multiplier(p[0], p[1])])
	print("  per-type multipliers: ", [Combat.eff_multiplier(0), Combat.eff_multiplier(1), Combat.eff_multiplier(2), Combat.eff_multiplier(3)])
