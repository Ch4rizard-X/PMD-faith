class_name Story
extends RefCounted
## Glue between Red's ground scripts and this game: team / names / friend areas / items for the scripts,
## SPECIAL_TEXT handlers (shops, naming, personality quiz, dungeon list...), the script "special functions"
## (sub_80A14E8), and per-day / scenario hooks.

const STARTERS_RED := [25, 52, 133, 325, 7, 158, 283, 54, 4, 280, 155, 104, 66, 1, 152, 277]

static var host                   # main.gd

# ------------------------------------------------------------------ team access
static func hero_species() -> String:
	return str(Game.hero.get("sp", "0025"))

static func partner_species() -> String:
	return str(Game.partner.get("sp", "0004"))

## main_loops.c sBaseKindTable / sTalkKindTable: the team base's look follows the HERO's species (BASE_KIND,
## 6 maps each: basic / construction / final, outside + inside); the partner's lines follow PARTNER_TALK_KIND.
## Red sets both when the team is made and on every start; the remake never did, so every base was Pikachu's
## (kind 0) once Team Meanies were beaten and the base was rebuilt.
const BASE_KIND_OF := {"0025": 0, "0052": 1, "0133": 2, "0300": 3, "0007": 4, "0158": 5, "0258": 6, "0054": 7,
	"0004": 8, "0255": 9, "0155": 10, "0104": 11, "0066": 12, "0001": 13, "0152": 14, "0252": 15}
const TALK_KIND_OF := {"0007": 1, "0158": 1, "0255": 3, "0152": 3}

static func sync_base_kind() -> void:
	if not Game.story.has("vars") or Game.hero.is_empty():
		return
	var kind := int(BASE_KIND_OF.get(hero_species().substr(0, 4), 0))
	if DebugNpc.style_override() >= 0:
		kind = DebugNpc.style_override()          # the Debug NPC's base style, for this session
	GVars.set_val(null, GVars.BASE_KIND, kind)
	if not Game.partner.is_empty():
		GVars.set_val(null, GVars.PARTNER_TALK_KIND, int(TALK_KIND_OF.get(partner_species().substr(0, 4), 2)))

static func leader_species() -> String:
	return str(Game.team[0].sp) if Game.team.size() > 0 else hero_species()

static func leader_is_hero() -> bool:
	return Game.team.size() > 0 and Game.team[0] == Game.hero

static func leader_is_partner() -> bool:
	return Game.team.size() > 0 and Game.team[0] == Game.partner

static func leader_kind() -> int:
	if leader_is_hero():
		return 1
	if leader_is_partner():
		return 2
	return 3

## Team members at the base other than hero/partner (kinds 10-13).
static func base_team() -> Array:
	var out: Array = []
	for e in Game.team:
		if e != Game.hero and e != Game.partner:
			out.append(e)
	return out

static func friend_area_mon(map: int, i: int) -> Dictionary:
	var fa := GData.fa_of_map(map)
	if fa == 0:
		return {}
	var key := fa_key(fa)
	var n := 0
	for e in Game.friends:
		if str(e.get("area", "")) == key:
			if n == i:
				return e
			n += 1
	return {}

## Lives kinds 30 / 31 (ground_lives.c via sub_8096AF8): the client / target of the job being thanked for.
static func job_client_species(client: bool) -> String:
	if ty_job.is_empty():
		return ""
	return str(ty_job.get("client", "")) if client else _ty_target(ty_job)

# ------------------------------------------------------------------ thank-you loop (SPECIAL_TEXT_UNK_22 / 23)
static var ty_job: Dictionary = {}

static func _ty_target(j: Dictionary) -> String:
	return str(j.get("target", "")) if str(j.get("kind", "")) in ["target", "escort"] else ""

## True when the finished jobs of this run are paid out by the ground thank-you loop (Red: a won rescue-job run,
## DUNGEON_ENTER 81 -> GETOUT_R00E01A -> EVENT_R00E01A_L001 at the Post Office) instead of right after the dungeon.
static func thank_you_in_ground(ok: bool) -> bool:
	return ok and Game.story.has("vars") and GAction._s16(GVars.get_val(null, GVars.DUNGEON_ENTER)) == 81 \
		and Missions.pending_rewards().size() > 0

## SPECIAL_TEXT_UNK_22: the next finished job -> 1 client only, 3 client + target (Red: 2 target only); 0 = done.
static func thank_you_next() -> int:
	var sc: Vector2i = GVars.scenario(2)
	var list: Array = Missions.pending_rewards()
	if not list.is_empty() and sc.y < 8:
		ty_job = list[0]
		GVars.scenario_calc(2, sc.x, sc.y)
		var v := (1 if str(ty_job.get("client", "")) != "" else 0) + (2 if _ty_target(ty_job) != "" else 0)
		return v if v != 0 else 3
	ty_job = {}
	GVars.scenario_calc(2, 0, 0)
	return 0

## SPECIAL_TEXT_UNK_23 (TYM_Create + mission_reward.c): the client's thanks and the reward, then the job is done.
static func thank_you_reward(root: Control) -> int:
	if ty_job.is_empty():
		return 0
	var j := ty_job
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	await Missions._reward_one(root, j, rng)
	Game.jobs.erase(j)
	for i in range(Game.board.size() - 1, -1, -1):
		if str(Game.board[i].id) == str(j.id):
			Game.board.remove_at(i)
	var cc := GVars.var_id("CLEAR_COUNT")
	if GVars.get_val(null, cc) < 100:
		GVars.set_val(null, cc, GVars.get_val(null, cc) + 1)
	GVars.set_val(null, 0x39, 1)
	var sc: Vector2i = GVars.scenario(2)
	GVars.scenario_calc(2, sc.x, sc.y + 1)
	ty_job = {}
	Game.save_game()
	return 1

