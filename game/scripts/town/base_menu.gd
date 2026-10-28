class_name BaseMenu
extends RefCounted
## Red's base menu (code_801D014.c sub_801D014): B / Start in town and on the ground.
##   Town:        Items / Team / Job List / Others, with the side windows of sub_801D894: the place name
##                (centred), the team-rank badge (tmrkpat) + "<Rank> N Pts." and "Money: N".
##   Friend Area: Friend / Items / Info / Exit (the area's name in the place window).
##   Others:      Game Options / Hints (options_menu1.c), plus the remake's Pokédex / Save / Title screen.
## The team list follows friend_list_menu.c (Give / Take / Stand By / Summary / Moves / Check IQ) and the
## menu of a Friend Area resident follows party_list_menu.c (Stand By / Make Leader / Join Team /
## Give Gummi / Give / Take / Say Farewell / Summary / Moves / Check IQ, with the "Item:" window).
##
##   var r := await BaseMenu.open(host, root)          # 0 closed, 2 Exit (Friend Areas map), 3 visit, 4 leader changed
##   var r := await BaseMenu.open(host, root, entry)   # talking to a Friend Area resident (SPECIAL_TEXT_FRIEND_MENU)

const P := UITheme.PX
const T := "code_801D014:"
const PL := "party_list_menu:"
## ground_place.c sGroundPlaceNames ($t = team name)
const GROUND_PLACE_NAMES := ["Square", "Square", "Pokémon Square", "Whiscash Pond", "Pelipper Post Office",
	"Pelipper Post Office", "Makuhita Dojo", "Makuhita Dojo", "Luminous Cave", "Friend Areas", "$t Team Base",
	"$t Team Base", "Dungeon", "Tiny Woods", "Thunderwave Cave", "Mt. Steel", "Sinister Woods", "Silent Chasm",
	"Mt. Thunder", "Mt. Thunder Mid", "Great Canyon", "Hill of the Ancients", "Lapis Cave", "Lapis Cave Exit",
	"Mt. Blaze", "Mt. Blaze Mid", "Frosty Forest", "Frosty Clearing", "Mt. Freeze", "Mt. Freeze Mid", "Magma Cavern",
	"Magma Cavern Mid", "Sky Tower", "Sky Tower Mid", "Western Cave"]
const TOWN_NAMES := {"square": "Pokémon Square", "base": "$t Team Base", "post_office": "Pelipper Post Office",
	"dojo": "Makuhita Dojo", "whiscash": "Whiscash Pond"}

static var _last := "Items"          # Red keeps the cursor on the last command (sUnknown_203B254)
static var _badges: Texture2D

# ============================================================================ entry
static func open(host, root: Control, mon: Dictionary = {}) -> int:
	host_ref = host
	TeamScreens.leader_changed = false
	var team_before := Game.team.duplicate()
	if not mon.is_empty():
		var r0 := await party_menu(host, root, mon, true)
		return 4 if TeamScreens.leader_changed or team_before != Game.team else r0
	var fa := current_friend_area()
	var result := 0
	while true:
		var rows: Array = []
		var acts: Array = []
		var has_team := Game.team.size() > 0
		if fa == "":
			if has_team:
				rows.append({"text": "Items", "disabled": Game.bag.is_empty()}); acts.append("Items")
				rows.append({"text": "Team"}); acts.append("Team")
				if not Game.story.has("vars") or GVars.quest(GVars.QUEST_CAN_ACCESS_JOBS):
					rows.append({"text": "Job List", "disabled": Game.jobs.is_empty()}); acts.append("Job List")
			rows.append({"text": "Others"}); acts.append("Others")
		else:
			if has_team:
				rows.append({"text": "Friend", "disabled": Game.friends.is_empty()}); acts.append("Friend")
				rows.append({"text": "Items", "disabled": Game.bag.is_empty()}); acts.append("Items")
			rows.append({"text": "Info"}); acts.append("Info")
			rows.append({"text": "Exit"}); acts.append("Exit")
		var m := TeamScreens.menu("", rows, 8 * 8 * P)
		var want := acts.find(_last)
		if want < 0 or rows[want].get("disabled", false):
			want = 0
			for k in rows.size():
				if not rows[k].get("disabled", false):
					want = k
					break
		m.sel = want
		var side := _side_windows(root, fa)
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		if r.act != "pick":
			_free_all(side)
			break
		var act: String = acts[r.i]
		_last = act
		if act != "Exit":
			_free_all(side)
		match act:
			"Items":
				await items_menu(root)
			"Team":
				await team_list(host, root)
			"Job List":
				await Board.open_job_list(root)
			"Others":
				var o := await others_menu(host, root)
				if o == "title":
					return 0
			"Friend":
				var v := await friend_list(host, root, fa)
				if v != "":
					if await _visit(host, v) == 3:
						return 3
			"Info":
				await RedShops.fa_info_screen(root, fa)
			"Exit":
				_free_all(side)
				return 2
		if TeamScreens.auto_on():
			break
	return 4 if TeamScreens.leader_changed or team_before != Game.team else result

