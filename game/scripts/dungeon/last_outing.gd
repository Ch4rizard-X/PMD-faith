class_name LastOuting
extends RefCounted
## Red's "The Last Outing" window (dungeon_cleared_window.c ShowDungeonClearedWindow_Async +
## dungeon_run_end.c PrintOnDungeonFinishedWindow): a 22x14-tile window with a header slides up one tile
## per frame from below the screen to tile row 3 and waits for A. Contents (window pixels):
##   (16,0) The Last Outing / centred "Place: <dungeon>" at y 16 / centred "<leader> was defeated by" (or just
##   the name) at 26 / the reason at 36 / Level + Exp. Pts. at 52 / HP 62 / Attack + Defense 72 /
##   Sp. Atk. + Sp. Def. 82 (held-item boosts in red) / Item at 98.
## Texts: strings.c gDungeonExitReasonTexts, gText_* (dungeon exit summary, dungeon_exit.c SetUpDungeonExitData).

const WIN_W := 176
const WIN_H := 112
const YELLOW := "#ffdc4a"
const RED := "#ff8070"

## Exit reasons (DUNGEON_EXIT_*): [defeated-by prefix, text].
const REASONS := {
	"move": [true, ""],
	"powerful_move": [true, "was defeated by a powerful move."],
	"recoil": [false, "fainted from a move's recoil damage."],
	"spikes": [false, "fainted from stepping on spikes."],
	"burn": [false, "fainted from a bad burn."],
	"constriction": [false, "fainted, unable to bear constriction."],
	"poison": [false, "fainted after the poison spread."],
	"wrap": [false, "fainted while still being wrapped."],
	"curse": [false, "was felled by a curse."],
	"leech_seed": [false, "was drained to nothing by Leech Seed."],
	"perish_song": [false, "fainted from hearing Perish Song."],
	"nightmare": [false, "fainted while in a nightmare."],
	"thrown_rock": [false, "was felled by a thrown rock."],
	"hunger": [false, "fainted from hunger."],
	"explosion": [false, "disappeared in an explosion."],
	"chestnut_trap": [false, "tripped a Chestnut Trap and fainted."],
	"trap": [false, "fainted due to a trap's damage."],
	"pitfall": [false, "fell into a Pitfall Trap and fainted."],
	"blast_seed": [true, "a Blast Seed's damage."],
	"thrown_item": [false, "was felled by a thrown item."],
	"gave_up": [false, "gave up the exploration."],
	"blown_out": [false, "was blown out by an unseen force."],
	"weather": [false, "fainted due to the weather."],
	"client": [false, "failed to protect the client Pokémon."],
	"wonder_orb": [false, "fainted from a Wonder Orb."],
	"item": [false, "fainted from an item."],
	"escaped": [false, "escaped in the middle of exploration."],
	"cleared": [false, "cleared the dungeon."],
	"rescue": [false, "succeeded in the rescue mission."],
	"mission": [false, "impressively completed a mission."],
	"mew": [false, "befriended Mew!"],
}

## SetUpDungeonExitData: the summary of who ended the run and how (leader's stats, held item, boosts).
static func summary(reason: String, victim: Mon, killer: Mon = null, move := "") -> Dictionary:
	var s := {"reason": reason, "move": move, "killer": killer.name if killer else "Someone"}
	if victim:
		s.merge({"name": victim.name, "level": victim.level, "exp": victim.exp, "hp": victim.max_hp,
			"atk": victim.atk, "def": victim.def, "spa": victim.spa, "spd": victim.spd, "held": victim.held})
		var held: String = victim.held
		var b := {"atk": 0, "def": 0, "spa": 0, "spd": 0}
		if held != "" and not victim.get_meta("held_sticky", false):
			if held == "powerband": b.atk += Combat.POWER_BAND_BOOST
			if held == "munchbelt": b.atk += Combat.MUNCH_BELT_BOOST
			if held == "specialband": b.spa += Combat.SPECIAL_BAND_BOOST
			if held == "munchbelt": b.spa += Combat.MUNCH_BELT_BOOST
			if held == "defscarf": b["def"] += Combat.DEF_SCARF_BOOST
			if held == "zincband": b.spd += Combat.ZINC_BAND_BOOST
		s["boost"] = b
	return s

static func _font() -> Font:
	return UITheme.font()

static func _w(t: String) -> float:
	var plain := RegEx.create_from_string("\\[[^\\]]*\\]").sub(t, "", true)
	return _font().get_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE).x / UITheme.PX

