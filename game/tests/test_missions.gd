extends SceneTree
## Headless test for res://scripts/core/missions.gd + res://data/missions.json (Red's rescue jobs).
## Run: godot --headless --path . --script tests/test_missions.gd
## Work happens in _initialize() so the DB / Game autoloads exist; Missions is loaded at runtime.
## Nothing is saved (Game.save_game is never called here).

var M
var fails := 0
var checks := 0
var fail_msgs := {}

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		fail_msgs[msg] = int(fail_msgs.get(msg, 0)) + 1
		if int(fail_msgs[msg]) <= 3:
			print("FAIL: ", msg)

func _initialize() -> void:
	var db = root.get_node_or_null("DB")
	if db and db.species.is_empty():
		db._ready()
	var game = root.get_node("Game")
	M = load("res://scripts/core/missions.gd")
	var saved := {"jobs": game.jobs, "board": game.board, "unlocked": game.unlocked, "cleared": game.cleared,
		"rank_points": game.rank_points, "flags": game.flags, "team": game.team, "friends": game.friends, "bag": game.bag, "friend_areas": game.friend_areas}
	game.flags = {}
	game.team = [{"sp": "0025", "name": "Pikachu"}, {"sp": "0004", "name": "Charmander"}]
	game.bag = []
	game.friends = [{"sp": "0990", "name": "Iron Treads"}]

	ok(not M.data().is_empty(), "missions.json loads")
	ok(M._in_red("0025") and not M._in_red("0990"), "Red species flag (Iron Treads is not in Red)")
	_test_ranks()
	_test_tables(db)
	_test_generation(db, game)
	_test_board(game)
	_test_mailbox(game)
	_test_job_list(game)
	_test_pages()

	for k in saved:
		game.set(k, saved[k])
	print("")
	print("test_missions: %d checks, %d failures" % [checks, fails])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	quit(1 if fails > 0 else 0)

func _test_ranks() -> void:
	var cases := [[0, "Normal"], [49, "Normal"], [50, "Bronze"], [499, "Bronze"], [500, "Silver"], [1499, "Silver"],
		[1500, "Gold"], [2999, "Gold"], [3000, "Platinum"], [7499, "Platinum"], [7500, "Diamond"], [14999, "Diamond"],
		[15000, "Lucario"], [99999999, "Lucario"]]
	for c in cases:
		ok(M.rank_name(c[0]) == c[1], "rank_name(%d) == %s (got %s)" % [c[0], c[1], M.rank_name(c[0])])
	ok(M.pts_to_next_rank(0) == 50 and M.pts_to_next_rank(60) == 440 and M.pts_to_next_rank(20000) == 0, "points to next rank")
	ok(M.rank_title(500) == "Silver Rank", "rank title")
	var D: Dictionary = M.data()
	ok(D.ranks.size() == M.RANKS.size(), "ranks match json")
	for i in M.RANKS.size():
		ok(str(D.ranks[i][0]) == str(M.RANKS[i][0]) and int(D.ranks[i][1]) == int(M.RANKS[i][1]), "rank %d matches decomp" % i)
	for i in 16:
		ok(int(D.rank_points[i]) == int(M.RANK_POINTS[i]), "rank points %d match decomp" % i)
	ok(M.letter_index(0) == 0 and M.letter_index(1) == 0 and M.letter_index(2) == 1 and M.letter_index(13) == 6 and M.letter_index(15) == 6, "difficulty letters")

func _test_tables(db) -> void:
	var D: Dictionary = M.data()
	ok(D.item_sets.size() == 15, "15 reward item sets")
	for s in D.item_sets:
		for c in D.item_sets[s].cats:
			ok(D.item_sets[s].items.has(c[0]), "set %s category %s has items" % [s, c[0]])
		for c in D.item_sets[s].items:
			for e in D.item_sets[s].items[c]:
				ok(db.items.has(e[0]), "set item %s exists" % e[0])
	var tw: Dictionary = M.dinfo("tiny_woods")
	ok(int(tw.red_floor_count) == 4 and tw.jobs, "Tiny Woods: 4 (3 floors + floor 0), hosts jobs")
	ok(M.no_job_floors("mt_steel").has(9), "Mt. Steel 9F (Skarmory) has no jobs")
	ok(not M.dinfo("oddity_cave").get("jobs", true), "Oddity Cave is Wonder-Mail only")
	for sp in D.banned_species:
		ok(db.species.has(sp), "banned species key %s valid" % sp)
	for e in D.parent_child + D.friend_pairs + D.lover_pairs:
		ok(db.species.has(e[0]) and db.species.has(e[1]), "pair species valid %s" % str(e.slice(0, 2)))
	for e in D.evo_items + D.gummi_prefs:
		ok(db.species.has(e[0]) and db.items.has(e[1]), "species/item pair valid %s" % str(e))

