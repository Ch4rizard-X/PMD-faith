extends SceneTree
## Headless test for res://scripts/ui/quiz.gd + res://data/quiz.json (PMD Red's personality test).
## Run: godot --headless --path . --script tests/test_quiz.gd
## Work happens in _initialize() so the DB autoload exists; Quiz is loaded at runtime.

var Q
var dbn
var fails := 0
var checks := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", msg)

func _initialize() -> void:
	dbn = root.get_node_or_null("DB")
	if dbn and dbn.species.is_empty():
		dbn._ready()
	Q = load("res://scripts/ui/quiz.gd")
	var D: Dictionary = Q.data()
	ok(not D.is_empty(), "quiz.json loads")
	var names: Array = Q.nature_names()
	ok(names.size() == 13, "13 natures")
	ok(D.questions.size() == 56 and int(D.num_selectable) == 55, "55 questions + Brave 2B")
	ok(int(D.questions_asked) == 8, "8 questions asked")

	# ---- texts non-empty, answers valid
	for p in D.intro:
		ok(p.segs.size() > 0 and str(p.segs[0]).strip_edges() != "", "intro page text")
	for q in D.questions:
		ok(q.pages.size() > 0, "%s has pages" % q.id)
		for p in q.pages:
			for s in p.segs:
				ok(str(s).strip_edges() != "", "%s segment text" % q.id)
		ok(q.answers.size() >= 2 and q.answers.size() <= 5, "%s answer count" % q.id)
		for a in q.answers:
			ok(str(a.text).strip_edges() != "", "%s answer text" % q.id)
			ok(not a.points.is_empty() or a.has("followup"), "%s answer gives points" % q.id)
			for k in a.points:
				ok(names.has(k), "%s points to known nature %s" % [q.id, k])
		ok(names.has(q.category) or q.category == "Misc", "%s category" % q.id)
	for n in D.natures:
		ok(n.pages.size() >= 3, "%s description pages" % n.name)
		for p in n.pages:
			for s in p.segs:
				ok(str(s).strip_edges() != "", "%s description text" % n.name)
		for g in ["male", "female"]:
			var sp: String = Q.starter_for(n.name, g)
			ok(dbn.species.has(sp), "%s/%s starter %s is a species" % [n.name, g, sp])
			ok(Q.partner_options(sp).size() > 0, "%s has partners" % sp)
			ok(not Q.partner_options(sp).has(sp), "%s can't partner itself" % sp)
	ok(D.gender.answers.size() == 2, "gender answers")
	ok(str(D.starter_reveal).contains("{pokemon}"), "reveal placeholder")
	for p in D.partners:
		ok(dbn.species.has(p), "partner %s is a species" % p)

	# ---- spot checks against the decomp
	ok(Q.starter_for("Hardy", "male") == "0004" and Q.starter_for("Hardy", "female") == "0025", "Hardy -> Charmander / Pikachu")
	ok(Q.starter_for("Quirky", "male") == "0052" and Q.starter_for("Quirky", "female") == "0252", "Quirky -> Meowth / Treecko")
	ok(Q.partner_options("0004") == ["0001", "0007", "0025", "0152", "0158", "0252", "0258"], "Charmander partners exclude Fire")
	ok(not Q.partner_options("0001").has("0152") and not Q.partner_options("0001").has("0252"), "Bulbasaur partners exclude Grass")

	# ---- tie-break: random start, first strictly-higher in cyclic order
	var t: Dictionary = Q.empty_totals()
	t["Docile"] = 4; t["Lonely"] = 4
	ok(Q.resolve_nature(t, 0) == "Docile", "tie from Hardy -> Docile")
	ok(Q.resolve_nature(t, 5) == "Lonely", "tie from Naive -> Lonely")
	ok(Q.resolve_nature(t, 12) == "Docile", "tie from Quirky wraps -> Docile")
	ok(Q.resolve_nature(Q.empty_totals(), 7) == "Hasty", "all zero -> random start")

	# ---- selection: 8 distinct categories per run
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for run in 2000:
		var used: Array = Q.new_used()
		var cats := {}
		for k in 8:
			var qi: int = Q.next_question(used, rng)
			ok(qi >= 0 and qi < 55, "question index in range")
			var c: String = D.questions[qi].category
			ok(not cats.has(c), "no repeated category")
			cats[c] = true
		if fails > 20:
			break

	# ---- every nature reachable: random runs, plus a greedy search per target nature
	var seen := {}
	var seen_start := {}
	for run in 20000:
		var used: Array = Q.new_used()
		var tot: Dictionary = Q.empty_totals()
		for k in 8:
			var qi: int = Q.next_question(used, rng)
			while qi >= 0:
				var q: Dictionary = D.questions[qi]
				var a: Dictionary = q.answers[rng.randi_range(0, q.answers.size() - 1)]
				Q.add_points(tot, a)
				qi = int(a.get("followup", -1))
		var nat: String = Q.resolve_nature(tot, rng.randi_range(0, 12))
		seen[nat] = int(seen.get(nat, 0)) + 1
	for n in names:
		ok(seen.has(n), "nature %s reachable with random answers" % n)
	# deterministic: for each nature, choose the answer maximising (target - best other) on every question
	for target in names:
		var reached := false
		for attempt in 50:
			var used: Array = Q.new_used()
			var tot: Dictionary = Q.empty_totals()
			for k in 8:
				var qi: int = Q.next_question(used, rng)
				while qi >= 0:
					var q: Dictionary = D.questions[qi]
					var best: Dictionary = q.answers[0]
					var best_v := -999
					for a in q.answers:
						var v: int = int(a.points.get(target, 0)) * 10 - a.points.size() + (5 if a.has("followup") and target == "Brave" else 0)
						if v > best_v:
							best_v = v; best = a
					Q.add_points(tot, best)
					qi = int(best.get("followup", -1))
			if Q.resolve_nature(tot, 0) == target and Q.resolve_nature(tot, 12) == target:
				reached = true
				break
		ok(reached, "nature %s reachable by aiming for it" % target)
	print("random-run nature distribution: ", seen)
	print("test_quiz: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)
