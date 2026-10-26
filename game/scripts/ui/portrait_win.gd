class_name PortraitWin
extends PanelContainer
## A Red portrait window (DisplayMonPortraitSpriteFlipped into a 5x5-tile window, e.g. the personality test's
## starter reveal at tile (12,6) and the partner list's portrait at (14,4)): the 40x40 face in a window frame.

var face: TextureRect

static func make(sp: String, emotion := "Normal", flip := true) -> PortraitWin:
	var w := PortraitWin.new()
	var sb := UITheme.box()
	sb.content_margin_left = 4 * UITheme.PX
	sb.content_margin_right = 4 * UITheme.PX
	sb.content_margin_top = 4 * UITheme.PX
	sb.content_margin_bottom = 4 * UITheme.PX
	w.add_theme_stylebox_override("panel", sb)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.face = TextureRect.new()
	w.face.custom_minimum_size = Vector2(40, 40) * UITheme.PX
	w.face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	w.face.stretch_mode = TextureRect.STRETCH_SCALE
	w.face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	w.face.flip_h = flip
	w.add_child(w.face)
	w.set_species(sp, emotion)
	return w

func set_species(sp: String, emotion := "Normal") -> void:
	face.texture = Dialog.portrait_tex(sp, emotion)

## Place the window so its 5x5-tile inside starts at Red tile (tx, ty) (the frame is drawn around it, as in Red).
func at_tile(tx: int, ty: int) -> void:
	position = Vector2(tx * 8 - 4, ty * 8 - 4) * UITheme.PX

## Red's screen is 160 px tall, ours 135 (GBA px): keep the window clear of the bottom text box.
func keep_above_textbox(root: Control) -> void:
	var top := root.get_viewport_rect().size.y - (3 * UITheme.LINE + 10 * UITheme.PX) - 2 * UITheme.PX
	var h := 48 * UITheme.PX
	if position.y + h > top - 2 * UITheme.PX:
		position.y = maxf(2 * UITheme.PX, top - h - 2 * UITheme.PX)
