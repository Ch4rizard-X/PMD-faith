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
var _splash: CPUParticles3D
var _fog: MeshInstance3D
var _fog_mat: ShaderMaterial
var _wet := 0.0                  # 0..1, follows the weather over a few seconds
var _snow := 0.0
var _wtarget := {"wet": 0.0, "snow": 0.0}
var _base_light := {}
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
	# rain splashes on the floor
	_splash = CPUParticles3D.new()
	_splash.emitting = false
	_splash.local_coords = false
	_splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_splash.emission_box_extents = Vector3(230, 0.1, 170)
	_splash.direction = Vector3(0, 1, 0)
	_splash.spread = 60.0
	_splash.initial_velocity_min = 8.0
	_splash.initial_velocity_max = 18.0
	_splash.gravity = Vector3(0, -120, 0)
	_splash.lifetime = 0.25
	_splash.scale_amount_min = 0.6
	_splash.scale_amount_max = 1.2
	var sm := BoxMesh.new()
	sm.size = Vector3(0.6, 0.6, 0.6)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(0.85, 0.92, 1.0, 0.75)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = smat
	_splash.mesh = sm
	_world.add_child(_splash)
	# drifting fog / blowing sand: a big plane a little above the floor
	_fog = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1100)
	_fog.mesh = pm
	_fog_mat = ShaderMaterial.new()
	_fog_mat.shader = load("res://shaders/voxel/weather_fog.gdshader")
	_fog.material_override = _fog_mat
	_fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fog.visible = false
	_world.add_child(_fog)
	set_active(false)

## Turns the 3D view on or off (the 2D view comes back untouched).
func set_active(on: bool) -> void:
	active = on
	_bg_layer.visible = on
	_post_layer.visible = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	MonSprite.body_hidden = on
	MonSprite.fig_k = fig_k()
	if dg == null:
		return
	if dg.terrain_view:
		dg.terrain_view.visible = not on
	if dg.get("red_fx") != null and is_instance_valid(dg.red_fx):
		dg.red_fx.dark_on = not on
	for m in dg.fs.mons if dg.fs else []:
		if m.visual:
			m.visual.queue_redraw()
	if dg.get("obj_layer") != null:
		dg.obj_layer.queue_redraw()             # stairs / traps / items move between the 2D and 3D floors
	_objs_sig = ""
	if on:
		apply_settings()
		rebuild()
	else:
		_clear_floor()
	dg.apply_cam_zoom()

func cam_squash() -> float:
	return sin(deg_to_rad(pitch)) if active else 1.0

## How far the figures lean back from upright, toward the camera (degrees).
func lean() -> float:
	return (90.0 - pitch) * 0.7

## The figures' size: a standing figure is taller on screen than the tilted floor around it, so it would tower
## over corridors and walls; it's scaled down (keeping its proportions) halfway to the floor's squash.
func fig_s() -> float:
	if not active:
		return 1.0
	return minf(1.0, sqrt(sin(deg_to_rad(pitch)) / cos(deg_to_rad(pitch - lean()))))

## A figure pixel's height in 2D-world units: its screen height (cos(pitch - lean)) over the floor's squash.
func fig_k() -> float:
	if not active:
		return 1.0
	return fig_s() * cos(deg_to_rad(pitch - lean())) / sin(deg_to_rad(pitch))

func apply_settings() -> void:
	st = PACKS.resolve(dg)
	pitch = [35.0, 45.0, 60.0][clampi(int(Game.settings.get("vox_cam", 1)), 0, 2)]
	MonSprite.fig_k = fig_k()
	_base_light = {"sun": float(st.sun), "sun_col": st.sun_col, "amb": float(st.ambient), "amb_col": st.amb_col}
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
	_env.fog_enabled = false
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
	p.set_shader_parameter("fog", int(st.fog))
	p.set_shader_parameter("fog_amt", float(st.fog_amt))
	p.set_shader_parameter("fog_col", Vector3(st.fog_col.r, st.fog_col.g, st.fog_col.b))
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
		and float(st.grain) <= 0.0 and float(st.vignette) <= 0.0 and float(st.scan) <= 0.0 and float(st.ca) <= 0.0 \
		and (int(st.fog) == 0 or float(st.fog_amt) <= 0.0)
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
	for m in _marks:
		if is_instance_valid(_marks[m]):
			_marks[m].queue_free()
	_marks.clear()
	if _objs != null and is_instance_valid(_objs):
		_objs.queue_free()
	_objs = null
	_objs_sig = ""

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

