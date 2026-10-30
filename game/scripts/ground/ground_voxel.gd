extends Node
## Remake: the 3D view for ground maps (Game Options -> 3D View -> View: 3D): the town, the team bases, Makuhita
## Dojo, Whiscash Pond, the Post Office and the Friend Areas as voxel dioramas built from the map's own painting:
##   - walkable ground stays flat with the painting on it; smooth green pixels (lawns between bushes and houses)
##     too, whatever the walk grid says
##   - other pixels the walk grid blocks that aren't in a ground colour (trees, houses, bushes, rocks) stand up as
##     columns, on a rounded profile from their distance to the object's edge (thin hedges low, trees and roofs
##     domed); what the map draws above the actors (roofs, treetops) always counts as tall
##   - ponds, rivers and seas sit below the ground; the sky and far scenery above the first walkable row stand up
##     as a backdrop at the back
##   - Pokémon are the dungeon view's voxel figures (scripts/dungeon/voxel/vox_mon.gd) from their current frame
## Text, emote bubbles and ornament objects stay 2D; the 2D world is squashed by sin(pitch) so they sit where the
## 3D ground is (as Dungeon.apply_cam_zoom does). Indoor rooms, cutscene backdrops and dungeons keep the 2D view.
## Loaded by path (no class_name): scripts/ground/ground.gd creates it.

const MON := preload("res://scripts/dungeon/voxel/vox_mon.gd")
const CELL := 8
const STEP := 2
const MAX_H := 22.0
const GRASS_CONTRAST := 0.09
const PREFIXES := ["friend_area_", "team_base_", "pokemon_square", "makuhita_dojo", "whiscash_pond", "pelipper_post_office"]

var g                       # Ground
var active := false         # the current map is shown in 3D
var pitch := 45.0
var _bg_layer: CanvasLayer
var _rect: TextureRect
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _terrain: MeshInstance3D
var _backdrop: MeshInstance3D
var _figs := {}             # GSprite -> MeshInstance3D
var _shadows := {}          # GSprite -> MeshInstance3D
var _mat: StandardMaterial3D
var _task := -1
var _result: Array = []
var _map_id := 0
var _hidden_2d: Array = []

