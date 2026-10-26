class_name GAction
extends RefCounted
## One script runner (Red's `Action`: ground_script.c). Port of HandleAction + ExecuteScriptCommand.
## Owners: the map (kind 0), a Lives (1), an Object (2), an Effect (3). The owner implements the callback
## methods (get_center, move_rel, set_dir, ...); positions are 24.8 fixed point (Vector2i) like the original.

enum { RET_00, RET_01, RET_02, RET_03, RET_04 }

class ScriptInfo:
	var ptr := GData.NULL_PTR
	var ptr2 := GData.NULL_PTR
	var group := -1
	var sector := -1
	func copy() -> ScriptInfo:
		var s := ScriptInfo.new()
		s.ptr = ptr; s.ptr2 = ptr2; s.group = group; s.sector = sector
		return s

class SData:
	var state := -1
	var saved_state := 0
	var si := ScriptInfo.new()
	var saved := ScriptInfo.new()
	var cur_ptr := GData.NULL_PTR
	var cur_op := 0
	var unk22 := -1               # lock id being waited for (-1 = none)
	var wait_since := 0           # frame the current cue wait began (deadlock safety net, Ground._cue_rescue)
	var unk24 := 0                # event index (animation) to restore
	var stored_dir := -1
	var branch := 0
	var unk2A := 0                # frame counter
	var unk2C := 0
	var unk30 := 0
	var pos1 := Vector2i.ZERO
	var pos2 := Vector2i.ZERO
	var unk48 := 0
	var unk4D := 0
	var local := PackedByteArray()
	func _init() -> void:
		local.resize(16)
	func copy() -> SData:
		var d := SData.new()
		d.state = state; d.saved_state = saved_state; d.si = si.copy(); d.saved = saved.copy()
		d.cur_ptr = cur_ptr; d.cur_op = cur_op; d.unk22 = unk22; d.unk24 = unk24; d.stored_dir = stored_dir
		d.branch = branch; d.unk2A = unk2A; d.unk2C = unk2C; d.unk30 = unk30; d.pos1 = pos1; d.pos2 = pos2
		d.unk48 = unk48; d.unk4D = unk4D; d.local = local.duplicate()
		return d

var G                       # Ground
var owner                   # entity (or null for the map)
var kind := 0               # unk8.unk0: 0 map, 1 lives, 2 object, 3 effect
var index := 0              # unk8.unk2
var unkC := Vector2i(-1, 0) # (kind, index) of the entity that triggered this script (talk partner)
var group := -1
var sector := -1
var predefined: Array = [GData.NULL_PTR, GData.NULL_PTR, GData.NULL_PTR, GData.NULL_PTR]
var sd := SData.new()
var sd2 := SData.new()

func _init(ground, own, k: int, grp := -1, sec := -1) -> void:
	G = ground
	owner = own
	kind = k
	group = grp
	sector = sec
	index = own.get_index() if own != null else 0

func reset() -> void:
	sd = SData.new()
	sd2 = SData.new()

func reset_for_delete() -> void:
	reset()
	sd.saved_state = RET_04

func is_running() -> bool:
	return sd.saved_state != RET_00

func set_predefined(i: int, p: Vector2i) -> void:
	predefined[i] = p

## {ptr, state, group, sector}
func predefined_info(i: int) -> Dictionary:
	return {"ptr": predefined[i], "state": i, "group": group, "sector": sector}

func running_script(info: Dictionary) -> bool:     # sub_809D684
	for d in [sd, sd2]:
		if d.saved_state != RET_00:
			if d.saved.ptr != GData.NULL_PTR:
				if d.saved.ptr2 == info.ptr:
					return true
			elif d.si.ptr2 == info.ptr:
				return true
	return false

## GroundScript_ExecutePP
func execute(info: Dictionary, trigger = null) -> bool:
	if info.is_empty() or info.ptr == GData.NULL_PTR:
		return false
	match int(info.state):
		2, 3:
			if sd.state == 1:
				sd2 = sd.copy()
			elif sd.state == 5:
				sd2 = SData.new()
		5:
			sd2 = sd.copy()
		0:
			if sd.state != 1:
				sd2 = SData.new()
			else:
				sd2 = sd.copy()
		1:
			sd2 = SData.new()
	sd = SData.new()
	if trace and owner == null:
		print("    [f%d] MAP EXEC %s state=%d" % [G._frame, GData.scr_names[info.ptr.x], int(info.state)])
	unkC = trigger if trigger != null else Vector2i(-1, 0)
	sd.state = int(info.state)
	sd.saved_state = RET_03
	sd.si.group = int(info.group)
	sd.si.sector = int(info.sector)
	sd.si.ptr = info.ptr
	sd.si.ptr2 = info.ptr
	if owner != null:
		sd.stored_dir = owner.get_dir()
	return true

func execute_predefined(i: int, trigger = null) -> bool:
	return execute(predefined_info(i), trigger)

var heard := {}          # cue id -> frame of the alert this script last received

func notify(id: int) -> bool:
	var r := false
	if sd.unk22 != -1 and sd.unk22 == id:
		sd.unk22 = -1
		r = true
	if sd2.unk22 != -1 and sd2.unk22 == id:
		sd2.unk22 = -1
		r = true
	if r:
		heard[id] = int(G.cue_last.get(id, G._frame))
	return r

func _check_lock(id: int) -> bool:          # GroundScriptCheckLockCondition
	if id == 0 and not G.text.is_open():
		sd.si.ptr = _resolve_jump(0)
		return false
	if id > 1 and G.pending_cues.has(id):
		G.pending_cues[id][0] -= 1
		if G.pending_cues[id][0] <= 0:
			G.pending_cues.erase(id)
		sd.si.ptr = _resolve_jump(G.unlock_labels[id])
		if trace:
			print("    [f%d] late cue %d taken  %s" % [G._frame, id, _where()])
		return false
	# a cue sent a few frames before this wait began, that this script didn't receive: take it now
	# (our walk / jump timings can run a few frames behind Red's)
	if id > 1 and id < 0x80 and G.cue_last.has(id):
		var t: int = G.cue_last[id]
		if G._frame - t <= 15 and int(heard.get(id, -1)) != t:
			heard[id] = t
			sd.si.ptr = _resolve_jump(G.unlock_labels[id])
			if trace:
				print("    [f%d] just-missed cue %d taken  %s" % [G._frame, id, _where()])
			return false
	sd.unk22 = id
	sd.wait_since = G._frame
	sd.saved_state = RET_02
	G.any_locked = true
	if trace:
		print("    [f%d] WAIT lock %d  %s" % [G._frame, id, _where()])
	return true

static var trace := false

func _lock_cond(id: int, label: int) -> bool:   # GroundScriptLockCond
	G.unlock_labels[id] = label
	if id == 0:
		if not G.text.is_open():
			return false
		sd.unk22 = id
	else:
		sd.unk22 = id | 0x80
		G.locks[id] = true
		G.lock_conds[id] = true
	sd.saved_state = RET_02
	G.any_locked = true
	return true

