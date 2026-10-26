extends Node
## Town QoL visual test (run: xvfb-run ... godot --path . --rendering-driver opengl3 --resolution 1440x810 -- --towntest2).
## Drives the real UI with simulated input and saves screenshots to user://t2_*.png:
## prepare screen (through the world map), Pokédex list + entry, bank / storage / Kecleon bulk actions,
## board "Accept all" + Job List "Take all suspended", and a quicksave -> title -> resume round trip.
## The real save file and suspend file are backed up and restored.

var main: Node
var root: Control
var shot_n := 0
var fails := 0
var _backup := ""
var _sus_backup := ""

func _ready() -> void:
	main = get_parent()
	root = main.root
	_run.call_deferred()

func ok(c: bool, msg: String) -> void:
	print(("PASS " if c else "FAIL ") + msg)
	if not c:
		fails += 1

func _shot(n: String) -> void:
	await get_tree().create_timer(0.35).timeout
	var path := "user://t2_%02d_%s.png" % [shot_n, n]
	shot_n += 1
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path))

func _press(a: String, n := 1) -> void:
	for i in n:
		await main._mt_press(a)

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _run() -> void:
	if FileAccess.file_exists(Game.SAVE_PATH):
		_backup = FileAccess.get_file_as_string(Game.SAVE_PATH)
	if DungeonSave.has_suspend():
		_sus_backup = FileAccess.get_file_as_string(DungeonSave.PATH)
	DungeonSave.clear()
	Dialog.auto = false
	ListMenu.auto = false
	Game.new_game("0258", "Mudkip", "0255", "Torchic", "QoL")
	Game.money = 1234
	Game.bank = 500
	Game.cleared = ["tiny_woods", "thunderwave_cave", "mt_steel"]
	Game.unlocked = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods"]
	Game.friend_areas = ["flyaway", "jungle"]
	Game.friends = [{"sp": "0016", "name": "Pidgey", "level": 6, "exp": DB.exp_at("0016", 6), "moves": DB.default_moves("0016", 6), "iq": 0, "held": "", "bonus": {}, "area": Services.area_of("0016")}]
	Game.flags["seen"] = {"0016": true, "0191": true, "0265": true, "0081": true, "0025": true}
	for id in ["oran", "apple", "apple", "apple", "pecha", "sleepseed", "blastseed"]:
		Game.bag_add(id)
	Game.bag_add("stick", 9)
	Game.storage = {"oran": 3, "gravelerock": 30, "reviverseed": 1}
	Game.board_day = -1
	Missions.refresh_board_if_new_day()
	start_town_bg()
	await _wait(1.5)
	# The old bulk bank / storage / Kecleon menus were replaced by Red's own shops (scripts/town/red_shops.gd);
	# those are checked by tests/test_townmenus.gd (--townmenutest), so _bank / _storage / _kecleon no longer run.
	await _board()
	await _prepare()
	await _pokedex()
	await _quicksave_resume()
	_finish()

func start_town_bg() -> void:
	main.start_town("base")

func _paused(on: bool) -> void:
	if is_instance_valid(main.town):
		main.town.set_paused(on)

# ------------------------------------------------------------------ UI helpers (robust against typing timing)
func _top_menu() -> ListMenu:
	var m: ListMenu = null
	for c in root.get_children():
		if c is ListMenu and not c.is_queued_for_deletion() and not c._done:
			m = c
	return m

func _dialog() -> Dialog:
	for c in root.get_children():
		if c is Dialog and not c.is_queued_for_deletion():
			return c
	return null

## Wait until a menu is up (advancing text boxes on the way), then pick the option starting with `txt`.
func _pick(txt: String) -> bool:
	for k in 40:
		var m := _top_menu()
		if m:
			for i in m.options.size():
				if str(m.options[i].text).begins_with(txt):
					m._set_sel(i)
					await _wait(0.05)
					m._click(i)
					await _wait(0.25)
					return true
			print("  (no option ", txt, " in ", m.options.map(func(o): return o.text), ")")
			return false
		await _adv_once()
	return false

func _adv_once() -> void:
	var d := _dialog()
	if d and d.panel.visible and _top_menu() == null:
		d._finish_typing()
		d._advance.emit()
	await _wait(0.12)

## Cancel menus / advance text until nothing is open.
func _drain() -> void:
	var quiet := 0
	for k in 60:
		var m := _top_menu()
		var d := _dialog()
		if m:
			m._finish(-1)
			quiet = 0
		elif d and d.panel.visible:
			d._finish_typing()
			d._advance.emit()
			quiet = 0
		else:
			quiet += 1
			if quiet >= 3:
				return
		await _wait(0.12)

## Text box up and fully typed (for screenshots of messages).
func _typed() -> void:
	for k in 30:
		var d := _dialog()
		if d and d.panel.visible:
			d._finish_typing()
			return
		await _wait(0.1)

