class_name Dungeon
extends Node2D
## Runs one dungeon expedition: floor generation, the turn loop, attacks, items, stairs.

static var test_invincible := false   # --storytest: the team can't faint
static var test_want := ""            # --storytest: an item the story needs (autoplay fetches it)
signal finished(result: String)        # "cleared" | "defeated" | "quit"

const T := 24
const WALK_TIME := 0.13
const RUN_TIME := 0.045
const LINE_RANGE := 10

var dkey := ""
var ddata: Dictionary = {}
var dname := ""
var floor_i := 0
var fs: FloorState
var hud: Hud
var ui_root: Control

var terrain_view: TerrainView
var obj_layer: Node2D
var mon_layer: Node2D
var fx_layer: Node2D
var cam: Camera2D
var dark: ColorRect

var team_mons: Array = []
var mem := {}                          # AI memory per uid
var belly := 100.0
var belly_max := 100
var busy := false
var menu_open := false
var spawn_timer := 0
var wind_state := {}
var belly_state := {"belly": 100.0}
var rng := RandomNumberGenerator.new()
var _icon_tex: Texture2D
var _stairs_tex: Texture2D
var _pending_walks: Array = []        # [Mon, from_px, to_px]
var _running := false
var _hold_t := 0.0
var _map_on := false
var autoplay := false
var auto_answer := false          # automated tests: menus pick their first option
var _auto_target := Vector2i(-1, -1)
var result_sent := false
var recruited_names: Array = []
var partner_ai: PartnerAI = null   # Game Options "Partner AI: Smarter"
var shop: KecleonShop = null       # the floor's Kecleon Shop (dungeon/kecleon_shop.gd)
var shop_base := 0                 # wares' value when the floor began / since the last payment (Red unk50)
var shop_stole := false            # thief on this floor (Red stoleFromKecleon)
var _entry_state: Dictionary = {}  # DungeonSave.entry_state() at this floor's start (boss floors save this)

## Fixed rooms (story bosses, legendaries, Explorers of Sky boss arenas) can't be resumed mid-floor: their
## cutscene and boss state live in the scene, so saves there go back to the floor's start.
func restart_floor_on_load() -> bool:
	return fixed_no != 0 or not eos_arena.is_empty() or boss != null
var dx_turns := 0                 # turns taken in this dungeon (DX recruiting: the farewell payment)
const QOL := preload("res://scripts/dungeon/dungeon_qol.gd")
var boss: BossScene = null             # fixed-room cutscene of this floor (Red dungeon_cutscene.c)
var start_floor := 0                   # story: Red splits a dungeon into script dungeons (the boss part starts here)
var stop_floor := -1                   # story: the run ends on reaching this floor (the boss part follows)
var fixed_no := 0                      # FloorProperties.fixedRoomNumber of this floor
var qol                                # DungeonQoL: run mode, tap-to-walk, previews, maps, low-HP warning

# ================================================================= setup
func start(key: String, team_entries: Array) -> void:
	rng.randomize()
	# test hook: --bosstest=<dungeon_key>:<floor index>[:<team level>] starts on a boss floor (with --autotest)
	var test_floor := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bosstest="):
			var parts := a.substr(11).split(":")
			key = parts[0]
			test_floor = int(parts[1]) if parts.size() > 1 else 0
			Dialog.auto = true
			if parts.size() > 2:
				for e in team_entries:
					e.level = int(parts[2])
	dkey = key
	ddata = DB.dungeons.get("dungeons", {}).get(key, {})
	dname = key.capitalize()
	_icon_tex = DB.tex("res://assets/ui/items.png")
	_stairs_tex = DB.tex("res://assets/ui/stairs.png")
	if ClassDB.class_exists("Combat") or true:
		Combat.load_data()
	team_mons.clear()
	# "All items will be lost on entering" (max_items 0: Purity Forest, Zero Isle West/South, Destiny Tower).
	# Kinder than Red: the Toolbox and held items go to Kangaskhan Storage instead of vanishing.
	var stored := 0
	if int(ddata.get("max_items", 20)) == 0 and not ddata.get("maze", false):
		for b in Game.bag:
			if str(b.id) != "poke":
				Game.storage[b.id] = int(Game.storage.get(b.id, 0)) + int(b.get("n", 1))
				stored += 1
		Game.bag.clear()
		for e in team_entries:
			if str(e.get("held", "")) != "":
				Game.storage[e.held] = int(Game.storage.get(e.held, 0)) + 1
				e.held = ""
				stored += 1
	for i in team_entries.size():
		var m: Mon = Game.mon_from_entry(team_entries[i])
		if ddata.get("level_reset", false):
			# "The team will enter at Level 1": Lv1 stats for this dungeon only; moves and IQ are kept and the
			# levels gained inside are not kept (Game.store_mon skips level / Exp. for these)
			m.level = 1
			m.exp = 0
			DB.recalc(m)
			m.hp = m.max_hp
			m.set_meta("level_reset", true)
		m.is_leader = i == 0
		m.set_meta("story", i < 2)          # hero and partner: losing either ends the expedition (story rule)
		team_mons.append(m)
	terrain_view = TerrainView.new(); add_child(terrain_view)
	obj_layer = Node2D.new(); obj_layer.z_index = 1; obj_layer.draw.connect(_draw_objects); add_child(obj_layer)
	arrow_layer = Node2D.new(); arrow_layer.z_index = 4; arrow_layer.draw.connect(_draw_mode_arrows); add_child(arrow_layer)
	mon_layer = Node2D.new(); mon_layer.y_sort_enabled = true; mon_layer.z_index = 2; add_child(mon_layer)
	fx_layer = Node2D.new(); fx_layer.z_index = 5; add_child(fx_layer)
	cam = Camera2D.new()
	cam.zoom = Vector2.ONE * float(Game.settings.get("zoom", 1.25)) / UITheme.ui_scale()
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()
	_ensure_qol()
	floor_i = maxi(0, test_floor) if test_floor >= 0 else start_floor
	Missions.on_dungeon_start(self)
	belly = 100.0
	belly_state = {"belly": 100.0}
	await build_floor()
	AbilityFx.update_weather(self)
	EosItems.fs = fs
	for tm_ in fs.team():
		EosItems.floor_start(self, tm_)
	if stored > 0:
		_msg("The items were sent to Kangaskhan Storage.")

## The QoL module (also made lazily, for a dungeon rebuilt from a quicksave without start()).
func _ensure_qol() -> void:
	if qol == null:
		qol = QOL.new()
		qol.dg = self
		add_child(qol)

func _floor_label() -> String:
	var up: bool = ddata.get("up", false)
	return ("%dF" % (floor_i + 1)) if up else ("B%dF" % (floor_i + 1))

func build_floor() -> void:
	busy = true
	# the team as it arrives on this floor (before anything is generated): a Quicksave or autosave made on
	# a fixed / boss floor stores this instead, so loading rebuilds the floor and replays its cutscene
	_entry_state = DungeonSave.entry_state(self)
	for c in mon_layer.get_children():
		c.queue_free()
	var fdata: Dictionary = ddata.floors[floor_i]
	var raw := PackedByteArray()
	for b in fdata.props:
		raw.append(int(b))
	var props: Dictionary = DungeonGen.props_from_bytes(raw)
	boss = null
	fixed_no = int(props.get("fixedRoomNumber", 0))
	if fixed_no != 0:
		var fx := BossScene.gen_input(fixed_no)
		if not fx.is_empty():
			props["_fixed"] = fx
		else:
			fixed_no = 0
	if fdata.has("eos_secondary"):
		props["_sec_kind"] = str(fdata.eos_secondary)
	eos_arena = {}
	if int(fdata.get("eos_fixed", 0)) > 0:
		eos_arena = eos_fixed_data().get(str(int(fdata.eos_fixed)), {})
	var gen: Dictionary = DungeonGen.generate(props, rng.randi()) if eos_arena.is_empty() else _eos_arena_gen(eos_arena, str(fdata.get("eos_secondary", "water")))
	var arena_key := ""
	if int(props.get("tileset", 14)) >= 64 and not fdata.has("eos_tileset"):
		arena_key = DungeonGfx.arena_key(int(props.get("tileset", 14)))   # Red's arena graphics b64..b75
		props["tileset"] = _fallback_tileset()
	fs = FloorState.new()
	fs.rng.seed = rng.randi()
	fs.setup(gen)
	fs.floor_no = floor_i + 1
	fs.dungeon_key = dkey
	fs.visibility = int(props.get("visibilityRange", 0))
	fs.secondary = str(gen.get("secondary_kind", "water"))
	var ts_key := "r%02d" % int(props.get("tileset", 14))
	if DB.tilesets.has("t%02d" % int(props.get("tileset", 14))) and DB.tilesets["t%02d" % int(props.get("tileset", 14))].has("hd"):
		ts_key = "t%02d" % int(props.get("tileset", 14))
	if fdata.has("eos_tileset") and DB.tilesets.has("s%03d" % int(fdata.eos_tileset)):
		ts_key = "s%03d" % int(fdata.eos_tileset)     # Explorers of Sky dungeon graphics
	if not DB.tilesets.has(ts_key):
		ts_key = "t14"
	if arena_key != "":
		ts_key = arena_key
	terrain_view.build({"w": fs.w, "h": fs.h, "terrain": fs.terrain}, ts_key)
	_ts_key = ts_key
	fs.set_meta("fixed_floor", fixed_no != 0)
	# team
	var start: Vector2i = gen.player
	for m in team_mons:
		if m.hp <= 0:
			continue
		var p := start if m.is_leader else fs.free_tile_near(start, m, 4)
		if p.x < 0:
			continue
		m.pos = p
		m.facing = 0
		_reset_floor_status(m)
		fs.mons.append(m)
		if m.is_leader:
			fs.leader = m
		_add_sprite(m)
	# wild Pokémon
	for p in gen.get("enemies", []):
		_spawn_wild(p)
	# boss rooms: the team takes its marked places (sub_80854D4, run by the boss cutscenes' setup):
	# leader on slot 1, partner on slot 2, the others after, usually a few steps back from the boss
	_place_team_slots(gen)
	# fixed room: its Pokémon, items and traps (PlaceFixedRoomTile)
	_spawn_fixed(gen)
	if not eos_arena.is_empty():
		_spawn_eos_bosses(eos_arena)
	# items and traps
	for it in gen.get("items", []):
		var kind: String = it.get("kind", "normal")
		if kind == "buried":
			continue
		var table := int(fdata.items)
		if kind == "house":
			table = int(fdata.house_items)
		elif kind == "shop":
			table = int(fdata.shop)
		var id := ""
		if kind == "shop" and rng.randi_range(0, 1) == 0:
			id = EosItems.shop_pick(self, rng)        # Kecleon's wares: half Red's shop list, half Explorers of Sky items
		if id == "" or not KecleonShop.shoppable(id):
			id = _pick_item(table)
		if id == "":
			continue
		var n := 1
		var I: Dictionary = DB.items.get(id, {})
		if id == "poke":
			n = rng.randi_range(1, maxi(1, int(props.get("moneyUpperBound", 1)) * 40))
		elif I.has("amt"):
			n = rng.randi_range(int(I.amt[0]), int(I.amt[1]))
		var price := KecleonShop.buy_price(id, n) if kind == "shop" and KecleonShop.shoppable(id) else 0
		fs.items[it.pos] = {"id": id, "n": n, "price": price}
	if shop == null:
		shop = KecleonShop.new(self)
	shop.on_floor_built(gen)                 # Kecleon in the middle of the shop, the wares' value noted
	if test_want != "" and _floor_has_want():
		print("  TEST floor items: ", fs.items.values().map(func(x): return x.id))
	for p in gen.get("traps", []):
		var tid := _pick_trap(int(fdata.traps))
		if tid != "":
			fs.traps[p] = {"id": tid, "seen": tid == "wonder"}     # Red: Wonder Tiles are always visible
	for t in gen.get("fixed_traps", []):
		fs.traps[t.pos] = {"id": str(t.id), "seen": bool(t.visible)}
	for it in gen.get("fixed_items", []):
		fs.items[it.pos] = {"id": str(it.id), "n": maxi(1, int(it.qty)), "price": 0}
	if fixed_no != 0:
		boss = BossScene.make(self, fixed_no)
		if boss:
			# story fights can't end in a recruitment; post-story re-fights can (Red's legend recruits)
			if boss.cutscene.contains("POSTSTORY"):
				for m in fs.mons:
					if str(m.get_meta("behavior", "")) not in ["", "BEHAVIOR_FIXED_ENEMY"]:
						m.recruit_ok = true
			await boss.run_setup()
	spawn_timer = 0
	wind_state = {"turns": int(ddata.get("turn_limit", 1000)), "phase": 0}
	mem.clear()
	_snap_visuals()
	_reveal()
	obj_layer.queue_redraw()
	house_seen = false
	_test_blowouts = 0
	_test_floor_t0 = Time.get_ticks_msec()
	var scene_bgm: bool = boss != null and JSON.stringify(boss.scene.get("setup", [])).contains("\"bgm")
	if not scene_bgm:
		Audio.play_music(_music_for())
	hud.clear_msgs()
	_update_hud()
	Missions.on_floor_built(self)
	IQSky.on_floor_start(self)
	DungeonSave.autosave(self)          # crash-safe resume point at each floor start
	await _floor_banner()
	_announce_jobs_here()
	if boss:
		menu_open = true
		await boss.run_prefight()
		menu_open = false
		_update_hud()
		if boss.floor_over and not result_sent:
			await _boss_floor_over()
			return
	busy = false

## Tilesets 64+ are Red's special arena graphics we don't have: use the dungeon's own look instead.
func _fallback_tileset() -> int:
	for i in range(floor_i, -1, -1):
		var b: Array = ddata.floors[i].props
		if int(b[2]) < 64:
			return int(b[2])
	for f in ddata.floors:
		if int(f.props[2]) < 64:
			return int(f.props[2])
	return 14

func _spawn_fixed(gen: Dictionary) -> void:
	for e in gen.get("fixed_mons", []):
		var sp := str(e.sp)
		if not DB.species.has(sp):
			continue
		var occ = fs.mon_at(e.pos)
		if occ != null and occ.is_team():
			# a team member landed on the story Pokémon's tile (bigger parties than the arena expects): step aside
			var np: Vector2i = fs.free_tile_near(e.pos, occ, 4)
			if np.x >= 0 and np != e.pos:
				occ.pos = np
				if occ.visual:
					occ.visual.position = _px(np)
					_walkers.erase(occ.visual)
				occ = null
		if occ != null:
			continue
		var lv := BossScene.level_for(dkey, floor_i, sp)
		var m := DB.make_mon(sp, maxi(1, lv), "enemy")
		TurnRules.init_spawned(m, fs.rng)
		m.pos = e.pos
		m.facing = 0
		var b := str(e.behavior)
		m.set_meta("behavior", b)
		if b != "BEHAVIOR_FIXED_ENEMY":          # story Pokémon are never generated asleep
			for k in ["sleep", "napping", "nightmare"]:
				m.status[k] = 0
		if b in BossScene.NEUTRAL:
			m.side = "client"
			m.set_meta("story_npc", true)
		if b != "BEHAVIOR_FIXED_ENEMY":
			m.recruit_ok = false
		if not (b in BossScene.NEUTRAL) and Shiny.roll_boss(fs.rng):
			m.set_meta("shiny", true)                    # bosses and legendaries can be shiny too (re-enter to try again)
		fs.mons.append(m)
		_add_sprite(m)

## sub_8086A3C / sub_8086A54: a story Pokémon hidden until its entrance (can't act or be hit meanwhile).
func cs_hide(m: Mon, on: bool) -> void:
	if on:
		if not m.get_meta("cs_hidden", false):
			m.set_meta("cs_hidden", true)
			m.set_meta("cs_side", m.side)
			m.side = "client"
		if m.visual:
			m.visual.visible = false
	else:
		if m.get_meta("cs_hidden", false):
			m.set_meta("cs_hidden", false)
			m.side = str(m.get_meta("cs_side", "enemy"))
		if m.visual:
			m.visual.visible = true
			m.visual.position = _px(m.pos)
			_walkers.erase(m.visual)

## HandleFaint_Async(..., DUNGEON_EXIT_DELETED_FOR_EVENT): removed without fainting.
func cs_remove(m: Mon) -> void:
	fs.mons.erase(m)
	if m.visual:
		m.visual.queue_free()
		m.visual = null

## DungeonSave hooks: keep the floor's fixed room / cutscene across a quicksave.
func save_extra() -> Dictionary:
	var d := {"fixed_no": fixed_no}
	if boss:
		d.boss = {"cutscene": boss.cutscene, "names": boss.names, "floor_over": boss.floor_over, "ended": boss.ended}
	return d

func load_extra(d: Dictionary) -> void:
	fixed_no = int(d.get("fixed_no", 0))
	boss = null
	if d.has("boss"):
		var b := BossScene.make(self, fixed_no)
		if b:
			var bd: Dictionary = d.boss
			b.cutscene = str(bd.get("cutscene", b.cutscene))
			b.scene = BossScene.load_data().get("cutscenes", {}).get("scenes", {}).get(b.cutscene, {})
			for k in bd.get("names", {}):
				b.names[int(k)] = str(bd.names[k])
			b.floor_over = bool(bd.get("floor_over", false))
			b.ended = bool(bd.get("ended", false))
			boss = b

