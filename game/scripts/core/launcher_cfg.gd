extends RefCounted
## The launcher's choices (scripts/ui/launcher.gd): which Pokémon and Explorers of Sky dungeons are in the game,
## and the difficulty. Saved in user://launcher.json, for every save file. Without that file (dev builds, the
## APK) nothing changes: every Pokémon and dungeon is on and the difficulty is the one in Game Options.
## Loaded by path (no class_name): preload("res://scripts/core/launcher_cfg.gd").

static var PATH := ("user://test_setup/" if OS.get_cmdline_user_args().has("--test-setup") else "user://") + "launcher.json"   # the setup test keeps its own
const VERSION := 1

## Difficulty sliders: key -> [label, min, max, step, normal, unit]
const SLIDERS := {
	"lv": ["Enemy level", -10, 10, 1, 0, "lv"],
	"str": ["Enemy strength", 50, 200, 10, 100, "%"],
	"boss": ["Boss strength", 50, 200, 10, 100, "%"],
	"taken": ["Damage you take", 50, 200, 10, 100, "%"],
	"dealt": ["Damage you deal", 50, 200, 10, 100, "%"],
	"enemies": ["Enemies per floor", 50, 200, 10, 100, "%"],
	"exp": ["Exp. gained", 50, 300, 10, 100, "%"],
	"recruit": ["Recruit rate", 50, 300, 10, 100, "%"],
	"money": ["Money on floors", 50, 300, 10, 100, "%"],
	"items": ["Items on floors", 50, 200, 10, 100, "%"],
	"hunger": ["Hunger speed", 0, 200, 10, 100, "%"],
	"traps": ["Traps per floor", 0, 200, 10, 100, "%"],
}
const SLIDER_ORDER := ["lv", "str", "boss", "taken", "dealt", "enemies", "exp", "recruit", "money", "items", "hunger", "traps"]
## Presets: hard = Hard mode's level curve (scripts/core/difficulty.gd); the rest are slider values.
const PRESETS := {
	"Easy": {"hard": false, "lv": -3, "str": 80, "boss": 80, "taken": 70, "dealt": 130, "enemies": 80, "exp": 150,
		"recruit": 150, "money": 150, "items": 130, "hunger": 50, "traps": 50},
	"Normal": {"hard": false},
	"Hard": {"hard": true},
}
const PRESET_ORDER := ["Easy", "Normal", "Hard"]

static var _cfg := {}
static var _loaded := false

static func defaults() -> Dictionary:
	var d := {"v": VERSION, "parts": {}, "mons_off": [], "mons_extra": [], "dungeons_off": [], "hard": false, "preset": "Normal", "d": {}}
	for k in SLIDERS:
		d.d[k] = int(SLIDERS[k][4])
	return d

## The launcher's file was saved: its choices are in force.
static func active() -> bool:
	_load()
	return not _cfg.is_empty()

static func cfg() -> Dictionary:
	_load()
	return _cfg if not _cfg.is_empty() else defaults()

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_cfg = {}
	if not FileAccess.file_exists(PATH):
		return
	var v = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(v) != TYPE_DICTIONARY:
		return
	var d := defaults()
	for k in d:
		if v.has(k):
			if k == "d" and typeof(v.d) == TYPE_DICTIONARY:
				for s in v.d:
					if SLIDERS.has(s):
						d.d[s] = int(v.d[s])
			else:
				d[k] = v[k]
	_cfg = d
	_rebuild_sets()

static func save(c: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(c, " "))
	_cfg = c.duplicate(true)
	_loaded = true
	_rebuild_sets()
	_red_keys = {}

static var _mons_off := {}
static var _mons_extra := {}
static var _dun_off := {}

static func _rebuild_sets() -> void:
	_mons_off = {}
	_mons_extra = {}
	_dun_off = {}
	for s in _cfg.get("mons_off", []):
		_mons_off[str(s).substr(0, 4)] = true
	for s in _cfg.get("mons_extra", []):              # Pokémon switched on on top of Red's 386
		_mons_extra[str(s).substr(0, 4)] = true
	for k in _cfg.get("dungeons_off", []):
		_dun_off[str(k)] = true

# ------------------------------------------------------------------ what's in the game
static var _red_build := -1
static var _red_data := -1
static var _red_keys := {}

