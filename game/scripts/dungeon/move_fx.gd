class_name MoveFx
extends RefCounted
## Plays EoS / Explorers Remixed move-effect animations (data/move_fx.json + data/fx.json,
## sheets in assets/fx). Moves without their own animation borrow one by type and category.
## With Move animations on Red's (Red-only builds, or the launcher's Game page) Red Rescue Team's own play (data/red_move_fx.json + assets/fx_red,
## from the pmd-red decomp's effect tables): the user's pose, the move's sound, and four effects in Red's order.

static var fx: Dictionary = {}
static var moves: Dictionary = {}
static var _loaded := false

const ALIAS := {"vicegrip": "vicegrip", "highjumpkick": "hijumpkick", "excavate": "dig",
	"judgment": "judgement", "spinslash": "nightslash"}
## Fallback per type: [special/status, physical]. The first name that has an entry is used.
const BY_TYPE := {
	"Normal": [["swift"], ["scratch", "megapunch"]],
	"Fire": [["ember", "flamethrower"], ["firepunch"]],
	"Water": [["watergun"], ["waterfall"]],
	"Grass": [["razorleaf"], ["needlearm"]],
	"Electric": [["thundershock"], ["thunderpunch"]],
	"Ice": [["icebeam"], ["icepunch"]],
	"Fighting": [["focusblast"], ["karatechop"]],
	"Poison": [["sludge"], ["poisonsting"]],
	"Ground": [["mudslap"], ["dig"]],
	"Flying": [["gust"], ["wingattack"]],
	"Psychic": [["confusion"], ["zenheadbutt"]],
	"Bug": [["signalbeam"], ["xscissor"]],
	"Rock": [["rockthrow"], ["rockslide"]],
	"Ghost": [["shadowball"], ["shadowpunch"]],
	"Dragon": [["dragonbreath"], ["dragonclaw"]],
	"Dark": [["darkpulse"], ["bite"]],
	"Steel": [["flashcannon"], ["metalclaw"]],
	"Fairy": [["moonblast", "dazzlinggleam", "sweetkiss"], ["playrough", "sweetkiss"]],
}

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for p in [["res://data/fx.json", "fx"], ["res://data/move_fx.json", "moves"]]:
		var f := FileAccess.open(p[0], FileAccess.READ)
		if f == null:
			continue
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			if p[1] == "fx":
				fx = d
			else:
				moves = d

static func key(n: String) -> String:
	var out := ""
	for c in n.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
	return out

static func entry_for(move_name: String, mv: Dictionary) -> Dictionary:
	_load()
	var k := key(move_name)
	k = ALIAS.get(k, k)
	if moves.has(k):
		return moves[k]
	var tl: Array = BY_TYPE.get(str(mv.get("t", "")), [])
	if tl.is_empty():
		return {}
	var cands: Array = tl[1] if str(mv.get("c", "S")) == "P" else tl[0]
	if str(mv.get("c", "")) == "X" and str(mv.get("t", "")) == "Normal":
		return {}
	for c in cands:
		if moves.has(c):
			return moves[c]
	return {}

# ---------------------------------------------------------------- Red Rescue Team's own move animations
static var red: Dictionary = {}
static var _red_loaded := false
const RED_NO_SOUND := 997
const RED_ALIAS := {"highjumpkick": "hijumpkick", "vicegrip": "vicegrip", "faintattack": "faintattack",
	"feintattack": "faintattack", "smellingsalts": "smellingsalt", "selfdestruct": "selfdestruct"}

## Red's animations are used in a Red-only build (the data is there when the build made it).
static func red_on() -> bool:
	if not load("res://scripts/core/launcher_cfg.gd").red_part("anim"):
		return false
	if not _red_loaded:
		_red_loaded = true
		if FileAccess.file_exists("res://data/red_move_fx.json"):
			var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/red_move_fx.json"))
			if d is Dictionary:
				red = d
	return not red.is_empty()

## Moves Red doesn't have borrow a Red move by type: [special / status, physical] (as BY_TYPE does for EoS).
## Red has no Fairy type; Sweet Kiss and Moonlight are its closest.
const RED_BY_TYPE := {
	"Normal": ["swift", "slash"], "Fire": ["flamethrower", "firepunch"], "Water": ["watergun", "waterfall"],
	"Grass": ["razorleaf", "leafblade"], "Electric": ["thunderbolt", "thunderpunch"], "Ice": ["icebeam", "icepunch"],
	"Fighting": ["focuspunch", "brickbreak"], "Poison": ["sludgebomb", "poisonfang"], "Ground": ["mudslap", "bonemerang"],
	"Flying": ["gust", "aerialace"], "Psychic": ["psybeam", "confusion"], "Bug": ["signalbeam", "furycutter"],
	"Rock": ["ancientpower", "rockslide"], "Ghost": ["shadowball", "lick"], "Dragon": ["dragonbreath", "dragonclaw"],
	"Dark": ["crunch", "bite"], "Steel": ["irontail", "metalclaw"], "Fairy": ["moonlight", "sweetkiss"],
}

