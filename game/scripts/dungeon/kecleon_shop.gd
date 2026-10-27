class_name KecleonShop
extends RefCounted
## Red's Kecleon Shop inside dungeons (dungeon_kecleon_shop.c, dungeon_items.c SpawnItem / RemoveGroundItem),
## with Red's own lines (dungeon_strings.c).
##
##   - The shop is the generator's shop rectangle; Kecleon (Lv. 90, Red's spawn level) stands in its middle and
##     doesn't move or fight. Its wares carry a price ("price" on the floor item / Toolbox entry = IN_SHOP).
##   - Picking a ware up leaves it unpaid. Owed = the wares' value when the floor began (or since the last
##     payment) minus the value still lying on shop tiles; your own items left on shop tiles are offered for.
##   - Stepping into the shop with Kecleon in the room: "Ah, welcome~♪" and the shop theme.
##   - Stepping out of it while owing: Kecleon steps next to you and offers for what you left, then asks you to
##     pay. No, or not enough money = thief. Owing with no Kecleon able to stop you (another room, asleep,
##     invisible leader) = thief too. Leaving with nothing owed: "I await your next visit."
##   - Talking to Kecleon: the same offers; saying no inside the shop is only "That is very disappointing...".
##   - Thief: "Help! Thief! I've been robbed!", the Stop Thief! theme, every price is cleared (you keep the
##     items), Kecleon turn hostile and new Kecleon (Lv. 90) arrive every 5 turns (gKecleonSpawnIntervalFrames).

const KECLEON := "0352"
const LEVEL := 90                      # pokemon_found tables: Kecleon, level 90, probability 0
const MUS_SHOP := "017"                # MUS_KECLEON_SHOP
const MUS_THIEF := "018"               # MUS_STOP_THIEF
const THIEF_SPAWN_TURNS := 5

const T_WELCOME := "Ah, welcome〜♪"
const T_NEXT_VISIT := "I await your next visit."
const T_COSTS := "The merchandise you have chosen\ncosts %d Poké.\nIs that acceptable?"
const T_SELL := "For the merchandise you have left me,\nI shall pay %d Poké.\nIs that acceptable?"
const T_PATRONAGE := "Your patronage is valued."
const T_THANKS := "Thank you so very much."
const T_NO_MONEY := "You don't seem to have enough money."
const T_DISAPPOINTED := "That is very disappointing.\nPlease return any items\nbefore you leave..."
const T_AGAIN := "I'm looking forward to serving you again!"
const T_THIEF := "Help! Thief! I've been robbed!\nHelp me catch the thief!"

var dg                                 # Dungeon (untyped: no class cycle)
var prev_in_shop := false

func _init(d) -> void:
	dg = d

# ------------------------------------------------------------------ state
func rect() -> Rect2i:
	return dg.fs.get_meta("shop_rect", Rect2i()) if dg.fs else Rect2i()

func active() -> bool:
	return rect().size.x > 0

func is_shop_tile(p: Vector2i) -> bool:
	var r := rect()
	return r.size.x > 0 and r.has_point(p) and not dg.fs.is_wall(p)

static func shoppable(id: String) -> bool:
	return id != "poke" and DB.items.has(id) and int(DB.items[id].get("price", 0)) > 0

## GetActualBuyPrice: stackable items cost per piece.
static func buy_price(id: String, n: int) -> int:
	var I: Dictionary = DB.items.get(id, {})
	return int(I.get("price", 0)) * (maxi(1, n) if bool(I.get("stack", false)) else 1)

static func sell_price(id: String, n: int) -> int:
	var I: Dictionary = DB.items.get(id, {})
	return int(I.get("sell", 0)) * (maxi(1, n) if bool(I.get("stack", false)) else 1)

## Value of the wares still lying on shop tiles (Red's unk48).
func wares_on_shelves() -> int:
	var tot := 0
	for p in dg.fs.items:
		var it: Dictionary = dg.fs.items[p]
		if int(it.get("price", 0)) > 0 and is_shop_tile(p):
			tot += int(it.price)
	return tot

## What the team owes (Red: unk50 - unk48).
func owed() -> int:
	return maxi(0, int(dg.shop_base) - wares_on_shelves())

