extends Node
## Remake: the optional 3D (voxel) dungeon view (Game Options -> 3D View -> View: 3D).
##
## The 3D scene (terrain, Pokémon figures, grass, water, lava, weather) renders in a SubViewport shown on a
## CanvasLayer behind the dungeon's 2D canvas. The 3D camera is orthographic and tilted; the 2D Camera2D gets
## the same view with its vertical zoom squashed by sin(tilt), so the 2D floor plane lines up exactly with
## the 3D floor: items, traps, stairs, the shadow markers, move animations, status icons, damage numbers and
## taps on the map all keep working unchanged on top of the 3D view. Only the tile picture and the Pokémon's
## 2D bodies are hidden (MonSprite.body_hidden; their animation state still runs and drives the figures).
## Shader packs (shader_packs.gd) set the look; their screen pass draws under the menus.
## Loaded by path (no class_name): see dungeon.gd voxel_sync().

const PACKS := preload("res://scripts/dungeon/voxel/shader_packs.gd")
const TERRAIN := preload("res://scripts/dungeon/voxel/vox_terrain.gd")
const MON := preload("res://scripts/dungeon/voxel/vox_mon.gd")
const TW := 24

var dg                      # Dungeon
var active := false
var st: Dictionary = {}     # resolved pack settings
var pitch := 55.0

var _bg_layer: CanvasLayer
var _rect: TextureRect
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _post_layer: CanvasLayer
var _post: ColorRect
var _post_mat: ShaderMaterial
var _custom_post: ShaderMaterial = null

var _data: Dictionary = {}
var _map_tex: ImageTexture
var _mats := {}
var _chunks: Node3D
var _floor_id := 0
var _pending: Array = []        # chunk coords still to build, nearest first
var _running := 0
var _mutex := Mutex.new()
var _done: Array = []            # [floor_id, cx, cy, result]
var _figs := {}                  # Mon -> MeshInstance3D
var _weather: CPUParticles3D
var _weather_now := ""
var _torch_now := -1.0
var _tasks: Array = []

const MAX_TASKS := 2