# ------------------------------------------------------------------ HandleAction
func handle() -> int:
	if sd.saved_state == RET_00:
		return RET_00
	var guard := 0
	while true:
		guard += 1
		if guard > 4000:
			push_warning("ground: runaway script %s" % _where())
			return RET_03
		match sd.saved_state:
			RET_02:
				if not _wait_step():
					return RET_03
			RET_03:
				var st := _exec()
				sd.saved_state = st
				match st:
					RET_00:
						if sd2.saved_state != RET_00:
							sd = sd2
							if owner != null:
								if sd.stored_dir != -1 and (owner.get_flags() & 0x400):
									owner.set_dir(sd.stored_dir)
								owner.set_event_index(sd.unk24)
							sd2 = SData.new()
						else:
							sd = SData.new()
						return RET_03
					RET_03:
						return RET_03
					RET_04:
						return RET_04
					RET_01:
						return RET_01
					_:
						sd.unk2C = 0
			_:
				return sd.saved_state
	return RET_03

func _where() -> String:
	var p := sd.cur_ptr
	return "%s+%d" % [GData.scr_names[p.x] if p.x >= 0 else "?", p.y]

## One RET_02 (waiting) step. Returns true to keep looping this frame (state changed to RET_03),
## false to stop for this frame.
func _wait_step() -> bool:
	var op := sd.cur_op
	match op:
		0x58, 0x59, 0x5A, 0x5B, 0x5D, 0x5E, 0x60, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F, 0x90, 0x98, 0x99, 0xDB, 0xDC:
			if sd.unk2A > 0:
				sd.unk2A -= 1
				return false
			sd.saved_state = RET_03
			return true
		0xDD:
			if owner.sprite_busy_4c():
				return false
			sd.saved_state = RET_03
			return true
		0xDE:
			if owner.sprite_busy_50():
				return false
			sd.saved_state = RET_03
			return true
		0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0xDF:
			if G.fade_busy():
				return false
			sd.saved_state = RET_03
			return true
		0xE0:
			var c := GData.cmd(sd.cur_ptr)
			if Audio.is_bgm_playing_id(int(c[2])) and sd.unk2C < 180 * 60:
				sd.unk2C += 1
				return false
			sd.saved_state = RET_03
			return true
		0xE1, 0xE2:
			var c := GData.cmd(sd.cur_ptr)
			if G.sound_playing(int(c[2])) and sd.unk2C < 60 * 60:
				sd.unk2C += 1
				return false
			sd.saved_state = RET_03
			return true
		0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67:
			var pos: Vector2i = owner.get_center()
			var d := _clamp(sd.pos2 - pos, sd.unk30)
			if d == Vector2i.ZERO:
				sd.saved_state = RET_03
				return true
			if owner.move_rel(d) & 9:
				sd.saved_state = RET_03
				return true
			owner.set_event_index(0x1000)
			if sd.unk2A >= 0:
				if sd.unk2A > 0:
					sd.unk2A -= 1
					return false
				sd.saved_state = RET_03
				return true
			return false
		0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F:
			var pos: Vector2i = owner.get_center()
			var d := _clamp(sd.pos2 - pos, sd.unk30)
			if d == Vector2i.ZERO:
				sd.saved_state = RET_03
				return true
			var res: int = owner.move_rel(d)
			var dir := GDir.vec_dir8(d)
			sd.stored_dir = dir
			owner.set_dir(dir)
			if res & 9:
				sd.saved_state = RET_03
				return true
			owner.set_event_index(0x1000)
			if sd.unk2A >= 0:
				if sd.unk2A > 0:
					sd.unk2A -= 1
					return false
				sd.saved_state = RET_03
				return true
			return false
		0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x7D, 0x7E, 0x7F, 0x80, 0x81, 0x82:
			if sd.unk2A > 0:
				owner.move_real(_interp(sd.pos1, sd.pos2, sd.unk2A, sd.unk2C))
				owner.set_event_index(0x1000)
				sd.unk2A -= 1
				sd.unk2C += 1
				return false
			sd.saved_state = RET_03
			return true
		0x77, 0x78, 0x79, 0x7A, 0x7B, 0x7C, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88:
			if sd.unk2A > 0:
				var p1: Vector2i = owner.get_center()
				var p2 := _interp(sd.pos1, sd.pos2, sd.unk2A, sd.unk2C)
				var dir := GDir.vec_dir8(p2 - p1)
				sd.stored_dir = dir
				owner.set_dir(dir)
				owner.move_real(p2)
				owner.set_event_index(0x1000)
				sd.unk2A -= 1
				sd.unk2C += 1
				return false
			sd.saved_state = RET_03
			return true
		0x68, 0x70:
			var hu: Vector2i = owner.get_height()
			var delta := sd.unk48 - hu.x
			if delta == 0:
				sd.saved_state = RET_03
				return true
			owner.set_height(hu.x + clampi(delta, -sd.unk30, sd.unk30))
			return false
		0x89, 0x8A:
			var v := GDir.vec(owner.get_dir(), sd.unk30)
			if owner.move_rel(v) & 9:
				sd.saved_state = RET_03
				return true
			owner.set_event_index(0x1000)
			if sd.unk2A > 0:
				sd.unk2A -= 1
				return false
			sd.saved_state = RET_03
			return true
		0x91, 0x92, 0x93, 0x94, 0x95:
			if sd.unk2A > 0:
				sd.unk2A -= 1
				return false
			var c := GData.cmd(sd.cur_ptr)
			var cur: int = owner.get_dir()
			var target := -1
			var flag := false
			var p1 := Vector2i.ZERO
			var p2 := Vector2i.ZERO
			match int(c[0]):
				0x91, 0x92:
					target = _s8(sd.unk4D)
				0x93:
					var r = G.lives_find(int(c[3]))
					if r >= 0:
						flag = true
						p1 = G.lives[r].get_center()
						p2 = G.lives[r].get_size()
				0x94:
					var r = G.lives_find(int(c[3]))
					if r >= 0:
						flag = true
						p1 = G.lives[r].get_center()
				0x95:
					flag = true
					p1 = owner.get_center()
					p2 = owner.get_size()
					p1 = G.link_pos(int(c[3]), p1)
			if flag:
				var p3: Vector2i = owner.get_center()
				var p4: Vector2i = owner.get_size()
				target = GDir.sized_delta8(p3, p4, p1, p2)
				if target == -1:
					target = GDir.sized_delta4(p3, Vector2i.ZERO, p1, Vector2i.ZERO)
			if target == -1 or target == cur:
				sd.saved_state = RET_03
				return true
			sd.stored_dir = GDir.transform2(cur, target, int(c[2]) & 0xFF)
			owner.set_dir(sd.stored_dir)
			sd.unk2A = int(c[1])
			return false
		0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xA0, 0xA1, 0xA2, 0xA3:
			if G.camera.moving():
				return false
			sd.saved_state = RET_03
			return true
		0xE3, 0xE5:
			if sd.unk22 != -1:
				return false
			sd.si.ptr = _resolve_jump(G.unlock_labels[sd.branch])
			sd.saved_state = RET_03
			return true
		0x2C, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38:
			if sd.unk22 != -1:
				return false
			sd.saved_state = RET_03
			G.set_player_mode(0)
			return true
		0x39:
			if sd.unk22 != -1 or G.fade_busy():
				return false
			sd.saved_state = RET_03
			G.set_player_mode(0)
			return true
		0x3B:
			var c := GData.cmd(sd.cur_ptr)
			var t: int = G.special_func(self, int(c[1]), int(c[2]), int(c[3]))
			if t < 0:
				return false
			sd.saved_state = RET_03
			sd.si.ptr = _resolve_jump(t)
			return true
		0x3C:
			var r: Array = G.text.result()
			if not r[0]:
				return false
			sd.si.ptr = _resolve_jump(int(r[1]))
			sd.saved_state = RET_03
			G.set_player_mode(0)
			return true
		0x03:
			var r: Array = G.text.result()
			if not r[0]:
				return false
			var val := int(r[1])
			if val >= 0:
				var c := GData.cmd(sd.cur_ptr)
				G.ground_request(GData.map_of_fa(val), 0, int(c[2]))
			sd.si.ptr = _resolve_jump(val)
			sd.saved_state = RET_03
			G.set_player_mode(0)
			return true
		0x04, 0x05, 0x06, 0x07:
			return _wait_dungeon_select()
		0x3D, 0x3E, 0x3F:
			var r: Array = G.text.result()
			if not r[0]:
				return false
			var val := int(r[1])
			var c := GData.cmd(sd.cur_ptr)
			if op == 0x3D and val == 1 and int(c[3]) != -1:
				G.rename_lives(_s16(int(c[3])), G.text.name_buffer)
			elif op == 0x3E and val == 1:
				Game.story_set("team_name", G.text.name_buffer)
			elif op == 0x3F and val == 1:
				if G.text.name_buffer != str(c[5]):
					val = 2
			sd.si.ptr = _resolve_jump(val)
			sd.saved_state = RET_03
			G.set_player_mode(0)
			return true
		0x3A:
			if sd.unk2C == 0:
				if sd.unk22 != -1:
					return false
				sd.unk2C += 1
				return true
			var r: Array = G.text.result()
			if not r[0]:
				return false
			if int(r[1]) == 1:
				var c := GData.cmd(sd.cur_ptr)
				sd.si.ptr = _find_label(int(c[2]))
			sd.saved_state = RET_03
			G.set_player_mode(0)
			return true
		0xCF:
			var c := GData.cmd(sd.cur_ptr)
			if sd.unk2C == 0:
				var found := false
				if sd.branch < 0:
					if int(GData.cmd(sd.si.ptr)[0]) != 0xD1:
						sd.saved_state = RET_03
						return true
				else:
					while int(GData.cmd(sd.si.ptr)[0]) == 0xD0:
						if int(GData.cmd(sd.si.ptr)[2]) == sd.branch:
							found = true
							break
						sd.si.ptr.y += 1
					if not found:
						while int(GData.cmd(sd.si.ptr)[0]) == 0xD1:
							sd.si.ptr.y += 1
						sd.saved_state = RET_03
						return true
				if G.text.say(int(c[1]), _s16(int(c[3])), GData.cmd(sd.si.ptr)[5]):
					G.set_player_mode(10)
					if _check_lock(0):
						sd.unk2C = 1
				sd.si.ptr.y += 1
				return true
			else:
				if sd.unk22 != -1:
					return false
				sd.unk2C = 0
				G.set_player_mode(0)
				return true
		0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8:
			if sd.unk2C == 0:
				if sd.unk22 != -1:
					return false
				sd.unk2C += 1
				return true
			var r: Array = G.text.result()
			if not r[0]:
				return false
			var tmp := int(r[1])
			if tmp > 0:
				var c := GData.cmd(Vector2i(sd.cur_ptr.x, sd.cur_ptr.y + sd.branch + tmp))
				sd.si.ptr = _find_label(int(c[2]))
			sd.saved_state = RET_03
			G.set_player_mode(0)
			return true
		0xDA:
			if sd.unk22 != -1:
				return false
			sd.si.ptr = _resolve_jump(G.unlock_labels[1])
			sd.saved_state = RET_03
			return true
	return false

