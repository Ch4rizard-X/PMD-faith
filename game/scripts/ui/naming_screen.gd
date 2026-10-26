class_name NamingScreen
extends Control
## Red's naming screen (naming_screen.c) with the confirm step of confirm_name_menu.c.
##
##   var nm := await NamingScreen.ask(root, NamingScreen.SELF, "Pikachu")        # hero / partner / recruits
##   var tn := await NamingScreen.ask(root, NamingScreen.TEAM, "")               # team name
##   var pw := await NamingScreen.ask(root, NamingScreen.PASSWORD2, "", true)    # Wonder Mail (24 symbols)
##
## Returns the entered text, or "" when cancelled (only possible with can_cancel: B on an empty name, as
## Red's textbox does when its unk424 flag is set). Name modes loop until a name is confirmed: an empty
## name gives "Please enter a name.", one wider than 60 px "This name is too long.", then
## "Is the name X OK?" Yes / No (No goes back to the keyboard with the name kept). Password modes return as
## soon as all slots are filled and END is chosen.
##
## Layout: Red's two borderless windows (name window + 28x9-tile letter window), drawn at Red's pixel
## coordinates times UITheme.PX. The 160 px tall GBA screen is fitted into the 135 px tall UI by moving the
## two windows closer together. ♂ / ♀ are stored as the real symbols (as in species names).
## Controls: D-pad moves, A types, B deletes, Start jumps to END, L / R move the letter cursor; taps work too.

enum { SELF, TEAM, POKEMON, PARTNER, PASSWORD1, PASSWORD2 }

signal _done(result)

