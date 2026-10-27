class_name Town
extends Node2D
## Walkable town maps (Pokémon Square, Pelipper Post Office, Makuhita Dojo, Whiscash Pond, the team base),
## ported from the old HTML remake's walkable town (TOWN_MAPS / townUpdate / townPath / renderTownWalk).
##
## Coordinates are map pixels of the original GBA-sized picture; Pokémon sprites are drawn 1:1 in those
## pixels (as the old version did). The picture itself is the 3x HD version drawn at 1/3 with linear filtering.
## Walking is free 8-way pixel movement (84 px/s, Shift/B runs at 2x) on the traced walk grid, with
## wall sliding and corner assist; tapping the map walks there (A* on 6 px cells), tapping an NPC walks
## up to it and talks. Partners follow along the leader's trail, 30 px apart.
##
##   var t := Town.new(); add_child(t); t.start("square", ui_root, "base")
##   t.interact(id)  - "kecleon_shop", "kecleon_wares", "persian_bank", "kangaskhan_storage", "gulpin_shop",
##                     "wigglytuff", "makuhita_dojo", "pelipper_board", "whiscash", "bed", "mailbox", "nohome"
##   t.exit(to)      - "square", "base", "post_office", "dojo", "whiscash" (town maps; pass the current
##                     map_key as arrive_at when starting the next one) or "world_map", "friend_areas", "dojo_maze"
##   t.menu()        - Menu button / act_menu

signal interact(id: String)
signal exit(to: String)
signal menu()

const PC := 6                          # path-finding cell (map px)
const FOLLOW_GAP := 30.0
const SPEED := 84.0
const FOOT := [Vector2(-4, -2), Vector2(4, -2), Vector2(-4, 2), Vector2(4, 2)]
const TOWN_MAPS := ["square", "base", "post_office", "dojo", "whiscash"]

static var DATA: Dictionary = {}

var map_key := ""
var M: Dictionary = {}                 # map entry (npcs, spots, exits, arrive, blocks, music)
var I: Dictionary = {}                 # picture entry (w, h, tex, k, grid, anim, xblocks)
var ui_root: Control
var paused := false
var busy := false                      # exit fade / talking
var pos := Vector2.ZERO
var facing := 0
var moving := false
var running := false
var trail: Array = []                  # [Vector3(x, y, facing)]
var path: Array = []                   # waypoints (Vector2)
var after := ""                        # interact id to trigger when the tap-walk arrives
var _stuck := 0
var _prog := {}
var _cool := 0.0

var _bits: PackedByteArray
var _gC := 4
var _gW := 0
var _gH := 0
var _nav: PackedByteArray
var _nW := 0
var _nH := 0

var cam: Camera2D
var bg: Sprite2D
var anim_layer: AnimLayer
var actors: Node2D
var overlay: Node2D
var leader: Actor
var followers: Array = []
var npc_actors: Array = []
var _ui: Control
var hud: Hud
var menu_btn: Button
var info: Label
var fade: ColorRect

