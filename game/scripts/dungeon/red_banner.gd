class_name RedBanner
extends RefCounted
## Red's floor-start banner (dungeon_name_banner.c ShowDungeonNameBanner_Async + dungeon_vram.c sub_803E748):
## the dungeon name and "B3F" / "3F" in the big banner font 'banfont' (24x24 glyphs, palette 'banrpal'),
## centred in a 28x8-tile area at tile row 4 of a black screen. Then over 44 frames the banner fades to
## black (2 brightness steps per frame) while the dungeon fades in from frame 12 on.

const W := 224
const H := 64

## Banner text width (CalcStringWidth): '#' is 8 px, ' ' is 12 px, glyphs their own width.
static func text_width(s: String) -> int:
	var g: Dictionary = DungeonGfx.data().get("banner", {}).get("glyphs", {})
	var w := 0
	for ch in s:
		if ch == "#":
			w += 8
		elif ch == " ":
			w += 12
		else:
			w += int(_glyph(g, ch)[1])
	return w

static func _glyph(g: Dictionary, ch: String) -> Array:
	var code := ch.unicode_at(0)
	if g.has(str(code)):
		return g[str(code)]
	return g.get("43", [1, 11])          # sub_803DEC8: an unknown character gives entry 1 ('+')

## Renders the two banner lines into a 224x64 image (GBA pixels).
static func render(name: String, floor_txt: String) -> Image:
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var tx := DungeonGfx.tex("banfont.png")
	if tx == null:
		return out
	var font := tx.get_image()
	if font.is_compressed():
		font.decompress()
	font.convert(Image.FORMAT_RGBA8)
	var bd: Dictionary = DungeonGfx.data().get("banner", {})
	var g: Dictionary = bd.get("glyphs", {})
	var cols := int(bd.get("cols", 16))
	var lines := [[name, 0], [floor_txt, 32]]
	for ln in lines:
		var s: String = ln[0]
		var x := (W - text_width(s)) / 2
		var y: int = ln[1]
		for ch in s:
			if ch == "#":
				x += 8
				continue
			if ch == " ":
				x += 12
				continue
			var e := _glyph(g, ch)
			var i := int(e[0])
			out.blend_rect(font, Rect2i((i % cols) * 24, (i / cols) * 24, 24, 24), Vector2i(x, y))
			x += int(e[1])
	return out

## "B5F" for dungeons that go down, "#5F" (an 8 px gap, then 5F) for ones that go up.
static func floor_text(up: bool, floor_no: int) -> String:
	return ("#" if up else "B") + str(floor_no) + "F"

## Shows the banner over the dungeon (UI scale 2) and plays Red's cross-fade. Awaitable.
static func play(host: Node, name: String, up: bool, floor_no: int, hold := 1.0) -> void:
	var cl := CanvasLayer.new()
	cl.layer = 20
	host.add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(bg)
	var img := render(name, floor_text(up, floor_no))
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	var px := float(UITheme.PX)
	var vs := host.get_viewport().get_visible_rect().size
	tr.size = Vector2(W, H) * px
	tr.position = ((vs - tr.size) / 2.0).floor()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(tr)
	var tree := host.get_tree()
	if hold > 0.0:
		await tree.create_timer(hold).timeout
	# Red steps once per frame (60 Hz); go by elapsed time so slow frame rates don't stretch the fade
	var t0 := Time.get_ticks_msec()
	var i := 0
	while i < 0x2C:
		if not is_instance_valid(tr) or not is_instance_valid(bg):
			break
		i = mini(0x2C, int((Time.get_ticks_msec() - t0) * 60 / 1000))
		var banner := maxi(0, 31 - 2 * mini(i, 0x20))
		var bright := clampi(i - 0xB, 0, 0x1F)
		tr.modulate = Color(banner / 31.0, banner / 31.0, banner / 31.0, 1.0)
		bg.color = Color(0, 0, 0, 1.0 - bright / 31.0)
		await tree.process_frame
	if is_instance_valid(cl):
		cl.queue_free()
