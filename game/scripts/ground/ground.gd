class_name Ground
extends Node2D
## Red's ground mode (ground_main.c + ground_map/lives/object/effect/event): runs the original map scripts
## at 60 ticks per second. Emits finished(code) with ground_main's return code when it hands back to the game:
##   5 friend areas map, 6 world map (dungeon select), 7 enter a story dungeon, 8 out-on-rescue dungeon,
##   9 rescue mail dungeon, 10 maze, 14 game end (title), 15/16 demo.

signal finished(code: int)

enum { SP_UNK_0, SP_UNK_1, SP_WAITING, SP_UNK_3, SP_PLAYER_NAME_INPUT, SP_TEAM_NAME_INPUT, SP_PASSWORD_INPUT,
	SP_FRIEND_MENU, SP_MENU, SP_YES_NO_LARGE, SP_LARGE_TEXT, SP_BUY_FRIEND_AREAS, SP_DUNGEON_LIST, SP_DOJO_LIST,
	SP_SAVE_1, SP_SAVE_2, SP_STORAGE_WITH_DIALOG, SP_STORAGE, SP_UNK_12, SP_BANK, SP_UNK_14, SP_UNK_15,
	SP_FRIEND_AREA_SELECT, SP_GREEN_KECLEON, SP_PURPLE_KECLEON, SP_LINK_SHOP, SP_LUMINOUS_CAVE, SP_FRIEND_SHOP,
	SP_FRIEND_RESCUE, SP_UNK_1D, SP_THANK_YOU_MAIL, SP_PPO_HELP, SP_BOARD_JOBS, SP_BOARD, SP_UNK_22, SP_UNK_23,
	SP_DOJO_ENTER, SP_DOJO_SUCCESS, SP_DOJO_FAILURE, SP_DOJO_ALL_CLEARED, SP_PERSONALITY_QUIZ, SP_UNK_29,
	SP_SCRIPTING_MENU, SP_ITEM_REWARD, SP_UNK_2C, SP_TOOL_BOX, SP_CREDITS_NAME }
enum { STARTMODE_NEW_GAME, STARTMODE_CONTINUE_GAME, STARTMODE_GROUND, STARTMODE_3, STARTMODE_FRIEND_AREAS,
	STARTMODE_DUNGEON_FROM_WORLD_MAP, STARTMODE_6, STARTMODE_CONTINUE_QUICKSAVE, STARTMODE_8, STARTMODE_DUNGEON_WON,
	STARTMODE_10, STARTMODE_11, STARTMODE_DUNGEON_LOST }
enum { REQ_NONE, REQ_GROUND, REQ_2, REQ_FRIEND_AREAS, REQ_WORLD_MAP, REQ_RESCUE, REQ_RESCUE_JOB, REQ_RESCUE_MAIL,
	REQ_MAZE, REQ_GAME_END, REQ_GAME_CANCEL }

const N_LIVES := 24
const N_OBJECTS := 16
const N_EFFECTS := 16
const N_EVENTS := 32
const TICK := 1.0 / 60.0

var host                         # main.gd (special text / service UIs)
var ui_root: Control
var text: GText
var camera: GCamera

# script locks
var any_locked := false
var locks: Array = []
var lock_conds: Array = []
var unlock_labels: Array = []
var pending_cues := {}          # cue id -> ticks left (see _unlock)
var cue_last := {}              # cue id -> frame it was last alerted (see _cue_rescue)
var _cue_quiet := 0             # frames since the last cue alert

# entities
var map_action: GAction
var lives: Array = []
var objects: Array = []
var effects: Array = []
var events: Array = []            # {used, kind_id, group, sector, flags, a, b, script}
var lives_meta := {"dir28": -1, "head": -1, "slots": [{"i8": -1, "s0": 0, "s4": 0}, {"i8": -1, "s0": 0, "s4": 0}, {"i8": -1, "s0": 0, "s4": 0}], "trail": []}

# map state
var cur_map := -1                # gCurrentMap
var vis_map := -1                # gUnknown_2039A32 (adjusted map shown)
var station_map := -1            # gUnknown_2039A34
var map_file := ""
static var active_map := ""     # map file on screen (the quiz shows its animated backdrop through)
var map_info: Dictionary = {}
var collision: Array = []
var col_w := 0
var col_h := 0
var bounds_a := Vector2i.ZERO    # dungeon bounds (24.8)
var bounds_b := Vector2i.ZERO
var links: Array = []
var scroll := {"e8": Vector2i.ZERO, "f0": 0, "f4": 0, "f8": Vector2i.ZERO}

# requests (ground_main)
var req := REQ_NONE
var req_count := 0
var req_speed := -1
var req_map := -1
var req_link := 0
var req_dungeon := -1
var start_mode := STARTMODE_CONTINUE_GAME
var _done := false

# nodes
var world: Node2D
var map_lo: Sprite2D
var map_hi: Sprite2D
var anim_nodes: Array = []       # [{node, frames:[[tex,pos,ticks]], t, i}]
var pal_anim := {}               # BPL palette cycling via shader: {img, tex, rows: [{row, colors, ticks, t, i}]}
var edge_fill: Sprite2D
var layer_sprites := {}          # layer file -> Sprite2D (for the palette shader)
var actors: Node2D
var weather: GWeather            # ground_weather.c layer
var dun_view: Node2D
var fade_rect: ColorRect
var flash_rect: ColorRect
var _acc := 0.0
var _frame := 0
var fadeA := {"state": 0, "t": 0, "dur": 1, "lvl": 0x100, "to": 0x100, "d": 0}
var fadeB := {"state": 0, "t": 0, "dur": 1, "lvl": 0x100, "to": 0x100, "d": 0}
var flash_st := {"kind": 0, "fade": {"state": 0, "t": 0, "dur": 1, "lvl": 0x100, "to": 0x100, "d": 0}, "col": Color.BLACK}
var _fade_all := false           # sub_80999D4 (request transition)
var _fade_all_speed := 30
var _pad := {"dir": -1, "a_pressed": false, "b_held": false, "b_pressed": false, "menu_pressed": false, "up": false, "down": false}
var _a_latch := false
var _b_latch := false
var _m_latch := false
var bgm_saved := -1
var _zoom := 1.6875
## the menu-size setting scales the whole canvas (content_scale_factor); the map keeps its size
var zoom: float:
	get: return _zoom / UITheme.ui_scale()
	set(v): _zoom = v
var auto_test := false
var autopilot = null           # GAutopilot (tests)

func _ready() -> void:
	GData.load_all()
	locks.resize(136)
	lock_conds.resize(136)
	unlock_labels.resize(136)
	world = Node2D.new()
	add_child(world)
	edge_fill = Sprite2D.new()           # zoomed out past the map edge: a mirrored copy of the bottom layer
	edge_fill.centered = false
	world.add_child(edge_fill)
	map_lo = Sprite2D.new()
	map_lo.centered = false
	world.add_child(map_lo)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	world.add_child(actors)
	map_hi = Sprite2D.new()
	map_hi.centered = false
	world.add_child(map_hi)
	weather = GWeather.new(self)
	world.add_child(weather)
	var cl := CanvasLayer.new()
	cl.layer = 1
	add_child(cl)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.add_child(fade_rect)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cl.add_child(flash_rect)
	var cl2 := CanvasLayer.new()
	cl2.layer = 2
	add_child(cl2)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl2.add_child(holder)
	# touch: the same on-screen pad + A / Menu buttons as in dungeons and the town (under the text boxes)
	hud = Hud.new()
	holder.add_child(hud)
	hud.top_draw.visible = false
	hud.msg_panel.visible = false
	hud.set_touch_visible(hud.touch_ui)
	for k2 in hud._btns:
		if k2 != "attack" and k2 != "menu":
			hud._btns[k2].visible = false
	hud.button.connect(func(btn: String):
		if btn == "attack":
			_touch_tap = true
		elif btn == "menu":
			_touch_menu = true)
	text = GText.new(self)
	holder.add_child(text)
	camera = GCamera.new(self)
	map_action = GAction.new(self, null, 0, -1, -1)
	for i in N_LIVES:
		lives.append(GLive.new(self, i))
	for i in N_OBJECTS:
		objects.append(GThing.new(self, i, false))
	for i in N_EFFECTS:
		effects.append(GThing.new(self, i, true))
	for i in N_EVENTS:
		events.append({"used": false})
	zoom = float(Game.settings.get("ground_zoom", 1.6875))

# ------------------------------------------------------------------ boot demos (STARTMODE_14..17)
## Red's boot sequence runs DEMO_01..04 (health & safety, company screens, intro + title, title) through
## ground mode with sUnknown_20398B9 set: no script variables are touched, a game end request returns 15 and
## a cancel (a button pressed while sUnknown_20398B8 is FALSE) runs DEMO_CANCEL and returns 16.
var demo := false
var demo_cancel_ok := false          # !sUnknown_20398B8 (special 0x40 / start mode)

func start_demo(n: int, cancel_ok: bool) -> void:
	demo = true
	demo_cancel_ok = cancel_ok
	req = REQ_NONE
	req_count = 0
	req_speed = -1
	req_map = -1
	text.set_auto_press(-1, -1)
	text.clear()
	_reset_locks()
	text.reset_all()
	_map_reset()
	camera.reset()
	_delete_all_entities()
	map_execute_event(GData.fn_id("DEMO_%02d" % n), false)
	map_action.handle()

## Boot screen maps 224-227 hold two stacked copies (the "Press" line blinks by warping the camera) and junk
## tiles past x 240: black out everything outside Red's 240x160 screen (agent "front").
var _demo_mask: Array = []

func _demo_mask_update(on: bool, vs: Vector2) -> void:
	if _demo_mask.is_empty():
		if not on:
			return
		for i in 4:
			var r := ColorRect.new()
			r.color = Color.BLACK
			r.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fade_rect.get_parent().add_child(r)
			fade_rect.get_parent().move_child(r, 0)
			_demo_mask.append(r)
	var sz := Vector2(240, 160) * zoom
	var tl := ((vs - sz) / 2.0).round()
	var br := tl + sz.round()
	var rects := [Rect2(0, 0, vs.x, tl.y), Rect2(0, br.y, vs.x, vs.y - br.y), Rect2(0, 0, tl.x, vs.y), Rect2(br.x, 0, vs.x - br.x, vs.y)]
	for i in 4:
		_demo_mask[i].visible = on
		_demo_mask[i].position = rects[i].position
		_demo_mask[i].size = rects[i].size

func _demo_cancel_check() -> void:
	if text.is_open() and text.bg_label.visible:      # sub_809AFAC: not while a text box of type 4 is up
		return
	var pressed: bool = _pad.a_pressed or _pad.b_pressed or _pad.menu_pressed or _demo_tap
	_demo_tap = false
	for a in ["gp_select", "gp_l", "gp_r", "ui_accept", "ui_cancel"]:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			pressed = true
	if pressed:
		map_execute_event(GData.fn_id("DEMO_CANCEL"), false)
		_request(REQ_GAME_CANCEL, 30)
		Audio.fade_out_music(30)

# ------------------------------------------------------------------ start (xxx_script_related_8098468)
func start(mode: int) -> void:
	Story.sync_base_kind()          # Red: BASE_KIND / PARTNER_TALK_KIND from the hero / partner on every start
	start_mode = mode
	req = REQ_GROUND
	req_count = 0
	req_map = GVars.get_val(null, GVars.GROUND_ENTER)
	req_link = GVars.get_val(null, GVars.GROUND_ENTER_LINK)
	req_dungeon = -1
	_begin_loop()

