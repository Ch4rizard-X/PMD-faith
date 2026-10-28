class_name DungeonQoL
extends Node
## Quality-of-life extras for the dungeon. None of these are in Red; each can be switched off in
## Others -> Game Options -> Others (kept in Game.settings):
##   run mode (hold Run + tap a direction: keep walking until something interesting happens),
##   tap-to-walk (tap/click a tile; tap an adjacent foe to attack it), damage preview in the Moves window,
##   Pokémon info (long-press, hover or right-click a Pokémon), map markers + an always-on corner minimap,
##   auto-pickup filter, low-HP warning (red screen-edge pulse, beep, blinking HP bar),
##   team item prompts (an ally gets low / poisoned / faints: offer the matching Toolbox item),
##   burn / poison wear off after a while (later PMD games; Red keeps them until cured or the next floor),
##   DX recruiting (Rescue Team DX: defeated Pokémon join for the dungeon from 2 tiles; keep them at the exit).

const DEFAULTS := {"qol_run": true, "qol_tap": true, "qol_preview": true, "qol_info": true,
	"qol_minimap": false, "qol_pickup": 0, "qol_lowhp": true, "qol_itemask": true, "qol_statusfade": true, "qol_recruit": 1, "qol_partner_ai": 1, "qol_msgsize": 1, "qol_autosave": true}
const KEYS := ["qol_run", "qol_tap", "qol_preview", "qol_info", "qol_minimap", "qol_pickup", "qol_lowhp", "qol_itemask", "qol_statusfade", "qol_recruit", "qol_partner_ai", "qol_msgsize", "qol_autosave"]
const PICKUP_NAMES := ["All", "No thrown", "Poké+food", "None"]
const PARTNER_AI_NAMES := ["Red", "Smarter"]   # Smarter: dungeon/partner_ai.gd for Let's go together!
const RECRUIT_NAMES := ["Red", "DX"]
const MSG_SIZE_NAMES := ["Small", "Normal", "Large"]   # dungeon message box + message log text size     # Red: joins for good; DX: joins for the dungeon, choose at the exit
const LONG_PRESS := 0.5
const HOVER_TIME := 0.35
const TAP_SLOP := 12.0

var dg      # Dungeon (untyped: avoids a class cycle with dungeon.gd)

# ---- run mode / tap-to-walk
var run_dir := -1                     # running in this direction
var path_goal := Vector2i(-1, -1)     # tap-to-walk destination
var last_stop := ""                   # why the last run/walk stopped (tests, debugging)
var steps := 0                        # steps taken by the current run/walk
var _start_dir := -1                  # the direction pressed to start the run (still held = keep going)
var _block_dir := -1                  # after a run stops, that held direction does nothing until released
var _ticking := false

# ---- touch / mouse
var _touch := {}                      # index -> {pos, t0, cancel, long}
var _hover_tile := Vector2i(-1, -1)
var _hover_t0 := 0.0
var _info: PanelContainer
var _info_mon: Mon
var _info_pinned := false

# ---- maps / low HP
var _mini: Control
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _low := {}                        # uid -> was at <= 1/4 HP
var low_flashes := 0                  # times the low-HP warning fired (tests)
var _beep: AudioStreamPlayer

static func opt(k: String) -> Variant:
	return Game.settings.get(k, DEFAULTS.get(k))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ============================================================== run mode / tap-to-walk
func is_moving() -> bool:
	return run_dir >= 0 or path_goal.x >= 0

func stop(why := "input") -> void:
	if not is_moving():
		return
	last_stop = why
	run_dir = -1
	path_goal = Vector2i(-1, -1)
	if dg and why != "input":
		_block_dir = dg._input_dir()

## Called by Dungeon._process every frame it could take input. Returns true when this frame is used here.
func process_input(d: int) -> bool:
	if _block_dir >= 0:
		if d == _block_dir:
			return true
		_block_dir = -1
	if is_moving():
		if d >= 0 and d != _start_dir:      # a new direction takes over
			var again: bool = run_dir >= 0 and dg._running and bool(opt("qol_run"))
			stop("input")
			if not again:
				return false
			start_run(d)
		dg._running = true
		_tick()
		return true
	if d >= 0 and dg._running and bool(opt("qol_run")) and not dg._rotate and not Input.is_action_pressed("act_turn"):
		start_run(d)
		dg._running = true
		_tick()
		return true
	return false

func start_run(d: int) -> void:
	run_dir = d
	_start_dir = d
	path_goal = Vector2i(-1, -1)
	steps = 0
	last_stop = ""

func walk_to(goal: Vector2i) -> void:
	run_dir = -1
	_start_dir = -1
	path_goal = goal
	steps = 0
	last_stop = ""

func _tick() -> void:
	if _ticking or dg.busy:
		return
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	var dir := run_dir
	if path_goal.x >= 0:
		if L.pos == path_goal:
			stop("arrived")
			return
		var o := fs.mon_at(path_goal)
		if o and o != L and FloorState.cheb(L.pos, path_goal) <= 1:
			stop("arrived")
			return
		dir = _path_dir(path_goal)
		if dir < 0:
			stop("no path")
			return
	if dir < 0:
		return
	var before := _snapshot()
	var old := L.pos
	_ticking = true
	await dg.leader_action({"type": "move", "dir": dir})
	_ticking = false
	if not is_moving():
		return
	if dg.result_sent or dg.fs != fs or not is_instance_valid(self):
		stop("floor")
		return
	if L.pos == old:
		stop("blocked")
		return
	steps += 1
	var why := _interesting(before, old)
	if why != "":
		stop(why)
		return
	if path_goal.x >= 0:
		if L.pos == path_goal:
			stop("arrived")
		return
	var nd := _next_dir(L.pos, old, dir)
	if nd < 0:
		stop("junction")
	else:
		run_dir = nd

