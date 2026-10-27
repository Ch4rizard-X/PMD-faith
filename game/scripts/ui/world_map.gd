class_name WorldMap
extends Control
## Red's world map trip to a dungeon (world_map.c ShowWorldMap_Async), Red's Friend Areas map
## (friend_areas_map.c / friend_areas_map_util.c) and the same trip on the Explorers of Sky Wonder Map.
##
##   if await WorldMap.trip_red(root, "tiny_woods"): ...      # leader walks base -> dungeon, requirements prompt
##   if await WorldMap.trip_eos(root, "eos_beach_cave"): ...  # same on EoS's map (MAP_BG s01p01a ...)
##   var k := await WorldMap.friend_areas(root)               # Friend Area key, "" = the team base
##
## Art and tables come from the ROMs (gen_world_map.py): Red's wmp2* / wmap* backgrounds and wmapspr markers
## from the titlemenu archive, gDungeonCoordinates, sFriendAreaLocations, gDungeons rules; EoS's
## MAP_BG maps and MAP_MARKER_PLACEMENTS. The leader is drawn with our SpriteCollab walk animation.
## Red counts frames at 60 fps; this screen steps on physics frames (60 / s) to match.

const DIR := "res://assets/worldmap/"
const PX := UITheme.PX
const CELL := 64                                   # wmapspr.png: one 64x64 cell per pose, origin at (32, 32)
## gUnknown_80D40C4: arrow offsets around the leader, by direction (S, SE, E, NE, N, NW, W, SW)
const ARROW_OFF := [Vector2(0, 24), Vector2(24, 24), Vector2(24, 0), Vector2(24, -24), Vector2(0, -24),
	Vector2(-24, -24), Vector2(-24, 0), Vector2(-24, 24)]
## sDistanceRanges (friend_areas_map.c): angle sectors (4096 = full turn) for the nearest-location fallback
const SECTORS := [[0x380, 0x480], [0x80, 0x380], [0xF80, 0x80], [0xC80, 0xF80], [0xB80, 0xC80], [0x880, 0xB80],
	[0x780, 0x880], [0x480, 0x780]]
const BGM_SQUARE := "007"                          # MUS_POKEMON_SQUARE
const BGM_CALAMITY := "019"                        # MUS_WORLD_CALAMITY

static var _data: Dictionary = {}
static var force_visible: Array = []               # tests: Red dungeon markers to show
static var _shader: Shader

var world: Node2D
var map_size := Vector2(480, 320)
var bg_pos := Vector2.ZERO                         # camera (map pixels), like sWorldMapPtr->bgPos
var mon_pos := Vector2.ZERO                        # leader (map pixels), like monSpritePos
var leader: LeaderSprite
var brightness := 0                                # 0..31, FadeScreen()
var fade_rect: ColorRect
var name_box: PanelContainer
var arrows: Array = []                             # 8 Sprite2D (Friend Areas map)
var _anim_tex: Array = []                          # animated colour frames (Friend Areas map, wmapcani)
var _anim_mat: ShaderMaterial
var _anim_dur := 6
var _anim_t := 0
var _anim_i := 0
var _fade_in := true
var _press_a := false
var _press_b := false
var _touch_dir := 0xFF          # touch: a tapped direction for ChooseLocation (Red's d-pad)
var _touch_locs: Array = []
var _touch_cur := -1
var _back_btn: Button
var _held_dir := 0xFF                              # GetChosenDirection state
var _held_n := 0

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/world_map.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
	return _data

# ============================================================================ entry points
## Red: pick a dungeon at the crossroads -> this. True = the team goes in.
static func trip_red(root: Control, key: String) -> bool:
	var D: Dictionary = data().get("red", {})
	var dest: Array = D.get(key, {}).get("pos", [])
	var base: Array = D.get("d63", {}).get("pos", [192, 183])        # DUNGEON_OUT_ON_RESCUE
	var wm := WorldMap.new()
	root.add_child(wm)
	wm._setup_map(DIR + "red_world_map.png", Vector2(480, 320))
	# sub_8010494: markers of the dungeons that are open or conquered (sub_80A28F0), plus the base (anim 12)
	for k in _red_visible():
		var p: Array = D.get(k, {}).get("pos", [])
		if p.size() == 2:
			wm._add_marker(Vector2(p[0], p[1]), 3)
	wm._add_marker(Vector2(base[0], base[1]), 14)
	var to := Vector2(base[0], base[1]) if dest.size() != 2 else Vector2(dest[0], dest[1])
	var ok := await wm._trip(Vector2(base[0], base[1]), to, key)
	wm.queue_free()
	return ok

