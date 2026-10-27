class_name RedShops
extends RefCounted
## Pokémon Square's shops with Red's own text and menus:
##   Kecleon Bros. (kecleon_bros1-4.c): two counters. The green one sells items (8 a day), the purple one
##     TMs and Orbs (4 a day), from Red's RANDOM_ITEMS_SET_KECLEON_SHOP/WARES_1..4 (data/kecleon_sets.json)
##     picked by story progress (ground_main.c). Buy / Sell / Sell All / Info / Cancel.
##   Kangaskhan Storage (kangaskhan_storage1/2.c): Store / Take / Info / Cancel, several items at once.
##   Felicity Bank (felicity_bank.c): Store / Take / Info / Cancel with Red's digit entry window.
##   Wigglytuff Club (wigglytuff_shop1-3.c): Buy / Check / Info / Cancel and the Friend Area info screen.
## At night (QUEST_SQUARE_ASLEEP) every shopkeeper talks in its sleep (the *_ASLEEP_* texts, no portrait).

const P := UITheme.PX
const MAX_MONEY := 99999           # MAX_TEAM_MONEY
const MAX_SAVINGS := 9999999       # MAX_TEAM_SAVINGS
const STORAGE_MAX := 999           # per item (kangaskhan: teamStorage > 998)

static var force_asleep := false     # tests

static func asleep() -> bool:
	return force_asleep or (Game.story.has("vars") and GVars.quest(GVars.QUEST_SQUARE_ASLEEP))

static func postgame() -> bool:
	if Game.flags.get("postgame", false):
		return true
	return Game.story.has("vars") and GVars.quest(GVars.QUEST_REACHED_POSTGAME)

static func _yn() -> Array:
	return ["Yes", "No"]

static func _money_box(root: Control, at := Vector2(-1, -1)) -> PanelContainer:
	var w := PanelContainer.new()
	w.theme = UITheme.theme()
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	w.add_child(vb)
	vb.add_child(TeamScreens._rtl(RedText.get_text("felicity_bank:sMoney")))
	vb.add_child(TeamScreens._rtl("[right]%d[/right]" % Game.money))
	w.custom_minimum_size = Vector2(9 * 8 * P, 0)
	root.add_child(w)
	var vs := root.get_viewport_rect().size
	w.position = at if at.x >= 0 else Vector2(vs.x - 9 * 8 * P - 2 * 8 * P, 2 * 8 * P)
	return w

static func _price_rows(list: Array, price_of: Callable) -> Array:
	var rows: Array = []
	for b in list:
		var nm := DB.item_name(str(b.id))
		if DB.items.get(b.id, {}).get("stack", false) and int(b.get("n", 0)) > 0:
			nm += " %d" % int(b.n)
		rows.append({"text": nm, "right": str(price_of.call(b))})
	return rows

# ============================================================================ Kecleon Bros.
static func buy_value(b: Dictionary) -> int:
	var I: Dictionary = DB.items.get(str(b.id), {})
	return int(I.get("price", 0)) * (maxi(1, int(b.get("n", 1))) if I.get("stack", false) else 1)

static func sell_value(b: Dictionary) -> int:
	return Services.sell_value(b)

## IsShoppableItem: Kecleon won't buy Poké or used TMs.
static func shoppable(id: String) -> bool:
	return id != "poke" and id != "usedtm" and int(DB.items.get(id, {}).get("sell", 0)) > 0

## ground_main.c: which Kecleon set (0..3) the story has reached.
static func kecleon_set() -> int:
	if Game.story.has("vars"):
		if GVars.before(GVars.SCENARIO_MAIN, 0xB, 0):
			return 0
		if GVars.before(GVars.SCENARIO_MAIN, 0xF, 0):
			return 1
		if GVars.before(GVars.SCENARIO_MAIN, 0x12, 0):
			return 2
		return 3
	var n := Game.cleared.size()
	return 3 if n >= 14 else (2 if n >= 9 else (1 if n >= 4 else 0))

static var _sets: Dictionary = {}

static func _set_data(name: String) -> Dictionary:
	if _sets.is_empty():
		var f := FileAccess.open("res://data/kecleon_sets.json", FileAccess.READ)
		if f:
			_sets = JSON.parse_string(f.get_as_text())
	return _sets.get(name, {})

## GetRandomItemForSet: a category by cumulative odds, then an item of that category.
static func random_item(set_name: String, rng: RandomNumberGenerator) -> String:
	var d := _set_data(set_name)
	var rc := rng.randi_range(0, 9999) / 100.0
	var cat := ""
	for c in d.get("cats", []):
		if float(c[1]) >= rc:
			cat = str(c[0])
			break
	var ri := rng.randi_range(0, 9999) / 100.0
	for it in d.get("items", []):
		if str(it[2]) == cat and float(it[1]) >= ri:
			return str(it[0])
	return "plainseed" if DB.items.has("plainseed") else ""