func _visible_foes() -> Dictionary:
	var out := {}
	var fs: FloorState = dg.fs
	for o in fs.mons:
		if o.hp > 0 and not o.is_team() and _seen(o.pos):
			out[o.uid] = true
	return out

func _seen(p: Vector2i) -> bool:
	var fs: FloorState = dg.fs
	return fs.leader != null and fs.can_see(fs.leader, p)

func _snapshot() -> Dictionary:
	var fs: FloorState = dg.fs
	var items := {}
	for p in fs.items:
		if _seen(p):
			items[p] = true
	return {"foes": _visible_foes(), "items": items, "hp": fs.leader.hp, "msgs": dg.hud.msg_count if dg.hud else 0,
		"stairs": fs.stairs.x >= 0 and _seen(fs.stairs)}

## Why the walk should stop after this step ("" = keep going).
func _interesting(before: Dictionary, old: Vector2i) -> String:
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	for uid in _visible_foes():
		if not before.foes.has(uid):
			return "foe"
	for d in 8:
		var o := fs.mon_at(L.pos + DB.DIRS[d])
		if o and not o.is_team():
			if path_goal.x >= 0 and o.pos == path_goal:
				return "arrived"
			return "foe"
	if L.hp < int(before.hp):
		return "hp"
	if dg.hud and dg.hud.msg_count != int(before.msgs) and _leader_msg(int(before.msgs)):
		return "message"
	if fs.items.has(L.pos):
		return "item"
	if L.pos == fs.stairs:
		return "stairs"
	if fs.traps.has(L.pos) and fs.traps[L.pos].get("seen", false):
		return "trap"
	if run_dir < 0:
		return ""
	# run mode only: things coming into view, rooms, traps ahead
	for p in fs.items:
		if _seen(p) and not before.items.has(p):
			return "item"
	if fs.stairs.x >= 0 and _seen(fs.stairs) and not bool(before.stairs):
		return "stairs"
	for d in 8:
		var q: Vector2i = L.pos + DB.DIRS[d]
		if fs.traps.has(q) and fs.traps[q].get("seen", false):
			return "trap"
	if fs.room_at(L.pos) != 255 and fs.room_at(old) == 255:
		return "room"
	return ""

## The direction a run continues in from p (came from prev going d), or -1 at a junction / dead end / wall.
func _next_dir(p: Vector2i, prev: Vector2i, d: int) -> int:
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	if fs.room_at(p) != 255:
		if not fs.can_step(p, d, L):
			return -1
		if d % 2 == 0:       # straight across a room: stop beside an exit
			for side in [(d + 2) % 8, (d + 6) % 8]:
				var q: Vector2i = p + DB.DIRS[side]
				if fs.walkable(q, L) and fs.room_at(q) == 255:
					return -1
		return d
	var opts: Array = []
	for k in 8:
		if not fs.can_step(p, k, L):
			continue
		var q: Vector2i = p + DB.DIRS[k]
		if FloorState.cheb(q, prev) <= 1:
			continue
		opts.append(k)
	if opts.size() == 1:
		return int(opts[0])
	if opts.size() == 2 and opts.has(d):     # a corridor bend where the corner tile is also open
		var other: int = opts[0] if int(opts[1]) == d else opts[1]
		var a: Vector2i = p + DB.DIRS[d]
		var b: Vector2i = p + DB.DIRS[other]
		if FloorState.cheb(b, a) <= 1 and fs.room_at(b) == 255 and not _leads_elsewhere(b, a, p):
			return d
	return -1

## True when corridor tile b opens onto something not reachable from a (a real fork, not a cut corner):
## a walkable neighbour of b that isn't p, isn't next to p and isn't next to a.
func _leads_elsewhere(b: Vector2i, a: Vector2i, p: Vector2i) -> bool:
	var fs: FloorState = dg.fs
	for k in 8:
		var q: Vector2i = b + DB.DIRS[k]
		if q == p or q == a or not fs.walkable(q, fs.leader):
			continue
		if FloorState.cheb(q, p) <= 1 or FloorState.cheb(q, a) <= 1:
			continue
		return true
	return false

## BFS over explored tiles that avoids seen traps (and the stairs unless they are the goal).
func _path_dir(goal: Vector2i) -> int:
	var d := _bfs(goal, true)
	return d if d >= 0 else _bfs(goal, false)

func _bfs(goal: Vector2i, avoid_stairs: bool) -> int:
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	if L.pos == goal:
		return -1
	var prev := {L.pos: L.pos}
	var q: Array = [L.pos]
	var head := 0
	var found := false
	while head < q.size() and head < 4000:
		var c: Vector2i = q[head]
		head += 1
		if c == goal:
			found = true
			break
		for d in 8:
			if not fs.can_step(c, d, L):
				continue
			var n: Vector2i = c + DB.DIRS[d]
			if prev.has(n) or fs.explored[fs.idx(n)] == 0:
				continue
			if n != goal:
				if fs.traps.has(n) and fs.traps[n].get("seen", false):
					continue
				if avoid_stairs and n == fs.stairs:
					continue
				var o := fs.mon_at(n)
				if o and not o.is_team():
					continue
			prev[n] = c
			q.append(n)
	if not found:
		return -1
	var cur := goal
	while prev[cur] != L.pos:
		cur = prev[cur]
	return DB.dir_index(cur - L.pos)