## The boss is beaten (or nobody's here): Red ends the floor like taking the stairs.
# ------------------------------------------------------------------ Explorers of Sky boss arenas
var eos_arena := {}
var _test_blowouts := 0
var _test_floor_t0 := 0
static var _eos_fixed := {}
static func eos_fixed_data() -> Dictionary:
	if _eos_fixed.is_empty():
		var f := FileAccess.open("res://data/eos_fixed.json", FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			_eos_fixed = v if v is Dictionary else {}
	return _eos_fixed

## The arena from fixed.bin as a generator result: walled border, one lit room, no stairs (beat the boss).
func _eos_arena_gen(a: Dictionary, sec: String) -> Dictionary:
	var w := int(a.w) + 2
	var h := int(a.h) + 2
	var terr := PackedByteArray(); terr.resize(w * h)
	var room := PackedByteArray(); room.resize(w * h); room.fill(255)
	var flg := PackedInt32Array(); flg.resize(w * h)
	var src: Array = a.terrain
	for y in int(a.h):
		for x in int(a.w):
			var t := int(src[y * int(a.w) + x])
			terr[(y + 1) * w + x + 1] = t
			if t != 0:
				room[(y + 1) * w + x + 1] = 0
	var ld: Array = a.leader if a.get("leader") != null else [int(a.w) / 2, int(a.h) - 2]
	return {"w": w, "h": h, "terrain": terr, "room": room, "flags": flg, "stairs": Vector2i(-1, -1),
		"player": Vector2i(int(ld[0]) + 1, int(ld[1]) + 1), "items": [], "traps": [], "enemies": [],
		"monster_house_room": -1, "shop": Rect2i(), "kecleon": -1, "rooms": [Rect2i(1, 1, int(a.w), int(a.h))],
		"secondary_kind": sec, "layout": -2, "fixed_room": 0, "fixed_floorwide": true,
		"fixed_mons": [], "fixed_items": [], "fixed_traps": []}

func _spawn_eos_bosses(a: Dictionary) -> void:
	for e in a.get("mons", []):
		var sp := str(e.sp)
		if not DB.species.has(sp):
			continue
		var p := Vector2i(int(e.x) + 1, int(e.y) + 1)
		if fs.mon_at(p) != null:
			p = fs.free_tile_near(p, null, 4)
			if p.x < 0:
				continue
		var m := DB.make_mon(sp, maxi(1, int(e.level)), "enemy")
		TurnRules.init_spawned(m, fs.rng)
		if int(e.hp) > 0:
			m.max_hp = int(e.hp)
			m.hp = m.max_hp
		m.pos = p
		m.facing = 0
		m.recruit_ok = false
		m.set_meta("eos_boss", true)
		m.set_meta("boss", true)
		fs.mons.append(m)
		_add_sprite(m)
		if Dialog.auto:
			print("  BOSS %s Lv%d HP %d (EoS)" % [m.name, m.level, m.hp])

func _boss_floor_over() -> void:
	if boss == null or boss.ended:
		return
	boss.ended = true
	await get_tree().create_timer(0.4 if not Dialog.auto else 0.05).timeout
	if boss.end_dungeon:
		_end("rescued")             # the rescued Pokémon left: the mission is over and the team goes home
		return
	await next_floor()

## gDungeonMusic: FloorProperties.bgMusic -> song id (run_dungeon.c DungeonStartNewBGM).
const DUNGEON_MUSIC := [114, 125, 14, 120, 15, 113, 111, 20, 102, 25, 104, 115, 108, 22, 125, 125, 125, 125, 13, 21, 15, 126, 33, 39, 123, 124, 23, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 26, 110, 110, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 125, 26, 127, 35, 35, 35, 125, 125, 125, 125, 125, 125]

func _music_for() -> String:
	if not eos_arena.is_empty() and str(eos_arena.get("music", "")) != "" and ResourceLoader.exists("res://assets/music/%s.ogg" % str(eos_arena.music)):
		return str(eos_arena.music)       # the arena's boss theme
	var fl: Array = DB.dungeons.get("dungeons", {}).get(dkey, {}).get("floors", [])
	if not fl.is_empty():
		var fm := str(fl[clampi(floor_i, 0, fl.size() - 1)].get("music", ""))
		if fm != "" and (ResourceLoader.exists("res://assets/music/%s.ogg" % fm) or ResourceLoader.exists("res://assets/music/%s.mp3" % fm)):
			return fm
	var idx := 1
	if not fl.is_empty():
		var pr: Array = fl[clampi(floor_i, 0, fl.size() - 1)].get("props", [])
		if pr.size() > 3:
			idx = int(pr[3])
	return "%03d" % int(DUNGEON_MUSIC[clampi(idx, 0, DUNGEON_MUSIC.size() - 1)])

## Arriving on a floor where a taken job is (not in Red, which says nothing; the outlaw line is Explorers
## of Sky's). One line per job in the message log, with the job chime.
func _announce_jobs_here() -> void:
	var fl := floor_i + 1
	var lines: Array = []
	for j in Game.jobs:
		if str(j.get("state", "")) != "taken" or str(j.get("dungeon", "")) != dkey or int(j.get("floor", -1)) != fl:
			continue
		var cn := "[color=#7fe0ff]%s[/color]" % str(DB.species.get(str(j.get("client", "")), {}).get("name", "your client"))
		var tn := "[color=#7fe0ff]%s[/color]" % str(DB.species.get(str(j.get("target", "")), {}).get("name", "the target"))
		var line := ""
		match str(j.get("kind", "")):
			"find":
				line = "The [color=#ffdc4a]%s[/color] you're looking for is on this floor!" % DB.item_name(str(j.get("item", "")))
			"deliver":
				line = "%s is waiting on this floor for the [color=#ffdc4a]%s[/color]!" % [cn, DB.item_name(str(j.get("item", "")))]
			"escort":
				line = "%s's friend, %s, is somewhere on this floor!" % [cn, tn]
			"target":
				line = "%s is somewhere on this floor!" % tn
			_:
				line = "%s is somewhere on this floor!" % cn
		if bool(j.get("outlaw", false)) or str(j.get("kind", "")) == "outlaw":
			line = "There's an outlaw on this floor. I know it!"
		if not line in lines:
			lines.append(line)
	if lines.is_empty():
		return
	Audio.sfx("join")
	for l in lines:
		_msg(l)

func _floor_banner() -> void:
	_ensure_red_fx()
	if DungeonGfx.tex("banfont.png") != null:
		# Red's banner font and cross-fade (dungeon_name_banner.c, dungeon_vram.c sub_803E748)
		await RedBanner.play(self, _display_name(), bool(ddata.get("up", false)), floor_i + 1)
		red_fx.floor_start()
		return
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.add_child(bg)
	var l := Label.new()
	l.theme = UITheme.theme()
	l.text = "%s\n%s" % [_display_name(), _floor_label()]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.add_child(l)
	await get_tree().create_timer(1.1).timeout
	var tw := create_tween()
	tw.tween_property(bg, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.35)
	await tw.finished
	cl.queue_free()

func _display_name() -> String:
	return str(ddata.get("name", dkey.capitalize()))

## ResetMonEntityData (dungeon_mon_spawn.c), run on every team member as each floor starts: every status
## condition ends and all stat stages go back to normal (Red keeps only HP, PP, Belly and levels).
func _reset_floor_status(m: Mon) -> void:
	for k in m.status.keys():
		m.status[k] = "" if m.status[k] is String else 0
	for k in m.stages.keys():
		m.stages[k] = 10

func _add_sprite(m: Mon) -> void:
	var s := MonSprite.new()
	mon_layer.add_child(s)
	s.setup(m)
	s.position = _px(m.pos)
	if m.get_meta("cs_hidden", false):
		s.visible = false

var _ts_key := "t14"

## Drought / One-Room / Fill-In Orbs changed the terrain: redraw it.
func _redraw_terrain() -> void:
	terrain_view.build({"w": fs.w, "h": fs.h, "terrain": fs.terrain}, _ts_key)

## Transfer Orb changed a Pokémon's species: new sprite.
func _refresh_mon_visual(m: Mon) -> void:
	if m.visual:
		m.visual.queue_free()
		m.visual = null
	_add_sprite(m)

func _px(p: Vector2i) -> Vector2:
	return Vector2(p.x * T + T / 2.0, p.y * T + T / 2.0)

func _snap_visuals() -> void:
	for m in fs.mons:
		if m.visual:
			m.visual.position = _px(m.pos)
			_walkers.erase(m.visual)
	if fs.leader and fs.leader.visual:
		cam.position = fs.leader.visual.position

func _pick_weighted(pairs: Array) -> Variant:
	var tot := 0
	for p in pairs:
		tot += int(p[1])
	if tot <= 0:
		return null
	var r := rng.randi_range(0, tot - 1)
	for p in pairs:
		r -= int(p[1])
		if r < 0:
			return p[0]
	return pairs[-1][0]

func _floor_has_want() -> bool:
	if test_want == "":
		return false
	var fl: Dictionary = DB.dungeons.dungeons.get(dkey, {}).get("floors", [])[mini(floor_i, DB.dungeons.dungeons.get(dkey, {}).get("floors", []).size() - 1)] if DB.dungeons.dungeons.has(dkey) else {}
	var tabs: Array = DB.dungeons.get("item_tables", [])
	var ti := int(fl.get("items", -1))
	return ti >= 0 and ti < tabs.size() and JSON.stringify(tabs[ti]).contains('"%s"' % test_want)

func _pick_item(table_i: int) -> String:
	var tabs: Array = DB.dungeons.get("item_tables", [])
	if table_i < 0 or table_i >= tabs.size():
		return ""
	if not boss and fixed_no == 0 and Awaken.can_drop() and rng.randi_range(0, 199) == 0:
		return "empowerseed"                            # DX: rare, after the story
	if not boss and fixed_no == 0:
		var x := EosItems.floor_pick(self, rng)        # Explorers of Sky / Remixed items and exclusives
		if x != "" and DB.items.has(x):
			return x
	var cats: Array = tabs[table_i].cats
	var cp: Array = []
	for c in cats:
		cp.append([c, int(c.p)])
	var c = _pick_weighted(cp)
	if c == null:
		return ""
	var ip: Array = []
	for i in c.items:
		if DB.items.has(str(i[0])):
			ip.append([str(i[0]), int(i[1])])
	var id = _pick_weighted(ip)
	return "" if id == null else str(id)

func _pick_trap(table_i: int) -> String:
	var tabs: Array = DB.dungeons.get("trap_tables", [])
	if table_i < 0 or table_i >= tabs.size():
		return ""
	var pairs: Array = []
	for k in tabs[table_i]:
		pairs.append([k, int(tabs[table_i][k])])
	var t = _pick_weighted(pairs)
	return "" if t == null else str(t)

func _spawn_wild(p: Vector2i) -> Mon:
	# SpawnWildMon fails on a tile someone already stands on (the team is placed first)
	if fs.mon_at(p) != null:
		return null
	var fdata: Dictionary = ddata.floors[floor_i]
	var pairs: Array = []
	for e in fdata.get("pk", []):
		if DB.species.has(str(e[0])):
			pairs.append([e, int(e[2])])
	var e = _pick_weighted(pairs)
	if e == null:
		return null
	var m := DB.make_mon(str(e[0]), maxi(1, int(e[1])), "enemy")
	if Shiny.roll(fs.rng):
		m.set_meta("shiny", true)                    # DX: a rare shiny
	TurnRules.init_spawned(m, fs.rng)
	m.pos = p
	m.facing = rng.randi_range(0, 7)
	fs.mons.append(m)
	_add_sprite(m)
	return m

# ================================================================= drawing
func _draw_objects() -> void:
	if fs == null:
		return
	if (_rotate or _turn_held()) and fs.leader:
		# Red's rotate mode (ChangeDungeonCameraPos): trappat metatile 20 (grid) on visible floor tiles,
		# metatile 21 (red square) on the leader's tile and the 5 tiles in the facing direction
		var L: Vector2i = fs.leader.pos
		var line := {}
		var q2: Vector2i = L
		for k in 6:
			line[q2] = true
			q2 += DB.DIRS[fs.leader.facing]
		var gt := DB.tex("res://assets/ui/mode_grid.png")
		var ht := DB.tex("res://assets/ui/mode_hilite.png")
		for yy in range(L.y - 9, L.y + 10):
			for xx in range(L.x - 12, L.x + 13):
				var q := Vector2i(xx, yy)
				if not fs.inb(q) or fs.is_wall(q) or not _tile_seen(q):
					continue
				obj_layer.draw_texture(ht if line.has(q) else gt, Vector2(q.x * T, q.y * T))
	if _stairs_tex and fs.stairs.x >= 0:
		obj_layer.draw_texture(_stairs_tex, Vector2(fs.stairs.x * T, fs.stairs.y * T) + (Vector2(T, T) - _stairs_tex.get_size()) / 2)
	for p in fs.traps:
		var t: Dictionary = fs.traps[p]
		if t.seen:
			var ti: int = TRAP_ICON.get(str(t.id), -1)
			var tt := DB.tex("res://assets/ui/traps_red.png")
			if ti >= 0 and tt:
				obj_layer.draw_texture_rect_region(tt, Rect2(p.x * T, p.y * T, T, T), Rect2(ti * 24, 0, 24, 24))
			else:
				var r := Rect2(p.x * T + 5, p.y * T + 5, T - 10, T - 10)
				obj_layer.draw_rect(r, Color(0.9, 0.3, 0.3, 0.85) if t.id != "wonder" else Color(0.4, 0.8, 1, 0.85))
	for p in fs.items:
		var it: Dictionary = fs.items[p]
		var ic := _icon_rect(it.id)
		if ic.size.x > 0 and _icon_tex:
			obj_layer.draw_texture_rect_region(_icon_tex, Rect2(p.x * T + 4, p.y * T + 4, 16, 16), ic)

func _icon_rect(id: String) -> Rect2:
	var a = DB.item_icons.get(id)
	if a == null:
		var I: Dictionary = DB.items.get(id, {})
		for k in DB.items:   # same Red sprite as another item that has an icon
			var J: Dictionary = DB.items[k]
			if DB.item_icons.has(k) and int(J.get("sprite", -1)) == int(I.get("sprite", -2)):
				a = DB.item_icons[k]
				DB.item_icons[id] = a
				break
	if a == null:
		return Rect2()
	return Rect2(a[0], a[1], 16, 16)

# ================================================================= input
static var perf_log := false            # --perf: report frames whose game logic took long
static var perf_acc := {}
static func pacc(k: String, us: int) -> void:
	perf_acc[k] = int(perf_acc.get(k, 0)) + us
var _perf: Array = []
var _perf_last := 0
func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_main(dt)
	_advance_walkers(dt)      # after input, so a step chosen this frame continues the motion with no pause
	if perf_log:
		var now := Time.get_ticks_usec()
		if _perf_last > 0:
			_perf.append(now - _perf_last)       # whole frame: game logic, resumed coroutines, drawing
			if now - _perf_last > 12000:
				print("  SLOW frame %.1fms %s" % [(now - _perf_last) / 1000.0, str(perf_acc)])
		perf_acc.clear()
		_perf_last = now
		if _perf.size() >= 300:
			var srt := _perf.duplicate()
			srt.sort()
			print("PERF frames=%d median=%.2fms p95=%.2fms max=%.2fms over8ms=%d" % [srt.size(), srt[srt.size() / 2] / 1000.0, srt[int(srt.size() * 0.95)] / 1000.0, srt[-1] / 1000.0, srt.filter(func(x): return x > 8000).size()])
			_perf.clear()

## Walking: every moving sprite glides toward its tile at a constant speed (no per-step tweens), so
## holding a direction moves smoothly: the next step is taken just before the current one ends.
var _walkers := {}       # visual -> {"to": Vector2, "v": px per second}

func _advance_walkers(dt: float) -> void:
	if _walkers.is_empty():
		return
	for vis in _walkers.keys():
		if not is_instance_valid(vis):
			_walkers.erase(vis)
			continue
		var w: Dictionary = _walkers[vis]
		var to: Vector2 = w.to
		var step: float = float(w.v) * dt
		if vis.position.distance_to(to) <= step:
			vis.position = to
			_walkers.erase(vis)
		else:
			vis.position = vis.position.move_toward(to, step)

func _walk_left(vis) -> float:
	if vis == null or not _walkers.has(vis):
		return 0.0
	var w: Dictionary = _walkers[vis]
	return vis.position.distance_to(w.to) / maxf(1.0, float(w.v))

func _process_main(dt: float) -> void:
	if fs == null:
		return
	if _lmoves != null and (menu_open or result_sent or not Input.is_action_pressed("gp_l")):
		_show_l_moves(false)
	if fs.leader and fs.leader.visual:
		cam.position = cam.position.lerp(fs.leader.visual.position, minf(1.0, dt * 14.0))
	var dg_now := _diag_held()
	if dg_now and not _diag_was:
		_arrow_t0 = Time.get_ticks_msec()
	if dg_now or _diag_was or _rotate or _turn_held():
		arrow_layer.queue_redraw()
		if _rotate or _turn_held():
			obj_layer.queue_redraw()
	_diag_was = dg_now
	if busy or menu_open or result_sent:
		return
	var d := _input_dir()
	_running = Input.is_action_pressed("act_run") or Input.is_action_pressed("gp_b") or (hud != null and hud.pad_run and hud.pad_dir >= 0)
	if d >= 0 and Input.is_action_pressed("gp_b"):
		_b_moved = true
	if autoplay:
		if d >= 0:
			set_autoplay(false)      # taking control stops Autoplay
		else:
			_running = test_invincible or Dialog.auto     # the player's Autoplay walks at the normal pace
			autoplay_step()
			return
	if qol and qol.process_input(d):     # run mode / tap-to-walk
		return
	if d >= 0:
		if Input.is_action_pressed("act_turn") or _rotate:
			if fs.leader.facing != d:
				fs.leader.facing = d
				obj_layer.queue_redraw()
			return
		_hold_t += dt
		leader_action({"type": "move", "dir": d})
	else:
		_hold_t = 0.0
		if fs.leader and fs.leader.visual and fs.leader.visual.anim == "Walk":
			for mm in fs.mons:
				if mm.visual and mm.visual.anim == "Walk":
					mm.visual.play("Idle")

func _input_dir() -> int:
	if hud and hud.pad_dir >= 0:
		return hud.pad_dir
	var x := int(Input.is_action_pressed("move_right")) - int(Input.is_action_pressed("move_left"))
	var y := int(Input.is_action_pressed("move_down")) - int(Input.is_action_pressed("move_up"))
	for k in [["move_ul", -1, -1], ["move_ur", 1, -1], ["move_dl", -1, 1], ["move_dr", 1, 1]]:
		if Input.is_action_pressed(k[0]):
			x = k[1]; y = k[2]
	if x == 0 and y == 0:
		return -1
	if (Input.is_action_pressed("act_diag") or Input.is_action_pressed("gp_r")) and (x == 0 or y == 0):
		return -1
	return DB.dir_index(Vector2i(x, y))

func set_zoom(z: float) -> void:
	z = clampf(z, 0.75, 3.0)
	Game.settings.zoom = z
	cam.zoom = Vector2.ONE * z / UITheme.ui_scale()      # menu size scales the canvas; the floor keeps its size

var _pinch := {}
func _input(e: InputEvent) -> void:
	if fs == null or result_sent:
		return
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		set_zoom(float(Game.settings.get("zoom", 1.25)) + (0.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1))
	elif e is InputEventMagnifyGesture:
		set_zoom(float(Game.settings.get("zoom", 1.25)) * e.factor)
	elif e is InputEventScreenTouch:
		if e.pressed:
			_pinch[e.index] = e.position
		else:
			_pinch.erase(e.index)
			if _pinch.size() < 2:
				Game.save_game()
	elif e is InputEventScreenDrag and _pinch.size() == 2 and _pinch.has(e.index) and (hud == null or e.index != hud._pad_touch):
		var other: Vector2 = _pinch[_pinch.keys()[0] if _pinch.keys()[1] == e.index else _pinch.keys()[1]]
		var before := other.distance_to(_pinch[e.index])
		_pinch[e.index] = e.position
		var after := other.distance_to(e.position)
		if before > 10:
			set_zoom(float(Game.settings.get("zoom", 1.25)) * after / before)

## Controller = Red's GBA buttons (dungeon_main.c):
## A attack · L+A / L+B / L+X / L+Y the leader's moves 1-4 · A+B wait · tap B menu · hold B run ·
## hold R diagonals only · tap R face the nearest foe · Start turn in place · L+Select message log ·
## L+R throw set item · Select map · X moves · Y items.
var _rotate := false
var _b_t0 := -1.0
var _b_moved := false
var _r_t0 := -1.0

func _pad_held(a: String) -> bool:
	return Input.is_action_pressed(a)

func _pad_event(e: InputEventJoypadButton) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if e.pressed:
		if autoplay:
			set_autoplay(false)
		if e.is_action("gp_a"):
			if _pad_held("gp_b"):
				leader_action({"type": "wait"})
			elif _pad_held("gp_l"):
				use_move_slot(0)
			else:
				leader_action({"type": "attack", "move": "", "dir": fs.leader.facing})
		elif e.is_action("gp_b"):
			if _pad_held("gp_l"):
				use_move_slot(1)
				_b_t0 = -1.0
			elif _pad_held("gp_a"):
				leader_action({"type": "wait"})
				_b_t0 = -1.0
			else:
				_b_t0 = now
				_b_moved = false
		elif e.is_action("gp_l"):
			_show_l_moves(true)
		elif e.is_action("gp_r"):
			if _pad_held("gp_l"):
				throw_set_item()
				_r_t0 = -1.0
			else:
				_r_t0 = now
		elif e.is_action("gp_start"):
			_set_rotate(not _rotate)
			if _rotate:
				_face_nearest_foe()
		elif e.is_action("gp_select"):
			if _pad_held("gp_l"):
				open_log()
			else:
				_toggle_map()
		elif e.is_action("gp_x"):
			if _pad_held("gp_l"):
				use_move_slot(2)
			else:
				open_moves()
		elif e.is_action("gp_y"):
			if _pad_held("gp_l"):
				use_move_slot(3)
			else:
				open_bag()
	else:
		if e.is_action("gp_l"):
			_show_l_moves(false)
		if e.is_action("gp_b") and _b_t0 >= 0.0:
			if not _b_moved and now - _b_t0 < 0.35:
				if _rotate:
					_set_rotate(false)
				else:
					open_main_menu()
			_b_t0 = -1.0
		elif e.is_action("gp_r") and _r_t0 >= 0.0:
			if now - _r_t0 < 0.3:
				_face_nearest_foe()          # a tap of R turns toward the nearest enemy (the grid is Start's)
			_r_t0 = -1.0

func _set_rotate(on: bool) -> void:
	_rotate = on
	if on:
		_arrow_t0 = Time.get_ticks_msec()
	obj_layer.queue_redraw()
	arrow_layer.queue_redraw()

var arrow_layer: Node2D
var _turn_key_t0 := 0
## dungeon_main.c sRotateArrowsInfo, per direction: [tile (0 = 0x212 up, 1 = 0x213 up-right, 2 = 0x214 right), hflip, vflip]
const ARROW_INFO := [[0, false, true], [1, false, true], [2, false, false], [1, false, false],
	[0, true, false], [1, true, false], [2, true, true], [1, true, true]]
## trappat metatile per trap (include/constants/trap.h order)
const TRAP_ICON := {"trip": 0, "mud": 1, "sticky": 2, "grimy": 3, "summon": 4, "pitfall": 5, "warp": 6, "gust": 7,
	"spin": 8, "slumber": 9, "slow": 10, "seal": 11, "poison": 12, "selfdestruct": 13, "explosion": 14, "ppzero": 15,
	"chestnut": 16, "wonder": 17, "pokemon": 18, "spiked": 19}
var _arrow_t0 := 0
var _diag_was := false

func _diag_held() -> bool:
	return Input.is_action_pressed("act_diag") or Input.is_action_pressed("gp_r")

func _turn_held() -> bool:
	return Input.is_action_pressed("act_turn")

## Red's mode arrows (dungeon_main.c TryCreateModeArrows): 4 diagonal arrows while R is held, one arrow in
## the facing direction in rotate mode. They bob outward 0..7 px, one pixel every 2 frames.
func _draw_mode_arrows() -> void:
	if fs == null or fs.leader == null or fs.leader.visual == null:
		return
	var diag := _diag_held()
	var rot := _rotate or _turn_held()
	if not diag and not rot:
		return
	# Red: arrow top-left = screen centre (116, 82) + dir * (10 + bob), i.e. arrows centred 6 px below the
	# leader's tile centre... our tile centre sits 4 px above the shadow, so centre them on the shadow.
	var c: Vector2 = fs.leader.visual.position + Vector2(0, 2)
	var bob := float(int((Time.get_ticks_msec() - _arrow_t0) / 1000.0 * 30.0) & 7)
	var at := DB.tex("res://assets/ui/mode_arrows.png")
	if at == null:
		return
	var dirs: Array = [5, 7, 1, 3] if diag else [fs.leader.facing]
	for k in dirs:
		var v := Vector2(DB.DIRS[k])
		var inf: Array = ARROW_INFO[k]      # [etcfont tile 0x212+n, hflip, vflip]
		var ctr := c + v * (10.0 + bob)
		arrow_layer.draw_set_transform(ctr, 0.0, Vector2(-1.0 if inf[1] else 1.0, -1.0 if inf[2] else 1.0))
		arrow_layer.draw_texture_rect_region(at, Rect2(-4, -4, 8, 8), Rect2(int(inf[0]) * 8, 0, 8, 8))
	arrow_layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _unhandled_input(e: InputEvent) -> void:
	if busy or menu_open or result_sent or fs == null:
		return
	if e is InputEventJoypadButton:
		_pad_event(e)
		get_viewport().set_input_as_handled()
		return
	if e is InputEventKey and e.is_action("act_turn") and not e.is_echo():     # keyboard: tap the turn key = face an enemy
		if e.pressed:
			_turn_key_t0 = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - _turn_key_t0 < 300:
			_face_nearest_foe()
	if e.is_action_pressed("act_setmove"):
		use_set_move()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("act_log"):
		open_log()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("act_auto"):
		set_autoplay(not autoplay)
		get_viewport().set_input_as_handled()
		return
	if autoplay and (e is InputEventKey or e is InputEventJoypadButton) and e.is_pressed():
		set_autoplay(false)
	if e.is_action_pressed("act_attack") and Input.is_action_pressed("act_run"):
		use_set_move()          # Red: L + A uses the set move
	elif e.is_action_pressed("act_bag") and Input.is_action_pressed("act_run"):
		throw_set_item()        # Red: L + R throws the set item
	elif e.is_action_pressed("act_attack"):
		leader_action({"type": "attack", "move": "", "dir": fs.leader.facing})
	elif e.is_action_pressed("act_menu"):
		open_main_menu()
	elif e.is_action_pressed("act_moves"):
		open_moves()
	elif e.is_action_pressed("act_bag"):
		open_bag()
	elif e.is_action_pressed("act_wait"):
		leader_action({"type": "wait"})
	elif e.is_action_pressed("act_map"):
		_toggle_map()
	else:
		return
	get_viewport().set_input_as_handled()

func on_hud_button(name: String) -> void:
	if name == "auto":
		set_autoplay(not autoplay)
		return
	if busy or menu_open or result_sent:
		return
	if autoplay:
		set_autoplay(false)
	match name:
		"attack": leader_action({"type": "attack", "move": "", "dir": fs.leader.facing})
		"moves": open_moves()
		"bag": open_bag()
		"menu": open_main_menu()
		"wait": leader_action({"type": "wait"})
		"map": _toggle_map()

# ================================================================= turn loop
func leader_action(a: Dictionary) -> void:
	if busy:
		return
	busy = true
	var L := fs.leader
	var used := await execute(L, a)
	if used and not (boss and boss.floor_over):
		await world_turn()
		if not result_sent and not (boss and boss.floor_over):
			await _team_item_prompts()
			_shiny_check()
	await _await_lead_walk(a.get("type", "") == "move")
	if boss and boss.floor_over and not result_sent:
		await _boss_floor_over()
		return
	busy = false
	if not result_sent:
		_update_hud()

const REVIVERS := ["reviver", "tinyreviver"]
const HEAL_KINDS := ["heal", "sitrus"]
const CURES := {"poison": ["pecha", "healseed"], "badpoison": ["pecha", "healseed"], "burn": ["rawst", "healseed"],
	"para": ["cheri", "healseed"], "sleep": ["chesto", "healseed"]}
const STATUS_WORDS := {"poison": "poisoned", "badpoison": "badly poisoned", "burn": "burned", "para": "paralyzed", "sleep": "asleep"}

## Team item prompts (QoL, not in Red): after the turn, an ally that dropped to 1/3 HP or caught a status
## gets one question offering the Toolbox items that help ("Use the Oran Berry on it?"). Saying yes uses
## the item on it and takes the leader's turn, like using an item from the menu. Each ally is asked once
## per drop / status (again once it has recovered).
## sub_806A5B8 (dungeon_misc.c), after each step: water heals a burn; lava thaws a frozen Pokémon and burns
## anyone who doesn't walk on lava (Ho-Oh and Moltres never); the leader moving inside a wall loses 5 Belly.
func _tile_effects(m: Mon) -> void:
	var t := fs.terrain_at(m.pos)
	if t == 2:
		if fs.secondary == "lava":
			if int(m.status.get("frozen", 0)) > 0:
				m.status.frozen = 0
				_msg("%s thawed out!" % _nm(m))
			var sp4 := m.sp.substr(0, 4)
			if not ("Fire" in m.types) and sp4 != "0250" and sp4 != "0146" and int(m.status.get("burn", 0)) <= 0 \
					and HeldItems.blocks_status(m, "burn") == "" and AbilityFx.blocks_status(m, "burn") == "":
				m.status.burn = TurnRules.red_turns("burn", fs.rng, m, 0x7F)
				_msg("%s was burned!" % _nm(m))
		elif int(m.status.get("burn", 0)) > 0:
			m.status.burn = 0
			m.status.erase("burn_cd")
			_msg("%s's burn was healed!" % _nm(m))
	elif t == 0 and m.is_leader and bool(Game.settings.get("hunger", true)):
		var before := float(belly_state.get("belly", belly))
		belly = maxf(0.0, before - 5.0)
		belly_state.belly = belly
		if before > 19 and belly <= 19:
			_msg("Getting hungry...")
		if before > 9 and belly <= 9:
			_msg("Getting dizzy from hunger...")

## DX: a shiny Pokémon sparkles the first time the leader sees it.
func _shiny_check() -> void:
	var L: Mon = fs.leader
	if L == null:
		return
	for m in fs.mons:
		if m.hp > 0 and not m.is_team() and Shiny.is_shiny(m) and not m.get_meta("shiny_seen", false) and fs.can_see(L, m.pos):
			m.set_meta("shiny_seen", true)
			if m.visual and is_instance_valid(m.visual):
				m.visual.sparkle = 1.6
			Audio.sfx("join")
			_msg("[color=#ffdc4a]Oh! A shiny %s![/color]" % _nm(m))

func _team_item_prompts() -> void:
	if not bool(QOL.opt("qol_itemask")) or auto_answer:
		return
	for m in fs.team():
		if m.is_leader or m.hp <= 0 or m.get_meta("escort", false) or Missions.is_client(m) or result_sent:
			continue
		if m.hp * 2 > m.max_hp:
			m.remove_meta("ask_low")
		for k in CURES:
			if int(m.status.get(k, 0)) <= 0:
				m.remove_meta("ask_" + k)
		var opts: Array = []        # [label, bag index]
		var why := ""
		if m.hp * 3 <= m.max_hp and not m.has_meta("ask_low"):
			m.set_meta("ask_low", true)
			why = "%s is low on HP! (%d/%d)" % [m.name, m.hp, m.max_hp]
			var seen := {}
			for i in Game.bag.size():
				var id := str(Game.bag[i].id)
				if str(DB.items.get(id, {}).get("kind", "")) in HEAL_KINDS and not seen.has(id) and not Game.bag[i].get("sticky", false):
					seen[id] = true
					opts.append([DB.item_name(id), i])
		else:
			for k in CURES:
				if int(m.status.get(k, 0)) > 0 and not m.has_meta("ask_" + k):
					m.set_meta("ask_" + k, true)
					why = "%s is %s!" % [m.name, STATUS_WORDS[k]]
					for want in CURES[k]:
						for i in Game.bag.size():
							if str(Game.bag[i].id) == want and not Game.bag[i].get("sticky", false):
								opts.append([DB.item_name(want), i])
								break
					break
		if opts.is_empty() and not Awaken.is_awake(m) and not fs.has_meta("ask_awk_%d" % m.uid):
			var strong := boss != null
			for o in fs.mons:
				if o.hp > 0 and not o.is_team() and o.side != "client" and FloorState.cheb(o.pos, m.pos) <= 1 and o.level >= m.level + 3:
					strong = true
			if strong:
				for i in Game.bag.size():
					if str(Game.bag[i].id) == "empowerseed" and not Game.bag[i].get("sticky", false):
						fs.set_meta("ask_awk_%d" % m.uid, true)
						why = "A strong foe! Give %s the Empowerment Seed?%s" % [m.name, " It can Mega Evolve!" if Awaken.mega_of(m.sp) != "" else ""]
						opts.append([DB.item_name("empowerseed"), i])
						break
		if opts.is_empty():
			continue
		var labels: Array = opts.map(func(o): return "Use " + str(o[0]))
		labels.append("Not now")
		var r := await TeamScreens.ask(ui_root, why, labels, 0)
		if r < 0 or r >= opts.size():
			continue
		await use_item(m, int(opts[r][1]))
		_update_hud()
		await world_turn()          # using an item is the leader's action for this turn
		return                      # one question per turn

## Everyone else acts, then end-of-turn effects.
func world_turn() -> void:
	var order: Array = []
	for m in fs.mons:
		if m.hp > 0 and not m.is_leader:
			order.append(m)
	# Red: team members act before wild Pokémon
	order.sort_custom(func(a, b): return int(a.is_team()) > int(b.is_team()))
	var skipped: Array = []
	for m in order:
		if m.hp <= 0 or m.side == "client" or result_sent or not fs.mons.has(m):
			continue
		var n := int(TurnRules.actions_this_turn(m, fs))
		for i in n:
			if m.hp <= 0 or result_sent:
				break
			var a := _decide(m)
			if a.get("ally_skip", false):
				skipped.append(m)
				break
			# Only something shown on screen (an attack, a throw) waits for the steps to finish first; a Pokémon
			# that just waits or picks something up doesn't stop the leader mid-stride (that made walking stutter
			# at random, whenever anyone on the floor was asleep or idle).
			# Off screen (attacker and the tile it faces): the action resolves at once, with no animation
			# pauses, so a fight somewhere else on the floor doesn't hold up the leader's walk.
			_quiet = not m.is_leader and not _on_screen(m.pos) and not _on_screen(m.pos + DB.DIRS[int(a.get("dir", m.facing)) & 7])
			if str(a.get("type", "wait")) in ["attack", "throw"] and not _quiet:
				await _flush_walks()
			await execute(m, a)
			_quiet = false
	# Red re-runs allies that were blocked, nearest to the leader first (up to 3 passes)
	for pass_i in 3:
		if skipped.is_empty() or result_sent:
			break
		skipped.sort_custom(func(a, b): return FloorState.cheb(a.pos, fs.leader.pos) < FloorState.cheb(b.pos, fs.leader.pos))
		var again: Array = []
		for m in skipped:
			if m.hp <= 0:
				continue
			var mm: Dictionary = mem.get(m.uid, {})
			mm.recalculate_follow = true
			var a2 := _decide(m)
			if a2.get("ally_skip", false):
				again.append(m)
			else:
				await execute(m, a2)
		skipped = again
	await _flush_walks()
	if result_sent:
		return
	await end_of_turn()

var _quiet := false        # the acting Pokémon is off screen: skip animation pauses

func _pause(sec: float) -> void:
	if _quiet:
		return
	await get_tree().create_timer(sec).timeout

## Is tile p (or the tile next to it) inside the visible part of the floor?
func _on_screen(p: Vector2i) -> bool:
	if cam == null:
		return true
	var half := get_viewport_rect().size / cam.zoom * 0.5 + Vector2(T, T)
	var d := (_px(p) - cam.position).abs()
	return d.x <= half.x and d.y <= half.y

func _decide(m: Mon) -> Dictionary:
	if not mem.has(m.uid):
		mem[m.uid] = {}
	var t0 := Time.get_ticks_usec()
	if partner_ai == null:
		partner_ai = PartnerAI.new(self)
	AI.partner_hook = Callable(partner_ai, "decide")
	var r := AI.decide(m, fs, mem[m.uid])
	AI.partner_hook = Callable()
	if perf_log:
		pacc("ai", Time.get_ticks_usec() - t0)
	return r

func end_of_turn() -> void:
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_process_frames()
	await end_of_turn_i()
	if perf_log and Engine.get_process_frames() == f0:
		pacc("end_of_turn", Time.get_ticks_usec() - t0)

func end_of_turn_i() -> void:
	fs.turn += 1
	dx_turns += 1
	SpecialMoves.tick(self)
	EosItems.end_of_turn(self)
	await AbilityFx.end_of_turn(self)
	if result_sent:
		return
	await HeldItems.end_of_turn(self)
	if result_sent:
		return
	var L := fs.leader
	# belly: only the leader's drops in Red
	var starving := false
	if bool(Game.settings.get("hunger", true)):
		var bt: Dictionary = TurnRules.belly_tick(L, belly_state)
		belly = float(bt.belly)
		if str(bt.message) != "":
			_msg(str(bt.message))
		if int(bt.damage) > 0:
			starving = true
			_hurt(L, int(bt.damage), null, false)
			if L.hp <= 0:
				await faint(L, null)
				return
	else:
		belly = belly_max
		belly_state.belly = belly
	for m in fs.mons.duplicate():
		if m.hp <= 0:
			continue
		TurnRules.regen(m, starving and m.is_leader, fs.weather)
		for s in TurnRules.tick_status(m, fs):
			_msg(s)
		if m.hp <= 0:
			await faint(m, null)
			if result_sent:
				return
	# wild spawns (Red: every 36 turns, room tile away from the leader)
	spawn_timer += 1
	if shop_stole and shop:
		if spawn_timer >= KecleonShop.THIEF_SPAWN_TURNS:     # gKecleonSpawnIntervalFrames: Kecleon after the thief
			spawn_timer = 0
			shop.thief_spawn()
	elif spawn_timer >= int(TurnRules.spawn_interval(fs)):
		spawn_timer = 0
		if TurnRules.can_spawn(fs) and not BossScene.is_floorwide(fixed_no) and eos_arena.is_empty():
			var p := TurnRules.spawn_position(fs)
			if p.x >= 0:
				_spawn_wild(p)
	# turn limit: Red's wind
	var wt: Dictionary = TurnRules.wind_tick(wind_state)
	if str(wt.message) != "":
		_msg(str(wt.message))
	# tests: warp ahead when a floor drags on (the user allowed the story test to skip slow floors)
	if test_invincible and _test_floor_t0 > 0 and Time.get_ticks_msec() - _test_floor_t0 > 75000 and not _test_story_floor():
		print("  TEST warp: floor %d took over 75 s" % (floor_i + 1))
		_test_floor_t0 = 0
		await next_floor()
		return
	if bool(wt.blown_out) and test_invincible:
		print("  TEST wind blow-out ignored")
		wind_state = {}
		_test_blowouts += 1
		if _test_blowouts >= 2 and eos_arena.is_empty() and boss == null:
			print("  TEST stuck on floor %d: skipping to the next floor" % (floor_i + 1))
			_test_blowouts = 0
			await next_floor()
			return
	elif bool(wt.blown_out):
		await get_tree().create_timer(1.0).timeout
		exit_summary = LastOuting.summary("blown_out", fs.leader)
		_end("defeated")
		return
	_reveal()
	_update_hud()

# ================================================================= actions
func execute(m: Mon, a: Dictionary) -> bool:
	match a.get("type", "wait"):
		"move":
			return await do_move(m, int(a.dir), bool(a.get("swap", false)))
		"attack":
			var d := int(a.get("dir", m.facing))
			if d < 0:
				d = m.facing
			var chain: Array = a.get("chain", [])
			if chain.size() > 1:
				await use_linked_chain(m, chain, d)
			else:
				await do_attack(m, str(a.get("move", "")), d)
			return true
		"wait":
			return true
		"throw":      # AI / Autoplay: a held item (allies, wild) or a Toolbox slot (the leader)
			var id := ""
			if a.get("held", false):
				id = m.held
				m.held = ""
			elif int(a.get("bag", -1)) >= 0 and int(a.bag) < Game.bag.size():
				id = str(Game.bag[int(a.bag)].id)
				_take_bag(int(a.bag))
			if id == "":
				return true
			m.facing = int(a.get("dir", m.facing))
			await _flush_walks()
			await _throw_id(m, id, a.get("target", Vector2i(-1, -1)))
			return true
		"item":
			if fs.items.has(m.pos):
				_mon_try_pick_up(m)      # teammates: Poké to the money, items to the Toolbox (held only when it's full)
			return true
	return true

func do_move(m: Mon, d: int, swap := false) -> bool:
	m.facing = d
	if int(m.status.get("shadow_hold", 0)) > 0:
		if m.is_leader:
			_msg("%s is immobilized and can't move!" % _nm(m))
		return false
	if not fs.can_step(m.pos, d, m):
		if m.visual:
			m.visual.queue_redraw()
		return false
	var to: Vector2i = m.pos + DB.DIRS[d]
	var o := fs.mon_at(to)
	if o:
		if o.get_meta("story_npc", false) or o.get_meta("cs_hidden", false):
			return false
		if m.is_leader and Missions.is_client(o):
			await Missions.on_talk(self, o)
			return false
		if m.is_leader and bool(o.get_meta("shopkeeper", false)) and shop:
			await shop.talk(o)                       # Red: walking into Kecleon talks to it
			return false
		if (m.is_leader and o.is_team()) or (swap and o.is_team() and not o.is_leader and not Missions.is_client(o)):
			# swap places with a teammate (partners too, with the smarter partner AI)
			var oold := o.pos
			o.pos = m.pos
			AI.on_moved(o, oold)
			o.facing = (d + 4) % 8
			_queue_walk(o)
		else:
			return false
	var old := m.pos
	m.pos = to
	AI.on_moved(m, old)
	_queue_walk(m)
	_tile_effects(m)
	if m.held == "gogglespecs":
		HeldItems.goggles_reveal(self, m)
	if not m.is_leader and fs.items.has(m.pos):
		_mon_try_pick_up(m)
	if m.is_leader:
		_flush_walks_nowait()       # the leader's step plays together with everyone else's this turn
		await _after_leader_step()
	return true

## MonTryPickUpItem (dungeon_ai_items.c): every Pokémon but the leader picks up what it walks onto.
## Teammates put Poké into the team's money and other items into the Toolbox (stacking first), or hold it
## when the Toolbox is full; wild Pokémon can only hold it. Shop items and rescue targets are left alone.
func _mon_try_pick_up(m: Mon) -> void:
	var it: Dictionary = fs.items[m.pos]
	if int(it.get("price", 0)) > 0 or m.side == "client" or m.get_meta("client", false) or m.get_meta("story_npc", false):
		return
	var seen := fs.can_see(fs.leader, m.pos)
	var nm := _nm(m)
	var iname := "[color=#ffdc4a]%s[/color]" % DB.item_name(str(it.id))
	if m.is_team() and str(it.id) == "poke":
		Game.money += int(it.get("n", 0))
		fs.items.erase(m.pos)
		Audio.sfx("coin")
		if seen:
			_msg("%s picked up %d Poké." % [nm, int(it.get("n", 0))])
	elif m.is_team() and str(it.id) != "poke" and Game.bag_add(str(it.id), int(it.get("n", 1))):
		fs.items.erase(m.pos)
		if seen:
			Audio.sfx("pickup")
			_msg("%s picked up the %s and put it in the Toolbox." % [nm, iname])
	elif m.held == "" and str(it.id) != "poke" and not is_temp(m):
		m.held = str(it.id)
		fs.items.erase(m.pos)
		if seen:
			Audio.sfx("pickup")
			_msg("%s picked up the %s." % [nm, iname])
	elif seen and m.is_team():
		_msg("%s stepped on the %s." % [nm, iname])
	obj_layer.queue_redraw()

func _place_team_slots(gen: Dictionary) -> void:
	var slots: Dictionary = gen.get("team_slots", {})
	if slots.is_empty():
		return
	var order: Array = []
	if fs.leader:
		order.append(fs.leader)
	for m in fs.team():
		if not m in order:
			order.append(m)       # the partner comes right after the leader in the team list
	for i in order.size():
		var m: Mon = order[i]
		if not slots.has(i):
			continue
		var q: Vector2i = slots[i]
		var o := fs.mon_at(q)
		if o != null and o != m:
			if not o.is_team():
				continue
			o.pos = m.pos            # a teammate is on it: swap
			if o.visual:
				o.visual.position = _px(o.pos)
		m.pos = q
		if m.visual:
			m.visual.position = _px(q)
			_walkers.erase(m.visual)

func _queue_walk(m: Mon) -> void:
	if m.visual:
		_pending_walks.append(m)

func _flush_walks_nowait() -> void:
	_start_walks()

## Waits for the walking sprites to arrive. 'early': return once the leader has less than about a frame
## left, so a held direction chains straight into the next step.
func _await_lead_walk(early := false) -> void:
	var guard := 0
	while not _walkers.is_empty() and guard < 240:
		# the others may still have a frame or two left: their motion simply carries on. Measured in real
		# frames, so a device that dips below 60 fps doesn't finish each step and stand still for a frame.
		var fr := maxf(1.0 / 60.0, get_process_delta_time()) * 1.1
		if early and fs and fs.leader and fs.leader.visual and _walk_left(fs.leader.visual) <= fr \
				and _others_left() <= 2.0 * fr:
			return
		await get_tree().process_frame
		guard += 1

func _others_left() -> float:
	var mx := 0.0
	for vis in _walkers:
		if is_instance_valid(vis):
			mx = maxf(mx, _walk_left(vis))
	return mx

func _flush_walks() -> void:
	_start_walks()
	await _await_lead_walk()

func _start_walks() -> void:
	if _pending_walks.is_empty():
		return
	var t := RUN_TIME if _running else WALK_TIME
	for m in _pending_walks:
		if m.visual == null or not is_instance_valid(m.visual):
			continue
		var to := _px(m.pos)
		if m.visual.position.distance_to(to) > T * 3:
			m.visual.position = to
			_walkers.erase(m.visual)
			continue
		if m.visual.anim != "Walk":
			m.visual.play("Walk")
		# per-step speed: a diagonal step takes as long as a straight one, like Red
		_walkers[m.visual] = {"to": to, "v": maxf(1.0, m.visual.position.distance_to(to)) / t}
	_pending_walks.clear()

var house_seen := false

func _after_leader_step() -> void:
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_process_frames()
	await _after_leader_step_i()
	if shop and not result_sent:
		await shop.on_leader_step()              # Kecleon Shop: welcome / pay when stepping out / thief
	if perf_log and Engine.get_process_frames() == f0:
		pacc("after_leader_step", Time.get_ticks_usec() - t0)

func _after_leader_step_i() -> void:
	var L := fs.leader
	# Monster House: entering its room switches to Red's Monster House theme for the rest of the floor
	if not house_seen and fs.monster_house_room >= 0 and fs.room_at(L.pos) == fs.monster_house_room:
		house_seen = true
		_msg("It's a [color=#ff8070]Monster House[/color]!")
		Audio.play_music("128")
	# items (the Auto-pickup option can leave some on the ground: Ground menu picks them up)
	if fs.items.has(L.pos) and int(fs.items[L.pos].get("price", 0)) == 0 and qol and not qol.auto_pickup(fs.items[L.pos]):
		_msg("There's the [color=#ffdc4a]%s[/color] underfoot." % DB.item_name(fs.items[L.pos].id))
	elif fs.items.has(L.pos):
		var it: Dictionary = fs.items[L.pos]
		if it.id == "poke":
			it.n = IQSky.money_pickup(L, int(it.n))
			Game.money += int(it.n)
			fs.items.erase(L.pos)
			Audio.sfx("coin")
			_msg("Picked up %d Poké." % int(it.n))
		elif int(it.get("price", 0)) > 0:
			_msg("That's for sale.")
		elif test_want != "" and str(it.id) == test_want and Game.bag.size() >= Game.BAG_MAX and Game.bag.pop_back() == null:
			pass
		elif Game.bag_add(it.id, int(it.n)):
			if test_want != "":
				print("  TEST picked up ", it.id)
			fs.items.erase(L.pos)
			Audio.sfx("pickup")
			_msg("Picked up the [color=#ffdc4a]%s[/color]." % DB.item_name(it.id))
		else:
			_msg("The Toolbox is full.")
		obj_layer.queue_redraw()
	# traps
	var fs0 := fs
	if fs.traps.has(L.pos):
		await _await_lead_walk()
		# the walk takes a few frames: the floor may have changed or the trap gone meanwhile
		if fs == fs0 and not result_sent and fs.traps.has(L.pos):
			await trigger_trap(L, L.pos)
	# stairs
	if fs == fs0 and not result_sent and L.pos == fs.stairs:
		await _await_lead_walk()
		if fs == fs0 and not result_sent:
			await stairs_prompt()
	if fs == fs0 and not result_sent:
		await Missions.on_leader_step(self)

func trigger_trap(m: Mon, p: Vector2i) -> void:
	if not fs.traps.has(p):
		return
	if IQSky.try_bust_trap(self, m, p):
		return
	var t: Dictionary = fs.traps[p]
	t.seen = true
	if HeldItems.blocks_trap(m) and str(t.id) != "wonder":     # Red: the Trap Scarf doesn't stop a Wonder Tile
		_msg("%s's Trap Scarf kept the trap from going off!" % _nm(m))
		obj_layer.queue_redraw()
		return
	obj_layer.queue_redraw()
	match t.id:
		"wonder":
			# HandleWonderTile -> sub_8079E34: stages and multipliers back to normal; the tile stays (Red)
			var changed := false
			for k in m.stages:
				if int(m.stages[k]) != 10:
					m.stages[k] = 10
					changed = true
			var sm = m.get("stat_mult")
			if sm is Dictionary:
				for k in sm.keys():
					if int(sm[k]) != 256:
						sm[k] = 256
						changed = true
			_msg("%s stepped on a Wonder Tile!" % _nm(m))
			_msg(("%s's stats returned to normal." if changed else "%s's stats appear unchanged.") % _nm(m))
		"slumber":
			m.status.sleep = TurnRules.red_turns("sleep", fs.rng, m, 4)
			_msg("%s stepped on a Slumber Trap and fell asleep!" % _nm(m))
		"poison":
			m.status.poison = TurnRules.red_turns("poison", fs.rng, m, 20)
			_msg("%s was poisoned by a Poison Trap!" % _nm(m))
		"slow":
			m.status.slow = TurnRules.red_turns("slow", fs.rng, m, 8)
			_msg("%s stepped on a Slow Trap and slowed down!" % _nm(m))
		"warp":
			var q := _random_floor_tile()
			m.pos = q
			if m.visual:
				m.visual.position = _px(q)
				_walkers.erase(m.visual)
			_msg("%s was warped by a Warp Trap!" % _nm(m))
		"pitfall":
			_msg("%s fell into a pitfall!" % _nm(m))
			if m.is_leader:
				_hurt(m, maxi(1, m.max_hp / 4), null, true)
				await get_tree().create_timer(0.6).timeout
				await next_floor()
		"summon":
			_msg("A Summon Trap! Pokémon appeared!")
			for i in 3:
				var q := fs.free_tile_near(p, null, 3)
				if q.x >= 0:
					var w := _spawn_wild(q)
					if w:
						w.visual.position = _px(q)
						_walkers.erase(w.visual)
		"chestnut":
			_hurt(m, 10, null, true)
			_msg("%s was pelted by chestnuts!" % _nm(m))
		"spiked":
			_hurt(m, maxi(1, m.max_hp / 8), null, true)
			_msg("%s stepped on a Spiked Tile!" % _nm(m))
		"ppzero":
			for mv in m.moves:
				if int(mv.pp) > 0:
					mv.pp = 0
					_msg("A PP-Zero Trap! %s's %s lost all its PP!" % [_nm(m), mv.name])
					break
		_:
			_msg("%s stepped on a %s!" % [_nm(m), str(t.id).capitalize() + " Trap"])
	if m.hp <= 0:
		await faint(m, null)

func _random_floor_tile() -> Vector2i:
	for i in 200:
		var p := Vector2i(rng.randi_range(1, fs.w - 2), rng.randi_range(1, fs.h - 2))
		if fs.terrain_at(p) == 1 and fs.mon_at(p) == null:
			return p
	return fs.leader.pos

# ================================================================= attacks
func do_attack(m: Mon, move_name: String, d: int, announce := true) -> void:
	m.facing = d
	var mv: Dictionary
	var slot: Dictionary = {}
	if move_name == "":
		mv = DB.moves.get("Regular Attack", {"name": "Attack", "t": "None", "p": 1, "a1": 125, "a2": 125, "c": "P", "r": "front", "hits": 1, "crit": 12})
	else:
		mv = DB.moves.get(move_name, {})
		slot = m.move_by_name(move_name)
		if mv.is_empty():
			return
		if not slot.is_empty():
			if int(slot.get("disabled", 0)) > 0:
				_msg("%s can't use the disabled %s!" % [_nm(m), move_name])
				return
			if int(slot.pp) <= 0:
				_msg("There's no PP left for %s!" % move_name)
				return
			if not is_temp(m) and not (EosItems.has(m, "free_pp") and fs.rng.randi_range(0, 99) < 20):   # DX: temps use no PP
				slot.pp = maxi(0, int(slot.pp) - IQSky.pp_cost(m, move_name, fs.rng, self))
	if announce:
		m.last_move = move_name
	if move_name != "" and announce:
		_msg("%s used [color=#7fe0ff]%s[/color]!" % [_nm(m), mv.get("name", move_name)])
	# two-turn moves (SetChargeStatusTarget): the first use only charges; the next use attacks in front
	if move_name != "" and IQ.is_charge_move(move_name):
		if str(m.status.get("charge_move", "")) != move_name and not IQSky.skips_charge(m, move_name) \
				and not (move_name == "Solarbeam" and str(fs.weather) == "sunny"):
			m.status.charge_move = move_name
			m.status.charging = 2
			_msg(CHARGE_TEXT.get(move_name, "%s began charging power!") % _nm(m))
			if m.visual:
				m.visual.play("Charge")
			await _pause(0.25)
			_update_hud()
			return
		m.status.charge_move = ""
		m.status.charging = 0
		if str(mv.get("r", "")) in ["user", ""]:
			mv = mv.duplicate()
			mv.r = "front"
	var anim := "Attack"
	if mv.get("c", "P") != "P":
		anim = "Shoot" if mv.get("r", "front") in ["line", "room", "room_all", "floor_all"] else "Charge"
	if mv.get("r", "") in ["user", "team_room", "team_floor"]:
		anim = "Charge"
	if m.visual:
		m.visual.play(anim)
		if anim == "Attack":
			var dv: Vector2 = Vector2(DB.DIRS[d]) * 6.0
			var tw := create_tween()
			tw.tween_property(m.visual, "bob", dv, 0.07)
			tw.tween_property(m.visual, "bob", Vector2.ZERO, 0.1)
	await _pause(0.18)
	var targets := targets_for(m, mv, d)
	if m.is_leader:                  # the foe the leader is fighting (the smarter partner AI helps with it)
		for t_l in targets:
			if t_l != m and fs.is_foe(m, t_l):
				m.set_meta("last_target_uid", t_l.uid)
				break
	if move_name in AbilityFx.EXPLOSION_MOVES and AbilityFx.damp_on_floor(fs):
		_msg("Damp prevents explosions!")
		return
	for t_sp in targets.duplicate():
		if AbilityFx.soundproof(t_sp, move_name):
			_msg("%s's Soundproof suppressed the sound move!" % _nm(t_sp))
			targets.erase(t_sp)
	if not slot.is_empty() and announce and not is_temp(m):
		slot.pp = maxi(0, int(slot.pp) - AbilityFx.pressure_extra(m, targets, fs))    # Pressure
	if move_name != "" and not _quiet:
		await MoveFx.play(self, m, move_name, mv, d, targets)
	var hits := maxi(1, int(mv.get("hits", 1)))
	if int(mv.get("hits", 1)) == 0:
		hits = AbilityFx.multi_hits(m, fs.rng)          # 2-5 hits (Skill Link: 5)
	if move_name == "":
		hits = IQSky.regular_attack_hits(m, fs.rng)
	var pbond := move_name != "" and hits == 1 and AbilityFx.has(m, "parental bond")
	if pbond:
		hits = 2                                         # Parental Bond: a second strike at 1/4 power
	var mt: Array = AbilityFx.move_type(m, move_name, str(mv.get("t", "None")))
	if move_name != "":
		AbilityFx.protean(self, m, str(mt[0]))
	if mv.get("c", "P") == "X" or move_name in SpecialMoves.FORCE_STATUS:
		await _status_move(m, mv, targets)
		return
	var primal := Awaken.primal_block(self, str(mt[0])) if move_name != "" else ""
	if primal != "":
		_msg(primal)
		return
	if targets.is_empty():
		if move_name == "":
			Audio.sfx("miss")
		else:
			_msg("The move missed!" if mv.get("r", "front") != "user" else "")
		return
	for h in hits:
		if pbond:
			m.set_meta("pb_hit", h)
		for t0 in targets:
			var t: Mon = t0
			if t.hp <= 0:
				continue
			t = HeldItems.pass_scarf(self, m, t, mv)
			t = IQSky.before_hit(self, m, t)
			if t == null:
				continue
			var ctx := {"weather": fs.weather, "is_regular_attack": move_name == "", "att_is_team": m.is_team(), "move_type": str(mt[0])}
			if not Combat.accuracy_hits(m, t, mv, fs.rng, ctx):
				Audio.sfx("miss" if t.is_team() else "missfoe")
				red_number(t, 9999)
				_msg("%s avoided the attack!" % _nm(t) if move_name != "" else "The attack missed %s." % _nm(t))
				IQSky.after_miss(self, m, t)
				continue
			var res: Dictionary = Combat.calc_damage(m, t, mv, fs.rng, ctx)
			var fixed := SpecialMoves.fixed_damage(self, m, t, move_name)
			if fixed >= 0:
				res = {"dmg": fixed, "physical": true}
				if fixed == 0:
					SpecialMoves.after_hit(self, m, t, move_name)
					continue
			if bool(res.get("missed", false)):
				Audio.sfx("miss" if t.is_team() else "missfoe")
				red_number(t, 9999)
				_msg("%s avoided the attack!" % _nm(t))
				IQSky.after_miss(self, m, t)
				continue
			for s in res.get("msg", []):
				if str(s) != "":
					_msg(str(s))
			if int(res.get("heal", 0)) > 0:
				t.hp = mini(t.max_hp, t.hp + int(res.heal))
				_msg("%s recovered %d HP!" % [_nm(t), int(res.heal)])
				continue
			var dmg := int(res.get("dmg", 0))
			if dmg > 0 and fixed < 0 and AbilityFx.absorbs(self, t, str(mt[0]), dmg):
				continue
			var guard := EosItems.type_guard(t, str(mt[0])) if fixed < 0 else ""
			if guard == "absorb" and dmg > 0:
				t.hp = mini(t.max_hp, t.hp + dmg)
				_msg("%s's item absorbed the attack and restored %d HP!" % [_nm(t), dmg])
				continue
			elif guard == "immune":
				_msg("%s's item protected it from the attack!" % _nm(t))
				continue
			if fixed < 0 and dmg > 0:
				dmg = maxi(1, int(round(dmg * EosItems.damage_factor(m, t, bool(res.get("physical", true)), move_name))))
			if fixed < 0:
				dmg = AbilityFx.modify_damage(self, m, t, mv, move_name, str(mt[0]), dmg, res, float(mt[1]))
			if AbilityFx.sturdy(t, dmg):
				_msg("%s's Sturdy blocked the one-hit KO!" % _nm(t))
				continue
			if dmg <= 0 or t == m:
				continue
			if int(t.status.get("sleep", 0)) >= 0x7F:
				t.status.sleep = 0      # a napping wild Pokémon wakes up when hit
			if t.has_status("sleep") and false:
				pass
			_hurt(t, dmg, m, true, bool(res.get("crit", false)), int(res.get("eff", 2)))
			_msg("%s took [color=#ffdc4a]%d[/color] damage!" % [_nm(t), dmg])
			if t.hp > 0:
				await IQSky.after_hit(self, m, t, dmg, bool(res.get("physical", true)))
			# drain / recoil
			if mv.has("drain") and m.hp > 0:
				var heal := maxi(1, int(dmg * float(mv.drain) * (1.5 if EosItems.has(m, "drain_boost") else 1.0)))
				m.hp = mini(m.max_hp, m.hp + heal)
				_msg("%s absorbed %d HP!" % [_nm(m), heal])
			if mv.has("recoil") and m.hp > 0 and not AbilityFx.no_recoil(m):
				_hurt(m, maxi(1, int(dmg * float(mv.recoil))), null, false)
				_msg("%s is hit with recoil!" % _nm(m))
			SpecialMoves.after_hit(self, m, t, move_name)
			await AbilityFx.after_damaged(self, m, t, dmg, bool(res.get("physical", true)), str(mt[0]))
			await AbilityFx.after_hit_gen4(self, m, t, move_name, dmg, str(mt[0]))
			await EosItems.after_damaged(self, m, t, dmg, bool(res.get("physical", true)), move_name)
			if bool(res.get("crit", false)):
				AbilityFx.on_crit_taken(self, t)
			if t.hp <= 0:
				await faint(t, m)
			else:
				_secondary(m, t, mv)
			if m.hp <= 0:
				await faint(m, null)
				return
		await _pause(0.12)
	m.remove_meta("pb_hit")
	_update_hud()

## Red's charging-turn lines (dungeon_strings.c); Skull Bash and Focus Punch use the generic one.
const CHARGE_TEXT := {"Razor Wind": "%s readies Razor Wind!", "Sky Attack": "%s is readying Sky Attack!",
	"Solarbeam": "%s is readying Solarbeam!", "Fly": "%s flew up high!", "Bounce": "%s bounced up!",
	"Dive": "%s dove underwater!", "Dig": "%s burrowed underground!"}

func targets_for(m: Mon, mv: Dictionary, d: int) -> Array:
	var r: String = mv.get("r", "front")
	var out: Array = []
	var dv: Vector2i = DB.DIRS[d]
	match r:
		"front":
			if fs.can_attack_dir(m.pos, d):
				var o := fs.mon_at(m.pos + dv)
				if o:
					out.append(o)
		"front_corners":
			var o := fs.mon_at(m.pos + dv)
			if o and not fs.is_wall(m.pos + dv):
				out.append(o)
		"two_tiles":
			for i in [1, 2]:
				var p: Vector2i = m.pos + dv * i
				if fs.is_wall(p):
					break
				var o := fs.mon_at(p)
				if o:
					out.append(o)
					break
		"line":
			var p: Vector2i = m.pos
			for i in LINE_RANGE:
				p += dv
				if fs.is_wall(p):
					break
				var o := fs.mon_at(p)
				if o and IQSky.passes_through(m, o):
					continue
				if o:
					if fs.is_foe(m, o):
						out.append(o)
					break
		"room", "room_all", "floor_all", "floor_foes":
			for o in fs.mons:
				if o == m or o.hp <= 0:
					continue
				if r != "room_all" and not fs.is_foe(m, o):
					continue
				if r.begins_with("floor") or _same_area(m, o):
					out.append(o)
		"adjacent", "front_spread":
			for k in 8:
				if r == "front_spread" and not (k == d or k == (d + 1) % 8 or k == (d + 7) % 8):
					continue
				var o := fs.mon_at(m.pos + DB.DIRS[k])
				if o and fs.is_foe(m, o):
					out.append(o)
		"user", "floor", "special":
			out.append(m)
		"team_room", "team_floor":
			out.append(m)
			for o in fs.allies_of(m):
				if r == "team_floor" or _same_area(m, o):
					out.append(o)
		_:
			var o := fs.mon_at(m.pos + dv)
			if o:
				out.append(o)
	return out

func _same_area(a: Mon, b: Mon) -> bool:
	var ra := fs.room_at(a.pos)
	if ra != 255 and ra == fs.room_at(b.pos):
		return true
	return FloorState.cheb(a.pos, b.pos) <= 2

func _status_move(m: Mon, mv: Dictionary, targets: Array) -> void:
	if str(mv.get("name", "")) == "Bide":
		m.status.bide = 3
		_msg("%s began storing energy!" % _nm(m))        # BideMoveAction (gUnknown_80FAC74)
		_update_hud()
		return
	if str(mv.get("name", "")) in SpecialMoves.SELF_TARGETED or SpecialMoves.WEATHER_MOVES.has(str(mv.get("name", ""))):
		await SpecialMoves.run(self, m, mv, targets)
		_update_hud()
		return
	var hit_targets: Array = []
	var mvn: String = str(mv.get("name", ""))
	for t0 in targets.duplicate():
		if AbilityFx.prankster_fails(m, t0):
			_msg("Dark types are immune to Prankster!")
			targets.erase(t0)
		elif AbilityFx.powder_immune(t0, mvn):
			_msg("%s's Overcoat blocked the powder!" % _nm(t0))
			targets.erase(t0)
		elif AbilityFx.bounce(t0, m):
			_msg("%s's Magic Bounce reflected the move!" % _nm(t0))
			targets[targets.find(t0)] = m
	for t in targets:
		if t == m or Combat.accuracy_hits(m, t, mv, fs.rng, {"weather": fs.weather}):
			hit_targets.append(t)
		else:
			_msg("%s avoided it!" % _nm(t))
	if not targets.is_empty() and await SpecialMoves.run_on_targets(self, m, mv, hit_targets if not hit_targets.is_empty() else []):
		_update_hud()
		return
	if targets.is_empty():
		_msg("But nothing happened.")
		return
	for t in targets:
		if not hit_targets.has(t):
			continue
		if false:
			_msg("%s avoided it!" % _nm(t))
			continue
		var did := false
		if mv.has("heal"):
			var amt := maxi(1, int(t.max_hp * float(mv.heal)))
			amt = IQSky.heal_amount(m, amt)
			t.hp = mini(t.max_hp, t.hp + amt)
			_msg("%s recovered %d HP!" % [_nm(t), amt])
			Audio.sfx("heal")
			did = true
			if mv.name == "Rest":
				t.status.sleep = 3
		if mv.has("eff"):
			did = _apply_effs(m, t, mv.eff, true) or did
			if AbilityFx.has(m, "prankster"):           # Remixed: status moves work twice
				_apply_effs(m, t, mv.eff, true)
		if not did:
			_msg("Nothing happened to %s." % _nm(t))
	_update_hud()

func _secondary(m: Mon, t: Mon, mv: Dictionary) -> void:
	if not mv.has("eff"):
		return
	var e = mv.eff
	var ch := float(e.get("ch", 1.0)) if e is Dictionary else 1.0
	ch = AbilityFx.secondary_chance(m, ch)           # Serene Grace
	if AbilityFx.has(m, "sheer force"):              # Remixed: more power, no added effects
		return
	if AbilityFx.blocks_secondary(m, t):             # Shield Dust
		return
	if fs.rng.randf() < ch:
		_apply_effs(m, t, e, false)

const STATUS_NAMES := {"sleep": "fell asleep", "para": "is paralyzed", "burn": "was burned", "poison": "was poisoned", "badpoison": "was badly poisoned",
	"confused": "became confused", "frozen": "was frozen solid", "slow": "slowed down", "cringe": "cringed", "infatuated": "fell in love", "petrified": "was petrified"}

## Some moves list several effects (Array of effect dicts).
func _apply_effs(m: Mon, t: Mon, e, guaranteed: bool) -> bool:
	if e is Array:
		var any := false
		for x in e:
			if x is Dictionary:
				any = _apply_eff(m, t, x, guaranteed) or any
		return any
	if e is Dictionary:
		return _apply_eff(m, t, e, guaranteed)
	return false

func _apply_eff(m: Mon, t: Mon, e: Dictionary, guaranteed: bool) -> bool:
	if e.has("status"):
		var s: String = e.status
		var key: String = {"confuse": "confused", "infatuate": "infatuated", "petrify": "petrified", "freeze": "frozen", "toxic": "badpoison"}.get(s, s)
		var why := HeldItems.blocks_status(t, key)
		if why == "":
			why = AbilityFx.blocks_status_gen4(self, t, key)
		if why != "":
			if guaranteed:
				_msg(why % _nm(t))
			return false
		if t.has_status(key):
			if guaranteed:
				_msg("%s is already affected." % _nm(t))
			return false
		var turns := 0
		turns = int(TurnRules.status_turns(key, fs.rng, t))
		if turns <= 0:
			turns = {"sleep": fs.rng.randi_range(3, 6), "para": 20, "burn": 20, "poison": 20, "badpoison": 20, "confused": fs.rng.randi_range(7, 12),
				"frozen": fs.rng.randi_range(3, 5), "slow": fs.rng.randi_range(5, 8), "cringe": 1, "infatuated": 10, "petrified": 20}.get(key, 5)
		if key == "sleep":
			turns = AbilityFx.sleep_turns(t, turns)
		t.status[key] = turns
		_msg("%s %s!" % [_nm(t), STATUS_NAMES.get(key, "was affected")])
		AbilityFx.synchronize(self, t, key, turns)
		if t.visual and key == "sleep":
			t.visual.play("Idle")
		return true
	if e.has("tgt") or e.has("self"):
		var who := t if e.has("tgt") else m
		var k: String = e.get("tgt", e.get("self", "atk"))
		var stv := AbilityFx.stat_change(who, int(e.get("st", -1)))      # Simple / Contrary
		if stv < 0 and who != m and AbilityFx.flower_veil(fs, who):
			_msg("%s is protected by Flower Veil!" % _nm(who))
			return false
		if stv < 0 and who != m and AbilityFx.blocks_stat_drop(who, k) != "":
			_msg(AbilityFx.blocks_stat_drop(who, k) % _nm(who))
			return false
		if stv < 0 and HeldItems.blocks_stat_drop(who, k):
			_msg("%s's %s isn't lowered thanks to its Twist Band!" % [_nm(who), _stat_name(k)])
			return false
		var old := int(who.stages.get(k, 10))
		var nv := clampi(old + stv, 0, 20)
		if nv == old:
			_msg("%s's %s won't go %s!" % [_nm(who), _stat_name(k), "higher" if stv > 0 else "lower"])
			return false
		who.stages[k] = nv
		_msg("%s's %s %s!" % [_nm(who), _stat_name(k), ("rose" if stv == 1 else "rose sharply") if stv > 0 else ("fell" if stv == -1 else "fell harshly")])
		if stv < 0:
			AbilityFx.after_stat_drop(self, m, who)      # Defiant / Competitive
		return true
	if e.has("fast"):
		var who2 := m if mv_targets_self(e) else t
		who2.status.fast = int(e.fast)
		_msg("%s sped up!" % _nm(who2))
		return true
	return false

func mv_targets_self(_e: Dictionary) -> bool:
	return true

func _stat_name(k: String) -> String:
	return {"atk": "Attack", "def": "Defense", "spa": "Sp. Atk", "spd": "Sp. Def", "acc": "accuracy", "eva": "evasion"}.get(k, k)

func _hurt(t: Mon, dmg: int, by: Mon, anim := true, crit := false, eff := 2) -> void:
	if dmg >= t.hp and t.hp > 1 and by != null and by != t and EosItems.endure(t, fs.rng):
		dmg = t.hp - 1
		_msg("%s held on thanks to its item!" % _nm(t))
	t.hp = maxi(0, t.hp - dmg)
	HeldItems.on_damaged(self, t, dmg)
	if test_invincible and t.hp == 0 and fs.team().has(t):
		t.hp = t.max_hp      # tests only: the team can't faint
	if t.visual:
		if anim:
			t.visual.play("Hurt")
		red_number(t, -dmg)
	if anim:
		Audio.sfx("hitbig" if eff == 3 or crit else ("hitsmall" if eff == 1 else "hit"))
	if t.is_leader:
		_update_hud()

var _popup_layer: CanvasLayer

## Damage numbers / "!" marks: drawn in screen space at Red's font scale (2x, whole pixels) so they stay
## sharp at any map zoom, then follow the Pokémon as it drifts upward.
func _popup(at: Vector2, txt: String, col: Color, big := false) -> void:
	if _popup_layer == null or not is_instance_valid(_popup_layer):
		_popup_layer = CanvasLayer.new()
		_popup_layer.layer = 4
		add_child(_popup_layer)
	var l := Label.new()
	l.theme = UITheme.theme()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", UITheme.FONT_SIZE if not big else UITheme.FONT_SIZE + UITheme.PX * 2)
	l.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_popup_layer.add_child(l)
	var scr: Vector2 = fx_layer.get_global_transform_with_canvas() * (at + Vector2(0, -22))
	l.reset_size()
	l.position = (scr - l.size / 2.0).round()
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 18, 0.55)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.35)
	tw.tween_callback(l.queue_free)