# ------------------------------------------------------------------ data
static func data() -> Dictionary:
	if DATA.is_empty():
		var f := FileAccess.open("res://data/town.json", FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				DATA = v
	return DATA

static func base_shape(sp: String) -> String:
	var d := data()
	var s: String = d.get("base_shape", {}).get(sp, sp)
	if not d.get("bases", {}).has(s):
		s = sp.substr(0, 4)
		s = d.get("base_shape", {}).get(s, s)
	return s if d.get("bases", {}).has(s) else "0025"

# ------------------------------------------------------------------ build
func start(key: String, root: Control, arrive_at := "") -> void:
	ui_root = root
	var d := data()
	if not d.get("maps", {}).has(key):
		push_warning("Town: unknown map " + key)
		key = "square"
	map_key = key
	M = d.maps[key]
	if key == "base":
		var sp: String = Game.team[0].sp if Game.team.size() > 0 else "0025"
		I = d.bases[base_shape(sp)]
	else:
		I = M
	_load_grid()
	# background picture (HD at 1/k, linear) + animated tiles + base flag
	bg = Sprite2D.new()
	bg.centered = false
	bg.texture = DB.tex("res://assets/town/" + str(I.tex))
	var k := float(I.get("k", 1))
	bg.scale = Vector2.ONE / k
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if k > 1.0 else CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(bg)
	if I.has("anim"):
		anim_layer = AnimLayer.new()
		anim_layer.setup(I.anim)
		add_child(anim_layer)
	if key == "base" and d.has("flag"):
		var fl := FlagLayer.new()
		fl.cfg = d.flag
		add_child(fl)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	actors.z_index = 2
	add_child(actors)
	overlay = Node2D.new()
	overlay.z_index = 10
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	# NPCs at their stalls (idle, facing down like the old version)
	var i := 0
	for n in M.npcs:
		var a := Actor.new()
		a.setup(DB.make_mon(str(n.sp), 5, "npc"))
		a.position = Vector2(n.x, n.y)
		a.set_facing(int(n.get("f", 0)))
		actors.add_child(a)
		a.sprite.t0 -= i * 0.25
		npc_actors.append(a)
		i += 1
	# arrival point
	var sp: Array = M.spawn
	if arrive_at != "" and M.arrive.has(arrive_at):
		sp = M.arrive[arrive_at]
	elif arrive_at != "":
		for ex in M.exits:
			if ex.to == arrive_at and ex.has("back"):
				sp = ex.back
				break
	pos = Vector2(sp[0], sp[1])
	facing = int(sp[2])
	_reset_trail()
	# team
	for t in mini(4, Game.team.size()):
		var a := Actor.new()
		a.setup(Game.mon_from_entry(Game.team[t]))
		actors.add_child(a)
		if t == 0:
			leader = a
		else:
			followers.append(a)
	_place_team()
	# camera
	cam = Camera2D.new()
	cam.position_smoothing_enabled = false
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(I.w)
	cam.limit_bottom = int(I.h)
	add_child(cam)
	cam.make_current()
	_apply_zoom(float(Game.settings.get("zoom", 1.25)))
	cam.position = pos
	cam.reset_smoothing()
	_build_ui()
	get_viewport().size_changed.connect(_on_resize)
	Audio.play_music(str(M.get("music", "007")))
	_fade_to(0.0, 0.3)

func _build_ui() -> void:
	_ui = Control.new()
	_ui.name = "TownUI"
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(_ui)
	ui_root.move_child(_ui, 0)            # under dialogs / menus opened later
	_ui.tree_exiting.connect(_on_ui_gone)
	hud = Hud.new()
	_ui.add_child(hud)
	hud.top_draw.visible = false
	hud.msg_panel.visible = false
	hud.set_touch_visible(hud.touch_ui)
	for k2 in hud._btns:
		if k2 != "attack":
			hud._btns[k2].visible = false
	hud.button.connect(func(b: String): if b == "attack": try_interact())
	info = Label.new()
	info.position = Vector2(4, 2)
	info.add_theme_font_size_override("font_size", UITheme.FONT_SIZE)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(info)
	menu_btn = Button.new()
	menu_btn.text = "Menu"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.custom_minimum_size = Vector2(56, 24)
	menu_btn.size = menu_btn.custom_minimum_size
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = UITheme.box(0.82 if st == "normal" else 0.95).duplicate()
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
		sb.content_margin_left = 2
		sb.content_margin_right = 2
		menu_btn.add_theme_stylebox_override(st, sb)
	menu_btn.modulate = Color(1, 1, 1, 0.85)
	menu_btn.pressed.connect(func(): if _can_act(): menu.emit())
	_ui.add_child(menu_btn)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(fade)
	_on_resize()
	_update_info()

func _on_resize() -> void:
	if not is_instance_valid(menu_btn):
		return
	var vs := get_viewport_rect().size
	menu_btn.position = Vector2(vs.x - menu_btn.size.x - 4, 4)
	_apply_zoom(cam.zoom.x)

func _update_info() -> void:
	if info:
		info.text = "Team %s   %d Poké" % [Game.team_name, Game.money]

func _on_ui_gone() -> void:
	if not is_queued_for_deletion():
		queue_free()

func _exit_tree() -> void:
	if is_instance_valid(_ui) and not _ui.is_queued_for_deletion():
		_ui.tree_exiting.disconnect(_on_ui_gone)
		_ui.queue_free()

## Zoom (Game.settings.zoom), never so far out that the map doesn't fill the screen.
func _apply_zoom(z: float) -> void:
	var vs := get_viewport_rect().size
	var cover := maxf(vs.x / float(I.w), vs.y / float(I.h))
	cam.zoom = Vector2.ONE * clampf(maxf(z / UITheme.ui_scale(), cover), 0.75, 3.0)

func _fade_to(a: float, t: float) -> void:
	if not is_instance_valid(fade):
		return
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, t)
	await tw.finished