## Thousands of jobs over many unlocked/cleared sets, ranks and post-game states.
func _test_generation(db, game) -> void:
	var all_jobs: Array = []
	for k in M.data().dungeons:
		if M.dinfo(k).get("jobs", false) and db.dungeons.dungeons.has(k):
			all_jobs.append(k)
	var story: Array = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm", "mt_thunder"]
	var sets := [[], ["tiny_woods"], story.slice(0, 3), story, all_jobs, ["oddity_cave"], ["d50", "tiny_woods"]]
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for _r in 6:
		var sub: Array = []
		for k in all_jobs:
			if rng.randf() < 0.3:
				sub.append(k)
		sets.append(sub)
	var kinds := {}
	var total := 0
	var specials := {}
	var mbox_types := {}
	for si in sets.size():
		for rank_pts in [0, 120, 20000]:
			for post in [false, true]:
				game.cleared = sets[si].duplicate()
				game.unlocked = sets[si].duplicate()
				if game.unlocked.is_empty():
					game.unlocked = ["tiny_woods"]
				game.rank_points = rank_pts
				game.flags = {"postgame": post}
				game.jobs = []
				game.friend_areas = []
				var allowed: Array = M.job_dungeons()
				for b in 30:
					var ctx: Dictionary = M.make_context()
					ctx.mailbox = (b % 3 == 2)
					for n in 8:
						var j: Dictionary = M.gen_job(rng, ctx)
						if j.is_empty():
							break
						_check_job(db, j, allowed, rank_pts, ctx)
						for o in ctx.existing:
							ok(not (o.dungeon == j.dungeon and (o.floor == j.floor or o.kind == "escort")), "no two jobs at one location")
						ctx.existing.append(j)
						total += 1
						if rank_pts > 0:
							kinds[j.kind] = int(kinds.get(j.kind, 0)) + 1
						specials[j.special] = int(specials.get(j.special, 0)) + 1
						if ctx.mailbox:
							mbox_types[j.reward.type] = int(mbox_types.get(j.reward.type, 0)) + 1
	print("generated %d jobs; kinds (rank > Normal) %s; specials %s; mailbox rewards %s" % [total, str(kinds), str(specials), str(mbox_types)])
	ok(total > 3000, "thousands of jobs generated")
	var n := 0
	for k in kinds:
		n += int(kinds[k])
	# Red: 2/8 rescue, 2/8 target, 2/8 escort, 1/8 find, 1/8 deliver (item-less dungeons turn some into rescues)
	ok(absf(float(kinds.get("escort", 0)) / n - 0.25) < 0.04, "escort share ~25%")
	ok(absf(float(kinds.get("target", 0)) / n - 0.25) < 0.04, "target share ~25%")
	ok(float(kinds.get("find", 0)) / n > 0.08 and float(kinds.get("find", 0)) / n < 0.15, "find share ~12.5%")
	ok(float(kinds.get("deliver", 0)) / n > 0.08 and float(kinds.get("deliver", 0)) / n < 0.15, "deliver share ~12.5%")
	ok(specials.has(7) and specials.has(8) and specials.has(9) and specials.has(6) and specials.has(5), "all special job pools appear")
	ok(mbox_types.has("friend_area"), "mailbox offers Friend Areas")

