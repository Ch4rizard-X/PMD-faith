class_name GVars
extends RefCounted
## PMD Red's script variables (event_flag.c), byte-exact: one 0x400-byte global buffer laid out by
## gScriptVarInfo, plus a 16-byte local buffer per running script (LOCAL0-3). Scenario helpers, quest checks,
## FlagCalc / FlagJudge. The buffer is saved with the game (Game.story.vars, base64).

const BUF_LEN := 0x400
const LOCAL0 := 0x400

enum { T_0, T_BIT, T_U8, T_S8, T_U16, T_S16, T_S32, T_U8_2, T_SPECIAL }
enum { VERSION, CONDITION, SCENARIO_SELECT, SCENARIO_MAIN, SCENARIO_SUB1, SCENARIO_SUB2, SCENARIO_SUB3, SCENARIO_SUB4,
	SCENARIO_SUB5, SCENARIO_SUB6, SCENARIO_SUB7, SCENARIO_SUB8, SCENARIO_SUB9, GROUND_ENTER, GROUND_ENTER_LINK,
	GROUND_GETOUT, GROUND_MAP, GROUND_PLACE, DUNGEON_SELECT, DUNGEON_ENTER, DUNGEON_ENTER_INDEX,
	DUNGEON_ENTER_FREQUENCY, DUNGEON_RESULT, SCRIPT_MODE, START_MODE, CLEAR_COUNT, CONDITION_KIND, WEATHER_KIND,
	PLAYER_KIND, PARTNER1_KIND, PARTNER2_KIND, NEW_FRIEND_KIND, FRIEND_SUM, UNIT_SUM, GOLD, BANK_GOLD, WARP_LIST,
	WARP_LOCK, PARTNER_TALK_KIND, BASE_KIND, BASE_LEVEL, FLAG_KIND, FLAG_KIND_CHANGE_REQUEST,
	RESCUE_SCENARIO_ORDER_LIST, RESCUE_SCENARIO_JOB_LIST, RESCUE_SCENARIO_CONQUEST_LIST, TRAINING_CONQUEST_LIST,
	TRAINING_PRESENT_LIST, DUNGEON_ENTER_LIST, DUNGEON_CLEAR_LIST, POSITION_X, POSITION_Y, POSITION_HEIGHT,
	POSITION_DIRECTION, GROUND_LOCAL, MAP_LOCAL, MAP_LOCAL_DOOR, EVENT_LOCAL, STATION_ITEM_STATIC, STATION_ITEM_TEMP,
	DELIVER_ITEM_STATIC, DELIVER_ITEM_TEMP, SHOP_TEMP, INN_TEMP, EVENT_S07E01, EVENT_S08E01, EVENT_GONBE }
enum { CALC_SET, CALC_SUB, CALC_ADD, CALC_MUL, CALC_DIV, CALC_MOD, CALC_AND, CALC_OR, CALC_XOR, CALC_SETBIT,
	CALC_CLEARBIT, CALC_RANDOM }
enum { JUDGE_TRUE, JUDGE_FALSE, JUDGE_EQ, JUDGE_GT, JUDGE_LT, JUDGE_GE, JUDGE_LE, JUDGE_NE, JUDGE_AND_NONZERO,
	JUDGE_XOR_NONZERO, JUDGE_BIT_SET }
enum { QUEST_SET_TEAM_NAME, QUEST_UNK1, QUEST_CAN_ACCESS_JOBS, QUEST_CAN_RECRUIT, QUEST_SQUARE_ASLEEP, QUEST_UNK5,
	QUEST_REACHED_POSTGAME, QUEST_UNLOCKED_EVOLUTIONS, QUEST_CAN_CHANGE_LEADER, QUEST_CAN_DEPOSIT_PARTNER, QUEST_UNK10,
	QUEST_UNK11, QUEST_UNK12, QUEST_IN_WORLD_CALAMITY, QUEST_MAZE_14, QUEST_MAZE_15, QUEST_LEGEND_ZAPDOS,
	QUEST_LEGEND_MOLTRES, QUEST_LEGEND_ARTICUNO, QUEST_LEGEND_GROUDON, QUEST_LEGEND_RAYQUAZA, QUEST_LEGEND_KYOGRE,
	QUEST_LEGEND_LUGIA, QUEST_LEGEND_DEOXYS, QUEST_LEGEND_HO_OH, QUEST_LEGEND_MEWTWO, QUEST_LEGEND_MEW,
	QUEST_LEGEND_CELEBI, QUEST_LUCARIO_RANK, QUEST_COMPLETED_ALL_MAZES }

