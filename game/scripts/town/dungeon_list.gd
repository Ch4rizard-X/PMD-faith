class_name DungeonList
extends RefCounted
## Red's dungeon list at the crossroads (dungeon_list_menu.c PrintCurrentPage): a "Dungeons" window with the
## page number, 10 rows a page, and per row the GO icon (a story / side-story dungeon to go to:
## RESCUE_SCENARIO_JOB_LIST) or the envelope (jobs waiting in that dungeon). The remake's
## "Explorers of Sky dungeons" row (id -100) is kept at the end.

const P := UITheme.PX
const PER_PAGE := 10

## opts: labels, ids: rescue dungeon ids (or -100). Returns the picked index or -1.
static func pick(root: Control, opts: Array, ids: Array) -> int:
	if ListMenu.auto:
		var lm := ListMenu.make("Dungeons", opts)
		root.add_child(lm)
		lm.position = Vector2(8, 8)
		return await lm.choose()
	var desert := GData.rescue_id("RESCUE_DUNGEON_DESERT_REGION")
	var rows: Array = []
	for k in opts.size():
		var r := int(ids[k])
		var row := {"text": str(opts[k]), "icon": _col_icon("")}
		if r >= 0:
			var go := (desert < 0 or r < desert) and GVars.rescue_job(r)
			if go:
				row.icon = _col_icon("ICON_GO")
			elif _jobs_in(r) > 0:
				row.icon = _col_icon("ENVELOPE_OPEN")
		rows.append(row)
	# PrintCurrentPage: "Dungeons" and the page number (always shown, white) in the header; Left / Right page
	var pages := maxi(1, ceili(rows.size() / float(PER_PAGE)))
	var page := 0
	var sel := 0
	while true:
		var part := rows.slice(page * PER_PAGE, mini(rows.size(), (page + 1) * PER_PAGE))
		var m := TeamScreens.menu("Dungeons  [color=#ffffff]%d[/color]" % (page + 1), part, 16 * 8 * P)
		m.lr = pages > 1
		m.max_rows = PER_PAGE
		m.line_h = 10 * P
		m.sel = mini(sel, part.size() - 1)
		var r2 := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 4 * P))
		match str(r2.act):
			"left":
				page = (page - 1 + pages) % pages
				sel = 0
			"right":
				page = (page + 1) % pages
				sel = 0
			"pick":
				return page * PER_PAGE + int(r2.i)
			_:
				return -1
	return -1

## Red prints the icon at x 10 and the name at x 24: a fixed 14 px icon column.
static var _cols := {}

static func _col_icon(glyph: String) -> Texture2D:
	if _cols.has(glyph):
		return _cols[glyph]
	var im := Image.create(14 * P, 12 * P, false, Image.FORMAT_RGBA8)
	var g: Texture2D = RedText.glyph_tex(glyph) if glyph != "" else null
	if g != null:
		var gi := g.get_image()
		gi.convert(Image.FORMAT_RGBA8)
		im.blit_rect(gi, Rect2i(Vector2i.ZERO, Vector2i(mini(gi.get_width(), im.get_width()), mini(gi.get_height(), im.get_height()))), Vector2i.ZERO)
	var t := ImageTexture.create_from_image(im)
	_cols[glyph] = t
	return t

## CountJobsinDungeon: accepted jobs (Job List) in that dungeon.
static func _jobs_in(r: int) -> int:
	var sd := GData.rescue_to_script(r)
	if sd < 0:
		return 0
	var key := DB.dungeon_key(int(GData.dungeon_info(sd).dungeon))
	var n := 0
	for j in Game.jobs:
		if str(j.get("dungeon", "")) == key and not str(j.get("state", "")) in ["done", "done_pending"]:
			n += 1
	return n
