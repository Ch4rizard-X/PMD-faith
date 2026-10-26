extends SceneTree
## Headless test for the Explorers of Sky add-on IQ skills: data (gen_iq_sky.py -> data/iq.json), IQ menu
## rules, the combat / turn effects (combat.gd, turn_rules.gd) and the IQSky hooks (iq_sky.gd).
## Run: godot --headless --path . --script tests/test_iq_sky.gd     Nothing is saved.

var fails := 0
var checks := 0
var _db
var _game
var _IQ
var _SKY
var _CB
var _TR
var _AI
var _FS

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", msg)

## Minimal stand-in for the Dungeon node (the public members IQSky uses).
class FakeDungeon:
	var fs
	var team_mons: Array = []
	var obj_layer = null
	var log: Array = []
	var fainted: Array = []
	func _msg(t: String) -> void:
		log.append(t)
	func _nm(m) -> String:
		return m.name
	func _hurt(t, dmg: int, _by, _anim := true, _crit := false, _eff := 2) -> void:
		t.hp = maxi(0, t.hp - dmg)
	func faint(t, _killer) -> void:
		fainted.append(t)
	func _pick_item(_table: int) -> String:
		return "oran"

func _initialize() -> void:
	_db = root.get_node_or_null("DB")
	_game = root.get_node_or_null("Game")
	if _db and _db.species.is_empty():
		_db._ready()
	_IQ = load("res://scripts/core/iq.gd")
	_SKY = load("res://scripts/core/iq_sky.gd")
	_CB = load("res://scripts/core/combat.gd")
	_TR = load("res://scripts/core/turn_rules.gd")
	_AI = load("res://scripts/core/ai.gd")
	_FS = load("res://scripts/dungeon/floor_state.gd")
	_CB.load_data()
	_data()
	_menus()
	_passives()
	_combat()
	_turns()
	await _hooks()
	print("test_iq_sky: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)

func _e(sp: String, L := 20, iq := 0) -> Dictionary:
	return {"sp": sp, "name": _db.species[sp].name, "level": L, "exp": 0, "moves": _db.default_moves(sp, L), "iq": iq, "held": "", "bonus": {}}

func _sky_ids() -> Array:
	return _IQ.data().skills.filter(func(s): return s.get("sky", false)).map(func(s): return s.id)

# ------------------------------------------------------------------ data
func _data() -> void:
	var red: Array = _IQ.data().skills.filter(func(s): return not s.get("sky", false))
	var sky: Array = _IQ.data().skills.filter(func(s): return s.get("sky", false))
	ok(red.size() == 23, "Red's 23 skills still there")
	ok(sky.size() == 39, "39 Sky add-on skills (got %d)" % sky.size())
	# Sky's IQ_SKILLS[] values
	var want := {"cheerleader": 30, "acute_sniffer": 50, "pp_saver": 55, "bodyguard": 65, "brick_tough": 100,
		"power_pitcher": 130, "survivalist": 140, "coin_watcher": 150, "gap_prober": 170, "wise_healer": 175,
		"wary_fighter": 180, "concentrator": 185, "deep_breather": 190, "practice_swinger": 195, "aggressor": 220,
		"defender": 230, "sharpshooter": 260, "hit_and_runner": 270, "counter_basher": 280, "quick_healer": 290,
		"multitalent": 310, "exp_elite": 320, "counter_hitter": 330, "erratic_player": 340, "haggler": 350,
		"clutch_performer": 360, "collector": 370, "trap_buster": 420, "critical_dodger": 440, "stair_sensor": 480,
		"extra_striker": 520, "fast_friend": 550, "intimidator": 560, "no_charger": 570, "map_surveyor": 580,
		"quick_striker": 750, "pierce_hurler": 850, "nature_gifter": 900, "time_tripper": 950}
	for id in want:
		ok(int(_IQ.skill(id).get("iq", -1)) == want[id] and bool(_IQ.skill(id).get("sky", false)), "Sky IQ needed: %s = %d" % [id, want[id]])
	ok(_IQ.skill("escapist").is_empty(), "Escapist skipped")
	ok(int(_IQ.skill("quick_dodger").iq) == 100 and int(_IQ.skill("trap_avoider").iq) == 140 and int(_IQ.skill("lava_evader").group) == 16,
		"Red's own thresholds / groups unchanged for skills both games have")
	var groups := {}
	var red_max := 0
	for s in red:
		red_max = maxi(red_max, int(s.group))
	for s in sky:
		groups[int(s.group)] = true
		ok(int(s.group) > red_max, "Sky group of %s doesn't clash with Red's" % s.id)
		ok(str(s.desc) != "" and not str(s.desc).contains("[CS"), "desc cleaned: " + s.id)
	ok(groups.size() == sky.size(), "every Sky skill has its own restriction group (Sky's IQ_SKILL_RESTRICTIONS)")
	var last := 0
	for s in sky:
		ok(int(s.iq) >= last, "Sky skills listed in unlock order")
		last = int(s.iq)
	ok(_IQ.data().has("sky_messages"), "sky_messages present")

# ------------------------------------------------------------------ menus / unlocks / groups
func _menus() -> void:
	var e := _e("0025", 20, 219)
	var row := func(id): return _IQ.skills_for(e).filter(func(s): return s.id == id)[0]
	ok(not row.call("aggressor").unlocked and row.call("practice_swinger").unlocked, "Aggressor locked at IQ 219")
	e.iq = 220
	ok(row.call("aggressor").unlocked and not row.call("aggressor").on, "unlocks at 220, starts off (like Red)")
	ok(row.call("aggressor").sky == true and row.call("item_catcher").sky == false, "skills_for marks sky")
	var learned = _IQ.newly_unlocked(1, 999)
	for id in _sky_ids():
		ok(id in learned, "unlocked by IQ 999: " + id)
	ok(_IQ.newly_unlocked(219, 220) == ["aggressor"], "IQ 219 -> 220 learns just Aggressor")
	ok(_IQ.newly_unlocked(29, 30) == ["cheerleader"], "IQ 29 -> 30 learns Cheerleader")
	# switching
	e.iq = 999
	ok(_IQ.set_skill(e, "aggressor", true) and _IQ.set_skill(e, "defender", true), "switch on Aggressor + Defender")
	ok(_IQ.has(e, "aggressor") and _IQ.has(e, "defender"), "Sky skills are not mutually exclusive (own groups)")
	ok(_IQ.set_skill(e, "type_advantage_master", true) and _IQ.set_skill(e, "sure_hit_attacker", true), "Red group-4 skills")
	ok(_IQ.has(e, "sure_hit_attacker") and not _IQ.has(e, "type_advantage_master"), "Red's exclusive slot still works")
	for id in _sky_ids():
		_IQ.set_skill(e, id, true)
	ok(_IQ.has(e, "sure_hit_attacker") and _IQ.has(e, "item_catcher") and _IQ.has(e, "course_checker"), "Sky skills leave Red skills on")
	ok(_IQ.toggle_skill(e, "aggressor") and not _IQ.has(e, "aggressor"), "toggle off")
	var low := _e("0025", 20, 50)
	ok(not _IQ.set_skill(low, "aggressor", true) and not _IQ.has(low, "aggressor"), "locked Sky skill can't be switched on")
	# always on
	var b := _e("0001", 20, 99)
	ok(not _IQ.has(b, "brick_tough"), "Brick-Tough not yet at 99")
	b.iq = 100
	ok(_IQ.has(b, "brick_tough") and row.call("brick_tough").always_on, "Brick-Tough on by itself once learned")
	ok(not _IQ.set_skill(b, "brick_tough", false) and _IQ.has(b, "brick_tough"), "Brick-Tough can't be switched off")
	# wild Pokémon keep Red's fixed set
	var w = _db.make_mon("0019", 10, "enemy")
	ok(not _IQ.has(w, "aggressor") and not _CB.has_iq(w, "Aggressor"), "wild Pokémon get no Sky skills")
	# active list mirrors names + ids
	var m = _game.mon_from_entry(_e("0004", 20, 999))
	_IQ.set_skill(m, "exp_elite", true)
	ok("exp_elite" in m.iq_skills and _CB.has_iq(m, "exp_elite") and _AI.iq(m, "Exp. Elite"), "iq_skills has Sky ids")

# ------------------------------------------------------------------ passives
func _passives() -> void:
	var e := _e("0004", 20, 99)
	var m = _game.mon_from_entry(e)
	var base_hp: int = m.max_hp
	var base_pp: Array = m.moves.map(func(mv): return int(mv.max_pp))
	ok(not m.has_meta("iq_hp_bonus") or int(m.get_meta("iq_hp_bonus")) == 0, "no passives below IQ 100")
	e.iq = 100
	m.iq = 100
	_IQ.refresh(m)
	ok(m.max_hp == base_hp + 10 and m.hp == m.max_hp, "Brick-Tough: max HP +10 (%d -> %d)" % [base_hp, m.max_hp])
	ok(int(e.bonus.get("hp", 0)) == 0, "team entry's bonus untouched")
	m.level += 1
	_db.recalc(m)
	ok(m.max_hp == int(_db.stats_at(m.sp, m.level).hp) + 10, "Brick-Tough survives a level-up recalc")
	m.iq = 310
	e.iq = 310
	_IQ.refresh(m)
	var pp_ok := true
	for i in m.moves.size():
		pp_ok = pp_ok and int(m.moves[i].max_pp) == mini(99, base_pp[i] + 5)
	ok(pp_ok and m.moves.size() > 0, "Multitalent: every move +5 max PP")
	_IQ.refresh(m)
	ok(int(m.moves[0].max_pp) == mini(99, base_pp[0] + 5), "Multitalent not stacked by a second apply")
	_game.store_mon(m)
	var m2 = _game.mon_from_entry(e)
	ok(int(m2.moves[0].max_pp) == mini(99, base_pp[0] + 5), "stored + reloaded: still +5 once")
	m.iq = 50
	e.iq = 50
	_IQ.refresh(m)
	ok(int(m.moves[0].max_pp) == base_pp[0] and m.max_hp == int(_db.stats_at(m.sp, m.level).hp), "passives come off when IQ drops")

# ------------------------------------------------------------------ combat
func _team(sp: String, L: int, skills: Array) -> Mon:
	var m: Mon = _db.make_mon(sp, L, "team")
	m.iq_skills = skills.duplicate()
	return m

func _avg_dmg(a: Mon, d: Mon, mv: Dictionary, n := 3000, ctx := {}) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var c := ctx.duplicate()
	c["skip_accuracy2"] = true
	var tot := 0
	for i in n:
		tot += int(_CB.calc_damage(a, d, mv, rng, c).dmg)
	return tot / float(n)

func _crit_rate(a: Mon, d: Mon, mv: Dictionary, n := 4000) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var k := 0
	for i in n:
		if _CB.calc_damage(a, d, mv, rng, {"skip_accuracy2": true}).crit:
			k += 1
	return k / float(n)

func _combat() -> void:
	_SKY.fs = null; _CB.sky_floor = null
	var tackle = _CB.move("Tackle")
	var ember = _CB.move("Ember")
	var plain := _team("0004", 30, [])
	var foe: Mon = _db.make_mon("0074", 30, "enemy")     # Geodude (Rock/Ground)
	var foe2: Mon = _db.make_mon("0016", 30, "enemy")    # Pidgey
	var base := _avg_dmg(plain, foe2, tackle)
	var agg := _avg_dmg(_team("0004", 30, ["aggressor"]), foe2, tackle)
	var dfd := _avg_dmg(_team("0004", 30, ["defender"]), foe2, tackle)
	print("  Tackle avg: plain %.2f  Aggressor %.2f  Defender %.2f" % [base, agg, dfd])
	ok(agg > base * 1.1, "Aggressor raises damage dealt")
	ok(dfd < base * 0.95, "Defender lowers damage dealt")
	# damage taken: wild attacker vs team defender
	var wild: Mon = _db.make_mon("0020", 60, "enemy")   # Raticate Lv 60 hitting Lv 30 defenders
	var tk0 := _avg_dmg(wild, _team("0004", 30, []), tackle)
	var tk_agg := _avg_dmg(wild, _team("0004", 30, ["aggressor"]), tackle)
	var tk_def := _avg_dmg(wild, _team("0004", 30, ["defender"]), tackle)
	var tk_cb := _avg_dmg(wild, _team("0004", 30, ["counter_basher"]), tackle)
	var tk_cb_sp := _avg_dmg(wild, _team("0004", 30, ["counter_basher"]), _CB.move("Water Gun"))
	var tk_sp0 := _avg_dmg(wild, _team("0004", 30, []), _CB.move("Water Gun"))
	print("  taken: plain %.2f  Aggressor %.2f  Defender %.2f  Counter Basher %.2f" % [tk0, tk_agg, tk_def, tk_cb])
	ok(tk_agg > tk0 and tk_def < tk0 and tk_cb > tk0, "Aggressor/Counter Basher take more, Defender less")
	ok(absf(tk_cb_sp - tk_sp0) < 0.01, "Counter Basher's Defense drop is physical only")
	# Practice Swinger
	var ps := _team("0004", 30, ["practice_swinger"])
	var whiff := {"name": "Whiff", "t": "Normal", "p": 10, "a1": 0, "a2": 0, "crit": 0}
	var rng := RandomNumberGenerator.new()
	ok(not _CB.accuracy_hits(ps, foe2, whiff, rng, {}) and ps.has_meta("practice_swinger"), "Practice Swinger flag set on a miss")
	var r1 := RandomNumberGenerator.new(); r1.seed = 5
	var r2 := RandomNumberGenerator.new(); r2.seed = 5
	var boosted := int(_CB.calc_damage(ps, foe2, tackle, r1, {"skip_accuracy2": true}).dmg)
	ok(not ps.has_meta("practice_swinger"), "flag used up by the next attack")
	var normal := int(_CB.calc_damage(ps, foe2, tackle, r2, {"skip_accuracy2": true}).dmg)
	ok(boosted > normal, "Practice Swinger: next attack after a miss hits harder (%d > %d)" % [boosted, normal])
	ok(not _CB.accuracy_hits(plain, foe2, whiff, rng, {}) and not plain.has_meta("practice_swinger"), "no flag without the skill")
	# Cheerleader (needs the floor)
	var f = _floor()
	var att := _team("0004", 30, [])
	var cheer := _team("0001", 30, ["cheerleader"])
	att.pos = Vector2i(5, 5)
	cheer.pos = Vector2i(5, 6)
	foe2.pos = Vector2i(6, 5)
	f.mons = [att, cheer, foe2]
	var with_cheer := _avg_dmg(att, foe2, tackle, 2000, {"fs": f})
	cheer.pos = Vector2i(9, 9)
	var far := _avg_dmg(att, foe2, tackle, 2000, {"fs": f})
	ok(with_cheer > far * 1.1 and absf(far - base) < 0.5, "Cheerleader next to the attacker raises its damage (%.2f vs %.2f)" % [with_cheer, far])
	# crits
	var ra = _CB.regular_attack()
	var c0 := _crit_rate(_team("0004", 30, []), foe2, ra)
	var c1 := _crit_rate(_team("0004", 30, ["sharpshooter"]), foe2, ra)
	print("  crit rate: plain %.3f  Sharpshooter %.3f" % [c0, c1])
	ok(absf(c0 - 0.12) < 0.025 and absf(c1 - 0.27) < 0.03, "Sharpshooter: crit odds 12 -> 27")
	var fe: Mon = _db.make_mon("0019", 30, "enemy")
	fe.status.focus_energy = 5
	ok(_crit_rate(fe, _team("0004", 30, []), tackle, 200) > 0.99, "Focus Energy always crits (control)")
	ok(_crit_rate(fe, _team("0004", 30, ["critical_dodger"]), tackle, 500) == 0.0, "Critical Dodger: no crits taken")
	# Erratic Player: Ember vs Bug (super effective) and vs Rock (not very effective)
	var bug: Mon = _db.make_mon("0010", 30, "enemy")    # Caterpie
	var se0 := _avg_dmg(_team("0004", 30, []), bug, ember)
	var se1 := _avg_dmg(_team("0004", 30, ["erratic_player"]), bug, ember)
	var nv0 := _avg_dmg(_team("0004", 30, []), foe, ember)
	var nv1 := _avg_dmg(_team("0004", 30, ["erratic_player"]), foe, ember)
	print("  Erratic: SE %.2f -> %.2f   NVE %.2f -> %.2f" % [se0, se1, nv0, nv1])
	ok(se1 > se0 * 1.08 and nv1 < nv0, "Erratic Player: super effective harder, resisted weaker")
	var se2 := _avg_dmg(wild, _team("0074", 30, ["erratic_player"]), _CB.move("Water Gun"))
	var se3 := _avg_dmg(wild, _team("0074", 30, []), _CB.move("Water Gun"))
	ok(se2 > se3, "Erratic Player also affects moves that hit it")
	# accuracy / evasion
	var acc0 = _CB.accuracy_threshold(_team("0004", 30, []), foe2, tackle, {})
	var acc1 = _CB.accuracy_threshold(_team("0004", 30, ["concentrator"]), foe2, tackle, {})
	var ev0 = _CB.accuracy_threshold(wild, _team("0004", 30, []), tackle, {})
	var ev1 = _CB.accuracy_threshold(wild, _team("0004", 30, ["concentrator"]), tackle, {})
	ok(acc1 > acc0 and ev1 > ev0, "Concentrator: more accurate, easier to hit (%d>%d, %d>%d)" % [acc1, acc0, ev1, ev0])
	var cp := _team("0004", 30, ["clutch_performer"])
	var cp_full = _CB.accuracy_threshold(wild, cp, tackle, {})
	cp.hp = maxi(1, cp.max_hp / 4)
	var cp_low = _CB.accuracy_threshold(wild, cp, tackle, {})
	ok(cp_full == ev0 and cp_low < cp_full, "Clutch Performer: harder to hit at low HP only")
	_SKY.fs = null; _CB.sky_floor = null

func _floor(w := 20, h := 12):
	var f = _FS.new()
	var t := PackedByteArray()
	t.resize(w * h)
	var rm := PackedByteArray()
	rm.resize(w * h)
	for y in h:
		for x in w:
			t[y * w + x] = 0 if (x == 0 or y == 0 or x == w - 1 or y == h - 1) else 1
			rm[y * w + x] = 0
	f.setup({"w": w, "h": h, "terrain": t, "room": rm, "flags": PackedInt32Array(), "stairs": Vector2i(15, 8)})
	f.flags.resize(w * h)
	f.rng.seed = 4242
	return f

# ------------------------------------------------------------------ turn rules
func _turns() -> void:
	var a := _team("0004", 20, [])
	var b := _team("0004", 20, ["time_tripper"])
	ok(_TR.speed_stage(b) == _TR.speed_stage(a) + 1, "Time Tripper: speed stage +1")
	var w: Mon = _db.make_mon("0004", 20, "enemy")
	w.iq_skills = ["time_tripper"]
	ok(_TR.speed_stage(w) == _TR.speed_stage(a), "Time Tripper ignored on wild Pokémon")
	var h0 := _team("0004", 30, [])
	var h1 := _team("0004", 30, ["quick_healer"])
	h0.hp = 1
	h1.hp = 1
	var g0 := 0
	var g1 := 0
	for i in 40:
		g0 += _TR.regen(h0)
		g1 += _TR.regen(h1)
	ok(g1 >= g0 * 2 - 1 and g0 > 0, "Quick Healer: regenerates twice as fast (%d vs %d)" % [g1, g0])

# ------------------------------------------------------------------ hooks
func _hooks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var none := _team("0004", 20, [])
	ok(_SKY.money_pickup(_team("0004", 20, ["coin_watcher"]), 100) == 120 and _SKY.money_pickup(none, 100) == 100, "Coin Watcher x1.2")
	ok(_SKY.exp_gain(_team("0004", 20, ["exp_elite"]), 100) == 110 and _SKY.exp_gain(none, 100) == 100, "Exp. Elite +10%")
	var ff := _team("0004", 20, ["fast_friend"])
	ok(_SKY.recruit_bonus(ff) == 50 and _SKY.recruit_bonus([ff, none]) == 50 and _SKY.recruit_bonus([none, ff]) == 0, "Fast Friend +50 (leader only)")
	var hag := _team("0004", 20, ["haggler"])
	ok(_SKY.shop_price(hag, 100, true) == 80 and _SKY.shop_price(hag, 100, false) == 120 and _SKY.shop_price(none, 100, true) == 100, "Haggler prices")
	var ent := _e("0004", 20, 999)
	_IQ.set_skill(ent, "haggler", true)
	ok(_SKY.shop_price(ent, 100, true) == 80, "Haggler works on a team entry (town)")
	# strikes
	var qs := _team("0004", 20, ["quick_striker"])
	var es := _team("0004", 20, ["extra_striker"])
	var two := 0
	var ok_q := true
	for i in 3000:
		ok_q = ok_q and _SKY.regular_attack_hits(qs, rng) == 2
		if _SKY.regular_attack_hits(es, rng) == 2:
			two += 1
		ok_q = ok_q and _SKY.regular_attack_hits(none, rng) == 1
	ok(ok_q, "Quick Striker always 2, none always 1")
	ok(absf(two / 3000.0 - 0.33) < 0.04, "Extra Striker ~1/3 double strikes (%.3f)" % (two / 3000.0))
	# PP
	var pps := _team("0004", 20, ["pp_saver"])
	var free := 0
	for i in 3000:
		if _SKY.pp_cost(pps, "Ember", rng) == 0:
			free += 1
	ok(absf(free / 3000.0 - 0.30) < 0.04, "PP Saver ~30%% free (%.3f)" % (free / 3000.0))
	var cm: Array = _IQ.data().get("charge_moves", [])
	ok(cm.size() > 0 and _SKY.pp_cost(_team("0004", 20, ["no_charger"]), str(cm[0]), rng) == 2 and _SKY.skips_charge(_team("0004", 20, ["no_charger"]), str(cm[0])), "No-Charger: 2 PP, no charge turn")
	ok(_SKY.pp_cost(none, "Ember", rng) == 1 and _SKY.pp_cost(none, str(cm[0]), rng) == 1 and not _SKY.skips_charge(none, str(cm[0])), "no skill: 1 PP")
	# traps
	var tb := _team("0004", 20, ["trap_buster"])
	var broke := 0
	for i in 3000:
		if _SKY.trap_breaks(tb, rng):
			broke += 1
	ok(absf(broke / 3000.0 - 0.30) < 0.04, "Trap Buster ~30%% (%.3f)" % (broke / 3000.0))
	# items
	ok(_SKY.heal_amount(_team("0004", 20, ["wise_healer"]), 100) == 115 and _SKY.heal_amount(none, 100) == 100, "Wise Healer +15%")
	ok(is_equal_approx(_SKY.food_bonus(_team("0004", 20, ["survivalist"]), 50.0), 75.0) and _SKY.food_bonus(none, 50.0) == 50.0, "Survivalist food x1.5")
	ok(_SKY.thrown_damage(_team("0004", 20, ["power_pitcher"]), 4) == 6 and _SKY.thrown_damage(none, 4) == 4, "Power Pitcher x1.5")
	# floor start
	var d := FakeDungeon.new()
	var f = _floor()
	d.fs = f
	var L := _team("0004", 20, ["stair_sensor", "acute_sniffer", "deep_breather", "map_surveyor"])
	L.is_leader = true
	L.pos = Vector2i(3, 3)
	f.leader = L
	f.mons = [L]
	d.team_mons = [L]
	f.items[Vector2i(4, 4)] = {"id": "oran", "n": 1}
	f.items[Vector2i(6, 4)] = {"id": "poke", "n": 30}
	for mv in L.moves:
		mv.pp = 0
	var msgs = _SKY.on_floor_start(d)
	ok(_SKY.fs == f, "on_floor_start remembers the floor")
	ok(f.explored[f.idx(f.stairs)] == 1 and msgs.has("The stairs seem to be over this way!"), "Stair Sensor reveals the stairs")
	ok(f.explored[f.idx(Vector2i(10, 6))] == 1 and f.explored[f.idx(Vector2i(0, 0))] == 0, "Map Surveyor reveals the floor layout")
	ok(msgs.has("Total items on this floor: 2."), "Acute Sniffer counts items: %s" % [msgs])
	ok(L.moves.all(func(mv): return int(mv.pp) == mini(2, int(mv.max_pp))), "Deep Breather +2 PP each move")
	var f2 = _floor()
	var d2 := FakeDungeon.new()
	d2.fs = f2
	var L2 := _team("0004", 20, [])
	f2.mons = [L2]
	ok(_SKY.on_floor_start(d2).is_empty() and f2.explored[f2.idx(f2.stairs)] == 0, "no skills: floor start does nothing")
	# Bodyguard / Intimidator
	f = _floor()
	d.fs = f
	d.log.clear()
	var weak := _team("0007", 20, [])
	var guard := _team("0001", 20, ["bodyguard"])
	var enemy: Mon = _db.make_mon("0019", 20, "enemy")
	weak.pos = Vector2i(5, 5)
	guard.pos = Vector2i(4, 5)
	enemy.pos = Vector2i(6, 5)
	f.mons = [weak, guard, enemy]
	ok(_SKY.before_hit(d, enemy, weak) == weak, "Bodyguard waits while the friend's HP is fine")
	weak.hp = maxi(1, weak.max_hp / 4)
	ok(_SKY.before_hit(d, enemy, weak) == guard and d.log.size() == 1, "Bodyguard takes the hit for a low-HP teammate")
	ok(_SKY.before_hit(d, enemy, guard) == guard, "Bodyguard doesn't redirect hits on itself")
	var intim := _team("0004", 20, ["intimidator"])
	intim.pos = Vector2i(5, 5)
	f.mons = [intim, enemy]
	var blocked := 0
	for i in 2000:
		enemy.status.cringe = 0
		if _SKY.before_hit(d, enemy, intim) == null:
			blocked += 1
	ok(absf(blocked / 2000.0 - 0.32) < 0.04 and enemy.status.cringe >= 0, "Intimidator ~32%% (%.3f)" % (blocked / 2000.0))
	enemy.pos = Vector2i(8, 5)
	var far_block := false
	for i in 200:
		far_block = far_block or _SKY.before_hit(d, enemy, intim) == null
	ok(not far_block, "Intimidator only vs adjacent attackers")
	# loop variable can be reassigned (how the lead wires before_hit into do_attack's target loop)
	var arr := [weak]
	var seen: Array = []
	for t in arr:
		t = guard
		seen.append(t)
	ok(seen[0] == guard, "GDScript lets the for-loop variable be reassigned")
	# counters
	f = _floor()
	d.fs = f
	var cb := _team("0004", 30, ["counter_basher"])
	var ch := _team("0004", 30, ["counter_hitter"])
	var att: Mon = _db.make_mon("0019", 30, "enemy")
	cb.pos = Vector2i(5, 5)
	att.pos = Vector2i(6, 5)
	f.mons = [cb, att]
	var back := 0
	var times := 0
	for i in 3000:
		att.hp = att.max_hp
		await _SKY.after_hit(d, att, cb, 40, true)
		if att.hp < att.max_hp:
			times += 1
			back = att.max_hp - att.hp
	ok(absf(times / 3000.0 - 0.10) < 0.025 and back == mini(40, att.max_hp), "Counter Basher ~10%%, all the damage back (%.3f, %d)" % [times / 3000.0, back])
	ch.pos = cb.pos
	f.mons = [ch, att]
	times = 0
	for i in 3000:
		att.hp = att.max_hp
		await _SKY.after_hit(d, att, ch, 40, true)
		if att.hp < att.max_hp:
			times += 1
			back = att.max_hp - att.hp
	ok(absf(times / 3000.0 - 0.24) < 0.03 and back == 10, "Counter Hitter ~24%%, 1/4 back (%.3f, %d)" % [times / 3000.0, back])
	att.hp = att.max_hp
	var sp_back := false
	for i in 300:
		await _SKY.after_hit(d, att, ch, 40, false)
		sp_back = sp_back or att.hp < att.max_hp
	ok(not sp_back, "no counter for special moves")
	var hr: Mon = _team("0019", 30, ["hit_and_runner"])
	hr.side = "enemy"   # a hit-and-runner attacker (side only matters for adjacency here)
	hr.pos = att.pos
	f.mons = [ch, hr]
	times = 0
	for i in 4000:
		hr.hp = hr.max_hp
		await _SKY.after_hit(d, hr, ch, 40, true)
		if hr.hp < hr.max_hp:
			times += 1
	ok(absf(times / 4000.0 - 0.24 * 0.67) < 0.03, "Hit-and-Runner dodges a third of the counters (%.3f)" % (times / 4000.0))
	att.hp = 5
	f.mons = [cb, att]
	d.fainted.clear()
	var guard_n := 0
	while att.hp > 0 and guard_n < 500:
		await _SKY.after_hit(d, att, cb, 40, true)
		guard_n += 1
	ok(d.fainted.has(att), "a counter KO calls dungeon.faint")
	# Wary Fighter
	f = _floor()
	d.fs = f
	var wf := _team("0004", 20, ["wary_fighter"])
	var tgt: Mon = _db.make_mon("0019", 20, "enemy")
	wf.pos = Vector2i(5, 5)
	tgt.pos = Vector2i(6, 5)
	f.mons = [wf, tgt]
	ok(_SKY.after_miss(d, wf, tgt) and wf.pos == Vector2i(4, 5), "Wary Fighter steps back after a miss")
	ok(not _SKY.after_miss(d, none, tgt), "no step without the skill")
	# throws
	f = _floor()
	d.fs = f
	var th := _team("0004", 20, [])
	var mate := _team("0001", 20, [])
	var e1: Mon = _db.make_mon("0019", 20, "enemy")
	var e2: Mon = _db.make_mon("0019", 20, "enemy")
	th.pos = Vector2i(2, 5)
	mate.pos = Vector2i(3, 5)
	e1.pos = Vector2i(5, 5)
	e2.pos = Vector2i(7, 5)
	f.mons = [th, mate, e1, e2]
	var right := 2   # DB.DIRS index for +x
	for k in 8:
		if _db.DIRS[k] == Vector2i(1, 0):
			right = k
	var p0 = _SKY.throw_path(d, th, right)
	ok(p0.hits == [mate], "normal throw hits the first Pokémon (the teammate)")
	th.iq_skills = ["gap_prober"]
	ok(_SKY.throw_path(d, th, right).hits == [e1], "Gap Prober flies past the teammate")
	th.iq_skills = ["gap_prober", "course_checker"]
	ok(_SKY.throw_path(d, th, right).hits == [mate], "Gap Prober needs Course Checker off")
	th.iq_skills = ["pierce_hurler"]
	f.terrain[f.idx(Vector2i(6, 5))] = 0    # a wall between e1 and e2
	var pp = _SKY.throw_path(d, th, right)
	ok(pp.hits == [mate, e1, e2], "Pierce Hurler hits everyone in the line, through walls: %s" % [pp.hits.map(func(x): return x.name)])
	th.iq_skills = []
	f.mons = [th]
	var pe = _SKY.throw_path(d, th, right)
	ok(pe.hits.is_empty() and pe.end == Vector2i(5, 5), "a miss lands before the wall")
	ok(_SKY.passes_through(_team("0004", 20, ["gap_prober"]), mate) and not _SKY.passes_through(_team("0004", 20, ["gap_prober"]), e1), "passes_through: teammates only")
	# trap busting, nature gifter, collector
	f = _floor()
	d.fs = f
	var tbm := _team("0004", 20, ["trap_buster"])
	f.traps[Vector2i(3, 3)] = {"id": "poison", "seen": false}
	var busted := false
	for i in 60:
		if _SKY.try_bust_trap(d, tbm, Vector2i(3, 3)):
			busted = true
			break
	ok(busted and not f.traps.has(Vector2i(3, 3)), "try_bust_trap removes the trap")
	ok(not _SKY.try_bust_trap(d, none, Vector2i(3, 3)), "no trap, no bust")
	var ng := _team("0004", 20, ["nature_gifter"])
	ng.is_leader = true
	var mate2 := _team("0001", 20, [])
	f.mons = [ng, mate2]
	var heal_id := ""
	for k in _db.items:
		if str(_db.items[k].get("kind", "")) == "heal":
			heal_id = k
			break
	ok(_SKY.nature_gifter_targets(d, ng, heal_id) == [mate2], "Nature Gifter spreads a healing item (%s)" % heal_id)
	ok(_SKY.nature_gifter_targets(d, ng, "apple").is_empty() and _SKY.nature_gifter_targets(d, mate2, heal_id).is_empty(), "Nature Gifter: healing items, leader only")
	var col := _team("0004", 20, ["collector"])
	var victim: Mon = _db.make_mon("0019", 20, "enemy")
	victim.pos = Vector2i(8, 8)
	var drops := 0
	for i in 2000:
		f.items.clear()
		if _SKY.collector_drop(d, col, victim):
			drops += 1
	ok(absf(drops / 2000.0 - 0.10) < 0.025 and f.items.size() <= 1, "Collector ~10%% drops (%.3f)" % (drops / 2000.0))
	f.items.clear()
	var nd := false
	for i in 200:
		nd = nd or _SKY.collector_drop(d, none, victim)
	ok(not nd, "no drops without Collector")
	_SKY.fs = null; _CB.sky_floor = null