static func _put(parent: Control, x: float, y: float, bb: String) -> void:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", _font())
	r.add_theme_font_size_override("normal_font_size", UITheme.FONT_SIZE)
	r.add_theme_color_override("font_shadow_color", UITheme.SHADOW)
	r.add_theme_constant_override("shadow_offset_x", UITheme.PX / 2)
	r.add_theme_constant_override("shadow_offset_y", UITheme.PX / 2)
	r.text = bb
	r.position = Vector2(x, y - 1) * UITheme.PX
	r.size = Vector2(WIN_W * UITheme.PX, UITheme.LINE)
	parent.add_child(r)

## Builds the window contents (positions in Red's window pixels, scaled by UITheme.PX).
static func build(s: Dictionary, place: String) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme = UITheme.theme()
	pc.add_theme_stylebox_override("panel", UITheme.frame())
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	var c := Control.new()
	c.custom_minimum_size = Vector2(WIN_W, WIN_H) * UITheme.PX
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(c)
	_put(c, 16, 0, "The Last Outing")
	var line := ColorRect.new()          # the header strip's lower edge
	line.color = UITheme.FRAME_LIGHT
	line.position = Vector2(0, 13) * UITheme.PX
	line.size = Vector2(WIN_W, 1) * UITheme.PX
	c.add_child(line)
	var pl := "Place: [color=%s]%s[/color]" % [YELLOW, place]
	_put(c, (WIN_W - _w(pl)) / 2.0, 16, pl)
	var rs: Array = REASONS.get(str(s.get("reason", "")), [true, "was defeated by a powerful move."])
	var t1 := ("%s was defeated by" % str(s.get("name", ""))) if rs[0] else str(s.get("name", ""))
	_put(c, (WIN_W - _w(t1)) / 2.0, 26, t1)
	var t2: String = rs[1]
	if str(s.get("reason", "")) == "move":
		t2 = "%s's %s." % [str(s.get("killer", "Someone")), str(s.get("move", ""))]   # gText_DeathToMove
	_put(c, (WIN_W - _w(t2)) / 2.0, 36, t2)
	var b: Dictionary = s.get("boost", {})
	var lv := int(s.get("level", 1))
	_put(c, 4, 52, "Level")
	_put(c, 42 if lv < 100 else 35, 52, str(lv))
	_put(c, 64, 52, "Exp. Pts. %d" % int(s.get("exp", 0)) if lv < 100 else "Exp. Pts.%d" % int(s.get("exp", 0)))
	_put(c, 4, 62, "HP")
	_put(c, 42, 62, str(int(s.get("hp", 0))))
	for row in [[72, "Attack", "atk", "Defense", "def"], [82, "Sp. Atk.", "spa", "Sp. Def.", "spd"]]:
		_put(c, 4, row[0], row[1])
		_put(c, 42, row[0], _val(s, b, row[2]))
		_put(c, 80, row[0], row[3])
		_put(c, 128, row[0], _val(s, b, row[4]))
	var held := str(s.get("held", ""))
	_put(c, 4, 98, "Item:")
	_put(c, 42, 98, DB.item_name(held) if held != "" else "None")
	return pc

static func _val(s: Dictionary, b: Dictionary, k: String) -> String:
	var v := int(s.get(k, 0))
	var bo := int(b.get(k, 0))
	if bo != 0:
		return "[color=%s]%d[/color]" % [RED, v + bo]
	return str(v)

## Slides the window up (one tile per frame, 20 -> 3) and waits for A / a click. Awaitable.
static func show(root: Control, s: Dictionary, place: String) -> void:
	var pc := build(s, place)
	root.add_child(pc)
	var vs := root.get_viewport_rect().size
	var px := float(UITheme.PX)
	var x := (vs.x - WIN_W * px) / 2.0
	# Red stops at tile row 3 of 20; keep the same share of the 270 px screen
	var y_end := maxf(8.0 * px, minf(3.0 * 8.0 * px, vs.y - (WIN_H + 8.0) * px))
	var y := vs.y
	pc.position = Vector2(x, y)
	var step := 8.0 * px
	var tree := root.get_tree()
	var y0 := y
	var t0 := Time.get_ticks_msec()
	while y > y_end and is_instance_valid(pc):      # one tile per 60 Hz frame, by elapsed time
		y = maxf(y_end, y0 - step * float(Time.get_ticks_msec() - t0) * 60.0 / 1000.0)
		pc.position = Vector2(x, y)
		await tree.process_frame
	if Dialog.auto or TeamScreens.auto_on():
		await tree.create_timer(0.3).timeout
	else:
		var was_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		while true:
			await tree.process_frame
			var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("act_attack") \
					or Input.is_action_just_pressed("ui_cancel") \
					or (down and not was_down):
				break
			was_down = down
	Audio.sfx("confirm")
	if is_instance_valid(pc):
		pc.queue_free()
