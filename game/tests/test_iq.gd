extends SceneTree
## Headless test for res://scripts/core/iq.gd + res://data/iq.json (Red's IQ skills, tactics, gummis,
## Gulpin link rules). Run: godot --headless --path . --script tests/test_iq.gd
## Nothing is saved.

var fails := 0
var checks := 0
var _db
var _AI
var _CB

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	var db = root.get_node_or_null("DB")
	_db = db
	_AI = load("res://scripts/core/ai.gd")
	_CB = load("res://scripts/core/combat.gd")
	if db and db.species.is_empty():
		db._ready()
	var I = load("res://scripts/core/iq.gd")
	ok(not I.data().is_empty(), "iq.json loads")
	ok(I.data().skills.filter(func(s): return not s.get("sky", false)).size() == 23, "23 Red IQ skills (Sky add-on skills are flagged \"sky\")")
	_skills(I)
	_gummis(I)
	_tactics(I)
	_links(I)
	_remember(I)
	print("test_iq: %d checks, %d failed" % [checks, fails])
	quit(1 if fails > 0 else 0)

func _e(sp: String, L := 5, iq := 0) -> Dictionary:
	return {"sp": sp, "name": _db.species[sp].name, "level": L, "exp": 0, "moves": _db.default_moves(sp, L), "iq": iq, "held": "", "bonus": {}}

func _skills(I) -> void:
	var e := _e("0025")
	# Red's thresholds (gReqIQSkillPts) -- same for every species, no IQ groups in Red
	var want := {"item_catcher": 1, "course_checker": 1, "pp_checker": 2, "efficiency_expert": 10, "status_checker": 25,
		"nontraitor": 40, "self_curer": 70, "quick_dodger": 100, "type_advantage_master": 105, "weak_type_picker": 125,
		"trap_avoider": 140, "nonsleeper": 160, "exp_go_getter": 200, "energy_saver": 250, "lava_evader": 300,
		"all_terrain_hiker": 400, "sure_hit_attacker": 500, "trap_seer": 600, "house_avoider": 800, "super_mobile": 990,
		"dedicated_traveler": 1, "item_master": 1, "exclusive_move_user": 1}
	for id in want:
		ok(int(I.skill(id).get("iq", -1)) == want[id], "threshold " + id)
		e.iq = want[id] - 1
		var before: bool = I.skills_for(e).filter(func(s): return s.id == id)[0].unlocked
		e.iq = want[id]
		var after: bool = I.skills_for(e).filter(func(s): return s.id == id)[0].unlocked
		ok((not before or want[id] == 1) and after, "unlocks exactly at IQ %d: %s" % [want[id], id])
	# defaults (SetDefaultIQSkills) and IQ 0 counting as 1
	var n := _e("0001")
	ok(I.has(n, "item_catcher") and I.has(n, "course_checker") and I.has(n, "item_master"), "default skills on")
	ok(not I.has(n, "exclusive_move_user") and not I.has(n, "dedicated_traveler"), "other IQ-1 skills start off")
	# exclusive slots (sIQSkillGroups)
	n.iq = 600
	ok(I.set_skill(n, "type_advantage_master", true), "switch on TAM")
	ok(I.set_skill(n, "quick_dodger", true), "switch on Quick Dodger")
	ok(I.has(n, "quick_dodger") and not I.has(n, "type_advantage_master"), "group 4 is exclusive")
	ok(I.set_skill(n, "sure_hit_attacker", true) and not I.has(n, "quick_dodger"), "Sure-Hit replaces Quick Dodger")
	ok(I.set_skill(n, "efficiency_expert", true) and I.set_skill(n, "weak_type_picker", true) and not I.has(n, "efficiency_expert"), "group 9 exclusive")
	n.iq = 50
	ok(not I.set_skill(n, "quick_dodger", true), "locked skill can't be switched on")
	ok(not I.has(n, "sure_hit_attacker"), "switched-on skill inactive while IQ too low")
	ok(I.set_skill(n, "item_catcher", false) and not I.has(n, "item_catcher"), "switch off")
	ok("iq_on" in n and not "item_catcher" in n.iq_on, "persisted in entry.iq_on")
	# Mon adapter -> m.iq_skills for AI / Combat
	var g = root.get_node("Game")
	var m = g.mon_from_entry(_e("0025", 10, 120))
	I.apply(m)
	ok(_AI.iq(m, "item catcher") and _AI.iq(m, "course checker") and not _AI.iq(m, "quick dodger"), "_AI.iq sees applied skills")
	I.set_skill(m, "quick_dodger", true)
	ok(_CB.has_iq(m, "Quick Dodger") and _AI.iq(m, "quick dodger"), "set_skill on Mon refreshes iq_skills")
	ok("quick_dodger" in m.get_meta("entry").iq_on, "Mon writes through to its entry")
	var msgs: Array = I.on_iq_changed(m, 90)
	# (the Sky add-on also unlocks Brick-Tough at IQ 100, listed after Red's skills)
	ok(msgs.size() >= 2 and msgs[0].contains("Type-Advantage Master") and msgs[1].contains("Quick Dodger") \
		and (msgs.size() == 2 or msgs.slice(2).all(func(x): return str(x).contains("Brick-Tough"))), "on_iq_changed lists TAM + Quick Dodger: %s" % [msgs])

