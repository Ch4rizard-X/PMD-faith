class_name DungeonGfx
extends RefCounted
## Red's dungeon graphics taken from the ROM by tools_dungeon/gen_dungeon_gfx.py (data/dungeon_gfx.json,
## assets/dungeon/): tileset palette animation (bNNcanm), boss arenas (b64..b75), status icons, weather
## colour ramps (colvec) and efbg weather animations, the floor banner font (banfont) and map tiles (zmappat).

const DIR := "res://assets/dungeon/"
static var _data: Dictionary = {}
static var _talk: Dictionary = {}
static var _loaded := false

static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var f := FileAccess.open("res://data/dungeon_gfx.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
		var f2 := FileAccess.open("res://data/dungeon_talk.json", FileAccess.READ)
		if f2:
			var t = JSON.parse_string(f2.get_as_text())
			if t is Dictionary:
				_talk = t
	return _data

static func tex(file: String) -> Texture2D:
	if file == "" or not ResourceLoader.exists(DIR + file):
		return null
	return load(DIR + file)

## Red tileset number behind a TerrainView key ("r14", "t14", "a66"); -1 for EoS sets ("s012").
static func tileset_no(ts_key: String) -> int:
	if ts_key.length() < 2 or not (ts_key[0] in ["r", "t", "a"]):
		return -1
	return int(ts_key.substr(1))

static func is_arena(ts_key: String) -> bool:
	return ts_key.begins_with("a") and data().get("arenas", {}).has(str(tileset_no(ts_key)))

## TerrainView key for Red tileset t (arena sets 64+ only when their graphics were extracted).
static func arena_key(t: int) -> String:
	if t >= 64 and data().get("arenas", {}).has(str(t)):
		return "a%02d" % t
	return ""

## [[duration, [colour hex...], base hex] x 32] for tileset t (Red's gDungeonAnimatedColors).
static func anim(t: int) -> Array:
	return data().get("anim", {}).get(str(t), [])

## Species talk line (talkN / talkpN files, sub_806A3D4): kind "mon" | "partner", id 0..3
## (3 = level up). Returns "" when the species has none.
static func talk(sp: String, id: int, partner := false) -> String:
	data()
	var tbl: Dictionary = _talk.get("partner" if partner else "mon", {})
	var arr: Array = tbl.get(sp, tbl.get(sp.substr(0, 4), []))
	if id < 0 or id >= arr.size():
		return ""
	return str(arr[id])

static func talk_special(key: String, id: int) -> String:
	data()
	var arr: Array = _talk.get("special", {}).get(key, [])
	return str(arr[id]) if id < arr.size() else ""