static func _bulk(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var I: Dictionary = DB.items.get(id, {})
	var n := 0
	if I.get("stack", false) and I.has("amt"):
		n = rng.randi_range(int(I.amt[0]), int(I.amt[1]))
	return {"id": id, "n": n}

## Today's stock (ChooseKecleonShopInventory, refreshed each day; bought items leave the shelf).
static func stock(wares: bool) -> Array:
	var st = Game.flags.get("kecleon", null)
	if not st is Dictionary or int(st.get("day", -1)) != Game.day:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("kecleon_red%d_%d" % [Game.day, Game.money])
		var si := kecleon_set() + 1
		var items: Array = []
		for k in 8:
			var id := random_item("KecleonShop%d" % si, rng)
			if DB.items.has(id):
				items.append(_bulk(id, rng))
		var ware: Array = []
		for k in 4:
			var id2 := random_item("KecleonWares%d" % si, rng)
			if DB.items.has(id2):
				ware.append(_bulk(id2, rng))
		items.sort_custom(func(a, b): return int(DB.items[a.id].get("red_id", 999)) < int(DB.items[b.id].get("red_id", 999)))
		ware.sort_custom(func(a, b): return int(DB.items[a.id].get("red_id", 999)) < int(DB.items[b.id].get("red_id", 999)))
		st = {"day": Game.day, "items": items, "wares": ware}
		Game.flags["kecleon"] = st
	return st["wares" if wares else "items"]

static func kecleon(root: Control, wares := false) -> void:
	var mode := ("WARES" if wares else "ITEMS") + ("_ASLEEP" if asleep() else "_AWAKE")
	var K := "KEC_%s_DLG_" % mode
	var sp := "" if asleep() else "0352"
	var nm: String = str(DB.species.get("0352", {}).get("name", "Kecleon"))
	var v := {"mon6": "[color=#ffdc4a]%s[/color]" % nm}
	var first := true
	var sel := 0
	while true:
		if _auto_spin():
			return
		var rows: Array = ["Buy", "Sell", "Sell All", "Info", "Cancel"]
		var has_box := not wares and not asleep() and Game.bag.any(func(b): return EosItems.is_box(str(b.id)))
		if has_box:
			rows.insert(3, "Open Box")
		var c := await RedText.ask(root, K + ("00" if first else "01"), nm, sp, rows, v, mini(sel, rows.size() - 1))
		first = false
		if c >= 0 and rows[c] == "Open Box":
			sel = c
			await _kec_open_box(root, nm, sp)
			continue
		if c >= 0 and has_box and c > 3:
			c -= 1                      # back to Red's row numbers
		if c < 0 or c == 4:
			await RedText.say(root, K + "02", nm, sp, v, "Happy")
			Game.save_game()
			return
		sel = c
		match c:
			0:
				if stock(wares).is_empty():
					await RedText.say(root, K + "12", nm, sp, v)
				elif Game.bag.size() >= Game.BAG_MAX:
					await RedText.say(root, K + "17", nm, sp, v)
				else:
					await RedText.say(root, K + "03", nm, sp, v)
					await _kec_buy(root, wares, K, nm, sp, v)
			1:
				if Game.bag.is_empty():
					await RedText.say(root, K + "16", nm, sp, v)
				elif not Game.bag.any(func(b): return shoppable(str(b.id))):
					await RedText.say(root, K + "15", nm, sp, v)
				elif Game.money >= MAX_MONEY:
					await RedText.say(root, K + "14", nm, sp, v)
				else:
					await RedText.say(root, K + "07", nm, sp, v)
					await _kec_sell(root, K, nm, sp, v)
			2:
				var total := 0
				for b in Game.bag:
					if shoppable(str(b.id)):
						total += sell_value(b)
				if Game.bag.is_empty():
					await RedText.say(root, K + "16", nm, sp, v)
				elif total <= 0:
					await RedText.say(root, K + "15", nm, sp, v)
				elif total + Game.money > MAX_MONEY:
					await RedText.say(root, K + "14", nm, sp, v)
				elif await RedText.ask(root, K + "10", nm, sp, _yn(), v.merged({"value0": total})) == 0:
					Game.bag = Game.bag.filter(func(b): return not shoppable(str(b.id)))
					Game.money += total
					Audio.sfx("332")
					await RedText.say(root, K + "11", nm, sp, v, "Happy")
			3:
				await RedText.say(root, K + "22", nm, sp, v)
		if TeamScreens.auto_on():
			return

## Treasure boxes (EoS: Xatu's appraisal, 150 Poké). The green Kecleon opens one box at a time.
static func _kec_open_box(root: Control, nm: String, sp: String) -> void:
	var fee := EosItems.APPRAISE_FEE
	await RedText.say(root, " Oh! A treasure box!\nI can open it for you for {COLOR CYAN}{VALUE_0}{RESET} {POKE}〜♪", nm, sp, {"value0": fee})
	while true:
		if _auto_spin():
			return
		var idx: Array = []
		var rows: Array = []
		for i in Game.bag.size():
			if EosItems.is_box(str(Game.bag[i].id)):
				idx.append(i)
				rows.append({"text": DB.item_name(str(Game.bag[i].id)), "right": str(fee)})
		if idx.is_empty():
			return
		var mb := _money_box(root)
		var r := await BaseMenu.paged(root, "", rows, 0, Vector2(2 * 8 * P, 2 * 8 * P), 8, 16 * 8 * P)
		TeamScreens._drop(mb)
		if r.act != "pick":
			return
		var bi: int = int(idx[int(r.i)])
		var box := str(Game.bag[bi].id)
		var c := await TeamScreens.submenu(root, null, ["Open", "Info"])
		if c == "Info":
			await TeamScreens.item_info(root, box)
			continue
		if c != "Open":
			continue
		if Game.money < fee:
			await RedText.say(root, " Oh... You don't have enough money\nfor that.", nm, sp)
			return
		if await RedText.ask(root, " Shall I open the {COLOR GREEN}{MOVE_ITEM_0}{RESET}\nfor {COLOR CYAN}{VALUE_0}{RESET} {POKE}?", nm, sp, _yn(), {"item0": DB.item_name(box), "value0": fee}) != 0:
			continue
		Game.money -= fee
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var got := EosItems.open_box(rng)
		Game.bag[bi] = {"id": got, "n": 1}         # the box's slot holds what was inside
		Audio.sfx("332")
		await RedText.say(root, " Here we go...!\nThe {COLOR GREEN}{MOVE_ITEM_0}{RESET} held\n{COLOR GREEN}{MOVE_ITEM_1}{RESET}!", nm, sp, {"item0": DB.item_name(box), "item1": DB.item_name(got)}, "Happy")
		Game.save_game()
		if not Game.bag.any(func(b): return EosItems.is_box(str(b.id))):
			return
		if Game.money < fee:
			return
		if await RedText.ask(root, " Shall I open another box?", nm, sp, _yn()) != 0:
			return
		if TeamScreens.auto_on():
			return

static func _kec_buy(root: Control, wares: bool, K: String, nm: String, sp: String, v: Dictionary) -> void:
	var start := 0
	while true:
		if _auto_spin():
			return
		var list := stock(wares)
		if list.is_empty():
			return
		var mb := _money_box(root)
		var r := await BaseMenu.paged(root, "", _price_rows(list, buy_value), start, Vector2(2 * 8 * P, 2 * 8 * P), 8, 16 * 8 * P)
		TeamScreens._drop(mb)
		if r.act != "pick":
			return
		start = int(r.i)
		var b: Dictionary = list[r.i]
		var c := await TeamScreens.submenu(root, null, ["Buy", "Info"])
		if c == "Info":
			await TeamScreens.item_info(root, str(b.id))
			continue
		if c != "Buy":
			continue
		var price := buy_value(b)
		if Game.money < price:
			await RedText.say(root, K + ("13" if Game.money == 0 else "19"), nm, sp, v)
			continue
		if await RedText.ask(root, K + "05", nm, sp, _yn(), v.merged({"item0": "[color=#7fff7f]%s[/color]" % DB.item_name(str(b.id)), "value0": price})) != 0:
			continue
		if not Game.bag_add(str(b.id), maxi(1, int(b.n))):
			await RedText.say(root, K + "17", nm, sp, v)
			return
		Game.money -= price
		list.erase(b)
		Audio.sfx("332")
		await RedText.say(root, K + "06", nm, sp, v, "Happy")
		if list.is_empty():
			await RedText.say(root, K + "18", nm, sp, v)
			return
		if Game.bag.size() >= Game.BAG_MAX:
			return
		await RedText.say(root, K + "04", nm, sp, v)
		if TeamScreens.auto_on():
			return

static func _kec_sell(root: Control, K: String, nm: String, sp: String, v: Dictionary) -> void:
	var start := 0
	while not Game.bag.is_empty():
		var mb := _money_box(root)
		var labels: Array = []
		var rights: Array = []
		for b0 in Game.bag:
			labels.append(DB.item_name(str(b0.id)) + (" %d" % int(b0.n) if int(b0.get("n", 1)) > 1 else ""))
			rights.append(str(sell_value(b0)) if shoppable(str(b0.id)) else "-")
		var marks := {}
		var r := await _multi_list(root, "", labels, marks, start, rights)     # L / R / Select mark several (Red)
		TeamScreens._drop(mb)
		if r.act != "pick":
			return
		start = int(r.i)
		if not (r.marks as Array).is_empty():
			var idx: Array = (r.marks as Array).duplicate()
			idx.sort()
			var total := 0
			var sell_idx: Array = []
			for i0 in idx:
				var bb: Dictionary = Game.bag[int(i0)]
				if shoppable(str(bb.id)):
					total += sell_value(bb)
					sell_idx.append(int(i0))
			if sell_idx.is_empty():
				await RedText.say(root, K + "20", nm, sp, v.merged({"item0": DB.item_name(str(Game.bag[int(idx[0])].id))}))
				continue
			if Game.money + total > MAX_MONEY:
				await RedText.say(root, K + "21", nm, sp, v)
				continue
			if await RedText.ask(root, K + "10", nm, sp, _yn(), v.merged({"value0": total})) != 0:
				continue
			sell_idx.reverse()
			for i1 in sell_idx:
				Game.bag.remove_at(int(i1))
			Game.money += total
			Audio.sfx("332")
			await RedText.say(root, K + "11", nm, sp, v, "Happy")
			if Game.bag.is_empty() or Game.money >= MAX_MONEY:
				return
			await RedText.say(root, K + "08", nm, sp, v)
			continue
		var b: Dictionary = Game.bag[r.i]
		var c := await TeamScreens.submenu(root, null, ["Sell", "Info"])
		if c == "Info":
			await TeamScreens.item_info(root, str(b.id))
			continue
		if c != "Sell":
			continue
		if not shoppable(str(b.id)):
			await RedText.say(root, K + "20", nm, sp, v.merged({"item0": DB.item_name(str(b.id))}))
			continue
		var val := sell_value(b)
		if Game.money + val > MAX_MONEY:
			await RedText.say(root, K + "21", nm, sp, v)
			continue
		if await RedText.ask(root, K + "09", nm, sp, _yn(), v.merged({"item0": "[color=#7fff7f]%s[/color]" % DB.item_name(str(b.id)), "value0": val})) != 0:
			continue
		Game.bag.remove_at(r.i)
		Game.money += val
		Audio.sfx("332")
		await RedText.say(root, K + "11", nm, sp, v, "Happy")
		if Game.bag.is_empty() or Game.money >= MAX_MONEY:
			return
		await RedText.say(root, K + "08", nm, sp, v)
		if TeamScreens.auto_on():
			return

# ============================================================================ number entry (sub_8013AA0)
## Red's number window: the digits of the amount, Up/Down changes the digit under the cursor, Left/Right
## moves the cursor, A accepts, B cancels. Starts at the maximum. Returns the amount or -1.
class NumberPicker extends PanelContainer:
	signal done(v: int)
	var prompt := ""
	var digits := 5
	var maxv := 99999
	var minv := 1
	var value := 0
	var cur := 0                    # digit index from the left
	var _lbl: RichTextLabel
	var _finished := false

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		TeamScreens._stack.append(self)
		tree_exiting.connect(func(): TeamScreens._stack.erase(self))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		if prompt != "":
			vb.add_child(TeamScreens._rtl(prompt))
		_lbl = TeamScreens._rtl("")
		vb.add_child(_lbl)
		value = maxv
		cur = digits - 1
		_show()
		if TeamScreens.auto_on():
			(func(): _finish(value)).call_deferred()

	func _show() -> void:
		var s := str(value).pad_zeros(digits)
		var out := ""
		for k in digits:
			out += ("[color=#ffdc4a][u]%s[/u][/color]" if k == cur else "%s") % s[k]
		_lbl.text = "[right]%s %s %s[/right]" % [TeamScreens.ARROW_U, out, TeamScreens.ARROW_D]

	func _step(d: int) -> void:
		var pw := int(pow(10, digits - 1 - cur))
		var nv := value + d * pw
		if nv > maxv:
			nv = minv if d > 0 and value == maxv else maxv
		elif nv < minv:
			nv = maxv if d < 0 and value == minv else minv
		value = nv
		Audio.sfx("cursor")
		_show()

	func _finish(v: int) -> void:
		if _finished:
			return
		_finished = true
		Audio.sfx("confirm" if v >= 0 else "cancel")
		done.emit(v)

	func _is_top() -> bool:
		return not TeamScreens._stack.is_empty() and TeamScreens._stack.back() == self

	func _unhandled_input(e: InputEvent) -> void:
		if _finished or not _is_top():
			return
		var vp := get_viewport()      # _finish() may free this node before we mark the event handled
		if e.is_action_pressed("ui_up", true) or e.is_action_pressed("move_up", true):
			_step(1)
		elif e.is_action_pressed("ui_down", true) or e.is_action_pressed("move_down", true):
			_step(-1)
		elif e.is_action_pressed("ui_left") or e.is_action_pressed("move_left"):
			cur = (cur - 1 + digits) % digits
			Audio.sfx("cursor")
			_show()
		elif e.is_action_pressed("ui_right") or e.is_action_pressed("move_right"):
			cur = (cur + 1) % digits
			Audio.sfx("cursor")
			_show()
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			_finish(value)
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			_finish(-1)
		else:
			return
		if vp:
			vp.set_input_as_handled()

	func _gui_input(e: InputEvent) -> void:
		# touch: upper half of the window raises the digit under the cursor, lower half lowers it; a tap on the
		# prompt line accepts, right click cancels; a horizontal tap position picks the digit
		if _finished or not _is_top():
			return
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_RIGHT:
				_finish(-1)
			elif e.button_index == MOUSE_BUTTON_LEFT:
				var lp: Vector2 = e.position
				if lp.y < size.y * 0.35:
					_finish(value)
				else:
					var w := size.x - 12 * P
					var k := clampi(int((lp.x - 6 * P) / w * (digits + 2)) - 1, 0, digits - 1)
					if k != cur:
						cur = k
						_show()
					else:
						_step(1 if lp.y < size.y * 0.7 else -1)
			accept_event()

static func pick_number(root: Control, prompt: String, maxv: int, digits := 5, at := Vector2(-1, -1)) -> int:
	if maxv <= 0:
		return -1
	if Dialog.auto or ListMenu.auto:       # automated runs: back out of the number window
		return -1
	var np := NumberPicker.new()
	np.prompt = prompt
	np.maxv = maxv
	np.digits = digits
	var bd := TeamScreens._backdrop(root, np)
	root.add_child(np)
	await root.get_tree().process_frame
	var vs := root.get_viewport_rect().size
	np.position = at if at.x >= 0 else Vector2(vs.x - np.size.x - 2 * 8 * P, 6 * 8 * P)
	var v: int = await np.done
	TeamScreens._drop(bd)
	TeamScreens._drop(np)
	return v

# ============================================================================ Felicity Bank
static func _bank_header(root: Control) -> PanelContainer:
	var w := PanelContainer.new()
	w.theme = UITheme.theme()
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6 * P)
	w.add_child(hb)
	hb.add_child(TeamScreens._rtl("%s[color=#7fe0ff]%d[/color]" % [RedText.get_text("felicity_bank:sDisplayMoney"), Game.money]))
	hb.add_child(TeamScreens._rtl("%s[color=#7fe0ff]%d[/color]" % [RedText.get_text("felicity_bank:sDisplaySavings"), Game.bank]))
	root.add_child(w)
	w.position = Vector2(2 * 8 * P, 2 * 8 * P)
	w.custom_minimum_size.x = 26 * 8 * P
	return w

