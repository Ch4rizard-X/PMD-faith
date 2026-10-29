extends SceneTree
## Headless test for res://scripts/core/wonder_mail.gd (PMD Red Wonder Mail passwords).
## Run: godot --headless --path . --script tests/test_wondermail.gd
## Work happens in _initialize() so the autoloads exist. The real save file is backed up and restored.

var fails := 0
var checks := 0
var WM
var G
var MS

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		if fails < 40:
			print("FAIL: ", msg)

## Real Red Rescue Team passwords published by players (cheatcc.com list), with the fields Red decodes.
const KNOWN := [
	# code, mail_type, mission, special, client, target, target_item, reward_type, item_reward, friend_area, seed, dungeon, floor
	["F?4N+WT??+6NFR?JF?6685?W", 5, 0, 0, 340, 340, 66, 0, 77, 0, 16773573, 0, 2],
	["5?2YQW0??T0QJC?♂FH16WR?W", 5, 0, 0, 250, 250, 67, 9, 63, 14, 16776854, 35, 19],   # Friend Area: Sky Blue Plains
	["X??S??X?468?♀+??9756SY??", 5, 0, 0, 129, 129, 56, 0, 88, 52, 61, 19, 12],          # 400 Poké
	["X?7P♀?+??XP6RJ?QFJC5?W??", 5, 4, 0, 374, 374, 67, 2, 192, 52, 253, 41, 9],         # Feebas + Trawl Orb
	["??-FH?F??3P?Q??+8?76T8??", 5, 0, 0, 40, 40, 55, 6, 155, 0, 24, 2, 8],              # 200 Poké + TM
	["6?2Y5!+?45N7-!?FK4F5!R?W", 5, 4, 0, 163, 163, 188, 9, 53, 10, 16752916, 3, 7],     # Friend Area: Mt. Moonview
	["??1Y4!F?01PCJF?9-4?0-J?W", 5, 2, 9, 32, 29, 182, 8, 45, 0, 16755156, 3, 9],        # Nidoran escort (lovers)
]

