class_name DungeonSave
extends RefCounted
## Red's Quicksave (dungeon suspend) + an autosave at the start of every floor.
##
##   DungeonSave.save(dungeon)               # write user://dungeon_suspend.json (whole floor + run state)
##   DungeonSave.load_into(dungeon) -> bool  # rebuild a fresh Dungeon (already in the tree, hud/ui_root set)
##   DungeonSave.has_suspend() / clear() / info()
##   DungeonSave.save_and_quit(dungeon)      # "Quicksave" menu command: save, stop the dungeon, back to title
##
## Red rule: resuming deletes the suspend file, so the same quicksave can't be loaded twice.
## The autosave writes the same file silently at each new floor, so after a crash the run resumes at
## that floor's start.
##
## File: JSON {"v", "dkey", "dname", "floor", "label", "team", "time", "state"} where "state" is
## JSON.from_native() of the full state dictionary (keeps Vector2i / Rect2i / packed arrays / int keys
## exact). See _state() for its fields.

const PATH := "user://dungeon_suspend.json"
const VERSION := 1

## FloorState vars that are rebuilt rather than stored.
const FS_SKIP := ["mons", "leader", "rng", "_red_exits_cache"]
## Mon vars that are not stored (scene node) / metas that only live during an animation.
const MON_SKIP := ["visual"]
const META_SKIP := ["fainting"]
## Dungeon vars stored as-is (plain data).
const DUNGEON_VARS := ["dkey", "dname", "floor_i", "belly", "belly_max", "belly_state", "wind_state", "spawn_timer", "mem", "recruited_names", "dx_turns", "shop_base", "shop_stole"]
## Game fields that change inside a dungeon (snapshotted so the suspend file is self-consistent).
const GAME_VARS := ["team", "bag", "money", "jobs", "flags", "rank_points", "storage"]

# ------------------------------------------------------------------ public API
static func has_suspend() -> bool:
	return FileAccess.file_exists(PATH)

static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))

## Header of the suspend file (no state): {dkey, dname, floor, label, team, time} or {}.
static func info() -> Dictionary:
	var d := _read_raw()
	d.erase("state")
	return d

static func save(dungeon) -> void:
	if dungeon == null or dungeon.fs == null:
		return
	# progress of the team goes back to the team entries too (as on the stairs), and the main save is
	# written so that a crash leaves save.json and the suspend file in step
	for m in dungeon.team_mons:
		Game.store_mon(m)
	var st := _state(dungeon)
	if dungeon.has_method("restart_floor_on_load") and dungeon.restart_floor_on_load() and not dungeon._entry_state.is_empty():
		st = dungeon._entry_state          # boss / fixed floor: resume from the floor's start (cutscene again)
	var head := {
		"v": VERSION,
		"dkey": str(dungeon.dkey),
		"dname": str(dungeon.ddata.get("name", dungeon.dkey)),
		"floor": int(dungeon.floor_i),
		"label": _floor_label(dungeon),
		"team": dungeon.team_mons.filter(func(m): return m.hp > 0).map(func(m): return "%s Lv%d" % [m.name, m.level]),
		"time": Time.get_datetime_string_from_system(),
		"state": JSON.from_native(st),
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(head))
		f.close()
	Game.save_game(true)

## Autosave at the start of a floor (same file, no message).
static func autosave(dungeon) -> void:
	if not bool(Game.settings.get("qol_autosave", true)):
		return                      # Game Options -> Auto save: Off
	save(dungeon)

## The dungeon's "Quicksave" command: write the file, stop the dungeon and hand over to main.gd
## (quicksave_exit() shows the message and returns to the title screen).
static func save_and_quit(dungeon) -> void:
	save(dungeon)
	dungeon.result_sent = true
	dungeon.busy = true
	if dungeon.autoplay:
		dungeon.autoplay = false
	var p: Node = dungeon.get_parent()
	if p and p.has_method("quicksave_exit"):
		p.call_deferred("quicksave_exit")
	else:
		dungeon.finished.emit.call_deferred("quit")

