class_name RedCredits
extends RefCounted
## Red's ending staff credits (credits1.c DrawCredits / sub_8035574, SPECIAL_TEXT_CREDITS_NAME): one page of
## gCreditsTable (data/red_credits.json, tools_story/gen_credits.py) printed in a frameless 26x16-tile window at
## tile (2,2) over the ending scene; the text fades in from Red's dark blue (0x18,0x18,0x38) in 30 frames, stays
## 'frames' frames, then fades out in 30 frames. Rows are [type, x, y, text]; y < 0 means "previous y + |y|".

const FADE := 30
const DARK := Color(0x18 / 255.0, 0x18 / 255.0, 0x38 / 255.0)
static var _pages: Array = []

static func pages() -> Array:
	if _pages.is_empty():
		var f := FileAccess.open("res://data/red_credits.json", FileAccess.READ)
		if f:
			_pages = JSON.parse_string(f.get_as_text())
	return _pages

static func _bracket(side: String) -> String:
	var p := "res://assets/ground/credits/bracket_%s.png" % side
	if not ResourceLoader.exists(p):
		return ""
	return "[img=%dx%d]%s[/img]" % [8 * UITheme.PX, 12 * UITheme.PX, p]

## Builds the page as a Control (for tests / screenshots too).
static func make_page(i: int) -> Control:
	var P := UITheme.PX
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.position = Vector2(2 * 8, 2 * 8) * P
	box.size = Vector2(26 * 8, 16 * 8) * P
	var all := pages()
	if i < 0 or i >= all.size():
		return box
	var y := 0
	for rec in all[i]:
		var ry := int(rec[2])
		y = ry if ry >= 0 else y - ry
		var s := str(rec[3])
		var center := s.contains("{CENTER_ALIGN}")
		s = s.replace("{CENTER_ALIGN}", "").replace("{BL}", _bracket("l")).replace("{BR}", _bracket("r"))
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_override("normal_font", UITheme.font())
		l.add_theme_font_size_override("normal_font_size", UITheme.FONT_SIZE)
		l.add_theme_color_override("default_color", Color8(231, 255, 231))      # fontpal row 7 (sub_8099690(2)), colour 7
		l.add_theme_constant_override("outline_size", 0)
		l.text = ("[center]%s[/center]" % s) if center else s
		l.position = Vector2(0 if center else int(rec[1]), y - 2) * P
		l.size = Vector2(26 * 8 * P - l.position.x, 16 * P)
		box.add_child(l)
	return box

## SPECIAL_TEXT_CREDITS_NAME (page, frames).
static func show(root: Control, page: int, frames: int) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	root.add_child(layer)
	var box := make_page(page)
	layer.add_child(box)
	var quick := Dialog.auto or ListMenu.auto
	var tree := root.get_tree()
	var dt := 1.0 / 60.0
	box.modulate = DARK
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate", Color.WHITE, (0.05 if quick else FADE * dt))
	await tw.finished
	if quick:
		await tree.create_timer(0.3).timeout
	else:
		await tree.create_timer(maxi(0, frames) * dt).timeout
	var tw2 := box.create_tween()
	tw2.tween_property(box, "modulate", Color(DARK.r, DARK.g, DARK.b, 0.0), (0.05 if quick else FADE * dt))
	await tw2.finished
	layer.queue_free()