## The game data was built from the Red Rescue Team ROM alone (MD-Recomp's Red-only setup): only Red's
## Pokémon (Gen 1-3) and dungeons, no Explorers of Sky content (data/build_info.json, written by the build).
static func red_build() -> bool:
	if _red_build < 0:
		_red_build = 0
		if FileAccess.file_exists("res://data/build_info.json"):
			var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/build_info.json"))
			if typeof(v) == TYPE_DICTIONARY and bool(v.get("red_only", false)):
				_red_build = 1
	return _red_build == 1

## A full build (Red + Explorers of Sky + Remixed) can be played as Red, as everything, or anything between: the
## build keeps the tables as a Red-only build has them in data/red/ (tools/data/build.py), and the launcher's
## Game page picks Red's or Explorers of Sky / Remixed's version of each part.
static func has_parts() -> bool:
	if _red_data < 0:
		_red_data = 1 if not red_build() and FileAccess.file_exists("res://data/red/species.json") else 0
	return _red_data == 1

## The parts of the game that can be Red's own or the remake's additions:
## [key, name, Red's version, the other version, what it changes, what it needs: "red" = the Red tables a full
## build keeps (data/red/), "eos" = Explorers of Sky / Remixed data (not a Red-only build), "" = nothing]
const PARTS := [
	["pokemon", "Pokémon", "Red's 386", "All", "Red's Gen 1-3 Pokémon, or every generation and form (single ones: the Pokémon page).", "red"],
	["dungeons", "Dungeons", "Red's", "+ Explorers of Sky", "Red's dungeons, or Explorers of Sky's too (which ones: the Dungeons page).", "red"],
	["abilities", "Abilities", "Red's", "Remixed", "Red's Pokémon keep Red's abilities, or take the ones Explorers Remixed gave them.", "red"],
	["moves", "Move data", "Red's", "Remixed", "Power, accuracy and PP of the moves Red doesn't have: estimates, or Explorers Remixed's numbers.", "red"],
	["anim", "Move animations", "Red's", "Explorers of Sky", "Red Rescue Team's move animations and sounds, or Explorers of Sky's.", "red"],
	["iq", "IQ skills", "Red's 23", "+ Sky's", "Red's IQ skills, or Explorers of Sky's added to them.", "red"],
	["items", "Items", "Red's", "+ Explorers of Sky", "Explorers of Sky / Remixed items: floor drops, exclusive items, boxes.", "red"],
	["growth", "Move Growth", "Off", "On", "Explorers Remixed's Move Growth: moves gain Exp. with use and level up (more power, accuracy, PP).", "eos"],
	["swapshop", "Swap Shop", "Off", "On", "Croagunk's Swap Shop in Pokémon Square (Explorers Remixed's item recipes).", "eos"],
	["megas", "Mega Evolution", "Off", "On", "Rescue Team DX's Empowerment Seed: it drops after the story and Mega Evolves (or Primal Reverts) the Pokémon that can.", ""],
	["fairy", "Fairy type", "Off", "On", "Red has no Fairy type. Off: later Fairy Pokémon and Fairy moves go back to their older types (pure Fairy = Normal, as Clefairy is).", ""],
	["rules", "Remake rules", "Red's", "Remake", "DX recruiting, Smarter partner AI, burn and poison wearing off. Red's: Red's own rules (and they leave Game Options).", ""],
	["remakeitems", "Remake items", "Off", "On", "The remake's own items: the Exp. Share (Kecleon stocks one now and then).", ""],
]

## Parts the launcher's Game page can switch in this build (a Red-only build: the ones that need no Explorers of Sky data).
static func switchable() -> Array:
	return PARTS.filter(func(P): return _can_switch(str(P[5])))

static func _can_switch(need: String) -> bool:
	match need:
		"red":
			return has_parts()
		"eos":
			return not red_build()
	return true

## Part <p> is Red's own version. A part this build can't switch is Red's in a Red-only build and the additions in a
## full build without Red tables (the APK, dev builds); otherwise the Game page decides (unset: Red's in a Red-only
## build, the additions in a full one).
static func red_part(p: String) -> bool:
	var need := ""
	for P in PARTS:
		if P[0] == p:
			need = str(P[5])
	if not _can_switch(need):
		return red_build()
	return bool(cfg().get("parts", {}).get(p, red_build()))

## Which parts are Red's: {key: bool}.
static func red_parts() -> Dictionary:
	var out := {}
	for P in PARTS:
		out[P[0]] = red_part(P[0])
	return out

