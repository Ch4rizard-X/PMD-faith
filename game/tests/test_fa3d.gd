extends Node
## Mockup: a Friend Area as a 3D diorama (--fa3d=<area>[,<area>...]). Not used by the game.
## The painted map (assets/ground/friend_area_<name>.png) and its 8x8 walk grid (_collision.json):
##   - walkable cells: flat ground, the painting laid on the floor
##   - blocked cells joined to the top edge above the first walkable row: the sky / far scenery, stood up as
##     a backdrop at the back of the area
##   - other blocked cells (flower beds, trees, rocks, water edges): raised voxel columns, higher the further
##     they are from the walkable ground, coloured from the painting
## A few residents stand on the ground as voxel figures (scripts/dungeon/voxel/vox_mon.gd).

const MON := preload("res://scripts/dungeon/voxel/vox_mon.gd")
const CELL := 8
const STEP := 2                  # voxel column size in map pixels
const MAX_H := 22.0
const GRASS_CONTRAST := 0.09

var areas: Array = []
var vp: SubViewport

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fa3d="):
			areas = a.substr(7).split(",")
	_run.call_deferred()

func _run() -> void:
	var shots: Array = []
	for nm in areas:
		var img := await _render(str(nm))
		if img:
			shots.append(img)
			img.save_png("user://fa3d_%s%s.png" % [nm, "_close" if " ".join(OS.get_cmdline_user_args()).contains("--fazoom=") else ""])
			print("FA3D ", nm)
	get_tree().quit()

