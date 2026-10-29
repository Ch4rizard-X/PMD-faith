extends Node
## --voxelshot [--dkey=key]: voxel mockups of a real dungeon floor.
##  user://vox_2d.png      the game as it is
##  user://vox_native.png  the view at GBA pixel size (terrain + Pokémon), for the voxel-filter mockup
##  user://vox_3d.png / vox_3d_close.png  a 3D voxel diorama built from the same floor
var m
var _gallery := ""

const TW := 24
const VIEW_X := 9      # tiles left/right of the leader in the 3D scene
const VIEW_Y := 6

func _ready() -> void:
	m = get_parent()
	var dkey := "tiny_woods"
	var hero := "0004"
	var partner := "0007"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dkey="):
			dkey = a.substr(7)
		if a.begins_with("--hero="):
			hero = a.substr(7)
		if a.begins_with("--partner="):
			partner = a.substr(10)
		if a.begins_with("--gallery="):
			_gallery = a.substr(10)
	Game.new_game(hero, DB.species[hero].name, partner, DB.species[partner].name, "Q")
	var first := 0
	for a3 in OS.get_cmdline_user_args():
		if a3.begins_with("--floor="):
			first = int(a3.substr(8))
	await m.start_dungeon(dkey, first)
	await get_tree().create_timer(2.5).timeout
	var d = m.dungeon
	get_viewport().get_texture().get_image().save_png("user://vox_2d.png")
	var fs = d.fs
	var timg: Image = d.terrain_view.tex_sprite.texture.get_image()
	if timg.is_compressed():
		timg.decompress()
	timg.convert(Image.FORMAT_RGBA8)
	if d.terrain_view.hd_k != 1:
		timg.resize(fs.w * TW, fs.h * TW, Image.INTERPOLATE_NEAREST)
	var L = fs.leader
	for mon in fs.mons:
		mon.facing = 0                   # everyone faces the camera for the mockup
	_native(fs, timg, L)
	await _diorama(fs, timg, L)
	get_tree().quit()

func _frame(mon, force_row := -1) -> Image:
	var v = mon.visual
	if v == null or v.man.is_empty():
		return null
	var A: Dictionary = v._anim("Idle")
	var tex: Texture2D = DB.tex("res://assets/sp/" + str(A.get("s", v.man.sheet)))
	if tex == null:
		return null
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var row := mini(mon.facing if force_row < 0 else force_row, int(A.rows) - 1)
	var r := Rect2i(int(A.get("x", 0)), int(A.y) + row * int(A.h), int(A.w), int(A.h))
	return img.get_region(r)

func _near(fs, L) -> Array:
	var out: Array = []
	for mon in fs.mons:
		if mon.alive() and absi(mon.pos.x - L.pos.x) <= VIEW_X and absi(mon.pos.y - L.pos.y) <= VIEW_Y:
			out.append(mon)
	return out

## GBA-sized view (10 x 7 tiles around the leader) with the Pokémon pasted on: 240 x 168
func _native(fs, timg: Image, L) -> void:
	var x0: int = (L.pos.x - 5) * TW
	var y0: int = (L.pos.y - 3) * TW
	var out := Image.create(240, 168, false, Image.FORMAT_RGBA8)
	out.fill(Color.BLACK)
	out.blit_rect(timg, Rect2i(x0, y0, 240, 168), Vector2i.ZERO)
	var mons := _near(fs, L)
	mons.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for mon in mons:
		var f := _frame(mon)
		if f == null:
			continue
		var cx: int = mon.pos.x * TW + TW / 2 - x0
		var cy: int = mon.pos.y * TW + TW / 2 - y0
		out.blend_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i(cx - f.get_width() / 2, cy - f.get_height() / 2 - 4))
	out.save_png("user://vox_native.png")