## One pass of the outer while-loop in xxx_script_related_8098468: set up variables for the start mode,
## reset everything and run the first event.
func _begin_loop() -> void:
	var script_id := -1
	text.set_auto_press(-1, -1)
	text.clear()
	match start_mode:
		STARTMODE_NEW_GAME:
			_day_reset()
			start_mode = STARTMODE_CONTINUE_GAME
		STARTMODE_GROUND, STARTMODE_3:
			Story.daily_update()
		STARTMODE_DUNGEON_FROM_WORLD_MAP:
			script_id = GData.fn_id("EVENT_RESCUE")
		STARTMODE_DUNGEON_WON, STARTMODE_10, STARTMODE_11, STARTMODE_DUNGEON_LOST:
			GVars.set_val(null, GVars.DUNGEON_RESULT, start_mode)
			GVars.set_val(null, GVars.WARP_LOCK, 0)
			_day_reset()
			GVars.update_imm(null, GVars.DUNGEON_ENTER_FREQUENCY, 1, GVars.CALC_ADD)
			var sdn := GAction._s16(GVars.get_val(null, GVars.DUNGEON_ENTER))
			if sdn != -1:
				var di := GData.dungeon_info(GAction._s16(GVars.get_val(null, GVars.DUNGEON_ENTER_INDEX)) if sdn == 81 else sdn)
				script_id = int(di.script3)
				if start_mode == STARTMODE_DUNGEON_WON:
					GVars.set_arr(null, GVars.DUNGEON_CLEAR_LIST, sdn, 1)
				var rm := _return_map()
				if rm != -1:
					req_map = rm
					req_link = 0
	var genter := GVars.get_val(null, GVars.GROUND_ENTER)
	if Dialog.auto:
		print("    BEGIN mode=%d req_map=%d genter=%d script=%d cc=%d sub1=%s" % [start_mode, req_map, genter, script_id, GVars.get_val(null, GVars.CLEAR_COUNT), str(GVars.scenario(GVars.SCENARIO_SUB1))])
	GVars.set_val(null, GVars.START_MODE, start_mode)
	if start_mode != STARTMODE_CONTINUE_GAME:
		if start_mode == STARTMODE_3:
			GVars.set_val(null, GVars.GROUND_GETOUT, req_map)
		else:
			GVars.set_val(null, GVars.GROUND_GETOUT, genter)
	GVars.set_val(null, GVars.GROUND_ENTER, req_map)
	GVars.set_val(null, GVars.GROUND_ENTER_LINK, req_link)
	start_mode = STARTMODE_GROUND
	req = REQ_NONE
	req_count = 0
	req_speed = -1
	req_map = -1
	_reset_locks()
	text.reset_all()
	_map_reset()
	camera.reset()
	_delete_all_entities()
	if script_id != -1:
		map_execute_event(script_id, false)
	else:
		map_execute_event(GData.fn_id("EVENT_DIVIDE"), false)
	map_action.handle()

func _day_reset() -> void:          # sub_8098C58
	GVars.clear_arr(null, GVars.GROUND_LOCAL)
	GVars.clear_arr(null, GVars.EVENT_LOCAL)
	Story.daily_update()
	if GVars.get_val(null, GVars.FLAG_KIND_CHANGE_REQUEST) != 0:
		var t := GVars.get_val(null, GVars.FLAG_KIND) + 1
		GVars.set_val(null, GVars.FLAG_KIND, 0 if t > 15 else t)
		GVars.set_val(null, GVars.FLAG_KIND_CHANGE_REQUEST, 0)
	var g := GVars.get_arr(null, GVars.EVENT_GONBE, 0)
	if g <= 0:
		g = 1
	GVars.set_arr(null, GVars.EVENT_GONBE, 0, g - 1)
	Story.new_day()

func _return_map() -> int:           # GetReturnMap
	var sdn := GAction._s16(GVars.get_val(null, GVars.DUNGEON_ENTER))
	if sdn == -1:
		return GData.map_id("MAP_TEAM_BASE_INSIDE")
	var s2 := GAction._s16(GVars.get_val(null, GVars.DUNGEON_ENTER_INDEX)) if sdn == 81 else sdn
	var di := GData.dungeon_info(s2)
	if start_mode == STARTMODE_DUNGEON_WON:
		return int(di.map2)
	var m3 := int(di.map3)
	if m3 == GData.map_id("MAP_TINY_WOODS_ENTRY"):
		if GVars.after(GVars.SCENARIO_MAIN, 2, -1):
			return GData.map_id("MAP_TEAM_BASE_INSIDE")
	elif m3 in [GData.map_id("MAP_LAPIS_CAVE_ENTRY"), GData.map_id("MAP_MT_BLAZE_ENTRY"), GData.map_id("MAP_FROSTY_FOREST_ENTRY"), GData.map_id("MAP_MT_FREEZE_ENTRY")]:
		if not GVars.quest(GVars.QUEST_UNK5):
			return GData.map_id("MAP_TEAM_BASE_INSIDE")
	return m3

func _reset_locks() -> void:
	any_locked = false
	pending_cues.clear()
	cue_last.clear()
	_cue_quiet = 0
	_cue_quiet_total = 0
	for i in 136:
		locks[i] = false
		lock_conds[i] = false
		unlock_labels[i] = 0

# ------------------------------------------------------------------ requests
func ground_request(map: int, link: int, speed: int) -> bool:
	if req != REQ_NONE:
		return false
	req = REQ_GROUND
	req_count = 1
	req_speed = speed
	start_mode = STARTMODE_GROUND
	req_map = map
	req_link = link
	return true

func _request(kind: int, speed: int) -> bool:
	if req != REQ_NONE:
		return false
	req = kind
	req_count = 1
	req_speed = speed
	return true

func request_friend_areas(speed: int) -> bool:
	return _request(REQ_FRIEND_AREAS, speed)

func request_world_map(speed: int) -> bool:
	return _request(REQ_WORLD_MAP, speed)

func rescue_request(sdun: int, speed: int) -> bool:
	if req != REQ_NONE:
		return false
	req_dungeon = sdun
	match dungeon_kind(sdun):
		4:
			req = REQ_MAZE
		2:
			req = REQ_RESCUE_JOB
		3:
			req = REQ_RESCUE_MAIL
		_:
			req = REQ_RESCUE
	req_count = 1
	req_speed = speed
	return true

func game_end_request(speed: int) -> bool:
	return _request(REQ_GAME_END, speed)

## sub_80A2750
func dungeon_kind(sdun: int) -> int:
	if sdun == 80:
		return 3
	if sdun == 81:
		return 2
	if sdun == 82:
		return 4
	if sdun >= 43 and sdun <= 54:
		return 2
	if sdun >= 55 and sdun <= 79:
		return 4
	var di := GData.dungeon_info(sdun)
	var r := int(di.rescue)
	if r == -1 or GVars.quest(GVars.QUEST_UNK5) or not GVars.rescue_conquered(r) or not GVars.quest(GVars.QUEST_UNK1):
		return 1
	return 2

func _finish_request() -> void:
	if demo and req != REQ_GROUND and req != REQ_2:
		_end(16 if req == REQ_GAME_CANCEL else 15)
		return
	match req:
		REQ_GROUND, REQ_2:
			_begin_loop()
			return
		REQ_FRIEND_AREAS:
			GVars.set_val(null, GVars.DUNGEON_ENTER, -1)
			GVars.set_val(null, GVars.DUNGEON_ENTER_INDEX, -1)
			GVars.set_val(null, GVars.START_MODE, 4)
			GVars.set_val(null, GVars.DUNGEON_RESULT, 4)
			GVars.set_val(null, GVars.GROUND_GETOUT, GVars.get_val(null, GVars.GROUND_ENTER))
			_end(5)
		REQ_WORLD_MAP:
			GVars.set_val(null, GVars.START_MODE, 5)
			GVars.set_val(null, GVars.DUNGEON_RESULT, 5)
			GVars.set_val(null, GVars.DUNGEON_ENTER, -1)
			_end(6)
		REQ_RESCUE:
			GVars.set_val(null, GVars.DUNGEON_ENTER, req_dungeon)
			GVars.set_val(null, GVars.DUNGEON_ENTER_INDEX, int(GData.dungeon_info(req_dungeon).rescue))
			GVars.set_arr(null, GVars.DUNGEON_ENTER_LIST, req_dungeon, 1)
			GVars.set_val(null, GVars.START_MODE, 7)
			GVars.set_val(null, GVars.DUNGEON_RESULT, 7)
			if GVars.get_val(null, GVars.GROUND_PLACE) == 10:
				GVars.set_val(null, GVars.GROUND_PLACE, 0)
			_end(7)
		REQ_RESCUE_JOB:
			GVars.set_val(null, GVars.DUNGEON_ENTER, 81)
			GVars.set_val(null, GVars.DUNGEON_ENTER_INDEX, req_dungeon)
			GVars.set_val(null, GVars.START_MODE, 7)
			GVars.set_val(null, GVars.DUNGEON_RESULT, 7)
			_end(8)
		REQ_RESCUE_MAIL:
			GVars.set_val(null, GVars.DUNGEON_ENTER, 80)
			GVars.set_val(null, GVars.START_MODE, 7)
			GVars.set_val(null, GVars.DUNGEON_RESULT, 7)
			_end(9)
		REQ_MAZE:
			GVars.set_val(null, GVars.DUNGEON_ENTER, 82)
			GVars.set_val(null, GVars.DUNGEON_ENTER_INDEX, req_dungeon)
			GVars.set_val(null, GVars.START_MODE, 7)
			GVars.set_val(null, GVars.DUNGEON_RESULT, 7)
			_end(10)
		_:
			GVars.set_val(null, GVars.START_MODE, 1)
			_end(14)

func _end(code: int) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	finished.emit(code)

static var turbo := 1   # tests: ticks per frame multiplier

# ------------------------------------------------------------------ main loop
func _process(dt: float) -> void:
	if _done:
		return
	if hud:
		hud.visible = not demo and not (cur_map >= 223 and cur_map <= 227)    # no pad on the boot, title and quiz screens
	_acc += dt
	var n := 0
	var cap := 4 * turbo
	if turbo > 1:
		_acc += TICK * (turbo - 1)
	while _acc >= TICK and n < cap:
		_acc -= TICK
		n += 1
		_tick()
		if _done:
			return
	if n >= cap:
		_acc = 0.0
	_stick_zoom(dt)
	_render()

## Controller: the right stick zooms the town / ground maps (up = in, down = out); saved when let go.
## Not on the boot, title and personality-quiz screens (Red's fixed 240x160 views).
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.5
var _stick_zooming := false
func _stick_zoom(dt: float) -> void:
	if demo or (cur_map >= 223 and cur_map <= 227):
		return
	if BottomScreen.hover.begins_with("dungeon:") and BottomScreen.instance != null and BottomScreen.instance.is_active():
		return                                   # the right stick scrolls the dungeon list on the second screen
	var ax := 0.0
	for dev in Input.get_connected_joypads():
		var v := Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
		if absf(v) > absf(ax):
			ax = v
	if absf(ax) > 0.3:
		var tilt := (absf(ax) - 0.3) / 0.7 * signf(ax)
		set_ground_zoom(_zoom - tilt * 1.6 * dt)
		_stick_zooming = true
	elif _stick_zooming:
		_stick_zooming = false
		Game.save_game()

func set_ground_zoom(z: float) -> void:
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	Game.settings["ground_zoom"] = _zoom

func _tick() -> void:
	_frame += 1
	_poll_input()
	if req != REQ_NONE:
		if req_count > 0:
			req_count -= 1
			if req_count < 1:
				_fade_all = true
				_fade_all_speed = 30 if req_speed < 0 else req_speed
				if req_speed == 0:
					fadeA.lvl = 0
		elif not fade_busy():
			_finish_request()
			return
	elif demo and demo_cancel_ok:
		_demo_cancel_check()
	map_action.handle()
	_lives_action()
	_things_action(objects)
	_things_action(effects)
	text.tick()
	_unlock()
	for k in pending_cues.keys():
		pending_cues[k][1] -= 1
		if pending_cues[k][1] <= 0:
			pending_cues.erase(k)
	_cue_rescue()
	camera.update()
	_scroll_update()
	_lives_sprites()
	_things_sprites(objects)
	_things_sprites(effects)
	weather.tick()
	_anim_tick()
	_fade_update()

