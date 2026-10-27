class_name Board
extends RefCounted
## Pelipper's Bulletin Board, the Job List and the Mailbox (Red: pelipper_board.c, wonder_mail_802C*.c).
##
##   await Board.open(root)          # "Bulletin Board / Job List" menu at the board (town interact "pelipper_board")
##   await Board.open_board(root)    # straight to the board
##   await Board.open_job_list(root) # the team's Job List (8 slots): Take Job / Suspend, Delete, Info
##   await Board.open_mailbox(root)  # the base mailbox (town interact "mailbox")
##
## Lists show 4 jobs per page, two lines each (title + difficulty, place + status) like Red's board;
## Left/Right flip pages. Info shows Red's Rescue Description with the client's portrait.

const PER_PAGE := 4
const PELIPPER := "0279"

static func open(root: Control) -> void:
	Missions.refresh_board_if_new_day()
	while true:
		var lm := ListMenu.make("Bulletin Board", ["Bulletin Board", "Job List (%d/%d)" % [Game.jobs.size(), Missions.MAX_JOBS], "Exit"])
		root.add_child(lm)
		lm.position = Vector2(8, 8)
		var i := await lm.choose()
		match i:
			0: await open_board(root)
			1: await open_job_list(root)
			_: break
	Game.save_game()

## The board: Accept (disabled when already in the Job List or the list is full) / Info.
static func open_board(root: Control) -> int:
	Missions.refresh_board_if_new_day()
	if ListMenu.auto:          # story test: accept a posted story request straight away
		for sj in Game.board:
			if sj.has("story"):
				Game.board.erase(sj)
				print("  BOARD accepted story job ", sj.story)
				return int(sj.story)
	var v := JobView.new()
	v.title = "Bulletin Board"
	v.mode = "board"
	v.jobs = Game.board
	root.add_child(v)
	while true:
		var i: int = await v.choose()
		if i < 0:
			break
		var j: Dictionary = Game.board[i]
		if j.has("story"):
			var lm2 := ListMenu.make("", ["Accept", "Info"])
			root.add_child(lm2)
			await root.get_tree().process_frame
			lm2.position = _menu_pos(root, v, lm2)
			var a2 := await lm2.choose()
			if a2 == 0:
				Audio.sfx("join")
				Game.board.erase(j)
				v.queue_free()
				return int(j.story)
			elif a2 == 1:
				await show_info(root, j)
			v.refresh()
			continue
		var can := not Missions.in_job_list(j) and Game.jobs.size() < Missions.MAX_JOBS
		var dk := str(j.get("dungeon", ""))
		var n_all := Missions.acceptable_count(dk)
		var lm := ListMenu.make("", [{"text": "Accept", "disabled": not can}, {"text": "Accept all for %s (%d)" % [Missions.dungeon_name(dk), n_all], "disabled": n_all <= 0}, "Info"])
		root.add_child(lm)
		await root.get_tree().process_frame
		lm.position = _menu_pos(root, v, lm)
		var a := await lm.choose()
		if a == 0 and can:
			Missions.accept(j)
			Audio.sfx("join")
			Game.save_game()
		elif a == 1 and n_all > 0:
			await accept_all_ui(root, dk)
		elif a == 2:
			await show_info(root, j)
		v.refresh()
	v.queue_free()
	return 0

## "Accept all for <dungeon>": accepts every job for it that fits in the Job List, then offers to take them.
static func accept_all_ui(root: Control, dk: String) -> void:
	var got := Missions.accept_all_for(dk)
	if got.is_empty():
		return
	Audio.sfx("join")
	Game.save_game()
	var msg := "Accepted %d job%s for %s. (Job List %d/%d)" % [got.size(), "" if got.size() == 1 else "s", Missions.dungeon_name(dk), Game.jobs.size(), Missions.MAX_JOBS]
	if Game.jobs.size() >= Missions.MAX_JOBS and Game.board.any(func(b): return str(b.get("dungeon", "")) == dk and not Missions.in_job_list(b)):
		msg += " The Job List is full."
	var c := await Dialog.ask(root, msg + "\nTake them now?", ["Take them", "Not now"], PELIPPER)
	if c == 0:
		for j in got:
			Missions.take(j)
		Game.save_game()