func _diorama(fs, timg: Image, L) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1440, 810)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.02, 0.02, 0.04)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.7)
	e.ambient_light_energy = 0.35
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.9
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 600.0
	vp.add_child(sun)

	var cols: Array = []
	var xforms: Array = []
	var lx: int = clampi(L.pos.x, VIEW_X, fs.w - 1 - VIEW_X)
	var ly: int = clampi(L.pos.y, VIEW_Y, fs.h - 1 - VIEW_Y)
	var ter := func(gx: int, gy: int) -> int:
		var tx := floori(gx / float(TW))
		var ty := floori(gy / float(TW))
		if tx < 0 or ty < 0 or tx >= fs.w or ty >= fs.h:
			return 0
		return fs.terrain[ty * fs.w + tx]
	var px_of := func(gx: int, gy: int) -> Color:
		if gx < 0 or gy < 0 or gx >= timg.get_width() or gy >= timg.get_height():
			return Color.BLACK
		return timg.get_pixel(gx, gy)
	if _gallery != "":
		var tile := timg.get_region(Rect2i(L.pos.x * TW, L.pos.y * TW, TW, TW))
		ter = func(gx: int, gy: int) -> int: return 1
		px_of = func(gx: int, gy: int) -> Color: return tile.get_pixel(posmod(gx, TW), posmod(gy, TW))
	var X0 := (lx - VIEW_X) * TW
	var Y0 := (ly - VIEW_Y) * TW
	var X1 := (lx + VIEW_X + 1) * TW
	var Y1 := (ly + VIEW_Y + 1) * TW
	# rock palette: the cliff band the 2D art draws along the walls' edges
	var band: Array = []
	for gy in range(Y0, Y1, 2):
		for gx in range(X0, X1, 2):
			if ter.call(gx, gy) != 0:
				continue
			for d in [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3), Vector2i(0, -3)]:
				if ter.call(gx + d.x, gy + d.y) != 0:
					band.append(px_of.call(gx, gy))
					break
	band.sort_custom(func(a, b): return a.get_luminance() < b.get_luminance())
	var pal: Array = []
	if band.size() > 10:
		for k in 6:
			pal.append(band[int(band.size() * (0.08 + 0.12 * k))])
	else:
		pal = [Color(0.35, 0.3, 0.27), Color(0.45, 0.4, 0.36), Color(0.55, 0.5, 0.45)]
	const WH := 15
	const R := 6.0                    # radius of the rounded top edge (cubes)
	var FACE_H := int(WH - R)          # stones go up to here, then the edge curves over
	# distance (in cubes) from each wall pixel to the nearest non-wall pixel: 3-4 chamfer, two passes
	var VW := X1 - X0
	var VH := Y1 - Y0
	var dist := PackedInt32Array()
	dist.resize(VW * VH)
	for y in VH:
		for x in VW:
			dist[y * VW + x] = 0 if ter.call(X0 + x, Y0 + y) != 0 else 9999
	for y in VH:
		for x in VW:
			var i := y * VW + x
			var v := dist[i]
			if v == 0:
				continue
			if x > 0: v = mini(v, dist[i - 1] + 3)
			if y > 0:
				v = mini(v, dist[i - VW] + 3)
				if x > 0: v = mini(v, dist[i - VW - 1] + 4)
				if x < VW - 1: v = mini(v, dist[i - VW + 1] + 4)
			dist[i] = v
	for y in range(VH - 1, -1, -1):
		for x in range(VW - 1, -1, -1):
			var i := y * VW + x
			var v := dist[i]
			if v == 0:
				continue
			if x < VW - 1: v = mini(v, dist[i + 1] + 3)
			if y < VH - 1:
				v = mini(v, dist[i + VW] + 3)
				if x < VW - 1: v = mini(v, dist[i + VW + 1] + 4)
				if x > 0: v = mini(v, dist[i + VW - 1] + 4)
			dist[i] = v
	var hsh := func(a: int, b: int, c: int) -> float:
		var n := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
		n = (n ^ (n >> 13)) * 1274126177
		return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0
	var add := func(p: Vector3, hgt: float, c: Color) -> void:
		xforms.append(Transform3D(Basis().scaled(Vector3(1, hgt, 1)), p + Vector3(0, hgt / 2.0, 0)))
		cols.append(c)
	# wall material, read from the tileset itself: the colours of the wall tops (pixels 4+ cubes inside a wall)
	var mh := 0.0
	var msat := 0.0
	var mlum := 0.0
	var mgreen := 0
	var mn := 0
	var mhx := 0.0
	var mhy := 0.0
	for gy in range(Y0, Y1, 3):
		for gx in range(X0, X1, 3):
			if ter.call(gx, gy) != 0 or dist[(gy - Y0) * VW + (gx - X0)] < 12:
				continue
			var c0: Color = px_of.call(gx, gy)
			mhx += cos(c0.h * TAU) * c0.s
			mhy += sin(c0.h * TAU) * c0.s
			msat += c0.s
			mlum += c0.get_luminance()
			if c0.g > c0.r * 1.15 and c0.g > c0.b * 1.25:
				mgreen += 1
			mn += 1
	mn = maxi(mn, 1)
	msat /= mn
	mlum /= mn
	mh = fposmod(atan2(mhy, mhx) / TAU, 1.0) * 360.0
	var mat := "rock"
	if float(mgreen) / mn > 0.35:
		mat = "grass"
	elif mlum > 0.88 and mh > 180.0 and mh < 250.0 and msat < 0.5:
		mat = "cloud"
	elif mlum > 0.8 and msat < 0.22:
		mat = "snow"
	elif msat > 0.45 and mh > 190.0 and mh < 320.0:
		mat = "crystal"
	if OS.get_cmdline_user_args().has("--mat=" ):
		pass
	# tilesets the colour test misreads (light grey rock read as snow, deep sea read as crystal)
	var MAT_FIX := {40: "rock", 42: "rock", 43: "rock", 55: "rock", 49: "rock", 54: "rock", 16: "rock"}
	var tsid := int(m.dungeon.ddata.floors[m.dungeon.floor_i].get("props", [0, 0, -1])[2])
	if MAT_FIX.has(tsid) and not bool(m.dungeon.ddata.get("eos", false)) and not str(m.dungeon.dkey).begins_with("eos_"):
		mat = MAT_FIX[tsid]
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("--mat="):
			mat = a2.substr(6)
	var RR := 12.0 if mat == "cloud" else R
	FACE_H = int(WH - RR)
	print("MATERIAL %s  hue %.0f sat %.2f lum %.2f green %.2f" % [mat, mh, msat, mlum, float(mgreen) / mn])
	# floor tufts only where the floor itself is green and the walls are a plant material
	# grass: green pixels grow blades of 1-4 cubes (lighter green = taller, tips lighter), flowers stand on
	# 1-2 cube stems; on the floor, the green patches become low tufts
	var GRASS := mat == "grass" and not OS.get_cmdline_user_args().has("--nograss")
	# crystal: sparse pointed clusters; snow: a smooth white cap with drifts; cloud: puffy domes; rock: pebbles
	var deco := func(at2: Vector3, top2: float, c2: Color, gx2: int, gy2: int, inner: float) -> void:
		match mat:
			"crystal":
				if inner > 2.0 and hsh.call(gx2 / 3, gy2 / 3, 41) < 0.06 and gx2 % 3 == 1 and gy2 % 3 == 1:
					var hh := 4 + int(hsh.call(gx2, gy2, 42) * 6.0)
					for k in hh:
						add.call(at2 + Vector3(0, top2 + k, 0), 1.0, c2.lightened(0.1 + 0.5 * k / hh))
					for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
						for k in hh / 2:
							add.call(at2 + d + Vector3(0, top2 + k, 0), 1.0, c2.lightened(0.05 + 0.3 * k / hh))
			"snow":
				var drift := 1.0 + 2.0 * maxf(0.0, sin(gx2 * 0.21 + hsh.call(gx2 / 9, gy2 / 9, 43) * 3.0) * cos(gy2 * 0.17))
				add.call(at2 + Vector3(0, top2, 0), drift, Color(0.95, 0.97, 1.0).lerp(c2, 0.2))
			"cloud":
				# round puffs: domes on a jittered grid (radius 4-8), the tallest one under this pixel wins
				var best := 0.0
				var cx0 := floori(gx2 / 11.0)
				var cy0 := floori(gy2 / 11.0)
				for oy in [-1, 0, 1]:
					for ox in [-1, 0, 1]:
						var qx: int = cx0 + ox
						var qy: int = cy0 + oy
						if hsh.call(qx, qy, 52) < 0.25:
							continue
						var pcx: float = qx * 11.0 + hsh.call(qx, qy, 53) * 11.0
						var pcy: float = qy * 11.0 + hsh.call(qx, qy, 54) * 11.0
						var rad: float = 4.0 + hsh.call(qx, qy, 55) * 4.0
						var dd: float = Vector2(gx2 - pcx, gy2 - pcy).length()
						if dd < rad:
							best = maxf(best, sqrt(rad * rad - dd * dd) * 0.8)
				if best > 0.5 and inner > 1.0:
					add.call(at2 + Vector3(0, top2, 0), best, c2.lightened(0.06 + 0.02 * best))
			"rock":
				if inner > 3.0 and hsh.call(gx2, gy2, 46) < 0.006:
					var pc: Color = pal[int(hsh.call(gx2, gy2, 48) * pal.size())]
					add.call(at2 + Vector3(0, top2, 0), 1.0, pc)
	var FLOORG := not OS.get_cmdline_user_args().has("--nograss")
	var tuft := func(at2: Vector3, top2: float, c2: Color, gx2: int, gy2: int, floor_px: bool) -> void:
		var weed := not floor_px and not GRASS            # plants drawn on non-grass walls (Stormy Sea seaweed)
		if not (FLOORG if floor_px else (GRASS or weed)):
			return
		var green := c2.g > c2.r * 1.15 and c2.g > c2.b * 1.25 and c2.s > 0.35 and c2.get_luminance() > 0.28
		# flowers: real pink / magenta / red petals only (not brown or skin-toned floor art), on grass walls
		var hue := c2.h * 360.0
		var flower := GRASS and not floor_px and c2.s > 0.35 and c2.get_luminance() > 0.45 and (hue > 290.0 or hue < 15.0)
		if weed:
			if not green:
				return
			var wn := 0
			for d6 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q6: Color = px_of.call(gx2 + d6.x, gy2 + d6.y)
				if q6.g > q6.r * 1.15 and q6.g > q6.b * 1.25 and q6.s > 0.35:
					wn += 1
			if wn < 1 or hsh.call(gx2, gy2, 73) > 0.22:
				return                            # thin: a few separate fronds per patch
			# a frond: 3-6 cubes, leaning with the current, darker at the root
			var fh := 4 + int(hsh.call(gx2, gy2, 71) * 5.0)
			var lean := Vector3(1, 0, 0) if hsh.call(gx2 / 5, gy2 / 5, 72) < 0.5 else Vector3(0, 0, 1)
			for k in fh:
				var off := lean * floorf(k * k / 10.0)
				var sway := sin(gx2 * 0.7 + k * 0.9) * 0.6
				add.call(at2 + off + Vector3(sway, top2 + k, 0), 1.0, c2.darkened(0.3).lerp(c2.lightened(0.15), float(k) / fh))
			return
		if floor_px and green:
			# floor tufts only where the green forms a patch (3+ green neighbours), not on single specks
			var gn := 0
			for d5 in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1)]:
				var q5: Color = px_of.call(gx2 + d5.x, gy2 + d5.y)
				if q5.g > q5.r * 1.15 and q5.g > q5.b * 1.25:
					gn += 1
			green = gn >= 3
		if not green and not flower:
			return
		var r: float = hsh.call(gx2, gy2, 31)
		if green and hsh.call(gx2, gy2, 37) > (0.25 if floor_px else 0.35):
			return                         # sparse: about a third of the green pixels grow a blade
		var hgt := 0
		if flower:
			hgt = 4 + int(r * 2.0)          # above the blades
		else:
			hgt = int(clampf(c2.get_luminance() * 3.5 + r * 2.0 - 0.8, 0.0, 4.0))
			if floor_px:
				hgt = mini(hgt, 2)
		for k in hgt:
			var col := c2
			if flower and k < hgt - 2:
				col = Color(0.32, 0.62, 0.18)       # stem
			elif green:
				col = c2.lightened(0.08 * k) if k < hgt - 1 else c2.lightened(0.22)
			add.call(at2 + Vector3(0, top2 + k, 0), 1.0, col)
	for gy in range(Y0, Y1):
		for gx in range(X0, X1):
			var t: int = ter.call(gx, gy)
			var c: Color = px_of.call(gx, gy)
			var lum := c.get_luminance()
			var sec_kind := "chasm" if t == 3 else str(fs.secondary)
			if t >= 2:
				var atp := Vector3(gx - lx * TW, 0, gy - ly * TW)
				match sec_kind:
					"chasm":
						# a deep drop: the 2D art (sky / clouds / void) far below
						add.call(atp + Vector3(0, -CH_D - 1, 0), 1.0, c.darkened(0.35))
					"lava":
						add.call(atp + Vector3(0, -LV_D, 0), LV_D - 1.0, c.lightened(0.15))
					_:
						add.call(atp + Vector3(0, -WT_D, 0), WT_D - 1.5, c)
				continue
			# banks: pixels beside water / lava / a chasm reach down to its bottom
			var bank := 0.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var tn: int = ter.call(gx + d.x, gy + d.y)
				if tn >= 2:
					var kn := "chasm" if tn == 3 else str(fs.secondary)
					bank = maxf(bank, CH_D + 1.0 if kn == "chasm" else (LV_D if kn == "lava" else WT_D))
			if bank > 0.0:
				var atb := Vector3(gx - lx * TW, 0, gy - ly * TW)
				var z2 := -int(bank)
				while z2 < 0:
					var st: Color = pal[int(hsh.call(gx / 4 + gy / 4, z2 / 3, 61) * pal.size())]
					var k4 := clampf(1.0 + float(z2) / bank, 0.0, 1.0)
					if bank > 10.0:
						k4 = k4 * k4                          # a chasm wall fades into the dark
					var joint2 := (z2 % 3 == 0) or ((gx + gy + (z2 / 3) * 2) % 5 == 0)
					var cb := st.darkened(0.25 if joint2 else 0.0)
					add.call(atb + Vector3(0, z2, 0), 1.0, Color(cb.r * (0.25 + 0.75 * k4), cb.g * (0.25 + 0.75 * k4), cb.b * (0.25 + 0.75 * k4)))
					z2 += 1
			var at := Vector3(gx - lx * TW, 0, gy - ly * TW)
			if t != 0:
				var h := 1.0                       # flat floor: per-pixel relief turned busy floor art into noise
				add.call(at, h, c)
				if t == 1:
					tuft.call(at, h, c, gx, gy, true)
				# rubble: a few small stones on the floor along the walls
				if t == 1:
					var near_wall := false
					for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
						if ter.call(gx + d.x, gy + d.y) == 0:
							near_wall = true
					if near_wall and hsh.call(gx, gy, 7) < 0.05:
						var rc: Color = pal[int(hsh.call(gx, gy, 8) * pal.size())]
						add.call(at + Vector3(0, h, 0), 1.0 + floorf(hsh.call(gx, gy, 9) * 2.0), rc.darkened(0.1))
				continue
			# wall: is this pixel on a face that can be seen (a neighbour pixel isn't wall)?
			var out := Vector2i.ZERO
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if ter.call(gx + d.x, gy + d.y) != 0:
					out = d
			# rounded top: a quarter circle from the face (height WH - R) up to the full height R cubes in
			var ed := dist[(gy - Y0) * VW + (gx - X0)] / 3.0 - 1.0
			var top := WH + lum * 1.5
			if ed < RR:
				top = WH - RR + sqrt(maxf(0.0, RR * RR - (RR - ed) * (RR - ed))) + lum * 1.5 * (ed / RR)
			if out == Vector2i.ZERO:
				add.call(at, maxf(top, FACE_H + 1.0), c)   # one column, the 2D art on top
				tuft.call(at, maxf(top, FACE_H + 1.0), c, gx, gy, false)
				deco.call(at, maxf(top, FACE_H + 1.0), c, gx, gy, ed)
				continue
			# face: stacked stones in the cliff colours, darker towards the floor, with mortar lines
			add.call(at + Vector3(0, FACE_H, 0), maxf(1.0, top - FACE_H), c)       # the art where the curve starts
			tuft.call(at, FACE_H + maxf(1.0, top - FACE_H), c, gx, gy, false)
			deco.call(at, FACE_H + maxf(1.0, top - FACE_H), c, gx, gy, ed)
			var along := gx if out.x == 0 else gy
			var z := 0
			if mat == "cloud" or mat == "snow":
				# soft faces: the cap colour fading darker downward, a little noise, snow gets icicles
				var capc: Color = pal[pal.size() - 1] if mat == "snow" else c
				for zz in FACE_H:
					var k2 := 0.62 + 0.38 * float(zz) / WH
					var n2: float = 0.95 + 0.1 * hsh.call(gx + gy * 3, zz, 48)
					var cc2 := capc.lerp(Color(0.85, 0.92, 1.0), 0.35) if mat == "snow" else capc
					add.call(at + Vector3(0, zz, 0), 1.0, Color(cc2.r * k2 * n2, cc2.g * k2 * n2, cc2.b * k2 * n2))
					if mat == "cloud" and hsh.call(along_px(gx, gy, out), zz / 3, 49) < 0.25:
						add.call(at + Vector3(out.x, zz, out.y), 1.0, cc2.lightened(0.05))
				if mat == "snow" and hsh.call(gx, gy, 50) < 0.18:
					var ln := 1 + int(hsh.call(gx, gy, 51) * 4.0)
					for k3 in ln:
						add.call(at + Vector3(out.x, FACE_H - 1 - k3, out.y), 1.0, Color(0.8, 0.92, 1.0, 1.0))
				z = FACE_H
			while z < FACE_H:
				# a course of stones: random height 2-4, random widths 3-7, joints staggered per course
				var ch := 2 + int(hsh.call(z, along / 64, 11) * 3.0)
				var row := z * 7 + along / 512
				var w := 3 + int(hsh.call(row, 0, 12) * 5.0)
				var off := int(hsh.call(row, 0, 13) * w)
				var cell := (along + off) / w
				var stone: Color = pal[int(hsh.call(cell, row, 1) * pal.size())]
				var stick: float = hsh.call(cell, row, 5)
				for zz in range(z, mini(z + ch, FACE_H)):
					var joint := (along + off) % w == 0 or zz == z
					var k := 0.6 + 0.4 * float(zz) / WH
					var n: float = 0.94 + 0.12 * hsh.call(gx * 3 + gy, zz, 21)        # grain
					var col := stone.darkened(0.32 if joint else 0.0)
					if mat == "crystal":
						col = stone.lightened(0.25 if joint else 0.0)
					col = Color(col.r * k * n, col.g * k * n, col.b * k * n)
					add.call(at + Vector3(0, zz, 0), 1.0, col)
					# some stones stand out of the face (1-2 cubes), a few big boulders
					if not joint and stick < 0.3:
						add.call(at + Vector3(out.x, zz, out.y), 1.0, col.lightened(0.05))
						if stick < 0.08:
							add.call(at + Vector3(out.x * 2, zz, out.y * 2), 1.0, col.lightened(0.1))
				z += ch
	_multimesh(vp, xforms, cols)

	if _gallery != "":
		await _gallery_shots(vp, fs, lx, ly, ter)
		return
	if OS.get_cmdline_user_args().has("--thick"):
		var D := 8                                   # cubes deep
		var tx: Array = []
		var tc: Array = []
		for mon in _near(fs, L):
			var f := _frame(mon)
			if f == null:
				continue
			var used := f.get_used_rect()
			var cx: float = (mon.pos.x - lx) * TW + TW / 2.0
			var cz: float = (mon.pos.y - ly) * TW + TW / 2.0
			for y in range(used.position.y, used.end.y):
				for x in range(used.position.x, used.end.x):
					var c := f.get_pixel(x, y)
					if c.a < 0.5:
						continue
					var p := Vector3(cx + x - used.position.x - used.size.x / 2.0, 1.5 + (used.end.y - 1 - y) + 0.5, cz)
					tx.append(Transform3D(Basis().scaled(Vector3(1, 1, D)), p))
					tc.append(c)
		_multimesh(vp, tx, tc)
		var cam3 := Camera3D.new()
		vp.add_child(cam3)
		var fx3: float = (L.pos.x - lx) * TW
		var fz3: float = (L.pos.y - ly) * TW
		cam3.fov = 38
		cam3.position = Vector3(0, 190, 290)
		cam3.look_at(Vector3(0, 0, 10))
		await _grab(vp, "user://vox_3d.png")
		cam3.fov = 30
		cam3.position = Vector3(fx3 - 30, 85, fz3 + 120)
		cam3.look_at(Vector3(fx3, 8, fz3 - 20))
		await _grab(vp, "user://vox_3d_close.png")
		cam3.fov = 28
		cam3.position = Vector3(fx3 + 30, 48, fz3 + 95)
		cam3.look_at(Vector3(fx3 - 6, 12, fz3 - 6))
		await _grab(vp, "user://vox_3d_mon.png")
		return
	if OS.get_cmdline_user_args().has("--inflate"):
		await _inflated(vp, fs, L, lx, ly)
		return
	if OS.get_cmdline_user_args().has("--vote"):
		var vx: Array = []
		var vc: Array = []
		for mon in _near(fs, L):
			var views: Array = []
			for k in 8:
				views.append(_frame(mon, k))
			if views[0] == null:
				continue
			var base := Vector3((mon.pos.x - lx) * TW + TW / 2.0, 1.5, (mon.pos.y - ly) * TW + TW / 2.0)
			for v in _hull_persp(views):
				vx.append(Transform3D(Basis(), base + Vector3(v[0], v[1] + 0.5, v[2])))
				vc.append(v[3])
		_multimesh(vp, vx, vc)
		var cam2 := Camera3D.new()
		vp.add_child(cam2)
		var fx2: float = (L.pos.x - lx) * TW
		var fz2: float = (L.pos.y - ly) * TW
		cam2.fov = 30
		cam2.position = Vector3(fx2 - 30, 85, fz2 + 120)
		cam2.look_at(Vector3(fx2, 8, fz2 - 20))
		await _grab(vp, "user://vox_3d_close.png")
		cam2.fov = 28
		cam2.position = Vector3(fx2 + 30, 48, fz2 + 95)
		cam2.look_at(Vector3(fx2 - 6, 12, fz2 - 6))
		await _grab(vp, "user://vox_3d_mon.png")
		cam2.position = Vector3(fx2 + 110, 45, fz2 + 50)
		cam2.look_at(Vector3(fx2 - 6, 14, fz2 - 4))
		await _grab(vp, "user://vox_3d_side.png")
		return
	# Pokémon (hybrid): the front sprite is inflated per body part (transparent pixels and the dark lines
	# between parts are edges, so arms, belly and head bulge separately); the side view sets how far each row
	# reaches forward and backward (a tail or shell behind, a snout in front). Each pixel becomes a column:
	# the front half in the front sprite's colours, the back half in the back view's.
	var mx: Array = []
	var mc: Array = []
	for mon in _near(fs, L):
		var F := _frame(mon, 0)
		var S := _frame(mon, 2)
		var B := _frame(mon, 4)
		if F == null:
			continue
		var w := F.get_width()
		var h := F.get_height()
		var pdist := _part_dist(F)
		var maxd := 1
		for v in pdist:
			maxd = maxi(maxd, v)
		var hmax := 0.5 + sqrt(float(maxd)) * 1.4
		# side view: per row, reach in front of / behind the body's pivot (feet centre of the side sprite)
		var su := S.get_used_rect() if S else Rect2i()
		var pivot := su.position.x + su.size.x / 2.0
		var fr := PackedFloat32Array()
		var bk := PackedFloat32Array()
		fr.resize(h)
		bk.resize(h)
		for y in h:
			var u0 := -1
			var u1 := -1
			if S:
				for u in w:
					if S.get_pixel(u, y).a >= 0.5:
						if u0 < 0:
							u0 = u
						u1 = u
			fr[y] = (u1 + 1 - pivot) if u0 >= 0 else 0.0
			bk[y] = (pivot - u0) if u0 >= 0 else 0.0
		var cx: float = (mon.pos.x - lx) * TW + TW / 2.0
		var cz: float = (mon.pos.y - ly) * TW + TW / 2.0
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-12.0))
		var base := Vector3(cx, 1.5, cz)
		var bottom := F.get_used_rect().end.y - 1
		for y in h:
			for x in w:
				var d := pdist[y * w + x]
				if d == 0:
					continue
				var c := F.get_pixel(x, y)
				var half := minf(5.0, 0.5 + sqrt(float(d)) * 1.4)
				var t := clampf(half / hmax, 0.0, 1.0)
				var zf := maxf(0.5, maxf(half, fr[y] * t * 0.9))
				var zb := maxf(0.5, maxf(half, bk[y] * t * 0.9))
				if c.get_luminance() < 0.14 and d <= 1:
					zf = 0.5
					zb = minf(zb, 1.5)
				var bc := c
				if B:
					var cb := B.get_pixel(w - 1 - x, y)
					bc = cb if cb.a >= 0.5 else c.darkened(0.2)
				var local := Vector3(x - w / 2.0, bottom - y, 0)
				# front half [0, zf], back half [-zb, 0]
				mx.append(Transform3D(tilt * Basis().scaled(Vector3(1, 1, zf)), base + tilt * (local + Vector3(0, 0.5, zf / 2.0))))
				mc.append(c)
				mx.append(Transform3D(tilt * Basis().scaled(Vector3(1, 1, zb)), base + tilt * (local + Vector3(0, 0.5, -zb / 2.0))))
				mc.append(bc)
	_multimesh(vp, mx, mc)

	# water surface
	var cam := Camera3D.new()
	cam.fov = 38
	vp.add_child(cam)
	cam.position = Vector3(0, 190, 290)
	cam.look_at(Vector3(0, 0, 10))
	await _grab(vp, "user://vox_3d.png")
	cam.fov = 30
	var fx: float = (L.pos.x - lx) * TW
	var fz: float = (L.pos.y - ly) * TW
	cam.position = Vector3(fx - 30, 85, fz + 120)
	cam.look_at(Vector3(fx, 8, fz - 20))
	await _grab(vp, "user://vox_3d_close.png")
	cam.fov = 30
	var far := 1.7 if OS.get_cmdline_user_args().has("--camfar") else 1.0
	cam.position = Vector3(fx + 30 * far, 48 * far, fz + 95 * far)
	cam.look_at(Vector3(fx - 6, 12, fz - 6))
	await _grab(vp, "user://vox_3d_mon.png")
	cam.position = Vector3(fx + 110 * far, 45 * far, fz + 60 * far)
	cam.look_at(Vector3(fx - 10, 14, fz - 4))
	await _grab(vp, "user://vox_3d_side.png")