func setup(ground) -> void:
	g = ground
	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = -1
	add_child(_bg_layer)
	_rect = TextureRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(_rect)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	_rect.texture = _vp.get_texture()
	_world = Node3D.new()
	_vp.add_child(_world)
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.04, 0.05, 0.12)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.75, 0.78, 0.9)
	_env.ambient_light_energy = 0.6
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.ssao_enabled = true
	_env.ssao_radius = 3.0
	_env.ssao_intensity = 1.4
	var we := WorldEnvironment.new()
	we.environment = _env
	_world.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -35, 0)
	_sun.light_energy = 0.9
	_world.add_child(_sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.far = 4000.0
	_world.add_child(_cam)
	_mat = StandardMaterial3D.new()
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true
	_mat.roughness = 1.0
	_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_bg_layer.visible = false

## 3D View is on in Game Options.
static func wanted() -> bool:
	return int(Game.settings.get("vox_view", 0)) == 1

static func eligible(map_file: String, info: Dictionary) -> bool:
	if info.is_empty() or bool(info.get("dungeon_map", false)) or str(info.get("collision", "")) == "":
		return false
	if map_file.contains("inside"):
		return false
	for p in PREFIXES:
		if map_file.begins_with(p):
			return true
	return false

## A new map was loaded (Ground._load_map): build its diorama in the background, or show it in 2D.
func on_map() -> void:
	_map_id += 1
	_clear()
	if not (wanted() and eligible(str(g.map_file), g.map_info)):
		_set_active(false)
		return
	pitch = [35.0, 45.0, 60.0][clampi(int(Game.settings.get("vox_cam", 1)), 0, 2)]
	var img := _composite()
	var hi := _hi_mask()
	if img == null:
		_set_active(false)
		return
	var col: Array = g.collision.duplicate(true)
	var id := _map_id
	var t0 := Time.get_ticks_msec()
	_task = WorkerThreadPool.add_task(func():
		var r := _build(img, col, hi)
		_result = [id, r]
		if OS.get_cmdline_user_args().has("--voxdbg"):
			print("GVOX built %s in %d ms, %d verts" % [str(g.map_file), Time.get_ticks_msec() - t0, (r.get("V", PackedVector3Array()) as PackedVector3Array).size()]))
	_set_active(true)

## The map is going away (Ground._clear_map_nodes): back to 2D until the next map decides.
func deactivate() -> void:
	_map_id += 1
	_clear()
	_set_active(false)

func _set_active(on: bool) -> void:
	active = on
	_bg_layer.visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	GSprite.body_hidden = on
	for n in _hidden_2d:
		if is_instance_valid(n):
			n.visible = true
	_hidden_2d.clear()
	if on:
		for n in g.world.get_children():
			if n != g.actors and n != g.weather and n is CanvasItem and n.visible:
				n.visible = false
				_hidden_2d.append(n)

func _clear() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_result = []
	for n in [_terrain, _backdrop]:
		if n and is_instance_valid(n):
			n.queue_free()
	_terrain = null
	_backdrop = null
	for d in [_figs, _shadows]:
		for k in d:
			if is_instance_valid(d[k]):
				d[k].queue_free()
		d.clear()

## The map's layers drawn together at the map's own size (HD layers scaled back down).
func _composite() -> Image:
	var info: Dictionary = g.map_info
	var w := int(info.get("w", 240))
	var h := int(info.get("h", 160))
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var any := false
	for lf in info.get("layers", []):
		var tex: Texture2D = GData.ground_tex(str(lf), false)
		if tex == null:
			continue
		var im := tex.get_image()
		if im.is_compressed():
			im.decompress()
		im.convert(Image.FORMAT_RGBA8)
		if im.get_width() != w or im.get_height() != h:
			im.resize(w, h, Image.INTERPOLATE_NEAREST)
		out.blend_rect(im, Rect2i(0, 0, w, h), Vector2i.ZERO)
		any = true
	return out if any else null

## Opaque pixels of the layer drawn above the actors (roofs, treetops): always tall.
func _hi_mask() -> Image:
	var above = g.map_info.get("above_layer", null)
	if above == null:
		return null
	var tex: Texture2D = GData.ground_tex(str(above), false)
	if tex == null:
		return null
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	var w := int(g.map_info.get("w", 240))
	var h := int(g.map_info.get("h", 160))
	if im.get_width() != w or im.get_height() != h:
		im.resize(w, h, Image.INTERPOLATE_NEAREST)
	return im

# ------------------------------------------------------------------ building (worker thread)
func _build(img: Image, col: Array, hi: Image) -> Dictionary:
	var W := img.get_width()
	var H := img.get_height()
	var gh: int = col.size()
	var gw: int = col[0].size() if gh > 0 else 0
	if gw == 0:
		return {}
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
	# the backdrop only where the top really is sky / far scenery: mostly blue or bright (Beau Plains' sky);
	# a forest or cliff along the top edge (the town, the bases) stays part of the diorama
	var sky_n := 0
	var back_n := 0
	for y in gh:
		for x in gw:
			if back[y * gw + x]:
				back_n += 1
				var c0 := img.get_pixel(mini(x * CELL + 4, W - 1), mini(y * CELL + 4, H - 1))
				if (c0.b > c0.r and c0.b > c0.g * 0.85) or c0.get_luminance() > 0.72:
					sky_n += 1
	if back_n == 0 or sky_n < back_n * 0.5 or first_row > gh * 0.5:
		back.fill(0)
		first_row = 0
	var gw2 := W / STEP
	var gh2 := H / STEP
	var qk := func(c: Color) -> int:
		return ((c.r8 >> 4) << 8) | ((c.g8 >> 4) << 4) | (c.b8 >> 4)
	var hist := {}
	var nwalk := 0
	for y2 in gh2:
		for x2 in gw2:
			var ci0: int = mini(y2 * STEP / CELL, gh - 1) * gw + mini(x2 * STEP / CELL, gw - 1)
			if walk[ci0]:
				var k0: int = qk.call(img.get_pixel(x2 * STEP + 1, y2 * STEP + 1))
				hist[k0] = int(hist.get(k0, 0)) + 1
				nwalk += 1
	var ground := {}
	for k1 in hist:
		if int(hist[k1]) >= maxi(3, nwalk / 1000):
			var r := (int(k1) >> 8) & 15
			var gg := (int(k1) >> 4) & 15
			var b := int(k1) & 15
			for dr in [-2, -1, 0, 1, 2]:
				for dg in [-2, -1, 0, 1, 2]:
					for db in [-2, -1, 0, 1, 2]:
						ground[(clampi(r + dr, 0, 15) << 8) | (clampi(gg + dg, 0, 15) << 4) | clampi(b + db, 0, 15)] = true
	var kind := PackedByteArray()        # 0 ground, 1 object, 2 water, 3 backdrop
	kind.resize(gw2 * gh2)
	var lumi := PackedFloat32Array()
	lumi.resize(gw2 * gh2)
	var tall := PackedByteArray()        # drawn above the actors
	tall.resize(gw2 * gh2)
	for y2 in gh2:
		for x2 in gw2:
			var px := x2 * STEP + 1
			var py := y2 * STEP + 1
			var i2 := y2 * gw2 + x2
			var ci: int = mini(py / CELL, gh - 1) * gw + mini(px / CELL, gw - 1)
			var c := img.get_pixel(px, py)
			lumi[i2] = c.get_luminance()
			if hi and hi.get_pixel(px, py).a > 0.5:
				tall[i2] = 1
			var k := 0
			if back[ci]:
				k = 3
			elif tall[i2]:
				k = 1
			elif not walk[ci]:
				if c.b > c.r + 0.12 and c.b > c.g - 0.08 and c.b > 0.45:
					k = 2
				elif not ground.has(qk.call(c)):
					k = 1
			kind[i2] = k
	# fill pinholes inside objects; flatten smooth green (grass the walk grid blocks)
	var kind2 := kind.duplicate()
	for y2 in range(1, gh2 - 1):
		for x2 in range(1, gw2 - 1):
			var i2 := y2 * gw2 + x2
			if kind[i2] == 0:
				var n := 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if kind[i2 + dy * gw2 + dx] == 1:
							n += 1
				if n >= 6:
					kind2[i2] = 1
			elif kind[i2] == 1 and not tall[i2]:
				var lo := 9.0
				var hi2 := -9.0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var l := lumi[i2 + dy * gw2 + dx]
						lo = minf(lo, l)
						hi2 = maxf(hi2, l)
				var c3 := img.get_pixel(x2 * STEP + 1, y2 * STEP + 1)
				if hi2 - lo < GRASS_CONTRAST and c3.g > c3.r and c3.g > c3.b:
					kind2[i2] = 0
	kind = kind2
	# distance to the object's edge (chamfer 3-4)
	var dist := PackedInt32Array()
	dist.resize(gw2 * gh2)
	for i2 in gw2 * gh2:
		dist[i2] = 99999 if kind[i2] == 1 else 0
	for it in 2:
		var sgn := -1 if it == 0 else 1
		for yy in gh2:
			var y2: int = yy if it == 0 else gh2 - 1 - yy
			for xx in gw2:
				var x2: int = xx if it == 0 else gw2 - 1 - xx
				var i2: int = y2 * gw2 + x2
				if dist[i2] == 0:
					continue
				var v := dist[i2]
				var xa: int = x2 + sgn
				var ya: int = y2 + sgn
				if xa >= 0 and xa < gw2:
					v = mini(v, dist[y2 * gw2 + xa] + 3)
				else:
					v = mini(v, 3)
				if ya >= 0 and ya < gh2:
					v = mini(v, dist[ya * gw2 + x2] + 3)
					if xa >= 0 and xa < gw2:
						v = mini(v, dist[ya * gw2 + xa] + 4)
				else:
					v = mini(v, 3)
				dist[i2] = v
	var hmap := PackedFloat32Array()
	hmap.resize(gw2 * gh2)
	for i2 in gw2 * gh2:
		match kind[i2]:
			1:
				var d := dist[i2] / 3.0 * STEP
				var h := minf(MAX_H, 1.5 + 2.6 * sqrt(d))
				if tall[i2]:
					h = maxf(h, 8.0)
				hmap[i2] = h
			2:
				hmap[i2] = -3.0
			3:
				hmap[i2] = -999.0
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	var S := float(STEP)
	for y2 in gh2:
		for x2 in gw2:
			var i2 := y2 * gw2 + x2
			var h := hmap[i2]
			if h <= -999.0:
				continue
			var c := img.get_pixel(x2 * STEP + 1, y2 * STEP + 1)
			var X := float(x2 * STEP)
			var Z := float(y2 * STEP)
			_quad(V, N, C, Vector3(X, h, Z), Vector3(X + S, h, Z), Vector3(X + S, h, Z + S), Vector3(X, h, Z + S), Vector3.UP, c)
			for e in [[1, 0, Vector3.RIGHT], [-1, 0, Vector3.LEFT], [0, 1, Vector3.BACK], [0, -1, Vector3.FORWARD]]:
				var nx: int = x2 + e[0]
				var ny: int = y2 + e[1]
				var nh := -6.0
				if nx >= 0 and ny >= 0 and nx < gw2 and ny < gh2:
					nh = hmap[ny * gw2 + nx]
					if nh <= -999.0:
						nh = 0.0
				if nh >= h:
					continue
				var n: Vector3 = e[2]
				var sc := c.darkened(0.25 if n.z != 0 else 0.15)
				match n:
					Vector3.RIGHT: _quad(V, N, C, Vector3(X + S, nh, Z + S), Vector3(X + S, h, Z + S), Vector3(X + S, h, Z), Vector3(X + S, nh, Z), n, sc)
					Vector3.LEFT: _quad(V, N, C, Vector3(X, nh, Z), Vector3(X, h, Z), Vector3(X, h, Z + S), Vector3(X, nh, Z + S), n, sc)
					Vector3.BACK: _quad(V, N, C, Vector3(X, nh, Z + S), Vector3(X, h, Z + S), Vector3(X + S, h, Z + S), Vector3(X + S, nh, Z + S), n, sc)
					_: _quad(V, N, C, Vector3(X + S, nh, Z), Vector3(X + S, h, Z), Vector3(X, h, Z), Vector3(X, nh, Z), n, sc)
	var horizon := first_row * CELL if first_row < gh else 0
	if horizon <= 0:
		return {"V": V, "N": N, "C": C, "W": W, "H": H, "horizon": 0, "strip": null}
	var strip: Image = img.get_region(Rect2i(0, 0, W, horizon)) if horizon > 4 else null
	return {"V": V, "N": N, "C": C, "W": W, "H": H, "horizon": horizon, "strip": strip}

static func _quad(V: PackedVector3Array, N: PackedVector3Array, C: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, cl: Color) -> void:
	V.append_array([a, b, c, a, c, d])
	for k in 6:
		N.append(n)
		C.append(cl)

func _apply_result(r: Dictionary) -> void:
	if r.is_empty() or (r.V as PackedVector3Array).is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = r.V
	arr[Mesh.ARRAY_NORMAL] = r.N
	arr[Mesh.ARRAY_COLOR] = r.C
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_terrain = MeshInstance3D.new()
	_terrain.mesh = mesh
	_terrain.material_override = _mat
	_world.add_child(_terrain)
	if r.strip != null:
		var W: float = r.W
		var hz: float = r.horizon
		_backdrop = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(W * 1.25, hz * 1.25 / sin(deg_to_rad(pitch)))
		_backdrop.mesh = qm
		var bm := StandardMaterial3D.new()
		bm.albedo_texture = ImageTexture.create_from_image(r.strip)
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_backdrop.material_override = bm
		_backdrop.position = Vector3(W / 2.0, qm.size.y / 2.0 - 2.0, hz - 1.0)
		_world.add_child(_backdrop)

# ------------------------------------------------------------------ every frame
## Ground._render calls this with the view centre (map pixels), the zoom and the viewport size, after placing
## the 2D world; it squashes the 2D world vertically so 2D overlays sit on the 3D ground.
func sync(center: Vector2, zoom: float, vs: Vector2) -> void:
	if not active:
		return
	if _task >= 0 and not _result.is_empty() and int(_result[0]) == _map_id:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply_result(_result[1])
		_result = []
	var sq := sin(deg_to_rad(pitch))
	g.world.scale = Vector2(zoom, zoom * sq)
	g.world.position = Vector2(round(vs.x / 2.0 - center.x * zoom), round(vs.y / 2.0 - center.y * zoom * sq))
	if _vp.size != Vector2i(vs):
		_vp.size = Vector2i(DisplayServer.window_get_size())
	_cam.size = vs.y / maxf(0.01, zoom)
	var th := deg_to_rad(pitch)
	var fwd := Vector3(0, -sin(th), -cos(th))
	var tgt := Vector3(center.x, 0.0, center.y)
	_cam.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), tgt - fwd * 1500.0)
	_sync_figures()
	if OS.get_cmdline_user_args().has("--voxdbg") and Engine.get_process_frames() % 60 == 0:
		for n in g.world.get_children():
			if n is CanvasItem and n.visible:
				print("GVOX visible 2D: ", n, " ", n.get_class(), " scale ", n.get("scale"), " tex ", n.get("texture"))
		print("GVOX world ", g.world.scale, " ", g.world.position)
		print("GVOX center ", center, " zoom ", zoom, " vs ", vs, " cam ", _cam.size, " vp ", _vp.size, " terrain ", _terrain != null, " backdrop ", _backdrop != null, " figs ", _figs.size())

