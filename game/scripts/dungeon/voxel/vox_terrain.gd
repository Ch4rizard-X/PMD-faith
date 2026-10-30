extends RefCounted
## Remake: the 3D (voxel) dungeon terrain, built from the floor's own tile picture (TerrainView) and its
## wall / floor / water / chasm grid. One world unit = one pixel of the GBA tiles (24 per tile); the floor's
## top is at y = 1. Walls stand WH high with rounded edges, stone faces in the tileset's cliff colours, and
## decorations that depend on the wall material read from the tile colours (grass, rock, snow, cloud,
## crystal). Water and lava sink below the floor, chasms drop deep. Past the map edge everything is wall.
## Built per chunk (CT x CT tiles) on worker threads; see voxel_view.gd. Loaded by path (no class_name).

const TW := 24
const CT := 4                      # chunk size in tiles
const WH := 15.0                   # wall height
const WT_D := 3.0                  # water: bed at -WT_D, surface at -1.5
const LV_Y := -0.5                 # lava surface
const CH_D := 40.0                 # chasm depth
const STAIRS := 5                  # terrain value of the stairs tile in the 3D view (floor everywhere else)
const BORDER := 6                  # wall tiles added around the map (no black edges)

## Material of the walls from their top colours (and corrections for tilesets the test misreads).
const EOS_MAT_FIX := {3: "rock", 6: "rock", 23: "crystal", 34: "rock", 39: "rock", 57: "rock", 59: "rock", 64: "rock",
	118: "rock", 128: "grass"}
const MAT_FIX := {40: "rock", 42: "rock", 43: "rock", 55: "rock", 49: "rock", 54: "rock", 16: "rock"}

## Floor data for the builder: the extended picture and grid. Called on the main thread.
static func prepare(dg) -> Dictionary:
	var fs = dg.fs
	var tv = dg.terrain_view
	var src: Image = tv.tex_sprite.texture.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	if tv.hd_k != 1:
		src.resize(fs.w * TW, fs.h * TW, Image.INTERPOLATE_NEAREST)
	var wall: Image = tv.wall_block if tv.get("wall_block") != null else null
	var EW: int = fs.w + 2 * BORDER
	var EH: int = fs.h + 2 * BORDER
	var img := Image.create(EW * TW, EH * TW, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.1))
	if wall != null:
		var wb := wall.duplicate()
		if wb.is_compressed():
			wb.decompress()
		wb.convert(Image.FORMAT_RGBA8)
		if wb.get_width() != TW:
			wb.resize(TW, TW, Image.INTERPOLATE_NEAREST)
		for ty in EH:
			for tx in EW:
				img.blit_rect(wb, Rect2i(0, 0, TW, TW), Vector2i(tx * TW, ty * TW))
	img.blit_rect(src, Rect2i(0, 0, fs.w * TW, fs.h * TW), Vector2i(BORDER * TW, BORDER * TW))
	var terr := PackedByteArray()
	terr.resize(EW * EH)
	for y in fs.h:
		for x in fs.w:
			terr[(y + BORDER) * EW + x + BORDER] = fs.terrain[y * fs.w + x]
	if fs.stairs.x >= 0 and fs.terrain[fs.stairs.y * fs.w + fs.stairs.x] == 1:
		terr[(fs.stairs.y + BORDER) * EW + fs.stairs.x + BORDER] = STAIRS     # an opening with steps going down
	var d := {"img": img, "data": img.get_data(), "EW": EW, "EH": EH, "terr": terr, "sec": str(fs.secondary)}
	_material(d, dg)
	return d

static func _px(d: Dictionary, gx: int, gy: int) -> Color:
	var W: int = d.EW * TW
	gx = clampi(gx, 0, W - 1)
	gy = clampi(gy, 0, d.EH * TW - 1)
	var i: int = (gy * W + gx) * 4
	var b: PackedByteArray = d.data
	return Color8(b[i], b[i + 1], b[i + 2])

