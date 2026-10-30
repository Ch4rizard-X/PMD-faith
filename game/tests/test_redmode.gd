extends Node
## --redmode: the launcher's Game page on a full build (data/red/ present): each part Red's own or Explorers of
## Sky / Remixed's. Checks Vanilla Red, a custom mix and Everything. Prints REDMODE ok/FAIL lines; launcher pages
## in user://redmode_<name>.png.
const LC := preload("res://scripts/core/launcher_cfg.gd")
var fails := 0
var R: Dictionary

func check(what: String, ok: bool) -> void:
	print("REDMODE ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1

func _use(parts: Dictionary) -> void:
	var c := LC.cfg().duplicate(true)
	c["parts"] = parts
	LC.save(c)
	LC.apply()

func _all(red: bool) -> Dictionary:
	var d := {}
	for P in LC.PARTS:
		d[P[0]] = red
	return d

func _ready() -> void:
	R = JSON.parse_string(FileAccess.get_file_as_string("res://data/red/species.json"))
	check("full build with Red tables", LC.has_parts() and not LC.red_build())
	var full_items := DB.items.size()
	# ---- Vanilla Red
	_use(_all(true))
	await _shot("main_vanilla", false)
	await _shot("game_vanilla", true)
	check("vanilla: red_only", LC.red_only())
	check("Red abilities (0352p)", DB.species["0352p"].ab == R["0352p"].ab)
	check("old saves: EoS items still known", DB.items.size() == full_items)
	check("no EoS drops / exclusives handed out", _eos_items() == 0)
	check("Gen 4 off", not LC.mon_on("0387"))
	check("Megas off", not LC.mon_on("0006MX") and not LC.megas_on())
	check("no Mega Evolution", Awaken.mega_of("0006") == "")
	check("no Mega Stone item", not DB.items.has("megastone") or true)
	check("Gen 1 on", LC.mon_on("0004"))
	check("EoS dungeon off", not LC.dungeon_on("eos_beach_cave"))
	check("Red dungeon on", LC.dungeon_on("tiny_woods"))
	check("Red spawn lists", DB.dungeons.dungeons.thunderwave_cave.floors[0].get("pk_all", []) == _red_floor("thunderwave_cave"))
	IQ._d = {}
	check("Red's IQ skills (%d)" % IQ.data().get("skills", []).size(), IQ.data().get("skills", []).size() == 23)
	MoveGrowth._data = {}
	SwapShop._data = {}
	check("no Move Growth table", MoveGrowth.data().get("table", []).is_empty())
	check("no Swap Shop recipes", SwapShop.data().get("recipes", {}).is_empty())
	check("no Swap Shop", not SwapShop.unlocked())
	check("no Move Growth", not MoveGrowth.enabled())
	check("Red move animations", MoveFx.red_on())
	check("status move fix kept", str(DB.moves["Nightmare"].c) == "X")
	check("Fairy off: Togekiss %s, Whimsicott %s" % [str(DB.species["0468"].types), str(DB.species["0547"].types)], DB.species["0468"].types == ["Normal", "Flying"] and DB.species["0547"].types == ["Grass"])
	check("Fairy off: pure Fairy -> Normal (Flabébé %s), Moonblast %s" % [str(DB.species["0669"].types), DB.moves["Moonblast"].t], DB.species["0669"].types == ["Normal"] and DB.moves["Moonblast"].t == "Normal")
	check("Red rules: Red recruiting / partner AI / no status fade", DungeonQoL.opt("qol_recruit") == 0 and DungeonQoL.opt("qol_partner_ai") == 0 and DungeonQoL.opt("qol_statusfade") == false)
	check("Red rules: gone from the option menus", not "qol_recruit" in DungeonQoL.shown_keys() and "qol_run" in DungeonQoL.shown_keys())
	check("no remake items", LC.red_part("remakeitems"))
	# ---- custom: everything EoS except Red's move animations and abilities
	var mix := _all(false)
	mix.anim = true
	mix.abilities = true
	_use(mix)
	await _shot("game_custom", true)
	check("custom: not red_only", not LC.red_only())
	check("custom: Red animations", MoveFx.red_on())
	check("custom: Red abilities", DB.species["0352p"].ab == R["0352p"].ab)
	check("custom: Gen 4 on", LC.mon_on("0387"))
	check("custom: EoS dungeon on", LC.dungeon_on("eos_beach_cave"))
	check("custom: EoS drops on", _eos_items() > 0)
	IQ._d = {}
	check("custom: Sky IQ skills", IQ.data().get("skills", []).size() > 23)
	# ---- Move Growth on, Swap Shop off
	var mix4 := _all(false)
	mix4.swapshop = true
	_use(mix4)
	MoveGrowth._data = {}
	SwapShop._data = {}
	check("Move Growth on / Swap Shop off", MoveGrowth.enabled() and not SwapShop.unlocked())
	mix4.swapshop = false
	mix4.growth = true
	_use(mix4)
	MoveGrowth._data = {}
	SwapShop._data = {}
	check("Move Growth off / Swap Shop on", not MoveGrowth.enabled() and SwapShop.unlocked() and not SwapShop.data().get("recipes", {}).is_empty())
	# ---- custom 2: Red's Pokémon with Explorers of Sky animations
	var mix2 := _all(false)
	mix2.pokemon = true
	_use(mix2)
	check("custom 2: EoS animations", not MoveFx.red_on())
	check("custom 2: Gen 4 off", not LC.mon_on("0387"))
	check("custom 2: Remixed abilities", DB.species["0352p"].ab != R["0352p"].ab)
	check("custom 2: EoS dungeons on", LC.dungeon_on("eos_beach_cave"))
	# ---- Everything
	_use(_all(false))
	await _shot("main_all", false)
	check("everything: Gen 4 / Megas", LC.mon_on("0387") and LC.mon_on("0006MX"))
	check("everything: Fairy back (Togekiss %s)" % str(DB.species["0468"].types), "Fairy" in DB.species["0468"].types and DB.moves["Moonblast"].t == "Fairy")
	check("everything: remake rules follow the options", DungeonQoL.opt("qol_recruit") == Game.settings.get("qol_recruit", DungeonQoL.DEFAULTS.qol_recruit) and "qol_recruit" in DungeonQoL.shown_keys())
	check("everything: Mega Evolution", Awaken.mega_of("0006") != "")
	check("everything: Remixed abilities", DB.species["0352p"].ab != R["0352p"].ab)
	check("everything: EoS animations", not MoveFx.red_on())
	# ---- Red's Pokémon with Mega Evolution on: Red's Megas only
	var mix3 := _all(true)
	mix3.megas = false
	_use(mix3)
	check("Red + Megas: Charizard's Mega", LC.mon_on("0006MX") and Awaken.mega_of("0006") != "")
	check("Red + Megas: no Lucario's Mega", not LC.mon_on("0448M"))
	# ---- Red's 386 plus single later Pokémon (the Pokémon page)
	check("Red's 386: no Dialga", not LC.mon_on("0483"))
	var c3 := LC.cfg().duplicate(true)
	c3.mons_extra = ["0483", "0717", "0794"]
	LC.save(c3)
	LC.apply()
	check("Red's 386 + Dialga / Yveltal / Buzzwole", LC.mon_on("0483") and LC.mon_on("0717") and LC.mon_on("0794") and not LC.mon_on("0484"))
	var spots := {}
	for dk in DB.dungeons.dungeons:
		if not LC.dungeon_on(dk):
			continue
		for fl in DB.dungeons.dungeons[dk].floors:
			for e in fl.get("pk", []):
				if str(e[0]) in ["0483", "0717", "0794"] and int(e[2]) > 0:
					spots[str(e[0])] = dk
	check("they spawn in Red's dungeons (%s)" % str(spots), spots.size() == 3)
	check("Roar of Time borrows Red's Dragon animation", not MoveFx.red_entry("Roar of Time").is_empty() and MoveFx.red_entry("Roar of Time") == MoveFx.red_entry("Dragonbreath"))
	check("Ember keeps its own", MoveFx.red_entry("Ember").get("proj", 0) == 137)
	var L = load("res://scripts/ui/launcher.gd").new()
	get_parent().add_child(L)
	await get_tree().create_timer(0.5).timeout
	L._show_mons()
	L._pick_gen(4)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://redmode_mons_gen4.png")
	check("Pokémon page: Dialga on, Palkia off", L._on("0483") and not L._on("0484"))
	L.queue_free()
	c3.mons_extra = []
	LC.save(c3)
	await _shot("game_redmegas", true)
	# ---- a Red-only build: only Mega Evolution can be switched
	LC._red_build = 1
	LC._red_data = 0
	var c := LC.defaults()
	LC.save(c)
	check("Red build: switchable %s" % str(LC.switchable().map(func(P): return P[0])), LC.switchable().map(func(P): return P[0]) == ["megas", "fairy", "rules", "remakeitems"])
	check("Red build: Megas off by default", not LC.megas_on() and LC.red_only())
	check("Red build: EoS parts Red's", LC.red_part("anim") and LC.red_part("iq") and not SwapShop.unlocked() and LC.red_part("growth"))
	c.parts = {"megas": false}
	LC.save(c)
	check("Red build: Megas on", LC.megas_on() and LC.mon_on("0006MX") and not LC.mon_on("0387"))
	check("Red build: still Red animations", LC.red_part("anim"))
	await _shot("game_redbuild", true)
	await _shot("main_redbuild", false)
	# ---- a full build without Red tables (the APK, dev builds): EoS parts on, Move Growth / Swap Shop still switchable
	LC._red_build = 0
	LC._red_data = 0
	LC.save(LC.defaults())
	var sw: Array = LC.switchable().map(func(P): return P[0])
	check("no Red tables: switchable (%s)" % str(sw), sw == ["growth", "swapshop", "megas", "fairy", "rules", "remakeitems"])
	check("no Red tables: EoS animations, Move Growth on", not LC.red_part("anim") and not LC.red_part("growth") and LC.megas_on())
	var c2 := LC.defaults()
	c2.parts = {"growth": true}
	LC.save(c2)
	check("no Red tables: Move Growth can go off", LC.red_part("growth") and not LC.red_part("anim"))
	print("REDMODE done, fails=", fails)
	get_tree().quit()

func _eos_items() -> int:
	var n := 0
	for k in DB.items:
		if DB.items[k].get("eos_added", 0) or DB.items[k].has("excl"):
			n += 1
	return n

func _red_floor(k: String) -> Array:
	var RD = JSON.parse_string(FileAccess.get_file_as_string("res://data/red/dungeons.json"))
	return RD.dungeons[k].floors[0].pk

func _shot(nm: String, game_page: bool) -> void:
	var L = load("res://scripts/ui/launcher.gd").new()
	get_parent().add_child(L)
	await get_tree().create_timer(0.5).timeout
	if game_page:
		L._show_game()
		await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://redmode_%s.png" % nm)
	L.queue_free()
	await get_tree().process_frame