func faint(t: Mon, killer: Mon) -> void:
	if test_invincible and t.is_team():
		t.hp = t.max_hp      # tests only: the team can't faint
		return
	if not fs.mons.has(t) or t.get_meta("fainting", false):
		return
	t.set_meta("fainting", true)
	# Red (dungeon_damage.c): Exp. goes to the team present at the KO (AddExpPoints) and is announced at the
	# end of the turn, after a join sequence; only the team leader's KO can recruit.
	var exp_team: Array = fs.team().duplicate() if (not t.is_team() and killer and killer.is_team()) else []
	if not t.is_team() and killer and killer.is_team() and killer.hp > 0 and (killer.is_leader or not RED_LEADER_RECRUITS):
		if await try_recruit(killer, t):
			t.set_meta("fainting", false)
			if boss:
				await boss.on_faint(t, true)
			await _give_ko_exp(exp_team, t)
			return
	if t.is_team() and (t.is_leader or t.get_meta("story", false)) and exit_summary.is_empty():
		exit_summary = _faint_summary(t, killer)
	# Reviver Seed: one the Pokémon holds is used at once; one in the Toolbox revives the leader at once,
	# and for an ally the game asks first (Team item prompts on) -- Off: used at once, as before
	if t.is_team() and not t.get_meta("escort", false) and not Missions.is_client(t):
		var seed_i := -2
		if t.held == "possessorb" and t.is_leader:
			# Possess Orb (held by the leader): a teammate next to it faints in its place
			for o in fs.team():
				if o != t and o.hp > 0 and FloorState.cheb(o.pos, t.pos) <= 1 and not o.get_meta("story", false):
					t.held = ""
					t.hp = t.max_hp
					t.set_meta("fainting", false)
					_msg("%s possessed %s and survived!" % [_nm(t), _nm(o)])
					exit_summary = {}
					o.hp = 0
					await faint(o, killer)
					_update_hud()
					return
		if t.held in REVIVERS or t.held == "reviverorb":
			seed_i = -1
		else:
			for i in Game.bag.size():
				if str(Game.bag[i].id) in REVIVERS and not Game.bag[i].get("sticky", false):
					seed_i = i
					break
			if seed_i >= 0 and not t.is_leader and bool(QOL.opt("qol_itemask")) and not auto_answer:
				var nm: String = DB.item_name(str(Game.bag[seed_i].id))
				if await TeamScreens.ask(ui_root, "%s fainted!\nUse a %s on it?" % [t.name, nm], ["Yes", "No"], 0) != 0:
					seed_i = -2
		if seed_i != -2:
			var sid: String = t.held if seed_i == -1 else str(Game.bag[seed_i].id)
			if seed_i == -1:
				t.held = ""
			else:
				_take_bag(seed_i)
			var frac := float(DB.items.get(sid, {}).get("v", 1))
			if frac <= 0.0:
				frac = 1.0
			t.hp = maxi(1, int(t.max_hp * frac))
			for k in ["poison", "badpoison", "burn", "para", "sleep", "confused"]:
				t.status[k] = 0
			if t.is_leader:
				belly = belly_max
			t.set_meta("fainting", false)
			_msg("%s was revived by the %s!" % [_nm(t), DB.item_name(sid)])
			Audio.sfx("heal")
			exit_summary = {}
			_update_hud()
			return
	if not t.get_meta("went_away", false):
		_msg("%s fainted!" % _nm(t))
	AbilityFx.on_faint(self, t, killer)              # Aftermath / Moxie
	EosItems.on_ko(self, t, killer)                  # Amulet Coin and money exclusives
	if t.visual and not (_quiet and not _on_screen(t.pos)):
		# Pokémon with a Faint anim play it to the end, then fade; the others (most of them) hold their Hurt
		# pose and, if they float (Skarmory, Zubat ...), sink down to their shadow first.
		var vis: MonSprite = t.visual
		var has_faint := vis.has_anim("Faint")
		vis.play("Faint", true)
		var tw := create_tween()
		if has_faint:
			tw.tween_property(vis, "fade", 0.0, 0.45).set_delay(maxf(0.25, vis.anim_length("Faint")))
		else:
			var drop := vis.height_above_ground("Faint")
			if drop >= 3.0:
				tw.tween_property(vis, "bob", Vector2(0, drop), 0.4).set_delay(0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(vis, "fade", 0.0, 0.45).set_delay(0.15 if drop >= 3.0 else 0.35)
		await tw.finished
	if t.visual:
		if t.visual:
			t.visual.queue_free()
			t.visual = null
	fs.mons.erase(t)
	if boss and not t.is_team():
		await boss.on_faint(t, false)
	if not eos_arena.is_empty() and t.get_meta("eos_boss", false):
		var left := fs.mons.filter(func(m): return m.get_meta("eos_boss", false) and m.hp > 0)
		if left.is_empty() and not eos_arena.get("_done", false):
			eos_arena["_done"] = true
			if Dialog.auto:
				print("  BOSS floor over (EoS arena %s)" % str(ddata.floors[floor_i].get("eos_fixed", "?")))
			await get_tree().create_timer(0.6 if not Dialog.auto else 0.05).timeout
			await next_floor()
			return
	if t.held != "" and not t.is_team():
		if not fs.items.has(t.pos):
			fs.items[t.pos] = {"id": t.held, "n": 1, "price": 0}
			obj_layer.queue_redraw()
	if killer:
		IQSky.collector_drop(self, killer, t)
	if not t.is_team() and killer and killer.is_team():
		await _give_ko_exp(exp_team, t)
	if t.is_team():
		if t.is_leader or t.get_meta("story", false):
			print("  TEST defeat: ", t.sp, " leader=", t.is_leader)
			await get_tree().create_timer(0.6).timeout
			_end("defeated")

## Red's TryRecruitMonster: recruiter within 1 tile, recruitRate (per 1000) + Friend Bow 100 + level bonus,
## a Friend Area for the species, room on the team (body size), legendaries only once.
const RECRUIT_BY_LEVEL := [[90, 240], [80, 175], [70, 150], [60, 125], [50, 100], [40, 75], [30, 50]]
const LEGEND_ONCE := ["0144", "0145", "0146", "0244", "0243", "0245", "0380", "0381", "0385", "0384", "0386", "0377", "0378", "0379"]
## Story legendaries Red only lets you meet until they join (their fight ends once recruited): Mewtwo, Kyogre,
## Groudon, Lugia, Ho-Oh, Celebi. With shiny hunting they come back, so they also join only once (+ once shiny).
const LEGEND_BOSSES := ["0150", "0382", "0383", "0249", "0250", "0251"]
const MAX_TEAM_BODY := 6

## Chance (per 1000) that recruiter r recruits species of t if it lands the final blow (rate + Friend Bow + IQ + level).
func recruit_rate(r: Mon, t: Mon) -> int:
	var rate := int(DB.species.get(t.sp, {}).get("recruit", 0))
	if r == null:
		return rate
	if r.held == "friendbow":
		rate += 100
	rate += EosItems.recruit_bonus(r, t)                # Golden Mask, Amber Tear, the EoS instruments
	rate += IQSky.recruit_bonus(fs.leader)
	for e in RECRUIT_BY_LEVEL:
		if r.level >= int(e[0]):
			rate += int(e[1])
			break
	return rate

## Red: each legendary joins only once. Shinies: a shiny one may still join when you only have the normal one.
func legend_owned(t: Mon) -> bool:
	if not (t.sp in LEGEND_ONCE or t.sp in LEGEND_BOSSES):
		return false
	var want_shiny := Shiny.is_shiny(t)
	for f in Game.friends + Game.team:
		if str(f.get("sp", "")).substr(0, 4) == t.sp.substr(0, 4) and (not want_shiny or bool(f.get("shiny", false))):
			return true
	return false

## MonCutsceneCompleted (dungeon_cutscene.c): these Pokémon can't join before their story event is done.
const RECRUIT_AFTER := {"0227": "CUTSCENE_FLAG_MT_STEEL_COMPLETE",
	"0023": "CUTSCENE_FLAG_SINISTER_WOODS_COMPLETE", "0094": "CUTSCENE_FLAG_SINISTER_WOODS_COMPLETE", "0308": "CUTSCENE_FLAG_SINISTER_WOODS_COMPLETE",
	"0145": "CUTSCENE_FLAG_MT_THUNDER_PEAK_COMPLETE", "0146": "CUTSCENE_FLAG_MT_BLAZE_PEAK_COMPLETE", "0144": "CUTSCENE_FLAG_FROSTY_GROTTO_COMPLETE",
	"0383": "CUTSCENE_FLAG_MAGMA_CAVERN_PIT_COMPLETE", "0384": "CUTSCENE_FLAG_SKY_TOWER_SUMMIT_COMPLETE", "0150": "CUTSCENE_FLAG_WESTERN_CAVE_COMPLETE",
	"0244": "CUTSCENE_FLAG_FIERY_FIELD_COMPLETE", "0243": "CUTSCENE_FLAG_LIGHTNING_FIELD_COMPLETE", "0245": "CUTSCENE_FLAG_NORTHWIND_FIELD_COMPLETE",
	"0250": "CUTSCENE_FLAG_MT_FARAWAY_COMPLETE", "0056": "CUTSCENE_FLAG_UPROAR_FOREST_COMPLETE",
	"0377": "CUTSCENE_FLAG_REGI_ITEM_OBTAINED", "0378": "CUTSCENE_FLAG_REGI_ITEM_OBTAINED", "0379": "CUTSCENE_FLAG_REGI_ITEM_OBTAINED"}
const NEVER_RECRUIT := ["0380", "0381"]      # IsMonsterRecruitable: Latias and Latios never join

## The checks Red makes before rolling (IsMonsterRecruitable and TryRecruitMonster), without the roll.
func recruit_allowed(t: Mon) -> bool:
	var sp4 := t.sp.substr(0, 4)
	if sp4 in NEVER_RECRUIT:
		return false
	if RECRUIT_AFTER.has(sp4) and not BossScene.get_flag(str(RECRUIT_AFTER[sp4])):
		return false
	if sp4 == "0151":                       # Mew doesn't join while you're out on a friend rescue (DUNGEON_MISSION_OUTONRESCUE)
		for j in Game.jobs:
			if j.has("sos") and str(j.get("state", "")) == "taken" and str(j.get("dungeon", "")) == dkey:
				return false
	return true

## Game Options "Recruiting: DX" (Rescue Team DX): a defeated Pokémon joins for this dungeon only (from up to 2
## tiles, Red's rate, its Friend Area needed as in Red, up to 8 members); at the exit you choose who stays.
const DX_TEAM_MAX := 8
const DX_RANGE := 2

static func dx_recruiting() -> bool:
	return int(QOL.opt("qol_recruit")) == 1

## No recruiting at all until Wigglytuff gives the team its first Friend Areas (story special 0x17: Wild
## Plains and Mist-Rise Forest); after that each species still needs its own Friend Area (Red and DX).
static func recruiting_unlocked() -> bool:
	return not Game.friend_areas.is_empty()

static func is_temp(m: Mon) -> bool:
	return m != null and bool(m.get_meta("temp_recruit", false))

## Smarter partner AI: a foe the leader could recruit with its next hit (low HP, leader in range, allowed,
## room on the team). Partners leave it alone; not while the leader is in trouble.
func recruit_candidate(t: Mon) -> bool:
	if t.is_team() or not t.recruit_ok or not ddata.get("recruit", true) or not recruiting_unlocked():
		return false
	if t.hp * 3 > t.max_hp:
		return false
	var L := fs.leader
	if L == null or L.hp * 4 <= L.max_hp:
		return false
	var dx := dx_recruiting()
	if FloorState.cheb(L.pos, t.pos) > (DX_RANGE if dx else 1) + 1:
		return false
	if not recruit_allowed(t) or legend_owned(t):
		return false
	if int(DB.species.get(t.sp, {}).get("recruit", 0)) == -999 or recruit_rate(L, t) <= 0:
		return false
	if not Services.has_area_for(t.sp):
		return false
	if dx:
		return fs.team().size() < DX_TEAM_MAX
	return fs.team().size() < Services.PARTY_MAX

func try_recruit(r: Mon, t: Mon) -> bool:
	if not ddata.get("recruit", true) or not t.recruit_ok or not recruiting_unlocked():
		return false
	var dx := dx_recruiting()
	if FloorState.cheb(r.pos, t.pos) > (DX_RANGE if dx else 1):
		return false
	if not recruit_allowed(t):
		return false
	if not fs.can_see(t, r.pos):            # CanSeeTarget(target, attacker)
		return false
	var S: Dictionary = DB.species.get(t.sp, {})
	var rate := int(S.get("recruit", 0))
	if rate == -999:
		return false
	if legend_owned(t):
		return false
	if not Services.has_area_for(t.sp):          # Red and DX: only with the species' Friend Area
		return false
	if dx:
		if fs.team().size() >= DX_TEAM_MAX:
			return false
	else:
		var body := 0
		for m in fs.team():
			body += maxi(1, int(DB.species.get(m.sp, {}).get("size", 1)))
		if fs.team().size() >= Services.PARTY_MAX or body + maxi(1, int(S.get("size", 1))) > MAX_TEAM_BODY:
			return false
	if r.held == "friendbow":
		rate += 100
	rate += EosItems.recruit_bonus(r, t)                # Golden Mask, Amber Tear, the EoS instruments
	rate += IQSky.recruit_bonus(fs.leader)
	for e in RECRUIT_BY_LEVEL:
		if r.level >= int(e[0]):
			rate += int(e[1])
			break
	if fs.rng.randi_range(0, 999) >= rate:
		return false
	# it gets up and asks to join
	t.hp = t.max_hp
	for k in t.status:
		if t.status[k] is int:
			t.status[k] = 0
	if t.visual:
		t.visual.play("Idle")
	await _flush_walks()
	# MonsterJoinSequence_Async (dungeon_mon_recruit.c), texts from dungeon_strings.c
	Audio.sfx("recruit")
	menu_open = true
	var cyan := "[color=#7fe0ff]%s[/color]" % t.name       # CopyCyanMonsterNametoBuffer
	var c := 0
	if not auto_answer:
		if dx:
			c = await Dialog.ask(ui_root, "Yes! %s wants to join the team!\nTake %s along on this adventure?" % [cyan, cyan], ["Yes", "No"], "", "Normal", false)
		else:
			c = await Dialog.ask(ui_root, "Yes! %s wants to join the team!\nAccept %s as a team member?" % [cyan, cyan], ["Yes", "No"], "", "Normal", false)
	menu_open = false
	if c != 0:
		if t.sp.substr(0, 4) != "0385":                  # Jirachi leaves without the line
			_msg("%s went away..." % cyan)
		t.set_meta("went_away", true)                    # HandleFaint(DUNGEON_EXIT_LEFT_WITHOUT_BEING_BEFRIENDED)
		return false
	t.side = "team"
	t.set_meta("recruited", true)
	if dx:
		t.set_meta("temp_recruit", true)
		t.set_meta("join_turn", dx_turns)
		t.set_meta("tactic", "lets_go_together")       # DX: temporary members don't follow tactics
		if t.held != "":                                # ...and hold nothing: its item goes in the Toolbox (or drops)
			if not Game.bag_add(t.held) and not fs.items.has(t.pos):
				fs.items[t.pos] = {"id": t.held, "n": 1, "price": 0}
				obj_layer.queue_redraw()
			t.held = ""
	else:
		AdventureLog.add("joined")             # IncrementAdventureNumJoined
	Awaken.revert(t)
	t.set_meta("entry", {"shiny": Shiny.is_shiny(t), "sp": t.sp, "name": t.name, "level": t.level, "exp": t.exp, "moves": t.moves.duplicate(true), "iq": 0, "held": "", "bonus": {}, "area": Services.area_of(t.sp)})
	team_mons.append(t)
	mem.erase(t.uid)
	if t.visual:
		t.visual.set_species(t.sp)     # team marker colour
	await _join_sequence(t)
	return true

func gain_exp(m: Mon, n: int) -> void:
	if m.level >= 100:
		return
	if EosItems.has(m, "exp_bonus"):
		n = int(ceil(n * 1.5))                       # Wonder Chest / exclusive items: bonus Exp.
	m.exp += n
	# dungeon_leveling.c: "$m0 gained $d0 Exp. Points!", then per level the fanfare (once) and
	# "$m0 grew to Level $d0!", new moves, then the level-up message boxes (sub_807218C).
	_msg("%s gained %d Exp. Points!" % [_nm(m), n])
	var before := {"hp": m.max_hp, "atk": m.atk, "def": m.def, "spa": m.spa, "spd": m.spd}
	var leveled := false
	var new_moves: Array = []
	while m.level < 100 and m.exp >= DB.exp_at(m.sp, m.level + 1):
		m.level += 1
		DB.recalc(m)
		if not leveled:
			Audio.sfx("levelup")
		leveled = true
		_msg("%s grew to Level %d!" % [_nm(m), m.level])
		for e in DB.species.get(m.sp, {}).get("learn", []):
			if int(e[0]) == m.level and DB.moves.has(e[1]) and m.move_by_name(e[1]).is_empty() and not (e[1] in new_moves):
				new_moves.append(e[1])
	var gulpin_told := false
	for mvn in new_moves:
		if m.moves.size() >= 4 and m.is_team() and not gulpin_told:
			gulpin_told = true
			await _red_box(["This Pokémon learned a new move,\nso it must forget an old one. Moves can\nbe relearned at the Gulpin Link Shop."])
		await learn_move(m, mvn)
	if leveled and m.is_team():
		await _level_up_boxes(m, before)
	_update_hud()

func learn_move(m: Mon, mvn: String) -> void:
	var mvd: Dictionary = DB.moves[mvn]
	var IQS = TeamScreens.iq_script()
	if IQS and not IQS.can_learn_move(m, mvn):
		return
	if m.moves.size() < 4:
		m.moves.append({"name": mvn, "pp": int(mvd.pp), "max_pp": int(mvd.pp), "on": true, "linked": false})
		_msg("%s learned [color=#7fe0ff]%s[/color]!" % [_nm(m), mvn])     # gUnknown_80F9F04
		return
	if not m.is_team():
		return
	# dungeon_menu_moves.c sub_8063E70: the five moves (B does nothing), pick one, confirm, it is forgotten
	menu_open = true
	var opts: Array = []
	for mv in m.moves:
		opts.append(mv.name)
	opts.append(mvn)
	var i := 4
	while true:
		var lm := ListMenu.make(m.name, opts, false)
		_show_menu(lm, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		i = await lm.choose()
		var auto := auto_answer or Dialog.auto or TeamScreens.auto_on()
		if i < 0:
			i = 4 if auto else -1
		if i < 0:
			continue
		var ok := 0 if auto else await Dialog.ask(ui_root, "The move [color=#7fe0ff]%s[/color] will be\nforgotten.\nIs that OK?" % str(opts[i]), ["Yes", "No"], "", "Normal", false)
		if ok == 0:
			break
	menu_open = false
	if i >= 0 and i < 4:
		m.moves[i] = {"name": mvn, "pp": int(mvd.pp), "max_pp": int(mvd.pp), "on": true, "linked": false}
		_msg("%s learned [color=#7fe0ff]%s[/color]!" % [_nm(m), mvn])

# ================================================================= stairs / end
func stairs_prompt() -> void:
	if autoplay:
		Audio.sfx("stairs")
		await next_floor()
		return
	if auto_answer:
		Audio.sfx("stairs")
		await next_floor()
		return
	menu_open = true
	var go := await _stairs_menu()
	menu_open = false
	if go:
		Audio.sfx("stairs")
		await next_floor()

## Red's stairs menu (dungeon_menu_stairs.c): "Stairs" window, commands Proceed / Info.
func _stairs_menu() -> bool:
	while true:
		var m := TeamScreens.menu("Stairs", ["Stairs"], 200)
		m.keep_on_pick = true
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		if r.act != "pick":
			return false
		var c := await TeamScreens.submenu(ui_root, m, ["Proceed", "Info"])
		if c == "Proceed":
			return true
		if c == "Info":
			await TeamScreens.show_text(ui_root, "Stairs", str(TeamScreens.text().get("stairs_desc", "")))
	return false

func next_floor() -> void:
	floor_i += 1
	for m in team_mons:
		Awaken.revert(m)
		Game.store_mon(m)
	if floor_i >= ddata.floors.size() or (stop_floor >= 0 and floor_i >= stop_floor):
		_end("cleared")
		return
	AdventureLog.add("floors")             # IncrementAdventureFloorsExplored
	await build_floor()
	AbilityFx.update_weather(self)
	EosItems.fs = fs
	for tm_ in fs.team():
		EosItems.floor_start(self, tm_)

func _end(res: String) -> void:
	if result_sent:
		return
	result_sent = true
	DungeonSave.clear()                 # run over: no stale suspend/autosave
	if exit_summary.is_empty() or res != "defeated":
		exit_summary = _end_summary(res)
	for m in team_mons:
		Awaken.revert(m)
		Game.store_mon(m)
	# Red: Pokémon recruited on this expedition only stay if you get home safely
	if res != "defeated":
		for m in team_mons:
			if m.get_meta("recruited", false) and not is_temp(m):
				var e: Dictionary = m.get_meta("entry")
				Game.friends.append(e)
				recruited_names.append(m.name)
		await _dx_farewells()
	finished.emit(res)

## DX recruiting, leaving the dungeon: each temporary member (still standing or not) may stay if you have its
## Friend Area; otherwise, or if you say no, it leaves and pays a little for the adventure (more turns, more Poké).
func _dx_farewells() -> void:
	var temps: Array = team_mons.filter(func(m): return is_temp(m) and m.hp > 0)
	if temps.is_empty():
		return
	menu_open = true
	for m in temps:
		var cyan := "[color=#7fe0ff]%s[/color]" % m.name
		var keep := -1
		if legend_owned(m):
			keep = -1
		elif Services.has_area_for(m.sp):
			keep = 0 if auto_answer or Dialog.auto else await Dialog.ask(ui_root,
					"%s had fun on the adventure!\nAsk %s to join the team for good?" % [cyan, cyan], ["Yes", "No"], "", "Normal", false)
		else:
			await _dx_say("%s would like to stay, but it has no Friend Area to live in..." % cyan)
		if keep == 0:
			m.remove_meta("temp_recruit")
			var e: Dictionary = m.get_meta("entry")
			Game.friends.append(e)
			recruited_names.append(m.name)
			AdventureLog.add("joined")
			await _join_sequence(m)
			e.name = m.name
		else:
			var pay := clampi((dx_turns - int(m.get_meta("join_turn", dx_turns))) / 2, 10, 500)
			Game.money += pay
			Audio.sfx("coin")
			await _dx_say("%s went home.\nIt left %d Poké as thanks for a fun adventure!" % [cyan, pay])
	menu_open = false

func _dx_say(t: String) -> void:
	if auto_answer or Dialog.auto:
		print("  DX ", t)
		return
	await Dialog.say(ui_root, t)

# ================================================================= menus
## Red's dungeon main menu (dungeon_main.c ShowMainMenu): Moves / Items / Team / Others / Ground, with
## the dungeon-name window and the leader info window (team HP, Belly, Money, Weather, Play time).
## Sub-menus come back to the main menu until something uses up the turn.
func open_main_menu() -> void:
	if menu_open or fs == null:
		return
	menu_open = true
	hud.clear_msgs()
	var sel := 0
	while not result_sent:
		var wins := _leader_info()
		var m := TeamScreens.menu("", ["Moves", "Items", "Team", "Others", "Ground"], 96)
		m.sel = sel
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		for w in wins:
			TeamScreens._drop(w)
		if r.act != "pick":
			break
		sel = r.i
		var acted := false
		match r.i:
			0: acted = await _moves_menu()
			1: acted = await _items_menu(false)
			2: acted = await _team_menu()
			3: acted = await _others_menu()
			4: acted = await _ground_menu()
		if acted:
			break
	menu_open = false
	if not result_sent:
		_update_hud()

## Moves / Items / Team straight from their hotkeys (M, I) or touch buttons.
func open_moves() -> void:
	if menu_open or fs == null:
		return
	menu_open = true
	await _moves_menu()
	menu_open = false

func open_bag() -> void:
	if menu_open or fs == null:
		return
	menu_open = true
	await _items_menu(false)
	menu_open = false

func open_team() -> void:
	if menu_open or fs == null:
		return
	menu_open = true
	await _team_menu()
	menu_open = false

func open_ground() -> void:
	if menu_open or fs == null:
		return
	menu_open = true
	await _ground_menu()
	menu_open = false

func _show_menu(c: Control, at := Vector2(10, 30)) -> void:
	ui_root.add_child(c)
	c.position = at
	if auto_answer and c is ListMenu:
		(func(): c._finish(c.options.size() - 1 if c.options.size() > 1 and str(c.options[-1].text).begins_with("Don't") else 0)).call_deferred()

## The rest of the turn after a menu command (everyone else acts).
func _menu_turn() -> void:
	busy = true
	if not result_sent:
		await world_turn()
	busy = false
	if not result_sent:
		_update_hud()

func _do_menu_action(a: Dictionary) -> bool:
	if a.has("use") and not result_sent:
		busy = false
		await leader_action({"type": "attack", "move": str(a.use), "dir": fs.leader.facing, "chain": a.get("chain", [])})
		return true
	return false

# ------------------------------------------------------------------ leader info window
static var _play_tick := 0
func _play_seconds() -> int:
	var now := Time.get_ticks_msec()
	Game.flags["play_s"] = float(Game.flags.get("play_s", 0.0)) + (now - _play_tick) / 1000.0
	_play_tick = now
	return int(Game.flags.play_s)

func _info_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme = UITheme.theme()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(pc)
	return pc

func _grid_label(g: GridContainer, t: String, right := false) -> void:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size.y = 22
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g.add_child(l)

func _leader_info() -> Array:
	var vs := ui_root.get_viewport_rect().size
	var nb := _info_panel()
	var nl := Label.new()
	nl.text = _display_name()
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nb.add_child(nl)
	nb.position = Vector2(TeamScreens.WIN_X + 112, TeamScreens.WIN_Y)
	nb.custom_minimum_size.x = minf(272, vs.x - nb.position.x - 16)
	var ib := _info_panel()
	var sb: StyleBoxFlat = UITheme.box().duplicate()
	sb.content_margin_top = 2 * UITheme.PX
	sb.content_margin_bottom = 2 * UITheme.PX
	ib.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16 * UITheme.PX)
	ib.add_child(hb)
	var left := GridContainer.new()
	left.columns = 2
	left.add_theme_constant_override("v_separation", 0)
	left.add_theme_constant_override("h_separation", 8 * UITheme.PX)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(left)
	var n := 0
	for t in fs.team():
		if n >= 4:
			break
		_grid_label(left, t.name)
		_grid_label(left, "%d/%d" % [t.hp, t.max_hp], true)
		n += 1
	var right := GridContainer.new()
	right.columns = 2
	right.add_theme_constant_override("v_separation", 0)
	right.add_theme_constant_override("h_separation", 4 * UITheme.PX)
	hb.add_child(right)
	var s := _play_seconds()
	_grid_label(right, "Belly:")
	_grid_label(right, "%d/%d" % [int(ceil(belly)), belly_max], true)
	_grid_label(right, "Money:")
	_grid_label(right, "%d Poké" % Game.money, true)
	_grid_label(right, "Weather:")
	_grid_label(right, str(fs.weather).capitalize() if str(fs.weather) != "" else "Clear", true)
	_grid_label(right, "Play:")
	_grid_label(right, "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60], true)
	var h := 4 * 22 + 4 * UITheme.PX + 2 * UITheme.PX
	ib.custom_minimum_size.x = minf(448, vs.x - 2 * TeamScreens.WIN_X)
	ib.position = Vector2(TeamScreens.WIN_X, vs.y - h - 4)
	return [nb, ib]

# ------------------------------------------------------------------ moves (linked moves)
func _moves_menu(start: Mon = null) -> bool:
	var a := await TeamScreens.moves_menu(ui_root, start if start else fs.leader, true, self)
	return await _do_menu_action(a)

## While L is held: which button uses which move (A / B / X / Y = moves 1-4), with PP; linked moves show
## their chain. Hidden when L is let go or a menu opens.
var _lmoves: Control = null

func _show_l_moves(on: bool) -> void:
	if _lmoves != null and is_instance_valid(_lmoves):
		_lmoves.queue_free()
	_lmoves = null
	if not on or fs == null or fs.leader == null or menu_open or result_sent:
		return
	var L := fs.leader
	var pc := _info_panel()
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 6 * UITheme.PX)
	g.add_theme_constant_override("v_separation", 0)
	pc.add_child(g)
	var glyphs := ["A_BUTTON", "B_BUTTON", "NDS_X_BUTTON", "NDS_Y_BUTTON"]
	var letters := ["A", "B", "X", "Y"]
	for i in 4:
		var key := UITheme.glyph(glyphs[i])
		g.add_child(TeamScreens._rtl(key if key != "" else "[color=%s]%s[/color]" % [TeamScreens.CYAN, letters[i]]))
		var nm := "-"
		var pp := ""
		if i < L.moves.size() and str(L.moves[i].get("name", "")) != "":
			var mv: Dictionary = L.moves[i]
			nm = str(mv.name)
			if i > 0 and bool(mv.get("linked", false)):
				nm = "+" + nm                          # fires the chain from the move above
			var p := int(mv.get("pp", 0))
			if p <= 0:
				nm = "[color=%s]%s[/color]" % [TeamScreens.RED, nm]
			pp = "%d/%d" % [p, int(mv.get("max_pp", p))]
		g.add_child(TeamScreens._rtl(nm))
		var r := TeamScreens._rtl(pp)
		r.custom_minimum_size.x = 40 * UITheme.PX
		g.add_child(r)
	pc.position = Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y)
	_lmoves = pc