static func _free_all(a: Array) -> void:
	for c in a:
		TeamScreens._drop(c)

## The Friend Area key the ground map belongs to ("" = town / base / not on the ground).
static var force_fa := ""             # tests: pretend to stand in this Friend Area

static func current_friend_area() -> String:
	if force_fa != "":
		return force_fa
	if not Game.story.has("vars"):
		return ""
	var map := GVars.get_val(null, GVars.GROUND_MAP)
	var fa := GData.fa_of_map(map)
	return Story.fa_key(fa) if fa > 0 else ""

static func residents(fa: String) -> Array:
	var out: Array = []
	for f in Game.friends:
		if str(f.get("area", "")) == fa:
			out.append(f)
	return out

static var host_ref = null

static func place_name(fa: String) -> String:
	if fa != "":
		return Services.area_name(fa)
	if Game.story.has("vars"):
		var pid := GVars.get_val(null, GVars.GROUND_PLACE)
		if pid >= 0 and pid < GROUND_PLACE_NAMES.size():
			return str(GROUND_PLACE_NAMES[pid]).replace("$t", Game.team_name)
	var t = host_ref.get("town") if host_ref != null and is_instance_valid(host_ref) else null
	if t != null and is_instance_valid(t):
		return str(TOWN_NAMES.get(str(t.map_key), "Pokémon Square")).replace("$t", Game.team_name)
	return "Pokémon Square"

## Script special function 0x10 (HABITAT_TALK -> sub_80A87E0): talking to a Pokémon in its Friend Area opens
## its party_list_menu (SPECIAL_TEXT_FRIEND_MENU with that Pokémon); the player waits in control mode 5.
static func friend_talk(G, act) -> int:
	if act == null or ListMenu.auto or int(act.kind) != 1 or int(act.index) != 0 or int(act.unkC.x) != 1:
		return 0
	var li := int(act.unkC.y)
	if li < 0 or li >= G.lives.size():
		return 0
	var k := int(G.lives[li].kind_id)
	if k < 14 or k > 29:
		return 0
	var e: Dictionary = Story.friend_area_mon(GVars.get_val(null, GVars.GROUND_MAP), k - 14)
	if e.is_empty():
		return 0
	G.text.special(G.SP_FRIEND_MENU, 0, 0, e)
	G.lives[0].set_ctrl(5)
	return 1

# ============================================================================ side windows
## The team-rank badge for a rank index (tmrkpat, 16x16, from the ROM: assets/ui/rank_badges.png).
static func rank_badge(rank: int) -> Texture2D:
	if _badges == null:
		_badges = load("res://assets/ui/rank_badges.png")
	var at := AtlasTexture.new()
	at.atlas = _badges
	at.region = Rect2(clampi(rank, 0, 6) * 16, 0, 16, 16)
	return at