## 0x04-0x07: pick a dungeon / dojo, show requirements, then go (EVENT_RESCUE).
func _wait_dungeon_select() -> bool:
	var op := sd.cur_op
	if op == 0x04 and sd.branch == 0:
		var r: Array = G.text.result()
		if not r[0]:
			return false
		var val := int(r[1])
		if val >= 0:
			GVars.set_val(null, GVars.DUNGEON_SELECT, GData.rescue_to_script(val))
			sd.branch = 1
		else:
			sd.branch = -1
		G.set_player_mode(0)
		return true
	if op == 0x04 and sd.branch == 1:
		var c := GData.cmd(sd.cur_ptr)
		var sel := GVars.get_val(null, GVars.DUNGEON_SELECT)
		if sel != 19 or GVars.get_arr(null, GVars.DUNGEON_ENTER_LIST, sel) != 0:
			G.request_world_map(int(c[2]))
			sd.si.ptr = _resolve_jump(0)
			G.set_player_mode(0)
			sd.saved_state = RET_03
			return true
		GVars.set_val(null, GVars.DUNGEON_ENTER, 19)
	if (op == 0x06 or op == 0x04) and sd.branch == 0:
		var r: Array = G.text.result()
		if not r[0]:
			return false
		var val := int(r[1])
		if val >= 0:
			GVars.set_val(null, GVars.DUNGEON_ENTER, GData.rescue_to_script(val) if op == 0x04 else val)
			sd.branch = 1
		else:
			sd.branch = -1
		G.set_player_mode(0)
		return true
	if (op == 0x04 or op == 0x06 or op == 0x07) and sd.branch == 1:
		var sdun := GVars.get_val(null, GVars.DUNGEON_ENTER)
		var req: Array = G.dungeon_requirements(sdun)      # [result, text]
		match int(req[0]):
			2:
				sd.branch = 2
				G.text.special(G.SP_YES_NO_LARGE, 1, 0, req[1])
				if _check_lock(1):
					G.set_player_mode(11)
			0:
				sd.branch = 3
			1:
				sd.branch = 4
				G.text.special(G.SP_LARGE_TEXT, 1, 0, req[1])
				if _check_lock(1):
					G.set_player_mode(11)
			_:
				sd.branch = -1
		return true
	if op == 0x05 and sd.branch == 1:
		sd.branch = 3
		return true
	if sd.branch == 2:
		var r: Array = G.text.result()
		if not r[0]:
			return false
		sd.branch = 3 if int(r[1]) != 0 else -1
		G.set_player_mode(0)
		G.text.clear()
		return true
	if sd.branch == 3:
		var c := GData.cmd(sd.cur_ptr)
		sd.saved_state = RET_03
		G.fade_out_a(int(c[2]))
		G.map_execute_event(GData.fn_id("EVENT_RESCUE"), false)
		if kind == 0:
			return true
		sd.si.ptr = _resolve_jump(1)
		return true
	if sd.branch == 4:
		var r: Array = G.text.result()
		if not r[0]:
			return false
		sd.branch = -1
		G.set_player_mode(0)
		G.text.clear()
		return true
	GVars.set_val(null, GVars.DUNGEON_ENTER, -1)
	sd.si.ptr = _resolve_jump(-1)
	sd.saved_state = RET_03
	return true

