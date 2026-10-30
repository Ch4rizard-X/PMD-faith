class_name SwapShop
extends RefCounted
## Croagunk's Swap Shop (Explorers of Sky, with Explorers Remixed's item list), standing in Pokémon Square in
## front of the house by the Kecleon Shop. Croagunk's own lines are EoS's.
##
##   Swap      - pick one of today's Exclusive Items ("offered up by another Pokémon"), then put in a set:
##               the set its description names (data/swap_shop.json, from Remixed's item texts: two 1-star items
##               for a 2-star one, those plus the 2-star for a 3-star one), or any Exclusive Items: 2 for a
##               1-star item, 3 for a 2-star, 5 for a 3-star. Items in storage count too. 150 Poké a swap.
##   View List - the Exclusive Items a team member (or friend) can use, with their stars.
##   Info      - Croagunk explains the swaps and the list.
## Today's stock (seeded by the day): 8 items, 5 of them usable by the team and 1 by a friend when there are such
## items, plus every item whose named set you own.

const MAP := 1                     # Pokémon Square
const DIR := 0
const CROAGUNK := "0453"
const DAILY := 8
const TEAM_SLOTS := 5               # of the 8: items the team can use, then 1 for a friend, the rest any
const FRIEND_SLOTS := 1
static var spot_override = null    # tests: [x, y, 0, 2] in map tiles
static var _data := {}

static func spot() -> Array:
	if spot_override != null:
		return spot_override
	return [50, 35, 0, 2]          # in front of the house by the Kecleon Shop

static func unlocked() -> bool:
	return not load("res://scripts/core/launcher_cfg.gd").red_part("swapshop")      # the launcher's Game page

# ------------------------------------------------------------------ data
static func data() -> Dictionary:
	if _data.is_empty():
		var path: String = load("res://scripts/core/launcher_cfg.gd").data_path("swap_shop")    # "" in Red mode
		var f := FileAccess.open(path, FileAccess.READ) if path != "" else null
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
		if _data.is_empty():
			_data = {"fee": 150, "any_count": {"1": 2, "2": 3, "3": 5}, "recipes": {}}
	return _data

static func fee() -> int:
	return int(data().get("fee", 150))

static func is_exclusive(id: String) -> bool:
	return str(DB.items.get(id, {}).get("kind", "")) == "exclusive"

static func stars(id: String) -> int:
	return clampi(int(DB.items.get(id, {}).get("rarity", 1)), 1, 3)

static func star_text(id: String) -> String:
	var s := ""
	for _i in stars(id):
		s += TeamScreens.star_mark()
	return s

static func recipe(id: String) -> Array:
	return data().get("recipes", {}).get(id, [])

static func any_count(id: String) -> int:
	return int(data().get("any_count", {}).get(str(stars(id)), 2))

## Can the team member (entry) use this Exclusive Item (its species line or its type)?
static func usable_by(e: Dictionary, id: String) -> bool:
	var ex: Dictionary = DB.items.get(id, {}).get("excl", {})
	var sp := str(e.get("sp", "")).substr(0, 4)
	if sp in ex.get("for", []):
		return true
	var types: Array = DB.species.get(str(e.get("sp", "")), DB.species.get(sp, {})).get("types", [])
	for t in ex.get("types", []):
		if t in types:
			return true
	return false

## Exclusive Items you own, Toolbox and storage: [{id, where: "bag"|"storage", i}] (one entry per item).
static func owned() -> Array:
	var out: Array = []
	for i in Game.bag.size():
		var b: Dictionary = Game.bag[i]
		if is_exclusive(str(b.id)) and int(b.get("price", 0)) == 0:
			out.append({"id": str(b.id), "where": "bag", "i": i})
	for id in Game.storage:
		if is_exclusive(str(id)):
			for _k in int(Game.storage[id]):
				out.append({"id": str(id), "where": "storage", "i": -1})
	return out

static func _count_owned(own: Array) -> Dictionary:
	var c := {}
	for o in own:
		c[o.id] = int(c.get(o.id, 0)) + 1
	return c

