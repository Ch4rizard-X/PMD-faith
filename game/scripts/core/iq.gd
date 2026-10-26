class_name IQ
extends RefCounted
## PMD Red's IQ system, tactics, gummis and move-link rules (data: res://data/iq.json, made by gen_iq.py
## from the pret/pmd-red decomp).
##
## Red (unlike Explorers) has no per-species IQ groups: every Pokémon unlocks the same skill at the same
## IQ (gReqIQSkillPts). Skills that share an sIQSkillGroups slot are mutually exclusive: switching one on
## switches the others in its slot off (SetIQSkill). A skill works when it is unlocked AND switched on
## (LoadIQSkills). New Pokémon start with Item Catcher, Course Checker and Item Master switched on
## (SetDefaultIQSkills); skills learned later start switched off until the player turns them on.
##
## Every function takes either a dungeon Mon or a team-entry Dictionary ({sp, name, level, iq, ...}).
## Persistent state lives in the team entry:
##   entry.iq_on  : Array of skill ids switched on (missing = Red's defaults)
##   entry.tactic : tactic id (missing = "lets_go_together")
## A Mon uses its meta "entry" (set by Game.mon_from_entry) and mirrors the result into
## m.iq_skills (skill names + ids, what AI.iq / Combat.has_iq read) and meta "tactic" (AI.tactic_of).
##
## Explorers of Sky add-on (gen_iq_sky.py, skills with "sky": true, listed after Red's 23): Sky's other
## IQ skills unlock at Sky's IQ requirement on top of Red's shared thresholds (still no per-species groups).
## They behave like Red skills in the menus. Sky gives each of them its own restriction group, so none are
## mutually exclusive. Brick-Tough and Multitalent are "always_on" (Sky forces them on: they can't be
## switched off once learned). Their effects live in combat.gd / turn_rules.gd and IQSky (iq_sky.gd).

const DATA_PATH := "res://data/iq.json"
## Usable tactics in Red's menu order (GetAvailTacticsforLvl walks the enum; All for one / Group
## safety / unused need Lv 999 and never show up).
const TACTICS := ["lets_go_together", "go_the_other_way", "go_after_foes", "avoid_the_first_hit",
	"avoid_trouble", "be_patient", "keep_your_distance", "wait_there", "get_away"]
const DEFAULT_TACTIC := "lets_go_together"
const STAT_CAP := 255                 # Red's offense/defense bytes stop at 255 (GetGummiItemStatBoost)
const WILD_ITEM_MASTER_LEVEL := 16    # gIqItemMasterMinWildLevel

static var _d: Dictionary = {}
static var _by_id: Dictionary = {}
static var rng := RandomNumberGenerator.new()

static func data() -> Dictionary:
	if _d.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_d = v
		for s in _d.get("skills", []):
			_by_id[s.id] = s
		rng.randomize()
	return _d

static func skill(id: String) -> Dictionary:
	data()
	return _by_id.get(_norm_id(id), {})

static func skill_name(id: String) -> String:
	return str(skill(id).get("name", id))

static func _norm_id(id: String) -> String:
	var s := id.to_lower().replace("é", "e").replace("'", "")
	var out := ""
	for ch in s:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")

# ------------------------------------------------------------------ adapter (Mon or team entry)
static func entry_of(m) -> Dictionary:
	if m is Dictionary:
		return m
	if m is Mon:
		return m.get_meta("entry", {})
	return {}

static func iq_of(m) -> int:
	if m is Mon:
		return int(m.iq)
	return int(entry_of(m).get("iq", 0))

## Red clamps IQ to 1..999 and new Pokémon start at 1 (pokemon.c), so IQ 0 counts as 1.
static func eff_iq(m) -> int:
	return clampi(iq_of(m), 1, int(data().get("iq_max", 999)))

static func level_of(m) -> int:
	if m is Mon:
		return int(m.level)
	return int(entry_of(m).get("level", 1))

