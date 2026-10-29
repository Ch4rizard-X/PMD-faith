extends Node
## Autoload "DB": game data tables + stat formulas (Red's level-up tables).

const DIRS := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1)]
const STAT_KEYS := ["hp", "atk", "spa", "def", "spd"]
const TILE := 24

var species: Dictionary = {}
var moves: Dictionary = {}
var items: Dictionary = {}
var growth: Dictionary = {}
var sprites: Dictionary = {}
var tilesets: Dictionary = {}
var marks: Dictionary = {}
var item_icons: Dictionary = {}
var types: Dictionary = {}
var evo: Dictionary = {}
var dungeons: Dictionary = {}
var _tex_cache: Dictionary = {}
var _uid := 1

func _ready() -> void:
	species = _json("species")
	moves = _json("moves")
	items = _json("items")
	growth = _json("growth")
	sprites = _json("sprites")
	tilesets = _json("tilesets")
	marks = _json("marks")
	item_icons = _json("item_icons")
	types = _json("types")
	evo = _json("evo")
	dungeons = _json("dungeons")

## Red dungeon id (DUNGEON_*) -> our key ("" if none). dungeons.json keeps Red's order.
func dungeon_key(did: int) -> String:
	var dd: Dictionary = dungeons.get("dungeons", {})
	var keys := dd.keys()
	return str(keys[did]) if did >= 0 and did < keys.size() else ""

func dungeon_data(did: int) -> Dictionary:
	return dungeons.get("dungeons", {}).get(dungeon_key(did), {})

func _json(n: String) -> Dictionary:
	var f := FileAccess.open("res://data/%s.json" % n, FileAccess.READ)
	if f == null:
		push_warning("missing data/%s.json" % n)
		return {}
	var v = JSON.parse_string(f.get_as_text())
	return v if v is Dictionary else {}

static func dir_index(d: Vector2i) -> int:
	var s := Vector2i(signi(d.x), signi(d.y))
	for i in 8:
		if DIRS[i] == s:
			return i
	return -1

func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex_cache[path] = t
	return t

# ---------------------------------------------------------------- stats
func _pmd(sp: String) -> Variant:
	var g: Dictionary = growth.get("mon", {})
	if g.has(sp):
		return g[sp]
	if sp.length() > 4 and g.has(sp.substr(0, 4)):
		return g[sp.substr(0, 4)]
	return null

## Red's stats at level L (HP, Attack, Sp. Atk, Defense, Sp. Def).
func stats_at(sp: String, L: int) -> Dictionary:
	var S: Dictionary = species.get(sp, {})
	if S.has("megaBase"):
		var o := stats_at(S.megaBase, L)
		var mul: Array = S.get("mul", [1, 1, 1, 1, 1])
		for j in 5:
			o[STAT_KEYS[j]] = int(round(o[STAT_KEYS[j]] * float(mul[j])))
		return o
	L = maxi(1, L)
	var d = _pmd(sp)
	var out := {}
	if d != null and L > 100:   # past Red's table: Lv 100 + average gain per level over 51-100
		var top := stats_at(sp, 100)
		var mid := stats_at(sp, 50)
		for k in STAT_KEYS:
			out[k] = top[k] + int(floor((top[k] - mid[k]) * (L - 100) / 50.0))
		return out
	if d == null:
		var b: Array = S.get("b", [50, 50, 50, 50, 50, 50])
		out.hp = int(floor(2 * b[0] * L / 100.0)) + L + 10
		var keys := ["atk", "def", "spa", "spd"]
		for i in 4:
			out[keys[i]] = int(floor(2 * b[i + 1] * L / 100.0)) + 5
		return out
	if d[5] is String:
		var gs: String = d[5]
		for j in 5:
			var v := int(d[j])
			for l in range(2, L + 1):
				v += gs.unicode_at(j * 99 + l - 2) - 48
			out[STAT_KEYS[j]] = v
	else:
		var curve: Array = growth.curve
		for j in 5:
			out[STAT_KEYS[j]] = int(round(float(d[j]) + (float(d[5][j]) - float(d[j])) * float(curve[j][L - 1])))
	return out

func exp_at(sp: String, L: int) -> int:
	var d = _pmd(sp)
	L = clampi(L, 1, 999)
	if d == null:
		return L * L * L
	var x: Array = growth.xp[int(d[6])]
	if L <= 100:
		return int(x[L - 1])
	var d1: int = int(x[99]) - int(x[98])
	var d2: int = maxi(0, d1 - (int(x[98]) - int(x[97])))
	var n := L - 100
	return int(x[99]) + n * d1 + d2 * n * (n + 1) / 2

func default_moves(sp: String, L: int) -> Array:
	var learn: Array = species.get(sp, {}).get("learn", [])
	var names: Array = []
	for e in learn:
		if int(e[0]) <= L and moves.has(e[1]):
			names.erase(e[1])
			names.append(e[1])
	if names.size() > 4:
		names = names.slice(names.size() - 4)
	var out: Array = []
	for n in names:
		out.append({"name": n, "pp": int(moves[n].pp), "max_pp": int(moves[n].pp), "on": true, "linked": false})
	return out

func make_mon(sp: String, L: int, side: String, extra := {}) -> Mon:
	var m := Mon.new()
	m.uid = _uid
	_uid += 1
	var S: Dictionary = species.get(sp, {})
	m.sp = sp
	m.name = extra.get("name", S.get("name", "???"))
	m.side = side
	m.level = L
	m.exp = extra.get("exp", exp_at(sp, L))
	m.types = S.get("types", ["Normal"]).duplicate()
	var abl: Array = S.get("ab", [])
	# Red: a Pokémon has both of its abilities at once (EntityInfo.abilities[2])
	m.ability = extra.get("ability", abl[0] if abl.size() > 0 else "")
	m.ability2 = abl[1] if abl.size() > 1 else ""
	recalc(m)
	m.hp = m.max_hp
	m.moves = extra.get("moves", default_moves(sp, L))
	m.held = extra.get("held", "")
	m.iq = extra.get("iq", 0)
	return m

## Recompute stats from level (+ permanent boosts stored in m.bonus if present).
func recalc(m: Mon) -> void:
	var s := stats_at(m.sp, m.level)
	var bonus: Dictionary = m.get_meta("bonus", {})
	var old_max := m.max_hp
	m.max_hp = int(s.hp) + int(bonus.get("hp", 0))
	m.atk = int(s.atk) + int(bonus.get("atk", 0))
	m.spa = int(s.spa) + int(bonus.get("spa", 0))
	m.def = int(s.def) + int(bonus.get("def", 0))
	m.spd = int(s.spd) + int(bonus.get("spd", 0))
	if m.has_meta("lscale"):                        # launcher: enemy / boss strength
		var k := int(m.get_meta("lscale")) / 100.0
		m.max_hp = maxi(1, int(round(m.max_hp * k)))
		m.atk = maxi(1, int(round(m.atk * k)))
		m.spa = maxi(1, int(round(m.spa * k)))
		m.def = maxi(1, int(round(m.def * k)))
		m.spd = maxi(1, int(round(m.spd * k)))
	if old_max > 1 and m.hp > 0:
		m.hp = mini(m.max_hp, m.hp + (m.max_hp - old_max))

func move_data(n: String) -> Dictionary:
	return moves.get(n, {})

func item_name(id: String) -> String:
	return items.get(id, {}).get("name", id)