func _check_job(db, j: Dictionary, allowed: Array, rank_pts: int, ctx: Dictionary) -> void:
	var key: String = j.dungeon
	ok(key in allowed, "dungeon %s allowed" % key)
	var D: Dictionary = db.dungeons.dungeons.get(key, {})
	var real: int = D.get("floors", []).size()
	var rc: int = M.red_floor_count(key)
	ok(j.floor >= 1 and j.floor <= real, "floor within dungeon (%s %d/%d)" % [key, j.floor, real])
	ok(j.floor >= rc / 2, "floor in Red's upper half (%s %d, count %d)" % [key, j.floor, rc])
	ok(not int(j.floor) in M.no_job_floors(key), "not a no-job floor")
	ok(j.kind in ["rescue", "target", "escort", "find", "deliver"], "kind valid")
	if rank_pts == 0:
		ok(j.kind != "escort", "no escorts at Normal Rank")
	ok(db.species.has(j.client) and db.species.has(j.target), "species valid")
	ok(j.client.length() == 4 and not j.client in M.data().banned_species, "client base form, not banned")
	ok(M._in_red(j.client) and M._in_red(j.target), "client/target exist in Red")
	if not ctx.postgame:
		ok(not j.client in M.data().banned_species_pregame, "story species not used before post-game")
		ok(j.client != "0025" and j.client != "0004", "hero/partner not clients before post-game")
	if j.kind in ["rescue", "find", "deliver"]:
		ok(j.target == j.client, "target == client for %s" % j.kind)
	if j.kind in ["find", "deliver"]:
		ok(db.items.has(j.item) and j.item != "poke" and not M._thrown(j.item), "job item valid (%s)" % j.item)
		ok(M.item_in_dungeon(key, j.item), "job item can appear in the dungeon")
	else:
		ok(j.item == "", "no item for %s" % j.kind)
	if j.kind == "deliver":
		ok(int(D.get("max_items", 1)) > 0, "deliver only where items are allowed")
	match int(j.special):
		5:
			ok(ctx.postgame and j.kind in ["find", "deliver"], "evo-item jobs only post-game")
		6:
			ok(j.kind in ["find", "deliver"], "gummi jobs are item jobs")
		7, 8:
			ok(j.kind == "target", "parent/friend pairs are rescue-target jobs")
		9:
			ok(j.kind == "escort", "lovers are escorts")
	var arr: Array = M.dinfo(key).get("difficulty", [])
	var d := int(arr[j.floor]) + (2 if j.kind == "escort" else 0)
	d = mini(d, 15)
	ok(j.diff == d, "difficulty from Red's floor table")
	ok(j.difficulty == M.DIFF_LETTERS[mini(d / 2, 6)], "difficulty letter")
	var r: Dictionary = j.reward
	ok(int(r.rank_points) == int(M.RANK_POINTS[d]), "rank points by difficulty")
	var li: int = mini(d / 2, 6)
	if ctx.mailbox:
		ok(r.type in M.MAILBOX_REWARDS, "mailbox reward type")
	else:
		ok(r.type in M.BOARD_REWARDS, "board reward type")
	match r.type:
		"money", "money_extra":
			ok(int(r.money) == (li + 1) * 100, "money = (letter+1)*100")
		"money1", "money1_extra":
			ok(int(r.money) == (li + 1) * 200, "mailbox money = (letter+1)*200")
		_:
			ok(int(r.money) == 0, "no money for %s" % r.type)
	if r.type in ["money_extra", "item", "item_extra", "money1_extra", "item1", "item1_extra"]:
		ok(db.items.has(r.item), "reward item exists (%s)" % r.item)
		ok(r.item_n == (10 if M._thrown(r.item) else 1), "reward quantity")
		if int(j.special) == 0:
			ok(r.item != j.item, "reward item differs from the job item")
	if r.type == "friend_area":
		ok(li > 0 and r.friend_area in M.data().wonder_mail_friend_areas, "friend area reward valid")
	for f in ["title", "text", "objective", "place"]:
		var s := str(j.get(f, ""))
		ok(s != "" and not "%s" in s and not "{" in s, "%s filled (%s)" % [f, s])

func _test_board(game) -> void:
	game.cleared = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods"]
	game.rank_points = 600
	game.jobs = []
	game.board = []
	game.board_day = -1
	game.day = 3
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var sizes := {}
	for i in 300:
		var b: Array = M.make_board(rng)
		sizes[b.size()] = int(sizes.get(b.size(), 0)) + 1
		var seen := {}
		for j in b:
			var k := "%s:%d" % [j.dungeon, j.floor]
			ok(not seen.has(k), "board: unique locations")
			seen[k] = true
			ok(j.source == "board" and j.state == "board", "board job state")
	print("board sizes: ", sizes)
	ok(sizes.keys().max() <= 8 and int(sizes.get(5, 0)) > 0 and int(sizes.get(8, 0)) > 0, "board has up to 8 jobs")
	# with plenty of free locations the board always has 5..8 (fewer only when every floor is taken)
	var many: Array = []
	for k in M.data().dungeons:
		if M.dinfo(k).get("jobs", false):
			many.append(k)
	game.cleared = many
	for i in 300:
		var b2: Array = M.make_board(rng)
		ok(b2.size() >= 5 and b2.size() <= 8, "board has 5..8 jobs (got %d)" % b2.size())
	game.cleared = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods"]
	ok(M.refresh_board_if_new_day(rng), "refresh on a new day")
	ok(game.board_day == 3 and not game.board.is_empty(), "board_day stored")
	var first: String = game.board[0].id
	ok(not M.refresh_board_if_new_day(rng) and game.board[0].id == first, "same day keeps the board")
	game.day = 4
	ok(M.refresh_board_if_new_day(rng), "next day refreshes")
	# Tiny Woods only: B2F-B3F
	game.cleared = ["tiny_woods"]
	var floors := {}
	for i in 200:
		var j: Dictionary = M.gen_job(rng, M.make_context())
		ok(j.dungeon == "tiny_woods", "Tiny Woods only")
		floors[j.floor] = true
	ok(floors.keys().size() == 2 and floors.has(2) and floors.has(3), "Tiny Woods jobs on B2F/B3F (got %s)" % str(floors.keys()))
	# nothing cleared -> Red's fallback (Tiny Woods + Thunderwave Cave)
	game.cleared = []
	ok(M.job_dungeons() == ["tiny_woods", "thunderwave_cave"], "fallback job dungeons")