const MAX_NAME_WIDTH := 60           # GetMaxPokeNameWidth
const L_DEL := 0x105
const L_END := 0x106
const L_INS := 0x107
const L_BLANK := 0x108
## sLayoutInfo[0]: [up, down, left, right, x, y, colorType, letter] (letter: char code or L_*)
const LAYOUT := [
	[0, 0, 0, 0, 8, 3, 0, L_BLANK], [0, 0, 0, 0, 8, 14, 0, L_BLANK], [0, 0, 0, 0, 8, 25, 0, L_BLANK],
	[5, 4, 81, 9, 8, 36, 3, L_INS], [3, 5, 82, 10, 8, 47, 3, L_DEL], [4, 3, 83, 11, 8, 58, 3, L_END],
	[11, 7, 78, 12, 36, 3, 0, 97], [6, 8, 79, 13, 36, 14, 0, 110], [7, 9, 80, 14, 36, 25, 0, 65], [8, 10, 3, 15, 36, 36, 0, 78],
	[9, 11, 4, 16, 36, 47, 0, 233], [10, 6, 5, 17, 36, 58, 0, 43],
	[17, 13, 6, 18, 50, 3, 0, 98], [12, 14, 7, 19, 50, 14, 0, 111], [13, 15, 8, 20, 50, 25, 0, 66], [14, 16, 9, 21, 50, 36, 0, 79],
	[15, 17, 10, 22, 50, 47, 0, 49], [16, 12, 11, 23, 50, 58, 0, 45],
	[23, 19, 12, 24, 64, 3, 0, 99], [18, 20, 13, 25, 64, 14, 0, 112], [19, 21, 14, 26, 64, 25, 0, 67], [20, 22, 15, 27, 64, 36, 0, 80],
	[21, 23, 16, 28, 64, 47, 0, 50], [22, 18, 17, 29, 64, 58, 0, 44],
	[29, 25, 18, 30, 78, 3, 0, 100], [24, 26, 19, 31, 78, 14, 0, 113], [25, 27, 20, 32, 78, 25, 0, 68], [26, 28, 21, 33, 78, 36, 0, 81],
	[27, 29, 22, 34, 78, 47, 0, 51], [28, 24, 23, 35, 78, 58, 0, 46],
	[35, 31, 24, 36, 92, 3, 0, 101], [30, 32, 25, 37, 92, 14, 0, 114], [31, 33, 26, 38, 92, 25, 0, 69], [32, 34, 27, 39, 92, 36, 0, 82],
	[33, 35, 28, 40, 92, 47, 0, 52], [34, 30, 29, 41, 92, 58, 0, 33],
	[41, 37, 30, 42, 106, 3, 0, 102], [36, 38, 31, 43, 106, 14, 0, 115], [37, 39, 32, 44, 106, 25, 0, 70], [38, 40, 33, 45, 106, 36, 0, 83],
	[39, 41, 34, 46, 106, 47, 0, 53], [40, 36, 35, 47, 106, 58, 0, 63],
	[47, 43, 36, 48, 120, 3, 0, 103], [42, 44, 37, 49, 120, 14, 0, 116], [43, 45, 38, 50, 120, 25, 0, 71], [44, 46, 39, 51, 120, 36, 0, 84],
	[45, 47, 40, 52, 120, 47, 0, 54], [46, 42, 41, 53, 120, 58, 0, 145],
	[53, 49, 42, 54, 134, 3, 0, 104], [48, 50, 43, 55, 134, 14, 0, 117], [49, 51, 44, 56, 134, 25, 0, 72], [50, 52, 45, 57, 134, 36, 0, 85],
	[51, 53, 46, 58, 134, 47, 0, 55], [52, 48, 47, 59, 134, 58, 0, 146],
	[59, 55, 48, 60, 148, 3, 0, 105], [54, 56, 49, 61, 148, 14, 0, 118], [55, 57, 50, 62, 148, 25, 0, 73], [56, 58, 51, 63, 148, 36, 0, 86],
	[57, 59, 52, 64, 148, 47, 0, 56], [58, 54, 53, 65, 148, 58, 0, 147],
	[65, 61, 54, 66, 162, 3, 0, 106], [60, 62, 55, 67, 162, 14, 0, 119], [61, 63, 56, 68, 162, 25, 0, 74], [62, 64, 57, 69, 162, 36, 0, 87],
	[63, 65, 58, 70, 162, 47, 0, 57], [64, 60, 59, 71, 162, 58, 0, 148],
	[71, 67, 60, 72, 176, 3, 0, 107], [66, 68, 61, 73, 176, 14, 0, 120], [67, 69, 62, 74, 176, 25, 0, 75], [68, 70, 63, 75, 176, 36, 0, 88],
	[69, 71, 64, 76, 176, 47, 0, 48], [70, 66, 65, 77, 176, 58, 0, 189],
	[77, 73, 66, 78, 190, 3, 0, 108], [72, 74, 67, 79, 190, 14, 0, 121], [73, 75, 68, 80, 190, 25, 0, 76], [74, 76, 69, 81, 190, 36, 0, 89],
	[75, 77, 70, 82, 190, 47, 0, 58], [76, 72, 71, 83, 190, 58, 0, 190],
	[83, 79, 72, 6, 204, 3, 0, 109], [78, 80, 73, 7, 204, 14, 0, 122], [79, 81, 74, 8, 204, 25, 0, 77], [80, 82, 75, 3, 204, 36, 0, 90],
	[81, 83, 76, 4, 204, 47, 0, 133], [82, 78, 77, 5, 204, 58, 0, 32],
]
## Red's extended letters -> text (♂ / ♀ = Red 0xBD / 0xBE)
const SPECIAL_CHARS := {233: "é", 145: "‘", 146: "’", 147: "“", 148: "”", 189: "♂", 190: "♀", 133: "…"}
## Wonder Mail / rescue password symbols (sUnknown_80F42F0 entries that aren't 0xFF)
const PASSWORD_CHARS := "!+-0123456789?CFHJKMNPQRSTWXY…♂♀"
const PW1_POS := [[3, 13], [15, 13], [27, 13], [39, 13], [51, 13], [64, 15], [76, 15], [88, 15], [100, 15], [112, 15], [124, 15],
	[136, 15], [148, 15], [161, 13], [173, 13], [185, 13], [197, 13], [209, 13], [3, 26], [15, 26], [27, 26], [39, 26], [51, 26],
	[64, 28], [76, 28], [88, 28], [100, 28], [112, 28], [124, 28], [136, 28], [148, 28], [161, 26], [173, 26], [185, 26],
	[197, 26], [209, 26], [3, 40], [15, 40], [27, 40], [39, 40], [51, 40], [64, 42], [76, 42], [88, 42], [100, 42], [112, 42],
	[124, 42], [136, 42], [148, 42], [161, 40], [173, 40], [185, 40], [197, 40], [209, 40]]