# ============================================================== touch / mouse on the map
func screen_to_tile(sp: Vector2) -> Vector2i:
	if dg._map_on and dg.get("red_map") != null:
		return dg.red_map.tile_at(sp)       # Red's floor map layout (RedMap)
	if dg._map_on:
		var g := _map_layout(dg._map.get_viewport_rect().size)
		var t: Vector2 = (sp - g.off) / g.s
		return Vector2i(floori(t.x), floori(t.y))
	var w: Vector2 = dg.get_viewport().get_canvas_transform().affine_inverse() * sp
	return Vector2i(floori(w.x / dg.T), floori(w.y / dg.T))

func tile_to_screen(p: Vector2i) -> Vector2:
	return dg.get_viewport().get_canvas_transform() * dg._px(p)

## True when the point is on the touch pad, a touch button, or a window (not the map).
func _on_controls(sp: Vector2) -> bool:
	var hud: Hud = dg.hud
	if dg.menu_open or not TeamScreens._stack.is_empty():
		return true
	if hud and hud.pad.visible:
		if sp.distance_to(hud.pad.position + hud.pad.size / 2) < 56:
			return true
		for k in hud._btns:
			var b: Control = hud._btns[k]
			if b.visible and b.get_global_rect().grow(2).has_point(sp):
				return true
	for c in dg.ui_root.get_children():
		if c is Control and c.visible and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.get_global_rect().has_point(sp):
			return true
	return false

func _input(e: InputEvent) -> void:
	if dg == null or dg.fs == null or dg.result_sent:
		return
	if (e is InputEventKey or e is InputEventJoypadButton or e is InputEventAction) and e.is_pressed() and not e.is_echo():
		if _info_pinned:
			_hide_info()
		if is_moving() and path_goal.x >= 0:
			stop("input")                    # any key stops tap-to-walk
		elif is_moving() and not (e.is_action("act_run") or e.is_action("gp_b") or _is_move_event(e)):
			stop("input")                    # run mode: anything but Run / directions stops it
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if is_moving():
				stop("input")
			_hide_info()
			if not _touch.is_empty():         # a second finger: pinch zoom, not a tap
				for k in _touch:
					_touch[k].cancel = true
			if not _on_controls(e.position) and not dg.menu_open:
				_touch[e.index] = {"pos": e.position, "t0": _now(), "cancel": not _touch.is_empty(), "long": false}
		else:
			var t: Dictionary = _touch.get(e.index, {})
			_touch.erase(e.index)
			if not t.is_empty() and not t.cancel and not t.long and _now() - float(t.t0) < LONG_PRESS:
				tap(e.position)
	elif e is InputEventScreenDrag:
		if _touch.has(e.index) and e.position.distance_to(_touch[e.index].pos) > TAP_SLOP:
			_touch[e.index].cancel = true
	elif e is InputEventMouseMotion and e.device != InputEvent.DEVICE_ID_EMULATION:
		_hover(e.position)
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT and e.device != InputEvent.DEVICE_ID_EMULATION:
		if _on_controls(e.position) or dg.menu_open:
			return
		var m := _mon_at_screen(e.position)
		if m and bool(opt("qol_info")):
			show_info(m, true)
			get_viewport().set_input_as_handled()
		else:
			_hide_info()

func _is_move_event(e: InputEvent) -> bool:
	for a in ["move_up", "move_down", "move_left", "move_right", "move_ul", "move_ur", "move_dl", "move_dr", "act_diag", "gp_r"]:
		if InputMap.has_action(a) and e.is_action(a):
			return true
	return false

func tap(sp: Vector2) -> void:
	if not bool(opt("qol_tap")) or dg.menu_open or dg.result_sent:
		return
	var fs: FloorState = dg.fs
	var L: Mon = fs.leader
	var tile := screen_to_tile(sp)
	if not fs.inb(tile):
		return
	if tile == L.pos:
		if not dg.busy and (fs.items.has(L.pos) or L.pos == fs.stairs or (fs.traps.has(L.pos) and fs.traps[L.pos].seen)):
			dg.open_ground()
		elif not dg.busy:
			# touch: turn in place (Red's turn button): face the nearest enemy; with none in view (or tapped
			# again while already facing it) turn one step clockwise
			var before := L.facing
			dg._face_nearest_foe()
			if L.facing == before:
				L.facing = (L.facing + 1) % 8
				dg.obj_layer.queue_redraw()
				dg.arrow_layer.queue_redraw()
		return
	var o := fs.mon_at(tile)
	if o and fs.is_foe(L, o) and FloorState.cheb(L.pos, tile) == 1 and _seen(tile):
		var d := DB.dir_index(tile - L.pos)
		if not dg.busy and fs.can_attack_dir(L.pos, d):
			last_stop = "attack"
			dg.leader_action({"type": "attack", "move": "", "dir": d})
		return
	if fs.explored[fs.idx(tile)] == 0:
		return
	if not fs.walkable(tile, L) and o == null:
		return
	walk_to(tile)

func _mon_at_screen(sp: Vector2) -> Mon:
	var fs: FloorState = dg.fs
	var tile := screen_to_tile(sp)
	if not fs.inb(tile):
		return null
	var m := fs.mon_at(tile)
	if m and (m.is_team() or _seen(tile)):
		return m
	return null

