class_name WonderMailS
extends RefCounted
## Wonder Mail S: Explorers of Sky's 34-symbol Wonder Mail passwords, for the Explorers of Sky dungeons.
##
##   WonderMailS.available()            the ids table (data/eos_wm.json, made from the user's EoS ROM) is there
##   WonderMailS.decode(code)           {ok, error, reason, job, raw}  (job: the Missions job format)
##   WonderMailS.encode_ex(fields)      {ok, error, code, raw}         fields: kind, dungeon (key), floor, client,
##                                      target, item, reward {type, item}
##
## The password format is the game's own: the symbol set, the position swap and the 256-byte table the game adds
## to the bytes are the ones in the Explorers of Sky (US) arm9 (ROM 0xA20E8 / 0xA2108 / 0xA22A0); the 17 data
## bytes carry a CRC-32 (24 + 8 bits), the low 8 bits of which pick where in the table the game starts and which
## way it walks. The fields follow pmdsky-debug's struct mission. A real EoS password decodes here, and the
## passwords this makes have the same form.
## The jobs use this game's rules: the job kinds it has (rescue a client, rescue a target, escort, find an item,
## deliver an item, and EoS's guide-the-client), its own difficulty and rewards for the floor; the other EoS
## mission kinds are refused. EoS's special reward (the client asks to join) is kept.

const CODE_LEN := 34
const CHARS := "&67NPR89F0+#STXY45MCHJ-K12=%3Q@W"
## The five symbols Red's password screen has in the same places (and for typing them on that screen).
const RED_SYMBOLS := {"?": "&", "…": "#", "!": "=", "♀": "%", "♂": "@"}
const SWAP := [0x07, 0x1B, 0x0D, 0x1F, 0x15, 0x1A, 0x06, 0x01, 0x17, 0x1C, 0x09, 0x1E, 0x0A, 0x20, 0x10, 0x21, 0x0F,
	0x08, 0x1D, 0x11, 0x14, 0x00, 0x13, 0x16, 0x05, 0x12, 0x0E, 0x04, 0x03, 0x18, 0x02, 0x0B, 0x0C, 0x19]
const ENC_HEX := "2e753f99096cbc617c2a964af46d29fa90149d336fcb493c48807b4667011759b8fa70c0447848fb268081fcfd6170c7fea870286c9c07a4cb3f70a38cd6ffb07a3a3554e99a3b611641e9a390a3e9ee0efadc9bd6fb24b5419a20bab3517a363e600e3d02b034576981eb67f3eb8c4793ce2aaf35f47487502c3968bb471a02a393642e8cadb1c461045fbd59211ce70e29269770a9cd18a37b747096dea672dd1393aa906ca7b5762fa87ac88106bb8575110cd2d1c9f88170eec871533daf76cb0dc15628e83c61644bb8ef3b4109720750adf32e5c43ffc3b3327a3e9ca3c2ab106099fb088a90578a7f6190218855e8fc4b0d4a7a48c9b0c7a6d0047e05"
## [name, bits], first field first (the top 2 bits of "null" stay outside the encryption).
const FIELDS := [["null", 8], ["special_floor", 8], ["floor", 8], ["dungeon", 8], ["flavor", 24], ["restriction", 11],
	["restriction_type", 1], ["reward", 11], ["reward_type", 4], ["target_item", 10], ["target2", 11], ["target", 11],
	["client", 11], ["mission_special", 4], ["mission", 4], ["mail_type", 4]]
const MAIL_TYPE := 4
## enum mission_type -> this game's job kinds
const MISSION_KIND := {0: "rescue", 1: "target", 2: "escort", 5: "guide", 6: "find", 7: "deliver"}
const KINDS := ["rescue", "target", "escort", "guide", "find", "deliver"]
const MISSION_NAMES := ["Rescue client", "Rescue target", "Escort to target", "Explore with client", "Prospect with client",
	"Guide client", "Find item", "Deliver item", "Search for target", "Take item from outlaw", "Arrest outlaw",
	"Challenge Request", "Treasure Memo"]
