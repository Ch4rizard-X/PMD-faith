class_name FriendRescue
extends RefCounted
## Friend Rescue (friend_rescue.c, rescue_password_menu.c, thank_you_wonder_mail.c, wonder_mail_2.c) played
## locally: there is no link cable, every mail travels as a password (Red's own 54-symbol rescue password
## format: code_803D0D8.c sub_803D2C0 / sub_803D204 with the mail fields of code_8094F88.c sub_8095824, so
## the passwords are those the GBA game makes).
##
##   Get Help:  Send SOS Mail (after the team was defeated) -> password; Receive A-OK Mail (password) -> the
##              team may revive; Send Thank-You Mail -> password (an item from storage can go with it).
##   Go Rescue: Receive SOS Mail (password) -> a rescue job in the Job List; Send A-OK Mail once that job is
##              done -> password; Get Thank-You Mail (password) -> the reward item.
##
##   await FriendRescue.counter(root)       # Pelipper's Friend Rescue counter / the main menu's Friend Rescue
##   FriendRescue.on_defeated(dkey, floor)  # main.gd: the team fainted in a dungeon (an SOS Mail can be sent)
## State: Game.flags.friend_rescue = {sos: {...} | null, sent, revive, rescued_by, thanks_sent, done: [ids]}

const FR := "friend_rescue:"
const CODE_LEN := 54
const TYPE_SOS := 1
const TYPE_AOK := 4
const TYPE_THANK_YOU := 5
const RESCUES_ALLOWED := 10
## gUnknown_80F43F0: password position of symbol i
const SCRAMBLE := [0x0d, 0x07, 0x19, 0x0f, 0x04, 0x1d, 0x2a, 0x31, 0x08, 0x13, 0x2d, 0x18, 0x0e, 0x1a, 0x1b, 0x29, 0x01, 0x20,
	0x21, 0x22, 0x11, 0x33, 0x26, 0x00, 0x35, 0x0a, 0x2b, 0x1f, 0x12, 0x23, 0x2c, 0x17, 0x27, 0x10, 0x1c, 0x30, 0x0b, 0x02,
	0x24, 0x09, 0x32, 0x05, 0x28, 0x34, 0x2e, 0x03, 0x1e, 0x0c, 0x25, 0x14, 0x2f, 0x16, 0x06, 0x15]
## sub_8095824 field order: [name, bits]
const FIELDS := [["mail_type", 4], ["dungeon", 7], ["floor", 7], ["seed", 24], ["client", 9], ["mail_id", 32], ["name", 80],
	["item_flags", 8], ["item_qty", 8], ["item", 8], ["unk24", 32], ["unk28", 32], ["rescues", 8], ["unk2d", 1]]

static func state() -> Dictionary:
	if not Game.flags.get("friend_rescue", null) is Dictionary:
		Game.flags["friend_rescue"] = {"sos": null, "sent": false, "revive": false, "rescued_by": "", "thanks_sent": false, "done": []}
	return Game.flags["friend_rescue"]

static func txt(id: String) -> String:
	return RedText.get_text(FR + id)

# ============================================================================ password codec
static func _bits_put(buf: PackedByteArray, pos: int, value: int, n: int) -> int:
	for b in n:
		if (value >> b) & 1:
			buf[pos >> 3] = buf[pos >> 3] | (1 << (pos & 7))
		pos += 1
	return pos

static func _bits_get(buf: PackedByteArray, pos: int, n: int) -> int:
	var v := 0
	for b in n:
		if (buf[pos >> 3] >> (pos & 7)) & 1:
			v |= 1 << b
		pos += 1
	return v

