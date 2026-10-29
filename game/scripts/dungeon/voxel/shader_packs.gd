extends RefCounted
## Remake: shader packs for the 3D (voxel) dungeon view. A pack is a set of look settings (light, colour,
## outlines, water, fog, film effects ...); every setting can be overridden in Game Options -> 3D View
## ("Pack" = take the pack's value). Packs are plain data, so new ones ship in script patches; players can
## also drop their own into user://shaderpacks/*.json (see SHADERPACKS.md in the repository):
##   {"name": "My pack", "base": "Vibrant", "settings": {"sat": 1.4, ...}, "post_shader": "<canvas_item code>"}
## Loaded by path (no class_name): preload("res://scripts/dungeon/voxel/shader_packs.gd").

const USER_DIR := "user://shaderpacks/"

## Every look setting with its neutral value.
const BASE := {
	"sun": 0.9, "sun_pitch": 52.0, "sun_yaw": -35.0, "sun_col": Color(1.0, 0.96, 0.88), "ambient": 0.35,
	"amb_col": Color(0.6, 0.62, 0.72), "shadows": 1, "sat": 1.0, "contrast": 1.0, "bright": 1.0,
	"tint": Color(1, 1, 1), "tint_amt": 0.0, "palette": 0, "outline": 0.15, "outline_all": false,
	"ink": Color(0.04, 0.03, 0.06), "neon": false, "sway": 0.55, "grass": 0.22, "water_alpha": 0.72,
	"waves": 1.0, "lava": 1.0, "torch": 2.6, "torch_col": Color(1.0, 0.92, 0.78), "glow": 0.45, "fog": 0,
	"fog_col": Color(0.55, 0.6, 0.7), "fog_amt": 0.0, "ao": 0.35, "dof": 0, "dof_amt": 0.0, "grain": 0.0,
	"vignette": 0.0, "scan": 0.0, "ca": 0.0, "weather": 1, "res": 1.0, "toon": 0, "wrap": 0.0, "paper": 0.0,
	"mono": 0, "haze": 0.0, "edge_glow": 0.0, "post_shader": "",
}

## The packs (name -> settings that differ from BASE).
const PACKS := [
	["Off", {"outline": 0.0, "sway": 0.0, "glow": 0.0, "ao": 0.0, "shadows": 0, "weather": 0, "water_alpha": 0.95, "waves": 0.0}],
	["Classic", {}],
	["Soft", {"sun": 0.75, "ambient": 0.42, "shadows": 1, "ao": 0.6, "sat": 0.95, "contrast": 0.95, "bright": 0.96, "sun_col": Color(1.0, 0.95, 0.9), "sway": 0.4, "waves": 0.6, "glow": 0.25, "outline": 0.1}],
	["Vibrant", {"sun": 1.15, "sat": 1.35, "contrast": 1.12, "glow": 0.9, "lava": 1.4, "water_alpha": 0.62, "waves": 1.3, "sway": 0.8, "outline": 0.18}],
	["Cinematic", {"sun": 0.85, "ambient": 0.22, "shadows": 2, "contrast": 1.22, "sat": 0.85, "bright": 0.88, "tint": Color(0.8, 0.9, 1.0), "tint_amt": 0.12, "fog": 1, "fog_amt": 0.22, "fog_col": Color(0.25, 0.3, 0.4), "vignette": 0.5, "torch": 2.2, "glow": 0.45, "grain": 0.06}],
	["Retro", {"res": 0.5, "palette": 16, "scan": 0.25, "outline": 0.2, "sway": 0.3, "glow": 0.0, "ao": 0.0, "shadows": 0}],
	["Toon", {"toon": 3, "outline": 0.32, "outline_all": true, "sat": 1.2, "ao": 0.0, "shadows": 2, "glow": 0.2}],
	["Claymation", {"wrap": 0.4, "sun": 0.8, "ambient": 0.3, "sat": 1.05, "contrast": 1.02, "bright": 0.95, "sun_col": Color(1.0, 0.9, 0.78), "ao": 0.75, "outline": 0.05, "sway": 0.25, "waves": 0.5, "glow": 0.0}],
	["Miniature", {"dof": 1, "dof_amt": 1.0, "sat": 1.25, "contrast": 1.08, "sun": 1.1, "ao": 0.5}],
	["Storybook", {"paper": 0.6, "sat": 0.75, "contrast": 0.9, "outline": 0.22, "ink": Color(0.18, 0.12, 0.08), "vignette": 0.2, "glow": 0.0}],
	["Neon Night", {"sun": 0.25, "ambient": 0.12, "neon": true, "edge_glow": 1.0, "outline": 0.2, "glow": 1.1, "lava": 1.6, "torch": 3.2, "torch_col": Color(0.7, 0.85, 1.0), "sat": 1.2}],
	["Golden Hour", {"sun_pitch": 22.0, "sun_yaw": -60.0, "sun_col": Color(1.0, 0.72, 0.42), "sun": 1.2, "ambient": 0.35, "amb_col": Color(0.7, 0.55, 0.6), "shadows": 2, "tint": Color(1.0, 0.8, 0.6), "tint_amt": 0.15, "glow": 0.7}],
	["Monochrome", {"mono": 1, "grain": 0.2, "vignette": 0.3, "contrast": 1.15}],
	["Dream", {"sat": 0.85, "bright": 0.95, "contrast": 0.92, "haze": 0.22, "glow": 0.6, "tint": Color(1.0, 0.82, 1.0), "tint_amt": 0.12, "outline": 0.08, "sway": 0.7}],
]

