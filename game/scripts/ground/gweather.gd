class_name GWeather
extends Node2D
## Red's ground weather (ground_weather.c): GroundWeather_Select puts a ground BG file (gUnknown_811E5F4) on an
## extra BG layer, blended with the map by BLDALPHA, and sub_80A60D8 scrolls it. Maps pick their weather
## from the conversion table (GroundMap_Select: map_conv.u6) and scripts with SELECT_WEATHER (CMD 0x0B).
## Placed in the ground world above the map and actors.

## weather id -> [type, ground BG file id]  (gUnknown_811E5F4)
const TABLE := [[0, 9], [0, 107], [0, 111], [0, 113], [0, 115], [0, 131], [0, 151], [0, 154], [0, 169],
	[1, 238], [1, 239], [1, 240], [1, 241], [1, 242], [1, 243], [1, 244]]

var G
var kind := -1
var info: Dictionary = {}
var base: Sprite2D
var overlays: Array = []          # [{node, frames: [[tex, pos, ticks]], t, i}]
var pal := {}                     # {img, tex, rows}
var lw := 1                       # layer size (GBA pixels)
var lh := 1
var k := 1.0                      # texture px per GBA px of the base layer
var c4 := Vector2i.ZERO           # unk4 / unk8 sub-pixel accumulators
var drift := Vector2i.ZERO        # unkC
var _mats: Array = []

func _init(ground) -> void:
	G = ground
	z_index = 10

func clear() -> void:
	kind = -1
	for c in get_children():
		c.queue_free()
	base = null
	overlays.clear()
	pal = {}
	_mats.clear()

## GroundWeather_Select
func select(w: int) -> void:
	clear()
	kind = w
	if w < 0 or w >= TABLE.size():
		return
	var fid := int(TABLE[w][1])
	info = {}
	for key in GData.ground_bg():
		if int(GData.ground_bg()[key].get("id", -1)) == fid:
			info = GData.ground_bg()[key]
			break
	if info.is_empty():
		return
	lw = int(info.get("w", 240))
	lh = int(info.get("h", 160))
	var layers: Array = info.get("layers", [])
	if layers.is_empty():
		return
	var bld := 0x1000
	match w:
		9, 15:
			bld = 0x40C
		7:
			bld = 0x808
		14, 0, 3, 4, 5, 8:
			bld = 0x1010
	var eva := float(bld & 0x1F) / 16.0
	var evb := float((bld >> 8) & 0x1F) / 16.0
	var lf := str(layers[0])
	base = Sprite2D.new()
	base.centered = false
	base.texture = GData.ground_tex(lf)
	if base.texture == null:
		base = null
		return
	k = float(base.texture.get_width()) / float(maxi(lw, 1))
	base.scale = Vector2.ONE / k
	base.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if k > 1.5 else CanvasItem.TEXTURE_FILTER_NEAREST
	base.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	base.region_enabled = true
	add_child(base)
	var an: Dictionary = info.get("anim", {})
	# BPL palette cycling (rows without overlays)
	var rows: Array = []
	for p in an.get("palettes", []):
		if not (p.get("overlays", []) as Array).is_empty():
			continue
		var cols: Array = p.get("colors", [])
		if cols.size() > 0:
			rows.append({"row": int(p.palette), "colors": cols, "ticks": maxi(1, int(p.get("frame_ticks", p.get("duration", 8)))), "t": 0, "i": 0})
	var idx_imgs: Dictionary = an.get("index_images", {})
	var mat := _material(eva, evb)
	if rows.size() > 0 and idx_imgs.has(lf):
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var bp: Array = an.get("base_palette", [])
		for r in mini(16, bp.size()):
			for c in mini(16, (bp[r] as Array).size()):
				img.set_pixel(c, r, Color(str(bp[r][c])))
		var mask := 0
		for rw in rows:
			mask |= 1 << int(rw.row)
		pal = {"img": img, "tex": ImageTexture.create_from_image(img), "rows": rows}
		mat.set_shader_parameter("idx_tex", GData.ground_tex(str(idx_imgs[lf]), false))
		mat.set_shader_parameter("pal_tex", pal.tex)
		mat.set_shader_parameter("anim_rows", mask)
		_pal_apply()
	base.material = mat
	# BPA tile animations: full-layer overlay frames
	for t in an.get("tiles", []):
		var frames: Array = t.get("frames", [])
		var ticks: Array = t.get("frame_ticks", [])
		var fl: Array = []
		for fi in frames.size():
			var fr: Dictionary = frames[fi]
			if fr.has(lf):
				fl.append([GData.ground_tex(str(fr[lf].file), false), Vector2(fr[lf].pos[0], fr[lf].pos[1]), int(ticks[fi]) if fi < ticks.size() else 8])
		if fl.is_empty():
			continue
		var s := Sprite2D.new()
		s.centered = false
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.texture = fl[0][0]
		s.position = fl[0][1]
		s.material = _material(eva, evb)
		base.add_child(s)
		s.scale = Vector2.ONE * k        # overlays are 1x: undo the base's HD down-scale
		overlays.append({"node": s, "frames": fl, "t": 0, "i": 0})
	c4 = Vector2i.ZERO
	drift = Vector2i.ZERO