## Per-part distance: 4-neighbour steps to the nearest transparent pixel; dark outline pixels inside the
## body count as distance 1, so each body part between the lines rises on its own.
func _part_dist(F: Image) -> PackedInt32Array:
	var w := F.get_width()
	var h := F.get_height()
	var md := PackedInt32Array()
	md.resize(w * h)
	for y in h:
		for x in w:
			var c := F.get_pixel(x, y)
			md[y * w + x] = 0 if c.a < 0.5 else (1 if c.get_luminance() < 0.12 else 999)
	for it in 2:
		var ys := range(h) if it == 0 else range(h - 1, -1, -1)
		var xs := range(w) if it == 0 else range(w - 1, -1, -1)
		for y in ys:
			for x in xs:
				var i: int = y * w + x
				if md[i] <= 1:
					continue
				var v := md[i]
				for dd in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
					var nx: int = x + dd.x
					var ny: int = y + dd.y
					var nv := 0 if (nx < 0 or ny < 0 or nx >= w or ny >= h) else md[ny * w + nx]
					v = mini(v, nv + 1)
				md[i] = v
	return md

## Body from the 8 sprite directions, allowing for the sprites' three-quarter view: the artist's camera looks
## down at PHI, so a point at height Y that is d pixels nearer that camera is drawn Y cos(PHI) - d sin(PHI)
## above the feet. Each voxel is tested against every view at its projected pixel; the front view must
## match exactly, the other 7 vote (5 needed). Surfaces take the colour of the view facing them; a top surface
## that lands on the dark outline takes the first non-outline pixel below it.
const PHI := 26.0

