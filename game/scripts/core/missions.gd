class_name Missions
extends RefCounted
## Red's rescue jobs: Pelipper's Bulletin Board, the base Mailbox, the Job List (8 slots), clients/targets in
## dungeons, and the thank-you + reward scene (money, items, Friend Areas, rescue points, team rank).
##
## Ported from pret/pmd-red: code_80958E8.c (GenerateMailJobInfo, GenerateMailJobDungeonInfo,
## GeneratePelipperJobs, sub_80961D8 mailbox jobs, AcceptJob), code_803C1B4.c (difficulty, rank points,
## rewards), pokemon_mail.c (CreateRescueTitle / CreateRescueDescription text rules), dungeon_jobs.c
## (talking to clients), thank_you_messages.c + mission_reward.c (rewards), rescue_team_info.c (ranks).
## Tables come from data/missions.json (exported by gen_missions.py).
##
## Job dictionary:
##   {id, kind: "rescue" | "target" | "escort" | "find" | "deliver", special (Red's unk2: 0, 5 evo item,
##    6 gummi, 7 parent/child, 8 friend pair, 9 lovers), dungeon, floor (1-based), client, target, item,
##    seed, diff (0..15), difficulty ("E".."*"), reward: {type, money, item, item_n, extra, rank_points,
##    friend_area}, title, text, objective, place, accepted, state, source ("board" | "mailbox")}
## state: "board" (on the board / in the mailbox), "suspended" / "taken" (in the Job List; only taken jobs are
## active in dungeons), "done_pending" (finished on the floor, not yet home safe), "done" (thank-you pending).

const MAX_JOBS := 8                       # MAX_ACCEPTED_JOBS
const MAILBOX_SLOTS := 4                  # NUM_MAILBOX_SLOTS
const RANK_PTS_CAP := 99999999            # AddToTeamRankPts
const ESCORT_LEVEL := 1                   # sub_8096A08: CreateLevel1Pokemon(clientSpecies)
const CLIENT_LEVEL := 1                   # SpawnWildMonsOnFloor: target spawns with level 1
const THROWN_REWARD_QTY := 10             # MissionRewards.quantity
const AREA_OWNED_REFUND := 1000           # MR_STATE_UNLOCK_FRIEND_AREA
## Red only talks to a client when you face it and press A. With touch controls stepping next to a client
## (Missions.on_leader_step) can open the same prompt once per approach; set false for strict Red behaviour.
const AUTO_TALK_ON_ADJACENT := true

const DIFF_LETTERS := ["E", "D", "C", "B", "A", "S", "*"]
const DIFF_COLORS := ["#ffffff", "#7fff7f", "#7fff7f", "#7fe0ff", "#7fe0ff", "#ff8070", "#ffdc4a"]
## Red's team ranks (rescue_team_info.c sRescueRankMaxPoints): [name, minimum rescue points].
const RANKS := [["Normal", 0], ["Bronze", 50], ["Silver", 500], ["Gold", 1500], ["Platinum", 3000], ["Diamond", 7500], ["Lucario", 15000]]
## gUnknown_80E80A0: rescue points by mission difficulty 0..15.
const RANK_POINTS := [1, 5, 10, 20, 40, 60, 80, 100, 150, 200, 300, 500, 700, 1000, 1500, 2000]
## sPossibleMissionTypes (values are WonderMail mission types: 0 rescue client, 1 rescue target, 2 escort,
## 3 find item, 4 deliver item).
const MISSION_ROLL := ["rescue", "target", "escort", "find", "deliver", "escort", "target", "rescue"]
const BOARD_REWARDS := ["money", "money_extra", "item", "item_extra"]                       # RandRange(MONEY, BLANK_4)
const MAILBOX_REWARDS := ["money1", "money1_extra", "item1", "item1_extra", "friend_area"]  # RandRange(MONEY1, END_REWARDS)
const FALLBACK_CLIENT := "0016"           # Red: 0x10 Pidgey when no species is eligible
const HL := "#ffdc4a"                     # Red's yellow names
const IT := "#7fff7f"                     # green item names

static var _data: Dictionary = {}

# ============================================================================ data
static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/missions.json", FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_data = v
	return _data

static func txt(k: String) -> Variant:
	return data().get("text", {}).get(k, "")

static func dinfo(key: String) -> Dictionary:
	var d: Dictionary = data().get("dungeons", {}).get(key, {})
	if d.is_empty() and bool(ddb(key).get("eos", false)):
		return eos_dinfo(key)
	return d

## Explorers of Sky / Remixed dungeons have no entry in Red's mission table: built from the dungeon itself.
## Difficulty per floor from its wild Pokémon levels (1 + level / 5, Red's 1..15 scale), no jobs on boss arena
## floors (eos_fixed) or in Lv. 1 dungeons, the items from its floor item tables, sorted after Red's dungeons.
static var _eos_info := {}

static func eos_dinfo(key: String) -> Dictionary:
	if _eos_info.has(key):
		return _eos_info[key]
	var D := ddb(key)
	var floors: Array = D.get("floors", [])
	var diff: Array = [0]
	var no_jobs: Array = []
	var items := {}
	var tabs: Array = DB.dungeons.get("item_tables", [])
	for i in floors.size():
		var f: Dictionary = floors[i]
		var lv := 0.0
		var n := 0
		for e in f.get("pk", []):
			if e is Array and e.size() > 1:
				lv += float(e[1])
				n += 1
		var avg := lv / n if n > 0 else float(D.get("eos_level", 10))
		diff.append(clampi(1 + int(avg / 5.0), 1, 15))
		if int(f.get("eos_fixed", 0)) > 0 or n == 0:
			no_jobs.append(i + 1)
		var ti := int(f.get("items", -1))
		if ti >= 0 and ti < tabs.size():
			for c in tabs[ti].get("cats", []):
				for it in c.get("items", []):
					items[str(it[0])] = true
	var info := {"red_index": 1000 + int(D.get("eos_id", D.get("index", 0))), "red_floor_count": floors.size() + 1,
		"difficulty": diff, "no_job_floors": no_jobs, "items": items.keys(),
		"jobs": floors.size() >= 2 and not bool(D.get("level_reset", false)) and no_jobs.size() < floors.size(), "eos": true}
	_eos_info[key] = info
	return info

