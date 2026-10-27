#!/usr/bin/env python3
"""Merge Pokemon Mystery Dungeon: Explorers of Sky's extra IQ skills (the ones Red does not have) into
game/data/iq.json as an add-on on top of Red's 23 skills. Run AFTER gen_iq.py (it rewrites iq.json from
scratch); running this script twice is safe (old "sky" entries are replaced).

Sources (pret/pmd-sky, US):
  src/iq_skills.c          IQ_SKILLS[]               IQ needed per skill (ONE value per skill: Sky's IQ
                                                     groups only decide WHICH species can learn a skill,
                                                     never the IQ needed, so no per-group choice is needed)
  src/monster_parameters.c IQ_SKILL_RESTRICTIONS[]   exclusive-group id per skill (EnableIqSkill turns off
                                                     every other skill with the same id). Every Sky-only
                                                     skill has its own id (24..67) -> none of them are
                                                     mutually exclusive, and none clash with Red's 1..17.
  files/language-specific/US/MESSAGE/text_e.str      skill names (string 9957 + id - 1), descriptions
                                                     (10026 + id - 1) and the dungeon messages used by the
                                                     effects (sky_messages below)
Skipped Sky skills: Escapist (rescue-target escape, always on: no such mechanic in Red), and the five
unused 9999-IQ entries (Lock-Picker, Cautious Creeper, Parry Expert, No-Defeatist, True Powerist).
Absolute Mover is Red's Super Mobile and is already in Red's list.
"""
import json, os, re, sys
sys.path[:0] = [os.path.dirname(os.path.dirname(os.path.abspath(__file__))), os.path.dirname(os.path.abspath(__file__))]
import common  # noqa: E402

SKY = common.PMDSKY
GAME = common.GAME
DST = os.path.join(GAME, "data/iq.json")


def read(p):
    with open(os.path.join(SKY, p), encoding="utf-8") as f:
        return f.read()


def c_list(src, name):
    """value, // IQ_X  pairs of a 1-D initialiser in enum order."""
    body = re.search(re.escape(name) + r"\s*\[[^\]]*\]\s*=\s*\{(.*?)\n\};", src, re.S).group(1)
    return [(m.group(2), int(m.group(1))) for m in re.finditer(r"(-?\d+),\s*//\s*(IQ_\w+)", body)]


def strings():
    d = open(common.need(os.path.join(common.EOS, "fs", "MESSAGE", "text_e.str"), "extracted Explorers of Sky text_e.str"), "rb").read()
    n = int.from_bytes(d[0:4], "little") // 4
    out = []
    for i in range(n):
        o = int.from_bytes(d[4 * i:4 * i + 4], "little")
        e = d.find(b"\0", o) if o < len(d) else -1
        out.append(d[o:e].decode("latin-1") if e >= 0 else "")
    return out


def clean(s):
    """Sky text markup -> Red's {color X}..{reset} style used by the game's red_text()."""
    s = s.split("\n\n")[0]                       # drops the "Select detail:" footer of long entries
    s = re.sub(r"\[LS:\d+\](.*?)\[LE\]", r"{color CYAN}\1{reset}", s)
    s = re.sub(r"\[CS:\w\](.*?)\[CR\]", r"\1", s)
    s = s.replace("[M:S0]", "Poké")
    s = re.sub(r"\[[^\]]*\]", "", s)
    return s.strip()


def snake(s):
    s = s.lower().replace("é", "e").replace("'", "")
    return re.sub(r"[^a-z0-9]+", "_", s).strip("_")