func _hover(sp: Vector2) -> void:
	if _info_pinned:
		return
	if dg.menu_open or dg.busy and not is_moving() or _on_controls(sp) or not bool(opt("qol_info")):
		_hover_tile = Vector2i(-1, -1)
		_hide_info()
		return
	var tile := screen_to_tile(sp)
	if tile != _hover_tile:
		_hover_tile = tile
		_hover_t0 = _now()
		if _info and _info_mon and _info_mon.pos != tile:
			_hide_info()

func _process(_dt: float) -> void:
	if dg == null or dg.fs == null:
		return
	var now := _now()
	for k in _touch:
		var t: Dictionary = _touch[k]
		if not t.cancel and not t.long and now - float(t.t0) >= LONG_PRESS:
			t.long = true
			var m := _mon_at_screen(t.pos)
			if m and bool(opt("qol_info")) and not dg.menu_open:
				show_info(m, true)
	if _hover_tile.x >= 0 and not _info and now - _hover_t0 >= HOVER_TIME and not dg.menu_open:
		var fs: FloorState = dg.fs
		var m2: Mon = fs.mon_at(_hover_tile) if fs.inb(_hover_tile) else null
		if m2 and (m2.is_team() or _seen(_hover_tile)):
			show_info(m2, false)
	if _info:
		if dg.menu_open or dg.result_sent or _info_mon == null or _info_mon.hp <= 0 or not dg.fs.mons.has(_info_mon):
			_hide_info()
	if _mini:
		var want: bool = bool(opt("qol_minimap")) and not dg._map_on and not dg.menu_open and TeamScreens._stack.is_empty() and not dg.result_sent
		if _mini.visible != want:
			_mini.visible = want
			_mini.queue_redraw()

# ============================================================== Pokémon info window
const STATUS_TEXT := {"sleep": "Asleep", "nightmare": "Nightmare", "yawn": "Drowsy", "napping": "Napping", "burn": "Burned",
	"poison": "Poisoned", "badpoison": "Badly poisoned", "para": "Paralyzed", "frozen": "Frozen", "confused": "Confused",
	"cowering": "Cowering", "cringe": "Cringing", "infatuated": "Infatuated", "petrified": "Petrified", "paused": "Paused",
	"slow": "Slowed", "fast": "Sped up", "reflect": "Reflect", "light_screen": "Light Screen", "protect": "Protect",
	"safeguard": "Safeguard", "mist": "Mist", "focus_energy": "Focus Energy", "sure_shot": "Sure Shot", "leech_seed": "Leech Seed",
	"wrapped": "Wrapped", "wrapping": "Wrapping", "bide": "Bide", "charging": "Charging", "blinker": "Blinker",
	"cross_eyed": "Cross-eyed", "eyedrops": "Eyedrops", "radar": "Radar", "stockpile": "Stockpile", "invisible": "Invisible",
	"perish": "Perish Song", "decoy": "Decoy", "curse": "Cursed", "destiny_bond": "Destiny Bond", "magic_coat": "Magic Coat",
	"snatch": "Snatch", "grudge": "Grudge", "enduring": "Enduring", "mirror_coat": "Mirror Coat", "counter": "Counter",
	"taunt": "Taunted", "torment": "Tormented", "encore": "Encore", "embargo": "Embargo", "muzzled": "Muzzled",
	"terrified": "Terrified"}
const STAT_SHORT := {"atk": "Atk", "def": "Def", "spa": "SpA", "spd": "SpD", "acc": "Acc", "eva": "Eva"}

## Can this wild Pokémon join if it's defeated (dungeon allows it, species can join, Friend Area owned)?
func recruit_text(m: Mon) -> String:
	if m.is_team():
		return ""
	if m.side == "client":
		return "[color=#7fe0ff]Client[/color]"
	if not dg.recruit_ok_here():
		return "[color=#ff8070]No recruiting here[/color]"
	var S: Dictionary = DB.species.get(m.sp, {})
	if int(S.get("recruit", 0)) == -999:
		return "[color=#ff8070]Won't join[/color]"
	if dg.legend_owned(m):
		return "[color=#ff8070]Already a friend[/color]"
	if not Services.has_area_for(m.sp):
		return "[color=#ff8070]Can't join: no Friend Area[/color]"
	var base := int(S.get("recruit", 0))
	var now: int = dg.recruit_rate(dg.fs.leader, m)
	var txt := "Recruit %s%%" % _pct(now)
	if now != base:
		txt += " (base %s%%)" % _pct(base)
	return "[color=#7fff7f]%s[/color]" % txt

func _pct(per_mille: int) -> String:
	var v := clampf(per_mille / 10.0, 0.0, 100.0)
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v

func info_text(m: Mon) -> String:
	var col := TeamScreens.YELLOW if m.is_team() else TeamScreens.CYAN
	var lines: Array = ["[color=%s]%s[/color]  Lv%d" % [col, m.name, m.level]]
	var ts: Array = []
	for t in m.types:
		if str(t) != "" and str(t) != "None":
			ts.append(str(t))
	lines.append(" / ".join(ts) if ts.size() > 0 else "???")
	lines.append("HP %d/%d" % [maxi(0, m.hp), m.max_hp])
	var st: Array = []
	for k in STATUS_TEXT:
		if int(m.status.get(k, 0)) > 0:
			st.append(STATUS_TEXT[k])
	for k in STAT_SHORT:
		var s := int(m.stages.get(k, 10)) - 10
		if s != 0:
			st.append("%s %+d" % [STAT_SHORT[k], s])
	if st.size() > 0:
		lines.append("[color=#ffb080]%s[/color]" % ", ".join(st))
	if m.held != "" and m.is_team():
		lines.append("Holding %s" % TeamScreens.held_name(m))
	var rt := recruit_text(m)
	if rt != "":
		lines.append(rt)
	return "\n".join(lines)