func setup(d) -> void:
	dg = d
	_bg_layer = CanvasLayer.new()
	_bg_layer.layer = -1
	add_child(_bg_layer)
	_rect = TextureRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_layer.add_child(_rect)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	_rect.texture = _vp.get_texture()
	_world = Node3D.new()
	_vp.add_child(_world)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.02, 0.04)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = _env
	_world.add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.directional_shadow_max_distance = 900.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_world.add_child(_sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 1.0
	_cam.far = 3000.0
	_vp.add_child(_cam)
	_cam.current = true
	_chunks = Node3D.new()
	_world.add_child(_chunks)
	_post_layer = CanvasLayer.new()
	_post_layer.layer = 3
	add_child(_post_layer)
	_post = ColorRect.new()
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/voxel/post.gdshader")
	_post.material = _post_mat
	_post_layer.add_child(_post)
	_weather = CPUParticles3D.new()
	_weather.emitting = false
	_world.add_child(_weather)
	set_active(false)

## Turns the 3D view on or off (the 2D view comes back untouched).
func set_active(on: bool) -> void:
	active = on
	_bg_layer.visible = on
	_post_layer.visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	MonSprite.body_hidden = on
	if dg == null:
		return
	if dg.terrain_view:
		dg.terrain_view.visible = not on
	if dg.get("red_fx") != null and is_instance_valid(dg.red_fx):
		dg.red_fx.dark_on = not on
	for m in dg.fs.mons if dg.fs else []:
		if m.visual:
			m.visual.queue_redraw()
	if on:
		apply_settings()
		rebuild()
	else:
		_clear_floor()
	dg.apply_cam_zoom()

func cam_squash() -> float:
	return sin(deg_to_rad(pitch)) if active else 1.0

func apply_settings() -> void:
	st = PACKS.resolve(dg)
	pitch = [35.0, 45.0, 60.0][clampi(int(Game.settings.get("vox_cam", 1)), 0, 2)]
	_sun.light_energy = float(st.sun)
	_sun.light_color = st.sun_col
	_sun.rotation_degrees = Vector3(-float(st.sun_pitch), float(st.sun_yaw), 0)
	_sun.shadow_enabled = int(st.shadows) > 0
	_sun.shadow_blur = 2.5 if int(st.shadows) == 1 else 0.6
	_env.ambient_light_color = st.amb_col
	_env.ambient_light_energy = float(st.ambient)
	_env.glow_enabled = float(st.glow) > 0.0
	_env.glow_intensity = float(st.glow)
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.2
	_env.fog_enabled = int(st.fog) > 0 and float(st.fog_amt) > 0.0
	_env.fog_light_color = st.fog_col
	_env.fog_density = 0.0012 * float(st.fog_amt)
	_env.fog_height = 6.0
	_env.fog_height_density = 0.12 * float(st.fog_amt) if int(st.fog) == 2 else 0.0
	_mats.clear()
	var torch := _torch()
	_torch_now = torch
	for k in ["terrain", "blade", "water", "lava"]:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/voxel/%s.gdshader" % k)
		if _map_tex:
			sm.set_shader_parameter("map", _map_tex)
		sm.set_shader_parameter("torch", torch)
		sm.set_shader_parameter("torch_col", Vector3(st.torch_col.r, st.torch_col.g, st.torch_col.b))
		_mats[k] = sm
	_mats.terrain.set_shader_parameter("ao", float(st.ao))
	_mats.terrain.set_shader_parameter("toon", int(st.toon))
	_mats.terrain.set_shader_parameter("wrap", float(st.wrap))
	_mats.blade.set_shader_parameter("sway", float(st.sway))
	_mats.blade.set_shader_parameter("toon", int(st.toon))
	_mats.water.set_shader_parameter("alpha", float(st.water_alpha))
	_mats.water.set_shader_parameter("waves", float(st.waves))
	_mats.lava.set_shader_parameter("glow", float(st.lava))
	for n in _chunks.get_children():
		_apply_chunk_mats(n)
	for m in _figs:
		_fig_mat(_figs[m])
	# screen pass
	var p := _post_mat
	p.set_shader_parameter("sat", float(st.sat))
	p.set_shader_parameter("contrast", float(st.contrast))
	p.set_shader_parameter("bright", float(st.bright))
	p.set_shader_parameter("tint", Vector3(st.tint.r, st.tint.g, st.tint.b))
	p.set_shader_parameter("tint_amt", float(st.tint_amt))
	p.set_shader_parameter("palette", float(st.palette))
	p.set_shader_parameter("mono", int(st.mono))
	p.set_shader_parameter("dof", int(st.dof))
	p.set_shader_parameter("dof_amt", float(st.dof_amt))
	p.set_shader_parameter("haze", float(st.haze))
	p.set_shader_parameter("paper", float(st.paper))
	p.set_shader_parameter("grain", float(st.grain))
	p.set_shader_parameter("vignette", float(st.vignette))
	p.set_shader_parameter("scan", float(st.scan))
	p.set_shader_parameter("ca", float(st.ca))
	_post.material = _post_mat
	if str(st.get("post_shader", "")) != "":
		var sh := Shader.new()
		sh.code = str(st.post_shader)          # a custom pack's own screen shader
		_custom_post = ShaderMaterial.new()
		_custom_post.shader = sh
		_post.material = _custom_post
	var neutral := is_equal_approx(float(st.sat), 1.0) and is_equal_approx(float(st.contrast), 1.0) \
		and is_equal_approx(float(st.bright), 1.0) and float(st.tint_amt) <= 0.0 and int(st.palette) == 0 \
		and int(st.mono) == 0 and float(st.dof_amt) <= 0.0 and float(st.haze) <= 0.0 and float(st.paper) <= 0.0 \
		and float(st.grain) <= 0.0 and float(st.vignette) <= 0.0 and float(st.scan) <= 0.0 and float(st.ca) <= 0.0
	_post_layer.visible = active and (not neutral or str(st.get("post_shader", "")) != "")
	_update_weather()
	_resize()

func _resize() -> void:
	var ws: Vector2 = Vector2(get_viewport().get_visible_rect().size)
	var real := Vector2(DisplayServer.window_get_size())
	var k := float(st.get("res", 1.0))
	_vp.size = Vector2i(maxi(64, int(real.x * k)), maxi(64, int(real.y * k)))
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if k < 0.99 else CanvasItem.TEXTURE_FILTER_LINEAR

# ------------------------------------------------------------------ floor
func _clear_floor() -> void:
	_floor_id += 1
	_pending.clear()
	for n in _chunks.get_children():
		n.queue_free()
	for m in _figs:
		if is_instance_valid(_figs[m]):
			_figs[m].queue_free()
	_figs.clear()

## A new floor (or the terrain changed): rebuild the chunks, nearest to the leader first.
func rebuild() -> void:
	if not active or dg == null or dg.fs == null or dg.terrain_view == null or dg.terrain_view.tex_sprite == null:
		return
	_clear_floor()
	_data = TERRAIN.prepare(dg)
	_map_tex = ImageTexture.create_from_image(_data.img)
	apply_settings()
	var cx_n: int = TERRAIN.chunks_x(_data)
	var cy_n: int = TERRAIN.chunks_y(_data)
	var lp := Vector2.ZERO
	if dg.fs.leader:
		lp = Vector2(dg.fs.leader.pos.x + TERRAIN.BORDER, dg.fs.leader.pos.y + TERRAIN.BORDER) / float(TERRAIN.CT)
	var all: Array = []
	for cy in cy_n:
		for cx in cx_n:
			all.append(Vector2i(cx, cy))
	all.sort_custom(func(a, b): return Vector2(a).distance_squared_to(lp) < Vector2(b).distance_squared_to(lp))
	_pending = all

func _start_tasks() -> void:
	while _running < MAX_TASKS and not _pending.is_empty():
		var c: Vector2i = _pending.pop_front()
		_running += 1
		var fid := _floor_id
		var dd := _data
		var opts := {"grass": float(st.get("grass", 0.33))}
		var done := _done
		var mx := _mutex
		_tasks.append(WorkerThreadPool.add_task(func():
			var r: Dictionary = TERRAIN.build_chunk(dd, c.x, c.y, opts)
			mx.lock()
			done.append([fid, c.x, c.y, r])
			mx.unlock()))

func _collect() -> void:
	_mutex.lock()
	var got := _done.duplicate()
	_done.clear()
	_mutex.unlock()
	var keep: Array = []
	for t in _tasks:
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
		else:
			keep.append(t)
	_tasks = keep
	for e in got:
		_running -= 1
		if int(e[0]) != _floor_id:
			continue
		var r: Dictionary = e[3]
		var node := Node3D.new()
		node.name = "c%d_%d" % [e[1], e[2]]
		for k in ["solid", "water", "lava"]:
			if r[k] == null:
				continue
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, r[k])
			var mi := MeshInstance3D.new()
			mi.mesh = am
			mi.set_meta("kind", k)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if k == "solid" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mi)
		var bl: Array = r.blades
		if not bl.is_empty():
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = _blade_mesh()
			mm.instance_count = bl.size()
			for i in bl.size():
				var b: Array = bl[i]
				var hgt := float(b[1])
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(1, hgt, 1)), b[0] + Vector3(0, hgt / 2.0, 0)))
				mm.set_instance_color(i, b[2])
				mm.set_instance_custom_data(i, Color(b[0].y, float(b[3]), 0, 0))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.set_meta("kind", "blade")
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(mmi)
		_apply_chunk_mats(node)
		_chunks.add_child(node)