# ------------------------------------------------------------------ bank / storage / Kecleon
func _bank() -> void:
	_paused(true)
	var m0: int = Game.money
	Services.bank(root)
	await _wait(0.4)
	_dialog()._finish_typing()
	await _shot("bank_menu")
	await _pick("Deposit all")
	await _typed()
	await _shot("bank_deposit_all")
	ok(Game.money == 0 and Game.bank == 500 + m0, "Deposit all moved %d Poké" % m0)
	await _pick("Withdraw all")
	ok(Game.bank == 0 and Game.money == 500 + m0, "Withdraw all")
	await _drain()

func _storage() -> void:
	var nbag: int = Game.bag.size()
	Services.storage(root)
	await _pick("Store all")
	ok(Game.bag.is_empty() and int(Game.storage.get("apple", 0)) == 3, "Store all (%d slots)" % nbag)
	await _pick("Take all")
	await _typed()
	await _shot("storage_take_all")
	ok(Game.bag.size() == Game.BAG_MAX or Game.storage.is_empty(), "Take all filled the Toolbox (%d/%d, left %s)" % [Game.bag.size(), Game.BAG_MAX, Game.storage])
	await _adv_once()
	await _wait(0.3)
	_dialog()._finish_typing()
	await _shot("storage_menu")
	await _drain()
	Game.bag = []
	for id in ["oran", "apple", "apple", "apple", "pecha", "sleepseed", "blastseed"]:
		Game.bag_add(id)
	Game.bag_add("stick", 9)

func _kecleon() -> void:
	var m0: int = Game.money
	RedShops.kecleon(root)    # Red's Kecleon (Sell / Sell All); the old bulk-sell menu is gone
	await _pick("Apple")
	await _wait(0.2)
	_dialog()._finish_typing()
	await _shot("kecleon_sell_all_kind")
	await _pick("Sell all 3:")
	ok(Services.slots_of("apple").is_empty() and Game.money > m0, "Sell all of a kind (apples)")
	await _pick("Sell several")
	var n0: int = Game.bag.size()
	await _pick("[ ] Pecha")
	await _pick("[ ] Sleep")
	await _shot("kecleon_sell_several")
	await _pick("Sell marked (2)")
	await _pick("Sell")
	await _drain()
	ok(Game.bag.size() == n0 - 2, "Sell several sold 2 items (%d -> %d)" % [n0, Game.bag.size()])

# ------------------------------------------------------------------ board
func _board() -> void:
	Game.jobs = []
	var cnt := {}
	for j in Game.board:
		cnt[j.dungeon] = int(cnt.get(j.dungeon, 0)) + 1
	var best := ""
	for k in cnt:
		if best == "" or cnt[k] > cnt[best]:
			best = k
	var idx := -1
	for i in Game.board.size():
		if Game.board[i].dungeon == best:
			idx = i
			break
	print("board: ", cnt, " best ", best, " idx ", idx)
	Board.open_board(root)
	await _wait(0.4)
	await _press("ui_down", idx)
	await _press("ui_accept")
	await _wait(0.3)
	_top_menu()._set_sel(1)
	await _shot("board_accept_all_menu")
	await _pick("Accept all")
	await _wait(0.2)
	await _shot("board_accept_all_ask")
	var got: int = Game.jobs.filter(func(j): return j.dungeon == best).size()
	ok(got == mini(cnt[best], Missions.MAX_JOBS), "Accept all for %s: %d jobs" % [best, got])
	ok(Game.jobs.all(func(j): return j.state == "suspended"), "accepted jobs are suspended until taken (Red)")
	await _pick("Not now")
	await _drain()
	Board.open_job_list(root)
	await _wait(0.4)
	await _press("ui_accept")
	await _wait(0.3)
	await _shot("joblist_take_all_menu")
	await _pick("Take all suspended")
	await _wait(0.2)
	ok(Game.jobs.all(func(j): return j.state == "taken"), "Take all suspended")
	await _adv_once()
	await _adv_once()
	await _wait(0.3)
	await _shot("joblist_taken")
	await _drain()
	# Red's 8-job limit
	for k in cnt:
		Missions.accept_all_for(k)
	ok(Game.jobs.size() <= Missions.MAX_JOBS, "accept_all_for keeps the 8-job limit (%d)" % Game.jobs.size())
	Missions.take_all_suspended()

# ------------------------------------------------------------------ prepare screen (through the real world-map flow)
func _prepare() -> void:
	_paused(false)
	var k: String = Game.jobs[0].dungeon if not Game.jobs.is_empty() else "thunderwave_cave"
	if not k in Game.unlocked:
		Game.unlocked.append(k)
	main._on_town_exit("world_map")
	await _wait(0.4)
	var keys: Array = []
	for d in Services.STORY_ORDER:
		if d in Game.unlocked:
			keys.append(d)
	for d in Game.unlocked:
		if not d in Services.STORY_ORDER:
			keys.append(d)
	await _press("ui_down", keys.find(k))
	await _press("ui_accept")
	await _wait(0.5)
	var pv: Control = null
	for c in root.get_children():
		if c is PrepareScreen.PrepView:
			pv = c
	ok(pv != null, "prepare screen opened for %s" % k)
	await _shot("prepare")
	await _press("ui_right", 2)
	await _press("ui_accept")           # Storage
	await _wait(0.4)
	await _pick("Leave")
	for n in 6:
		await _adv_once()
	await _wait(0.5)
	ok(root.get_children().any(func(c): return c is PrepareScreen.PrepView), "back on the prepare screen after Storage")
	await _press("ui_cancel")           # Cancel -> world map again
	await _wait(0.4)
	ok(root.get_children().any(func(c): return c is ListMenu), "Cancel returns to the world map")
	await _press("ui_cancel")
	await _wait(0.4)

