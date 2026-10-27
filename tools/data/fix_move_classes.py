"""Moves the engine runs as status moves (category "X": no damage, handled by the status-move code), although
Red's data gives them a physical/special category. Their original category is kept as "c_orig".
Runs at the end of the eos step, after every tool that writes moves.json."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

STATUS_MOVES = [
    'Nightmare', 'Vital Throw', 'Encore', 'Rage', 'Pain Split', 'Torment',
    'Rock Smash', 'Spite', 'Pursuit', 'Mirror Move', 'Grudge', 'Counter',
    'Odor Sleuth', 'Sharpen', 'Disable', 'Bide', 'Grasswhistle', 'Spider Web',
    'Mind Reader', 'Follow Me', 'Uproar', 'Psych Up', 'Nature Power', 'Mist',
    'Skill Swap', 'Taunt', 'Conversion', 'Conversion 2', 'Helping Hand', 'Trick',
    'Mud Sport', 'Role Play', 'Sleep Talk', 'Assist', 'Ingrain', 'Knock Off',
    'Baton Pass', 'Doom Desire', 'Barrier', 'Imprison', 'Beat Up', 'Flash',
    'Camouflage', 'Perish Song', 'Wrap', 'Spikes', 'Magic Coat', 'Substitute',
    'Water Sport', 'Destiny Bond', 'Foresight', 'Mirror Coat', 'Future Sight', 'Mimic',
    'Meditate', 'Snatch', 'Recycle', 'Refresh', 'Revenge', 'Lock-On',
    '-', 'Excavate', 'See-Trap', 'Rebound', 'Switcher', 'Warp',
    'Transfer', 'Slow Down', 'Speed Boost', 'Searchlight', 'Petrify', 'Stay Away',
    'Pounce', 'Trawl', 'Cleanse', 'Observer', 'Decoy Maker', 'Siesta',
    'Totter', 'No-Move', 'Escape', 'Scan', 'Power-Ears', 'Drought',
    'Trap Buster', 'Wild Call', 'Invisify', 'HP Gauge', 'Reviver', 'Shocker',
    'Famish', 'One-Room', 'Fill-In', 'Trapper', 'Itemize', 'Mobile',
    'See Stairs', 'Long Toss', 'Pierce', 'Metal Burst', 'Payback',
]

# self stat boosts the converted data lacks (Red: Sharpen/Meditate raise Attack, Barrier sharply raises Defense)
SELF_BOOSTS = {"Sharpen": {"self": "atk", "st": 1}, "Meditate": {"self": "atk", "st": 1}, "Barrier": {"self": "def", "st": 2}}


def main():
    path = os.path.join(common.DATA, "moves.json")
    moves = common.load_json(path)
    n = 0
    for name in STATUS_MOVES:
        mv = moves.get(name)
        if mv is None or mv.get("c") == "X":
            continue
        mv["c_orig"] = mv.get("c")
        mv["c"] = "X"
        n += 1
    for name, eff in SELF_BOOSTS.items():
        if name in moves and not moves[name].get("eff"):
            moves[name]["eff"] = dict(eff)
    common.save_json(path, moves)
    print("move classes:", n, "moves set to status")


if __name__ == '__main__':
    main()
