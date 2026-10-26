class_name Gulpin
extends RefCounted
## Gulpin Link Shop (gulpin_shop_801FB50.c / gulpin_shop.c, dialogue from gulpin_shop_usa.h).
##
## Red's rules:
##  - Link/Delink/Forget/Set and Remember for any recruited Pokémon (team + Friend Areas).
##  - Linking costs 150 Poké once per visit, however many links are made ("Link moves all you like for
##    just 150 Poké!"): Link needs >= 150 on hand, the fee is paid when you leave.
##  - Link joins the next unlinked move after the chosen one to its chain (TryLinkMovesAfter); charging
##    moves (Solarbeam, Sky Attack, Razor Wind, Focus Punch, Skull Bash, Fly, Bounce, Dive, Dig) can't be
##    linked. Delink breaks the links after the chosen move. Forget drops the move and the moves linked
##    after it, but never the last remaining chain.
##  - Remembering is free: level-up moves of the evolution line (see IQ.rememberable); Deoxys can't.
##    A remembered move starts with 0 PP (refilled when a dungeon starts). With four moves one (and
##    whatever is linked after it) is forgotten first.
## Speaker: Gulpin "0316". Game.flags.gulpin_asleep switches to Red's sleeping-Gulpin dialogue.

const SP := "0316"
const SCRIPT_TS := "res://scripts/ui/team_screens.gd"

static var _mode := "awake"
static var _money_box: PanelContainer

## Red's text for dialogue `i`, split into pages at {EXTRA_MSG}; subs: {POKEMON_0} etc.
static func pages(i: int, subs := {}) -> Array:
	var txt := str(IQ.data().get("gulpin", {}).get(_mode, [])[i])
	var rep := {
		"{COLOR CYAN_M}": "[color=#7fe0ff]", "{COLOR CYAN}": "[color=#7fe0ff]", "{COLOR GREEN}": "[color=#7fff7f]",
		"{COLOR YELLOW}": "[color=#ffdc4a]", "{RESET}": "[/color]", "{POKE}": "Poké", "{WAIT_PRESS}": "",
		"{L_BUTTON}": "L", "{R_BUTTON}": "R", "{A_BUTTON}": "A", "{SELECT_BUTTON}": "Select", "{DPAD}": "the Control Pad",
		"“": "\"", "”": "\"",
	}
	for k in subs:
		txt = txt.replace(k, str(subs[k]))
	for k in rep:
		txt = txt.replace(k, rep[k])
	var out: Array = []
	for p in txt.split("{EXTRA_MSG}"):
		var s := p.strip_edges()
		if s != "":
			out.append("Gulpin: " + s)
	return out

static func _speaker() -> String:
	return SP if _mode == "awake" else ""     # Red hides the portrait while Gulpin sleeps

static func _say(root: Control, i: int, subs := {}) -> void:
	await Dialog.talk(root, pages(i, subs), _speaker())

static func _ask(root: Control, i: int, opts: Array, subs := {}) -> int:
	var p := pages(i, subs)
	if p.size() > 1:
		await Dialog.talk(root, p.slice(0, p.size() - 1), _speaker())
	return await Dialog.ask(root, p[-1], opts, _speaker())

static func _show_money(root: Control) -> void:
	_hide_money()
	_money_box = PanelContainer.new()
	_money_box.theme = UITheme.theme()
	var l := Label.new()
	l.text = "Money: %d Poké" % Game.money
	_money_box.add_child(l)
	root.add_child(_money_box)
	await root.get_tree().process_frame
	if is_instance_valid(_money_box):
		_money_box.position = Vector2(root.get_viewport_rect().size.x - _money_box.size.x - 8, 8)

static func _hide_money() -> void:
	if is_instance_valid(_money_box):
		_money_box.queue_free()
	_money_box = null

static func _ts():
	return load(SCRIPT_TS) if ResourceLoader.exists(SCRIPT_TS) else null