# ------------------------------------------------------------------ helpers
static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v

static func _s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v >= 0x80 else v

static func _clamp(v: Vector2i, lim: int) -> Vector2i:
	return Vector2i(clampi(v.x, -lim, lim), clampi(v.y, -lim, lim))

static func _interp(a: Vector2i, b: Vector2i, wa: int, wb: int) -> Vector2i:
	var w := wa + wb
	if w == 0:
		return b
	return Vector2i(int((wa * a.x + wb * b.x) / w), int((wa * a.y + wb * b.y) / w))

func _hypot_steps(speed: int) -> int:
	var d := sd.pos2 - sd.pos1
	var h := int(sqrt(float(d.x) * d.x + float(d.y) * d.y))
	var n := int(h / maxi(speed, 1))
	return maxi(n, 1)

func _find_label(label: int) -> Vector2i:
	var p := sd.si.ptr2
	var a: Array = GData.scr[p.x]
	var i := p.y + 1
	while i < a.size():
		var c: Array = a[i]
		i += 1
		if int(c[0]) == 0xF4 and int(c[2]) == label:
			return Vector2i(p.x, i)
	push_warning("ground: label %d not found in %s" % [label, GData.scr_names[p.x]])
	return Vector2i(p.x, a.size())

func _resolve_jump(v: int) -> Vector2i:
	var p := sd.si.ptr
	while true:
		var c := GData.cmd(p)
		match int(c[0]):
			0xCC:
				if v == int(c[3]):
					return _find_label(int(c[2]))
			0xCD:
				if GVars.flag_judge(v, int(c[3]), int(c[1])):
					return _find_label(int(c[2]))
			0xCE:
				if GVars.flag_judge(v, GVars.get_val(sd.local, _s16(int(c[3]))), int(c[1])):
					return _find_label(int(c[2]))
			_:
				return p
		p.y += 1
	return p

func _grp(c: Array) -> int:
	return sd.si.group if int(c[2]) < 0 else int(c[2])

func _sec(c: Array) -> int:
	var b := _s8(int(c[1]))
	return sd.si.sector if b < 0 else b

