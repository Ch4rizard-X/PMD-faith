class_name GCamera
extends RefCounted
## code_809D148.c: the ground camera. Follows an entity (lives/object/effect) or a fixed point, optionally
## moving there at a speed (mode 1: clamp step, 2: interpolate frames, 3: frames from distance), plus shake.

var G
var target_kind := 0        # unk0: 0 fixed point, 1 lives, 2 object, 3 effect
var target_id := -1         # unk4
var mode := 0               # unk8
var speed := 0              # unkC
var frames := 0             # unk10
var cur := Vector2i.ZERO    # unk14 (center, 24.8)
var goal := Vector2i.ZERO   # unk1C
var shake_kind := 0         # unk24
var shake_amp := 0          # unk28
var shake_period := 0       # unk2C
var shake_t := 0
var shake_off := Vector2i.ZERO
var top_left := Vector2i.ZERO   # unk3C (GBA screen px)
var valid := false

func _init(ground) -> void:
	G = ground

func reset() -> void:
	top_left = Vector2i.ZERO
	valid = false
	target_kind = 0
	mode = 0
	goal = Vector2i.ZERO
	speed = 0
	frames = 0
	target_id = -1
	shake_kind = 0
	shake_amp = 0
	shake_period = 0
	shake_t = 0
	shake_off = Vector2i.ZERO

func shake(k: int, amp: int, period: int) -> void:
	if shake_kind != k:
		shake_kind = k
		shake_t = 0
		shake_off = Vector2i.ZERO
	shake_amp = amp
	shake_period = period

func set_target(p: Vector2i) -> void:
	target_kind = 0
	mode = 0
	goal = p

func follow(kind: int, id: int) -> void:
	target_kind = kind
	mode = 0
	target_id = id

func move_to(m: int, p: Vector2i, spd: int) -> void:
	target_kind = 0
	mode = m
	if m == 2:
		frames = spd
	else:
		speed = spd
	cur = cur if valid else p
	goal = p

func move_follow(m: int, kind: int, id: int, spd: int) -> void:
	target_kind = kind
	mode = m
	target_id = id
	if m == 2:
		frames = spd
	else:
		speed = spd

func moving() -> bool:
	return mode != 0

func _entity_center(kind: int, id: int):
	match kind:
		1:
			return G.lives[id].get_center() if id >= 0 and id < G.lives.size() and G.lives[id].kind_id != -1 else null
		2:
			return G.objects[id].get_center() if id >= 0 and id < G.objects.size() and G.objects[id].kind != -1 else null
		3:
			return G.effects[id].get_center() if id >= 0 and id < G.effects.size() and G.effects[id].kind != -1 else null
	return null

func update() -> void:
	if target_kind >= 1 and target_kind <= 3:
		var c = _entity_center(target_kind, target_id)
		if c == null:
			target_kind = 0
		else:
			goal = c
	match mode:
		1:
			var d := goal - cur
			d = Vector2i(clampi(d.x, -speed, speed), clampi(d.y, -speed, speed))
			if d == Vector2i.ZERO:
				mode = 0
			else:
				cur += d
		3:
			var dx := (goal.x - cur.x) / 256
			var dy := (goal.y - cur.y) / 256
			frames = int(sqrt(float(dx * dx + dy * dy)) * 256.0) / maxi(speed, 1)
			if frames <= 0:
				frames = 1
			mode = 2
			_interp_step()
		2:
			_interp_step()
		_:
			cur = goal
	match shake_kind:
		1:
			shake_t -= 1
			if shake_t <= 0:
				shake_t = 4
				shake_off = Vector2i(randi_range(-2, 1) << 10, randi_range(-2, 1) << 10)
		2:
			shake_t -= 1
			if shake_t <= 0:
				shake_t = shake_period
				shake_off = Vector2i((randi_range(-2, 1) * shake_amp) << 8, (randi_range(-2, 1) * shake_amp) << 8)
		_:
			shake_off = Vector2i.ZERO
	var b1: Vector2i = G.bounds_a + Vector2i(0x7800, 0x5000)
	var b2: Vector2i = G.bounds_b - Vector2i(0x7800, 0x5000)
	if b1.x > b2.x:
		b2.x = b1.x
	if b1.y > b2.y:
		b2.y = b1.y
	var r2 := clampi(cur.x + shake_off.x - 0x80, b1.x, b2.x - 1)
	var r3 := clampi(cur.y + shake_off.y - 2944, b1.y, b2.y - 1)
	top_left = Vector2i((r2 - 30976) / 256, (r3 - 20480) / 256)
	valid = true

func _interp_step() -> void:
	var w := frames + 1
	cur = Vector2i(int((frames * cur.x + goal.x) / w), int((frames * cur.y + goal.y) / w))
	frames -= 1
	if frames <= 0:
		mode = 0

## Unclamped view centre for our wider screen: Ground._render re-clamps against the map size.
func top_left_px() -> Vector2i:
	var c := cur + shake_off
	return Vector2i((c.x - 0x80 - 30976) / 256, (c.y - 2944 - 20480) / 256)