static func name_of(m) -> String:
	if m is Mon:
		return str(m.name)
	var e := entry_of(m)
	return str(e.get("name", DB.species.get(str(e.get("sp", "")), {}).get("name", "???")))

static func sp_of(m) -> String:
	if m is Mon:
		return str(m.sp)
	return str(entry_of(m).get("sp", "0001"))

static func moves_of(m) -> Array:
	if m is Mon:
		return m.moves
	return entry_of(m).get("moves", [])

static func is_team(m) -> bool:
	return not (m is Mon) or m.is_team()

## Types used by the gummi table: Red's own typing for Red species (monster_data.json), else the
## project's species types. A dungeon Mon uses its current types (EntityInfo.types).
static func types_of(m) -> Array:
	if m is Mon and not m.types.is_empty():
		return m.types.duplicate()
	var sp := sp_of(m)
	var rt: Dictionary = data().get("red_types", {})
	if rt.has(sp.substr(0, 4)) and sp.length() == 4:
		return rt[sp].duplicate()
	return DB.species.get(sp, {}).get("types", ["Normal"]).duplicate()

static func _set_iq(m, v: int) -> void:
	if m is Mon:
		m.iq = v
	var e := entry_of(m)
	if not e.is_empty():
		e.iq = v

static func _on_list(m) -> Array:
	var e := entry_of(m)
	if not e.is_empty():
		if not e.has("iq_on"):
			e.iq_on = data().get("default_on", []).duplicate()
		return e.iq_on
	if m is Mon:
		if not m.has_meta("iq_on"):
			m.set_meta("iq_on", data().get("default_on", []).duplicate())
		return m.get_meta("iq_on")
	return []

# ------------------------------------------------------------------ IQ skills
## Red's 23 skills in Red's order, then the Sky add-on skills by IQ needed:
## {id, name, desc, iq (needed), group, unlocked, on, sky, always_on}.
## Red's menus only list unlocked ones -- filter on `unlocked`.
static func skills_for(m) -> Array:
	var out: Array = []
	var q := eff_iq(m)
	var on := _on_list(m)
	for s in data().get("skills", []):
		var unl := q >= int(s.iq)
		var always := bool(s.get("always_on", false))
		out.append({"id": s.id, "name": s.name, "desc": s.desc, "iq": int(s.iq), "group": int(s.group),
			"unlocked": unl, "on": unl and (always or s.id in on), "sky": bool(s.get("sky", false)), "always_on": always})
	return out

static func unlocked_ids(iq_points: int) -> Array:
	var out: Array = []
	for s in data().get("skills", []):
		if iq_points >= int(s.iq):
			out.append(s.id)
	return out

## Unlocked and switched on (IqSkillIsEnabled). Wild Pokémon use LoadIQSkills' fixed set.
static func has(m, id: String) -> bool:
	id = _norm_id(id)
	if m is Mon and not m.is_team():
		match id:
			"status_checker", "pp_checker", "item_catcher":
				return true
			"self_curer":
				return bool(m.get_meta("boss", false))
			"item_master":
				return int(m.level) >= WILD_ITEM_MASTER_LEVEL
		return false
	var s := skill(id)
	if s.is_empty():
		return false
	return eff_iq(m) >= int(s.iq) and (bool(s.get("always_on", false)) or id in _on_list(m))

## Switch a skill on/off (ToggleIQSkill / SetIQSkill). Switching on turns off the other skills of the
## same sIQSkillGroups slot. Returns false for unknown or still-locked skills.
static func set_skill(m, id: String, on: bool) -> bool:
	id = _norm_id(id)
	var s := skill(id)
	if s.is_empty():
		return false
	if on and eff_iq(m) < int(s.iq):
		return false
	if not on and bool(s.get("always_on", false)) and eff_iq(m) >= int(s.iq):
		return false          # Sky: Brick-Tough / Multitalent can't be turned off
	var lst := _on_list(m)
	if on:
		for o in data().skills:
			if int(o.group) == int(s.group):
				lst.erase(o.id)
		lst.append(id)
	else:
		lst.erase(id)
	refresh(m)
	return true

