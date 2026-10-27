class_name Quiz
extends Node
## PMD Red's personality test, ported from the pret/pmd-red decomp (personality_test1.c / personality_test2.c).
## Data (Red's English text, answer points, starter table, partner list) lives in res://data/quiz.json, which
## tools/data/gen_quiz.py exports from the decomp.
##
## Red's rules:
##  - 8 questions (MAX_ASKED_QUESTIONS). Each pick is a random index among the 55 questions that is not used yet;
##    picking one marks its whole category used, so you never get two questions of the same nature group.
##  - Every answer adds points to natures. Brave Q2 "Fight." adds nothing and asks the follow-up alien question
##    in the same slot (it does not count as an extra question).
##  - Then "Are you a boy or a girl?".
##  - Nature = highest total; ties: start at a random nature and walk forward (wrapping), switching only on a
##    strictly higher total, so among tied natures the first one met from the random start wins.
##  - Starter = per-nature table, separate column for boy / girl.
##  - Partner list = Red's 10 partners minus any sharing a type with the hero.
##
##   var r := await Quiz.run(root)   # {hero, nature, gender} or {} if the player chose to pick freely

const DATA_PATH := "res://data/quiz.json"

static var _data: Dictionary = {}
static var auto := false            # --quiztest: answers picked automatically, screenshots saved
static var _shot_n := 0

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_data = v
	return _data

# ------------------------------------------------------------------ pure logic (also used by tests)
static func nature_names() -> Array:
	return data().natures.map(func(n): return n.name)

static func nature_info(nature: String) -> Dictionary:
	for n in data().natures:
		if n.name == nature:
			return n
	return {}

static func empty_totals() -> Dictionary:
	var t := {}
	for n in nature_names():
		t[n] = 0
	return t

## Red's GenerateNewQuestionOrGender: random unused index, then mark the whole category used.
## `used` is an Array[bool] of size num_selectable (modified). Returns the question index.
static func next_question(used: Array, rng: RandomNumberGenerator) -> int:
	var qs: Array = data().questions
	var n := int(data().num_selectable)
	if not used.has(false):
		return -1
	var q := rng.randi_range(0, n - 1)
	while used[q]:
		q = rng.randi_range(0, n - 1)
	var cat: String = qs[q].category
	for i in n:
		if qs[i].category == cat:
			used[i] = true
	return q

static func new_used() -> Array:
	var u: Array = []
	u.resize(int(data().num_selectable))
	u.fill(false)
	return u

static func add_points(totals: Dictionary, answer: Dictionary) -> void:
	var p: Dictionary = answer.get("points", {})
	for k in p:
		totals[k] = int(totals.get(k, 0)) + int(p[k])

## Red's RevealPersonality. `start` is the random starting nature index (RandInt(13) in Red).
static func resolve_nature(totals: Dictionary, start: int) -> String:
	var names := nature_names()
	var best := start
	var cur := start
	for i in names.size() - 1:
		cur = (cur + 1) % names.size()
		if int(totals.get(names[cur], 0)) > int(totals.get(names[best], 0)):
			best = cur
	return names[best]

static func starter_for(nature: String, gender: String) -> String:
	var n := nature_info(nature)
	if n.is_empty():
		return ""
	return str(n.female if gender == "female" else n.male)

## Red's GetValidPartners: the 10 partners, minus any that share a type with the hero.
static func partner_options(hero: String) -> Array:
	var out: Array = []
	var ht: Array = DB.species.get(hero, {}).get("types", [])
	for p in data().partners:
		if not DB.species.has(p):
			continue
		var ok := true
		for t in DB.species[p].types:
			if ht.has(t):
				ok = false
		if ok:
			out.append(p)
	return out

# ------------------------------------------------------------------ presentation
## Dialog.get_box(), plus a size fix: Dialog._ready() uses set_anchors_preset(FULL_RECT) which in Godot 4
## keeps the (zero) size, leaving the box off-screen above the root; re-apply with offsets.
static func _box(root: Control) -> Dialog:
	var d := Dialog.get_box(root)
	if d.size != root.size:
		d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return d

static func _page_text(acc: String, center: bool) -> String:
	acc = acc.replace("[", "[lb]")
	return "[center]%s[/center]" % acc if center else acc

