class_name RedMsg
extends RefCounted
## Red's message strings ({CENTER_ALIGN}, {EXTRA_MSG}, {WAIT_PRESS}, {NAME_0}, {POKEMON_0}, {COLOR X}...{RESET})
## shown with the game's Dialog box. Used by the story screens ported from the decomp (Luminous Cave, Dojo,
## thank-you scene, credits ...).

const COLORS := {"YELLOW": "#ffdc4a", "CYAN": "#7fe0ff", "GREEN": "#7fff7f", "RED": "#ff8070", "LIGHT_BLUE": "#a0c8ff"}

## {EXTRA_MSG} starts a new box; returns BBCode pages.
static func pages(s: String, names := [], mons := [], nums := []) -> Array:
	var out: Array = []
	for p in s.split("{EXTRA_MSG}"):
		if p.strip_edges() == "":
			continue
		out.append(bb(p, names, mons, nums))
	return out

static func bb(s: String, names := [], mons := [], nums := []) -> String:
	for i in names.size():
		s = s.replace("{NAME_%d}" % i, "[color=#7fe0ff]%s[/color]" % str(names[i]))
	for i in mons.size():
		s = s.replace("{POKEMON_%d}" % i, str(mons[i]))
	for i in nums.size():
		s = s.replace("{VALUE_%d}" % i, str(nums[i]))
	var r := RegEx.new()
	r.compile("\\{COLOR (\\w+)\\}")
	for m in r.search_all(s):
		s = s.replace(m.get_string(0), "[color=%s]" % COLORS.get(m.get_string(1), "#ffffff"))
	s = s.replace("{RESET}", "[/color]")
	s = s.replace("{WAIT_PRESS}", "")
	var lines: Array = []
	for ln in s.split("\n"):
		if ln.contains("{CENTER_ALIGN}"):
			lines.append("[center]%s[/center]" % ln.replace("{CENTER_ALIGN}", ""))
		else:
			lines.append(ln)
	s = "\n".join(lines).replace("[/center]\n[center]", "\n")
	s = UITheme.glyph_tags(s)
	var r2 := RegEx.new()
	r2.compile("\\{[^}]*\\}")
	return r2.sub(s, "", true)

static func say(root: Control, s: String, speaker := "", emotion := "Normal", names := [], mons := [], nums := []) -> void:
	await Dialog.talk(root, pages(s, names, mons, nums), speaker, emotion)

## All pages but the last are plain boxes; the last one carries the menu.
static func ask(root: Control, s: String, options: Array, speaker := "", emotion := "Normal", cancel := true, names := [], mons := []) -> int:
	var ps := pages(s, names, mons)
	for i in ps.size() - 1:
		await Dialog.talk(root, [ps[i]], speaker, emotion)
	if Dialog.auto or ListMenu.auto:
		print("  DIALOG ", str(ps[-1] if ps.size() else "").replace("\n", " | ").left(160), "  -> ", options)
	return await Dialog.ask(root, ps[-1] if ps.size() else "", options, speaker, emotion, cancel)