static func _win(root: Control, pos: Vector2, size: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = UITheme.theme()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.position = pos
	p.custom_minimum_size = size
	p.size = size
	root.add_child(p)
	return p

## sub_801D894: window 1 (12,4) 16x2 tiles with the place name centred, window 2 (2,14) 26x4 tiles with the
## rank badge, "<Rank> N Pts." and "Money: N". Window 2 sits at the bottom (the UI is 135 px tall, not 160).
static func _side_windows(root: Control, fa: String) -> Array:
	var vs := root.get_viewport_rect().size
	var w1 := _win(root, Vector2(12 * 8 * P, 4 * 8 * P), Vector2(16 * 8 * P, 2 * 8 * P))
	var l1 := TeamScreens._rtl("[center]%s[/center]" % place_name(fa))
	l1.autowrap_mode = TextServer.AUTOWRAP_OFF
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	w1.add_child(l1)
	var h2 := 4 * 8 * P
	var w2 := _win(root, Vector2(2 * 8 * P, vs.y - h2 - 4 * P), Vector2(26 * 8 * P, h2))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8 * P)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w2.add_child(hb)
	var badge := TextureRect.new()
	badge.texture = rank_badge(Missions.rank_index(Game.rank_points))
	badge.custom_minimum_size = Vector2(16, 16) * P
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_SCALE
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(badge)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2 * P)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	vb.add_child(TeamScreens._rtl(RedText.line(RedText.get_text(T + "sFmtPointsCyan"), {"args": [Missions.rank_title(Game.rank_points), Game.rank_points]})))
	vb.add_child(TeamScreens._rtl(RedText.line(RedText.get_text(T + "sFmtMoneyCyan"), {"args": [Game.money]})))
	return [w1, w2]

# ============================================================================ Items (Toolbox)
static func _bag_label(b: Dictionary) -> String:
	return DB.item_name(str(b.id)) + (" %d" % int(b.n) if DB.items.get(b.id, {}).get("stack", false) else "")

## A paged RedMenu list (8 per page). Returns {act, i} with i an index into rows.
## Red's item order (ConvertMoneyItemToMoney: Poké becomes money, then sorted by the item order).
static func sort_bag() -> void:
	var keep: Array = []
	for b in Game.bag:
		if b.id == "poke":
			Game.money += int(b.n)
		else:
			keep.append(b)
	keep.sort_custom(func(a, b): return item_order(a.id) < item_order(b.id))
	Game.bag.clear()
	Game.bag.append_array(keep)

static func item_order(id: String) -> int:
	var I: Dictionary = DB.items.get(id, {})
	return int(I.get("red_id", 1000)) * 1000 + int(I.get("sprite", 0))

static func paged(root: Control, title: String, rows: Array, start := 0, at := Vector2(2 * 8 * P, 2 * 8 * P), per := 8, min_w := 0.0, line_h := 0, sortable := false) -> Dictionary:
	var pages := maxi(1, ceili(rows.size() / float(per)))
	var page := clampi(start / per, 0, pages - 1)
	var sel := start % per
	while true:
		var part := rows.slice(page * per, mini(rows.size(), (page + 1) * per))
		var m := TeamScreens.menu(title, part, min_w)
		m.pages = pages
		m.page = page
		m.sel = mini(sel, part.size() - 1)
		m.max_rows = per
		if line_h > 0:
			m.line_h = line_h
		if sortable:
			m.select_key = true
			m.header_buttons = [["Sort", "select"]]
		var r := await TeamScreens.run_menu(root, m, at)
		match str(r.act):
			"select":
				if sortable:
					return {"act": "sort", "i": -1}
			"left":
				page = (page - 1 + pages) % pages
				sel = 0
			"right":
				page = (page + 1) % pages
				sel = 0
			"pick":
				return {"act": "pick", "i": page * per + int(r.i)}
			_:
				return {"act": "cancel", "i": -1}
	return {"act": "cancel", "i": -1}

## Red's Items window (sub_80227B8): Toolbox list, then Use (Gummis) / Give / Info.
static func items_menu(root: Control) -> void:
	var start := 0
	while not Game.bag.is_empty():
		var rows: Array = []
		for b in Game.bag:
			rows.append(TeamScreens.item_row(b))
		var r := await paged(root, "Toolbox", rows, start, Vector2(2 * 8 * P, 2 * 8 * P), 8, 120 * P, 0, true)
		if r.act == "sort":
			sort_bag()
			start = 0
			continue
		if r.act != "pick":
			return
		start = int(r.i)
		var id := str(Game.bag[r.i].id)
		var is_tm := is_tm_item(id)
		var c := await TeamScreens.submenu(root, null, [{"text": "Use", "disabled": not IQ.is_gummi(id) and not is_tm}, "Give", "Info"])
		match c:
			"Use":
				var w := await TeamScreens.which_member(root, Game.team, "Teach to whom?" if is_tm else "Use on whom?")
				if w >= 0:
					if is_tm:
						await teach_tm(root, Game.team[w], r.i)
					else:
						await IQ.feed_from_bag(root, Game.team[w], r.i)
			"Give":
				var w2 := await TeamScreens.which_member(root, Game.team, "Give to whom?")
				if w2 >= 0:
					await give_item(root, Game.team[w2], r.i)
			"Info":
				await TeamScreens.item_info(root, id)
		if TeamScreens.auto_on():
			return