func _hull_persp(views: Array) -> Array:
	var w: int = views[0].get_width()
	var h: int = views[0].get_height()
	var R := w / 2
	var cp := cos(deg_to_rad(PHI))
	var sp := sin(deg_to_rad(PHI))
	var foot: int = (views[0] as Image).get_used_rect().end.y - 1
	var masks: Array = []
	for k in 8:
		var img: Image = views[k] if views[k] else views[0]
		var m := PackedByteArray()
		m.resize(w * h)
		for y in h:
			for x in w:
				var on := img.get_pixel(x, y).a >= 0.5
				if not on and k != 0:
					for dx in [-1, 1]:
						var xx: int = x + dx
						if xx >= 0 and xx < w and img.get_pixel(xx, y).a >= 0.5:
							on = true
				m[y * w + x] = 1 if on else 0
		masks.append(m)
	var cs: Array = []
	var sn: Array = []
	for k in 8:
		cs.append(cos(deg_to_rad(45.0 * k)))
		sn.append(sin(deg_to_rad(45.0 * k)))
	var proj := func(k: int, X: int, Y: int, Z: int) -> Vector2i:
		var sx := int(round(X * cs[k] + Z * sn[k])) + R
		var near: float = -X * sn[k] + Z * cs[k]
		var sy := foot - int(round(Y * cp - near * sp))
		return Vector2i(sx, sy)
	var solid := {}
	var ymax := int(h / cp) + 4
	for Y in ymax:
		for Z in range(-R, R):
			for X in range(-R, R):
				var p0: Vector2i = proj.call(0, X, Y, Z)
				if p0.x < 0 or p0.x >= w or p0.y < 0 or p0.y >= h or masks[0][p0.y * w + p0.x] == 0:
					continue
				var votes := 0
				for k in range(1, 8):
					var pk: Vector2i = proj.call(k, X, Y, Z)
					if pk.x >= 0 and pk.x < w and pk.y >= 0 and pk.y < h and masks[k][pk.y * w + pk.x] != 0:
						votes += 1
				if votes >= 5:
					solid[Vector3i(X, Y, Z)] = true
	# smooth: drop voxels with fewer than 2 face neighbours (stray spikes)
	var drop: Array = []
	for key in solid:
		var nb := 0
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if solid.has(key + d):
				nb += 1
		if nb < 2:
			drop.append(key)
	for key in drop:
		solid.erase(key)
	var out: Array = []
	for key in solid:
		var nrm := Vector3.ZERO
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if not solid.has(key + d):
				nrm += Vector3(d)
		if nrm == Vector3.ZERO:
			continue
		var ang := 0.0
		if absf(nrm.x) + absf(nrm.z) > 0.01:
			ang = fposmod(rad_to_deg(atan2(nrm.x, nrm.z)), 360.0)
		var k := posmod(-int(round(ang / 45.0)), 8)
		var up := nrm.y > 0.5 and absf(nrm.x) + absf(nrm.z) < 1.5
		var c := Color(0, 0, 0, 0)
		for tries in [0, 1, -1, 2, -2]:
			var kk: int = posmod(k + tries, 8)
			var img: Image = views[kk]
			if img == null:
				continue
			var pk: Vector2i = proj.call(kk, key.x, key.y, key.z)
			if pk.x < 0 or pk.x >= w:
				continue
			var yy := pk.y
			for step in 6:
				if yy < 0 or yy >= h:
					break
				var cc := img.get_pixel(pk.x, yy)
				if cc.a >= 0.5 and (not up or cc.get_luminance() >= 0.14 or step == 5):
					c = cc
					break
				yy += 1
			if c.a >= 0.5:
				break
		if c.a < 0.5:
			c = Color(0.12, 0.12, 0.12)
		out.append([key.x, key.y, key.z, c])
	return out