func _render() -> void:
	var vs := get_viewport_rect().size
	var cam := camera.top_left_px()
	world.scale = Vector2(zoom, zoom)
	var view_gba := vs / zoom
	var off := Vector2(cam) - (view_gba - Vector2(240, 160)) / 2.0
	var mw := float(map_info.get("w", map_info.get("w_px", 240)))
	var mh := float(map_info.get("h", map_info.get("h_px", 160)))
	if map_info.get("dungeon_map", false):
		mw = float(map_info.get("w_px", 240))
		mh = float(map_info.get("h_px", 160))
	if mw >= view_gba.x:
		off.x = clampf(off.x, 0, mw - view_gba.x)
	else:
		off.x = (mw - view_gba.x) / 2.0
	if mh >= view_gba.y:
		off.y = clampf(off.y, 0, mh - view_gba.y)
	else:
		off.y = (mh - view_gba.y) / 2.0
	if demo and cur_map >= 224 and cur_map <= 227:
		off = Vector2(cam) - (view_gba - Vector2(240, 160)) / 2.0      # boot screens: exactly Red's 240x160 view
	_demo_mask_update(demo and cur_map >= 224 and cur_map <= 227, vs)
	world.position = (-off * zoom).round()
	weather.place(off, view_gba)
	var lvl := float(fadeA.lvl) / 256.0
	fade_rect.color = Color(0, 0, 0, 1.0 - clampf(lvl, 0.0, 1.0))
	text.modulate = Color(1, 1, 1, clampf(float(fadeB.lvl) / 256.0, 0.0, 1.0)) if text.bg_label.visible else Color.WHITE
	var fl: Dictionary = flash_st.fade
	if int(flash_st.kind) != 0:
		var c: Color = flash_st.col
		flash_rect.color = Color(c.r, c.g, c.b, 1.0 - clampf(float(fl.lvl) / 256.0, 0.0, 1.0))
	else:
		flash_rect.color = Color(0, 0, 0, 0)

# ------------------------------------------------------------------ input
func _poll_input() -> void:
	var up := Input.is_action_pressed("move_up") or Input.is_action_pressed("move_ul") or Input.is_action_pressed("move_ur")
	var down := Input.is_action_pressed("move_down") or Input.is_action_pressed("move_dl") or Input.is_action_pressed("move_dr")
	var left := Input.is_action_pressed("move_left") or Input.is_action_pressed("move_ul") or Input.is_action_pressed("move_dl")
	var right := Input.is_action_pressed("move_right") or Input.is_action_pressed("move_ur") or Input.is_action_pressed("move_dr")
	var a := Input.is_action_pressed("act_attack") or Input.is_action_pressed("ui_accept") or Input.is_action_pressed("gp_a")
	var b := Input.is_action_pressed("act_run") or Input.is_action_pressed("gp_b")
	var m := Input.is_action_pressed("act_menu") or Input.is_action_pressed("gp_start")
	var d := GDir.from_input(up, down, left, right)
	if _touch_dir != -1:
		d = _touch_dir
	if hud and hud.pad.visible and hud.pad_dir >= 0:
		d = hud.pad_dir
		up = d in [3, 4, 5]
		down = d in [7, 0, 1]
	var pad_run := hud != null and hud.pad.visible and hud.pad_run and hud.pad_dir >= 0
	_pad = {"dir": d, "a_pressed": (a and not _a_latch) or _touch_tap, "b_held": b or _touch_run or pad_run, "b_pressed": b and not _b_latch,
		"menu_pressed": (m and not _m_latch) or _touch_menu, "up": up, "down": down}
	_touch_tap = false
	_touch_menu = false
	if autopilot != null:
		var o: Dictionary = autopilot.drive()
		if not o.is_empty():
			_pad = o
	_a_latch = a
	_b_latch = b
	_m_latch = m

var hud: Hud
var _touch_menu := false
var _touch_dir := -1
var _touch_tap := false
var _touch_run := false
var _touch_down := false
var _touch_pos := Vector2.ZERO
var _touch_t := 0

func input_state() -> Dictionary:
	if text.is_open() or text._menu != null:
		return {"dir": -1, "a_pressed": false, "b_held": false, "b_pressed": false, "menu_pressed": false, "up": false, "down": false}
	return _pad

var _demo_tap := false     # a screen tap / click while a skippable boot demo plays (no controller needed)

## _input, not _unhandled_input: on-screen controls must not swallow the tap that skips the intro
func _input(e: InputEvent) -> void:
	if demo and demo_cancel_ok and e.is_pressed() and (e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)):
		_demo_tap = true

func _unhandled_input(e: InputEvent) -> void:
	if text.handle_input(e):
		get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN) \
			and not demo and not (cur_map >= 223 and cur_map <= 227):
		set_ground_zoom(_zoom + (0.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1))      # PC: the mouse wheel zooms too
		return
	if hud and hud.pad.visible and (hud._pad_touch != -1 or _on_pad(e)):
		return          # the on-screen pad has this finger (also its emulated mouse events): not tap-to-walk
	if e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		if e.pressed:
			_touch_down = true
			_touch_pos = e.position
			_touch_t = Time.get_ticks_msec()
		else:
			if _touch_down and Time.get_ticks_msec() - _touch_t < 220:
				_touch_tap = true
			_touch_down = false
			_touch_dir = -1
			_touch_run = false
	elif (e is InputEventScreenDrag or e is InputEventMouseMotion) and _touch_down:
		_touch_pos = e.position
	if _touch_down and Time.get_ticks_msec() - _touch_t >= 120 and lives[0].kind_id != -1:
		var vs := get_viewport_rect().size
		var pc: Vector2 = world.position + Vector2(lives[0].get_center()) / 256.0 * zoom
		var dv := _touch_pos - pc
		if dv.length() > 12:
			_touch_dir = GDir.vec_dir8(Vector2i(int(dv.x), int(dv.y)))
			_touch_run = dv.length() > vs.y * 0.35

func _on_pad(e: InputEvent) -> bool:
	if not (e is InputEventScreenTouch or e is InputEventScreenDrag or e is InputEventMouseButton or e is InputEventMouseMotion):
		return false
	var local: Vector2 = hud.get_global_transform_with_canvas().affine_inverse() * e.position
	return local.distance_to(hud.pad.position + hud.pad.size / 2) < 52

# ------------------------------------------------------------------ locks
## Cutscene deadlock safety net. Our timings differ a little from Red's (and text can be advanced faster),
## so an actor can still be busy turning or jumping when the cue it needs is sent, miss it, and then wait
## forever while everyone else waits on it. When the scene has been completely quiet for 3 s (no cue sent,
## no text box), the actor that is waiting for a cue that was sent just before it started waiting gets it.
const CUE_QUIET := 180
const CUE_QUIET_LONG := 600
var _cue_quiet_total := 0       # quiet frames counted while some script was still busy
func _cue_rescue() -> void:
	_cue_quiet += 1
	if _cue_quiet < CUE_QUIET or text.is_open() or cue_last.is_empty():
		return
	var best = null
	var best_t := -1
	var acts: Array = [map_action]
	for L in lives:
		if L.kind_id != -1:
			acts.append(L.action)
	for T in objects + effects:
		if T.kind != -1:
			acts.append(T.action)
	# only a real deadlock: if any script is still doing something (a WAIT, a walk, an animation, a sound),
	# it may yet send the cue, so a quiet stretch of the scene is not a reason to step in. After 10 quiet
	# seconds it is (an actor looping an idle animation forever would otherwise hide a real deadlock).
	if _cue_quiet_total < CUE_QUIET_LONG:
		for a in acts:
			var st: int = a.sd.saved_state
			if (st == GAction.RET_02 or st == GAction.RET_03) and a.sd.unk22 == -1:
				_cue_quiet_total += 30
				_cue_quiet = CUE_QUIET - 30
				return
	for a in acts:
		var w: int = a.sd.unk22
		if w <= 1 or w >= 0x80 or not cue_last.has(w):
			continue
		var t: int = cue_last[w]
		# missed: sent before this wait began, recently (within ~10 s of it), and NOT already received by this
		# script (an actor that heard the last cue 6 and now waits for the next one is not stuck, just early)
		if t <= a.sd.wait_since and a.sd.wait_since - t < 600 and int(a.heard.get(w, -1)) < t and t > best_t:
			best = a
			best_t = t
	_cue_quiet = CUE_QUIET - 30          # look again in half a second
	if best == null:
		return
	var id: int = best.sd.unk22
	print("    CUE rescue: delivering missed cue %d (sent f%d, waiting since f%d)" % [id, best_t, best.sd.wait_since])
	best.notify(id)                      # the wait op (0xE3) then jumps to the cue's label itself (and marks it heard)
func lock_jump_zero(i: int) -> void:
	if GAction.trace:
		print("    [f%d] UNLOCK %d" % [_frame, i])
	locks[i] = true
	unlock_labels[i] = 0
	any_locked = true

func lock(i: int, val: int) -> void:
	locks[i] = true
	unlock_labels[i] = val
	any_locked = true

func _notify_all(i: int) -> bool:
	if GAction.trace:
		print("    [f%d] notify %d" % [_frame, i])
	var c := map_action.notify(i)
	for L in lives:
		if L.kind_id != -1:
			c = L.action.notify(i) or c
	for T in objects:
		if T.kind != -1:
			c = T.action.notify(i) or c
	for T in effects:
		if T.kind != -1:
			c = T.action.notify(i) or c
	return c

func _unlock() -> void:
	if not any_locked:
		return
	any_locked = false
	for i in 129:
		if locks[i]:
			if i > 1 and i < 0x80 and not lock_conds[i]:
				cue_last[i] = _frame
				_cue_quiet = 0
				_cue_quiet_total = 0
			var c := _notify_all(i)
			if not c and i > 1 and i < 0x80 and not lock_conds[i]:
				# nobody is waiting yet: keep the cue a moment for an actor that is a few frames late
				# (our animation timings differ slightly from Red's, which can make a cue miss its waiter)
				var pc: Array = pending_cues.get(i, [0, 0])
				pending_cues[i] = [int(pc[0]) + 1, 60]      # [count, ticks left]: ~1 s grace only (Red drops unheard cues)
			if lock_conds[i]:
				if c:
					_notify_all(i | 0x80)
					lock_conds[i] = false
					locks[i] = false
			else:
				locks[i] = false

func set_player_mode(x: int) -> void:     # sub_80A87AC(0, x)
	if lives[0].kind_id != -1:
		lives[0].set_ctrl(x)

# ------------------------------------------------------------------ fades (palette_util.c)
func _fade_set_in(f: Dictionary, t: int) -> void:
	if t < 0:
		t = 30
	if t == 0:
		f.lvl = 0x100
		f.state = 1
	else:
		f.state = 2
	f.t = t
	f.dur = maxi(t, 1)

func _fade_set_out(f: Dictionary, t: int) -> void:
	if t < 0:
		t = 30
	if t == 0:
		f.lvl = 0
		f.state = 1
	else:
		f.state = 3
	f.t = t
	f.dur = maxi(t, 1)

func _fade_set_to(f: Dictionary, t: int, a: int, b: int) -> void:
	if t < 0:
		t = 30
	f.state = 5 if a > b else (4 if a < b else 1)
	f.d = absi(a - b)
	f.t = t
	f.dur = maxi(t, 1)
	f.lvl = a
	f.to = b

func _fade_step(f: Dictionary) -> bool:
	match int(f.state):
		1:
			f.state = 0
			return true
		2:
			f.t -= 1
			if f.t > 0:
				f.lvl = maxi(f.lvl, 0x100 - int((f.t << 8) / f.dur))
			else:
				f.lvl = 0x100
				f.state = 0
			return true
		3:
			f.t -= 1
			if f.t > 0:
				f.lvl = mini(f.lvl, int((f.t << 8) / f.dur))
			else:
				f.lvl = 0
				f.state = 0
			return true
		4:
			f.t -= 1
			if f.t > 0:
				f.lvl = f.to - int(f.t * f.d / f.dur)
			else:
				f.lvl = f.to
				f.state = 0
			return true
		5:
			f.t -= 1
			if f.t > 0:
				f.lvl = f.to + int(f.t * f.d / f.dur)
			else:
				f.lvl = f.to
				f.state = 0
			return true
	return false

func fade_in_a(t: int) -> void:
	_fade_set_in(fadeA, t)

func fade_out_a(t: int) -> void:
	_fade_set_out(fadeA, t)

func fade_to_a(t: int, a: int, b: int) -> void:
	_fade_set_to(fadeA, t, a & 0xFFFF, b & 0xFFFF)

