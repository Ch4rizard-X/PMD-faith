class_name StatusIcons
extends Node2D
## Red's status icons over Pokémon (dungeon_pokemon_sprites.c + EntityGetStatusSprites in dungeon_8041AD0.c).
## Two slots per Pokémon: slot 0 cycles through the set status symbols (one every 61 frames), slot 1 shows
## only Frozen (drawn over the body). Icon frames advance every 4 frames; graphics are graphics/status/*
## in the dungeon OBJ palettes from the monster archive's 'palet' (assets/dungeon/status_icons.png).

var dg                                  # Dungeon
var _tex: Texture2D
var _info: Dictionary = {}
var _frame := 0
var _acc := 0.0
var _slots := {}                        # Mon uid -> [[bit, frame], [bit, frame]]
static var _head_cache := {}            # species -> head y offset (px, relative to the sprite node)

const ID_SLEEPLESS := 0
const ID_BURNED := 1
const ID_POISONED := 2
const ID_BADLY_POISONED := 3
const ID_CONFUSED := 4
const ID_COWERING := 5
const ID_TAUNTED := 6
const ID_ENCORE := 7
const ID_SHIELD_BLUE := 8
const ID_SHIELD_RED := 9
const ID_SHIELD_YELLOW := 10
const ID_SHIELD_GREEN := 11
const ID_ENDURE := 12
const ID_LOWHP := 13
const ID_CURSED := 14
const ID_SNATCH := 15
const ID_SURE_SHOT := 16
const ID_WHIFFER := 17
const ID_SET_DAMAGE := 18
const ID_FOCUS_ENERGY := 19
const ID_BLINKER := 20
const ID_CROSS_EYED := 21
const ID_EYEDROPS := 22
const ID_MUZZLED := 23
const ID_GRUDGE := 24
const ID_EXPOSED := 25
const ID_SLEEP := 26
const ID_STAT_DOWN := 27
const ID_FROZEN := 28
const ID_LAST := 28

## Remake status key -> Red status sprite id (sStatusSpriteMasks_* tables).
const STATUS_TO_ID := {
	"sleep": ID_SLEEP, "nightmare": ID_SLEEP, "napping": ID_SLEEP, "sleepless": ID_SLEEPLESS,
	"burn": ID_BURNED, "poison": ID_POISONED, "badpoison": ID_BADLY_POISONED, "frozen": ID_FROZEN,
	"confused": ID_CONFUSED, "cowering": ID_COWERING, "taunt": ID_TAUNTED, "encore": ID_ENCORE,
	"reflect": ID_SHIELD_BLUE, "counter": ID_SHIELD_BLUE, "mini_counter": ID_SHIELD_BLUE, "mist": ID_SHIELD_BLUE,
	"safeguard": ID_SHIELD_RED, "mirror_coat": ID_SHIELD_RED,
	"light_screen": ID_SHIELD_YELLOW, "magic_coat": ID_SHIELD_YELLOW,
	"protect": ID_SHIELD_GREEN, "mirror_move": ID_SHIELD_GREEN, "vital_throw": ID_SHIELD_GREEN,
	"enduring": ID_ENDURE, "curse": ID_CURSED, "snatch": ID_SNATCH,
	"sure_shot": ID_SURE_SHOT, "whiffer": ID_WHIFFER, "set_damage": ID_SET_DAMAGE, "focus_energy": ID_FOCUS_ENERGY,
	"blinker": ID_BLINKER, "cross_eyed": ID_CROSS_EYED, "eyedrops": ID_EYEDROPS, "muzzled": ID_MUZZLED,
	"grudge": ID_GRUDGE,
}

func _ready() -> void:
	z_index = 3
	_tex = DungeonGfx.tex("status_icons.png")
	_info = DungeonGfx.data().get("status", {})

## EntityGetStatusSprites: the status sprite bit mask of a Pokémon.
static func mask_of(m: Mon) -> int:
	var bits := 0
	for k in STATUS_TO_ID:
		if m.status.has(k) and m.status[k] is int and int(m.status[k]) > 0:
			bits |= 1 << int(STATUS_TO_ID[k])
	if m.exposed:
		bits |= 1 << ID_EXPOSED
	if m.is_team() and m.max_hp / 4 > m.hp:
		bits |= 1 << ID_LOWHP
	var down := false
	for k in ["atk", "spa", "def", "spd", "acc", "eva"]:
		if int(m.stages.get(k, 10)) < 10:
			down = true
	for k in m.stat_mult:
		if int(m.stat_mult[k]) < 256:
			down = true
	if down:
		bits |= 1 << ID_STAT_DOWN
	return bits

