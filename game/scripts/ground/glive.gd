class_name GLive
extends RefCounted
## One "lives" actor (ground_lives.c GroundLive): a Pokémon on a ground map with its own script runner.
## Positions are 24.8 fixed point: p144 = hitbox top-left, p14C = bottom-right, size = unkC, half = unk14.

var G
var id := 0
var kind_id := -1           # unk2 (-1 = free slot)
var group := 0
var sector := 0
var species := ""           # our species key
var red_species := 0
var size := Vector2i.ZERO   # unkC
var half := Vector2i.ZERO   # unk14
var dir0 := 0               # unk1C
var pos0 := Vector2i.ZERO   # unk20
var b_from := Vector2i(-0x7FFFFFF, -0x7FFFFFF)
var b_to := Vector2i(0x7FFFFFF, 0x7FFFFFF)
var action: GAction
var flags := 0
var ctrl := {"s0": 0, "s4": 0, "t10": -1, "t14": 0, "t8": 0, "dC": -1}   # unk120 player controller
var follow_idx := 0         # unk13C
var event_id := -1          # unk13E
var fa_dialog := 0
var direction1 := 0
var p144 := Vector2i.ZERO
var p14C := Vector2i.ZERO
var p154 := Vector2i.ZERO   # (height, unk)
var dir_dirty := true       # directionRelated
var direction2 := -1
var anim_speed := 0x300     # unk15E
var anim_kind := 1          # unk160
var walk_t := 0             # unk164
var anim := 0x807           # unk168
var emote_req := 0          # unk16A
var emote_arg := 0          # unk16C
var sprite: GSprite
var display_name := ""

func _init(ground, slot: int) -> void:
	G = ground
	id = slot

# ------------------------------------------------------------------ callbacks (CallbackData)
func get_index() -> int:
	return id

func get_size() -> Vector2i:
	return size

func get_center() -> Vector2i:
	return p144 + half

func get_height() -> Vector2i:
	return p154

func get_dir() -> int:
	return direction1

func get_flags() -> int:
	return flags

func set_hitbox_pos(p) -> void:
	if p != null:
		p144 = p - half
		p14C = p + half
	else:
		p144 = pos0 - half
		p14C = pos0 + half
		p154 = Vector2i.ZERO
		if direction1 != dir0:
			dir_dirty = true
		direction1 = dir0

func set_bounds(a: Vector2i, b: Vector2i) -> void:
	b_from = a
	b_to = b

func move_real(p: Vector2i) -> int:
	var a := p - half
	var b := p + half
	if a.x < b_from.x or b.x >= b_to.x or a.y < b_from.y or b.y >= b_to.y:
		return 1
	var r := _collide(a, b)
	if r != 0:
		return r
	p144 = a
	p14C = b
	return 0

func set_height(h: int) -> void:
	p154.x = h

func set_dir(d: int) -> void:
	if d != -1:
		direction1 = d
		if direction2 != direction1:
			dir_dirty = true

func set_event_index(a1: int) -> void:
	_event_index(a1)

func f38(a1: int, a2: int) -> void:
	emote_req = 448 if a1 == 0 else a1
	emote_arg = a2

func set_flags(f: int) -> void:
	G.lives_set_flags(id, f)

func clear_flags(f: int) -> void:
	G.lives_clear_flags(id, f)

func f44(_a: int) -> void:
	pass

func move_rel(d: Vector2i) -> int:
	return _move_rel(d)

func sprite_busy_4c() -> bool:
	if dir_dirty:
		return true
	return sprite.anim_busy() if sprite else false

func sprite_busy_50() -> bool:
	if emote_req != 0:
		return true
	return sprite != null and sprite.emote >= 0

func is_starter() -> bool:
	return red_species in Story.STARTERS_RED

# ------------------------------------------------------------------ movement / collision
func _tiles(a: Vector2i, b: Vector2i) -> Array:
	var p1 := Vector2i(a.x >> 11, a.y >> 11)
	var t := Vector2i((b.x - 1) >> 11, (b.y - 1) >> 11)
	return [p1, t - p1 + Vector2i.ONE]

## sub_80A9488
func _collide(a: Vector2i, b: Vector2i) -> int:
	var tt := _tiles(a, b)
	if flags & 1 and G.map_collide(tt[0], tt[1], 0x80):
		return 1
	if flags & 2 and G.map_collide(tt[0], tt[1], 0x40):
		return 1
	if flags & 4 and G.lives_collision(id, 4, a, b) >= 0:
		return 4
	if flags & 8 and G.objects_collision(4, a, b) >= 0:
		return 8
	if flags & 0x10 and G.events_find(0x40, a, b) >= 0:
		return 0x10
	return 0