## Explorers of Sky dungeon (data/dungeons.json "eos_*"): the leader walks from Treasure Town on the Wonder Map.
static func trip_eos(root: Control, key: String) -> bool:
	var E: Dictionary = data().get("eos", {})
	var eid := int(DB.dungeons.get("dungeons", {}).get(key, {}).get("eos_id", -1))
	var mk: Array = E.get("markers", {}).get(str(eid), [])
	# a few paths (Side Path, Rock Path, Forest Path, The Nightmare) have no marker in EoS's table:
	# use the dungeon before them, whose marker they continue from
	var back := eid - 1
	while mk.size() != 3 and back >= 0 and eid - back <= 3:
		mk = E.get("markers", {}).get(str(back), [])
		back -= 1
	var start: Array = E.get("start", ["s01p01a", 212, 180])
	var map_name: String = mk[0] if mk.size() == 3 else str(start[0])
	var wm := WorldMap.new()
	root.add_child(wm)
	var tex_path := DIR + "eos_%s.png" % map_name
	var tex: Texture2D = load(tex_path) if ResourceLoader.exists(tex_path) else null
	wm._setup_map(tex_path, tex.get_size() if tex else Vector2(504, 336))
	for k in Story.eos_unlocked():
		var m: Array = E.get("markers", {}).get(str(int(DB.dungeons.dungeons[k].get("eos_id", -1))), [])
		if m.size() == 3 and m[0] == map_name:
			wm._add_marker(Vector2(m[1], m[2]), 3)
	var from := wm.map_size / 2.0
	if map_name == str(start[0]):
		from = Vector2(start[1], start[2])
		wm._add_marker(from, 14)
	var to := from if mk.size() != 3 else Vector2(mk[1], mk[2])
	var ok := await wm._trip(from, to, key)
	wm.queue_free()
	return ok

## Red's Friend Areas map. Returns the chosen Friend Area key, or "" for the team base.
static func friend_areas(root: Control, start_key := "") -> String:
	var wm := WorldMap.new()
	root.add_child(wm)
	wm._setup_map(DIR + "red_friend_map.png", Vector2(480, 320))
	wm._setup_anim_colors()
	var k: String = await wm._friend_loop(start_key)
	wm.queue_free()
	return k

## The Friend Area the team is standing in (MapIdToFriendAreaId(GROUND_ENTER)), "" at the base / elsewhere.
static func current_fa_key() -> String:
	var m := GVars.get_val(null, GVars.GROUND_ENTER)
	for v in GData.extra.enums.friend_areas:
		var fa := int(v)
		if fa > 0 and GData.map_of_fa(fa) == m:
			return Story.fa_key(fa)
	return ""

## Remake option: the "Prepare for dungeon" screen after the map (Game.settings.prepare_screen, off = Red's flow).
static func want_prepare() -> bool:
	return bool(Game.settings.get("prepare_screen", false))

# ============================================================================ setup / per-frame
func _ready() -> void:
	theme = UITheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	world = Node2D.new()
	world.scale = Vector2(PX, PX)
	world.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(world)
	fade_rect = ColorRect.new()
	fade_rect.color = Color.BLACK
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.z_index = 5
	add_child(fade_rect)

func _setup_map(path: String, size: Vector2) -> void:
	map_size = size
	var s := Sprite2D.new()
	s.centered = false
	s.texture = load(path) if ResourceLoader.exists(path) else null
	s.z_index = 0
	world.add_child(s)
	leader = LeaderSprite.new()
	leader.z_index = 2                               # OAM priority 3: behind arrows (2) and markers (1)
	leader.set_species(str(Game.team[0].sp) if Game.team.size() > 0 else "0025")
	world.add_child(leader)

