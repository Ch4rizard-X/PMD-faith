class_name GSprite
extends Node2D
## Draws a ground actor: a Pokémon (Red animation index -> SpriteCollab animation), an ornament object
## (flags etc. from the decomp's graphics/ornament), plus shadow and emote bubbles.
## Red animation ids (sub_80A6EFC): low byte = animation group, 0x800 = loop, 0x700 = speed
## (0x300 frozen, 0x100 half, 0x200 double), 0x400 = keep the current animation.

const ANIM_NAMES := ["Walk", "Attack", "Kick", "Shoot", "Strike", "Sleep", "Hurt", "Idle", "Swing", "Double", "Hop",
	"Charge", "Rotate", "EventSleep", "Wake", "Eat", "Tumble", "Pose", "Pull", "Pain", "Float", "DeepBreath", "Nod",
	"Sit", "LookUp", "Sink", "Trip", "Laying", "LeapForth", "Head", "Cringe", "LostBalance", "TumbleBack", "Faint",
	"HitGround"]
const FALLBACK := {"Kick": "Attack", "Shoot": "Attack", "Strike": "Attack", "Swing": "Attack", "Double": "Attack",
	"Charge": "Attack", "Rotate": "Idle", "EventSleep": "Sleep", "Wake": "Idle", "Eat": "Idle", "Tumble": "Hurt",
	"Pose": "Idle", "Pull": "Attack", "Pain": "Hurt", "Float": "Idle", "DeepBreath": "Idle", "Nod": "Idle", "Sit": "Idle",
	"LookUp": "Idle", "Sink": "Hurt", "Trip": "Hurt", "Laying": "Sleep", "LeapForth": "Hop", "Head": "Attack",
	"Cringe": "Hurt", "LostBalance": "Hurt", "TumbleBack": "Hurt", "Faint": "Hurt", "HitGround": "Hurt", "Hop": "Idle",
	"Hurt": "Idle", "Attack": "Idle", "Sleep": "Idle"}

var species := ""
var man: Dictionary = {}
var ornament := ""                    # object sprite (assets/ground/orn/<name>.png + json)
var orn: Dictionary = {}
var anim_group := 0
var dir := 0
var loop := true
var speed := 0x100
var _acc := 0
var _frame_t := 0                     # animation time in frames
var finished := false                 # a non-looping animation reached its end
var visible_flag := true
var blink := false
var shadow := true
var height := 0.0
var emote := -1                       # emote id (Red effect index), -1 none
var emote_t := 0
var emote_dir := 0                    # direction for 8-way effects

## Show Red effect <id> (effect_data.c gUnknown_80B9CC4; 0x1C0 / 0 clears) and play its sound.
func show_effect(id: int, d := 0) -> void:
	if id == 0 or id == 448:
		emote = -1
		return
	emote = id
	emote_t = 0
	emote_dir = d & 7 if d >= 0 else 0
	var sfx := int(GData.ornaments().get("fx%d" % id, {}).get("sfx", -1))
	if sfx > 0:
		Audio.sfx("%03d" % sfx)
var zbias := 0
## Red's moving animations (take-off, landing, jumps; tools/ground/gen_red_anim_offsets.py): when the
## SpriteCollab sheet lacks the Red group, its fallback pose is moved by Red's per-frame offsets for Red's
## duration, so e.g. Skarmory flies off the screen before the script removes it.
static var _red_tracks: Dictionary = {}
static var _red_tracks_loaded := false
var _track: Array = []                # [[frames, dx, dy], ...] for the current animation, or []
var _track_total := 0