## Figures are drawn pulled toward the camera (depth only, the picture doesn't move): enough that the leaning
## top stays in front of the wall behind, the feet in front of the wall tops below, and pixels under the
## shadow line on top of the floor instead of in it - as the 2D sprites are drawn over walls and floor.
func _fig_push(sm: ShaderMaterial) -> void:
	var th := deg_to_rad(pitch)
	var c := 14.0 / cos(th)
	var k := absf(sin(deg_to_rad(lean()))) / cos(th) + 0.1
	sm.set_shader_parameter("push_c", c)
	sm.set_shader_parameter("push_k", k)
	sm.set_shader_parameter("push_floor", 1.0 / sin(th) + 0.2)
	if sm.next_pass is ShaderMaterial:
		for n in ["push_c", "push_k", "push_floor"]:
			(sm.next_pass as ShaderMaterial).set_shader_parameter(n, sm.get_shader_parameter(n))

## Walls open up in front of the Pokémon on screen (terrain / blade shaders' xray_cut).
func _sync_xray(fwd: Vector3) -> void:
	var arr: Array = []
	var fs_ := fig_s()
	var near := Vector2(dg.cam.position)
	var list: Array = []
	for m in _figs:
		var mi: MeshInstance3D = _figs[m]
		if is_instance_valid(mi) and mi.visible and m.visual:
			list.append([Vector2(m.visual.position).distance_squared_to(near), m])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for e in list.slice(0, 12):
		var v = e[1].visual
		var h := 26.0
		if not v.vx.is_empty():
			h = maxf(16.0, float(v.vx.ground) - (v.vx.dst as Rect2).position.y)
		var feet := Vector3(v.position.x, 1.0, v.position.y + float(v.vx.get("ground", 4.0)))
		var up := Basis(Vector3.RIGHT, deg_to_rad(-lean())) * Vector3.UP
		arr.append(Vector4(feet.x + up.x * h * 0.5 * fs_, feet.y + up.y * h * 0.5 * fs_, feet.z + up.z * h * 0.5 * fs_, maxf(13.0, h * 0.62 * fs_)))
	while arr.size() < 12:
		arr.append(Vector4.ZERO)
	for k in ["terrain", "blade"]:
		if _mats.has(k):
			_mats[k].set_shader_parameter("xray", arr)
			_mats[k].set_shader_parameter("xray_n", mini(list.size(), 12))
			_mats[k].set_shader_parameter("view_fwd", fwd)

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
			# the figure is drawn pulled toward the camera (_fig_push); in the sun's shadow pass that would shade
			# it with its own shadow, so a plain twin casts the shadow and the figure itself casts none
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var tw := MeshInstance3D.new()
			tw.name = "shadow"
			tw.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			var tm := StandardMaterial3D.new()
			tm.cull_mode = BaseMaterial3D.CULL_DISABLED
			tw.material_override = tm
			mi.add_child(tw)
			_figs[m] = mi
		var vx: Dictionary = v.vx
		var shiny: String = m.sp if Shiny.is_shiny(m) else ""
		var mesh: ArrayMesh = MON.mesh_for(str(vx.path), vx.src, shiny)
		mi.mesh = mesh
		var twin := mi.get_node_or_null("shadow") as MeshInstance3D
		if twin:
			twin.mesh = mesh
		var dst: Rect2 = vx.dst
		var g: float = float(vx.ground)
		var tilt := Basis(Vector3.RIGHT, deg_to_rad(-lean()))
		# tilted about the feet (the shadow row, 1 above the floor plane), so leaning doesn't lift the figure off
		# its shadow marker; the frame's rows below the feet are drawn over the floor (_fig_push)
		var fs_ := fig_s()
		var feet := Vector3(v.position.x, 1.0, v.position.y + g)
		mi.transform = Transform3D(tilt.scaled(Vector3(fs_, fs_, fs_)), feet) * Transform3D(Basis(), Vector3(dst.position.x, -(dst.end.y - g), 0))
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
		sm.set_shader_parameter("wet", _wet)
		_fig_push(sm)
		mi.visible = mod.a > 0.02
		_sync_mark(m, v, vx.get("mark", {}))
	for m in _figs.keys():
		if not alive.has(m):
			if is_instance_valid(_figs[m]):
				_figs[m].queue_free()
			_figs.erase(m)
	for m in _marks.keys():
		if not alive.has(m):
			if is_instance_valid(_marks[m]):
				_marks[m].queue_free()
			_marks.erase(m)