static var buf := PackedByteArray()
static var info: Array = []          # gScriptVarInfo dicts {type, off, bit, len, def, name}
static var local_info: Array = []
static var _ready := false

static func init() -> void:
	if _ready:
		return
	_ready = true
	GData.load_all()
	info = GData.common.vars
	local_info = GData.extra.local_vars
	if buf.size() != BUF_LEN:
		buf.resize(BUF_LEN)

static func var_name(id: int) -> String:
	return str(info[id].name) if id >= 0 and id < info.size() else str(id)

static func var_id(name: String) -> int:
	for i in info.size():
		if info[i].name == name:
			return i
	return -1

# ------------------------------------------------------------------ save
static func save_b64() -> String:
	return Marshalls.raw_to_base64(buf)

static func load_b64(s: String) -> void:
	init()
	if s == "":
		reset_all()
		return
	buf = Marshalls.base64_to_raw(s)
	if buf.size() != BUF_LEN:
		buf.resize(BUF_LEN)

## ThoroughlyResetScriptVars: a new game.
static func reset_all() -> void:
	init()
	buf = PackedByteArray()
	buf.resize(BUF_LEN)
	for i in info.size() - 1:
		var v: Dictionary = info[i]
		if int(v.type) != T_0 and int(v.type) != T_SPECIAL:
			for j in int(v.len):
				set_arr(null, i, j, int(v.def))
	clear_arr(null, CONDITION)
	for s in range(SCENARIO_SELECT, SCENARIO_SUB9 + 1):
		scenario_calc(s, 0, 0)
	set_val(null, GROUND_ENTER, GData.map_id("MAP_PERSONALITY_TEST_CYAN"))
	set_val(null, GROUND_ENTER_LINK, 0)
	set_val(null, GROUND_GETOUT, GData.map_id("MAP_PERSONALITY_TEST_CYAN"))
	set_val(null, GROUND_MAP, -1)
	set_val(null, GROUND_PLACE, 0)
	set_val(null, DUNGEON_SELECT, -1)
	set_val(null, DUNGEON_ENTER, 0)
	set_val(null, DUNGEON_ENTER_INDEX, -1)
	set_val(null, WEATHER_KIND, -1)
	for v in [DUNGEON_RESULT, START_MODE, CLEAR_COUNT, PLAYER_KIND, PARTNER1_KIND, PARTNER2_KIND, NEW_FRIEND_KIND,
			WARP_LOCK, PARTNER_TALK_KIND, BASE_KIND, BASE_LEVEL, FLAG_KIND, FLAG_KIND_CHANGE_REQUEST]:
		set_val(null, v, 0)
	for v in [WARP_LIST, RESCUE_SCENARIO_ORDER_LIST, RESCUE_SCENARIO_JOB_LIST, RESCUE_SCENARIO_CONQUEST_LIST,
			TRAINING_CONQUEST_LIST, TRAINING_PRESENT_LIST, DUNGEON_ENTER_LIST, DUNGEON_CLEAR_LIST, EVENT_S08E01]:
		clear_arr(null, v)

# ------------------------------------------------------------------ raw access
static func _ref(local, id: int) -> Array:      # [info, buffer, byte offset]
	if not _ready:
		init()          # read before any story save was loaded (title / town mode): all variables read as 0
	if id < LOCAL0:
		var i: Dictionary = info[id]
		return [i, buf, int(i.off)]
	var li: Dictionary = local_info[id - LOCAL0]
	return [li, local, int(li.off) * 4]

