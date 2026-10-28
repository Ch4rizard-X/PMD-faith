class_name MoveGrowth
extends RefCounted
## Explorers Remixed's Move Growth (SkyTemple's patch, the Gates to Infinity system), as a remake option
## (Game Options -> Dungeon -> Move growth). data/move_growth.json comes from Remixed's BALANCE/mgrowth.bin
## (tools/eos/gen_move_growth.py): 25 levels of {Exp. to the next level, power, PP, accuracy}, added up
## level by level.
##   - A move's Exp. belongs to the move, not to one Pokémon: every team member that knows it shares its level
##     (Game.flags.move_exp = {move name: Exp.}).
##   - Each use of a growing move that isn't cut short gives it 3 Exp. Status moves don't grow.
##   - Ginseng gives 300 Exp. (1000 when lucky) to the leader's topmost growing move instead of Red's boost.
##   - Only the team benefits; enemies never do.

const EXP_PER_USE := 3
const GINSENG_EXP := 300
const GINSENG_LUCKY_EXP := 1000

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/move_growth.json", FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_data = d
		if _data.is_empty():
			_data = {"table": [], "moves": []}
	return _data

static func enabled() -> bool:
	return bool(Game.settings.get("qol_movegrowth", true)) and not (data().table as Array).is_empty()

## Damaging moves grow (Remixed's growing list covers the EoS ones; the remake's other damaging moves follow
## the same rule), plus Remixed's few growing moves without a fixed power (Beat Up, Bide, Revenge ...).
static func grows(move_name: String) -> bool:
	if move_name == "":
		return false
	if move_name in data().moves:
		return true
	var M: Dictionary = DB.moves.get(move_name, {})
	return str(M.get("c", "X")) != "X" and int(M.get("p", 0)) > 0

static func exp_of(move_name: String) -> int:
	return int((Game.flags.get("move_exp", {}) as Dictionary).get(move_name, 0))

## {level (1..25), exp (in this level), need (to the next, 0 at the top), power, pp, acc}
static func info(move_name: String) -> Dictionary:
	var out := {"level": 1, "exp": 0, "need": 0, "power": 0, "pp": 0, "acc": 0}
	var tab: Array = data().table
	if tab.is_empty() or not grows(move_name):
		return out
	var left := exp_of(move_name)
	var lv := 0
	while true:
		var row: Array = tab[lv]
		out.power += int(row[1])
		out.pp += int(row[2])
		out.acc += int(row[3])
		var need := int(row[0])
		if need <= 0 or lv >= tab.size() - 1:
			out.need = 0
			out.exp = 0
			break
		if left < need:
			out.need = need
			out.exp = left
			break
		left -= need
		lv += 1
	out.level = lv + 1
	return out

## The move as the team member uses it: power and accuracy with the move's growth.
static func apply(m: Mon, move_name: String, mv: Dictionary) -> Dictionary:
	if not enabled() or m == null or not m.is_team() or not grows(move_name):
		return mv
	var g := info(move_name)
	if int(g.power) == 0 and int(g.acc) == 0:
		return mv
	var out := mv.duplicate()
	out.p = int(mv.get("p", 0)) + int(g.power)
	for k in ["a1", "a2"]:
		if out.has(k) and int(out[k]) <= 100:                    # >100 = never misses
			out[k] = mini(100, int(out[k]) + int(g.acc))
	return out

## PP: a move slot carries its growth bonus in "mg_pp"; this brings max PP (and PP) in line with the move's
## current level, or takes the bonus back off when Move growth is turned off.
static func sync_slot(slot: Dictionary) -> void:
	var mname := str(slot.get("name", ""))
	var want := int(info(mname).pp) if enabled() and grows(mname) else 0
	var have := int(slot.get("mg_pp", 0))
	if want == have:
		return
	var d := want - have
	slot["mg_pp"] = want
	slot.max_pp = maxi(1, int(slot.get("max_pp", 1)) + d)
	slot.pp = clampi(int(slot.get("pp", 0)) + maxi(d, 0), 0, int(slot.max_pp))

static func sync_moves(moves: Array) -> void:
	for s in moves:
		if s is Dictionary:
			sync_slot(s)

## Every team / Friend Area Pokémon (and the team on the floor) after a move levelled up or the option changed.
static func sync_all(dg = null) -> void:
	for e in Game.team + Game.friends:
		sync_moves(e.get("moves", []))
	if dg != null:
		for m in dg.team_mons:
			if m != null:
				sync_moves(m.moves)

## Adds Exp. to a move; returns the new level when it went up, else 0.
static func add_exp(move_name: String, n: int) -> int:
	if not enabled() or not grows(move_name) or n <= 0:
		return 0
	var before := int(info(move_name).level)
	var me: Dictionary = Game.flags.get("move_exp", {})
	me[move_name] = exp_of(move_name) + n
	Game.flags["move_exp"] = me
	var after := int(info(move_name).level)
	return after if after > before else 0