## The Job List: Take Job / Suspend, Delete (with confirmation), Info.
static func open_job_list(root: Control) -> void:
	var v := JobView.new()
	v.title = "Job List"
	v.mode = "list"
	v.jobs = Game.jobs
	root.add_child(v)
	while true:
		var i: int = await v.choose()
		if i < 0:
			break
		var j: Dictionary = Game.jobs[i]
		var opts: Array = []
		var acts: Array = []
		if j.state == "suspended":
			opts.append("Take Job"); acts.append("take")
		elif j.state == "taken":
			opts.append("Suspend"); acts.append("suspend")
		if not j.state in ["done", "done_pending"]:
			opts.append("Delete"); acts.append("delete")
		var n_sus := Game.jobs.filter(func(x): return x.state == "suspended").size()
		if n_sus > 0:
			opts.append("Take all suspended (%d)" % n_sus); acts.append("take_all")
		opts.append("Info"); acts.append("info")
		var lm := ListMenu.make("", opts)
		root.add_child(lm)
		await root.get_tree().process_frame
		lm.position = _menu_pos(root, v, lm)
		var a := await lm.choose()
		if a < 0:
			continue
		match acts[a]:
			"take":
				Missions.take(j)
			"suspend":
				Missions.suspend(j)
			"take_all":
				var n := Missions.take_all_suspended()
				Audio.sfx("join")
				await Dialog.say(root, "Took %d job%s. Good luck out there!" % [n, "" if n == 1 else "s"])
			"delete":
				var c := ListMenu.make("Delete this job?", ["Yes", "No"])
				root.add_child(c)
				await root.get_tree().process_frame
				c.position = _menu_pos(root, v, c)
				if await c.choose() == 0:
					Missions.cancel(j)
			"info":
				await show_info(root, j)
		Game.save_game()
		v.refresh()
	v.queue_free()

## The base mailbox (mailbox.c): Check Mail / Job List / PKMN News. Check Mail lists the job letters and the
## Pokémon News letters (news: Store / Read; jobs: Accept / Info, plus the remake's Delete).
static func open_mailbox(root: Control) -> void:
	Missions.refresh_mailbox_if_new_day()
	PokemonNews.refresh_if_new_day(Missions.mailbox().size())
	var sel := 0
	while true:
		var mb := Missions.mailbox()
		var rows: Array = [{"text": "Check Mail", "disabled": mb.is_empty() and PokemonNews.letters().is_empty()},
			{"text": "Job List", "disabled": Game.jobs.is_empty()}, {"text": "PKMN News", "disabled": PokemonNews.received().is_empty()}]
		if rows.all(func(r): return r.disabled):
			await Dialog.say(root, "There is no mail.")
			return
		var m := TeamScreens.menu("Mailbox", rows, 10 * 8 * UITheme.PX)
		m.sel = sel
		if rows[sel].disabled:
			for k in rows.size():
				if not rows[k].disabled:
					m.sel = k
					break
		var r := await TeamScreens.run_menu(root, m, Vector2(2, 2) * 8 * UITheme.PX)
		if r.act != "pick":
			Game.save_game()
			return
		sel = int(r.i)
		match sel:
			0: await check_mail(root)
			1: await open_job_list(root)
			2: await PokemonNews.news_list(root)
		if ListMenu.auto:
			return

static func _mail_list() -> Array:
	var all: Array = Missions.mailbox().duplicate()
	for n in PokemonNews.letters():
		all.append({"news": int(n), "title": "%s %s" % [UITheme.glyph("ICON_NEWS"), PokemonNews.headline(int(n))], "place": ""})
	return all

