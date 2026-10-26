class_name TerrainView
extends Node2D
## Renders a floor's terrain from a Red tileset using the auto-tiling rules
## (8-neighbour mask -> block index, 3 variants per mask). Uses the HD (3x) tileset when present.

const T := 24
var tex_sprite: Sprite2D
var hd_k := 1

## Palette animation state (Red bNNcanm): one entry per animated colour slot that has colours.
var _anim: Array = []                # [{k, dur, cols: [Color], t, p}]
var _pal_img: Image
var _pal_tex: ImageTexture
var _acc := 0.0

func build(fl: Dictionary, ts_key: String) -> void:
	for c in get_children():
		c.queue_free()
	_anim = []
	if DungeonGfx.is_arena(ts_key):
		_build_arena(fl, ts_key)
		return
	var ts: Dictionary = DB.tilesets.get(ts_key, DB.tilesets.get("t14"))
	var path: String = "res://assets/tiles/" + ts.img
	var hd := false
	if ts.has("hd") and ResourceLoader.exists("res://assets/tiles/" + ts.hd):
		path = "res://assets/tiles/" + ts.hd
		hd = true
	var src_tex: Texture2D = load(path)
	var src: Image = src_tex.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	hd_k = 3 if hd else 1
	var B := T * hd_k
	var cols := int(ts.get("cols", 10))
	var rules: Array = ts.rules
	var w: int = fl.w
	var h: int = fl.h
	var terr: PackedByteArray = fl.terrain
	var out := Image.create(w * B, h * B, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 1))
	# palette-animation index image (1x, same block layout); null when the tileset has none
	var ts_no := DungeonGfx.tileset_no(ts_key)
	var isrc: Image = _idx_image("tidx_r%02d.png" % ts_no) if ts_no >= 0 else null
	var iout: Image = null
	if isrc:
		iout = Image.create(w * T, h * T, false, Image.FORMAT_RGBA8)
		iout.fill(Color(0, 0, 0, 1))
	var floor_full: int = int(rules[(512 + 255) * 3])
	for y in h:
		for x in w:
			var me := _t(terr, w, h, x, y)
			var dst := Vector2i(x * B, y * B)
			if me == 2:
				_blit(out, src, floor_full, cols, B, dst, false)
				if iout:
					_blit(iout, isrc, floor_full, cols, T, Vector2i(x * T, y * T), false)
			var mask := 0
			for k in 8:
				var d: Vector2i = DB.DIRS[k]
				var n := _t(terr, w, h, x + d.x, y + d.y)
				var same := false
				if me == 0:
					same = n == 0
				elif me == 2:
					same = n == 2
				else:
					same = n != 0
				if same:
					mask |= 1 << k
			if me == 1:
				mask += 512
			elif me == 2:
				mask += 256
			var v := int(floor(_hash(x, y, 5) * 3.0))
			var block: int = int(rules[v + mask * 3])
			_blit(out, src, block, cols, B, dst, me == 2)
			if iout:
				_blit(iout, isrc, block, cols, T, Vector2i(x * T, y * T), me == 2)
	# past the map's edge: solid wall tiles instead of black (zoomed out / wide screens)
	var wall_img := Image.create(B, B, false, Image.FORMAT_RGBA8)
	_blit(wall_img, src, int(rules[0 + 255 * 3]), cols, B, Vector2i.ZERO, false)
	var fill := Sprite2D.new()
	fill.texture = ImageTexture.create_from_image(wall_img)
	fill.centered = false
	fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	fill.region_enabled = true
	const M := 24
	fill.region_rect = Rect2(0, 0, (w + 2 * M) * B, (h + 2 * M) * B)
	fill.position = Vector2(-M * T, -M * T)
	fill.scale = Vector2.ONE / float(hd_k)
	fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if hd else CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(fill)
	var tex := ImageTexture.create_from_image(out)
	tex_sprite = Sprite2D.new()
	tex_sprite.texture = tex
	tex_sprite.centered = false
	tex_sprite.scale = Vector2.ONE / float(hd_k)
	tex_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if hd else CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(tex_sprite)
	if iout:
		_setup_anim(ts_no, iout)