## Restore a suspended run into a fresh Dungeon node (in the tree, with hud and ui_root set).
## Deletes the suspend file on success (Red rule). Does not show the floor banner.
static func load_into(dungeon) -> bool:
	var raw := _read_raw()
	if raw.is_empty() or int(raw.get("v", 0)) != VERSION or not raw.has("state"):
		return false
	var st = JSON.to_native(raw.state)
	if not st is Dictionary or not DB.dungeons.get("dungeons", {}).has(str(st.get("dkey", ""))):
		return false
	_apply(dungeon, st)
	clear()
	return true

# ------------------------------------------------------------------ serialize
## The run as it stands when a floor starts, before it is generated: no floor, only the team, the Game data
## and the dungeon's RNG. Loading it builds that floor again from the same seed ("fresh": true).
static func entry_state(d) -> Dictionary:
	var st := {"fresh": true}
	for k in DUNGEON_VARS:
		if k in d:
			st[k] = _plain(d.get(k))
	st.rng = [d.rng.seed, d.rng.state]
	var mons: Array = []
	for m in d.team_mons:
		Game.store_mon(m)
		mons.append(_mon_dict(m))
	st.mons = mons
	st.team_mons = d.team_mons.map(func(m): return m.uid)
	st.floor_mons = []
	st.uid_next = DB._uid
	var g := {}
	for k in GAME_VARS:
		g[k] = _plain(Game.get(k))
	st.game = g
	if d.hud and "log_all" in d.hud:
		st.log = d.hud.log_all.slice(maxi(0, d.hud.log_all.size() - 60))
	if d.has_method("save_extra"):
		st.extra = _plain(d.save_extra())
	return JSON.to_native(JSON.from_native(st))      # a deep copy: later changes on the floor don't leak in

static func _state(d) -> Dictionary:
	var st := {}
	for k in DUNGEON_VARS:
		if k in d:
			st[k] = _plain(d.get(k))
	st.rng = [d.rng.seed, d.rng.state]
	# floor
	var fs: FloorState = d.fs
	var fsd := {}
	for p in fs.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name in FS_SKIP:
			fsd[p.name] = _plain(fs.get(p.name))
	fsd.rng = [fs.rng.seed, fs.rng.state]
	fsd.meta = _metas(fs, null)
	fsd.leader = fs.leader.uid if fs.leader else -1
	st.fs = fsd
	st.ts_key = _ts_key(d)
	# every Pokémon: the floor's plus fainted team members that stay in team_mons
	var all: Array = []
	for m in fs.mons:
		if not m in all:
			all.append(m)
	for m in d.team_mons:
		if not m in all:
			all.append(m)
	var mons: Array = []
	for m in all:
		mons.append(_mon_dict(m))
	st.mons = mons
	st.floor_mons = fs.mons.map(func(m): return m.uid)
	st.team_mons = d.team_mons.map(func(m): return m.uid)
	st.uid_next = DB._uid
	# Game data that changes during the run
	var g := {}
	for k in GAME_VARS:
		g[k] = _plain(Game.get(k))
	st.game = g
	# message log (last 60 lines)
	if d.hud and "log_all" in d.hud:
		st.log = d.hud.log_all.slice(maxi(0, d.hud.log_all.size() - 60))
	# extra state a newer dungeon.gd may keep (optional hook)
	if d.has_method("save_extra"):
		st.extra = _plain(d.save_extra())
	return st

static func _mon_dict(m: Mon) -> Dictionary:
	var md := {}
	for p in m.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not p.name in MON_SKIP:
			md[p.name] = _plain(m.get(p.name))
	md.meta = _metas(m, m)
	return md

