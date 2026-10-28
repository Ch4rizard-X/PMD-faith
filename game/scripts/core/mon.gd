class_name Mon
extends RefCounted
## One Pokémon on a dungeon floor (team member or wild).
## Stat stages follow Red: 10 is neutral, range 0..20 (index into the stage tables).

var uid: int = 0
var sp: String = "0001"          # species key, as in data/species.json
var name: String = ""
var side: String = "enemy"       # "team" | "enemy"
var is_leader: bool = false
var level: int = 1
var exp: int = 0
var hp: int = 1
var max_hp: int = 1
var atk: int = 1
var spa: int = 1
var def: int = 1
var spd: int = 1
var types: Array = []            # e.g. ["Grass", "Poison"]
var ability: String = ""          # e.g. "overgrow"
var moves: Array = []             # [{name: String, pp: int, max_pp: int, linked: bool, on: bool}]
var held: String = ""             # item id from data/items.json
var held_n: int = 1               # how many of a stackable held item (Iron Thorns, Gravelerocks ...)
var iq: int = 0
var iq_skills: Array = []
var stages := {"atk": 10, "spa": 10, "def": 10, "spd": 10, "acc": 10, "eva": 10}
## Status timers (turns left; 0 = none). Names mirror Red's status groups.
var status := {
	"sleep": 0, "nightmare": 0, "yawn": 0, "napping": 0,
	"burn": 0, "poison": 0, "badpoison": 0, "badpoison_n": 0, "frozen": 0, "para": 0,
	"confused": 0, "cowering": 0, "cringe": 0, "infatuated": 0, "petrified": 0, "paused": 0,
	"slow": 0, "fast": 0,
	"reflect": 0, "light_screen": 0, "protect": 0, "safeguard": 0, "mist": 0, "focus_energy": 0, "sure_shot": 0,
	"leech_seed": 0, "wrapped": 0, "wrapping": 0, "bide": 0, "charging": 0, "charge_move": "",
	"blinker": 0, "cross_eyed": 0, "eyedrops": 0, "radar": 0, "stockpile": 0, "invisible": 0,
	"perish": 0, "decoy": 0, "curse": 0, "destiny_bond": 0, "magic_coat": 0, "snatch": 0,
	"grudge": 0, "enduring": 0, "mirror_coat": 0, "counter": 0, "taunt": 0, "torment": 0, "encore": 0,
	"embargo": 0, "muzzled": 0, "terrified": 0, "flash_fire": 0
}
var pos := Vector2i.ZERO
var facing: int = 0               # 0..7, see Dirs.DIRS (0 = down, then counter-clockwise like Red)
var regen_acc: int = 0            # HP regeneration accumulator
var turn_energy: int = 0          # speed / extra-turn bookkeeping
var last_move: String = ""
var exp_given: bool = false
var recruit_ok: bool = true
var mega: String = ""             # mega form species key while Mega Evolved
var visual: Node = null           # MonSprite node drawing this Pokémon

func is_team() -> bool:
	return side == "team"

func alive() -> bool:
	return hp > 0

func stat(k: String) -> int:
	match k:
		"atk": return atk
		"spa": return spa
		"def": return def
		"spd": return spd
	return 0

func has_status(k: String) -> bool:
	return int(status.get(k, 0)) > 0

func move_by_name(n: String) -> Dictionary:
	for m in moves:
		if m.name == n:
			return m
	return {}

# ---- Fields appended for Combat (Red's EntityInfo has these; see scripts/core/combat.gd) ----
## Red monsters carry two ability slots (EntityInfo.abilities[2]); `ability` is slot 0, this is slot 1.
var ability2: String = ""
## Red's EntityInfo.exposed (Foresight/Odor Sleuth/Eyedrops-type reveal): Ghosts lose their
## Normal/Fighting "little effect" rule and evasion stages are ignored.
var exposed: bool = false
## Red's offensiveMultipliers / defensiveMultipliers as s24_8 (256 = x1.0). Charm/Memento/Screech etc.
## multiply these (clamped 0.01..99.99) instead of changing stages. Keys: atk, spa (offense), def, spd (defense).
var stat_mult := {"atk": 256, "spa": 256, "def": 256, "spd": 256}