# ------------------------------------------------------------------ main flow
static func shop(root: Control) -> void:
	_mode = "asleep" if bool(Game.flags.get("gulpin_asleep", false)) else "awake"
	var st := {"paid_link": false}
	var greet := 0
	while true:
		await _show_money(root)
		var c := await _ask(root, greet, ["Proceed", "Info", "Cancel"])
		_hide_money()
		greet = 1
		if c == 1:
			var k := await _ask(root, 21, ["Setting moves", "Linking moves", "Remembering moves"])
			if k >= 0:
				await _say(root, 22 + k, {"{POKEMON_4}": IQ.name_of(Game.team[0]) if Game.team.size() > 0 else ""})
			continue
		if c == 0:
			await _say(root, 8)
			while true:
				var mem = await _pick_member(root)
				if mem == null:
					if await _ask(root, 6, ["Yes", "No"]) == 0:
						await _say(root, 8)
						continue
					break
				await _member_menu(root, mem, st)
				if ListMenu.auto:
					break
		break
	await _say(root, 7)
	if st.paid_link:
		Game.money = maxi(0, Game.money - int(IQ.data().get("link_fee", 150)))
		Audio.sfx("coin")
	Game.save_game()

## Team first, then the Friend Area residents (Red's FriendList shows every recruited Pokémon).
static func members() -> Array:
	var out: Array = []
	for e in Game.team:
		out.append(e)
	for f in Game.friends:
		var dup := false
		for o in out:
			if is_same(o, f):
				dup = true
		if not dup:
			out.append(f)
	return out

static func _pick_member(root: Control):
	var list := members()
	var opts: Array = []
	for e in list:
		var tag := ""
		for t in Game.team:
			if is_same(t, e):
				tag = " ★"
		opts.append("%s  Lv%d%s" % [IQ.name_of(e), int(e.get("level", 1)), tag])
	var i := await IQ.paged_choose(root, "Pokémon", opts)
	return null if i < 0 else list[i]

static func _member_menu(root: Control, e: Dictionary, st: Dictionary) -> void:
	var sel := 0
	while true:
		var lm := ListMenu.make(IQ.name_of(e), ["Moves", "Summary", "Check IQ", "Remember"])
		root.add_child(lm)
		lm.position = Vector2(8, 8)
		lm._set_sel(sel)
		var c := await lm.choose()
		if c < 0:
			return
		sel = c
		match c:
			0:
				await moves_editor(root, e, st)
			1:
				var ts = _ts()
				if ts != null:
					await ts.summary(root, e)
				else:
					await Dialog.say(root, IQ.summary_text(e))
			2:
				var ts2 = _ts()
				if ts2 != null:
					await ts2.iq_menu(root, e)
				else:
					await IQ.check_iq_ui(root, e)
			3:
				await _remember(root, e)
		if ListMenu.auto:
			return

# ------------------------------------------------------------------ moves (link / delink / set / forget)
static func move_rows(e: Dictionary, leader: bool) -> Array:
	var rows: Array = []
	for mv in e.get("moves", []):
		var mark := ""
		if leader and bool(mv.get("set", false)):
			mark = " ★"
		elif not leader and not bool(mv.get("on", true)):
			mark = " (off)"
		rows.append("%s%-13s %2d/%2d%s" % ["+" if bool(mv.get("linked", false)) else " ", mv.name, int(mv.pp), int(mv.max_pp), mark])
	return rows

static func _move_info(moves: Array, i: int) -> String:
	var lines: Array = []
	for j in IQ.chain_from(moves, i).slice(0, 4):
		var d: Dictionary = DB.moves.get(str(moves[j].name), {})
		lines.append("[color=#7fe0ff]%s[/color]  %s  Pow %d  Acc %d  PP %d" % [moves[j].name, d.get("t", "?"), int(d.get("p", 0)), int(d.get("a1", 0)), int(d.get("pp", 0))])
	return "\n".join(lines)