# ------------------------------------------------------------------ ExecuteScriptCommand
func _exec() -> int:
	var guard := 0
	while true:
		guard += 1
		if guard > 20000:
			push_warning("ground: script loop %s" % _where())
			return RET_02
		sd.cur_ptr = sd.si.ptr
		var c := GData.cmd(sd.si.ptr)
		sd.si.ptr.y += 1
		var op := int(c[0])
		sd.cur_op = op
		var b := int(c[1])
		var s := int(c[2])
		var a1 := int(c[3])
		var a2 := int(c[4])
		match op:
			0x01:
				G.ground_request(_s16(a1), b & 0xFF, s)
			0x02:
				var dun := _s16(a1)
				if dun == -1:
					dun = _s16(GVars.get_val(null, GVars.DUNGEON_ENTER))
				if dun != -1:
					G.rescue_request(dun, s)
					sd.si.ptr = _resolve_jump(1)
				else:
					sd.si.ptr = _resolve_jump(0)
			0x03:
				# go to the Friend Area select screen (sub_8021700 / sub_8098D80)
				var none := false
				if a1 == 1:
					none = Game.friend_areas.is_empty()
				elif a1 == 2:
					none = Services.shop_areas_left() == 0
				if none:
					sd.si.ptr = _resolve_jump(-1)
				else:
					G.request_friend_areas(s)
					sd.si.ptr = _resolve_jump(0)
			0x04:
				if a1 == -1:
					if G.text.special(G.SP_DUNGEON_LIST, 0, 0, null):
						G.set_player_mode(11)
						sd.branch = 0
					else:
						sd.branch = -1
					return RET_02
				GVars.set_val(null, GVars.DUNGEON_SELECT, GData.rescue_to_script(_s16(a1)))
				sd.branch = 1
				return RET_02
			0x06:
				if a1 == -1:
					if G.text.special(G.SP_DOJO_ENTER, 0, 0, null):
						G.set_player_mode(11)
						sd.branch = 0
					else:
						sd.branch = -1
					return RET_02
				GVars.set_val(null, GVars.DUNGEON_ENTER, a1)
				sd.branch = 1
				return RET_02
			0x05:
				sd.branch = 1
				return RET_02
			0x07:
				var t := _s16(a1)
				if t == -1:
					t = _s16(GVars.get_val(null, GVars.DUNGEON_ENTER))
				else:
					GVars.set_val(null, GVars.DUNGEON_ENTER, t)
				sd.branch = 1 if t != -1 else -1
				return RET_02
			0x08, 0x09:
				G.select_map(_s16(a1), op == 0x08)
			0x0A:
				G.select_dungeon_map(_s16(a2), _s16(a1), s, b)
			0x0B:
				G.weather_select(_s16(a1))
			0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15:
				var grp := _grp(c)
				var sec := _sec(c)
				match op:
					0x0C:
						G.lives_select(grp, sec); G.objects_select(grp, sec); G.effects_select(grp, sec); G.events_select(grp, sec)
					0x0D:
						G.lives_select(grp, sec)
					0x0E:
						G.objects_select(grp, sec)
					0x0F:
						G.effects_select(grp, sec)
					0x10:
						G.events_select(grp, sec)
					0x11:
						G.lives_cancel(grp, sec); G.objects_cancel(grp, sec); G.effects_cancel(grp, sec); G.events_cancel(grp, sec)
					0x12:
						G.lives_cancel(grp, sec)
					0x13:
						G.objects_cancel(grp, sec)
					0x14:
						G.effects_cancel(grp, sec)
					0x15:
						G.events_cancel(grp, sec)
			0x16:
				G.lives_cancel_offscreen()
			0x17:
				G.objects_cancel_offscreen()
			0x18:
				G.effects_cancel_offscreen()
			0x19:
				var grp := sd.si.group if s < 0 else s
				var sec := sd.si.sector if _s8(b) < 0 else _s8(b)
				var d := {"kind": a2, "u1": owner.get_dir() if owner else 0, "w": 1, "h": 1, "pos": [0, 0, 0, 0],
					"scripts": [null, null, null, GData.common.functions[a1].script]}
				var r: int = G.objects_add(-1, d, grp, sec)
				if r >= 0 and owner:
					G.objects[r].move_real(owner.get_center())
			0x1A:
				var grp := sd.si.group if s < 0 else s
				var sec := sd.si.sector if _s8(b) < 0 else _s8(b)
				var d := {"kind": a2, "u1": owner.get_dir() if owner else 0, "w": 1, "h": 1, "pos": [0, 0, 0, 0],
					"script": GData.common.functions[a1].script}
				var r: int = G.effects_add(-1, d, grp, sec)
				if r >= 0 and owner:
					G.effects[r].move_real(owner.get_center())
			0x1C:
				G.map_execute_event(s, true)
			0x1B:
				G.map_execute_event(s, false)
			0x1D, 0x1E:
				var map = G.cur_map if a1 == -1 else _s16(a1)
				map = G.adjusted_map(map)
				G.map_execute_station(map, _grp(c), _sec(c), op == 0x1E)
				if G.station_map != map:
					G.station_map = map
					G.cancel_all_entities()
					if kind != 0:
						return RET_04
			0x1F:
				var a := _s16(GVars.get_val(null, GVars.DUNGEON_ENTER))
				var di := GData.dungeon_info(a)
				var sidx := int(di.script1) if GVars.get_arr(null, GVars.DUNGEON_ENTER_LIST, a) == 0 else int(di.script2)
				var maze := a >= 55 and a <= 71
				if not maze and G.dungeon_kind(a) == 1:
					if sidx == -1:
						G.rescue_request(a, -1)
					else:
						G.map_execute_event(sidx, false)
				else:
					G.rescue_request(a, -1)
			0x20:
				match unkC.x:
					0:
						G.map_execute_event(s, false)
					1:
						G.lives[unkC.y].action.execute(_fn_info(s), Vector2i(kind, index))
					2:
						G.objects[unkC.y].action.execute(_fn_info(s), Vector2i(kind, index))
					3:
						G.effects[unkC.y].action.execute(_fn_info(s), Vector2i(kind, index))
			0x21:
				var r = G.lives_find(_s16(a1))
				if r >= 0:
					var L = G.lives[r]
					if L.flags & 0x200:
						var p1: Vector2i = owner.get_center()
						var p2: Vector2i = owner.get_size()
						var t := GDir.sized_delta8(L.get_center(), L.get_size(), p1, p2)
						if t == -1:
							t = GDir.sized_delta4(p1, Vector2i.ZERO, L.get_center(), Vector2i.ZERO)
						if t != -1:
							L.direction1 = t
					G.lives_player_talk(index, r)
					return RET_03
			0x22:
				G.fade_in_a(s)
				if b != 0:
					return RET_02
			0x23:
				G.fade_out_a(s)
				if b != 0:
					return RET_02
			0x24:
				G.fade_to_a(s, a1, a2)
				if b != 0:
					return RET_02
			0x25:
				G.fade_in_b(s)
				if b != 0:
					return RET_02
			0x26:
				G.fade_out_b(s)
				if b != 0:
					return RET_02
			0x27, 0x28:
				var col := Color8((a2 >> 16) & 0xFF, (a2 >> 8) & 0xFF, a2 & 0xFF)
				G.flash(op == 0x27, s, a1, col)
				if b != 0:
					return RET_02
			0x29:
				G.text.window_flags_set(s & 0xFFFF)
			0x2A:
				G.text.window_flags_clear(s & 0xFFFF)
			0x2B:
				G.text.set_auto_press(a1, a2)
			0x2C:
				if G.text.is_open():
					G.set_player_mode(10)
					if _check_lock(0):
						return RET_02
			0x30:
				G.text.clear()
			0x31:
				G.text.clear2()
			0x2D:
				_portrait_setup(b & 0xFF, s, a1)
			0x2E:
				G.text.set_portrait(s, _s8(a1), b & 0xFF)
			0x2F:
				G.text.set_portrait_delta(s, Vector2i(a1, a2))
			0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38:
				var ret := false
				match op:
					0x32:
						ret = G.text.say(G.text.T_INSTANT, s, c[5])
					0x33:
						ret = G.text.say(G.text.T_QUIET, s, c[5])
					0x34:
						ret = G.text.say(G.text.T_NPC, s, c[5])
					0x35:
						ret = G.text.say(G.text.T_LETTER, s, c[5])
					0x36:
						ret = G.text.say(G.text.T_OVERHEARD, s, c[5])
					0x37, 0x38:
						ret = G.text.say_on_bg(c[5], false)
				if ret:
					G.set_player_mode(10)
					if _check_lock(0):
						return RET_02
			0x39:
				if G.text.say_on_bg(c[5], true) and s >= 0:
					G.set_player_mode(10)
					if _check_lock(0):
						return RET_02
			0x3A:
				G.text.ask_yes_no((b & 0xFF) > 0, a1, _s16(a2), c[5])
				if _check_lock(1):
					G.set_player_mode(11)
					return RET_02
			0x3C:
				G.text.special(b, a1, a2, c[5])
				G.set_player_mode(11)
				return RET_02
			0x3B:
				sd.unk2A = 0
				return RET_02
			0x3D:
				if _s16(a1) != -1:
					var nm: String = G._strip_name(G.lives_name_by_kind(_s16(a1)))   # plain text for the name box
					G.text.name_buffer = nm
					G.text.special(G.SP_PLAYER_NAME_INPUT, 0, 0, nm)
				else:
					G.text.special(G.SP_PLAYER_NAME_INPUT, 1, 0, G.text.name_buffer)
				G.set_player_mode(11)
				return RET_02
			0x3E:
				G.text.name_buffer = str(Game.story_get("team_name", ""))
				G.text.special(G.SP_TEAM_NAME_INPUT, 0, 0, G.text.name_buffer)
				G.set_player_mode(11)
				return RET_02
			0x3F:
				G.text.name_buffer = ""
				G.text.special(G.SP_PASSWORD_INPUT, b & 0xFF, 0, "")
				G.set_player_mode(11)
				return RET_02
			0x41:
				G.remove_item(s)
			0x42:
				Audio.stop_music()
			0x43:
				Audio.fade_out_music(30 if s < 0 else s)
			0x44:
				var id = G.modify_bgm(a1 & 0xFFFF) if b == 0 else a1
				G.bgm_play(id, 0)
			0x45:
				var id = G.modify_bgm(a1 & 0xFFFF) if b == 0 else a1
				G.bgm_play(id, s)
			0x46:
				var id = G.modify_bgm(a1 & 0xFFFF) if b == 0 else a1
				G.bgm_queue(id)
			0x47:
				Audio.stop_music()
			0x48:
				Audio.fade_out_music(30 if s < 0 else s)
			0x49, 0x4C:
				G.sound_play(a1 & 0xFFFF)
			0x4A, 0x4D:
				G.sound_stop(a1 & 0xFFFF)
			0x4B, 0x4E:
				G.sound_stop(a1 & 0xFFFF)
			0x4F:
				if sd2.state == 1:
					sd2 = SData.new()
				owner.set_hitbox_pos(null)
			0x50:
				var other = G.action_of(unkC)
				if other != null and other.owner != null:
					var p: Vector2i = other.owner.get_center()
					var d: int = other.owner.get_dir()
					owner.move_real(p)
					sd.stored_dir = d
					owner.set_dir(d)
			0x51:
				var area: Array = G.link_area(s, owner.get_center())
				owner.set_bounds(area[0], area[1])
			0x52:
				owner.set_flags(a1)
			0x53:
				if (a1 & 0x400) and sd2.state == 1:
					sd2 = SData.new()
				owner.clear_flags(a1)
			0x54:
				sd.stored_dir = owner.get_dir()
				if s != 0:
					sd.unk24 = s & 0xFFFF
				owner.set_event_index(s & 0xFFFF)
			0x55:
				pass
			0x56:
				owner.f38(_s16(a1), s)
			0x57:
				owner.f44(s)
			0x58:
				owner.move_real(Vector2i(a1 << 8, a2 << 8))
				sd.unk2A = b & 0xFF
				return RET_02
			0x59:
				owner.move_rel(Vector2i(s << 8, a1 << 8))
				sd.unk2A = b & 0xFF
				return RET_02
			0x5A:
				owner.move_rel(Vector2i(randi_range(0, maxi(s, 1) - 1) << 8, randi_range(0, maxi(a1, 1) - 1) << 8))
				sd.unk2A = b & 0xFF
				return RET_02
			0x5B:
				owner.move_real(G.link_pos(_s16(a1), owner.get_center()))
				sd.unk2A = b & 0xFF
				return RET_02
			0x5C:
				var area: Array = G.link_area(_s16(a1), owner.get_center())
				var p1: Vector2i = area[0]
				var p2: Vector2i = area[1]
				owner.move_real(Vector2i(p1.x + randi_range(0, maxi(p2.x - p1.x, 1) - 1), p1.y + randi_range(0, maxi(p2.y - p1.y, 1) - 1)))
				sd.unk2A = b & 0xFF
				return RET_02
			0x5D:
				var r = G.lives_find(_s16(a1))
				if r >= 0:
					owner.move_real(G.lives[r].get_center())
					sd.unk2A = b & 0xFF
					return RET_02
			0x5E:
				var i := a1 & 0xFFFF
				var p := Vector2i(GVars.get_arr(null, GVars.POSITION_X, i), GVars.get_arr(null, GVars.POSITION_Y, i))
				owner.move_real(p)
				owner.set_height(GVars.get_arr(null, GVars.POSITION_HEIGHT, i))
				var d := _s8(GVars.get_arr(null, GVars.POSITION_DIRECTION, i))
				sd.stored_dir = d
				owner.set_dir(d)
				sd.unk2A = b & 0xFF
				return RET_02
			0x5F:
				var i := a1 & 0xFFFF
				var p: Vector2i = owner.get_center()
				GVars.set_arr(null, GVars.POSITION_X, i, p.x)
				GVars.set_arr(null, GVars.POSITION_Y, i, p.y)
				GVars.set_arr(null, GVars.POSITION_HEIGHT, i, owner.get_height().x)
				GVars.set_arr(null, GVars.POSITION_DIRECTION, i, owner.get_dir())
			0x60:
				owner.set_height(a1 << 8)
				sd.unk2A = b & 0xFF
				return RET_02
			0x61, 0x69:
				sd.pos2 = Vector2i(a1 << 8, a2 << 8)
				sd.unk30 = s
				sd.unk2A = -1
				return RET_02
			0x62, 0x6A:
				var p: Vector2i = owner.get_center()
				sd.pos2 = p + Vector2i(a1 << 8, a2 << 8)
				sd.unk30 = s
				sd.unk2A = -1
				return RET_02
			0x63, 0x6B:
				sd.pos2 = G.link_pos(_s16(a1), owner.get_center())
				sd.unk30 = s
				sd.unk2A = -1
				return RET_02
			0x64, 0x6C:
				sd.pos2 = G.link_pos(_s16(a1), owner.get_center())
				sd.unk30 = s
				sd.unk2A = b & 0xFF
				return RET_02
			0x65, 0x6D:
				sd.pos2 = G.link_pos(_s16(a1), owner.get_center())
				sd.unk30 = s
				sd.unk2A = randi_range(0, maxi(b & 0xFF, 1) - 1)
				return RET_02
			0x66, 0x67, 0x6E, 0x6F:
				var r = G.lives_find(_s16(a1))
				if r >= 0:
					sd.pos2 = G.lives[r].get_center()
					sd.unk30 = s
					sd.unk2A = b & 0xFF
					return RET_02
			0x71, 0x77, 0x7D, 0x83:
				sd.pos1 = owner.get_center()
				sd.pos2 = Vector2i(a1 << 8, a2 << 8)
				sd.unk2A = _hypot_steps(s) if op == 0x7D or op == 0x83 else s
				return RET_02
			0x72, 0x78, 0x7E, 0x84:
				sd.pos1 = owner.get_center()
				sd.pos2 = sd.pos1 + Vector2i(a1 << 8, a2 << 8)
				sd.unk2A = _hypot_steps(s) if op == 0x7E or op == 0x84 else s
				return RET_02
			0x73, 0x79, 0x7F, 0x85:
				var cap1 := a1 * 2 - 1
				var cap2 := a2 * 2 - 1
				sd.pos1 = owner.get_center()
				sd.pos2 = sd.pos1 + Vector2i((randi_range(0, maxi(cap1, 1) - 1) - s) << 8, (randi_range(0, maxi(cap2, 1) - 1) - a1) << 8)
				sd.unk2A = _hypot_steps(s) if op == 0x7F or op == 0x85 else s
				return RET_02
			0x74, 0x7A, 0x80, 0x86:
				sd.pos1 = owner.get_center()
				sd.pos2 = G.link_pos(_s16(a1), sd.pos1)
				sd.unk2A = _hypot_steps(s) if op == 0x80 or op == 0x86 else s
				return RET_02
			0x75, 0x7B, 0x81, 0x87:
				var cap := a1 * 2 - 1
				sd.pos2 = G.link_pos(_s16(a2), owner.get_center())
				sd.pos2 += Vector2i((randi_range(0, maxi(cap, 1) - 1) - s) << 8, (randi_range(0, maxi(cap, 1) - 1) - s) << 8)
				sd.pos1 = owner.get_center()
				sd.unk2A = _hypot_steps(s) if op == 0x81 or op == 0x87 else s
				return RET_02
			0x76, 0x7C, 0x82, 0x88:
				var r = G.lives_find(_s16(a1))
				if r >= 0:
					sd.pos1 = owner.get_center()
					sd.pos2 = G.lives[r].get_center()
					sd.unk2A = _hypot_steps(s) if op == 0x82 or op == 0x88 else s
					return RET_02
			0x68, 0x70:
				sd.unk48 = a1 << 8
				sd.unk30 = s
				sd.unk2A = -1
				return RET_02
			0x89:
				sd.stored_dir = a1
				owner.set_dir(_s8(a1))
				sd.unk30 = s
				sd.unk2A = b & 0xFF
				return RET_02
			0x8A:
				sd.stored_dir = GDir.transform1(owner.get_dir(), a1 & 0xFF)
				owner.set_dir(sd.stored_dir)
				sd.unk30 = s
				sd.unk2A = b & 0xFF
				return RET_02
			0x8B:
				sd.stored_dir = s
				owner.set_dir(sd.stored_dir)
				sd.unk2A = b & 0xFF
				return RET_02
			0x8C:
				var r = G.lives_find(_s16(a1))
				if r >= 0:
					sd.stored_dir = GDir.transform1(G.lives[r].direction1, s & 0xFF)
					owner.set_dir(sd.stored_dir)
				sd.unk2A = b & 0xFF
				return RET_02
			0x8D:
				sd.stored_dir = GDir.transform1(owner.get_dir(), s & 0xFF)
				owner.set_dir(sd.stored_dir)
				sd.unk2A = b & 0xFF
				return RET_02
			0x8E, 0x8F, 0x90:
				var flag := false
				var p1 := Vector2i.ZERO
				var p2 := Vector2i.ZERO
				match op:
					0x8E:
						var r = G.lives_find(_s16(a1))
						if r >= 0:
							flag = true
							p1 = G.lives[r].get_center()
							p2 = G.lives[r].get_size()
					0x8F:
						var r = G.lives_find(_s16(a1))
						if r >= 0:
							flag = true
							p1 = G.lives[r].get_center()
					0x90:
						flag = true
						p1 = owner.get_center()
						p2 = owner.get_size()
						p1 = G.link_pos(_s16(a1), p1)
				if flag:
					var p3: Vector2i = owner.get_center()
					var p4: Vector2i = owner.get_size()
					var d := GDir.sized_delta8(p3, p4, p1, p2)
					if d == -1:
						d = GDir.sized_delta4(p3, Vector2i.ZERO, p1, Vector2i.ZERO)
					if d == -1:
						d = owner.get_dir()
					sd.stored_dir = GDir.transform1(d, s & 0xFF)
					owner.set_dir(sd.stored_dir)
				sd.unk2A = b & 0xFF
				return RET_02
			0x93, 0x94, 0x95:
				sd.unk2A = 0
				return RET_02
			0x91:
				sd.unk4D = _s8(a1)
				sd.unk2A = 0
				return RET_02
			0x92:
				sd.unk4D = GDir.transform1(owner.get_dir(), a1 & 0xFF)
				sd.unk2A = 0
				return RET_02
			0x97:
				G.camera.shake(s, a1, a2)
			0x98:
				if kind >= 1 and kind <= 3:
					G.camera.follow(kind, owner.get_index())
			0x99:
				if kind >= 1 and kind <= 3:
					G.camera.set_target(owner.get_center())
			0x9A:
				G.camera.follow(1, 0)
			0x9B:
				var id: int = owner.get_index() if owner else -1
				if id >= 0 and kind >= 1 and kind <= 3:
					G.camera.move_follow(1, kind, id, s)
					return RET_02
			0x9C:
				if kind >= 1 and kind <= 3:
					G.camera.move_to(1, owner.get_center(), s)
					return RET_02
			0x9D:
				G.camera.move_follow(1, 1, 0, s)
				return RET_02
			0x9E:
				var id: int = owner.get_index() if owner else -1
				if id >= 0 and kind >= 1 and kind <= 3:
					G.camera.move_follow(2, kind, id, s)
					return RET_02
			0x9F:
				if kind >= 1 and kind <= 3:
					G.camera.move_to(2, owner.get_center(), s)
					return RET_02
			0xA0:
				G.camera.move_follow(2, 1, 0, s)
				return RET_02
			0xA1:
				var id: int = owner.get_index() if owner else -1
				if id >= 0 and kind >= 1 and kind <= 3:
					G.camera.move_follow(3, kind, id, s)
					return RET_02
			0xA2:
				if kind >= 1 and kind <= 3:
					G.camera.move_to(3, owner.get_center(), s)
					return RET_02
			0xA3:
				G.camera.move_follow(3, 1, 0, s)
				return RET_02
			0xA4:
				GVars.reset_arr(sd.local, s)
			0xA5:
				GVars.clear_arr(sd.local, s)
			0xA6:
				GVars.update_imm(sd.local, s, a1, b)
			0xA7:
				GVars.update_var(sd.local, s, _s16(a1), b)
			0xA8:
				GVars.set_arr(sd.local, s, a1 & 0xFFFF, a2)
			0xA9:
				if Dialog.auto:
					print("    SCEN set %s %d,%d at %s" % ["main" if s == 3 else GVars.var_name(s), a1, a2, _where()])
				GVars.scenario_calc(s, a1, a2)
			0xAA:
				var cur := GVars.scenario(s)
				if Dialog.auto:
					print("    SCEN set %s %d,%d (advance) at %s" % [GVars.var_name(s), cur.x, cur.y + 1, _where()])
				GVars.scenario_calc(s, cur.x, cur.y + 1)
			0xAB:
				GVars.set_val(null, GVars.DUNGEON_ENTER, a1)
				GVars.set_val(null, GVars.DUNGEON_RESULT, s)
			0xAC:
				GVars.set_val(null, GVars.PLAYER_KIND, s)
			0xAD:
				Story.unlock_friend_area(GData.fa_of_map(s))
			0xAE:
				GVars.rescue_set_order(s, (b & 0xFF) > 0)
			0xAF:
				GVars.rescue_set_job(s, (b & 0xFF) > 0)
			0xB0:
				GVars.rescue_set_conquered(s, (b & 0xFF) > 0)
				Story.on_rescue_conquered(s)
			0xB1:
				Story.set_misc_flag(s, (b & 0xFF) > 0)
			0xB2:
				Story.achievement(s)
			0xB3:
				if GVars.judge_imm(null, s, a1, GVars.JUDGE_EQ):
					sd.si.ptr = _find_label(b & 0xFF)
			0xB4:
				if GVars.judge_imm(sd.local, _s16(a1), a2, b & 0xFF):
					sd.si.ptr = _find_label(s)
			0xB5:
				if GVars.judge_var(sd.local, _s16(a1), _s16(a2), b & 0xFF):
					sd.si.ptr = _find_label(s)
			0xB6:
				if GVars.get_arr(sd.local, _s16(a1), a2 & 0xFFFF) != 0:
					sd.si.ptr = _find_label(s)
			0xB7:
				if GVars.flag_judge(GVars.arr_sum(sd.local, _s16(a1)), a2, b & 0xFF):
					sd.si.ptr = _find_label(s)
			0xB8:
				if GVars.before(s, a1, a2):
					sd.si.ptr = _find_label(b & 0xFF)
			0xB9:
				if GVars.equal(s, a1, a2):
					sd.si.ptr = _find_label(b & 0xFF)
			0xBA:
				if GVars.after(s, a1, a2):
					sd.si.ptr = _find_label(b & 0xFF)
			0xBB:
				if GVars.quest(s):
					sd.si.ptr = _find_label(b & 0xFF)
			0xBC:
				if Story.cutscene_flag(s):
					sd.si.ptr = _find_label(b & 0xFF)
			0xBD:
				if Story.friend_area_unlocked(GData.fa_of_map(_s16(a1))):
					sd.si.ptr = _find_label(b & 0xFF)
			0xBF:
				if G.has_item(s):
					sd.si.ptr = _find_label(b & 0xFF)
			0xBE:
				if kind == 1 and G.lives[index].is_starter():
					sd.si.ptr = _find_label(b & 0xFF)
			0xC0, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xCB:
				var val := 0
				match op:
					0xC0:
						val = GVars.get_val(sd.local, s)
					0xC1:
						val = GVars.flag_calc(GVars.get_val(sd.local, s), a1, b & 0xFF)
					0xC2:
						val = GVars.flag_calc(GVars.get_val(sd.local, s), GVars.get_val(sd.local, _s16(a1)), b & 0xFF)
					0xC3:
						val = randi_range(0, maxi(s, 1) - 1)
					0xC4:
						val = GVars.get_arr(null, s, 0)
					0xC5:
						val = GVars.get_arr(null, s, 1)
					0xC6:
						val = G.red_species_of_kind(_s16(a1))
					0xC7:
						val = owner.get_dir()
					0xCA:
						var p: Vector2i = owner.get_center()
						val = GDir.vec_dir8(G.link_pos(_s16(a1), p) - p)
					0xC8:
						var r = G.lives_find(_s16(a1))
						if r >= 0:
							var p1: Vector2i = owner.get_center()
							var p2: Vector2i = owner.get_size()
							val = GDir.sized_delta8(p1, p2, G.lives[r].get_center(), G.lives[r].get_size())
							if val == -1:
								val = GDir.sized_delta4(p1, Vector2i.ZERO, G.lives[r].get_center(), Vector2i.ZERO)
						else:
							val = -1
					0xC9:
						var r = G.lives_find(_s16(a1))
						if r >= 0:
							var p1: Vector2i = owner.get_center()
							var p2: Vector2i = owner.get_size()
							val = GDir.sized_delta8(p1, p2, G.lives[r].get_center(), Vector2i.ZERO)
							if val == -1:
								val = GDir.sized_delta4(p1, Vector2i.ZERO, G.lives[r].get_center(), Vector2i.ZERO)
						else:
							val = -1
					0xCB:
						val = G.item_space(s)
				sd.si.ptr = _resolve_jump(val)
			0xCF:
				sd.branch = GVars.get_val(sd.local, s)
				while int(GData.cmd(sd.si.ptr)[0]) == 0xD0:
					if int(GData.cmd(sd.si.ptr)[2]) == sd.branch:
						return RET_02
					sd.si.ptr.y += 1
				if int(GData.cmd(sd.si.ptr)[0]) == 0xD1:
					sd.branch = -1
					return RET_02
			0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8:
				var out = c[5]
				var choices: Array = []
				sd.branch = 0
				if op >= 0xD6:
					var disc := GVars.get_val(sd.local, _s16(a2))
					while int(GData.cmd(sd.si.ptr)[0]) == 0xD0:
						var cc := GData.cmd(sd.si.ptr)
						if int(cc[2]) == disc:
							out = cc[5]
						sd.si.ptr.y += 1
						sd.branch += 1
					while int(GData.cmd(sd.si.ptr)[0]) == 0xD1:
						if out == null:
							out = GData.cmd(sd.si.ptr)[5]
						sd.si.ptr.y += 1
						sd.branch += 1
				if out == null:
					out = ""
				while int(GData.cmd(sd.si.ptr)[0]) == 0xD9:
					choices.append(str(GData.cmd(sd.si.ptr)[5]))
					sd.si.ptr.y += 1
				if choices.is_empty():
					continue
				var ttype: int = G.text.T_INSTANT
				if op == 0xD4 or op == 0xD7:
					ttype = G.text.T_QUIET
				elif op == 0xD5 or op == 0xD8:
					ttype = G.text.T_NPC
				G.text.ask(choices, s, (b & 0xFF) > 0, ttype, _s16(a1), str(out))
				if _check_lock(1):
					G.set_player_mode(11)
					return RET_02
			0xDA:
				if _check_lock(1):
					return RET_02
			0xDB:
				sd.unk2A = s
				return RET_02
			0xDC:
				sd.unk2A = s + randi_range(0, maxi(a1 - s, 1) - 1)
				return RET_02
			0xDD, 0xDE, 0xDF, 0xE0, 0xE1, 0xE2:
				return RET_02
			0xE3:
				sd.branch = s
				if _check_lock(s):
					return RET_02
			0xE4:
				G.lock_jump_zero(s)
			0xE5:
				sd.branch = s
				if _lock_cond(s, b):
					return RET_02
			0xE6:
				sd.saved = sd.si.copy()
				sd.si.ptr = _find_label(s)
			0xE7:
				sd.si.ptr = _find_label(s)
			0xE8:
				sd.saved = sd.si.copy()
				sd.si.ptr = GData.fn_script(s)
				sd.si.ptr2 = sd.si.ptr
			0xE9:
				sd.si.ptr = GData.fn_script(s)
				sd.si.ptr2 = sd.si.ptr
			0xEA:
				sd.saved = sd.si.copy()
				var grp := _grp(c)
				var sec := _sec(c)
				var p: Vector2i = G.station_script(G.station_map, grp, sec)
				sd.si.ptr = p
				sd.si.ptr2 = p
				sd.si.group = grp
				sd.si.sector = sec
			0xEB:
				var grp := _grp(c)
				var sec := _sec(c)
				var p: Vector2i = G.station_script(G.station_map, grp, sec)
				sd.si.ptr = p
				sd.si.ptr2 = p
				sd.si.group = grp
				sd.si.sector = sec
			0xEC:
				G.station_map = G.adjusted_map(_s16(GVars.get_val(sd.local, s)))
				if G.station_script(G.station_map, 0, 0) == GData.NULL_PTR:
					G.station_map = G.adjusted_map(GData.map_id("MAP_TEAM_BASE"))   # safety: never fall through
				if Dialog.auto:
					print("    EXEC_MAP_VAR var%d -> map %d station %s" % [s, G.station_map, G.station_script(G.station_map, 0, 0)])
				G.cancel_all_entities()
				G.map_execute_enter(G.station_map)
			0xED:
				sd.saved = ScriptInfo.new()
			0xEE:
				if sd.saved.ptr == GData.NULL_PTR:
					return RET_00
				sd.si = sd.saved
				sd.saved = ScriptInfo.new()
			0xEF:
				return RET_00
			0xF0:
				return RET_01
			0xF1:
				return RET_04
			0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0x00:
				pass
			_:
				pass
	return RET_02