static func _rd(b: PackedByteArray, o: int, t: int) -> int:
	match t:
		T_U8, T_U8_2:
			return b[o]
		T_S8:
			var v := int(b[o])
			return v - 256 if v > 127 else v
		T_U16:
			return b.decode_u16(o)
		T_S16:
			return b.decode_s16(o)
		T_S32:
			return b.decode_s32(o)
	return 0

static func _wr(b: PackedByteArray, o: int, t: int, v: int) -> void:
	match t:
		T_U8, T_U8_2, T_S8:
			b[o] = v & 0xFF
		T_U16, T_S16:
			b.encode_u16(o, v & 0xFFFF)
		T_S32:
			b.encode_s32(o, wrapi(v, -2147483648, 2147483647) if v > 2147483647 or v < -2147483648 else v)

static func _special(id: int) -> int:
	match id:
		SCRIPT_MODE:
			return 0
		FRIEND_SUM:
			return Story.friend_sum()
		UNIT_SUM:
			return Story.unit_sum()
		GOLD:
			return int(Game.spendable())          # remake: Auto bank lets town payments use the bank
		BANK_GOLD:
			return int(Game.bank)
	return 0

static func get_val(local, id: int) -> int:
	var r := _ref(local, id)
	var i: Dictionary = r[0]
	var t := int(i.type)
	if t == T_BIT:
		var b: PackedByteArray = r[1]
		return 1 if (b[r[2]] & (1 << int(i.bit))) != 0 else 0
	if t == T_SPECIAL:
		return _special(id)
	return _rd(r[1], r[2], t)

static func get_arr(local, id: int, idx: int) -> int:
	idx &= 0xFFFF
	var r := _ref(local, id)
	var i: Dictionary = r[0]
	var t := int(i.type)
	var b: PackedByteArray = r[1]
	var o: int = r[2]
	match t:
		T_BIT:
			var n := idx + int(i.bit)
			return 1 if (b[o + n / 8] & (1 << (n % 8))) != 0 else 0
		T_U8, T_U8_2, T_S8:
			return _rd(b, o + idx, t)
		T_U16, T_S16:
			return _rd(b, o + idx * 2, t)
		T_S32:
			return _rd(b, o + idx * 4, t)
		T_SPECIAL:
			return _special(id)
	return 0

static func set_val(local, id: int, v: int) -> void:
	if Dialog.auto and local == null and id == BASE_LEVEL and v != get_val(null, BASE_LEVEL):
		print("    BASE_LEVEL %d -> %d at scen %s" % [get_val(null, BASE_LEVEL), v, str(scenario(SCENARIO_MAIN))])
	var r := _ref(local, id)
	var i: Dictionary = r[0]
	var t := int(i.type)
	var b: PackedByteArray = r[1]
	if t == T_BIT:
		var m := 1 << int(i.bit)
		b[r[2]] = (b[r[2]] | m) if v != 0 else (b[r[2]] & ~m & 0xFF)
	elif t == T_SPECIAL:
		if id == GOLD:
			var d := v - Game.spendable()
			if d >= 0:
				Game.money += d
			else:
				Game.pay(mini(-d, Game.spendable()))
		elif id == BANK_GOLD:
			Game.bank = v
	else:
		_wr(b, r[2], t, v)

static func set_arr(local, id: int, idx: int, v: int) -> void:
	idx &= 0xFFFF
	var r := _ref(local, id)
	var i: Dictionary = r[0]
	var t := int(i.type)
	var b: PackedByteArray = r[1]
	var o: int = r[2]
	match t:
		T_BIT:
			var n := idx + int(i.bit)
			var m := 1 << (n % 8)
			b[o + n / 8] = (b[o + n / 8] | m) if v != 0 else (b[o + n / 8] & ~m & 0xFF)
		T_U8, T_U8_2, T_S8:
			_wr(b, o + idx, t, v)
		T_U16, T_S16:
			_wr(b, o + idx * 2, t, v)
		T_S32:
			_wr(b, o + idx * 4, t, v)
		T_SPECIAL:
			set_val(local, id, v)

static func arr_len(id: int) -> int:
	return int((info[id] if id < LOCAL0 else local_info[id - LOCAL0]).len)

