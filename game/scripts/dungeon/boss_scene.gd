class_name BossScene
extends RefCounted
## Red's fixed-room cutscenes (dungeon_cutscene*.c): picks the cutscene for the floor's fixed room
## (sFixedRoomCutsceneLookup + cutscene flags), runs its setup / pre-fight dialogue, and the boss-faint
## handler that ends the floor ("unk2 = DUNGEON_UNK2_1": the floor is over, like taking the stairs).
## Scripts are step trees generated from the decomp by gen_fixed_rooms.py (data/fixed_rooms.json).

static var data: Dictionary = {}

## Non-combatant story Pokémon (Diglett in the Skarmory arena, rescue clients): neutral, never attacked.
const NEUTRAL := ["BEHAVIOR_DIGLETT", "BEHAVIOR_RESCUE_TARGET", "BEHAVIOR_SMEARGLE", "BEHAVIOR_CELEBI", "BEHAVIOR_ALLY"]
const EMOTIONS := ["Normal", "Happy", "Pain", "Angry", "Worried", "Sad", "Crying", "Shouting", "Teary-Eyed",
	"Determined", "Joyous", "Inspired", "Surprised", "Dizzy", "Special0", "Special1"]
const DIRS := {"DIRECTION_SOUTH": 0, "DIRECTION_SOUTHEAST": 1, "DIRECTION_EAST": 2, "DIRECTION_NORTHEAST": 3,
	"DIRECTION_NORTH": 4, "DIRECTION_NORTHWEST": 5, "DIRECTION_WEST": 6, "DIRECTION_SOUTHWEST": 7}
const NAME_COL := "#7fe0ff"

var dg                                  # Dungeon
var room := 0
var cutscene := ""
var scene: Dictionary = {}
var names := {}                         # {POKEMON_n} buffers set by the scripts
var floor_over := false                 # the floor ends as soon as the dungeon can take it
var ended := false
var end_dungeon := false                 # gDungeon->unk4 = 1 (Smeargle / Medicham rescues): leave the dungeon, not next floor
var _faint_behavior := ""
var _joined := false