const PW2_POS := [[32, 18], [46, 18], [60, 18], [74, 18], [88, 20], [102, 20], [116, 20], [130, 20], [144, 18], [158, 18],
	[172, 18], [186, 18], [32, 36], [46, 36], [60, 36], [74, 36], [88, 38], [102, 38], [116, 38], [130, 38], [144, 36], [158, 36],
	[172, 36], [186, 36]]
const PROMPTS := ["What is your name?", "What is your team's name?", "What is this Pokémon's nickname?",
	"What is your partner's nickname?", "Please enter the password.", "Please enter the password."]
## font palette 15 entries used here (fontpal[16..31])
const C_RED := Color8(255, 135, 95)
const C_GREEN := Color8(95, 255, 95)
const C_CYAN := Color8(7, 255, 255)
const C_YELLOW := Color8(255, 255, 7)
const C_WHITE := Color8(255, 255, 255)
const C_SHADOW := Color8(71, 71, 71)
const C_LINE := Color8(103, 135, 255)

var mode := SELF
var can_cancel := false
var max_letters := 10
var text: Array = []                 # one string per slot, "" = empty
var letter_pos := 0                  # letterCursorPos
var input_pos := 6                   # inputCursorPosition (index into LAYOUT)
var insert := false                  # INS / OVR
var _frames := 0
var _in_frames := 0
var _finished := false
var _sp: Texture2D                   # fontsp (cursors)

static var auto_answer := ""         # tests: returned instead of opening the screen when menus run themselves

# ------------------------------------------------------------------ API
static func ask(root: Control, m: int, default_name := "", cancel := false) -> String:
	if Dialog.auto or ListMenu.auto:
		if auto_answer != "":
			return auto_answer
		return default_name if default_name != "" or m >= PASSWORD1 else "Team"
	var cur := _clean(default_name)
	while true:
		var ns := NamingScreen.new()
		ns.mode = m
		ns.can_cancel = cancel
		ns._setup(cur)
		root.add_child(ns)
		var r = await ns._done
		ns.queue_free()
		if r == null:
			return ""
		cur = str(r)
		if m >= PASSWORD1:
			return cur
		if cur.strip_edges() == "":
			await Dialog.say(root, "Please enter a name.")
			continue
		if text_width(cur) > MAX_NAME_WIDTH:
			await Dialog.say(root, "This name is too long.")
			continue
		var c := await Dialog.ask(root, "Is the name [color=#7fe0ff]%s[/color] OK?" % _shown(cur), ["Yes", "No"])
		if c == 0:
			return cur
	return cur

## Width of a name in Red's font (native 11 px size), for the 60 px limit.
static func text_width(s: String) -> float:
	var f := UITheme.font()
	return f.get_string_size(_shown(s), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE).x / UITheme.PX

## Text as Red's font file draws it (♂ / ♀ sit at ½ / ¾ in pmd_red_text.ttf).
static func _shown(s: String) -> String:
	return s.replace("♂", "½").replace("♀", "¾")

static func _clean(s: String) -> String:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	return re.sub(s, "", true)

func _setup(def: String) -> void:
	match mode:
		PASSWORD1:
			max_letters = 54
			input_pos = 9
		PASSWORD2:
			max_letters = 24
			input_pos = 9
		_:
			max_letters = 10
			input_pos = 6
	text.resize(max_letters)
	text.fill("")
	var i := 0
	for ch in def:
		if i >= max_letters:
			break
		text[i] = ch
		i += 1
	letter_pos = _len()
	if letter_pos == max_letters:
		letter_pos -= 1

func is_password() -> bool:
	return mode >= PASSWORD1

func _len() -> int:
	var n := 0
	for i in max_letters:
		if text[i] == "":
			break
		n = i + 1
	return n