static func has_set(id: String, own: Array) -> bool:
	var r := recipe(id)
	if r.is_empty():
		return false
	var c := _count_owned(own)
	for x in r:
		if int(c.get(x, 0)) <= 0:
			return false
		c[x] = int(c[x]) - 1
	return true

static func _all_exclusive() -> Array:
	var all_ex: Array = []
	for id in DB.items:
		if is_exclusive(str(id)) and not str(DB.items[id].get("name", "")).begins_with("$"):
			all_ex.append(str(id))
	all_ex.sort()
	return all_ex

## Today's stock (seeded by the day): mostly items the team can use, then any; plus every item whose set you own.
static func stock() -> Array:
	var all_ex := _all_exclusive()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("swap_shop_%d" % Game.day)
	var team_pool: Array = []
	var friend_pool: Array = []
	for id in all_ex:
		if Game.team.any(func(e): return usable_by(e, id)):
			team_pool.append(id)
		elif Game.friends.any(func(e): return usable_by(e, id)):
			friend_pool.append(id)
	var out: Array = []
	_pick_weighted(rng, team_pool, out, TEAM_SLOTS)
	_pick_weighted(rng, friend_pool, out, TEAM_SLOTS + FRIEND_SLOTS)
	_pick_weighted(rng, all_ex, out, DAILY)
	var own := owned()
	for id in data().get("recipes", {}):
		if not id in out and DB.items.has(id) and has_set(id, own):
			out.append(str(id))
	return out

## Adds items from pool to out until out has n (rarer items less often: 1-star x3, 2-star x2, 3-star x1).
static func _pick_weighted(rng: RandomNumberGenerator, pool: Array, out: Array, n: int) -> void:
	var cand: Array = pool.filter(func(id): return not id in out)
	while out.size() < n and not cand.is_empty():
		var tot := 0
		for id in cand:
			tot += [0, 3, 2, 1][stars(id)]
		var r := rng.randi_range(0, tot - 1)
		for k in cand.size():
			r -= [0, 3, 2, 1][stars(cand[k])]
			if r < 0:
				out.append(cand[k])
				cand.remove_at(k)
				break

# ------------------------------------------------------------------ text
static func _say(root: Control, t: String) -> void:
	await Dialog.say(root, t, CROAGUNK)

static func _ask(root: Control, t: String, opts: Array) -> int:
	return await Dialog.ask(root, t, opts, CROAGUNK)

static func _fee_txt() -> String:
	return "[color=#ffdc4a]%d[/color]%s" % [fee(), UITheme.glyph("POKE")]

static func _item_txt(id: String) -> String:
	return "[color=#ffdc4a]%s[/color]" % DB.item_name(id)

static func _hero() -> String:
	return str(Game.team[0].get("name", "You")) if not Game.team.is_empty() else "You"

# ------------------------------------------------------------------ shop
static func open(root: Control) -> void:
	var first := true
	while true:
		var t := ("Meh-heh-heh. Welcome to the\nCroagunk Swap Shop. Want to swap? It'll\ncost ya %s." % _fee_txt()) if first \
			else "Meh-heh-heh. Anything else you\nwanna swap?"
		first = false
		match await _ask(root, t, ["Swap", "View List", "Info", "Exit"]):
			0:
				await _swap(root)
			1:
				await _view_list(root)
			2:
				await _info(root)
			_:
				await _say(root, "Come again! Meh-heh-heh!")
				Game.save_game()
				return