## TMs (Red's and the Explorers of Sky / Remixed ones): Use teaches the move; Red turns the TM into a Used TM.
static func is_tm_item(id: String) -> bool:
	var I: Dictionary = DB.items.get(id, {})
	return str(I.get("red_cat", "")) == "tms_hms" or str(I.get("kind", "")) == "tm"

static func tm_move(id: String) -> String:
	var I: Dictionary = DB.items.get(id, {})
	var v = I.get("v", "")
	if v is String and v != "" and DB.moves.has(v):
		return v
	var nm := str(I.get("name", "")).trim_prefix("TM ")
	return nm if DB.moves.has(nm) else ""

static func can_learn_tm(sp: String, mv: String) -> bool:
	var S: Dictionary = DB.species.get(sp, DB.species.get(sp.substr(0, 4), {}))
	var tms = S.get("tm", null)
	if tms is Array and not tms.is_empty():
		return mv in tms
	for e in S.get("learn", []):            # no TM list (added Pokémon): its own level-up moves, or its types
		if str(e[1]) == mv:
			return true
	return str(DB.moves.get(mv, {}).get("t", "")) in S.get("types", [])

static func teach_tm(root: Control, e: Dictionary, k: int) -> void:
	var id := str(Game.bag[k].id)
	var mv := tm_move(id)
	var nm := str(e.get("name", ""))
	if mv == "":
		await TeamScreens.say(root, "This TM can't be used.")
		return
	if not can_learn_tm(str(e.sp), mv):
		await TeamScreens.say(root, "%s can't learn %s." % [nm, mv])
		return
	for m0 in e.moves:
		if str(m0.name) == mv:
			await TeamScreens.say(root, "%s already knows %s." % [nm, mv])
			return
	var pp := int(DB.moves.get(mv, {}).get("pp", 10))
	var slot := {"name": mv, "pp": pp, "max_pp": pp}
	if e.moves.size() >= 4:
		var opts: Array = []
		for m1 in e.moves:
			opts.append(str(m1.name))
		opts.append("Don't learn")
		var r := await TeamScreens.ask(root, "%s wants to learn %s.\nWhich move should it forget?" % [nm, mv], opts, opts.size() - 1)
		if r < 0 or r >= e.moves.size():
			return
		e.moves[r] = slot
	else:
		e.moves.append(slot)
	Game.bag.remove_at(k)
	if DB.items.get(id, {}).get("red", 0):
		Game.bag_add("usedtm")
	Audio.sfx("levelup")
	await TeamScreens.say(root, "%s learned %s!" % [nm, mv])

## Hand Toolbox slot k to a member (its old held item goes back to the Toolbox).
static func give_item(root: Control, e: Dictionary, k: int) -> void:
	var it: Dictionary = Game.bag[k]
	var held := str(e.get("held", ""))
	var held_n := TeamScreens.held_n_of(e) if TeamScreens.held_stacks(held) else 1
	Game.bag.remove_at(k)
	if held != "":
		Game.bag_add(held, held_n)
	TeamScreens.set_held(e, str(it.id), int(it.get("n", 1)))
	Audio.sfx("333")
	var key := PL + ("sUnknown_80DD5B8" if held != "" else "sUnknown_80DD594")
	await RedText.say(root, key, "", "", {"item1": DB.item_name(str(it.id)), "item0": DB.item_name(held)})

static func take_item(root: Control, e: Dictionary) -> void:
	var held := str(e.get("held", ""))
	if held == "" or not Game.bag_add(held, TeamScreens.held_n_of(e) if TeamScreens.held_stacks(held) else 1):
		return
	TeamScreens.set_held(e, "")
	Audio.sfx("333")
	await RedText.say(root, PL + "sUnknown_80DD60C", "", "", {"item0": DB.item_name(held)})

