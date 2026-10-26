class_name AdventureLog
extends RefCounted
## Red's Adventure Log (adventure_info.c achievements + adventure_log.c screen, strings.c gAdventureLogText).
##
##   AdventureLog.set_bit(AdventureLog.AA_SPOTTED_MUNCHLAX)   # script command 0xB2 / story milestones
##   AdventureLog.add("floors")                               # counters: floors, joined, evolved, thieving, friend_rescues
##   AdventureLog.mark_leader(species)                        # sub_80978C8: species that led an expedition
##   AdventureLog.update()                                    # UpdateAdventureAchievements (+ the scenario milestones)
##   await AdventureLog.open(root)                            # the 4-page screen (Left / Right pages, A / B closes)
##
## Everything is stored in Game.flags: "aa" (achievement bits), "aa_floors", "aa_joined", "aa_evolved",
## "aa_thieving", "aa_friend_rescues", "aa_moves" (move names ever known by a team member), "aa_seen"
## (species ever recruited), "aa_leaders" (species that were leader).

enum { AA_HILL_OF_ANCIENTS, AA_FUGITIVE, AA_PREVENT_METEOR, AA_BROKE_CURSE, AA_TEAM_BASE_DONE, AA_SMEARGLE,
	AA_SPOTTED_MUNCHLAX, AA_NUM_MOVES_LEARNED, AA_NUM_FRIEND_RESCUE_SUCCESSES, AA_NUM_POKEMON_EVOLVED,
	AA_NUM_POKEMON_JOINED, AA_NUM_THIEVING_SUCCESSES, AA_NUM_FLOORS_EXPLORED, AA_ALL_FRIEND_AREAS,
	AA_ALL_POKEMON_LEADERS, AA_ALL_POKEMON_JOINED, AA_RECRUIT_MOLTRES, AA_RECRUIT_ZAPDOS, AA_RECRUIT_ARTICUNO,
	AA_RECRUIT_DEOXYS, AA_RECRUIT_ENTEI, AA_RECRUIT_RAIKOU, AA_RECRUIT_SUICUNE, AA_RECRUIT_HO_OH, AA_RECRUIT_KYOGRE,
	AA_RECRUIT_GROUDON, AA_RECRUIT_RAYQUAZA, AA_RECRUIT_LUGIA, AA_RECRUIT_CELEBI, AA_RECRUIT_MEW, AA_RECRUIT_MEWTWO,
	AA_RECRUIT_JIRACHI }

const TEXT := [
	"Reached the Hill of the Ancients.", "Took to the road as fugitives.", "Prevented the meteor's collision.",
	"Broke the curse on Gardevoir.", "The rescue team base was completed.", "Rescued Smeargle.", "Spotted Munchlax.",
	"{VALUE_0} moves were learned.", "{VALUE_0} Friend Rescues were successful.", "{VALUE_0} Pokémon evolved.",
	"{VALUE_0} Pokémon joined the team.", "{VALUE_0} thieving attempts succeeded.", "{VALUE_0} floors were explored.",
	"All Friend Areas were obtained.", "All Pokémon were made leaders.", "All Pokémon joined the team.",
	"Moltres joined the team.", "Zapdos joined the team.", "Articuno joined the team.", "Deoxys joined the team.",
	"Entei joined the team.", "Raikou joined the team.", "Suicune joined the team.", "Ho-Oh joined the team.",
	"Kyogre joined the team.", "Groudon joined the team.", "Rayquaza joined the team.", "Lugia joined the team.",
	"Celebi joined the team.", "Mew joined the team.", "Mewtwo joined the team.", "Jirachi joined the team."]
const PLACEHOLDER := "•••••••••••••••"
## counter shown by each numbered line, with Red's caps
const COUNTERS := {AA_NUM_MOVES_LEARNED: ["moves", 511], AA_NUM_FRIEND_RESCUE_SUCCESSES: ["friend_rescues", 99999],
	AA_NUM_POKEMON_EVOLVED: ["evolved", 99999], AA_NUM_POKEMON_JOINED: ["joined", 9999],
	AA_NUM_THIEVING_SUCCESSES: ["thieving", 9999], AA_NUM_FLOORS_EXPLORED: ["floors", 99999]}