func _sync_figures() -> void:
	var alive := {}
	for n in g.actors.get_children():
		if not (n is GSprite):
			continue
		var s: GSprite = n
		if s.vx.is_empty() or not s.is_visible_in_tree():
			continue
		alive[s] = true
		var mi: MeshInstance3D = _figs.get(s)
		if mi == null or not is_instance_valid(mi):
			mi = MeshInstance3D.new()
			var fm := _mat.duplicate() as StandardMaterial3D
			mi.material_override = fm
			_world.add_child(mi)
			_figs[s] = mi
			var sh := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(14, 7)
			sh.mesh = pm
			var smat := StandardMaterial3D.new()
			smat.albedo_color = Color(0, 0, 0, 0.4)
			smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sh.material_override = smat
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_world.add_child(sh)
			_shadows[s] = sh
		var vx: Dictionary = s.vx
		mi.mesh = MON.mesh_for(str(vx.path), vx.src, "")
		var dst: Rect2 = vx.dst
		var gnd: float = float(vx.ground)
		var p: Vector2 = s.position
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-(90.0 - pitch) * 0.7))
		mi.transform = Transform3D(tilt, Vector3(p.x + dst.position.x, gnd - dst.end.y, p.y + gnd))
		var a: float = s.modulate.a * s.self_modulate.a
		var fm2 := mi.material_override as StandardMaterial3D
		fm2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
		fm2.albedo_color = Color(1, 1, 1, a)
		mi.visible = a > 0.02 and s.visible_flag and not (s.blink and (Engine.get_process_frames() & 1))
		var sh2: MeshInstance3D = _shadows[s]
		sh2.visible = mi.visible and bool(s.shadow)
		sh2.position = Vector3(p.x + float(vx.get("fx", 0.0)), 0.05, p.y + gnd)
	for d in [_figs, _shadows]:
		for k in d.keys():
			if not alive.has(k):
				if is_instance_valid(d[k]):
					d[k].queue_free()
				d.erase(k)

func _exit_tree() -> void:
	_clear()
	GSprite.body_hidden = false