func value() -> String:
	return "".join(PackedStringArray(text.slice(0, _len())))

static func letter_text(code: int) -> String:
	if SPECIAL_CHARS.has(code):
		return SPECIAL_CHARS[code]
	return char(code)

func _valid_pw(code: int) -> bool:
	return code <= 0xFF and PASSWORD_CHARS.contains(letter_text(code))

# ------------------------------------------------------------------ node
func _ready() -> void:
	theme = UITheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40
	_sp = load("res://assets/ui/front/fontsp.png")

func _process(_dt: float) -> void:
	_frames += 1
	_in_frames += 1
	queue_redraw()

## Red-pixel origin of the 240 x 135 area (centred in a wider / taller viewport).
func _origin() -> Vector2:
	var vs := get_viewport_rect().size / UITheme.PX
	return Vector2(floorf((vs.x - 240) / 2), floorf((vs.y - 135) / 2))

func _name_win() -> Rect2:
	return Rect2(8, 2, 224, 56) if is_password() else Rect2(32, 8, 176, 40)

func _input_win() -> Rect2:
	return Rect2(8, 62, 224, 72) if is_password() else Rect2(8, 56, 224, 72)

func _p(v: Vector2) -> Vector2:
	return (_origin() + v) * UITheme.PX

# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if _finished or not is_visible_in_tree():
		return
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_BACKSPACE:
		_press_b()
	elif e.is_action_pressed("ui_up") or e.is_action_pressed("move_up"):
		_move(0)
	elif e.is_action_pressed("ui_down") or e.is_action_pressed("move_down"):
		_move(1)
	elif e.is_action_pressed("ui_left") or e.is_action_pressed("move_left"):
		_move(2)
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("move_right"):
		_move(3)
	elif e.is_action_pressed("ui_accept") or e.is_action_pressed("act_attack"):
		_press_a()
	elif e.is_action_pressed("ui_cancel") or e.is_action_pressed("act_run"):
		_press_b()
	elif e.is_action_pressed("act_menu") or e.is_action_pressed("gp_start"):
		Audio.sfx("cursor")
		input_pos = 5
		_in_frames = 8
	elif e.is_action_pressed("gp_l") or (e is InputEventKey and e.pressed and e.keycode == KEY_PAGEUP):
		if letter_pos == 0:
			Audio.sfx("error")
		else:
			letter_pos -= 1
			Audio.sfx("cursor")
	elif e.is_action_pressed("gp_r") or (e is InputEventKey and e.pressed and e.keycode == KEY_PAGEDOWN):
		if letter_pos != max_letters - 1 and letter_pos < _len():
			letter_pos += 1
			Audio.sfx("cursor")
		else:
			Audio.sfx("error")
	else:
		return
	get_viewport().set_input_as_handled()

## Taps and clicks: this Control stops mouse input (so the screen under it can't be clicked), which means
## they arrive here as GUI input, never in _unhandled_input. Touch reaches it as an emulated mouse press.
func _gui_input(e: InputEvent) -> void:
	if _finished or not is_visible_in_tree():
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_tap(e.position)
		accept_event()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		_press_b()
		accept_event()

func _move(dir: int) -> void:
	var n: int = LAYOUT[input_pos][dir]
	if n != input_pos:
		input_pos = n
		Audio.sfx("cursor")
		_in_frames = 8

func _tap(pos: Vector2) -> void:
	var o := _origin()
	var rp := pos / UITheme.PX - o
	var iw := _input_win()
	for i in range(3, LAYOUT.size()):
		var L: Array = LAYOUT[i]
		var w := 26 if int(L[7]) > 0xFF else 12
		if Rect2(iw.position + Vector2(L[4] - 2, L[5] - 1), Vector2(w, 11)).has_point(rp):
			input_pos = i
			_in_frames = 8
			_press_a()
			return
	var nw := _name_win()
	for i in max_letters:
		if Rect2(nw.position + _slot_pos(i) - Vector2(1, 1), Vector2(12, 14)).has_point(rp):
			letter_pos = mini(i, mini(_len(), max_letters - 1))
			Audio.sfx("cursor")
			return

