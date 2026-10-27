class_name Controls
extends RefCounted
## Key and controller bindings. Controller buttons are mapped to Red's GBA buttons (A, B, L, R, Start,
## Select) plus X/Y extras; the dungeon reads those exactly like Red does (see Dungeon._pad_event).
## Bindings are saved in Game.settings.binds and can be changed in the Controls screen.

const KEY_ACTIONS := [
	["move_up", "Move up"], ["move_down", "Move down"], ["move_left", "Move left"], ["move_right", "Move right"],
	["move_ul", "Move up-left"], ["move_ur", "Move up-right"], ["move_dl", "Move down-left"], ["move_dr", "Move down-right"],
	["act_attack", "Attack / Talk / OK"], ["act_menu", "Menu / Back"], ["act_run", "Run (hold)"], ["act_moves", "Moves"],
	["act_bag", "Items"], ["act_wait", "Wait a turn"], ["act_turn", "Turn in place (hold)"], ["act_diag", "Diagonal only (hold)"],
	["act_map", "Map"], ["act_auto", "Autoplay"], ["act_setmove", "Use set move"], ["act_log", "Message log"],
]
const PAD_ACTIONS := [
	["gp_a", "A button"], ["gp_b", "B button"], ["gp_l", "L button"], ["gp_r", "R button"],
	["gp_start", "Start"], ["gp_select", "Select"], ["gp_x", "X (Moves)"], ["gp_y", "Y (Items)"],
]
const DEFAULT_KEYS := {
	"move_up": [KEY_UP, KEY_W, KEY_KP_8], "move_down": [KEY_DOWN, KEY_S, KEY_KP_2], "move_left": [KEY_LEFT, KEY_A, KEY_KP_4],
	"move_right": [KEY_RIGHT, KEY_D, KEY_KP_6], "move_ul": [KEY_Q, KEY_KP_7], "move_ur": [KEY_E, KEY_KP_9], "move_dl": [KEY_Z, KEY_KP_1],
	"move_dr": [KEY_C, KEY_KP_3], "act_attack": [KEY_SPACE, KEY_J], "act_menu": [KEY_X, KEY_ESCAPE], "act_run": [KEY_SHIFT],
	"act_moves": [KEY_M, KEY_K], "act_bag": [KEY_I, KEY_B], "act_wait": [KEY_PERIOD, KEY_KP_5], "act_turn": [KEY_CTRL, KEY_R],
	"act_diag": [KEY_ALT], "act_map": [KEY_TAB], "act_auto": [KEY_P], "act_setmove": [KEY_F], "act_log": [KEY_L],
}
const DEFAULT_PAD := {
	"gp_a": JOY_BUTTON_A, "gp_b": JOY_BUTTON_B, "gp_l": JOY_BUTTON_LEFT_SHOULDER, "gp_r": JOY_BUTTON_RIGHT_SHOULDER,
	"gp_start": JOY_BUTTON_START, "gp_select": JOY_BUTTON_BACK, "gp_x": JOY_BUTTON_X, "gp_y": JOY_BUTTON_Y,
}
const STICK_DEADZONE := 0.5

static func binds() -> Dictionary:
	var b = Game.settings.get("binds", {})
	return b if b is Dictionary else {}

static func keys_for(a: String) -> Array:
	var b := binds()
	if b.has("k_" + a):
		return b["k_" + a]
	return DEFAULT_KEYS.get(a, [])

static func pad_for(a: String) -> int:
	var b := binds()
	if b.has("p_" + a):
		return int(b["p_" + a])
	return int(DEFAULT_PAD.get(a, -1))

static func set_key(a: String, slot: int, keycode: int) -> void:
	var b := binds()
	var ks: Array = keys_for(a).duplicate()
	while ks.size() <= slot:
		ks.append(0)
	ks[slot] = keycode
	b["k_" + a] = ks
	Game.settings.binds = b
	apply()

static func set_pad(a: String, button: int) -> void:
	var b := binds()
	# swap with whichever action already used this button
	for o in DEFAULT_PAD:
		if o != a and pad_for(o) == button:
			b["p_" + o] = pad_for(a)
	b["p_" + a] = button
	Game.settings.binds = b
	apply()

static func reset() -> void:
	Game.settings.binds = {}
	apply()

## (Re)build the InputMap from the bindings.
static func apply() -> void:
	for pair in KEY_ACTIONS:
		_reset_action(pair[0])
		for k in keys_for(pair[0]):
			if int(k) <= 0:
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(pair[0], ev)
	for pair in PAD_ACTIONS:
		_reset_action(pair[0])
		_pad_ev(pair[0], pad_for(pair[0]))
	# D-pad and left stick move
	for m in [["move_up", JOY_BUTTON_DPAD_UP, JOY_AXIS_LEFT_Y, -1.0], ["move_down", JOY_BUTTON_DPAD_DOWN, JOY_AXIS_LEFT_Y, 1.0],
			["move_left", JOY_BUTTON_DPAD_LEFT, JOY_AXIS_LEFT_X, -1.0], ["move_right", JOY_BUTTON_DPAD_RIGHT, JOY_AXIS_LEFT_X, 1.0]]:
		_pad_ev(m[0], m[1])
		var ax := InputEventJoypadMotion.new()
		ax.axis = m[2]
		ax.axis_value = m[3]
		InputMap.action_add_event(m[0], ax)
		InputMap.action_set_deadzone(m[0], STICK_DEADZONE)
	# the town and menus use the generic actions: give them the GBA-mapped buttons too
	_pad_ev("act_attack", pad_for("gp_a"))
	_pad_ev("act_run", pad_for("gp_b"))
	_pad_ev("act_menu", pad_for("gp_start"))
	_pad_ev("act_map", pad_for("gp_select"))
	for ui in ["ui_accept", "ui_cancel"]:
		for ev in InputMap.action_get_events(ui):
			if ev is InputEventJoypadButton:
				InputMap.action_erase_event(ui, ev)
	_pad_ev("ui_accept", pad_for("gp_a"))
	_pad_ev("ui_cancel", pad_for("gp_b"))