## A blade: two crossed unit quads (drawn from both sides), 12 vertices instead of a box's 24.
static var _bmesh: ArrayMesh = null
static func _blade_mesh() -> ArrayMesh:
	if _bmesh:
		return _bmesh
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	for q in [[Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0), Vector3.BACK],
			[Vector3(0, -0.5, -0.5), Vector3(0, -0.5, 0.5), Vector3(0, 0.5, 0.5), Vector3(0, 0.5, -0.5), Vector3.RIGHT]]:
		V.append_array([q[0], q[1], q[2], q[0], q[2], q[3]])
		for i in 6:
			N.append(q[4])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = V
	a[Mesh.ARRAY_NORMAL] = N
	_bmesh = ArrayMesh.new()
	_bmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return _bmesh

func _apply_chunk_mats(node: Node) -> void:
	for c in node.get_children():
		var k := str(c.get_meta("kind", ""))
		var mat: Material = _mats.get("terrain" if k == "solid" else k)
		if mat:
			c.material_override = mat

# ------------------------------------------------------------------ Pokémon figures
func _fig_mat(mi: MeshInstance3D) -> void:
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/voxel/mon.gdshader")
	sm.set_shader_parameter("toon", int(st.get("toon", 0)))
	sm.set_shader_parameter("wrap", float(st.get("wrap", 0.0)))
	var torch: float = _mats.terrain.get_shader_parameter("torch") if _mats.has("terrain") else 0.0
	sm.set_shader_parameter("torch", torch)
	var tc: Color = st.get("torch_col", Color.WHITE)
	sm.set_shader_parameter("torch_col", Vector3(tc.r, tc.g, tc.b))
	if float(st.get("outline", 0.0)) > 0.0:
		var ol := ShaderMaterial.new()
		ol.shader = load("res://shaders/voxel/outline.gdshader")
		ol.set_shader_parameter("grow", float(st.outline))
		var ink: Color = st.get("ink", Color(0.04, 0.03, 0.06))
		if bool(st.get("neon", false)):
			ink = Color(0.35, 0.85, 1.0)
		ol.set_shader_parameter("ink", ink)
		ol.set_shader_parameter("neon", float(st.get("edge_glow", 0.0)))
		sm.next_pass = ol
	mi.material_override = sm

