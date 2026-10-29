class_name StatusMoves
extends RefCounted
## Red's status moves that have no effect entry in data/moves.json, after their *MoveAction functions in the
## pret/pmd-red decomp (move_orb_actions_*.c, move_orb_effects_*.c, dungeon_move.c). Called by
## Dungeon._apply_status_move for each target; returns true when the move did something.
## The reactions to the statuses set here live in dungeon.gd (Protect, Counter / Mirror Coat, Endure,
## Destiny Bond, Rage, Magic Coat, Mirror Move, Mist, Safeguard, Taunt, Encore, Uproar).

const CURE_ALL := ["sleep", "nightmare", "yawn", "napping", "burn", "poison", "badpoison", "frozen", "para", "confused",
	"cowering", "infatuated", "petrified", "slow", "blinker", "cross_eyed", "curse", "leech_seed", "taunt", "encore",
	"muzzled", "terrified", "cringe", "paused"]
const CURE_REFRESH := ["burn", "poison", "badpoison", "para"]

static func handles(nm: String) -> bool:
	return nm in ["Counter", "Mirror Coat", "Magic Coat", "Mist", "Safeguard", "Endure", "Lock-On", "Mind Reader",
		"Grudge", "Destiny Bond", "Encore", "Taunt", "Torment", "Nightmare", "Disable", "Uproar", "Rage", "Wrap",
		"Vital Throw", "Mirror Move", "Ingrain", "Pain Split", "Haze", "Psych Up", "Spite", "Heal Bell",
		"Aromatherapy", "Refresh", "Roar", "Whirlwind", "Teleport", "Knock Off", "Trick", "Odor Sleuth",
		"Foresight", "Helping Hand", "Perish Song", "Spikes", "Flash", "Grasswhistle", "Spider Web", "Assist",
		"Substitute", "Conversion", "Conversion 2", "Camouflage", "Mimic", "Sketch", "Role Play", "Skill Swap",
		"Metronome", "Sleep Talk", "Nature Power"]

static func _turns(d, key: String, t: Mon, fallback := 10) -> int:
	return TurnRules.red_turns(key, d.fs.rng, t, fallback)

static func _put(d, t: Mon, key: String, text: String, fallback := 10) -> bool:
	t.status[key] = _turns(d, key, t, fallback)
	d._msg(text % d._nm(t))
	return true

