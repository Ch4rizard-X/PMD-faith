class_name HeldItems
extends RefCounted
## Red's held-item effects that live outside the damage formula (Combat already has Power Band, Def. Scarf,
## Special Band, Zinc Band, Scope Lens, Patsy Band, Detect Band, Munch Belt, Weather Band; TurnRules has
## the Belly and regen ones). Sources: dungeon_turn_effects.c (Warp Scarf), dungeon_damage.c (Joy Ribbon),
## trap.c (Trap Scarf), dungeon_monster_house.c (Sneak Scarf, Racket Band), dungeon_projectile_throw.c and
## dungeon_action_handler.c (throwing: Pierce Band, No-Aim Scope, Whiff/Lockon Specs, Dodge Scarf, Bounce Band),
## dungeon_move.c (Pass Scarf), dungeon_tilemap.c / dungeon_misc.c (X-Ray Specs), dungeon_logic.c (Goggle Specs),
## status_checks (Persim Band, Pecha Scarf, Insomniscope, Twist Band), Thief / Mug Orb (Alert Specs).

const WARP_SCARF_CHANCES := [0, 6, 12, 30, 50, 70, 90, 110, 130, 150, 170, 190, 210, 230, 250, 270, 290, 310, 999, 0]
const PROJECTILE_HIT_CHANCE := 90     # gProjectileHitChance
const PASS_SCARF_BELLY := 2           # gPassScarfBellyDownValue

## The held item stops this status. Returns the message to show, or "".
static func blocks_status(t: Mon, key: String) -> String:
	var ab := AbilityFx.blocks_status(t, key)
	if ab != "":
		return ab
	ab = EosItems.blocks_status(t, key)
	if ab != "":
		return ab
	match t.held:
		"persimband":
			if key == "confused":
				return "%s is protected by its Persim Band!"
		"pechascarf":
			if key in ["poison", "badpoison"]:
				return "%s is protected by its Pecha Scarf!"
		"insomniscope":
			if key in ["sleep", "yawn", "nightmare", "napping"]:
				return "%s is protected by its Insomniscope!"
	return ""

## Twist Band: Attack and Sp. Atk can't be lowered.
static func blocks_stat_drop(t: Mon, k: String) -> bool:
	return t.held == "twistband" and k in ["atk", "spa"]

## End of every turn (sub_80444F4 caller): Warp Scarf warps its holder now and then.
static func end_of_turn(d) -> void:
	var fs: FloorState = d.fs
	for m in fs.team():
		var je := int(m.get_meta("joy_exp", 0))
		if je > 0 and m.hp > 0:
			m.set_meta("joy_exp", 0)
			await d.gain_exp(m, je)
	# napping wild Pokémon (sleep 0x7F) wake when a team member is next to them, or when one holding a
	# Racket Band is in their room; a Sneak Scarf holder never wakes them (dungeon_monster_house.c)
	for f in fs.mons:
		if f.hp <= 0 or f.is_team() or int(f.status.get("sleep", 0)) < 0x7F:
			continue
		var wake := false
		for t in fs.team():
			var w := wakes(t, f, fs)
			if w == 2 or (w == 1 and FloorState.cheb(t.pos, f.pos) <= 1):
				wake = true
				break
		if wake:
			f.status.sleep = 0
			if fs.can_see(fs.leader, f.pos):
				d._msg("%s woke up!" % d._nm(f))
	for m in fs.mons.duplicate():
		if m.hp <= 0 or m.held != "warpscarf":
			continue
		var n := mini(int(m.get_meta("warp_scarf_turns", 0)) + 1, WARP_SCARF_CHANCES.size() - 1)
		m.set_meta("warp_scarf_turns", n)
		if fs.rng.randi_range(0, 99) < int(WARP_SCARF_CHANCES[n]):
			m.set_meta("warp_scarf_turns", 0)
			SpecialMoves.warp(d, m)
			if fs.can_see(fs.leader, m.pos) or m.is_team():
				d._msg("%s was warped by its Warp Scarf!" % d._nm(m))

## Joy Ribbon: the holder earns Exp. equal to the damage it took (not from a one-hit KO); paid out at the
## end of the turn so level-up messages don't interrupt the attack.
static func on_damaged(d, t: Mon, dmg: int) -> void:
	if t.held == "joyribbon" and t.hp > 0 and dmg > 0 and dmg < 9999 and t.is_team():
		t.set_meta("joy_exp", int(t.get_meta("joy_exp", 0)) + dmg)

