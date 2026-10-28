extends Node
## Autoload "Game": the save file (team, bag, money, progress) and settings.

const SAVE_PATH := "user://save.json"
const BAG_MAX := 20               # Red: Toolbox holds 20 at the start (upgraded later in the story)

var team_name := "Team"
var hero := {}                    # team entries: {sp, name, level, exp, moves, iq, held, bonus}
var partner := {}
var team: Array = []              # active team (hero first)
var bag: Array = []               # [{id, n}]
var money := 0
var bank := 0
var flags := {}
var rank_points := 0              # rescue team rank points (Red: Normal, Bronze, Silver, Gold, Diamond, Super, Ultra, Hyper, Master)
var jobs: Array = []              # accepted jobs (max 8 in Red): see Missions
var board: Array = []             # jobs currently on Pelipper's board
var board_day := -1
var day := 0                      # advances each time the team sleeps at the base
var unlocked: Array = ["tiny_woods"]   # dungeon keys the team can go to
var cleared: Array = []           # dungeon keys cleared at least once
var friend_areas: Array = []      # owned Friend Area keys (Wigglytuff sells them)
var friends: Array = []           # recruited Pokémon living in Friend Areas (team-entry dicts + "area")
var storage := {}                 # Kangaskhan Storage: item id -> count
var nature := ""                  # result of the personality quiz
var gender := ""
var story := {}                   # Red story state: script var buffer (base64) + misc
var settings := {"music": 0.8, "sfx": 0.9, "zoom": 1.25, "zoom_v": 2, "msg_speed": 1,
	# Red's Game Options (game_options.c InitializeGameOptions defaults): map_mode 0 Off / 1 Clear / 2 Shade,
	# far_off_pals 0 Self / 1 Look, window_color 0 Blue / 1 Red / 2 Green
	"map_mode": 1, "grids": true, "damage_turn": true, "far_off_pals": 1, "window_color": 0}

func _ready() -> void:
	load_game()

## play time (Red's load screen): counts while a game is loaded
func _process(dt: float) -> void:
	if team.size() > 0:
		flags["play_secs"] = float(flags.get("play_secs", 0.0)) + dt

func new_game(hero_sp: String, hero_name: String, partner_sp: String, partner_name: String, tname: String) -> void:
	team_name = tname
	hero = _entry(hero_sp, hero_name, 5)
	hero["role"] = "hero"
	partner = _entry(partner_sp, partner_name, 5)
	partner["role"] = "partner"
	team = [hero, partner]
	bag = []
	money = 0
	flags = {"started": true}
	rank_points = 0
	jobs = []
	board = []
	board_day = -1
	day = 0
	unlocked = ["tiny_woods"]
	cleared = []
	friend_areas = []
	friends = []
	storage = {}
	Story.sync_base_kind()      # the base looks like the hero's (Red: sBaseKindTable)
	save_game(true)       # a new adventure replaces the old save even with Auto save off

func _entry(sp: String, nm: String, L: int) -> Dictionary:
	return {"sp": sp, "name": nm, "level": L, "exp": DB.exp_at(sp, L), "moves": DB.default_moves(sp, L), "iq": 0, "held": "", "bonus": {}}

func mon_from_entry(e: Dictionary) -> Mon:
	MoveGrowth.sync_moves(e.get("moves", []))      # Move Growth PP bonus (or its removal) before the dungeon
	var nm0 := str(e.get("name", ""))
	if nm0.strip_edges() == "":
		nm0 = str(DB.species.get(str(e.sp), {}).get("name", "???"))    # Red shows the species name for an unnamed Pokémon
	var m := DB.make_mon(e.sp, int(e.level), "team", {"name": nm0, "exp": int(e.exp), "moves": e.moves.duplicate(true), "held": e.get("held", ""), "iq": int(e.get("iq", 0))})
	m.held_n = maxi(1, int(e.get("held_n", 1)))
	m.set_meta("bonus", e.get("bonus", {}))
	m.set_meta("entry", e)
	if bool(e.get("shiny", false)):
		m.set_meta("shiny", true)
	DB.recalc(m)
	m.hp = m.max_hp
	IQ.apply(m)          # IQ skills + tactic from the team entry
	return m