static func toggle_skill(m, id: String) -> bool:
	return set_skill(m, id, not has(m, id))

## Active skills as names + ids (both spellings so AI.iq / Combat.has_iq match either way).
static func active_skill_list(m) -> Array:
	var out: Array = []
	for s in skills_for(m):
		if s.on:
			out.append(s.name)
			out.append(s.id)
	return out

## Push the entry's IQ skills + tactic onto a dungeon Mon (call after Game.mon_from_entry).
static func apply(m: Mon) -> void:
	if not m.is_team():
		return
	m.iq_skills = active_skill_list(m)
	m.set_meta("tactic", tactic_of(m))
	IQSky.apply_passives(m)   # Sky: Brick-Tough max HP, Multitalent max PP (no-op without them)

static func refresh(m) -> void:
	if m is Mon:
		apply(m)

## Messages for skills unlocked since iq_before (DisplayMsgIfNewIqSkillLearned). With iq_before < 0 the
## entry's remembered value ("iq_seen") is used. Also refreshes a Mon's active skills.
static func on_iq_changed(m, iq_before := -1) -> Array:
	var e := entry_of(m)
	if iq_before < 0:
		iq_before = int(e.get("iq_seen", eff_iq(m)))
	var now := eff_iq(m)
	if not e.is_empty():
		e.iq_seen = now
	var msgs: Array = []
	var before := unlocked_ids(maxi(1, iq_before))
	var tpl := str(data().messages.dungeon_learned)
	for id in unlocked_ids(now):
		if not id in before:
			msgs.append(_fmt(tpl, {"{POKEMON_0}": name_of(m), "{MOVE_ITEM_0}": skill_name(id)}))
	refresh(m)
	return msgs

static func newly_unlocked(iq_before: int, iq_after: int) -> Array:
	var b := unlocked_ids(maxi(1, iq_before))
	var out: Array = []
	for id in unlocked_ids(maxi(1, iq_after)):
		if not id in b:
			out.append(id)
	return out

# ------------------------------------------------------------------ tactics
static func tactic_info(id: String) -> Dictionary:
	for t in data().get("tactics", []):
		if t.id == id:
			return t
	return {}

static func tactic_name(id: String) -> String:
	return str(tactic_info(id).get("name", id))

## Tactics unlocked at the Pokémon's level (gReqTacticLvls), Red's order:
## [{id, name, desc, level, unlocked, on}]. include_locked also lists the ones still to come.
static func tactics_for(m, include_locked := false) -> Array:
	var out: Array = []
	var L := level_of(m)
	var cur := tactic_of(m)
	for id in TACTICS:
		var t := tactic_info(id)
		var unl := L >= int(t.level)
		if unl or include_locked:
			out.append({"id": id, "name": t.name, "desc": t.desc, "level": int(t.level), "unlocked": unl, "on": id == cur})
	return out

static func tactic_of(m) -> String:
	var e := entry_of(m)
	if e.has("tactic"):
		return str(e.tactic)
	if m is Mon and m.has_meta("tactic"):
		return str(m.get_meta("tactic"))
	return DEFAULT_TACTIC

static func set_tactic(m, id: String) -> bool:
	if not id in TACTICS or level_of(m) < int(tactic_info(id).get("level", 999)):
		return false
	var e := entry_of(m)
	if not e.is_empty():
		e.tactic = id
	if m is Mon:
		m.set_meta("tactic", id)
	return true

# ------------------------------------------------------------------ gummis
static func is_gummi(item_id: String) -> bool:
	return str(DB.items.get(item_id, {}).get("kind", "")) == "iqgummi" or data().get("gummis", {}).has(item_id)

