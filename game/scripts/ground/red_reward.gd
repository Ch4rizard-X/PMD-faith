class_name RedReward
extends RefCounted
## Red's "received item" flow with a full Toolbox (code_801B60C.c sub_801B60C, SPECIAL_TEXT_UNK_2C) and the
## Toolbox picker used by the story scripts (SPECIAL_TEXT_TOOL_BOX: feeding Munchlax, edible items only).

const S_PROMISED := "{CENTER_ALIGN}{COLOR YELLOW}{POKEMON_0}{RESET} received\n{CENTER_ALIGN}the promised {COLOR GREEN}{MOVE_ITEM_0}{RESET}. "
const S_TEAM_PROMISED := "{CENTER_ALIGN}{COLOR YELLOW}{POKEMON_0}{RESET}'s team received\n{CENTER_ALIGN}the promised {COLOR GREEN}{MOVE_ITEM_0}{RESET}."
const S_ALSO := "{CENTER_ALIGN}The team also received\n{CENTER_ALIGN}the item {COLOR GREEN}{MOVE_ITEM_0}{RESET}."
const S_STATUE := "{CENTER_ALIGN}Received the {COLOR GREEN}{MOVE_ITEM_0}{RESET}!{EXTRA_MSG}{CENTER_ALIGN}A very rare statue. It has been placed\n{CENTER_ALIGN}outside your rescue team base."
const S_1000 := "{CENTER_ALIGN}The {COLOR GREEN}{MOVE_ITEM_0}{RESET}...\n{CENTER_ALIGN}You've already acquired it.{EXTRA_MSG}{CENTER_ALIGN}Sorry to see that...{EXTRA_MSG}{CENTER_ALIGN}In its place, {COLOR YELLOW}{POKEMON_0}{RESET},\n{CENTER_ALIGN}you can have {COLOR CYAN}1,000{RESET} {POKE}."
const S_TO_STORAGE := "{CENTER_ALIGN}Your Toolbox is full.\n{CENTER_ALIGN}The item was sent to storage."
const S_FULL := "{CENTER_ALIGN}Your Toolbox is full.\n{CENTER_ALIGN}What would you like to do?"
const S_CONFIRM := "{CENTER_ALIGN}Is it OK to throw away\n{CENTER_ALIGN}this {COLOR GREEN}{MOVE_ITEM_0}{RESET}?"
const S_THROWN := "{CENTER_ALIGN}The {COLOR GREEN}{MOVE_ITEM_0}{RESET}\n{CENTER_ALIGN}was thrown away."
const S_STORED_FOR := "{CENTER_ALIGN}The {COLOR GREEN}{MOVE_ITEM_1}{RESET} was put in\n{CENTER_ALIGN}storage to get the {COLOR GREEN}{MOVE_ITEM_0}{RESET}."
const S_DISCARD_FOR := "{CENTER_ALIGN}The {COLOR GREEN}{MOVE_ITEM_1}{RESET} was discarded\n{CENTER_ALIGN}to get the {COLOR GREEN}{MOVE_ITEM_0}{RESET}."

static var test_choice := 1            # tests (auto mode): 0 trash a Toolbox item (Storage), 1 trash the received item

static func _it(s: String, item0: String, item1 := "") -> String:
	return s.replace("{MOVE_ITEM_0}", item0).replace("{MOVE_ITEM_1}", item1)

static func _say(root: Control, s: String, item0: String, item1 := "") -> void:
	await RedMsg.say(root, _it(s, item0, item1), "", "Normal", [], [str(Story.name_of_kind(3))])

static func _ask(root: Control, s: String, opts: Array, item0: String) -> int:
	return await RedMsg.ask(root, _it(s, item0), opts, "", "Normal", true, [], [str(Story.name_of_kind(3))])

## sub_801B60C(mode, item, qty): mode 1 = "The team also received", else "received the promised".
static func receive(root: Control, mode: int, key: String, qty := 1) -> void:
	if not DB.items.has(key):
		return
	var nm := DB.item_name(key)
	var stack: bool = DB.items[key].get("stack", false)
	var n := qty if stack else 1
	var red := int(DB.items[key].get("red_id", -1))
	# the Weavile / Mime Jr. figurines: a statue at the base the first time, else 1,000 Poké
	if red == 234 or red == 235:            # ITEM_WEAVILE_FIG / ITEM_MIME_JR_FIG
		var slot := 1 if red == 234 else 0
		var ev := GVars.var_id("EVENT_B01P01")
		if GVars.get_arr(null, ev, slot) != 0:
			Game.money += 1000
			await _say(root, S_1000, nm)
		else:
			GVars.set_arr(null, ev, slot, 1)
			Audio.sfx("212")
			await _say(root, S_STATUE, nm)
		return
	var then := ""
	if Game.bag.size() >= Game.BAG_MAX and not _stacks_into_bag(key, n):
		if key != "poke" and int(Game.storage.get(key, 0)) + n <= 999:
			Game.storage[key] = int(Game.storage.get(key, 0)) + n
			Audio.sfx("203")
			then = "stored"
		else:
			then = "full"
	else:
		Game.bag_add(key, n)
		Audio.sfx("203")
	if mode == 1:
		await _say(root, S_ALSO, nm)
	else:
		await _say(root, S_TEAM_PROMISED if Game.team.size() >= 2 else S_PROMISED, nm)
	if then == "stored":
		await _say(root, S_TO_STORAGE, nm)
	elif then == "full":
		await _full_toolbox(root, key, n)