static func red_entry(move_name: String) -> Dictionary:
	var k := key(move_name) if move_name != "" else "regularattack"
	var M: Dictionary = red.get("moves", {})
	var e: Dictionary = M.get(k, M.get(RED_ALIAS.get(k, k), {}))
	if not e.is_empty() or move_name == "":
		return e
	var mv: Dictionary = DB.moves.get(move_name, {})
	var tl: Array = RED_BY_TYPE.get(str(mv.get("t", "")), [])
	if tl.is_empty() or (str(mv.get("c", "")) == "X" and str(mv.get("t", "")) == "Normal"):
		return {}
	return M.get(tl[1] if str(mv.get("c", "S")) == "P" else tl[0], {})

## [animation index, sound] for this Pokémon (Red has per-species overrides, e.g. Marowak's Ember).
static func _red_pose_sound(m: Mon, e: Dictionary) -> Array:
	var by: Dictionary = e.get("by", {})
	var o = by.get(key(Missions.sp_name(m.sp)), null)
	if o is Array:
		return [int(o[0]), int(o[1])]
	return [int(e.get("anim", 1)), int(e.get("sfx", RED_NO_SOUND))]

## The user's pose for this move in Red ("" = keep the game's choice; "spin" = turns round on the spot).
static func red_anim(m: Mon, move_name: String) -> String:
	if not red_on():
		return ""
	var e := red_entry(move_name)
	if e.is_empty():
		return ""
	var a: int = _red_pose_sound(m, e)[0]
	if a == 98 or a == 99:
		return "spin"
	if a < 0 or a >= GSprite.ANIM_NAMES.size():
		return ""
	return GSprite.ANIM_NAMES[a]

## Red's order (code_8040094_1.c, dungeon_move_util.c): the move's sound; effect 1 on the user before the
## attack; effect 2 on the user at the attack pose's hit frame; effect 3 travels to the target (arcing when
## the move says so); effect 4 on each target.
static func play_red(dg: Node, m: Mon, move_name: String, d: int, targets: Array) -> void:
	var e := red_entry(move_name)
	if e.is_empty():
		return
	var snd: int = _red_pose_sound(m, e)[1]
	if snd > 0 and snd != RED_NO_SOUND:
		Audio.sfx("%03d" % snd)
	var first_t: Mon = null
	for t in targets:
		if t != null and t != m and t.visual:
			first_t = t
			break
	var pre := int(e.get("pre", 0))
	if pre:
		var n := _red_node(dg, pre, m, d)
		if n:
			await n.done
	var user := int(e.get("user", 0))
	var un: FxNode = _red_node(dg, user, m, d) if user else null
	var proj := int(e.get("proj", 0))
	if proj:
		var F: Dictionary = red.fx.get(str(proj), {})
		if not F.get("anims", []).is_empty():
			if un:
				await dg.get_tree().create_timer(0.12).timeout
			var from := _anchor(m, "center")
			var to := _anchor(first_t, "center") if first_t else from + Vector2(DB.DIRS[d]) * 24.0 * 4.0
			var n := _red_node(dg, proj, m, d, true)
			if n:
				n.position = from
				# Red: <speed> px a frame; arcing ones rise (frames + 8) px, at most 64 (32 for one tile)
				var frames := maxf(1.0, from.distance_to(to) / maxf(1.0, float(e.get("speed", 6))))
				var secs := clampf(frames / 60.0, 0.05, 1.2)
				var h := 32.0 if from.distance_to(to) <= 34.0 else minf(64.0, frames + 8.0)
				var arc := bool(e.get("arc", false))
				var tw := dg.create_tween()
				tw.tween_method(func(f: float) -> void:
					if is_instance_valid(n):
						n.position = from.lerp(to, f) + (Vector2(0, -sin(f * PI) * h) if arc else Vector2.ZERO), 0.0, 1.0, secs)
				await tw.finished
				if is_instance_valid(n):
					n.queue_free()
		elif F.get("sfx", -1) > 0:
			Audio.sfx("%03d" % int(F.sfx))
	elif un:
		await un.done
	var hit := int(e.get("hit", 0))
	if hit:
		var last: FxNode = null
		var shown := 0
		for t in targets:
			if t == null or t.visual == null or shown >= 6:
				continue
			last = _red_node(dg, hit, t, d, false, shown > 0)
			shown += 1
		if last:
			await last.done