static func name_of_kind(k: int) -> String:
	match k:
		1, 6, 33:
			return str(Game.hero.get("name", ""))
		2, 7, 34:
			return str(Game.partner.get("name", ""))
		3, 8, 35:
			return str(Game.team[0].name) if Game.team.size() > 0 else ""
	if k >= 10 and k <= 13:
		var bt := base_team()
		return str(bt[k - 10].name) if k - 10 < bt.size() else ""
	return ""

static func rename_kind(k: int, nm: String) -> void:
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	nm = re.sub(nm, "", true).strip_edges()     # never store BBCode markup as a name
	if nm == "":
		return
	match k:
		1, 6, 33:
			Game.hero.name = nm
		2, 7, 34:
			Game.partner.name = nm

static func friend_sum() -> int:
	return Game.friends.size()

static func unit_sum() -> int:
	return Game.team.size()

# ------------------------------------------------------------------ friend areas
static func map_of_fa_key(k: String) -> int:
	k = norm_fa_key(k)
	for v in GData.extra.enums.friend_areas:
		var fa := int(v)
		if fa_key(fa) == k:
			return GData.map_of_fa(fa)
	return -1

## Red's enum names that differ from the remake's Friend Area keys (data/friend_areas.json, the world map,
## Wigglytuff, residents' "area"): the remake key is the one used everywhere.
const FA_ALIASES := {"mistriseforest": "mistrise", "flyawayforest": "flyaway", "agedchamberoexclaim": "agedchambero"}

static func norm_fa_key(k: String) -> String:
	return FA_ALIASES.get(k, k)

static func fa_key(fa: int) -> String:
	var n := GData.enum_name("friend_areas", fa)
	return norm_fa_key(n.trim_prefix("FRIEND_AREA_").to_lower().replace("_", ""))

## Old saves could hold both spellings of the same area ("mistriseforest" and "mistrise"): one, the remake key.
static func normalize_friend_areas() -> void:
	var out: Array = []
	for k in Game.friend_areas:
		var n := norm_fa_key(str(k))
		if not n in out:
			out.append(n)
	Game.friend_areas = out

static func unlock_friend_area(fa: int) -> void:
	if fa <= 0:
		return
	var k := fa_key(fa)
	if not k in Game.friend_areas:
		Game.friend_areas.append(k)

static func unlock_friend_area_of(sp: String) -> void:
	var k := Services.area_of(sp)
	if k != "" and not k in Game.friend_areas:
		Game.friend_areas.append(k)

## Special 0x29 (ground_script.c): pick the Pokémon that comes to visit the base and asks to join. Red skips the
## legendaries, and, when its Friend Area is already yours, Pokémon you have or whose area is full.
## Returns 1 (its Friend Area is yours), 2 (it isn't: joining unlocks it) or 0 (nobody can come).
const NEW_FRIEND_SKIP := ["0144", "0145", "0146", "0383", "0384", "0382", "0249", "0351", "0386", "0150", "0385", "0151",
	"0380", "0381", "0244", "0243", "0245", "0250", "0377", "0378", "0379", "0251"]
static func _pick_new_friend(G) -> int:
	var cands: Array = []
	for rid in range(2, 0x1A4):
		var sp := GData.species_of_red(rid)
		if sp == "" or not DB.species.has(sp) or sp.substr(0, 4) in NEW_FRIEND_SKIP:
			continue
		var area := Services.area_of(sp)
		if area == "":
			continue
		if area in Game.friend_areas:
			if _has_mon(sp):
				continue
			var n := 0
			for f in Game.friends:
				if str(f.get("area", Services.area_of(str(f.get("sp", ""))))) == area:
					n += 1
			if n >= int(Services.fa().get("areas", {}).get(area, {}).get("cap", 99)):
				continue
		cands.append(rid)
	if cands.is_empty():
		GVars.set_val(null, GVars.NEW_FRIEND_KIND, 0)
		return 0
	var pick: int = cands[randi_range(0, cands.size() - 1)]
	GVars.set_val(null, GVars.NEW_FRIEND_KIND, pick)
	var psp := GData.species_of_red(pick)
	G.text.friend_area_name = Services.area_name(Services.area_of(psp))
	return 1 if Services.has_area_for(psp) else 2

static func friend_area_unlocked(fa: int) -> bool:
	return fa > 0 and fa_key(fa) in Game.friend_areas

# ------------------------------------------------------------------ items (Red ids)
static func item_key(red_id: int) -> String:
	for k in DB.items:
		if int(DB.items[k].get("red_id", -1)) == red_id:
			return k
	return ""

static func has_item_red(id: int) -> bool:
	var k := item_key(id)
	for b in Game.bag:
		if str(b.id) == k:
			return true
	return false

static func remove_item_red(id: int) -> void:
	var k := item_key(id)
	for i in Game.bag.size():
		if str(Game.bag[i].id) == k:
			Game.bag.remove_at(i)
			return

static func item_space_red(_id: int) -> int:
	return 1 if Game.bag.size() < Game.BAG_MAX else 0

static func give_item_red(id: int) -> void:
	var k := item_key(id)
	if k == "":
		return
	if not Game.bag_add(k):
		Game.storage[k] = int(Game.storage.get(k, 0)) + 1