static func bank(root: Control) -> void:
	var mode := "ASLEEP" if asleep() else "AWAKE"
	var F := "FEL_%s_" % mode
	var sp := "" if asleep() else "0053"
	var nm: String = str(DB.species.get("0053", {}).get("name", "Persian"))
	await RedText.say(root, F + "WELCOME", nm, sp)
	var sel := 0
	while true:
		if _auto_spin():
			return
		var hdr := _bank_header(root)
		var serve := F + ("HOW_MAY_I_SERVE__HAS_MONEY" if Game.bank > 0 else "HOW_MAY_I_SERVE__NO_MONEY")
		var c := await RedText.ask(root, serve, nm, sp, ["Store", "Take", "Info", "Cancel"], {"value0": Game.bank}, sel)
		TeamScreens._drop(hdr)
		if c < 0 or c == 3:
			var bye := F + ("BYE__HAS_MONEY" if Game.bank > 0 else "BYE__NO_MONEY")
			if not RedText.has(bye):
				bye = "FEL_ASLEP_BYE__HAS_MONEY"
			await RedText.say(root, bye, nm, sp)
			Game.save_game()
			return
		sel = c
		match c:
			0:
				if Game.money <= 0:
					await RedText.say(root, F + "DEPOSIT__NO_MONEY", nm, sp)
				elif Game.bank >= MAX_SAVINGS:
					await RedText.say(root, F + "DEPOSIT__BANK_FULL", nm, sp)
				else:
					await RedText.say(root, F + "DEPOSIT__HOW_MUCH", nm, sp)
					var h := _bank_header(root)
					var amt := await pick_number(root, RedText.get_text("common_strings:sDepositPrompt0"), mini(MAX_SAVINGS - Game.bank, Game.money))
					TeamScreens._drop(h)
					if amt > 0:
						Services.bank_move(true, amt)
						Audio.sfx("332")
						await RedText.say(root, F + "DEPOSIT__RECEIPT", nm, sp)
					else:
						await RedText.say(root, F + "VERY_WELL", nm, sp)
			1:
				if Game.money >= MAX_MONEY:
					await RedText.say(root, F + "WITHDRAW__WALLET_FULL", nm, sp)
				elif Game.bank <= 0:
					await RedText.say(root, F + "WITHDRAW__NO_MONEY", nm, sp)
				else:
					await RedText.say(root, F + "WITHDRAW__HOW_MUCH", nm, sp)
					var h2 := _bank_header(root)
					var amt2 := await pick_number(root, RedText.get_text("common_strings:sWithdrawPrompt0"), mini(MAX_MONEY - Game.money, Game.bank))
					TeamScreens._drop(h2)
					if amt2 > 0:
						Services.bank_move(false, amt2)
						Audio.sfx("332")
						await RedText.say(root, F + "WITHDRAW__RECEIPT", nm, sp)
					else:
						await RedText.say(root, F + "VERY_WELL", nm, sp)
			2:
				await RedText.say(root, F + "HOW_IT_WORKS", nm, sp)
		if TeamScreens.auto_on():
			return