static func ddb(key: String) -> Dictionary:
	return DB.dungeons.get("dungeons", {}).get(key, {})

# ============================================================================ ranks
static func rank_index(points: int) -> int:
	var r := 0
	for i in RANKS.size():
		if points >= int(RANKS[i][1]):
			r = i
	return r

static func rank_name(points: int) -> String:
	return str(RANKS[rank_index(points)][0])

## "Bronze Rank" (Red's GetTeamRankString)
static func rank_title(points: int) -> String:
	return rank_name(points) + " Rank"

## Points still needed for the next rank (0 at Lucario Rank) - GetPtsToNextRank.
static func pts_to_next_rank(points: int) -> int:
	var i := rank_index(points)
	if i >= RANKS.size() - 1:
		return 0
	return int(RANKS[i + 1][1]) - points

static func add_rank_points(n: int) -> void:
	Game.rank_points = mini(RANK_PTS_CAP, Game.rank_points + n)

# ============================================================================ difficulty / rewards
## Red floor count includes floor 0 (sDungeonFloorCount); real floors are 1 .. count-1.
static func red_floor_count(key: String) -> int:
	var n := int(dinfo(key).get("red_floor_count", 0))
	var real: int = ddb(key).get("floors", []).size()
	if real > 0:
		n = real + 1 if n <= 0 else mini(n, real + 1)
	return maxi(n, 2)

## sub_803C1B4: floor mission difficulty (0..15), +2 for escorts.
static func mission_difficulty(key: String, fl: int, kind: String) -> int:
	var arr: Array = dinfo(key).get("difficulty", [])
	var d := int(arr[fl]) if fl >= 0 and fl < arr.size() else 1
	if kind == "escort":
		d += 2
	return mini(d, 15)

## sub_803C1D0: difficulty letter index 0 (E) .. 6 (*).
static func letter_index(diff: int) -> int:
	return mini(diff / 2, 6)

static func difficulty_bb(letter: String) -> String:
	var i := DIFF_LETTERS.find(letter)
	return "[color=%s]%s[/color]" % [DIFF_COLORS[maxi(i, 0)], letter]

static func _thrown(id: String) -> bool:
	var it: Dictionary = DB.items.get(id, {})
	var c := str(it.get("red_cat", ""))
	return c == "thrown_line" or c == "thrown_arc"

static func _pick_w(rng: RandomNumberGenerator, pairs: Array) -> Variant:
	var tot := 0
	for p in pairs:
		tot += int(p[1])
	if tot <= 0:
		return null
	var r := rng.randi_range(0, tot - 1)
	for p in pairs:
		r -= int(p[1])
		if r < 0:
			return p[0]
	return pairs[-1][0]

## GetRandomItemForSet(setId = difficulty) - Red's reward item sets 1..15.
static func roll_reward_item(rng: RandomNumberGenerator, diff: int) -> String:
	var sets: Dictionary = data().get("item_sets", {})
	var s: Dictionary = sets.get(str(clampi(diff, 1, 15)), {})
	var cat = _pick_w(rng, s.get("cats", []))
	if cat == null:
		return "plainseed" if DB.items.has("plainseed") else ""
	var it = _pick_w(rng, s.get("items", {}).get(cat, []))
	if it == null or not DB.items.has(str(it)):
		return "plainseed" if DB.items.has("plainseed") else ""   # Red falls back to ITEM_PLAIN_SEED
	return str(it)

## sub_8095F28: a random item that can appear in this dungeon (not thrown, not Poké / Used TM).
static func dungeon_item(rng: RandomNumberGenerator, key: String) -> String:
	var pool: Array = []
	for id in dinfo(key).get("items", []):
		if id == "poke" or id == "usedtm" or not DB.items.has(id) or _thrown(id):
			continue
		pool.append(id)
	return "" if pool.is_empty() else str(pool[rng.randi_range(0, pool.size() - 1)])

static func item_in_dungeon(key: String, id: String) -> bool:
	return id in dinfo(key).get("items", [])

# ============================================================================ generation context
## Which dungeons can host jobs: Red's sub_80A29B0 = conquered rescue dungeons flagged for jobs (not the four
## Wonder-Mail-only dungeons); Tiny Woods + Thunderwave Cave if none.
static func job_dungeons() -> Array:
	var out: Array = []
	for k in Game.cleared:
		if bool(dinfo(k).get("jobs", false)) and ddb(k).has("floors") and not k in out and load("res://scripts/core/launcher_cfg.gd").dungeon_on(str(k)):
			out.append(k)
	if out.is_empty():
		for k in data().get("fallback_dungeons", ["tiny_woods", "thunderwave_cave"]):
			if ddb(k).has("floors"):
				out.append(k)
	out.sort_custom(func(a, b): return int(dinfo(a).get("red_index", 0)) < int(dinfo(b).get("red_index", 0)))
	return out

## Species Red would pick (sub_803C110): seen, base form, not banned; before the post-game also not the
## hero/partner and not the story-NPC list. "Seen" = Game.flags.seen if the game tracks it, otherwise every
## species that lives on the floors of unlocked/cleared dungeons plus the team and Friend Area residents.
static func eligible_species() -> Array:
	var seen := {}
	var fs_seen = Game.flags.get("seen", null)
	if fs_seen is Array and not fs_seen.is_empty():
		for s in fs_seen:
			seen[str(s).substr(0, 4)] = true
	elif fs_seen is Dictionary and not fs_seen.is_empty():
		for s in fs_seen:
			seen[str(s).substr(0, 4)] = true
	else:
		var keys: Array = Game.unlocked.duplicate()
		for k in Game.cleared:
			if not k in keys:
				keys.append(k)
		for k in keys:
			for f in ddb(k).get("floors", []):
				for e in f.get("pk", []):
					seen[str(e[0]).substr(0, 4)] = true
		for e in Game.team + Game.friends:
			seen[str(e.get("sp", "")).substr(0, 4)] = true
	var post := bool(Game.flags.get("postgame", false))
	var banned: Array = data().get("banned_species", [])
	var banned_pre: Array = data().get("banned_species_pregame", [])
	var hero := str(Game.team[0].get("sp", "")) if Game.team.size() > 0 else ""
	var partner := str(Game.team[1].get("sp", "")) if Game.team.size() > 1 else ""
	var out: Array = []
	for sp in seen:
		if sp.length() != 4 or not DB.species.has(sp) or sp in banned or not _in_red(sp) or not load("res://scripts/core/launcher_cfg.gd").mon_on(sp):
			continue
		if not post and (sp in banned_pre or sp == hero or sp == partner):
			continue
		out.append(sp)
	out.sort()
	return out