func fade_in_b(t: int) -> void:
	_fade_set_in(fadeB, t)

func fade_out_b(t: int) -> void:
	_fade_set_out(fadeB, t)

## sub_8099A5C (from_color: color -> normal, fade in) / sub_8099AFC (normal -> color, fade out).
func flash(from_color: bool, kind: int, t: int, col: Color) -> void:
	flash_st.kind = kind
	flash_st.col = col
	if from_color:
		flash_st.fade.lvl = 0
		_fade_set_in(flash_st.fade, t)
		if kind in [1, 3]:
			fadeA.lvl = 0x100
			fadeB.lvl = 0x100
		elif kind in [9, 11]:
			fadeB.lvl = 0x100
		elif kind in [5, 7, 13, 14]:
			fadeA.lvl = 0x100
	else:
		flash_st.fade.lvl = 0x100
		_fade_set_out(flash_st.fade, t)
		if kind in [2, 4]:
			fadeA.lvl = 0
			fadeB.lvl = 0
		elif kind in [10, 12]:
			fadeB.lvl = 0
		elif kind in [6, 8, 13, 14]:
			fadeA.lvl = 0

func fade_busy() -> bool:
	if _fade_all:
		return true
	if int(flash_st.kind) != 0:
		return int(flash_st.fade.state) != 0
	return int(fadeA.state) != 0 or int(fadeB.state) != 0

## sub_8099BE4
func _fade_update() -> void:
	var k := int(flash_st.kind)
	if k != 0 or int(flash_st.fade.state) != 0:
		if not _fade_step(flash_st.fade) and int(flash_st.fade.state) == 0:
			if k in [1, 3, 5, 7, 9, 11]:
				if int(flash_st.fade.lvl) >= 0x100:
					flash_st.kind = 0
				elif _fade_all:
					var nk: int = {1: 2, 3: 4, 5: 6, 7: 8}.get(k, 0)
					if nk != 0:
						flash(false, nk, _fade_all_speed, flash_st.col)
					else:
						flash_st.kind = 0
			elif k in [2, 4, 6, 8, 10, 12, 13, 14]:
				if int(flash_st.fade.lvl) == 0:
					flash_st.kind = 0
				elif _fade_all:
					flash(false, k, _fade_all_speed, flash_st.col)
	elif _fade_all:
		var done := true
		for f in [fadeA, fadeB]:
			if int(f.lvl) != 0 or int(f.state) != 0:
				done = false
				if int(f.state) != 3:
					_fade_set_out(f, _fade_all_speed)
				_fade_step(f)
		if done:
			_fade_all = false
	else:
		_fade_step(fadeA)
		_fade_step(fadeB)

# ------------------------------------------------------------------ map
func adjusted_map(m: int) -> int:
	if m == GData.map_id("MAP_TEAM_BASE") or m == GData.map_id("MAP_TEAM_BASE_INSIDE"):
		# GetAdjustedGroundMap: TEAM_BASE_MAPS_PER_SPECIES = 6 (3 outside + 3 inside: basic, construction, final)
		return m + GVars.get_val(null, GVars.BASE_KIND) * 6 + GVars.get_val(null, GVars.BASE_LEVEL)
	if m == GData.map_id("MAP_WHISCASH_POND") and GVars.quest(GVars.QUEST_REACHED_POSTGAME):
		return GData.map_id("MAP_WHISCASH_POND_OPEN")
	return m

func select_map(m: int, is_map: bool) -> void:
	if is_map:
		cur_map = m
		vis_map = adjusted_map(m)
		station_map = vis_map
	else:
		cur_map = m
		vis_map = m
		station_map = m
	GVars.set_val(null, GVars.GROUND_MAP, cur_map)
	GVars.set_val(null, GVars.GROUND_PLACE, int(GData.map_conv(cur_map).place))
	camera.reset()
	_delete_all_entities()
	_load_map(vis_map)
	_map_weather(vis_map)
	links = GData.maps[vis_map].links if GData.maps[vis_map] else []
	lives_select_map(vis_map, 0, 0)
	objects_select_map(vis_map, 0, 0)

func select_dungeon_map(m: int, sdun: int, floor_n: int, _b: int) -> void:
	cur_map = m
	vis_map = m
	station_map = m
	camera.reset()
	_delete_all_entities()
	_load_map(m, int(GData.dungeon_info(sdun).dungeon), floor_n)
	weather_enabled = false
	weather.clear()
	GVars.set_val(null, GVars.WEATHER_KIND, -1)
	links = GData.maps[m].links if GData.maps[m] else []
	lives_select_map(m, 0, 0)
	objects_select_map(m, 0, 0)

var weather_enabled := false      # gUnknown_3001B74->unk2

## GroundWeather_Select
func weather_select(w: int) -> void:
	GVars.set_val(null, GVars.WEATHER_KIND, w)
	if weather_enabled:
		weather.select(w)

## GroundMap_Select: sub_80A5EDC(on) for normal maps (not map types 5..9), then the conversion table's weather.
func _map_weather(m: int) -> void:
	GVars.set_val(null, GVars.WEATHER_KIND, -1)
	weather.clear()
	if m < 0:
		weather_enabled = false
		return
	var conv := GData.map_conv(m)
	weather_enabled = not (int(conv.u0) in [5, 6, 7, 8, 9])
	if int(conv.get("u6", -1)) != -1:
		weather_select(int(conv.u6))

func _map_reset() -> void:
	GVars.clear_arr(null, GVars.MAP_LOCAL)
	GVars.clear_arr(null, GVars.MAP_LOCAL_DOOR)
	map_action.reset()

func _clear_map_nodes() -> void:
	edge_fill.texture = null
	map_lo.texture = null
	map_hi.texture = null
	for a in anim_nodes:
		a.node.queue_free()
	anim_nodes.clear()
	for sp0 in [map_lo, map_hi]:
		if sp0.has_meta("last_overlay"):
			sp0.remove_meta("last_overlay")
	pal_anim = {}
	layer_sprites = {}
	if dun_view:
		dun_view.queue_free()
		dun_view = null

func _load_map(m: int, dungeon_id := -1, floor_n := 0) -> void:
	_clear_map_nodes()
	pending_cues.clear()      # a held cue never carries over into another map's scene
	cue_last.clear()          # nor counts as "missed" by the new map's actors (Ground._cue_rescue)
	_cue_quiet = 0
	_cue_quiet_total = 0
	GVars.clear_arr(null, GVars.MAP_LOCAL)
	GVars.clear_arr(null, GVars.MAP_LOCAL_DOOR)
	scroll = {"e8": Vector2i.ZERO, "f0": 0, "f4": 0, "f8": Vector2i.ZERO}
	if m < 0:
		map_info = {}
		collision = []
		return
	var conv := GData.map_conv(m)
	map_file = GData.enum_name("map_files", int(conv.file)).trim_prefix("MAP_FILE_ID_").to_lower()
	active_map = map_file
	map_info = GData.ground_bg().get(map_file, {})
	collision = GData.ground_collision(map_file, map_info)
	col_h = collision.size()
	col_w = collision[0].size() if col_h > 0 else 0
	var w := int(map_info.get("w_px", map_info.get("w", 240))) if map_info.get("dungeon_map", false) else int(map_info.get("w", 240))
	var h := int(map_info.get("h_px", map_info.get("h", 160))) if map_info.get("dungeon_map", false) else int(map_info.get("h", 160))
	bounds_a = Vector2i.ZERO
	bounds_b = Vector2i(w << 8, h << 8)
	if map_info.get("dungeon_map", false):
		_build_dungeon_view(map_info)
	else:
		var layers: Array = map_info.get("layers", [])
		var above = map_info.get("above_layer", null)
		var lo_set := false
		for lf in layers:
			var tex := GData.ground_tex(str(lf))
			if above != null and str(lf) == str(above):
				map_hi.texture = tex
				_fit_hd(map_hi, tex, w)
				layer_sprites[str(lf)] = map_hi
			elif not lo_set:
				map_lo.texture = tex
				_fit_hd(map_lo, tex, w)
				lo_set = true
				layer_sprites[str(lf)] = map_lo
			else:
				# a second below-actors layer: stack it onto map_lo as a child
				var s := Sprite2D.new()
				s.centered = false
				s.texture = tex
				_fit_hd(s, tex, w)
				# a sibling right above map_lo (as a child it inherited map_lo's HD scale twice and shrank to 1/16:
				# e.g. the Pelipper Post Office cliff vanished, leaving only the sea)
				world.add_child(s)
				world.move_child(s, map_lo.get_index() + 1)
				anim_nodes.append({"node": s, "frames": [], "t": 0, "i": 0})
				layer_sprites[str(lf)] = s
		_build_anims(map_info)
		_build_pal_anim(map_info)
		_apply_blend(map_info)
		_build_edge_fill(w, h)

## GBA colour blending of a map layer (BLDCNT/BLDALPHA: out = layer*eva/16 + below*evb/16). evb = 0 is plain
## drawing; otherwise the layer is added onto what's below it (the Silent Chasm fog, the Personality Test
## and Nightmare backdrops, whose black parts must vanish), and an opaque layer dims the one below by evb/16.
func _apply_blend(info: Dictionary) -> void:
	for sp in layer_sprites.values():
		sp.modulate = Color.WHITE
	var b: Dictionary = info.get("blend", {})
	var evb := int(b.get("evb", 0))
	var spr = layer_sprites.get(str(b.get("layer", "")), null)
	if b.is_empty() or evb <= 0 or spr == null:
		return
	if spr.material == null:
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		spr.material = mat
	var ka := clampf(int(b.get("eva", 16)) / 16.0, 0.0, 1.0)
	spr.modulate = Color(ka, ka, ka, 1.0)
	if evb < 16:
		var kb := evb / 16.0
		for k in layer_sprites:
			if layer_sprites[k] != spr:
				layer_sprites[k].modulate = Color(kb, kb, kb, 1.0)

## BPL palette animations that have no pre-rendered overlays (long cycles): recolour the layers with a
## shader driven by a live 16x16 palette texture (sub_80A49E8 advances each row every 'frame_ticks' frames).
func _build_pal_anim(info: Dictionary) -> void:
	for sp in [map_lo, map_hi]:
		sp.material = null
		sp.region_enabled = false
	var an: Dictionary = info.get("anim", {})
	var rows: Array = []
	for p in an.get("palettes", []):
		if not (p.get("overlays", []) as Array).is_empty():
			continue
		var cols: Array = p.get("colors", [])
		if cols.is_empty():
			continue
		rows.append({"row": int(p.palette), "colors": cols, "ticks": maxi(1, int(p.get("frame_ticks", p.get("duration", 8)))), "t": 0, "i": 0})
	var idx_imgs: Dictionary = an.get("index_images", {})
	if rows.is_empty() or idx_imgs.is_empty():
		return
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var base: Array = an.get("base_palette", [])
	for r in mini(16, base.size()):
		for c in mini(16, (base[r] as Array).size()):
			img.set_pixel(c, r, Color(str(base[r][c])))
	var mask := 0
	for rw in rows:
		mask |= 1 << int(rw.row)
	var tex := ImageTexture.create_from_image(img)
	pal_anim = {"img": img, "tex": tex, "rows": rows}
	var shader: Shader = load("res://shaders/ground_palette.gdshader")
	for lf in idx_imgs:
		var spr = layer_sprites.get(str(lf), null)
		var it := GData.ground_tex(str(idx_imgs[lf]), false)
		if spr == null or it == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("idx_tex", it)
		mat.set_shader_parameter("pal_tex", tex)
		mat.set_shader_parameter("anim_rows", mask)
		spr.material = mat
	_pal_apply()

func _pal_apply() -> void:
	var img: Image = pal_anim.img
	for rw in pal_anim.rows:
		var fr: Array = rw.colors[int(rw.i) % (rw.colors as Array).size()]
		for c in mini(15, fr.size()):
			img.set_pixel(c + 1, int(rw.row), Color(str(fr[c])))
	(pal_anim.tex as ImageTexture).update(img)