## Every part is Red's: vanilla Red Rescue Team (a Red-only build, or a full build set to Vanilla Red).
static func red_only() -> bool:
	return not red_parts().values().has(false)

## The keys of a Red table ("species" / "dungeons") from data/red/.
static func red_keys(table: String) -> Dictionary:
	if not _red_keys.has(table):
		var keys := {}
		var v = JSON.parse_string(FileAccess.get_file_as_string("res://data/red/%s.json" % table)) if has_parts() else null
		if typeof(v) == TYPE_DICTIONARY:
			for k in (v.get("dungeons", {}) if table == "dungeons" else v):
				keys[str(k)] = true
		_red_keys[table] = keys
	return _red_keys[table]

## The path of a data file: when its part is Red's, the Red version (data/red/<name>.json) when there is one,
## and "" for Explorers of Sky / Remixed-only tables a Red-only build doesn't have.
const PART_OF := {"iq": "iq", "swap_shop": "swapshop", "move_growth": "growth"}
const EOS_ONLY := ["swap_shop", "move_growth"]
static func data_path(name: String) -> String:
	if has_parts() and red_part(str(PART_OF.get(name, ""))):
		if name in EOS_ONLY:
			return ""
		if FileAccess.file_exists("res://data/red/%s.json" % name):
			return "res://data/red/%s.json" % name
	return "res://data/%s.json" % name

## A species is one of Red's: Gen 1-3, no Megas or Primals (and in a full build in Red's table).
static func red_mon(sp: String) -> bool:
	if has_parts() and not red_keys("species").has(sp):
		return false
	if is_mega(sp):                                       # Megas / Primals: the Mega Evolution switch
		return false
	var base := sp.substr(0, 4)
	return not (base.is_valid_int() and gen_of(int(base)) > 3)

static func is_mega(sp: String) -> bool:
	return sp.length() > 4 and sp[4] in ["M", "P"]

## Red's rules instead of the remake's (the Game page's Remake rules part): these options take Red's value.
const RED_RULES := {"qol_statusfade": false, "qol_recruit": 0, "qol_partner_ai": 0}

static func red_rule(k: String) -> bool:
	return RED_RULES.has(k) and red_part("rules")

## Mega Evolution (and the Empowerment Seed) is on.
static func megas_on() -> bool:
	return not red_part("megas")

## A species is in the game (forms follow their base number; Megas / Primals need Mega Evolution on). With Pokémon on
## Red's 386, a later one is in only when the Pokémon page switched it on ("mons_extra").
static func mon_on(sp: String) -> bool:
	_load()
	var base := sp.substr(0, 4)
	if is_mega(sp):
		return megas_on() and mon_on(base)
	if red_part("pokemon") and not red_mon(sp):
		return _mons_extra.has(base)                      # Red's 386 plus the ones switched on (the Pokémon page)
	return _mons_off.is_empty() or not _mons_off.has(base)

## A dungeon is in the game: Red's always; an Explorers of Sky one unless its chain was switched off.
static func dungeon_on(k: String) -> bool:
	_load()
	if has_parts() and red_part("dungeons") and not red_keys("dungeons").has(k):
		return false
	if _dun_off.is_empty():
		return true
	return not _dun_off.has(Story.eos_chain_head(k))

static func val(k: String) -> int:
	return int(cfg().d.get(k, SLIDERS[k][4])) if SLIDERS.has(k) else 0

## A percentage slider as a factor (1.0 = normal).
static func f(k: String) -> float:
	return val(k) / 100.0

## Hard mode's level curve: the launcher's choice when it's in use, else the save's flag.
static func hard(save_flag: bool) -> bool:
	return bool(cfg().get("hard", false)) if active() else save_flag

## Generation of a national dex number.
static func gen_of(n: int) -> int:
	var tops := [151, 251, 386, 493, 649, 721, 809, 905, 1025]
	for i in tops.size():
		if n <= int(tops[i]):
			return i + 1
	return 9

# ------------------------------------------------------------------ applying it
## Called once the launcher's Play is pressed (and at boot): the Game mode's tables, spawn lists without the switched-off Pokémon,
## and the hunger option from the Hunger speed slider.
static func apply() -> void:
	DB.use_parts(red_parts())                       # the Game page's Red parts over the full tables
	if not active():
		return
	_filter_spawns()
	var G = Engine.get_main_loop().root.get_node_or_null("/root/Game")
	if G and typeof(G.settings) == TYPE_DICTIONARY:
		G.settings["hunger"] = val("hunger") > 0