func _marker_tex(pose: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = load(DIR + "wmapspr.png")
	at.region = Rect2(pose * CELL, 0, CELL, CELL)
	return at

## wmapspr pose: 3 = dungeon / location (anim 1), 14 = the base (anim 12), 6..13 = arrows (anims 4..11).
func _add_marker(p: Vector2, pose: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _marker_tex(pose)
	s.position = p
	s.z_index = 4
	world.add_child(s)
	return s

## wmapcani: palette entries 0xB0..0xBF cycle (UpdateAnimatedColors), drawn as a mask + palette shader.
func _setup_anim_colors() -> void:
	var meta: Dictionary = data().get("friend_anim", {})
	var mask_p := DIR + "red_friend_map_anim_mask.png"
	var pal_p := DIR + "red_friend_map_anim_pal.png"
	if meta.is_empty() or not ResourceLoader.exists(mask_p) or not ResourceLoader.exists(pal_p):
		return
	var strip: Image = (load(pal_p) as Texture2D).get_image()
	if strip.is_compressed():
		strip.decompress()
	for f in strip.get_width():
		_anim_tex.append(ImageTexture.create_from_image(strip.get_region(Rect2i(f, 0, 1, 16))))
	_anim_dur = maxi(1, int(meta.get("duration", 6)))
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type canvas_item;
uniform sampler2D pal : filter_nearest;
void fragment() {
	vec4 m = texture(TEXTURE, UV);
	if (m.a < 0.5) { discard; }
	float i = floor(m.r * 255.0 / 16.0);
	COLOR = vec4(texture(pal, vec2(0.5, (i + 0.5) / 16.0)).rgb, 1.0);
}"""
	_anim_mat = ShaderMaterial.new()
	_anim_mat.shader = _shader
	_anim_mat.set_shader_parameter("pal", _anim_tex[0])
	var o := Sprite2D.new()
	o.centered = false
	o.texture = load(mask_p)
	o.material = _anim_mat
	o.z_index = 1
	world.add_child(o)

func _view() -> Vector2:
	return get_viewport_rect().size / PX

## UpdateMonSpritePosition: keep the leader inside a margin, clamp to the map.
func _follow() -> void:
	var v := _view()
	var mx := 48.0
	var my := minf(48.0, v.y * 0.3)
	if mon_pos.x - bg_pos.x < mx:
		bg_pos.x = mon_pos.x - mx
	elif mon_pos.x - bg_pos.x > v.x - mx:
		bg_pos.x = mon_pos.x - (v.x - mx)
	if mon_pos.y - bg_pos.y < my:
		bg_pos.y = mon_pos.y - my
	elif mon_pos.y - bg_pos.y > v.y - my:
		bg_pos.y = mon_pos.y - (v.y - my)
	bg_pos.x = clampf(bg_pos.x, 0.0, maxf(0.0, map_size.x - v.x))
	bg_pos.y = clampf(bg_pos.y, 0.0, maxf(0.0, map_size.y - v.y))
	if map_size.x < v.x:
		bg_pos.x = -(v.x - map_size.x) / 2.0
	if map_size.y < v.y:
		bg_pos.y = -(v.y - map_size.y) / 2.0

## One Red frame (WorldMap_RunFrameActions): scroll, sprites, fade, animated colours.
func _frame() -> void:
	world.position = (-bg_pos * PX).round()
	leader.position = mon_pos + Vector2(0, -4)
	if _fade_in and brightness < 31:
		brightness += 1
	fade_rect.color.a = 1.0 - clampf(brightness / 31.0, 0.0, 1.0)

## UpdateAnimatedColors keeps running while menus are open.
func _physics_process(_dt: float) -> void:
	if _anim_mat and not _anim_tex.is_empty():
		_anim_t += 1
		if _anim_t >= _anim_dur:
			_anim_t = 0
			_anim_i = (_anim_i + 1) % _anim_tex.size()
			_anim_mat.set_shader_parameter("pal", _anim_tex[_anim_i])

func _frames(n: int) -> void:
	for i in n:
		_frame()
		await get_tree().physics_frame

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
		_press_a = true
	elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
		_press_b = true
	else:
		return
	get_viewport().set_input_as_handled()

## Touch (no controller): tap an area to walk toward it, tap the area you're on to choose it, Back to leave.
func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed) or _touch_locs.is_empty() or _touch_cur < 0:
		return
	accept_event()
	var mp: Vector2 = e.position / PX + bg_pos
	var here: Vector2 = _touch_locs[_touch_cur].pos
	if mp.distance_to(here) < 14.0:
		_press_a = true
		return
	var want := (mp - here).normalized()
	var best := 0xFF
	var best_dot := 0.45
	for d in 8:
		var n: int = _touch_locs[_touch_cur].by_dir[d]
		if n < 0 or not _touch_locs[n].shown:
			continue
		var dot := want.dot((_touch_locs[n].pos - here).normalized())
		if dot > best_dot:
			best_dot = dot
			best = d
	_touch_dir = best

func _touch_back(on: bool) -> void:
	if _back_btn == null:
		_back_btn = Button.new()
		_back_btn.text = "Back"
		_back_btn.focus_mode = Control.FOCUS_NONE
		_back_btn.add_theme_font_size_override("font_size", UITheme.FONT_SIZE)
		_back_btn.add_theme_stylebox_override("normal", UITheme.box(0.85))
		_back_btn.add_theme_stylebox_override("hover", UITheme.box(0.95))
		_back_btn.add_theme_stylebox_override("pressed", UITheme.box(0.95))
		_back_btn.z_index = 6
		_back_btn.pressed.connect(func(): _press_b = true)
		add_child(_back_btn)
	_back_btn.position = Vector2(get_viewport_rect().size.x - 64 - 4 * UITheme.PX, 4 * UITheme.PX)
	_back_btn.size = Vector2(64, 24)
	_back_btn.visible = on

func _clear_presses() -> void:
	_press_a = false
	_press_b = false

## FadeFromWorldMap_Async: windows off, music fades over 30 frames, 60 frames getting darker.
func _fade_out(fade_music := true) -> void:
	_hide_name()
	if fade_music:
		Audio.fade_out_music(30)
	_fade_in = false
	for i in 60:
		brightness -= 2
		await _frames(1)

static func _play_bgm() -> void:
	Audio.play_music(BGM_CALAMITY if GVars.quest(GVars.QUEST_IN_WORLD_CALAMITY) else BGM_SQUARE)

# ============================================================================ the trip (ShowWorldMap_Async)
func _trip(from: Vector2, to: Vector2, key: String) -> bool:
	mon_pos = from
	var v := _view()
	bg_pos = mon_pos - Vector2(v.x / 2.0, v.y / 2.0)
	leader.facing = 0
	_follow()
	_play_bgm()
	var auto := ListMenu.auto or Dialog.auto
	await _frames(1 if auto else 60)
	await _walk(from, to, auto)
	var nm := str(DB.dungeons.get("dungeons", {}).get(key, {}).get("name", key))
	_show_name(nm, 12, 16)
	await _frames(1 if auto else 60)
	var req := requirements(key)
	var entered := false
	match int(req[0]):
		0:
			entered = true
		1:
			_hide_name()
			await Dialog.say(self, str(req[1]))
			await _frames(10)
		2:
			entered = await _enter_prompt(str(req[1]))
	await _fade_out()
	return entered

## AnimateMonPath_Async: 2 px a frame along the longer axis; A or B skips to the end.
func _walk(a: Vector2, b: Vector2, skip := false) -> void:
	var d := b - a
	var steps := int(maxf(absf(d.x), absf(d.y))) / 2
	# direction as Red computes it: Atan2_4096(pos1 - pos2 in x, pos2 - pos1 in y) - 1024, 512 per direction
	if steps > 0:
		leader.facing = _red_dir(d)
	_clear_presses()
	for i in (0 if skip else steps):
		mon_pos = a + (d * float(i) / float(steps)).floor()
		_follow()
		await _frames(1)
		if _press_a or _press_b:
			break
	mon_pos = b
	_follow()
	await _frames(1)

static func _atan4096(y: float, x: float) -> int:
	return posmod(int(floor(atan2(y, x) / TAU * 4096.0)), 4096)

static func _red_dir(d: Vector2) -> int:
	var r3 := _atan4096(d.y, -d.x) - 1024
	if r3 < 0:
		r3 += 511
	return (r3 >> 9) & 7

## PrintDungeonName / FriendAreasMap_PrintCurrAreaName: a 2-tile window at the top or the bottom.
func _show_name(text: String, x_tiles: int, w_tiles: int) -> void:
	_hide_name()
	var v := get_viewport_rect().size
	var ox := (v.x - 240 * PX) / 2.0
	name_box = PanelContainer.new()
	name_box.z_index = 6
	name_box.custom_minimum_size = Vector2(w_tiles * 8 * PX - 12 * PX, 16 * PX - 6 * PX)
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_box.add_child(l)
	add_child(name_box)
	name_box.position.x = ox + x_tiles * 8 * PX
	# Red: leader in the upper half of the screen -> the window goes to the bottom (y 17), else the top (y 1)
	if (mon_pos.y - bg_pos.y) <= _view().y / 2.0:
		name_box.position.y = v.y - 8 * PX - 16 * PX
	else:
		name_box.position.y = 8 * PX

func _hide_name() -> void:
	if is_instance_valid(name_box):
		name_box.queue_free()
	name_box = null

## PlayerEnterDungeonPrompt_Async: the rules text in a 26-tile window, Yes / No above its right end
## (the cursor starts on No, B does nothing).
func _enter_prompt(text: String) -> bool:
	_hide_name()                                   # ShowWindows(&sWorldMapWindows) replaces the name window
	var lines := text.count("\n")
	var h := (lines * 12 + 11) / 8
	var v := get_viewport_rect().size
	var ox := (v.x - 240 * PX) / 2.0
	var box := PanelContainer.new()
	box.z_index = 6
	box.custom_minimum_size = Vector2(26 * 8 * PX - 12 * PX, h * 8 * PX - 6 * PX)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_OFF
	rt.text = UITheme.red_text(text.strip_edges(false, true))
	box.add_child(rt)
	add_child(box)
	await get_tree().process_frame
	box.position = Vector2(ox + 2 * 8 * PX, v.y - 8 * PX - box.size.y)
	var lm := ListMenu.make("", ["Yes", "No"], false)
	lm.z_index = 7
	add_child(lm)
	lm._set_sel(1)
	lm.position = Vector2(ox + 23 * 8 * PX, box.position.y - 2 * 8 * PX - 2 * UITheme.LINE - 6 * PX)
	var pick := await lm.choose()
	box.queue_free()
	return pick == 0

# ============================================================================ requirements (BufferDungeonRequirementsText)
static func _team_entries() -> Array:
	return Game.team.slice(0, 4)

static func _has_move(mv: String) -> bool:
	for e in _team_entries():
		for m in e.get("moves", []):
			if m is Dictionary and str(m.get("name", "")) == mv:
				return true
	return false

static func _possession(item: String) -> int:
	var n := 0
	for b in Game.bag:
		if str(b.get("id", "")) == item:
			n += 1
	for e in _team_entries():
		if str(e.get("held", "")) == item:
			n += 1
	return n

static func _is_water(sp: String) -> bool:
	return "Water" in DB.species.get(sp, DB.species.get(sp.substr(0, 4), {})).get("types", [])

static func _append(buf: String, t: String) -> String:
	var n := buf.count("\n")             # AppendWithNewLines: pad to a multiple of 3 lines first
	while n % 3 != 0:
		buf += "\n"
		n += 1
	return buf + t

## [0 = go, 1 = can't (dialogue box), 2 = ask (Yes / No), text], following Red's rules for the dungeon.
static func requirements(key: String) -> Array:
	var R: Dictionary = data().get("red", {}).get(key, {})
	var D: Dictionary = DB.dungeons.get("dungeons", {}).get(key, {})
	if R.is_empty():          # EoS dungeons: the same checks from dungeons.json
		R = {"max_party": int(D.get("party", 4)), "max_items": int(D.get("max_items", 0)), "hm_mask": 0,
			"level_reset": bool(D.get("level_reset", false)), "keep_money": true, "no_save": true}
	var team := _team_entries()
	var counter := team.size()
	var held := 0
	for e in team:
		if str(e.get("held", "")) != "":
			held += 1
	var inv := Game.bag.size()
	var require_hm := GVars.quest(GVars.QUEST_CAN_CHANGE_LEADER)
	var buf := ""
	var failed := false
	var max_party := int(R.get("max_party", 4))
	if not require_hm and max_party > 3:
		max_party = 3
	if counter > max_party:
		if max_party == 1:
			buf = _append(buf, "Only one Pokémon may enter this dungeon.\nThe team must be reduced in size.")
		else:
			buf = _append(buf, "There are too many members on your team\nto enter this dungeon. Your team must be\nreduced by one member.")
		failed = true
	var max_items := int(R.get("max_items", 0))
	if max_items != 0 and max_items < inv:
		if failed:
			buf = _append(buf, "Also, only %d items may be brought\ninto this dungeon.\nPlease put away %d item(s)." % [max_items, inv - max_items])
		else:
			buf = _append(buf, "Only %d items may be brought into\nthis dungeon.\nPlease put away %d item(s)." % [max_items, inv - max_items])
		failed = true
	var client := _escort_client(key)
	if client != "":
		var cn := "[color=#7fe0ff]%s[/color]" % str(DB.species.get(client, {}).get("name", client))
		if counter > 3:
			buf = _append(buf, ("Also, your client, %s, could not\njoin the team because there are too many\nmembers already." if failed else "Your client, %s, could not join\nthe team because there are too many\nmembers already.") % cn)
			failed = true
		var body := int(DB.species.get(client, {}).get("size", 1))
		for e in team:
			body += int(DB.species.get(str(e.sp), DB.species.get(str(e.sp).substr(0, 4), {})).get("size", 1))
		if body > 6:
			buf = _append(buf, ("Also, your client, %s, could not\njoin the team because there is no space." if failed else "Your client, %s, could not join\nthe team because there is no space.") % cn)
			failed = true
	var mask := int(R.get("hm_mask", 0))
	if require_hm:
		var moves := ["Fly", "Dive", "Waterfall", "Surf"]
		var items := ["fly", "dive", "waterfall", "surf"]
		for i in 4:
			if (mask >> i) & 1 and not _has_move(moves[i]) and _possession(items[i]) == 0:
				var mv := "[color=#7fe0ff]%s[/color]" % moves[i]
				buf = _append(buf, ("Also, the team must have a Pokémon with\nthe move %s or have the\nHidden Machine %s." if failed else "To enter this dungeon, the team must have\na Pokémon with the move %s\nor have the Hidden Machine %s.") % [mv, mv])
				failed = true
				break
	if mask & 0x10:
		var water := client != "" and _is_water(client)
		for e in team:
			if _is_water(str(e.sp)):
				water = true
		if not water:
			buf = _append(buf, "Also, the team must have a Water-type\nPokémon." if failed else "To enter this dungeon, the team must have\na Water-type Pokémon.")
			failed = true
	if failed:
		return [1, buf]
	var rules: Array = []
	if not bool(R.get("no_save", true)):
		rules.append("{STAR_BULLET} Game will be saved before entering.")
	if bool(R.get("level_reset", false)):
		rules.append("{STAR_BULLET} The team will enter at Level 1. ")
	if max_items == 0 and inv + held != 0:
		rules.append("{STAR_BULLET} All items will be sent to Storage.")
	if not bool(R.get("keep_money", true)) and Game.money != 0:
		rules.append("{STAR_BULLET} All money will be lost on entering.")
	if rules.is_empty():
		return [0, "No problem."]
	return [2, "Is it OK to enter this dungeon with the\nfollowing rule(s)?\n" + "\n".join(rules) + "\n"]

## A taken escort job for this dungeon: its client walks with the team (sub_80990EC / sub_8096A08).
static func _escort_client(key: String) -> String:
	for j in Game.jobs:
		if str(j.get("dungeon", "")) == key and str(j.get("state", "")) == "taken" and str(j.get("kind", "")) == "escort":
			return str(j.get("client", ""))
	return ""

## Dungeons whose marker Red shows: open or conquered rescue dungeons (sub_80A28F0 / rescue_available).
static func _red_visible() -> Array:
	if not force_visible.is_empty():
		return force_visible
	var out: Array = []
	var keys: Array = DB.dungeons.get("dungeons", {}).keys()
	GData.load_all()
	if not Game.story.has("vars"):          # town mode / no story progress: show the cleared and unlocked dungeons
		for k in Game.unlocked + Game.cleared:
			if not k in out:
				out.append(k)
		return out
	for r in 46:
		var sd := GData.rescue_to_script(r)
		if sd < 0 or not Story.rescue_available(r):
			continue
		var did := int(GData.dungeon_info(sd).dungeon)
		if did >= 0 and did < keys.size() and not keys[did] in out:
			out.append(keys[did])
	return out

# ============================================================================ Friend Areas map
class FLoc:
	var name := ""
	var pos := Vector2.ZERO
	var keys: Array = []
	var adj: Array = []
	var shown := false
	var by_dir: Array = [-1, -1, -1, -1, -1, -1, -1, -1]

static var _fa: Dictionary = {}
static func _fa_data() -> Dictionary:
	if _fa.is_empty():
		var f := FileAccess.open("res://data/friend_areas.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_fa = d
	return _fa

## IsFriendAreaShownOnMap: the base always, otherwise an owned Friend Area.
static func _fa_shown(k: String) -> bool:
	return k == "" or k in Game.friend_areas

func _friend_loop(start_key: String) -> String:
	var locs: Array = []
	var base_i := 0
	var cur := -1
	for L in data().get("friend_locations", []):
		var f := FLoc.new()
		f.name = str(L.name)
		if f.name == "$t":
			f.name = Game.team_name
		f.pos = Vector2(L.pos[0], L.pos[1])
		f.keys = L.get("keys", [])
		f.adj = L.adj
		for k in f.keys:
			if _fa_shown(str(k)):
				f.shown = true
				if str(k) == "":
					base_i = locs.size()
				if str(k) == start_key and start_key != "":
					cur = locs.size()
		locs.append(f)
	if cur < 0:
		cur = base_i
	for i in locs.size():
		if locs[i].shown:
			_add_marker(locs[i].pos, 14 if i == base_i else 3)
	_link_locations(locs)
	for d in 8:
		var a := Sprite2D.new()
		a.texture = _marker_tex(6 + d)
		a.z_index = 3
		a.visible = false
		world.add_child(a)
		arrows.append(a)
	mon_pos = locs[cur].pos
	var v := _view()
	bg_pos = mon_pos - Vector2(v.x / 2.0, v.y / 2.0)
	_follow()
	_play_bgm()
	var result := ""
	while true:
		# ChooseLocation_Async
		_show_arrows(locs, cur)
		_show_name(locs[cur].name, 7, 21)
		_clear_presses()
		_touch_locs = locs
		_touch_cur = cur
		_touch_back(true)
		var ret := 0
		var nl := -1
		var nd := 0
		while ret == 0:
			await _frames(1)
			_update_arrow_vis()
			var d := _chosen_dir()
			if d != 0xFF and locs[cur].by_dir[d] >= 0 and locs[locs[cur].by_dir[d]].shown:
				ret = 1
				nl = locs[cur].by_dir[d]
				nd = d
			if _press_a:
				Audio.sfx("confirm")
				ret = 2
			elif _press_b:
				Audio.sfx("cancel")
				ret = 3
			if ListMenu.auto and ret == 0:
				ret = 3
		_touch_back(false)
		_touch_locs = []
		if ret == 1:
			await _move_to(locs, cur, nl, nd, 50)
			cur = nl
		elif ret == 2:
			var pick = await _choose_area(locs[cur])
			if pick != null:
				result = str(pick)
				break
		else:
			if cur == base_i:
				result = ""
				break
			await _move_to(locs, cur, base_i, 0, 10)
			cur = base_i
	_hide_arrows()
	await _fade_out(not GVars.quest(GVars.QUEST_IN_WORLD_CALAMITY))
	return result

## InitMapLocations: listed neighbours first, then the nearest shown location in each 45-degree sector.
func _link_locations(locs: Array) -> void:
	for i in locs.size():
		var L: FLoc = locs[i]
		if not L.shown:
			continue
		for j in 8:
			var a := int(L.adj[j])
			L.by_dir[j] = a if a >= 0 and locs[a].shown else -1
		for j in 8:
			if L.by_dir[j] >= 0:
				continue
			var found := -1
			var best := 999999
			for k in locs.size():
				if k == i or not locs[k].shown:
					continue
				var dv: Vector2 = locs[k].pos - L.pos
				var ang := _atan4096(dv.y, dv.x)
				var px := int(dv.x / 4.0)
				var py := int(dv.y / 4.0)
				if px == 0: px = 1
				if py == 0: py = 1
				var ok := false
				if j == 2:
					ok = ang > SECTORS[j][0] or ang < SECTORS[j][1]
				else:
					ok = ang >= SECTORS[j][0] and ang < SECTORS[j][1]
				if ok and px * px + py * py < best:
					best = px * px + py * py
					found = k
			if found >= 0:
				L.by_dir[j] = found

func _show_arrows(locs: Array, cur: int) -> void:
	for d in 8:
		var n: int = locs[cur].by_dir[d]
		arrows[d].set_meta("on", n >= 0 and locs[n].shown)
		arrows[d].position = locs[cur].pos + ARROW_OFF[d]
	_update_arrow_vis()

func _update_arrow_vis() -> void:
	var diag := Input.is_action_pressed("act_diag")
	for d in arrows.size():
		arrows[d].visible = bool(arrows[d].get_meta("on", false)) and not (diag and d % 2 == 0)

func _hide_arrows() -> void:
	for a in arrows:
		a.set_meta("on", false)
		a.visible = false

## GetChosenDirection: the d-pad (R = diagonals only) held for 3 frames.
func _chosen_dir() -> int:
	if _touch_dir != 0xFF:
		var td := _touch_dir
		_touch_dir = 0xFF
		return td
	var all := [0xFF, 0, 2, 1, 4, 0xFF, 3, 0xFF, 6, 7, 0xFF, 0xFF, 5, 0xFF, 0xFF, 0xFF]
	var dg := [0xFF, 0xFF, 0xFF, 1, 0xFF, 0xFF, 3, 0xFF, 0xFF, 7, 0xFF, 0xFF, 5, 0xFF, 0xFF, 0xFF]
	var id := 0
	if Input.is_action_pressed("ui_down"): id |= 1
	if Input.is_action_pressed("ui_right"): id |= 2
	if Input.is_action_pressed("ui_up"): id |= 4
	if Input.is_action_pressed("ui_left"): id |= 8
	var t: Array = dg if Input.is_action_pressed("act_diag") else all
	var d: int = t[id]
	if d == _held_dir:
		_held_n += 1
		if _held_n >= 3:
			return d
	else:
		_held_dir = d
		_held_n = 0
	return 0xFF

## MoveToNewLocation_Async: straight line over n frames, facing the d-pad direction.
func _move_to(locs: Array, from_i: int, to_i: int, dir: int, n: int) -> void:
	leader.facing = dir & 7
	_hide_name()
	_hide_arrows()
	Audio.sfx("cursor")
	var a: Vector2 = locs[from_i].pos
	var b: Vector2 = locs[to_i].pos
	for i in n:
		mon_pos = a + ((b - a) * float(i) / float(n)).floor()
		_follow()
		await _frames(1)
	mon_pos = b
	_follow()
	await _frames(1)
	leader.facing = 0

## ChooseAreaInLocation_Async: "Where would you like to go?" with the shown areas and their (residents/capacity).
func _choose_area(L: FLoc):
	_hide_name()
	var keys: Array = []
	var opts: Array = []
	for k in L.keys:
		if not _fa_shown(str(k)):
			continue
		keys.append(str(k))
		if str(k) == "":
			opts.append("%s Team Base" % Game.team_name)
		else:
			var n := 0
			for f in Game.friends:
				if str(f.get("area", "")) == str(k):
					n += 1
			var A: Dictionary = _fa_data().get("areas", {}).get(str(k), {})
			opts.append("%s(%d/%d)" % [str(A.get("name", k)), n, int(A.get("cap", 0))])
	var lm := ListMenu.make("Where would you like to go?", opts)
	lm.z_index = 7
	add_child(lm)
	var v := get_viewport_rect().size
	lm.position = Vector2((v.x - 240 * PX) / 2.0 + 7 * 8 * PX, 2 * 8 * PX)
	var pick := await lm.choose()
	_clear_presses()
	return keys[pick] if pick >= 0 else null

# ============================================================================ leader sprite (SpriteCollab walk)
class LeaderSprite extends Node2D:
	var man: Dictionary = {}
	var facing := 0
	var t0 := 0.0

	func set_species(sp: String) -> void:
		man = DB.sprites.get(sp, DB.sprites.get(sp.substr(0, 4), {}))
		t0 = Time.get_ticks_msec() / 1000.0

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var anims: Dictionary = man.get("anims", {})
		var A: Dictionary = anims.get("Walk", anims.get("Idle", {}))
		if A.is_empty():
			return
		var tex: Texture2D = DB.tex("res://assets/sp/" + str(A.get("s", man.get("sheet", ""))))
		if tex == null:
			return
		var dur: Array = A.dur
		var total := 0
		for d in dur:
			total += int(d)
		var t := posmod(int((Time.get_ticks_msec() / 1000.0 - t0) * 60.0), maxi(total, 1))
		var f := 0
		var acc := 0
		while f < dur.size():
			acc += int(dur[f])
			if t < acc:
				break
			f += 1
		f = mini(f, dur.size() - 1)
		var row := mini(facing, int(A.rows) - 1)
		var w := int(A.w)
		var h := int(A.h)
		var src := Rect2(int(A.get("x", 0)) + f * w, int(A.y) + row * h, w, h)
		if A.has("cols"):
			var cols := maxi(1, int(A.cols))
			src.position = Vector2(int(A.get("x", 0)) + (f % cols) * w, int(A.y) + (f / cols) * int(A.rows) * h + row * h)
		draw_texture_rect_region(tex, Rect2(Vector2(-w / 2.0, -h / 2.0 - 2.0).round(), Vector2(w, h)), src)