## Vectors from a literal Python port of code_803D0D8.c / data_serializer.c),
## random field values (not necessarily valid missions): exact bit-level agreement.
const REF := [
# >>> VECTORS
	["N?C3XX4??F71Y2?FR?!9!J?P", 14, 1, 0, 92, 35, 42, 3, 181, 30, 584788, 7, 4],
	["W6C6S♂♀?XH♀MS+?K…M1♂NQ?W", 11, 7, 14, 152, 93, 93, 3, 7, 62, 8382839, 16, 119],
	["S6WT+25?6F!6JP?4C8+P!K?W", 2, 1, 1, 276, 64, 154, 15, 181, 34, 8360157, 51, 116],
	["1?33+46?40H4+Q?P♂W2P+F?C", 0, 1, 0, 341, 147, 242, 12, 85, 6, 2557987, 127, 41],
	["W6PFTP-?H7N+34?19T+SXR?+", 2, 3, 4, 27, 354, 56, 4, 156, 58, 1328407, 106, 70],
	["♂6♂!YY+?F♂…♀9!?S0WPF+4?2", 1, 2, 8, 158, 307, 79, 14, 21, 49, 11730371, 126, 87],
	["36♂35--?6RJ20K?…3RXW…4?W", 14, 7, 1, 482, 174, 225, 14, 151, 35, 4156611, 47, 106],
	["6?8519X?N…C53Y??41-917?F", 13, 1, 3, 496, 385, 130, 6, 176, 13, 5273736, 68, 39],
	["?662FRH?7KFF86?RTMM♂08?1", 10, 7, 2, 80, 404, 109, 1, 146, 4, 7361560, 22, 81],
	["-?-JN!Y?MF♂RFH?M♀XF♂21?5", 9, 7, 2, 263, 74, 218, 6, 51, 50, 6529762, 117, 60],
	["766N23Q?T0+C-7?HCWXX!!?W", 11, 3, 13, 178, 208, 154, 1, 180, 19, 16763368, 120, 85],
	["??!1HM??5TMFW7?RPM60…!?Y", 4, 2, 1, 169, 148, 35, 10, 87, 0, 2040936, 22, 37],
	["3?39F6M?T+C+48?CT+!69T?S", 6, 0, 13, 400, 332, 106, 12, 143, 38, 14161207, 81, 38],
	["S6N5M1H?FKMP…X?852Y4?3?-", 2, 4, 8, 420, 409, 141, 3, 192, 35, 7176817, 76, 101],
	["463FK1Y?XCM-TC?Q+W7HX6?M", 1, 5, 14, 238, 502, 84, 12, 157, 0, 2460422, 122, 101],
	["Q?RMW-0?YCJS3M?8♂-♂!FP?1", 9, 6, 15, 190, 410, 244, 5, 144, 47, 11626003, 52, 43],
	["66♀5Y♀5?4HS?2K?!6!NW22?N", 14, 7, 0, 479, 106, 13, 11, 243, 8, 4698212, 84, 89],
	["R67+-MT?+2!6F3?55!TMHJ?J", 9, 4, 10, 300, 199, 142, 2, 104, 43, 11215060, 82, 117],
	["-?PSQMR?C!!?+♀?6K5F89N?0", 8, 1, 3, 251, 263, 190, 4, 14, 50, 1253390, 11, 53],
	["C?F-♂?6?…47KX-?5C7CJ3!?2", 4, 5, 11, 444, 70, 156, 8, 248, 28, 11668458, 21, 4],
	["C675H64?JW05SW?WF3QXRR?+", 10, 3, 5, 489, 511, 71, 2, 74, 31, 5511318, 100, 83],
	["5?T+♂T6?642MXJ?5K9PQ…C?4", 4, 7, 1, 380, 70, 188, 13, 22, 9, 10541390, 58, 50],
	["867-!N♂?WH♂114?93P!!…3?K", 11, 6, 15, 53, 30, 229, 2, 150, 54, 11418736, 37, 124],
	["♀?M5♂01?…94+8R?+…HS6P6?M", 7, 0, 11, 380, 424, 89, 2, 9, 27, 6591751, 36, 33],
	["T?SR2♂6?XX6+WR?WM0W7F0?♀", 8, 0, 14, 370, 380, 147, 12, 208, 47, 7857445, 73, 2],
	["3?R-M3K?NJ-431?KK1-MM0?3", 10, 4, 3, 36, 223, 189, 5, 164, 37, 12175399, 69, 45],
	["+6♂75M-??0♂!M8?QST!…R♂?!", 14, 2, 0, 418, 244, 98, 14, 139, 22, 11873657, 104, 124],
	["K?PN♂♂♂?♂H45MT?!2C4W♀3?3", 15, 7, 14, 381, 105, 205, 4, 54, 60, 16378098, 24, 33],
	["♀6♀W…76?M♀F8♀T?PM♂NX90?2", 8, 3, 2, 343, 401, 150, 11, 207, 24, 15868711, 119, 81],
	["M?JK…-4?♂H2M?0?CS1!9J0??", 14, 1, 14, 87, 77, 101, 5, 171, 22, 12675366, 69, 51],
	["-65♂6K7?J394QJ?27+!77X?M", 8, 0, 5, 323, 102, 23, 1, 133, 54, 10844218, 87, 78],
	["♀60R+♂0?S42HQX?7M-♂…5Y?9", 13, 2, 12, 404, 9, 148, 9, 162, 31, 5237311, 49, 115],
	["R?FR0T-?!NH7TS?Y20N♀♂K?W", 14, 6, 10, 275, 445, 200, 8, 252, 40, 8311132, 73, 40],
	["Y?8358Y?JJF0W4?♀-3N2XT?8", 5, 6, 5, 35, 238, 181, 6, 220, 56, 812213, 103, 17],
	["J69NN-J?9…8SMX?31M8PTP?C", 2, 1, 7, 390, 497, 194, 7, 154, 41, 15164946, 16, 77],
	["P6RH…?P?PY+F27??♀W2FN5?1", 0, 2, 4, 150, 384, 219, 5, 70, 38, 3146820, 125, 85],
	["9?JR5♂N?Q8WY…Y?9H♂?54♀?!", 4, 4, 13, 483, 285, 161, 5, 33, 56, 7727084, 113, 63],
	["M68QS0J?PRHR7P?R2!04C♀?-", 2, 4, 4, 280, 148, 201, 6, 102, 18, 7115502, 87, 105],
	["C6♀FM!??-P--2N?P6T♀H47?7", 0, 5, 6, 229, 16, 9, 11, 225, 30, 371466, 106, 108],
	["16Y♂W1♀?!C2KPN?3CCF♀PC?+", 15, 6, 10, 255, 496, 156, 15, 8, 2, 9800655, 31, 115],
# <<< VECTORS
]