static func _metas(o: Object, m) -> Dictionary:
	var out := {}
	for k in o.get_meta_list():
		if k in META_SKIP:
			continue
		var v = o.get_meta(k)
		if k == "entry" and v is Dictionary:
			var ti := _team_index(v)
			if ti >= 0:
				out["entry@team"] = ti          # the Game.team entry itself (restored by index)
				continue
		if k == "bonus" and m != null and m.has_meta("entry") and _team_index(m.get_meta("entry")) >= 0:
			continue                             # shared with the team entry; relinked on load
		if v is Object:
			continue
		out[k] = _plain(v)
	return out

static func _team_index(e) -> int:
	if not e is Dictionary:
		return -1
	for i in Game.team.size():
		if is_same(Game.team[i], e):
			return i
	return -1

## Deep copy with Objects removed (JSON.from_native can't keep node / Mon references).
static func _plain(v):
	if v is Object:
		return null
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_plain(x))
		return a
	if v is Dictionary:
		var o := {}
		for k in v:
			if k is Object:
				continue
			o[k] = _plain(v[k])
		return o
	return v

# ------------------------------------------------------------------ restore
static func _apply(d, st: Dictionary) -> void:
	d.busy = true
	d.result_sent = false
	# Game snapshot first: team entries are relinked by index below
	var g: Dictionary = st.get("game", {})
	for k in g:
		if k in Game:
			Game.set(k, g[k])
	if Game.team.size() > 0:
		Game.hero = Game.team[0]
	if Game.team.size() > 1:
		Game.partner = Game.team[1]
	for k in DUNGEON_VARS:
		if st.has(k) and k in d:
			d.set(k, st[k])
	d.ddata = DB.dungeons.get("dungeons", {}).get(d.dkey, {})
	if st.has("rng"):
		d.rng.seed = int(st.rng[0])
		d.rng.state = int(st.rng[1])
	_setup_nodes(d)
	# Pokémon
	var by_uid := {}
	var max_uid := 0
	for md in st.get("mons", []):
		var m := Mon.new()
		for k in md:
			if k == "meta":
				continue
			if k in m:
				m.set(k, md[k])
		var meta: Dictionary = md.get("meta", {})
		for k in meta:
			if k == "entry@team":
				var ti := int(meta[k])
				if ti < Game.team.size():
					m.set_meta("entry", Game.team[ti])
					m.set_meta("bonus", Game.team[ti].get("bonus", {}))
			else:
				m.set_meta(k, meta[k])
		by_uid[m.uid] = m
		max_uid = maxi(max_uid, m.uid)
	DB._uid = maxi(int(DB._uid), maxi(int(st.get("uid_next", 1)), max_uid + 1))
	d.team_mons.clear()
	for u in st.get("team_mons", []):
		if by_uid.has(int(u)):
			d.team_mons.append(by_uid[int(u)])
	if bool(st.get("fresh", false)):
		# saved on a boss / fixed floor: Dungeon.build_floor() runs again (resume_dungeon awaits it)
		if st.has("extra") and d.has_method("load_extra"):
			d.load_extra(st.extra)
		if d.hud and "log_all" in d.hud and st.has("log"):
			d.hud.log_all = st.log.duplicate()
		d.set_meta("resume_fresh", true)
		return
	# floor
	var fs := FloorState.new()
	var fsd: Dictionary = st.get("fs", {})
	for k in fsd:
		if k in ["rng", "meta", "leader"]:
			continue
		if k in fs:
			fs.set(k, fsd[k])
	if fsd.has("rng"):
		fs.rng.seed = int(fsd.rng[0])
		fs.rng.state = int(fsd.rng[1])
	for k in fsd.get("meta", {}):
		fs.set_meta(k, fsd.meta[k])
	fs.mons = []
	for u in st.get("floor_mons", []):
		if by_uid.has(int(u)):
			fs.mons.append(by_uid[int(u)])
	fs.leader = by_uid.get(int(fsd.get("leader", -1)))
	if fs.leader == null:
		for m in d.team_mons:
			if m.is_leader:
				fs.leader = m
	fs.red_reset_cache()
	d.fs = fs
	if st.has("extra") and d.has_method("load_extra"):
		d.load_extra(st.extra)
	# visuals
	for c in d.mon_layer.get_children():
		c.queue_free()
	var ts_key := str(st.get("ts_key", "t14"))
	if not DB.tilesets.has(ts_key) and not DungeonGfx.is_arena(ts_key):
		ts_key = "t14"
	d.terrain_view.build({"w": fs.w, "h": fs.h, "terrain": fs.terrain}, ts_key)
	for m in fs.mons:
		d._add_sprite(m)
	IQSky.fs = fs
	Combat.sky_floor = fs
	d._snap_visuals()
	d._reveal()
	d.obj_layer.queue_redraw()
	Audio.play_music(d._music_for())
	if d.hud:
		d.hud.clear_msgs()
		if "log_all" in d.hud and st.has("log"):
			d.hud.log_all = st.log.duplicate()
	d._update_hud()
	if "shop" in d:                          # the Kecleon Shop's state (shop rect is a FloorState meta)
		d.shop = KecleonShop.new(d)
		d.shop.prev_in_shop = d.shop.is_shop_tile(fs.leader.pos) if fs.leader else false