# ------------------------------------------------------------------ hooks
static func on_scenario_main(_m: int, _s: int) -> void:
	pass

static func on_rescue_conquered(r: int) -> void:
	var sd := GData.rescue_to_script(r)
	if sd < 0:
		return
	var did := int(GData.dungeon_info(sd).dungeon)
	var keys: Array = DB.dungeons.get("dungeons", {}).keys()
	if did >= 0 and did < keys.size():
		var k: String = keys[did]
		if not k in Game.unlocked:
			Game.unlocked.append(k)

## Script command 0xB1 (sub_80975A8): a training maze cleared (TRAINING_CONQUEST_LIST[maze]).
static func set_misc_flag(s: int, on: bool) -> void:
	GVars.set_arr(null, GVars.TRAINING_CONQUEST_LIST, s, 1 if on else 0)

static func achievement(s: int) -> void:
	AdventureLog.set_bit(s)        # script command 0xB2 (SetAdventureAchievement)

static func cutscene_flag(f: int) -> bool:
	return bool(Game.story_get("cut_%d" % f, false))

static func daily_update() -> void:       # sub_8001D88 (event_flag.c): opens post-game dungeons / starts side stories
	var m := GVars.scenario(GVars.SCENARIO_MAIN)
	if m.x < 1 or m.x > 0x1b:
		return
	var S1 := GVars.SCENARIO_SUB1
	if GVars.before(S1, 31, 0):
		if GVars.after(GVars.SCENARIO_MAIN, 0xf, 7):
			if Dialog.auto:
				print("    DAILY base upgrade: main=%s sub1=%s" % [str(m), str(GVars.scenario(S1))])
			GVars.scenario_calc(S1, 31, 0)
			GVars.rescue_set_conquered(_rd("UPROAR_FOREST"), true)
			GVars.set_val(null, GVars.BASE_LEVEL, 2)
		elif GVars.equal(S1, 0, 0) and GVars.after(GVars.SCENARIO_MAIN, 0xf, 3):
			GVars.scenario_calc(S1, 0x1d, 1)
	if GVars.equal(S1, 0x1f, 0) and _fa("skyblueplains"):
		GVars.scenario_calc(S1, 0x1f, 1)
		GVars.rescue_set_order(_rd("HOWLING_FOREST"), true)
	if m.x <= 0x11:
		return
	var S2 := GVars.var_id("SCENARIO_SUB2")
	GVars.rescue_set_job(_rd("WATERFALL_POND"), true)
	if _has_item("dive") or GVars.after(S2, 0x21, 3):
		GVars.rescue_set_job(_rd("SOLAR_CAVE"), true)
	if _fa("furnacedesert"):
		GVars.rescue_set_job(_rd("DESERT_REGION"), true)
	if _fa("bouldercave"):
		GVars.rescue_set_job(_rd("SOUTHERN_CAVERN"), true)
	if _fa("dragoncave"):
		GVars.rescue_set_job(_rd("WYVERN_HILL"), true)
	if _fa("secretiveforest"):
		GVars.rescue_set_job(_rd("DARKNIGHT_RELIC"), true)
	if _fa("serenesea"):
		GVars.rescue_set_job(_rd("GRAND_SEA"), true)
		GVars.rescue_set_job(_rd("FAR_OFF_SEA"), true)
	if _fa("agedchamberan") and _fa("agedchambero"):
		GVars.rescue_set_job(_rd("UNOWN_RELIC"), true)
	if GVars.equal(S2, 0, 0):
		GVars.scenario_calc(S2, 0x21, 1)
	if _has_item("surf"):
		if GVars.equal(GVars.var_id("SCENARIO_SUB4"), 0, 0):
			GVars.scenario_calc(GVars.var_id("SCENARIO_SUB4"), 0x26, 1)
		if GVars.equal(GVars.var_id("SCENARIO_SUB6"), 0, 0) and _fa("southernisland"):
			GVars.scenario_calc(GVars.var_id("SCENARIO_SUB6"), 0x2e, 1)
	if not GVars.before(GVars.var_id("SCENARIO_SUB6"), 0x30, 0):
		if GVars.equal(S2, 0x22, 0) and _recruited("0144") and _recruited("0145") and _recruited("0146"):
			GVars.scenario_calc(S2, 0x22, 1)
		var S8 := GVars.var_id("SCENARIO_SUB8")
		if GVars.equal(S8, 0, 0) and GVars.after(S2, 0x21, 3) and _fa("skyblueplains"):
			GVars.scenario_calc(S8, 0x33, 1)
		if _fa("skyblueplains"):
			GVars.rescue_set_job(_rd("JOYOUS_TOWER"), true)
			GVars.rescue_set_job(_rd("PURITY_FOREST"), true)
	if not GVars.before(S2, 0x22, 0):
		var S7 := GVars.var_id("SCENARIO_SUB7")
		if GVars.equal(S7, 0, 0):
			GVars.scenario_calc(S7, 0x31, 1)
			GVars.rescue_set_order(_rd("BURIED_RELIC"), true)
		var S9 := GVars.var_id("SCENARIO_SUB9")
		if GVars.equal(S9, 0, 0) and not GVars.before(GVars.var_id("SCENARIO_SUB8"), 0x34, 0):
			GVars.scenario_calc(S9, 0x35, 1)
	var S3 := GVars.var_id("SCENARIO_SUB3")
	if GVars.equal(S3, 0, 0) and _recruited("0249"):
		GVars.scenario_calc(S3, 0x24, 1)
	var S5 := GVars.var_id("SCENARIO_SUB5")
	if GVars.equal(S5, 0, 0) and _recruited("0250"):
		GVars.scenario_calc(S5, 0x2c, 1)