func _press_a() -> void:
	var letter: int = LAYOUT[input_pos][7]
	match letter:
		L_INS:
			insert = not insert
			Audio.sfx("confirm")
		L_DEL:
			_press_b()
		L_END:
			if _len() == 0 or (is_password() and _len() != max_letters):
				Audio.sfx("error")
			else:
				Audio.sfx("confirm")
				_finished = true
				_done.emit(value())
		_:
			if is_password() and not _valid_pw(letter):
				Audio.sfx("error")
				return
			if insert:
				for i in range(max_letters - 2, letter_pos - 1, -1):
					text[i + 1] = text[i]
			text[letter_pos] = letter_text(letter)
			if letter_pos < max_letters - 1:
				letter_pos += 1
			else:
				input_pos = 5
			Audio.sfx("confirm")

func _press_b() -> void:
	if text[letter_pos] == "":
		if letter_pos == 0:
			Audio.sfx("error")
			if can_cancel:
				_finished = true
				_done.emit(null)
			return
		letter_pos -= 1
		text[letter_pos] = ""
		Audio.sfx("cancel")
	else:
		var n := _len() - 1
		for i in range(letter_pos, n):
			text[i] = text[i + 1]
		text[n] = ""
		Audio.sfx("cancel")

# ------------------------------------------------------------------ drawing
func _hline(o: Vector2, x: float, y: float, w: float, c: Color) -> void:
	draw_rect(Rect2((o + Vector2(x, y)) * UITheme.PX, Vector2(w, 1) * UITheme.PX), c)

func _vline(o: Vector2, x: float, y: float, h: float, c: Color) -> void:
	draw_rect(Rect2((o + Vector2(x, y)) * UITheme.PX, Vector2(1, h) * UITheme.PX), c)

func _str(o: Vector2, x: float, y: float, s: String, c: Color) -> float:
	var f := UITheme.font()
	var base := (o + Vector2(x, y)) * UITheme.PX + Vector2(0, f.get_ascent(UITheme.FONT_SIZE))
	draw_string(f, base + Vector2(UITheme.PX, UITheme.PX), _shown(s), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE, C_SHADOW)
	draw_string(f, base, _shown(s), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE, c)
	return f.get_string_size(_shown(s), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE).x / UITheme.PX

## DrawCharOnWindowWidth12: one letter centred in a 12 px cell
func _char12(o: Vector2, x: float, y: float, s: String, c: Color) -> void:
	var w := UITheme.font().get_string_size(_shown(s), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE).x / UITheme.PX
	_str(o, x + floorf((12 - w) / 2), y, s, c)

## fontsp tile(s): n tiles wide starting at tile t
func _sprite(px: Vector2, t: int, n: int, vflip := false) -> void:
	if _sp == null:
		return
	var dst := Rect2(px * UITheme.PX, Vector2(8 * n, 8) * UITheme.PX)
	if vflip:
		dst = Rect2(dst.position + Vector2(0, dst.size.y), Vector2(dst.size.x, -dst.size.y))
	draw_texture_rect_region(_sp, dst, Rect2(t * 8, 0, 8 * n, 8))

func _window(r: Rect2, o: Vector2) -> void:
	draw_rect(Rect2((o + r.position) * UITheme.PX, r.size * UITheme.PX), UITheme.window_bg())
	_hline(o + r.position, 0, 0, r.size.x, C_LINE)
	_hline(o + r.position, 0, r.size.y - 1, r.size.x, C_LINE)
	_vline(o + r.position, 0, 0, r.size.y, C_LINE)
	_vline(o + r.position, r.size.x - 1, 0, r.size.y, C_LINE)

func _slot_pos(i: int) -> Vector2:
	if mode == PASSWORD1:
		return Vector2(PW1_POS[i][0], PW1_POS[i][1])
	if mode == PASSWORD2:
		return Vector2(PW2_POS[i][0], PW2_POS[i][1])
	var x := 38.0
	for k in i:
		x += _w(text[k]) if text[k] != "" else 8.0
	return Vector2(x, 22)