## Team name -> Red's 10 name bytes (ASCII letters / digits / space map 1:1; the rest becomes '?').
static func _name_bytes(s: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(10)
	for i in mini(10, s.length()):
		var c := s.unicode_at(i)
		b[i] = c if c >= 32 and c < 127 else 63
	return b

static func _name_str(v: PackedByteArray) -> String:
	var s := ""
	for c in v:
		if c == 0:
			break
		s += char(c) if c >= 32 and c < 127 else "?"
	return s

static func encode(f: Dictionary) -> String:
	var data := PackedByteArray()
	data.resize(34)
	var pos := 8
	for fd in FIELDS:
		if fd[0] == "name":
			var nb := _name_bytes(str(f.get("name", "")))
			for c in nb:
				pos = _bits_put(data, pos, c, 8)
			continue
		pos = _bits_put(data, pos, int(f.get(fd[0], 0)) & ((1 << int(fd[1])) - 1), int(fd[1]))
	var sum := 0
	for i in range(1, 34):
		sum += data[i] + i
	data[0] = sum & 0xff
	var plain: Array = []
	for i in CODE_LEN:
		plain.append(WonderMail.CHARSET[_bits_get(data, i * 5, 5)])
	var out: Array = []
	out.resize(CODE_LEN)
	for i in CODE_LEN:
		out[SCRAMBLE[i]] = plain[i]
	return "".join(PackedStringArray(out))

## {} when a symbol is unknown or the checksum is wrong (Red: "This password is incorrect.").
static func decode(code: String) -> Dictionary:
	code = WonderMail.normalize(code)
	if code.length() != CODE_LEN:
		return {}
	var data := PackedByteArray()
	data.resize(35)
	for i in CODE_LEN:
		var v := WonderMail.symbol_value(code[SCRAMBLE[i]])
		if v < 0:
			return {}
		_bits_put(data, i * 5, v, 5)
	var sum := 0
	for i in range(1, 34):
		sum += data[i] + i
	if data[0] != (sum & 0xff):
		return {}
	var f := {}
	var pos := 8
	for fd in FIELDS:
		if fd[0] == "name":
			var nb := PackedByteArray()
			for k in 10:
				nb.append(_bits_get(data, pos, 8))
				pos += 8
			f.name = _name_str(nb)
			continue
		f[fd[0]] = _bits_get(data, pos, int(fd[1]))
		pos += int(fd[1])
	return f

# ============================================================================ events
## The team fainted: Red keeps the place so an SOS Mail can be sent (Get Help).
static func on_defeated(dkey: String, floor_i: int) -> void:
	var d := WonderMail.dungeon_index(dkey)
	if d < 0:
		return
	var s := state()
	s.sos = {"dungeon": d, "floor": floor_i + 1, "seed": randi() & 0xffffff, "mail_id": randi() & 0x7fffffff,
		"client": WonderMail.species_id(str(Game.team[0].sp)) if Game.team.size() > 0 else 0, "name": Game.team_name}
	s.sent = false
	s.revive = false
	s.rescued_by = ""
	s.thanks_sent = false

static func _place(f: Dictionary) -> String:
	var key := WonderMail.dungeon_key(int(f.get("dungeon", 0)))
	return "%s %s" % [Missions.dungeon_name(key), Missions.floor_label(key, int(f.get("floor", 1)))]

# ============================================================================ UI helpers
static func _say(root: Control, id_or_text: String, vars: Dictionary = {}) -> void:
	await RedText.say(root, (FR + id_or_text) if RedText.has(FR + id_or_text) else id_or_text, "", "", vars)

static func _ask(root: Control, id_or_text: String, opts: Array, vars: Dictionary = {}, def := 0) -> int:
	return await RedText.ask(root, (FR + id_or_text) if RedText.has(FR + id_or_text) else id_or_text, "", "", opts, vars, def)

## Red's password window: 3 rows of 18 symbols (5 + 8 + 5, as rescue_password_menu.c lays them out).
static func show_password(root: Control, title: String, code: String) -> void:
	var rows: Array = []
	for r in 3:
		var part := code.substr(r * 18, 18)
		rows.append("%s  %s  %s" % [part.substr(0, 5), part.substr(5, 8), part.substr(13, 5)])
	var body := "[center]%s[/center]" % WonderMail.font_text("\n".join(rows))
	await TeamScreens.run_page(root, TeamScreens.page(title, [body], 26 * 8 * UITheme.PX), Vector2(2, 4) * 8 * UITheme.PX)

## Password entry with Red's naming screen (PASSWORD1 = 54 symbols); "" = cancelled.
static func enter_password(root: Control) -> String:
	return await NamingScreen.ask(root, NamingScreen.PASSWORD1, "", true)

# ============================================================================ counter
static func counter(root: Control) -> void:
	var sel := 0
	while true:
		var c := await _ask(root, "gUnknown_80E25F4", ["Go Rescue", "Get Help", "Info", "Exit"], {}, sel)
		if c < 0 or c == 3:
			return
		sel = c
		match c:
			0: await go_rescue(root)
			1: await get_help(root)
			2: await info(root)
		if TeamScreens.auto_on():
			return

static func info(root: Control) -> void:
	var topics := [["Friend Rescue", "gUnknown_80E3690"], ["Send SOS Mail", "gUnknown_80E3818"], ["Receive A-OK Mail", "gUnknown_80E3998"],
		["Send Thank-You Mail", "gUnknown_80E3B1C"], ["Go Rescue", "gUnknown_80E3BF8"], ["Receive SOS Mail", "gUnknown_80E3DE4"],
		["Send A-OK Mail", "gUnknown_80E3E98"], ["Leave for Rescue", "gUnknown_80E4014"], ["Get Thank-You Mail", "gUnknown_80E4130"]]
	var labels: Array = []
	for t in topics:
		labels.append(t[0])
	labels.append("Exit")
	var sel := 0
	while true:
		var c := await _ask(root, "gUnknown_80E367C", labels, {}, sel)
		if c < 0 or c >= topics.size():
			return
		sel = c
		await _say(root, topics[c][1])
		if TeamScreens.auto_on():
			return

# ---------------------------------------------------------------------------- Get Help
static func get_help(root: Control) -> void:
	var s := state()
	while true:
		var has_sos: bool = s.sos is Dictionary
		var opts: Array = [{"text": "Send SOS Mail", "disabled": not has_sos or s.revive},
			{"text": "Receive A-OK Mail", "disabled": not has_sos or not s.sent or s.revive},
			{"text": "Send Thank-You Mail", "disabled": not s.revive or s.thanks_sent}, "Exit"]
		var c := await _ask(root, "gUnknown_80E25F4", opts)
		if c < 0 or c == 3:
			return
		match c:
			0: await send_sos(root)
			1: await receive_aok(root)
			2: await send_thanks(root)
		if TeamScreens.auto_on():
			return

static func send_sos(root: Control) -> void:
	var s := state()
	if not s.sos is Dictionary:
		return
	var sos: Dictionary = s.sos
	await _say(root, "Place: [color=#7fe0ff]%s[/color]" % _place(sos))
	if await _ask(root, "gUnknown_80E29A0", ["Yes", "No"]) != 0:
		return
	var code := encode({"mail_type": TYPE_SOS, "dungeon": sos.dungeon, "floor": sos.floor, "seed": sos.seed, "client": sos.client,
		"mail_id": sos.mail_id, "name": sos.name, "rescues": RESCUES_ALLOWED})
	s.sent = true
	s.sos_code = code
	Game.save_game()
	await _say(root, "gUnknown_80E29D0")
	await _say(root, "gUnknown_80E2A5C")
	await show_password(root, "SOS Mail", code)
	await _say(root, "gUnknown_80E2A1C")

static func receive_aok(root: Control) -> void:
	var s := state()
	while true:
		await _say(root, "gUnknown_80E2814")
		var code := await enter_password(root)
		if code == "":
			return
		var f := decode(code)
		if f.is_empty():
			if await _ask(root, "gUnknown_80E48A8", ["Yes", "No"]) == 0:
				continue
			return
		if int(f.mail_type) != TYPE_AOK:
			await _say(root, "gUnknown_80E4964")
			return
		if not s.sos is Dictionary or int(f.mail_id) != int(s.sos.mail_id):
			await _say(root, "gUnknown_80E468C")
			return
		await _say(root, "gUnknown_80E2840")
		s.revive = true
		s.rescued_by = str(f.name)
		Game.save_game()
		await _say(root, "gUnknown_80E2898")
		await _say(root, "gUnknown_80E28D8")
		return

static func send_thanks(root: Control) -> void:
	var s := state()
	if not s.sos is Dictionary:
		return
	var item := ""
	var qty := 0
	var ids: Array = []
	for id in Game.storage:
		if int(Game.storage[id]) > 0 and DB.items.has(id) and id != "poke":
			ids.append(id)
	if ids.is_empty():
		var c0 := await _ask(root, "gUnknown_80E339C", ["Send w/o Item", "Cancel"])
		if c0 != 0:
			return
	else:
		var c := await _ask(root, "gUnknown_80E33D8", ["Send Item", "Don't Send Item", "Cancel"])
		if c < 0 or c == 2:
			return
		if c == 0:
			await _say(root, "gUnknown_80E3378")
			var rows: Array = []
			for id in ids:
				rows.append({"text": "%s  %d" % [DB.item_name(id), int(Game.storage[id])]})
			var r := await BaseMenu.paged(root, "Storage", rows)
			if r.act != "pick":
				return
			item = ids[r.i]
			if await _ask(root, "gUnknown_80E331C", ["Yes", "No"]) != 0:
				return
			qty = mini(int(Game.storage[item]), 99) if DB.items.get(item, {}).get("stack", false) else 0
	if await _ask(root, "gUnknown_80E30A4", ["Yes", "No"]) != 0:
		return
	if item != "":
		Game.storage[item] = int(Game.storage[item]) - maxi(1, qty)
		if int(Game.storage[item]) <= 0:
			Game.storage.erase(item)
	var sos: Dictionary = s.sos
	var code := encode({"mail_type": TYPE_THANK_YOU, "dungeon": sos.dungeon, "floor": sos.floor, "seed": sos.seed, "client": sos.client,
		"mail_id": sos.mail_id, "name": Game.team_name, "item_flags": 1 if item != "" else 0, "item_qty": qty,
		"item": WonderMail.item_id(item) if item != "" else 0})
	s.thanks_sent = true
	Game.save_game()
	await _say(root, "gUnknown_80E3248")
	await _say(root, "gUnknown_80E314C")
	await show_password(root, "Thank-You Mail", code)

# ---------------------------------------------------------------------------- Go Rescue
static func sos_jobs() -> Array:
	var out: Array = []
	for j in Game.jobs:
		if j.has("sos"):
			out.append(j)
	return out

static func _done_sos_jobs() -> Array:
	return sos_jobs().filter(func(j): return str(j.get("state", "")) in ["done", "done_pending"])

static func go_rescue(root: Control) -> void:
	var s := state()
	while true:
		var opts: Array = ["Receive SOS Mail", {"text": "Send A-OK Mail", "disabled": _done_sos_jobs().is_empty() and not s.has("aok_ready")},
			"Get Thank-You Mail", "Exit"]
		var c := await _ask(root, "gUnknown_80E25F4", opts)
		if c < 0 or c == 3:
			return
		match c:
			0: await receive_sos(root)
			1: await send_aok(root)
			2: await get_thanks(root)
		if TeamScreens.auto_on():
			return

static func receive_sos(root: Control) -> void:
	while true:
		await _say(root, "gUnknown_80E3078")
		var code := await enter_password(root)
		if code == "":
			return
		var f := decode(code)
		if f.is_empty():
			if await _ask(root, "gUnknown_80E48A8", ["Yes", "No"]) == 0:
				continue
			return
		if int(f.mail_type) != TYPE_SOS:
			await _say(root, "gUnknown_80E48E8")
			return
		var id := "sos-%d" % int(f.mail_id)
		for j in Game.jobs:
			if str(j.get("id", "")) == id:
				await _say(root, "gUnknown_80E460C")
				return
		if int(f.mail_id) in state().get("done", []):
			await _say(root, "gUnknown_80E460C")
			return
		if Game.jobs.size() >= Missions.MAX_JOBS:
			await _say(root, "gUnknown_80E2FA0")
			return
		var j := make_job(f, code)
		if j.is_empty():
			await _say(root, "gUnknown_80E499C")
			return
		Game.jobs.append(j)
		j.state = "taken"
		j.accepted = true
		Game.save_game()
		await _say(root, "gUnknown_80E4928")
		await _say(root, "gUnknown_80E3030")
		return

## A rescue job for the friend's defeated team (client = their leader).
static func make_job(f: Dictionary, code: String) -> Dictionary:
	var dkey := WonderMail.dungeon_key(int(f.dungeon))
	var client := WonderMail.species_key(int(f.client))
	if dkey == "" or client == "" or not DB.species.has(client):
		return {}
	var rewards := WonderMail.wm_reward_items()
	var raw := {"mail_type": 5, "mission": 0, "special": 0, "client": int(f.client), "target": int(f.client), "target_item": 0,
		"reward_type": 2, "item_reward": WonderMail.item_id(str(rewards[int(f.seed) % rewards.size()])) if not rewards.is_empty() else 0,
		"friend_area": 0, "seed": int(f.seed), "dungeon": int(f.dungeon), "floor": int(f.floor)}
	var j := WonderMail.job_from_raw(raw, code.substr(0, 24))
	j.id = "sos-%d" % int(f.mail_id)
	j.wonder_mail = false
	j.source = "sos"
	j.sos = {"mail_id": int(f.mail_id), "team": str(f.name), "seed": int(f.seed), "client": int(f.client)}
	j.title = "Rescue team [color=#7fe0ff]%s[/color]!" % str(f.name)
	j.text = "Team %s was defeated at %s.\nPlease rescue them!" % [str(f.name), _place(f)]
	return j

static func send_aok(root: Control) -> void:
	var done := _done_sos_jobs()
	if done.is_empty():
		await _say(root, "gUnknown_80E2D60")
		return
	await _say(root, "gUnknown_80E2CE8")
	var rows: Array = []
	for j in done:
		rows.append({"text": str(j.sos.team)})
	var r := await BaseMenu.paged(root, "A-OK Mail", rows)
	if r.act != "pick":
		return
	var j: Dictionary = done[r.i]
	if await _ask(root, "gUnknown_80E2D30", ["Yes", "No"]) != 0:
		return
	var sos: Dictionary = j.sos
	var code := encode({"mail_type": TYPE_AOK, "dungeon": WonderMail.dungeon_index(str(j.dungeon)), "floor": int(j.floor), "seed": int(sos.seed),
		"client": int(sos.client), "mail_id": int(sos.mail_id), "name": Game.team_name, "rescues": RESCUES_ALLOWED})
	var st := state()
	if not int(sos.mail_id) in st.done:
		st.done.append(int(sos.mail_id))
		if ResourceLoader.exists("res://scripts/ui/adventure_log.gd"):
			var AL = load("res://scripts/ui/adventure_log.gd")
			if AL and AL.has_method("add"):
				AL.add("friend_rescues")
	Game.jobs.erase(j)
	Game.save_game()
	await _say(root, "gUnknown_80E2B54")
	await _say(root, "gUnknown_80E2A80")
	await show_password(root, "A-OK Mail", code)
	await _say(root, "gUnknown_80E2AA8")

static func get_thanks(root: Control) -> void:
	while true:
		await _say(root, "gUnknown_80E311C")
		var code := await enter_password(root)
		if code == "":
			return
		var f := decode(code)
		if f.is_empty():
			if await _ask(root, "gUnknown_80E48A8", ["Yes", "No"]) == 0:
				continue
			return
		if int(f.mail_type) != TYPE_THANK_YOU:
			await _say(root, "gUnknown_80E49C4")
			return
		var st := state()
		if not int(f.mail_id) in st.done:
			await _say(root, "gUnknown_80E4704")
			return
		var got: Array = st.get("thanks_got", [])
		if int(f.mail_id) in got:
			await _say(root, "gUnknown_80E460C")
			return
		got.append(int(f.mail_id))
		st.thanks_got = got
		await _say(root, "gUnknown_80E3220")
		if int(f.item) > 0:
			var key := WonderMail.item_key(int(f.item))
			if key != "":
				var n := maxi(1, int(f.item_qty))
				if not Game.bag_add(key, n):
					Game.storage[key] = int(Game.storage.get(key, 0)) + n
				Audio.sfx("333")
				await RedText.say(root, "%s received [color=#7fff7f]%s[/color]!" % [Game.team_name, DB.item_name(key)])
		Game.save_game()
		return

## SPECIAL_TEXT_UNK_1D (wonder_mail_2.c): Pelipper's greeting after a friend rescue mission.
static func rescue_reward_talk(root: Control) -> void:
	var team := Game.team_name if Game.team_name != "" else "????"
	await RedText.say(root, RedText.get_text("wonder_mail_2:sWelcomeBackText") if RedText.has("wonder_mail_2:sWelcomeBackText") else "", "Pelipper", "0279", {"args": [team]})

## SPECIAL_TEXT_THANK_YOU_MAIL (thank_you_wonder_mail.c): the Pelipper who handles Thank-You Mail.
static func thank_you_counter(root: Control) -> void:
	var s := state()
	while true:
		var c := await _ask(root, "gUnknown_80E25F4", [{"text": "Send Thank-You Mail", "disabled": not s.revive or s.thanks_sent},
			"Get Thank-You Mail", "Exit"])
		if c < 0 or c == 2:
			return
		if c == 0:
			await send_thanks(root)
		else:
			await get_thanks(root)
		if TeamScreens.auto_on():
			return
