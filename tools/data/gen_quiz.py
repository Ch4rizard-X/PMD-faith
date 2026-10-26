#!/usr/bin/env python3
"""Export PMD Red's personality test (pret/pmd-red decomp) to game/data/quiz.json.

Sources (in /tmp/claude-0/pmdred):
  src/data/locale/personality_test1_usa.h  - all English strings
  src/data/personality_test1.h             - questions, answers, per-answer nature points, starter table
  src/data/personality_test2.h             - partner list
  src/personality_test1.c / personality_test2.c - logic (8 questions, category exclusion, tie-break, partner rule)
  data/scripts/personality_test.inc        - the intro lines spoken before the test
"""
import json, os, re, sys

DECOMP = "/tmp/claude-0/pmdred"
GAME = "/tmp/claude-0/pmd1/game"
OUT = os.path.join(GAME, "data", "quiz.json")

NATURES = ["Hardy", "Docile", "Brave", "Jolly", "Impish", "Naive", "Timid", "Hasty", "Sassy", "Calm", "Relaxed", "Lonely", "Quirky"]
CATEGORIES = NATURES + ["Misc"]


def read(p):
    with open(os.path.join(DECOMP, p), encoding="utf-8") as f:
        return f.read()


def c_strings(s):
    """Concatenate all C string literals in s and unescape them."""
    out = []
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"', s):
        out.append(m.group(1).replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\'))
    return "".join(out)


def clean(t):
    t = t.replace("“", '"').replace("”", '"').replace("\\0", "")
    return t


def pages_of(text):
    """Red text -> pages. {EXTRA_MSG} starts a new box; {WAIT_PRESS} waits for a press and keeps typing in the
    same box. Each page: {segs: [str...], center: bool}; showing seg i means concatenating segs[0..i]."""
    text = clean(text)
    pages = []
    for raw in text.split("{EXTRA_MSG}"):
        center = "{CENTER_ALIGN}" in raw
        raw = raw.replace("{CENTER_ALIGN}", "")
        segs = raw.split("{WAIT_PRESS}")
        segs = [re.sub(r"\{[^}]*\}", "", s) for s in segs]
        if segs and segs[0].startswith("\n"):
            segs[0] = segs[0][1:]
        segs = [s for s in segs if s != ""]
        if segs:
            pages.append({"segs": segs, "center": center})
    return pages


def main():
    # ---- strings
    loc = read("src/data/locale/personality_test1_usa.h")
    S = {}
    for m in re.finditer(r"#define (\w+) \(_\((.*?)\)\)\s*$", loc, re.S | re.M):
        S[m.group(1)] = c_strings(m.group(2))

    # ---- species names -> dex keys
    with open(os.path.join(GAME, "data", "species.json"), encoding="utf-8") as f:
        species = json.load(f)
    by_name = {}
    for k, v in species.items():
        by_name.setdefault(re.sub(r"[^A-Z0-9]", "", v["name"].upper()), k)

    def mon(sym):
        n = sym.replace("MONSTER_", "")
        if n not in by_name:
            sys.exit("unknown species " + sym)
        return by_name[n]

    # ---- questions
    data = read("src/data/personality_test1.h")
    points = {}
    for m in re.finditer(r"PersonalityEffects (\w+)Points\[\] = \{(.*?)\n\};", data, re.S):
        rows = []
        for row in re.findall(r"\{([^{}]*)\}", m.group(2)):
            d = {}
            for nat, val in re.findall(r"\[(\w+)\]\s*=\s*(-?\d+)", row):
                d[nat.capitalize()] = int(val)
            rows.append(d)
        points[m.group(1)] = rows
    answers = {}
    for m in re.finditer(r"MenuItem (\w+)Answers\[\] =\s*\{(.*?)\n\};", data, re.S):
        answers[m.group(1)] = [(a, int(v)) for a, v in re.findall(r"\{\s*(\w+),\s*(-?\d+)\s*\}", m.group(2)) if a != "NULL"]
    quest = {}
    for m in re.finditer(r"PersonalityQuestion (\w+) = \{ (\w+), (\w+)Answers, (\w+)Points \};", data):
        quest[m.group(1)] = (m.group(2), m.group(3), m.group(4))
    table = re.search(r"gPersonalityQuestionPointerTable\[[^\]]*\] = \{(.*?)\};", data, re.S).group(1)
    order = re.findall(r"&(\w+)", table)
    cats = re.findall(r"\b(\w+)\b", re.search(r"gNatureQuestionTable\[[^\]]*\] = \{(.*?)\};", data, re.S).group(1))
    assert len(order) == len(cats) == 56, (len(order), len(cats))
    index_of = {name: i for i, name in enumerate(order)}

    questions = []
    for i, qname in enumerate(order):
        sym, aname, pname = quest[qname]
        q = {"id": sym, "category": cats[i].capitalize(), "pages": pages_of(S[sym]), "answers": []}
        for j, (asym, val) in enumerate(answers[aname]):
            a = {"text": clean(S[asym]).strip(), "points": points[pname][j]}
            if val == 99:   # BRAVE_2B_TRIGGER: "Fight." leads to the follow-up question, no points
                a["points"] = {}
                a["followup"] = index_of["BraveQuest2B"]
            q["answers"].append(a)
        questions.append(q)

    # ---- starters per nature (male, female)
    st = re.search(r"gStarters\[[^\]]*\]\[2\] = \{(.*?)\};", data, re.S).group(1)
    natures = []
    for nat, male, female in re.findall(r"\[(\w+)\s*\] = \{ (\w+),\s*(\w+) \}", st):
        n = nat.capitalize()
        natures.append({"name": n, "pages": pages_of(S["DESC_" + nat]), "male": mon(male), "female": mon(female)})
    assert [n["name"] for n in natures] == NATURES

    # ---- partners
    p2 = read("src/data/personality_test2.h")
    partners = [mon(x) for x in re.findall(r"(MONSTER_\w+)", re.search(r"gPartners\[[^\]]*\] =\s*\{(.*?)\};", p2, re.S).group(1))]

    # ---- intro (ground script floatingText lines, in the order the script shows them)
    inc = read("data/scripts/personality_test.inc")
    labels = {}
    for m in re.finditer(r"(\w+):\n((?:\s*\.string \".*\"\n)+)", inc):
        labels[m.group(1)] = c_strings(m.group(2))
    intro_order = re.findall(r"floatingText (\w+)", inc)
    intro = [pages_of(labels[l])[0] for l in intro_order]

    out = {
        "source": "pret/pmd-red decomp (USA): personality_test1.c/.h, personality_test2.c/.h, personality_test.inc",
        "natures": natures,
        "questions": questions,
        "num_selectable": 55,           # NUM_QUIZ_QUESTIONS; index 55 (BRAVE_Q2B) is only reached via followup
        "questions_asked": 8,           # MAX_ASKED_QUESTIONS
        "selection": "Pick a random question index in [0, num_selectable) that is not used; then mark every question "
                     "of the same category used (so at most one question per category). Repeat for questions_asked "
                     "questions, then ask the gender question.",
        "tie_break": "Start at a random nature r, then walk r+1..r+12 (wrapping Quirky->Hardy) and switch only to a "
                     "strictly higher total: among tied natures the first one met from r wins.",
        "gender": {"pages": pages_of(S["GENDER_Q"]), "answers": [S["GENDER_A0"], S["GENDER_A1"]], "values": ["male", "female"]},
        "intro": intro,
        "starter_reveal": clean(S["STARTER_REVEAL"]).replace("{CENTER_ALIGN}", "").strip().replace("{POKEMON_0}", "{pokemon}"),
        "partner_prompt": pages_of(S["PARTNER_PROMPT"]),
        "partner_nick_prompt": pages_of(S["PARTNER_NICK_PROMPT"]),
        "end_text": pages_of(S["END_TEXT"]),
        "partners": partners,
        "partner_rule": "exclude_shared_type",   # GetValidPartners: drop partners sharing either type with the hero
        "partner_header": "Pokémon",
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("wrote", OUT, len(questions), "questions,", len(natures), "natures, partners", partners)


if __name__ == "__main__":
    main()