func _initialize() -> void:
	var dbn = root.get_node_or_null("DB")
	if dbn and dbn.species.is_empty():
		dbn._ready()
	WM = load("res://scripts/core/wonder_mail.gd")
	G = root.get_node("Game")
	MS = load("res://scripts/core/missions.gd")
	var backup := ""
	if FileAccess.file_exists(G.SAVE_PATH):
		backup = FileAccess.get_file_as_string(G.SAVE_PATH)
	var t0 := Time.get_ticks_msec()

	_test_tables()
	_test_known()
	_test_reference()
	_test_round_trips(3000)
	_test_mutations()
	_test_validity()
	_test_receive()

	if backup != "":
		var f := FileAccess.open(G.SAVE_PATH, FileAccess.WRITE)
		f.store_string(backup)
	print("wonder mail: %d checks, %d failed (%d ms)" % [checks, fails, Time.get_ticks_msec() - t0])
	quit(1 if fails > 0 else 0)

func _fields(row: Array) -> Dictionary:
	var r := {}
	for i in WM.FIELDS.size():
		r[WM.FIELDS[i][0]] = int(row[i + 1])
	return r

func _test_tables() -> void:
	ok(WM.CHARSET.length() == 32, "32 symbols")
	var seen := {}
	for p in WM.SCRAMBLE:
		seen[p] = true
	ok(seen.size() == 24, "scramble is a permutation")
	ok(WM.RED_FLOOR_COUNT.size() == 63 and WM.RED_DIFFICULTY.size() == 63, "63 dungeon rows")
	ok(WM.RED_SPECIES.size() == 424 and WM.RED_ITEMS.size() == 240, "species / item tables")
	ok(WM.species_id("0025") == 25 and WM.species_key(25) == "0025", "Pikachu id")
	ok(WM.species_id("0252") == 277, "Treecko is Red #277")
	ok(WM.species_id("0201") == 201, "Unown -> MONSTER_UNOWN")
	ok(WM.item_key(WM.item_id("oran")) == "oran", "item map")
	ok(WM.dungeon_key(0) == "tiny_woods" and WM.dungeon_index("tiny_woods") == 0, "dungeon map")
	var wd: Array = WM.wm_dungeons()
	ok(not 24 in wd and not 61 in wd and 0 in wd and 46 in wd, "Wonder Mail dungeon list (%d)" % wd.size())
	ok(not 9 in WM.wm_floors(2) and 8 in WM.wm_floors(2) and not 0 in WM.wm_floors(2), "Mt. Steel floors")
	var sp: Array = WM.wm_species()
	ok(sp.size() > 350 and not "0352" in sp and not "0150" in sp and "0025" in sp, "species list (%d)" % sp.size())