## Controller L + A / B / X / Y: the leader's move in that slot (1-4). A move linked to the one before it
## fires its whole chain from the first move, like choosing it in the Moves menu.
func use_move_slot(i: int) -> void:
	if busy or menu_open or fs == null:
		return
	var L := fs.leader
	if i >= L.moves.size() or str(L.moves[i].get("name", "")) == "":
		_msg("There's no move in that slot.")
		return
	while i > 0 and bool(L.moves[i].get("linked", false)):
		i -= 1
	var chain: Array = []
	for j in TeamScreens.chain_from(L.moves, i):
		chain.append(str(L.moves[j].name))
	if int(L.moves[i].get("pp", 0)) <= 0:
		_msg("There's no PP left for %s!" % chain[0])
		return
	_show_l_moves(false)
	await leader_action({"type": "attack", "move": chain[0], "dir": L.facing, "chain": chain})
	if _pad_held("gp_l"):
		_show_l_moves(true)                      # still holding L: show the new PP

## Keyboard (Run + Attack): the leader's set move (and the moves linked after it).
func use_set_move() -> void:
	if busy or menu_open:
		return
	var L := fs.leader
	for i in L.moves.size():
		if bool(L.moves[i].get("set", false)) and (i == 0 or not bool(L.moves[i].get("linked", false))):
			var chain: Array = []
			for j in TeamScreens.chain_from(L.moves, i):
				if int(L.moves[j].pp) <= 0:
					_msg("The set move can't be used.")
					return
				chain.append(str(L.moves[j].name))
			leader_action({"type": "attack", "move": chain[0], "dir": L.facing, "chain": chain})
			return
	_msg("No move has been set.")