## One Red text box: segments separated by {WAIT_PRESS} keep typing into the same box.
static func _show_page(root: Control, page: Dictionary) -> void:
	var d := _box(root)
	var acc := ""
	for s in page.segs:
		var prev := acc
		acc += str(s)
		d._show(_page_text(acc, page.center), "", "Normal", "")
		d._visible_chars = float(prev.length())
		if auto:
			await root.get_tree().create_timer(0.12).timeout
			d._finish_typing()
			await root.get_tree().process_frame
			_check_fit(d, acc)
		else:
			await d._advance

static func say_pages(root: Control, pages: Array) -> void:
	for p in pages:
		await _show_page(root, p)
	_box(root).hide_box()

## Pages before the last are shown as text boxes; the last page is the question with the answer menu.
static func _ask_pages(root: Control, pages: Array, options: Array) -> int:
	_box(root)
	for i in pages.size() - 1:
		await _show_page(root, pages[i])
	var last: Dictionary = pages[pages.size() - 1]
	var segs: Array = last.segs
	# earlier {WAIT_PRESS} parts of the question page are typed first, then the menu opens on the full text
	if segs.size() > 1:
		await _show_page(root, {"segs": segs.slice(0, segs.size() - 1), "center": last.center})
	var full := "".join(segs)
	if auto:
		_auto_pick(root, options.size())
	return await Dialog.ask(root, _page_text(full, last.center), options, "", "Normal", false)

static func _auto_pick(root: Control, n: int) -> void:
	await root.get_tree().create_timer(0.35).timeout
	shot(root, "ask")
	for c in root.get_children():
		if c is ListMenu:
			c._click(randi() % n)
			return

static func shot(root: Control, tag: String) -> void:
	if not auto:
		return
	var p := "user://quiz_%02d_%s.png" % [_shot_n, tag]
	_shot_n += 1
	root.get_viewport().get_texture().get_image().save_png(p)

static var overflow: Array = []
static func _check_fit(d: Dialog, txt: String) -> void:
	if d.text.get_line_count() > 3 or d.text.get_content_height() > d.text.size.y + 1:
		overflow.append(txt)

static func _backdrop(root: Control) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.10)
	if Ground.active_map.begins_with("personality_test"):
		bg.color = Color(0, 0, 0, 0)      # Red shows the drifting personality-test backdrop behind the questions
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	root.move_child(bg, 0)
	return bg

static func run(root: Control) -> Dictionary:
	if data().is_empty():
		push_warning("quiz.json missing")
		return {}
	var D := data()
	var bg := _backdrop(root)
	await say_pages(root, D.intro)
	while true:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var totals := empty_totals()
		var used := new_used()
		for k in int(D.questions_asked):
			var qi := next_question(used, rng)
			while qi >= 0:
				var q: Dictionary = D.questions[qi]
				var opts: Array = q.answers.map(func(a): return a.text)
				var a := await _ask_pages(root, q.pages, opts)
				var ans: Dictionary = q.answers[maxi(a, 0)]
				add_points(totals, ans)
				qi = int(ans.get("followup", -1))
		var g := await _ask_pages(root, D.gender.pages, D.gender.answers)
		var gender: String = D.gender["values"][maxi(g, 0)]
		var nature := resolve_nature(totals, rng.randi_range(0, nature_names().size() - 1))
		var hero := starter_for(nature, gender)
		var info := nature_info(nature)
		await say_pages(root, info.pages)
		# "The Pokémon Charmander!" with its happy portrait in a 5x5 window at tile (12,6)
		# (personality_test1.c PersonalityTest_DisplayStarterSprite, sUnknown_80F4244)
		var pv := PortraitWin.make(hero, "Happy", true)
		root.add_child(pv)
		pv.at_tile(12, 6)
		pv.keep_above_textbox(root)
		Audio.sfx("join")
		var reveal: String = "\n" + str(D.starter_reveal).replace("{pokemon}", "[color=#7fe0ff]%s[/color]" % DB.species[hero].name)
		var d := _box(root)
		d._show("[center]%s[/center]" % reveal, "", "Normal", "")
		if auto:
			await root.get_tree().create_timer(0.6).timeout
			d._finish_typing()
			shot(root, "reveal")
		else:
			await d._advance
		# not in Red: let the player keep the result, retake, or pick freely
		if auto:
			_auto_pick_first(root)
		var c := await Dialog.ask(root, "[center]%s[/center]" % reveal, ["Yes, that's me!", "Retake the test.", "Choose freely."], "", "Normal", false)
		pv.queue_free()
		if c == 0:
			bg.queue_free()
			return {"hero": hero, "nature": nature, "gender": gender}
		if c == 2:
			bg.queue_free()
			return {}
	return {}