func _sync_figures() -> void:
	var alive := {}
	for m in dg.fs.mons:
		var v = m.visual
		if v == null or not is_instance_valid(v) or v.vx.is_empty() or not v.visible:
			continue
		alive[m] = true
		var mi: MeshInstance3D = _figs.get(m)
		if mi == null or not is_instance_valid(mi):
			mi = MeshInstance3D.new()
			_world.add_child(mi)
			_fig_mat(mi)
			_figs[m] = mi
		var vx: Dictionary = v.vx
		var shiny: String = m.sp if Shiny.is_shiny(m) else ""
		var mesh: ArrayMesh = MON.mesh_for(str(vx.path), vx.src, shiny)
		mi.mesh = mesh
		var dst: Rect2 = vx.dst
		var g: float = float(vx.ground)
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-(90.0 - pitch) * 0.7))
		var base := Vector3(v.position.x + dst.position.x, 1.0 + (g - dst.end.y), v.position.y + g)
		mi.transform = Transform3D(tilt, base)
		var sm := mi.material_override as ShaderMaterial
		var mod: Color = vx.mod
		mod.a *= v.modulate.a * v.self_modulate.a
		sm.set_shader_parameter("mod_col", mod)
		var glow := Vector3.ZERO
		if Awaken.is_awake(m):
			var pl := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0)
			glow = Vector3(0.5, 0.35, 0.05) * pl
		sm.set_shader_parameter("glow_col", glow)
		sm.render_priority = 1 if mod.a < 0.99 else 0
		sm.set_shader_parameter("lead_pos", _lead_pos())
		mi.visible = mod.a > 0.02
	for m in _figs.keys():
		if not alive.has(m):
			if is_instance_valid(_figs[m]):
				_figs[m].queue_free()
			_figs.erase(m)

func _lead_pos() -> Vector3:
	if dg.fs and dg.fs.leader and dg.fs.leader.visual:
		var p: Vector2 = dg.fs.leader.visual.position
		return Vector3(p.x, 1, p.y)
	return Vector3.ZERO