## Game Options rows of the 3D View page: key -> [label, choices]. Index 0 of a tweak row means "Pack".
const ROWS := {
	"vox_view": ["View", ["2D", "3D"]],
	"vox_pack": ["Shader pack", []],                       # filled from pack_names()
	"vox_cam": ["Camera", ["Low", "Medium", "High"]],
	"vox_perf": ["Performance", ["Battery", "Balanced", "Quality"]],
	"vox_auto": ["Pack per dungeon", ["Off", "Auto"]],
	"vox_light": ["Sunlight", ["Pack", "Dim", "Normal", "Bright"]],
	"vox_warm": ["Warmth", ["Pack", "Cool", "Neutral", "Warm"]],
	"vox_shadow": ["Shadows", ["Pack", "Off", "Soft", "Hard"]],
	"vox_sat": ["Saturation", ["Pack", "Low", "Normal", "High", "Max"]],
	"vox_contrast": ["Contrast", ["Pack", "Low", "Normal", "High"]],
	"vox_bright": ["Brightness", ["Pack", "Dark", "Normal", "Bright"]],
	"vox_tint": ["Tint", ["Pack", "None", "Warm", "Cool", "Green", "Purple", "Sepia"]],
	"vox_palette": ["Palette", ["Pack", "Full", "32", "16", "8"]],
	"vox_outline": ["Outlines", ["Pack", "Off", "Thin", "Thick"]],
	"vox_ink": ["Outline on", ["Pack", "Pokémon", "Everything"]],
	"vox_sway": ["Grass sway", ["Pack", "Off", "Low", "Normal", "High"]],
	"vox_grass": ["Grass density", ["Pack", "Sparse", "Normal", "Dense"]],
	"vox_water": ["Water", ["Pack", "Clear", "Normal", "Murky"]],
	"vox_waves": ["Waves", ["Pack", "Calm", "Normal", "Rough"]],
	"vox_lava": ["Lava glow", ["Pack", "Dim", "Normal", "Bright"]],
	"vox_torch": ["Torch light", ["Pack", "Small", "Normal", "Large"]],
	"vox_torchc": ["Torch colour", ["Pack", "Warm", "Neutral", "Cool"]],
	"vox_glow": ["Glow", ["Pack", "Off", "Low", "Normal", "High"]],
	"vox_fog": ["Fog", ["Pack", "Off", "Distance", "Height"]],
	"vox_ao": ["Corner shading", ["Pack", "Off", "On"]],
	"vox_dof": ["Depth of field", ["Pack", "Off", "Tilt-shift", "Background"]],
	"vox_grain": ["Film grain", ["Pack", "Off", "On"]],
	"vox_vignette": ["Vignette", ["Pack", "Off", "On"]],
	"vox_scan": ["Scanlines", ["Pack", "Off", "On"]],
	"vox_ca": ["Colour fringe", ["Pack", "Off", "On"]],
	"vox_weather": ["3D weather", ["Pack", "Off", "On", "Heavy"]],
	"vox_res": ["Resolution", ["Pack", "50%", "75%", "100%"]],
	"vox_save": ["Save as my pack", ["-", "Save"]],
}
const KEYS := ["vox_view", "vox_pack", "vox_cam", "vox_perf", "vox_auto", "vox_light", "vox_warm", "vox_shadow",
	"vox_sat", "vox_contrast", "vox_bright", "vox_tint", "vox_palette", "vox_outline", "vox_ink", "vox_sway",
	"vox_grass", "vox_water", "vox_waves", "vox_lava", "vox_torch", "vox_torchc", "vox_glow", "vox_fog", "vox_ao",
	"vox_dof", "vox_grain", "vox_vignette", "vox_scan", "vox_ca", "vox_weather", "vox_res", "vox_save"]