func _test_mailbox(game) -> void:
	game.flags = {}
	game.day = 10
	game.cleared = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	ok(M.refresh_mailbox_if_new_day(rng), "mailbox gets letters")
	var mb: Array = M.mailbox()
	ok(mb.size() >= 1 and mb.size() <= M.MAILBOX_SLOTS, "mailbox 1..4 letters")
	ok(not M.refresh_mailbox_if_new_day(rng), "one delivery per day")
	for j in mb:
		ok(j.source == "mailbox" and j.reward.type in M.MAILBOX_REWARDS, "mailbox job rules")

func _test_job_list(game) -> void:
	game.jobs = []
	game.cleared = ["tiny_woods", "thunderwave_cave", "mt_steel", "sinister_woods", "silent_chasm", "mt_thunder", "great_canyon"]
	game.rank_points = 600
	game.flags = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ctx: Dictionary = M.make_context()
	var made: Array = []
	for i in 10:
		var j: Dictionary = M.gen_job(rng, ctx)
		ctx.existing.append(j)
		made.append(j)
	game.board = made
	for i in 8:
		ok(M.accept(made[i]), "accept job %d" % i)
	ok(not M.accept(made[8]), "Job List holds 8")
	ok(not M.accept(made[0]), "no duplicate accept")
	ok(game.jobs.size() == 8 and made[0].accepted, "8 accepted")
	var j0: Dictionary = M.find_job(made[0].id)
	ok(j0.state == "suspended", "accepted jobs start suspended (Red)")
	ok(M.jobs_for_floor(j0.dungeon, j0.floor).is_empty(), "suspended jobs are inactive")
	M.take(j0)
	ok(j0.state == "taken", "Take Job")
	if j0.kind != "find":
		ok(M.jobs_for_floor(j0.dungeon, j0.floor).has(j0), "taken job on its floor")
	M.suspend(j0)
	ok(j0.state == "suspended", "Suspend")
	M.cancel(made[1])
	ok(game.jobs.size() == 7 and not made[1].accepted, "Delete")
	# dungeon end bookkeeping
	M.take(j0)
	j0.state = "done_pending"
	M.on_dungeon_end(j0.dungeon, "defeated")
	ok(j0.state == "taken", "fainting loses an unfinished-home job")
	j0.state = "done_pending"
	M.on_dungeon_end(j0.dungeon, "rescued")
	ok(j0.state == "done", "getting home completes it")
	ok(M.pending_rewards().has(j0), "pending reward listed")
	# find item: done when the item is in the Toolbox on returning from that dungeon
	var fj := {}
	for i in 400:
		var j: Dictionary = M.gen_job(rng, M.make_context())
		if j.kind == "find":
			fj = j
			break
	ok(not fj.is_empty(), "found a find-item job")
	if not fj.is_empty():
		game.jobs = []
		M.accept(fj)
		var f: Dictionary = M.find_job(fj.id)
		M.take(f)
		game.bag = []
		M.on_dungeon_end(f.dungeon, "cleared")
		ok(f.state == "taken", "find job not done without the item")
		game.bag = [{"id": f.item, "n": 1}]
		M.on_dungeon_end("some_other_dungeon", "cleared")
		ok(f.state == "taken", "find job needs its own dungeon")
		M.on_dungeon_end(f.dungeon, "cleared")
		ok(f.state == "done", "find job done with the item in the Toolbox")
	ok(M.reward_text({"reward": {"type": "money_extra", "money": 200}}) == "200 Poké + ?", "reward text")

func _test_pages() -> void:
	var p: Array = M.pages("A happily accepted the item!\n\n\nA: Thank you!\n\n\nA left the dungeon!\n\n")
	ok(p == ["A happily accepted the item!", "A: Thank you!", "A left the dungeon!"], "pages split (%s)" % str(p))
	var q: Array = M.pages("Congratulations!\fX went up in rank\nfrom the A\nto the B!")
	ok(q.size() == 2 and q[0] == "Congratulations!", "\\f page breaks")