func _pal_tick() -> void:
	if pal_anim.is_empty():
		return
	var changed := false
	for rw in pal_anim.rows:
		rw.t += 1
		if rw.t >= int(rw.ticks):
			rw.t = 0
			rw.i = (int(rw.i) + 1) % (rw.colors as Array).size()
			changed = true
	if changed:
		_pal_apply()

## Instead of black past the map's edges (when zoomed out or on a wide screen), mirror the bottom layer
## outward. Only a backdrop: the real layers, collision and the camera are unchanged.
const EDGE_FILL_PX := 96         # enough for a slight zoom-out without showing mirrored buildings
func _build_edge_fill(w: int, h: int) -> void:
	edge_fill.texture = null
	if map_lo.texture == null or str(map_file).begins_with("personality_test"):
		return
	var tex := map_lo.texture
	var k := float(tex.get_width()) / float(maxi(w, 1))
	edge_fill.texture = tex
	edge_fill.scale = map_lo.scale
	edge_fill.texture_filter = map_lo.texture_filter
	edge_fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	edge_fill.region_enabled = true
	edge_fill.region_rect = Rect2(-EDGE_FILL_PX * k, -EDGE_FILL_PX * k, (w + 2 * EDGE_FILL_PX) * k, (h + 2 * EDGE_FILL_PX) * k)
	edge_fill.position = Vector2(-EDGE_FILL_PX, -EDGE_FILL_PX)

func _fit_hd(s: Sprite2D, tex: Texture2D, w: int) -> void:
	if tex == null:
		return
	var k := float(tex.get_width()) / float(maxi(w, 1))
	s.scale = Vector2.ONE / k
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if k > 1.5 else CanvasItem.TEXTURE_FILTER_NEAREST

func _build_anims(info: Dictionary) -> void:
	var an: Dictionary = info.get("anim", {})
	for t in an.get("tiles", []):
		var frames: Array = t.get("frames", [])
		var ticks: Array = t.get("frame_ticks", [])
		var per_layer := {}
		for fi in frames.size():
			var fr: Dictionary = frames[fi]
			for lf in fr:
				if not per_layer.has(lf):
					per_layer[lf] = []
				per_layer[lf].append([fr[lf].file, fr[lf].pos, int(ticks[fi]) if fi < ticks.size() else 8])
		for lf in per_layer:
			_add_anim_node(str(lf), per_layer[lf], info)
	for p in an.get("palettes", []):
		var ov: Array = p.get("overlays", [])
		if ov.is_empty():
			continue
		var ticks: Array = p.get("frame_ticks", [])
		var per_layer := {}
		for fi in ov.size():
			var fr: Dictionary = ov[fi]
			for lf in fr:
				if not per_layer.has(lf):
					per_layer[lf] = []
				per_layer[lf].append([fr[lf].file, fr[lf].pos, int(ticks[fi]) if fi < ticks.size() else 8])
		for lf in per_layer:
			_add_anim_node(str(lf), per_layer[lf], info)

func _add_anim_node(layer: String, frames: Array, info: Dictionary) -> void:
	var above = info.get("above_layer", null)
	var parent: Node2D = world
	var s := Sprite2D.new()
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if above != null and layer == str(above):
		world.add_child(s)
		world.move_child(s, world.get_child_count() - 1)
	else:
		world.add_child(s)
		# right above its own layer: a lower layer's overlays (e.g. the Pelipper sea waves) must stay under
		# the layers drawn on top of it (the cliff)
		var own = layer_sprites.get(layer, null)
		if own != null and own.get_parent() == world:
			# after this layer's earlier overlays (keeping their order), but never past the next layer sprite
			var last = own.get_meta("last_overlay", own) if own.has_meta("last_overlay") else own
			if not is_instance_valid(last) or last.get_parent() != world:
				last = own
			world.move_child(s, last.get_index() + 1)
			own.set_meta("last_overlay", s)
		else:
			world.move_child(s, actors.get_index())
	var fl: Array = []
	for f in frames:
		fl.append([GData.ground_tex(str(f[0]), false), Vector2(f[1][0], f[1][1]), int(f[2])])
	anim_nodes.append({"node": s, "frames": fl, "t": 0, "i": 0})
	if fl.size() > 0:
		s.texture = fl[0][0]
		s.position = fl[0][1]

func _anim_tick() -> void:
	_pal_tick()
	for a in anim_nodes:
		var fr: Array = a.frames
		if fr.is_empty():
			continue
		a.t += 1
		if a.t >= int(fr[a.i][2]):
			a.t = 0
			a.i = (a.i + 1) % fr.size()
			a.node.texture = fr[a.i][0]
			a.node.position = fr[a.i][1]

func _build_dungeon_view(info: Dictionary) -> void:
	var terr: Array = GData.ground_json(str(info.get("terrain", "")))
	var w := int(info.get("w", 1))
	var h := int(info.get("h", 1))
	var pb := PackedByteArray()
	pb.resize(w * h)
	for y in mini(h, terr.size()):
		for x in mini(w, terr[y].size()):
			pb[y * w + x] = int(terr[y][x])
	var tv := TerrainView.new()
	tv.build({"w": w, "h": h, "terrain": pb}, dungeon_tileset_key(int(info.get("tileset", 14))))
	world.add_child(tv)
	world.move_child(tv, 0)
	dun_view = tv

## The tileset a dungeon-style ground map uses, named the way the dungeon floors name them (dungeon.gd
## build_floor): boss summits (64+) use Red's arena graphics, the rest the upscaled set (t..) or the
## original (r..). The old "t%d" lookup only matched Tiny Woods (t14), so e.g. the Mt. Steel summit
## after Skarmory showed Tiny Woods.
static func dungeon_tileset_key(t: int) -> String:
	var a := DungeonGfx.arena_key(t)
	if a != "":
		return a                  # TerrainView draws these from dungeon_gfx.json
	var k := "t%02d" % t
	if DB.tilesets.has(k) and DB.tilesets[k].has("hd"):
		return k
	k = "r%02d" % t
	if DB.tilesets.has(k):
		return k
	return "t14"

## Collision test on the 8x8 grid (CheckMapCollision): any tile in the box with the bit set.
func map_collide(p: Vector2i, sz: Vector2i, bit: int) -> bool:
	if collision.is_empty():
		return false
	for y in range(p.y, p.y + sz.y):
		for x in range(p.x, p.x + sz.x):
			if y < 0 or x < 0 or y >= col_h or x >= col_w:
				if bit == 0x80:
					return true
				continue
			if int(collision[y][x]) & bit:
				return true
	return false

## sub_80A3BB0 / GroundMap_Action: the personality-test backdrops drift (layer 0 down, layer 1 up, 0.5 px/frame).
func _scroll_update() -> void:
	var nm := str(map_file)
	if nm == "silent_chasm_entry":
		# sub_80A59DC MAP_SILENT_CHASM_ENTRY: the mist layer drifts right 1 px every 4 frames, wrapping around
		scroll.f0 = int(scroll.f0) + 1
		scroll.f8 = Vector2i(scroll.f8.x + int(scroll.f0) / 4, 0)
		scroll.f0 = int(scroll.f0) & 3
		var ww := int(map_info.get("w", 672))
		var spr = layer_sprites.get(str(map_info.get("blend", {}).get("layer", "")), null)
		if spr and spr.texture:
			var k := float(spr.texture.get_width()) / float(maxi(ww, 1))
			spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			spr.region_enabled = true
			spr.region_rect = Rect2(float(posmod(-int(scroll.f8.x), ww)) * k, 0, spr.texture.get_width(), spr.texture.get_height())
		return
	if not nm.begins_with("personality_test"):
		return
	scroll.f4 = int(scroll.f4) + 2
	scroll.f8 = Vector2i(0, scroll.f8.y + int(scroll.f4) / 4)
	scroll.f4 = int(scroll.f4) & 3
	var hh := int(map_info.get("h", 384))
	var y := posmod(int(scroll.f8.y), maxi(hh, 1))
	_scroll_layer(map_lo, y)
	_scroll_layer(map_hi, -y)

func _scroll_layer(spr: Sprite2D, dy: int) -> void:
	if spr == null or spr.texture == null:
		return
	var k := float(spr.texture.get_width()) / float(maxi(int(map_info.get("w", 1)), 1))
	spr.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	spr.region_enabled = true
	spr.region_rect = Rect2(0, float(dy) * k, spr.texture.get_width(), spr.texture.get_height())

# ------------------------------------------------------------------ links (ground_link.c)
func _cpos(p: Array, cur: Vector2i) -> Vector2i:
	var out := cur
	if not (int(p[2]) & 4):
		out.x = int(p[0]) << 11
		if int(p[2]) & 2:
			out.x += 0x400
	if not (int(p[3]) & 4):
		out.y = int(p[1]) << 11
		if int(p[3]) & 2:
			out.y += 0x400
	return out

func link_pos(i: int, cur: Vector2i) -> Vector2i:
	if i < 0 or i >= links.size():
		return cur
	return _cpos(links[i].pos, cur)

func link_area(i: int, cur: Vector2i) -> Array:
	if i < 0 or i >= links.size():
		return [cur, cur]
	var a := _cpos(links[i].pos, cur)
	return [a, a + Vector2i(int(links[i].w) * 8 << 8, int(links[i].h) * 8 << 8)]

# ------------------------------------------------------------------ map scripts
func station_script(map: int, grp: int, sec: int) -> Vector2i:
	var M = GData.maps[map] if map >= 0 and map < GData.maps.size() else null
	if M == null or grp < 0 or grp >= M.groups.size() or sec < 0 or sec >= M.groups[grp].size():
		return GData.NULL_PTR
	var st = M.groups[grp][sec].station
	if st == null:
		return GData.NULL_PTR
	return GData.ptr(st.script)

func map_execute_event(script_id: int, sub: bool) -> void:
	var info := {"ptr": GData.fn_script(script_id), "state": 5 if sub else 2, "group": -1, "sector": -1}
	map_action.execute(info)

func map_execute_station(map: int, grp: int, sec: int, sub: bool) -> void:
	var info := {"ptr": station_script(map, grp, sec), "state": 5 if sub else 2, "group": grp, "sector": sec}
	pending_cues.clear()      # new scene: cues held from the previous one don't apply
	map_action.execute(info)

func map_execute_enter(map: int) -> void:
	var info := {"ptr": station_script(map, 0, 0), "state": 2, "group": 0, "sector": 0}
	map_action.execute(info)

func action_of(k: Vector2i):
	match k.x:
		0:
			return map_action
		1:
			return lives[k.y].action if lives[k.y].kind_id != -1 else null
		2:
			return objects[k.y].action if objects[k.y].kind != -1 else null
		3:
			return effects[k.y].action if effects[k.y].kind != -1 else null
	return null

func cancel_all_entities() -> void:
	for L in lives:
		if L.kind_id != -1:
			L.action.reset_for_delete()
	for T in objects:
		if T.kind != -1:
			T.action.reset_for_delete()
	for T in effects:
		if T.kind != -1:
			T.action.reset_for_delete()

func _delete_all_entities() -> void:
	for i in N_LIVES:
		if lives[i].kind_id != -1:
			_lives_delete(i)
	for i in N_OBJECTS:
		if objects[i].kind != -1:
			_thing_delete(objects[i])
	for i in N_EFFECTS:
		if effects[i].kind != -1:
			_thing_delete(effects[i])
	for e in events:
		e.used = false
	lives_meta = {"dir28": -1, "head": -1, "slots": [{"i8": -1, "s0": 0, "s4": 0}, {"i8": -1, "s0": 0, "s4": 0}, {"i8": -1, "s0": 0, "s4": 0}], "trail": []}

func _sector(map: int, grp: int, sec: int):
	var M = GData.maps[map] if map >= 0 and map < GData.maps.size() else null
	if M == null or grp < 0 or grp >= M.groups.size() or sec < 0 or sec >= M.groups[grp].size():
		return null
	return M.groups[grp][sec]

# ------------------------------------------------------------------ lives
func lives_select(grp: int, sec: int) -> void:
	lives_select_map(vis_map, grp, sec)