func _test_known() -> void:
	for row in KNOWN:
		var code: String = row[0]
		var want := _fields(row)
		var raw: Dictionary = WM.decode_raw(code)
		ok(raw == want, "decode_raw %s -> %s" % [code, raw])
		ok(WM.encode_raw(want) == code, "encode_raw gives back %s (got %s)" % [code, WM.encode_raw(want)])
		ok(WM.validate_raw(want) == "", "Red accepts %s: %s" % [code, WM.validate_raw(want)])
		var res: Dictionary = WM.decode(code)
		ok(res.ok, "decode %s: %s %s" % [code, res.error, res.reason])
		if res.ok:
			var j: Dictionary = res.job
			ok(j.wonder_mail and j.code == code and j.dungeon == WM.dungeon_key(want.dungeon) and int(j.floor) == want.floor, "job fields " + code)
			ok(str(j.title) != "" and str(j.text) != "", "job text " + code)
			ok(WM.encode(j) == code, "encode(job) == code " + code)
	# spaces, lowercase and the other spellings of the special symbols
	ok(WM.decode("f?4n +wt? ?+6n fr?j f?66 85?w").ok, "lowercase + spaces")
	ok(WM.decode("X??S??X?468?*+??9756SY??").ok, "* stand-in decodes")
	ok(WM.decode("5?2YQW0??T0QJC?½FH16WR?W").ok, "½ (font glyph) decodes as ♂")
	var sky: Dictionary = WM.decode("5?2YQW0??T0QJC?♂FH16WR?W").job
	ok(sky.reward.type == "friend_area" and sky.reward.friend_area == "skyblueplains", "Sky Blue Plains reward")
	ok(sky.dungeon == "northwind_field" and int(sky.floor) == 19 and sky.client == "0225", "Delibird at Northwind Field 19F (%s %s %s)" % [sky.dungeon, sky.floor, sky.client])
	var esc: Dictionary = WM.decode("??1Y4!F?01PCJF?9-4?0-J?W").job
	ok(esc.kind == "escort" and esc.client == "0032" and esc.target == "0029" and int(esc.special) == 9, "Nidoran escort")
	ok(esc.reward.type == "item1_extra" and int(esc.reward.extra) == 2, "item1_extra reward")
	print("example: ", sky.title, " / ", sky.place, " / ", MS.reward_text(sky))

func _test_reference() -> void:
	ok(REF.size() >= 20, "reference vectors present")
	for row in REF:
		var want := _fields(row)
		ok(WM.encode_raw(want) == row[0], "ref encode %s" % row[0])
		ok(WM.decode_raw(row[0]) == want, "ref decode %s" % row[0])

func _random_job(rng: RandomNumberGenerator) -> Dictionary:
	var ds: Array = WM.wm_dungeons()
	var sp: Array = WM.wm_species()
	var d: int = ds[rng.randi_range(0, ds.size() - 1)]
	var fls: Array = WM.wm_floors(d)
	var fl: int = fls[rng.randi_range(0, fls.size() - 1)]
	var kinds: Array = WM.wm_kinds(d)
	var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
	var f := {"kind": kind, "dungeon": WM.dungeon_key(d), "floor": fl, "client": sp[rng.randi_range(0, sp.size() - 1)],
		"seed": rng.randi() & 0xffffff, "special": rng.randi_range(0, 9)}
	if kind == "target" or kind == "escort":
		f.target = sp[rng.randi_range(0, sp.size() - 1)]
	if kind == "find" or kind == "deliver":
		var its: Array = WM.wm_target_items(d, kind)
		f.item = its[rng.randi_range(0, its.size() - 1)]
	var types := ["money", "money_extra", "item", "item_extra", "money1", "money1_extra", "item1", "item1_extra"]
	var fas: Array = WM.wm_friend_areas(d, fl, kind)
	if not fas.is_empty():
		types.append("friend_area")
	var t: String = types[rng.randi_range(0, types.size() - 1)]
	var ri: Array = WM.wm_reward_items()
	f.reward = {"type": t, "item": ri[rng.randi_range(0, ri.size() - 1)], "friend_area": fas[rng.randi_range(0, fas.size() - 1)] if t == "friend_area" else ""}
	return f