## Red: gTypeGummiIQBoost[type1][gummi] + gTypeGummiIQBoost[type2][gummi] (TYPE_NONE row is all 0).
## Types missing from Red's table (Fairy) count as TYPE_NONE; a Pokémon with no Red type at all
## uses the Normal row. Rainbow/Wonder Gummi are not in Red: Rainbow = its best type gummi,
## Wonder = 14 (a dual-type double favourite).
static func gummi_gain(m, item_id: String) -> int:
	var d := data()
	var gt: String = d.gummis.get(item_id, "")
	var ts := _red_types(types_of(m))
	if gt == "":
		var v := str(DB.items.get(item_id, {}).get("v", ""))
		if v == "wonder":
			return 14
		if v == "Fairy":                     # Remixed Fairy Gummi: Fairy types love it
			return 14 if "Fairy" in types_of(m) else 5
		if v == "rainbow":
			var best := 0
			for g in d.gummis:
				best = maxi(best, gummi_gain(m, g))
			return best
		return 0
	var n := 0
	for t in ts:
		n += int(d.gummi_iq[t][gt])
	return n

static func gummi_belly(m, item_id: String) -> int:
	var d := data()
	var gt: String = d.gummis.get(item_id, "")
	if gt == "":
		return 0
	var n := 0
	for t in _red_types(types_of(m)):
		n += int(d.gummi_belly[t][gt])
	return n

static func _red_types(ts: Array) -> Array:
	var known: Array = data().get("types", [])
	var out: Array = []
	for t in ts:
		if str(t) in known and out.size() < 2:
			out.append(str(t))
	if out.is_empty():
		out.append("Normal")
	return out

## Red's taste index from the IQ gain: >= 9 love, 5..8 like, 3..4 ok, <= 2 satisfied.
static func taste(gain: int) -> int:
	if gain >= 9:
		return 0
	if gain >= 5:
		return 1
	if gain >= 3:
		return 2
	return 3

## Feed a gummi. Town (team entry / in_dungeon false) follows "Give Gummi" (code_80227B8.c,
## GetGummiItemStatBoost): IQ up, "IQ helped it learn" lines, then +1 to one random stat (all four
## with a 1/16 chance when it was a big favourite). Dungeon (HandleGummiItemAction): IQ up with the
## two dungeon lines, belly filled by gummi_belly (the caller applies `belly`), no stat boost; wild
## Pokémon only get the belly. The caller removes the item.
## Returns {ok, iq_gain, iq_before, iq_after, taste, msgs, learned: [ids], belly, stats: {atk..}}.
static func eat_gummi(m, item_id: String, in_dungeon = null) -> Dictionary:
	var dungeon: bool = (m is Mon) if in_dungeon == null else bool(in_dungeon)
	var d := data()
	var nm := name_of(m)
	var res := {"ok": false, "iq_gain": 0, "iq_before": iq_of(m), "iq_after": iq_of(m), "taste": -1,
		"msgs": [], "learned": [], "belly": 0, "stats": {}}
	if not is_gummi(item_id):
		if not dungeon:
			res.msgs.append(str(d.messages.town_not_hungry))
		return res
	res.ok = true
	res.belly = gummi_belly(m, item_id)
	if not is_team(m):
		return res
	var before := eff_iq(m)
	var gain := gummi_gain(m, item_id)
	var after := clampi(before + gain, 1, int(d.iq_max))
	_set_iq(m, after)
	res.iq_gain = after - before
	res.iq_before = before
	res.iq_after = after
	res.taste = taste(gain)
	res.learned = newly_unlocked(before, after)
	var e := entry_of(m)
	if not e.is_empty():
		e.iq_seen = after
	if dungeon:
		if before == after:
			res.msgs.append(str(d.messages.dungeon_no_change))
		else:
			res.msgs.append(str(d.messages.dungeon_taste[res.taste]))
			res.msgs.append(str(d.messages.dungeon_iq[taste(after - before)]))
			for id in res.learned:
				res.msgs.append(_fmt(str(d.messages.dungeon_learned), {"{POKEMON_0}": nm, "{MOVE_ITEM_0}": skill_name(id)}))
	else:
		res.msgs.append(_fmt(str(d.messages.town_taste[res.taste]), {"{POKEMON_1}": nm}))
		for id in res.learned:
			res.msgs.append(_fmt(str(d.messages.town_learned), {"{POKEMON_1}": nm, "{MOVE_ITEM_1}": skill_name(id)}))
		var keys := ["atk", "spa", "def", "spd"]
		var pick: Array = keys.duplicate() if (res.taste == 0 and rng.randi_range(0, 15) == 10) else [keys[rng.randi_range(0, 3)]]
		var bonus: Dictionary = e.get("bonus", {}) if not e.is_empty() else {}
		var base := DB.stats_at(sp_of(m), level_of(m))
		var raised: Array = []
		for k in pick:
			if int(base.get(k, 0)) + int(bonus.get(k, 0)) < STAT_CAP:
				bonus[k] = int(bonus.get(k, 0)) + 1
				raised.append(k)
				res.stats[k] = 1
		if not e.is_empty():
			e.bonus = bonus
		if m is Mon:
			m.set_meta("bonus", bonus)
			DB.recalc(m)
		if raised.size() == 1:
			res.msgs.append(_fmt(str(d.messages.town_stat[raised[0]]), {"{POKEMON_1}": nm}))
		elif raised.size() > 1:
			res.msgs.append(_fmt(str(d.messages.town_stat.all), {"{POKEMON_1}": nm}))
	refresh(m)
	return res