func lives_select_map(map: int, grp: int, sec: int) -> void:
	var S = _sector(map, grp, sec)
	if S == null:
		return
	for d in S.lives:
		lives_add(-1, d, grp, sec)
	# remake: Croagunk's Swap Shop stands in Pokémon Square whenever the Kecleon shop there is open
	# remake: the Debug NPC at the team base (off unless Game Options -> Debug NPC is on)
	if DebugNpc.enabled() and grp == 0 and sec >= 1 and sec <= 6 and cur_map == GData.map_id("MAP_TEAM_BASE"):
		lives_add(-1, {"kind": GData.debug_kind, "u1": DebugNpc.DIR, "pos": DebugNpc.SPOT, "scripts": [null, null, null, null]}, grp, sec)
	if map == SwapShop.MAP and SwapShop.unlocked():
		for d in S.lives:
			if int(d.kind) == 71 and d.scripts[2] != null:
				lives_add(-1, {"kind": GData.croagunk_kind, "u1": SwapShop.DIR, "pos": SwapShop.spot(), "scripts": [null, null, null, null]}, grp, sec)
				break

func lives_cancel(grp: int, sec: int) -> void:
	for i in N_LIVES:
		var L: GLive = lives[i]
		if L.kind_id != -1 and L.group == grp and (sec < 0 or L.sector == sec):
			_lives_delete(i)

func lives_cancel_offscreen() -> void:
	for i in N_LIVES:
		if lives[i].kind_id != -1 and not _onscreen(lives[i].get_center()):
			_lives_delete(i)

func _onscreen(p: Vector2i) -> bool:
	var cam := camera.top_left_px()
	var r := Vector2i(p.x >> 8, p.y >> 8) - cam
	return r.x >= -64 and r.x <= 303 and r.y >= -16 and r.y <= 207

## sub_80A7B94: resolve special lives kinds (player / partner / team / friends). Returns [kind, slot class].
func resolve_kind(k: int) -> Array:
	var types: Array = GData.extra.lives_types
	if k < 0 or k >= types.size():
		return [-1, -1]
	var t := int(types[k][0])
	var ret := -1
	if t == 1:
		if k == 0:
			match GVars.get_val(null, GVars.PLAYER_KIND):
				0:
					k = 1
				1:
					k = 2
				2:
					k = Story.leader_kind()
				_:
					return [-1, -1]
		ret = 0
	elif t == 2:
		var p1 := GVars.get_val(null, GVars.PARTNER1_KIND)
		var p2 := GVars.get_val(null, GVars.PARTNER2_KIND)
		if k == 4 or k == 5:
			var partner := 0
			if k == 4:
				partner = p1 if p1 != 0 else p2
			else:
				partner = p2 if p1 != 0 else 0
			match partner:
				1:
					k = 6
				2:
					k = 7
				3:
					k = Story.leader_kind() + 5
				_:
					return [-1, -1]
		match k:
			6:
				ret = 2
				if Story.leader_is_hero():
					k = 6
			7:
				ret = 1
				if Story.leader_is_partner():
					k = 6
			8:
				ret = 2
			_:
				return [-1, -1]
	elif t == 3:
		if k >= 10 and k <= 13:
			if k - 10 >= Story.base_team().size():
				return [-1, -1]
			return [k, -1]
		elif k >= 14 and k <= 29:
			if Story.friend_area_mon(GVars.get_val(null, GVars.GROUND_MAP), k - 14).is_empty():
				return [-1, -1]
			return [k, -1]
		return [-1, -1]
	elif k == 0x23:
		if Story.leader_is_hero():
			k = 0x21
		elif Story.leader_is_partner():
			k = 0x22
	return [k, ret]

## sub_80A7DDC: species (our key) for a resolved kind.
func species_of_resolved(k: int) -> String:
	if k < 0:
		return ""
	match k:
		1, 6, 33:
			return Story.hero_species()
		2, 7, 34:
			return Story.partner_species()
		3, 8, 35:
			return Story.leader_species()
		36:
			return GData.species_of_red(Story.STARTERS_RED[randi_range(0, 14)])
		32:
			var nf := GVars.get_val(null, GVars.NEW_FRIEND_KIND)
			return GData.species_of_red(nf) if nf != 0 else ""
		30, 31:
			return Story.job_client_species(k == 30)
	if k >= 10 and k <= 13:
		var bt: Array = Story.base_team()
		return bt[k - 10].sp if k - 10 < bt.size() else ""
	if k >= 14 and k <= 29:
		var e: Dictionary = Story.friend_area_mon(GVars.get_val(null, GVars.GROUND_MAP), k - 14)
		return str(e.get("sp", ""))
	var types: Array = GData.extra.lives_types
	if k == GData.croagunk_kind:
		return "0453"
	if k == GData.debug_kind:
		return DebugNpc.SPECIES
	if k == 71:
		return "0352p"            # the Kecleon Wares brother: GetPokemonOverworldPalette(id, kecleonShop) -> purple
	if k < types.size() and int(types[k][1]) == 422:
		return "@statue"          # MONSTER_STATUE: Red's stone statue (ornament sprite, stoneim palette)
	return GData.species_of_red(int(types[k][1])) if k < types.size() else ""

## Shiny team members / Friend Area residents keep their shiny colours in town scenes.
func shiny_of_resolved(k: int) -> bool:
	if k >= 10 and k <= 13:
		var bt: Array = Story.base_team()
		return k - 10 < bt.size() and bool((bt[k - 10] as Dictionary).get("shiny", false))
	if k >= 14 and k <= 29:
		return bool(Story.friend_area_mon(GVars.get_val(null, GVars.GROUND_MAP), k - 14).get("shiny", false))
	if k in [3, 8, 35] and not Game.team.is_empty() and not (Story.leader_is_hero() or Story.leader_is_partner()):
		return bool(Game.team[0].get("shiny", false))
	return false

func species_of_kind(k: int) -> String:
	var r := resolve_kind(k)
	return species_of_resolved(int(r[0]))

func red_species_of_kind(k: int) -> int:
	var sp := species_of_kind(k)
	return GData.red_of_species(sp) if sp != "" else 0

func lives_name_by_kind(k: int) -> String:
	var r := resolve_kind(k)
	var kk := int(r[0])
	var nm := Story.name_of_kind(kk)
	if nm != "":
		return "[color=#7fe0ff]%s[/color]" % nm
	var sp := species_of_resolved(kk)
	if kk == 52 or kk == 100:
		return "???"
	return "[color=#7fe0ff]%s[/color]" % (DB.species.get(sp, DB.species.get(sp.substr(0, 4), {})).get("name", "???") if sp != "" else "???")

func rename_lives(k: int, nm: String) -> void:
	Story.rename_kind(int(resolve_kind(k)[0]), nm)

## sub_80A7AE8: lives slot holding a (resolved) kind
func lives_find(k: int) -> int:
	var kk := int(resolve_kind(k)[0])
	if kk == -1:
		return -1
	for i in N_LIVES:
		if lives[i].kind_id == kk:
			return i
	return -1

const LIVES_FLAGS := {1: 0x2300181D, 2: 0x23001000, 3: 0x2300068D, 6: 0x2000000D, 7: 0x20000, 8: 0, 9: 0xC0000, 10: 0x20010000}

func lives_add(slot: int, d: Dictionary, grp: int, sec: int) -> int:
	var r := resolve_kind(int(d.kind))
	var kk := int(r[0])
	var cls := int(r[1])
	if kk == -1:
		return -1
	var sp := species_of_resolved(kk)
	match cls:
		0:
			slot = 0
		1:
			slot = 1
		2:
			if GVars.get_val(null, GVars.PARTNER1_KIND) == 0:
				cls = 1
			slot = 2
	var types: Array = GData.extra.lives_types
	var td: Array = types[kk]
	if slot < 0:
		if kk == 0x21 and lives[0].kind_id == 1:
			return -1
		if kk == 0x23 and lives[0].kind_id == 3:
			return -1
		slot = -1
		for i in N_LIVES:
			if lives[i].kind_id == kk:
				slot = i
				break
		if slot < 0:
			for i in range(3, N_LIVES):
				if lives[i].kind_id == -1:
					slot = i
					break
		if slot < 0:
			return -1
	var L: GLive = lives[slot]
	var fresh := L.kind_id == -1
	L.kind_id = kk
	L.group = grp
	L.sector = sec
	L.species = sp
	L.red_species = GData.red_of_species(sp) if sp != "" else 0
	L.ctrl = {"s0": 9, "s4": 0, "t10": -1, "t14": 0, "t8": 0, "dC": -1}
	var tt := int(td[0])
	L.flags = LIVES_FLAGS.get(tt, 0x2300068D)
	if tt == 1:
		L.ctrl.s0 = 1
	L.size = Vector2i(int(td[2]) << 11, int(td[3]) << 11)
	L.half = L.size / 2
	L.dir0 = int(d.u1)
	L.pos0 = _cpos(d.pos, Vector2i.ZERO)
	if fresh:
		L.direction1 = L.dir0
		L.p144 = L.pos0 - L.half
		L.p14C = L.pos0 + L.half
		L.p154 = Vector2i.ZERO
		L.follow_idx = cls if cls >= 0 else 0
		if cls >= 0:
			lives_meta.slots[cls] = {"i8": -1, "s0": 0, "s4": 0}
		L.fa_dialog = randi_range(0, 20) if kk >= 14 and kk <= 29 else 0
	L.event_id = events_find(0x20, L.p144, L.p14C) if (L.flags & 0x800) else -1
	L.b_from = bounds_a
	L.b_to = bounds_b
	if fresh:
		L.direction2 = -1
		L.anim_speed = 0x300
		L.anim_kind = 1
		L.walk_t = 0
		L.anim = 0x807
		L.dir_dirty = true
		L.emote_req = 0
		L.sprite = GSprite.new()
		L.sprite.set_species(sp + ("*" if sp != "" and shiny_of_resolved(kk) else ""))
		actors.add_child(L.sprite)
		L.sprite.play(0x300, 0)
		_apply_sprite_flags(L.sprite, L.flags)
	var restarted := false
	var follow_info := _follow_info()
	if not fresh and L.action != null and L.action.running_script(follow_info):
		var keep_dir := L.action.sd2.stored_dir if L.action.sd2.saved_state != 0 else L.action.sd.stored_dir
		var keep_24 := L.action.sd2.unk24 if L.action.sd2.saved_state != 0 else L.action.sd.unk24
		L.action = GAction.new(self, L, 1, grp, sec)
		L.action.execute(follow_info)
		L.action.sd.unk24 = keep_24
		L.action.sd.stored_dir = keep_dir
		restarted = true
	else:
		L.action = GAction.new(self, L, 1, grp, sec)
	var sc: Array = d.scripts
	L.action.set_predefined(1, GData.ptr(sc[1]) if sc[1] != null else GData.fn_script(GData.fn_id("LIVES_MOVE_NORMAL")))
	L.action.set_predefined(2, GData.ptr(sc[2]) if sc[2] != null else GData.fn_script(GData.fn_id("INCOMPLETE_TALK")))
	L.action.set_predefined(3, GData.ptr(sc[3]) if sc[3] != null else GData.fn_script(GData.fn_id("LIVES_REPLY_NORMAL")))
	if sc[0] != null:
		L.action.set_predefined(0, GData.ptr(sc[0]))
		if not fresh and not restarted and not (L.flags & 0x1800):
			L.action.execute(follow_info)
			L.action.sd.unk24 = L.anim_kind | L.anim_speed
			L.action.sd.stored_dir = L.direction1
		L.action.execute_predefined(0)
	elif restarted:
		L.dir_dirty = true
		L.direction1 = L.action.sd.stored_dir
		L._event_index(L.action.sd.unk24)
	if tt == 1 and fresh:
		camera.follow(1, slot)
	return slot

func _follow_info() -> Dictionary:
	return {"ptr": GData.fn_script(0x19), "state": 1, "group": -1, "sector": -1}

func _lives_delete(i: int) -> void:
	var L: GLive = lives[i]
	if L.sprite:
		L.sprite.queue_free()
		L.sprite = null
	L.kind_id = -1
	L.action = null

func _apply_sprite_flags(s: GSprite, f: int) -> void:
	var sf := (f >> 16) & 0x337F
	s.visible_flag = not (sf & 0x40)
	s.blink = (sf & 0x10) != 0
	s.shadow = (sf & 0x100) != 0
	s.zbias = (0x40 if sf & 4 else 0) - (0x40 if sf & 2 else 0) + (8 if sf & 1 else 0)