static func _swap(root: Control) -> void:
	if Game.spendable() < fee():
		await _say(root, "Meh-heh-heh... Hey, hold it!\nNo money, no swap. Got that?")
		return
	var offers := stock()
	if offers.is_empty():
		await _say(root, "Meh-heh-heh. Sorry...\nIt looks like there's nobody to trade with now.")
		return
	var own := owned()
	if own.size() < 2:
		await _say(root, "Let me take a look... Nope, you\ndon't have a set of swappable items. Meh-heh.")
		return
	await _say(root, "So which Exclusive Item do you\nwant?")
	while true:
		var rows: Array = []
		for id in offers:
			var can_set := has_set(id, own)
			var can_any := own.size() >= any_count(id)
			rows.append({"text": "%s %s" % [DB.item_name(id), star_text(id)], "icon": TeamScreens.item_icon(id), "item": id,
				"right": "Set" if can_set else "%d items" % any_count(id), "disabled": not (can_set or can_any)})
		var m := TeamScreens.menu("Swap", rows, 22 * 8 * UITheme.PX)
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * UITheme.PX, 2 * 8 * UITheme.PX))
		if str(r.get("act", "")) != "pick":
			await _say(root, "You don't wanna? Meh-heh-heh!")
			return
		var want: String = offers[int(r.i)]
		var give: Array = []                     # entries of owned()
		if has_set(want, own):
			var used := {}
			for x in recipe(want):
				for k in own.size():
					if not used.has(k) and own[k].id == x:
						used[k] = true
						give.append(own[k])
						break
			var names: Array = give.map(func(o): return _item_txt(o.id))
			var q := ""
			if names.size() == 2:
				q = "So you wanna swap your\n%s and %s for that?\nIt'll cost %s. OK?" % [names[0], names[1], _fee_txt()]
			else:
				q = "So you wanna swap your\n%s, %s, and\n%s for that? It'll cost %s. OK?" % [names[0], names[1], names[2], _fee_txt()]
			if await _ask(root, q, ["Yes", "No"]) != 0:
				await _say(root, "You don't wanna? Meh-heh-heh!")
				continue
		else:
			var need := any_count(want)
			if own.size() < need:
				await _say(root, "Let me take a look... Nope, you\ndon't have a set of swappable items. Meh-heh.")
				continue
			await _say(root, "OK, so which Exclusive\nItems are you offering in return?")
			give = await _pick_items(root, own, need)
			if give.size() != need:
				await _say(root, "You don't wanna? Meh-heh-heh!")
				continue
			if await _ask(root, "So you wanna swap your\n%d Exclusive Items, then?\nIt'll cost %s. OK?" % [need, _fee_txt()], ["Yes", "No"]) != 0:
				await _say(root, "You don't wanna? Meh-heh-heh!")
				continue
		await _do_swap(root, want, give)
		return

## Pick exactly n of the owned Exclusive Items (marking rows; Done when n are marked).
static func _pick_items(root: Control, own: Array, n: int) -> Array:
	var labels: Array = []
	var ids: Array = []
	var rights: Array = []
	for o in own:
		labels.append("%s %s" % [DB.item_name(o.id), star_text(o.id)])
		ids.append(o.id)
		rights.append("" if o.where == "bag" else "Storage")
	var marks := {}
	while true:
		var r := await RedShops._multi_list(root, "Offer %d" % n, labels, marks, 0, rights, ids)
		if str(r.act) != "pick":
			return []
		var ks: Array = r.marks
		if ks.is_empty():
			ks = [int(r.i)]
		if ks.size() == n:
			return ks.map(func(k): return own[int(k)])
		await Dialog.say(root, "Mark exactly %d Exclusive Items to offer (%d marked)." % [n, ks.size()])
		if ks.size() > n:
			marks.clear()
	return []