static var eos_pick := ""

## Explorers of Sky dungeons open by the team's highest level (their first floor's usual enemy level);
## the level-reset ones (Zero Isles, Destiny Tower ...) wait for the post-game.
## Explorers of Sky's post-game dungeons: only after Red's story is over (whatever the team's level).
const EOS_POSTGAME := ["eos_zero_isle_north", "eos_zero_isle_east", "eos_zero_isle_west", "eos_zero_isle_south",
	"eos_zero_isle_center", "eos_destiny_tower"]

## The Explorers of Sky dungeons on the dungeon list: those at or below the level of the team you're taking
## (not Friend Area residents: a Lv. 90 recruit, such as a Kecleon from a shop, used to open everything), and
## the level-reset and post-game ones after the story.
static func eos_unlocked() -> Array:
	var top := 1
	for e in Game.team:
		top = maxi(top, int(e.get("level", 1)))
	# post-game: the story past its last chapter AND Sky Tower beaten (either alone has opened them by mistake)
	# post-game: Red's own "reached the post-game" quest flag AND Sky Tower beaten (the scenario number alone
	# changes mid-script, which could flash these dungeons into the list)
	var post := Game.story.has("vars") and GVars.quest(GVars.QUEST_REACHED_POSTGAME) and "sky_tower_summit" in Game.cleared
	var out: Array = []
	for k in DB.dungeons.get("dungeons", {}):
		var d: Dictionary = DB.dungeons.dungeons[k]
		if not d.get("eos", false):
			continue
		if d.get("level_reset", false) or k in EOS_POSTGAME:
			if post:
				out.append(k)
		elif top >= int(d.get("eos_level", 1)):
			out.append(k)
	out.sort_custom(func(a, b): return int(DB.dungeons.dungeons[a].get("eos_level", 1)) < int(DB.dungeons.dungeons[b].get("eos_level", 1)))
	return out

static func _side_story_rescues() -> Array:
	var out: Array = []
	for n in ["HOWLING_FOREST", "STORMY_SEA", "GREAT_CANYON_2", "FIERY_FIELD", "LIGHTNING_FIELD", "NORTHWIND_FIELD", "MT_FARAWAY",
			"NORTHERN_RANGE", "PITFALL_VALLEY", "SILVER_TRENCH", "BURIED_RELIC", "WISH_CAVE", "METEOR_CAVE", "WESTERN_CAVE",
			"MT_FREEZE_2", "MURKY_CAVE"]:
		out.append(_rd(n))
	return out

static func _rd(n: String) -> int:
	return GData.rescue_id("RESCUE_DUNGEON_" + n)

static func _fa(k: String) -> bool:
	return k in Game.friend_areas

static func _has_item(id: String) -> bool:
	for b in Game.bag:
		if str(b.get("id", "")) == id:
			return true
	return int(Game.storage.get(id, 0)) > 0 if Game.storage is Dictionary else false

static func _recruited(sp: String) -> bool:
	for f in Game.friends:
		if str(f.get("sp", "")).substr(0, 4) == sp:
			return true
	for t in Game.team:
		if t is Dictionary and str(t.get("sp", "")).substr(0, 4) == sp:
			return true
	return false

static func new_day() -> void:
	Game.day += 1

# ------------------------------------------------------------------ dungeon entry text (BufferDungeonRequirementsText)
## [0 = go, 1 = can't (info box), 2 = ask (yes/no box), text]
static func dungeon_requirements(sdun: int) -> Array:
	var did := int(GData.dungeon_info(sdun).dungeon)
	var keys: Array = DB.dungeons.get("dungeons", {}).keys()
	if did < 0 or did >= keys.size():
		return [0, ""]
	var d: Dictionary = DB.dungeons.dungeons[keys[did]]
	if Dojo.is_maze_script(sdun):
		d = DB.dungeons.dungeons[Dojo.maze_key(sdun - Dojo.FIRST_SCRIPT)]
	var party := int(d.get("party", 4))
	if Game.team.size() > party:
		return [1, "Only %d Pokémon may enter %s.\nYour team is too large." % [party, d.name]]
	return [0, ""]