func _gummis(I) -> void:
	# gTypeGummiIQBoost[type1][g] + [type2][g]
	var cases := [["0004", "redgummi", 7], ["0004", "bluegummi", 4], ["0001", "grassgummi", 9], ["0001", "redgummi", 7],
		["0094", "whitegummi", 4], ["0081", "pinkgummi", 4], ["0050", "yellowgummi", 1], ["0007", "silvergummi", 2],
		["0035", "whitegummi", 7], ["0149", "royalgummi", 10]]
	for c in cases:
		ok(I.gummi_gain(_e(c[0]), c[1]) == c[2], "gummi %s on %s = %d (got %d, types %s)" % [c[1], c[0], c[2], I.gummi_gain(_e(c[0]), c[1]), I.types_of(_e(c[0]))])
	ok(I.taste(9) == 0 and I.taste(8) == 1 and I.taste(5) == 1 and I.taste(4) == 2 and I.taste(3) == 2 and I.taste(2) == 3, "taste buckets")
	var e := _e("0004", 5, 0)
	var r: Dictionary = I.eat_gummi(e, "redgummi", false)
	ok(r.ok and int(e.iq) == 8 and r.iq_gain == 7, "town gummi: IQ 0(=1) + 7 = 8 (got %d)" % int(e.iq))
	ok(str(r.msgs[0]).contains("looks like a favorite!"), "town favorite line")
	ok(r.learned.has("pp_checker"), "learned PP Checker at IQ 8")
	var bsum := 0
	for k in e.bonus:
		bsum += int(e.bonus[k])
	ok(bsum >= 1, "town gummi raised a stat")
	e.iq = 995
	r = I.eat_gummi(e, "redgummi", true)
	ok(int(e.iq) == 999 and r.iq_gain == 4, "IQ capped at 999")
	ok(r.msgs[0] == "It seems to like this Gummi!" and r.msgs[1] == "IQ went up somewhat!", "dungeon lines use raw / clamped gain: %s" % [r.msgs])
	r = I.eat_gummi(e, "redgummi", true)
	ok(r.msgs == ["Its IQ didn't change."], "no change at 999")
	ok(int(r.belly) == 60, "Fire + Red Gummi fills 60 belly (got %d)" % int(r.belly))
	r = I.eat_gummi(_e("0004"), "oran", false)
	ok(not r.ok and r.msgs[0] == "It doesn't appear to be hungry.", "non-gummi in town")
	# every species resolves to a Red typing for the gummi table
	var bad := 0
	for sp in _db.species:
		var best := 0
		for gm in I.data().gummis:
			best = maxi(best, I.gummi_gain(_e(sp), gm))
		if best < 3:
			bad += 1
	ok(bad == 0, "every species has a gummi it likes (%d bad)" % bad)

