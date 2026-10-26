class_name GDir
extends RefCounted
## direction_util.c: 0 S, 1 SE, 2 E, 3 NE, 4 N, 5 NW, 6 W, 7 SW (screen y grows downwards).

const VEC := [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1)]
enum { S, SE, E, NE, N, NW, W, SW }
enum { T_NONE, T_SPINRIGHT1, T_SPINLEFT1, T_SPINRIGHT2, T_SPINLEFT2, T_FLIP, T_RAND_SOFT_CARD, T_RAND_SOFT, T_RAND_CARD, T_RAND, T_10, T_11 }

static func vec(dir: int, speed: int) -> Vector2i:
	if dir < 0 or dir > 7:
		return Vector2i.ZERO
	return VEC[dir] * speed

static func transform1(d: int, t: int) -> int:
	match t:
		T_SPINRIGHT1:
			return (d + 7) & 7 if d >= 0 else d
		T_SPINLEFT1:
			return (d + 1) & 7 if d >= 0 else d
		T_SPINRIGHT2:
			return (d + 6) & 7 if d >= 0 else d
		T_SPINLEFT2:
			return (d + 2) & 7 if d >= 0 else d
		T_FLIP:
			return (d + 4) & 7 if d >= 0 else d
		T_RAND_SOFT_CARD:
			if d & 1:
				return (d + 7 + randi_range(0, 1) * 2) % 8
			return (d + 6 + randi_range(0, 2) * 2) % 8
		T_RAND_SOFT:
			return (d + 7 + randi_range(0, 2)) % 8
		T_RAND_CARD:
			return randi_range(0, 7) & ~1
		T_RAND:
			return randi_range(0, 7)
	return d

static func step_towards(d1: int, d2: int) -> int:     # sub_8002B04
	if d2 == -1:
		return d1
	var n := ((d2 + 8) - d1) % 8
	if n != 0:
		if n <= 3:
			n = (d1 + 1) % 8
		else:
			n = (d1 + 7) % 8
		return n
	return d1

static func transform2(d1: int, d2: int, t: int) -> int:
	if d1 == d2:
		return d1
	match t:
		T_SPINRIGHT1:
			return (d1 + 7) & 7 if d1 >= 0 else d1
		T_SPINLEFT1:
			return (d1 + 1) & 7 if d1 >= 0 else d1
		T_SPINRIGHT2:
			return (d1 + 6) & 7 if d1 >= 0 else d1
		T_SPINLEFT2:
			return (d1 + 2) & 7 if d1 >= 0 else d1
		T_11:
			return step_towards(step_towards(d1, d2), d2)
		T_10:
			return step_towards(d1, d2)
	return d1

static func vec_dir8(p: Vector2i) -> int:
	var ax := absi(p.x)
	var ay := absi(p.y)
	if p.x < 0:
		if p.y < 0:
			if ay > ax * 2:
				return N
			if ax <= ay * 2:
				return NW
			return W
		if ay <= ax * 2:
			if ax > ay * 2:
				return W
			return SW
	elif p.x > 0:
		if p.y < 0:
			if ay > ax * 2:
				return N
			if ax <= ay * 2:
				return NE
			return E
		if ay > ax * 2:
			return S
		if ax > ay * 2:
			return E
		return SE
	else:
		if p.y < 0:
			return N
		if p.y < 1:
			return -1
	return S

static func vec_dir4(p: Vector2i) -> int:
	var ax := absi(p.x)
	var ay := absi(p.y)
	if p.x < 0:
		if p.y < 0:
			return N if ay > ax else W
		if ay <= ax:
			return W
	elif p.x > 0:
		if p.y < 0:
			return N if ay > ax else E
		return S if ay > ax else E
	else:
		if p.y < 0:
			return N
		if p.y < 1:
			return -1
	return S

static func _sized(p1: Vector2i, p2: Vector2i, p3: Vector2i, p4: Vector2i) -> Vector2i:
	var n := p3 - p1
	if n.x >= 0:
		n.x = maxi(n.x + 1 - int((p2.x + p4.x) / 2), 0)
	else:
		n.x = mini(n.x - 1 + int((p2.x + p4.x) / 2), 0)
	if n.y >= 0:
		n.y = maxi(n.y + 1 - int((p2.y + p4.y) / 2), 0)
	else:
		n.y = mini(n.y - 1 + int((p2.y + p4.y) / 2), 0)
	return n

static func sized_delta8(p1: Vector2i, p2: Vector2i, p3: Vector2i, p4: Vector2i) -> int:
	return vec_dir8(_sized(p1, p2, p3, p4))

static func sized_delta4(p1: Vector2i, p2: Vector2i, p3: Vector2i, p4: Vector2i) -> int:
	return vec_dir4(_sized(p1, p2, p3, p4))

static func from_input(up: bool, down: bool, left: bool, right: bool) -> int:
	if up:
		return NE if right else (NW if left else N)
	if down:
		return SE if right else (SW if left else S)
	if right:
		return E
	if left:
		return W
	return -1