func lives_set_flags(i: int, f: int) -> void:
	var L: GLive = lives[i]
	if L.kind_id == -1:
		return
	if L.follow_idx == 0:
		if f & 0x3000:
			_meta_reset()
	elif f & 0x1000:
		lives_meta.slots[L.follow_idx] = {"i8": -1, "s0": 0, "s4": 0}
	L.flags |= f
	if L.sprite:
		_apply_sprite_flags(L.sprite, L.flags)

func lives_clear_flags(i: int, f: int) -> void:
	var L: GLive = lives[i]
	if L.kind_id == -1:
		return
	if L.follow_idx == 0 and (f & 0x3000):
		_meta_reset()
	L.flags &= ~f
	if L.sprite:
		_apply_sprite_flags(L.sprite, L.flags)

func _meta_reset() -> void:
	lives_meta.head = -1
	lives_meta.dir28 = -1
	for s in lives_meta.slots:
		s.i8 = -1
		s.s0 = 0
		s.s4 = 0

func lives_collision(self_id: int, f: int, a: Vector2i, b: Vector2i) -> int:
	for i in N_LIVES:
		var L: GLive = lives[i]
		if i != self_id and L.kind_id != -1 and (L.flags & f) and L.p144.x < b.x and L.p14C.x > a.x and L.p144.y < b.y and L.p14C.y > a.y:
			return i
	return -1

## GroundLives_ExecutePlayerScriptActionLives: player talks to lives id2.
func lives_player_talk(id1: int, id2: int) -> bool:
	if id1 < 0 or id2 < 0:
		return false
	var L1: GLive = lives[id1]
	var L2: GLive = lives[id2]
	if L1.kind_id == -1 or L2.kind_id == -1:
		return false
	if L2.kind_id == GData.croagunk_kind and GData.croagunk_kind >= 0:
		_croagunk_talk(L1, L2)
		return true
	if L2.kind_id == GData.debug_kind and GData.debug_kind >= 0:
		_debug_talk(L1, L2)
		return true
	var info := L2.action.predefined_info(2)
	if info.ptr == GData.NULL_PTR:
		return false
	L2.action.execute_predefined(3, Vector2i(1, id1))
	return _player_script(L1, Vector2i(1, id2), info)

## The team formation changed in the menu (Make Leader, members swapped). Red can only do that in the
## post-game, where FORMATION_HERO also moves the story to 19,2 (the post-game tutorial). The remake lets you
## change the team any time, and running FORMATION_HERO mid-story threw the save into the post-game (19,2:
## Zero Isle / Destiny Tower opened, the base finished). Before the post-game only its reload part runs.
func formation_changed() -> void:
	if GVars.after(GVars.SCENARIO_MAIN, 18, -1):
		map_execute_event(GData.fn_id("FORMATION_HERO"), false)
		return
	GVars.set_val(null, GVars.GROUND_GETOUT, GVars.get_val(null, GVars.GROUND_ENTER))
	GVars.set_val(null, GVars.START_MODE, 2)
	map_execute_event(GData.fn_id("EVENT_DIVIDE"), false)

## remake: talking to the Swap Shop's Croagunk (no Red script: the shop runs straight away).
func _croagunk_talk(L1: GLive, L2: GLive) -> void:
	set_player_mode(11)
	var t := GDir.sized_delta8(L2.get_center(), L2.get_size(), L1.get_center(), L1.get_size())
	if t != -1:
		L2.direction1 = t
		L2.dir_dirty = true
	await get_tree().process_frame
	await SwapShop.open(ui_root)
	set_player_mode(0)

## remake: the Debug NPC's menu; a story change reloads the ground from the base (EVENT_DIVIDE runs it).
func _debug_talk(L1: GLive, L2: GLive) -> void:
	set_player_mode(11)
	var t := GDir.sized_delta8(L2.get_center(), L2.get_size(), L1.get_center(), L1.get_size())
	if t != -1:
		L2.direction1 = t
		L2.dir_dirty = true
	await get_tree().process_frame
	var reload: bool = await DebugNpc.open(self)
	if reload and host and host.has_method("start_story"):
		GVars.set_val(null, GVars.GROUND_ENTER, GData.map_id("MAP_TEAM_BASE"))
		GVars.set_val(null, GVars.GROUND_ENTER_LINK, 0)
		host.call_deferred("start_story", STARTMODE_GROUND)
		return
	set_player_mode(0)

func _player_script(L: GLive, trig, info) -> bool:
	L.anim_speed = 0x300
	L.anim_kind = 1
	L.walk_t = 0
	if L.anim != 0x807:
		L.anim = 0x807
		L.dir_dirty = true
	if info != null:
		return L.action.execute(info, trig)
	return false

func object_player_talk(id1: int, id2: int) -> bool:
	var T: GThing = objects[id2]
	if T.kind == -1:
		return false
	var info := T.action.predefined_info(2)
	if info.ptr == GData.NULL_PTR:
		return false
	T.action.execute(T.action.predefined_info(3), Vector2i(1, id1))
	return _player_script(lives[id1], Vector2i(2, id2), info)

func event_player_trigger(id1: int, ev: int) -> bool:
	var e: Dictionary = events[ev]
	if Dialog.auto:
		print("    TRIGGER ev%d %s var37=%d" % [ev, GData.scr_names[e.script.x] if e.used and e.script.x >= 0 else "?", GVars.get_val(null, GVars.WARP_LOCK)])
	if not e.used:
		return false
	return _player_script(lives[id1], null, {"ptr": e.script, "state": 2, "group": e.group, "sector": e.sector})

func _lives_action() -> void:
	for i in N_LIVES:
		var L: GLive = lives[i]
		if L.kind_id == -1:
			continue
		var r := L.action.handle()
		if r == GAction.RET_04:
			_lives_delete(i)
			continue
		if r == GAction.RET_00:
			if L.flags & 0x800:
				var c := L._controller()
				match int(c[0]):
					1, 2, 5, 8:
						L._player_act(int(c[1]), int(c[2]))
			elif L.flags & 0x1000:
				_follow(L)
			else:
				L.action.execute_predefined(1)
		if L.dir_dirty and L.sprite:
			L.dir_dirty = false
			L.direction2 = L.direction1
			L.sprite.play(L.anim, L.direction1)
	_trail_update()

## Leader trail for the followers (GroundLives_Action tail).
func _trail_update() -> void:
	var L: GLive = lives[0]
	lives_meta.slots[0].s0 = 0
	lives_meta.slots[0].s4 = 0
	if L.kind_id == -1 or (L.flags & 0x2000) or not (L.flags & 0x1000):
		_meta_reset()
		return
	var tr: Array = lives_meta.trail
	if lives_meta.head < 0:
		tr.clear()
		for i in 64:
			tr.append({"d": 0, "p": Vector2i.ZERO})
		lives_meta.head = 0
		tr[0] = {"d": 0, "p": L.get_center()}
		for s in lives_meta.slots:
			s.i8 = 0
			s.s0 = 0
			s.s4 = 0
	else:
		var prev: int = lives_meta.head
		var nxt := (prev + 1) % 64
		var p := L.get_center()
		var dd: Vector2i = p - tr[prev].p
		var dist := maxi(absi(dd.x), absi(dd.y))
		if dist > 0:
			tr[nxt] = {"d": dist, "p": p}
			lives_meta.head = nxt
			lives_meta.slots[0].s0 = dist

## sub_80AB5D4: follow the leader's trail.
func _follow(L: GLive) -> void:
	var fi := L.follow_idx
	if fi == 0:
		return
	var meta: Dictionary = lives_meta.slots[fi]
	var tr: Array = lives_meta.trail
	L.anim_speed = 0x300
	L.anim_kind = 1
	if L.flags & 0x2000:
		if L.direction1 != 4 or L.anim != 0x800:
			L.walk_t = 0
			L.anim = 0x800
			L.direction1 = 4
			L.dir_dirty = true
		if int(lives_meta.dir28) != -1:
			L._move_rel(GDir.vec(int(lives_meta.dir28), 0x100))
		if meta.i8 < 0 and lives_meta.head >= 0:
			meta.i8 = lives_meta.head
			meta.s0 = 0
			meta.s4 = 0
		return
	var p32 := L.get_center()
	var p16 := p32
	if meta.i8 < 0:
		if lives_meta.head < 0:
			return
		meta.i8 = lives_meta.head
		meta.s0 = 0
		meta.s4 = 0
	if tr.size() < 64:
		return
	var r7: int = meta.s0
	var go := true
	while go:
		var r1 := 0
		var tp: Vector2i = tr[meta.i8].p
		var sx: int = tp.x - p16.x
		var sy: int = tp.y - p16.y
		if sx > 0:
			if sx > r7:
				p16.x += r7
				go = false
			else:
				p16.x = tp.x
			r1 = sx
		elif sx < 0:
			if sx < -r7:
				p16.x -= r7
				go = false
			else:
				p16.x = tp.x
			r1 = -sx
		if sy > 0:
			if sy > r7:
				p16.y += r7
				go = false
			else:
				p16.y = tp.y
				r1 = maxi(r1, sy)
		elif sy < 0:
			if sy < -r7:
				p16.y -= r7
				go = false
			else:
				p16.y = tp.y
				r1 = maxi(r1, -sy)
		if go:
			r7 -= r1
			if r7 <= 0:
				go = false
			elif meta.i8 != lives_meta.head:
				meta.i8 = (meta.i8 + 1) % 64
			else:
				go = false
	var r6 := 0
	var head: int = lives_meta.head
	if head > meta.i8:
		for i in range(meta.i8 + 1, head):
			r6 += int(tr[i].d)
	elif head < meta.i8:
		for i in range(meta.i8 + 1, 64):
			r6 += int(tr[i].d)
		for i in range(0, head):
			r6 += int(tr[i].d)
	var gap := [0x1400, 0x1400, 0x1800]
	var r12: int = int(lives_meta.slots[fi - 1].s4) + gap[fi]
	var tpp: Vector2i = tr[meta.i8].p
	r6 += maxi(absi(tpp.x - p16.x), absi(tpp.y - p16.y))
	meta.s4 = r6
	if r6 <= r12:
		if meta.s0 > 0:
			meta.s0 -= 256
	elif r6 <= fi * 0x1800:
		if meta.s0 < 256:
			meta.s0 += 256
	else:
		var v: int = maxi(int(lives_meta.slots[fi - 1].s0), 256)
		if meta.s0 < v:
			meta.s0 += 256
	if ((head + 64) - meta.i8) % 64 >= 60:
		meta.i8 = (head + 5) % 64
		p16 = tr[meta.i8].p
	if L.move_real(p16) == 0:
		var d := p16 - p32
		L.direction1 = GDir.step_towards(L.direction1, GDir.vec_dir8(d))
		var r4 := 0x807
		if meta.s0 > 0:
			L.walk_t = 4
			r4 = 0xA00 if meta.s0 > 0x200 else 0x800
		else:
			L.walk_t = 0
		L._water_check()
		if L.dir_dirty or r4 != L.anim or L.direction2 != L.direction1:
			L.dir_dirty = false
			L.anim = r4
			L.direction2 = L.direction1
			if L.sprite:
				L.sprite.play(r4, L.direction1)

## sub_80ABA7C: per-frame sprite position / animation.
func _lives_sprites() -> void:
	for L in lives:
		if L.kind_id == -1:
			continue
		if L.walk_t > 0:
			L.walk_t -= 1
			if L.walk_t <= 0 and (L.anim_kind == 1 or L.anim_kind == 2):
				L._event_index(L.anim_kind)
		if L.sprite == null:
			continue
		if L.dir_dirty:
			L.dir_dirty = false
			L.direction2 = L.direction1
			L.sprite.play(L.anim, L.direction1)
		if L.emote_req != 0:
			L.sprite.show_effect(L.emote_req, L.emote_arg)
			L.emote_req = 0
		var c = L.get_center()
		L.sprite.position = Vector2(c.x >> 8, c.y >> 8)
		L.sprite.height = float(L.p154.x + L.p154.y) / 256.0
		L.sprite.z_index = L.sprite.zbias / 0x40
		L.sprite.tick()