# ------------------------------------------------------------------ public
func set_paused(on: bool) -> void:
	paused = on
	path.clear()
	after = ""
	_set_moving(false)
	_cool = 0.2

func is_idle() -> bool:
	return path.is_empty() and not moving and not busy

## Walk (path-find) to a map point; `then` = interact id to trigger on arrival if in reach.
func walk_to(p: Vector2, then := "") -> bool:
	if not walkable(p.x, p.y):
		# tapping a doorway at the map edge: aim for the nearest point of the exit we can stand on
		for ex in M.exits:
			var r: Array = ex.r
			if _in_rect([r[0] - 8, r[1] - 8, r[2] + 8, r[3] + 8], p):
				var best := p
				var bd := INF
				for y in range(int(r[1]), int(r[3]) + 1):
					for x in range(int(r[0]), int(r[2]) + 1):
						var q := Vector2(x, y)
						if q.distance_squared_to(p) < bd and walkable(x, y):
							bd = q.distance_squared_to(p)
							best = q
				p = best
				break
	path = _plan(p.x, p.y)
	after = then if not path.is_empty() else ""
	_prog = {}
	return not path.is_empty()

## Walk up to an NPC / spot by interact id and talk to it.
func walk_to_target(id: String) -> bool:
	for o in M.npcs + M.spots:
		if o.id == id:
			var r: Array = o.reach
			if _in_rect(r, pos):
				_do(id)
				return true
			return walk_to(Vector2(clampf(pos.x, r[0] + 5, r[2] - 5), (r[1] + r[3]) / 2.0), id)
	return false

func try_interact() -> void:
	if not _can_act():
		return
	var h := here()
	if h.is_empty():
		return
	var v: Vector2 = h[0].p - pos
	if v.length() > 1:
		var fi := DB.dir_index(Vector2i(int(signf(v.x)) if absf(v.x) > absf(v.y) * 0.5 else 0, int(signf(v.y)) if absf(v.y) > absf(v.x) * 0.5 else 0))
		if fi >= 0:
			facing = fi
			leader.set_facing(fi)
	_do(h[0].id)

## Interactables whose reach box the leader stands in, nearest first: [{id, p, d}]
func here() -> Array:
	var out: Array = []
	for n in M.npcs:
		if _in_rect(n.reach, pos):
			out.append({"id": n.id, "p": Vector2(n.x, n.y), "d": pos.distance_to(Vector2(n.x, n.y))})
	for s in M.spots:
		if _in_rect(s.reach, pos):
			out.append({"id": s.id, "p": Vector2((s.reach[0] + s.reach[2]) / 2.0, s.reach[1]), "d": 0.0})
	out.sort_custom(func(a, b): return a.d < b.d)
	return out

func _do(id: String) -> void:
	path.clear()
	after = ""
	_set_moving(false)
	_cool = 0.25
	interact.emit(id)
	_update_info()

func _can_act() -> bool:
	return not paused and not busy and _cool <= 0.0 and not _ui_busy() and is_inside_tree()

## A dialog box or menu is open over the town.
func _ui_busy() -> bool:
	if ui_root == null:
		return false
	for c in ui_root.get_children():
		if c is ListMenu and c.visible:
			return true
		if c is Dialog and c.panel and c.panel.visible:
			return true
	return false

# ------------------------------------------------------------------ walk grid
func _load_grid() -> void:
	var g: Dictionary = I.grid
	_gC = int(g.C)
	_gW = int(g.W)
	_gH = int(g.H)
	_bits = Marshalls.base64_to_raw(g.b64)
	_nav = PackedByteArray()

func _open(x: float, y: float) -> bool:
	var gx := int(floor(x / _gC))
	var gy := int(floor(y / _gC))
	if gx < 0 or gy < 0 or gx >= _gW or gy >= _gH:
		return false
	var i := gy * _gW + gx
	return (_bits[i >> 3] >> (i & 7)) & 1 == 1