static func _ter(d: Dictionary, gx: int, gy: int) -> int:
	var tx := floori(gx / float(TW))
	var ty := floori(gy / float(TW))
	if tx < 0 or ty < 0 or tx >= d.EW or ty >= d.EH:
		return 0
	return d.terr[ty * d.EW + tx]

static func _material(d: Dictionary, dg) -> void:
	var hx := 0.0
	var hy := 0.0
	var sat := 0.0
	var lum := 0.0
	var green := 0
	var n := 0
	var band: Array = []
	var W: int = d.EW * TW
	var H: int = d.EH * TW
	var b0 := BORDER * TW
	for gy in range(b0, H - b0, 5):
		for gx in range(b0, W - b0, 5):
			if _ter(d, gx, gy) != 0:
				continue
			var c := _px(d, gx, gy)
			var edge := false
			for o in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4)]:
				if _ter(d, gx + o.x, gy + o.y) != 0:
					edge = true
			if edge:
				band.append(c)
				continue
			hx += cos(c.h * TAU) * c.s
			hy += sin(c.h * TAU) * c.s
			sat += c.s
			lum += c.get_luminance()
			if c.g > c.r * 1.15 and c.g > c.b * 1.25:
				green += 1
			n += 1
	n = maxi(n, 1)
	sat /= n
	lum /= n
	var hue := fposmod(atan2(hy, hx) / TAU, 1.0) * 360.0
	var mat := "rock"
	if float(green) / n > 0.35:
		mat = "grass"
	elif lum > 0.88 and hue > 180.0 and hue < 250.0 and sat < 0.5:
		mat = "cloud"
	elif lum > 0.8 and sat < 0.22:
		mat = "snow"
	elif sat > 0.45 and hue > 190.0 and hue < 320.0:
		mat = "crystal"
	elif lum > 0.55 and hue > 25.0 and hue < 65.0 and sat > 0.35:
		mat = "desert"
	var ts := -1
	var fd: Dictionary = dg.ddata.floors[dg.floor_i]
	if fd.has("props") and not fd.has("eos_tileset"):
		ts = int(fd.props[2])
	if MAT_FIX.has(ts):
		mat = MAT_FIX[ts]
	if fd.has("eos_tileset") and EOS_MAT_FIX.has(int(fd.eos_tileset)):
		mat = EOS_MAT_FIX[int(fd.eos_tileset)]
	band.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
	var pal: Array = []
	if band.size() > 10:
		for k in 6:
			pal.append(band[int(band.size() * (0.08 + 0.12 * k))])
	else:
		pal = [Color(0.35, 0.3, 0.27), Color(0.45, 0.4, 0.36), Color(0.55, 0.5, 0.45)]
	d["mat"] = mat
	d["pal"] = pal
	dg.set_meta("vox_material", mat)