static func red_track(sp: String, g: int, d: int) -> Array:
	if not _red_tracks_loaded:
		_red_tracks_loaded = true
		var f := FileAccess.open("res://data/ground/red_anim_offsets.json", FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_red_tracks = j
	var e = _red_tracks.get(sp.substr(0, 4), {}).get(str(g))
	if e is Dictionary:
		e = e.get(str(d & 7), [])
	return e if e is Array else []

func _track_offset() -> Vector2:
	if _track.is_empty():
		return Vector2.ZERO
	var t := _frame_t
	if loop:
		t = posmod(t, maxi(_track_total, 1))
	elif t >= _track_total:
		t = _track_total - 1
	var acc := 0
	for fr in _track:
		acc += int(fr[0])
		if t < acc:
			return Vector2(int(fr[1]), int(fr[2]))
	var last: Array = _track.back()
	return Vector2(int(last[1]), int(last[2]))

static var _emote_tex: Texture2D

func set_species(sp: String) -> void:
	var shiny := sp.ends_with("*")
	if shiny:
		sp = sp.substr(0, sp.length() - 1)
	material = Shiny.material(sp) if shiny else null
	species = sp
	if sp.begins_with("@"):
		man = {}
		set_ornament(sp.substr(1))
		queue_redraw()
		return
	man = DB.sprites.get(sp, DB.sprites.get(sp.substr(0, 4), {}))
	queue_redraw()

func set_ornament(name: String) -> void:
	ornament = name
	orn = GData.ornaments().get(name, {})

func has_pokemon() -> bool:
	return not man.is_empty()

func _anim_name(g: int) -> String:
	var n: String = ANIM_NAMES[g] if g >= 0 and g < ANIM_NAMES.size() else "Idle"
	var anims: Dictionary = man.get("anims", {})
	var guard := 0
	while not anims.has(n) and guard < 4:
		n = FALLBACK.get(n, "Idle")
		guard += 1
	return n if anims.has(n) else ("Idle" if anims.has("Idle") else (anims.keys()[0] if anims.size() else ""))

## sub_80A6EFC
func play(a1: int, d: int) -> void:
	if a1 & 0x400:
		return
	match a1 & 0x700:
		0x300:
			speed = 0
		0x100:
			speed = 0x80
		0x200:
			speed = 0x200
		_:
			speed = 0x100
	var g := (a1 & 0xFF) + int(d / 8)
	var new_dir := d & 7
	if g != anim_group or (a1 & 0x800) != (0x800 if loop else 0):
		_frame_t = 0
		_acc = 0
		finished = false
	anim_group = g
	dir = new_dir
	loop = (a1 & 0x800) != 0
	_track = []
	_track_total = 0
	if not man.is_empty() and g >= 0 and g < ANIM_NAMES.size() and _anim_name(g) != ANIM_NAMES[g]:
		_track = red_track(species, g, new_dir)
		for fr in _track:
			_track_total += int(fr[0])
	queue_redraw()

## RunAxAnimationFrame at the current speed (one game frame).
func tick() -> void:
	_acc += speed
	while _acc >= 0x100:
		_acc -= 0x100
		_frame_t += 1
	if emote >= 0:
		emote_t += 1
		if _emote_done():
			emote = -1
	queue_redraw()

func anim_busy() -> bool:
	if man.is_empty() and orn.is_empty():
		return false
	if loop:
		return false
	return not finished

func _anim_dict() -> Dictionary:
	var anims: Dictionary = man.get("anims", {})
	return anims.get(_anim_name(anim_group), {})

func _draw() -> void:
	if not visible_flag:
		return
	if blink and (Engine.get_process_frames() & 1):
		return
	if not orn.is_empty():
		_draw_ornament()
		if emote >= 0:
			_draw_emote(Vector2(0, -height))
		return
	if man.is_empty():
		if emote >= 0:           # body-less object / effect showing an effect animation
			_draw_emote(Vector2(0, -height))
		return
	var A := _anim_dict()
	if A.is_empty():
		return
	var tex := DB.tex("res://assets/sp/" + str(A.get("s", man.sheet)))
	if tex == null:
		return
	var dur: Array = A.dur
	var total := 0
	for x in dur:
		total += int(x)
	var t := _frame_t
	if not loop:
		if t >= total:
			t = total - 1
			finished = _frame_t >= _track_total      # a Red motion track runs to its end first
	else:
		t = posmod(t, maxi(total, 1))
	var f := 0
	var acc := 0
	while f < dur.size():
		acc += int(dur[f])
		if t < acc:
			break
		f += 1
	f = mini(f, dur.size() - 1)
	var row := mini(dir, int(A.rows) - 1)
	var w := int(A.w)
	var h := int(A.h)
	if shadow:
		var shd: Array = man.get("shd", [])
		var fp := Vector2(0, 4)
		if shd.size() > 0:
			var e: Array = shd[mini(dir, shd.size() - 1)]
			fp = Vector2(e[0], e[1])
		var sz := int(man.get("sh", 1))
		var rx = [5.0, 7.0, 10.0][clampi(sz, 0, 2)]
		draw_set_transform(fp + Vector2(0, -1), 0.0, Vector2(1.0, 0.45))
		draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, 0.45))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var src := Rect2(int(A.get("x", 0)) + f * w, int(A.y) + row * h, w, h)
	if A.has("cols"):        # frames wrap onto further lines (sheets wider than 4096 px)
		var cols := maxi(1, int(A.cols))
		src.position = Vector2(int(A.get("x", 0)) + (f % cols) * w, int(A.y) + (f / cols) * int(A.rows) * h + row * h)
	var toff := _track_offset()
	var dst := Rect2((Vector2(-w / 2.0, -h / 2.0 - 2.0 - height) + toff).round(), Vector2(w, h))
	draw_texture_rect_region(tex, dst, src)
	if emote >= 0:
		# Red anchors effects at an ax position set of the pose (0 head, 3 body centre; -1 = sprite origin).
		# SpriteCollab sheets have no such points: use Red's typical head / centre heights per body size
		# (e.g. Pikachu's head is at y -10, its centre at -7).
		var ps := int(GData.ornaments().get("fx%d" % emote, {}).get("posset", -1))
		var bs := clampi(int(man.get("sh", 1)), 0, 2)
		var at := Vector2(0, -height)
		if ps == 0:
			at.y -= [10.0, 14.0, 22.0][bs]
		elif ps > 0:
			at.y -= [7.0, 9.0, 14.0][bs]
		_draw_emote(at.round())