static func _reset_action(a: String) -> void:
	if InputMap.has_action(a):
		InputMap.action_erase_events(a)
	else:
		InputMap.add_action(a)

static func _pad_ev(a: String, button: int) -> void:
	if button < 0:
		return
	if not InputMap.has_action(a):
		InputMap.add_action(a)
	var jb := InputEventJoypadButton.new()
	jb.button_index = button
	InputMap.action_add_event(a, jb)

static func key_name(k: int) -> String:
	if k <= 0:
		return "-"
	return OS.get_keycode_string(k)

static func pad_name(b: int) -> String:
	var names := {JOY_BUTTON_A: "A / Cross", JOY_BUTTON_B: "B / Circle", JOY_BUTTON_X: "X / Square", JOY_BUTTON_Y: "Y / Triangle",
		JOY_BUTTON_LEFT_SHOULDER: "LB / L1", JOY_BUTTON_RIGHT_SHOULDER: "RB / R1", JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Select / Back",
		JOY_BUTTON_LEFT_STICK: "L-Stick press", JOY_BUTTON_RIGHT_STICK: "R-Stick press", JOY_BUTTON_GUIDE: "Home",
		JOY_BUTTON_DPAD_UP: "D-Up", JOY_BUTTON_DPAD_DOWN: "D-Down", JOY_BUTTON_DPAD_LEFT: "D-Left", JOY_BUTTON_DPAD_RIGHT: "D-Right"}
	return names.get(b, "Button %d" % b)

## The Controls screen: pick Keyboard or Controller, pick an action, press the new key/button.
static func menu(root: Control) -> void:
	while true:
		var c := await Dialog.ask(root, "Controls", ["Keyboard", "Controller", "Controller help", "Reset to default", "Done"])
		match c:
			0:
				await _remap_list(root, false)
			1:
				await _remap_list(root, true)
			2:
				await Dialog.talk(root, [
					"Controller (Red's GBA controls):\nA: attack / talk.  A+B together: wait a turn.\nL+A / L+B / L+X / L+Y: use move 1 / 2 / 3 / 4.",
					"Tap B: menu.  Hold B + direction: run.\nHold R: diagonal moves only.\nTap R: face the nearest foe.  Start: turn in place.",
					"L+Select: message log.  L+R: throw the set item.\nSelect: map.  X: moves.  Y: items."])
			3:
				reset()
				Game.save_game()
				await Dialog.say(root, "Controls were reset.")
			_:
				Game.save_game()
				return

static func _remap_list(root: Control, pad: bool) -> void:
	var list: Array = PAD_ACTIONS if pad else KEY_ACTIONS
	var sel := 0
	while true:
		var opts: Array = []
		for pair in list:
			var cur := pad_name(pad_for(pair[0])) if pad else " / ".join(keys_for(pair[0]).map(func(k): return key_name(int(k))))
			opts.append("%-20s %s" % [pair[1], cur])
		var lm := ListMenu.make("Controller buttons" if pad else "Keyboard keys", opts)
		root.add_child(lm)
		lm.position = Vector2(8, 4)
		lm._set_sel.call_deferred(sel)
		var i := await lm.choose()
		if i < 0:
			return
		sel = i
		var a: String = list[i][0]
		var slot := 0
		if not pad and keys_for(a).size() > 1:
			var s := await Dialog.ask(root, "Change which key for %s?" % list[i][1], ["First (%s)" % key_name(int(keys_for(a)[0])), "Second (%s)" % key_name(int(keys_for(a)[1]))])
			if s < 0:
				continue
			slot = s
		var got: int = await _capture(root, pad, "Press the new %s for\n%s...\n(wait 5 seconds to cancel)" % ["button" if pad else "key", list[i][1]])
		if got < 0:
			continue
		if pad:
			set_pad(a, got)
		else:
			set_key(a, slot, got)
		Audio.sfx("confirm")

## Waits for one key or controller button press. Returns its code, or -1 after 5 s.
static func _capture(root: Control, pad: bool, prompt: String) -> int:
	var cap := _Capture.new()
	cap.pad = pad
	root.add_child(cap)
	var box := Dialog.get_box(root)
	box._show(prompt, "", "Normal", "")
	box._finish_typing()
	var t := root.get_tree().create_timer(5.0)
	t.timeout.connect(func(): cap.done.emit(-1))
	var r: int = await cap.done
	cap.queue_free()
	box.hide_box()
	return r

class _Capture extends Node:
	signal done(code: int)
	var pad := false
	var _sent := false
	func _input(e: InputEvent) -> void:
		if _sent:
			return
		if not pad and e is InputEventKey and e.pressed and not e.echo:
			_sent = true
			get_viewport().set_input_as_handled()
			done.emit(e.physical_keycode if e.physical_keycode != 0 else e.keycode)
		elif pad and e is InputEventJoypadButton and e.pressed:
			_sent = true
			get_viewport().set_input_as_handled()
			done.emit(e.button_index)