const DEFAULTS := {"vox_view": 0, "vox_pack": 1, "vox_cam": 1, "vox_perf": 1, "vox_auto": 0}

static var _custom: Array = []            # [[name, settings, post_shader]]
static var _custom_loaded := false

static func on() -> bool:
	return int(Game.settings.get("vox_view", 0)) == 1

static func _load_custom() -> void:
	if _custom_loaded:
		return
	_custom_loaded = true
	_custom.clear()
	var d := DirAccess.open(USER_DIR)
	if d == null:
		return
	var files: Array = Array(d.get_files())
	files.sort()
	for f in files:
		if not str(f).ends_with(".json"):
			continue
		var v = JSON.parse_string(FileAccess.get_file_as_string(USER_DIR + str(f)))
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var st: Dictionary = _base_of(str(v.get("base", "Classic"))).duplicate()
		for k in v.get("settings", {}):
			if BASE.has(k):
				st[k] = _coerce(k, v.settings[k])
		var tw: Dictionary = v.get("tweaks", {})
		_custom.append([str(v.get("name", str(f).get_basename())), st, str(v.get("post_shader", "")), tw])

static func reload() -> void:
	_custom_loaded = false
	_load_custom()

static func _coerce(k: String, v):
	var b = BASE[k]
	if b is Color:
		if v is String:
			return Color(v)
		if v is Array and v.size() >= 3:
			return Color(float(v[0]), float(v[1]), float(v[2]))
		return b
	if b is bool:
		return bool(v)
	if b is int:
		return int(v)
	if b is String:
		return str(v)
	return float(v)

static func pack_names() -> Array:
	_load_custom()
	var out: Array = []
	for p in PACKS:
		out.append(p[0])
	for c in _custom:
		out.append(c[0])
	return out

static func _base_of(nm: String) -> Dictionary:
	for p in PACKS:
		if p[0] == nm:
			return BASE.merged(p[1], true)
	return BASE.duplicate()

## The pack's settings by index (built-in packs, then custom ones).
static func pack(i: int) -> Dictionary:
	_load_custom()
	if i >= 0 and i < PACKS.size():
		return BASE.merged(PACKS[i][1], true)
	var j := i - PACKS.size()
	if j >= 0 and j < _custom.size():
		var st: Dictionary = _custom[j][1].duplicate()
		st["post_shader"] = _custom[j][2]
		return st
	return BASE.duplicate()

static func pack_index(nm: String) -> int:
	return pack_names().find(nm)