func show_info(m: Mon, pinned: bool) -> void:
	_hide_info()
	if m == null or dg.ui_root == null:
		return
	_info_mon = m
	_info_pinned = pinned
	var pc := PanelContainer.new()
	pc.theme = UITheme.theme()
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	var all_lines := info_text(m).split("\n")
	var r := TeamScreens._rtl("\n".join(all_lines.slice(0, 3)))     # name, types, HP; the HP bar goes under them
	r.add_theme_constant_override("line_separation", -4)
	vb.add_child(r)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(150, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(func():
		var w := bar.size.x
		var f: float = clampf(float(m.hp) / maxf(1.0, m.max_hp), 0.0, 1.0)
		bar.draw_rect(Rect2(0, 1, w, 8), Color.BLACK)
		bar.draw_rect(Rect2(0, 3, w, 4), Color("7a2a22"))
		var c := Color("2cff34") if f > 0.5 else (Color("ffd030") if f > 0.25 else Color("ff4030"))
		bar.draw_rect(Rect2(0, 3, round(w * f / 2) * 2, 4), c))
	vb.add_child(bar)
	var rest := "\n".join(all_lines.slice(3))
	if rest != "":
		var r2 := TeamScreens._rtl(rest)
		r2.add_theme_constant_override("line_separation", -4)
		vb.add_child(r2)
	dg.ui_root.add_child(pc)
	_info = pc
	_place_info.call_deferred(pc, m)

func _place_info(pc: PanelContainer, m: Mon) -> void:
	if not is_instance_valid(pc) or pc != _info:
		return
	pc.reset_size()
	var vs := pc.get_viewport_rect().size
	var at: Vector2 = tile_to_screen(m.pos) if m.visual == null else dg.get_viewport().get_canvas_transform() * m.visual.position
	var p := Vector2(at.x - pc.size.x / 2, at.y - pc.size.y - 22)
	if p.y < 24:
		p.y = at.y + 22
	p.x = clampf(p.x, 4, maxf(4, vs.x - pc.size.x - 4))
	p.y = clampf(p.y, 22, maxf(22, vs.y - pc.size.y - 4))
	pc.position = p

func _hide_info() -> void:
	if _info and is_instance_valid(_info):
		if _info.get_parent():
			_info.get_parent().remove_child(_info)
		_info.queue_free()
	_info = null
	_info_mon = null
	_info_pinned = false

func info_visible() -> bool:
	return _info != null and is_instance_valid(_info)

# ============================================================== damage preview (Moves window)
func _preview_target(att: Mon) -> Mon:
	var fs: FloorState = dg.fs
	var f := fs.mon_at(att.pos + DB.DIRS[att.facing])
	if f and fs.is_foe(att, f):
		return f
	var best: Mon = null
	var bd := 999
	for o in fs.foes_of(att):
		if fs.can_see(att, o.pos):
			var dd := FloorState.cheb(att.pos, o.pos)
			if dd < bd:
				bd = dd
				best = o
	return best

## min/max damage without the random factor's luck: Combat.calc_damage run many times with crits left
## out (Red's x0.875..x1.125 roll). Side effects of calc_damage (ability flags, Practice Swinger) are undone.
static func damage_range(att: Mon, tgt: Mon, md: Dictionary, ctx: Dictionary) -> Dictionary:
	var vis_a = att.get_meta("red_vis", 0)
	var vis_d = tgt.get_meta("red_vis", 0)
	var practice := att.has_meta("practice_swinger")
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EED
	var c := ctx.duplicate()
	c["skip_accuracy2"] = true
	var lo := 1 << 30
	var hi := -1
	var clo := 1 << 30
	var chi := -1
	var eff := 2
	var heal := false
	var nodmg := false
	for i in 64:
		var r: Dictionary = Combat.calc_damage(att, tgt, md, rng, c)
		if practice:
			att.set_meta("practice_swinger", true)
		eff = int(r.get("eff", 2))
		if int(r.get("heal", 0)) > 0 or bool(r.get("absorbed", false)):
			heal = true
		if bool(r.get("missed_by_type", false)):
			nodmg = true
		var dmg := int(r.get("dmg", 0))
		if bool(r.get("crit", false)):
			clo = mini(clo, dmg); chi = maxi(chi, dmg)
		else:
			lo = mini(lo, dmg); hi = maxi(hi, dmg)
	att.set_meta("red_vis", vis_a)
	tgt.set_meta("red_vis", vis_d)
	if hi < 0:       # always a critical hit (Focus Energy)
		lo = clo; hi = chi
	return {"min": maxi(0, lo), "max": maxi(0, hi), "eff": eff, "heal": heal, "immune": nodmg}

func move_preview(who, mvn: String) -> String:
	if not bool(opt("qol_preview")) or not (who is Mon) or dg.fs == null:
		return ""
	var att: Mon = who
	var md: Dictionary = DB.moves.get(mvn, {})
	if md.is_empty():
		return ""
	var tgt := _preview_target(att)
	if tgt == null:
		return "[color=#8890b0]No foe in sight[/color]"
	var lines: Array = ["vs [color=%s]%s[/color] Lv%d" % [TeamScreens.CYAN, tgt.name, tgt.level]]
	if str(md.get("c", "P")) == "X" or int(md.get("p", 0)) <= 0:
		lines.append("[color=#8890b0]Status move:\nno damage[/color]")
		return "\n".join(lines)
	var ctx := {"weather": dg.fs.weather, "is_regular_attack": false, "att_is_team": att.is_team()}
	var r := damage_range(att, tgt, md, ctx)
	if bool(r.heal):
		lines.append("[color=#7fff7f]It would heal it![/color]")
	elif bool(r.immune) or int(r.max) <= 0:
		lines.append("Dmg [color=#ff8070]0[/color]")
	else:
		lines.append("Dmg [color=#ffdc4a]%d-%d[/color]" % [int(r.min), int(r.max)])
	match int(r.eff):
		3: lines.append("[color=#7fff7f]Super effective![/color]")
		1: lines.append("[color=#ffb080]Not very effective[/color]")
		0: lines.append("[color=#ff8070]Little effect[/color]")
	var a1 := mini(100, Combat.accuracy_threshold(att, tgt, md, ctx.merged({"acc_type": 1})))
	var a2 := mini(100, Combat.accuracy_threshold(att, tgt, md, ctx.merged({"acc_type": 2})))
	var ko := "  [color=#ff8070]KO![/color]" if int(r.min) >= tgt.hp and not bool(r.heal) else ""
	lines.append("Hit %d%%%s" % [int(round(a1 * a2 / 100.0)), ko])
	var d := _dir_to(att, tgt)
	if d < 0 or not dg.targets_for(att, md, d).has(tgt):
		lines.append("[color=#8890b0](out of range)[/color]")
	return "\n".join(lines)

func _dir_to(att: Mon, tgt: Mon) -> int:
	var dv: Vector2i = tgt.pos - att.pos
	if dv == Vector2i.ZERO:
		return -1
	if dv.x == 0 or dv.y == 0 or absi(dv.x) == absi(dv.y):
		return DB.dir_index(Vector2i(signi(dv.x), signi(dv.y)))
	return att.facing

# ============================================================== auto-pickup filter
## Should the leader pick this floor item up automatically? (Autoplay always picks up.)
func auto_pickup(it: Dictionary) -> bool:
	if dg.autoplay:
		return true
	var id := str(it.get("id", ""))
	match int(opt("qol_pickup")):
		1:
			return id == "poke" or not TeamScreens.is_thrown(id)
		2:
			if id == "poke":
				return true
			var I: Dictionary = DB.items.get(id, {})
			return str(I.get("action", "")) == "food" or str(I.get("kind", "")) in ["food", "red_food", "heal", "sitrus", "iqgummi"]
		3:
			return false
	return true

# ============================================================== maps
func _map_layout(vs: Vector2) -> Dictionary:
	var fs: FloorState = dg.fs
	var s := floorf(minf((vs.x - 16) / fs.w, (vs.y - 64) / fs.h))
	s = clampf(s, 3, 8)
	var off := ((vs - Vector2(fs.w, fs.h) * s) / 2).floor()
	off.y = maxf(off.y, 22)
	return {"s": s, "off": off}

## Red-style floor map: explored tiles with lit edges, then stairs, items, seen traps and Pokémon in sight.
func draw_map(c: CanvasItem, off: Vector2, s: float, alpha := 1.0) -> void:
	var fs: FloorState = dg.fs
	if fs == null:
		return
	var floor_c := Color(0.22, 0.42, 0.95, 0.5 * alpha)
	var water_c := Color(0.1, 0.25, 0.7, 0.5 * alpha)
	var edge_c := Color(0.7, 0.85, 1.0, 0.9 * alpha)
	var lw := 1.0 if s < 5 else 2.0
	for y in fs.h:
		for x in fs.w:
			var i := y * fs.w + x
			if fs.explored[i] == 0:
				continue
			var t := fs.terrain[i]
			if t == 0:
				continue
			var r := Rect2(off + Vector2(x, y) * s, Vector2(s, s))
			c.draw_rect(r, floor_c if t == 1 else water_c)
			if s >= 3:
				if fs.terrain_at(Vector2i(x, y - 1)) == 0:
					c.draw_rect(Rect2(r.position, Vector2(s, lw)), edge_c)
				if fs.terrain_at(Vector2i(x, y + 1)) == 0:
					c.draw_rect(Rect2(r.position + Vector2(0, s - lw), Vector2(s, lw)), edge_c)
				if fs.terrain_at(Vector2i(x - 1, y)) == 0:
					c.draw_rect(Rect2(r.position, Vector2(lw, s)), edge_c)
				if fs.terrain_at(Vector2i(x + 1, y)) == 0:
					c.draw_rect(Rect2(r.position + Vector2(s - lw, 0), Vector2(lw, s)), edge_c)
	var inset := maxf(0.0, floorf(s / 5))
	if fs.stairs.x >= 0 and fs.explored[fs.idx(fs.stairs)] == 1:
		var sr := Rect2(off + Vector2(fs.stairs) * s, Vector2(s, s))
		c.draw_rect(sr, Color(1, 1, 1, 0.95 * alpha))
		if s >= 5:
			c.draw_rect(sr.grow(-inset), Color(0.2, 0.4, 0.95, alpha))
			c.draw_rect(Rect2(sr.position + Vector2(inset, s / 2), Vector2(s - 2 * inset, maxf(1, inset))), Color(1, 1, 1, alpha))
	for p in fs.traps:
		if fs.traps[p].get("seen", false) and fs.explored[fs.idx(p)] == 1:
			var tr := Rect2(off + Vector2(p) * s, Vector2(s, s)).grow(-inset)
			var tc := Color(1, 0.35, 0.55, alpha) if fs.traps[p].id != "wonder" else Color(0.45, 0.85, 1, alpha)
			c.draw_line(tr.position, tr.end, tc, lw)
			c.draw_line(Vector2(tr.end.x, tr.position.y), Vector2(tr.position.x, tr.end.y), tc, lw)
	for p in fs.items:
		if fs.explored[fs.idx(p)] == 1:
			c.draw_rect(Rect2(off + Vector2(p) * s, Vector2(s, s)).grow(-maxf(inset, 1.0 if s >= 4 else 0.0)), Color(1, 0.86, 0.3, alpha))
	var L: Mon = fs.leader
	for m in fs.mons:
		if m.hp <= 0:
			continue
		var vis: bool = m.is_team()
		if not vis:
			for t in fs.team():
				if fs.can_see(t, m.pos):
					vis = true
					break
		if not vis:
			continue
		var col := Color(1, 0.3, 0.3)
		if m == L:
			col = Color(1, 0.9, 0.2)
		elif m.is_team():
			col = Color(0.4, 1, 0.5)
		elif m.side == "client":
			col = Color(0.5, 0.9, 1)
		col.a = alpha
		var ctr := off + (Vector2(m.pos) + Vector2(0.5, 0.5)) * s
		if s >= 4:
			c.draw_circle(ctr, s * 0.48 + 0.5, Color(0, 0, 0, 0.7 * alpha))
			c.draw_circle(ctr, s * 0.4, col)
		else:
			c.draw_rect(Rect2(off + Vector2(m.pos) * s - Vector2(0.5, 0.5), Vector2(s + 1, s + 1)), col)

## The full-screen map (Select / Tab / Map button), drawn half see-through over the dungeon.
func draw_full_map(c: Control) -> void:
	var vs := c.get_viewport_rect().size
	c.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0.08, 0.45))
	var g := _map_layout(vs)
	draw_map(c, g.off, g.s, 1.0)