## Copy a dungeon Mon's progress back to its team entry.
func store_mon(m: Mon) -> void:
	var e: Dictionary = m.get_meta("entry", {})
	if e.is_empty():
		return
	if not m.get_meta("level_reset", false):      # Lv1 dungeons: the levels gained there don't stay
		e.level = m.level
		e.exp = m.exp
	e.moves = m.moves.duplicate(true)
	e.held = m.held
	e.held_n = m.held_n if m.held != "" else 1
	e.iq = m.iq
	if m.mega == "" and not DB.species.get(m.sp, {}).has("megaBase"):
		e.sp = m.sp

func bag_add(id: String, n := 1) -> bool:
	var it: Dictionary = DB.items.get(id, {})
	if it.get("stack", false):
		for b in bag:
			if b.id == id and int(b.n) < 99:
				b.n = mini(99, int(b.n) + n)
				return true
	if bag.size() >= BAG_MAX:
		return false
	bag.append({"id": id, "n": n})
	return true

## Every automatic save in the game goes through here. Game Options -> Auto save: Off keeps the save file as
## it was at the last real save (Save at the bed / the save points, Quicksave) and only updates the settings.
## force = an explicit save by the player.
func save_game(force := false) -> void:
	if not force and not bool(settings.get("qol_autosave", true)) and FileAccess.file_exists(SAVE_PATH):
		_save_settings_only()
		return
	var d := {"v": 2, "team_name": team_name, "team": team, "bag": bag, "money": money, "bank": bank, "flags": flags, "settings": settings,
		"rank_points": rank_points, "jobs": jobs, "board": board, "board_day": board_day, "day": day, "unlocked": unlocked, "cleared": cleared,
		"friend_areas": friend_areas, "friends": friends, "storage": storage, "nature": nature, "gender": gender, "story": _story_out()}
	for e in team + friends:
		ensure_uid(e)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))

func _save_settings_only() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary):
		return
	d["settings"] = settings
	var w := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if w:
		w.store_string(JSON.stringify(d))

## Every team / Friend Area entry gets an id, so the same Pokémon is still one Pokémon after a save and load
## (JSON writes a team member that also lives in a Friend Area twice).
func ensure_uid(e: Dictionary) -> void:
	if str(e.get("uid", "")) == "":
		e["uid"] = "%x%04x" % [int(Time.get_unix_time_from_system()), randi() % 0x10000] + str(randi() % 1000)

## The same Pokémon as e: same id, or (saves from before ids) same species and name with no more progress.
static func _same_mon(e: Dictionary, o: Dictionary) -> bool:
	var a := str(e.get("uid", ""))
	var b := str(o.get("uid", ""))
	if a != "" and b != "":
		return a == b
	return str(e.get("sp", "")) == str(o.get("sp", "")) and str(e.get("name", "")) == str(o.get("name", "")) \
			and bool(e.get("shiny", false)) == bool(o.get("shiny", false)) \
			and int(o.get("exp", 0)) <= int(e.get("exp", 0)) and int(o.get("iq", 0)) <= int(e.get("iq", 0)) \
			and str(o.get("role", "")) in ["", str(e.get("role", ""))]