## A linked chain fires in sequence with one command: each move spends its own PP, and the leader's
## Belly drops extra (gLinkedMovesBellyGoDownValues via TurnRules.belly_loss). When a move of the chain
## runs out of PP the links come apart (Red's warnings at 2 and 1 uses left).
func use_linked_chain(m: Mon, chain: Array, d: int) -> void:
	var used := 0
	if chain.size() > 1:
		m.set_meta("linked_hit", true)
	for nm in chain:
		if m.hp <= 0 or result_sent or not fs.mons.has(m):
			break
		var slot := m.move_by_name(str(nm))
		if slot.is_empty() or int(slot.pp) <= 0:
			break
		await do_attack(m, str(nm), d)
		used += 1
	m.remove_meta("linked_hit")
	if m.is_leader and used > 1 and bool(Game.settings.get("hunger", true)):
		var extra := TurnRules.belly_loss(m, used) - TurnRules.belly_loss(m, 0)
		belly_state.belly = maxf(0.0, float(belly_state.get("belly", belly)) - extra)
		belly = float(belly_state.belly)
	if m.is_team():
		var low := 99
		var head := -1
		for nm in chain:
			for i in m.moves.size():
				if str(m.moves[i].name) == str(nm):
					low = mini(low, int(m.moves[i].pp))
					if head < 0:
						head = i
		if head >= 0 and low <= 0:
			for j in TeamScreens.chain_from(m.moves, head):
				if j != head:
					m.moves[j].linked = false
			_msg("The linked moves came apart!")
		elif m.is_leader and low == 1:
			_msg("[color=#ffdc4a]The linked moves are almost out of PP! Use them again and they will come apart![/color]")
		elif m.is_leader and low == 2:
			_msg("[color=#ffdc4a]The linked moves are almost out of PP! Use them twice and they will come apart![/color]")

