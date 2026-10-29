class_name Services
extends RefCounted
## Pokémon Square services and base actions (menus + Red-style dialogue).
## Speakers: Kecleon 0352, Kangaskhan 0115, Persian 0053 (Felicity Bank), Wigglytuff 0040, Pelipper 0279.
## The shop dialogue and menus are Red's (scripts/town/red_shops.gd); the helpers here stay for tests.

const STORY_ORDER := ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm", "mt_thunder", "mt_thunder_peak",
	"great_canyon", "lapis_cave", "mt_blaze", "mt_blaze_peak", "frosty_forest", "frosty_grotto", "mt_freeze", "mt_freeze_peak",
	"magma_cavern", "magma_cavern_pit", "sky_tower", "sky_tower_summit"]
const PARTY_MAX := 4

static var _fa: Dictionary = {}

static func fa() -> Dictionary:
	if _fa.is_empty():
		var f := FileAccess.open("res://data/friend_areas.json", FileAccess.READ)
		if f:
			_fa = JSON.parse_string(f.get_as_text())
	return _fa

static func area_of(sp: String) -> String:
	return str(fa().get("species", {}).get(sp.substr(0, 4), ""))

static func area_name(k: String) -> String:
	return str(fa().get("areas", {}).get(k, {}).get("name", k))

static func has_area_for(sp: String) -> bool:
	var a := area_of(sp)
	return a != "" and a in Game.friend_areas

## Unlock the next story dungeon after clearing one (until stage 3 adds the story scenes).
static func on_cleared(key: String) -> Array:
	var newly: Array = []
	if not key in Game.cleared:
		Game.cleared.append(key)
	var i := STORY_ORDER.find(key)
	if i >= 0 and i + 1 < STORY_ORDER.size():
		var nxt: String = STORY_ORDER[i + 1]
		if not nxt in Game.unlocked:
			Game.unlocked.append(nxt)
			newly.append(nxt)
	return newly

static func dname(key: String) -> String:
	return str(DB.dungeons.get("dungeons", {}).get(key, {}).get("name", key.capitalize()))

# ------------------------------------------------------------------ world map
## Returns the chosen dungeon key, a friend area key prefixed "fa:", or "" (stay).
static func world_map(root: Control) -> String:
	var opts: Array = []
	var keys: Array = []
	for k in STORY_ORDER:
		if k in Game.unlocked:
			var star := " ★" if k in Game.cleared else ""
			opts.append("%s%s" % [dname(k), star])
			keys.append(k)
	for k in Game.unlocked:
		if not k in STORY_ORDER:
			opts.append(dname(k))
			keys.append(k)
	if Game.friend_areas.size() > 0:
		opts.append("Friend Areas")
		keys.append("fa:")
	opts.append("Back to town")
	keys.append("")
	var lm := ListMenu.make("Where to?", opts)
	_place(root, lm)
	var i := await lm.choose()
	if i < 0:
		return ""
	var k: String = keys[i]
	if k == "fa:":
		var fk := await pick_friend_area(root)
		return "" if fk == "" else "fa:" + fk
	# (the Prepare screen in main.gd confirms setting out)
	return k

static func _place(root: Control, c: Control, at := Vector2(8, 8)) -> void:
	root.add_child(c)
	c.position = at

# ------------------------------------------------------------------ friend areas
static func pick_friend_area(root: Control) -> String:
	var opts: Array = []
	for k in Game.friend_areas:
		var n := 0
		for f in Game.friends:
			if f.get("area", "") == k:
				n += 1
		opts.append("%s (%d)" % [area_name(k), n])
	var lm := ListMenu.make("Friend Areas", opts)
	lm.on_select = func(j: int): BottomScreen.hover_item("fa:" + str(Game.friend_areas[j]) if j >= 0 and j < Game.friend_areas.size() else "")
	_place(root, lm)
	var i := await lm.choose()
	BottomScreen.hover_item("")
	return "" if i < 0 else str(Game.friend_areas[i])

## Visit a Friend Area: see residents, bring them into the team or send team members home.
static func visit_area(root: Control, k: String) -> void:
	while true:
		var residents: Array = []
		for f in Game.friends:
			if f.get("area", "") == k:
				residents.append(f)
		var opts: Array = []
		for f in residents:
			var in_team := _in_team(f)
			opts.append("%s Lv%d%s" % [f.name, int(f.level), "  (team)" if in_team else ""])
		if opts.is_empty():
			await Dialog.say(root, "Nobody lives in %s yet." % area_name(k))
			return
		opts.append("Leave")
		var lm := ListMenu.make(area_name(k), opts)
		_place(root, lm)
		var i := await lm.choose()
		if i < 0 or i >= residents.size():
			return
		var f: Dictionary = residents[i]
		if _in_team(f):
			if Game.team.find(f) < 2:
				await Dialog.say(root, "%s has to stay on the team for now." % f.name, f.sp)
				continue
			var c := await Dialog.ask(root, "Send %s home to rest?" % f.name, ["Yes", "No"], f.sp)
			if c == 0:
				Game.team.erase(f)
		else:
			if Game.team.size() >= PARTY_MAX:
				var opts2: Array = []
				for t in Game.team.slice(2):
					opts2.append(t.name)
				if opts2.is_empty():
					await Dialog.say(root, "The team is full.")
					continue
				opts2.append("Cancel")
				var sw := ListMenu.make("Swap out who?", opts2)
				_place(root, sw, Vector2(200, 8))
				var j := await sw.choose()
				if j < 0 or j >= opts2.size() - 1:
					continue
				Game.team.erase(Game.team[j + 2])
			Game.team.append(f)
			Audio.sfx("join")
			await Dialog.say(root, "%s joined the team!" % f.name, f.sp, "Happy")
		Game.save_game()

