class_name LuminousCave
extends RefCounted
## Red's Luminous Cave (luminous_cave.c, SPECIAL_TEXT_LUMINOUS_CAVE in textbox.c) and evolution
## (pokemon_evolution.c SetMonEvolveStatus / sub_808F734). Requirements come from Red's monster data
## (data/red_evo.json, gen_red_evo.py) and, for species Red doesn't have, from data/evo.json.
## When the leader evolves, the map event EVOLUTION_HERO runs (station 1/1 of the cave: the light effect,
## then the lives are reloaded with the new species) while the voice keeps talking.

const S_INTRO := "{CENTER_ALIGN}...{WAIT_PRESS}A voice emanates from somewhere...{EXTRA_MSG}{CENTER_ALIGN}...Ye who seek awakening...{EXTRA_MSG}{CENTER_ALIGN}This is Luminous Cave.{WAIT_PRESS}\n{CENTER_ALIGN}Do ye seek a new evolution?"
const S_PROMPT := "{CENTER_ALIGN}Do ye seek evolution?"
const S_INFO := "{CENTER_ALIGN}There are those among Pokémon\n{CENTER_ALIGN}that can evolve.{EXTRA_MSG}{CENTER_ALIGN}Such Pokémon can evolve at this very\n{CENTER_ALIGN}spot if they satisfy certain conditions.{EXTRA_MSG}{CENTER_ALIGN}Evolution brings about changes\n{CENTER_ALIGN}in appearance and abilities.{EXTRA_MSG}{CENTER_ALIGN}Not only that, some Pokémon even change\n{CENTER_ALIGN}type and learn different moves.{EXTRA_MSG}{CENTER_ALIGN}However...{WAIT_PRESS} The requirements for\n{CENTER_ALIGN}evolution differ among Pokémon.{EXTRA_MSG}{CENTER_ALIGN}Some become ready for evolution\n{CENTER_ALIGN}merely by leveling up.{EXTRA_MSG}{CENTER_ALIGN}Still others may need special items\n{CENTER_ALIGN}to attain evolution.{EXTRA_MSG}{CENTER_ALIGN}Ye must also be aware of this:{EXTRA_MSG}{CENTER_ALIGN}Once it has evolved, a Pokémon\n{CENTER_ALIGN}can never regain its previous form.{EXTRA_MSG}{CENTER_ALIGN}That is why ye must think carefully\n{CENTER_ALIGN}before committing to evolution."
const S_RETURN := "{CENTER_ALIGN}Ye shall return if evolution\n{CENTER_ALIGN}is what ye seek..."
const S_GIVE := "{CENTER_ALIGN}Will ye give an item for evolution?"
const S_GIVE2 := "{CENTER_ALIGN}Will ye give yet another item?"
const S_LACK_NEEDED := "{CENTER_ALIGN}Alas, ye seem to lack what is needed\n{CENTER_ALIGN}for evolution."
const S_ONE_ITEM := "{CENTER_ALIGN}Ye seem to have but one item."
const S_BEGIN := "{CENTER_ALIGN}...Ye who seek awakening...\n{CENTER_ALIGN}Let us begin."
const S_CHANGED := "{CENTER_ALIGN}...{WAIT_PRESS}{NAME_0} is undergoing changes...{EXTRA_MSG}{CENTER_ALIGN}{NAME_0}'s appearance changed...{EXTRA_MSG}"
const S_EVOLVED := "{CENTER_ALIGN}It evolved from {COLOR GREEN}{POKEMON_0}{RESET}\n{CENTER_ALIGN}to {COLOR YELLOW}{POKEMON_1}{RESET}!"
const S_ALONE := "{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}One cannot evolve if one\n{CENTER_ALIGN}is in the company of others.{EXTRA_MSG}{CENTER_ALIGN}Come alone if ye wish to evolve."
const S_LACK := {
	"level": "{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}Ye cannot evolve yet.{EXTRA_MSG}{CENTER_ALIGN}Ye have not high enough a level.",
	"no_more": "{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}Ye cannot evolve anymore.",
	"friend_area": "{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}Ye cannot evolve yet.{EXTRA_MSG}{CENTER_ALIGN}Ye need your Friend Area to evolve.",
	"room": "{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}Ye cannot evolve yet.{EXTRA_MSG}{CENTER_ALIGN}The Friend Area to which ye shall go\n{CENTER_ALIGN}has no room for ye.",
	"iq": "{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}Ye cannot evolve yet.{EXTRA_MSG}{CENTER_ALIGN}Ye seem to lack the IQ to evolve.",
	"item": "{CENTER_ALIGN}{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}Ye cannot evolve yet.{EXTRA_MSG}{CENTER_ALIGN}Ye seem to lack an item to evolve.",
	"yet": "{CENTER_ALIGN}{CENTER_ALIGN}...{EXTRA_MSG}{CENTER_ALIGN}Ye cannot evolve yet. ",
}

static var _red_evo := {}
static var test_items: Array = []          # tests: item keys to offer (auto mode)

