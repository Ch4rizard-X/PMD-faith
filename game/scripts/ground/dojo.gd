class_name Dojo
extends RefCounted
## Red's Makuhita Dojo (makuhita_dojo1.c / makuhita_dojo2.c, training_maze.c, locale/makuhita_dojo_usa.h):
## SPECIAL_TEXT_DOJO_ENTER (main menu: Go Train / Info / Cancel, then the "Courses" list), DOJO_SUCCESS /
## FAILURE / ALL_CLEARED (Makuhita's result talk; all cleared gives the Bonsly Doll and a Ginseng).
## The training mazes are script dungeons 55..77 = Red dungeons 75..97, which all use DUNGEON_NORMAL_MAZE's
## floor data three floors each (GeneralizeMazeDungeonLoc). They are added to DB.dungeons at run time as
## "maze_NN" keys (ensure_mazes) so the dungeon code can run them like any other dungeon.

const MAKUHITA := "0296"
const N_MAZES := 23                  # NUM_DUNGEON_MAZE
const N_BASIC := 17                  # NUM_BASIC_DUNGEON_MAZE (Normal .. Steel)
const FIRST_SCRIPT := 55             # sub_80A26CC: script dungeon = 55 + maze index
const NAMES := ["Normal Maze", "Fire Maze", "Water Maze", "Grass Maze", "Electric Maze", "Ice Maze", "Fighting Maze",
	"Ground Maze", "Flying Maze", "Psychic Maze", "Poison Maze", "Bug Maze", "Rock Maze", "Ghost Maze", "Dragon Maze",
	"Dark Maze", "Steel Maze", "Team Shifty", "Team Constrictor", "Team Hydro", "Team Rumblerock", "Rescue Team 2",
	"Rescue Team Maze"]

# gCommonMakuhita[awake / asleep][MAKUHITA_DLG_0..9]
const DLG := [[
	" This is the Makuhita Dojo!{WAIT_PRESS}\nThrough rigorous training, one begets\ntrue power.",
	" What else do you seek?",
	" Fine, farewell.\nReturn if you seek more training.",
	" Where do you wish to train?",
	" The {POKEMON_0}?{WAIT_PRESS}\nYour decision stands!{WAIT_PRESS}\nLet the training begin!",
	" Aiyah...{WAIT_PRESS}\nYou failed to reach the end...{WAIT_PRESS}\nMore training is what you need.{EXTRA_MSG} But effort is never wasted!{EXTRA_MSG} Learn from this and move\nforward!",
	" Ah...\nYou have succeeded in your training!{EXTRA_MSG} You've shown your worth!{WAIT_PRESS}\nWithout a doubt, you have grown more\npowerful from your training!{EXTRA_MSG} May this success drive\nyou to train even harder!",
	" Ah...\nYou have succeeded in your training!{EXTRA_MSG} You've shown your worth!{WAIT_PRESS}\nWithout a doubt, you have grown more\npowerful from your training!{WAIT_PRESS} Wait...{WAIT_PRESS} ...{EXTRA_MSG} Wuh?{WAIT_PRESS}\nWhat, what, what?!{EXTRA_MSG} Did you maybe...{WAIT_PRESS}\nConquer all the training courses?{EXTRA_MSG} That's...{WAIT_PRESS} Amazing! You!{WAIT_PRESS}\nCongratulations!{EXTRA_MSG} I promised!{WAIT_PRESS}\nI promised you a reward for completing\nthe training courses!{EXTRA_MSG} So... Here it is!{WAIT_PRESS}\nMy {COLOR GREEN}Bonsly Doll{RESET}!{EXTRA_MSG} Isn't it smashing? Hey?!",
	" Don't let up on your training!\nKeep bettering yourself!{EXTRA_MSG} May you never lose your\ndrive!",
	" This dojo was founded to\nsupport the efforts of rescue teams.{EXTRA_MSG} Train in different rooms to\nlevel up...{WAIT_PRESS}\nAnd toughen up your rescue team.{EXTRA_MSG} Also...{WAIT_PRESS}\nIn the {COLOR YELLOW}Fire Maze{RESET} you will find only\nFire-type Pokémon.{EXTRA_MSG} In the {COLOR YELLOW}Water Maze{RESET} there\nwill only be Water-type Pokémon.{EXTRA_MSG} In such ways, only one type\nof Pokémon will be in a given room.\nStudy how types match up in battle.{EXTRA_MSG} The Pokémon in this dojo,\nby the way, are all volunteers.{EXTRA_MSG} They are participating\nbecause they want to see rescue teams\nsucceed.{EXTRA_MSG} The only thanks they expect\nis to see you become stronger.\nDon't let them down!{EXTRA_MSG} There's more.{WAIT_PRESS}\nFor a rescue team that successfully\ncompletes all training courses...{EXTRA_MSG} I have a special reward!{EXTRA_MSG} Let that compel you to train\nharder!",
], [
	" Zzznarr... Zzznarr...\nMakuhita... Dojo...",
	" Zzznarr... Urr?\nWhat else?",
	" Urr... Narr...\nSee you...",
	" Zzznarr... Zzz...\nTrain where?",
	" Zzz... Narr...\n{POKEMON_0}? 'K, go...",
	" Aiyah... Zzznarr...\nDidn't finish...{EXTRA_MSG} Zzz... Urr?\nNo giving up...",
	" Ah... Zzznarr...\nCleared it...{EXTRA_MSG} Congrazzz...\nKeep going... Zzz...",
	" Ah... Zzznarr...\nCleared it...{EXTRA_MSG} Zzzznarr... Urr...\nGood going... Keep going...{WAIT_PRESS}\nHunh...{WAIT_PRESS} ...{EXTRA_MSG} Gwoh?{WAIT_PRESS}\nGwogwogwoh?{EXTRA_MSG} Mugawah?\nCleared everything?{EXTRA_MSG} Zzznarr!\nCongrazzz...{EXTRA_MSG} Zzznarr... Zzznarr...\nYour reward...\nPromised...{EXTRA_MSG} Zzz... Urr!\n{COLOR GREEN}Bonsly Doll{RESET}...",
	" Zzznarr... Zzz...!\nKeep working...",
	" Zzznarr... Zzz...\nThis dojo...\nHelp rescue teams...{EXTRA_MSG} Zzznarr... Urr...\nTrain in different rooms to level up...{EXTRA_MSG} Zzznarr... Urr!\nMake stronger rescue team...{EXTRA_MSG} Urr... Zzznarr!\nDon't let up!",
]]
const S_BONSLY := "{CENTER_ALIGN}{COLOR YELLOW}{POKEMON_0}{RESET} received the {COLOR GREEN}Bonsly Doll{RESET}!\n{CENTER_ALIGN}It has been placed outside your\n{CENTER_ALIGN}rescue team base."