## 8-view visual hull. views[k] = the frame facing direction k (0 down, then counter-clockwise: 1 down-right,
## 2 right, 3 up-right, 4 up, 5 up-left, 6 left, 7 down-left). For a point (X, y, Z) in the Pokémon's own
## space (it faces +Z, toward the camera), view k shows it at screen x = X cos(45k) + Z sin(45k).
## Returns surface voxels [X, height, Z, colour].
func _hull8(views: Array, vote := false) -> Array:
	var w: int = views[0].get_width()
	var h: int = views[0].get_height()
	var R := w / 2
	var masks: Array = []          # dilated opacity per view
	for k in 8:
		var img: Image = views[k] if views[k] else views[0]
		var m := PackedByteArray()
		m.resize(w * h)
		for y in h:
			for x in w:
				var on := false
				for dx in [-1, 0, 1]:
					var xx: int = x + dx
					if xx >= 0 and xx < w and img.get_pixel(xx, y).a >= 0.5:
						on = true
						break
				m[y * w + x] = 1 if on else 0
		if vote and k == 0:                     # the front view is exact (no tolerance): it must match 1:1
			for y in h:
				for x in w:
					m[y * w + x] = 1 if img.get_pixel(x, y).a >= 0.5 else 0
		masks.append(m)
	var cs: Array = []
	var sn: Array = []
	for k in 8:
		cs.append(cos(deg_to_rad(45.0 * k)))
		sn.append(sin(deg_to_rad(45.0 * k)))
	var solid := {}
	var bottom := 0
	for y in h:
		for Z in range(-R, R):
			for X in range(-R, R):
				var keep := true
				if vote:
					# must be inside the front view; the other 7 views vote (5 needed), so a wing folded in one
					# view or a tail hidden in another doesn't carve the body away
					var sx0 := X + R
					if sx0 < 0 or sx0 >= w or masks[0][y * w + sx0] == 0:
						keep = false
					else:
						var votes := 0
						for k in range(1, 8):
							var sxk := int(round(X * cs[k] + Z * sn[k])) + R
							if sxk >= 0 and sxk < w and masks[k][y * w + sxk] != 0:
								votes += 1
						keep = votes >= 5
				else:
					for k in 8:
						var sx := int(round(X * cs[k] + Z * sn[k])) + R
						if sx < 0 or sx >= w or masks[k][y * w + sx] == 0:
							keep = false
							break
				if keep:
					solid[Vector3i(X, y, Z)] = true
					bottom = maxi(bottom, y)
	var out: Array = []
	for key in solid:
		var nrm := Vector3.ZERO
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if not solid.has(key + d):
				nrm += Vector3(d)
		if nrm == Vector3.ZERO and not (solid.has(key + Vector3i(1, 0, 0)) and solid.has(key + Vector3i(-1, 0, 0))):
			pass
		if nrm == Vector3.ZERO:
			continue                               # inside
		# horizontal direction of the surface -> the view that looks at it; straight up/down: the front
		var ang := 0.0
		if absf(nrm.x) + absf(nrm.z) > 0.01:
			ang = fposmod(rad_to_deg(atan2(nrm.x, nrm.z)), 360.0)
		var k := posmod(-int(round(ang / 45.0)), 8)     # view k sees the surfaces whose normal points at -45k degrees
		var c := Color(0, 0, 0, 0)
		for tries in [0, 1, -1, 2, -2]:
			var kk: int = posmod(k + tries, 8)
			var img: Image = views[kk]
			if img == null:
				continue
			var sx := int(round(key.x * cs[kk] + key.z * sn[kk])) + R
			if sx >= 0 and sx < w:
				var cc := img.get_pixel(sx, key.y)
				if cc.a >= 0.5:
					c = cc
					break
		if c.a < 0.5:
			c = Color(0.1, 0.1, 0.1)
		out.append([key.x, bottom - key.y, key.z, c])
	return out