# ------------------------------------------------------------------ weather
func _update_weather() -> void:
	var w := str(dg.fs.weather) if dg and dg.fs else "clear"
	var lvl := int(st.get("weather", 1))
	_weather.emitting = false
	if lvl == 0 or not w in ["rain", "hail", "snow", "sandstorm"]:
		return
	var heavy := lvl == 2
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match w:
		"rain":
			bm.size = Vector3(0.4, 6, 0.4)
			mat.albedo_color = Color(0.7, 0.8, 1.0, 0.6)
			_weather.gravity = Vector3(-30, -900, 0)
		"hail":
			bm.size = Vector3(1.2, 1.2, 1.2)
			mat.albedo_color = Color(0.9, 0.95, 1.0)
			_weather.gravity = Vector3(0, -700, 0)
		"snow":
			bm.size = Vector3(1, 1, 1)
			mat.albedo_color = Color(1, 1, 1)
			_weather.gravity = Vector3(10, -60, 0)
		"sandstorm":
			bm.size = Vector3(1.5, 1, 1)
			mat.albedo_color = Color(0.85, 0.7, 0.45, 0.8)
			_weather.gravity = Vector3(500, -40, 0)
	if mat.albedo_color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.material = mat
	_weather.mesh = bm
	_weather.amount = 1600 if heavy else 700
	_weather.lifetime = 1.4 if w != "snow" else 6.0
	_weather.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_weather.emission_box_extents = Vector3(260, 2, 200)
	_weather.direction = Vector3(0, -1, 0)
	_weather.initial_velocity_min = 0.0
	_weather.initial_velocity_max = 40.0
	_weather.local_coords = false
	_weather.emitting = true

# ------------------------------------------------------------------ per frame
func _process(_dt: float) -> void:
	if not active or dg == null or dg.fs == null or dg.cam == null:
		return
	if _vp.size != Vector2i(Vector2(DisplayServer.window_get_size()) * float(st.get("res", 1.0))):
		_resize()
	_collect()
	_start_tasks()
	# camera: the same view as the 2D Camera2D (see the header)
	var s: float = dg.cam.zoom.x
	var h: float = get_viewport().get_visible_rect().size.y
	_cam.size = h / maxf(0.01, s)
	var tgt := Vector3(dg.cam.position.x, 1.0, dg.cam.position.y)
	var th := deg_to_rad(pitch)
	var fwd := Vector3(0, -sin(th), -cos(th))
	_cam.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), tgt - fwd * 900.0)
	_weather.position = tgt + Vector3(0, 220, 40)
	if str(dg.fs.weather) != _weather_now:
		_weather_now = str(dg.fs.weather)
		_update_weather()
	var tr := _torch()
	if tr != _torch_now:
		_torch_now = tr
		for k in ["terrain", "blade", "water"]:
			if _mats.has(k):
				_mats[k].set_shader_parameter("torch", tr)
		for m in _figs:
			if is_instance_valid(_figs[m]):
				(_figs[m].material_override as ShaderMaterial).set_shader_parameter("torch", tr)
	var lp := _lead_pos()
	for k in ["terrain", "blade", "water"]:
		if _mats.has(k):
			_mats[k].set_shader_parameter("lead_pos", lp)
	_sync_figures()

func _exit_tree() -> void:
	_pending.clear()
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
	MonSprite.body_hidden = false

func _torch() -> float:
	if dg.fs and int(dg.fs.visibility) > 0 and not bool(dg.fs.get_meta("all_revealed", false)):
		return float(st.get("torch", 2.6)) * TW
	return 0.0

## Debug / tests: chunks still to build.
func stats() -> String:
	var v := 0
	var b := 0
	for n in _chunks.get_children():
		for c in n.get_children():
			if c is MeshInstance3D and c.mesh:
				v += c.mesh.surface_get_array_len(0)
			elif c is MultiMeshInstance3D:
				b += c.multimesh.instance_count
	return "chunks %d, vertices %d, blades %d" % [_chunks.get_child_count(), v, b]

func built() -> int:
	return _chunks.get_child_count()

func pending() -> int:
	return _pending.size() + _running
