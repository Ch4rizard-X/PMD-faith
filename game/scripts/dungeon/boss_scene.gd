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

# ------------------------------------------------------------------ running steps
func run_setup() -> void:
	await _run(scene.get("setup", []), false)

func run_prefight() -> void:
	await _run(scene.get("prefight", []), true)

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
			if _cond(st[1]):
				await _run(st[2], visual)
			else:
				await _run(st[3], visual)
		"say":
			await say(str(st[1]))
		"wait":
			if visual:
				await _wait(mini(int(st[1]), 90))
		"bgm":
			var id := int(st[1]) if str(st[1]).is_valid_int() else -1
			if id == 999 or id < 0:
				Audio.stop_music()
			else:
				Audio.play_music("%03d" % id)
		"bgm_stop":
			Audio.stop_music()
		"sfx":
			Audio.sfx("%03d" % int(st[1]))
		"flash":
			if visual:
				await _flash()
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
			var d2 = DIRS.get(str(st[1]), int(st[1]) if str(st[1]).is_valid_int() else -1)
			if int(d2) >= 0 and int(d2) < 8:
				for m4 in dg.fs.team():
					m4.facing = int(d2)
					if m4.visual:
						m4.visual.queue_redraw()
		"hide":
			var m5 := _mon_of(st[1])
			if m5:
				dg.cs_hide(m5, true)
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
					m8.max_hp = int(st[2])
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