func _ensure_nodes() -> void:
	if dg.ui_root == null:
		return
	if _mini == null:
		_mini = Control.new()
		_mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mini.visible = false
		_mini.draw.connect(_draw_mini)
		dg.ui_root.add_child(_mini)
		dg.ui_root.move_child(_mini, 0)
	if _vignette == null:
		_vignette = ColorRect.new()
		_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var sh := Shader.new()
		sh.code = """shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	vec2 d = (UV - vec2(0.5)) * 2.0;
	float r = length(d * vec2(1.0, 1.1));
	float v = smoothstep(0.75, 1.5, r);
	COLOR = vec4(1.0, 0.06, 0.04, v * strength);
}
"""
		_vig_mat = ShaderMaterial.new()
		_vig_mat.shader = sh
		_vignette.material = _vig_mat
		_vignette.visible = false
		dg.ui_root.add_child(_vignette)
		dg.ui_root.move_child(_vignette, 0)

const MINI_S := 2.0
func _draw_mini() -> void:
	var fs: FloorState = dg.fs
	if fs == null or not bool(opt("qol_minimap")):
		return
	var vs := _mini.get_viewport_rect().size
	var sz := Vector2(fs.w, fs.h) * MINI_S
	var off := Vector2(vs.x - sz.x - 6, 22)
	_mini.draw_rect(Rect2(off - Vector2(2, 2), sz + Vector2(4, 4)), Color(0, 0, 0.1, 0.3))
	draw_map(_mini, off, MINI_S, 0.95)