static func red_evo() -> Dictionary:
	if _red_evo.is_empty():
		var f := FileAccess.open("res://data/red_evo.json", FileAccess.READ)
		if f:
			_red_evo = JSON.parse_string(f.get_as_text())
	return _red_evo

## Evolution entries of a species: Red's own data, plus evo.json targets Red doesn't know.
## [[target, type, main, additional]]
static func evolutions(sp: String) -> Array:
	var key := sp.substr(0, 4)
	var out: Array = (red_evo().get(key, []) as Array).duplicate()
	var have := {}
	for e in out:
		have[str(e[0])] = true
	for e in DB.evo.get(key, []):
		var tgt := str(e[0])
		if have.has(tgt) or GData.red_of_species(tgt) != 0 and red_evo().has(key):
			continue
		var cond := str(e[2]) if e.size() > 2 else ""
		if cond == "f":
			out.append([tgt, "iq", 200 if int(e[1]) == 0 else 150, 0])     # friendship: Red uses IQ for these
		elif cond != "" and DB.items.has(cond):
			out.append([tgt, "item", cond, 0])
		elif int(e[1]) > 0:
			out.append([tgt, "level", int(e[1]), 0])
	var lc = load("res://scripts/core/launcher_cfg.gd")
	return out.filter(func(x): return lc.mon_on(str(x[0])))      # launcher: switched-off Pokémon don't evolve in

static func _friends_in(area: String) -> int:
	var n := 0
	for f in Game.friends:
		if str(f.get("area", "")) == area:
			n += 1
	for t in Game.team:
		if t is Dictionary and Services.area_of(str(t.get("sp", ""))) == area:
			n += 1
	return n

## SetMonEvolveStatus. items = the evolution items given (keys). Returns {status: {...flags}, target}.
static func evolve_status(e: Dictionary, items: Array, from_inventory := false) -> Dictionary:
	var sp := str(e.get("sp", ""))
	var evs := evolutions(sp)
	var res := {"flags": {}, "target": ""}
	if evs.is_empty():
		res.flags["no_more"] = true
		return res
	var m: Mon = Game.mon_from_entry(e)
	var have := func(k: String) -> bool:
		if from_inventory:
			return Game.bag.any(func(b): return str(b.get("id", "")) == k)
		return k in items
	var wurmple := randi_range(0, 254)
	for ev in evs:
		var tgt := str(ev[0])
		var bad := false
		var area := Services.area_of(tgt)
		var cur_area := Services.area_of(sp)
		if area != "":
			if not area in Game.friend_areas:
				res.flags["friend_area"] = true
				bad = true
			else:
				var n := _friends_in(area)
				if area == cur_area:
					n -= 1
				if int(Services.fa().get("areas", {}).get(area, {}).get("cap", 99)) <= n:
					res.flags["room"] = true
					bad = true
		match str(ev[1]):
			"level":
				if int(e.get("level", 1)) < int(ev[2]):
					res.flags["level"] = true
					bad = true
			"iq":
				if int(e.get("iq", 0)) < int(ev[2]):
					res.flags["iq"] = true
					bad = true
			"item":
				if not have.call(str(ev[2])):
					res.flags["item"] = true
					bad = true
		match int(ev[3]):
			4:
				if not have.call("linkcable"):
					res.flags["item"] = true
					bad = true
			5:
				if m.atk <= m.def:
					bad = true
			6:
				if m.atk >= m.def:
					bad = true
			7:
				if m.atk != m.def:
					bad = true
			8:
				if not have.call("sunribbon"):
					res.flags["item"] = true
					bad = true
			9:
				if not have.call("lunarribbon"):
					res.flags["item"] = true
					bad = true
			10:
				if not have.call("beautyscarf"):
					bad = true
			11:
				if wurmple & 1:
					bad = true
			12:
				if not (wurmple & 1):
					bad = true
		if not bad:
			res.flags["good"] = true
			res.target = tgt
	return res

## sub_808F734 / sub_808F798: the entry becomes the new species (Nincada also leaves a Shedinja behind).
static func evolve_entry(e: Dictionary, target: String) -> void:
	var old := str(e.sp)
	var old_name := str(DB.species.get(old, {}).get("name", ""))
	var lv: Array = e.get("evo_levels", [])
	lv.insert(0, int(e.get("level", 1)))
	e["evo_levels"] = lv
	e.sp = target
	e.exp = DB.exp_at(target, int(e.get("level", 1)))
	if str(e.get("name", "")) == old_name:
		e.name = str(DB.species.get(target, {}).get("name", old_name))
	if target.substr(0, 4) == "0291":       # MONSTER_NINJASK: a Shedinja appears if there's room
		var area := Services.area_of("0292")
		if area != "" and area in Game.friend_areas and _friends_in(area) < int(Services.fa().get("areas", {}).get(area, {}).get("cap", 99)):
			var sh: Dictionary = Story.add_friend("0292", str(DB.species.get("0292", {}).get("name", "Shedinja")), int(e.get("level", 1)), [])
			if not sh.is_empty():
				sh["moves"] = (e.get("moves", []) as Array).duplicate(true)
	if DB.species.has(target):
		Pokedex.mark_seen(target)