static func _auto_pick_first(root: Control) -> void:
	await root.get_tree().create_timer(0.35).timeout
	shot(root, "accept")
	for c in root.get_children():
		if c is ListMenu:
			c._click(0)
			return

## Red's partner selection (personality_test2.c CreatePartnerSelectionMenu): the "Pokémon" list window at
## tile (2,2) (9x11) and the highlighted partner's normal portrait, flipped, in a 5x5 window at tile (14,4).
static func partner_pick(root: Control, hero: String) -> String:
	var list := partner_options(hero)
	if list.is_empty():
		return ""
	var P := UITheme.PX
	var rows: Array = []
	for k in list:
		rows.append({"text": str(DB.species[k].name)})
	var pw := PortraitWin.make(str(list[0]), "Normal", true)
	root.add_child(pw)
	pw.at_tile(14, 4)
	var m := TeamScreens.menu("Pokémon", rows, 9 * 8 * P - 16 * P)
	m.allow_cancel = false
	m.max_rows = 10
	m.on_select = func(i): pw.set_species(str(list[clampi(i, 0, list.size() - 1)]))
	if auto:
		_auto_pick_menu.call_deferred(root, m)
	var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
	pw.queue_free()
	Audio.sfx("join")
	return str(list[int(r.get("i", 0))]) if str(r.get("act", "")) == "pick" else str(list[0])

static func _auto_pick_menu(root: Control, m) -> void:
	await root.get_tree().create_timer(0.5).timeout
	shot(root, "partner")
	if is_instance_valid(m) and not m.finished:
		m._finish({"act": "pick", "i": 0})

## Red's "This is the final step... choose your partner" (shown before the partner list).
static func partner_prompt(root: Control) -> void:
	await say_pages(root, data().get("partner_prompt", []))

## Red's "OK! We're all set!..." after the partner is chosen.
static func end_text(root: Control) -> void:
	await say_pages(root, data().get("end_text", []))

# ------------------------------------------------------------------ --quiztest (desktop visual check)
## Checks every question / result page fits the 3-line text box, then plays the quiz with random answers,
## saving screenshots to user://quiz_*.png. `pick` is main.gd's pick_species for the partner screen.
static func autotest(root: Control, pick: Callable) -> void:
	auto = true
	var D := data()
	var tree := root.get_tree()
	await tree.create_timer(0.5).timeout     # let the UI root get its size first
	var d := _box(root)
	await tree.process_frame
	var bg := _backdrop(root)
	var all_pages: Array = []
	for q in D.questions:
		all_pages.append_array(q.pages)
	for n in D.natures:
		all_pages.append_array(n.pages)
	all_pages.append_array(D.intro)
	all_pages.append_array(D.partner_prompt)
	all_pages.append_array(D.end_text)
	for p in all_pages:
		d._show(_page_text("".join(p.segs), p.center), "", "Normal", "")
		d._finish_typing()
		await tree.process_frame
		_check_fit(d, "".join(p.segs))
	print("QUIZTEST pages checked: ", all_pages.size(), " overflow: ", overflow.size())
	#print("DBG root ", root.get_global_rect(), " vis ", root.is_visible_in_tree(), " panel ", d.panel.get_global_rect(), " ", d.panel.visible, " text ", d.text.size, " lines ", d.text.get_line_count(), " ch ", d.text.get_content_height(), " modulate ", root.modulate)
	for o in overflow:
		print("  OVERFLOW: ", o.replace("\n", " | "))
	# longest answer menu over its question
	for q in D.questions:
		if q.id == "TIMID_Q2" or q.id == "QUIRKY_Q3" or q.id == "JOLLY_Q4":
			_auto_pick(root, q.answers.size())
			await Dialog.ask(root, _page_text("".join(q.pages[-1].segs), false), q.answers.map(func(a): return a.text), "", "Normal", false)
	# a long result page
	d._show(_page_text("".join(D.natures[6].pages[3].segs), true), "", "Normal", "")
	d._finish_typing()
	await tree.process_frame
	shot(root, "desc_long")
	d.hide_box()
	bg.queue_free()
	overflow.clear()
	var r := await run(root)
	print("QUIZTEST result: ", r, " overflow during run: ", overflow.size())
	if not r.is_empty():
		await partner_prompt(root)
		var opts := partner_options(r.hero)
		print("QUIZTEST partners for ", r.hero, ": ", opts)
		_auto_pick_first(root)
		var p: String = await pick.call("Pokémon", opts, "")
		print("QUIZTEST partner: ", p)
		await end_text(root)
	tree.quit()