## sub_80A95AC: like _collide, but touching a talkable actor starts its talk script.
func _collide_talk(a: Vector2i, b: Vector2i) -> int:
	var tt := _tiles(a, b)
	if flags & 1 and G.map_collide(tt[0], tt[1], 0x80):
		return 1
	if flags & 2 and G.map_collide(tt[0], tt[1], 0x40):
		return 1
	if flags & 4:
		var id2: int = G.lives_collision(id, 0x44, a, b)
		if id2 >= 0:
			var o = G.lives[id2]
			if o.flags & 0x40:
				if o.flags & 0x200:
					o.direction1 = GDir.transform1(direction1, GDir.T_FLIP)
				if G.lives_player_talk(id, id2):
					return 2
			return 1
	if flags & 8:
		var id2: int = G.objects_collision(0x44, a, b)
		if id2 >= 0:
			if (G.objects[id2].flags & 0x40) and G.object_player_talk(id, id2):
				return 2
			return 1
	if flags & 0x10:
		var id2: int = G.events_find(0x40, a, b)
		if id2 >= 0:
			if G.event_player_trigger(id, id2):
				return 2
			return 1
	return 0

func _clamp_box(a: Vector2i, b: Vector2i) -> Array:
	var changed := false
	if a.x < b_from.x:
		a.x = b_from.x; b.x = b_from.x + size.x; changed = true
	elif b.x >= b_to.x:
		a.x = b_to.x - size.x; b.x = b_to.x; changed = true
	if a.y < b_from.y:
		a.y = b_from.y; b.y = b_from.y + size.y; changed = true
	elif b.y >= b_to.y:
		a.y = b_to.y - size.y; b.y = b_to.y; changed = true
	return [a, b, changed]

## sub_80A9F94
func _move_rel(d: Vector2i) -> int:
	var r := _clamp_box(p144 + d, p14C + d)
	var c := _collide(r[0], r[1])
	if c != 0:
		_water_check()
		return c
	p144 = r[0]
	p14C = r[1]
	_water_check()
	return 1 if r[2] else 0

## sub_80AA074 (player step)
func _move_player(d: Vector2i) -> int:
	var r := _clamp_box(p144 + d, p14C + d)
	var ret := _collide_talk(r[0], r[1])
	if ret == 0:
		p144 = r[0]
		p14C = r[1]
		if flags & 0x10:
			var e: int = G.events_find(0x20, p144, p14C)
			if e >= 0:
				if event_id != e and G.event_player_trigger(id, e):
					event_id = e
					ret = 2
			else:
				event_id = -1
	return ret

## sub_80AAF68: shallow water hides the shadow
func _water_check() -> void:
	if flags & 0x4000:
		var tt := _tiles(p144, p14C)
		if G.map_collide(tt[0], tt[1], 0x01):
			G.lives_clear_flags(id, 0x1000000)
		else:
			G.lives_set_flags(id, 0x1000000)

# ------------------------------------------------------------------ animation (sub_80A9750)
const EVENT_ANIMS := [-1, 0x800, 0x300, 0x300, 0x807, 0x800, 0x805, 0x302, 0x306, 0x80B, 0x307, 0x1006, 0x1002,
	0x1001, 0x1008, 0x100C, 0x1009, 0x100A, 0x1003, 0x1004, 0x803, 0x804, 0x100D, 0x100E, 0x100F, 0x1010, 0x1011,
	0x1012, 0x1013, 0x1014, 0x80D, 0x80E, 0x80F, 0x810, 0x811, 0x812, 0x813, 0x814, 0x80D, 0x100E, 0x100F, 0x1010,
	0x1011, 0x812, 0x1013, 0x1014, 0x1015, 0x1016, 0x1017, 0x818, 0x1019, 0x81A, 0x81B]
const IDLE_LOOP := [12, 15, 22, 41, 42, 49, 72, 73, 74, 81, 82, 91, 92, 93, 109, 110, 116, 117, 118, 119, 130, 133, 137,
	142, 144, 145, 146, 150, 151, 165, 166, 169, 170, 171, 187, 188, 189, 190, 191, 193, 198, 230, 232, 236, 248, 251,
	255, 258, 271, 275, 276, 292, 294, 303, 304, 309, 316, 317, 332, 343, 344, 345, 346, 355, 358, 362, 363, 364, 365,
	368, 369, 374, 376, 377, 378, 379, 381, 383, 386, 390, 395, 396, 397, 398, 402, 403, 406, 408, 409, 410, 200, 201,
	202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224,
	225, 226, 412, 413, 414, 415, 416, 417, 418, 419]
const IDLE_307 := [50, 51, 53, 58, 59, 98, 99, 134, 135, 161, 162, 164, 252, 277, 286, 287, 323, 326, 338, 339, 354,
	359, 360, 391, 401]