# ------------------------------------------------------------------ special functions (sub_80A14E8)
static func special_func(G, act: GAction, idx: int, r2: int, r3: int) -> int:
	match idx:
		1:
			G._day_reset()
			return 0
		2:
			return 0
		3:
			return 0
		4, 8, 15:
			return 0
		5, 6, 7:
			return 0
		9:
			return 0 if Game.team.size() <= 1 else 1
		0xA:
			return 0
		0xB:
			var did := int(GData.dungeon_info(GVars.get_val(null, GVars.DUNGEON_ENTER_INDEX)).dungeon)
			var keys: Array = DB.dungeons.get("dungeons", {}).keys()
			var dk: String = keys[did] if did >= 0 and did < keys.size() else ""
			for j in Game.jobs:
				if str(j.get("dungeon", "")) == dk:
					return 1
			return 0
		0xC:
			return 0
		0xD:
			return Dojo.all_cleared_once()       # sub_8097640: every basic training course cleared (first time)
		0xE:
			return Dojo.team_maze_present()      # a cleared team maze not yet rewarded (index - 16)
		0x10:
			return BaseMenu.friend_talk(G, act)     # HABITAT_TALK: a Friend Area resident's menu (party_list_menu.c)
		0x11:
			return 1 if G.lives[0].ctrl_mode() == 1 else 0
		0x12:
			return 1 if Input.is_action_pressed("gp_l") or Input.is_action_pressed("gp_r") else 0
		0x13:
			return 1
		0x14:
			return 1
		0x15:
			var r = G.lives_find(r2)
			if r >= 0 and act.owner != null:
				var lim := r3 << 8
				var a: Vector2i = act.owner.get_center()
				var b: Vector2i = G.lives[r].get_center()
				if a.x - lim <= b.x and a.x + lim >= b.x and a.y - lim <= b.y and a.y + lim >= b.y:
					return 1
			return 0
		0x16:
			Game.partner.name = ""
			return 1
		0x17:
			unlock_friend_area(GData.enum_value("friend_areas", "FRIEND_AREA_WILD_PLAINS"))
			unlock_friend_area(GData.enum_value("friend_areas", "FRIEND_AREA_MIST_RISE_FOREST"))
			return 0
		0x18, 0x1A, 0x1E, 0x24, 0x26, 0x2B, 0x31:
			var kind = {0x18: 0x3C, 0x1A: 0x53, 0x1E: 124, 0x24: 0x79, 0x26: 0x7A, 0x2B: 0x20, 0x31: 82}[idx]
			G.text.name_buffer = G._strip_name(G.lives_name_by_kind(kind))
			return 0
		0x19:
			return _recruit_story(G, "0081", "Magnemite", 6, ["Metal Sound", "Tackle", "ThunderShock"], r2)
		0x1B:
			return _recruit_story(G, "0359", "Absol", 20, ["Scratch", "Leer", "Taunt", "Quick Attack"], -1, true)
		0x1C:
			return 0
		0x1D:
			return 0
		0x1F:
			return _recruit_story(G, "0235", "Smeargle", 5, ["Sketch"], r2)
		0x20:
			unlock_friend_area(GData.enum_value("friend_areas", "FRIEND_AREA_LEGENDARY_ISLAND"))
			for sp in ["0145", "0146", "0144"]:
				_add_friend(sp, DB.species.get(sp, {}).get("name", "?"), 1, [])
			return 0
		0x21:
			for sp in ["0144", "0145", "0146"]:
				if not _has_mon(sp):
					return 0
			return 1
		0x22:
			var ls := leader_species()
			return 0 if ls in ["0144", "0145", "0146"] else 1
		0x23:
			return 2 if leader_species() == "0250" else (1 if Pokedex.seen_dict().has("0250") else 0)
		0x25:
			unlock_friend_area_of("0381")          # Red unlocks Latios's Friend Area first if needed
			return _recruit_story(G, "0381", G.text.name_buffer, 30, ["Psywave", "Memento", "Helping Hand", "Safeguard"], -1)
		0x27:
			return _recruit_story(G, "0380", G.text.name_buffer, 28, ["Psywave", "Wish", "Helping Hand", "Safeguard"], -1)
		0x28:
			_give_key("wishstone")
			return 0
		0x29:
			return _pick_new_friend(G)
		0x2A:
			var nf := GVars.get_val(null, GVars.NEW_FRIEND_KIND)
			if nf == 0:
				return 0
			var nsp := GData.species_of_red(nf)
			G.text.friend_area_name = Services.area_name(Services.area_of(nsp))
			return 1 if Services.has_area_for(nsp) else 2
		0x2C:
			# a Pokémon that came to the base joins (r2 != 0: you said yes), unlocking its Friend Area if needed
			if r2 == 0:
				GVars.set_val(null, GVars.NEW_FRIEND_KIND, 0)
				return 0
			var nf2 := GVars.get_val(null, GVars.NEW_FRIEND_KIND)
			if nf2 == 0:
				return 0
			var sp2 := GData.species_of_red(nf2)
			G.text.friend_area_name = Services.area_name(Services.area_of(sp2))
			unlock_friend_area_of(sp2)
			var nm2: String = G.text.name_buffer if G.text.name_buffer != "" else str(DB.species.get(sp2, {}).get("name", "?"))
			if _add_friend(sp2, nm2, 1, []).is_empty():
				return 0
			AdventureLog.add("joined")
			return 1
		0x2D:
			return 0
		0x2E:
			return 0
		0x2F:
			Game.money += 10000
			return 0
		0x30:
			return 0
		0x32:
			return _recruit_story(G, "0282", G.text.name_buffer, 5, ["Confusion", "Double Team", "Teleport", "Growl"], -1)
		0x33:
			return 0
		0x34:
			for i in 3:
				_give_key("apple")
			return 0
		0x35:
			return 2 if leader_species() == "0113" else (1 if Pokedex.seen_dict().has("0113") else 0)
		0x36:
			G.scroll.e8 = Vector2i(r2, r3)
			return 0
		0x37:
			G.scroll.f8 = Vector2i(r2, r3)
			G.scroll.f0 = 0
			G.scroll.f4 = 0
			return 0
		0x38, 0x39, 0x3A, 0x3B:
			return 0
		0x3C:
			for i in 24:
				G.lives_set_flags(i, 0x400000)
			for T in G.objects:
				if T.kind != -1:
					T.flags |= 0x400000
			return 0
		0x3D, 0x3E:
			return 0
		0x3F:
			return 0
		0x40:
			G.demo_cancel_ok = r2 != 0      # sub_80993C0: boot demos may be skipped from now on
			return 0
		0x41, 0x42:
			G.game_end_request(r2)
			Audio.fade_out_music(r2)
			return 0
		0x43:
			G.bgm_saved = int(Audio.current) if Audio.current != "" else -1
			return 1 if G.bgm_saved != -1 else 0
		0x44, 0x45, 0x46:
			if G.bgm_saved != -1:
				G.bgm_play(G.bgm_saved, 0)
				G.bgm_saved = -1
				return 1
			return 0
		0x47, 0x48, 0x49, 0x4A:
			return 0
	return 0

