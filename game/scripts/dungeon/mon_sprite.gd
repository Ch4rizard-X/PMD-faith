class_name MonSprite
extends Node2D
## Draws one Pokémon from its SpriteCollab-style sheet (8 facing rows, frame durations at 60 fps)
## plus the team/enemy shadow marker.

const ONESHOT := ["Attack", "Hurt", "Shoot", "Charge", "Strike", "Eat", "Hop", "Faint"]
## Anims that repeat; every other anim (move poses such as Swing, Rotate, Double) plays once then returns to Idle.
const LOOPING := ["Idle", "Walk", "Sleep", "EventSleep", "Laying", "Float", "Hover", "Sit", "Swim"]
const FALLBACK := {"Shoot": "Attack", "Charge": "Attack", "Strike": "Attack", "Eat": "Idle", "Faint": "Hurt", "Hop": "Idle"}
const SIZES := ["small", "medium", "large"]

var mon: Mon
var man: Dictionary = {}
var anim := "Idle"
var t0 := 0.0
var hold_last := false
var fade := 1.0
var flash := 0.0
var sparkle := 0.0                 # shiny sparkle (seconds left)
var bob := Vector2.ZERO
var _mark_tex: Texture2D
var _mark_off := Vector2.ZERO

func setup(m: Mon) -> void:
	mon = m
	m.visual = self
	set_species(m.sp)
	z_index = 2

func set_species(sp: String) -> void:
	man = DB.sprites.get(sp, DB.sprites.get(sp.substr(0, 4), {}))
	material = Shiny.material(sp) if mon != null and Shiny.is_shiny(mon) else null
	var size_i := int(DB.marks.get("size", {}).get(sp.substr(0, 4), man.get("sh", 1)))
	size_i = clampi(size_i, 0, 2)
	var side := "team" if mon and _team_mark(mon) else "enemy"
	var k: String = side + "_" + SIZES[size_i]
	_mark_tex = DB.tex("res://assets/ui/mark_%s.png" % k)
	var o: Array = DB.marks.get("off", {}).get(k, [0, 0])
	_mark_off = Vector2(o[0], o[1])
	queue_redraw()

func play(a: String, hold := false) -> void:
	anim = a
	hold_last = hold
	t0 = Time.get_ticks_msec() / 1000.0

func anim_length(a: String) -> float:
	var A := _anim(a)
	if A.is_empty():
		return 0.0
	var tot := 0
	for d in A.dur:
		tot += int(d)
	return tot / 60.0

func _anim(a: String) -> Dictionary:
	var anims: Dictionary = man.get("anims", {})
	if anims.has(a):
		return anims[a]
	if FALLBACK.has(a) and anims.has(FALLBACK[a]):
		return anims[FALLBACK[a]]
	return anims.get("Idle", {})

func _process(dt: float) -> void:
	if sparkle > 0.0:
		sparkle = maxf(0.0, sparkle - dt)
	queue_redraw()

func _draw() -> void:
	if man.is_empty() or mon == null:
		return
	var a := anim
	if mon.alive() and mon.has_status("sleep") and a == "Idle" and man.anims.has("Sleep"):
		a = "Sleep"
	var A := _anim(a)
	if A.is_empty():
		return
	var sheet_name: String = A.get("s", man.sheet)
	var tex := DB.tex("res://assets/sp/" + sheet_name)
	if tex == null:
		return
	var dur: Array = A.dur
	var total := 0
	for d in dur:
		total += int(d)
	var t := int((Time.get_ticks_msec() / 1000.0 - t0) * 60.0)
	if not (a in LOOPING) and not hold_last and t >= total:
		anim = "Idle"
		t0 = Time.get_ticks_msec() / 1000.0
		A = _anim("Idle")
		dur = A.dur
		total = 0
		for d in dur:
			total += int(d)
		t = 0
		sheet_name = A.get("s", man.sheet)
		tex = DB.tex("res://assets/sp/" + sheet_name)
	elif hold_last and t >= total:
		t = total - 1
	t = posmod(t, maxi(total, 1))
	var f := 0
	var acc := 0
	while f < dur.size():
		acc += int(dur[f])
		if t < acc:
			break
		f += 1
	f = mini(f, dur.size() - 1)
	var row := mini(mon.facing, int(A.rows) - 1)
	var w := int(A.w)
	var h := int(A.h)
	var mod := Color(1, 1, 1, fade)
	if flash > 0.0:
		mod = Color(1.0 + flash, 1.0 + flash, 1.0 + flash, fade)
	if Awaken.is_awake(mon):          # DX: an Awakened Pokémon glows
		var pl := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
		mod = Color(mod.r * (1.0 + 0.45 * pl), mod.g * (1.0 + 0.3 * pl), mod.b * (1.0 - 0.15 * pl), mod.a)
	# shadow marker
	if _mark_tex:
		var shd: Array = man.get("shd", [])
		var fp := Vector2(0, 4)
		if shd and shd.size() > 0:
			var e: Array = shd[mini(mon.facing, shd.size() - 1)]
			fp = Vector2(e[0], e[1])
		draw_texture(_mark_tex, (fp + Vector2(0, 1) + _mark_off + Vector2(0, -2)).round(), Color(1, 1, 1, fade * (1.0 if _team_mark(mon) else 0.6)))
	var src := Rect2(int(A.get("x", 0)) + f * w, int(A.y) + row * h, w, h)
	if A.has("cols"):        # frames wrap onto further lines (sheets wider than 4096 px)
		var cols := maxi(1, int(A.cols))
		src.position = Vector2(int(A.get("x", 0)) + (f % cols) * w, int(A.y) + (f / cols) * int(A.rows) * h + row * h)
	var dst := Rect2((Vector2(-w / 2.0, -h / 2.0 - 2.0) + bob).round(), Vector2(w, h))
	draw_texture_rect_region(tex, dst, src, mod)
	if sparkle > 0.0:                # four twinkling stars around the shiny
		var k := 1.6 - sparkle
		for i in 4:
			var ph := k * 3.0 - i * 0.35
			if ph < 0.0 or ph > 1.0:
				continue
			var ang := i * PI / 2.0 + 0.6
			var c := Vector2(cos(ang), sin(ang)) * (8.0 + 6.0 * ph) + Vector2(0, -h / 4.0)
			var r := 3.0 * sin(ph * PI)
			var col := Color(1.0, 1.0, 0.85, 1.0)
			draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 1.0)
			draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 1.0)

## Red (dungeon_mon_sprite_render.c): team members, decoys and experience-locked guests / rescue clients
## (IsExperienceLocked or monsterBehavior 1) all get the team-coloured shadow marker.
static func _team_mark(m: Mon) -> bool:
	if m.is_team() or m.side == "client":
		return true
	return m.get_meta("client", false) or m.has_meta("job_id") or m.has_meta("escort_job") or m.has_status("decoy")