## Each floor's list ("pk": [species, level, weight, ...]) without the Pokémon that are off. Kecleon and other
## Lv 90 / weight-0 entries stay. A floor left with nobody borrows the nearest floor's Pokémon in the same dungeon,
## or the last floor of an earlier part of its Explorers of Sky chain; with nobody left at all it keeps its list.
static func _filter_spawns() -> void:
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	var kept_of := {}
	for k in dd:
		var kept: Array = []
		for fl in dd[k].get("floors", []):
			if not fl.has("pk_all"):
				fl["pk_all"] = fl.get("pk", [])
			var out: Array = []
			var wild := 0
			for e in fl.pk_all:
				if int(e[1]) >= 90 or int(e[2]) <= 0 or mon_on(str(e[0])):
					out.append(e)
					if int(e[2]) > 0 and int(e[1]) < 90:
						wild += 1
			kept.append([out, wild])
		kept_of[k] = kept
	for k in dd:
		var floors: Array = dd[k].get("floors", [])
		var kept: Array = kept_of[k]
		for i in floors.size():
			var has_wild := false
			for e in floors[i].pk_all:
				if int(e[2]) > 0 and int(e[1]) < 90:
					has_wild = true
			if int(kept[i][1]) > 0 or not has_wild:
				floors[i]["pk"] = kept[i][0]
				continue
			var donor: Array = []
			for dist in range(1, floors.size()):          # the nearest floor of this dungeon that kept someone
				for j in [i - dist, i + dist]:
					if donor.is_empty() and j >= 0 and j < floors.size() and int(kept[j][1]) > 0:
						donor = kept[j][0]
				if not donor.is_empty():
					break
			if donor.is_empty():                          # else the earlier parts of its Explorers of Sky chain
				var chain: Array = Story.eos_chain_of(str(k))
				var ci := chain.find(str(k))
				for cj in range(ci - 1, -1, -1):
					var ck: Array = kept_of.get(chain[cj], [])
					for fj in range(ck.size() - 1, -1, -1):
						if int(ck[fj][1]) > 0:
							donor = ck[fj][0]
							break
					if not donor.is_empty():
						break
			if donor.is_empty():
				floors[i]["pk"] = floors[i].pk_all            # nobody left anywhere: keep the list (it can't be empty)
				continue
			var out2: Array = kept[i][0].duplicate()
			for e in donor:
				if int(e[2]) > 0 and int(e[1]) < 90:
					out2.append(e)
			floors[i]["pk"] = out2

## Floor generator settings scaled by the sliders (enemies, items, buried items, traps).
static func scale_props(props: Dictionary) -> void:
	if not active():
		return
	for pair in [["enemyDensity", "enemies"], ["itemDensity", "items"], ["buriedItemDensity", "items"], ["trapDensity", "traps"]]:
		var v := int(props.get(pair[0], 0)) & 0xFF
		if v <= 0:
			continue
		var n := int(round(v * f(pair[1])))
		props[pair[0]] = clampi(n, 1 if pair[1] == "enemies" else 0, 255)

## Enemy / boss strength: scales a freshly made enemy's stats (Kecleon and other Lv 90 Pokémon stay).
static func strengthen(m, boss := false) -> void:
	if not active() or m == null or int(m.level) >= 90:
		return
	var pct := val("boss" if boss else "str")
	if pct == 100:
		return
	m.set_meta("lscale", pct)
	var k := pct / 100.0
	m.max_hp = maxi(1, int(round(m.max_hp * k)))
	m.atk = maxi(1, int(round(m.atk * k)))
	m.spa = maxi(1, int(round(m.spa * k)))
	m.def = maxi(1, int(round(m.def * k)))
	m.spd = maxi(1, int(round(m.spd * k)))
	m.hp = m.max_hp

## Damage after Red's formula: the team's hits on enemies and enemies' hits on the team.
static func scale_damage(dmg: int, att_team: bool, def_team: bool) -> int:
	if not active() or dmg <= 0 or att_team == def_team:
		return dmg
	var k := f("dealt") if att_team else f("taken")
	return maxi(1, int(round(dmg * k)))

static func level_offset(lv: int) -> int:
	if not active() or lv >= 90:
		return lv
	return clampi(lv + val("lv"), 1, 100)