## After loading: a team member's Friend Area copy becomes the team entry itself again, and copies made by
## the old split (the same Pokémon twice on the team, or a stale twin in a Friend Area) are dropped.
static func _moves_common(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	var bn: Array = []
	for mv in b.get("moves", []):
		bn.append(str(mv.get("name", "")))
	for mv in a.get("moves", []):
		if str(mv.get("name", "")) in bn:
			n += 1
	return n

func link_entries() -> void:
	var dropped: Array = []
	var i := 0
	while i < team.size():
		var t: Dictionary = team[i]
		var j := i + 1
		while j < team.size():
			var o: Dictionary = team[j]
			if _same_mon(t, o) or _same_mon(o, t):
				var keep: Dictionary = t if int(t.get("exp", 0)) >= int(o.get("exp", 0)) else o
				var gone: Dictionary = o if keep == t else t
				if str(gone.get("role", "")) != "" and str(keep.get("role", "")) == "":
					keep["role"] = gone.role
				team[i] = keep
				team.remove_at(j)
				dropped.append(str(gone.get("name", "?")))
				t = keep
				continue
			j += 1
		i += 1
	for t in team:
		if friends.any(func(f): return is_same(f, t)):
			continue
		# the team member's own Friend Area listing: the matching entry with the most moves in common
		var cands: Array = []
		for f in friends:
			if _same_mon(t, f):
				cands.append(f)
		if cands.is_empty():
			continue
		var best: Dictionary = cands[0]
		for f in cands:
			if _moves_common(t, f) > _moves_common(t, best) or (_moves_common(t, f) == _moves_common(t, best) and int(f.exp) > int(best.exp)):
				best = f
		if t.get("area", "") == "" and str(best.get("area", "")) != "":
			t["area"] = best.area
		friends[friends.find(best)] = t
		# exact twins of that listing (same progress and moves) are copies too; anything else is kept
		for f in cands:
			if not is_same(f, best) and int(f.exp) == int(best.exp) and _moves_common(f, best) == best.get("moves", []).size():
				friends.erase(f)
				dropped.append(str(f.get("name", "?")))
	for e in team + friends:
		ensure_uid(e)
	if dropped.size() > 0:
		print("LINK dropped duplicate entries: ", dropped)
	for e in team:
		if str(e.get("role", "")) == "hero":
			hero = e
		elif str(e.get("role", "")) == "partner":
			partner = e

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and team.size() > 0

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	team_name = d.get("team_name", "Team")
	team = d.get("team", [])
	for e in team:
		e.level = int(e.level)
		e.exp = int(e.exp)
		for mv in e.moves:
			mv.pp = int(mv.pp)
			mv.max_pp = int(mv.max_pp)
	# names saved by older builds could hold half a BBCode tag ("[color=#7f") and showed up blank
	for e in team:
		if str(e.get("name", "")).contains("[") or str(e.get("name", "")).strip_edges() == "":
			e.name = str(DB.species.get(str(e.sp), {}).get("name", "???"))
	# hero / partner keep their story roles even after Make Leader reorders the team
	hero = {}
	partner = {}
	for e in team + d.get("friends", []):
		if str(e.get("role", "")) == "hero" and hero.is_empty():
			hero = e
		elif str(e.get("role", "")) == "partner" and partner.is_empty():
			partner = e
	if hero.is_empty() and team.size() > 0:
		hero = team[0]
		hero["role"] = "hero"
	if partner.is_empty() and team.size() > 1:
		partner = team[1]
		partner["role"] = "partner"
	bag = d.get("bag", [])
	for b in bag:
		b.n = int(b.n)
	money = int(d.get("money", 0))
	bank = int(d.get("bank", 0))
	flags = d.get("flags", {})
	rank_points = int(d.get("rank_points", 0))
	jobs = d.get("jobs", [])
	board = d.get("board", [])
	board_day = int(d.get("board_day", -1))
	day = int(d.get("day", 0))
	unlocked = d.get("unlocked", ["tiny_woods"])
	cleared = d.get("cleared", [])
	friend_areas = d.get("friend_areas", [])
	Story.normalize_friend_areas()      # one spelling per area (old saves mixed Red's enum names in)
	friends = d.get("friends", [])
	for e in friends:
		e.level = int(e.level)
		e.exp = int(e.exp)
	link_entries()
	storage = d.get("storage", {})
	nature = d.get("nature", "")
	gender = d.get("gender", "")
	story = d.get("story", {})
	if story.has("vars"):
		GVars.load_b64(str(story.vars))
	settings.merge(d.get("settings", {}), true)
	if int(settings.get("zoom_v", 0)) < 2:     # v0.1 saved the old, too-close zoom
		settings.zoom = 1.25
		settings.zoom_v = 2

func _story_out() -> Dictionary:
	if GVars._ready:
		story["vars"] = GVars.save_b64()
	return story

func story_get(k: String, def = null):
	return story.get(k, def)

func story_set(k: String, v) -> void:
	story[k] = v