static func _fmt(s: String, subs: Dictionary) -> String:
	for k in subs:
		s = s.replace(k, str(subs[k]))
	return s

# ------------------------------------------------------------------ move links (moves.c)
## Linked moves: moves[i].linked == true means "used right after moves[i-1]" (MOVE_FLAG_SUBSEQUENT_IN_
## LINK_CHAIN). A chain is a head plus the linked moves after it; with 4 move slots a chain is at most 4.
static func is_charge_move(name: String) -> bool:
	return name in data().get("charge_moves", [])

static func chains(moves: Array) -> Array:
	var out: Array = []
	for i in moves.size():
		if i == 0 or not bool(moves[i].get("linked", false)):
			out.append([i])
		else:
			out[-1].append(i)
	return out

## Indices of the chain that contains move i.
static func chain_of(moves: Array, i: int) -> Array:
	for c in chains(moves):
		if i in c:
			return c
	return []

## The move i and the linked moves after it (what Forget / Delink act on).
static func chain_from(moves: Array, i: int) -> Array:
	var out := [i]
	var j := i + 1
	while j < moves.size() and bool(moves[j].get("linked", false)):
		out.append(j)
		j += 1
	return out

## TryLinkMovesAfter: links the next unlinked move after i onto i's chain. Fails if i or any move
## up to that one is a charging move (DoesMoveCharge), or there is no unlinked move after i.
static func can_link(moves: Array, i: int) -> bool:
	return link(moves.duplicate(true), i)

static func link(moves: Array, i: int) -> bool:
	if i < 0 or i >= moves.size() or is_charge_move(str(moves[i].name)):
		return false
	for j in range(i + 1, moves.size()):
		if is_charge_move(str(moves[j].name)):
			return false
		if not bool(moves[j].get("linked", false)):
			moves[j].linked = true
			_fix_chains(moves)
			return true
	return false

## UnlinkMovesAfter: breaks the links of every move linked after i.
static func can_delink(moves: Array, i: int) -> bool:
	return delink(moves.duplicate(true), i)

static func delink(moves: Array, i: int) -> bool:
	var did := false
	for j in range(i + 1, moves.size()):
		if bool(moves[j].get("linked", false)):
			moves[j].linked = false
			did = true
		else:
			break
	_fix_chains(moves)
	return did

## IsAnyMoveLinked (misnamed): Forget is allowed while more than one chain exists.
static func can_forget(moves: Array, _i := 0) -> bool:
	return chains(moves).size() > 1