func _fn_info(id: int) -> Dictionary:
	return {"ptr": GData.fn_script(id), "state": 2, "group": group, "sector": sector}

## CMD 0x2D: set up a portrait slot / format buffer from an entity.
func _portrait_setup(mode: int, slot: int, a1: int) -> void:
	match mode:
		0:
			G.text.reset_portrait(slot)
		1:
			if kind == 1:
				G.text.portrait_from_kind(slot, G.lives[index].kind_id, 0)
		2:
			if unkC.x == 1:
				G.text.portrait_from_kind(slot, G.lives[unkC.y].kind_id, 0)
		3:
			var r = G.lives_find(_s16(a1))
			if r >= 0:
				G.text.portrait_from_kind(slot, G.lives[r].kind_id, 0)
		4:
			if kind == 1:
				G.text.portrait_from_kind(slot, G.lives[index].kind_id, 1)
		5:
			if unkC.x == 1:
				G.text.portrait_from_kind(slot, G.lives[unkC.y].kind_id, 1)
		6:
			var r = G.lives_find(_s16(a1))
			G.text.portrait_from_kind(slot, G.lives[r].kind_id if r >= 0 else _s16(a1), 1)
		7:
			if kind == 1:
				G.text.portrait_from_kind(slot, G.lives[index].kind_id, 2)
		8:
			if unkC.x == 1:
				G.text.portrait_from_kind(slot, G.lives[unkC.y].kind_id, 2)
		9:
			var r = G.lives_find(_s16(a1))
			G.text.portrait_from_kind(slot, G.lives[r].kind_id if r >= 0 else _s16(a1), 2)
		10:
			var o := 0
			match _s16(a1):
				0:
					o = 1
				2:
					o = -1
			G.text.format_args[slot] = G.dungeon_floor_count(_s16(a1)) + o