func _render(nm: String) -> Image:
	var base := "res://assets/ground/%s" % nm
	if not ResourceLoader.exists(base + ".png"):
		base = "res://assets/ground/friend_area_%s" % nm
	var colbase := base
	if not FileAccess.file_exists(colbase + "_collision.json"):
		colbase = base.trim_suffix("_lo").trim_suffix("_hi")
	var tex: Texture2D = load(base + ".png")
	if tex == null:
		print("FA3D missing ", nm)
		return null
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var col = JSON.parse_string(FileAccess.get_file_as_string(colbase + "_collision.json"))
	var gh: int = col.size()
	var gw: int = col[0].size()
	var W := img.get_width()
	var H := img.get_height()
	# walkable cells and the backdrop region
	var walk := PackedByteArray()
	walk.resize(gw * gh)
	var first_row := gh
	for y in gh:
		for x in gw:
			if int(col[y][x]) == 0:
				walk[y * gw + x] = 1
				first_row = mini(first_row, y)
	var back := PackedByteArray()
	back.resize(gw * gh)
	var stack: Array = []
	for x in gw:
		if walk[x] == 0:
			stack.append(Vector2i(x, 0))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= gw or p.y >= gh or p.y >= first_row:
			continue
		var i := p.y * gw + p.x
		if back[i] or walk[i]:
			continue
		back[i] = 1
		stack.append_array([p + Vector2i.LEFT, p + Vector2i.RIGHT, p + Vector2i.DOWN, p + Vector2i.UP])
	# ---- what stands up: pixels that look like objects, not the ground showing through blocked cells
	# The ground's colours are the common colours of the walkable cells; a blocked pixel in one of those colours
	# (the grass or path between a bush and a house) stays flat. Heights come from each object pixel's distance to
	# the object's edge (in map pixels), on a rounded profile: thin hedges stay low, big trees and roofs dome.
	var gw2 := W / STEP
	var gh2 := H / STEP
	var qk := func(c: Color) -> int:
		return ((c.r8 >> 4) << 8) | ((c.g8 >> 4) << 4) | (c.b8 >> 4)
	var hist := {}
	var nwalk := 0
	for py in range(0, H, STEP):
		for px in range(0, W, STEP):
			var ci0: int = mini(py / CELL, gh - 1) * gw + mini(px / CELL, gw - 1)
			if walk[ci0]:
				var k0: int = qk.call(img.get_pixel(px + STEP / 2, py + STEP / 2))
				hist[k0] = int(hist.get(k0, 0)) + 1
				nwalk += 1
	var ground := {}
	for k1 in hist:
		if int(hist[k1]) >= maxi(3, nwalk / 1000):
			# the colour and its near shades (one step on each channel) count as ground
			var r := (int(k1) >> 8) & 15
			var g := (int(k1) >> 4) & 15
			var b := int(k1) & 15
			for dr in [-2, -1, 0, 1, 2]:
				for dg in [-2, -1, 0, 1, 2]:
					for db in [-2, -1, 0, 1, 2]:
						ground[(clampi(r + dr, 0, 15) << 8) | (clampi(g + dg, 0, 15) << 4) | clampi(b + db, 0, 15)] = true
	var kind := PackedByteArray()        # 0 ground, 1 object, 2 water, 3 backdrop
	kind.resize(gw2 * gh2)
	for y2 in gh2:
		for x2 in gw2:
			var px := x2 * STEP
			var py := y2 * STEP
			var ci: int = mini(py / CELL, gh - 1) * gw + mini(px / CELL, gw - 1)
			var c := img.get_pixel(px + STEP / 2, py + STEP / 2)
			var k := 0
			if back[ci]:
				k = 3
			elif not walk[ci]:
				var water := c.b > c.r + 0.12 and c.b > c.g - 0.08 and c.b > 0.45
				if water:
					k = 2
				elif not ground.has(qk.call(c)):
					k = 1
			kind[y2 * gw2 + x2] = k
	# close small holes inside objects (highlights in a ground colour)
	var kind2 := kind.duplicate()
	for y2 in range(1, gh2 - 1):
		for x2 in range(1, gw2 - 1):
			var i2 := y2 * gw2 + x2
			if kind[i2] != 0:
				continue
			var n := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if kind[i2 + dy * gw2 + dx] == 1:
						n += 1
			if n >= 6:
				kind2[i2] = 1
	kind = kind2
	# smooth green pixels are grass, whatever the walk grid says (shaded grass beside a base, lawns between
	# hedges): flat. Trees have strong leaf shading; roofs are smooth but not green, so both stay up.
	var lumi := PackedFloat32Array()
	lumi.resize(gw2 * gh2)
	for y2 in gh2:
		for x2 in gw2:
			lumi[y2 * gw2 + x2] = img.get_pixel(x2 * STEP + STEP / 2, y2 * STEP + STEP / 2).get_luminance()
	for y2 in range(1, gh2 - 1):
		for x2 in range(1, gw2 - 1):
			var i3 := y2 * gw2 + x2
			if kind[i3] != 1:
				continue
			var lo := 9.0
			var hi := -9.0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var l := lumi[i3 + dy * gw2 + dx]
					lo = minf(lo, l)
					hi = maxf(hi, l)
			var c3 := img.get_pixel(x2 * STEP + STEP / 2, y2 * STEP + STEP / 2)
			if hi - lo < GRASS_CONTRAST and c3.g > c3.r and c3.g > c3.b:
				kind[i3] = 0
	# distance to the object's edge (chamfer 3-4, in STEP units x3)
	var dist := PackedInt32Array()
	dist.resize(gw2 * gh2)
	for i2 in gw2 * gh2:
		dist[i2] = 99999 if kind[i2] == 1 else 0
	for it in 2:
		var ys := range(gh2) if it == 0 else range(gh2 - 1, -1, -1)
		var xs := range(gw2) if it == 0 else range(gw2 - 1, -1, -1)
		var sgn := -1 if it == 0 else 1
		for y2 in ys:
			for x2 in xs:
				var i2: int = y2 * gw2 + x2
				if dist[i2] == 0:
					continue
				var v := dist[i2]
				var xa: int = x2 + sgn
				var ya: int = y2 + sgn
				if xa >= 0 and xa < gw2: v = mini(v, dist[y2 * gw2 + xa] + 3)
				else: v = mini(v, 3)
				if ya >= 0 and ya < gh2:
					v = mini(v, dist[ya * gw2 + x2] + 3)
					if xa >= 0 and xa < gw2: v = mini(v, dist[ya * gw2 + xa] + 4)
				else: v = mini(v, 3)
				dist[i2] = v
	var hmap := {}
	var horizon := float(first_row * CELL)
	for y2 in gh2:
		for x2 in gw2:
			var i2 := y2 * gw2 + x2
			var k := kind[i2]
			if k == 3:
				continue
			var h := 0.0
			if k == 2:
				h = -3.0                                  # ponds and seas sit below the ground
			elif k == 1:
				var d := dist[i2] / 3.0 * STEP            # map pixels to the object's edge
				h = minf(MAX_H, 1.5 + 2.6 * sqrt(d))      # rounded: low at the rim, domed in the middle
			hmap[Vector2i(x2 * STEP, y2 * STEP)] = h
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var quad := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, cl: Color):
		V.append_array([a, b, c, a, c, d])
		for k in 6:
			N.append(n)
			C.append(cl)
	for key in hmap:
		var p: Vector2i = key
		var h: float = hmap[p]
		var c := img.get_pixel(p.x + STEP / 2, p.y + STEP / 2)
		var X := float(p.x)
		var Z := float(p.y)
		var S := float(STEP)
		quad.call(Vector3(X, h, Z), Vector3(X + S, h, Z), Vector3(X + S, h, Z + S), Vector3(X, h, Z + S), Vector3.UP, c)
		for e in [[Vector2i(STEP, 0), Vector3.RIGHT], [Vector2i(-STEP, 0), Vector3.LEFT], [Vector2i(0, STEP), Vector3.BACK], [Vector2i(0, -STEP), Vector3.FORWARD]]:
			var nb: Vector2i = p + e[0]
			var nh: float = hmap.get(nb, -6.0 if not (nb.x >= 0 and nb.y >= 0 and nb.x < W and nb.y < H) else 0.0)
			if nh >= h:
				continue
			var n: Vector3 = e[1]
			var sc := c.darkened(0.25 if n.z != 0 else 0.15)
			match n:
				Vector3.RIGHT: quad.call(Vector3(X + S, nh, Z + S), Vector3(X + S, h, Z + S), Vector3(X + S, h, Z), Vector3(X + S, nh, Z), n, sc)
				Vector3.LEFT: quad.call(Vector3(X, nh, Z), Vector3(X, h, Z), Vector3(X, h, Z + S), Vector3(X, nh, Z + S), n, sc)
				Vector3.BACK: quad.call(Vector3(X, nh, Z + S), Vector3(X, h, Z + S), Vector3(X + S, h, Z + S), Vector3(X + S, nh, Z + S), n, sc)
				_: quad.call(Vector3(X + S, nh, Z), Vector3(X + S, h, Z), Vector3(X, h, Z), Vector3(X, nh, Z), n, sc)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = V
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_COLOR] = C
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# scene
	if vp:
		vp.queue_free()
	vp = SubViewport.new()
	vp.size = Vector2i(1440, 810)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.9)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = true
	env.ssao_radius = 3.0
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.95
	sun.shadow_enabled = false
	sun.shadow_bias = 0.25
	sun.shadow_normal_bias = 3.0
	sun.directional_shadow_max_distance = 2000.0
	world.add_child(sun)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	world.add_child(mi)
	# the backdrop: the sky / far scenery strip standing behind the area
	var strip := img.get_region(Rect2i(0, 0, W, int(horizon)))
	var bt := ImageTexture.create_from_image(strip)
	var bq := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(W * 1.25, horizon * 1.25)
	bq.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.albedo_texture = bt
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bq.material_override = bm
	bq.position = Vector3(W / 2.0, horizon * 1.25 / 2.0 - 2.0, horizon - 1.0)
	world.add_child(bq)
	# residents
	var picks := ["0025", "0001", "0004", "0007", "0133", "0052"]
	var spots: Array = []
	for y in range(first_row + 4, gh - 3, 5):
		for x in range(6, gw - 6, 9):
			if walk[y * gw + x]:
				spots.append(Vector2i(x, y))
	spots.shuffle()
	for i in mini(picks.size(), spots.size()):
		var sp: String = picks[i]
		var man: Dictionary = DB.sprites.get(sp, {})
		if man.is_empty():
			continue
		var A: Dictionary = man.anims.get("Idle", man.anims.values()[0])
		var src := Rect2(int(A.get("x", 0)), int(A.y), int(A.w), int(A.h))
		var m: ArrayMesh = MON.mesh_for("res://assets/sp/" + str(A.get("s", man.sheet)), src, "")
		var fm := MeshInstance3D.new()
		fm.mesh = m
		fm.material_override = mat
		var p: Vector2i = spots[i]
		fm.position = Vector3(p.x * CELL - A.w / 2.0, -2.0, p.y * CELL)
		world.add_child(fm)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var zoom := 1.0
	var focus := Vector2(0.5, 0.52)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fazoom="):
			zoom = float(a.substr(9))
		if a.begins_with("--fafocus="):
			var f := a.substr(10).split("x")
			focus = Vector2(float(f[0]), float(f[1]))
	cam.size = H * 0.78 * zoom
	var th := deg_to_rad(48.0)
	var tgt := Vector3(W * focus.x, 0, H * focus.y)
	var fwd := Vector3(0, -sin(th), -cos(th))
	cam.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), tgt - fwd * 900.0)
	cam.far = 3000
	world.add_child(cam)
	for k in 8:
		await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()