# ------------------------------------------------------------------ Pokédex
func _pokedex() -> void:
	_paused(true)
	main._on_town_menu()
	await _wait(0.4)
	await _press("ui_down", 3)
	await _shot("base_menu")
	await _press("ui_accept")           # Pokédex
	await _wait(0.3)
	await _shot("dex_filters")
	await _press("ui_accept")           # All
	await _wait(0.4)
	await _press("ui_down", 15)          # #016 Pidgey (recruited)
	await _shot("dex_list")
	await _press("ui_right")
	await _wait(0.2)
	await _shot("dex_list_p3")
	await _press("ui_left")
	await _press("ui_accept")
	await _wait(0.4)
	await _shot("dex_entry")
	await _press("ui_right")
	await _wait(0.4)
	await _shot("dex_entry_where")
	await _press("ui_down")             # next species (unseen)
	await _wait(0.4)
	await _shot("dex_entry_unseen")
	await _press("ui_cancel")
	await _wait(0.3)
	await _press("ui_cancel")
	await _wait(0.3)
	await _press("ui_down", 3)           # By dungeon
	await _press("ui_accept")
	await _wait(0.3)
	await _press("ui_down")
	await _press("ui_accept")           # Thunderwave Cave
	await _wait(0.4)
	await _shot("dex_by_dungeon")
	await _press("ui_cancel")
	await _wait(0.3)
	await _press("ui_cancel")
	await _wait(0.3)
	await _press("ui_cancel")           # close base menu
	await _wait(0.4)
	var c := Pokedex.counts()
	ok(c.recruited >= 3 and c.seen >= 6, "Pokédex counts seen %d recruited %d" % [c.seen, c.recruited])
	ok(Pokedex.recommended_level("thunderwave_cave") > 0, "recommended level %d" % Pokedex.recommended_level("thunderwave_cave"))
	ok(Pokedex.locations("0016").size() > 0, "Pidgey locations %s" % [Pokedex.locations("0016").map(func(l): return l.dkey)])

# ------------------------------------------------------------------ quicksave -> resume
func _quicksave_resume() -> void:
	await main.start_dungeon("thunderwave_cave")
	await _wait(0.5)
	var d: Dungeon = main.dungeon
	d.auto_answer = true
	for i in 4:
		await d.leader_action({"type": "wait"})
	var L: Mon = d.fs.leader
	var before := {"pos": L.pos, "turn": d.fs.turn, "floor": d.floor_i, "mons": d.fs.mons.size(), "hp": L.hp, "stairs": d.fs.stairs, "terrain": d.fs.terrain.duplicate()}
	await _shot("dungeon_before_quicksave")
	Dialog.auto = true
	DungeonSave.save_and_quit(d)
	await _wait(1.5)
	Dialog.auto = false
	ok(DungeonSave.has_suspend(), "quicksave wrote the suspend file")
	var tm: ListMenu = null
	for c in root.get_children():
		if c is ListMenu:
			tm = c
	ok(tm != null and str(tm.options[0].text).begins_with("Resume"), "title shows Resume: %s" % (tm.options[0].text if tm else "-"))
	await _shot("title_resume")
	await _press("ui_accept")
	await _wait(2.2)
	var d2: Dungeon = main.dungeon
	ok(d2 != null and d2 != d, "resumed into a new Dungeon")
	if d2:
		ok(d2.fs.leader.pos == before.pos and d2.fs.turn == before.turn and d2.floor_i == before.floor and d2.fs.mons.size() == before.mons and d2.fs.leader.hp == before.hp, "resumed state matches (pos/turn/floor/mons/hp)")
		ok(d2.fs.stairs == before.stairs and d2.fs.terrain == before.terrain, "same floor layout")
		ok(not DungeonSave.has_suspend(), "suspend file deleted after resume")
		ok(not d2.busy, "resumed dungeon accepts input")
		await _shot("dungeon_resumed")
		var t0: int = d2.fs.turn
		d2.auto_answer = true
		await d2.leader_action({"type": "wait"})
		ok(d2.fs.turn == t0 + 1, "resumed dungeon plays on")

func _finish() -> void:
	DungeonSave.clear()
	if _backup != "":
		var f := FileAccess.open(Game.SAVE_PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	if _sus_backup != "":
		var f2 := FileAccess.open(DungeonSave.PATH, FileAccess.WRITE)
		f2.store_string(_sus_backup)
		f2.close()
	print("TOWNTEST2 done, %d failed" % fails)
	get_tree().quit()