static func _give_key(k: String) -> void:
	if DB.items.has(k):
		if not Game.bag_add(k):
			Game.storage[k] = int(Game.storage.get(k, 0)) + 1

static func _has_mon(sp: String) -> bool:
	for e in Game.team + Game.friends:
		if str(e.sp) == sp:
			return true
	return false

static func add_friend(sp: String, nm: String, lv: int, moves: Array) -> Dictionary:
	return _add_friend(sp, nm, lv, moves)

static func _add_friend(sp: String, nm: String, lv: int, moves: Array) -> Dictionary:
	if not DB.species.has(sp):
		return {}
	var e: Dictionary = Game._entry(sp, nm, lv)
	if moves.size() > 0:
		var mv: Array = []
		for m in moves:
			var md: Dictionary = DB.moves.get(m, {})
			if not md.is_empty():
				mv.append({"name": m, "pp": int(md.get("pp", 10)), "max_pp": int(md.get("pp", 10)), "linked": false, "on": true})
		if mv.size() > 0:
			e.moves = mv
	e["area"] = Services.area_of(sp)
	if e.area != "" and not e.area in Game.friend_areas:
		Game.friend_areas.append(e.area)
	Game.friends.append(e)
	return e

static func _recruit_story(G, sp: String, nm: String, lv: int, moves: Array, fmt_slot: int, join_team := false) -> int:
	if nm == "":
		nm = DB.species.get(sp, {}).get("name", "?")
	var e := _add_friend(sp, nm, lv, moves)
	if e.is_empty():
		return 1
	if fmt_slot >= 0 and fmt_slot < G.text.names.size():
		G.text.names[fmt_slot] = "[color=#7fe0ff]%s[/color]" % nm
	if join_team and Game.team.size() < 4:
		Game.friends.erase(e)
		Game.team.append(e)
	return 0

# ------------------------------------------------------------------ special text
static func special_text(G, kind: int, a1: int, a2: int, s) -> int:
	var root: Control = G.ui_root
	match kind:
		G.SP_WAITING:
			return 1
		G.SP_PLAYER_NAME_INPUT:
			# Red's naming screen (scripts/ui/naming_screen.gd): a1 0 = "What is your name?" (CreateConfirmNameMenu 0),
			# else the nickname prompt (mode 2); a2 != 0 lets B on an empty name cancel (textbox unk424)
			var nm := await NamingScreen.ask(root, NamingScreen.SELF if a1 == 0 else NamingScreen.POKEMON, str(s) if s != null else "", a2 != 0)
			if nm == "":
				return 0
			G.text.name_buffer = nm
			return 1
		G.SP_TEAM_NAME_INPUT:
			var nm := await NamingScreen.ask(root, NamingScreen.TEAM, str(s) if s != null else "", a2 != 0)
			if nm == "":
				return 0
			G.text.name_buffer = nm
			return 1
		G.SP_PASSWORD_INPUT:
			var nm := await NamingScreen.ask(root, NamingScreen.PASSWORD1, "", a2 != 0)
			if nm == "":
				return 0
			G.text.name_buffer = nm
			return 1
		G.SP_FRIEND_MENU, G.SP_MENU:
			if host and host.has_method("ground_menu"):
				return await host.ground_menu(G, s if s is Dictionary else {})
			return -1
		G.SP_YES_NO_LARGE:
			var i := await Dialog.ask(root, str(s), ["Yes", "No"])
			return 1 if i == 0 else 0
		G.SP_LARGE_TEXT:
			await Dialog.say(root, str(s))
			return 0
		G.SP_BUY_FRIEND_AREAS, G.SP_FRIEND_SHOP:
			await Services.wigglytuff(root)
			return 0
		G.SP_DUNGEON_LIST:
			return await _dungeon_list(root, G)
		G.SP_SAVE_1, G.SP_SAVE_2:
			if kind == G.SP_SAVE_1:
				GVars.set_val(null, GVars.START_MODE, 1)
			AdventureLog.update()
			if Dialog.auto or ListMenu.auto:
				Game.save_game(true)
			else:
				await SaveUI.save_ground(root)     # save_write.c texts + saving icon
			return 0
		G.SP_STORAGE_WITH_DIALOG, G.SP_STORAGE:
			await Services.storage(root)
			return 0
		G.SP_BANK:
			await Services.bank(root)
			return 0
		G.SP_GREEN_KECLEON, G.SP_PURPLE_KECLEON:
			await Services.kecleon(root, kind == G.SP_PURPLE_KECLEON)
			return 0
		G.SP_LINK_SHOP:
			await Gulpin.shop(root)
			return 0
		G.SP_LUMINOUS_CAVE:
			if host and host.has_method("luminous_cave"):
				await host.luminous_cave()
			return 0
		G.SP_PPO_HELP:
			# Pelipper's help counter: Wonder Mail in / out (tests: nothing to type, just leave)
			if ListMenu.auto or Dialog.auto:
				return 0
			await PostOffice.help_counter(root)       # Red's guide menus (+ Wonder Mail / Make Wonder Mail)
			return 0
		G.SP_BOARD_JOBS:
			Missions.refresh_board_if_new_day()
			return await Board.open_board(root)
		G.SP_BOARD:
			await Board.open_mailbox(root)
			return 0
		G.SP_THANK_YOU_MAIL, G.SP_FRIEND_RESCUE, G.SP_UNK_1D:
			if ListMenu.auto or Dialog.auto:
				return 0
			if kind == G.SP_FRIEND_RESCUE:
				await FriendRescue.counter(root)
			elif kind == G.SP_THANK_YOU_MAIL:
				await FriendRescue.thank_you_counter(root)
			else:
				await FriendRescue.rescue_reward_talk(root)
			return 0
		G.SP_DOJO_ENTER:
			return await Dojo.enter(root)          # Makuhita's menu + "Courses" list -> script dungeon 55..77
		G.SP_DOJO_LIST:
			var mi := await Dojo.courses(root)
			return Dojo.FIRST_SCRIPT + mi if mi >= 0 else -1
		G.SP_DOJO_SUCCESS, G.SP_DOJO_FAILURE, G.SP_DOJO_ALL_CLEARED:
			await Dojo.result(root, {G.SP_DOJO_SUCCESS: "success", G.SP_DOJO_FAILURE: "failure"}.get(kind, "all"))
			return 0
		G.SP_PERSONALITY_QUIZ:
			if host and host.has_method("story_choose_team"):
				await host.story_choose_team()
			return 0
		G.SP_UNK_29:
			return 0
		G.SP_ITEM_REWARD:
			give_item_red(a1)
			return 1
		G.SP_TOOL_BOX:
			return await RedReward.toolbox_feed(root, G)     # edible items only (feeding Munchlax)
		G.SP_UNK_2C:
			# sub_801B60C(mode a2, item a1, 1): "received" + the full-Toolbox menu
			var ik := item_key(a1)
			if ik == "":
				return -1
			await RedReward.receive(root, a2, ik, 1)
			return 0
		G.SP_CREDITS_NAME:
			if Dialog.auto:
				print("  STORY CREDITS page %d" % a1)        # tests: the ending credits are running
			await RedCredits.show(root, a1, a2)           # ending staff credits page a1, shown a2 frames
			return -1
		G.SP_SCRIPTING_MENU:
			return await _scripting_menu(root)
		G.SP_UNK_22:
			return thank_you_next()                     # Red's per-job thank-you loop at the Post Office
		G.SP_UNK_23:
			return await thank_you_reward(root)
		G.SP_FRIEND_AREA_SELECT:
			# CreateFriendListMenu(2): pick a Friend Area to walk to
			if Game.friend_areas.is_empty() or ListMenu.auto:
				return -2
			var k := await Services.pick_friend_area(root)
			if k == "":
				return -1
			var m := map_of_fa_key(k)
			if m >= 0:
				G.ground_request(m, 0, 30)
				return 1
			return -1
	return -1