## Trap Scarf: traps don't go off for its holder.
static func blocks_trap(t: Mon) -> bool:
	return t.held == "trapscarf"

## X-Ray Specs on the leader: every item and Pokémon on the floor shows on the map.
static func xray(fs: FloorState) -> bool:
	return fs.leader != null and fs.leader.held == "xrayspecs"

## Goggle Specs: hidden traps around the holder show up (and invisible Pokémon can be seen).
static func goggles_reveal(d, m: Mon) -> void:
	if m.held != "gogglespecs":
		return
	var fs: FloorState = d.fs
	var r := fs.room_at(m.pos)
	for p in fs.traps:
		if not fs.traps[p].get("seen", false) and ((r != 255 and fs.room_at(p) == r) or FloorState.cheb(p, m.pos) <= 2):
			fs.traps[p].seen = true
			if d.obj_layer:
				d.obj_layer.queue_redraw()

## Throwing (HandleStraightProjectileThrow setup): range and piercing for this thrower.
## Returns {range, pierce, dir}.
static func throw_setup(d, m: Mon, dir: int) -> Dictionary:
	var rng := 10
	var pierce := false
	if int(m.status.get("long_toss", 0)) > 0 or EosItems.has(m, "long_toss"):
		rng = 99
	if int(m.status.get("pierce", 0)) > 0 or m.held == "pierceband":
		rng = 99
		pierce = true
	if m.held == "noaimscope":
		dir = d.fs.rng.randi() % 8
	return {"range": rng, "pierce": pierce, "dir": dir}

## sub_8083D... hit roll for a thrown item reaching Pokémon t (90%; Whiff Specs never, Lockon Specs always,
## Dodge Scarf on the target never). Bounce Band: the item bounces off (returns "bounce").
static func throw_hits(d, thrower: Mon, t: Mon) -> String:
	if t.held == "bounceband" or EosItems.has(t, "bounce_throw"):
		return "bounce"
	var ok: bool = d.fs.rng.randi_range(0, 99) < PROJECTILE_HIT_CHANCE
	if thrower.held == "whiffspecs":
		ok = false
	elif thrower.held == "lockonspecs":
		ok = true
	if t.held == "dodgescarf" or EosItems.has(t, "dodge_throw"):
		ok = false
	return "hit" if ok else "miss"

## Pass Scarf: a single-target attack on the holder is passed to a Pokémon next to it (costs 2 Belly
## when the holder is the leader). Returns the new target or t.
static func pass_scarf(d, att: Mon, t: Mon, mv: Dictionary) -> Mon:
	if t.held != "passscarf" or att == t:
		return t
	if not str(mv.get("r", "front")) in ["front", "front_corners", "two_tiles", "line"]:
		return t
	var fs: FloorState = d.fs
	if fs.get_meta("fixed_floor", false):
		return t
	if t.is_leader and d.belly < PASS_SCARF_BELLY:
		return t
	for k in 8:
		var o := fs.mon_at(t.pos + DB.DIRS[(t.facing + k) % 8])
		if o and o != att and o != t and o.hp > 0:
			if t.is_leader:
				d.belly = maxf(0.0, d.belly - PASS_SCARF_BELLY)
				d.belly_state.belly = d.belly
			d._msg("%s passed the attack to %s!" % [d._nm(t), d._nm(o)])
			return o
	return t

## Sneak Scarf / Racket Band (dungeon_monster_house.c): does this team member wake a napping foe f?
static func wakes(team_mon: Mon, f: Mon, fs: FloorState) -> int:
	if team_mon.held == "sneakscarf":
		return 0                         # never
	if team_mon.held == "racketband" and fs.room_at(team_mon.pos) != 255 and fs.room_at(team_mon.pos) == fs.room_at(f.pos):
		return 2                         # always, anywhere in the room
	return 1                             # the normal rule (next to it)

static func has_bad_status(m: Mon) -> bool:
	for k in ["poison", "badpoison", "burn", "para", "sleep", "frozen", "confused"]:
		if int(m.status.get(k, 0)) > 0:
			return true
	return false