## Visual hull of a front view F (x, y) and a side view S (u, y) facing right (u grows toward the front).
## Returns {Vector3i(x, y, u): Vector3 normal-ish}. Each body-part run is rounded into an ellipse.
func _hull(F: Image, S: Image) -> Dictionary:
	var out := {}
	var w := F.get_width()
	var h := F.get_height()
	for y in h:
		var fr := _runs(F, y)
		var sr := _runs(S, y)
		if fr.is_empty() or sr.is_empty():
			continue
		for a in fr:
			var ax0: int = a[0]
			var ax1: int = a[1]
			var hx := maxf(0.5, (ax1 - ax0 + 1) / 2.0)
			var mxc := (ax0 + ax1) / 2.0
			for b in sr:
				var bu0: int = b[0]
				var bu1: int = b[1]
				var hz := maxf(0.5, (bu1 - bu0 + 1) / 2.0)
				var mzc := (bu0 + bu1) / 2.0
				for x in range(ax0, ax1 + 1):
					for u in range(bu0, bu1 + 1):
						var dx := (x - mxc) / hx
						var dz := (u - mzc) / hz
						if dx * dx + dz * dz <= 1.2:
							out[Vector3i(x, y, u)] = Vector3(dx, 0, dz)
	return out

## Opaque runs of a sprite row, split at transparent pixels and at dark outline pixels inside the body
## (the lines between parts): a dark pixel joins the run on its right so the outline stays on the surface.
func _runs(img: Image, y: int) -> Array:
	var runs: Array = []
	var start := -1
	var w := img.get_width()
	for x in w + 1:
		var c := img.get_pixel(x, y) if x < w else Color(0, 0, 0, 0)
		var solid := c.a >= 0.5
		var split := solid and c.get_luminance() < 0.12 and start >= 0 and x - start >= 3 \
			and x + 1 < w and img.get_pixel(x + 1, y).a >= 0.5 and img.get_pixel(x + 1, y).get_luminance() >= 0.12
		if start >= 0 and (not solid or split):
			runs.append([start, x - 1])
			start = -1
		if solid and start < 0:
			start = x
	return runs