func _event_index(a1: int) -> void:
	var f1 := a1 & 0xFF
	var f2 := a1 & 0xF00
	if f1 != 0:
		anim_kind = f1
	if f2 != 0:
		anim_speed = f2
	var r2 := 0
	if anim_kind == 1:
		if a1 == 0x1000:
			walk_t = 4
			r2 = 0x800
		else:
			r2 = 0x800 if walk_t > 0 else 0x807
	elif anim_kind == 2:
		if a1 == 0x1000:
			walk_t = 4
			r2 = 0x800
		elif walk_t > 0:
			r2 = 0x800
		elif red_species in IDLE_LOOP:
			r2 = 0x807
		elif red_species in IDLE_307:
			r2 = 0x307
		elif red_species == 65:
			r2 = 0x300 if (anim != 0x807 and anim != 0x307) else 0x807
		else:
			r2 = 0x300
	else:
		r2 = EVENT_ANIMS[anim_kind] if anim_kind < EVENT_ANIMS.size() else 0x807
	if not (r2 & 0x700):
		match anim_speed:
			0x100:
				r2 |= 0x300
			0x200:
				r2 |= 0x100
			0x400:
				r2 |= 0x200
			0x800:
				r2 |= 0x400
	if anim != r2:
		anim = r2
		dir_dirty = true
	elif anim & 0x1000:
		dir_dirty = true

# ------------------------------------------------------------------ player control (sub_809CDC8 + sub_80AAAE8)
func ctrl_mode() -> int:
	return ctrl.s4 if ctrl.s4 != 0 else ctrl.s0

func set_ctrl(a1: int) -> void:     # sub_809CD8C
	if a1 == 5:
		ctrl = {"s0": 5, "s4": 0, "t10": -1, "t14": 0, "t8": 0, "dC": -1}
	elif ctrl.s4 != a1:
		ctrl.s4 = a1
		ctrl.t10 = -1
		ctrl.t14 = 0

func _controller() -> Array:          # returns [result, r6 action, dir]
	match int(ctrl.s0):
		1:
			if flags & 0x2000:
				ctrl = {"s0": 2, "s4": 0, "t10": -1, "t14": 0, "t8": 0, "dC": -1}
		2:
			if not (flags & 0x2000):
				ctrl = {"s0": 1, "s4": 0, "t10": -1, "t14": 0, "t8": 0, "dC": -1}
	var r8 := ctrl_mode()
	match r8:
		1:
			var inp: Dictionary = G.input_state()
			var held_dir: int = inp.dir
			var b_held: bool = inp.b_held
			var r6 := 7
			if held_dir != -1:
				ctrl.t10 = 0 if b_held else -1
			elif inp.b_pressed:
				ctrl.t10 = 0x14
			elif ctrl.t10 > 1:
				ctrl.t10 -= 1
				if not b_held:
					return [5, 0x13, -1]
			else:
				ctrl.t10 = -1
			if inp.a_pressed:
				r6 = 10
			elif ctrl.t10 == 0:
				r6 = 8
			elif inp.menu_pressed:
				return [5, 0x13, -1]
			return [ctrl.s0, r6, held_dir]
		5:
			var r: Array = G.text.result()
			if r[0]:
				ctrl = {"s0": 1, "s4": ctrl.s4, "t10": -1, "t14": 0, "t8": 0, "dC": -1}
				match int(r[1]):
					2:
						ctrl.s0 = 4
						G.request_friend_areas(30)
						return [4, 1, -1]
					1, 3:
						ctrl.s0 = 4
						return [4, 1, -1]
					4:
						ctrl.s0 = 4
						G.formation_changed()
						return [4, 1, -1]
				G.lock_jump_zero(2)
		6, 7:
			var r: Array = G.text.result()
			if r[0]:
				ctrl.s0 = 1
				return [1, 0, -1]
		2:
			if ctrl.t8 >= 1:
				ctrl.t8 -= 1
				return [r8, 9, ctrl.dC]
			var inp: Dictionary = G.input_state()
			var d := -1
			if inp.up:
				d = 4
			elif inp.down:
				d = 0
			ctrl.dC = d
			if d != -1:
				ctrl.t8 = 0x20
			return [r8, 9, d]
	return [r8, 0, -1]