const RECRUIT_BITS := {"0146": AA_RECRUIT_MOLTRES, "0145": AA_RECRUIT_ZAPDOS, "0144": AA_RECRUIT_ARTICUNO,
	"0386": AA_RECRUIT_DEOXYS, "0244": AA_RECRUIT_ENTEI, "0243": AA_RECRUIT_RAIKOU, "0245": AA_RECRUIT_SUICUNE,
	"0250": AA_RECRUIT_HO_OH, "0382": AA_RECRUIT_KYOGRE, "0383": AA_RECRUIT_GROUDON, "0384": AA_RECRUIT_RAYQUAZA,
	"0249": AA_RECRUIT_LUGIA, "0251": AA_RECRUIT_CELEBI, "0151": AA_RECRUIT_MEW, "0150": AA_RECRUIT_MEWTWO,
	"0385": AA_RECRUIT_JIRACHI}
static var _n_areas := -1
const RED_DEX_MAX := 386          # Red's Pokémon (Munchlax, the decoy and form duplicates are skipped there too)

# ------------------------------------------------------------------ data
static func bits() -> int:
	return int(Game.flags.get("aa", 0))

static func has(i: int) -> bool:
	return (bits() >> i) & 1 == 1

static func set_bit(i: int) -> void:
	if i >= 0 and i < 32:
		Game.flags["aa"] = bits() | (1 << i)

static func count(key: String) -> int:
	if key == "moves":
		return (Game.flags.get("aa_moves", []) as Array).size()
	return int(Game.flags.get("aa_" + key, 0))

## IncrementAdventureFloorsExplored / NumJoined / NumEvolved / ThievingSuccesses / FriendRescueSuccesses
static func add(key: String, n := 1) -> void:
	var cap := 99999
	var bit := -1
	for b in COUNTERS:
		if COUNTERS[b][0] == key:
			cap = COUNTERS[b][1]
			bit = b
	Game.flags["aa_" + key] = mini(cap, int(Game.flags.get("aa_" + key, 0)) + n)
	if bit >= 0:
		set_bit(bit)

static func _base(sp: String) -> String:
	return sp.substr(0, 4)

static func mark_leader(sp: String) -> void:
	var l: Array = Game.flags.get("aa_leaders", [])
	if not _base(sp) in l:
		l.append(_base(sp))
	Game.flags["aa_leaders"] = l