static var test_pick := -1            # tests: maze index to pick in auto mode (-1 = cancel)

# ------------------------------------------------------------------ mazes
static func is_maze_script(sd: int) -> bool:
	return sd >= FIRST_SCRIPT and sd < FIRST_SCRIPT + N_MAZES

static func maze_key(i: int) -> String:
	ensure_mazes()
	return "maze_%02d" % i

static func is_maze_key(k: String) -> bool:
	return k.begins_with("maze_")

## Adds the 23 training mazes to DB.dungeons (floors 3i..3i+2 of the Normal Maze, Red's dungeon_data
## entries 75..97: party 3, no recruiting, money kept).
static func ensure_mazes() -> void:
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	if dd.has("maze_00") or not dd.has("dojo_registration"):
		return
	var src: Dictionary = dd.dojo_registration
	var fl: Array = src.get("floors", [])
	for i in N_MAZES:
		var floors: Array = []
		for f in range(3 * i, mini(3 * i + 3, fl.size())):
			floors.append(fl[f])
		dd["maze_%02d" % i] = {"dir": "NormalMaze", "name": NAMES[i], "index": 75 + i, "floors": floors, "up": false,
			"recruit": false, "max_items": 20, "party": 3, "turn_limit": 1000, "maze": true}

## sub_8097504: which mazes Makuhita offers.
static func maze_open(i: int) -> bool:
	if i < 17:
		match i:
			2, 10, 11, 12:
				return GVars.quest(GVars.QUEST_MAZE_14)
			0, 1, 5, 7, 9, 14:
				return GVars.quest(GVars.QUEST_MAZE_15)
			13:
				return GVars.quest(GVars.QUEST_REACHED_POSTGAME)
		return true
	if i >= 21:
		return false
	return GVars.quest(GVars.QUEST_REACHED_POSTGAME)

## IsMazeCompleted
static func maze_done(i: int) -> bool:
	return GVars.get_arr(null, GVars.TRAINING_CONQUEST_LIST, i) != 0