func walkable(x: float, y: float) -> bool:
	for o in FOOT:
		if not _open(x + o.x, y + o.y):
			return false
	for n in M.npcs:
		if Vector2(n.x, n.y).distance_to(Vector2(x, y)) < 12:
			return false
	for b in M.blocks:
		if Vector2(b[0], b[1]).distance_to(Vector2(x, y)) < b[2] + 5:
			return false
	for b in I.get("xblocks", []):
		if Vector2(b[0], b[1]).distance_to(Vector2(x, y)) < b[2] + 5:
			return false
	return true

static func _in_rect(r: Array, p: Vector2) -> bool:
	return p.x >= r[0] and p.x <= r[2] and p.y >= r[1] and p.y <= r[3]

# ------------------------------------------------------------------ update
func _process(dt: float) -> void:
	if _cool > 0:
		_cool -= dt
	if leader == null:
		return
	if paused or busy or _ui_busy():
		_set_moving(false)
	else:
		_step(dt)
	_place_team()
	cam.position = pos
	overlay.queue_redraw()

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
	return DB.dir_index(Vector2i(x, y))

func _step(dt: float) -> void:
	var v := Vector2.ZERO
	var d := _input_dir()
	if d >= 0:
		path.clear()
		after = ""
		v = Vector2(DB.DIRS[d]).normalized()
	elif not path.is_empty():
		var wp: Vector2 = path[0]
		var e := wp - pos
		if e.length() < 1.0:
			path.pop_front()
			if path.is_empty():
				_set_moving(false)
				_arrive_after()
			return
		v = e.normalized()
	if v == Vector2.ZERO:
		_set_moving(false)
		return
	running = (Input.is_action_pressed("act_run") or (hud != null and hud.pad_run)) and d >= 0
	var sp := SPEED * dt * (2.0 if running else 1.0)
	var s := v * sp
	if not path.is_empty():
		var wp: Vector2 = path[0]
		if sp > pos.distance_to(wp):
			s = wp - pos
	var fi := DB.dir_index(Vector2i(int(signf(v.x)) if absf(v.x) > 0.38 else 0, int(signf(v.y)) if absf(v.y) > 0.38 else 0))
	if fi >= 0:
		facing = fi
	var moved := true
	if walkable(pos.x + s.x, pos.y + s.y):
		pos += s
	elif s.x != 0 and walkable(pos.x + s.x, pos.y):
		pos.x += s.x
	elif s.y != 0 and walkable(pos.x, pos.y + s.y):
		pos.y += s.y
	else:
		# corner assist: if a few pixels to the side would let us pass, nudge that way
		moved = false
		var ln := maxf(s.length(), 0.0001)
		var perp := Vector2(-s.y, s.x) / ln
		for k in range(1, 7):
			for sg in [1, -1]:
				var o: Vector2 = perp * k * sg
				if walkable(pos.x + o.x, pos.y + o.y) and walkable(pos.x + o.x + s.x, pos.y + o.y + s.y):
					pos += perp * sg * minf(ln, 1.5)
					moved = true
					break
			if moved:
				break
	_set_moving(moved)
	if not moved and not path.is_empty():
		_stuck += 1
		if _stuck > 6:
			_stuck = 0
			var g: Vector2 = path[path.size() - 1]
			path = _plan(g.x, g.y)
			if path.is_empty():
				after = ""
	# progress watchdog: if a tap-walk makes no headway for a while, re-plan, then give up
	if not path.is_empty():
		var now := Time.get_ticks_msec()
		if _prog.is_empty() or pos.distance_to(_prog.p) > 4:
			_prog = {"p": pos, "t": now, "tries": _prog.get("tries", 0)}
		elif now - int(_prog.t) > 600:
			var g: Vector2 = path[path.size() - 1]
			if int(_prog.tries) >= 2 or g.distance_to(pos) < 16:
				path.clear()
				_prog = {}
				_set_moving(false)
				_arrive_after()
				return
			path = _plan(g.x, g.y)
			_prog = {"p": pos, "t": now, "tries": int(_prog.tries) + 1}
			if path.is_empty():
				after = ""
	else:
		_prog = {}
	if moved:
		_stuck = 0
		trail.append(Vector3(pos.x, pos.y, facing))
		if trail.size() > 400:
			trail.pop_front()
		for ex in M.exits:
			if _in_rect(ex.r, pos):
				_take_exit(ex)
				break

func _arrive_after() -> void:
	if after == "":
		return
	var a := after
	after = ""
	for h in here():
		if h.id == a:
			try_interact()
			return