## Only Pokémon that exist in Red (species.json "red" flag) can post jobs.
static func _in_red(sp: String) -> bool:
	var r = DB.species.get(sp, {}).get("red", 0)
	if r is String:
		return r.is_valid_float() and float(r) != 0.0
	if r is bool:
		return r
	return (r is int or r is float) and float(r) != 0.0

static func mailbox() -> Array:
	if not Game.flags.get("mailbox", null) is Array:
		Game.flags["mailbox"] = []
	return Game.flags["mailbox"]

static func make_context(extra_existing: Array = []) -> Dictionary:
	var existing: Array = []
	existing.append_array(Game.jobs)
	existing.append_array(mailbox())
	existing.append_array(extra_existing)
	return {"species": eligible_species(), "existing": existing, "postgame": bool(Game.flags.get("postgame", false)),
		"rank": rank_index(Game.rank_points), "mailbox": false}

## sub_8095E38: an escort job blocks its whole dungeon, other jobs block their floor.
static func _occupied(existing: Array, key: String, fl: int) -> bool:
	for j in existing:
		if str(j.get("dungeon", "")) != key:
			continue
		if str(j.get("kind", "")) == "escort" or int(j.get("floor", 0)) == fl:
			return true
	return false

## GenerateMailJobDungeonInfo: random job dungeon, random floor in [count/2, count), walking floors then
## dungeons until a free location is found.
static func pick_location(rng: RandomNumberGenerator, existing: Array) -> Array:
	var list := job_dungeons()
	var cap := list.size()
	if cap == 0:
		return []
	var counter := rng.randi_range(0, cap - 1)
	var c1 := counter
	while true:
		var key: String = list[counter]
		var fc := red_floor_count(key)
		var half := fc / 2
		var fl := half if half >= fc else rng.randi_range(half, fc - 1)
		fl = maxi(fl, 1)
		var f1 := fl
		var no_job := no_job_floors(key)
		while true:
			if not fl in no_job and not _occupied(existing, key, fl):
				return [key, fl]
			fl += 1
			if fl >= fc:
				fl = maxi(half, 1)
			if fl == f1:
				break
		counter += 1
		if counter == cap:
			counter = 0
		if counter == c1:
			return []
	return []

## Floors Red never puts jobs on (gUnknown_8107828: boss / last floors). JSON numbers load as floats.
static func no_job_floors(key: String) -> Array:
	var out: Array = []
	for f in dinfo(key).get("no_job_floors", []):
		out.append(int(f))
	return out

static func _new_id(rng: RandomNumberGenerator) -> String:
	return "%d-%08x" % [Game.day, rng.randi()]