## The shadow marker under a Pokémon (team colour / plain shadow) as a flat tile on the floor, under its figure.
var _marks := {}                 # Mon -> MeshInstance3D

func _sync_mark(m, v, mk: Dictionary) -> void:
	var mi: MeshInstance3D = _marks.get(m)
	if mk.is_empty() or mk.get("tex") == null:
		if mi and is_instance_valid(mi):
			mi.visible = false
		return
	var tex: Texture2D = mk.tex
	var sz := tex.get_size()
	if mi == null or not is_instance_valid(mi):
		mi = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.render_priority = -1
		mi.material_override = mat
		_world.add_child(mi)
		_marks[m] = mi
	(mi.mesh as PlaneMesh).size = sz
	var mat2 := mi.material_override as StandardMaterial3D
	if mat2.albedo_texture != tex:
		mat2.albedo_texture = tex
	var col: Color = mk.get("col", Color.WHITE)
	col.a *= v.modulate.a * v.self_modulate.a
	mat2.albedo_color = col
	var p: Vector2 = v.position + Vector2(mk.pos) + sz / 2.0
	mi.position = Vector3(p.x, OBJ_Y + 0.04, p.y)
	mi.visible = v.visible and col.a > 0.02

func _lead_pos() -> Vector3:
	if dg.fs and dg.fs.leader and dg.fs.leader.visual:
		var p: Vector2 = dg.fs.leader.visual.position
		return Vector3(p.x, 1, p.y)
	return Vector3.ZERO

