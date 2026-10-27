#!/usr/bin/env python3
"""SpriteCollab credits for every form the game uses (from tracker.json + credit_names.txt).

  python3 -I tools/sprites/credits.py [OUT]     (default: WORK_DIR/tmp/CREDITS_sprites.md)

SpriteCollab art is licensed CC BY-NC 4.0 (LICENSE.md in the checkout); this lists who made each sheet."""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402
import sclib  # noqa: E402


def names():
    out = {}
    with open(os.path.join(sclib.SC, 'credit_names.txt'), encoding='utf-8') as f:
        next(f)
        for line in f:
            p = line.rstrip('\n').split('\t')
            if len(p) >= 2:
                out[p[1]] = p[0] or p[1]
    return out


def node(form):
    parts = form.split('/')
    t = sclib.tracker()[parts[0]]
    for sid in parts[1:]:
        t = t['subgroups'][sid]
    return t


def who(cred, nm):
    if not cred or not cred.get('primary'):
        return []
    ids = [cred['primary']] + list(cred.get('secondary', []))
    return [nm.get(i, i) for i in ids]


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(common.TMP, 'CREDITS_sprites.md')
    sprites = common.load_json(os.path.join(common.DATA, 'sprites.json'))
    nm = names()
    lines = ['# Pokémon sprites and portraits', '',
             'From PMDCollab/SpriteCollab (https://github.com/PMDCollab/SpriteCollab), CC BY-NC 4.0. '
             'Contact details of every artist: credit_names.txt in that repository.', '']
    everyone = set()
    rows = []
    for key in sorted(sprites):
        form = sclib.form_path(key)
        if not form:
            continue
        t = node(form)
        s = [] if sprites[key].get('base_sprite') else who(t.get('sprite_credit'), nm)
        p = who(t.get('portrait_credit'), nm)
        everyone.update(s + p)
        title = sclib.tracker()[form.split('/')[0]].get('name', key) + (f' ({t.get("name")})' if '/' in form else '')
        rows.append(f'| {key} | {title} | {", ".join(s) or "-"} | {", ".join(p) or "-"} |')
    lines += ['## All artists', '', ', '.join(sorted(everyone, key=str.lower)), '',
              '## Per species', '', '| Key | Pokémon | Sprite | Portrait |', '|---|---|---|---|'] + rows
    with open(common.p(out), 'w', encoding='utf-8') as f:
        text = '\n'.join(lines) + '\n'
        # credits with no name in credit_names.txt are Discord ids (<@!123>): write them as plain text for Markdown
        text = re.sub(r'<@!?(\d+)>', r'Discord user \1', text)
        text = re.sub(r'<([^>\s]+)>', r'\1', text)
        f.write(text)
    print(f'{out}: {len(rows)} species, {len(everyone)} artists')


if __name__ == '__main__':
    main()