## Boss arena (Red tilesets 64+): the 24x24-block emap0 picture at the map's top-left, black elsewhere
## (dungeon_map_access.c: tileset >= 0x40 takes block emap0[y*24+x] for x,y < 24, block 0 = black otherwise).
func _build_arena(fl: Dictionary, ts_key: String) -> void:
	var t := DungeonGfx.tileset_no(ts_key)
	var ar: Dictionary = DungeonGfx.data().arenas[str(t)]
	var hd := ResourceLoader.exists(DungeonGfx.DIR + str(ar.hd))
	var src_tex: Texture2D = DungeonGfx.tex(str(ar.hd) if hd else str(ar.img))
	var src: Image = src_tex.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	hd_k = 3 if hd else 1
	var B := T * hd_k
	var w: int = fl.w
	var h: int = fl.h
	var out := Image.create(w * B, h * B, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 1))
	var n := int(ar.get("size", 24))
	var cw := mini(n, w) * B
	var ch := mini(n, h) * B
	out.blit_rect(src, Rect2i(0, 0, mini(cw, src.get_width()), mini(ch, src.get_height())), Vector2i.ZERO)
	tex_sprite = Sprite2D.new()
	tex_sprite.texture = ImageTexture.create_from_image(out)
	tex_sprite.centered = false
	tex_sprite.scale = Vector2.ONE / float(hd_k)
	tex_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if hd else CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(tex_sprite)
	var isrc := _idx_image(str(ar.get("idx", "")))
	if isrc:
		var iout := Image.create(w * T, h * T, false, Image.FORMAT_RGBA8)
		iout.fill(Color(0, 0, 0, 1))
		iout.blit_rect(isrc, Rect2i(0, 0, mini(n, w) * T, mini(n, h) * T), Vector2i.ZERO)
		_setup_anim(t, iout)

static func _idx_image(file: String) -> Image:
	var tx := DungeonGfx.tex(file)
	if tx == null:
		return null
	var im: Image = tx.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	return im

## Red's UpdateAnimatedColors: each of the 32 animated colours (BG 160..191) steps through its own colour
## list every 'duration' frames (60 Hz). The first step repeats colour 0 (currentColor starts at colorsStart).
func _setup_anim(t: int, iout: Image) -> void:
	var an := DungeonGfx.anim(t)
	if an.is_empty():
		return
	_pal_img = Image.create(32, 2, false, Image.FORMAT_RGBA8)
	for k in mini(32, an.size()):
		var e: Array = an[k]
		var base := Color(str(e[2]))
		_pal_img.set_pixel(k, 0, base)
		_pal_img.set_pixel(k, 1, base)
		var cols: Array = []
		for c in e[1]:
			cols.append(Color(str(c)))
		if cols.size() > 0 and int(e[0]) > 0:
			_anim.append({"k": k, "dur": int(e[0]), "cols": cols, "t": int(e[0]), "p": 0})
			_pal_img.set_pixel(k, 0, cols[0])
	if _anim.is_empty():
		return
	_pal_tex = ImageTexture.create_from_image(_pal_img)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/dungeon_palette.gdshader")
	mat.set_shader_parameter("idx_tex", ImageTexture.create_from_image(iout))
	mat.set_shader_parameter("pal_tex", _pal_tex)
	tex_sprite.material = mat

func _process(dt: float) -> void:
	if _anim.is_empty() or _pal_tex == null:
		return
	_acc += dt * 60.0
	var steps := mini(int(_acc), 8)
	if steps <= 0:
		return
	_acc -= float(int(_acc))
	var changed := false
	for _s in steps:
		for a in _anim:
			a.t -= 1
			if a.t <= 0:
				a.t = a.dur
				var cols: Array = a.cols
				_pal_img.set_pixel(int(a.k), 0, cols[int(a.p)])
				a.p = (int(a.p) + 1) % cols.size()
				changed = true
	if changed:
		_pal_tex.update(_pal_img)

static func _t(terr: PackedByteArray, w: int, h: int, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return 0
	var v := terr[y * w + x]
	return 2 if v >= 2 else v

static func _blit(out: Image, src: Image, block: int, cols: int, B: int, dst: Vector2i, blend: bool) -> void:
	var r := Rect2i((block % cols) * B, (block / cols) * B, B, B)
	if blend:
		out.blend_rect(src, r, dst)
	else:
		out.blit_rect(src, r, dst)

## Same hash as the old remake, so variants look the same.
static func _hash(x: int, y: int, k: int) -> float:
	var h: int = (x * 374761393 + y * 668265263 + k * 2147483647) & 0xFFFFFFFF
	h = _s32(h)
	h = _s32(((h ^ (_u32(h) >> 13)) * 1274126177) & 0xFFFFFFFF)
	var r: int = _u32(h ^ (_u32(h) >> 16))
	return float(r) / 4294967295.0

static func _s32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v

static func _u32(v: int) -> int:
	return v & 0xFFFFFFFF