## enum mission_reward_type -> this game's rewards (4 = an item shown as "?", 5 = money shown as "?",
## 6 = MISSION_REWARD_SPECIAL: the client asks to join - EoS can also give an egg there; this game has no eggs)
const REWARD_KIND := {0: "money", 1: "money_extra", 2: "item", 3: "item_extra", 4: "item", 5: "money", 6: "join"}
const REWARD_TYPES := ["money", "money_extra", "item", "item_extra", "", "", "join"]
const ITEM_APPLE := 109         # the target item EoS puts in jobs that don't use one
const FEMALE := 600             # monster index + 600: the same Pokémon, female

const ERR_INCORRECT := "This password is incorrect."
const ERR_UNSUPPORTED := "This Wonder Mail S is for a job\nthis game doesn't have."

static var _data := {}
static var _sp_of := {}          # EoS monster index -> species key
static var _sp_id := {}          # species key -> EoS monster index (the first one)
static var _it_of := {}          # EoS item id -> item key
static var _it_id := {}          # item key -> EoS item id (the first one)
static var _dk_of := {}          # EoS dungeon id -> dungeon key (the first part)
static var _enc := PackedByteArray()

static func _init_tables() -> void:
	if not _data.is_empty():
		return
	var f := FileAccess.open("res://data/eos_wm.json", FileAccess.READ)
	if f != null:
		var v = JSON.parse_string(f.get_as_text())
		if v is Dictionary:
			_data = v
	if _data.is_empty():
		_data = {"species": {}, "items": {}, "dungeons": {}}
	for k in _data.get("species", {}):
		var key := str(_data.species[k])
		_sp_of[int(k)] = key
		if not _sp_id.has(key) or int(k) < int(_sp_id[key]):
			_sp_id[key] = int(k)
	for k in _data.get("items", {}):
		var key := str(_data.items[k])
		_it_of[int(k)] = key
		if not _it_id.has(key) or int(k) < int(_it_id[key]):
			_it_id[key] = int(k)
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	for key in dd:
		if bool(dd[key].get("eos", false)) and dd[key].has("eos_id") and not _dk_of.has(int(dd[key].eos_id)):
			_dk_of[int(dd[key].eos_id)] = str(key)
	_enc = ENC_HEX.hex_decode()

static func available() -> bool:
	_init_tables()
	return not _sp_of.is_empty() and not _dk_of.is_empty()

# ============================================================================ bits / crypto
## Password symbols -> the symbol order the game packs (the position swap undone); "" if not 34 symbols.
static func normalize(code: String) -> String:
	var s := ""
	for ch in code.to_upper():
		var c := str(RED_SYMBOLS.get(ch, ch))
		if CHARS.contains(c):
			s += c
	return s

static func _crc32(data: PackedByteArray) -> int:
	var c := 0xFFFFFFFF
	for b in data:
		c ^= b
		for _k in 8:
			c = (c >> 1) ^ (0xEDB88320 if c & 1 else 0)
	return c ^ 0xFFFFFFFF

## 170 bits (2 null + 136 data + 24 + 8 checksum), first bit first.
static func _bits_of(v: int, n: int) -> Array:
	var out: Array = []
	for i in range(n - 1, -1, -1):
		out.append((v >> i) & 1)
	return out

static func _num(bits: Array, from: int, n: int) -> int:
	var v := 0
	for i in n:
		v = (v << 1) | int(bits[from + i])
	return v

## The game's add / subtract pass over the 17 data bytes (last byte first).
static func _crypt(bits: Array, encrypt: bool) -> Array:
	var ck := _num(bits, 162, 8)
	var full := _num(bits, 138, 32)
	var blocks: Array = []
	for i in 17:
		blocks.append(_num(bits, 2 + 8 * (16 - i), 8))
	var entries: Array = []
	var p := ck
	var backwards := (ck & 1) == 0
	for _i in 17:
		entries.append(_enc[p])
		p = (p + (-1 if backwards else 1) + 256) % 256
	var b := full & 0xFF
	var reset := b / 16 + 8 + b % 16
	if reset >= 17:
		reset = -1
	var e := 0
	for i in 17:
		if e == reset:
			e = 0
		blocks[i] = (int(blocks[i]) + int(entries[e])) & 0xFF if encrypt else (int(blocks[i]) - int(entries[e])) & 0xFF
		e += 1
	var out: Array = bits.slice(0, 2)
	for i in range(16, -1, -1):
		out.append_array(_bits_of(int(blocks[i]), 8))
	out.append_array(bits.slice(138, 170))
	return out