# ============================================================================ Kangaskhan Storage
static func storage(root: Control) -> void:
	var mode := "ASLEEP" if asleep() else "AWAKE"
	var KA := "KANG_%s_" % mode
	var sp := "" if asleep() else "0115"
	var nm: String = str(DB.species.get("0115", {}).get("name", "Kangaskhan"))
	var v := {"mon6": "[color=#ffdc4a]%s[/color]" % nm}
	var first := true
	var sel := 0
	while true:
		if _auto_spin():
			return
		var c := await RedText.ask(root, KA + ("WELCOME" if first else "ANYTHING_ELSE"), nm, sp, ["Store", "Take", "Info", "Cancel"], v, sel)
		first = false
		if c < 0 or c == 3:
			await RedText.say(root, KA + "BYE", nm, sp, v, "Happy")
			Game.save_game()
			return
		sel = c
		match c:
			0:
				if Game.bag.is_empty():
					await RedText.say(root, KA + "YOU_HAVE_NOTHING", nm, sp, v)
				else:
					await RedText.say(root, KA + "STORE_WHAT", nm, sp, v)
					await _kang_store(root, KA, nm, sp, v)
			1:
				if _storage_ids().is_empty():
					await RedText.say(root, KA + ("STORAGE_HAS_NOTHING" if RedText.has(KA + "STORAGE_HAS_NOTHING") else "STORAGE_EMPTY"), nm, sp, v)
				elif Game.bag.size() >= Game.BAG_MAX:
					await RedText.say(root, KA + "YOU_ARE_FULL", nm, sp, v)
				else:
					await RedText.say(root, KA + "TAKE_WHAT", nm, sp, v)
					await _kang_take(root, KA, nm, sp, v)
			2:
				await RedText.say(root, KA + "HOW_IT_WORKS", nm, sp, v)
		if TeamScreens.auto_on():
			return

