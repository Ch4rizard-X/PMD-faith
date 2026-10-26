class_name PrepareScreen
extends RefCounted
## "Prepare for dungeon" screen shown after picking a dungeon on the world map: the team (level / HP),
## the Toolbox, the jobs taken for this dungeon and the dungeon's info, with the commands
## Set out / Change team (Friend Areas) / Storage / Cancel along the bottom.
##
##   if await PrepareScreen.run(root, key): start_dungeon(key)

const ACTS := ["go", "team", "storage", "cancel"]
const LABELS := ["Set out", "Change team", "Storage", "Cancel"]

## True = set out.
static func run(root: Control, key: String) -> bool:
	var sel := 0
	while true:
		var v := PrepView.new()
		v.key = key
		v.sel = sel
		root.add_child(v)
		var a: String = await v.choose()
		sel = v.sel
		root.remove_child(v)
		v.queue_free()
		match a:
			"go":
				return true
			"team":
				await change_team(root)
			"storage":
				await Services.storage(root)
			_:
				return false
		if ListMenu.auto:
			return false
	return false

static func change_team(root: Control) -> void:
	if Game.friend_areas.is_empty():
		await Dialog.say(root, "You don't have any Friend Areas yet. Wigglytuff in Pokémon Square sells them!")
		return
	while true:
		var fk := await Services.pick_friend_area(root)
		if fk == "":
			return
		await Services.visit_area(root, fk)
		if ListMenu.auto:
			return

static func job_line(j: Dictionary) -> String:
	var fl := Missions.floor_label(str(j.dungeon), int(j.floor))
	var what := ""
	match str(j.kind):
		"rescue": what = "Rescue " + Missions.sp_name(str(j.client))
		"target": what = "Find " + Missions.sp_name(str(j.target))
		"escort": what = "Escort " + Missions.sp_name(str(j.client))
		"find": what = "Find " + DB.item_name(str(j.get("item", "")))
		"deliver": what = "Deliver " + DB.item_name(str(j.get("item", "")))
		_: what = str(j.get("objective", j.kind))
	return "%s %s" % [fl, what]

static func taken_jobs(key: String) -> Array:
	return Game.jobs.filter(func(j): return str(j.dungeon) == key and str(j.state) == "taken")

static func suspended_jobs(key: String) -> Array:
	return Game.jobs.filter(func(j): return str(j.dungeon) == key and str(j.state) == "suspended")

