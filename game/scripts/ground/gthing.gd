class_name GThing
extends RefCounted
## Ground objects and effects (ground_object.c / ground_effect.c): scripted actors that are mostly invisible
## helpers (camera targets, triggers); a few objects draw an ornament sprite (team-base flags, title, npcs).

var G
var is_effect := false
var id := 0
var kind := -1
var group := 0
var sector := 0
var size := Vector2i.ZERO
var half := Vector2i.ZERO
var direction1 := 0
var pos0 := Vector2i.ZERO
var b_from := Vector2i(-0x7FFFFFF, -0x7FFFFFF)
var b_to := Vector2i(0x7FFFFFF, 0x7FFFFFF)
var p124 := Vector2i.ZERO
var p12C := Vector2i.ZERO
var p134 := Vector2i.ZERO
var flags := 0
var anim := 0x800
var dir_dirty := true
var action: GAction
var sprite: GSprite

func _init(ground, slot: int, effect: bool) -> void:
	G = ground
	id = slot
	is_effect = effect

func get_index() -> int:
	return id

func get_size() -> Vector2i:
	return size

func get_center() -> Vector2i:
	return p124 + half

func get_height() -> Vector2i:
	return p134

func get_dir() -> int:
	return direction1

func get_flags() -> int:
	return flags

func set_hitbox_pos(p) -> void:
	var c: Vector2i = pos0 if p == null else p
	p124 = c - half
	p12C = c + half
	if p == null:
		p134 = Vector2i.ZERO

func set_bounds(a: Vector2i, b: Vector2i) -> void:
	b_from = a
	b_to = b

func move_real(p: Vector2i) -> int:
	var a := p - half
	var b := p + half
	if a.x < b_from.x or b.x >= b_to.x or a.y < b_from.y or b.y >= b_to.y:
		return 1
	if _collide(a, b):
		return 1
	p124 = a
	p12C = b
	return 0

func move_rel(d: Vector2i) -> int:
	var a := p124 + d
	var b := p12C + d
	var changed := false
	if a.x < b_from.x:
		a.x = b_from.x; b.x = a.x + size.x; changed = true
	elif b.x >= b_to.x:
		b.x = b_to.x; a.x = b.x - size.x; changed = true
	if a.y < b_from.y:
		a.y = b_from.y; b.y = a.y + size.y; changed = true
	elif b.y >= b_to.y:
		b.y = b_to.y; a.y = b.y - size.y; changed = true
	if _collide(a, b):
		return 1
	p124 = a
	p12C = b
	return 1 if changed else 0

func _collide(a: Vector2i, b: Vector2i) -> bool:
	if not (flags & 3):
		return false
	var p1 := Vector2i(a.x >> 11, a.y >> 11)
	var t := Vector2i((b.x - 1) >> 11, (b.y - 1) >> 11)
	var sz := t - p1 + Vector2i.ONE
	if flags & 1 and G.map_collide(p1, sz, 0x80):
		return true
	if flags & 2 and G.map_collide(p1, sz, 0x40):
		return true
	return false

func set_height(h: int) -> void:
	p134.x = h

func set_dir(d: int) -> void:
	if d != -1 and d != direction1:
		direction1 = d
		dir_dirty = true

func set_event_index(a1: int) -> void:
	if a1 != 0 and a1 != 0x1000:
		if anim != a1:
			anim = a1
			dir_dirty = true

## CMD 0x56 (sub_80A7040): show Red effect animation a1 on this object/effect (0 clears).
func f38(a1: int, a2: int) -> void:
	if sprite == null:
		if a1 == 0 or a1 == 448:
			return
		sprite = GSprite.new()           # body-less holder for the effect animation
		sprite.shadow = false
		G.actors.add_child(sprite)
		var c := get_center()
		sprite.position = Vector2(c.x >> 8, c.y >> 8)
	sprite.show_effect(a1, a2)
	sprite.z_index = 1

func set_flags(f: int) -> void:
	flags |= f

func clear_flags(f: int) -> void:
	flags &= ~f

func f44(_a: int) -> void:
	pass

func sprite_busy_4c() -> bool:
	return sprite.anim_busy() if sprite else false

func sprite_busy_50() -> bool:
	return sprite != null and sprite.emote >= 0