static func _pick_give(root: Control) -> int:
	var rows: Array = []
	for b in Game.bag:
		var ir := TeamScreens.item_row(b)
		ir.disabled = str(b.id) == "poke"
		rows.append(ir)
	var r := await paged(root, "Toolbox", rows, 0, Vector2(2 * 8 * P, 2 * 8 * P), 8, 120 * P)
	return int(r.i) if r.act == "pick" else -1

# ============================================================================ Team (friend_list_menu.c, mode 0)
static func _member_rows(list: Array) -> Array:
	var rows: Array = []
	for e in list:
		rows.append({"text": TeamScreens.name_of(e), "icon": TeamScreens.icon("star") if TeamScreens.is_leader(e) else TeamScreens.icon("blank"),
			"right": "Lv%d" % int(e.get("level", 1))})
	return rows

static func _item_window(root: Control, e: Dictionary) -> PanelContainer:
	var w := _win(root, Vector2(2 * 8 * P, root.get_viewport_rect().size.y - 2 * 8 * P - 6 * P), Vector2(26 * 8 * P, 2 * 8 * P))
	var held := str(e.get("held", ""))
	w.add_child(TeamScreens._rtl(RedText.line(RedText.get_text(PL + "sPartyMenuItemPlaceholder"), {"item0": TeamScreens.held_name(e)})))
	return w

## can this member go on standby (friend_list_menu.c FriendListMenu_isOnTeam / party_list sub_8026E88)?
static func can_stand_by(e: Dictionary) -> bool:
	if TeamScreens.is_leader(e):
		return false
	if (e == Game.partner or e == Game.hero) and Game.story.has("vars") and not GVars.quest(GVars.QUEST_CAN_CHANGE_LEADER):
		return false
	return true

static func _can_change_leader() -> bool:
	return Game.story.has("vars") and GVars.quest(GVars.QUEST_CAN_CHANGE_LEADER)

static func team_list(host, root: Control) -> void:
	var sel := 0
	while Game.team.size() > 0:
		var m := TeamScreens.menu(Game.team_name if Game.team_name != "" else "Team", _member_rows(Game.team), 120 * P)
		m.sel = mini(sel, Game.team.size() - 1)
		m.keep_on_pick = true
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		if r.act != "pick":
			return
		sel = int(r.i)
		var e: Dictionary = Game.team[r.i]
		var iw := _item_window(root, e)
		var opts: Array = [{"text": "Give", "disabled": Game.bag.is_empty()},
			{"text": "Take", "disabled": str(e.get("held", "")) == "" or Game.bag.size() >= Game.BAG_MAX}]
		if can_stand_by(e):
			opts.append("Stand By")
		opts.append({"text": "Give Gummi", "disabled": not Game.bag.any(func(b): return IQ.is_gummi(str(b.id)))})
		if not TeamScreens.is_leader(e) and _can_change_leader():
			opts.append("Make Leader")
		opts.append_array(["Summary", "Moves", "Check IQ"])
		var c := await TeamScreens.submenu(root, m, opts, r.i - m.top)
		TeamScreens._drop(iw)
		await _member_action(host, root, e, c)
		if TeamScreens.auto_on():
			return

static func _member_action(_host, root: Control, e: Dictionary, c: String) -> void:
	match c:
		"Give":
			var k := await _pick_give(root)
			if k >= 0:
				await give_item(root, e, k)
		"Take":
			await take_item(root, e)
		"Give Gummi":
			await IQ.give_gummi_ui(root, e)
		"Stand By":
			stand_by(e)
			Audio.sfx("207")
			await RedText.say(root, PL + "sUnknown_80DD4F4", "", "", {"mon1": "[color=#ffdc4a]%s[/color]" % TeamScreens.name_of(e)})
		"Make Leader":
			TeamScreens.make_leader(e)
			Audio.sfx("204")
			await RedText.say(root, PL + "sBecameLeader", "", "", {"mon1": "[color=#ffdc4a]%s[/color]" % TeamScreens.name_of(e)})
		"Summary":
			await TeamScreens.summary(root, e)
		"Moves":
			await TeamScreens.moves_menu(root, e, false, null, Game.team)
		"Check IQ":
			await TeamScreens.iq_menu(root, e)
	Game.save_game()