## What Kecleon pays for the team's own items left on shop tiles (Red's unk4C).
func offer() -> int:
	var tot := 0
	for p in dg.fs.items:
		var it: Dictionary = dg.fs.items[p]
		if int(it.get("price", 0)) == 0 and is_shop_tile(p) and shoppable(str(it.id)):
			tot += sell_price(str(it.id), int(it.get("n", 1)))
	return tot

func keepers() -> Array:
	return dg.fs.mons.filter(func(m): return m.hp > 0 and bool(m.get_meta("shopkeeper", false)))

## sub_8070BC0: a Kecleon that can act (not asleep, frozen, paralysed, petrified ...).
func _can_act(k: Mon) -> bool:
	return not AI.is_sleeping(k) and AI.st(k, "frozen") == 0 and AI.st(k, "petrified") == 0 and AI.st(k, "para") == 0 \
		and AI.st(k, "paused") == 0 and AI.st(k, "infatuated") == 0

func _same_room(a: Vector2i, b: Vector2i) -> bool:
	var ra: int = dg.fs.room_at(a)
	return ra != 255 and ra == dg.fs.room_at(b)

# ------------------------------------------------------------------ floor start
## The floor's shop (gen "shop" rect, "kecleon" middle): Kecleon in the middle, the wares' value noted.
func on_floor_built(gen: Dictionary) -> void:
	var r: Rect2i = gen.get("shop", Rect2i())
	dg.fs.set_meta("shop_rect", r)
	dg.shop_stole = false
	prev_in_shop = false
	if r.size.x <= 0:
		dg.shop_base = 0
		return
	var kp: Vector2i = gen.get("kecleon", Vector2i(-1, -1))
	if kp.x < 0:
		kp = r.get_center()
	if dg.fs.mon_at(kp) != null:
		kp = dg.fs.free_tile_near(kp, null, 3)
	if kp.x >= 0:
		var k: Mon = DB.make_mon(KECLEON, LEVEL, "enemy")
		k.pos = kp
		k.facing = 4
		k.recruit_ok = false
		k.set_meta("shopkeeper", true)
		dg.fs.mons.append(k)
		dg._add_sprite(k)
	dg.shop_base = wares_on_shelves()
	prev_in_shop = is_shop_tile(dg.fs.leader.pos) if dg.fs.leader else false

# ------------------------------------------------------------------ leader steps (sub_807EC28)
func on_leader_step() -> void:
	if not active() or dg.result_sent or dg.fs.leader == null:
		return
	var L: Mon = dg.fs.leader
	var was := prev_in_shop
	var now := is_shop_tile(L.pos)
	prev_in_shop = now
	if was != now and not dg.shop_stole:
		Audio.play_music(MUS_SHOP if now else dg._music_for())
	if dg.shop_stole or int(dg.shop_base) == 0 and offer() == 0:
		return
	if AI.st(L, "invisible") > 0:
		prev_in_shop = false
		now = false
	var keeper_here: Mon = null
	for k in keepers():
		if _can_act(k) and _same_room(L.pos, k.pos):
			keeper_here = k
	if not was:
		if now and keeper_here != null:
			await _say(T_WELCOME)
		return
	if now:
		return
	# stepped out of the shop
	var owing := owed() > 0 or offer() > 0
	if owing and keeper_here != null:
		_come_over(keeper_here)
		await _offer_for_left_items(true)
		if await _ask_payment(true) != 0:
			await thief()
		return
	if owed() > 0:
		await thief()                        # nobody there to stop you
		return
	if keeper_here != null:
		await _say(T_NEXT_VISIT)

## Talking to Kecleon (sub_807EF84).
func talk(k: Mon) -> void:
	if dg.shop_stole:
		return
	dg.fs.leader.facing = AI.dir_toward(dg.fs.leader.pos, k.pos)
	k.facing = AI.dir_toward(k.pos, dg.fs.leader.pos)
	await _offer_for_left_items(true)
	var r := await _ask_payment(true)
	if r != 0:
		if is_shop_tile(dg.fs.leader.pos):
			if r != 2:
				await _say(T_DISAPPOINTED)
		else:
			await thief()
	else:
		await _say(T_AGAIN)