## --gallery=FILE.json: voxel models (tools: voxelize.py) placed on floor tiles of the leader's room.
## --gallery=FILE.json: voxel models (voxelize.py) in two rows on an open floor.
func _gallery_shots(vp: SubViewport, fs, lx: int, ly: int, ter: Callable) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(_gallery))
	var back := ["383", "149", "248", "3", "6"]
	var front := ["9", "94", "150", "448", "25"]
	var mx: Array = []
	var mc: Array = []
	for row in 2:
		var keys: Array = back if row == 0 else front
		for i in keys.size():
			if not data.has(keys[i]):
				continue
			var base := Vector3((i - 2) * 56.0 + (0.0 if row == 0 else 28.0), 1.5, -45.0 if row == 0 else 40.0)
			for v in data[keys[i]]:
				mx.append(Transform3D(Basis(), base + Vector3(v[0], v[1] + 0.5, v[2])))
				mc.append(Color(v[3], v[4], v[5]))
	_multimesh(vp, mx, mc)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.fov = 40
	cam.position = Vector3(14, 175, 260)
	cam.look_at(Vector3(14, 8, 0))
	await _grab(vp, "user://vox_gal_wide.png")
	cam.fov = 32
	cam.position = Vector3(-60, 70, 170)
	cam.look_at(Vector3(-50, 20, 0))
	await _grab(vp, "user://vox_gal_a.png")
	cam.position = Vector3(80, 70, 170)
	cam.look_at(Vector3(70, 20, 0))
	await _grab(vp, "user://vox_gal_b.png")
	cam.position = Vector3(230, 55, 120)
	cam.look_at(Vector3(10, 18, 0))
	await _grab(vp, "user://vox_gal_side.png")