# ------------------------------------------------------------------ items
## Red's Items window (dungeon_menu_items.c): pages Team Toolbox A / B, Ground, and each team member's
## held item, switched with Left/Right; Tab (Select) sorts the Toolbox.
func _item_pages(ground_only: bool) -> Array:
	var pages: Array = []
	if not ground_only:
		if Game.bag.size() > 0:
			pages.append({"kind": "bag", "start": 0, "title": "Team Toolbox A"})
		if Game.bag.size() > 10:
			pages.append({"kind": "bag", "start": 10, "title": "Team Toolbox B"})
	if fs.items.has(fs.leader.pos):
		pages.append({"kind": "ground", "title": "Ground"})
	if not ground_only:
		for t in fs.team():
			if t.held != "":
				pages.append({"kind": "held", "mon": t, "title": "%s's item" % t.name})
	return pages

func _item_rows(pg: Dictionary) -> Array:
	var rows: Array = []
	match str(pg.kind):
		"bag":
			for k in range(int(pg.start), mini(int(pg.start) + 10, Game.bag.size())):
				rows.append(TeamScreens.item_row(Game.bag[k]))
		"ground":
			var it: Dictionary = fs.items[fs.leader.pos]
			var row2 := TeamScreens.item_row(it, false)
			row2.erase("right")
			if int(it.get("price", 0)) > 0:
				row2.right = "%d Poké" % int(it.price)
			elif int(it.get("n", 1)) > 1:
				row2.right = str(int(it.n))
			rows.append(row2)
		"held":
			rows.append(TeamScreens.item_row({"id": pg.mon.held}, false))
	return rows

func _items_menu(ground_only: bool) -> bool:
	var pi := 0
	var sel := 0
	while not result_sent:
		var pages := _item_pages(ground_only)
		if pages.is_empty():
			await TeamScreens.say(ui_root, "There are no items.")
			return false
		pi = clampi(pi, 0, pages.size() - 1)
		var pg: Dictionary = pages[pi]
		var m := TeamScreens.menu(str(pg.title), _item_rows(pg), 288)
		m.pages = pages.size()
		m.page = pi
		m.sel = sel
		m.max_rows = 8                    # a Toolbox page holds 10: swipe or the header arrows show the rest
		m.select_key = pg.kind == "bag"
		if pg.kind == "bag":
			m.header_buttons = [["Sort", "select"]]   # touch: Red sorts with Select
		m.keep_on_pick = true
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		match str(r.act):
			"cancel":
				return false
			"left":
				pi = (pi - 1 + pages.size()) % pages.size()
				sel = 0
				continue
			"right":
				pi = (pi + 1) % pages.size()
				sel = 0
				continue
			"select":
				_sort_bag()
				pi = 0
				sel = 0
				continue
		sel = r.i
		if await _item_commands(pg, r.i, m):
			return true
		if TeamScreens.auto_on():
			return false
	return false

## Red's item order (ConvertMoneyItemToMoney: Poké becomes money, then sorted by the item order).
func _sort_bag() -> void:
	BaseMenu.sort_bag()

func _cant_hold(t: Mon) -> bool:
	return is_temp(t) or t.get_meta("escort", false) or Missions.is_client(t) or t.get_meta("no_attack", false)

func _bag_is_full(id: String) -> bool:
	if DB.items.get(id, {}).get("stack", false):
		for b in Game.bag:
			if b.id == id and int(b.n) < 99:
				return false
	return Game.bag.size() >= Game.BAG_MAX

## Pick a Toolbox item for an exchange ("Which?"). Returns the bag index or -1.
func _which_bag_item() -> int:
	var rows: Array = []
	for b in Game.bag:
		rows.append(DB.item_name(b.id))
	if rows.is_empty():
		return -1
	var m := TeamScreens.menu("Which?", rows, 240)
	m.max_rows = 8
	var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X + 40, TeamScreens.WIN_Y + 12))
	return r.i if r.act == "pick" else -1

func _item_commands(pg: Dictionary, idx: int, win: Control) -> bool:
	var L := fs.leader
	var opts: Array = []
	var id := ""
	var bag_i := -1
	var holder: Mon = null
	match str(pg.kind):
		"bag":
			bag_i = int(pg.start) + idx
			id = Game.bag[bag_i].id
			var verb := TeamScreens.item_verb(id)
			if verb != "":
				opts.append({"text": verb, "id": "use"})
			if TeamScreens.is_thrown(id):
				opts.append({"text": "Deselect" if Game.bag[bag_i].get("set", false) else "Set", "id": "set"})
			var can_give := false
			for t in fs.team():
				if not _cant_hold(t):
					can_give = true
			opts.append({"text": "Give", "id": "give", "disabled": not can_give})
			if fs.items.has(L.pos):
				opts.append({"text": "Swap", "id": "swap_ground"})
			elif L.pos != fs.stairs:
				opts.append({"text": "Place", "id": "place"})
			opts.append({"text": "Throw", "id": "throw"})
		"ground":
			var it: Dictionary = fs.items[L.pos]
			id = it.id
			var unpaid := int(it.get("price", 0)) > 0
			opts.append({"text": "Pick Up", "id": "pickup", "disabled": (id != "poke" and _bag_is_full(id)) or (unpaid and Game.bag.size() >= Game.BAG_MAX)})
			opts.append({"text": "Switch", "id": "switch", "disabled": Game.bag.is_empty()})
			var verb2 := TeamScreens.item_verb(id)
			if verb2 != "":
				opts.append({"text": verb2, "id": "use_ground", "disabled": unpaid})
			opts.append({"text": "Throw", "id": "throw_ground", "disabled": unpaid})
		"held":
			holder = pg.mon
			id = holder.held
			if Game.bag.size() >= Game.BAG_MAX:
				opts.append({"text": "Swap", "id": "swap_held"})
			else:
				opts.append({"text": "Take", "id": "take"})
			var cat := str(DB.items.get(id, {}).get("red_cat", ""))
			if holder.is_leader:
				var verb3 := TeamScreens.item_verb(id)
				if verb3 != "":
					opts.append({"text": verb3, "id": "use_held"})
			else:
				opts.append({"text": "Use", "id": "use_held", "disabled": cat in ["tms_hms", "orbs"] or TeamScreens.item_verb(id) == ""})
	opts.append({"text": "Info", "id": "info"})
	var c := await TeamScreens.submenu(ui_root, win, opts, idx - (win as TeamScreens.RedMenu).top)
	var nm := "[color=#ffdc4a]%s[/color]" % DB.item_name(id)
	match c:
		"info":
			await TeamScreens.item_info(ui_root, id)
		"set":
			var was: bool = Game.bag[bag_i].get("set", false)
			for b in Game.bag:
				b.erase("set")
			if not was:
				Game.bag[bag_i].set = true
				_msg("The %s was set. Hold Shift and press I to throw one." % nm)
			else:
				_msg("The %s was deselected." % nm)
		"use":
			busy = true
			await use_item(L, bag_i)
			await _menu_turn()
			return true
		"give":
			var team := fs.team()
			var dis: Array = []
			for k in team.size():
				if _cant_hold(team[k]):
					dis.append(k)
			var w := await TeamScreens.which_member(ui_root, team, "Which?", dis)
			if w < 0:
				return false
			var t: Mon = team[w]
			var old := t.held
			_take_bag(bag_i)
			TeamScreens.set_held(t, id)
			if old != "":
				Game.bag.insert(mini(bag_i, Game.bag.size()), {"id": old, "n": 1})
				_msg("%s took the %s and returned the [color=#ffdc4a]%s[/color]." % [_nm(t), nm, DB.item_name(old)])
			else:
				_msg("The item %s was given to %s." % [nm, _nm(t)])
			await _menu_turn()
			return true
		"place":
			var b: Dictionary = Game.bag[bag_i]
			fs.items[L.pos] = {"id": b.id, "n": int(b.n), "price": int(b.get("price", 0))}
			Game.bag.remove_at(bag_i)
			obj_layer.queue_redraw()
			_msg("%s put the %s on the ground." % [_nm(L), nm])
			await _menu_turn()
			return true
		"swap_ground":
			var g: Dictionary = fs.items[L.pos]
			var b2: Dictionary = Game.bag[bag_i]
			fs.items[L.pos] = {"id": b2.id, "n": int(b2.n), "price": int(b2.get("price", 0))}
			Game.bag[bag_i] = {"id": g.id, "n": int(g.get("n", 1))}
			if int(g.get("price", 0)) > 0:
				Game.bag[bag_i].price = int(g.price)
			obj_layer.queue_redraw()
			_msg("Exchanged the [color=#ffdc4a]%s[/color] on the ground with the %s." % [DB.item_name(g.id), nm])
			await _menu_turn()
			return true
		"throw":
			busy = true
			await throw_item(L, bag_i)
			await _menu_turn()
			return true
		"pickup":
			var it2: Dictionary = fs.items[L.pos]
			if id == "poke":
				Game.money += int(it2.n)
				Audio.sfx("coin")
				_msg("Picked up %d Poké." % int(it2.n))
			elif int(it2.get("price", 0)) > 0 and Game.bag.size() < Game.BAG_MAX:
				Game.bag.append({"id": id, "n": int(it2.get("n", 1)), "price": int(it2.price)})    # a Kecleon ware: unpaid
				Audio.sfx("pickup")
				_msg("Picked up the %s." % nm)
			elif int(it2.get("price", 0)) == 0 and Game.bag_add(id, int(it2.get("n", 1))):
				Audio.sfx("pickup")
				_msg("Picked up the %s." % nm)
			else:
				_msg("The Toolbox is full.")
				return false
			fs.items.erase(L.pos)
			obj_layer.queue_redraw()
			await _menu_turn()
			return true
		"switch":
			var k2 := await _which_bag_item()
			if k2 < 0:
				return false
			var g2: Dictionary = fs.items[L.pos]
			var b3: Dictionary = Game.bag[k2]
			fs.items[L.pos] = {"id": b3.id, "n": int(b3.n), "price": int(b3.get("price", 0))}
			Game.bag[k2] = {"id": g2.id, "n": int(g2.get("n", 1))}
			if int(g2.get("price", 0)) > 0:
				Game.bag[k2].price = int(g2.price)
			obj_layer.queue_redraw()
			_msg("Exchanged the %s on the ground with the [color=#ffdc4a]%s[/color]." % [nm, DB.item_name(b3.id)])
			await _menu_turn()
			return true
		"use_ground":
			fs.items.erase(L.pos)
			obj_layer.queue_redraw()
			busy = true
			await _use_item_id(L, id)
			await _menu_turn()
			return true
		"throw_ground":
			fs.items.erase(L.pos)
			obj_layer.queue_redraw()
			busy = true
			await _throw_id(L, id)
			await _menu_turn()
			return true
		"take":
			Game.bag_add(id)
			TeamScreens.set_held(holder, "")
			_msg("%s returned the %s." % [_nm(holder), nm])
			await _menu_turn()
			return true
		"swap_held":
			var k3 := await _which_bag_item()
			if k3 < 0:
				return false
			var b4: Dictionary = Game.bag[k3]
			TeamScreens.set_held(holder, b4.id)
			Game.bag[k3] = {"id": id, "n": 1}
			_msg("The %s was exchanged for the [color=#ffdc4a]%s[/color] in the Toolbox." % [nm, DB.item_name(b4.id)])
			await _menu_turn()
			return true
		"use_held":
			TeamScreens.set_held(holder, "")
			_msg("%s used the %s it was holding!" % [_nm(holder), nm])
			busy = true
			await _use_item_id(holder, id, false)
			await _menu_turn()
			return true
	return false

## L + R: throw one of the set item.
func throw_set_item() -> void:
	if busy or menu_open:
		return
	for i in Game.bag.size():
		if Game.bag[i].get("set", false):
			busy = true
			await throw_item(fs.leader, i)
			await _menu_turn()
			return
	_msg("No item has been set.")

func _take_bag(i: int) -> void:
	var b: Dictionary = Game.bag[i]
	b.n = int(b.n) - 1
	if b.n <= 0 or not DB.items.get(b.id, {}).get("stack", false):
		Game.bag.remove_at(i)

func use_item(m: Mon, i: int) -> void:
	var id: String = Game.bag[i].id
	_take_bag(i)
	await _use_item_id(m, id)

const USE_VERB_MSG := {"Eat": "%s ate the %s.", "Ingest": "%s swallowed the %s.", "Peel": "%s peeled the %s.", "Use": "%s used the %s."}

func _use_item_id(m: Mon, id: String, announce := true) -> void:
	var I: Dictionary = DB.items.get(id, {})
	var cat := str(I.get("red_cat", ""))
	if cat == "orbs":
		await use_orb(m, id)
		return
	var verb := TeamScreens.item_verb(id)
	if cat in ["other", "link_box", "tms_hms", "used_tm", "held_items", "exclusive"] or verb == "":
		_msg("The %s can't be used here." % I.get("name", id))
		Game.bag_add(id)
		return
	if cat == "berries_seeds_vitamins" and str(I.get("name", "")).ends_with("Berry"):
		for o in fs.mons:
			if o.hp > 0 and fs.is_foe(m, o) and AbilityFx.has(o, "unnerve") and fs.can_see(m, o.pos):
				_msg("%s is too nervous to eat Berries!" % _nm(m))
				Game.bag_add(id)
				return
	if m.visual:
		m.visual.play("Eat")
	if announce:
		_msg(USE_VERB_MSG.get(verb if verb != "" else "Use", "%s used the %s.") % [_nm(m), I.get("name", id)])
	await get_tree().create_timer(0.3).timeout
	await _item_effect(m, m, id, false)

## What a Red item does to target (dungeon_item_action.c, item_effects): eaten / used (thrown = false), or
## thrown at a Pokémon (thrown = true: seeds and berries act on whoever they hit; a thrown Blast Seed does
## 20 damage, an eaten one hits the foe in front for 45).
func _item_effect(user: Mon, m: Mon, id: String, thrown: bool) -> void:
	var I: Dictionary = DB.items.get(id, {})
	var kind: String = I.get("kind", "")
	var IQS = TeamScreens.iq_script()
	if IQS and IQS.is_gummi(id):
		if thrown and not m.is_team():
			_msg("%s ate the %s." % [_nm(m), I.get("name", id)])
			return
		var res: Dictionary = IQS.eat_gummi(m, id)
		if m.is_leader and int(res.get("belly", 0)) > 0:
			belly = minf(belly_max, belly + float(res.belly))
			belly_state.belly = belly
		for s in res.get("msgs", []):
			_msg(str(s))
		return
	if not thrown and EosItems.has(m, "berry_heal") and (str(I.get("name", "")).ends_with("Berry") or str(I.get("name", "")).ends_with("Apple")):
		m.hp = mini(m.max_hp, m.hp + maxi(1, m.max_hp / 8))
		_msg("%s recovered some HP!" % _nm(m))
	match kind:
		"confuse_x":
			_set_item_status(m, "cross_eyed", 10, "%s became cross-eyed!")
			return
		"golden":
			var tgt := mini(100, m.level + 5)
			if m.level >= 100:
				_msg("But nothing happened.")
			else:
				await gain_exp(m, maxi(1, DB.exp_at(m.sp, tgt) - m.exp))
			return
		"vile":
			m.stages.def = 0
			m.stages.spd = 0
			_msg("%s's Defense and Sp. Def fell to their lowest!" % _nm(m))
			return
		"vanish":
			m.status.invisible = 20
			_msg("%s turned invisible!" % _nm(m))
			return
		"dropeye":
			_set_item_status(m, "blinker", 10, "%s's vision went dark!")
			return
		"slip":
			m.status.slip = 0x7F
			_msg("%s can now walk on water!" % _nm(m))
			return
		"mixelixir":
			if m.sp.substr(0, 4) == "0264":
				for mv in m.moves:
					mv.pp = int(mv.get("max_pp", mv.pp))
				_msg("%s's PP was restored!" % _nm(m))
			else:
				_msg("But nothing happened.")
			return
		"nectar":
			var IQN = TeamScreens.iq_script()
			if IQN and m.is_team():
				m.iq = int(m.iq) + 5
				_msg("%s's IQ went up!" % _nm(m))
			return
		"golden_apple":
			_eat_food(m, 200.0, 50)
			return
		"empower":
			await Awaken.awaken(self, m)
			return
		"plain":
			_msg("But nothing happened.")
			return
	match id:
		"hugeapple":
			_eat_food(m, 999.0, 10)
			return
		"banana", "chestnut":
			_eat_food(m, 50.0, 5)
			return
		"hungerseed":
			if m.is_leader:
				belly = 0.0
				belly_state.belly = 0.0
				_msg("%s's Belly emptied!" % _nm(m))
			elif AI.iq(m, "self-curer"):
				_msg("%s's Self-Curer stopped the hunger!" % _nm(m))
			else:
				_msg("%s became hungry!" % _nm(m))
			return
		"allureseed":
			_set_item_status(m, "cross_eyed", 10, "%s became cross-eyed!")
			return
		"ginseng":
			var up := 3 if fs.rng.randi_range(0, 99) < 12 else 1      # gGinsengPlus3BoostChance
			var boosted := false
			if m.is_leader:
				for mv in m.moves:
					if bool(mv.get("set", false)) and int(DB.moves.get(mv.name, {}).get("p", 0)) > 2:
						mv.ginseng = mini(99, int(mv.get("ginseng", 0)) + up)
						boosted = true
			if boosted:
				_msg("The set moves' power went up!")
				if up > 1:
					_msg("They went up by %d!" % up)
			else:
				_msg("But nothing happened.")
			return
	match kind:
		"food":
			_eat_food(m, float(I.get("v", 50)), int(float(I.get("v", 50)) / 10))
		"grimy":
			_eat_food(m, 30.0, 0)
			match fs.rng.randi_range(0, 4):
				0: _set_item_status(m, "poison", 20, "%s was poisoned!")
				1: _set_item_status(m, "shadow_hold", 6, "%s is immobilized!")
				2: _set_item_status(m, "burn", 20, "%s got burned!")
				3: _set_item_status(m, "para", 20, "%s is paralyzed!")
				4:
					for k in ["atk", "spa"]:
						if not HeldItems.blocks_stat_drop(m, k):
							m.stages[k] = maxi(0, int(m.stages.get(k, 10)) - 3)
					_msg("%s's Attack and Sp. Atk fell harshly!" % _nm(m))
		"heal", "sitrus":
			var full := m.hp >= m.max_hp
			var v2 := 100
			v2 = IQSky.heal_amount(m, v2)
			m.hp = mini(m.max_hp, m.hp + v2)
			if kind == "sitrus" and full:
				_raise_max_hp(m, 2)                     # gSitrusBerryMaxHpRiseValue
			elif kind == "sitrus":
				_msg("%s's HP was fully restored!" % _nm(m))
			else:
				_msg("%s recovered HP!" % _nm(m))
			if m.is_leader and not thrown:
				belly = minf(belly_max, belly + 5)
				belly_state.belly = belly
			Audio.sfx("heal")
		"life":
			_raise_max_hp(m, 3)                         # gLifeSeedMaxHpRiseValue
		"sleep":
			_set_item_status(m, "sleep", fs.rng.randi_range(3, 6), "%s fell asleep!")
			if m.visual and m.has_status("sleep"):
				m.visual.play("Idle")
		"blind":
			_set_item_status(m, "blinker", 20, "%s was blinded!")
		"confuse":
			_set_item_status(m, "confused", fs.rng.randi_range(7, 12), "%s became confused!")
		"petrify":
			_set_item_status(m, "petrified", 20, "%s was petrified!")
		"quick":
			m.status.fast = TurnRules.red_turns("fast", fs.rng, m, 8)
			_msg("%s sped up!" % _nm(m))
		"eyedrop":
			m.status.blinker = 0
			m.status.eyedrops = 20
			_msg("%s can now see clearly!" % _nm(m))
		"warp":
			SpecialMoves.warp(self, m)
			_msg("%s was warped!" % _nm(m))
		"joy":
			if m.level >= 100:
				_msg("But nothing happened.")
			else:
				await gain_exp(m, maxi(1, DB.exp_at(m.sp, m.level + 1) - m.exp))
		"doom":
			if m.level <= 1:
				_msg("But nothing happened.")
			else:
				m.level -= 1
				m.exp = DB.exp_at(m.sp, m.level)
				var hp_lost := m.max_hp - m.hp
				DB.recalc(m)
				m.hp = maxi(1, m.max_hp - hp_lost)
				_msg("%s's level went down to %d!" % [_nm(m), m.level])
		"elixir":
			for mv in m.moves:
				mv.pp = int(mv.get("max_pp", mv.pp))
			_msg("%s's PP was restored!" % _nm(m))
		"vitamin":
			var k: String = str(I.get("v", "atk"))
			var bonus: Dictionary = m.get_meta("bonus", {})
			bonus[k] = int(bonus.get(k, 0)) + 3
			m.set_meta("bonus", bonus)
			var e: Dictionary = m.get_meta("entry", {})
			if not e.is_empty():
				e.bonus = bonus
			var hp_lost2 := m.max_hp - m.hp
			DB.recalc(m)
			m.hp = maxi(1, m.max_hp - hp_lost2)
			_msg("%s's %s rose!" % [_nm(m), _stat_name(k)])
		"blast":
			var boss_floor := boss != null
			if thrown:
				var dmg := 15 if boss_floor else 20
				_hurt(m, dmg, user, true)
				_msg("%s took %d damage!" % [_nm(m), dmg])
				if m.hp <= 0:
					await faint(m, user)
			else:
				var t := fs.mon_at(m.pos + DB.DIRS[m.facing])
				if t and fs.can_attack_dir(m.pos, m.facing):
					var dmg2 := 30 if boss_floor else 45
					_hurt(t, dmg2, m, true)
					_msg("%s took %d damage!" % [_nm(t), dmg2])
					if t.hp <= 0:
						await faint(t, m)
				else:
					_msg("The blast hit nothing.")
		"cure", "healall":      # Heal Seed (healall) and the status berries: every status goes away
			for k in ["poison", "badpoison", "burn", "para", "sleep", "confused"]:
				m.status[k] = 0
			_msg("%s's status returned to normal." % _nm(m))
		"reviver":
			if thrown:
				_msg("But nothing happened.")
			else:
				_msg("Nothing happened. (It works when you faint.)")
				Game.bag_add(id)
		_:
			_msg("But nothing happened.")
	_update_hud()

