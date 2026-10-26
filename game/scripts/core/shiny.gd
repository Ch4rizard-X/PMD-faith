class_name Shiny
extends RefCounted
## Shiny Pokémon (Rescue Team DX): now and then a wild Pokémon is shiny. It sparkles when it comes into view,
## and stays shiny if it joins the team. The colours come from SpriteCollab's shiny sprites and portraits
## (data/shiny.json, made by gen_shiny.py): sprites are recoloured by shaders/shiny.gdshader, portraits on the CPU.

const RATE := 200                 # 1 wild Pokémon in RATE
const MAXC := 16
static var _data := {}
static var _mats := {}
static var _por := {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/shiny.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text()) if f else {}
		if _data == null or _data.is_empty():
			_data = {"_": {}}
	return _data

static func is_shiny(m) -> bool:
	return m != null and bool(m.get_meta("shiny", false))

static func roll(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, RATE - 1) == 0

## Bosses and story legendaries (shiny hunting by re-entering): 1 in 50, 1 in 20 after the story.
const BOSS_RATE := 50
const BOSS_RATE_POSTGAME := 20
static func roll_boss(rng: RandomNumberGenerator) -> bool:
	return rng.randi_range(0, (BOSS_RATE_POSTGAME if RedShops.postgame() else BOSS_RATE) - 1) == 0

## The sprite material for a shiny of this species (null when SpriteCollab has no shiny colours for it).
static func material(sp: String) -> ShaderMaterial:
	var k := sp if data().has(sp) else sp.substr(0, 4)      # Mega sheets have their own colours
	if _mats.has(k):
		return _mats[k]
	var rows: Array = data().get(k, {}).get("s", [])
	var mat: ShaderMaterial = null
	if not rows.is_empty():
		mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/shiny.gdshader")
		var s := PackedVector3Array()
		var d := PackedVector3Array()
		for i in MAXC:
			var r: Array = rows[i] if i < rows.size() else [0, 0, 0, 0, 0, 0]
			s.append(Vector3(r[0], r[1], r[2]) / 255.0)
			d.append(Vector3(r[3], r[4], r[5]) / 255.0)
		mat.set_shader_parameter("n", mini(rows.size(), MAXC))
		mat.set_shader_parameter("src", s)
		mat.set_shader_parameter("dst", d)
	_mats[k] = mat
	return mat

## A portrait recoloured with the shiny portrait colours.
static func portrait(at: AtlasTexture, sp: String) -> Texture2D:
	var k := sp.substr(0, 4)
	var key := "%s|%s" % [k, at.region]
	if _por.has(key):
		return _por[key]
	var rows: Array = data().get(k, {}).get("p", [])
	if rows.is_empty() or at.atlas == null:
		return at
	var img := at.atlas.get_image().get_region(Rect2i(at.region))
	img.convert(Image.FORMAT_RGBA8)
	var map := {}
	for r in rows:
		map[(int(r[0]) << 16) | (int(r[1]) << 8) | int(r[2])] = Color8(int(r[3]), int(r[4]), int(r[5]))
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.0:
				continue
			var kk := (c.r8 << 16) | (c.g8 << 8) | c.b8
			if map.has(kk):
				var nc: Color = map[kk]
				nc.a = c.a
				img.set_pixel(x, y, nc)
	var t := ImageTexture.create_from_image(img)
	_por[key] = t
	return t

## Portrait key for Dialog.portrait_tex: "0025*" draws the shiny portrait.
static func por_key(sp: String, shiny: bool) -> String:
	return sp + "*" if shiny else sp