## Red's link editor (state 0x1E..0x23). st.paid_link turns true after the first link this visit.
static func moves_editor(root: Control, e: Dictionary, st: Dictionary) -> void:
	var leader := Game.team.size() > 0 and is_same(Game.team[0], e)
	var fee := int(IQ.data().get("link_fee", 150))
	var sel := 0
	var subs := {"{POKEMON_5}": IQ.name_of(e)}
	while true:
		var moves: Array = e.get("moves", [])
		if moves.is_empty():
			return
		var lm := ListMenu.make("%s's moves" % IQ.name_of(e), move_rows(e, leader))
		root.add_child(lm)
		lm.position = Vector2(8, 8)
		lm._set_sel(mini(sel, moves.size() - 1))
		var i := await lm.choose()
		if i < 0:
			return
		sel = i
		var set_txt := ("Deselect" if bool(moves[i].get("set", false)) else "Set") if leader else ("Deselect" if bool(moves[i].get("on", true)) else "Set")
		var opts := [set_txt, "Link", "Delink", "Forget", "Shift up", "Info"]
		var c := await IQ._small_menu(root, opts, Vector2(250, 8 + i * UITheme.LINE))
		subs["{POKEMON_1}"] = moves[i].name
		match c:
			0:
				if leader:
					IQ.toggle_set(moves, i)
				else:
					IQ.toggle_on(moves, i)
				Audio.sfx("confirm")
			1:
				if Game.money < fee and not st.paid_link:
					Audio.sfx("error")
					await _say(root, 2)
				elif not IQ.link(moves, i):
					Audio.sfx("error")
					await _say(root, 3)
				else:
					if not st.paid_link:
						st.paid_link = true
						Audio.sfx("coin")
					else:
						Audio.sfx("confirm")
			2:
				if not IQ.delink(moves, i):
					Audio.sfx("error")
					await _say(root, 4)
			3:
				if not IQ.can_forget(moves, i):
					Audio.sfx("error")
					await _say(root, 5)
				else:
					var linked_after := IQ.chain_from(moves, i).size() > 1
					if await _ask(root, 18 if linked_after else 17, ["Yes", "No"], subs) == 0:
						IQ.forget(moves, i)
						await _say(root, 20 if linked_after else 19, subs)
						sel = 0
			4:
				IQ.shift_up(moves, i)
			5:
				await Dialog.say(root, _move_info(moves, i))
		if ListMenu.auto:
			return

# ------------------------------------------------------------------ remember
static func _remember(root: Control, e: Dictionary) -> void:
	var subs := {"{POKEMON_5}": IQ.name_of(e)}
	if not IQ.can_remember(e):
		await _say(root, 16, subs)
		return
	var list := IQ.rememberable(e)
	if list.is_empty():
		await _say(root, 15, subs)
		return
	await _say(root, 9, subs)
	while true:
		list = IQ.rememberable(e)
		if list.is_empty():
			return
		var opts: Array = []
		for n in list:
			var d: Dictionary = DB.moves.get(n, {})
			opts.append("%-14s %s" % [n, d.get("t", "")])
		var i := await IQ.paged_choose(root, "Remember which move?", opts)
		if i < 0:
			return
		var mv: String = list[i]
		var c := await IQ._small_menu(root, ["Remember", "Info"], Vector2(250, 8 + (i % IQ.PAGE) * UITheme.LINE))
		if c == 1:
			await Dialog.say(root, _move_info([{"name": mv}], 0))
			continue
		if c != 0:
			continue
		subs["{POKEMON_0}"] = mv
		var moves: Array = e.get("moves", [])
		if moves.size() < 4:
			IQ.remember(e, mv)
			Audio.sfx("confirm")
			await _say(root, 10, subs)
			return
		# Only four moves: pick one to forget (gulpin_shop.c)
		var lm2 := ListMenu.make("Only four moves may be learned! Forget which?", move_rows(e, false))
		root.add_child(lm2)
		lm2.position = Vector2(8, 8)
		var f := await lm2.choose()
		if f < 0:
			continue
		subs["{POKEMON_1}"] = moves[f].name
		var linked_after := IQ.chain_from(moves, f).size() > 1
		if await _ask(root, 12 if linked_after else 11, ["Yes", "No"], subs) != 0:
			continue
		IQ.remember(e, mv, f)
		Audio.sfx("confirm")
		await _say(root, 14 if linked_after else 13, subs)
		return