func _eat_food(m: Mon, v: float, max_rise: int) -> void:
	if not m.is_leader:
		_msg("%s's Belly filled up!" % _nm(m))
		return
	v = IQSky.food_bonus(m, v)
	if belly >= belly_max:
		belly_max = mini(200, belly_max + max_rise)
		if max_rise > 0:
			_msg("Its max Belly grew!")
	belly = minf(belly_max, belly + v)
	belly_state.belly = belly
	_msg("Its Belly filled up!")

func _raise_max_hp(m: Mon, n: int) -> void:
	var bonus: Dictionary = m.get_meta("bonus", {})
	bonus.hp = int(bonus.get("hp", 0)) + n
	m.set_meta("bonus", bonus)
	var e: Dictionary = m.get_meta("entry", {})
	if not e.is_empty():
		e.bonus = bonus
	DB.recalc(m)
	m.hp = mini(m.max_hp, m.hp + n)
	_msg("%s's max HP rose by %d!" % [_nm(m), n])
	Audio.sfx("heal")

func _set_item_status(m: Mon, key: String, turns: int, text: String) -> void:
	var why := HeldItems.blocks_status(m, key)
	if why != "":
		_msg(why % _nm(m))
		return
	if m.has_status(key):
		_msg("%s is already affected." % _nm(m))
		return
	m.status[key] = TurnRules.red_turns(key, fs.rng, m, turns)
	_msg(text % _nm(m))

## Using an Orb: it does its move (Red: the orb's moveID) in the direction the user faces, without PP.
func use_orb(m: Mon, id: String) -> void:
	if id in SpecialMoves.HELD_ONLY_ORBS:
		_msg("The %s works when it is held." % DB.item_name(id))
		Game.bag_add(id)
		return
	if id in ["allmachorb", "foefearorb", "allhitorb"]:
		_msg("%s used the [color=#ffdc4a]%s[/color]!" % [_nm(m), DB.item_name(id)])
		for o in fs.mons:
			if o.hp <= 0:
				continue
			if id == "allmachorb" and not fs.is_foe(m, o):
				o.status.fast = TurnRules.red_turns("fast", fs.rng, o, 8)
				_msg("%s sped up!" % _nm(o))
			elif id == "allhitorb" and not fs.is_foe(m, o) and _same_area(m, o) or (id == "allhitorb" and o == m):
				o.status.focus_energy = TurnRules.red_turns("focus_energy", fs.rng, o, 10)
				_msg("%s is getting pumped!" % _nm(o))
			elif id == "foefearorb" and fs.is_foe(m, o) and _same_area(m, o):
				o.status.terrified = 10
				_msg("%s is terrified!" % _nm(o))
		_update_hud()
		return
	if id in SpecialMoves.NO_EFFECT_ORBS or not SpecialMoves.ORB_MOVES.has(id):
		_msg("But nothing happened.")
		return
	var mvn: String = SpecialMoves.ORB_MOVES[id]
	_msg("%s used the [color=#ffdc4a]%s[/color]!" % [_nm(m), DB.item_name(id)])
	if m.visual:
		m.visual.play("Charge")
	if not DB.moves.has(mvn):
		_msg("But nothing happened.")
		return
	await do_attack(m, mvn, m.facing, false)

func throw_item(m: Mon, i: int) -> void:
	var id: String = Game.bag[i].id
	_take_bag(i)
	await _throw_id(m, id)

## arc_to: an arcing item (Gravelerock, Geo Pebble) thrown at a chosen tile flies over everything to it.
func _throw_id(m: Mon, id: String, arc_to := Vector2i(-1, -1)) -> void:
	var I: Dictionary = DB.items.get(id, {})
	var cat := str(I.get("red_cat", ""))
	Audio.sfx("throw")
	_msg("%s threw the [color=#ffdc4a]%s[/color]!" % [_nm(m), I.get("name", id)])
	var ts: Dictionary = HeldItems.throw_setup(self, m, m.facing)     # Long Toss / Pierce / Pierce Band / No-Aim Scope
	m.facing = int(ts.dir)
	var p: Vector2i = m.pos
	var hits_all: Array = []
	if arc_to.x >= 0:
		p = arc_to
		var o := fs.mon_at(arc_to)
		if o and o != m:
			hits_all = [o]
	elif bool(ts.pierce):
		# Pierce: flies through walls and Pokémon to the end of its range, hitting everyone on the line
		var q := m.pos
		for i in int(ts.range):
			q += DB.DIRS[m.facing]
			if not fs.inb(q) or q.x < 1 or q.y < 1 or q.x >= fs.w - 1 or q.y >= fs.h - 1:
				break
			p = q
			var o2 := fs.mon_at(q)
			if o2 and o2 != m:
				hits_all.append(o2)
	else:
		var tp: Dictionary = IQSky.throw_path(self, m, m.facing, int(ts.range))
		p = tp.end
		hits_all = tp.hits
	var spr := Sprite2D.new()
	spr.texture = _icon_tex
	spr.region_enabled = true
	spr.region_rect = _icon_rect(id)
	spr.position = _px(m.pos)
	fx_layer.add_child(spr)
	var tw := create_tween()
	tw.tween_property(spr, "position", _px(p), 0.05 * maxi(1, FloorState.cheb(m.pos, p)))
	await tw.finished
	spr.queue_free()
	# who actually gets hit: 90% each (Whiff Specs: never, Lockon Specs: always, Dodge Scarf: never);
	# a Bounce Band sends the item back to the ground in front of its holder
	var hits: Array = []
	var land := p
	for o3 in hits_all:
		var r := HeldItems.throw_hits(self, m, o3)
		if r == "hit":
			hits.append(o3)
		else:
			_msg("%s %s!" % [_nm(o3), "bounced the item away" if r == "bounce" else "dodged the item"])
			land = o3.pos - DB.DIRS[m.facing] if r == "bounce" else o3.pos
	if hits.is_empty():
		_drop_thrown(id, land)
		return
	var thrown_dmg: bool = cat in ["thrown_line", "thrown_arc"] or I.get("kind", "") in ["arc", "line"]
	if thrown_dmg:
		var dmg: int = {"stick": 3, "ironthorn": 4, "silverspike": 5, "goldfang": 6, "cacneaspike": 7, "corsolatwig": 7, "gravelerock": 8, "geopebble": 10, "goldthorn": 12, "rarefossil": 14}.get(id, 4)
		dmg = IQSky.thrown_damage(m, dmg)
		for o4 in hits:
			if o4.hp <= 0:
				continue
			_hurt(o4, dmg, m, true)
			_msg("%s took %d damage!" % [_nm(o4), dmg])
			if o4.hp <= 0:
				await faint(o4, m)
	elif cat in ["berries_seeds_vitamins", "food_gummies"]:
		# a seed, berry or food that hits a Pokémon takes effect on it
		await _item_effect(m, hits[0], id, true)
	else:
		_msg("Nothing happened to %s." % _nm(hits[0]))
		_drop_thrown(id, hits[0].pos)

func _drop_thrown(id: String, at: Vector2i) -> void:
	var q := at
	if fs.items.has(q) or fs.terrain_at(q) != 1:
		q = Vector2i(-1, -1)
		for r in range(0, 3):
			for y in range(-r, r + 1):
				for x in range(-r, r + 1):
					var c: Vector2i = at + Vector2i(x, y)
					if q.x < 0 and fs.inb(c) and fs.terrain_at(c) == 1 and not fs.items.has(c) and c != fs.stairs:
						q = c
	if q.x < 0:
		_msg("The %s disappeared..." % DB.item_name(id))
		return
	fs.items[q] = {"id": id, "n": 1, "price": 0}
	obj_layer.queue_redraw()
	_msg("The %s fell on the ground." % DB.item_name(id))

# ------------------------------------------------------------------ team
func _team_menu() -> bool:
	var a := await TeamScreens.team_menu(ui_root, fs.team(), true, self)
	return await _do_menu_action(a)

# ------------------------------------------------------------------ ground
## Red's Ground command: the item at your feet (Items window, Ground page), the trap (Tile underfoot:
## Trigger / Info), the stairs (Proceed / Info), or "There is nothing at X's feet."
func _ground_menu() -> bool:
	var L := fs.leader
	if fs.items.has(L.pos):
		return await _items_menu(true)
	if fs.traps.has(L.pos) and fs.traps[L.pos].get("seen", false):
		return await _tile_menu()
	if L.pos == fs.stairs:
		if await _stairs_menu():
			Audio.sfx("stairs")
			busy = true
			await next_floor()
			busy = false
			return true
		return false
	await TeamScreens.say(ui_root, "There is nothing at %s's feet." % L.name)
	return false

func _tile_menu() -> bool:
	var L := fs.leader
	while not result_sent:
		var t: Dictionary = fs.traps.get(L.pos, {})
		if t.is_empty():
			return false
		var td: Dictionary = TeamScreens.text().get("traps", {}).get(str(t.id), {})
		var nm := str(td.get("name", str(t.id).capitalize() + " Trap"))
		var m := TeamScreens.menu("Tile underfoot", [nm], 240)
		m.keep_on_pick = true
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		if r.act != "pick":
			return false
		var c := await TeamScreens.submenu(ui_root, m, ["Trigger", "Info"])
		if c == "Trigger":
			busy = true
			await trigger_trap(L, L.pos)
			await _menu_turn()
			return true
		elif c == "Info":
			await TeamScreens.show_text(ui_root, nm, str(td.get("desc", "")))
		if TeamScreens.auto_on():
			return false
	return false

# ------------------------------------------------------------------ others
## Red's Others menu (dungeon_menu_others.c).
func _others_menu() -> bool:
	var sel := 0
	while not result_sent:
		var can_recruit := bool(ddata.get("recruit", true))
		var rows: Array = ["Game Options", "Quicksave or Give Up", "Message log", "Mission objectives",
			{"text": "Recruitment search" if can_recruit else "[color=#ff8070]Recruitment search[/color]", "disabled": not can_recruit}, "Hints"]
		var m := TeamScreens.menu("Others", rows, 288)
		m.sel = sel
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		if r.act != "pick":
			return false
		sel = r.i
		match r.i:
			0: await open_settings()
			1:
				if await _quicksave_give_up():
					return true
			2: await open_log()
			3: await _mission_objectives()
			4: await _recruitment_search()
			5: await _hints_menu()
		if TeamScreens.auto_on():
			return false
	return false

func _quicksave_give_up() -> bool:
	var m := TeamScreens.menu("Quicksave", ["Quicksave", "Give Up"], 200)
	var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
	if r.act != "pick":
		return false
	if r.i == 0:
		var q := await TeamScreens.ask(ui_root, "Quicksave and stop playing for now?\nChoose Resume on the title screen to continue.", ["Yes", "No"], 1)
		if q == 0:
			DungeonSave.save_and_quit(self)
			return true
		return false
	var c := await TeamScreens.ask(ui_root, "Give up on this adventure?\nIf you do, it will be treated as a defeat.", ["Yes", "No"], 1)
	if c == 0:
		exit_summary = LastOuting.summary("gave_up", fs.leader)
		_end("defeated")
		return true
	return false

func open_log() -> void:
	var lines: Array = hud.log_all.duplicate() if hud else []
	if lines.is_empty():
		lines = [" "]
	var sc := Hud.msg_scale()                   # Game Options "Message size"
	var per := int(round(7 / sc))
	var fs := int(round(UITheme.FONT_SIZE * sc))
	var n := ceili(lines.size() / float(per))
	var pg := TeamScreens.InfoPage.new()
	pg.count = n
	pg.page = n - 1
	pg.width = 448
	if fs % 11 != 0:
		UITheme.font_free_scale()                  # writes the freely scaling font for [font=...]
	var fpath := "" if fs % 11 == 0 else "[font=%s]" % UITheme.FONT_FREE_PATH
	var fend := "" if fpath == "" else "[/font]"
	pg.builder = func(i): return {"title": "Message log", "parts": ["%s[font_size=%d]%s[/font_size]%s" % [fpath, fs, "\n".join(lines.slice(i * per, (i + 1) * per)), fend]]}
	await TeamScreens.run_page(ui_root, pg, Vector2(TeamScreens.WIN_X, 8))

## Red's Mission objectives (post_office_guide2.c DisplayMissionObjectives).
func _mission_objectives() -> void:
	var lines: Array = []
	for j in Game.jobs:
		if str(j.get("dungeon", "")) != dkey or not str(j.get("state", "")) in ["taken", "done_pending", "done"]:
			continue
		var fl := "" if j.kind == "find" else "%dF" % int(j.get("floor", 1))
		var what := ""
		match str(j.kind):
			"deliver": what = "Bring [color=#7fff7f]%s[/color]" % DB.item_name(str(j.get("item", "")))
			"find": what = "Find [color=#7fff7f]%s[/color]" % DB.item_name(str(j.get("item", "")))
			"escort": what = "Escort to [color=#ffdc4a]%s[/color]" % Missions.sp_name(str(j.get("target", "")))
			_: what = "Rescue [color=#ffdc4a]%s[/color]" % Missions.sp_name(str(j.get("target", "")))
		lines.append({"table": 2, "cells": ["%s  " % fl if fl != "" else "", what]})
	var parts: Array = []
	if lines.is_empty():
		parts.append("Just go!")
	else:
		parts.append_array(lines)
	await TeamScreens.run_page(ui_root, TeamScreens.page("Objectives", parts, 320))

## Red's Recruitment search: the Pokémon that can appear (and join) on this floor.
func _recruitment_search() -> void:
	var fdata: Dictionary = ddata.floors[floor_i]
	var lines: Array = []
	var seen := {}
	for e in fdata.get("pk", []):
		var sp := str(e[0])
		if seen.has(sp) or not DB.species.has(sp) or int(DB.species[sp].get("recruit", 0)) == -999:
			continue
		var sp4 := sp.substr(0, 4)
		if sp4 in NEVER_RECRUIT or (RECRUIT_AFTER.has(sp4) and not BossScene.get_flag(str(RECRUIT_AFTER[sp4]))):
			continue                                   # Red's list skips Pokémon that can't join yet (IsMonsterRecruitable)
		seen[sp] = true
		var got := false
		for f in Game.friends:
			if str(f.get("sp", "")) == sp:
				got = true
		lines.append(("[color=#7fe0ff]%s[/color]" if got else "%s") % DB.species[sp].name)
	var parts: Array = ["Potential recruits\n", "  " + ("\n  ".join(lines) if lines.size() > 0 else "None")]
	await TeamScreens.run_page(ui_root, TeamScreens.page("Recruitment search", parts, 320))

## Red's Hints (gHintsNames / gHintsDescriptions), with the controls rewritten for this game's keys.
const HINTS := [
	["Controls", "Shift+Space: Use set move\nX: Menu   M: Moves   I: Items\nShift+I: Throw set item\nAlt+Arrows or Q/E/Z/C: Move diagonally\nTab: Floor map\nCtrl+Arrows: Turn without moving\nP: Autoplay"],
	["Orientation", "Avoid attacks by moving diagonally.\nKeeping Alt pressed, press the Arrows\nto move only diagonally.\nIt's also crucial to change the direction\nyou're facing without taking a step.\nJust hold Ctrl!"],
	["Seeds", "Seeds can be thrown.\nThey are usually for eating, but throw\nthem at foes to get the same effect.\nIf you have any Seeds you don't want\nto eat, try throwing them at foes.\nYou can also throw them at partners.\nIf they hit, their effects will be felt."],
	["Moves", "Normal-, Steel-, Poison-, Ground-,\nFlying-, Bug-, Rock-, Ghost-, and\nFighting-type moves are based on\nAttack and Defense. Fire-, Dark-,\nWater-, Grass-, Electric-, Ice-,\nPsychic-, and Dragon-type moves\nare based on Sp. Atk. and Sp. Def."],
	["Range", "All moves have a range of effect.\nA move that affects a room, such as\nGrowl, reaches 2 tiles when in a\ncorridor. However, if the visibility is\nlimited to only 1 tile, the move's\nrange will be likewise restricted.\nCheck the descriptions of moves!"],
	["Linking moves", "Moves can be linked at the Gulpin Link\nShop or by using a Link Box.\nTwo moves can be linked and used\nsimultaneously.\nIf they're used even once in defeating\na foe, you will earn more Exp. Points,\nbut your Belly will go down faster, too."],
	["Extras", "Hold Shift (B) and tap a direction to\nrun until something comes up.\nTap or click a tile to walk there; tap a\nfoe next to you to attack it.\nHold, hover or right-click a Pokémon\nto see its info. Game Options > Others\nturns these extras on and off."],
	["Pokémon types", "There are seventeen types of Pokémon\nand moves: Normal, Fire, Water, Grass,\nElectric, Ice, Fighting, Poison, Ground,\nFlying, Psychic, Bug, Rock, Ghost,\nDragon, Dark, and Steel. All Pokémon\nhave one or two types that determine\nthe damage they take and give."],
]

func _hints_menu() -> void:
	var sel := 0
	while true:
		var names: Array = []
		for h in HINTS:
			names.append(h[0])
		var m := TeamScreens.menu("Hints", names, 200)
		m.sel = sel
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		if r.act != "pick":
			return
		sel = r.i
		var pg := TeamScreens.InfoPage.new()
		pg.count = HINTS.size()
		pg.page = r.i
		pg.builder = func(i): return {"title": HINTS[i][0], "parts": [HINTS[i][1]]}
		await TeamScreens.run_page(ui_root, pg, Vector2(TeamScreens.WIN_X, 8))
		if TeamScreens.auto_on():
			return

# ------------------------------------------------------------------ Game Options
## Red's Game Options: Dungeon / Others / Default; Left/Right change a setting, leaving asks
## "Change the settings?". Settings kept from before: zoom, hunger, Autoplay, touch controls, speed.
const ZOOMS := [0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]

func open_settings() -> void:
	var sel := 0
	while true:
		var m := TeamScreens.menu("Game Options", ["Dungeon", "Others", "Controls", "Default"], 200)
		m.sel = sel
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		if r.act != "pick":
			return
		sel = r.i
		match r.i:
			0: await _option_page("Dungeon", ["speed", "zoom", "map", "hunger", "autoplay"])
			1: await _option_page("Others", ["ui_scale", "touch"] + QOL.KEYS)
			2: await Controls.menu(ui_root)
			3:
				if await TeamScreens.ask(ui_root, "Reset the options to their default setting?", ["Yes", "No"], 1) == 0:
					_apply_options({"speed": 1, "zoom": 1.25, "hunger": true, "autoplay": false, "touch": hud.touch_ui}.merged(QOL.DEFAULTS))
		if TeamScreens.auto_on():
			return

func _option_values() -> Dictionary:
	return {"speed": clampi(int(Game.settings.get("msg_speed", 1)), 0, 2), "zoom": float(Game.settings.get("zoom", 1.25)),
		"hunger": bool(Game.settings.get("hunger", true)), "autoplay": autoplay, "map": RedMap.map_mode(), "ui_scale": UITheme.ui_scale_index(), "touch": hud.pad.visible}.merged(qol.option_values() if qol else {})

func _choice(opts: Array, cur: int) -> String:
	var out: Array = []
	for k in opts.size():
		out.append(("[color=#ffdc4a]%s[/color]" if k == cur else "[color=#8890b0]%s[/color]") % opts[k])
	return "  ".join(out)

func _option_row(k: String, v: Dictionary) -> Dictionary:
	match k:
		"speed": return {"text": "Speed", "right": _choice(["Slow", "Normal", "Fast"], int(v.speed))}
		"zoom": return {"text": "Zoom", "right": "%s %sx %s" % [TeamScreens.ARROW_L, str(snappedf(float(v.zoom), 0.01)), TeamScreens.ARROW_R]}
		"hunger": return {"text": "Hunger", "right": _choice(["Off", "On"], int(v.hunger))}
		"map": return {"text": "Map", "right": _choice(["Off", "Clear", "Shade"], int(v.map))}
		"ui_scale": return {"text": "Menu size", "right": UITheme.slider_text(int(v.ui_scale))}
		"autoplay": return {"text": "Autoplay", "right": _choice(["Off", "On"], int(v.autoplay))}
		"touch": return {"text": "Touch controls", "right": _choice(["Off", "On"], int(v.touch))}
	if qol:
		return qol.option_row(k, v)
	return {"text": k}

func _option_page(title: String, keys: Array) -> void:
	var v := _option_values()
	var orig := v.duplicate()
	var sel := 0
	var picked := false
	while true:
		var rows: Array = []
		for k in keys:
			rows.append(_option_row(k, v))
		var mw := mini(360, int(ui_root.get_viewport_rect().size.x) - 2 * int(TeamScreens.WIN_X))   # fits at any menu size
		var m := TeamScreens.menu(title, rows, mw)
		m.lr = true
		m.sel = sel
		var r := await TeamScreens.run_menu(ui_root, m, Vector2(TeamScreens.WIN_X, TeamScreens.WIN_Y))
		sel = int(r.get("i", sel))
		if r.act == "left" or r.act == "right":
			var d := -1 if r.act == "left" else 1
			var k: String = keys[sel]
			match k:
				"speed": v.speed = clampi(int(v.speed) + d, 0, 2)
				"map": v.map = posmod(int(v.map) + d, 3)
				"ui_scale": v.ui_scale = clampi(int(v.ui_scale) + d, 0, UITheme.UI_SCALE_STEPS)
				"zoom":
					var zi := 0
					for n in ZOOMS.size():
						if absf(float(ZOOMS[n]) - float(v.zoom)) < absf(float(ZOOMS[zi]) - float(v.zoom)):
							zi = n
					v.zoom = ZOOMS[clampi(zi + d, 0, ZOOMS.size() - 1)]
				_:
					if not (qol and qol.option_change(k, v, d)):
						v[k] = not bool(v[k])
			continue
		picked = r.act == "pick"
		break
	if v == orig and not picked:
		return
	if await TeamScreens.ask(ui_root, "Change the settings?", ["Yes", "No"], 0) == 0:
		_apply_options(v)

func _apply_options(v: Dictionary) -> void:
	Game.settings.msg_speed = int(v.speed)
	set_zoom(float(v.zoom))
	Game.settings.map_mode = int(v.map)
	if int(v.ui_scale) != UITheme.ui_scale_index():
		UITheme.set_ui_scale_index(int(v.ui_scale))
		set_zoom(float(Game.settings.get("zoom", 1.25)))
	if red_map:
		red_map.refresh()
	var was_hunger := bool(Game.settings.get("hunger", true))
	Game.settings.hunger = bool(v.hunger)
	if not Game.settings.hunger:
		belly = belly_max
		belly_state.belly = belly
	if was_hunger != Game.settings.hunger:
		_msg("Hunger is now %s." % ("on" if Game.settings.hunger else "off"))
	if bool(v.touch) != hud.pad.visible:
		hud.set_touch_visible(bool(v.touch))
	if bool(v.autoplay) != autoplay:
		set_autoplay(bool(v.autoplay))
	if qol:
		qol.apply_options(v)
	Game.save_game()

# ================================================================= map / vision
func _reveal() -> void:
	var t0 := Time.get_ticks_usec()
	_reveal_i()
	if perf_log:
		pacc("reveal", Time.get_ticks_usec() - t0)

func _reveal_i() -> void:
	for t in fs.team():
		var r := fs.room_at(t.pos)
		if r != 255 and r < fs.rooms.size():
			var rc: Rect2i = fs.rooms[r].grow(1)
			for y in range(rc.position.y, rc.end.y):
				for x in range(rc.position.x, rc.end.x):
					if fs.inb(Vector2i(x, y)):
						fs.explored[y * fs.w + x] = 1
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var p: Vector2i = t.pos + Vector2i(dx, dy)
				if fs.inb(p):
					fs.explored[fs.idx(p)] = 1
		# traps next to the team become visible only when stepped on / revealed (Red)
	Pokedex.see_visible(self)           # marks every non-team Pokémon a team member can see
	if _map_on:
		_map_node().queue_redraw()
	if red_map:
		red_map.refresh()

var _map: Control
func _map_node() -> Control:
	if _map == null:
		_map = Control.new()
		_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_map.draw.connect(_draw_map)
		ui_root.add_child(_map)
		ui_root.move_child(_map, 0)
	return _map

func _toggle_map() -> void:
	_map_on = not _map_on
	_map_node().visible = _map_on
	_map_node().queue_redraw()
	_ensure_red_fx()
	if red_map:
		red_map.full = _map_on          # Red's floor map mode (Select): dungeon off, map on black
		red_map.refresh()