static func _pick_item(root: Control, exclude := -1) -> int:
	if Dialog.auto or ListMenu.auto:
		for i in Game.bag.size():
			if i != exclude and str(Game.bag[i].id) in test_items:
				return i
		return -1
	while true:
		var labels: Array = []
		for b in Game.bag:
			labels.append(str(DB.items.get(str(b.id), {}).get("name", b.id)))
		var lm := ListMenu.make("Toolbox", labels)
		root.add_child(lm)
		lm.position = Vector2(8, 8) * UITheme.PX
		var i := await lm.choose()
		if i < 0:
			return -1
		if i == exclude:
			continue                 # PlayMenuSoundEffect(MENU_SFX_FAIL)
		var c := await Dialog.ask(root, str(DB.items.get(str(Game.bag[i].id), {}).get("name", "")), ["Yes", "Info"])
		if c == 0:
			return i
		if c == 1:
			await Dialog.say(root, str(DB.items.get(str(Game.bag[i].id), {}).get("desc", "")))
	return -1

## SPECIAL_TEXT_LUMINOUS_CAVE
static func run(root: Control, G) -> void:
	if Game.team.is_empty():
		return
	GVars.clear_arr(null, GVars.EVENT_LOCAL)
	var alone := Game.team.size() == 1
	var first := true
	while true:
		var c := await RedMsg.ask(root, S_INTRO if first else S_PROMPT, ["Evolve", "Info", "Cancel"])
		first = false
		if c == 1:
			await RedMsg.say(root, S_INFO)
			continue
		if c != 0:
			break
		if not alone:
			await RedMsg.say(root, S_ALONE)
			break
		# items
		var it1 := -1
		var it2 := -1
		var cancelled := false
		while true:
			var g := await RedMsg.ask(root, S_GIVE, ["No", "Yes", "Cancel"])
			if g == 1:
				if Game.bag.is_empty():
					await RedMsg.say(root, S_LACK_NEEDED)
					continue
				it1 = await _pick_item(root)
				if it1 < 0:
					continue
				var done2 := false
				while true:
					var g2 := await RedMsg.ask(root, S_GIVE2, ["No", "Yes", "Cancel"])
					if g2 == 1:
						if Game.bag.size() < 2:
							await RedMsg.say(root, S_ONE_ITEM)
							continue
						it2 = await _pick_item(root, it1)
						if it2 < 0:
							continue
						done2 = true
						break
					elif g2 == 0:
						done2 = true
						break
					else:
						cancelled = true
						break
				if done2 or cancelled:
					break
			elif g == 0:
				break
			else:
				cancelled = true
				break
		if cancelled:
			continue
		await _begin(root, G, it1, it2)
		break
	Audio.play_music("008")         # FadeInNewBGM_(MUS_FILE_SELECT)
	await RedMsg.say(root, S_RETURN)

static func _begin(root: Control, G, it1: int, it2: int) -> void:
	var e: Dictionary = Game.team[0]
	var items: Array = []
	for i in [it1, it2]:
		if i >= 0 and i < Game.bag.size():
			items.append(str(Game.bag[i].id))
	var st := evolve_status(e, items)
	Audio.fade_out_music(60)
	await RedMsg.say(root, S_BEGIN)
	var f: Dictionary = st.flags
	if not f.get("good", false):
		# Red compares the whole status word: a single reason gets its own text, several get "not yet"
		var k := "yet"
		if f.size() == 1:
			k = str(f.keys()[0])
		await RedMsg.say(root, S_LACK.get(k, S_LACK.yet))
		return
	var nm := str(e.get("name", ""))
	if nm == "":
		nm = str(DB.species.get(str(e.sp), {}).get("name", ""))
	Audio.sfx("511")
	await RedMsg.say(root, S_CHANGED, "", "Normal", [nm])
	var old_sp := str(e.sp)
	evolve_entry(e, str(st.target))
	# remove the used items (highest index first)
	var idx: Array = [it1, it2].filter(func(i): return i >= 0)
	idx.sort()
	idx.reverse()
	for i in idx:
		if i < Game.bag.size():
			Game.bag.remove_at(i)
	Game.flags["evolved"] = int(Game.flags.get("evolved", 0)) + 1      # IncrementNumEvolved (Adventure Log)
	Audio.sfx("210")
	# HasEvolutionCompleted -> the cave's EVOLUTION_HERO event (light + new sprite) runs during the text
	if G != null and GVars.get_val(null, GVars.EVENT_LOCAL) == 0:
		GVars.set_val(null, GVars.EVENT_LOCAL, 1)
		G.map_execute_event(GData.fn_id("EVOLUTION_HERO"), false)
	await RedMsg.say(root, S_EVOLVED, "", "Normal", [], [DB.species.get(old_sp, {}).get("name", old_sp), DB.species.get(str(e.sp), {}).get("name", e.sp)])