## RemoveLinkSequenceFromMoves8: forget move i and every move linked after it.
static func forget(moves: Array, i: int) -> Array:
	var gone: Array = []
	var idx := chain_from(moves, i)
	idx.reverse()
	for j in idx:
		gone.push_front(moves[j].name)
		moves.remove_at(j)
	_fix_chains(moves)
	return gone

## unk_FixLinkedMovesSetEnabled8: a chain shares its head's switch / set state; slot 0 can't be linked.
static func _fix_chains(moves: Array) -> void:
	if moves.size() > 0:
		moves[0].linked = false
	for c in chains(moves):
		var head: Dictionary = moves[c[0]]
		for j in c:
			moves[j].on = bool(head.get("on", true))
			if head.has("set"):
				moves[j].set = bool(head.set)

## R + Up in Red's move list: swap the chain holding move i with the chain above it.
static func shift_up(moves: Array, i: int) -> bool:
	var cs := chains(moves)
	var k := -1
	for n in cs.size():
		if i in cs[n]:
			k = n
	if k <= 0:
		return false
	var a: Array = cs[k - 1]
	var b: Array = cs[k]
	var block_b: Array = []
	for j in b:
		block_b.append(moves[j])
	var block_a: Array = []
	for j in a:
		block_a.append(moves[j])
	var start: int = a[0]
	var merged: Array = block_b + block_a
	for n in merged.size():
		moves[start + n] = merged[n]
	_fix_chains(moves)
	return true

## Leader: Set marks the one move used with L+A (ToggleSetMove); others: Switch toggles AI use.
static func toggle_set(moves: Array, i: int) -> void:
	var was := bool(moves[i].get("set", false))
	for mv in moves:
		mv.set = false
	for j in chain_of(moves, i):
		moves[j].set = not was

static func toggle_on(moves: Array, i: int) -> void:
	var c := chain_of(moves, i)
	var v := not bool(moves[c[0]].get("on", true))
	for j in c:
		moves[j].on = v

# ------------------------------------------------------------------ remembering moves (sub_808E218)
## Level-up moves of the Pokémon's evolution line it could have learned, minus known ones. For the current
## species up to its level; for earlier stages up to the level it evolved at (entry.evo_levels, newest
## first, like Red's Pokemon.unkC; without it, the evolution level from evo.json, else its level).
## Frenzy Plant / Hydro Cannon / Blast Burn / Volt Tackle also need IQ 333. Deoxys and Munchlax: none.
static func can_remember(m) -> bool:
	return not sp_of(m).substr(0, 4) in data().get("no_remember", [])

static func evolution_line(m) -> Array:
	var sp := sp_of(m)
	var L := level_of(m)
	var out: Array = [[sp, L]]
	var evo_lv: Array = entry_of(m).get("evo_levels", [])
	var cur := sp
	for n in 2:
		var prev := ""
		var at := 0
		for k in DB.evo:
			for ev in DB.evo[k]:
				if str(ev[0]) == cur:
					prev = k
					at = int(ev[1])
		if prev == "":
			break
		var lv := int(evo_lv[n]) if n < evo_lv.size() else (at if at > 0 else L)
		lv = mini(lv, out[-1][1])
		out.append([prev, lv])
		cur = prev
	return out

static func rememberable(m) -> Array:
	if not can_remember(m):
		return []
	var known: Array = []
	for mv in moves_of(m):
		known.append(str(mv.name))
	var ult: Dictionary = data().get("ultimate_moves_iq", {})
	var q := eff_iq(m)
	var out: Array = []
	for stage in evolution_line(m):
		for e in DB.species.get(stage[0], {}).get("learn", []):
			if int(e[0]) > int(stage[1]):
				break
			var n := str(e[1])
			if not DB.moves.has(n) or n in known or n in out:
				continue
			if ult.has(n) and q < int(ult[n]):
				continue
			out.append(n)
	return out