static func _stacks_into_bag(key: String, n: int) -> bool:
	if not DB.items[key].get("stack", false):
		return false
	for b in Game.bag:
		if str(b.id) == key and int(b.n) + n <= 99:
			return true
	return false

## States 6..15: "Trash Toolbox Item" (pick one: Storage / Trash / Info) or "Trash Received Item".
static func _full_toolbox(root: Control, key: String, n: int) -> void:
	var nm := DB.item_name(key)
	while true:
		var c: int
		if Dialog.auto or ListMenu.auto:
			print("  REWARD full toolbox -> ", ["Trash Toolbox Item", "Trash Received Item"][test_choice])
			c = test_choice
		else:
			c = await _ask(root, S_FULL, ["Trash Toolbox Item", "Trash Received Item"], nm)
		if c == 1:
			var y := 0 if (Dialog.auto or ListMenu.auto) else await _ask(root, S_CONFIRM, ["Yes", "No"], nm)
			if y == 0:
				await _say(root, S_THROWN, nm)
				return
			continue
		if c != 0:
			continue
		# pick the Toolbox item to give up
		while true:
			var k := 0 if (Dialog.auto or ListMenu.auto) else await _pick_toolbox(root, "Toolbox")
			if k < 0:
				break
			var old := str(Game.bag[k].id)
			var on := DB.item_name(old)
			var opts: Array = [{"text": "Storage", "disabled": old == "poke"}, "Trash", "Info"]
			var a := "Storage" if (Dialog.auto or ListMenu.auto) else await TeamScreens.submenu(root, null, opts)
			match a:
				"Storage":
					var cnt := int(Game.bag[k].get("n", 1))
					Game.storage[old] = int(Game.storage.get(old, 0)) + maxi(1, cnt)
					Game.bag.remove_at(k)
					Game.bag_add(key, n)
					Audio.sfx("203")
					await _say(root, S_STORED_FOR, nm, on)
					return
				"Trash":
					var y2 := await RedMsg.ask(root, _it(S_CONFIRM, on), ["Yes", "No"])
					if y2 == 0:
						Game.bag.remove_at(k)
						Game.bag_add(key, n)
						Audio.sfx("203")
						await _say(root, S_DISCARD_FOR, nm, on)
						return
				"Info":
					await TeamScreens.item_info(root, old)
		continue

static func _pick_toolbox(root: Control, title: String) -> int:
	var rows: Array = []
	for b in Game.bag:
		rows.append({"text": BaseMenu._bag_label(b)})
	var P := UITheme.PX
	var r := await BaseMenu.paged(root, title, rows, 0, Vector2(2 * 8 * P, 2 * 8 * P), 8, 120 * P)
	return int(r.i) if r.act == "pick" else -1

static var test_feed := ""            # tests: the item key fed in auto mode ("" = cancel)

## SPECIAL_TEXT_TOOL_BOX: pick a Toolbox item; an edible one (IsEdibleItem: berries/seeds/vitamins,
## food/gummies) is removed, its name goes to {MOVE_ITEM_0} and the result is 1, else -1.
static func toolbox_feed(root: Control, G) -> int:
	if Game.bag.is_empty():
		return -1
	var k := -1
	if Dialog.auto or ListMenu.auto:
		for i in Game.bag.size():
			if str(Game.bag[i].id) == test_feed:
				k = i
	else:
		k = await _pick_toolbox(root, "Toolbox")
	if k < 0:
		return -1
	var id := str(Game.bag[k].id)
	var cat := str(DB.items.get(id, {}).get("red_cat", ""))
	if not cat in ["berries_seeds_vitamins", "food_gummies"]:
		return -1
	if G != null and "items" in G.text:
		G.text.items[0] = DB.item_name(id)
	var it: Dictionary = Game.bag[k]
	if int(it.get("n", 1)) > 1 and DB.items[id].get("stack", false):
		it.n = int(it.n) - 1
	else:
		Game.bag.remove_at(k)
	return 1