func _draw_ornament() -> void:
	var tex := DB.tex("res://assets/ground/orn/%s.png" % ornament)
	if tex == null:
		return
	var anims: Array = orn.get("anims", [])
	if anims.is_empty():
		draw_texture(tex, -tex.get_size() / 2.0)
		return
	# axmain animations[group][dir] -> [[pose, frames, dx, dy], ...] (gen_ornaments.py)
	var grp: Array = anims[clampi(anim_group, 0, anims.size() - 1)]
	var seq: Array = grp[clampi(dir, 0, grp.size() - 1)]
	if seq.is_empty():
		return
	var total := 0
	for fr in seq:
		total += int(fr[1])
	var t := _frame_t
	if loop:
		t = posmod(t, maxi(total, 1))
	elif t >= total:
		t = total - 1
		finished = true
	var acc := 0
	var poses: Array = orn.get("poses", [])
	for fr in seq:
		acc += int(fr[1])
		if t < acc:
			var P: Array = poses[int(fr[0])]
			var dst := Vector2(int(P[4]) + int(fr[2]), int(P[5]) + int(fr[3]) - height)
			draw_texture_rect_region(tex, Rect2(dst, Vector2(P[2], P[3])), Rect2(P[0], P[1], P[2], P[3]))
			return

## Red's emote effects 88..94 (NOTICE "!", QUESTION "?", 90 ♪-burst, SHOCK, SWEAT, SPARKLE, ANGER): the
## efob001 effect animations (gen_ornaments.py -> assets/ground/orn/fxNN.png), drawn at the head position.
## Non-looping ones end with their animation; looping ones stay until replaced or cleared (448).
func _draw_emote(at: Vector2) -> void:
	var E: Dictionary = GData.ornaments().get("fx%d" % emote, {})
	if E.is_empty():
		return
	var tex := DB.tex("res://assets/ground/orn/fx%d.png" % emote)
	if tex == null:
		return
	var g: Array = E.anims[0]
	var seq: Array = g[clampi(emote_dir, 0, g.size() - 1)]
	var total := 0
	for fr in seq:
		total += int(fr[1])
	var t := emote_t
	if bool(E.get("loop", false)):
		t = posmod(t, maxi(total, 1))
	elif t >= total:
		return
	var acc := 0
	for fr in seq:
		acc += int(fr[1])
		if t < acc:
			var P: Array = E.poses[int(fr[0])]
			var dst := at + Vector2(int(P[4]) + int(fr[2]), int(P[5]) + int(fr[3]) + int(EMOTE_DY.get(emote, 0)))
			draw_texture_rect_region(tex, Rect2(dst, Vector2(P[2], P[3])), Rect2(P[0], P[1], P[2], P[3]))
			return

## user tweak: these effects sat too high over our sprites (no Red head points), lowered by a few px
const EMOTE_DY := {88: 10, 90: 6, 91: 6, 93: 6}

func _emote_done() -> bool:
	var E: Dictionary = GData.ornaments().get("fx%d" % emote, {})
	if E.is_empty():
		return true
	if bool(E.get("loop", false)):
		return false
	var total := 0
	for fr in E.anims[0][0]:
		total += int(fr[1])
	return emote_t >= total