func _tactics(I) -> void:
	var counts := {1: 3, 9: 3, 10: 4, 15: 5, 20: 6, 25: 7, 34: 7, 35: 8, 40: 9, 100: 9}
	for L in counts:
		ok(I.tactics_for(_e("0025", L)).size() == counts[L], "tactics at Lv %d = %d" % [L, counts[L]])
	for id in I.TACTICS:
		ok(int(I.tactic_info(id).level) == int(_AI.TACTIC_LEVELS[id]), "tactic level matches AI: " + id)
	var e := _e("0025", 12)
	ok(not I.set_tactic(e, "wait_there"), "Wait there locked at Lv 12")
	ok(I.set_tactic(e, "get_away") and e.tactic == "get_away", "Get away at Lv 12")
	var m = root.get_node("Game").mon_from_entry(e)
	I.apply(m)
	ok(_AI.tactic_of(m) == "get_away", "AI reads applied tactic")

func _mv(names: Array, linked := []) -> Array:
	var out: Array = []
	for i in names.size():
		out.append({"name": names[i], "pp": 10, "max_pp": 10, "on": true, "linked": i in linked})
	return out

func _links(I) -> void:
	var mv := _mv(["Tackle", "Growl", "Solarbeam", "Ember"])
	ok(I.link(mv, 0) and mv[1].linked, "link Tackle+Growl")
	ok(not I.can_link(mv, 0), "can't link into Solarbeam (charging)")
	ok(not I.can_link(mv, 2), "Solarbeam can't be linked")
	ok(I.delink(mv, 0) and not mv[1].linked, "delink")
	ok(not I.delink(mv, 0), "nothing to delink")
	mv = _mv(["Tackle", "Growl", "Ember", "Scratch"])
	ok(I.link(mv, 0) and I.link(mv, 0) and I.link(mv, 0) and mv[3].linked, "chain of 4")
	ok(not I.can_link(mv, 0) and not I.can_forget(mv), "full chain: no more links, can't forget the only chain")
	mv = _mv(["Tackle", "Growl", "Ember", "Scratch"], [1])
	ok(I.link(mv, 2) and mv[3].linked and I.chains(mv).size() == 2, "link second pair")
	mv = _mv(["Tackle", "Growl", "Ember"], [1])
	I.forget(mv, 0)
	ok(mv.size() == 1 and mv[0].name == "Ember" and not mv[0].linked, "forget removes linked moves after it")
	mv = _mv(["A", "B", "C"], [2])
	ok(I.shift_up(mv, 2) and mv[0].name == "B" and mv[1].name == "C" and mv[1].linked and mv[2].name == "A" and not mv[0].linked, "shift chain up")
	mv = _mv(["A", "B"])
	mv[0].on = false
	I.link(mv, 0)
	ok(not mv[1].on, "chain shares head's switch")

func _remember(I) -> void:
	var e := _e("0002", 20)
	e.moves = [{"name": "Tackle", "pp": 1, "max_pp": 22, "on": true, "linked": false}]
	var r: Array = I.rememberable(e)
	ok("Growl" in r and "Vine Whip" in r and not "Tackle" in r, "Ivysaur remembers Bulbasaur moves: %s" % [r])
	ok(not "Solarbeam" in r, "not above its level")
	ok(I.rememberable(_e("0386", 50)).is_empty() and not I.can_remember(_e("0386", 50)), "Deoxys can't remember")
	I.remember(e, "Growl")
	ok(e.moves.size() == 2 and e.moves[1].name == "Growl" and int(e.moves[1].pp) == 0, "remembered with 0 PP")
	e.moves = _mv(["Tackle", "Growl", "Vine Whip", "Razor Leaf"], [1])
	var gone: Array = I.remember(e, "Leech Seed", 0)
	ok(gone == ["Tackle", "Growl"] and e.moves.size() == 3 and e.moves[2].name == "Leech Seed", "remember forgetting a linked chain")
	# ultimate moves need IQ 333
	for sp in _db.species:
		for l in _db.species[sp].get("learn", []):
			if str(l[1]) == "Frenzy Plant":
				var v := _e(sp, 100, 100)
				v.moves = []
				ok(not "Frenzy Plant" in I.rememberable(v), "Frenzy Plant locked below IQ 333 (%s)" % sp)
				v.iq = 333
				ok("Frenzy Plant" in I.rememberable(v), "Frenzy Plant at IQ 333 (%s)" % sp)
				return