## The stairs: the floor picture around a stone-rimmed opening, steps going down away from the camera and
## darker the deeper they are, the opening's inner sides and back wall in shadow.
static func _stairs(S, wx0: float, wz0: float, uv0: Vector2, uv1: Vector2) -> void:
	var I := 4.0                                   # rim width
	var xa := wx0 + I
	var xb := wx0 + TW - I
	var za := wz0 + I
	var zb := wz0 + TW - I
	var fuv := func(x: float, z: float) -> Vector2:
		return Vector2(lerpf(uv0.x, uv1.x, (x - wx0) / TW), lerpf(uv0.y, uv1.y, (z - wz0) / TW))
	var fq := func(x0: float, z0: float, x1: float, z1: float) -> void:   # a piece of floor at y = 1
		S.quad(Vector3(x0, 1, z0), Vector3(x1, 1, z0), Vector3(x1, 1, z1), Vector3(x0, 1, z1), Vector3.UP, Color(1, 1, 1, 1),
			fuv.call(x0, z0), fuv.call(x1, z0), fuv.call(x1, z1), fuv.call(x0, z1))
	fq.call(wx0, wz0, wx0 + TW, za)
	fq.call(wx0, zb, wx0 + TW, wz0 + TW)
	fq.call(wx0, za, xa, zb)
	fq.call(xb, za, wx0 + TW, zb)
	var rim := Color(0.62, 0.6, 0.58, 1)
	var n := 5
	var rise := 1.1                                # gentler than the lowest camera (35 deg), so every step shows
	var dd := (zb - za) / n
	var bottom := 1.0 - (n + 1) * rise
	for k in n:
		var z1 := zb - k * dd
		var z0 := z1 - dd
		var y := 1.0 - (k + 1) * rise
		var sh := 1.0 - 0.11 * k
		var stone := Color(0.74 * sh, 0.72 * sh, 0.7 * sh, 1)
		S.quad(Vector3(xa, y, z0), Vector3(xb, y, z0), Vector3(xb, y, z1), Vector3(xa, y, z1), Vector3.UP, stone, Vector2(-1, -1))
		# the step's front edge, a little lighter
		S.quad(Vector3(xa, y + 0.01, z1 - 0.8), Vector3(xb, y + 0.01, z1 - 0.8), Vector3(xb, y + 0.01, z1), Vector3(xa, y + 0.01, z1),
			Vector3.UP, stone.lightened(0.18), Vector2(-1, -1))
		# under the step down to the next one (seen only from above at the back)
		S.quad(Vector3(xa, y - rise, z0), Vector3(xb, y - rise, z0), Vector3(xb, y, z0), Vector3(xa, y, z0), Vector3.BACK,
			stone.darkened(0.35), Vector2(-1, -1))
	# inner sides and back wall of the opening, in shadow, darker toward the bottom
	for side in [[xa, Vector3.RIGHT], [xb, Vector3.LEFT]]:
		var x: float = side[0]
		S.quad(Vector3(x, bottom, za), Vector3(x, bottom, zb), Vector3(x, 1, zb), Vector3(x, 1, za), side[1], Color(0.42, 0.4, 0.38, 1), Vector2(-1, -1))
	S.quad(Vector3(xa, bottom, za), Vector3(xb, bottom, za), Vector3(xb, 1, za), Vector3(xa, 1, za), Vector3.BACK, Color(0.2, 0.19, 0.19, 1), Vector2(-1, -1))
	# the stone rim around the opening
	for r in [[xa - 1, za - 1, xb + 1, za], [xa - 1, zb, xb + 1, zb + 1], [xa - 1, za, xa, zb], [xb, za, xb + 1, zb]]:
		S.quad(Vector3(r[0], 1.05, r[1]), Vector3(r[2], 1.05, r[1]), Vector3(r[2], 1.05, r[3]), Vector3(r[0], 1.05, r[3]), Vector3.UP, rim, Vector2(-1, -1))

static func _hsh(a: int, b: int, c: int) -> float:
	var n := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0

static func _green(c: Color) -> bool:
	return c.g > c.r * 1.15 and c.g > c.b * 1.25 and c.s > 0.35 and c.get_luminance() > 0.28

# ------------------------------------------------------------------ chunk builder (worker thread)
class Out:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func quad(a: Vector3, b: Vector3, cc: Vector3, dd: Vector3, nrm: Vector3, col: Color, uva: Vector2, uvb := Vector2.INF, uvc := Vector2.INF, uvd := Vector2.INF) -> void:
		if uvb == Vector2.INF:
			uvb = uva
			uvc = uva
			uvd = uva
		v.append_array([a, b, cc, a, cc, dd])
		for i in 6:
			n.append(nrm)
			c.append(col)
		uv.append_array([uva, uvb, uvc, uva, uvc, uvd])

	func box(p: Vector3, s: Vector3, col: Color, sides := 31) -> void:
		var x0 := p.x
		var x1 := p.x + s.x
		var y0 := p.y
		var y1 := p.y + s.y
		var z0 := p.z
		var z1 := p.z + s.z
		var u := Vector2(-1, -1)
		if sides & 1:
			quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, col, u)
		if sides & 2:
			quad(Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3.BACK, col.darkened(0.08), u)
		if sides & 4:
			quad(Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3.FORWARD, col.darkened(0.08), u)
		if sides & 8:
			quad(Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3.RIGHT, col.darkened(0.15), u)
		if sides & 16:
			quad(Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3.LEFT, col.darkened(0.15), u)

	func arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_COLOR] = c
		a[Mesh.ARRAY_TEX_UV] = uv
		return a

