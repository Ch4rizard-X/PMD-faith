class_name MoveFx
extends RefCounted
## Plays EoS / Explorers Remixed move-effect animations (data/move_fx.json + data/fx.json,
## sheets in assets/fx). Moves without their own animation borrow one by type and category.

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

static func enabled() -> bool:
	return not Dialog.auto or OS.get_cmdline_user_args().has("--fx")

## Plays the whole animation for one use of a move. Returns when the blocking parts are done.
static func play(dg: Node, m: Mon, move_name: String, mv: Dictionary, d: int, targets: Array) -> void:
	if not enabled() or m.visual == null:
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

static func _screen_node(dg: Node, tex: Texture2D, frames: Array) -> FxNode:
	var cl := CanvasLayer.new()
	cl.layer = 3
	dg.add_child(cl)
	var n := FxNode.new()
	n.tex = tex
	n.frames = frames
	n.screen = true
	var vs: Vector2 = dg.get_viewport().get_visible_rect().size
	var s := maxf(vs.x / 256.0, vs.y / 192.0)
	n.scale = Vector2(s, s)
	n.position = (vs - Vector2(256, 192) * s) / 2.0
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
