class_name DebugNpc
extends RefCounted
## Testing helper (Game Options -> Others -> Debug NPC, off by default): a Porygon at the team base whose menu
## shows the story flags and jumps around the story, in the spirit of Red's own debug station scripts.
##
##   Show flags    - SCENARIO_MAIN / SELECT / SUB1-9, base stage and style, post-game, money, team levels
##   Jump chapter  - SCENARIO_MAIN = (chapter, 0): the story dungeons before it are conquered / cleared, the team
##                   gets a fitting level, then the base reloads and EVENT_DIVIDE plays that chapter's opening
##   Side story    - runs Red's own EVENT_Sxx_START setup script for a side story, then reloads
##   Base          - stage (hut / construction / finished) and style (16 starters)
##   Team          - level, money, give an item

const SPECIES := "0137"            # Porygon
const DIR := 0
const SPOT := [30, 29, 0, 2]       # map tiles: in the base yard, left of the path to the door
const CHAPTERS := [
	[2, "Tiny Woods", ["tiny_woods"], 5],
	[3, "Thunderwave Cave", ["thunderwave_cave"], 6],
	[4, "Mt. Steel (Skarmory)", ["mt_steel"], 8],
	[5, "Sinister Woods (Team Meanies)", ["sinister_woods"], 11],
	[6, "Silent Chasm", ["silent_chasm"], 13],
	[7, "Mt. Thunder (Zapdos)", ["mt_thunder", "mt_thunder_peak"], 16],
	[8, "Great Canyon (Xatu)", ["great_canyon"], 19],
	[9, "Leaving town", [], 21],
	[10, "On the run", [], 22],
	[11, "Lapis Cave", ["lapis_cave"], 23],
	[12, "Mt. Blaze (Moltres)", ["mt_blaze", "mt_blaze_peak"], 25],
	[13, "Frosty Forest", ["frosty_forest", "frosty_grotto"], 28],
	[14, "Mt. Freeze (Articuno)", ["mt_freeze", "mt_freeze_peak"], 31],
	[15, "Magma Cavern (Groudon)", ["magma_cavern", "magma_cavern_pit"], 35],
	[16, "Sky Tower (Rayquaza)", ["sky_tower", "sky_tower_summit"], 40],
	[17, "The ending", [], 45],
	[18, "Post-game", [], 50],
]
const RESCUE_OF := {"tiny_woods": "TINY_WOODS", "thunderwave_cave": "THUNDERWAVE_CAVE", "mt_steel": "MT_STEEL",
	"sinister_woods": "SINISTER_WOODS", "silent_chasm": "SILENT_CHASM", "mt_thunder": "MT_THUNDER",
	"mt_thunder_peak": "MT_THUNDER_PEAK", "great_canyon": "GREAT_CANYON", "lapis_cave": "LAPIS_CAVE",
	"mt_blaze": "MT_BLAZE", "mt_blaze_peak": "MT_BLAZE_PEAK", "frosty_forest": "FROSTY_FOREST",
	"frosty_grotto": "FROSTY_GROTTO", "mt_freeze": "MT_FREEZE", "mt_freeze_peak": "MT_FREEZE_PEAK",
	"magma_cavern": "MAGMA_CAVERN", "magma_cavern_pit": "MAGMA_CAVERN_PIT", "sky_tower": "SKY_TOWER",
	"sky_tower_summit": "SKY_TOWER_SUMMIT"}
const SIDE := [
	["EVENT_S01E01A_START", "Mankey / Uproar Forest (SUB1)"],
	["EVENT_S01E02A_START", "Howling Forest (SUB1, part 2)"],
	["EVENT_S02E01A_START", "Stormy Sea (SUB2)"],
	["EVENT_S02E02A_START", "Stormy Sea, part 2 (SUB2)"],
	["EVENT_S03E01A_START", "Side story 3 (SUB3)"],
	["EVENT_S04E01A_START", "Side story 4 (SUB4)"],
	["EVENT_S05E01A_START", "Side story 5 (SUB5)"],
	["EVENT_S06E01A_START", "Side story 6 (SUB6)"],
	["EVENT_S07E01A_START", "Side story 7 (SUB7)"],
	["EVENT_S08E01A_START", "Side story 8 (SUB8)"],
	["EVENT_S09E01A_START", "Side story 9 (SUB9)"],
]
const BASE_STAGES := ["Hut", "Construction", "Finished"]

static func enabled() -> bool:
	return bool(Game.settings.get("qol_debugnpc", false))

