extends RefCounted
## Remake: a Pokémon's current sprite frame as a rounded voxel figure for the 3D view. Every opaque pixel is a
## column whose thickness grows with its distance from the sprite's edge (thin at the silhouette, thick in the
## middle, at most 9 cubes); the dark outline stays a thin rim. Meshes are cached per frame. Local space:
## x = pixel column, y = rows counted up from the frame's bottom row, z = 0 the figure's middle plane.
## Loaded by path (no class_name).

const TH_MAX := 4.5
const TH_K := 1.6
static var _cache := {}
static var _imgs := {}

static func sheet_image(path: String) -> Image:
	if _imgs.has(path):
		return _imgs[path]
	var tex: Texture2D = DB.tex(path)
	var img: Image = tex.get_image() if tex else null
	if img:
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
	_imgs[path] = img
	return img

static func clear_cache() -> void:
	_cache.clear()
	_imgs.clear()

## The mesh for frame `src` of sheet `path` (shiny: species key for the shiny colours, "" = normal).
static func mesh_for(path: String, src: Rect2, shiny_sp := "") -> ArrayMesh:
	var key := "%s|%d|%d|%d|%d|%s" % [path, src.position.x, src.position.y, src.size.x, src.size.y, shiny_sp]
	if _cache.has(key):
		return _cache[key]
	var img := sheet_image(path)
	var m: ArrayMesh = null
	if img != null and src.end.x <= img.get_width() and src.end.y <= img.get_height():
		m = _build(img.get_region(Rect2i(src)), _shiny_map(shiny_sp))
	if _cache.size() > 1500:
		_cache.clear()
	_cache[key] = m
	return m

static func _shiny_map(sp: String) -> Dictionary:
	if sp == "":
		return {}
	var dat: Dictionary = Shiny.data()
	var k := sp if dat.has(sp) else sp.substr(0, 4)
	var out := {}
	for r in dat.get(k, {}).get("s", []):
		out[(int(r[0]) << 16) | (int(r[1]) << 8) | int(r[2])] = Color8(int(r[3]), int(r[4]), int(r[5]))
	return out

static func _build(f: Image, shiny: Dictionary) -> ArrayMesh:
	var w := f.get_width()
	var h := f.get_height()
	var md := PackedInt32Array()
	md.resize(w * h)
	var col := PackedColorArray()
	col.resize(w * h)
	for y in h:
		for x in w:
			var c := f.get_pixel(x, y)
			if c.a >= 0.5 and not shiny.is_empty():
				var k := (c.r8 << 16) | (c.g8 << 8) | c.b8
				if shiny.has(k):
					c = shiny[k]
			col[y * w + x] = c
			md[y * w + x] = 999 if c.a >= 0.5 else 0
	for it in 2:
		var ys := range(h) if it == 0 else range(h - 1, -1, -1)
		var xs := range(w) if it == 0 else range(w - 1, -1, -1)
		for y in ys:
			for x in xs:
				var i: int = y * w + x
				if md[i] == 0:
					continue
				var v := md[i]
				v = mini(v, (md[i - 1] if x > 0 else 0) + 1)
				v = mini(v, (md[i + 1] if x < w - 1 else 0) + 1)
				v = mini(v, (md[i - w] if y > 0 else 0) + 1)
				v = mini(v, (md[i + w] if y < h - 1 else 0) + 1)
				md[i] = v
	var half := PackedFloat32Array()
	half.resize(w * h)
	for i in w * h:
		if md[i] == 0:
			continue
		var c: Color = col[i]
		var outline := c.get_luminance() < 0.14 and md[i] <= 1
		half[i] = 0.5 if outline else minf(TH_MAX, 0.5 + sqrt(float(md[i])) * TH_K)
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var q := func(a: Vector3, b: Vector3, cc: Vector3, dd: Vector3, nrm: Vector3, cl: Color) -> void:
		V.append_array([a, b, cc, a, cc, dd])
		for k in 6:
			N.append(nrm)
			C.append(cl)
	for y in h:
		for x in w:
			var i := y * w + x
			var hz: float = half[i]
			if hz <= 0.0:
				continue
			var c: Color = col[i]
			var X := float(x)
			var Y := float(h - 1 - y)
			q.call(Vector3(X, Y, hz), Vector3(X, Y + 1, hz), Vector3(X + 1, Y + 1, hz), Vector3(X + 1, Y, hz), Vector3.BACK, c)
			q.call(Vector3(X + 1, Y, -hz), Vector3(X + 1, Y + 1, -hz), Vector3(X, Y + 1, -hz), Vector3(X, Y, -hz), Vector3.FORWARD, c.darkened(0.15))
			# sides where the neighbour is thinner (or missing): front and back strips
			var nb := [[1, 0, Vector3.RIGHT], [-1, 0, Vector3.LEFT], [0, -1, Vector3.UP], [0, 1, Vector3.DOWN]]
			for e in nb:
				var nx: int = x + e[0]
				var ny: int = y + e[1]
				var nh := 0.0 if (nx < 0 or ny < 0 or nx >= w or ny >= h) else half[ny * w + nx]
				if nh >= hz:
					continue
				var nrm: Vector3 = e[2]
				var sc := c.darkened(0.12 if nrm.y == 0.0 else (0.0 if nrm.y > 0.0 else 0.3))
				var a0: Vector3
				var a1: Vector3
				match nrm:
					Vector3.RIGHT:
						a0 = Vector3(X + 1, Y, 0)
						a1 = Vector3(X + 1, Y + 1, 0)
					Vector3.LEFT:
						a0 = Vector3(X, Y + 1, 0)
						a1 = Vector3(X, Y, 0)
					Vector3.UP:
						a0 = Vector3(X + 1, Y + 1, 0)
						a1 = Vector3(X, Y + 1, 0)
					_:
						a0 = Vector3(X, Y, 0)
						a1 = Vector3(X + 1, Y, 0)
				q.call(a0 + Vector3(0, 0, nh), a1 + Vector3(0, 0, nh), a1 + Vector3(0, 0, hz), a0 + Vector3(0, 0, hz), nrm, sc)
				q.call(a0 + Vector3(0, 0, -hz), a1 + Vector3(0, 0, -hz), a1 + Vector3(0, 0, -nh), a0 + Vector3(0, 0, -nh), nrm, sc)
	if V.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m