func _draw_map() -> void:
	if not _map_on or fs == null or qol == null:
		return
	if red_map:
		return                      # drawn by RedMap (zmappat tiles)
	qol.draw_full_map(_map)     # Red-style see-through map: explored tiles, stairs, items, seen traps, Pokémon

# ================================================================= helpers
func _nm(m: Mon) -> String:
	if m == null:
		return "?"
	return ("[color=#ffdc4a]%s[/color]" if m.is_team() else "[color=#7fe0ff]%s[/color]") % m.name

func _msg(t: String) -> void:
	var t0 := Time.get_ticks_usec()
	var f0 := Engine.get_process_frames()
	_msg_i(t)
	if perf_log and Engine.get_process_frames() == f0:
		pacc("msg", Time.get_ticks_usec() - t0)

func _msg_i(t: String) -> void:
	if t == "" or hud == null:
		return
	hud.msg(t)

func _update_hud() -> void:
	var t0 := Time.get_ticks_usec()
	_update_hud_i()
	if perf_log:
		pacc("update_hud", Time.get_ticks_usec() - t0)

func _update_hud_i() -> void:
	if hud and fs and fs.leader:
		hud.set_status(_floor_label(), fs.leader, int(ceil(belly)))
		_ensure_qol()
		qol.on_update()
		_ensure_red_fx()
		red_map.refresh()

## Moves window damage preview for `who`'s move (DungeonQoL; "" when the option is off).
func move_preview(who, move_name: String) -> String:
	return qol.move_preview(who, move_name) if qol else ""


# ================================================================= Autoplay
## Explores, fights, picks up items and takes the stairs by itself.
## Stops when you press any control, when HP is low with nothing to heal, or when a menu needs you.
func set_autoplay(on: bool) -> void:
	if autoplay == on:
		return
	autoplay = on
	_auto_target = Vector2i(-1, -1)
	_msg("Autoplay [color=#7fff7f]on[/color]." if on else "Autoplay off.")
	if hud:
		hud.set_auto(on)

var _auto_last := Vector2i(-99, -99)
var _auto_still := 0
var _auto_ignore := {}          # positions Autoplay gave up on this floor (unreachable / blocked)
var _auto_floor := -1

func autoplay_step() -> void:
	var L := fs.leader
	# standing still: an unreachable goal or a blocked step (a peaceful Pokémon, a shopkeeper, water...)
	if _auto_floor != floor_i:
		_auto_floor = floor_i
		_auto_ignore.clear()
	if L.pos == _auto_last:
		_auto_still += 1
	else:
		_auto_still = 0
		_auto_last = L.pos
	if _auto_still >= 4 and fs.adjacent_foes(L).is_empty():
		_auto_still = 0
		if _auto_target.x >= 0:
			_auto_ignore[_auto_target] = true
		_auto_target = Vector2i(-1, -1)
		for o in fs.foes_of(L):
			if fs.can_see(L, o.pos) and fs.path_dir(L, o.pos, 2500, true) < 0:
				_auto_ignore[o.pos] = true
		var opts: Array = []
		for k in 8:
			var q: Vector2i = L.pos + DB.DIRS[k]
			if fs.can_step(L.pos, k, L) and fs.mon_at(q) == null:
				opts.append(k)
		if not opts.is_empty():
			leader_action({"type": "move", "dir": opts[fs.rng.randi() % opts.size()]})
			return
	# low HP: eat a healing berry, or stop and hand control back
	if L.hp * 3 <= L.max_hp:
		for i in Game.bag.size():
			var k: String = DB.items.get(Game.bag[i].id, {}).get("kind", "")
			if k == "heal" or k == "sitrus":
				busy = true
				await use_item(L, i)
				await world_turn()
				busy = false
				_update_hud()
				return
		if not fs.adjacent_foes(L).is_empty() or L.hp * 5 <= L.max_hp:
			set_autoplay(false)
			_msg("[color=#ff8070]HP is low! Autoplay stopped.[/color]")
			return
	# hungry: eat food
	if bool(Game.settings.get("hunger", true)) and belly <= 10:
		for i in Game.bag.size():
			if DB.items.get(Game.bag[i].id, {}).get("kind", "") == "food":
				busy = true
				await use_item(L, i)
				await world_turn()
				busy = false
				return
	# fight an adjacent foe with the strongest usable move
	var adj := fs.adjacent_foes(L)
	if not adj.is_empty():
		adj.sort_custom(func(a, b): return a.hp < b.hp)
		var t: Mon = adj[0]
		var d := DB.dir_index(t.pos - L.pos)
		leader_action({"type": "attack", "move": _auto_best_move(L, t), "dir": d})
		return
	# a visible foe in line for a ranged move
	for o in fs.foes_of(L):
		if not fs.can_see(L, o.pos):
			continue
		var dv: Vector2i = o.pos - L.pos
		if (dv.x == 0 or dv.y == 0 or absi(dv.x) == absi(dv.y)) and FloorState.cheb(L.pos, o.pos) <= LINE_RANGE:
			var dd := DB.dir_index(dv)
			for mv in L.moves:
				var md: Dictionary = DB.moves.get(mv.name, {})
				if int(mv.pp) > 0 and md.get("r", "") == "line" and int(md.get("p", 0)) > 0 and _clear_line(L.pos, dd, o.pos):
					leader_action({"type": "attack", "move": mv.name, "dir": dd})
					return
	# a visible foe not next to us: throw a throwing item from the Toolbox (straight ones need a clear line,
	# Gravelerock / Geo Pebble arc over everything within 10 tiles)
	var thr := _auto_throw(L)
	if not thr.is_empty():
		leader_action(thr)
		return
	# goal: nearest visible foe, else visible item, else unexplored area, else stairs.
	# Once the wind starts stirring (or in unattended tests) head straight for known stairs.
	var goal := Vector2i(-1, -1)
	var best := 9999
	# a job client in sight: walk up to it (the client prompt opens when adjacent)
	for m in fs.mons:
		if m.hp > 0 and Missions.is_client(m) and not m.get_meta("asked", false) and not Missions.still_needs_item(m) and fs.can_see(L, m.pos):
			var dc := fs.path_dir(L, m.pos, 2500, true)
			if dc >= 0 and FloorState.cheb(L.pos, m.pos) > 1:
				leader_action({"type": "move", "dir": dc})
				return
	if test_want != "" and int(wind_state.get("phase", 0)) < 2:
		for p in fs.items:
			if str(fs.items[p].get("id", "")) == test_want and int(fs.items[p].get("price", 0)) == 0 and fs.explored[fs.idx(p)] == 1:
				if p == L.pos:
					break
				var dw := fs.path_dir(L, p, 2500, true)
				if dw >= 0:
					leader_action({"type": "move", "dir": dw})
					return
	var no_task: bool = Missions.jobs_for_floor(dkey, floor_i + 1).is_empty() and not _floor_has_want()
	var hurry: bool = int(wind_state.get("phase", 0)) >= 1 or (test_invincible and no_task)
	var stairs_known: bool = fs.stairs.x >= 0 and fs.explored[fs.idx(fs.stairs)] == 1 and fs.path_dir(L, fs.stairs, 2500, true) >= 0
	if hurry and stairs_known:
		leader_action({"type": "move", "dir": fs.path_dir(L, fs.stairs, 2500, true)})
		return
	# the stairs are known and nothing on this floor needs doing: grab what's close by, then go down
	# (exploring every corner first looked like aimless wandering)
	if stairs_known and no_task:
		var near := Vector2i(-1, -1)
		var nd := 6
		for p in fs.items:
			if Game.bag.size() >= Game.BAG_MAX and str(fs.items[p].get("id", "")) != "poke":
				continue
			if int(fs.items[p].get("price", 0)) == 0 and fs.explored[fs.idx(p)] == 1 and not _auto_ignore.has(p) and p != L.pos:
				var di := FloorState.cheb(L.pos, p)
				if di < nd and fs.path_dir(L, p, 400, true) >= 0:
					nd = di
					near = p
		var tgt := near if near.x >= 0 else fs.stairs
		var ds := fs.path_dir(L, tgt, 2500, true)
		if ds >= 0:
			if near.x >= 0:
				_auto_target = near
			leader_action({"type": "move", "dir": ds})
			return
	for o in fs.foes_of(L):
		if fs.can_see(L, o.pos) and not _auto_ignore.has(o.pos):
			var dist := FloorState.cheb(L.pos, o.pos)
			if dist < best:
				best = dist
				goal = o.pos
	if goal.x < 0:
		for p in fs.items:
			if Game.bag.size() >= Game.BAG_MAX and str(fs.items[p].get("id", "")) != "poke":
				continue      # Toolbox full: don't keep walking onto items it can't pick up
			if int(fs.items[p].get("price", 0)) == 0 and fs.explored[fs.idx(p)] == 1 and not _auto_ignore.has(p):
				var dist2 := FloorState.cheb(L.pos, p)
				if dist2 < best:
					best = dist2
					goal = p
	if goal.x < 0:
		if _auto_target.x < 0 or fs.explored[fs.idx(_auto_target)] == 1 or _auto_target == L.pos:
			_auto_target = _nearest_unexplored(L)
		goal = _auto_target
	if goal.x < 0 or fs.explored[fs.idx(fs.stairs)] == 1 and _nearest_unexplored(L).x < 0:
		goal = fs.stairs
	if goal.x < 0:
		goal = fs.stairs
	var d2 := fs.path_dir(L, goal, 2500, true)
	if d2 < 0:
		_auto_target = Vector2i(-1, -1)
		d2 = fs.path_dir(L, fs.stairs, 2500, true)
	if d2 < 0:
		leader_action({"type": "wait"})
		return
	leader_action({"type": "move", "dir": d2})

## Autoplay's throw: the cheapest throwing item in the Toolbox at the nearest visible foe it can hit.
func _auto_throw(L: Mon) -> Dictionary:
	var best_i := -1
	var best_price := 1 << 30
	for i in Game.bag.size():
		var id := str(Game.bag[i].id)
		if not id in AI.AI_THROWN_ITEMS or Game.bag[i].get("sticky", false):
			continue
		var pr := int(DB.items.get(id, {}).get("price", 0))
		if pr < best_price:
			best_price = pr
			best_i = i
	if best_i < 0:
		return {}
	var arc: bool = str(DB.items.get(str(Game.bag[best_i].id), {}).get("red_cat", "")) == "thrown_arc"
	var foes: Array = fs.foes_of(L).filter(func(o): return o.hp > 0 and fs.can_see(L, o.pos) and not Missions.is_client(o))
	foes.sort_custom(func(a, b): return FloorState.cheb(L.pos, a.pos) < FloorState.cheb(L.pos, b.pos))
	for o in foes:
		var dist := FloorState.cheb(L.pos, o.pos)
		if dist < 2:
			continue
		if arc:
			if dist <= AI.ARC_RANGE:
				return {"type": "throw", "bag": best_i, "dir": AI.dir_toward(L.pos, o.pos), "target": o.pos}
			continue
		var dv: Vector2i = o.pos - L.pos
		if (dv.x == 0 or dv.y == 0 or absi(dv.x) == absi(dv.y)) and dist <= LINE_RANGE:
			var dd := DB.dir_index(dv)
			if _clear_line(L.pos, dd, o.pos):
				return {"type": "throw", "bag": best_i, "dir": dd}
	return {}

func _auto_best_move(L: Mon, t: Mon) -> String:
	var best := ""
	var best_score := 1.0   # regular attack baseline
	for mv in L.moves:
		var md: Dictionary = DB.moves.get(mv.name, {})
		if int(mv.pp) <= 0 or int(md.get("p", 0)) <= 0:
			continue
		if not md.get("r", "front") in ["front", "front_corners", "line", "two_tiles", "room", "adjacent", "front_spread"]:
			continue
		var eff := Combat.type_eff(str(md.get("t", "Normal")), t.types)
		var score := float(md.get("p", 0)) * Combat.eff_multiplier(eff) * (1.5 if md.get("t", "") in L.types else 1.0) / 3.0
		if score > best_score:
			best_score = score
			best = mv.name
	return best

func _clear_line(from: Vector2i, d: int, to: Vector2i) -> bool:
	var p := from
	for i in LINE_RANGE:
		p += DB.DIRS[d]
		if fs.is_wall(p):
			return false
		if p == to:
			return true
		if fs.mon_at(p):
			return false
	return false

func _nearest_unexplored(L: Mon) -> Vector2i:
	var seen := {L.pos: true}
	var q: Array = [L.pos]
	var head := 0
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		if fs.explored[fs.idx(c)] == 0:
			return c
		for d in 8:
			if not fs.can_step(c, d, L):
				continue
			var n: Vector2i = c + DB.DIRS[d]
			if seen.has(n):
				continue
			seen[n] = true
			q.append(n)
	return Vector2i(-1, -1)

func _tile_seen(q: Vector2i) -> bool:
	return fs.explored[fs.idx(q)] == 1

# ================================================================= Red presentation (status icons, weather,
# darkness, map, banner, join / level-up texts, The Last Outing). See the scripts they use for the sources.
const RED_LEADER_RECRUITS := true       # dungeon_damage.c: a KO only recruits when the team leader made it
var red_fx: DungeonFx = null            # darkness around the leader, weather colour ramp and animation
var red_status: StatusIcons = null      # status icons over the Pokémon
var red_map: RedMap = null              # Red's map overlay (Map option) and floor map (Select)
var exit_summary: Dictionary = {}       # dungeon exit summary for "The Last Outing"

func _ensure_red_fx() -> void:
	if red_fx == null or not is_instance_valid(red_fx):
		red_fx = DungeonFx.new()
		red_fx.dg = self
		add_child(red_fx)
	if red_status == null or not is_instance_valid(red_status):
		red_status = StatusIcons.new()
		red_status.dg = self
		add_child(red_status)
	if (red_map == null or not is_instance_valid(red_map)) and ui_root != null:
		red_map = RedMap.new()
		red_map.dg = self
		ui_root.add_child(red_map)
		ui_root.move_child(red_map, 0)

## Exp. for a KO (CalculateEXPGain) to the team members that were there.
func _give_ko_exp(team: Array, t: Mon) -> void:
	var S: Dictionary = DB.species.get(t.sp, {})
	var y := int(S.get("exp", 10))
	var gain := maxi(1, y + (y * (t.level - 1)) / 10)
	for tm in team:
		if tm.hp > 0 and fs.mons.has(tm) and not is_temp(tm):      # DX: temporary members gain no Exp.
			await gain_exp(tm, IQSky.exp_gain(tm, gain))

## Exit reason when the leader (or a story Pokémon) faints (GetDungeonExitReasonFromMoveOrItemID etc.).
func _faint_summary(t: Mon, killer: Mon) -> Dictionary:
	if killer and killer != t:
		return LastOuting.summary("move", t, killer, killer.last_move if killer.last_move != "" else "Attack")
	var reason := "powerful_move"
	if belly <= 0.0:
		reason = "hunger"
	elif t.has_status("burn"):
		reason = "burn"
	elif t.has_status("poison") or t.has_status("badpoison"):
		reason = "poison"
	elif t.has_status("curse"):
		reason = "curse"
	elif t.has_status("wrapped"):
		reason = "wrap"
	elif t.has_status("leech_seed"):
		reason = "leech_seed"
	elif t.has_status("perish"):
		reason = "perish_song"
	elif t.has_status("nightmare"):
		reason = "nightmare"
	elif str(fs.weather) in ["hail", "sandstorm"]:
		reason = "weather"
	elif fs.traps.has(t.pos):
		reason = "trap"
	return LastOuting.summary(reason, t)

func _end_summary(res: String) -> Dictionary:
	var who: Mon = fs.leader if fs and fs.leader else (team_mons[0] if not team_mons.is_empty() else null)
	match res:
		"cleared":
			return LastOuting.summary("cleared", who)
		"rescued":
			return LastOuting.summary("rescue", who)
		"quit", "escaped":
			return LastOuting.summary("escaped", who)
	return LastOuting.summary("powerful_move", who)

## main.gd calls this when the expedition is over: Red's "The Last Outing" window.
func show_last_outing(root: Control, res: String) -> void:
	if exit_summary.is_empty():
		exit_summary = _end_summary(res)
	if red_map:
		red_map.visible = false
	await LastOuting.show(root, exit_summary, _display_name())

## Red's message box (DisplayDungeonMessage_Async): pages that wait for a button.
func _red_box(pages: Array) -> void:
	if pages.is_empty() or ui_root == null:
		return
	if auto_answer and not Dialog.auto:      # automated runs (menus answer themselves): just log the boxes
		for pg in pages:
			_msg(str(pg).replace("\n", " "))
		return
	var was := menu_open
	menu_open = true
	await Dialog.talk(ui_root, pages)
	menu_open = was

## sub_8070BC0: can this Pokémon talk (level-up line)?
func _can_talk(m: Mon) -> bool:
	for k in ["charging", "yawn", "nightmare", "muzzled", "petrified", "frozen", "confused", "sleep", "invisible",
			"napping", "cringe", "wrapping", "wrapped", "cross_eyed", "decoy", "blinker", "infatuated", "paused"]:
		if m.has_status(k):
			return false
	return str(m.status.get("charge_move", "")) == ""

## sub_807218C: the level-up line (talk file entry 3, or "Yes! $m0 leveled up!"), then
## "$m0's HP went up $d0!" ... in boxes split like gUnknown_8107010 (press, press, newline, press).
func _level_up_boxes(m: Mon, before: Dictionary) -> void:
	var line := ""
	if _can_talk(m):
		if Missions.is_client(m):
			line = DungeonGfx.talk_special("mon_client", 3)
		else:
			line = DungeonGfx.talk(m.sp, 3, m.get_meta("story", false) and not m.is_leader)
	if line == "":
		line = "Yes! $m0 leveled up!"
	var nm := _nm(m)
	var lead := _nm(fs.leader) if fs and fs.leader else nm
	var pages: Array = [line.replace("$m0", nm).replace("$m1", lead)]
	var ups := [["hp", "%s's HP went up %d!"], ["atk", "%s's Attack went up %d!"], ["def", "%s's Defense went up %d!"],
		["spa", "%s's Sp. Atk. went up %d!"], ["spd", "%s's Sp. Def. went up %d!"]]
	var now := {"hp": m.max_hp, "atk": m.atk, "def": m.def, "spa": m.spa, "spd": m.spd}
	const SEP := [0, 1, 1, 2, 1, 1, 0, 0]
	var cur := ""
	var n := 0
	var stat_pages: Array = []
	for u in ups:
		var d := int(now[u[0]]) - int(before[u[0]])
		if d <= 0:
			continue
		if n > 0:
			if SEP[n] == 1:
				stat_pages.append(cur)
				cur = ""
			elif SEP[n] == 2:
				cur += "\n"
		cur += u[1] % [nm, d]
		n += 1
	if cur != "":
		stat_pages.append(cur)
	await _red_box(pages)
	await _red_box(stat_pages)

## The end of MonsterJoinSequence_Async after the Pokémon accepted: fanfare (0xCC), a pause, the nickname
## question, "$m0 joined $t to go on adventures!".
func _join_sequence(t: Mon) -> void:
	Audio.sfx("join")
	if is_temp(t):                     # DX: joins for this dungeon; the nickname comes if it stays at the exit
		_msg("%s joined the team for this adventure!" % _nm(t))
		return
	if not (auto_answer or Dialog.auto):
		await get_tree().create_timer(160.0 / 60.0).timeout
	menu_open = true
	var nick := 1
	if not auto_answer and not Dialog.auto:
		nick = await Dialog.ask(ui_root, "A new member joined the team!\nGive it a nickname?", ["Yes", "No"], "", "Normal", false)
	if nick == 0:
		await _nickname(t)
	menu_open = false
	var team := str(Game.story_get("team_name", Game.team_name)) if Game.has_method("story_get") else str(Game.team_name)
	_msg("%s joined [color=#ffdc4a]%s[/color] to go on adventures!" % [_nm(t), team])

## ---- NAMING SCREEN CALL SITE --------------------------------------------------------------------------
## Red opens the naming screen here (DungeonGiveNameToRecruitedMon; an empty name repeats
## "Please give your new team member\na proper nickname!"). Uses scripts/ui/naming_screen.gd (NamingScreen.ask);
## without it the Pokémon keeps its species name.
func _nickname(t: Mon) -> void:
	const NS_PATH := "res://scripts/ui/naming_screen.gd"
	if not ResourceLoader.exists(NS_PATH):
		return
	var NS = load(NS_PATH)
	var got = null
	while true:
		if NS.has_method("ask"):
			got = await NS.ask(ui_root, 2, t.name)        # NamingScreen.POKEMON (sub_803EAF0(8, name))
		elif NS.has_method("nickname"):
			got = await NS.nickname(ui_root, t.name, t.sp)
		elif NS.has_method("ask_name"):
			got = await NS.ask_name(ui_root, t.name)
		elif NS.has_method("run"):
			got = await NS.run(ui_root, t.name)
		else:
			return
		if got is String and String(got).strip_edges() != "":
			break
		await _red_box(["Please give your new team member\na proper nickname!"])
	t.name = String(got).strip_edges()
	if t.has_meta("entry"):
		var e: Dictionary = t.get_meta("entry")
		e["name"] = t.name

## tests: a floor with anything the story or a job needs is never skipped
func _test_story_floor() -> bool:
	if boss != null or not eos_arena.is_empty() or fixed_no != 0:
		return true
	if test_want != "" and _floor_has_want():
		return true
	for m in fs.mons:
		if Missions.still_needs_item(m):
			continue          # a delivery the team can't make: nothing more to do here
		if m.side == "client" or m.get_meta("story_npc", false) or m.get_meta("client", false) or m.has_meta("job_id") or m.has_meta("escort_job"):
			return true
	return false

## Red's floating damage number (dungeon_vram.c sub_803ED30 / sub_803EF90 / sub_803EDF0): an 8 px hp5font
## sprite above the Pokémon: "-N" in palette 3 (yellow) for damage, "+N" in palette 10 (green) for gains,
## "MISS" (value 9999, palette 10), below -999 palette 6. Each glyph advances 6 px; the sprite is centred by
## 3 px per glyph and rises 46/256 px a frame for 60 frames.
func red_number(t: Mon, value: int) -> void:
	if t == null or t.visual == null or value == 0:
		return
	var tiles: Array = []
	var row := 0
	if value == 9999:
		tiles = [13, 14, 15, 15]
		row = 1
	else:
		var v := clampi(value, -999, 999)
		row = 2 if value < -999 else (1 if value >= 0 else 0)
		tiles.append(10 if v > 0 else 11)
		for ch in str(absi(v)):
			tiles.append(int(ch))
	var tex := DB.tex("res://assets/ui/dmg_digits.png")
	if tex == null:
		return
	var n := Node2D.new()
	n.z_index = 7
	n.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var w := tiles.size() * 6 + 2
	n.draw.connect(func():
		for i in tiles.size():
			n.draw_texture_rect_region(tex, Rect2(i * 6 - w / 2.0, 0, 8, 8), Rect2(int(tiles[i]) * 8, row * 8, 8, 8)))
	n.position = (t.visual.position + Vector2(0, -20)).round()
	fx_layer.add_child(n)
	var tw := create_tween()
	tw.tween_property(n, "position:y", n.position.y - 46.0 * 60.0 / 256.0, 1.0)
	tw.tween_callback(n.queue_free)

## Red sub_805E738 (entering rotate mode): turn toward a visible enemy. Red checks the 7 neighbouring tiles
## starting clockwise from the current facing; when none is adjacent we turn toward the nearest visible foe.
func _face_nearest_foe() -> void:
	var L := fs.leader
	if L == null:
		return
	var d := L.facing
	for j in range(1, 8):
		var k := (d + j) % 8
		var o := fs.mon_at(L.pos + DB.DIRS[k])
		if o and o.hp > 0 and fs.is_foe(L, o) and fs.can_see(L, o.pos):
			L.facing = k
			obj_layer.queue_redraw()
			arrow_layer.queue_redraw()
			return
	var best: Mon = null
	var bd := 1 << 30
	for o in fs.foes_of(L):
		if o.hp <= 0 or not fs.can_see(L, o.pos):
			continue
		var dist := FloorState.cheb(L.pos, o.pos)
		if dist < bd:
			bd = dist
			best = o
	if best:
		var v: Vector2i = best.pos - L.pos
		L.facing = DB.dir_index(Vector2i(signi(v.x), signi(v.y)))
		obj_layer.queue_redraw()
		arrow_layer.queue_redraw()
