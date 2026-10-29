extends RefCounted
## The launcher's choices (scripts/ui/launcher.gd): which Pokémon and Explorers of Sky dungeons are in the game,
## and the difficulty. Saved in user://launcher.json, for every save file. Without that file (dev builds, the
## APK) nothing changes: every Pokémon and dungeon is on and the difficulty is the one in Game Options.
## Loaded by path (no class_name): preload("res://scripts/core/launcher_cfg.gd").

const PATH := "user://launcher.json"
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
	var d := {"v": VERSION, "mons_off": [], "dungeons_off": [], "hard": false, "preset": "Normal", "d": {}}
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

static var _mons_off := {}
static var _dun_off := {}

static func _rebuild_sets() -> void:
	_mons_off = {}
	_dun_off = {}
	for s in _cfg.get("mons_off", []):
		_mons_off[str(s).substr(0, 4)] = true
	for k in _cfg.get("dungeons_off", []):
		_dun_off[str(k)] = true

# ------------------------------------------------------------------ what's in the game
## A species is in the game (forms and Megas follow their base number).
static func mon_on(sp: String) -> bool:
	_load()
	return _mons_off.is_empty() or not _mons_off.has(sp.substr(0, 4))

## A dungeon is in the game: Red's always; an Explorers of Sky one unless its chain was switched off.
static func dungeon_on(k: String) -> bool:
	_load()
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
## Called once the launcher's Play is pressed (and at boot): spawn lists without the switched-off Pokémon,
## and the hunger option from the Hunger speed slider.
static func apply() -> void:
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