NAME0, DESC0 = 9957, 10026          # string ids of IQ_TYPE_ADVANTAGE_MASTER's name / description (US)
SKIP = {"IQ_NONE", "IQ_ESCAPIST", "IQ_NONE_2"}
# Short notes on what the add-on does and where (shown nowhere in-game; for the maintainers / tests).
# "decomp" = value read from pret/pmd-sky (+ pmdsky-debug symbol names); "chosen" = not in the decomp yet,
# picked from the in-game description.
FX = {
    "stair_sensor": "new floor: stairs revealed on the map (IQSky.on_floor_start)",
    "coin_watcher": "Poké picked up x1.2 (GetMoneyQuantity, decomp) (IQSky.money_pickup)",
    "exp_elite": "+10% Exp. (EXP_ELITE_EXP_BOOST, decomp) (IQSky.exp_gain)",
    "sharpshooter": "+15 crit odds like Sky's Scope Lens (SCOPE_LENS_CRIT_RATE_BOOST, decomp) (Combat)",
    "fast_friend": "leader: recruit rate +50/1000 (FRIEND_BOW_FAST_FRIEND_BOOST, decomp) (IQSky.recruit_bonus)",
    "pp_saver": "30% chance a move costs no PP (chosen) (IQSky.pp_cost)",
    "bodyguard": "takes a hit aimed at an adjacent teammate with HP <= 1/4 (IQSky.before_hit)",
    "aggressor": "own Atk/Sp.Atk stage +1, own Def/Sp.Def stage -1 in damage calc (decomp) (Combat)",
    "defender": "own Def/Sp.Def stage +1, own Atk/Sp.Atk stage -1 in damage calc (decomp) (Combat)",
    "intimidator": "32% an adjacent foe attacking it cringes and doesn't attack (INTIMIDATOR_ACTIVATION_CHANCE, decomp) (IQSky.before_hit)",
    "survivalist": "food fills Belly x1.5 (chosen); Grimy Food 50% harmless (decomp) (IQSky.food_bonus / grimy_resists)",
    "trap_buster": "30% a trap it steps on is removed instead of going off (TRAP_BUSTER_ACTIVATION_CHANCE, decomp) (IQSky.trap_breaks)",
    "counter_hitter": "24% an adjacent physical attacker takes 1/4 of the damage back (decomp) (IQSky.after_hit)",
    "extra_striker": "regular attack: 1/3 chance to strike twice (chosen) (IQSky.regular_attack_hits)",
    "hit_and_runner": "33% chance to ignore the target's counterattacks (decomp) (IQSky.after_hit)",
    "quick_striker": "regular attack always strikes twice (IQSky.regular_attack_hits)",
    "no_charger": "two-turn moves fire at once but use 2 PP (IQSky.skips_charge / pp_cost)",
    "wary_fighter": "after missing, steps one tile back from the target (IQSky.after_miss)",
    "gap_prober": "thrown items / line moves pass through teammates; needs Course Checker off (IQSky.passes_through / throw_path)",
    "power_pitcher": "thrown item damage x1.5 (POWER_PITCHER_DAMAGE_MULTIPLIER, decomp) (IQSky.thrown_damage)",
    "concentrator": "own accuracy stage +1, own evasion stage -1 (Combat)",
    "counter_basher": "10% an adjacent physical attacker takes all the damage back; own Def stage -1 vs physical (decomp) (Combat / IQSky.after_hit)",
    "cheerleader": "teammates next to it get Atk/Sp.Atk stage +1 (NearbyAllyIqSkillIsEnabled, decomp) (Combat)",
    "nature_gifter": "leader: healing Berries/Seeds it eats also work on the whole team (IQSky.nature_gifter_targets)",
    "wise_healer": "HP healed by moves/items +15% (WISE_HEALER_PERCENTAGE, decomp) (IQSky.heal_amount)",
    "quick_healer": "natural HP regeneration twice as fast (chosen) (TurnRules.regen)",
    "acute_sniffer": "new floor: 'Total items on this floor: N.' (IQSky.on_floor_start)",
    "deep_breather": "new floor: +2 PP to every move (chosen) (IQSky.on_floor_start)",
    "brick_tough": "Max HP +10 (decomp _020A1870); can't be turned off (IQ.apply)",
    "multitalent": "every move +5 max PP (MULTITALENT_PP_BOOST_AMOUNT, decomp); can't be turned off (IQ.apply)",
    "time_tripper": "speed stage +1 (CalcSpeedStage, decomp) (TurnRules.speed_stage)",
    "erratic_player": "type multipliers become 0.25/0.5/1/1.7 when it attacks or is hit (decomp) (Combat)",
    "practice_swinger": "after a miss, its next attack gets Atk/Sp.Atk stage +1 (decomp) (Combat)",
    "haggler": "leader: shop prices -20% when buying, +20% when selling (chosen) (IQSky.shop_price_mult)",
    "clutch_performer": "evasion stage +2 while HP <= 1/4 (Combat)",
    "critical_dodger": "can't take critical hits (decomp) (Combat)",
    "map_surveyor": "new floor: whole floor layout shown on the map (IQSky.on_floor_start)",
    "pierce_hurler": "thrown items fly through walls and Pokémon, hitting everyone in the line (IQSky.throw_path)",
    "collector": "foes it defeats drop an item 10% of the time (Red has no treasure boxes; chosen) (IQSky.collector_drop)",
}
ALWAYS_ON = {"brick_tough", "multitalent"}   # dungeon_pokemon_attributes_1.c forces these on

iq_req = c_list(read("src/iq_skills.c"), "IQ_SKILLS")
restr = dict(c_list(read("src/monster_parameters.c"), "IQ_SKILL_RESTRICTIONS"))
S = strings()

data = json.load(open(DST, encoding="utf-8"))
red = [s for s in data["skills"] if not s.get("sky")]
red_names = {s["name"].lower() for s in red} | {"absolute mover"}   # = Red's Super Mobile

sky = []
for idx, (enum, need) in enumerate(iq_req):
    if enum in SKIP or need < 0 or need >= 9999:
        continue
    name = S[NAME0 + idx - 1]
    if name.lower() in red_names:
        continue
    sid = snake(name)
    assert sid in FX, "no effect note for " + sid
    sky.append({"id": sid, "sky_id": idx, "name": name, "desc": clean(S[DESC0 + idx - 1]), "iq": need,
                "group": restr[enum], "sky": True, "always_on": sid in ALWAYS_ON, "fx": FX[sid]})
sky.sort(key=lambda s: (s["iq"], s["sky_id"]))
assert len({s["group"] for s in sky}) == len(sky) and min(s["group"] for s in sky) > max(s["group"] for s in red)

msg = lambda i: re.sub(r"\[CS:\w\]|\[CR\]", "", re.sub(r"\[string:(\d)\]", r"{\1}",
                       re.sub(r"\[digits_c:0\]", "{n}", S[i]))).replace("\n", " ")
data["skills"] = red + sky
data["sky_source"] = "pret/pmd-sky (see gen_iq_sky.py)"
data["sky_messages"] = {
    "stair_sensor": msg(3104), "acute_sniffer": msg(3105), "deep_breather": msg(3103),
    "pp_saver": msg(3572), "pp_saver2": msg(3574), "intimidator": msg(3752), "counter": msg(2941),
    "bodyguard": "{0} stepped in to protect {1}!", "trap_buster": "{0} broke the trap!",
    "map_surveyor": "{0} sensed the layout of the floor!", "wary_fighter": "{0} stepped back!",
    "nature_gifter": "The effect spread to the whole team!", "collector": "{1} dropped an item!",
}
with open(DST, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=1)
print("wrote", DST, len(red), "Red skills +", len(sky), "Sky skills")
for s in sky:
    print("  %-17s IQ %3d  group %2d%s" % (s["name"], s["iq"], s["group"], "  (always on)" if s["always_on"] else ""))
