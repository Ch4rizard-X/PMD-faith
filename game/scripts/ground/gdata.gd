class_name GData
extends RefCounted
## Red's ground data (from gen_ground_scripts.py / gen_ground_extra.py):
##   scripts    every ScriptCommand array -> scr[i] = [[op, argByte, argShort, arg1, arg2, text], ...]
##   maps       gMapScriptTable per GroundMapID: groups -> sectors -> lives/objects/effects/events/station
##   common     gFunctionScriptTable, gScriptVarInfo, map conversion, map files, enum names
##   extra      dungeon info, rescue tables, entity type tables, Red monster id -> species key
## A script pointer is a Vector2i(script index, command index); NULL_PTR = (-1, -1).

const NULL_PTR := Vector2i(-1, -1)

static var scr: Array = []            # script index -> commands
static var scr_names: Array = []
static var _name_idx := {}
static var maps: Array = []
static var common: Dictionary = {}
static var extra: Dictionary = {}
static var _enum_rev := {}            # enum kind -> {NAME: value}
static var _loaded := false
static var croagunk_kind := -1
static var debug_kind := -1         # remake: the Swap Shop's Croagunk (see Ground.lives_select_map)

static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var s: Dictionary = _json("res://data/ground/scripts.json")
	for k in s:
		_name_idx[k] = scr.size()
		scr_names.append(k)
		scr.append(s[k])
	maps = _json("res://data/ground/maps.json")
	common = _json("res://data/ground/common.json")
	extra = _json("res://data/ground/extra.json")
	# remake: Croagunk's Swap Shop (Explorers of Sky) gets a lives kind of its own, shaped like the Kecleon brothers
	croagunk_kind = extra.lives_types.size()
	extra.lives_types.append([5, 0, 2, 1])
	debug_kind = extra.lives_types.size()          # remake: the Debug NPC (Game Options -> Debug NPC)
	extra.lives_types.append([5, 0, 2, 1])
	GVars.init()

static func _json(p: String) -> Variant:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		push_error("missing " + p)
		return {}
	return JSON.parse_string(f.get_as_text())

## "name" or "name+N" -> pointer
static func ptr(name) -> Vector2i:
	if name == null or str(name) == "":
		return NULL_PTR
	var n := str(name)
	var off := 0
	var plus := n.find("+")
	if plus > 0:
		off = int(n.substr(plus + 1))
		n = n.substr(0, plus)
	if not _name_idx.has(n):
		push_warning("ground: unknown script " + n)
		return NULL_PTR
	return Vector2i(_name_idx[n], off)

static func cmd(p: Vector2i) -> Array:
	var a: Array = scr[p.x]
	if p.y >= a.size():
		return [0xEF, 0, 0, 0, 0, null]      # ran off the end: behave like RET
	return a[p.y]

static func fn_script(id: int) -> Vector2i:
	var f: Dictionary = common.functions[id]
	return ptr(f.script)

static func fn_type(id: int) -> int:
	return int(common.functions[id].type)

static func fn_id(name: String) -> int:
	return enum_value("script_ids", name)

static func enum_value(kind: String, name: String) -> int:
	if not _enum_rev.has(kind):
		var d := {}
		var src: Dictionary = common.enums.get(kind, extra.enums.get(kind, {}))
		for v in src:
			d[src[v]] = int(v)
		_enum_rev[kind] = d
	return int(_enum_rev[kind].get(name, -1))

static func enum_name(kind: String, v: int) -> String:
	var src: Dictionary = common.enums.get(kind, extra.enums.get(kind, {}))
	return str(src.get(str(v), "?%d" % v))

static func map_id(name: String) -> int:
	# constants/ground_map.h aliases
	name = {"MAP_TEAM_BASE": "MAP_TEAM_BASE_PIKACHU_BASIC", "MAP_TEAM_BASE_INSIDE": "MAP_TEAM_BASE_INSIDE_PIKACHU_BASIC"}.get(name, name)
	return enum_value("maps", name)

static func rescue_id(name: String) -> int:
	return enum_value("rescue", name)

static func dungeon_info(script_dungeon: int) -> Dictionary:
	if script_dungeon < 0 or script_dungeon >= extra.dungeons.size():
		return extra.dungeons[0]
	return extra.dungeons[script_dungeon]

static func rescue_to_script(r: int) -> int:
	if r < 0 or r >= extra.rescue_to_script.size():
		return -1
	return int(extra.rescue_to_script[r])

static func map_conv(map: int) -> Dictionary:
	return common.map_conv[map]

static func species_of_red(red_id: int) -> String:
	return str(extra.red_mon.get(str(red_id), ""))

static func red_of_species(key: String) -> int:
	for k in extra.red_mon:
		if extra.red_mon[k] == key:
			return int(k)
	if key.length() > 4:          # a palette variant ("0352p", the purple Kecleon) is still that species
		return red_of_species(key.substr(0, 4))
	return 0

static func fa_of_map(map: int) -> int:
	for e in extra.fa_maps:
		if int(e[0]) == map:
			return int(e[1])
	return 0

static func map_of_fa(fa: int) -> int:
	for e in extra.fa_maps:
		if int(e[1]) == fa:
			return int(e[0])
	return -1

# ------------------------------------------------------------------ ground map art (res://assets/ground)
static var _bg_index: Dictionary = {}
static var _orn: Dictionary = {}
static var _json_cache := {}

static func ground_bg() -> Dictionary:
	if _bg_index.is_empty():
		_bg_index = _json("res://assets/ground/index.json")
	return _bg_index

static func ground_json(name: String) -> Variant:
	if name == "":
		return []
	if _json_cache.has(name):
		return _json_cache[name]
	var v = _json("res://assets/ground/" + name)
	if _json_cache.size() > 8:
		_json_cache.clear()
	_json_cache[name] = v
	return v

static func ground_collision(map_file: String, info: Dictionary) -> Array:
	var c = info.get("collision", "")
	if c == null or str(c) == "":
		return []
	var v = ground_json(str(c))
	return v if v is Array else []

## Map layer texture; the HD (4x xBRZ) version when present and HD is on.
static func ground_tex(name: String, allow_hd := true) -> Texture2D:
	var base := name.get_basename()
	if allow_hd and bool(Game.settings.get("hd_maps", true)):
		for ext in [".webp", ".png"]:
			var p := "res://assets/ground/hd/%s_hd%s" % [base, ext]
			if ResourceLoader.exists(p):
				return load(p)
	for ext in [".png", ".webp"]:
		var p2 := "res://assets/ground/%s%s" % [base, ext]
		if ResourceLoader.exists(p2):
			return load(p2)
	return null

static func ornaments() -> Dictionary:
	if _orn.is_empty():
		if not FileAccess.file_exists("res://assets/ground/orn/ornaments.json"):
			_orn = {"_": {}}
			return _orn
		var v = _json("res://assets/ground/orn/ornaments.json")
		_orn = v if v is Dictionary else {"_": {}}
	return _orn