static func check_mail(root: Control) -> void:
	var v := JobView.new()
	v.title = "Mailbox"
	v.mode = "board"
	v.jobs = _mail_list()
	root.add_child(v)
	while true:
		if v.jobs.is_empty():
			break
		var i: int = await v.choose()
		if i < 0:
			break
		var j: Dictionary = v.jobs[i]
		if j.has("news"):
			var lm2 := ListMenu.make("", ["Store", "Read"])
			root.add_child(lm2)
			await root.get_tree().process_frame
			lm2.position = _menu_pos(root, v, lm2)
			var a2 := await lm2.choose()
			if a2 == 0:
				PokemonNews.store(int(j.news))
			elif a2 == 1:
				await PokemonNews.read(root, int(j.news))
		else:
			var can := Game.jobs.size() < Missions.MAX_JOBS and not Missions.in_job_list(j)
			var lm := ListMenu.make("", [{"text": "Accept", "disabled": not can}, "Info", "Delete"])
			root.add_child(lm)
			await root.get_tree().process_frame
			lm.position = _menu_pos(root, v, lm)
			var a := await lm.choose()
			if a == 0 and can:
				Missions.accept(j)
				Audio.sfx("307")
			elif a == 1:
				await show_info(root, j)
			elif a == 2:
				Missions.mailbox().erase(j)
		Game.save_game()
		v.jobs = _mail_list()
		v.refresh()
	v.queue_free()

static func _menu_pos(root: Control, v: Control, lm: Control) -> Vector2:
	var vs := root.get_viewport_rect().size
	return Vector2(vs.x - lm.size.x - 10, clampf(v.cursor_y() - 4, 6, vs.y - lm.size.y - 6))

## Red's "Rescue Description" page. Closes on any confirm / cancel / tap.
static func show_info(root: Control, j: Dictionary) -> void:
	var p := InfoView.new()
	p.job = j
	root.add_child(p)
	await p.closed
	p.queue_free()

static func status_text(j: Dictionary) -> String:
	match str(j.get("state", "")):
		"suspended": return "Suspend"
		"taken": return "Take Job"
		"done", "done_pending": return "Done"
	return ""

static func status_color(j: Dictionary) -> Color:
	match str(j.get("state", "")):
		"taken": return UITheme.GOOD
		"done", "done_pending": return UITheme.GOLD
	return UITheme.INK_DIM