static func reset_arr(local, id: int) -> void:
	var i: Dictionary = info[id] if id < LOCAL0 else local_info[id - LOCAL0]
	for j in int(i.len):
		set_arr(local, id, j, int(i.def))

static func clear_arr(local, id: int) -> void:
	for j in arr_len(id):
		set_arr(local, id, j, 0)

static func arr_sum(local, id: int) -> int:
	var t := 0
	for j in arr_len(id):
		t += get_arr(local, id, j)
	return t

# ------------------------------------------------------------------ scenario
static func scenario(id: int) -> Vector2i:
	return Vector2i(get_arr(null, id, 0), get_arr(null, id, 1))

static func scenario_calc(id: int, main: int, sub: int) -> void:
	var cur := scenario(id)
	if Dialog.auto and (main != cur.x or sub != cur.y):
		print("    SCEN now %s %d,%d (was %d,%d)" % [var_name(id), main, sub, cur.x, cur.y])
	if id == SCENARIO_MAIN and (main != cur.x or sub != cur.y):
		set_val(null, CLEAR_COUNT, 0)
	set_arr(null, id, 0, main)
	set_arr(null, id, 1, sub)
	if id == SCENARIO_MAIN:
		Story.on_scenario_main(main, sub)

static func before(id: int, m: int, s: int) -> bool:
	var c := scenario(id)
	if c.x == 0x3a:
		return false
	if c.x < m:
		return true
	return s >= 0 and c.x == m and c.y < s

static func equal(id: int, m: int, s: int) -> bool:
	var c := scenario(id)
	return c.x == m and (s < 0 or c.y == s)

static func after(id: int, m: int, s: int) -> bool:
	var c := scenario(id)
	if c.x == 58:
		return false
	if c.x > m:
		return true
	return s >= 0 and c.x == m and c.y > s

# ------------------------------------------------------------------ calc / judge
static func flag_calc(a: int, b: int, op: int) -> int:
	match op:
		CALC_SET:
			return b
		CALC_SUB:
			return a - b
		CALC_ADD:
			return a + b
		CALC_MUL:
			return a * b
		CALC_DIV:
			return 0 if b == 0 else int(a / b)
		CALC_MOD:
			return 0 if b == 0 else a % b
		CALC_AND:
			return a & b
		CALC_OR:
			return a | b
		CALC_XOR:
			return a ^ b
		CALC_SETBIT:
			return (1 << b) | a
		CALC_CLEARBIT:
			return a & ~(1 << b)
		CALC_RANDOM:
			return randi_range(0, maxi(b, 1) - 1)
	return a

static func flag_judge(a: int, b: int, op: int) -> bool:
	match op:
		JUDGE_TRUE:
			return true
		JUDGE_FALSE:
			return false
		JUDGE_EQ:
			return a == b
		JUDGE_NE:
			return a != b
		JUDGE_GT:
			return a > b
		JUDGE_GE:
			return a >= b
		JUDGE_LT:
			return a < b
		JUDGE_LE:
			return a <= b
		JUDGE_AND_NONZERO:
			return (a & b) != 0
		JUDGE_XOR_NONZERO:
			return (a ^ b) != 0
		JUDGE_BIT_SET:
			return ((a >> b) & 1) != 0
	return false

static func update_imm(local, id: int, v: int, op: int) -> void:
	set_val(local, id, flag_calc(get_val(local, id), v, op))

static func update_var(local, id: int, id2: int, op: int) -> void:
	set_val(local, id, flag_calc(get_val(local, id), get_val(local, id2), op))

static func judge_imm(local, id: int, v: int, op: int) -> bool:
	return flag_judge(get_val(local, id), v, op)

static func judge_var(local, id: int, id2: int, op: int) -> bool:
	return flag_judge(get_val(local, id), get_val(local, id2), op)

