"""SpriteCollab helpers: species key -> sprite/portrait folder, AnimData.xml parsing."""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import common  # noqa: E402

SC = common.SPRITECOLLAB
# key suffix -> SpriteCollab subgroup name in tracker.json
SUFFIX = {'M': 'Mega', 'MX': 'Mega_X', 'MY': 'Mega_Y', 'P': 'Primal', 'p': 'Purple'}
_tracker = None


def tracker():
    global _tracker
    if _tracker is None:
        _tracker = common.load_json(os.path.join(SC, 'tracker.json'))
    return _tracker


def split_key(key):
    m = re.fullmatch(r'(\d{4})(\w*)', key)
    return m.group(1), m.group(2)


def form_path(key):
    """Relative SpriteCollab form path ('0006' or '0006/0002') for a species key, or None."""
    num, suf = split_key(key)
    if not suf:
        return num
    want = SUFFIX.get(suf)
    for sid, sub in tracker().get(num, {}).get('subgroups', {}).items():
        if sub.get('name') == want:
            return f'{num}/{sid}'
    return None


def sprite_dir(form):
    return os.path.join(SC, 'sprite', *form.split('/'))


def portrait_dir(form):
    return os.path.join(SC, 'portrait', *form.split('/'))


def parse_animdata(path):
    """{name: ('copy', other) | ('anim', w, h, [durations])}, shadow size."""
    root = ET.parse(path).getroot()
    anims = {}
    for a in root.iter('Anim'):
        nm = a.findtext('Name')
        c = a.findtext('CopyOf')
        if c:
            anims[nm] = ('copy', c)
        else:
            anims[nm] = ('anim', int(a.findtext('FrameWidth')), int(a.findtext('FrameHeight')),
                         [int(d.text) for d in a.iter('Duration')])
    return anims, int(root.findtext('ShadowSize') or 1)


def resolve(anims, nm, seen=()):
    e = anims.get(nm)
    if e is None or nm in seen:
        return None
    return resolve(anims, e[1], seen + (nm,)) if e[0] == 'copy' else nm


def has_sheet(form):
    """The form has its own sprite: AnimData.xml and an Idle animation (possibly a CopyOf) with its png."""
    if not form:
        return False
    d = sprite_dir(form)
    xml = os.path.join(d, 'AnimData.xml')
    if not os.path.exists(xml):
        return False
    anims, _ = parse_animdata(xml)
    src = resolve(anims, 'Idle')
    return bool(src) and os.path.exists(os.path.join(d, f'{src}-Anim.png'))


def portrait_emotions(form):
    d = portrait_dir(form) if form else None
    if not d or not os.path.isdir(d):
        return []
    return sorted(f[:-4] for f in os.listdir(d) if f.endswith('.png') and '^' not in f)