static func rich(bb: String, w := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.scroll_active = false
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.clip_contents = true
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bb
	if w > 0:
		r.custom_minimum_size.x = w
	return r

static func label(t: String, col := UITheme.INK) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ============================================================================ job list view
class JobView extends PanelContainer:
	signal picked(i: int)
	var title := ""
	var mode := "board"            # "board" | "list"
	var jobs: Array = []
	var sel := 0
	var active := false
	var _rows: Array = []
	var _body: VBoxContainer
	var _page_lbl: Label
	var _title_lbl: Label

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		offset_left = 3 * UITheme.PX
		offset_right = -3 * UITheme.PX
		offset_top = 3 * UITheme.PX
		offset_bottom = -3 * UITheme.PX
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		add_child(vb)
		var head := HBoxContainer.new()
		vb.add_child(head)
		_title_lbl = Board.label(title, UITheme.GOLD)
		_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(_title_lbl)
		_page_lbl = Board.label("", UITheme.INK)
		_page_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		_page_lbl.gui_input.connect(_page_tap)
		head.add_child(_page_lbl)
		head.add_child(TeamScreens.back_button(func(): if not _blocked(): _emit(-1)))     # touch: leave the board
		var sep := ColorRect.new()
		sep.color = UITheme.WIN_EDGE
		sep.custom_minimum_size = Vector2(0, UITheme.PX)
		vb.add_child(sep)
		_body = VBoxContainer.new()
		_body.add_theme_constant_override("separation", UITheme.PX)
		vb.add_child(_body)
		refresh()

	func page() -> int:
		return sel / Board.PER_PAGE

	func pages() -> int:
		return maxi(1, int(ceil(jobs.size() / float(Board.PER_PAGE))))

	func refresh() -> void:
		if _body == null:
			return
		sel = clampi(sel, 0, maxi(0, jobs.size() - 1))
		for c in _body.get_children():
			c.queue_free()
		_rows.clear()
		_page_lbl.text = ("%d/%d" % [page() + 1, pages()]) if pages() > 1 else ""
		if mode == "list":
			_title_lbl.text = "%s  %d/%d" % [title, jobs.size(), Missions.MAX_JOBS]
		if jobs.is_empty():
			_body.add_child(Board.label("There are no jobs." if mode == "board" else "No jobs have been accepted.", UITheme.INK_DIM))
			return
		var start := page() * Board.PER_PAGE
		for k in range(start, mini(start + Board.PER_PAGE, jobs.size())):
			var row := _make_row(jobs[k], k)
			_body.add_child(row)
			_rows.append(row)
		_update_cursor()

	func _make_row(j: Dictionary, idx: int) -> Control:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UITheme.PX)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(_row_input.bind(idx))
		var cur := TextureRect.new()
		cur.texture = ListMenu._cursor_icon()
		cur.custom_minimum_size = Vector2(8, 8) * UITheme.PX
		cur.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		cur.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		cur.custom_minimum_size.y = UITheme.LINE
		cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cur.name = "Cursor"
		row.add_child(cur)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var l1 := HBoxContainer.new()
		l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l1)
		var dim := mode == "board" and Missions.in_job_list(j)
		var t := Board.rich(str(j.get("title", "")))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.custom_minimum_size.y = UITheme.LINE
		if dim:
			t.modulate = Color(0.7, 0.72, 0.82)
		l1.add_child(t)
		var d := Board.rich("" if j.has("news") else "[right]%s[/right]" % Missions.difficulty_bb(str(j.get("difficulty", "E"))))
		d.custom_minimum_size = Vector2(14 * UITheme.PX, UITheme.LINE)
		l1.add_child(d)
		var l2 := HBoxContainer.new()
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l2)
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(8 * UITheme.PX, 0)
		l2.add_child(pad)
		var pl := Board.label(str(j.get("place", "")), UITheme.INK_DIM if dim else UITheme.INK)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pl.clip_text = true
		l2.add_child(pl)
		var st := ""
		var sc := UITheme.INK_DIM
		if mode == "list":
			st = Board.status_text(j)
			sc = Board.status_color(j)
		elif dim:
			st = "Accepted"
		if st != "":
			l2.add_child(Board.label(st, sc))
		return row

	func _update_cursor() -> void:
		for r in _rows:
			var c: TextureRect = r.get_node("Cursor")
			c.modulate.a = 1.0 if _rows.find(r) == sel % Board.PER_PAGE else 0.0

	func cursor_y() -> float:
		var i := sel % Board.PER_PAGE
		if i < _rows.size():
			return (_rows[i] as Control).get_global_rect().position.y
		return 60.0

	func _move(to: int) -> void:
		if jobs.is_empty():
			return
		var old_page := page()
		sel = (to + jobs.size()) % jobs.size()
		Audio.sfx("cursor")
		if page() != old_page:
			refresh()
		else:
			_update_cursor()

	func choose() -> int:
		active = true
		if ListMenu.auto:
			_auto_close.call_deferred()
		var i: int = await picked
		active = false
		return i

	func _auto_close() -> void:
		await get_tree().create_timer(0.3).timeout
		print("  BOARD ", title, " -> close")
		_emit(-1)

	func _emit(i: int) -> void:
		if not active:
			return
		active = false
		if i >= 0:
			Audio.sfx("confirm")
		else:
			Audio.sfx("cancel")
		picked.emit(i)

	func _blocked() -> bool:
		if not active or not is_visible_in_tree():
			return true
		for c in get_parent().get_children():
			if c != self and (c is ListMenu or c is Board.InfoView or (c is Dialog and c.panel.visible)):
				return true
		return false

	func _unhandled_input(e: InputEvent) -> void:
		if _blocked():
			return
		if e.is_action_pressed("ui_down"):
			_move(sel + 1)
		elif e.is_action_pressed("ui_up"):
			_move(sel - 1)
		elif e.is_action_pressed("ui_right"):
			if pages() > 1:
				_move(mini(jobs.size() - 1, (page() + 1) * Board.PER_PAGE) if page() + 1 < pages() else sel % Board.PER_PAGE)
		elif e.is_action_pressed("ui_left"):
			if pages() > 1:
				_move((page() - 1) * Board.PER_PAGE if page() > 0 else mini(jobs.size() - 1, (pages() - 1) * Board.PER_PAGE))
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			if not jobs.is_empty():
				_emit(sel)
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			_emit(-1)
		else:
			return
		get_viewport().set_input_as_handled()

	func _row_input(e: InputEvent, idx: int) -> void:
		if _blocked():
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if sel == idx:
				_emit(idx)
			else:
				sel = idx
				Audio.sfx("cursor")
				_update_cursor()
			accept_event()

	func _page_tap(e: InputEvent) -> void:
		if _blocked():
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and pages() > 1:
			_move(((page() + 1) % pages()) * Board.PER_PAGE)
			accept_event()

	func _gui_input(e: InputEvent) -> void:
		if _blocked():
			return
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_emit(-1)
			accept_event()