static func _storage_ids() -> Array:
	var ids: Array = []
	for id in Game.storage:
		if int(Game.storage[id]) > 0 and DB.items.has(id):
			ids.append(id)
	ids.sort_custom(func(a, b): return int(DB.items[a].get("red_id", 999)) < int(DB.items[b].get("red_id", 999)))
	return ids

## A list where Select (or the "Mark" command) marks several rows, as Red's L / R. Returns
## {act: "pick"|"cancel", i, marks: Array of indices}.
static func _multi_list(root: Control, title: String, labels: Array, marks: Dictionary, start: int, rights: Array = []) -> Dictionary:
	var per := 8
	var pages := maxi(1, ceili(labels.size() / float(per)))
	var page := clampi(start / per, 0, pages - 1)
	var sel := start % per
	while true:
		if _auto_spin():
			return {"act": "cancel", "i": -1, "marks": []}
		var rows: Array = []
		for k in range(page * per, mini(labels.size(), (page + 1) * per)):
			var row := {"text": str(labels[k]), "marked": marks.has(k)}      # Red: a highlight bar, not an icon
			if k < rights.size():
				row["right"] = str(rights[k])
			rows.append(row)
		var m := TeamScreens.menu(title, rows, 16 * 8 * P)
		m.pages = pages
		m.page = page
		m.sel = mini(sel, rows.size() - 1)
		m.select_key = true
		m.shift_keys = false
		m.mark_touch = true          # touch: hold an item to mark it, then taps toggle (Red's L / R)
		if marks.is_empty():
			m.footer = [["Hold an item to mark several", ""]]
		else:
			m.footer = [["Done (%d)" % marks.size(), "done"], ["Mark all" if marks.size() < labels.size() else "Clear", "mark_all"]]
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		sel = int(r.get("i", sel))
		match str(r.act):
			"done":
				var ks: Array = marks.keys()
				ks.sort()
				return {"act": "pick", "i": int(ks[0]), "marks": ks}
			"mark_all":
				if marks.size() < labels.size():
					for k3 in labels.size():
						marks[k3] = true
				else:
					marks.clear()
			"left":
				page = (page - 1 + pages) % pages
				sel = 0
			"right":
				page = (page + 1) % pages
				sel = 0
			"select":
				var k2 := page * per + sel
				if marks.has(k2):
					marks.erase(k2)
				else:
					marks[k2] = true
			"pick":
				return {"act": "pick", "i": page * per + sel, "marks": marks.keys()}
			_:
				return {"act": "cancel", "i": -1, "marks": []}
	return {"act": "cancel", "i": -1, "marks": []}