## What Dungeon.start() builds before the first floor (layers, camera, textures). Uses the dungeon's own
## _setup_nodes() if a newer dungeon.gd has one.
static func _setup_nodes(d) -> void:
	if d.has_method("_setup_nodes"):
		if d.terrain_view == null:
			d._setup_nodes()
		return
	d._icon_tex = DB.tex("res://assets/ui/items.png")
	d._stairs_tex = DB.tex("res://assets/ui/stairs.png")
	Combat.load_data()
	if d.terrain_view != null:
		return
	d.terrain_view = TerrainView.new(); d.add_child(d.terrain_view)
	d.obj_layer = Node2D.new(); d.obj_layer.z_index = 1; d.obj_layer.draw.connect(d._draw_objects); d.add_child(d.obj_layer)
	d.mon_layer = Node2D.new(); d.mon_layer.y_sort_enabled = true; d.mon_layer.z_index = 2; d.add_child(d.mon_layer)
	d.fx_layer = Node2D.new(); d.fx_layer.z_index = 5; d.add_child(d.fx_layer)
	d.cam = Camera2D.new()
	d.cam.zoom = Vector2.ONE * float(Game.settings.get("zoom", 1.25)) / UITheme.ui_scale()
	d.cam.position_smoothing_enabled = false
	d.add_child(d.cam)
	d.cam.make_current()

# ------------------------------------------------------------------ helpers
static func _read_raw() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}

static func _floor_label(d) -> String:
	var up: bool = d.ddata.get("up", false)
	return ("%dF" % (d.floor_i + 1)) if up else ("B%dF" % (d.floor_i + 1))

## Same tileset choice as Dungeon.build_floor().
static func _ts_key(d) -> String:
	var floors: Array = d.ddata.get("floors", [])
	if d.floor_i >= floors.size():
		return "t14"
	var raw := PackedByteArray()
	for b in floors[d.floor_i].props:
		raw.append(int(b))
	var props: Dictionary = DungeonGen.props_from_bytes(raw)
	var t := int(props.get("tileset", 14))
	var ts_key := "r%02d" % t
	if DB.tilesets.has("t%02d" % t) and DB.tilesets["t%02d" % t].has("hd"):
		ts_key = "t%02d" % t
	if not DB.tilesets.has(ts_key):
		ts_key = "t14"
	if t >= 64 and not floors[d.floor_i].has("eos_tileset") and DungeonGfx.arena_key(t) != "":
		ts_key = DungeonGfx.arena_key(t)      # Red's boss arena graphics (b64..b75)
	return ts_key