static func _do_swap(root: Control, want: String, give: Array) -> void:
	await _say(root, "Let's do this swap then!\nMeh-heh-heh!")
	# take the items out: storage by count, Toolbox entries by index (highest first)
	var bag_idx: Array = []
	for o in give:
		if o.where == "storage":
			Game.storage[o.id] = int(Game.storage.get(o.id, 0)) - 1
			if int(Game.storage[o.id]) <= 0:
				Game.storage.erase(o.id)
		else:
			bag_idx.append(int(o.i))
	bag_idx.sort()
	bag_idx.reverse()
	for i in bag_idx:
		if i >= 0 and i < Game.bag.size():
			Game.bag.remove_at(i)
	Game.pay(fee())
	Audio.sfx("332")
	await Dialog.say(root, "%s put the Exclusive Items\nin the Swap Cauldron." % _hero())
	if stars(want) >= 3:
		await _say(root, "Meh-heh-heh! Seems that we\nbrewed up a successful swap there!")
		await _say(root, "What? What's that?!\n%s?! I must be hallucinating!" % _item_txt(want))
		await _say(root, "That's unbelievably valuable!\nSo incredibly special! I rarely see something so\nvaluable! Treat it with respect! Meh-heh-heh!")
		Audio.sfx("pickup")
		await Dialog.say(root, "%s accepted the extremely\nrare and precious %s!" % [_hero(), _item_txt(want)])
	else:
		await _say(root, "Meh-heh-heh! Seems to me your swap\nwent off without a hitch!")
		await _say(root, "Those Exclusive Items you\nswapped got you this %s.\nI'd say it's pretty rare. Treat it with care." % _item_txt(want))
		Audio.sfx("pickup")
		await Dialog.say(root, "%s accepted\nthe %s." % [_hero(), _item_txt(want)])
	if not Game.bag_add(want):
		Game.storage[want] = int(Game.storage.get(want, 0)) + 1
		await _say(root, "...But you can't take it. Not when\nyou don't have room for it! Meh-heh-heh.")
		await _say(root, "So I'll send it to your storage\nlater. You be sure to check on it.")
	Game.save_game()

static func _view_list(root: Control) -> void:
	var who: Array = Game.team + Game.friends
	if who.is_empty():
		return
	while true:
		var names: Array = who.map(func(e): return TeamScreens.name_of(e))
		await _say(root, "Whose list of Exclusive Items\ndo you want to see?")
		var lm := ListMenu.make("View List", names)
		root.add_child(lm)
		lm.position = Vector2(8, 8)
		var i := await lm.choose()
		if i < 0:
			return
		var e: Dictionary = who[i]
		var ids: Array = []
		for id in _all_exclusive():
			if usable_by(e, id):
				ids.append(id)
		ids.sort_custom(func(a, b): return stars(a) < stars(b) if stars(a) != stars(b) else DB.item_name(a) < DB.item_name(b))
		await _say(root, "Here's a list of Exclusive Items\nthat %s can use." % TeamScreens.name_of(e))
		if not ids.is_empty():
			var labels: Array = ids.map(func(id): return "%s %s" % [DB.item_name(id), star_text(id)])
			while true:
				var r := await RedShops._multi_list(root, TeamScreens.name_of(e), labels, {}, 0, [], ids)
				if str(r.act) != "pick":
					break
				await TeamScreens.item_info(root, str(ids[int(r.i)]))
		if await _ask(root, "Would you like to see anyone\nelse's Exclusive Items list?", ["Yes", "No"]) != 0:
			return

static func _info(root: Control) -> void:
	match await _ask(root, "What do you want to know?", ["Trade Info", "List Info", "Exit"]):
		0:
			await _say(root, "See the Swap Cauldron behind\nme? When ya throw in some Exclusive Items...")
			await _say(root, "They're swapped for one\nExclusive Item offered up by another Pokémon.")
			await _say(root, "But you have to put in a set of\nswappable items!")
			await _say(root, "Don't worry. It's worth it. You\ncan get back rare items in swaps.\nCount on it! Meh-heh-heh!")
			await _say(root, "If you look up the Info on\nitems, the ones that are Exclusive Items will\nhave a star rating on them.")
			await _say(root, "You'll need a set of items with\nthe star rating to do the swap.\nLet me give you an example.")
			await _say(root, "Let's say you have a [color=#7fe0ff]Shinx Claw[/color] and\na [color=#7fe0ff]Shinx Fang[/color]...\nYou could swap them for a [color=#7fe0ff]Flash Tag[/color]. Get it?")
			await _say(root, "Also, you don't have to be\nlimited to just your Treasure Bag...\nYou can trade the Exclusive Items in your storage as well.")
			await _say(root, "Keep at your exploration thing\nso you can do better swaps, OK?\nMeh-heh-heh!")
		1:
			await _say(root, "Which Exclusive Items will have\nan effect on you or your team...?\nYou can view them in a list.")
			await _say(root, "If you see an Exclusive Item you\nwant on the list...then of course you can\ntrade for it!")