## special func 0xD (sub_8097640): all basic courses cleared for the first time.
static func all_cleared_once() -> int:
	if GVars.get_arr(null, GVars.TRAINING_CONQUEST_LIST, 0x1F) != 0:
		return 0
	for i in N_BASIC:
		if not maze_done(i):
			return 0
	GVars.set_arr(null, GVars.TRAINING_CONQUEST_LIST, 0x1F, 1)
	return 1

## special func 0xE: the first not yet rewarded team maze (17..22) -> index - 16, else 0.
static func team_maze_present() -> int:
	for i in range(0x11, N_MAZES):
		if maze_done(i) and GVars.get_arr(null, GVars.TRAINING_PRESENT_LIST, i) == 0:
			GVars.set_arr(null, GVars.TRAINING_PRESENT_LIST, i, 1)
			return i - 0x10
	return 0

# ------------------------------------------------------------------ screens
static func _asleep() -> int:
	return 1 if GVars.quest(GVars.QUEST_SQUARE_ASLEEP) else 0

static func _say(root: Control, d: int, mons := []) -> void:
	var asleep := _asleep()
	await RedMsg.say(root, DLG[asleep][d], "" if asleep else MAKUHITA, "Normal", [], mons)

static func _menu(root: Control, d: int) -> int:
	var asleep := _asleep()
	return await RedMsg.ask(root, DLG[asleep][d], ["Go Train", "Info", "Cancel"], "" if asleep else MAKUHITA)

## SPECIAL_TEXT_DOJO_ENTER: returns the chosen maze's script dungeon id, or -1.
static func enter(root: Control) -> int:
	var d := 0
	while true:
		var c := await _menu(root, d)
		d = 1
		match c:
			0:
				await _say(root, 3)
				var i := await courses(root)
				if i < 0:
					continue
				await _say(root, 4, ["[color=#ffdc4a]%s[/color]" % NAMES[i]])
				return FIRST_SCRIPT + i
			1:
				await _say(root, 9)
			_:
				await _say(root, 2)
				return -1
	return -1

## The "Courses" window (makuhita_dojo2.c MakuhitaDojo_DrawCourseList): page number in the header,
## completed courses green with a star bullet. Returns the maze index or -1.
static func courses(root: Control) -> int:
	var list: Array = []
	for i in N_MAZES:
		if maze_open(i):
			list.append(i)
	if list.is_empty():
		return -1
	if Dialog.auto or ListMenu.auto:
		print("  DOJO courses ", list.map(func(i): return NAMES[i]))
		return test_pick if test_pick in list else -1
	var P := UITheme.PX
	const PER_PAGE := 8
	var pages := maxi(1, ceili(list.size() / float(PER_PAGE)))
	var page := 0
	var sel := 0
	while true:
		var rows: Array = []
		for i in list.slice(page * PER_PAGE, mini(list.size(), (page + 1) * PER_PAGE)):
			var done := maze_done(i)
			var row := {"text": NAMES[i], "icon": DungeonList._col_icon("STAR_BULLET" if done else "")}
			if done:
				row["color"] = Color("7fff7f")
			rows.append(row)
		var m := TeamScreens.menu("Courses  [color=#ffffff]%d[/color]" % (page + 1), rows, 14 * 8 * P)
		m.lr = pages > 1
		m.max_rows = PER_PAGE
		m.sel = mini(sel, rows.size() - 1)
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		match str(r.act):
			"left":
				page = (page - 1 + pages) % pages
				sel = 0
			"right":
				page = (page + 1) % pages
				sel = 0
			"pick":
				return int(list[page * PER_PAGE + int(r.i)])
			_:
				return -1
	return -1

## SPECIAL_TEXT_DOJO_SUCCESS / FAILURE / ALL_CLEARED (MakuhitaDojo_New modes 1..3 / 5..7).
static func result(root: Control, kind: String) -> void:
	match kind:
		"success":
			await _say(root, 6)
		"failure":
			await _say(root, 5)
		"all":
			await _say(root, 7)
			var nm := str(Story.name_of_kind(3))
			Audio.sfx("203")
			await RedMsg.say(root, S_BONSLY, "", "Normal", [], [nm])
			await RedReward.receive(root, 1, "ginseng", 1)       # sub_801B60C(1, ITEM_GINSENG, 1)
			await _say(root, 8)