## Stand By: leave the team and wait in the Friend Area.
static func stand_by(e: Dictionary) -> void:
	Game.team.erase(e)
	if not Game.friends.has(e):
		if str(e.get("area", "")) == "":
			e["area"] = Services.area_of(str(e.get("sp", "")))
		Game.friends.append(e)
	TeamScreens.leader_changed = TeamScreens.leader_changed or false

static func join_team(e: Dictionary) -> bool:
	if Game.team.has(e) or Game.team.size() >= Services.PARTY_MAX:
		return false
	Game.team.append(e)
	return true

# ============================================================================ Friend Areas
## friend_list_menu.c mode 1 (Friend in a Friend Area): every recruited friend with Visit (go to its
## Friend Area; off when it lives here) and Summary / Moves / Check IQ. Returns the area to visit or "".
static func friend_list(_host, root: Control, fa: String) -> String:
	var sel := 0
	while true:
		var list: Array = Game.friends.duplicate()
		if list.is_empty():
			return ""
		var r := await paged(root, "Friends", _member_rows(list), sel, Vector2(2 * 8 * P, 2 * 8 * P), 8, 120 * P)
		if r.act != "pick":
			return ""
		sel = int(r.i)
		var e: Dictionary = list[r.i]
		var area := str(e.get("area", ""))
		var c := await TeamScreens.submenu(root, null, [{"text": "Visit", "disabled": area == fa or area == "" or not area in Game.friend_areas},
			"Summary", "Moves", "Check IQ"])
		match c:
			"Visit":
				return area
			"Summary":
				await TeamScreens.summary(root, e)
			"Moves":
				await TeamScreens.moves_menu(root, e, false, null, [e])
			"Check IQ":
				await TeamScreens.iq_menu(root, e)
		if TeamScreens.auto_on():
			return ""
	return ""

## Visit: walk to that Friend Area (Red returns 3 from sub_801D178 and the ground changes map).
static func _visit(host, k: String) -> int:
	var map := Story.map_of_fa_key(k)
	var g = host.get("ground") if host != null else null
	if map < 0 or g == null or not is_instance_valid(g):
		return 0
	g.ground_request(map, 0, 30)
	return 3

## party_list_menu.c: the commands for one recruited Pokémon (talking to it in its Friend Area, or from Friend).
## Returns 0 normally.
static func party_menu(host, root: Control, e: Dictionary, talking: bool) -> int:
	var sel_act := ""
	while true:
		var on_team := Game.team.has(e)
		var opts: Array = []
		if on_team:
			opts.append({"text": "Stand By", "disabled": not can_stand_by(e)})
			if _can_change_leader() and not TeamScreens.is_leader(e):
				opts.append("Make Leader")
		else:
			opts.append({"text": "Join Team", "disabled": Game.team.size() >= Services.PARTY_MAX})
		opts.append({"text": "Give Gummi", "disabled": not Game.bag.any(func(b): return IQ.is_gummi(str(b.id)))})
		opts.append({"text": "Give", "disabled": Game.bag.is_empty()})
		opts.append({"text": "Take", "disabled": str(e.get("held", "")) == "" or Game.bag.size() >= Game.BAG_MAX})
		if not on_team:
			opts.append({"text": "Say Farewell", "disabled": not _can_farewell(e)})
		opts.append_array(["Summary", "Moves", "Check IQ"])
		# windows: name (2,3) 15x2 tiles, "Item:" (2,17) 26x2, commands (19,3) 8 wide
		var nw := _win(root, Vector2(2 * 8 * P, 2 * 8 * P), Vector2(15 * 8 * P, 2 * 8 * P))
		nw.add_child(TeamScreens._rtl("[center]%s[/center]" % TeamScreens.name_of(e)))
		var iw := _item_window(root, e)
		var rows: Array = []
		for o in opts:
			rows.append(o if o is Dictionary else {"text": str(o)})
		var m := TeamScreens.menu("", rows)
		for k in rows.size():
			if str(rows[k].text) == sel_act and not rows[k].get("disabled", false):
				m.sel = k
		var r := await TeamScreens.run_menu(root, m, Vector2(19 * 8 * P, 2 * 8 * P))
		TeamScreens._drop(nw)
		TeamScreens._drop(iw)
		if r.act != "pick":
			return 0
		var c := str(rows[r.i].text)
		sel_act = c
		var nm := "[color=#ffdc4a]%s[/color]" % TeamScreens.name_of(e)
		match c:
			"Join Team":
				if join_team(e):
					Audio.sfx("207")
					await RedText.say(root, PL + "sUnknown_80DD4C4", "", "", {"mon1": nm})
					if talking:
						return 0
			"Stand By":
				stand_by(e)
				Audio.sfx("207")
				await RedText.say(root, PL + "sUnknown_80DD4F4", "", "", {"mon1": nm})
				if talking:
					return 0
			"Say Farewell":
				if await RedText.ask(root, PL + "sUnknown_80DD388", "", "", ["Yes", "No"], {}, 1) == 0 \
						and await RedText.ask(root, PL + "sUnknown_80DD420", "", "", ["Yes", "No"], {}, 1) == 0:
					Audio.sfx("202")
					await RedText.say(root, PL + "sUnknown_80DD564", "", "", {"mon1": nm})
					var held := str(e.get("held", ""))
					if held != "":
						var fn := TeamScreens.held_n_of(e) if TeamScreens.held_stacks(held) else 1
						if Game.bag_add(held, fn):
							await RedText.say(root, PL + "sUnknown_80DD60C", "", "", {"item0": DB.item_name(held)})
						else:
							Game.storage[held] = int(Game.storage.get(held, 0)) + fn
							await RedText.say(root, PL + "sUnknown_80DD63C", "", "", {"item0": DB.item_name(held)})
					Game.friends.erase(e)
					Game.save_game()
					return 0
			_:
				await _member_action(host, root, e, c)
		Game.save_game()
		if TeamScreens.auto_on():
			return 0
	return 0