## The effective look: the chosen pack (or the per-dungeon one), then the Performance preset, then every
## row the player set away from "Pack".
static func resolve(dg = null) -> Dictionary:
	var pi := int(Game.settings.get("vox_pack", 1))
	if int(Game.settings.get("vox_auto", 0)) == 1 and dg != null:
		var ap := auto_pack(dg)
		if ap != "":
			pi = maxi(0, pack_index(ap))
	var s := pack(pi)
	match int(Game.settings.get("vox_perf", 1)):
		0:
			s.res = minf(float(s.res), 0.6)
			s.shadows = 0
			s.fog = 0
			s.grass = minf(float(s.grass), 0.1)
			s.dof = 0
		2:
			s.res = maxf(float(s.res), 1.0) if float(s.res) >= 0.99 else float(s.res)
	var t := func(k: String) -> int: return int(Game.settings.get(k, 0))
	if t.call("vox_light") > 0: s.sun = [0.0, 0.6, 1.0, 1.35][t.call("vox_light")]
	if t.call("vox_warm") > 0: s.sun_col = [Color(), Color(0.85, 0.92, 1.0), Color(1, 1, 1), Color(1.0, 0.85, 0.65)][t.call("vox_warm")]
	if t.call("vox_shadow") > 0: s.shadows = t.call("vox_shadow") - 1
	if t.call("vox_sat") > 0: s.sat = [0.0, 0.6, 1.0, 1.3, 1.6][t.call("vox_sat")]
	if t.call("vox_contrast") > 0: s.contrast = [0.0, 0.85, 1.0, 1.2][t.call("vox_contrast")]
	if t.call("vox_bright") > 0: s.bright = [0.0, 0.8, 1.0, 1.2][t.call("vox_bright")]
	if t.call("vox_tint") > 0:
		var tc := [Color(), Color(1, 1, 1), Color(1.0, 0.8, 0.6), Color(0.65, 0.8, 1.0), Color(0.7, 1.0, 0.7), Color(0.85, 0.7, 1.0), Color(1.0, 0.85, 0.6)]
		s.tint = tc[t.call("vox_tint")]
		s.tint_amt = 0.0 if t.call("vox_tint") == 1 else 0.2
		s.mono = 2 if t.call("vox_tint") == 6 else (0 if int(s.mono) == 2 else int(s.mono))
	if t.call("vox_palette") > 0: s.palette = [0, 0, 32, 16, 8][t.call("vox_palette")]
	if t.call("vox_outline") > 0: s.outline = [0.0, 0.0, 0.15, 0.3][t.call("vox_outline")]
	if t.call("vox_ink") > 0: s.outline_all = t.call("vox_ink") == 2
	if t.call("vox_sway") > 0: s.sway = [0.0, 0.0, 0.3, 0.55, 0.9][t.call("vox_sway")]
	if t.call("vox_grass") > 0: s.grass = [0.0, 0.1, 0.22, 0.4][t.call("vox_grass")]
	if t.call("vox_water") > 0: s.water_alpha = [0.0, 0.5, 0.72, 0.92][t.call("vox_water")]
	if t.call("vox_waves") > 0: s.waves = [0.0, 0.4, 1.0, 1.8][t.call("vox_waves")]
	if t.call("vox_lava") > 0: s.lava = [0.0, 0.6, 1.0, 1.6][t.call("vox_lava")]
	if t.call("vox_torch") > 0: s.torch = [0.0, 1.8, 2.6, 3.6][t.call("vox_torch")]
	if t.call("vox_torchc") > 0: s.torch_col = [Color(), Color(1.0, 0.85, 0.6), Color(1, 1, 1), Color(0.7, 0.85, 1.0)][t.call("vox_torchc")]
	if t.call("vox_glow") > 0: s.glow = [0.0, 0.0, 0.3, 0.6, 1.1][t.call("vox_glow")]
	if t.call("vox_fog") > 0:
		s.fog = t.call("vox_fog") - 1
		s.fog_amt = 0.0 if s.fog == 0 else maxf(float(s.fog_amt), 0.3)
	if t.call("vox_ao") > 0: s.ao = 0.0 if t.call("vox_ao") == 1 else maxf(float(s.ao), 0.5)
	if t.call("vox_dof") > 0:
		s.dof = t.call("vox_dof") - 1
		s.dof_amt = 0.0 if s.dof == 0 else 1.0
	if t.call("vox_grain") > 0: s.grain = 0.0 if t.call("vox_grain") == 1 else 0.15
	if t.call("vox_vignette") > 0: s.vignette = 0.0 if t.call("vox_vignette") == 1 else 0.35
	if t.call("vox_scan") > 0: s.scan = 0.0 if t.call("vox_scan") == 1 else 0.25
	if t.call("vox_ca") > 0: s.ca = 0.0 if t.call("vox_ca") == 1 else 1.0
	if t.call("vox_weather") > 0: s.weather = t.call("vox_weather") - 1
	if t.call("vox_res") > 0: s.res = [1.0, 0.5, 0.75, 1.0][t.call("vox_res")]
	return s

## "Pack per dungeon: Auto": dark floors Cinematic, warm canyons and deserts Golden Hour, snow and clouds
## Soft, crystal caves Neon Night; anything else keeps the chosen pack.
static func auto_pack(dg) -> String:
	if dg == null or dg.fs == null:
		return ""
	if int(dg.fs.visibility) > 0:
		return "Cinematic"
	var mat := str(dg.get_meta("vox_material", ""))
	match mat:
		"crystal": return "Neon Night"
		"snow", "cloud": return "Soft"
		"desert": return "Golden Hour"
	return ""

## Saves the current pack and tweaks as a new pack in user://shaderpacks/.
static func save_custom() -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var n := 1
	while FileAccess.file_exists(USER_DIR + "my_pack_%d.json" % n):
		n += 1
	var st := resolve(null)
	var out := {}
	for k in st:
		var v = st[k]
		out[k] = v.to_html(false) if v is Color else v
	var nm := "My pack %d" % n
	var f := FileAccess.open(USER_DIR + "my_pack_%d.json" % n, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"name": nm, "base": "Classic", "settings": out}, "\t"))
	reload()
	return nm