## Called whenever the dungeon refreshes its HUD (after every turn).
func on_update() -> void:
	_ensure_nodes()
	if _mini and _mini.visible:
		_mini.queue_redraw()
	check_low_hp()

# ============================================================== low-HP warning
func check_low_hp() -> void:
	var fs: FloorState = dg.fs
	if fs == null or fs.leader == null or dg.hud == null:
		return
	var on := bool(opt("qol_lowhp"))
	var fire := false
	for t in fs.team():
		var low: bool = t.hp > 0 and t.hp * 4 <= t.max_hp
		if low and not _low.get(t.uid, false):
			fire = true
		_low[t.uid] = low
	dg.hud.set_low_hp(on and fs.leader.hp > 0 and fs.leader.hp * 4 <= fs.leader.max_hp)
	if fire and on:
		flash_low()

func flash_low() -> void:
	low_flashes += 1
	_ensure_nodes()
	if _vignette == null:
		return
	_vignette.visible = true
	var tw := create_tween()
	for i in 2:
		tw.tween_method(func(v): _vig_mat.set_shader_parameter("strength", v), 0.0, 0.6, 0.16)
		tw.tween_method(func(v): _vig_mat.set_shader_parameter("strength", v), 0.6, 0.0, 0.45)
	tw.tween_callback(func(): _vignette.visible = false)
	_play_beep()

