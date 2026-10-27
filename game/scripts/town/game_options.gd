class_name GameOptions
extends RefCounted
## Red's Game Options (options_menu2.c + dungeon_strings.c option rows, game_options.c defaults), opened from
## the base menu's Others. All of Red's rows, stored in Game.settings (other screens read these keys):
##   msg_speed   0 Slow / 1 Normal / 2 Fast   (Red: Speed Slow / Fast; the remake keeps its middle step)
##   far_off_pals 0 Self / 1 Look            damage_turn  bool (No / Yes)
##   grids       bool (Off / On)              map_mode     0 Off / 1 Clear / 2 Shade
##   window_color 0 Blue / 1 Red / 2 Green
## plus the remake's extras (Hunger, Second screen, Controls). Left/Right change a row; leaving a page with
## changes asks Red's "Change settings?".

const P := UITheme.PX
const DEFAULTS := {"msg_speed": 1, "far_off_pals": 1, "damage_turn": true, "grids": true, "map_mode": 1, "window_color": 0, "hunger": true, "prepare_screen": false, "qol_statusfade": true, "qol_recruit": 1, "qol_partner_ai": 1}
const ROWS := {
	"msg_speed": ["Speed", ["Slow", "Normal", "Fast"]],
	"far_off_pals": ["Far-off pals", ["Self", "Look"]],
	"damage_turn": ["Damage turn", ["No", "Yes"]],
	"grids": ["Grids", ["Off", "On"]],
	"map_mode": ["Map", ["Off", "Clear", "Shade"]],
	"hunger": ["Hunger", ["Off", "On"]],
	"window_color": ["Windows", ["Blue", "Red", "Green"]],
	"prepare_screen": ["Prepare screen", ["Off", "On"]],     # remake: the Prepare screen after the world map
	"qol_statusfade": ["Burn/poison wear off", ["Off", "On"]],   # remake: as in the later PMD games
	"qol_recruit": ["Recruiting", ["Red", "DX"]],
	"qol_partner_ai": ["Partner AI", ["Red", "Smarter"]],       # remake: smarter Let's go together!               # remake: Rescue Team DX's temporary recruits
}
const PAGES := {"Dungeon": ["msg_speed", "far_off_pals", "damage_turn", "grids", "map_mode", "hunger", "qol_statusfade", "qol_recruit", "qol_partner_ai"], "Others": ["window_color", "prepare_screen", "second_screen", "ui_scale"]}

static func value(k: String) -> int:
	var v = Game.settings.get(k, DEFAULTS.get(k, 0))
	if v is bool:
		return 1 if v else 0
	if k == "window_color":
		return UITheme.window_color_index()
	if k == "ui_scale":
		return UITheme.ui_scale_index()
	return int(v)

static func _store(k: String, v: int) -> void:
	if k == "ui_scale":
		UITheme.set_ui_scale_index(v)
		return
	if DEFAULTS.get(k, 0) is bool:
		Game.settings[k] = v != 0
	else:
		Game.settings[k] = v

static func _choice(opts: Array, cur: int) -> String:
	var out: Array = []
	for k in opts.size():
		out.append(("[color=#ffdc4a]%s[/color]" if k == cur else "[color=#8890b0]%s[/color]") % opts[k])
	return "  ".join(out)

static func open(root: Control) -> void:
	var sel := 0
	while true:
		var m := TeamScreens.menu(RedText.get_text("options_menu2:sGameOptions"), ["Dungeon", "Others", "Controls", "Default"], 12 * 8 * P)
		m.sel = sel
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		if r.act != "pick":
			return
		sel = int(r.i)
		match sel:
			0: await page(root, "Dungeon")
			1: await page(root, "Others")
			2: await Controls.menu(root)
			3:
				if await RedText.ask(root, "Reset the options to their default setting?", "", "", ["Yes", "No"], {}, 1) == 0:
					for k in DEFAULTS:
						Game.settings[k] = DEFAULTS[k]
					UITheme.sync_window_color()
					Game.save_game()
		if TeamScreens.auto_on():
			return

static func page(root: Control, title: String) -> void:
	var keys: Array = PAGES[title]
	var vals := {}
	for k in keys:
		if k != "second_screen":
			vals[k] = value(k)
	var orig := vals.duplicate()
	var sel := 0
	while true:
		var rows: Array = []
		for k in keys:
			if k == "second_screen":
				rows.append({"text": "Second screen", "right": "[color=#ffdc4a]%s[/color]" % BottomScreen.setting_label()})
			elif k == "ui_scale":
				rows.append({"text": "Menu size", "right": UITheme.slider_text(int(vals[k]))})
			else:
				rows.append({"text": ROWS[k][0], "right": _choice(ROWS[k][1], int(vals[k]))})
		var m := TeamScreens.menu(title, rows, mini(24 * 8 * P, int(root.get_viewport_rect().size.x) - 4 * 8 * P))   # fits at any menu size
		m.lr = true
		m.sel = sel
		var r := await TeamScreens.run_menu(root, m, Vector2(2 * 8 * P, 2 * 8 * P))
		sel = int(r.get("i", sel))
		if r.act == "left" or r.act == "right":
			var k: String = keys[sel]
			var d := -1 if r.act == "left" else 1
			if k == "second_screen":
				BottomScreen.cycle_setting()
			elif k == "ui_scale":
				vals[k] = clampi(int(vals[k]) + d, 0, UITheme.UI_SCALE_STEPS)     # a slider: no wrap
			else:
				var n: int = ROWS[k][1].size()
				vals[k] = (int(vals[k]) + d + n) % n      # Red wraps (Blue <-> Green)
			continue
		break
	if vals == orig:
		return
	if await RedText.ask(root, RedText.get_text("options_menu1:sChangeSettingsPrompt"), "", "", ["Yes", "No"]) == 0:
		for k in vals:
			_store(k, int(vals[k]))
		UITheme.sync_window_color()
		Game.save_game()