func _take_exit(ex: Dictionary) -> void:
	if busy:
		return
	busy = true
	path.clear()
	after = ""
	_set_moving(false)
	if not TOWN_MAPS.has(ex.to):
		Audio.sfx("stairs")
	await _fade_to(1.0, 0.3)
	if not is_inside_tree():
		return
	if ex.has("back"):          # where we stand if the map doesn't change (and the way back in later)
		pos = Vector2(ex.back[0], ex.back[1])
		facing = int(ex.back[2])
		_reset_trail()
		_place_team()
		cam.position = pos
		cam.reset_smoothing()
	busy = false
	_cool = 0.3
	exit.emit(ex.to)
	if is_inside_tree() and not is_queued_for_deletion():
		_fade_to(0.0, 0.3)

func _set_moving(on: bool) -> void:
	if on == moving:
		return
	moving = on

func _place_team() -> void:
	if leader == null:
		return
	leader.position = pos.round()
	leader.set_facing(facing)
	leader.set_walking(moving)
	for k in followers.size():
		var p := _trail_at(FOLLOW_GAP * (k + 1))
		var a: Actor = followers[k]
		a.position = Vector2(p.x, p.y).round()
		a.set_facing(int(p.z))
		a.set_walking(moving)

## Partners line up behind the leader (as if they had just walked in), but never inside walls / off the map.
func _reset_trail() -> void:
	var dv := Vector2(DB.DIRS[facing])
	trail.clear()
	var last := pos
	var pts: Array = []
	for j in range(0, 161):
		var q := pos - dv * j * 1.25
		if j == 0 or (walkable(q.x, q.y) and last.distance_to(q) < 2.0):
			last = q
		pts.append(Vector3(last.x, last.y, facing))
	pts.reverse()
	trail = pts

func _trail_at(dist: float) -> Vector3:
	var d := 0.0
	for i in range(trail.size() - 1, 0, -1):
		var a: Vector3 = trail[i]
		var b: Vector3 = trail[i - 1]
		var s := Vector2(a.x - b.x, a.y - b.y).length()
		if d + s >= dist:
			var t := (dist - d) / s if s > 0 else 0.0
			return Vector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, b.z)
		d += s
	return trail[0]

# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if leader == null:
		return
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var z := cam.zoom.x + (0.1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else -0.1)
		_apply_zoom(z)
		Game.settings.zoom = cam.zoom.x
		return
	if not _can_act():
		return
	if e.is_action_pressed("act_attack"):
		try_interact()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("act_menu"):
		menu.emit()
		get_viewport().set_input_as_handled()
	elif e is InputEventScreenTouch and e.pressed:
		if get_viewport().gui_get_hovered_control() != null:
			return     # the touch landed on a button (Menu, A)
		_tap(make_canvas_position_local(e.position))
		get_viewport().set_input_as_handled()

func _tap(m: Vector2) -> void:
	var hit := {}
	for n in M.npcs:
		if Vector2(n.x, n.y - 8).distance_to(m) < 18:
			hit = n
			break
	if hit.is_empty():
		for s in M.spots:
			var r: Array = s.reach
			if _in_rect([r[0] - 6, r[1] - 26, r[2] + 6, r[3]], m):
				hit = s
				break
	if not hit.is_empty():
		walk_to_target(hit.id)
		return
	walk_to(m)

# ------------------------------------------------------------------ path finding (port of townPath)
func _nav_grid() -> void:
	if not _nav.is_empty():
		return
	_nW = int(ceil(float(I.w) / PC))
	_nH = int(ceil(float(I.h) / PC))
	_nav.resize(_nW * _nH)
	for y in _nH:
		for x in _nW:
			_nav[y * _nW + x] = 1 if walkable(x * PC + PC / 2.0, y * PC + PC / 2.0) else 0

func _los(a: Vector2, b: Vector2) -> bool:
	var n := int(ceil(a.distance_to(b) / 2.0))
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		if not walkable(p.x, p.y):
			return false
	return true