func _test_round_trips(n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var codes := {}
	var bad := 0
	for i in n:
		var f := _random_job(rng)
		var e: Dictionary = WM.encode_ex(f)
		if not e.ok:
			bad += 1
			ok(false, "valid job refused: %s %s" % [e.error, f])
			continue
		var code: String = e.code
		codes[code] = true
		var res: Dictionary = WM.decode(code)
		if not res.ok:
			ok(false, "round trip decode %s: %s" % [code, res.reason])
			continue
		var j: Dictionary = res.job
		var same: bool = j.kind == f.kind and j.dungeon == f.dungeon and int(j.floor) == f.floor and j.client == f.client \
			and int(j.seed) == f.seed and int(j.special) == f.special and j.reward.type == f.reward.type
		if f.has("target"):
			same = same and j.target == f.target
		else:
			same = same and j.target == f.client
		if f.has("item"):
			same = same and j.item == f.item
		if f.reward.type == "friend_area":
			same = same and j.reward.friend_area == f.reward.friend_area
		elif f.reward.type.contains("item"):
			same = same and j.reward.item == f.reward.item
		ok(same, "round trip fields %s" % code)
		ok(WM.encode(j) == code, "re-encode job %s" % code)
		# re-encode from the project fields alone (no "red" copy)
		var g := j.duplicate(true)
		g.erase("red")
		# hidden Red fields (unused target item of rescue jobs, item of a money reward, ...) aren't in the job, so
		# compare what the player sees
		var c2: String = WM.encode(g)
		var j2: Dictionary = WM.decode(c2).job if c2 != "" else {}
		var vis := ["kind", "dungeon", "floor", "client", "target", "item", "seed", "special", "diff", "title", "text"]
		var same2 := not j2.is_empty() and JSON.stringify(j2.reward) == JSON.stringify(j.reward)
		for key in vis:
			same2 = same2 and str(j2.get(key, "?")) == str(j.get(key, "!"))
		ok(same2, "encode(job fields) %s -> %s" % [code, c2])
		ok(WM.encode_raw(WM.decode_raw(code)) == code, "raw round trip %s" % code)
	ok(codes.size() > n * 0.99, "codes distinct (%d of %d)" % [codes.size(), n])
	print("round trips: %d jobs, %d refused" % [n, bad])

func _test_mutations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var single := 0
	var single_ok := 0
	var multi := 0
	var multi_cs := 0
	var multi_valid := 0
	var swaps := 0
	var swap_ok := 0
	for k in 300:
		var code: String = WM.encode(_random_job(rng))
		# every single-symbol change must fail Red's checksum
		var pos := rng.randi_range(0, 23)
		for s in WM.CHARSET:
			if s == code[pos]:
				continue
			var m: String = code.substr(0, pos) + s + code.substr(pos + 1)
			single += 1
			if not WM.decode_raw(m).is_empty():
				single_ok += 1
		# random 2-4 symbol changes: checksum lets ~1/256 through, validity catches most of those
		for t in 40:
			var m2 := code
			for c in rng.randi_range(2, 4):
				var p := rng.randi_range(0, 23)
				m2 = m2.substr(0, p) + WM.CHARSET[rng.randi_range(0, 31)] + m2.substr(p + 1)
			if m2 == code:
				continue
			multi += 1
			if not WM.decode_raw(m2).is_empty():
				multi_cs += 1
				if WM.decode(m2).ok:
					multi_valid += 1
		# swapping two different symbols
		var a := rng.randi_range(0, 23)
		var b := (a + rng.randi_range(1, 23)) % 24
		if code[a] != code[b]:
			var sw := code.substr(0, 0)
			for i in 24:
				sw += code[b] if i == a else (code[a] if i == b else code[i])
			swaps += 1
			if WM.decode(sw).ok:
				swap_ok += 1
	ok(single_ok == 0, "all %d single-symbol mutations rejected (%d passed)" % [single, single_ok])
	ok(multi_cs < multi / 50, "multi mutations pass checksum rarely (%d / %d)" % [multi_cs, multi])
	ok(swap_ok * 20 < swaps, "swapped symbols rarely accepted (%d / %d)" % [swap_ok, swaps])
	print("mutations: swaps %d/%d accepted; single %d/%d accepted; multi %d checksum-ok, %d valid of %d" % [swap_ok, swaps, single_ok, single, multi_cs, multi_valid, multi])
	ok(not WM.decode("F?4N+WT??+6NFR?JF?6685?").ok, "23 symbols rejected")
	ok(not WM.decode("F?4N+WT??+6NFR?JF?6685?WW").ok, "25 symbols rejected")
	ok(not WM.decode("A?4N+WT??+6NFR?JF?6685?W").ok, "unknown symbol rejected")
	ok(WM.decode("F?4N+WT??+6NFR?JF?6685?X").error == WM.ERR_INCORRECT, "Red's message")

func _test_validity() -> void:
	var base := {"mail_type": 5, "mission": 0, "special": 0, "client": 25, "target": 25, "target_item": WM.item_id("oran"),
		"reward_type": 0, "item_reward": 0, "friend_area": 0, "seed": 1, "dungeon": 2, "floor": 3}
	ok(WM.validate_raw(base) == "", "baseline valid: " + WM.validate_raw(base))
	var cases := [
		[{"mail_type": 4}, "A-OK mail type"], [{"mission": 5}, "mission 5"], [{"special": 10}, "unk2 10"],
		[{"dungeon": 24}, "Boss dungeon"], [{"dungeon": 63}, "dungeon 63"], [{"floor": 10}, "Mt. Steel 10F"],
		[{"floor": 9}, "Mt. Steel 9F (boss floor)"], [{"client": 352}, "Kecleon"], [{"client": 0}, "no client"],
		[{"client": 202, "target": 202}, "Unown B (not a base form)"], [{"client": 420, "target": 420}, "Munchlax"],
		[{"target": 4}, "rescue client with other target"], [{"target_item": 1}, "thrown target item"],
		[{"target_item": 105}, "Poké target item"], [{"target_item": 237}, "invalid item"],
		[{"reward_type": 4}, "BLANK_4"], [{"reward_type": 10}, "END_REWARDS"], [{"item_reward": 236}, "invalid reward item"],
		[{"friend_area": 58}, "friend area 58"], [{"reward_type": 9, "friend_area": 10}, "Friend Area at difficulty E"],
		[{"mission": 4, "dungeon": 62, "floor": 5}, "deliver in Purity Forest (no items)"],
		[{"mission": 3, "dungeon": 0, "floor": 1, "target_item": WM.item_id("reviver")}, "find an item not in the dungeon"],
	]
	for c in cases:
		var r: Dictionary = base.duplicate()
		r.merge(c[0], true)
		ok(WM.validate_raw(r) != "", "refused: " + str(c[1]))
	var fa := base.duplicate()
	fa.merge({"reward_type": 9, "friend_area": 14, "dungeon": 13, "floor": 5}, true)
	ok(WM.validate_raw(fa) == "", "Friend Area at Mt. Freeze is fine: " + WM.validate_raw(fa))
	fa.friend_area = 1
	ok(WM.validate_raw(fa) != "", "Bountiful Sea isn't a Wonder Mail area")
	var esc := base.duplicate()
	esc.merge({"mission": 2, "target": 4, "reward_type": 9, "friend_area": 35, "dungeon": 0, "floor": 1}, true)
	ok(WM.validate_raw(esc) == "", "escort +2 difficulty allows a Friend Area in Tiny Woods")
	ok(WM.encode({"kind": "rescue", "dungeon": "tiny_woods", "floor": 1, "client": "0352", "reward": {"type": "money"}}) == "", "encode refuses Kecleon")

func _test_receive() -> void:
	G.jobs = []
	G.flags = {}
	G.unlocked = ["tiny_woods"]
	var r: Dictionary = WM.decode("6?2Y5!+?45N7-!?FK4F5!R?W")
	ok(WM.receive(r.job) == "", "receive adds the job")
	ok(G.jobs.size() == 1 and G.jobs[0].state == "suspended" and G.jobs[0].wonder_mail, "job is in the Job List (suspended)")
	ok(WM.receive(WM.decode("6?2Y5!+?45N7-!?FK4F5!R?W").job) == WM.MSG_DUPLICATE, "duplicate refused")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var added := 1
	while added < 8:
		var j: Dictionary = WM.decode(WM.encode(_random_job(rng))).job
		if WM.receive(j) == "":
			added += 1
	ok(G.jobs.size() == 8, "8 jobs")
	ok(WM.receive(WM.decode("F?4N+WT??+6NFR?JF?6685?W").job) == WM.MSG_FULL, "Job List full")
	G.jobs = []
	var odd: String = WM.encode({"kind": "rescue", "dungeon": WM.dungeon_key(43), "floor": 3, "client": "0025", "reward": {"type": "money"}, "seed": 9})
	ok(odd != "", "Oddity Cave mail")
	ok(WM.receive(WM.decode(odd).job) == "" and WM.dungeon_key(43) in G.unlocked, "receiving opens Oddity Cave")
	WM.note_completed(G.jobs[0])
	G.jobs = []
	ok(WM.receive(WM.decode(odd).job) == WM.MSG_USED, "completed Wonder Mail can't be received again")
	G.jobs = []
	G.flags = {}