static func _kang_store(root: Control, KA: String, nm: String, sp: String, v: Dictionary) -> void:
	var start := 0
	while not Game.bag.is_empty():
		var labels: Array = []
		for b in Game.bag:
			labels.append(BaseMenu._bag_label(b))
		var marks := {}
		var r := await _multi_list(root, "", labels, marks, start)
		if r.act != "pick":
			return
		start = int(r.i)
		var picks: Array = r.marks if r.marks.size() > 0 else [r.i]
		var c := await TeamScreens.submenu(root, null, ["Store", "Info"] + (["Mark"] if r.marks.is_empty() else []))
		if c == "Info":
			await TeamScreens.item_info(root, str(Game.bag[r.i].id))
			continue
		if c == "Mark":
			marks[r.i] = true
			var r2 := await _multi_list(root, "", labels, marks, start)
			if r2.act != "pick":
				continue
			picks = r2.marks if r2.marks.size() > 0 else [r2.i]
		elif c != "Store":
			continue
		var bad := false
		for k in picks:
			var id := str(Game.bag[k].id)
			if id == "poke" or id == "usedtm":
				await RedText.say(root, KA + "DEPOSIT_INVALID_ITEM", nm, sp, v.merged({"item0": DB.item_name(id)}))
				bad = true
				break
			if int(Game.storage.get(id, 0)) >= STORAGE_MAX:
				await RedText.say(root, KA + "DEPOSIT_TOO_MANY_OF_ITEM", nm, sp, v.merged({"item0": DB.item_name(id)}))
				bad = true
				break
		if bad:
			continue
		var key := KA + ("DEPOSIT_ONE_PROMPT" if picks.size() == 1 else "DEPOSIT_MANY_PROMPT")
		if await RedText.ask(root, key, nm, sp, _yn(), v.merged({"item0": DB.item_name(str(Game.bag[picks[0]].id))})) != 0:
			continue
		picks.sort()
		picks.reverse()
		for k in picks:
			var b: Dictionary = Game.bag[k]
			Game.storage[b.id] = mini(STORAGE_MAX, int(Game.storage.get(b.id, 0)) + maxi(1, int(b.n)))
			Game.bag.remove_at(k)
		Audio.sfx("333")
		await RedText.say(root, KA + "DEPOSIT_CONFIRMATION", nm, sp, v, "Happy")
		if Game.bag.is_empty():
			return
		await RedText.say(root, KA + "STORE_MORE", nm, sp, v)
		if TeamScreens.auto_on():
			return