## GetNextStatusSymbol.
static func next_symbol(mask: int, cur: int, slot: int) -> int:
	if mask == 0:
		return 0
	var last_bit := 1 if slot == 0 else (1 << ID_LAST)
	var second := (1 << (ID_LAST - 1)) if slot == 0 else (1 << ID_LAST)
	var n := ID_LAST if slot == 0 else 1
	var bits := cur if cur != 0 else last_bit
	for _i in n:
		bits <<= 1
		if bits > second:
			bits = last_bit
		if mask & bits:
			return bits
	return 0

func _process(dt: float) -> void:
	if dg == null or dg.fs == null:
		return
	_acc += dt * 60.0
	var steps := mini(int(_acc), 6)
	_acc -= float(int(_acc))
	for _s in steps:
		_frame += 1
		for m in dg.fs.mons:
			_update_slots(m)
	queue_redraw()

func _update_slots(m: Mon) -> void:
	var mask := mask_of(m)
	var st: Array = _slots.get(m.uid, [[0, 0], [0, 0]])
	for i in 2:
		var s: Array = st[i]
		if mask == 0:
			s[0] = 0
			continue
		if int(s[0]) == 0:
			s[1] = 0
		if int(s[1]) < 1:
			s[0] = next_symbol(mask, int(s[0]), i)
			s[1] = 60
		else:
			s[1] = int(s[1]) - 1
	_slots[m.uid] = st

static func _bit_index(bit: int) -> int:
	var i := 0
	while bit > 1:
		bit >>= 1
		i += 1
	return i

func _draw() -> void:
	if _tex == null or dg == null or dg.fs == null:
		return
	for m in dg.fs.mons:
		var v = m.visual
		if v == null or not is_instance_valid(v) or not v.visible or float(v.fade) < 0.5 or m.hp <= 0:
			continue
		var st: Array = _slots.get(m.uid, [])
		if st.is_empty():
			continue
		var head := Vector2(0, _head_y(v))
		for i in 2:
			var bit := int(st[i][0])
			if bit == 0:
				continue
			_draw_icon(_bit_index(bit), MonSprite.fig_point(v, v.bob + head))

## DrawStatusSprite: centred on the head point, 16 px higher (Frozen sits on the body); Sleep's Zzz 8 px right.
func _draw_icon(id: int, at: Vector2) -> void:
	var e: Dictionary = _info.get(str(id), {})
	if e.is_empty():
		return
	var w := int(e.w)
	var h := int(e.h)
	var f := (_frame / 4) % maxi(1, int(e.n))
	var pos := at - Vector2(w / 2.0, h / 2.0)
	if id != ID_FROZEN:
		pos.y -= 16
	if id == ID_SLEEP:
		pos.x += 8
	draw_texture_rect_region(_tex, Rect2(pos.round(), Vector2(w, h)), Rect2(int(e.x), f * h, w, h))

## Red takes the head point from the AX frame data; the SpriteCollab sheets have none, so use the top of
## the Idle sprite's first (facing-down) frame, 4 px down.
static func _head_y(v) -> float:
	var man: Dictionary = v.man
	var sp: String = str(v.mon.sp) if v.mon else ""
	if _head_cache.has(sp):
		return _head_cache[sp]
	var hy := -16.0
	var A: Dictionary = man.get("anims", {}).get("Idle", {})
	if not A.is_empty():
		var tex := DB.tex("res://assets/sp/" + str(A.get("s", man.get("sheet", ""))))
		if tex:
			var img := tex.get_image()
			if img and img.is_compressed():
				img.decompress()
			if img:
				var x0 := int(A.get("x", 0))
				var y0 := int(A.y)
				var w := int(A.w)
				var h := int(A.h)
				var top := -1
				for yy in h:
					for xx in w:
						if x0 + xx < img.get_width() and y0 + yy < img.get_height() and img.get_pixel(x0 + xx, y0 + yy).a > 0.5:
							top = yy
							break
					if top >= 0:
						break
				if top >= 0:
					hy = -h / 2.0 - 2.0 + top + 4.0
	_head_cache[sp] = hy
	return hy