static func _data_bytes(bits: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for i in range(16, -1, -1):
		out.append(_num(bits, 2 + 8 * i, 8))
	return out

## Password -> raw fields ({} if the symbols or the checksum are wrong).
static func decode_raw(code: String) -> Dictionary:
	var s := normalize(code)
	if s.length() != CODE_LEN:
		return {}
	var bits: Array = []
	for i in range(CODE_LEN - 1, -1, -1):
		bits.append_array(_bits_of(CHARS.find(s[SWAP[i]]), 5))
	var dec := _crypt(bits, false)
	if _crc32(_data_bytes(dec)) != _num(dec, 138, 32):
		return {}
	var r := {}
	var p := 0
	for f in FIELDS:
		r[f[0]] = _num(dec, p, f[1])
		p += int(f[1])
	return r

static func encode_raw(r: Dictionary) -> String:
	var bits: Array = []
	for f in FIELDS:
		bits.append_array(_bits_of(int(r.get(f[0], 0)) & ((1 << int(f[1])) - 1), int(f[1])))
	bits[0] = 0
	bits[1] = 0
	bits.append_array(_bits_of(_crc32(_data_bytes(bits)), 32))
	var enc := _crypt(bits, true)
	var packed := ""
	for i in CODE_LEN:
		packed += CHARS[_num(enc, (CODE_LEN - 1 - i) * 5, 5)]
	var out: Array = []
	out.resize(CODE_LEN)
	for i in CODE_LEN:
		out[SWAP[i]] = packed[i]
	return "".join(PackedStringArray(out))

# ============================================================================ ids
static func species_key(eos_id: int) -> String:
	_init_tables()
	return str(_sp_of.get(eos_id % FEMALE, ""))

static func species_id(key: String) -> int:
	_init_tables()
	return int(_sp_id.get(key, -1))

static func item_key(eos_id: int) -> String:
	_init_tables()
	return str(_it_of.get(eos_id, ""))

static func item_id(key: String) -> int:
	_init_tables()
	return int(_it_id.get(key, -1))

static func dungeon_key(eos_id: int) -> String:
	_init_tables()
	return str(_dk_of.get(eos_id, ""))

static func dungeon_id(key: String) -> int:
	return int(Missions.ddb(key).get("eos_id", -1)) if bool(Missions.ddb(key).get("eos", false)) else -1

static func eos_dungeon_name(eos_id: int) -> String:
	_init_tables()
	return str(_data.get("dungeons", {}).get(str(eos_id), "dungeon %d" % eos_id))

# ============================================================================ checks
## Floors of an EoS dungeon a job can be on (Missions.eos_dinfo: not boss arenas).
static func floors(key: String) -> Array:
	var info := Missions.dinfo(key)
	var out: Array = []
	if not bool(info.get("jobs", false)):
		return out
	var nj: Array = info.get("no_job_floors", [])
	for fl in range(1, Missions.ddb(key).get("floors", []).size() + 1):
		if not fl in nj:
			out.append(fl)
	return out

## "" when this game can take the mail, else why not.
static func check_raw(r: Dictionary) -> String:
	_init_tables()
	if int(r.get("mail_type", 0)) != MAIL_TYPE:
		return "not a Wonder Mail S"
	var m := int(r.get("mission", 0))
	if not MISSION_KIND.has(m):
		return "%s jobs aren't in this game" % (MISSION_NAMES[m] if m < MISSION_NAMES.size() else "type %d" % m)
	var did := int(r.get("dungeon", 0))
	var key := dungeon_key(did)
	if key == "":
		return "%s isn't in this game" % eos_dungeon_name(did)
	var fl := int(r.get("floor", 0))
	if not fl in floors(key):
		return "no jobs on floor %d of %s" % [fl, Missions.dungeon_name(key)]
	if species_key(int(r.get("client", 0))) == "":
		return "client Pokémon %d isn't in this game" % int(r.get("client", 0))
	var kind: String = MISSION_KIND[m]
	if (kind == "target" or kind == "escort") and species_key(int(r.get("target", 0))) == "":
		return "target Pokémon %d isn't in this game" % int(r.get("target", 0))
	if (kind == "find" or kind == "deliver") and item_key(int(r.get("target_item", 0))) == "":
		return "item %d isn't in this game" % int(r.get("target_item", 0))
	var rt := int(r.get("reward_type", 0))
	if not REWARD_KIND.has(rt):
		return "reward type %d isn't in this game" % rt
	if not str(REWARD_KIND[rt]) in ["money", "join"] and item_key(int(r.get("reward", 0))) == "":
		return "reward item %d isn't in this game" % int(r.get("reward", 0))
	return ""

# ============================================================================ decode
static func decode(code: String) -> Dictionary:
	var res := {"ok": false, "error": ERR_INCORRECT, "job": {}, "raw": {}, "reason": ""}
	var n := normalize(code)
	if n.length() != CODE_LEN:
		res.reason = "a Wonder Mail S password has 34 symbols"
		return res
	var raw := decode_raw(n)
	if raw.is_empty():
		res.reason = "checksum / symbol"
		return res
	var why := check_raw(raw)
	if why != "":
		res.error = ERR_UNSUPPORTED
		res.reason = why
		res.raw = raw
		return res
	res.ok = true
	res.error = ""
	res.raw = raw
	res.job = job_from_raw(raw, n)
	return res

## Raw fields -> a Job List job (the Missions format), with this game's difficulty and reward amounts.
static func job_from_raw(r: Dictionary, code := "") -> Dictionary:
	if code == "":
		code = encode_raw(r)
	var kind: String = MISSION_KIND[int(r.mission)]
	var key := dungeon_key(int(r.dungeon))
	var fl := int(r.floor)
	var client := species_key(int(r.client))
	var target := species_key(int(r.target)) if kind == "target" or kind == "escort" else client
	var item := item_key(int(r.target_item)) if kind == "find" or kind == "deliver" else ""
	var diff := Missions.mission_difficulty(key, fl, kind)
	var li := Missions.letter_index(diff)
	var j := {"id": "wms-" + code, "kind": kind, "special": 0, "dungeon": key, "floor": fl, "client": client,
		"target": target, "item": item, "seed": int(r.get("flavor", 0)) & 0xffffff, "diff": diff,
		"difficulty": Missions.DIFF_LETTERS[li], "accepted": false, "state": "board", "source": "wonder_mail",
		"wonder_mail": true, "wonder_mail_s": true, "code": code, "eos": r.duplicate()}
	var t: String = REWARD_KIND[int(r.reward_type)]
	var rw := {"type": t, "money": 0, "item": "", "item_n": 0, "extra": 0, "rank_points": Missions.RANK_POINTS[diff],
		"friend_area": ""}
	var ri := item_key(int(r.reward)) if not t in ["money", "join"] else ""
	match t:
		"money": rw.money = (li + 1) * 100
		"money_extra": rw.money = (li + 1) * 100; rw.item = ri
		"item": rw.item = ri
		"item_extra": rw.item = ri; rw.extra = 1
		"join": rw.join = true                 # shown as "?" like EoS; the client asks to join when thanking
	if rw.item != "":
		rw.item_n = Missions.THROWN_REWARD_QTY if Missions._thrown(rw.item) else 1
	j.reward = rw
	Missions.describe(j)
	return j

# ============================================================================ encode
## Job fields -> raw fields: kind, dungeon (key), floor, client, target, item, reward {type, item}, flavor.
static func raw_from_fields(f: Dictionary) -> Dictionary:
	_init_tables()
	var kind := str(f.get("kind", "rescue"))
	var m := 0
	for k in MISSION_KIND:
		if MISSION_KIND[k] == kind:
			m = int(k)
	var r := {"mail_type": MAIL_TYPE, "mission": m, "mission_special": 0, "dungeon": dungeon_id(str(f.get("dungeon", ""))),
		"floor": int(f.get("floor", 1)), "special_floor": 0, "restriction": 0, "restriction_type": 0, "target2": 0}
	r.client = species_id(str(f.get("client", "")))
	var tg := str(f.get("target", ""))
	r.target = species_id(tg) if (kind == "target" or kind == "escort") and tg != "" else r.client
	var it := str(f.get("item", ""))
	r.target_item = item_id(it) if (kind == "find" or kind == "deliver") and it != "" else ITEM_APPLE
	var rw: Dictionary = f.get("reward", {}) if f.get("reward", null) is Dictionary else {}
	var t := str(rw.get("type", "money"))
	r.reward_type = maxi(0, REWARD_TYPES.find(t))
	r.reward = item_id(str(rw.get("item", ""))) if not t in ["money", "join"] and str(rw.get("item", "")) != "" else ITEM_APPLE
	if t == "join":
		r.reward = r.client
	# the job's text variant (struct mission description_id); the community generators use 300000-399999
	r.flavor = int(f.get("flavor", 300000 + randi() % 100000)) & 0xffffff
	return r

static func encode_ex(fields: Dictionary) -> Dictionary:
	if not available():
		return {"ok": false, "error": "No Explorers of Sky data (run the setup with an Explorers of Sky ROM)", "code": "", "raw": {}}
	var raw := raw_from_fields(fields)
	for k in ["dungeon", "client", "target", "target_item", "reward"]:
		if int(raw[k]) < 0:
			return {"ok": false, "error": "%s can't go in a Wonder Mail S" % k.replace("_", " "), "code": "", "raw": raw}
	var why := check_raw(raw)
	if why != "":
		return {"ok": false, "error": why, "code": "", "raw": raw}
	return {"ok": true, "error": "", "code": encode_raw(raw), "raw": raw}

# ============================================================================ lists for the maker
## EoS dungeons (first parts and the parts after) a job can be made for.
static func dungeons() -> Array:
	_init_tables()
	var out: Array = []
	var dd: Dictionary = DB.dungeons.get("dungeons", {})
	for key in dd:
		if bool(dd[key].get("eos", false)) and dd[key].has("eos_id") and dungeon_key(int(dd[key].eos_id)) == key \
				and not floors(key).is_empty():
			out.append(key)
	return out

static func species_list() -> Array:
	_init_tables()
	var out: Array = []
	for k in _sp_id:
		if DB.species.has(k) and (str(k).length() == 4 or str(k).begins_with("0201")):
			out.append(k)
	out.sort()
	return out

static func target_items(key: String, kind: String) -> Array:
	_init_tables()
	var pool: Array = Missions.dinfo(key).get("items", []) if kind == "find" else _it_id.keys()
	var out: Array = []
	for k in pool:
		if _it_id.has(k) and DB.items.has(k) and not Missions._thrown(str(k)):
			out.append(k)
	out.sort_custom(func(a, b): return DB.item_name(a) < DB.item_name(b))
	return out

static func reward_items() -> Array:
	_init_tables()
	var out: Array = []
	for k in _it_id:
		if DB.items.has(k):
			out.append(k)
	out.sort_custom(func(a, b): return DB.item_name(a) < DB.item_name(b))
	return out

## For the password screens: the symbols in EoS's grouping, two rows of 5 / 7 / 5.
static func pretty(code: String) -> String:
	var s := normalize(code)
	if s.length() != CODE_LEN:
		return s
	return "%s %s %s\n%s %s %s" % [s.substr(0, 5), s.substr(5, 7), s.substr(12, 5), s.substr(17, 5), s.substr(22, 7), s.substr(29, 5)]