# ------------------------------------------------------------------ menu
## Returns true when the ground has to reload (story changed).
static func open(G) -> bool:
	var root: Control = G.ui_root
	while true:
		var c := await Dialog.ask(root, "Debug: what do you want to do?", ["Show flags", "Jump to chapter", "Side story", "Base", "Team", "Exit"], SPECIES)
		match c:
			0:
				await Dialog.say(root, flags_text(), SPECIES)
			1:
				if await _jump_chapter(root):
					return true
			2:
				if await _side_story(root, G):
					return true
			3:
				if await _base(root):
					return true
			4:
				await _team(root)
			_:
				return false
	return false

static func flags_text() -> String:
	var s := GVars.scenario(GVars.SCENARIO_MAIN)
	var subs: Array = []
	for i in range(1, 10):
		var v := GVars.scenario(GVars.var_id("SCENARIO_SUB%d" % i))
		if v != Vector2i.ZERO:
			subs.append("S%d %d,%d" % [i, v.x, v.y])
	var sel := GVars.scenario(GVars.SCENARIO_SELECT)
	return "Main %d,%d  Select %d,%d\n%s\nBase: %s, style %d   Post-game: %s\nTeam Lv %s   %dP" % [
		s.x, s.y, sel.x, sel.y, "  ".join(subs) if not subs.is_empty() else "No side stories started",
		BASE_STAGES[clampi(GVars.get_val(null, GVars.BASE_LEVEL), 0, 2)], GVars.get_val(null, GVars.BASE_KIND),
		"yes" if GVars.quest(GVars.QUEST_REACHED_POSTGAME) else "no",
		"/".join(Game.team.map(func(e): return str(int(e.level)))), Game.money]

static func _warn(root: Control) -> bool:
	if bool(Game.settings.get("debug_warned", false)):
		return true
	var ok := await Dialog.ask(root, "Jumping around the story can leave odd flags.\nUse a save you don't mind losing. Continue?", ["Yes", "No"], SPECIES) == 0
	if ok:
		Game.settings["debug_warned"] = true
	return ok

static func _jump_chapter(root: Control) -> bool:
	var labels: Array = CHAPTERS.map(func(c): return "%d  %s" % [int(c[0]), str(c[1])])
	var lm := ListMenu.make("Jump to chapter", labels)
	root.add_child(lm)
	lm.position = Vector2(8, 8)
	var i := await lm.choose()
	if i < 0 or not await _warn(root):
		return false
	jump_to(int(CHAPTERS[i][0]))
	return true

## Story state for the start of chapter `main` (also used by tests).
static func jump_to(main: int) -> void:
	if main <= 17:
		# a clean main-story state: no side stories (Red starts them after chapter 15 / the post-game), no rescue
		# dungeons ordered or conquered (the chapter's opening orders its own; the earlier ones are set below)
		for i in range(1, 10):
			if main < 15 or i > 1:
				GVars.scenario_calc(GVars.var_id("SCENARIO_SUB%d" % i), 0, 0)
		for r in 64:
			GVars.set_arr(null, GVars.RESCUE_SCENARIO_ORDER_LIST, r, 0)
			GVars.set_arr(null, GVars.RESCUE_SCENARIO_JOB_LIST, r, 0)
			GVars.set_arr(null, GVars.RESCUE_SCENARIO_CONQUEST_LIST, r, 0)
	var lv := 5
	for c in CHAPTERS:
		if int(c[0]) < main:
			for k in c[2]:
				_conquer(str(k))
		if int(c[0]) <= main:
			lv = int(c[3])
	GVars.scenario_calc(GVars.SCENARIO_SELECT, 0, 0)
	GVars.scenario_calc(GVars.SCENARIO_MAIN, main, 0)
	if main <= 17:
		# the story's partner follows again (a post-game FORMATION_HERO sets both partner kinds to 0)
		GVars.set_val(null, GVars.PARTNER1_KIND, 2)
		GVars.set_val(null, GVars.PARTNER2_KIND, 0)
		# undo a post-game base rebuild that came before the Mankey quest (Red: Uproar Forest raises it)
		if GVars.before(GVars.SCENARIO_SUB1, 30, 0):
			GVars.set_val(null, GVars.BASE_LEVEL, 0)
	for e in Game.team:
		if int(e.level) < lv:
			e.level = lv
			e.exp = DB.exp_at(str(e.sp), lv)
	Game.save_game(true)

