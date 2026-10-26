class_name RedMap
extends Control
## Red's dungeon map (dungeon_map.c DrawMinimapTile): every floor tile is a 4x4 cell from the 'zmappat'
## graphics, laid over the dungeon from screen (8, 8) for map rows 2..30 (Red skips rows 0, 1 and 31).
## The Map option (Game.settings.map_mode: 0 Off / 1 Clear / 2 Shade) picks the style: Clear uses the
## see-through cells (+64), Shade the shaded ones. Off hides the overlay. Select opens the floor map
## (inFloorMapMode): the dungeon layers are switched off (black), the leader gets its own icon and the
## map shows even with the option Off (GameOptions_SetTransparentMiniMap).

const GFX_NOTHING := 0
const GFX_BLANK := 1
const GFX_ENEMY := 2
const GFX_ITEM := 3
const GFX_TRAP := 4
const GFX_SPECIAL_STAIRS := 5
const GFX_STAIRS := 6
const GFX_WONDER_TILE := 7
const GFX_PLAYER := 8
const GFX_ALLY := 10
const GFX_GREEN_DOT := 11
const VISITED := 0x10
const REVEALED := 0x20

var dg                                  # Dungeon
var full := false                       # floor map mode (Select)
var show_mons := true                   # gShowMonsterDotsInDungeonMap
var _atlas: Image
var _img: Image
var _tex: ImageTexture
var _frames := 0
var _acc := 0.0
var _leader_cell := Vector2i(100, 100)  # gPlayerDotMapPosition
var _dirty := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var t := DungeonGfx.tex("zmappat.png")
	if t:
		_atlas = t.get_image()
		if _atlas.is_compressed():
			_atlas.decompress()
		_atlas.convert(Image.FORMAT_RGBA8)
	_img = Image.create(224, 116, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)

## 0 Off, 1 Clear, 2 Shade (accepts the option's name too).
static func map_mode() -> int:
	var v = Game.settings.get("map_mode", 1)
	if v is String:
		return {"off": 0, "clear": 1, "shade": 2}.get(String(v).to_lower(), 1)
	return clampi(int(v), 0, 2)

func refresh() -> void:
	var t0 := Time.get_ticks_usec()
	refresh_i()
	if Dungeon.perf_log:
		Dungeon.pacc("redmap", Time.get_ticks_usec() - t0)

func refresh_i() -> void:
	_dirty = true
	queue_redraw()

## Screen layout: Red's map origin (8, 8) at UI scale; row 2 of the floor is the first map row.
func origin() -> Vector2:
	return Vector2(8, 8) * UITheme.PX

func tile_at(sp: Vector2) -> Vector2i:
	var t: Vector2 = (sp - origin()) / (4.0 * UITheme.PX)
	return Vector2i(floori(t.x), floori(t.y) + 2)

func _process(dt: float) -> void:
	if dg == null:
		return
	var want := _wanted()
	if visible != want:
		visible = want
		_dirty = true
	if not visible:
		return
	_acc += dt * 60.0
	var n := int(_acc)
	_acc -= float(n)
	var before := (_frames & 8) == 0
	_frames += n
	if ((_frames & 8) == 0) != before:
		queue_redraw()

func _wanted() -> bool:
	if dg.fs == null or dg.result_sent or dg.get_meta("hide_map", false):
		return false
	if full:
		return true
	if map_mode() == 0:
		return false
	if dg.menu_open or not TeamScreens._stack.is_empty():
		return false
	return true

func _is_floor(x: int, y: int) -> bool:
	return dg.fs.terrain_at(Vector2i(x, y)) == 1

func _mon_visible(m: Mon) -> bool:
	if m.hp <= 0:
		return false
	if m.is_team():
		return true
	if dg.fs.get_meta("radar", false) or HeldItems.xray(dg.fs):      # Radar Orb / X-Ray Specs
		return true
	for t in dg.fs.team():
		if dg.fs.can_see(t, m.pos):
			return true
	return false

func _rebuild() -> void:
	_dirty = false
	_img.fill(Color(0, 0, 0, 0))
	if _atlas == null or dg.fs == null:
		_tex.update(_img)
		return
	var fs: FloorState = dg.fs
	var transparent := map_mode() != 2
	var blinded: bool = fs.leader != null and fs.leader.has_status("blinker")
	var monat := {}
	if show_mons and not blinded:
		for m in fs.mons:
			if _mon_visible(m):
				monat[m.pos] = m
	_leader_cell = Vector2i(100, 100)
	for y in range(2, mini(fs.h, 31)):
		for x in fs.w:
			var p := Vector2i(x, y)
			var i := fs.idx(p)
			var known: bool = fs.explored[i] != 0
			var t := GFX_NOTHING
			var look := true
			if monat.has(p):
				var m: Mon = monat[p]
				if not m.is_team():
					t = GFX_ENEMY if m.side != "client" else GFX_ALLY
				elif m == fs.leader:
					_leader_cell = p
					if full:
						t = GFX_PLAYER
				else:
					t = GFX_ALLY
				look = false
			if look and not blinded and not known and fs.items.has(p) and (fs.get_meta("scanner", false) or HeldItems.xray(fs)):
				t = GFX_ITEM          # Scanner Orb / X-Ray Specs: every item shows
				look = false
			if look and not blinded and known:
				if fs.traps.has(p) and fs.traps[p].get("seen", false):
					t = GFX_WONDER_TILE if str(fs.traps[p].id) == "wonder" else GFX_TRAP
					look = false
				elif fs.items.has(p) and fs.terrain[i] != 0:
					t = GFX_ITEM
					look = false
				elif p == fs.stairs:
					t = GFX_STAIRS
					look = false
			if t == GFX_NOTHING:
				if not known or not _is_floor(x, y):
					t = GFX_BLANK
				else:
					var line := 0xF
					if y < fs.h - 1 and _is_floor(x, y + 1):
						line &= ~0x1
					if y >= 1 and _is_floor(x, y - 1):
						line &= ~0x4
					if x < fs.w - 1 and _is_floor(x + 1, y):
						line &= ~0x2
					if x >= 1 and _is_floor(x - 1, y):
						line &= ~0x8
					t = line + (VISITED if fs.explored[i] == 1 else REVEALED)
			if transparent:
				t += 64
			_img.blend_rect(_atlas, Rect2i((t % 16) * 4, (t / 16) * 4, 4, 4), Vector2i(x * 4, (y - 2) * 4))
	_tex.update(_img)

func _draw() -> void:
	if dg == null or dg.fs == null:
		return
	if _dirty:
		_rebuild()
	var s := float(UITheme.PX)
	if full:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color.BLACK)
	var o := origin()
	draw_texture_rect(_tex, Rect2(o, Vector2(224, 116) * s), false)
	# FlashLeaderIcon: outside the floor map mode the leader blinks (8 frames on, 8 off)
	if not full and _leader_cell.x < 100 and (_frames & 8) == 0 and _atlas:
		var t := GFX_PLAYER + (64 if map_mode() != 2 else 0)
		var at := o + Vector2(_leader_cell.x * 4, (_leader_cell.y - 2) * 4) * s
		draw_texture_rect_region(_tex_atlas(), Rect2(at, Vector2(4, 4) * s), Rect2((t % 16) * 4, (t / 16) * 4, 4, 4))

var _atlas_tex: Texture2D
func _tex_atlas() -> Texture2D:
	if _atlas_tex == null:
		_atlas_tex = DungeonGfx.tex("zmappat.png")
	return _atlas_tex