func _plan(tx: float, ty: float) -> Array:
	_nav_grid()
	var W := _nW
	var H := _nH
	var gx := clampi(int(tx / PC), 0, W - 1)
	var gy := clampi(int(ty / PC), 0, H - 1)
	var ok_t := walkable(tx, ty)
	if _nav[gy * W + gx] == 0 or not ok_t:
		var best := Vector2i(-1, -1)
		var bd := 1e9
		for r in 13:
			for yy in range(gy - r, gy + r + 1):
				for xx in range(gx - r, gx + r + 1):
					if xx < 0 or yy < 0 or xx >= W or yy >= H or _nav[yy * W + xx] == 0:
						continue
					var dd := float((xx - gx) * (xx - gx) + (yy - gy) * (yy - gy))
					if dd < bd:
						bd = dd
						best = Vector2i(xx, yy)
			if best.x >= 0:
				break
		if best.x < 0:
			return []
		gx = best.x
		gy = best.y
		if not ok_t:     # (a walkable point in a closed nav cell, e.g. an exit at the map edge, stays the goal)
			tx = gx * PC + PC / 2.0
			ty = gy * PC + PC / 2.0
	var target := Vector2(tx, ty)
	if _los(pos, target):
		return [target]
	var sx := clampi(int(pos.x / PC), 0, W - 1)
	var sy := clampi(int(pos.y / PC), 0, H - 1)
	var start := sy * W + sx
	var goal := gy * W + gx
	var cost := PackedFloat32Array()
	cost.resize(W * H)
	cost.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(W * H)
	prev.fill(-1)
	var heap: Array = []   # [f, cell]
	cost[start] = 0.0
	prev[start] = start
	_hpush(heap, _hest(start, W, gx, gy), start)
	while not heap.is_empty():
		var c: int = _hpop(heap)
		if c == goal:
			break
		var cx := c % W
		var cy := c / W
		for dd in DB.DIRS:
			var nx: int = cx + dd.x
			var ny: int = cy + dd.y
			if nx < 0 or ny < 0 or nx >= W or ny >= H:
				continue
			var ni := ny * W + nx
			if _nav[ni] == 0:
				continue
			if dd.x != 0 and dd.y != 0 and (_nav[cy * W + nx] == 0 or _nav[ny * W + cx] == 0):
				continue
			var nc := cost[c] + (1.4142 if dd.x != 0 and dd.y != 0 else 1.0)
			if nc < cost[ni]:
				cost[ni] = nc
				prev[ni] = c
				_hpush(heap, nc + _hest(ni, W, gx, gy), ni)
	if prev[goal] == -1:
		return []
	var pts: Array = []
	var c2 := goal
	while c2 != start:
		pts.append(Vector2((c2 % W) * PC + PC / 2.0, (c2 / W) * PC + PC / 2.0))
		c2 = prev[c2]
	pts.reverse()
	if pts.is_empty():
		pts.append(target)
	else:
		pts[pts.size() - 1] = target
	# string-pull: skip waypoints we can see past
	var out: Array = []
	var a := pos
	var i := 0
	while i < pts.size():
		var j := pts.size() - 1
		while j > i and not _los(a, pts[j]):
			j -= 1
		out.append(pts[j])
		a = pts[j]
		i = j + 1
	return out

static func _hest(c: int, W: int, gx: int, gy: int) -> float:
	var dx := absi(c % W - gx)
	var dy := absi(c / W - gy)
	return maxi(dx, dy) + 0.4142 * mini(dx, dy)

static func _hpush(h: Array, f: float, c: int) -> void:
	h.append([f, c])
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if h[p][0] <= h[i][0]:
			break
		var t = h[p]; h[p] = h[i]; h[i] = t
		i = p

static func _hpop(h: Array) -> int:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < h.size() and h[l][0] < h[m][0]: m = l
			if r < h.size() and h[r][0] < h[m][0]: m = r
			if m == i: break
			var t = h[m]; h[m] = h[i]; h[i] = t
			i = m
	return top[1]

# ------------------------------------------------------------------ overlay (talk bubble, tap target)
func _draw_overlay() -> void:
	var now := Time.get_ticks_msec()
	if not path.is_empty():
		var g: Vector2 = path[path.size() - 1]
		var r := 3.0 + sin(now / 150.0)
		overlay.draw_rect(Rect2(g.x - r - 1, g.y - r - 1, 2 * r + 2, 2 * r + 2), Color.BLACK)
		overlay.draw_rect(Rect2(g.x - r, g.y - r, 2 * r, 2 * r), Color("ffd54a"))
	if paused or busy or _ui_busy():
		return
	var h := here()
	if h.is_empty():
		return
	var p: Vector2 = h[0].p
	var bx := roundf(p.x)
	var by := roundf(p.y - 34 + sin(now / 180.0) * 2)
	overlay.draw_rect(Rect2(bx - 5, by - 5, 10, 10), Color.BLACK)
	overlay.draw_rect(Rect2(bx - 4, by - 4, 8, 8), Color("ffd54a"))
	overlay.draw_rect(Rect2(bx - 1, by - 3, 2, 4), Color.BLACK)
	overlay.draw_rect(Rect2(bx - 1, by + 2, 2, 1), Color.BLACK)