## Builds chunk (cx, cy) of the extended grid. Returns {solid, water, lava: mesh arrays or null,
## blades: [[Vector3 base, height, Color, flower]]} in world units relative to the map's top-left.
static func build_chunk(d: Dictionary, cx: int, cy: int, opts: Dictionary) -> Dictionary:
	var RR: float = 12.0 if d.mat == "cloud" else 6.0
	var FACE_H := int(WH - RR)
	var M := int(RR) + 2
	var X0 := cx * CT * TW
	var Y0 := cy * CT * TW
	var X1 := mini(X0 + CT * TW, d.EW * TW)
	var Y1 := mini(Y0 + CT * TW, d.EH * TW)
	var W := (X1 - X0) + 2 * M
	var H := (Y1 - Y0) + 2 * M
	var ox := BORDER * TW                # world offset: the map's top-left is 0, 0
	var TWX: float = d.EW * TW
	var TWY: float = d.EH * TW
	var grass_rate: float = float(opts.get("grass", 0.33))
	var sec: String = d.sec
	var pal: Array = d.pal
	var mat: String = d.mat
	# terrain + distance (3-4 chamfer, in thirds of a pixel) of wall pixels to the nearest non-wall pixel
	var T := PackedByteArray()
	T.resize(W * H)
	var dist := PackedInt32Array()
	dist.resize(W * H)
	for y in H:
		for x in W:
			var t := _ter(d, X0 - M + x, Y0 - M + y)
			T[y * W + x] = t
			dist[y * W + x] = 0 if t != 0 else 9999
	for y in H:
		for x in W:
			var i := y * W + x
			var v := dist[i]
			if v == 0:
				continue
			if x > 0: v = mini(v, dist[i - 1] + 3)
			if y > 0:
				v = mini(v, dist[i - W] + 3)
				if x > 0: v = mini(v, dist[i - W - 1] + 4)
				if x < W - 1: v = mini(v, dist[i - W + 1] + 4)
			dist[i] = v
	for y in range(H - 1, -1, -1):
		for x in range(W - 1, -1, -1):
			var i := y * W + x
			var v := dist[i]
			if v == 0:
				continue
			if x < W - 1: v = mini(v, dist[i + 1] + 3)
			if y < H - 1:
				v = mini(v, dist[i + W] + 3)
				if x < W - 1: v = mini(v, dist[i + W + 1] + 4)
				if x > 0: v = mini(v, dist[i + W - 1] + 4)
			dist[i] = v
	# heights: wall tops rounded within RR of an edge; floor 1; water bed; lava; chasm bottom
	var HT := PackedFloat32Array()
	HT.resize(W * H)
	for y in H:
		for x in W:
			var i := y * W + x
			match T[i]:
				0:
					var ed := dist[i] / 3.0 - 1.0
					var top := WH
					if ed < RR:
						top = WH - RR + sqrt(maxf(0.0, RR * RR - (RR - ed) * (RR - ed)))
					HT[i] = roundf(top)
				1, STAIRS:
					HT[i] = 1.0
				2:
					HT[i] = LV_Y if sec == "lava" else -WT_D
				_:
					HT[i] = -CH_D
	var S := Out.new()
	var WA := Out.new()
	var LA := Out.new()
	var blades: Array = []
	var uvp := func(gx: int, gy: int) -> Vector2: return Vector2((gx + 0.5) / TWX, (gy + 0.5) / TWY)
	# ---- tiles: flat floor / interior wall tops / water / lava / chasm as one textured quad each
	for ty in range(Y0 / TW, Y1 / TW):
		for tx in range(X0 / TW, X1 / TW):
			var t: int = d.terr[ty * d.EW + tx] if tx < d.EW and ty < d.EH else 0
			var gx0 := tx * TW
			var gy0 := ty * TW
			var wx0 := float(gx0 - ox)
			var wz0 := float(gy0 - ox)
			var uv0 := Vector2(gx0 / TWX, gy0 / TWY)
			var uv1 := Vector2((gx0 + TW) / TWX, (gy0 + TW) / TWY)
			var flat := true
			var y := 1.0
			var col := Color(1, 1, 1, 1)
			if t == 0:
				y = WH
				for py in range(0, TW, 3):           # interior wall tile: every pixel at full height
					for px in range(0, TW, 3):
						var li: int = (gy0 + py - Y0 + M) * W + (gx0 + px - X0 + M)
						if HT[li] < WH:
							flat = false
				if flat:
					for py in [0, TW - 1]:
						for px in [0, TW - 1]:
							var li2: int = (gy0 + py - Y0 + M) * W + (gx0 + px - X0 + M)
							if HT[li2] < WH:
								flat = false
			elif t == 2:
				var bed := Color(0.45, 0.45, 0.5, 1)
				if sec == "lava":
					LA.quad(Vector3(wx0, LV_Y, wz0), Vector3(wx0 + TW, LV_Y, wz0), Vector3(wx0 + TW, LV_Y, wz0 + TW), Vector3(wx0, LV_Y, wz0 + TW), Vector3.UP, col, uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y))
				else:
					S.quad(Vector3(wx0, -WT_D, wz0), Vector3(wx0 + TW, -WT_D, wz0), Vector3(wx0 + TW, -WT_D, wz0 + TW), Vector3(wx0, -WT_D, wz0 + TW), Vector3.UP, bed, uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y))
					WA.quad(Vector3(wx0, -1.5, wz0), Vector3(wx0 + TW, -1.5, wz0), Vector3(wx0 + TW, -1.5, wz0 + TW), Vector3(wx0, -1.5, wz0 + TW), Vector3.UP, col, uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y))
				continue
			elif t == STAIRS:
				_stairs(S, wx0, wz0, uv0, uv1)
				continue
			elif t == 3:
				var cc := Color(0.55, 0.55, 0.6, 1)
				S.quad(Vector3(wx0, -CH_D, wz0), Vector3(wx0 + TW, -CH_D, wz0), Vector3(wx0 + TW, -CH_D, wz0 + TW), Vector3(wx0, -CH_D, wz0 + TW), Vector3.UP, cc, uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y))
				continue
			if not flat:
				continue
			# corner shading: floor corners beside a wall are darker (vertex colour alpha = AO)
			var ao := [1.0, 1.0, 1.0, 1.0]
			if t == 1:
				var corners := [Vector2i(0, 0), Vector2i(TW, 0), Vector2i(TW, TW), Vector2i(0, TW)]
				for k in 4:
					var q: Vector2i = corners[k]
					var walls := 0
					for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
						if _ter(d, gx0 + q.x + o.x, gy0 + q.y + o.y) == 0:
							walls += 1
					ao[k] = 1.0 - 0.18 * walls
			var a := Vector3(wx0, y, wz0)
			var b := Vector3(wx0 + TW, y, wz0)
			var c := Vector3(wx0 + TW, y, wz0 + TW)
			var e := Vector3(wx0, y, wz0 + TW)
			S.v.append_array([a, b, c, a, c, e])
			for k2 in 6:
				S.n.append(Vector3.UP)
			var aoi := [0, 1, 2, 0, 2, 3]
			for k3 in 6:
				S.c.append(Color(1, 1, 1, ao[aoi[k3]]))
			S.uv.append_array([uv0, Vector2(uv1.x, uv0.y), uv1, uv0, uv1, Vector2(uv0.x, uv1.y)])
	# ---- per-pixel: rounded wall edges, faces, banks, decorations
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var dnorm := [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]
	# per tile: interior wall (no edge pixel) or plain floor (8 floor neighbours): no faces to build there
	var DATA: PackedByteArray = d.data
	var IW: int = d.EW * TW
	var tile_kind := {}
	for ty in range(Y0 / TW, Y1 / TW):
		for tx in range(X0 / TW, X1 / TW):
			var t0 := _ter(d, tx * TW, ty * TW)
			var k := 0
			if t0 == 0:
				k = 1
				for py in range(0, TW, 2):
					for px in [0, TW - 1]:
						if HT[(ty * TW + py - Y0 + M) * W + (tx * TW + px - X0 + M)] < WH:
							k = 0
					for pyx in [0, TW - 1]:
						if HT[(ty * TW + pyx - Y0 + M) * W + (tx * TW + py - X0 + M)] < WH:
							k = 0
				if k == 1:
					for py in range(2, TW - 2, 4):
						for px in range(2, TW - 2, 4):
							if HT[(ty * TW + py - Y0 + M) * W + (tx * TW + px - X0 + M)] < WH:
								k = 0
			elif t0 == 1:
				k = 2
				for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
					if _ter(d, (tx + o.x) * TW, (ty + o.y) * TW) != 1:
						k = 0
			tile_kind[Vector2i(tx, ty)] = k
	for gy in range(Y0, Y1):
		for gx in range(X0, X1):
			var li := (gy - Y0 + M) * W + (gx - X0 + M)
			var t: int = T[li]
			var h: float = HT[li]
			var wx := float(gx - ox)
			var wz := float(gy - ox)
			var pi := (gy * IW + gx) * 4
			var c := Color8(DATA[pi], DATA[pi + 1], DATA[pi + 2])
			var uv := Vector2((gx + 0.5) / TWX, (gy + 0.5) / TWY)
			var tk: int = tile_kind.get(Vector2i(gx / TW, gy / TW), 0)
			var tile_flat := tk == 1
			var plain := tk == 2
			if t == 0 and not tile_flat:
				S.quad(Vector3(wx, h, wz), Vector3(wx + 1, h, wz), Vector3(wx + 1, h, wz + 1), Vector3(wx, h, wz + 1), Vector3.UP, Color(1, 1, 1, 1), uv)
			if (t == 1 and not plain) or (t == 0 and not tile_flat):
				# sides toward lower neighbours
				for k in 4:
					var dv: Vector2i = dirs[k]
					var nli: int = li + dv.y * W + dv.x
					var nh: float = HT[nli]
					if nh >= h:
						continue
					var nt: int = T[nli]
					var p0: Vector3
					var p1: Vector3
					match k:
						0:
							p0 = Vector3(wx + 1, 0, wz + 1)
							p1 = Vector3(wx + 1, 0, wz)
						1:
							p0 = Vector3(wx, 0, wz)
							p1 = Vector3(wx, 0, wz + 1)
						2:
							p0 = Vector3(wx, 0, wz + 1)
							p1 = Vector3(wx + 1, 0, wz + 1)
						_:
							p0 = Vector3(wx + 1, 0, wz)
							p1 = Vector3(wx, 0, wz)
					var nrm: Vector3 = dnorm[k]
					var face_top := h
					if t == 0 and nt != 0:
						face_top = minf(h, float(FACE_H))
						# the rounded part above the stone face: the pixel's own colour
						if h > face_top:
							S.quad(p0 + Vector3(0, face_top, 0), p0 + Vector3(0, h, 0), p1 + Vector3(0, h, 0), p1 + Vector3(0, face_top, 0), nrm, Color(0.85, 0.85, 0.85, 1), uv)
						# stone courses (rock, snow / cloud: soft cap colour), from the neighbour's floor up
						var along := gx if dv.x == 0 else gy
						var z := int(floorf(nh))
						var soft := mat == "snow" or mat == "cloud"
						while z < int(face_top):
							var ch := 2 + int(_hsh(z, along / 64, 11) * 3.0)
							var row := z * 7 + along / 512
							var w := 3 + int(_hsh(row, 0, 12) * 5.0)
							var off := int(_hsh(row, 0, 13) * w)
							var cell := (along + off) / w
							var stone: Color = pal[int(_hsh(cell, row, 1) * pal.size())]
							if soft:
								stone = (pal[pal.size() - 1] as Color).lerp(Color(0.88, 0.94, 1.0), 0.35 if mat == "snow" else 0.0)
							var z1 := mini(z + ch, int(face_top))
							var joint := (along + off) % w == 0
							var k2 := 0.6 + 0.4 * float(z) / WH
							var sc := stone.darkened(0.3 if (joint and not soft) else 0.0)
							if mat == "crystal" and joint:
								sc = stone.lightened(0.25)
							sc = Color(sc.r * k2, sc.g * k2, sc.b * k2, 0.75 if z < 2 else 1.0)
							S.quad(p0 + Vector3(0, z, 0), p0 + Vector3(0, z1, 0), p1 + Vector3(0, z1, 0), p1 + Vector3(0, z, 0), nrm, sc, Vector2(-1, -1))
							# a mortar line on top of the course
							if not soft and z1 - z >= 2:
								S.quad(p0 + Vector3(0, z1 - 0.35, 0), p0 + Vector3(0, z1, 0), p1 + Vector3(0, z1, 0), p1 + Vector3(0, z1 - 0.35, 0), nrm, sc.darkened(0.35), Vector2(-1, -1))
							var stick := _hsh(cell, row, 5)
							if not soft and not joint and stick < 0.25:
								S.box(Vector3(wx, z, wz) + nrm, Vector3(1, z1 - z, 1), sc.lightened(0.06), 31)
							if soft and mat == "snow" and z1 >= int(face_top) and _hsh(gx, gy, 50) < 0.18:
								var ln := 1 + int(_hsh(gx, gy, 51) * 4.0)
								S.box(Vector3(wx, face_top - ln, wz) + nrm, Vector3(1, ln, 1), Color(0.8, 0.92, 1.0, 1), 31)
							z = z1
					elif t == 1 and nt >= 2 and nt != STAIRS:
						# a bank down to the water bed / lava / chasm bottom
						var depth := nh
						var z2 := 1.0
						var stepz := 1.0 if depth > -10 else 3.0
						while z2 > depth:
							var za := maxf(depth, z2 - stepz)
							var st: Color = pal[int(_hsh(gx / 4 + gy / 4, int(za) / 3, 61) * pal.size())]
							var kk := clampf(1.0 + za / maxf(1.0, -depth), 0.15, 1.0)
							if depth < -10:
								kk = kk * kk
							S.quad(p0 + Vector3(0, za, 0), p0 + Vector3(0, z2, 0), p1 + Vector3(0, z2, 0), p1 + Vector3(0, za, 0), nrm, Color(st.r * kk, st.g * kk, st.b * kk, 1), Vector2(-1, -1))
							z2 = za
					else:
						S.quad(p0 + Vector3(0, nh, 0), p0 + Vector3(0, face_top, 0), p1 + Vector3(0, face_top, 0), p1 + Vector3(0, nh, 0), nrm, Color(0.8, 0.8, 0.8, 1), uv)
			# ---- decorations
			if t == 0:
				var ed2 := dist[li] / 3.0 - 1.0
				match mat:
					"grass":
						var hue := c.h * 360.0
						var flower := c.s > 0.35 and c.get_luminance() > 0.45 and (hue > 290.0 or hue < 15.0)
						if flower and _hsh(gx, gy, 74) < 0.6:
							blades.append([Vector3(wx + 0.5, h, wz + 0.5), 4.0 + floorf(_hsh(gx, gy, 31) * 2.0), c, 1.0])
						elif _green(c) and _hsh(gx, gy, 37) < grass_rate:
							var bh := clampf(c.get_luminance() * 3.5 + _hsh(gx, gy, 31) * 2.0 - 0.8, 1.0, 4.0)
							blades.append([Vector3(wx + 0.5, h, wz + 0.5), floorf(bh), c, 0.0])
					"crystal":
						if ed2 > 2.0 and gx % 3 == 1 and gy % 3 == 1 and _hsh(gx / 3, gy / 3, 41) < 0.06:
							var hh := 4 + int(_hsh(gx, gy, 42) * 6.0)
							for kq in hh:
								S.box(Vector3(wx, h + kq, wz), Vector3(1, 1, 1), c.lightened(0.1 + 0.5 * kq / hh), 31)
							for dq in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
								S.box(Vector3(wx, h, wz) + dq, Vector3(1, hh / 2, 1), c.lightened(0.15), 31)
					"snow":
						if gx % 4 == 0 and gy % 4 == 0 and ed2 > 1.0:
							var drift := 2.0 * maxf(0.0, sin(gx * 0.21 + _hsh(gx / 9, gy / 9, 43) * 3.0) * cos(gy * 0.17))
							if drift >= 0.5:
								S.box(Vector3(wx, h, wz), Vector3(4, roundf(drift), 4), Color(0.95, 0.97, 1.0).lerp(c, 0.2), 31)
					"cloud":
						if gx % 3 == 0 and gy % 3 == 0 and ed2 > 1.0:
							var best := 0.0
							var cx0 := floori(gx / 11.0)
							var cy0 := floori(gy / 11.0)
							for oy in [-1, 0, 1]:
								for oxx in [-1, 0, 1]:
									var qx: int = cx0 + oxx
									var qy: int = cy0 + oy
									if _hsh(qx, qy, 52) < 0.25:
										continue
									var pcx: float = qx * 11.0 + _hsh(qx, qy, 53) * 11.0
									var pcy: float = qy * 11.0 + _hsh(qx, qy, 54) * 11.0
									var rad: float = 4.0 + _hsh(qx, qy, 55) * 4.0
									var dd: float = Vector2(gx + 1.5 - pcx, gy + 1.5 - pcy).length()
									if dd < rad:
										best = maxf(best, sqrt(rad * rad - dd * dd) * 0.8)
							if best > 0.5:
								S.box(Vector3(wx, h, wz), Vector3(3, roundf(best), 3), c.lightened(0.06 + 0.02 * best), 31)
					_:
						if _green(c) and _hsh(gx, gy, 73) < 0.22:     # seaweed / plants drawn on the walls
							var wn := 0
							for dv2 in dirs:
								if _green(_px(d, gx + dv2.x, gy + dv2.y)):
									wn += 1
							if wn >= 1:
								blades.append([Vector3(wx + 0.5, h, wz + 0.5), 4.0 + floorf(_hsh(gx, gy, 71) * 5.0), c, 0.0])
						elif ed2 > 3.0 and _hsh(gx, gy, 46) < 0.004:
							S.box(Vector3(wx, h, wz), Vector3(1, 1, 1), pal[int(_hsh(gx, gy, 48) * pal.size())], 31)
			elif t == 1:
				# floor tufts on green patches; rubble along the walls
				if _green(c) and _hsh(gx, gy, 37) < grass_rate * 0.75:
					var gn := 0
					for dv3 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
						if _green(_px(d, gx + dv3.x, gy + dv3.y)):
							gn += 1
					if gn >= 3:
						blades.append([Vector3(wx + 0.5, 1.0, wz + 0.5), 1.0 + floorf(_hsh(gx, gy, 31) * 2.0), c, 0.0])
				elif _hsh(gx, gy, 7) < 0.04:
					var near_wall := false
					for dv4 in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
						if _ter(d, gx + dv4.x, gy + dv4.y) == 0:
							near_wall = true
					if near_wall:
						var rc: Color = pal[int(_hsh(gx, gy, 8) * pal.size())]
						S.box(Vector3(wx, 1, wz), Vector3(1, 1.0 + floorf(_hsh(gx, gy, 9) * 2.0), 1), rc.darkened(0.1), 31)
	return {"solid": S.arrays() if S.v.size() > 0 else null, "water": WA.arrays() if WA.v.size() > 0 else null,
		"lava": LA.arrays() if LA.v.size() > 0 else null, "blades": blades}

static func chunks_x(d: Dictionary) -> int:
	return int(ceil(d.EW / float(CT)))

static func chunks_y(d: Dictionary) -> int:
	return int(ceil(d.EH / float(CT)))