# ------------------------------------------------------------------ objects / effects
func objects_select(grp: int, sec: int) -> void:
	objects_select_map(vis_map, grp, sec)

func objects_select_map(map: int, grp: int, sec: int) -> void:
	var S = _sector(map, grp, sec)
	if S == null:
		return
	for d in S.objects:
		objects_add(-1, d, grp, sec)

func effects_select(grp: int, sec: int) -> void:
	var S = _sector(vis_map, grp, sec)
	if S == null:
		return
	for d in S.effects:
		effects_add(-1, d, grp, sec)

func objects_cancel(grp: int, sec: int) -> void:
	for T in objects:
		if T.kind != -1 and T.group == grp and (sec < 0 or T.sector == sec):
			_thing_delete(T)

func effects_cancel(grp: int, sec: int) -> void:
	for T in effects:
		if T.kind != -1 and T.group == grp and (sec < 0 or T.sector == sec):
			_thing_delete(T)

func objects_cancel_offscreen() -> void:
	for T in objects:
		if T.kind != -1 and not _onscreen(T.get_center()):
			_thing_delete(T)

func effects_cancel_offscreen() -> void:
	for T in effects:
		if T.kind != -1 and not _onscreen(T.get_center()):
			_thing_delete(T)

const OBJ_FLAGS := {1: 0, 11: 0, 10: 0x20000, 12: 0x40000, 15: 0x20C0000, 14: 0x220C0000, 13: 0x20010000, 9: 5,
	3: 0x22000184, 4: 0x184, 5: 0x184, 6: 0x44, 7: 0x84, 8: 0x180, 2: 0x20000C4}

func objects_add(slot: int, d: Dictionary, grp: int, sec: int) -> int:
	var kind := int(d.kind)
	if kind == 0x1A:
		if GVars.get_val(null, GVars.BASE_LEVEL) < 2:
			kind = 0x1B
		else:
			var fk := GVars.get_val(null, GVars.FLAG_KIND)
			kind = GVars.get_val(null, GVars.BASE_KIND) + 0x1C if fk == 0 else fk + 0x2B
	var types: Array = GData.extra.object_types
	var td: Array = types[kind] if kind < types.size() else [0, 0, 0]
	if slot < 0:
		if kind == 0xD or kind == 0xE:
			for i in N_OBJECTS:
				if objects[i].kind == kind:
					slot = i
		if slot < 0:
			for i in N_OBJECTS:
				if objects[i].kind == -1:
					slot = i
					break
		if slot < 0:
			return -1
	var T: GThing = objects[slot]
	var fresh := T.kind == -1
	T.kind = kind
	T.group = grp
	T.sector = sec
	T.flags = OBJ_FLAGS.get(int(td[0]), 0x2000185)
	if int(td[1]) == 0:
		T.size = Vector2i(int(d.w) << 11, int(d.h) << 11)
	else:
		T.size = Vector2i(int(td[1]) << 11, int(td[2]) << 11)
	T.half = T.size / 2
	T.direction1 = int(d.u1)
	T.pos0 = _cpos(d.pos, Vector2i.ZERO)
	if fresh:
		T.p124 = T.pos0 - T.half
		T.p12C = T.pos0 + T.half
		T.p134 = Vector2i.ZERO
		T.anim = 0x800
		T.dir_dirty = true
		var ok: Array = GData.extra.object_kinds
		if kind < ok.size() and ok[kind][2] != null:
			T.sprite = GSprite.new()
			T.sprite.set_ornament(str(ok[kind][2]))
			actors.add_child(T.sprite)
	T.b_from = bounds_a
	T.b_to = bounds_b
	T.action = GAction.new(self, T, 2, grp, sec)
	var sc: Array = d.scripts
	var pkm := T.sprite != null and T.sprite.has_pokemon()
	T.action.set_predefined(1, GData.ptr(sc[1]) if sc[1] != null else GData.NULL_PTR)
	T.action.set_predefined(2, GData.ptr(sc[2]) if sc[2] != null else GData.fn_script(GData.fn_id("INCOMPLETE_TALK")))
	T.action.set_predefined(3, GData.ptr(sc[3]) if sc[3] != null else GData.fn_script(GData.fn_id("OBJECT_REPLY_NORMAL")))
	if sc[0] != null:
		T.action.set_predefined(0, GData.ptr(sc[0]))
		T.action.execute_predefined(0)
	return slot

func effects_add(slot: int, d: Dictionary, grp: int, sec: int) -> int:
	var kind := int(d.kind)
	if slot < 0:
		for i in N_EFFECTS:
			if effects[i].kind == -1:
				slot = i
				break
		if slot < 0:
			return -1
	var types: Array = GData.extra.effect_types
	var td: Array = types[kind] if kind < types.size() else [0, 1, 1]
	var T: GThing = effects[slot]
	T.kind = kind
	T.group = grp
	T.sector = sec
	T.flags = 0
	if int(td[1]) == 0:
		T.size = Vector2i(int(d.w) << 11, int(d.h) << 11)
	else:
		T.size = Vector2i(int(td[1]) << 11, int(td[2]) << 11)
	T.half = T.size / 2
	T.direction1 = int(d.u1)
	T.pos0 = _cpos(d.pos, Vector2i.ZERO)
	T.p124 = T.pos0 - T.half
	T.p12C = T.pos0 + T.half
	T.p134 = Vector2i.ZERO
	T.b_from = bounds_a - Vector2i(0x10000, 0x10000)
	T.b_to = bounds_b + Vector2i(0x10000, 0x10000)
	T.action = GAction.new(self, T, 3, grp, sec)
	if d.get("script") != null:
		T.action.set_predefined(0, GData.ptr(d.script))
		T.action.execute_predefined(0)
	return slot

func _thing_delete(T: GThing) -> void:
	if T.sprite:
		T.sprite.queue_free()
		T.sprite = null
	T.kind = -1
	T.action = null

func objects_collision(f: int, a: Vector2i, b: Vector2i) -> int:
	for i in N_OBJECTS:
		var T: GThing = objects[i]
		if T.kind != -1 and (T.flags & f) and T.p124.x < b.x and T.p12C.x > a.x and T.p124.y < b.y and T.p12C.y > a.y:
			return i
	return -1

func _things_action(arr: Array) -> void:
	for T in arr:
		if T.kind == -1:
			continue
		var r: int = T.action.handle()
		if r == GAction.RET_04:
			_thing_delete(T)
		elif r == GAction.RET_00 and not T.is_effect:
			if T.action.predefined[1] != GData.NULL_PTR:
				T.action.execute_predefined(1)

func _things_sprites(arr: Array) -> void:
	for T in arr:
		if T.kind == -1 or T.sprite == null:
			continue
		var c: Vector2i = T.get_center()
		T.sprite.position = Vector2(c.x >> 8, c.y >> 8)
		T.sprite.visible_flag = not (T.flags & 0x400000)
		if T.dir_dirty:
			T.dir_dirty = false
			T.sprite.play(T.anim, T.direction1)
		T.sprite.tick()

# ------------------------------------------------------------------ events
func events_select(grp: int, sec: int) -> void:
	var S = _sector(vis_map, grp, sec)
	if S == null:
		return
	for d in S.events:
		for e in events:
			if not e.used:
				var ref: Dictionary = d.ref
				var a := _cpos(d.pos, Vector2i.ZERO)
				e.used = true
				e.kind_id = int(ref.id)
				e.group = grp
				e.sector = sec
				e.flags = 0x60 if int(ref.type) in [1, 2] else 0x20
				e.a = a
				e.b = a + Vector2i(int(d.kind) << 11, int(d.u1) << 11)
				e.script = GData.ptr(ref.script)
				break
	for L in lives:
		if L.kind_id != -1:
			L.event_id = events_find(0x20, L.p144, L.p14C) if (L.flags & 0x800) else -1

func events_cancel(grp: int, sec: int) -> void:
	for e in events:
		if e.used and e.group == grp and (sec < 0 or e.sector == sec):
			e.used = false

func events_find(f: int, a: Vector2i, b: Vector2i) -> int:
	for i in N_EVENTS:
		var e: Dictionary = events[i]
		if e.used and (int(e.flags) & f) and e.a.x < b.x and e.b.x > a.x and e.a.y < b.y and e.b.y > a.y:
			return i
	return -1

## Debug: which scripts are running / waiting (tests).
func dump_actions() -> void:
	var acts: Array = [["map", map_action]]
	for L in lives:
		if L.kind_id != -1:
			acts.append(["L%d(k%d)" % [L.id, L.kind_id], L.action])
	for T in objects:
		if T.kind != -1:
			acts.append(["O%d(k%d)" % [T.id, T.kind], T.action])
	for T in effects:
		if T.kind != -1:
			acts.append(["E%d(k%d)" % [T.id, T.kind], T.action])
	for a in acts:
		var A = a[1]
		if A == null:
			continue
		for d in [A.sd, A.sd2]:
			if d.si.ptr != GData.NULL_PTR:
				var p: Vector2i = d.cur_ptr
				print("    %s %s+%d op=%x state=%d u22=%d u2c=%d br=%d" % [a[0], GData.scr_names[p.x] if p.x >= 0 else "?", p.y, d.cur_op, d.saved_state, d.unk22, d.unk2C, d.branch])
	for i in events.size():
		var e: Dictionary = events[i]
		if e.used:
			print("    EV%d g%d s%d flags=%x a=%s b=%s %s" % [i, e.group, e.sector, e.flags, e.a / 2048, e.b / 2048, GData.scr_names[e.script.x] if e.script.x >= 0 else "?"])
	print("    locks=%s any=%s fadeA=%s text_open=%s" % [locks, any_locked, fadeA.state, text.is_open()])

# ------------------------------------------------------------------ misc hooks used by scripts
func _strip_name(s: String) -> String:
	var r := RegEx.new()
	r.compile("\\[/?color[^\\]]*\\]")
	return r.sub(s, "", true)

func special_func(act: GAction, idx: int, r2: int, r3: int) -> int:
	return Story.special_func(self, act, idx, r2, r3)

func dungeon_requirements(sdun: int) -> Array:
	return Story.dungeon_requirements(sdun)

func dungeon_floor_count(sdun: int) -> int:
	var did := int(GData.dungeon_info(sdun).dungeon)
	var keys: Array = DB.dungeons.get("dungeons", {}).keys()
	if did >= 0 and did < keys.size():
		return DB.dungeons.dungeons[keys[did]].floors.size()
	return 1

func portrait_tex(sp: String, emotion: int) -> Texture2D:
	var names := ["Normal", "Happy", "Pain", "Angry", "Worried", "Sad", "Crying", "Shouting", "Teary-Eyed",
		"Determined", "Joyous", "Inspired", "Surprised", "Dizzy", "Special0", "Special1"]
	return Dialog.portrait_tex(sp, names[clampi(emotion, 0, names.size() - 1)])

func has_item(id: int) -> bool:
	return Story.has_item_red(id)

func remove_item(id: int) -> void:
	Story.remove_item_red(id)

func item_space(id: int) -> int:
	return Story.item_space_red(id)

func modify_bgm(id: int) -> int:
	if id == 50:
		return 50
	if not GVars.quest(GVars.QUEST_UNK12):
		return 999
	if GVars.quest(GVars.QUEST_IN_WORLD_CALAMITY):
		return 19
	if id != 1:
		return id
	return 1

func bgm_play(id: int, _fade: int) -> void:
	if id == 999 or id == 0x3E7:
		Audio.stop_music()
		return
	Audio.play_music("%03d" % id)

func bgm_queue(id: int) -> void:
	if id != 999 and not Audio.music.playing:
		bgm_play(id, 0)

func sound_play(id: int) -> void:
	Audio.sfx("%03d" % id)

func sound_stop(_id: int) -> void:
	pass

func sound_playing(_id: int) -> bool:
	return false

## SPECIAL_TEXT handlers live in Story (shops, naming, dungeon list ...). Returns the result value.
func special_text(kind: int, a1: int, a2: int, s) -> int:
	return await Story.special_text(self, kind, a1, a2, s)
