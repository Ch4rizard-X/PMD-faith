class_name PokemonNews
extends RefCounted
## Pokémon News (pokemon_mail.c sPokemonMail, pokemon_news1-3.c, code_80958E8.c sub_80961D8 / sub_80963B4):
## letters arrive in the base mailbox one a day; Store files one in the News List, Read shows it.
##   Game.flags.news_received: indices filed in the News List (PKMNNewsReceived)
##   Game.flags.news_mail:     indices of news letters waiting in the mailbox (mailType 1)

const MAILBOX_SLOTS := 4

static func news() -> Array:
	return RedText.data().get("_pokemon_news", [])

static func received() -> Array:
	if not Game.flags.get("news_received", null) is Array:
		Game.flags["news_received"] = []
	return Game.flags["news_received"]

static func letters() -> Array:
	if not Game.flags.get("news_mail", null) is Array:
		Game.flags["news_mail"] = [0]                 # sub_8096488: the welcome letter waits from the start
	return Game.flags["news_mail"]

static func headline(i: int) -> String:
	var n := news()
	return RedText.line(str(n[i][0])) if i >= 0 and i < n.size() else "?"

static func text_pages(i: int) -> Array:
	var n := news()
	return RedText.fmt(str(n[i][1])) if i >= 0 and i < n.size() else []

static func _has(i: int) -> bool:
	return i in received() or i in letters()

## sub_8096E2C: the next numbered letter (after the highest one in the mailbox), 0x38 = none.
static func next_index() -> int:
	var from := 0
	for i in letters():
		if int(i) < 0x32 and int(i) + 1 > from:
			from = int(i) + 1
	for i in range(from, 0x32):
		if not i in received():
			return i
	return 0x38

static func _quest(name: String) -> bool:
	if not Game.story.has("vars"):
		return true
	var cm: Dictionary = (GVars as Script).get_script_constant_map()
	return cm.has(name) and GVars.quest(int(cm[name]))

## Once a day (with the mailbox's job letters): the special letters first, then the numbered series.
static func refresh_if_new_day(job_letters: int) -> void:
	if int(Game.flags.get("news_day", -1)) == Game.day:
		return
	Game.flags["news_day"] = Game.day
	var mb := letters()
	if mb.size() + job_letters >= MAILBOX_SLOTS:
		return
	var pick := 0x38
	if Game.story.has("vars") and GVars.equal(GVars.var_id("SCENARIO_SUB7"), 0x31, 1) and not _has(0x35):
		pick = 0x35
	if _quest("QUEST_MAZE_15"):
		for i in [0x34, 0x33, 0x32]:
			if not _has(i):
				pick = i
	if Missions.rank_index(Game.rank_points) >= 6 and not _has(0x36):
		pick = 0x36
	if (Game.flags.get("postgame", false) or _quest("QUEST_REACHED_POSTGAME")) and Game.story.has("vars") and not _has(0x37):
		pick = 0x37
	if pick == 0x38:
		var n := next_index()
		if n < 0x32 and (n <= 2 or _quest("QUEST_MAZE_14")) and n != 0:
			pick = n
	if pick != 0x38 and not pick in mb:
		mb.append(pick)

## Store (mailbox.c case 6): the letter goes to the News List.
static func store(i: int) -> void:
	letters().erase(i)
	if not i in received():
		received().append(i)
		received().sort()
	Audio.sfx("307")

## Red's letter window (pokemon_news2.c): headline + body, Left/Right flips pages.
static func read(root: Control, i: int) -> void:
	var pages := text_pages(i)
	if pages.is_empty():
		pages = [""]
	var pg := TeamScreens.InfoPage.new()
	pg.width = 26 * 8 * UITheme.PX
	pg.count = pages.size()
	pg.builder = func(k): return {"title": UITheme.glyph("ICON_NEWS") + " " + headline(i), "parts": [str(pages[k])]}
	await TeamScreens.run_page(root, pg, Vector2(2, 2) * 8 * UITheme.PX)

## The News List (pokemon_news1.c): "News List" + page number, ICON_NEWS + headline rows.
static func news_list(root: Control) -> void:
	var start := 0
	while true:
		var rec := received()
		if rec.is_empty():
			return
		var rows: Array = []
		for i in rec:
			rows.append({"text": headline(int(i)), "icon": RedText.glyph_tex("ICON_NEWS")})
		var r := await BaseMenu.paged(root, "News List", rows, start, Vector2(2, 2) * 8 * UITheme.PX, 8, 24 * 8 * UITheme.PX)
		if r.act != "pick":
			return
		start = int(r.i)
		await read(root, int(rec[r.i]))
		if TeamScreens.auto_on():
			return