# ============================================================================ generation
## GenerateMailJobInfo: one job (board reward type by default; ctx.mailbox = true for mailbox rules).
## ctx: see make_context(); generated jobs should be appended to ctx.existing by the caller.
static func gen_job(rng: RandomNumberGenerator, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty():
		ctx = make_context()
	var loc := pick_location(rng, ctx.get("existing", []))
	if loc.is_empty():
		return {}
	var key: String = loc[0]
	var fl: int = loc[1]
	var j := {"id": _new_id(rng), "dungeon": key, "floor": fl, "seed": rng.randi() & 0xffffff, "special": 0,
		"accepted": false, "state": "board", "source": "mailbox" if ctx.get("mailbox", false) else "board"}
	var kind: String = MISSION_ROLL[rng.randi_range(0, 7)]
	if kind == "escort" and int(ctx.get("rank", 0)) == 0:
		kind = "rescue"                                   # no escorts at Normal Rank
	var pool: Array = ctx.get("species", [])
	var client := FALLBACK_CLIENT
	var target := "0019"
	if not pool.is_empty():
		client = pool[rng.randi_range(0, pool.size() - 1)]
		target = pool[rng.randi_range(0, pool.size() - 1)]
	if kind != "target" and kind != "escort":
		target = client
	var item := dungeon_item(rng, key)
	if item == "":
		kind = "rescue"
		target = client
	if int(ddb(key).get("max_items", 1)) == 0 and kind == "deliver":
		kind = "rescue"
		target = client
	var diff := mission_difficulty(key, fl, kind)
	var reward_item := ""
	for _i in 64:
		reward_item = roll_reward_item(rng, diff)
		if reward_item != item:
			break
	j.kind = kind
	j.client = client
	j.target = target
	j.item = item
	# special pools (Red: unk2 5..9)
	match kind:
		"target":
			var r := rng.randi() & 0x70
			if r == 0x10:
				_special_pair(rng, j, data().get("parent_child", []), pool, 7, false)
			elif r == 0x30:
				_special_pair(rng, j, data().get("friend_pairs", []), pool, 8, true)
		"escort":
			if (rng.randi() & 0x3000) == 0x1000:
				_special_pair(rng, j, data().get("lover_pairs", []), pool, 9, true)
		"find", "deliver":
			var r2 := rng.randi() & 0x700
			if (r2 == 0x100 or r2 == 0x600) and ctx.get("postgame", false):
				_special_item(rng, j, data().get("evo_items", []), pool, 5)
			elif r2 == 0x300:
				_special_item(rng, j, data().get("gummi_prefs", []), pool, 6)
	if kind != "find" and kind != "deliver":
		j.item = ""                                       # Red keeps a dummy targetItem; unused for these kinds
	j.diff = diff
	j.difficulty = DIFF_LETTERS[letter_index(diff)]
	j.reward = _make_reward(rng, j, reward_item, ctx)
	describe(j)
	return j

static func _special_pair(rng: RandomNumberGenerator, j: Dictionary, table: Array, pool: Array, code: int, may_swap: bool) -> void:
	var ok: Array = []
	for e in table:
		if str(e[0]) in pool and str(e[1]) in pool:
			ok.append(e)
	if ok.is_empty():
		return
	var e: Array = ok[rng.randi_range(0, ok.size() - 1)]
	if may_swap and (rng.randi() & 0x10) == 0:
		j.client = str(e[1])
		j.target = str(e[0])
	else:
		j.client = str(e[0])
		j.target = str(e[1])
	j.special = code

static func _special_item(rng: RandomNumberGenerator, j: Dictionary, table: Array, pool: Array, code: int) -> void:
	var ok: Array = []
	for e in table:
		if str(e[0]) in pool and item_in_dungeon(j.dungeon, str(e[1])) and DB.items.has(str(e[1])):
			ok.append(e)
	if ok.is_empty():
		return
	var e: Array = ok[rng.randi_range(0, ok.size() - 1)]
	j.client = str(e[0])
	j.target = str(e[0])
	j.item = str(e[1])
	j.special = code

## sub_8095E78: a Wonder-Mail Friend Area not owned and not already offered.
static func _free_friend_area(rng: RandomNumberGenerator, existing: Array) -> String:
	var ok: Array = []
	for a in data().get("wonder_mail_friend_areas", []):
		if a in Game.friend_areas:
			continue
		var offered := false
		for j in existing:
			if str(j.get("reward", {}).get("friend_area", "")) == a:
				offered = true
		if not offered:
			ok.append(a)
	return "" if ok.is_empty() else str(ok[rng.randi_range(0, ok.size() - 1)])

## sub_803C21C (+ the reward-type roll of GeneratePelipperJobs / sub_80961D8).
static func _make_reward(rng: RandomNumberGenerator, j: Dictionary, reward_item: String, ctx: Dictionary) -> Dictionary:
	var li := letter_index(int(j.diff))
	var t: String
	if ctx.get("mailbox", false):
		t = MAILBOX_REWARDS[rng.randi_range(0, MAILBOX_REWARDS.size() - 1)]
		if t == "friend_area":
			var fa := "" if li == 0 else _free_friend_area(rng, ctx.get("existing", []))
			if fa == "":
				t = "money1"
	else:
		t = BOARD_REWARDS[rng.randi_range(0, BOARD_REWARDS.size() - 1)]
	var r := {"type": t, "money": 0, "item": "", "item_n": 0, "extra": 0, "rank_points": RANK_POINTS[int(j.diff)], "friend_area": ""}
	match t:
		"money":
			r.money = (li + 1) * 100
		"money_extra":
			r.money = (li + 1) * 100
			r.item = reward_item
		"item":
			r.item = reward_item
		"item_extra":
			r.item = reward_item
			r.extra = 1
		"money1":
			r.money = (li + 1) * 200
		"money1_extra":
			r.money = (li + 1) * 200
			r.item = reward_item
		"item1":
			r.item = reward_item
		"item1_extra":
			r.item = reward_item
			r.extra = 2
		"friend_area":
			r.friend_area = _free_friend_area(rng, ctx.get("existing", []))
	if r.item != "":
		r.item_n = THROWN_REWARD_QTY if _thrown(r.item) else 1
	return r

# ============================================================================ text
static func sp_name(sp: String) -> String:
	return str(DB.species.get(sp, {}).get("name", "???"))

static func floor_label(key: String, fl: int) -> String:
	var up: bool = ddb(key).get("up", false)
	return ("%dF" % fl) if up else ("B%dF" % fl)

static func dungeon_name(key: String) -> String:
	return str(ddb(key).get("name", key.capitalize()))

static func _fmt(s: String, arg: String) -> String:
	return s.replace("%s", arg)

static func _pool_line(k: String, i: int, arg: String) -> String:
	var a: Array = txt(k)
	return "" if a.is_empty() else _fmt(str(a[i % a.size()]), arg)

## CreateRescueTitle / CreateRescueDescription: fills title, text, objective, place.
static func describe(j: Dictionary) -> void:
	var b2 := (int(j.seed) + int(dinfo(j.dungeon).get("red_index", 0))) & 0xff
	var b3 := (int(j.seed) + int(j.floor)) & 0xff
	var tn := sp_name(j.target)
	var iname: String = DB.item_name(j.item) if j.item != "" else ""
	var title := ""
	var text := ""
	var obj := ""
	match j.kind:
		"target":
			obj = _fmt(txt("obj_target"), tn)
			if j.special == 7:
				title = txt("child_title")
				for e in data().get("parent_child", []):
					if e[0] == j.client and e[1] == j.target:
						text = str(e[2])
			elif j.special == 8:
				for e in data().get("friend_pairs", []):
					if (e[0] == j.client and e[1] == j.target) or (e[1] == j.client and e[0] == j.target):
						title = str(e[2])
						text = _fmt(str(e[3]), tn)
			else:
				title = _pool_line("target_title", b2, tn)
				text = _pool_line("target_desc1", b2, tn) + "\n" + _pool_line("target_desc2", b3, tn)
		"escort":
			obj = _fmt(txt("obj_escort"), tn)
			if j.special == 9:
				title = txt("love_title")
				text = _pool_line("love_desc1", b2, tn) + "\n" + _pool_line("love_desc2", b3, tn)
			else:
				title = _pool_line("escort_title", b2, tn)
				text = _pool_line("escort_desc1", b2, tn) + "\n" + _pool_line("escort_desc2", b3, tn)
		"find", "deliver":
			obj = _fmt(txt("obj_find" if j.kind == "find" else "obj_deliver"), iname)
			title = _fmt(txt("find_title" if j.kind == "find" else "deliver_title"), iname)
			if j.special == 5:
				text = _fmt(txt("evo_desc"), iname)
			elif j.special == 6:
				text = _fmt(txt("gummi_desc"), iname)
			else:
				text = _pool_line("item_desc1", b2, iname) + "\n" + _pool_line("item_desc2", b3, iname)
		_:
			obj = txt("obj_rescue")
			title = _pool_line("rescue_title", b2, tn)
			text = _pool_line("rescue_desc1", b2, sp_name(j.client)) + "\n" + _pool_line("rescue_desc2", b3, sp_name(j.client))
	var place := "%s %s" % [dungeon_name(j.dungeon), floor_label(j.dungeon, j.floor)]
	if j.kind == "find":
		place = _fmt(txt("near"), place)
	j.title = title
	j.text = text
	j.objective = obj
	j.place = place

## Reward line as on the board: "200 Poké", "200 Poké + ?", "Oran Berry + ?", "Friend Area".
static func reward_text(j: Dictionary) -> String:
	var r: Dictionary = j.get("reward", {})
	var fm: Array = txt("reward_fmt")
	var nm := DB.item_name(str(r.get("item", ""))) if str(r.get("item", "")) != "" else ""
	match str(r.get("type", "")):
		"money", "money1":
			return str(fm[0]).replace("%d", str(r.money))
		"money_extra", "money1_extra":
			return str(fm[1]).replace("%d", str(r.money))
		"item", "item1":
			return _fmt(str(fm[2]), nm)
		"item_extra", "item1_extra":
			return _fmt(str(fm[3]), nm)
		"friend_area":
			return str(fm[4])
	return str(fm[5]) if fm.size() > 5 else "???"

# ============================================================================ board / mailbox / job list
## The board gets 5-8 fresh jobs each day (GeneratePelipperJobs: RandRange(4, 8) -> slots 0..range).
static func refresh_board_if_new_day(rng: RandomNumberGenerator = null) -> bool:
	if Game.board_day == Game.day and not Game.board.is_empty() and str(Game.flags.get("story_board", "")) == _story_sig():
		return false
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	Game.board = make_board(rng)
	Game.board_day = Game.day
	return true

static func make_board(rng: RandomNumberGenerator) -> Array:
	var board: Array = []
	var ctx := make_context()
	var hi := rng.randi_range(4, 7)
	for i in hi + 1:
		var j := gen_job(rng, ctx)
		if j.is_empty():
			break
		board.append(j)
		ctx.existing.append(j)
	# GeneratePelipperJobs: ordered story jobs come first (sub_8097318(0xe / 0xf / 0x1c))
	var sj := story_jobs(rng)
	board = board.slice(0, maxi(0, hi + 1 - sj.size()))
	sj.append_array(board)
	board = sj
	_sort(board)
	Game.flags["story_board"] = _story_sig()
	return board

## Story requests posted on the board (Red MAIL_TYPE_UNK2..4, mission type 6). Accepting one returns
## its code (1 Wynaut / 2 Smeargle / 3 Medicham) to the board's ground script instead of filing a job.
const STORY_JOBS := [
	[14, 1, "uproar_forest", 10, "0360", "0056", "Punish bad Mankey."],
	[15, 2, "howling_forest", 15, "0235", "0235", "Rescue Smeargle."],
	[28, 3, "wish_cave", 20, "0308", "0308", "Rescue Medicham."],
]

static func story_jobs(rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if not Game.story.has("vars"):      # no story progress yet: the story variables aren't loaded
		return out
	for e in STORY_JOBS:
		if not GVars.rescue_ordered(int(e[0])):
			continue
		var j := {"id": "story_%d" % int(e[1]), "story": int(e[1]), "dungeon": e[2], "floor": int(e[3]),
			"seed": rng.randi() & 0xffffff, "special": 0, "accepted": false, "state": "board", "source": "board",
			"kind": "target" if e[4] != e[5] else "rescue", "client": e[4], "target": e[5], "item": "",
			"reward": {"type": "item", "item": "reviver"}}
		describe(j)
		j.title = e[6]
		j.objective = e[6]
		if not j.has("difficulty"):
			j.difficulty = "C"
		out.append(j)
	return out

static func _story_sig() -> String:
	var a := ""
	if not Game.story.has("vars"):
		return a
	for e in STORY_JOBS:
		a += "1" if GVars.rescue_ordered(int(e[0])) else "0"
	return a

static func board_story_refresh() -> void:   # sub_809733C: ordering one of these regenerates the board
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	Game.board = make_board(rng)
	Game.board_day = Game.day

## Mailbox jobs (sub_80961D8): new letters fill slots up to a random count; rewards are the doubled-money /
## three-item / Friend Area set. Stored in Game.flags.mailbox (no dedicated save field yet).
static func refresh_mailbox_if_new_day(rng: RandomNumberGenerator = null) -> bool:
	if int(Game.flags.get("mailbox_day", -1)) == Game.day:
		return false
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	Game.flags["mailbox_day"] = Game.day
	var mb := mailbox()
	var num := mb.size()
	if num >= MAILBOX_SLOTS:
		return false
	var idx := rng.randi_range(num, MAILBOX_SLOTS - 1)
	var ctx := make_context(Game.board)
	ctx.mailbox = true
	var added := false
	for i in range(num, idx + 1):
		var j := gen_job(rng, ctx)
		if j.is_empty():
			break
		mb.append(j)
		ctx.existing.append(j)
		added = true
	_sort(mb)
	return added

## SortPelipperJobs / SortJobSlots: by dungeon, then floor.
static func _sort(a: Array) -> void:
	a.sort_custom(func(x, y):
		var ix := int(dinfo(x.dungeon).get("red_index", 0))
		var iy := int(dinfo(y.dungeon).get("red_index", 0))
		if ix != iy:
			return ix < iy
		return int(x.floor) < int(y.floor))

static func find_job(id: String) -> Dictionary:
	for j in Game.jobs:
		if str(j.id) == id:
			return j
	return {}

static func in_job_list(job: Dictionary) -> bool:
	return not find_job(str(job.get("id", ""))).is_empty()

## AcceptJob: copies the job into the Job List. Red files it as "Suspend"; use take() to activate.
static func accept(job: Dictionary) -> bool:
	if job.is_empty() or job.has("story") or in_job_list(job) or Game.jobs.size() >= MAX_JOBS:
		return false
	var c: Dictionary = job.duplicate(true)
	c.accepted = true
	c.state = "suspended"
	Game.jobs.append(c)
	_sort(Game.jobs)
	job.accepted = true
	if str(job.get("source", "")) == "mailbox":
		mailbox().erase(job)                 # a letter moves from the mailbox into the Job List
	return true

## Bulk accept (QoL): every acceptable board job for this dungeon, until the Job List is full (Red's 8).
## Returns the accepted copies (state "suspended", as accept() files them).
static func accept_all_for(dungeon_key: String, source: Array = []) -> Array:
	var out: Array = []
	var src: Array = source if not source.is_empty() else Game.board
	for j in src.duplicate():
		if Game.jobs.size() >= MAX_JOBS:
			break
		if str(j.get("dungeon", "")) == dungeon_key and accept(j):
			out.append(find_job(str(j.id)))
	return out

## Board jobs for this dungeon that accept() would take now.
static func acceptable_count(dungeon_key: String, source: Array = []) -> int:
	var src: Array = source if not source.is_empty() else Game.board
	var n := 0
	for j in src:
		if str(j.get("dungeon", "")) == dungeon_key and not in_job_list(j) and not j.has("story"):
			n += 1
	return mini(n, MAX_JOBS - Game.jobs.size())

## Job List "Take all suspended jobs". Returns how many were taken.
static func take_all_suspended(dungeon_key := "") -> int:
	var n := 0
	for j in Game.jobs:
		if j.state == "suspended" and (dungeon_key == "" or str(j.dungeon) == dungeon_key):
			take(j)
			n += 1
	return n

## Job List "Delete".
static func cancel(job: Dictionary) -> void:
	var id := str(job.get("id", ""))
	for i in range(Game.jobs.size() - 1, -1, -1):
		if str(Game.jobs[i].id) == id:
			Game.jobs.remove_at(i)
	for b in Game.board:
		if str(b.id) == id:
			b.accepted = false

## Job List "Take Job" / "Suspend".
static func take(job: Dictionary) -> void:
	var j := find_job(str(job.get("id", "")))
	if not j.is_empty() and j.state == "suspended":
		j.state = "taken"

static func suspend(job: Dictionary) -> void:
	var j := find_job(str(job.get("id", "")))
	if not j.is_empty() and j.state == "taken":
		j.state = "suspended"

## Taken jobs whose client/target waits on this floor (Red: sub_80842F0; find-item jobs have none).
static func jobs_for_floor(dungeon_key: String, fl: int) -> Array:
	var out: Array = []
	for j in Game.jobs:
		if j.state == "taken" and j.dungeon == dungeon_key and int(j.floor) == fl and j.kind != "find":
			out.append(j)
	return out

## Dungeon list marker (CountJobsinDungeon): taken / finished jobs in this dungeon.
static func count_jobs_in_dungeon(dungeon_key: String) -> int:
	var n := 0
	for j in Game.jobs:
		if j.dungeon == dungeon_key and j.state in ["taken", "done_pending", "done"]:
			n += 1
	return n

static func escort_job(dungeon_key: String) -> Dictionary:
	for j in Game.jobs:
		if j.state == "taken" and j.kind == "escort" and j.dungeon == dungeon_key:
			return j
	return {}

# ============================================================================ dungeon hooks
## Call after Dungeon.start() built team_mons and before the first build_floor(): an escort client joins.
static func on_dungeon_start(dungeon: Dungeon) -> void:
	var j := escort_job(dungeon.dkey)
	if j.is_empty():
		return
	var m := DB.make_mon(str(j.client), ESCORT_LEVEL, "team")
	m.set_meta("escort_job", str(j.id))
	m.set_meta("story", false)
	m.set_meta("no_attack", true)                 # Red: experience-locked clients don't fight (CheckVariousConditions)
	m.recruit_ok = false
	dungeon.team_mons.append(m)

## Call at the end of Dungeon.build_floor() (after wild Pokémon are placed).
## Red puts the target in place of the floor's first wild spawn (SpawnWildMonsOnFloor).
static func on_floor_built(dungeon: Dungeon) -> void:
	var fs: FloorState = dungeon.fs
	for j in jobs_for_floor(dungeon.dkey, dungeon.floor_i + 1):
		var sp := str(j.target)
		if not DB.species.has(sp):
			continue
		var pos := Vector2i(-1, -1)
		for o in fs.mons:
			if o.side == "enemy" and o.hp > 0 and not o.has_meta("shopkeeper"):
				pos = o.pos
				_remove_mon(dungeon, o)
				break
		if pos.x < 0:
			pos = _free_room_tile(fs)
		if pos.x < 0:
			continue
		var m := DB.make_mon(sp, CLIENT_LEVEL, "client")
		m.set_meta("job_id", str(j.id))
		m.set_meta("client", true)
		m.recruit_ok = false
		m.pos = pos
		m.facing = 0
		fs.mons.append(m)
		dungeon._add_sprite(m)

static func _free_room_tile(fs: FloorState) -> Vector2i:
	var cands: Array = []
	for r in fs.rooms:
		var rr: Rect2i = r
		for y in range(rr.position.y, rr.end.y):
			for x in range(rr.position.x, rr.end.x):
				var p := Vector2i(x, y)
				if fs.terrain_at(p) == 1 and fs.mon_at(p) == null and p != fs.stairs and not fs.items.has(p):
					if fs.leader == null or FloorState.cheb(p, fs.leader.pos) > 4:
						cands.append(p)
	if cands.is_empty():
		return Vector2i(-1, -1)
	return cands[fs.rng.randi_range(0, cands.size() - 1)]

static func _remove_mon(dungeon: Dungeon, m: Mon) -> void:
	dungeon.fs.mons.erase(m)
	dungeon.team_mons.erase(m)
	if m.visual and is_instance_valid(m.visual):
		m.visual.queue_free()
	m.visual = null

static func is_client(m: Mon) -> bool:
	return m != null and m.side == "client"

## Call from Dungeon._after_leader_step(). Opens the client prompt when the leader steps next to a client
## (once per approach) if AUTO_TALK_ON_ADJACENT. Returns true if a prompt was shown.
static func on_leader_step(dungeon: Dungeon) -> bool:
	if not AUTO_TALK_ON_ADJACENT or dungeon.result_sent:
		return false
	var L: Mon = dungeon.fs.leader
	if L == null:
		return false
	for m in dungeon.fs.mons.duplicate():
		if not is_client(m) or m.hp <= 0 or m.get_meta("story_npc", false) or m.get_meta("cs_hidden", false):
			continue
		var adj := FloorState.cheb(L.pos, m.pos) == 1
		if not still_needs_item(m) and adj and not m.get_meta("asked", false):
			m.set_meta("asked", true)
			await on_talk(dungeon, m)
			return true
		elif not adj:
			m.set_meta("asked", false)
	return false

## A delivery client already told the item isn't in the Toolbox, and it still isn't.
static func still_needs_item(m: Mon) -> bool:
	if not m.has_meta("need_item"):
		return false
	var it := str(m.get_meta("need_item"))
	for b in Game.bag:
		if str(b.id) == it:
			return false
	return true

## Talking to a client (Red: sub_8084448 rescue / deliver, sub_80845E0 escort). Call when the leader bumps
## into a client (do_move) or presses A facing one.
static func on_talk(dungeon: Dungeon, m: Mon) -> void:
	var root: Control = dungeon.ui_root
	var j := find_job(str(m.get_meta("job_id", "")))
	var who := "[color=%s]%s[/color]" % [HL, m.name]
	var leader_nm: String = dungeon.fs.leader.name if dungeon.fs.leader else "?"
	var subs := {"{POKEMON_0}": leader_nm, "{POKEMON_1}": who}
	if j.is_empty() or j.state != "taken":
		await say_pages(root, _sub(txt("dj_cant_talk"), subs))
		return
	dungeon.menu_open = true
	var escorted: Mon = null
	if j.kind == "escort":
		var esc: Mon = null
		for t in dungeon.fs.mons:
			if t.hp > 0 and str(t.get_meta("escort_job", "")) == str(j.id):
				esc = t
		subs["{POKEMON_2}"] = "[color=%s]%s[/color]" % [HL, esc.name if esc else sp_name(j.client)]
		if esc == null:
			await say_pages(root, txt("dj_cant_complete"))
			dungeon.menu_open = false
			return
		if not dungeon.fs.can_see(m, esc.pos):
			await say_pages(root, _sub(txt("dj_not_around"), subs))
			dungeon.menu_open = false
			return
		await say_pages(root, _sub(txt("dj_escorted"), subs))
		escorted = esc
	elif j.kind == "deliver":
		if await ask_pages(root, _sub(txt("dj_found_deliver"), subs), ["Yes", "No"]) != 0:
			dungeon.menu_open = false
			return
		var bi := -1
		for i in Game.bag.size():
			if str(Game.bag[i].id) == str(j.item) and not bool(Game.bag[i].get("sticky", false)):
				bi = i
				break
		subs["{MOVE_ITEM_0}"] = "[color=%s]%s[/color]" % [IT, DB.item_name(j.item)]
		if bi < 0:
			await say_pages(root, _sub(txt("dj_no_item"), subs))
			m.set_meta("need_item", str(j.item))     # don't come back (or pop up again) until the item is found
			dungeon.menu_open = false
			return
		Game.bag[bi].n = int(Game.bag[bi].n) - 1
		if int(Game.bag[bi].n) <= 0 or not bool(DB.items.get(str(j.item), {}).get("stack", false)):
			Game.bag.remove_at(bi)
		await say_pages(root, _sub(txt("dj_delivered"), subs))
	else:
		if await ask_pages(root, _sub(txt("dj_found_rescue"), subs), ["Yes", "No"]) != 0:
			dungeon.menu_open = false
			return
		await say_pages(root, _sub(txt("dj_badge"), subs))
	j.state = "done_pending"                      # sub_80843BC: MAIL_TYPE_UNK8
	_remove_mon(dungeon, m)                       # HandleFaint DELETED_FOR_EVENT as the beam starts
	if escorted:
		_remove_mon(dungeon, escorted)
	dungeon.obj_layer.queue_redraw()
	await dungeon.rescue_beam([m, escorted])      # sub_8042A34: light beam + sound 850, waited for
	# "A mission has been completed! Would you like to leave now?"
	while true:
		if dungeon.autoplay or dungeon.auto_answer:
			break
		if await ask_pages(root, txt("dj_done_leave"), ["Yes", "No"], false) == 0:
			if await ask_pages(root, txt("dj_really_leave"), ["Yes", "No"], false) == 0:
				dungeon.menu_open = false
				dungeon.set_meta("job_exit", true)     # left mid-dungeon: not a clear (no story / arena scripts)
				dungeon._end("rescued")
				return
		elif await ask_pages(root, txt("dj_continue"), ["Yes", "No"], false) == 0:
			break
	dungeon.menu_open = false

## Call when an expedition ends (any result) before returning to town. "cleared", "rescued" and "escaped"
## count as getting home safely: jobs done on the floor become "done" (sub_8084424) and find-item jobs
## for this dungeon are done if the item is in the Toolbox (sub_8096AF8). Otherwise finished-on-the-floor
## jobs are lost again.
static func on_dungeon_end(dungeon_key: String, result: String) -> void:
	var safe := result in ["cleared", "rescued", "escaped"]
	for j in Game.jobs:
		if j.state == "done_pending":
			j.state = "done" if safe else "taken"
		elif safe and j.state == "taken" and j.kind == "find" and j.dungeon == dungeon_key and bag_has(str(j.item)):
			j.state = "done"

static func bag_has(id: String) -> bool:
	for b in Game.bag:
		if str(b.id) == id:
			return true
	return false

static func _bag_take(id: String) -> void:
	for i in Game.bag.size():
		if str(Game.bag[i].id) == id:
			Game.bag[i].n = int(Game.bag[i].n) - 1
			if int(Game.bag[i].n) <= 0 or not bool(DB.items.get(id, {}).get("stack", false)):
				Game.bag.remove_at(i)
			return

static func pending_rewards() -> Array:
	var out: Array = []
	for j in Game.jobs:
		if j.state == "done":
			out.append(j)
	return out

# ============================================================================ rewards (back in town)
## Thank-you scene for every finished job (TYM_* + MR_*): the client thanks the team, then money, Friend
## Area, items, rescue points and a rank-up message. Removes the jobs from the Job List and saves.
static func complete_rewards(root: Control, rng: RandomNumberGenerator = null) -> void:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	for j in pending_rewards():
		await _reward_one(root, j, rng)
		Game.jobs.erase(j)
		for i in range(Game.board.size() - 1, -1, -1):
			if str(Game.board[i].id) == str(j.id):
				Game.board.remove_at(i)
	Game.save_game()

static func _reward_one(root: Control, j: Dictionary, rng: RandomNumberGenerator) -> void:
	var sp := str(j.client)
	var leader: String = str(Game.team[0].get("name", "?")) if Game.team.size() > 0 else "?"
	var solo := Game.team.size() < 2
	var cname := "[color=%s]%s[/color]: " % [HL, sp_name(sp)]
	var subs := {"{POKEMON_0}": leader, "{POKEMON_1}": sp_name(str(j.target)), "{MOVE_ITEM_0}": DB.item_name(str(j.item)), "$t": Game.team_name}
	var k := {"rescue": "thanks_rescue", "target": "thanks_target", "escort": "thanks_escort", "deliver": "thanks_deliver", "find": "thanks_find"}
	if j.kind == "find":
		_bag_take(str(j.item))
	await Dialog.say(root, cname + _sub(txt(k.get(j.kind, "thanks_rescue")), subs), sp)
	var r: Dictionary = j.reward
	# money
	if int(r.money) > 0:
		subs["{VALUE_0}"] = str(r.money)
		await Dialog.say(root, cname + _sub(txt("reward_money"), subs), sp)
		Game.money += int(r.money)
		Audio.sfx("coin")
		await say_pages(root, _sub(txt("got_money" if solo else "got_money_team"), subs))
	# Friend Area
	if str(r.get("friend_area", "")) != "":
		var a := str(r.friend_area)
		subs["{FRIEND_AREA}"] = _area_name(a)
		await Dialog.say(root, cname + _sub(txt("reward_area"), subs), sp)
		if a in Game.friend_areas:
			Game.money += AREA_OWNED_REFUND
			await say_pages(root, _sub(txt("area_owned"), subs))
		else:
			Game.friend_areas.append(a)
			await say_pages(root, _sub(txt("got_area" if solo else "got_area_team"), subs))
	# items ("+ ?" extras are rolled now, as Red does when the reward screen opens)
	if str(r.get("item", "")) != "":
		var ids: Array = [str(r.item)]
		for _e in int(r.get("extra", 0)):
			var x := ""
			for _t in 64:
				x = roll_reward_item(rng, int(j.diff))
				if not x in ids:
					break
			ids.append(x)
		if int(r.money) == 0:
			subs["{MOVE_ITEM_1}"] = _qty_name(str(r.item))
			await Dialog.say(root, cname + _sub(txt("reward_item"), subs), sp)
		for id in ids:
			if id == "":
				continue
			var n := THROWN_REWARD_QTY if _thrown(id) else 1
			var where := ""
			if not Game.bag_add(id, n):
				Game.storage[id] = int(Game.storage.get(id, 0)) + n
				where = "\nThe Toolbox is full, so it was sent to storage."
			Audio.sfx("pickup")
			await say_pages(root, "[color=%s]%s[/color] received\n[color=%s]%s[/color].%s" % [HL, leader if solo else leader + "'s team", IT, _qty_name(id), where])
	# rescue points / rank
	var pts := int(r.get("rank_points", 0))
	if pts > 0:
		var before := rank_index(Game.rank_points)
		add_rank_points(pts)
		subs["{VALUE_0}"] = str(pts)
		Audio.sfx("coin")
		await say_pages(root, _sub(txt("got_points"), subs))
		var after := rank_index(Game.rank_points)
		if after != before:
			subs["{POKEMON_2}"] = str(RANKS[before][0]) + " Rank"
			subs["{POKEMON_3}"] = str(RANKS[after][0]) + " Rank"
			Audio.sfx("levelup")
			await say_pages(root, _sub(txt("rank_up"), subs))

static func _qty_name(id: String) -> String:
	if _thrown(id):
		return "%d %s" % [THROWN_REWARD_QTY, DB.item_name(id)]
	return DB.item_name(id)

static func _area_name(a: String) -> String:
	var f := FileAccess.open("res://data/friend_areas.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			return str(d.get("areas", {}).get(a, {}).get("name", a))
	return a

# ============================================================================ message helpers
static func _sub(s: String, subs: Dictionary) -> String:
	for k in subs:
		s = s.replace(k, str(subs[k]))
	return s

## Red's messages use \f page breaks and blank-line padding; show them three lines per box.
static func pages(s: String) -> Array:
	var out: Array = []
	for part in s.split("\f"):
		var lines: Array = Array(part.split("\n"))
		var i := 0
		while i < lines.size():
			var chunk: Array = lines.slice(i, i + 3)
			while not chunk.is_empty() and str(chunk[-1]).strip_edges() == "":
				chunk.pop_back()
			while not chunk.is_empty() and str(chunk[0]).strip_edges() == "":
				chunk.pop_front()
			if not chunk.is_empty():
				out.append("\n".join(PackedStringArray(chunk)))
			i += 3
	return out

static func say_pages(root: Control, s: String, speaker := "") -> void:
	var p := pages(s)
	if p.is_empty():
		return
	await Dialog.talk(root, p, speaker)

static func ask_pages(root: Control, s: String, options: Array, cancel := true) -> int:
	var p := pages(s)
	if p.is_empty():
		return -1
	for i in p.size() - 1:
		await Dialog.say(root, p[i])
	return await Dialog.ask(root, p[-1], options, "", "Normal", cancel)