# ------------------------------------------------------------------ weather
## Weather in the 3D view (dungeon weather, Red's names). Falling particles, splashes, drifting fog or sand,
## the light of the sky, and targets for wet surfaces / settled snow (they follow over a few seconds).
func _update_weather() -> void:
	var w := str(dg.fs.weather) if dg and dg.fs else "clear"
	var lvl := int(st.get("weather", 1))
	_weather.emitting = false
	_splash.emitting = false
	_fog.visible = false
	_wtarget = {"wet": 0.0, "snow": 0.0}
	# the sky's light
	var L: Dictionary = _base_light if not _base_light.is_empty() else {"sun": 0.9, "sun_col": Color(1, 0.96, 0.88), "amb": 0.35, "amb_col": Color(0.6, 0.62, 0.72)}
	var sun: float = L.sun
	var sun_col: Color = L.sun_col
	var amb: float = L.amb
	var amb_col: Color = L.amb_col
	if lvl > 0:
		match w:
			"sunny":
				sun *= 1.3
				sun_col = sun_col.lerp(Color(1.0, 0.86, 0.62), 0.45)
				_sun.shadow_blur = 0.4
			"cloudy":
				sun *= 0.55
				amb *= 1.2
				amb_col = amb_col.lerp(Color(0.62, 0.64, 0.68), 0.6)
			"rain", "hail":
				sun *= 0.5
				sun_col = sun_col.lerp(Color(0.75, 0.82, 0.95), 0.6)
				amb_col = amb_col.lerp(Color(0.5, 0.55, 0.65), 0.6)
			"snow":
				sun *= 0.8
				sun_col = sun_col.lerp(Color(0.85, 0.92, 1.0), 0.6)
				amb *= 1.25
			"sandstorm":
				sun *= 0.7
				sun_col = sun_col.lerp(Color(1.0, 0.82, 0.55), 0.6)
				amb_col = amb_col.lerp(Color(0.75, 0.62, 0.45), 0.5)
			"fog":
				sun *= 0.6
				amb *= 1.3
	_sun.light_energy = sun
	_sun.light_color = sun_col
	_env.ambient_light_energy = amb
	_env.ambient_light_color = amb_col
	if lvl == 0 or not w in ["rain", "hail", "snow", "sandstorm", "fog"]:
		return
	var heavy := lvl == 2
	match w:
		"rain":
			_wtarget.wet = 1.0
		"hail":
			_wtarget.wet = 0.4
			_wtarget.snow = 0.25 if heavy else 0.15
		"snow":
			_wtarget.snow = 0.75 if heavy else 0.5
		"sandstorm", "fog":
			_fog.visible = true
			if w == "fog":
				_fog_mat.set_shader_parameter("col", Vector3(0.82, 0.85, 0.9))
				_fog_mat.set_shader_parameter("amount", 0.75 if heavy else 0.55)
				_fog_mat.set_shader_parameter("wind", Vector2(5, 1.5))
				_fog_mat.set_shader_parameter("scale", 0.008)
				return
			_fog_mat.set_shader_parameter("col", Vector3(0.86, 0.7, 0.45))
			_fog_mat.set_shader_parameter("amount", 0.7 if heavy else 0.5)
			_fog_mat.set_shader_parameter("wind", Vector2(90, 12))
			_fog_mat.set_shader_parameter("scale", 0.014)
	var bm := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match w:
		"rain":
			bm.size = Vector3(0.4, 6, 0.4)
			mat.albedo_color = Color(0.7, 0.8, 1.0, 0.6)
			_weather.gravity = Vector3(-30, -900, 0)
			_splash.amount = 400 if heavy else 180
			_splash.emitting = true
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

## Wet surfaces / settled snow follow the weather (about 6 s to soak, 12 s to dry or melt).
func _weather_tick(dt: float) -> void:
	var tw: float = _wtarget.wet
	var ts: float = _wtarget.snow
	_wet = move_toward(_wet, tw, dt / (6.0 if tw > _wet else 12.0))
	_snow = move_toward(_snow, ts, dt / (10.0 if ts > _snow else 14.0))
	for k in ["terrain", "blade"]:
		if _mats.has(k):
			_mats[k].set_shader_parameter("wet", _wet)
			_mats[k].set_shader_parameter("snow", _snow)
	if _mats.has("water"):
		_mats.water.set_shader_parameter("rain", 0.8 if str(_weather_now) == "rain" else 0.0)

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
	_splash.position = tgt + Vector3(0, 1.2, 0)
	_fog.position = tgt + Vector3(0, 7.0, 0)
	_weather_tick(_dt)
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
	_sync_objects()
	_tick_items()
	_sync_xray(fwd)

# ------------------------------------------------------------------ floor objects
## The stairs, traps, items and the Kecleon Shop floor (Dungeon.floor_objects) as flat tiles on the 3D floor,
## so Pokémon stand on them instead of being covered by the 2D layer. Rebuilt when something changes.
var _objs: Node3D
var _objs_sig := ""
var _obj_mats := {}
const OBJ_Y := 1.06