## The first rounded figures: the front sprite frame inflated (thick in the middle, thin at the silhouette,
## a thin outline rim), leaning back toward the camera.
const TH_MAX := 4.5      # half-thickness at the thickest point (9 cubes through)
const TH_K := 1.6

func _inflated(vp: SubViewport, fs, L, lx: int, ly: int) -> void:
	var shade := OS.get_cmdline_user_args().has("--shade")
	var mx: Array = []
	var mc: Array = []
	for mon in _near(fs, L):
		var f := _frame(mon)
		if f == null:
			continue
		var used := f.get_used_rect()
		var fw := used.size.x
		var fh := used.size.y
		var md := PackedInt32Array()
		md.resize(fw * fh)
		for y in fh:
			for x in fw:
				md[y * fw + x] = 999 if f.get_pixel(used.position.x + x, used.position.y + y).a >= 0.5 else 0
		for it in 2:
			var ys := range(fh) if it == 0 else range(fh - 1, -1, -1)
			var xs := range(fw) if it == 0 else range(fw - 1, -1, -1)
			for y in ys:
				for x in xs:
					var i: int = y * fw + x
					if md[i] == 0:
						continue
					var v := md[i]
					for dd in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var nx: int = x + dd.x
						var ny: int = y + dd.y
						var nv := 0 if (nx < 0 or ny < 0 or nx >= fw or ny >= fh) else md[ny * fw + nx]
						v = mini(v, nv + 1)
					md[i] = v
		var cx: float = (mon.pos.x - lx) * TW + TW / 2.0
		var cz: float = (mon.pos.y - ly) * TW + TW / 2.0
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-18.0))
		var base := Vector3(cx, 1.5, cz)
		for y in fh:
			for x in fw:
				var mdist := md[y * fw + x]
				if mdist == 0:
					continue
				var c := f.get_pixel(used.position.x + x, used.position.y + y)
				var outline := c.get_luminance() < 0.14 and mdist <= 1
				var half := 0.5 if outline else minf(TH_MAX, 0.5 + sqrt(float(mdist)) * TH_K)
				if shade and c.get_luminance() < 0.14 and not outline:
					half *= 0.55                      # a line between parts: a crease
				if shade and not outline:
					# the sprite's own shading: lit pixels (brighter than their neighbourhood) bulge toward the
					# viewer, shaded pixels sink back; dark lines inside the body make creases between parts
					var sum := 0.0
					var n := 0
					for oy in range(-3, 4):
						for ox in range(-3, 4):
							var qx := x + ox
							var qy := y + oy
							if qx < 0 or qy < 0 or qx >= fw or qy >= fh or md[qy * fw + qx] == 0:
								continue
							var q := f.get_pixel(used.position.x + qx, used.position.y + qy)
							if q.get_luminance() < 0.14:
								continue
							sum += q.get_luminance()
							n += 1
					var rel := (c.get_luminance() - sum / maxf(1, n)) if n > 0 else 0.0
					half = clampf(half * (1.0 + rel * 3.0) + rel * 4.0, 0.5, 6.5)
					var dark_near := 0
					for dd in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
						var qx2: int = x + dd.x
						var qy2: int = y + dd.y
						if qx2 >= 0 and qy2 >= 0 and qx2 < fw and qy2 < fh and md[qy2 * fw + qx2] > 1 \
								and f.get_pixel(used.position.x + qx2, used.position.y + qy2).get_luminance() < 0.14:
							dark_near += 1
					if dark_near > 0:
						half *= 0.75
				var local := Vector3(x - fw / 2.0, fh - 1 - y, 0)
				var b := tilt * Basis().scaled(Vector3(1, 1, half * 2.0))
				mx.append(Transform3D(b, base + tilt * local + Vector3(0, 0.5, 0)))
				mc.append(c)
	_multimesh(vp, mx, mc)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var fx: float = (L.pos.x - lx) * TW
	var fz: float = (L.pos.y - ly) * TW
	cam.fov = 38
	cam.position = Vector3(0, 190, 290)
	cam.look_at(Vector3(0, 0, 10))
	await _grab(vp, "user://vox_3d.png")
	cam.fov = 30
	cam.position = Vector3(fx - 30, 85, fz + 120)
	cam.look_at(Vector3(fx, 8, fz - 20))
	await _grab(vp, "user://vox_3d_close.png")
	cam.fov = 28
	cam.position = Vector3(fx + 30, 48, fz + 95)
	cam.look_at(Vector3(fx - 6, 12, fz - 6))
	await _grab(vp, "user://vox_3d_mon.png")

static func along_px(gx: int, gy: int, out: Vector2i) -> int:
	return gx if out.x == 0 else gy

const CH_D := 40.0      # chasm depth (cubes)
const WT_D := 3.0       # water: surface 1.5 below the floor
const LV_D := 2.5       # lava

func _multimesh(vp: SubViewport, xforms: Array, cols: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	bm.material = mat
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, (cols[i] as Color).srgb_to_linear())
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	vp.add_child(mi)

func _grab(vp: SubViewport, path: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)