static func _conquer(k: String) -> void:
	if not k in Game.cleared:
		Game.cleared.append(k)
	if not k in Game.unlocked:
		Game.unlocked.append(k)
	var r := GData.rescue_id("RESCUE_DUNGEON_" + str(RESCUE_OF.get(k, k.to_upper())))
	if r >= 0:
		GVars.rescue_set_conquered(r, true)

static func _side_story(root: Control, G) -> bool:
	var lm := ListMenu.make("Start a side story", SIDE.map(func(x): return str(x[1])))
	root.add_child(lm)
	lm.position = Vector2(8, 8)
	var i := await lm.choose()
	if i < 0 or not await _warn(root):
		return false
	if not run_setup_script("s_script_" + str(SIDE[i][0])):
		await Dialog.say(root, "That script isn't in this build.", SPECIES)
		return false
	Game.save_game(true)
	return true

## Applies one of Red's EVENT_Sxx_START scripts (they only set flags: scenario, rescue order / conquest,
## Friend Areas, variables), skipping their "already past this point" check so the side story starts now.
static func run_setup_script(name: String) -> bool:
	var cmds = GData.scr[GData._name_idx[name]] if GData._name_idx.has(name) else null
	if cmds == null:
		return false
	for c in cmds:
		var op := int(c[0])
		var b := int(c[1])
		var sv := int(c[2])
		match op:
			0xA6:
				GVars.update_imm(null, sv, int(c[3]), b)
			0xA9:
				GVars.scenario_calc(sv, int(c[3]), int(c[4]))
			0xAD:
				Story.unlock_friend_area(GData.fa_of_map(sv))
			0xAE:
				GVars.rescue_set_order(sv, (b & 0xFF) > 0)
			0xAF:
				GVars.rescue_set_job(sv, (b & 0xFF) > 0)
			0xB0:
				GVars.rescue_set_conquered(sv, (b & 0xFF) > 0)
				Story.on_rescue_conquered(sv)
	return true

static func _base(root: Control) -> bool:
	var c := await Dialog.ask(root, "Base: change what?", ["Stage", "Style", "Back"], SPECIES)
	if c == 0:
		var s := await Dialog.ask(root, "Base stage:", BASE_STAGES, SPECIES)
		if s >= 0:
			GVars.set_val(null, GVars.BASE_LEVEL, s)
			return true
	elif c == 1:
		var names: Array = []
		var keys: Array = Story.BASE_KIND_OF.keys()
		for k in keys:
			names.append(str(DB.species.get(k, {}).get("name", k)))
		var lm := ListMenu.make("Base style", names)
		root.add_child(lm)
		lm.position = Vector2(8, 8)
		var i := await lm.choose()
		if i >= 0:
			GVars.set_val(null, GVars.BASE_KIND, int(Story.BASE_KIND_OF[keys[i]]))
			_style_override = int(Story.BASE_KIND_OF[keys[i]])
			return true
	return false

static var _style_override := -1    # a style picked here wins over the hero's for this session

static func style_override() -> int:
	return _style_override

static func _team(root: Control) -> void:
	var c := await Dialog.ask(root, "Team: change what?", ["Level +5", "Level 50", "Money +10000", "Give item", "Back"], SPECIES)
	match c:
		0, 1:
			for e in Game.team:
				var lv := mini(100, int(e.level) + 5) if c == 0 else maxi(int(e.level), 50)
				e.level = lv
				e.exp = DB.exp_at(str(e.sp), lv)
			await Dialog.say(root, "Team Lv %s" % "/".join(Game.team.map(func(e): return str(int(e.level)))), SPECIES)
		2:
			Game.money += 10000
			await Dialog.say(root, "%d Poké." % Game.money, SPECIES)
		3:
			var ids: Array = DB.items.keys().filter(func(k): return not str(DB.items[k].get("name", "")).begins_with("$"))
			ids.sort_custom(func(a, b): return DB.item_name(a) < DB.item_name(b))
			var labels: Array = ids.map(func(k): return DB.item_name(k))
			var r := await RedShops._multi_list(root, "Give item", labels, {}, 0, [], ids)
			if str(r.act) == "pick":
				var ks: Array = r.marks if not (r.marks as Array).is_empty() else [int(r.i)]
				for k in ks:
					var id: String = ids[int(k)]
					if not Game.bag_add(id, 9 if bool(DB.items[id].get("stack", false)) else 1):
						Game.storage[id] = int(Game.storage.get(id, 0)) + 1
				await Dialog.say(root, "Gave %d item(s)." % ks.size(), SPECIES)
	Game.save_game(true)