# ============================================================================ view
class PrepView extends PanelContainer:
	signal picked(a: String)
	var key := ""
	var sel := 0
	var _btns: Array = []
	var _done := false

	func _ready() -> void:
		PokedexUI._full(self)
		var D: Dictionary = DB.dungeons.get("dungeons", {}).get(key, {})
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		# header
		var head := HBoxContainer.new()
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(head)
		var t := PokedexUI._lbl(Services.dname(key) + ("  " if key in Game.cleared else ""), UITheme.GOLD)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		if key in Game.cleared:
			var st := TextureRect.new()
			st.texture = TeamScreens.icon("star")
			st.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			st.custom_minimum_size = Vector2(9 * UITheme.PX, UITheme.LINE)
			head.add_child(st)
		head.add_child(PokedexUI._lbl("  %d Poké" % Game.money))
		vb.add_child(PokedexUI._sep())
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 6 * UITheme.PX)
		cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(cols)
		# left: team + toolbox
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 0)
		left.custom_minimum_size.x = 214
		left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cols.add_child(left)
		var party := int(D.get("party", Services.PARTY_MAX))
		left.add_child(PokedexUI._lbl("Team", UITheme.GOLD))
		var avg := 0
		for i in Game.team.size():
			var e: Dictionary = Game.team[i]
			var m: Mon = Game.mon_from_entry(e)
			avg += int(e.level)
			var over := i >= party
			left.add_child(PokedexUI._rich("%s%s[/color] [color=#9ea8c7]Lv[/color]%d [color=#9ea8c7]HP[/color]%d" % ["[color=#9ea8c7]" if over else "[color=#ffffff]", str(e.name), int(e.level), m.max_hp]))
		for i in range(Game.team.size(), Services.PARTY_MAX):
			left.add_child(PokedexUI._lbl("-", UITheme.INK_DIM))
		avg = int(round(avg / float(maxi(1, Game.team.size()))))
		var bag_t := PokedexUI._lbl("Toolbox %d/%d" % [Game.bag.size(), Game.BAG_MAX], UITheme.GOLD)
		left.add_child(bag_t)
		var names: Array = []
		for b in Game.bag:
			names.append(DB.item_name(str(b.id)) + (" ×%d" % int(b.n) if DB.items.get(b.id, {}).get("stack", false) else ""))
		var bt := PokedexUI._rich(", ".join(names) if not names.is_empty() else "[color=#9ea8c7]empty[/color]")
		bt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bt.fit_content = false
		bt.clip_contents = true
		bt.custom_minimum_size = Vector2(214, 2 * UITheme.LINE)
		left.add_child(bt)
		# right: dungeon info + jobs
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 0)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cols.add_child(right)
		var nf := int(D.get("floors", []).size())
		var up: bool = D.get("up", false)
		var rec := Pokedex.recommended_level(key)
		var rng := Pokedex.level_range(key)
		var rc := "#7fff7f" if avg >= rec else ("#ffdc4a" if avg >= rec - 3 else "#ff8070")
		right.add_child(PokedexUI._rich("[color=#9ea8c7]Floors[/color] %s%dF  [color=#9ea8c7]Recruit[/color] %s" % ["" if up else "B", nf, "[color=#7fff7f]OK[/color]" if D.get("recruit", true) else "[color=#ff8070]No[/color]"]))
		right.add_child(PokedexUI._rich("[color=#9ea8c7]Rec. Lv[/color] [color=%s]%d[/color] [color=#9ea8c7](foes %d-%d)[/color]" % [rc, rec, rng[0], rng[1]]))
		if party < Services.PARTY_MAX:
			right.add_child(PokedexUI._rich("[color=#ffdc4a]Only %d may enter[/color]" % party))
		var jobs := PrepareScreen.taken_jobs(key)
		var sus := PrepareScreen.suspended_jobs(key)
		right.add_child(PokedexUI._lbl("Jobs (%d)" % jobs.size(), UITheme.GOLD))
		var shown := 0
		for j in jobs:
			if shown >= 4:
				break
			var jl := PokedexUI._lbl(PrepareScreen.job_line(j))
			jl.clip_text = true
			right.add_child(jl)
			shown += 1
		if jobs.size() > shown:
			right.add_child(PokedexUI._lbl("+%d more" % (jobs.size() - shown), UITheme.INK_DIM))
		if jobs.is_empty():
			right.add_child(PokedexUI._lbl("No jobs taken here.", UITheme.INK_DIM))
		if not sus.is_empty():
			right.add_child(PokedexUI._lbl("%d suspended in Job List" % sus.size(), UITheme.INK_DIM))
		# command bar
		vb.add_child(PokedexUI._sep())
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 2 * UITheme.PX)
		bar.alignment = BoxContainer.ALIGNMENT_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(bar)
		for i in PrepareScreen.LABELS.size():
			var b := Button.new()
			b.text = PrepareScreen.LABELS[i]
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			b.icon = ListMenu._blank_icon()
			b.add_theme_constant_override("h_separation", UITheme.PX)
			for s in ["normal", "hover", "pressed", "disabled", "focus"]:
				b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
			b.add_theme_color_override("font_hover_color", UITheme.INK)
			b.add_theme_color_override("font_pressed_color", UITheme.GOLD)
			b.custom_minimum_size.y = UITheme.LINE
			b.pressed.connect(_click.bind(i))
			b.mouse_entered.connect(func(): _set_sel(i))
			bar.add_child(b)
			_btns.append(b)
		_set_sel(sel)

	func _set_sel(i: int) -> void:
		sel = clampi(i, 0, _btns.size() - 1)
		for j in _btns.size():
			_btns[j].icon = ListMenu._cursor_icon() if j == sel else ListMenu._blank_icon()

	func _click(i: int) -> void:
		_set_sel(i)
		_finish(PrepareScreen.ACTS[i])

	func _finish(a: String) -> void:
		if _done:
			return
		_done = true
		Audio.sfx("cancel" if a == "cancel" else "confirm")
		picked.emit.call_deferred(a)      # after this input event is fully handled

	func choose() -> String:
		if ListMenu.auto:
			print("  PREPARE ", key, " -> go")
			(func(): _finish("go")).call_deferred()
		return await picked

	func _unhandled_input(e: InputEvent) -> void:
		if _done or PokedexUI._blocked(self):
			return
		if e.is_action_pressed("ui_right") or e.is_action_pressed("ui_down"):
			_set_sel((sel + 1) % _btns.size()); Audio.sfx("cursor")
		elif e.is_action_pressed("ui_left") or e.is_action_pressed("ui_up"):
			_set_sel((sel - 1 + _btns.size()) % _btns.size()); Audio.sfx("cursor")
		elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
			_finish(PrepareScreen.ACTS[sel])
		elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_menu"):
			_finish("cancel")
		else:
			return
		get_viewport().set_input_as_handled()