## Red adds a remembered move with 0 PP (InitZeroedPPPokemonMove); PP is refilled when a dungeon starts.
## With 4 moves, forget_index's chain is forgotten first. Returns the forgotten move names.
static func remember(m, move_name: String, forget_index := -1) -> Array:
	var moves := moves_of(m)
	var gone: Array = []
	if moves.size() >= 4:
		if forget_index < 0:
			return []
		gone = forget(moves, forget_index)
	var pp := int(DB.moves.get(move_name, {}).get("pp", 10))
	moves.append({"name": move_name, "pp": 0, "max_pp": pp, "on": true, "linked": false})
	return gone

## Level-up / TM learning gate for the four ultimate moves (pokemon.c: IQ >= 333).
static func can_learn_move(m, move_name: String) -> bool:
	var ult: Dictionary = data().get("ultimate_moves_iq", {})
	return not ult.has(move_name) or eff_iq(m) >= int(ult[move_name])

# ------------------------------------------------------------------ town UI (Check IQ, Give Gummi, fallbacks)
static func _place(root: Control, c: Control, at := Vector2(8, 8)) -> void:
	root.add_child(c)
	c.position = at

const PAGE := 8                       # rows per page in long lists (480x270 screen)

## ListMenu over a long list, PAGE rows at a time; an extra "More..." row flips pages (Red pages its long
## lists). Returns the index into opts, or -1. on_select gets the index into opts too.
static func paged_choose(root: Control, title: String, opts: Array, on_select := Callable(), start := 0, at := Vector2(8, 8)) -> int:
	var pages := maxi(1, ceili(opts.size() / float(PAGE)))
	var page := clampi(start / PAGE, 0, pages - 1)
	while true:
		var lo := page * PAGE
		var hi := mini(opts.size(), lo + PAGE)
		var rows: Array = opts.slice(lo, hi)
		if pages > 1:
			rows.append("More... (%d/%d)" % [page + 1, pages])
		var lm := ListMenu.make(title, rows)
		if on_select.is_valid():
			var off := lo
			var n := hi - lo
			lm.on_select = func(i):
				if i < n:
					on_select.call(off + i)
		_place(root, lm, at)
		lm._set_sel(clampi(start - lo, 0, rows.size() - 1))
		var i := await lm.choose()
		if i < 0:
			return -1
		if i >= hi - lo:
			page = (page + 1) % pages
			start = page * PAGE
			if ListMenu.auto:
				return -1
			continue
		return lo + i
	return -1

static func _side_box(root: Control) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.theme = UITheme.theme()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_stylebox_override("normal", UITheme.box())
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(r)
	return r

static func _beside(root: Control, lm: Control, box: Control, minw := 180.0) -> void:
	await root.get_tree().process_frame
	if not is_instance_valid(lm) or not is_instance_valid(box):
		return
	var vw := root.get_viewport_rect().size.x
	box.position = Vector2(lm.position.x + lm.size.x + 4, lm.position.y)
	box.size.x = maxf(minw, vw - box.position.x - 8)

## Red's "Check IQ" (iq_skill_menu.c): unlocked skills, ★ = switched on; Switch / Info.
static func check_iq_ui(root: Control, m) -> void:
	var sel := 0
	while true:
		var list: Array = []
		for s in skills_for(m):
			if s.unlocked:
				list.append(s)
		var opts: Array = []
		for s in list:
			opts.append(str(s.name) + (" ★" if s.on else ""))
		var info := _side_box(root)
		info.position = Vector2(300, 8)
		info.size.x = root.get_viewport_rect().size.x - 308
		var show := func(i):
			if is_instance_valid(info) and i < list.size():
				info.text = UITheme.red_text(str(list[i].desc)).replace("\n", " ")
		show.call(sel)
		var i := await paged_choose(root, "%s  IQ %d" % [name_of(m), eff_iq(m)], opts, show, sel)
		if is_instance_valid(info):
			info.queue_free()
		if i < 0:
			return
		sel = i
		var s: Dictionary = list[i]
		var c := await _small_menu(root, ["Switch", "Info"], Vector2(200, 8 + (i % PAGE) * UITheme.LINE))
		if c == 0:
			toggle_skill(m, s.id)
			Audio.sfx("confirm")
		elif c == 1:
			await Dialog.say(root, "[color=#ffdc4a]%s[/color]\n%s" % [s.name, UITheme.red_text(str(s.desc)).replace("\n", " ")])
		if ListMenu.auto:
			return