func _player_act(a1: int, d: int) -> void:      # sub_80AAAE8
	var new_anim := -1
	anim_speed = 0x300
	anim_kind = 1
	if d != -1:
		direction1 = d
	match a1:
		2:
			walk_t = 0
			new_anim = 0x807
			_water_check()
		1:
			walk_t = 0
			new_anim = 0x300
			_water_check()
		6, 7, 8:
			if d != -1:
				var unk := 0
				walk_t = 4
				var n := 1
				match a1:
					6:
						new_anim = 0x900; n = 1
					7:
						new_anim = 0x800; n = 2
					8:
						new_anim = 0xA00; n = 4
				var v := GDir.vec(d, 0x100)
				for i in n:
					unk = _move_player(v)
					if unk == 2:
						break
					if unk != 1:
						continue
					unk = _move_player(Vector2i(0, v.y))
					if unk == 2:
						break
					if unk != 1:
						continue
					unk = _move_player(Vector2i(v.x, 0))
					if unk == 2:
						break
				if unk == 2:
					new_anim = -1
				_water_check()
			else:
				walk_t = 0
				new_anim = 0x807
				_water_check()
		3, 4, 5:
			if d != -1:
				walk_t = 4
				var n := 1
				match a1:
					3:
						new_anim = 0x900; n = 1
					4:
						new_anim = 0x800; n = 2
					5:
						new_anim = 0xA00; n = 4
				var v := GDir.vec(d, 0x100)
				for i in n:
					if _move_rel(v) != 0 and _move_rel(Vector2i(0, v.y)) != 0 and _move_rel(Vector2i(v.x, 0)) != 0:
						break
			else:
				walk_t = 0
				new_anim = 0x807
		9:
			G.lives_meta.dir28 = d if (flags & 0x1000) else -1
			walk_t = 0
			new_anim = 0x800
			direction1 = 4
			if d != -1 and _move_player(GDir.vec(d, 0x100)) == 2:
				new_anim = -1
		10:
			_talk_ahead(direction1)
		0x13:
			G.text.special(G.SP_FRIEND_MENU, 0, 0, null)
			set_ctrl(5)
		_:
			_water_check()
	if new_anim != -1 and new_anim != anim:
		dir_dirty = false
		anim = new_anim
		direction2 = direction1
		if sprite:
			sprite.play(anim, direction1)
		return
	if dir_dirty or direction2 != direction1:
		dir_dirty = false
		direction2 = direction1
		if sprite:
			sprite.play(anim, direction1)

## sub_80AA3F8: A button - talk to whoever is in front (also across a counter).
func _talk_ahead(d: int) -> bool:
	var v := GDir.vec(d, 0x100)
	if _talk_probe(0xC, p144 + v, p14C + v) == 3:
		return true
	var p6 := Vector2i(int(((size.x / 2) + 0x200) * v.x / 256), int(((size.y / 2) + 0x200) * v.y / 256))
	var p4 := get_center() + p6 - Vector2i(768, 768)
	var p5 := p4 + Vector2i(0x600, 0x600)
	var lim1 = [0x600, 0x441][d & 1]
	var lim2 = [0x2000, 0x16B1][d & 1]
	var lim3 = [0x800, 0x5AC][d & 1]
	var r7 := 0
	var i := 0x200
	while i < lim1:
		if p4.x < b_from.x or p5.x >= b_to.x or p4.y < b_from.y or p5.y >= b_to.y:
			return false
		r7 = _talk_probe(0xC, p4, p5)
		if r7 == 3:
			return true
		p4 += v; p5 += v
		i += 0x100
		if r7 == 6:
			break
	if r7 != 6:
		return false
	while i < lim2:
		if p4.x < b_from.x or p5.x >= b_to.x or p4.y < b_from.y or p5.y >= b_to.y:
			return false
		r7 = _talk_probe(4, p4, p5)
		if r7 == 3:
			return true
		p4 += v; p5 += v
		i += 0x100
		if r7 != 6:
			break
	if r7 == 6:
		return false
	i = 0
	while i < lim3:
		if p4.x < b_from.x or p5.x >= b_to.x or p4.y < b_from.y or p5.y >= b_to.y:
			return false
		r7 = _talk_probe(4, p4, p5)
		if r7 == 3:
			return true
		if r7 == 6:
			return false
		p4 += v; p5 += v
		i += 0x100
	return false

## sub_80AA2BC
func _talk_probe(f: int, a: Vector2i, b: Vector2i) -> int:
	if f & 4:
		var id2: int = G.lives_collision(id, 0x80, a, b)
		if id2 >= 0:
			var o = G.lives[id2]
			if o.flags & 0x200:
				o.direction1 = GDir.transform1(direction1, GDir.T_FLIP)
			if G.lives_player_talk(id, id2):
				return 3
	if f & 8:
		var id2: int = G.objects_collision(0x80, a, b)
		if id2 >= 0 and G.object_player_talk(id, id2):
			return 3
	var tt := _tiles(a, b)
	if G.map_collide(tt[0], tt[1], 0x10):
		return 6
	return 0