func _sync_objects() -> void:
	var list: Array = dg.floor_objects()
	var sig := str(dg.floor_i) + "|" + str(list.size())
	for o in list:
		sig += "|%d,%d,%d,%d" % [o[1].position.x, o[1].position.y, o[2].position.x, o[2].position.y]
	if sig == _objs_sig and _objs != null and is_instance_valid(_objs):
		return
	_objs_sig = sig
	if _objs != null and is_instance_valid(_objs):
		_objs.queue_free()
	_objs = Node3D.new()
	_world.add_child(_objs)
	_items.clear()
	for o in list:
		var r: Rect2 = o[1]
		if o[0] != null and o[0] == dg._stairs_tex and _data.get("terr") != null:
			continue                                  # the stairs are part of the 3D floor (vox_terrain._stairs)
		if o[0] != null and o[0] == dg._icon_tex:
			_add_item(r, o[2])
			continue
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = r.size
		mi.mesh = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _obj_mat(o[0], o[2], o[3])
		mi.position = Vector3(r.position.x + r.size.x / 2.0, OBJ_Y, r.position.y + r.size.y / 2.0)
		_objs.add_child(mi)

## Items on the floor as small voxel objects made from their icon (vox_mon.gd's figure builder), leaning like the
## Pokémon, bobbing gently, with a soft shadow on the floor and a glint now and then.
var _items: Array = []           # [node, rest position, phase]
static var _blob_tex: ImageTexture

func _add_item(r: Rect2, src: Rect2) -> void:
	var mesh: ArrayMesh = MON.mesh_for("res://assets/ui/items.png", src, "")
	if mesh == null:
		return
	var c := Vector2(r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0)
	var piv := Node3D.new()
	piv.position = Vector3(c.x, 1.0, c.y + 3.0)
	_objs.add_child(piv)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	_fig_mat(mi)
	_fig_push(mi.material_override as ShaderMaterial)
	(mi.material_override as ShaderMaterial).set_shader_parameter("mod_col", Color.WHITE)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var k := 0.8                                     # a bit smaller than the 2D icon, so it reads as an object
	mi.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-lean())).scaled(Vector3(k, k, k)), Vector3.ZERO) \
		* Transform3D(Basis(), Vector3(-src.size.x / 2.0, 0, 0))
	piv.add_child(mi)
	var sh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(15, 7)
	sh.mesh = pm
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = _blob()
	sm.albedo_color = Color(0, 0, 0, 0.45)
	sm.render_priority = -1
	sh.material_override = sm
	sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sh.position = Vector3(c.x, OBJ_Y + 0.03, c.y + 3.0)
	_objs.add_child(sh)
	_items.append([piv, piv.position, fmod(c.x * 0.37 + c.y * 0.11, TAU), mi])

static func _blob() -> ImageTexture:
	if _blob_tex == null:
		var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 32:
				var d := Vector2((x + 0.5 - 16.0) / 16.0, (y + 0.5 - 8.0) / 8.0).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 0.7))
		_blob_tex = ImageTexture.create_from_image(img)
	return _blob_tex

func _tick_items() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for it in _items:
		var n: Node3D = it[0]
		if not is_instance_valid(n):
			continue
		var ph: float = it[2]
		n.position = it[1] + Vector3(0, 1.2 + 1.2 * sin(t * 2.2 + ph), 0)
		var glint := maxf(0.0, sin(t * 1.3 + ph * 2.0)) ** 24
		var sm := (it[3] as MeshInstance3D).material_override as ShaderMaterial
		sm.set_shader_parameter("glow_col", Vector3(1.0, 0.95, 0.8) * glint * 0.3)

func _obj_mat(tex: Texture2D, src: Rect2, col: Color) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [str(tex.get_rid()) if tex else "", str(src), str(col)]
	if _obj_mats.has(key):
		return _obj_mats[key]
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if tex:
		var ts := tex.get_size()
		m.albedo_texture = tex
		m.uv1_scale = Vector3(src.size.x / ts.x, src.size.y / ts.y, 1)
		m.uv1_offset = Vector3(src.position.x / ts.x, src.position.y / ts.y, 0)
	else:
		m.albedo_color = col
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_obj_mats[key] = m
	return m

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