## SPECIAL_TEXT_SCRIPTING_MENU (code_803B050.c, debug only: DEBUG_SCRIPT): the SCRIPT_TYPE_10 functions.
static func _scripting_menu(root: Control) -> int:
	var ids: Array = []
	var labels: Array = []
	for f in GData.common.get("functions", []):
		if int(f.get("type", -1)) == 10:
			ids.append(int(f.id))
			labels.append(str(f.name))
	if ids.is_empty() or ListMenu.auto:
		return -1
	var lm := ListMenu.make("Scripts", labels)
	root.add_child(lm)
	lm.position = Vector2(2 * 8, 2 * 8) * UITheme.PX
	var i := await lm.choose()
	return int(ids[i]) if i >= 0 else -1

## Old plain LineEdit prompt (unused since NamingScreen; kept for reference / other callers).
static func _name_input(root: Control, title: String, cur: String, maxlen: int) -> String:
	if Dialog.auto or ListMenu.auto:
		return cur if cur != "" else "Team"
	var panel := PanelContainer.new()
	panel.theme = UITheme.theme()
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var l := Label.new()
	l.text = title
	vb.add_child(l)
	var le := LineEdit.new()
	var re := RegEx.new()
	re.compile("\\[[^\\]]*\\]")
	cur = re.sub(cur, "", true)
	le.text = cur
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(260, 0)
	vb.add_child(le)
	var ok := Button.new()
	ok.text = "OK"
	vb.add_child(ok)
	root.add_child(panel)
	await root.get_tree().process_frame
	panel.position = (root.get_viewport_rect().size - panel.size) / 2
	le.grab_focus()
	le.select_all()
	var done := [false]
	var fin := func(_t = null): done[0] = true
	le.text_submitted.connect(fin)
	ok.pressed.connect(fin)
	while not done[0]:
		await root.get_tree().process_frame
	var r := le.text.strip_edges()
	panel.queue_free()
	return r if r != "" else cur

## IsRescueDungeonAvailable (+ dungeons where a taken Job List job waits).
static func rescue_available(r: int) -> bool:
	var sd := GData.rescue_to_script(r)
	if sd < 0 or int(GData.dungeon_info(sd).map1) == -1:
		return false
	if GVars.quest(GVars.QUEST_UNK5):
		return false
	if GVars.rescue_ordered(r) or GVars.rescue_job(r):
		return true
	var key := DB.dungeon_key(int(GData.dungeon_info(sd).dungeon))
	for j in Game.jobs:
		if str(j.get("dungeon", "")) == key and str(j.get("state", "")) == "taken":
			return true
	return GVars.quest(GVars.QUEST_UNK1) and GVars.rescue_conquered(r)