## UpdateAdventureAchievements + the ScriptVarScenario milestones (event_flag.c), run before saving.
static func update() -> void:
	if Game.story.has("vars") and GVars._ready:
		var m := GVars.scenario(GVars.SCENARIO_MAIN)
		if m.x > 0 and m.x < 28:
			if GVars.after(GVars.SCENARIO_MAIN, 8, -1):
				set_bit(AA_HILL_OF_ANCIENTS)
			if GVars.after(GVars.SCENARIO_MAIN, 11, 3):
				set_bit(AA_FUGITIVE)
			if GVars.after(GVars.SCENARIO_MAIN, 17, 0):
				set_bit(AA_PREVENT_METEOR)
		if not GVars.before(GVars.SCENARIO_SUB1, 31, 0):
			set_bit(AA_TEAM_BASE_DONE)
		if not GVars.before(GVars.SCENARIO_SUB1, 32, 0):
			set_bit(AA_SMEARGLE)
		if not GVars.before(GVars.SCENARIO_SUB9, 55, 2):
			set_bit(AA_BROKE_CURSE)
	if _n_areas < 0:
		var f := FileAccess.open("res://data/friend_areas.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text()) if f else null
		_n_areas = (d.get("areas", {}) as Dictionary).size() if d is Dictionary else 0
	if _n_areas > 0 and Game.friend_areas.size() >= _n_areas:
		set_bit(AA_ALL_FRIEND_AREAS)
	var seen: Array = Game.flags.get("aa_seen", [])
	var moves: Array = Game.flags.get("aa_moves", [])
	for e in Game.team + Game.friends:
		var b := _base(str(e.get("sp", "")))
		if b != "" and not b in seen:
			seen.append(b)
		for mv in e.get("moves", []):
			var nm := str(mv.get("name", mv.get("id", ""))) if mv is Dictionary else str(mv)
			if nm != "" and not nm in moves:
				moves.append(nm)
	Game.flags["aa_seen"] = seen
	Game.flags["aa_moves"] = moves
	if not moves.is_empty():
		set_bit(AA_NUM_MOVES_LEARNED)
	for sp in RECRUIT_BITS:
		if sp in seen:
			set_bit(RECRUIT_BITS[sp])
	var leaders: Array = Game.flags.get("aa_leaders", [])
	var all_joined := true
	var all_leaders := true
	for i in range(1, RED_DEX_MAX + 1):
		var k := "%04d" % i
		if not k in seen:
			all_joined = false
		if not k in leaders:
			all_leaders = false
		if not all_joined and not all_leaders:
			break
	if all_joined:
		set_bit(AA_ALL_POKEMON_JOINED)
	if all_leaders:
		set_bit(AA_ALL_POKEMON_LEADERS)

static func line(i: int) -> String:
	if not has(i):
		return PLACEHOLDER
	var t: String = TEXT[i]
	if COUNTERS.has(i):
		t = t.replace("{VALUE_0}", str(count(COUNTERS[i][0])))
	return t

# ------------------------------------------------------------------ screen
## Red's WINDOW_TYPE_WITH_HEADER shape (text_2.c): a strip with one tab per page, the current page's tab
## (header width 11 tiles) raised 4 px and moved 8 px per page, the body below. Drawn in the window colour with
## the frame's light / mid outline. Children are laid out from the window's text origin (0, 0).
class HeaderWindow extends Control:
	var page := 0
	var count := 4
	var hwidth := 11
	func _shape() -> Array:
		var w := size.x / UITheme.PX
		var h := size.y / UITheme.PX
		var cur := Rect2(3 + page * 8, -4, (hwidth + 2) * 8 - 4, 4)
		var strip := Rect2(3, 0, (hwidth - 1 + count + 2) * 8 - 4, 8)
		var body := Rect2(-5, 8, w + 10, h - 8 + 5)
		return [cur, strip, body]
	func _draw() -> void:
		var P := float(UITheme.PX)
		var sh := _shape()
		for pass_i in 3:
			for r in sh:
				var rr: Rect2 = r
				var g := 2 - pass_i
				var c: Color = [UITheme.FRAME_DARK, UITheme.FRAME_LIGHT, UITheme.window_bg()][pass_i]
				draw_rect(Rect2((rr.position - Vector2(g, g)) * P, (rr.size + Vector2(g, g) * 2) * P), c)


## Red's Adventure Log window (2,2) 26 tiles wide, 8 lines a page, 4 pages; the header tab moves 8 px per page.
static func open(root: Control) -> void:
	update()
	var page := 0
	var panel := HeaderWindow.new()
	panel.theme = UITheme.theme()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var head := Control.new()
	head.position = Vector2(0, -2) * UITheme.PX
	panel.add_child(head)
	var title := Label.new()
	title.text = "Adventure Log"
	head.add_child(title)
	var num := Label.new()
	head.add_child(num)
	var rows: Array = []
	for i in 8:
		var l := Label.new()
		l.position = Vector2(8, 12 + i * 12) * UITheme.PX       # PrintFormattedStringOnWindow(8, GetMenuEntryYCoord)
		panel.add_child(l)
		rows.append(l)
	panel.size = Vector2(26 * 8, 14 + 8 * 12) * UITheme.PX
	root.add_child(panel)
	var vs := root.get_viewport_rect().size / UITheme.PX
	panel.position = Vector2(floorf((vs.x - 240) / 2) + 16, floorf((vs.y - 135) / 2) + 12) * UITheme.PX
	var refresh := func(pg: int):
		panel.page = pg
		panel.queue_redraw()
		title.position = Vector2(pg * 8 + 10, 0) * UITheme.PX
		num.text = str(pg + 1)
		num.position = Vector2(pg * 8 + 4 + 11 * 8 - 6, 0) * UITheme.PX     # PrintNumOnWindow: 1 digit right-aligned
		for i in 8:
			rows[i].text = line(pg * 8 + i)
	refresh.call(page)
	if ListMenu.auto or Dialog.auto:
		await root.get_tree().create_timer(0.3).timeout
		panel.queue_free()
		return
	var tree := root.get_tree()
	await SaveUI.release_keys(tree)        # the key that opened the screen must not close it
	var keys := SaveUI.KeyCatch.new()
	panel.add_child(keys)
	while true:
		await tree.process_frame
		if not is_instance_valid(panel):
			return
		var k: String = keys.pop()
		if k == "right":
			page = (page + 1) % 4
			Audio.sfx("cursor")
			refresh.call(page)
		elif k == "left":
			page = (page + 3) % 4
			Audio.sfx("cursor")
			refresh.call(page)
		elif k == "a":
			Audio.sfx("confirm")
			break
		elif k == "b":
			Audio.sfx("cancel")
			break
		elif k == "tap":
			var mp := panel.get_local_mouse_position()
			if not Rect2(Vector2.ZERO, panel.size).has_point(mp):
				Audio.sfx("cancel")
				break
			page = (page + (1 if mp.x > panel.size.x / 2 else 3)) % 4
			Audio.sfx("cursor")
			refresh.call(page)
	panel.queue_free()