## WarpTarget: Kecleon steps next to the leader (a room tile), and they face each other.
func _come_over(k: Mon) -> void:
	var L: Mon = dg.fs.leader
	if FloorState.cheb(L.pos, k.pos) >= 2:
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var p: Vector2i = L.pos + Vector2i(dx, dy)
				if p != L.pos and dg.fs.room_at(p) != 255 and dg.fs.mon_at(p) == null and dg.fs.walkable(p, k):
					k.pos = p
					if k.visual:
						k.visual.position = dg._px(p)
					dx = 9
					break
			if dx == 9:
				break
	L.facing = AI.dir_toward(L.pos, k.pos)
	k.facing = AI.dir_toward(k.pos, L.pos)
	if L.visual:
		L.visual.queue_redraw()
	if k.visual:
		k.visual.queue_redraw()

## sub_807EFFC: buy back the team's items left on the shop floor (they become wares).
func _offer_for_left_items(ask: bool) -> void:
	var v := offer()
	if v <= 0 or not ask:
		return
	if await _ask(T_SELL % v) != 0:
		return
	Audio.sfx("332")
	Game.money += v
	var added := 0
	for p in dg.fs.items.keys():
		var it: Dictionary = dg.fs.items[p]
		if int(it.get("price", 0)) == 0 and is_shop_tile(p) and shoppable(str(it.id)):
			it.price = buy_price(str(it.id), int(it.get("n", 1)))
			added += int(it.price)
	dg.shop_base = int(dg.shop_base) + added
	dg.obj_layer.queue_redraw()
	await _say(T_PATRONAGE)

## sub_807F19C: 0 paid / nothing owed, 1 refused, 2 not enough money.
func _ask_payment(ask: bool) -> int:
	var d := owed()
	if d <= 0:
		return 0
	if not ask:
		return 1
	if await _ask(T_COSTS % d) != 0:
		return 1
	if Game.money < d:
		await _say(T_NO_MONEY)
		return 2
	Audio.sfx("332")
	Game.money -= d
	_clear_prices(false)
	dg.shop_base = wares_on_shelves()
	await _say(T_THANKS)
	dg._update_hud()
	return 0

## Prices off everything the team carries / has dropped outside the shop (all = every item, the thief case).
func _clear_prices(all: bool) -> void:
	for b in Game.bag:
		b.erase("price")
	for p in dg.fs.items:
		if all or not is_shop_tile(p):
			dg.fs.items[p].price = 0
	dg.obj_layer.queue_redraw()

## sub_807F33C
func thief() -> void:
	if dg.shop_stole:
		return
	dg.shop_stole = true
	dg._msg(T_THIEF)
	_clear_prices(true)
	for k in dg.fs.mons:
		if bool(k.get_meta("shopkeeper", false)):
			k.remove_meta("shopkeeper")
			dg.mem.erase(k.uid)
	dg.shop_base = 0
	Audio.play_music(MUS_THIEF)
	await dg.get_tree().process_frame

## After a theft: a Kecleon (Lv. 90, hostile) instead of the floor's Pokémon, every 5 turns.
func thief_spawn() -> void:
	var p := TurnRules.spawn_position(dg.fs)
	if p.x < 0 or dg.fs.mon_at(p) != null:
		return
	var k: Mon = DB.make_mon(KECLEON, LEVEL, "enemy")
	k.pos = p
	k.recruit_ok = true
	dg.fs.mons.append(k)
	dg._add_sprite(k)

# ------------------------------------------------------------------ text
func _say(t: String) -> void:
	if dg.auto_answer or Dialog.auto:
		print("  SHOP ", t.replace("\n", " "))
		return
	dg.menu_open = true
	await Dialog.say(dg.ui_root, t, KECLEON)
	dg.menu_open = false

func _ask(t: String) -> int:
	if dg.auto_answer or Dialog.auto:
		print("  SHOP ", t.replace("\n", " "), " -> Yes")
		return 0
	dg.menu_open = true
	var c := await Dialog.ask(dg.ui_root, t, ["Yes", "No"], KECLEON, "Normal", false)
	dg.menu_open = false
	return c