func _w(s: String) -> float:
	return UITheme.font().get_string_size(_shown(s), HORIZONTAL_ALIGNMENT_LEFT, -1, UITheme.FONT_SIZE).x / UITheme.PX

func _draw() -> void:
	var o := _origin()
	# --- name window
	var nw := _name_win()
	_window(nw, o)
	var no := o + nw.position
	match mode:
		PASSWORD1:
			_str(no, 54, 2, PROMPTS[mode], C_WHITE)
		PASSWORD2:
			_str(no, 48, 4, PROMPTS[mode], C_WHITE)
		_:
			_str(no, 8, 5, PROMPTS[mode], C_WHITE)
	if is_password():
		var pos: Array = PW1_POS if mode == PASSWORD1 else PW2_POS
		var uw := 11 if mode == PASSWORD1 else 12
		for i in pos.size():
			_hline(no, pos[i][0], pos[i][1] + 11, uw, C_CYAN)
			_hline(no, pos[i][0], pos[i][1] + 12, uw, C_SHADOW)
		for i in pos.size():
			if text[i] == "":
				break
			var c := C_WHITE
			if mode == PASSWORD1:
				c = C_YELLOW if (i >= 5 and i <= 12) or (i >= 23 and i <= 30) or (i >= 41 and i <= 48) else C_WHITE
			else:
				c = C_YELLOW if (i >= 4 and i <= 7) or (i >= 16 and i <= 19) else C_WHITE
			_char12(no, pos[i][0], pos[i][1], text[i], c)
		if _frames & 8:
			var sp: Vector2 = _slot_pos(letter_pos)
			_sprite(no + sp + Vector2(0, 5), 6, 2)
	else:
		_hline(no, 38, 33, MAX_NAME_WIDTH, C_GREEN)
		_hline(no, 38, 34, MAX_NAME_WIDTH, C_SHADOW)
		var v := value()
		var col := C_WHITE
		if text_width(v) > MAX_NAME_WIDTH:
			col = C_RED
		elif _len() == max_letters:
			col = C_CYAN
		_str(no, 38, 22, v, col)
		if _frames & 8:
			var lx := _slot_pos(letter_pos).x
			var lw := _w(text[letter_pos]) if text[letter_pos] != "" else 8.0
			_sprite(no + Vector2(lx + floorf(lw / 2) - 8, 34), 0, 2, true)
	# --- letter window
	var iw := _input_win()
	_window(iw, o)
	var io := o + iw.position
	for i in range(LAYOUT.size()):
		var L: Array = LAYOUT[i]
		var letter: int = L[7]
		if letter == L_BLANK:
			continue
		var c := C_WHITE
		if int(L[6]) == 0 and is_password() and letter <= 0xFF and not _valid_pw(letter):
			c = C_RED
		if letter == L_INS:
			_str(io, L[4] + 3, L[5], "INS" if insert else "OVR", C_YELLOW if insert else C_GREEN)
		elif letter == L_DEL:
			_str(io, L[4] + 3, L[5], "DEL", c)
		elif letter == L_END:
			_str(io, L[4] + 3, L[5], "END", c)
		elif letter == 32:
			# {0x81}{0x59}: Red's open-box space glyph
			_vline(io, L[4] + 1, L[5] + 7, 3, C_SHADOW)
			_vline(io, L[4] + 2, L[5] + 8, 3, C_SHADOW)
			_vline(io, L[4] + 10, L[5] + 7, 3, C_SHADOW)
			_hline(io, L[4] + 2, L[5] + 10, 10, C_SHADOW)
			_vline(io, L[4] + 1, L[5] + 7, 3, c)
			_vline(io, L[4] + 10, L[5] + 7, 3, c)
			_hline(io, L[4] + 1, L[5] + 9, 10, c)
		else:
			_char12(io, L[4], L[5], letter_text(letter), c)
	if _in_frames & 8:
		var cl: Array = LAYOUT[input_pos]
		_sprite(io + Vector2(cl[4] - 5, cl[5] + 1), 4, 1)