# ------------------------------------------------------------------ quests (CheckQuest)
static func quest(q: int) -> bool:
	var M := SCENARIO_MAIN
	match q:
		QUEST_SET_TEAM_NAME:
			return after(M, 2, -1)
		QUEST_UNK1:
			return after(M, 3, 3)
		QUEST_CAN_ACCESS_JOBS:
			return after(M, 4, 3)
		QUEST_CAN_RECRUIT:
			return after(M, 5, 0)
		QUEST_SQUARE_ASLEEP:
			return after(M, 11, 0) and before(M, 13, 0)
		QUEST_UNK5:
			return after(M, 11, 3) and before(M, 15, 0)
		QUEST_REACHED_POSTGAME:
			return after(M, 17, -1)
		QUEST_UNLOCKED_EVOLUTIONS:
			return after(M, 18, 2)
		QUEST_CAN_CHANGE_LEADER:
			return after(M, 18, 3)
		QUEST_CAN_DEPOSIT_PARTNER:
			return after(M, 18, -1)
		QUEST_UNK10, QUEST_UNK11:
			return after(M, 5, 4)
		QUEST_UNK12:
			return not equal(M, 11, 2) and not equal(M, 11, 3)
		QUEST_IN_WORLD_CALAMITY:
			return equal(M, 16, 2)
		QUEST_MAZE_14:
			return not before(M, 5, 7)
		QUEST_MAZE_15:
			return not before(M, 15, 0)
		QUEST_LEGEND_ZAPDOS:
			return after(M, 7, -1)
		QUEST_LEGEND_MOLTRES:
			return after(M, 12, -1)
		QUEST_LEGEND_ARTICUNO:
			return after(M, 13, -1)
		QUEST_LEGEND_GROUDON:
			return after(M, 15, -1)
		QUEST_LEGEND_RAYQUAZA:
			return after(M, 16, -1)
		QUEST_LEGEND_KYOGRE:
			return after(SCENARIO_SUB2, 33, -1)
		QUEST_LEGEND_LUGIA:
			return after(SCENARIO_SUB2, 34, -1)
		QUEST_LEGEND_DEOXYS:
			return after(SCENARIO_SUB3, 36, -1)
		QUEST_LEGEND_HO_OH:
			return after(SCENARIO_SUB4, 42, -1)
		QUEST_LEGEND_MEWTWO:
			return after(SCENARIO_SUB5, 44, -1)
		QUEST_LEGEND_MEW:
			return after(SCENARIO_SUB7, 49, -1)
		QUEST_LEGEND_CELEBI:
			return rescue_conquered(GData.rescue_id("RESCUE_DUNGEON_PURITY_FOREST"))
	return false

# ------------------------------------------------------------------ rescue scenario lists (rescue_scenario.c)
static func rescue_ordered(r: int) -> bool:
	return r != 13 and get_arr(null, RESCUE_SCENARIO_ORDER_LIST, r) != 0

static func rescue_set_order(r: int, on: bool) -> void:
	if r == 13 or get_arr(null, RESCUE_SCENARIO_JOB_LIST, r) != 0:
		return
	set_arr(null, RESCUE_SCENARIO_ORDER_LIST, r, 1 if on else 0)
	if on and r in [14, 15, 28]:
		Missions.board_story_refresh()

static func rescue_job(r: int) -> bool:
	return r != 13 and get_arr(null, RESCUE_SCENARIO_JOB_LIST, r) != 0

static func rescue_set_job(r: int, on: bool) -> void:
	if r == 13:
		return
	if on:
		set_arr(null, RESCUE_SCENARIO_ORDER_LIST, r, 0)
		var sd := GData.rescue_to_script(r)
		if sd != -1:
			set_val(null, DUNGEON_SELECT, sd)
	set_arr(null, RESCUE_SCENARIO_JOB_LIST, r, 1 if on else 0)

static func rescue_conquered(r: int) -> bool:
	return r != 13 and r >= 0 and get_arr(null, RESCUE_SCENARIO_CONQUEST_LIST, r) != 0

static func rescue_set_conquered(r: int, on: bool) -> void:
	if r == 13:
		return
	if on:
		set_arr(null, RESCUE_SCENARIO_JOB_LIST, r, 0)
	set_arr(null, RESCUE_SCENARIO_CONQUEST_LIST, r, 1 if on else 0)