## One Red effect on Pokémon <at> (its attach point), facing <d>. Plays the effect's own sound unless <quiet>.
static func _red_node(dg: Node, eid: int, at: Mon, d: int, loop := false, quiet := false) -> FxNode:
	var F: Dictionary = red.get("fx", {}).get(str(eid), {})
	if F.is_empty():
		return null
	if not quiet and int(F.get("sfx", -1)) > 0:
		Audio.sfx("%03d" % int(F.sfx))
	if F.has("bg"):
		return _red_screen(dg, eid, F)
	var A: Array = F.get("anims", [])
	if A.is_empty() or at == null or at.visual == null:
		return null
	var seq: Array = A[d % A.size()] if A.size() == 8 else A[0]
	if seq.is_empty():
		return null
	var tex := DB.tex("res://assets/fx_red/fxr%d.png" % eid)
	if tex == null:
		return null
	var P: Array = F.get("poses", [])
	var frames: Array = []
	for fr in seq:                      # [pose, frames, dx, dy] -> FxNode's [sx, sy, w, h, x, y, frames]
		var p: Array = P[int(fr[0])]
		frames.append([p[0], p[1], p[2], p[3], p[4] + fr[2], p[5] + fr[3], int(fr[1])])
	var att := "none"
	match int(F.get("attach", -1)):
		-1:
			att = "none"
		0:
			att = "head"
		_:
			att = "center"
	return _sprite_node(dg, tex, frames, loop, _anchor(at, att))