static func _small_menu(root: Control, opts: Array, at: Vector2, title := "") -> int:
	var lm := ListMenu.make(title, opts)
	_place(root, lm, at)
	await root.get_tree().process_frame
	var vs := root.get_viewport_rect().size
	lm.position.x = minf(lm.position.x, vs.x - lm.size.x - 4)
	lm.position.y = minf(lm.position.y, vs.y - lm.size.y - 4)
	return await lm.choose()

## Tactics picker (Red's dungeon Tactics menu; usable on team entries in town too).
static func tactics_ui(root: Control, m) -> void:
	var list := tactics_for(m)
	var opts: Array = []
	for t in list:
		opts.append(str(t.name) + (" ★" if t.on else ""))
	var info := _side_box(root)
	info.position = Vector2(270, 8)
	info.size.x = root.get_viewport_rect().size.x - 278
	var show := func(i):
		if is_instance_valid(info) and i < list.size():
			info.text = UITheme.red_text(str(list[i].desc)).replace("\n", " ")
	show.call(0)
	var i := await paged_choose(root, "Tactics", opts, show)
	if is_instance_valid(info):
		info.queue_free()
	if i >= 0:
		set_tactic(m, list[i].id)

## Town "Give Gummi": pick a gummi from the Toolbox and feed it (the gummi is used up).
static func give_gummi_ui(root: Control, m) -> void:
	var idx: Array = []
	var opts: Array = []
	for k in Game.bag.size():
		if is_gummi(str(Game.bag[k].id)):
			idx.append(k)
			opts.append(DB.item_name(str(Game.bag[k].id)))
	if idx.is_empty():
		await Dialog.say(root, str(data().messages.town_no_gummis))
		return
	var i := await paged_choose(root, "Give which Gummi?", opts)
	if i < 0:
		return
	await feed_from_bag(root, m, idx[i])

static func feed_from_bag(root: Control, m, bag_index: int) -> void:
	var id := str(Game.bag[bag_index].id)
	var r := eat_gummi(m, id, false)
	if r.ok:
		var b: Dictionary = Game.bag[bag_index]
		if int(b.get("n", 1)) > 1 and DB.items.get(id, {}).get("stack", false):
			b.n = int(b.n) - 1
		else:
			Game.bag.remove_at(bag_index)
	for line in r.msgs:
		await Dialog.say(root, str(line))

## Simple summary text (fallback when TeamScreens is missing).
static func summary_text(m) -> String:
	var e := entry_of(m)
	var sp := sp_of(m)
	var S: Dictionary = DB.species.get(sp, {})
	var st := DB.stats_at(sp, level_of(m))
	var bonus: Dictionary = e.get("bonus", {})
	var held := str(e.get("held", "")) if not (m is Mon) else str(m.held)
	return "%s (%s)  Lv %d  IQ %d\nAtk %d  Def %d  Sp.Atk %d  Sp.Def %d  HP %d\nType: %s   Item: %s   Tactic: %s" % [
		name_of(m), S.get("name", sp), level_of(m), eff_iq(m),
		int(st.atk) + int(bonus.get("atk", 0)), int(st.def) + int(bonus.get("def", 0)),
		int(st.spa) + int(bonus.get("spa", 0)), int(st.spd) + int(bonus.get("spd", 0)), int(st.hp) + int(bonus.get("hp", 0)),
		"/".join(types_of(m)), DB.item_name(held) if held != "" else "None", tactic_name(tactic_of(m))]