func _play_beep() -> void:
	if _beep == null:
		_beep = AudioStreamPlayer.new()
		_beep.stream = _beep_stream()
		add_child(_beep)
	_beep.volume_db = linear_to_db(maxf(0.001, float(Game.settings.get("sfx", 0.9)) * 0.6))
	_beep.play()

## Two short square-wave beeps (Red has no low-HP sound; this is a soft synthesized one).
static func _beep_stream() -> AudioStreamWAV:
	var rate := 22050
	var data := PackedByteArray()
	var segs := [[1175.0, 0.07], [0.0, 0.05], [1175.0, 0.07], [0.0, 0.02]]
	for sg in segs:
		var n := int(rate * float(sg[1]))
		var base := data.size()
		data.resize(base + n * 2)
		for i in n:
			var v := 0.0
			if float(sg[0]) > 0.0:
				var env := minf(1.0, minf(i, n - i) / (rate * 0.008))
				v = (1.0 if fmod(i * float(sg[0]) / rate, 1.0) < 0.5 else -1.0) * 0.22 * env
			data.encode_s16(base + i * 2, int(v * 32767))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

# ============================================================== Game Options rows
func option_values() -> Dictionary:
	var v := {}
	for k in KEYS:
		v[k] = opt(k)
	v.qol_pickup = clampi(int(v.qol_pickup), 0, PICKUP_NAMES.size() - 1)
	v.qol_recruit = clampi(int(v.qol_recruit), 0, RECRUIT_NAMES.size() - 1)
	v.qol_partner_ai = clampi(int(v.qol_partner_ai), 0, PARTNER_AI_NAMES.size() - 1)
	v.qol_msgsize = clampi(int(v.qol_msgsize), 0, MSG_SIZE_NAMES.size() - 1)
	return v

func option_row(k: String, v: Dictionary) -> Dictionary:
	var oo := func(b): return dg._choice(["Off", "On"], int(bool(b)))
	match k:
		"qol_run": return {"text": "Run mode", "right": oo.call(v[k])}
		"qol_tap": return {"text": "Tap to walk", "right": oo.call(v[k])}
		"qol_preview": return {"text": "Damage preview", "right": oo.call(v[k])}
		"qol_info": return {"text": "Pokémon info", "right": oo.call(v[k])}
		"qol_minimap": return {"text": "Corner map", "right": oo.call(v[k])}
		"qol_pickup": return {"text": "Auto-pickup", "right": "%s %s %s" % [TeamScreens.ARROW_L, PICKUP_NAMES[int(v[k])], TeamScreens.ARROW_R]}
		"qol_lowhp": return {"text": "Low-HP warning", "right": oo.call(v[k])}
		"qol_itemask": return {"text": "Team item prompts", "right": oo.call(v[k])}
		"qol_statusfade": return {"text": "Burn/poison wear off", "right": oo.call(v[k])}
		"qol_autosave": return {"text": "Auto save", "right": oo.call(v[k])}
		"qol_msgsize": return {"text": "Message size", "right": "%s %s %s" % [TeamScreens.ARROW_L, MSG_SIZE_NAMES[int(v[k])], TeamScreens.ARROW_R]}
		"qol_partner_ai": return {"text": "Partner AI", "right": "%s %s %s" % [TeamScreens.ARROW_L, PARTNER_AI_NAMES[int(v[k])], TeamScreens.ARROW_R]}
		"qol_recruit": return {"text": "Recruiting", "right": "%s %s %s" % [TeamScreens.ARROW_L, RECRUIT_NAMES[int(v[k])], TeamScreens.ARROW_R]}
	return {"text": k}

## Left/Right on an option row. Returns false for keys this module doesn't own.
func option_change(k: String, v: Dictionary, d: int) -> bool:
	if not k in KEYS:
		return false
	if k == "qol_pickup":
		v[k] = (int(v[k]) + d + PICKUP_NAMES.size()) % PICKUP_NAMES.size()
	elif k == "qol_recruit":
		v[k] = (int(v[k]) + d + RECRUIT_NAMES.size()) % RECRUIT_NAMES.size()
	elif k == "qol_msgsize":
		v[k] = clampi(int(v[k]) + d, 0, MSG_SIZE_NAMES.size() - 1)
	elif k == "qol_partner_ai":
		v[k] = (int(v[k]) + d + PARTNER_AI_NAMES.size()) % PARTNER_AI_NAMES.size()
	else:
		v[k] = not bool(v[k])
	return true

func apply_options(v: Dictionary) -> void:
	for k in KEYS:
		if v.has(k):
			Game.settings[k] = v[k]
	if not bool(opt("qol_run")) or not bool(opt("qol_tap")):
		stop("input")
	if not bool(opt("qol_info")):
		_hide_info()
	if dg and dg.hud and dg.hud.has_method("apply_msg_size"):
		dg.hud.apply_msg_size()
	on_update()
	if _mini:
		_mini.queue_redraw()

## Did one of the new log lines since n0 mention the leader? (allies' and wild Pokémon's own messages
## used to stop the run after a single step)
func _leader_msg(n0: int) -> bool:
	if dg.hud == null or not "log_all" in dg.hud:
		return true
	var lines: Array = dg.hud.log_all
	var new_n: int = dg.hud.msg_count - n0
	var nm: String = str(dg._nm(dg.fs.leader))
	for i in range(maxi(0, lines.size() - new_n), lines.size()):
		var t := str(lines[i])
		if t.contains(nm) or t.contains(str(dg.fs.leader.name)):
			return true
	return false