static func load_data() -> Dictionary:
	if data.is_empty():
		var f := FileAccess.open("res://data/fixed_rooms.json", FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			data = v if v is Dictionary else {}
	return data

static func room_data(n: int) -> Dictionary:
	var rooms: Array = load_data().get("rooms", [])
	if n <= 0 or n >= rooms.size():
		return {}
	return rooms[n]

## Generator input for DungeonGen (props["_fixed"]).
static func gen_input(n: int) -> Dictionary:
	var r := room_data(n)
	if r.is_empty():
		return {}
	return {"room": r, "entities": load_data().get("entities", [])}

static func is_floorwide(n: int) -> bool:
	return n > 0 and n < 51

## Level of a fixed-room Pokémon: Red's GetSpawnedMonsterLevel (the floor's spawn list, including the
## 0%-chance boss entries), else 1.
static func level_for(dkey: String, floor_i: int, sp: String) -> int:
	var lv: Dictionary = load_data().get("levels", {}).get(dkey, {}).get(str(floor_i), {})
	return int(lv.get(sp, 1))

# ------------------------------------------------------------------ flags (exclusive_pokemon.c)
static func get_flag(name: String) -> bool:
	var f = Game.story_get("cutscene_flags", {})
	return f is Dictionary and bool(f.get(name, false))

static func set_flag(name: String, on := true) -> void:
	if name == "" or name == "NUM_CUTSCENE_FLAGS":
		return
	var f = Game.story_get("cutscene_flags", {})
	if not f is Dictionary:
		f = {}
	if on:
		f[name] = true
	else:
		f.erase(name)
	Game.story_set("cutscene_flags", f)

# ------------------------------------------------------------------ selection (sub_80847D4 / sub_8084854)
static func make(dungeon, fixed_no: int) -> BossScene:
	var lookup: Array = load_data().get("cutscenes", {}).get("lookup", [])
	var n := fixed_no
	if n >= 28 and n <= 50:                # every Dojo maze boss uses the first maze-boss cutscene
		n = 27
	for e in lookup:
		if int(e.room) != n:
			continue
		var b := BossScene.new()
		b.dg = dungeon
		b.room = fixed_no
		if get_flag(str(e.f3)):
			b.cutscene = str(e.c3)
		elif get_flag(str(e.f2)):
			b.cutscene = str(e.c2)
		else:
			b.cutscene = str(e.c1)
			set_flag(str(e.f2))
		b.scene = load_data().get("cutscenes", {}).get("scenes", {}).get(b.cutscene, {})
		return b
	return null

# ------------------------------------------------------------------ entity lookup
func _mon_of(who) -> Mon:
	var w := str(who)
	if w == "leader" or w.contains("Leader"):
		return dg.fs.leader
	if w == "partner" or w.contains("Partner"):
		return _partner()
	for m in dg.fs.mons:
		if str(m.get_meta("behavior", "")) == w:
			return m
	return null

## sub_8085B4C / sub_8085B80: scripted walks. Each path is rows of {direction, pixels per frame, frames, 0};
## the row with 0 frames ends it: face its direction and stand on tile (row[5], row[6]). All walkers move at once.
func _march(list: Array, visual: bool) -> void:
	var walkers: Array = []
	for e in list:
		var m := _mon_of(e[0])
		if m == null:
			continue
		var rows: Array = e[1]
		walkers.append({"m": m, "rows": rows, "i": 0, "left": int(rows[2]) if rows.size() > 2 else 0, "off": Vector2.ZERO})
	if walkers.is_empty():
		return
	var animate: bool = visual and not Dialog.auto and not (dg.autoplay and dg.auto_answer)
	var busy := true
	while busy:
		busy = false
		for w in walkers:
			if w.get("done", false):
				continue
			var rows: Array = w.rows
			var i: int = w.i
			if int(w.left) <= 0:
				i += 4
				w.i = i
				if i + 2 >= rows.size() or int(rows[i + 2]) == 0:
					w.done = true
					continue
				w.left = int(rows[i + 2])
			busy = true
			var d := int(rows[i]) & 7
			var step := Vector2(DB.DIRS[d]) * float(rows[i + 1])
			w.off += step
			w.left = int(w.left) - 1
			var m: Mon = w.m
			m.facing = d
			if animate and m.visual and is_instance_valid(m.visual):
				m.visual.position = dg._px(m.pos) + w.off
				if m.visual.anim != "Walk":
					m.visual.play("Walk")
		if busy and animate:
			await dg.get_tree().process_frame
	for w in walkers:
		var m: Mon = w.m
		var rows: Array = w.rows
		var i: int = w.i
		var tgt := m.pos
		if i + 6 < rows.size():
			tgt = Vector2i(int(rows[i + 5]), int(rows[i + 6]))
			m.facing = int(rows[i]) & 7
		var occ: Mon = dg.fs.mon_at(tgt)
		if occ != null and occ != m:
			var free: Vector2i = dg.fs.free_tile_near(tgt, m, 3)
			if free.x >= 0:
				tgt = free
		m.pos = tgt
		if m.visual and is_instance_valid(m.visual):
			m.visual.position = dg._px(m.pos)
			m.visual.play("Idle")
			m.visual.queue_redraw()

func _partner() -> Mon:
	for m in dg.fs.mons:
		if m.is_team() and not m.is_leader and m.get_meta("story", false):
			return m
	for m in dg.fs.mons:
		if m.is_team() and not m.is_leader:
			return m
	return null

func _species_of(who: String) -> String:
	match who:
		"leader":
			return dg.fs.leader.sp if dg.fs.leader else ""
		"partner":
			var p := _partner()
			return p.sp if p else ""
	return who

# ------------------------------------------------------------------ conditions
func _cond(c: Array) -> bool:
	match str(c[0]):
		"not":
			return not _cond(c[1])
		"and":
			for x in c.slice(1):
				if not _cond(x):
					return false
			return true
		"or":
			for x in c.slice(1):
				if _cond(x):
					return true
			return false
		"recruited":
			return _recruited(str(c[1]))
		"recruited_or_story":
			# sub_8086AE4: before the team can change leaders (story), the legend counts as done
			if not _can_change_leader():
				return true
			return _recruited(str(c[1]))
		"flag":
			return get_flag(str(c[1]))
		"item":
			return _has_item(str(c[1]))
		"cutscene":
			var eq := cutscene == str(c[2])
			return eq if str(c[1]) == "==" else not eq
		"behavior":
			var eq2 := _faint_behavior == str(c[2])
			return eq2 if str(c[1]) == "==" else not eq2
		"joined":
			return _joined
		"others_alive":
			return _hostile_bosses_left() > 0
	return false

func _can_change_leader() -> bool:
	return GVars.buf.size() > 0 and GVars.quest(GVars.QUEST_CAN_CHANGE_LEADER)

func _recruited(mon_const: String) -> bool:
	var sp := str(load_data().get("monsters", {}).get(mon_const, ""))
	if sp == "":
		return false
	var have := false
	var shiny := false
	for e in Game.team + Game.friends:
		if str(e.get("sp", "")).substr(0, 4) == sp:
			have = true
			shiny = shiny or bool(e.get("shiny", false))
	# after the story, a legendary keeps coming back until you have its shiny (shiny hunting)
	if have and not shiny and RedShops.postgame():
		return false
	return have

func _has_item(item_const: String) -> bool:
	var id := str(load_data().get("items", {}).get(item_const, ""))
	if id == "":
		return false
	for b in Game.bag:
		if str(b.get("id", "")) == id:
			return true
	for e in Game.team:
		if str(e.get("held", "")) == id:
			return true
	return false

func _hostile_bosses_left() -> int:
	var n := 0
	for m in dg.fs.mons:
		if m.hp > 0 and not m.is_team() and str(m.get_meta("behavior", "")) not in ["", "BEHAVIOR_FIXED_ENEMY"] \
				and str(m.get_meta("behavior", "")) not in NEUTRAL:
			n += 1
	return n


# ------------------------------------------------------------------ Red's screen colour effects and camera
## From the decomp's dungeon_cutscene*.c (written out here: the cutscene data only says "flash"). Each program is
## SetDungeonBGColorRGB loops ["l", from, to, step, [r, g, b]] (1 = the loop value, n = value / n, 0 = zero), one
## per frame, waits ["w", frames] and the restore ["r"] (sub_8085EB0). FLASH_ORDER: which one each "flash" of a
## cutscene is, in order. sub_8086738 fades the dungeon to white (and stays), sub_8086764 fades it back.
## INTRO_WALK: the cutscenes whose dialogue starts with sub_8086448 (the team walks in from below while the
## camera scrolls 56 px).
const FLASH_PROGRAMS := {
	"ArticunoScreenFlash": [["l", 250, 150, -10, [2, 1, 1]], ["w", 4], ["l", 250, 200, -10, [0, 1, 1]], ["w", 4], ["l", 250, 0, -10, [2, 1, 1]], ["w", 4], ["r"]],
	"DeoxysScreenFlash": [["l", 250, 150, -10, [1, 0, 0]], ["w", 10], ["l", 250, 200, -10, [1, 1, 0]], ["w", 10], ["l", 250, 0, -10, [1, 0, 0]], ["w", 10], ["r"]],
	"EnteiScreenFlash": [["l", 250, 150, -10, [1, 2, 2]], ["w", 10], ["l", 250, 200, -10, [1, 0, 0]], ["w", 10], ["l", 250, 0, -10, [1, 2, 2]], ["w", 10], ["r"]],
	"GroudonScreenFlash": [["l", 250, 150, -10, [1, 2, 2]], ["w", 10], ["l", 250, 200, -10, [1, 2, 0]], ["w", 10], ["l", 250, 0, -10, [1, 2, 2]], ["w", 10], ["r"]],
	"GroudonScreenFlash2": [["l", 250, 150, -10, [1, 2, 2]], ["w", 10], ["l", 250, 200, -10, [1, 2, 0]], ["w", 10], ["l", 250, 0, -10, [1, 2, 2]], ["w", 10], ["r"]],
	"HoOhScreenFlash": [["l", 250, 150, -10, [1, 1, 1]], ["w", 10], ["l", 250, 200, -10, [1, 1, 1]], ["w", 10], ["l", 250, 0, -10, [1, 1, 1]], ["w", 10], ["r"]],
	"KyogreScreenFlash": [["l", 250, 150, -10, [0, 0, 1]], ["w", 10], ["l", 250, 200, -10, [0, 1, 1]], ["w", 10], ["l", 250, 0, -10, [0, 0, 1]], ["w", 10], ["r"]],
	"LatiosScreenFlash": [["l", 250, 150, -10, [1, 1, 1]], ["w", 10], ["l", 250, 0, -10, [1, 1, 1]], ["w", 10], ["r"]],
	"LugiaScreenFlash": [["l", 250, 150, -10, [0, 0, 1]], ["w", 10], ["l", 250, 200, -10, [0, 1, 1]], ["w", 10], ["l", 250, 0, -10, [0, 0, 1]], ["w", 10], ["r"]],
	"LugiaScreenFlash2": [["l", 0, 199, 100, [1, 1, 1]], ["l", 200, 0, -100, [1, 1, 1]], ["w", 4], ["l", 0, 199, 100, [1, 1, 1]], ["l", 200, 0, -100, [1, 1, 1]], ["w", 10], ["r"]],
	"MewtwoScreenFlash": [["l", 250, 150, -10, [1, 1, 1]], ["w", 10], ["l", 250, 200, -10, [1, 1, 0]], ["w", 10], ["l", 250, 0, -10, [1, 1, 1]], ["w", 10], ["r"]],
	"MoltresScreenFlash1": [],
	"MoltresScreenFlash2": [["l", 250, 20, -10, [1, 0, 0]], ["w", 10], ["l", 250, 0, -10, [1, 0, 0]], ["w", 10], ["r"]],
	"MoltresScreenFlash3": [["l", 250, 10, -10, [1, 1, 2]], ["w", 30], ["l", 250, 0, -10, [1, 1, 2]], ["w", 30], ["r"]],
	"RaikouScreenFlash": [["l", 250, 150, -10, [1, 1, 1]], ["w", 10], ["l", 250, 200, -10, [1, 1, 1]], ["w", 10], ["l", 250, 0, -10, [1, 1, 1]], ["w", 10], ["r"]],
	"RayquazaScreenFlash": [["l", 250, 150, -10, [2, 1, 2]], ["w", 10], ["l", 250, 200, -10, [2, 1, 0]], ["w", 10], ["l", 250, 0, -10, [2, 1, 2]], ["w", 10], ["r"]],
	"SuicuneScreenFlash": [["l", 250, 150, -10, [1, 1, 1]], ["w", 10], ["l", 250, 200, -10, [1, 1, 1]], ["w", 10], ["l", 250, 0, -10, [1, 1, 1]], ["w", 10], ["r"]],
	"ZapdosScreenFlash": [["l", 250, 200, -10, [1, 1, 2]], ["l", 250, 200, -10, [1, 1, 2]], ["l", 250, 0, -10, [1, 1, 4]], ["r"]],
	"sub_8086738": [["l", 0, 249, 10, [1, 1, 1]]],
	"sub_8086764": [["l", 250, 0, -5, [1, 1, 1]], ["r"]],
	"sub_8086794": [["l", 0, 199, 1, [0, 0, 0]]],
}
const FLASH_ORDER := {
	"CUTSCENE_FIERY_FIELD_ATTEMPT1": ["EnteiScreenFlash", "EnteiScreenFlash", "EnteiScreenFlash"],
	"CUTSCENE_FIERY_FIELD_ATTEMPT2": ["EnteiScreenFlash", "EnteiScreenFlash", "EnteiScreenFlash"],
	"CUTSCENE_FIERY_FIELD_POSTSTORY": ["EnteiScreenFlash", "EnteiScreenFlash", "EnteiScreenFlash"],
	"CUTSCENE_FROSTY_GROTTO_ATTEMPT1": ["ArticunoScreenFlash", "sub_8086738", "ArticunoScreenFlash", "ArticunoScreenFlash", "ArticunoScreenFlash"],
	"CUTSCENE_FROSTY_GROTTO_ATTEMPT2": ["ArticunoScreenFlash", "ArticunoScreenFlash"],
	"CUTSCENE_FROSTY_GROTTO_POSTSTORY": ["ArticunoScreenFlash", "sub_8086738", "ArticunoScreenFlash", "ArticunoScreenFlash", "ArticunoScreenFlash", "ArticunoScreenFlash"],
	"CUTSCENE_LIGHTNING_FIELD_ATTEMPT1": ["RaikouScreenFlash", "RaikouScreenFlash", "RaikouScreenFlash", "RaikouScreenFlash"],
	"CUTSCENE_LIGHTNING_FIELD_ATTEMPT2": ["RaikouScreenFlash", "RaikouScreenFlash", "RaikouScreenFlash"],
	"CUTSCENE_LIGHTNING_FIELD_POSTSTORY": ["RaikouScreenFlash", "RaikouScreenFlash"],
	"CUTSCENE_MAGMA_CAVERN_PIT_ATTEMPT1": ["GroudonScreenFlash", "sub_8086738", "sub_8086764", "GroudonScreenFlash2", "sub_8086738", "sub_8086764"],
	"CUTSCENE_MAGMA_CAVERN_PIT_ATTEMPT2": ["GroudonScreenFlash", "sub_8086738", "sub_8086764"],
	"CUTSCENE_MAGMA_CAVERN_PIT_POSTSTORY": ["GroudonScreenFlash", "GroudonScreenFlash"],
	"CUTSCENE_METEOR_CAVE": ["DeoxysScreenFlash", "DeoxysScreenFlash"],
	"CUTSCENE_MT_BLAZE_PEAK_ATTEMPT1": ["MoltresScreenFlash1", "MoltresScreenFlash1", "MoltresScreenFlash2", "MoltresScreenFlash3", "MoltresScreenFlash1", "MoltresScreenFlash2", "MoltresScreenFlash1", "MoltresScreenFlash2", "MoltresScreenFlash3", "MoltresScreenFlash2"],
	"CUTSCENE_MT_BLAZE_PEAK_ATTEMPT2": ["MoltresScreenFlash1", "MoltresScreenFlash3", "MoltresScreenFlash2"],
	"CUTSCENE_MT_BLAZE_PEAK_POSTSTORY": ["MoltresScreenFlash1", "MoltresScreenFlash1", "MoltresScreenFlash2", "MoltresScreenFlash3", "MoltresScreenFlash2"],
	"CUTSCENE_MT_FARAWAY": ["HoOhScreenFlash", "HoOhScreenFlash", "HoOhScreenFlash"],
	"CUTSCENE_MT_FARAWAY_POSTSTORY": ["HoOhScreenFlash", "HoOhScreenFlash", "HoOhScreenFlash"],
	"CUTSCENE_MT_THUNDER_PEAK_ATTEMPT1": ["ZapdosScreenFlash", "ZapdosScreenFlash", "ZapdosScreenFlash", "ZapdosScreenFlash"],
	"CUTSCENE_MT_THUNDER_PEAK_ATTEMPT2": ["ZapdosScreenFlash", "ZapdosScreenFlash"],
	"CUTSCENE_MT_THUNDER_PEAK_POSTSTORY": ["ZapdosScreenFlash", "ZapdosScreenFlash", "ZapdosScreenFlash", "ZapdosScreenFlash"],
	"CUTSCENE_NORTHERN_RANGE_ATTEMPT1": ["LatiosScreenFlash", "LatiosScreenFlash"],
	"CUTSCENE_NORTHERN_RANGE_ATTEMPT2": ["LatiosScreenFlash", "LatiosScreenFlash"],
	"CUTSCENE_NORTHWIND_FIELD_ATTEMPT1": ["SuicuneScreenFlash", "SuicuneScreenFlash"],
	"CUTSCENE_NORTHWIND_FIELD_ATTEMPT2": ["SuicuneScreenFlash", "SuicuneScreenFlash"],
	"CUTSCENE_NORTHWIND_FIELD_POSTSTORY": ["SuicuneScreenFlash", "SuicuneScreenFlash"],
	"CUTSCENE_SILVER_TRENCH": ["LugiaScreenFlash", "LugiaScreenFlash", "LugiaScreenFlash2", "SetDungeonBGColorRGB", "LugiaScreenFlash"],
	"CUTSCENE_SKY_TOWER_SUMMIT_ATTEMPT1": ["RayquazaScreenFlash", "RayquazaScreenFlash", "RayquazaScreenFlash", "RayquazaScreenFlash", "RayquazaScreenFlash"],
	"CUTSCENE_SKY_TOWER_SUMMIT_ATTEMPT2": ["RayquazaScreenFlash", "RayquazaScreenFlash", "RayquazaScreenFlash", "RayquazaScreenFlash"],
	"CUTSCENE_SKY_TOWER_SUMMIT_POSTSTORY": ["RayquazaScreenFlash", "RayquazaScreenFlash", "RayquazaScreenFlash"],
	"CUTSCENE_STORMY_SEA": ["KyogreScreenFlash", "KyogreScreenFlash", "KyogreScreenFlash"],
	"CUTSCENE_WESTERN_CAVE_ATTEMPT1": ["sub_8086794", "MewtwoScreenFlash", "MewtwoScreenFlash"],
	"CUTSCENE_WESTERN_CAVE_ATTEMPT2": ["sub_8086794", "MewtwoScreenFlash", "MewtwoScreenFlash"],
	"CUTSCENE_WESTERN_CAVE_POSTSTORY": ["sub_8086794", "MewtwoScreenFlash", "MewtwoScreenFlash"],
}
## Red's ground shaking in boss scenes (dungeon_cutscene_*.c sub_8086838 / sub_808680C / sub_808682C, dropped by the
## scene data): each entry is one shake, started at the scene's n-th "gUnknown_202F3D0.unk3" step (where the
## data kept only its sound) and stopped after `off` = [dialogue it follows ("" = the shake's start), waits after].
## long: Groudon's 80-frame rumbles with their sound; jitter: every Pokémon trembles too; sfx: sound stopped at the end.
const QUAKES := {
	"CUTSCENE_MAGMA_CAVERN_MID": [{"long": false, "jitter": true, "off": ["MagmaCavernMidDialogue_3", 1], "sfx": 453}],
	"CUTSCENE_MAGMA_CAVERN_MID_POSTSTORY": [{"long": false, "jitter": true, "off": ["MagmaCavernMidDialogue_3", 1], "sfx": 453}],
	"CUTSCENE_MAGMA_CAVERN_PIT_ATTEMPT1": [{"long": true, "off": ["", 1]}, {"long": true, "off": ["GroudonPreFightDialogue_7", 1]},
		{"long": true, "off": ["GroudonPreFightDialogue_13", 2]}],
	"CUTSCENE_MAGMA_CAVERN_PIT_ATTEMPT2": [{"long": true, "off": ["gGroudonReFightDialogue_3", 1]}],
	"CUTSCENE_MT_FARAWAY": [{"long": false, "jitter": true, "off": ["", 1], "sfx": 453}],
	"CUTSCENE_MT_FARAWAY_POSTSTORY": [{"long": false, "jitter": true, "off": ["", 1]}],
}
var _quake_i := 0
var _quake_off = null                  # {"say": name, "waits": n, "armed": bool, "sfx": id}

func _quake_start(visual: bool) -> void:
	var list: Array = QUAKES.get(cutscene, [])
	if _quake_i >= list.size():
		return
	var q: Dictionary = list[_quake_i]
	_quake_i += 1
	if visual and dg.has_method("quake_set"):
		dg.quake_set(true, bool(q.get("long", false)), bool(q.get("long", false)))
		dg.quake_jitter = bool(q.get("jitter", false))
	var off: Array = q.get("off", ["", 1])
	_quake_off = {"say": str(off[0]), "waits": int(off[1]), "armed": str(off[0]) == "", "sfx": int(q.get("sfx", -1))}

func _quake_stop() -> void:
	if _quake_off != null and int(_quake_off.sfx) > 0 and Audio.has_method("stop_sfx"):
		Audio.call("stop_sfx", "%03d" % int(_quake_off.sfx))
	_quake_off = null
	if dg.has_method("quake_set"):
		dg.quake_set(false)
		dg.quake_jitter = false

const INTRO_WALK := ["CUTSCENE_FROSTY_GROTTO_ATTEMPT1", "CUTSCENE_FROSTY_GROTTO_POSTSTORY", "CUTSCENE_HOWLING_FOREST", "CUTSCENE_HOWLING_FOREST_POSTSTORY", "CUTSCENE_JIRACHI", "CUTSCENE_JIRACHI_POSTSTORY", "CUTSCENE_MAGMA_CAVERN_MID", "CUTSCENE_MAGMA_CAVERN_MID_POSTSTORY", "CUTSCENE_MAGMA_CAVERN_PIT_ATTEMPT1", "CUTSCENE_MAGMA_CAVERN_PIT_POSTSTORY", "CUTSCENE_METEOR_CAVE", "CUTSCENE_MT_FREEZE_PEAK_POSTSTORY", "CUTSCENE_MT_STEEL_ATTEMPT1", "CUTSCENE_MT_STEEL_ATTEMPT2", "CUTSCENE_MT_THUNDER_PEAK_ATTEMPT1", "CUTSCENE_MT_THUNDER_PEAK_ATTEMPT2", "CUTSCENE_MT_THUNDER_PEAK_POSTSTORY", "CUTSCENE_NORTHERN_RANGE_ATTEMPT1", "CUTSCENE_NORTHERN_RANGE_ATTEMPT2", "CUTSCENE_NORTHERN_RANGE_POSTSTORY", "CUTSCENE_NORTHWIND_FIELD_ATTEMPT1", "CUTSCENE_SILVER_TRENCH", "CUTSCENE_SINISTER_WOODS_ATTEMPT1", "CUTSCENE_SINISTER_WOODS_ATTEMPT2", "CUTSCENE_SINISTER_WOODS_POSTSTORY", "CUTSCENE_SKY_TOWER_SUMMIT_ATTEMPT1", "CUTSCENE_SKY_TOWER_SUMMIT_ATTEMPT2", "CUTSCENE_SKY_TOWER_SUMMIT_POSTSTORY", "CUTSCENE_UPROAR_FOREST_ATTEMPT1", "CUTSCENE_UPROAR_FOREST_ATTEMPT2", "CUTSCENE_UPROAR_FOREST_POSTSTORY", "CUTSCENE_WESTERN_CAVE_ATTEMPT1", "CUTSCENE_WESTERN_CAVE_ATTEMPT2", "CUTSCENE_WESTERN_CAVE_POSTSTORY"]

# ------------------------------------------------------------------ running steps
func run_setup() -> void:
	await _run(scene.get("setup", []), false)

func run_prefight() -> void:
	if cutscene in INTRO_WALK:
		await _intro_walk()
	await _run(scene.get("prefight", []), true)
	if _quake_off != null or (dg.get("quake") is Dictionary and dg.quake.on):
		_quake_stop()
	if not floor_over:                       # (a scene that ends the floor keeps its view until the next floor)
		await _release_camera()
	_set_bg(0, 0, 0)

## HandleBossFaint_Async: a Pokémon with a story behaviour fainted (or was recruited: joined = true).
func on_faint(m: Mon, joined := false) -> void:
	var b := str(m.get_meta("behavior", ""))
	if b == "" or b == "BEHAVIOR_FIXED_ENEMY" or ended:
		return
	_faint_behavior = b
	_joined = joined
	await _run(scene.get("faint", []), true)
	_faint_behavior = ""
	# Safety net for scenes whose win condition lives in code we don't run (Regis, Jirachi wishes ...):
	# a floor-wide arena without stairs ends once every hostile story Pokémon is down.
	if not floor_over and is_floorwide(room) and _hostile_bosses_left() == 0 and dg.fs.stairs.x < 0:
		floor_over = true
		if Dialog.auto:
			print("  BOSS floor over (fallback) ", b)

func _run(steps: Array, visual: bool) -> void:
	for st in steps:
		if dg.result_sent:
			return
		await _step(st, visual)

func _wait(frames: int) -> void:
	if Dialog.auto or (dg.autoplay and dg.auto_answer):
		return
	if frames > 0:
		await dg.get_tree().create_timer(frames / 60.0).timeout

func _step(st: Array, visual: bool) -> void:
	match str(st[0]):
		"if":
			if st[1] is Array and (st[1] as Array).size() > 1 and str(st[1][1]).begins_with("gUnknown_202F3D0.unk3"):
				_quake_start(visual)                 # sub_808680C: the shake starts here (its sound: _quake_start)
				return
			if _cond(st[1]):
				await _run(st[2], visual)
			else:
				await _run(st[3], visual)
		"say":
			await _before_say(str(st[1]))
			await say(str(st[1]))
			await _after_say(str(st[1]), visual)
			if _quake_off != null and not _quake_off.armed and str(_quake_off.say) == str(st[1]):
				_quake_off.armed = true
		"wait":
			if visual:
				await _wait(mini(int(st[1]), 90) if _quake_off == null else int(st[1]))
			if _quake_off != null and _quake_off.armed:
				_quake_off.waits -= 1
				if int(_quake_off.waits) <= 0:
					_quake_stop()
		"bgm":
			var id := int(st[1]) if (st[1] is int or st[1] is float or str(st[1]).is_valid_int()) else -1   # JSON numbers arrive as floats
			if id == 999 or id < 0:
				Audio.stop_music()
			else:
				Audio.play_music("%03d" % id)
		"bgm_stop":
			Audio.stop_music()
		"sfx":
			Audio.sfx("%03d" % int(st[1]))
		"flash":
			var order: Array = FLASH_ORDER.get(cutscene, [])
			var fname: String = str(order[_flash_i]) if _flash_i < order.size() else ""
			_flash_i += 1
			if FLASH_PROGRAMS.has(fname) and not (FLASH_PROGRAMS[fname] as Array).is_empty():
				await _run_flash(FLASH_PROGRAMS[fname], visual)
			elif visual:
				await _flash()
		"camera_at":
			var tp = _cam_expr(st[1], st[2] if st.size() > 2 else "0")
			if tp != null:
				dg.cs_cam_lock = true
				dg.cs_cam_pos = tp
				dg.cam.position = tp
		"camera":
			var target = _cam_target(str(st[1]))
			if target != null:
				await _move_camera(target, 32 if str(st[1]) == "&pos" else 16, visual)
			if str(st[1]).contains("leaderEntity"):
				dg.cs_cam_lock = false
		"emote":
			var m := _mon_of(st[1])
			if m and m.visual:
				dg._popup(m.visual.position, "!", Color(1, 0.9, 0.3), true)
				Audio.sfx("%03d" % 450)
				await _wait(30)
		"look_around":
			var m2 := _mon_of(st[1])
			if m2 and visual:
				var d0 := m2.facing
				for d in [2, 6, d0]:
					m2.facing = (d0 + d) % 8 if d != d0 else d0
					if m2.visual:
						m2.visual.queue_redraw()
					await _wait(12)
		"face":
			var m3 := _mon_of(st[1])
			if m3 and DIRS.has(str(st[2])):
				m3.facing = int(DIRS[str(st[2])])
				if m3.visual:
					m3.visual.queue_redraw()
		"team_face":
			var d2 = DIRS.get(str(st[1]), int(st[1]) if (st[1] is int or st[1] is float or str(st[1]).is_valid_int()) else -1)
			if int(d2) >= 0 and int(d2) < 8:
				for m4 in dg.fs.team():
					m4.facing = int(d2)
					if m4.visual:
						m4.visual.queue_redraw()
		"march":
			await _march(st[1], visual)
		"hide":
			var m5 := _mon_of(st[1])
			if m5:
				dg.cs_hide(m5, true)
				if cutscene.begins_with("CUTSCENE_MAGMA_CAVERN_MID") and m5.visual and m5.visual.has_method("play"):
					m5.visual.play("Laying" if m5.visual.man and m5.visual.man.anims.has("Laying") else "Sleep")   # pose 0xE: lying hurt
		"show":
			var m6 := _mon_of(st[1])
			if m6:
				dg.cs_hide(m6, false)
				if visual:
					await _wait(30)
		"remove":
			var m7 := _mon_of(st[1])
			if m7 and not m7.is_team():
				dg.cs_remove(m7)
		"boss_hp":
			var m8 := _mon_of(st[1])
			if m8:
				dg.cs_hide(m8, false)
				m8.set_meta("boss", true)
				if int(st[2]) > 0:
					m8.max_hp = Difficulty.boss_hp(int(st[2]), int(m8.get_meta("hard_base_lv", m8.level)), m8.level)
					m8.hp = m8.max_hp
					m8.set_meta("boss_hp", m8.max_hp)
				if Dialog.auto:
					print("  BOSS ", m8.name, " Lv", m8.level, " HP ", m8.hp)
			if st.size() > 3 and int(st[3]) > 0:
				Audio.play_music("%03d" % int(st[3]))
		"dungeon_end":
			floor_over = true
			end_dungeon = true
			if Dialog.auto:
				print("  BOSS dungeon over (", cutscene, ")")
		"floor_over":
			floor_over = true
			if Dialog.auto:
				print("  BOSS floor over (", cutscene, " faint=", _faint_behavior, ")")
		"set_flag":
			set_flag(str(st[1]))
		"unset_flag":
			set_flag(str(st[1]), false)
		"name":
			names[int(st[1])] = str(load_data().get("monsters", {}).get(str(st[2]), ""))
		_:
			pass

var _flash_i := 0
var _bg_layer: CanvasLayer
var _bg: ColorRect
var _cam_pos = null                      # "&pos" of the current scene (ShiftCameraToPosition(&pos, ...))

## SetDungeonBGColorRGB(r, g, b): Red brightens the dungeon's palettes toward the colour; an additive layer over the
## dungeon (under the text windows) does the same.
func _set_bg(r: int, g: int, b: int) -> void:
	if _bg == null:
		if r == 0 and g == 0 and b == 0:
			return
		_bg_layer = CanvasLayer.new()
		_bg_layer.layer = 3
		dg.add_child(_bg_layer)
		_bg = ColorRect.new()
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_bg.material = mat
		_bg_layer.add_child(_bg)
	_bg.color = Color(clampi(r, 0, 255) / 255.0, clampi(g, 0, 255) / 255.0, clampi(b, 0, 255) / 255.0, 1.0)
	_bg.visible = r > 0 or g > 0 or b > 0

func _frame(visual: bool) -> void:
	if visual and not Dialog.auto and not (dg.autoplay and dg.auto_answer):
		await dg.get_tree().process_frame

func _run_flash(prog: Array, visual: bool) -> void:
	for seg in prog:
		match str(seg[0]):
			"l":
				var v := int(seg[1])
				var to := int(seg[2])
				var step := int(seg[3])
				var ds: Array = seg[4]
				while (step > 0 and v <= to) or (step < 0 and v >= to):
					var c: Array = []
					for dv in ds:
						c.append(0 if int(dv) == 0 else (v if int(dv) == 1 else v / int(dv)))
					_set_bg(c[0], c[1], c[2])
					await _frame(visual)
					v += step
			"w":
				if visual:
					await _wait(int(seg[1]))
			"r":
				_set_bg(0, 0, 0)

## sub_8085860(x, y): the camera on a tile, from the scene's "leaderEntity->pos.x + n" expressions.
func _cam_expr(ex, ey):
	var x = _tile_expr(str(ex), "x")
	var y = _tile_expr(str(ey), "y")
	if x == null or y == null:
		return null
	return dg._px(Vector2i(int(x), int(y)))

func _tile_expr(e: String, axis: String):
	var re := RegEx.new()
	re.compile("^\\s*(\\w+)->pos\\.([xy])\\s*(?:([+-])\\s*(-?\\s*\\d+))?\\s*$")
	var m := re.search(e)
	if m == null:
		return int(e) if e.strip_edges().is_valid_int() else null
	var who := _mon_of("leader" if m.get_string(1).begins_with("leader") else ("partner" if m.get_string(1).begins_with("partner") else m.get_string(1)))
	if who == null:
		return null
	var base := who.pos.x if m.get_string(2) == "x" else who.pos.y
	var off := 0
	if m.get_string(3) != "":
		off = int(m.get_string(4).replace(" ", ""))
		if m.get_string(3) == "-":
			off = -off
	return base + off

func _cam_target(arg: String):
	if arg == "&pos":
		return _cam_pos
	var re := RegEx.new()
	re.compile("&(\\w+)->pixelPos")
	var m := re.search(arg)
	if m == null:
		return null
	var n := m.get_string(1)
	var who := _mon_of("leader" if n.begins_with("leader") else ("partner" if n.begins_with("partner") else n))
	if who and who.visual:
		return who.visual.position
	return null

## ShiftCameraToPosition(pos, steps): a straight glide over that many frames.
func _move_camera(to: Vector2, steps: int, visual: bool) -> void:
	var from: Vector2 = dg.cam.position if dg.cs_cam_lock else dg.cam.position
	dg.cs_cam_lock = true
	for i in range(1, steps + 1):
		dg.cs_cam_pos = from.lerp(to, float(i) / steps)
		dg.cam.position = dg.cs_cam_pos
		await _frame(visual)
	dg.cs_cam_pos = to

func _release_camera() -> void:
	if not dg.cs_cam_lock:
		return
	if dg.fs.leader and dg.fs.leader.visual:
		await _move_camera(dg.fs.leader.visual.position, 16, true)
	dg.cs_cam_lock = false

## sub_8086448: the team stands 56 px further down, then walks up into place while the camera scrolls down 56 px.
func _intro_walk() -> void:
	var team: Array = dg.fs.team().filter(func(m): return m.visual != null and is_instance_valid(m.visual))
	if team.is_empty():
		return
	var animate: bool = not Dialog.auto and not (dg.autoplay and dg.auto_answer)
	for m in team:
		m.facing = 4
		if animate:
			m.visual.position = dg._px(m.pos) + Vector2(0, 56)
			m.visual.play("Walk")
	if not animate:
		return
	for i in 56:
		for m in team:
			m.visual.position.y -= 1.0
		if dg.cs_cam_lock:
			dg.cs_cam_pos.y += 1.0
			dg.cam.position = dg.cs_cam_pos
		await dg.get_tree().process_frame
	for m in team:
		m.visual.position = dg._px(m.pos)
		m.visual.play("Idle")

## Team walks (IncreaseEntityPixelPos each frame) that the scene data doesn't carry.
func _team_walk(frames: int, step: Vector2, dir: int) -> void:
	var team: Array = dg.fs.team().filter(func(m): return m.visual != null and is_instance_valid(m.visual))
	for m in team:
		m.facing = dir
		m.visual.play("Walk")
	if Dialog.auto or (dg.autoplay and dg.auto_answer):
		return
	for i in frames:
		for m in team:
			m.visual.position += step
		await dg.get_tree().process_frame
	for m in team:
		m.visual.play("Idle")

## Scene parts written out from the decomp where the data has only the dialogue.
func _before_say(name: String) -> void:
	if cutscene == "CUTSCENE_MAGMA_CAVERN_MID" and name == "MagmaCavernMidDialogue_6":
		await _team_walk(48, Vector2(0, -2), 4)            # sub_80891F0: up to the fallen pair, 2 px a frame

func _after_say(name: String, visual: bool) -> void:
	if cutscene != "CUTSCENE_MAGMA_CAVERN_MID":
		return
	if name == "MagmaCavernMidDialogue_5":
		# the camera between the two (+8 px), as Red's ShiftCameraToPosition(&pos, 0x20) that follows
		var a := _mon_of("BEHAVIOR_GROUDON_1")
		var b := _mon_of("BEHAVIOR_ALAKAZAM_2")
		if a and b and a.visual and b.visual:
			_cam_pos = (a.visual.position + b.visual.position) / 2.0 + Vector2(0, 8)
	elif name == "MagmaCavernMidDialogue_14":
		await _team_walk(120, Vector2(0, -2), 4)           # sub_8089294: off up the passage before the next floor

func _flash() -> void:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.z_index = 40
	dg.ui_root.add_child(r)
	var tw: Tween = dg.create_tween()
	tw.tween_property(r, "color:a", 0.75, 0.08)
	tw.tween_property(r, "color:a", 0.0, 0.3)
	tw.tween_callback(r.queue_free)
	if not Dialog.auto:
		await tw.finished

# ------------------------------------------------------------------ dialogue (DisplayDungeonDialogue_Async)
const ALLOW_SETS := {7: ["0007", "0158"], 1: ["0001", "0155", "0258", "0025", "0004", "0252"], 280: ["0255", "0152"]}

func say(name: String) -> void:
	var lst: Array = load_data().get("dialogue", {}).get(name, [])
	if lst.is_empty():
		return
	var pick: Dictionary = lst[lst.size() - 1]
	for d in lst:
		var al := int(d.allow)
		if al == 0:
			pick = d
			break
		var who := _species_of(str(d.speaker)).substr(0, 4)
		if ALLOW_SETS.get(al, []).has(who):
			pick = d
			break
	var sp := _species_of(str(pick.speaker))
	var speaker_name := ""
	if str(pick.speaker) == "leader" and dg.fs.leader:
		speaker_name = dg.fs.leader.name
	elif str(pick.speaker) == "partner" and _partner():
		speaker_name = _partner().name
	elif sp != "" and DB.species.has(sp):
		speaker_name = str(DB.species[sp].name)
	var t := _format(str(pick.text))
	var pages := t.split("\u0002")
	var emo := int(pick.emo)
	var portrait := sp if (emo != 0x80 and int(pick.type) != 4) else ""
	var emotion: String = EMOTIONS[clampi(emo, 0, EMOTIONS.size() - 1)]
	var prefix := ""
	if speaker_name != "" and int(pick.type) != 2 and int(pick.type) != 3:
		prefix = "[color=%s]%s[/color]:" % [Missions.HL, speaker_name]
	for i in pages.size():
		var pg := pages[i].strip_edges()
		if pg == "":
			continue
		await Dialog.say(dg.ui_root, prefix + " " + pg if prefix != "" else pg, portrait, emotion)

func _format(s: String) -> String:
	var t := s.replace("[", "(").replace("]", ")")
	var leader_nm: String = dg.fs.leader.name if dg.fs.leader else "??"
	var p := _partner()
	var partner_nm: String = p.name if p else "??"
	var buf := {0: leader_nm, 1: partner_nm}
	for k in names:
		var spk := str(names[k])
		buf[k] = str(DB.species.get(spk, {}).get("name", spk))
	var re := RegEx.new()
	re.compile("\\{([A-Z_0-9]+)(?: ([A-Z_0-9]+))?\\}")
	var out := ""
	var last := 0
	for m in re.search_all(t):
		out += t.substr(last, m.get_start() - last)
		last = m.get_end()
		var tag := m.get_string(1)
		var arg := m.get_string(2)
		if tag.begins_with("POKEMON_"):
			var n := int(tag.substr(8))
			out += "[color=%s]%s[/color]" % [NAME_COL, buf.get(n, "??")]
		elif tag == "COLOR":
			out += "[color=%s]" % ({"YELLOW": "#ffdc4a", "YELLOW_D": "#ffdc4a", "CYAN": "#7fe0ff", "GREEN": "#7fff7f",
				"RED": "#ff7070", "LIGHT_BLUE": "#9fd0ff"}.get(arg, "#ffffff"))
		elif tag == "RESET":
			out += "[/color]"
		elif tag == "EXTRA_MSG" or tag == "WAIT_PRESS":
			out += "\u0002"
		elif tag == "TEAM_NAME":
			out += "[color=#ffdc4a]%s[/color]" % str(Game.team_name)
		else:
			pass
	out += t.substr(last)
	return out