## Red's full-screen effects (Psychic's waves, Haze, Heat Wave ...): 240x160 frames over the whole view.
## Red mixes them 10/16 effect + 10/16 dungeon with the effect's palette faded in (frame alpha = brightness).
const RED_BLEND := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float k = 0.625;
varying float bri;
void vertex() { bri = COLOR.a; }
void fragment() {
	vec4 e = texture(TEXTURE, UV);
	if (e.a < 0.5) discard;
	COLOR = vec4(min(vec3(1.0), (e.rgb * bri + texture(screen_tex, SCREEN_UV).rgb) * k), 1.0);
}"""
static var _blend_shader: Shader

static func _red_screen(dg: Node, eid: int, F: Dictionary) -> FxNode:
	var tex := DB.tex("res://assets/fx_red/fxr%d.png" % eid)
	if tex == null or F.get("frames", []).is_empty():
		return null
	var n := _screen_node(dg, tex, F.frames, Vector2(240, 160))
	if float(F.get("blend", 0)) > 0.0:
		if _blend_shader == null:
			_blend_shader = Shader.new()
			_blend_shader.code = RED_BLEND
		var mat := ShaderMaterial.new()
		mat.shader = _blend_shader
		mat.set_shader_parameter("k", float(F.blend))
		n.material = mat
	return n

static func enabled() -> bool:
	return not Dialog.auto or OS.get_cmdline_user_args().has("--fx")

## Plays the whole animation for one use of a move. Returns when the blocking parts are done.
static func play(dg: Node, m: Mon, move_name: String, mv: Dictionary, d: int, targets: Array) -> void:
	if not enabled() or m.visual == null:
		return
	if red_on():
		await play_red(dg, m, move_name, d, targets)
		return
	if move_name == "":
		return
	var e := entry_for(move_name, mv)
	if e.is_empty():
		return
	var ua := str(e.get("ua", ""))
	if ua != "" and m.visual.man.get("anims", {}).has(ua):
		m.visual.play(ua)
	var steps: Array = e.get("s", [])
	var first_t: Mon = null
	for t in targets:
		if t != null and t.visual:
			first_t = t
			break
	var t_end := Time.get_ticks_msec() + 4000
	for st in steps:
		if Time.get_ticks_msec() > t_end:
			break
		var fid := str(int(st.get("fx", -1)))
		if not fx.has(fid):
			continue
		var F: Dictionary = fx[fid]
		var dir := d if int(st.get("d", 0)) == 1 else 0
		var frames: Array = _frames(F, dir)
		if frames.is_empty():
			continue
		var tex := DB.tex("res://assets/fx/fx_%04d.png" % int(fid))
		if tex == null:
			continue
		var blocking := bool(st.get("b", true))
		var role := str(st.get("r", "target"))
		var att := str(st.get("at", "center"))
		if str(F.get("k", "p")) == "s":
			var n := _screen_node(dg, tex, frames)
			if blocking:
				await n.done
			continue
		match role:
			"projectile":
				var from: Vector2 = _anchor(m, att)
				var to: Vector2
				if first_t:
					to = _anchor(first_t, "center")
				else:
					to = from + Vector2(DB.DIRS[d]) * 24.0 * 4.0
				var n := _sprite_node(dg, tex, frames, true, from)
				var ppf := maxf(1.0, float(e.get("ppf", 4)))
				var secs := clampf(from.distance_to(to) / (ppf * 60.0), 0.08, 1.2)
				var tw := dg.create_tween()
				tw.tween_property(n, "position", to, secs)
				await tw.finished
				n.queue_free()
			"target":
				var last: FxNode = null
				var shown := 0
				for t in targets:
					if t == null or t.visual == null or shown >= 6:
						continue
					last = _sprite_node(dg, tex, frames, false, _anchor(t, att))
					shown += 1
				if last == null and first_t == null and str(mv.get("r", "")) in ["user", "team_room", "team_floor"]:
					last = _sprite_node(dg, tex, frames, false, _anchor(m, att))
				if last and blocking:
					await last.done
			_:
				var n := _sprite_node(dg, tex, frames, false, _anchor(m, att))
				if blocking:
					await n.done

static func _frames(F: Dictionary, dir: int) -> Array:
	var a: Dictionary = F.get("a", {})
	var k := str(dir) if bool(F.get("dir", false)) else "0"
	return a.get(k, a.get("0", []))

static func _anchor(m: Mon, att: String) -> Vector2:
	var off := Vector2(0, -6)
	match att:
		"head":
			off = Vector2(0, -16)
		"none":
			off = Vector2.ZERO
	return MonSprite.fig_point(m.visual, m.visual.bob + off)     # on the 3D figure's body in the 3D view

static func _sprite_node(dg: Node, tex: Texture2D, frames: Array, loop: bool, at: Vector2) -> FxNode:
	var n := FxNode.new()
	n.tex = tex
	n.frames = frames
	n.loop = loop
	n.position = at
	n.scale = Vector2(1, MonSprite.fig_k)      # 3D view: as tall as the figures, not squashed with the floor
	n.z_index = 6
	dg.fx_layer.add_child(n)
	return n

static func _screen_node(dg: Node, tex: Texture2D, frames: Array, size := Vector2(256, 192)) -> FxNode:
	var cl := CanvasLayer.new()
	cl.layer = 3
	dg.add_child(cl)
	var n := FxNode.new()
	n.tex = tex
	n.frames = frames
	n.screen = true
	var vs: Vector2 = dg.get_viewport().get_visible_rect().size
	var s := maxf(vs.x / size.x, vs.y / size.y)
	n.scale = Vector2(s, s)
	n.position = (vs - size * s) / 2.0
	cl.add_child(n)
	n.done.connect(cl.queue_free)
	return n


class FxNode extends Node2D:
	signal done
	var tex: Texture2D
	var frames: Array = []
	var loop := false
	var screen := false
	var t := 0.0
	var _total := 0
	var _fin := false

	## A frame's length in frames. A few effects (313, 318-321: beams, Counter's) carry a flag in the high byte
	## (0x101): only the low byte is the duration, else that frame held for 257 frames (4 s).
	static func _dur(f: Array) -> int:
		return maxi(1, int(f[6]) & 0xFF)

	func _ready() -> void:
		for f in frames:
			_total += _dur(f)
		if _total <= 0:
			_total = 1

	func _process(dt: float) -> void:
		t += dt * 60.0
		if not loop and t >= _total and not _fin:
			_fin = true
			done.emit()
			if not screen:
				queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		if frames.is_empty() or tex == null:
			return
		var ft := int(t) % _total if loop else mini(int(t), _total - 1)
		var acc := 0
		for f in frames:
			acc += _dur(f)
			if ft < acc:
				if int(f[2]) > 0 and int(f[3]) > 0:
					var a := float(f[7]) if f.size() > 7 else 1.0
					draw_texture_rect_region(tex, Rect2(f[4], f[5], f[2], f[3]), Rect2(f[0], f[1], f[2], f[3]), Color(1, 1, 1, a))
				return