# ================================================================== helpers
## One Pokémon walking around town: a soft round shadow + its MonSprite (pixel art, 1:1 map pixels).
class Actor extends Node2D:
	var mon: Mon
	var sprite: MonSprite
	var _walk := false

	func setup(m: Mon) -> void:
		mon = m
		sprite = MonSprite.new()
		sprite.setup(m)
		sprite._mark_tex = null           # town: soft shadow instead of the dungeon marker
		sprite.z_index = 0
		sprite.position = Vector2(0, -6)  # old version: sprite centred 8 px above the feet
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)

	func set_facing(f: int) -> void:
		mon.facing = f

	func set_walking(on: bool) -> void:
		if on != _walk:
			_walk = on
			sprite.play("Walk" if on else "Idle")

	func _draw() -> void:
		draw_set_transform(Vector2(0, -1), 0.0, Vector2(1.0, 3.0 / 7.0))
		draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.3))


## The original's tile animation (water, flowers, flames): 8x8 tiles from the anim atlas drawn over the
## picture. Frame f shows one full lap of changes + the changes of frames 0..f-1 (as loadMapAnim's canvas).
class AnimLayer extends Node2D:
	var atlas: Texture2D
	var T := 8
	var tw := 1
	var per := 64
	var starts: Array = []
	var total := 1
	var states: Array = []                # per frame: PackedInt32Array [pos, atlas index, ...]
	var frame := -1
	var t0 := 0

	func setup(a: Dictionary) -> void:
		var k := int(a.get("k", 1))
		atlas = DB.tex("res://assets/town/" + str(a.atlas))
		T = int(a.t) * k
		tw = int(a.tw)
		per = int(a.per)
		scale = Vector2.ONE / float(k)
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if k > 1 else CanvasItem.TEXTURE_FILTER_NEAREST
		var acc := 0
		for d in a.dur:
			starts.append(acc)
			acc += int(d)
		total = maxi(1, acc)
		var d: Array = a.d
		var cur := {}
		for fr in d:
			for i in range(0, fr.size(), 2):
				cur[int(fr[i])] = int(fr[i + 1])
		for f in d.size():
			var st := PackedInt32Array()
			var ks := cur.keys()
			ks.sort()
			for p in ks:
				st.append(p)
				st.append(cur[p])
			states.append(st)
			var fr: Array = d[f]
			for i in range(0, fr.size(), 2):
				cur[int(fr[i])] = int(fr[i + 1])
		t0 = Time.get_ticks_msec()

	func _process(_dt: float) -> void:
		var t := (Time.get_ticks_msec() - t0) % total
		var f := 0
		while f + 1 < starts.size() and starts[f + 1] <= t:
			f += 1
		if f != frame:
			frame = f
			queue_redraw()

	func _draw() -> void:
		if atlas == null or frame < 0 or frame >= states.size():
			return
		var st: PackedInt32Array = states[frame]
		for i in range(0, st.size(), 2):
			var p := st[i]
			var a := st[i + 1]
			draw_texture_rect_region(atlas, Rect2((p % tw) * T, (p / tw) * T, T, T), Rect2((a % per) * T, (a / per) * T, T, T))


## The team flag waving over the base (Game.flags.team_flag picks the row).
class FlagLayer extends Node2D:
	var cfg: Dictionary
	var tex: Texture2D

	func _ready() -> void:
		tex = DB.tex("res://assets/town/" + str(cfg.tex))
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if tex == null:
			return
		var w := int(cfg.w)
		var h := int(cfg.h)
		var rows := tex.get_height() / h
		var row := clampi(int(Game.flags.get("team_flag", 0)), 0, rows - 1)
		var f := int(Time.get_ticks_msec() / int(cfg.ms)) % int(cfg.frames)
		draw_texture_rect_region(tex, Rect2(cfg.x, cfg.y, w, h), Rect2(f * w, row * h, w, h))