static func _in_team(f: Dictionary) -> bool:
	for t in Game.team:
		if t == f:
			return true
	return false

# ------------------------------------------------------------------ Wigglytuff
## Friend Areas Wigglytuff still sells (sub_8021700 kind 2).
static func shop_areas_left() -> int:
	var n := 0
	var areas: Dictionary = fa().get("areas", {})
	for k in areas:
		var a: Dictionary = areas[k]
		if not k in Game.friend_areas and (a.how == "Shop Story" or (a.how == "Shop Post Game" and Game.flags.get("postgame", false))):
			n += 1
	return n

static func wigglytuff(root: Control) -> void:
	await RedShops.wigglytuff(root)       # Red's Wigglytuff Club (scripts/town/red_shops.gd)

static func _info_box(root: Control) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.theme = UITheme.theme()
	r.bbcode_enabled = true
	r.fit_content = true
	r.custom_minimum_size = Vector2(160, 0)
	r.add_theme_stylebox_override("normal", UITheme.box())
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	r.position = Vector2(220, 8)
	return r

# ------------------------------------------------------------------ Kecleon
static func shop_stock() -> Array:
	# Red's Kecleon Shop item sets (A..D) open up as the adventure goes on
	var sets := [1]
	var n := Game.cleared.size()
	if n >= 4: sets.append(19)
	if n >= 9: sets.append(28)
	if n >= 14: sets.append(37)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("kecleon%d" % Game.day)
	var pool: Array = []
	for t in sets:
		var tab: Dictionary = DB.dungeons.item_tables[t]
		for c in tab.cats:
			for it in c.items:
				var id := str(it[0])
				if DB.items.has(id) and int(it[1]) > 0 and not id in pool and int(DB.items[id].get("price", 0)) > 0:
					pool.append(id)
	var stock: Array = ["apple", "oran"]
	while stock.size() < 10 and pool.size() > 0:
		var id: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		if not id in stock:
			stock.append(id)
	return stock

## wares = the purple counter (TMs / Orbs); the green one sells items.
static func kecleon(root: Control, wares := false) -> void:
	await RedShops.kecleon(root, wares)   # Red's Kecleon Bros. (scripts/town/red_shops.gd)

static func sell_value(b: Dictionary) -> int:
	var I: Dictionary = DB.items.get(str(b.id), {})
	return int(I.get("sell", 0)) * (int(b.n) if I.get("stack", false) else 1)

static func _bag_label(b: Dictionary) -> String:
	return DB.item_name(str(b.id)) + (" ×%d" % int(b.n) if DB.items.get(b.id, {}).get("stack", false) else "")

## Sell the bag slots at these indices; returns the money made.
static func sell_slots(idx: Array) -> int:
	var total := 0
	var sorted := idx.duplicate()
	sorted.sort()
	sorted.reverse()
	for i in sorted:
		if i >= 0 and i < Game.bag.size() and sell_value(Game.bag[i]) > 0:
			total += sell_value(Game.bag[i])
			Game.bag.remove_at(i)
	Game.money += total
	return total

static func slots_of(id: String) -> Array:
	var out: Array = []
	for i in Game.bag.size():
		if str(Game.bag[i].id) == id:
			out.append(i)
	return out

# ------------------------------------------------------------------ Kangaskhan Storage
## Move every Toolbox item into storage. Returns how many slots were stored.
static func store_all() -> int:
	var n := Game.bag.size()
	for b in Game.bag:
		Game.storage[b.id] = int(Game.storage.get(b.id, 0)) + int(b.n)
	Game.bag.clear()
	return n

## Take as much as fits from storage. Returns [items taken, items left behind].
static func take_all() -> Array:
	var taken := 0
	var keys: Array = Game.storage.keys()
	keys.sort_custom(func(a, b): return DB.item_name(a) < DB.item_name(b))
	for id in keys:
		var stack: bool = DB.items.get(id, {}).get("stack", false)
		while int(Game.storage[id]) > 0:
			var n := mini(int(Game.storage[id]), 99) if stack else 1
			if not Game.bag_add(id, n):
				break
			Game.storage[id] = int(Game.storage[id]) - n
			taken += n
		if int(Game.storage[id]) <= 0:
			Game.storage.erase(id)
	var left := 0
	for id in Game.storage:
		left += int(Game.storage[id])
	return [taken, left]

static func storage(root: Control) -> void:
	await RedShops.storage(root)          # Red's Kangaskhan Storage (scripts/town/red_shops.gd)

# ------------------------------------------------------------------ Felicity Bank
static func bank(root: Control) -> void:
	await RedShops.bank(root)             # Red's Felicity Bank (scripts/town/red_shops.gd)

static func bank_move(deposit: bool, amt: int) -> void:
	if deposit:
		amt = mini(amt, Game.money)
		Game.money -= amt
		Game.bank += amt
	else:
		amt = mini(amt, Game.bank)
		Game.bank -= amt
		Game.money += amt

# ------------------------------------------------------------------ base
static func sleep(root: Control) -> void:
	var c := await Dialog.ask(root, "Go to sleep and save the adventure?", ["Sleep", "Not yet"])
	if c != 0:
		return
	Game.day += 1
	Game.save_game()
	await Dialog.say(root, "...\nA new day dawned. Your adventure was saved.")