func _material(eva: float, evb: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/ground_weather.gdshader")
	m.set_shader_parameter("eva", eva)
	m.set_shader_parameter("evb", evb)
	_mats.append(m)
	return m

func _pal_apply() -> void:
	var img: Image = pal.img
	for rw in pal.rows:
		var fr: Array = rw.colors[int(rw.i) % (rw.colors as Array).size()]
		for c in mini(15, fr.size()):
			img.set_pixel(c + 1, int(rw.row), Color(str(fr[c])))
	(pal.tex as ImageTexture).update(img)

## sub_80A60D8 + sub_80A62D0 (one game frame)
func tick() -> void:
	if base == null:
		return
	match kind:
		9:
			c4 += Vector2i(2, 1)
			drift += Vector2i(c4.x / 4, c4.y / 4)
			c4 = Vector2i(c4.x & 3, c4.y & 3)
		14:
			c4.x += 1
			drift.x += c4.x / 4
			c4.x &= 3
		15:
			c4.x += 2
			drift.x += c4.x / 4
			c4.x &= 3
	if not pal.is_empty():
		var changed := false
		for rw in pal.rows:
			rw.t += 1
			if rw.t >= int(rw.ticks):
				rw.t = 0
				rw.i = (int(rw.i) + 1) % (rw.colors as Array).size()
				changed = true
		if changed:
			_pal_apply()
	for a in overlays:
		var fr: Array = a.frames
		a.t += 1
		if a.t >= int(fr[a.i][2]):
			a.t = 0
			a.i = (a.i + 1) % fr.size()
			a.node.texture = fr[a.i][0]
			a.node.position = fr[a.i][1]

## Position the layer for the visible world rect (top-left 'off', size 'view' in GBA pixels).
func place(off: Vector2, view: Vector2) -> void:
	if base == null:
		return
	# BG scroll = camera (- drift): the layer follows the map; drifting kinds wrap around
	var scroll := Vector2(-drift.x, drift.y)
	var top := 0.0
	if kind == 14 or kind == 15:
		scroll.y = 0.0
		top = off.y                 # pixPos.y = 0: fixed to the top of the screen
	var mw := maxf(float(G.map_info.get("w", lw)), view.x + off.x)
	var mh := maxf(float(G.map_info.get("h", lh)), view.y + off.y)
	if kind in [9, 14, 15]:
		base.position = Vector2(0, top)
		base.region_rect = Rect2(Vector2(posmod(int(scroll.x), lw), posmod(int(scroll.y), lh)) * k, Vector2(mw, mh) * k)
		for a in overlays:
			a.node.visible = false      # the drifting layers have no BPA frames
	else:
		base.position = Vector2.ZERO
		base.region_rect = Rect2(Vector2.ZERO, Vector2(lw, lh) * k)