## sub_8026EB8: not the leader / hero / partner, and its held item can go somewhere.
static func _can_farewell(e: Dictionary) -> bool:
	if TeamScreens.is_leader(e) or e == Game.hero or e == Game.partner or Game.team.has(e):
		return false
	return true

# ============================================================================ Others (options_menu1.c)
## Returns "title" when the player chose the remake's Title screen.
static func others_menu(host, root: Control) -> String:
	var sel := 0
	while true:
		var rows: Array = [{"text": RedText.get_text("options_menu1:sGameOptions")}, {"text": RedText.get_text("options_menu1:sHints")},
			{"text": "Pokédex", "color": UITheme.INK}, {"text": "Save"}, {"text": "Title screen"}]
		var m := TeamScreens.menu(RedText.get_text("options_menu1:sOthers"), rows, 10 * 8 * P)
		m.sel = sel
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		if r.act != "pick":
			return ""
		sel = int(r.i)
		match sel:
			0:
				await GameOptions.open(root)
			1:
				await hints(root)
			2:
				await PokedexUI.open(root)
			3:
				Game.save_game()
				await RedText.say(root, "Your adventure was saved.")
			4:
				Game.save_game()
				if host and host.has_method("title"):
					host.title()
					return "title"
		if TeamScreens.auto_on():
			return ""
	return ""

## Town hints (hints_menu1/2.c, locale/hints_usa.h).
const HINT_KEYS := ["TOWN_CONTROLS_1", "TOWN_CONTROLS_2", "SAVING", "ADVENTURES_WITH_FRIENDS", "BUILDING_A_TEAM"]

static func hints(root: Control) -> void:
	var sel := 0
	while true:
		var rows: Array = []
		for k in HINT_KEYS:
			rows.append({"text": RedText.get_text("HINTHEADING_" + k)})
		var m := TeamScreens.menu(RedText.get_text("options_menu1:sHints"), rows, 22 * 8 * P)
		m.sel = sel
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		if r.act != "pick":
			return
		sel = int(r.i)
		var k: String = HINT_KEYS[sel]
		var pg := TeamScreens.InfoPage.new()
		pg.width = 26 * 8 * P
		pg.count = HINT_KEYS.size()
		pg.page = sel
		pg.builder = func(i): return {"title": RedText.get_text("HINTHEADING_" + str(HINT_KEYS[i])),
			"parts": ["\n".join(RedText.fmt(RedText.get_text("HINTBODY_" + str(HINT_KEYS[i]))))]}
		await TeamScreens.run_page(root, pg, Vector2(2 * 8 * P, 2 * 8 * P))
		if TeamScreens.auto_on():
			return