# ============================================================================ info view
class InfoView extends PanelContainer:
	signal closed
	var job: Dictionary = {}
	var _done := false

	func _ready() -> void:
		theme = UITheme.theme()
		mouse_filter = Control.MOUSE_FILTER_STOP
		z_index = 10
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		offset_left = 3 * UITheme.PX
		offset_right = -3 * UITheme.PX
		offset_top = 3 * UITheme.PX
		offset_bottom = -3 * UITheme.PX
		var j := job
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		add_child(vb)
		var head := HBoxContainer.new()
		vb.add_child(head)
		var t := Board.label(str(Missions.txt("description")), UITheme.GOLD)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var st := Board.status_text(j)
		if st != "":
			head.add_child(Board.label(st, Board.status_color(j)))
		var sep := ColorRect.new()
		sep.color = UITheme.WIN_EDGE
		sep.custom_minimum_size = Vector2(0, UITheme.PX)
		vb.add_child(sep)
		var desc := Board.rich(str(j.get("text", "")))
		desc.custom_minimum_size.y = 2 * UITheme.LINE
		vb.add_child(desc)
		var gap := Control.new()
		gap.custom_minimum_size.y = UITheme.PX * 2
		vb.add_child(gap)
		var low := HBoxContainer.new()
		vb.add_child(low)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 4 * UITheme.PX)
		grid.add_theme_constant_override("v_separation", 0)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		low.add_child(grid)
		var rows := [
			[Missions.txt("client"), "[color=%s]%s[/color]" % [Missions.HL, Missions.sp_name(str(j.get("client", "")))]],
			[Missions.txt("objective"), str(j.get("objective", ""))],
			[Missions.txt("place"), str(j.get("place", ""))],
			[Missions.txt("difficulty_label"), Missions.difficulty_bb(str(j.get("difficulty", "E")))],
			[Missions.txt("reward"), Missions.reward_text(j)],
		]
		for r in rows:
			var k := Board.label(str(r[0]), UITheme.INK_DIM)
			k.custom_minimum_size.y = UITheme.LINE
			grid.add_child(k)
			var v := Board.rich(str(r[1]))
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.custom_minimum_size.y = UITheme.LINE
			grid.add_child(v)
		var tex := Dialog.portrait_tex(str(j.get("client", "")))
		if tex:
			var frame := PanelContainer.new()
			var sb := UITheme.box()
			sb.set_content_margin_all(UITheme.PX)
			frame.add_theme_stylebox_override("panel", sb)
			frame.size_flags_vertical = Control.SIZE_SHRINK_END
			low.add_child(frame)
			var pr := TextureRect.new()
			pr.texture = tex
			pr.custom_minimum_size = Vector2(40, 40) * UITheme.PX
			pr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pr.stretch_mode = TextureRect.STRETCH_SCALE
			pr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			frame.add_child(pr)

	func _close() -> void:
		if _done:
			return
		_done = true
		Audio.sfx("cancel")
		closed.emit()

	func _unhandled_input(e: InputEvent) -> void:
		if _done:
			return
		if e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack") or e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			_close()
			get_viewport().set_input_as_handled()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close()
			accept_event()