static func _kang_take(root: Control, KA: String, nm: String, sp: String, v: Dictionary) -> void:
	var start := 0
	while true:
		if _auto_spin():
			return
		var ids := _storage_ids()
		if ids.is_empty() or Game.bag.size() >= Game.BAG_MAX:
			return
		var labels: Array = []
		for id in ids:
			labels.append("%s  %d" % [DB.item_name(id), int(Game.storage[id])])
		var marks := {}
		var r := await _multi_list(root, "", labels, marks, start)
		if r.act != "pick":
			return
		start = int(r.i)
		var picks: Array = r.marks if r.marks.size() > 0 else [r.i]
		var c := await TeamScreens.submenu(root, null, ["Take", "Info"])
		if c == "Info":
			await TeamScreens.item_info(root, str(ids[r.i]))
			continue
		if c != "Take":
			continue
		var qty := {}
		if picks.size() == 1:
			var id0: String = ids[picks[0]]
			if DB.items.get(id0, {}).get("stack", false):
				var q := await pick_number(root, RedText.get_text("kangaskhan_storage1:sNumber") if RedText.has("kangaskhan_storage1:sNumber") else "Number?", mini(99, int(Game.storage[id0])), 2)
				if q <= 0:
					continue
				qty[id0] = q
		var key := KA + ("WITHDRAW_ONE_PROMPT" if picks.size() == 1 else "WITHDRAW_MANY_PROMPT")
		if await RedText.ask(root, key, nm, sp, _yn(), v.merged({"item0": DB.item_name(str(ids[picks[0]]))})) != 0:
			continue
		for k in picks:
			var id: String = ids[k]
			var stack: bool = DB.items.get(id, {}).get("stack", false)
			var n: int = int(qty.get(id, mini(99, int(Game.storage[id])) if stack else 1))
			if not Game.bag_add(id, n):
				break
			Game.storage[id] = int(Game.storage[id]) - n
			if int(Game.storage[id]) <= 0:
				Game.storage.erase(id)
		Audio.sfx("333")
		await RedText.say(root, KA + "WITHDRAW_CONFIRMATION", nm, sp, v, "Happy")
		if _storage_ids().is_empty() or Game.bag.size() >= Game.BAG_MAX:
			return
		await RedText.say(root, KA + "TAKE_MORE", nm, sp, v)
		if TeamScreens.auto_on():
			return

# ============================================================================ Wigglytuff Club
static func shop_areas() -> Array:
	var keys: Array = []
	var areas: Dictionary = Services.fa().get("areas", {})
	for k in areas:
		var a: Dictionary = areas[k]
		if k in Game.friend_areas:
			continue
		if a.how == "Shop Story" or (a.how == "Shop Post Game" and postgame()):
			keys.append(k)
	return keys

static func wigglytuff(root: Control) -> void:
	var mode := "ASLEEP" if asleep() else "AWAKE"
	var W := "WIGGLY_%s_DLG_" % mode
	var sp := "" if asleep() else "0040"
	var nm: String = str(DB.species.get("0040", {}).get("name", "Wigglytuff"))
	var v := {"mon6": "[color=#ffdc4a]%s[/color]" % nm}
	var first := true
	var sel := 0
	while true:
		if _auto_spin():
			return
		var c := await RedText.ask(root, W + ("00" if first else "01"), nm, sp, ["Buy", "Check", "Info", "Cancel"], v, sel)
		first = false
		if c < 0 or c == 3:
			await RedText.say(root, W + "02", nm, sp, v, "Happy")
			Game.save_game()
			return
		sel = c
		match c:
			0:
				if Game.friend_areas.size() >= Services.fa().get("areas", {}).size():
					await RedText.say(root, W + "08", nm, sp, v)
				elif shop_areas().is_empty():
					await RedText.say(root, W + "10", nm, sp, v)
				elif Game.money <= 0:
					await RedText.say(root, W + "09", nm, sp, v)
				else:
					await RedText.say(root, W + "03", nm, sp, v)
					await _wiggly_buy(root, W, nm, sp, v)
			1:
				await RedText.say(root, W + "12", nm, sp, v)
				await _wiggly_check(root, W, nm, sp, v)
			2:
				await RedText.say(root, W + "19", nm, sp, v)
		if TeamScreens.auto_on():
			return

static func _wiggly_buy(root: Control, W: String, nm: String, sp: String, v: Dictionary) -> void:
	var start := 0
	while true:
		if _auto_spin():
			return
		var keys := shop_areas()
		if keys.is_empty():
			await RedText.say(root, W + "10", nm, sp, v)
			return
		var rows: Array = []
		for k in keys:
			rows.append({"text": Services.area_name(k), "right": str(int(Services.fa().areas[k].price))})
		var mb := _money_box(root, Vector2(root.get_viewport_rect().size.x - 9 * 8 * P - 8 * P, 2 * 8 * P))
		var r := await BaseMenu.paged(root, "", rows, start, Vector2(2 * 8 * P, 2 * 8 * P), 8, 17 * 8 * P)    # wigglytuff_shop1.h: 17 tiles
		TeamScreens._drop(mb)
		if r.act != "pick":
			return
		start = int(r.i)
		var k: String = keys[r.i]
		var c := await TeamScreens.submenu(root, null, ["Buy", "Info"])
		if c == "Info":
			await fa_info_screen(root, k)
			continue
		if c != "Buy":
			continue
		var price := int(Services.fa().areas[k].price)
		var fv := v.merged({"friend_area": "[color=#7fff7f]%s[/color]" % Services.area_name(k), "value0": price})
		if await RedText.ask(root, W + "05", nm, sp, _yn(), fv) != 0:
			continue
		if Game.money < price:
			await RedText.say(root, W + "11", nm, sp, v)
			continue
		Game.money -= price
		Game.friend_areas.append(k)
		Audio.sfx("332")
		await RedText.say(root, W + "06", nm, sp, fv, "Happy")
		Audio.sfx("206")
		await RedText.say(root, W + "07", nm, sp, fv, "Happy")
		Game.save_game()
		if shop_areas().is_empty():
			return
		await RedText.say(root, W + "04", nm, sp, v)
		if TeamScreens.auto_on():
			return