static func run(d, m: Mon, t: Mon, mv: Dictionary) -> bool:
	var nm := str(mv.get("name", ""))
	var fs: FloorState = d.fs
	match nm:
		"Counter":
			return _put(d, m, "counter", "%s is ready to counter attacks!")
		"Mirror Coat":
			return _put(d, m, "mirror_coat", "%s is protected by Mirror Coat!")
		"Magic Coat":
			return _put(d, m, "magic_coat", "%s is protected by Magic Coat!")
		"Mist":
			return _put(d, t, "mist", "%s is shrouded in mist!")
		"Safeguard":
			return _put(d, t, "safeguard", "%s is protected by Safeguard!")
		"Endure":
			return _put(d, m, "enduring", "%s braced itself!")
		"Lock-On", "Mind Reader":
			return _put(d, m, "sure_shot", "%s took aim! Its moves won't miss!")
		"Grudge":
			return _put(d, t, "grudge", "%s bears a grudge!", 10)
		"Destiny Bond":
			if t == m:
				return false
			m.status.destiny_bond = _turns(d, "destiny_bond", m, 10)
			m.set_meta("bond_uid", t.uid)
			d._msg("%s is trying to take %s down with it!" % [d._nm(m), d._nm(t)])
			return true
		"Encore":
			if t.last_move == "" or t == m:
				return false
			t.set_meta("encore_move", t.last_move)
			return _put(d, t, "encore", "%s got an encore!")
		"Taunt":
			return _put(d, t, "taunt", "%s fell for the taunt!")
		"Torment":
			var opts: Array = []
			for s in t.moves:
				if s is Dictionary and not bool(s.get("sealed", false)) and int(s.get("pp", 0)) > 0:
					opts.append(s)
			if opts.is_empty():
				return false
			var pick: Dictionary = opts[fs.rng.randi() % opts.size()]
			pick.sealed = true
			d._msg("%s's [color=#7fe0ff]%s[/color] was sealed!" % [d._nm(t), str(pick.name)])
			return true
		"Nightmare":
			t.status.sleep = 0
			return _put(d, t, "nightmare", "%s is caught in a nightmare!")
		"Disable":                                    # Red: DisableMoveAction paralyzes
			return d._apply_eff(m, t, {"status": "para"}, true)
		"Uproar":                                     # Red: SleeplessStatusTarget
			for k in ["sleep", "nightmare", "napping", "yawn"]:
				t.status[k] = 0
			return _put(d, t, "sleepless", "%s can't fall asleep!")
		"Rage":
			return _put(d, m, "enraged", "%s is enraged!")
		"Wrap":
			if t == m:
				return false
			t.status.wrapped = _turns(d, "wrapped", t, 6)
			m.status.wrapping = _turns(d, "wrapping", m, 6)
			t.set_meta("wrapped_by", m.uid)
			d._msg("%s was wrapped by %s!" % [d._nm(t), d._nm(m)])
			return true
		"Vital Throw":
			return _put(d, m, "vital_throw", "%s is ready to throw its foe!")
		"Mirror Move":
			return _put(d, m, "mirror_move", "%s is ready to return moves!")
		"Ingrain":
			return _put(d, m, "ingrain", "%s planted its roots!")
		"Pain Split":
			if t == m:
				return false
			var avg := (m.hp + t.hp) / 2
			m.hp = mini(m.max_hp, avg)
			t.hp = mini(t.max_hp, avg)
			d._msg("%s and %s shared their pain!" % [d._nm(m), d._nm(t)])
			return true
		"Haze":
			for k in t.stages:
				t.stages[k] = 10
			for k in t.stat_mult:
				t.stat_mult[k] = 256
			d._msg("%s's stats returned to normal!" % d._nm(t))
			return true
		"Psych Up":
			if t == m:
				return false
			m.stages = t.stages.duplicate()
			d._msg("%s copied %s's stat changes!" % [d._nm(m), d._nm(t)])
			return true
		"Spite":
			var any := false
			for s in t.moves:
				if s is Dictionary and int(s.get("pp", 0)) > 0:
					s.pp = maxi(0, int(s.pp) - 3)
					any = true
			if any:
				d._msg("%s's moves lost PP!" % d._nm(t))
			return any
		"Heal Bell", "Aromatherapy", "Refresh":
			var list: Array = CURE_REFRESH if nm == "Refresh" else CURE_ALL
			var cured := false
			for k in list:
				if t.has_status(k):
					t.status[k] = 0
					cured = true
			if cured:
				d._msg("%s's status returned to normal!" % d._nm(t))
			return cured
		"Roar", "Whirlwind":
			if t == m:
				return false
			await SpecialMoves.blow_away(d, m, t, m.facing)
			return true
		"Teleport":
			SpecialMoves.warp(d, m)
			d._msg("%s teleported!" % d._nm(m))
			return true
		"Knock Off":
			if t.held == "" or t == m:
				return false
			var it := t.held
			var nn := maxi(1, t.held_n)
			t.held = ""
			t.held_n = 1
			var q: Vector2i = t.pos
			if fs.items.has(q):
				q = fs.free_item_tile_near(q) if fs.has_method("free_item_tile_near") else Vector2i(-1, -1)
			if q.x >= 0:
				fs.items[q] = {"id": it, "n": nn, "price": 0}
				d.obj_layer.queue_redraw()
			d._msg("%s's %s was knocked off!" % [d._nm(t), DB.item_name(it)])
			return true
		"Trick":
			if t == m or (m.held == "" and t.held == ""):
				return false
			var a := [m.held, m.held_n]
			m.held = t.held
			m.held_n = t.held_n
			t.held = str(a[0])
			t.held_n = int(a[1])
			d._msg("%s swapped items with %s!" % [d._nm(m), d._nm(t)])
			return true
		"Odor Sleuth", "Foresight":
			t.exposed = true
			for k in ["eva"]:
				t.stages[k] = mini(int(t.stages.get(k, 10)), 10)
			d._msg("%s was exposed!" % d._nm(t))
			return true
		"Helping Hand":
			if t == m:
				d._msg("But nothing happened.")
				return false
			var r1: bool = d._apply_eff(m, t, {"tgt": "atk", "st": 1}, true)
			var r2: bool = d._apply_eff(m, t, {"tgt": "spa", "st": 1}, true)
			return r1 or r2
		"Perish Song":
			if t.has_status("perish"):
				return false
			return _put(d, t, "perish", "%s heard the Perish Song!", 3)
		"Spikes":
			if fs.room_at(m.pos) == 255 or fs.traps.has(m.pos) or m.pos == fs.stairs or fs.items.has(m.pos):
				d._msg("Spikes can't be laid here.")
				return false
			fs.traps[m.pos] = {"id": "spiked", "seen": true, "team": m.is_team()}
			d._msg("%s laid spikes!" % d._nm(m))
			SpecialMoves._redraw(d)
			return true
		"Flash":                                      # Gen 3: lowers accuracy
			return d._apply_eff(m, t, {"tgt": "acc", "st": -1}, true)
		"Grasswhistle":
			return d._apply_eff(m, t, {"status": "sleep"}, true)
		"Spider Web":
			return d._apply_eff(m, t, {"status": "slow"}, true)
		"Assist":                                     # Red: AssistMoveAction only shows a message and fails
			d._msg("But nothing happened.")
			return true
		"Substitute":
			if m.has_status("decoy") or m.hp <= m.max_hp / 4:
				return false
			m.hp -= maxi(1, m.max_hp / 4)
			return _put(d, m, "decoy", "%s made a substitute!", 20)
		"Conversion", "Camouflage":
			var ty := ""
			if nm == "Camouflage":
				ty = "Normal"
			else:
				for s in m.moves:
					var M: Dictionary = DB.moves.get(str(s.get("name", "")), {}) if s is Dictionary else {}
					var tt := str(M.get("t", ""))
					if tt != "" and not tt in m.types and str(s.get("name", "")) != "Conversion":
						ty = tt
						break
			if ty == "":
				return false
			m.types = [ty]
			d._msg("%s became the %s type!" % [d._nm(m), ty])
			return true
		"Conversion 2":
			var lt := str(DB.moves.get(t.last_move, {}).get("t", "")) if t != m else ""
			var resist := {"Normal": "Rock", "Fire": "Water", "Water": "Grass", "Electric": "Ground", "Grass": "Fire",
				"Ice": "Steel", "Fighting": "Psychic", "Poison": "Steel", "Ground": "Flying", "Flying": "Electric",
				"Psychic": "Dark", "Bug": "Fire", "Rock": "Steel", "Ghost": "Normal", "Dragon": "Steel", "Dark": "Fighting",
				"Steel": "Fire", "Fairy": "Steel"}
			var ty2 := str(resist.get(lt, "Steel"))
			m.types = [ty2]
			d._msg("%s became the %s type!" % [d._nm(m), ty2])
			return true
		"Mimic", "Sketch":
			if t == m or t.last_move == "" or not DB.moves.has(t.last_move) or m.move_by_name(t.last_move).size() > 0:
				return false
			for s in m.moves:
				if s is Dictionary and str(s.get("name", "")) == nm:
					var M2: Dictionary = DB.moves[t.last_move]
					s.name = t.last_move
					s.pp = int(M2.get("pp", 10))
					s.max_pp = int(M2.get("pp", 10))
					d._msg("%s learned [color=#7fe0ff]%s[/color]!" % [d._nm(m), t.last_move])
					return true
			return false
		"Role Play":
			if t == m:
				return false
			m.ability = t.ability
			m.ability2 = t.ability2
			d._msg("%s copied %s's ability!" % [d._nm(m), d._nm(t)])
			return true
		"Skill Swap":
			if t == m:
				return false
			var ab := [m.ability, m.ability2]
			m.ability = t.ability
			m.ability2 = t.ability2
			t.ability = str(ab[0])
			t.ability2 = str(ab[1])
			d._msg("%s swapped abilities with %s!" % [d._nm(m), d._nm(t)])
			return true
		"Metronome", "Nature Power":
			var pool: Array = []
			if nm == "Nature Power":
				pool = ["Swift"]
			else:
				for k in DB.moves:
					var M3: Dictionary = DB.moves[k]
					if str(M3.get("c", "X")) != "X" and int(M3.get("p", 0)) > 0 and int(M3.get("id", 0)) > 0 and int(M3.get("id", 0)) < 355:
						pool.append(k)
			if pool.is_empty():
				return false
			var pick2: String = pool[fs.rng.randi() % pool.size()]
			if not DB.moves.has(pick2):
				return false
			d._msg("%s used [color=#7fe0ff]%s[/color]!" % [d._nm(m), pick2])
			await d.do_attack(m, pick2, m.facing, false)
			return true
		"Sleep Talk":
			if not m.has_status("sleep") and not m.has_status("napping") and not m.has_status("nightmare"):
				return false
			var own: Array = []
			for s in m.moves:
				if s is Dictionary and str(s.get("name", "")) != "Sleep Talk" and DB.moves.has(str(s.get("name", ""))):
					own.append(str(s.name))
			if own.is_empty():
				return false
			await d.do_attack(m, own[fs.rng.randi() % own.size()], m.facing, true)
			return true
	return false