static var _test_visits := {}      # tests: how often each dungeon was picked this session

static func _has_taken_job(key: String) -> bool:
	for j in Game.jobs:
		if str(j.get("dungeon", "")) == key and str(j.get("state", "")) == "taken" and _job_doable(j):
			return true
	return false

## tests: a delivery whose item the team doesn't carry can't be finished, so it doesn't pull the team back
static func _job_doable(j: Dictionary) -> bool:
	if str(j.get("kind", "")) != "deliver":
		return true
	for b in Game.bag:
		if str(b.id) == str(j.get("item", "")):
			return true
	return false

static func _dungeon_list(root: Control, G = null) -> int:
	daily_update()          # textbox.c: sub_8001D88 runs when the dungeon list opens
	if ListMenu.auto and Dialog.auto and Dungeon.test_invincible:
		Game.save_game(true)    # tests: keep the story's progress for the next --continue segment
	var opts: Array = []
	var ids: Array = []
	var prio: Array = []
	var seen_did: Array = []
	for r in 46:
		var sd := GData.rescue_to_script(r)
		if sd < 0:
			continue
		if not rescue_available(r):
			continue
		var did := int(GData.dungeon_info(sd).dungeon)
		if did in seen_did:
			continue                  # several rescue entries can point at the same dungeon (e.g. two jobs in Tiny Woods)
		seen_did.append(did)
		var keys: Array = DB.dungeons.get("dungeons", {}).keys()
		var label: String = str(DB.dungeons.dungeons[keys[did]].name) if did < keys.size() else "?"
		opts.append(label)
		ids.append(r)
		if ListMenu.auto:
			# tests: newest unconquered story dungeon first, then dungeons with taken jobs
			var key := DB.dungeon_key(did)
			var pri := 0
			if Dungeon.test_want == "chestnut" and key == "uproar_forest":
				pri = 4000
			elif GVars.after(GVars.SCENARIO_MAIN, 17, -1) and r in _side_story_rescues() and (GVars.rescue_job(r) or GVars.rescue_ordered(r)) and not GVars.rescue_conquered(r) \
					and int(_test_visits.get(key, 0)) < 2:
				pri = 3500 + r       # post-game: the open side-story dungeon first (twice at most: some never get "conquered")
			elif (GVars.rescue_ordered(r) or GVars.rescue_job(r)) and not GVars.rescue_conquered(r) and not key in Game.cleared:
				pri = 3000 + r       # a newly opened story dungeon first
			elif _has_taken_job(key):
				pri = 2000 + r       # then taken jobs (the story often counts finished jobs)
			elif (GVars.rescue_ordered(r) or GVars.rescue_job(r)) and not GVars.rescue_conquered(r):
				pri = 1000 + r
			# tests: a dungeon picked twice already this session ranks below the others (rotate instead of looping)
			var vis := int(_test_visits.get(key, 0))
			if vis >= 2:
				pri = mini(pri, 50) - vis
			# tests: a dungeon the team can't enter yet (solo-only Purity Forest, missing HM) goes last
			if pri > 0 and int(WorldMap.requirements(key)[0]) == 1:
				pri = 1
			if pri == 0:
				pri = 100 - vis * 10      # nothing to do anywhere: the least-visited dungeon
			prio.append(pri)
	if opts.is_empty():
		return -1
	if ListMenu.auto:
		var order := range(opts.size())
		order.sort_custom(func(a, b): return prio[a] > prio[b])
		opts = order.map(func(i): return opts[i])
		ids = order.map(func(i): return ids[i])
	var eos := eos_unlocked()
	if not eos.is_empty() and not ListMenu.auto:
		opts.append("Explorers of Sky dungeons (%d)" % eos.size())
		ids.append(-100)
	var i := await DungeonList.pick(root, opts, ids)     # Red's "Dungeons" window with GO / envelope icons
	if i < 0:
		return -1
	if int(ids[i]) == -100:
		var labels: Array = []
		var icons: Array = []
		for k in eos:
			var d: Dictionary = DB.dungeons.dungeons[k]
			labels.append("%s  [Lv %d]" % [str(d.name), int(d.get("eos_level", 1))])
			icons.append("ENVELOPE_OPEN" if DungeonList.jobs_in_key(str(k)) > 0 else "")
		var j := await DungeonList.pick(root, labels, eos.map(func(_k): return -1), "Explorers of Sky", icons, eos)
		if j < 0 or G == null:
			return -1
		eos_pick = str(eos[j])
		# as REQ_WORLD_MAP: DUNGEON_RESULT 5 makes the base station put the team back at the south exit when the
		# trip / Prepare screen is cancelled (without it the station's fallback is the Friend Areas side)
		GVars.set_val(null, GVars.START_MODE, 5)
		GVars.set_val(null, GVars.DUNGEON_RESULT, 5)
		GVars.set_val(null, GVars.DUNGEON_ENTER, -1)
		G._end(16)                     # main.gd: Prepare screen, then the EoS dungeon
		return -1
	GVars.set_val(null, GVars.DUNGEON_SELECT, GData.rescue_to_script(ids[i]))
	if ListMenu.auto:
		var dk := DB.dungeon_key(int(GData.dungeon_info(GData.rescue_to_script(ids[i])).dungeon))
		_test_visits[dk] = int(_test_visits.get(dk, 0)) + 1
	return ids[i]