static func _wiggly_check(root: Control, W: String, nm: String, sp: String, v: Dictionary) -> void:
	var seen: Array = []
	for s in Pokedex.seen_dict():
		var a := Services.area_of(str(s))
		if a != "" and DB.species.has(str(s)):
			seen.append(str(s))
	seen.sort()
	if seen.is_empty():
		return
	var start := 0
	while true:
		if _auto_spin():
			return
		var rows: Array = []
		for s in seen:
			rows.append({"text": str(DB.species[s].name)})
		var r := await BaseMenu.paged(root, "", rows, start, Vector2(2 * 8 * P, 2 * 8 * P), 8, 14 * 8 * P)
		if r.act != "pick":
			return
		start = int(r.i)
		var s2: String = seen[r.i]
		var k := Services.area_of(s2)
		var fv := v.merged({"mon0": str(DB.species[s2].name), "friend_area": "[color=#7fff7f]%s[/color]" % Services.area_name(k)})
		await RedText.say(root, W + "14", nm, sp, fv)
		var a: Dictionary = Services.fa().areas.get(k, {})
		if k in Game.friend_areas:
			await RedText.say(root, W + "15", nm, sp, fv)
		elif str(a.get("how", "")) == "Shop Post Game" and not postgame():
			await RedText.say(root, W + "16", nm, sp, fv)
		elif str(a.get("how", "")) == "Wonder Mail":
			await RedText.say(root, W + "17", nm, sp, fv)
		elif str(a.get("how", "")) == "Legendary Request":
			await RedText.say(root, W + "18", nm, sp, fv)
		await RedText.say(root, W + "13", nm, sp, v)
		if TeamScreens.auto_on():
			return

## wigglytuff_shop2.c: the Friend Area's name, description and inhabitants (??? unseen, names seen,
## recruited ones in light blue) - also the base menu's Info in a Friend Area. Like Red (sub_8021A60) only
## base species are listed and an evolved Pokémon counts for its base form. Red fits 16 names in one window;
## the remake has more species per area, so 12 go on a page and Left / Right shows the rest.
static var _prevo := {}

static func base_species(sp: String) -> String:
	if _prevo.is_empty():
		var f := FileAccess.open("res://data/evo.json", FileAccess.READ)
		var evo = JSON.parse_string(f.get_as_text()) if f else {}
		if evo is Dictionary:
			for src in evo:
				for e in evo[src]:
					var t := str(e[0]).substr(0, 4)
					if not _prevo.has(t):
						_prevo[t] = str(src).substr(0, 4)
		_prevo["_"] = ""
	var s := sp.substr(0, 4)
	for guard in 4:
		if not _prevo.has(s):
			break
		s = str(_prevo[s])
	return s

static func fa_info_screen(root: Control, k: String) -> void:
	var a: Dictionary = Services.fa().get("areas", {}).get(k, {})
	if a.is_empty():
		return
	var seen := {}
	for s in Pokedex.seen_dict():
		seen[base_species(str(s))] = true
	var rec := {}
	for e in Game.friends + Game.team:
		rec[base_species(str(e.get("sp", "")))] = true
	var cells: Array = []
	for s in a.get("species", []):
		if base_species(str(s)) != str(s):
			continue
		var t := "???"
		if rec.has(str(s)):
			t = "[color=#7fe0ff]%s[/color]" % DB.species.get(s, {}).get("name", "?")
		elif seen.has(str(s)):
			t = str(DB.species.get(s, {}).get("name", "?"))
		cells.append(t)
	var head := RedText.line(RedText.get_text("wigglytuff_shop2:sUnknown_80DC4F0" if k in Game.friend_areas else "wigglytuff_shop2:sInhabitants"))
	var desc := UITheme.red_text(str(a.get("desc", "")))
	const PER := 12
	var pg := TeamScreens.InfoPage.new()
	pg.width = 26 * 8 * P
	pg.count = maxi(1, ceili(cells.size() / float(PER)))
	pg.builder = func(i): return {"title": Services.area_name(k),
		"parts": [desc, "\n", head + "\n", {"table": 3, "cells": _grid_cells(cells.slice(i * PER, (i + 1) * PER))}]}
	await TeamScreens.run_page(root, pg, Vector2(2 * 8 * P, 1 * 8 * P))

## Red prints the names on a fixed grid (x = col * 63 + 7): an invisible 63 px strip above the first row's
## cells keeps every column that wide.
static var _strip: Texture2D

static func _grid_cells(cells: Array) -> Array:
	if _strip == null:
		var im := Image.create(63 * P, 1, false, Image.FORMAT_RGBA8)
		_strip = ImageTexture.create_from_image(im)
	var out: Array = []
	for n in cells.size():
		out.append([_strip, "\n", cells[n]] if n < 3 else cells[n])
	return out

## automated runs (menus answer themselves): a shop loop that keeps re-asking (e.g. "not enough money")
## leaves after a few rounds instead of spinning forever
static var _spins := 0
static func _auto_spin() -> bool:
	if not (TeamScreens.auto_on() or Dialog.auto):
		return false
	_spins += 1
	return _spins % 6 == 0
