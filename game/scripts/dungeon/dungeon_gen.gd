## DungeonGen - port of Pokemon Mystery Dungeon: Red Rescue Team's random floor
## generator (pmd-red decomp, src/dungeon_generation.c, entry point GenerateFloor).
##
## Usage:
##   var floor := DungeonGen.generate(DungeonGen.props_from_bytes(record28), seed)
##
## The original C function names are kept in comments ("// C: Name") so every
## routine can be cross-checked against the decomp. RNG: DungeonRandInt(n) is
## reproduced as ((rand16 * n) >> 16) & 0xFFFF where rand16 comes from a Godot
## RandomNumberGenerator seeded with seed_value; the call order follows the C.
##
## Returned Dictionary:
##   "w": 56, "h": 32
##   "terrain": PackedByteArray [y*w+x]: 0 wall, 1 floor, 2 secondary terrain
##              (water or lava, see "secondary_kind"), 3 chasm (Red stores the
##              secondary terrain of the two "chasm" tilesets (9, 35) as type 3 =
##              NORMAL|SECONDARY via sub_804FC74; the item code calls it "fell out
##              of sight").
##   "room":    PackedByteArray [y*w+x]: room index 0..N-1, 255 = hallway / no room.
##              Raw Red value: wall tiles inside a room rectangle (maze walls,
##              imperfections) keep the room index.
##   "flags":   PackedInt32Array [y*w+x], bits:
##                 1 FLAG_IMPASSABLE   TERRAIN_TYPE_IMPASSABLE_WALL (map border); the AI won't step there
##                 2 FLAG_JUNCTION     natural junction (room tile next to hallway,
##                                     or hallway tile with >2 open neighbours)
##                 4 FLAG_SHOP         in Kecleon shop (after Red's shop shrink)
##                 8 FLAG_MONSTER_HOUSE in monster house
##                16 FLAG_STAIRS       stairs tile
##                32 FLAG_MAZE         tile in a maze room
##                64 FLAG_WARP         trap on this tile is a Warp Tile (island structure)
##               128 FLAG_ISLAND_MOAT  secondary tile of an island moat (Red marks it
##                                     corner-cuttable during generation, so the
##                                     reachability check treats it as passable)
##               256 FLAG_SS_ROOM      tile belongs to a room that got a secondary
##                                     structure (SPAWN_FLAG_UNK5)
##               512 FLAG_DIVIDER_HALF first half of a "divider" room (TERRAIN_TYPE_UNK_7)
##              1024 FLAG_KECLEON      Kecleon shopkeeper position
##              2048 FLAG_UNBREAKABLE  TERRAIN_TYPE_UNBREAKABLE (fixed-room tiles): walkable, not counted for spawns
##   "stairs": Vector2i, "player": Vector2i (leader spawn, gDungeon->playerSpawn)
##   "items": Array of {pos: Vector2i, kind: "normal"|"shop"|"house"|"buried"}
##            (items flagged on the stairs tile are skipped, as Red's item spawner does)
##   "traps": Array of Vector2i  (warp tiles included, see FLAG_WARP)
##   "enemies": Array of Vector2i
##   "monster_house_room": int (-1 if none), "shop": Rect2i (size 0 if none)
##   "kecleon": Vector2i (-1,-1 if none)
##   "rooms": Array of Rect2i, indexed by room index (bounding box of the room's
##            tiles; Rect2i() for an index that was removed by EnsureConnectedGrid)
##   "secondary_kind": "water"|"lava"|"chasm"
##   "layout": int layout actually generated (-1 = forced one-room monster house fallback)
##   "gen_attempts", "spawn_attempts": retry counters, "fixed_room_skipped": bool
class_name DungeonGen
extends RefCounted

@warning_ignore_start("integer_division", "unused_variable", "shadowed_variable")

const W := 56
const H := 32
const N := W * H
const GRID_CELL_LEN := 15
const MAX_ROOM_COUNT := 32

# Output flag bits
const FLAG_IMPASSABLE := 1
const FLAG_UNBREAKABLE := 2048    # TERRAIN_TYPE_UNBREAKABLE (fixed rooms, map border): walkable, can't be dug
const FLAG_JUNCTION := 2
const FLAG_SHOP := 4
const FLAG_MONSTER_HOUSE := 8
const FLAG_STAIRS := 16
const FLAG_MAZE := 32
const FLAG_WARP := 64
const FLAG_ISLAND_MOAT := 128
const FLAG_SS_ROOM := 256
const FLAG_DIVIDER_HALF := 512
const FLAG_KECLEON := 1024

const FIELD_NAMES := [
	"layout", "roomDensity", "tileset", "bgMusic", "weather", "floorConnectivity",
	"enemyDensity", "kecleonShopChance", "monsterHouseChance", "mazeRoomChance",
	"itemStickyChance", "allowDeadEnds", "secondaryStructuresBudget", "roomFlags",
	"unkE", "itemDensity", "trapDensity", "floorNumber", "fixedRoomNumber",
	"numExtraHallways", "buriedItemDensity", "standaloneLakeDensity",
	"visibilityRange", "moneyUpperBound", "kecleonShopLayout",
	"itemlessMonsterHouseChance", "unk1A", "unk1B",
]


## Decodes a 28-byte FloorProperties record (struct order; roomDensity is s8).
static func props_from_bytes(b: PackedByteArray) -> Dictionary:
	var d := {}
	for i in FIELD_NAMES.size():
		var v: int = b[i] if i < b.size() else 0
		d[FIELD_NAMES[i]] = v
	var rd: int = d["roomDensity"]
	if rd >= 128:
		d["roomDensity"] = rd - 256
	return d


static func generate(props: Dictionary, seed_value: int) -> Dictionary:
	var g := _Gen.new()
	return g.run(props, seed_value)


class GridCell:
	var start_x := 0
	var start_y := 0
	var end_x := 0
	var end_y := 0
	var isInvalid := false
	var hasSecondaryStructure := false
	var isRoom := false
	var isConnected := false
	var isKecleonShop := false
	var isMonsterHouse := false
	var unk15 := false
	var isMazeRoom := false
	var hasBeenMerged := false
	var isMerged := false
	var connectedToTop := false
	var connectedToBottom := false
	var connectedToLeft := false
	var connectedToRight := false
	var shouldConnectToTop := false
	var shouldConnectToBottom := false
	var shouldConnectToLeft := false
	var shouldConnectToRight := false
	var flagImperfect := false
	var flagSecondaryStructure := false


class _Gen:
	# --- Terrain flags (Tile.terrainFlags) ---
	const TT_WALL := 0
	const TT_NORMAL := 1
	const TT_SECONDARY := 2
	const TF_CORNER_CUTTABLE := 4
	const TF_JUNCTION := 8
	const TF_IMPASSABLE := 16
	const TF_SHOP := 32
	const TF_MONSTER_HOUSE := 64
	const TF_UNK_7 := 128
	const TF_UNBREAKABLE := 256
	const TF_STAIRS := 512
	# --- Spawn flags ---
	const SP_STAIRS := 1
	const SP_ITEM := 2
	const SP_TRAP := 4
	const SP_MONSTER := 8
	const SP_SPECIAL := 16
	const SP_UNK5 := 32
	const SP_UNK6 := 64

	const CORRIDOR_ROOM := 0xFF
	const ROOM_0xFE := 0xFE

	# enum CardinalDirection
	const CARDINAL_DIR_RIGHT := 0
	const CARDINAL_DIR_UP := 1
	const CARDINAL_DIR_LEFT := 2
	const CARDINAL_DIR_DOWN := 3
	# 8-way direction constants (constants/direction.h)
	const DIRECTION_SOUTH := 0
	const DIRECTION_EAST := 2
	const DIRECTION_NORTH := 4
	const DIRECTION_WEST := 6
	const DIRECTION_MASK_CARDINAL := 6
	const ADJ_X := [0, 1, 1, 1, 0, -1, -1, -1]  # gAdjacentTileOffsets
	const ADJ_Y := [1, 1, 0, -1, -1, -1, 0, 1]

	# GENERATION_CONSTANT_*
	const MERGE_ROOMS_CHANCE := 5
	const NO_IMPERFECTIONS_CHANCE := 60
	const SECONDARY_STRUCTURE_FLAG_CHANCE := 80
	const MONSTER_HOUSE_MAX_ITEMS_TRAPS := 7  # gMonsterHouseMaxItemsTraps
	const MONSTER_HOUSE_MAX_MONS := 12  # gMonsterHouseMaxMons

	const LAYOUT_LARGE := 0
	const LAYOUT_SMALL := 1
	const LAYOUT_ONE_ROOM_MONSTER_HOUSE := 2
	const LAYOUT_OUTER_RING := 3
	const LAYOUT_CROSSROADS := 4
	const LAYOUT_TWO_ROOMS_WITH_MONSTER_HOUSE := 5
	const LAYOUT_LINE := 6
	const LAYOUT_CROSS := 7
	const LAYOUT_LARGE_0x8 := 8
	const LAYOUT_BEETLE := 9
	const LAYOUT_OUTER_ROOMS := 10
	const LAYOUT_MEDIUM := 11

	const FLOOR_SIZE_LARGE := 0
	const FLOOR_SIZE_SMALL := 1
	const FLOOR_SIZE_MEDIUM := 2

	const NUM_TO_GEN_TABLE := [1, 1, 1, 2, 2, 2, 3, 3]  # sNumToGenTable
	# sCornerCardinalNeighborExpectOpen[corner][direction]
	const CORNER_EXPECT_OPEN := [
		[true, false, true, false, false, false, false, false],
		[true, false, false, false, false, false, true, false],
		[false, false, false, false, true, false, true, false],
		[false, false, true, false, true, false, false, false],
	]
	# sKecleonShopItemSpawnChances[layout][y][x] (all 16 layouts are identical in Red)
	const SHOP_ITEM_CHANCES := [[57, 57, 57], [100, 57, 100], [57, 57, 57]]
	# gDungeonWaterType: tilesets 9/35 = "WATER" (secondary becomes type 3 = chasm),
	# 46/48/59/70 = lava, everything else = water.
	const CHASM_TILESETS := [9, 35]
	const LAVA_TILESETS := [46, 48, 59, 70]

	var rng := RandomNumberGenerator.new()
	var fp := {}

	var tf := PackedInt32Array()   # terrainFlags
	var sp := PackedInt32Array()   # spawn flags
	var rm := PackedInt32Array()   # room index
	var maze := PackedByteArray()  # port-only: tiles in maze rooms
	var border_tf := PackedInt32Array()

	# Statics from dungeon_generation.c
	var sInvalidGeneration := false
	var sHasKecleonShop := false
	var sHasMonsterHouse := false
	var sHasMaze := false
	var sSecondSpawn := false
	var sFloorSize := 0
	var sKecleonShopChance := 0
	var sMonsterHouseChance := 0
	var sStairsRoomIndex := 0xFF
	var shop_min_x := -1  # sKecleonShopPosition
	var shop_max_x := -1
	var shop_min_y := -1
	var shop_max_y := -1
	var sSecondaryStructuresBudget := 0
	var sNumRooms := 0
	var sFloorLayout := 0
	var kecleon_mid := Vector2i(-1, -1)  # sKecleonShopMiddlePos
	var unk3A16 := 0  # generation attempt index
	var gUnknown_202F1A8 := false

	# gDungeon fields
	var player_spawn := Vector2i(-1, -1)
	var stairs_spawn := Vector2i(-1, -1)
	var force_monster_house := false
	var monster_house_room := 0xFF
	var layout_used := 0

	func _init() -> void:
		tf.resize(N)
		sp.resize(N)
		rm.resize(N)
		maze.resize(N)
		border_tf.resize(N)
		for x in W:
			for y in H:
				if x == 0 or y == 0 or x == W - 1 or y == H - 1:
					border_tf[y * W + x] = TF_IMPASSABLE

	# ------------------------------------------------------------------ RNG
	func rand_int(cap: int) -> int:  # C: DungeonRandInt
		var r := rng.randi() & 0xFFFF
		return ((r * cap) >> 16) & 0xFFFF

	func rand_range(low: int, high: int) -> int:  # C: DungeonRandRange
		if low == high:
			return low
		elif low < high:
			return rand_int(high - low) + low
		else:
			return rand_int(low - high) + high

	# ------------------------------------------------------------ tile access
	func tt(x: int, y: int) -> int:  # GetTerrainType(GetTile(x, y)); OOB tile is a wall
		if x < 0 or y < 0 or x >= W or y >= H:
			return TT_WALL
		return tf[y * W + x] & 3

	func set_tt(x: int, y: int, t: int) -> void:  # SetTerrainType (OOB writes are discarded)
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		var i := y * W + x
		tf[i] = (tf[i] & ~3) | t

	func room_at(x: int, y: int) -> int:
		if x < 0 or y < 0 or x >= W or y >= H:
			return CORRIDOR_ROOM
		return rm[y * W + x]

	func set_room(x: int, y: int, r: int) -> void:
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		rm[y * W + x] = r & 0xFF

	func flags_at(x: int, y: int) -> int:
		if x < 0 or y < 0 or x >= W or y >= H:
			return 0
		return tf[y * W + x]

	func tf_or(x: int, y: int, f: int) -> void:
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		tf[y * W + x] |= f

	func tf_clear(x: int, y: int, f: int) -> void:
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		tf[y * W + x] &= ~f

	func sp_or(x: int, y: int, f: int) -> void:
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		sp[y * W + x] |= f

	func sp_clear(x: int, y: int, f: int) -> void:
		if x < 0 or y < 0 or x >= W or y >= H:
			return
		sp[y * W + x] &= ~f

	# Fast path for the many "SetTerrainNormal + room = r" rectangle loops.
	func carve_rect(x0: int, y0: int, x1: int, y1: int, room_index: int) -> void:
		var r := room_index & 0xFF
		for y in range(maxi(y0, 0), mini(y1, H)):
			var row := y * W
			for x in range(maxi(x0, 0), mini(x1, W)):
				var i := row + x
				tf[i] = (tf[i] & ~3) | TT_NORMAL
				rm[i] = r

	func oob(x: int, y: int) -> bool:  # C: PosIsOutOfBounds
		return x < 0 or y < 0 or x >= W or y >= H

	func reset_tile(i: int) -> void:  # C: ResetTile
		tf[i] = 0
		sp[i] = 0
		rm[i] = CORRIDOR_ROOM
		maze[i] = 0

	func reset_floor() -> void:  # C: ResetFloor
		tf = border_tf.duplicate()
		sp.fill(0)
		rm.fill(CORRIDOR_ROOM)
		maze.fill(0)
		stairs_spawn = Vector2i(-1, -1)

	func new_grid() -> Array:
		var g := []
		g.resize(GRID_CELL_LEN * GRID_CELL_LEN)
		for i in g.size():
			g[i] = GridCell.new()
		return g

	func p(key: String) -> int:
		return int(fp.get(key, 0))

	# =================================================================
	# C: GenerateFloor
	# =================================================================
	func run(props: Dictionary, seed_value: int) -> Dictionary:
		rng.seed = seed_value
		fp = props
		var secondary_gen := false
		var tileset := p("tileset")

		sHasKecleonShop = false
		sHasMonsterHouse = false
		sHasMaze = false
		gUnknown_202F1A8 = CHASM_TILESETS.has(tileset) if not fp.has("_sec_kind") else str(fp["_sec_kind"]) == "chasm"
		sStairsRoomIndex = 0xFF
		sFloorSize = 0
		sKecleonShopChance = p("kecleonShopChance")
		sMonsterHouseChance = p("monsterHouseChance")
		sSecondSpawn = true
		shop_min_x = -1
		shop_max_x = -1
		shop_min_y = -1
		shop_max_y = -1

		reset_floor()
		sSecondaryStructuresBudget = p("secondaryStructuresBudget")

		var fx: Dictionary = fp.get("_fixed", {})
		fixed_floorwide = false
		var spawn_attempts := 0
		var gen_attempts := 0
		while spawn_attempts < 10:
			player_spawn = Vector2i(-1, -1)
			stairs_spawn = Vector2i(-1, -1)
			gen_attempts = 0
			while gen_attempts < 10:
				unk3A16 = gen_attempts
				if gen_attempts > 0:
					sSecondaryStructuresBudget = 0
				sInvalidGeneration = false
				kecleon_mid = Vector2i(-1, -1)
				reset_floor()
				player_spawn = Vector2i(-1, -1)
				force_monster_house = false
				# C: ProcessFixedRoom - floor-wide fixed rooms finish generation here;
				# smaller ones are embedded in a grid floor and generation carries on.
				var fixed_handled := false
				if p("fixedRoomNumber") != 0 and not fx.is_empty():
					fixed_handled = true
					if process_fixed_room(fx):
						fixed_floorwide = true
						break
				if not fixed_handled:
					var layout := p("layout") & 0xFF
					var grid_size_x := 0
					var grid_size_y := 0
					var attempts := 32
					while true:
						if layout != LAYOUT_LARGE_0x8:
							grid_size_x = rand_range(2, 9)
							grid_size_y = rand_range(2, 8)
						else:
							grid_size_x = rand_range(2, 5)
							grid_size_y = rand_range(2, 4)
						if grid_size_x <= 6 and grid_size_y <= 4:
							break
						attempts -= 1
						if attempts == 0:
							grid_size_x = 4
							grid_size_y = 4
							break
					if W / grid_size_x < 8:
						grid_size_x = 1
					if H / grid_size_y < 8:
						grid_size_y = 1

					force_monster_house = false
					monster_house_room = 0xFF
					sFloorLayout = layout
					layout_used = layout % 16
					match layout % 16:
						LAYOUT_SMALL:
							grid_size_x = 4
							grid_size_y = rand_int(2) + 2
							sFloorSize = FLOOR_SIZE_SMALL
							generate_standard_floor(grid_size_x, grid_size_y)
							secondary_gen = true
						LAYOUT_MEDIUM:
							grid_size_x = 4
							grid_size_y = rand_int(2) + 2
							sFloorSize = FLOOR_SIZE_MEDIUM
							generate_standard_floor(grid_size_x, grid_size_y)
							secondary_gen = true
						LAYOUT_ONE_ROOM_MONSTER_HOUSE:
							generate_one_room_monster_house_floor()
							force_monster_house = true
						LAYOUT_OUTER_RING:
							generate_outer_ring_floor()
							secondary_gen = true
						LAYOUT_CROSSROADS:
							generate_crossroads_floor()
							secondary_gen = true
						LAYOUT_TWO_ROOMS_WITH_MONSTER_HOUSE:
							generate_two_rooms_with_monster_house_floor()
							force_monster_house = true
						LAYOUT_LINE:
							generate_line_floor()
							secondary_gen = true
						LAYOUT_CROSS:
							generate_cross_floor()
						LAYOUT_BEETLE:
							generate_beetle_floor()
						LAYOUT_OUTER_ROOMS:
							generate_outer_rooms_floor(grid_size_x, grid_size_y)
							secondary_gen = true
						_:  # LAYOUT_LARGE, LAYOUT_LARGE_0x8, unused layouts
							generate_standard_floor(grid_size_x, grid_size_y)
							secondary_gen = true

				reset_inner_boundary_tile_rows()
				ensure_impassable_tiles_are_walls()

				if not sInvalidGeneration:
					# Need at least 2 rooms and 30 room tiles
					var rooms_seen := PackedByteArray()
					rooms_seen.resize(64)
					var room_tiles := 0
					for i in N:
						if (tf[i] & 3) == TT_NORMAL and rm[i] <= 240:
							room_tiles += 1
							if rm[i] < 64:
								rooms_seen[rm[i]] = 1
					var num_rooms := 0
					for r in 64:
						if rooms_seen[r] != 0:
							num_rooms += 1
					if room_tiles >= 30 and num_rooms >= 2:
						break
				gen_attempts += 1

			if gen_attempts == 10 and not fixed_floorwide:
				kecleon_mid = Vector2i(-1, -1)
				generate_one_room_monster_house_floor()
				force_monster_house = true
				layout_used = -1

			finalize_junctions()
			if secondary_gen:
				generate_secondary_terrain_formations(1)  # ROOM_FLAG_ALLOW_SECONDARY_TERRAIN

			var empty_mh := rand_int(100) < p("itemlessMonsterHouseChance")
			spawn_non_enemies(empty_mh)
			spawn_enemies(empty_mh)
			resolve_invalid_spawns()
			if player_spawn.x != -1 and player_spawn.y != -1:
				if fixed_floorwide:  # GetFloorType() == FLOOR_TYPE_FIXED: the room is already valid
					break
				if stairs_spawn.x != -1 and stairs_spawn.y != -1 and stairs_always_reachable(stairs_spawn.x, stairs_spawn.y):
					break
			spawn_attempts += 1

		if spawn_attempts == 10:
			kecleon_mid = Vector2i(-1, -1)
			reset_floor()
			generate_one_room_monster_house_floor()
			force_monster_house = true
			layout_used = -1
			finalize_junctions()
			spawn_non_enemies(false)
			spawn_enemies(false)
			resolve_invalid_spawns()

		# Kecleon (sub_806C330 at sKecleonShopMiddlePos) is placed by the game layer.
		if shop_min_x >= 0:
			kecleon_shop_finalize()

		# Record the island-moat marker before sub_804B534 clears it.
		var moat := PackedByteArray()
		moat.resize(N)
		for i in N:
			if (tf[i] & 3) == TT_SECONDARY and (tf[i] & TF_CORNER_CUTTABLE) != 0:
				moat[i] = 1
		sub_804B534(0, 0, W, H)
		if gUnknown_202F1A8:
			sub_804FC74()

		return build_output(moat, gen_attempts, spawn_attempts, tileset)

	# C: sub_804B534 - mark hallway crossings as natural junctions, clear corner-cut flag
	func sub_804B534(x_start: int, y_start: int, max_x: int, max_y: int) -> void:
		for x in range(x_start, max_x):
			for y in range(y_start, max_y):
				var cnt := 0
				var i := y * W + x
				tf[i] &= ~TF_CORNER_CUTTABLE
				if rm[i] == CORRIDOR_ROOM and (tf[i] & 3) == TT_NORMAL:
					if x > 0 and tt(x - 1, y) == TT_NORMAL:
						cnt += 1
					if y > 0 and tt(x, y - 1) == TT_NORMAL:
						cnt += 1
					if x < W - 2 and tt(x + 1, y) == TT_NORMAL:
						cnt += 1
					# BUG (kept): Red checks x instead of y here
					if x < H - 2 and tt(x, y + 1) == TT_NORMAL:
						cnt += 1
					if cnt > 2:
						tf[i] |= TF_JUNCTION

	# C: sub_804FC74 - secondary terrain of "WATER" tilesets becomes NORMAL|SECONDARY (chasm)
	func sub_804FC74() -> void:
		for i in N:
			if (tf[i] & 3) == TT_SECONDARY:
				tf[i] = (tf[i] & ~3) | 3

	# =================================================================
	# Layouts
	# =================================================================
	# C: GenerateStandardFloor
	func generate_standard_floor(gx: int, gy: int) -> void:
		var list_x := PackedInt32Array()
		var list_y := PackedInt32Array()
		list_x.resize(GRID_CELL_LEN)
		list_y.resize(GRID_CELL_LEN)
		get_grid_positions(list_x, list_y, gx, gy)
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		assign_rooms(grid, gx, gy, p("roomDensity"))
		create_rooms_and_anchors(grid, gx, gy, list_x, list_y, p("roomFlags"))
		assign_random_grid_cell_connections(grid, gx, gy)
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, false)
		ensure_connected_grid(grid, gx, gy, list_x, list_y)
		generate_maze_room(grid, gx, gy, p("mazeRoomChance"))
		generate_kecleon_shop(grid, gx, gy, sKecleonShopChance)
		generate_monster_house(grid, gx, gy, sMonsterHouseChance)
		generate_extra_hallways(grid, gx, gy, p("numExtraHallways"))
		generate_room_imperfections(grid, gx, gy)
		generate_secondary_structures(grid, gx, gy)

	# Shared by OuterRing / Crossroads: carve rooms (5..range) or anchors per cell.
	func _carve_fixed_grid(grid: Array, gx: int, gy: int, list_x: PackedInt32Array, list_y: PackedInt32Array, skip_invalid: bool) -> void:
		var curr_room := 0
		for y in gy:
			for x in gx:
				var c: GridCell = grid[x * GRID_CELL_LEN + y]
				if skip_invalid and c.isInvalid:
					continue
				if c.isRoom:
					var min_x := list_x[x] + 2
					var min_y := list_y[y] + 2
					var range_x := list_x[x + 1] - list_x[x] - 3
					var range_y := list_y[y + 1] - list_y[y] - 3
					var room_size_x := rand_range(5, range_x)
					var room_size_y := rand_range(4, range_y)
					var start_x := rand_int(range_x - room_size_x) + min_x
					var start_y := rand_int(range_y - room_size_y) + min_y
					var end_x := start_x + room_size_x
					var end_y := start_y + room_size_y
					c.start_x = start_x
					c.end_x = end_x
					c.start_y = start_y
					c.end_y = end_y
					carve_rect(start_x, start_y, end_x, end_y, curr_room)
					curr_room += 1
				else:
					var min_x := list_x[x] + 1
					var min_y := list_y[y] + 1
					var range_x := list_x[x + 1] - list_x[x] - 3
					var range_y := list_y[y + 1] - list_y[y] - 3
					var start_x := rand_range(min_x, min_x + range_x)
					var start_y := rand_range(min_y, min_y + range_y)
					c.start_x = start_x
					c.end_x = start_x + 1
					c.start_y = start_y
					c.end_y = start_y + 1
					set_tt(start_x, start_y, TT_NORMAL)
					set_room(start_x, start_y, CORRIDOR_ROOM)

	func cell(grid: Array, x: int, y: int) -> GridCell:
		return grid[x * GRID_CELL_LEN + y]

	# C: GenerateOuterRingFloor
	func generate_outer_ring_floor() -> void:
		var gx := 6
		var gy := 4
		var list_x := PackedInt32Array([0, 5, 16, 28, 39, 51, 56, 0, 0, 0, 0, 0, 0, 0, 0])
		var list_y := PackedInt32Array([2, 7, 16, 25, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		for x in gx:
			cell(grid, x, 0).isRoom = false
			cell(grid, x, gy - 1).isRoom = false
		for y in gy:
			cell(grid, 0, y).isRoom = false
			cell(grid, gx - 1, y).isRoom = false
		for x in range(1, gx - 1):
			for y in range(1, gy - 1):
				cell(grid, x, y).isRoom = true
		_carve_fixed_grid(grid, gx, gy, list_x, list_y, false)
		for x in 6:
			if x < 5:
				cell(grid, x, 0).connectedToRight = true
				cell(grid, x, 3).connectedToRight = true
			if x > 0:
				cell(grid, x, 0).connectedToLeft = true
				cell(grid, x, 3).connectedToLeft = true
		for y in 4:
			if y < 3:
				cell(grid, 0, y).connectedToBottom = true
				cell(grid, 5, y).connectedToBottom = true
			if y > 0:
				cell(grid, 0, y).connectedToTop = true
				cell(grid, 5, y).connectedToTop = true
		assign_random_grid_cell_connections(grid, gx, gy)
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, false)
		ensure_connected_grid(grid, gx, gy, list_x, list_y)
		generate_kecleon_shop(grid, gx, gy, sKecleonShopChance)
		generate_monster_house(grid, gx, gy, sMonsterHouseChance)
		generate_extra_hallways(grid, gx, gy, p("numExtraHallways"))
		generate_room_imperfections(grid, gx, gy)

	# C: GenerateCrossroadsFloor
	func generate_crossroads_floor() -> void:
		var gx := 5
		var gy := 4
		var list_x := PackedInt32Array([0, 11, 22, 33, 44, 56, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var list_y := PackedInt32Array([1, 9, 16, 23, 31, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		for x in gx:
			cell(grid, x, 0).isRoom = true
			cell(grid, x, gy - 1).isRoom = true
		for y in gy:
			cell(grid, 0, y).isRoom = true
			cell(grid, gx - 1, y).isRoom = true
		for x in range(1, gx - 1):
			for y in range(1, gy - 1):
				cell(grid, x, y).isRoom = false
		cell(grid, 0, 0).isInvalid = true
		cell(grid, 4, 0).isInvalid = true
		cell(grid, 0, 3).isInvalid = true
		cell(grid, 4, 3).isInvalid = true
		_carve_fixed_grid(grid, gx, gy, list_x, list_y, true)
		for x in range(1, 4):
			for y in range(0, 3):
				cell(grid, x, y).connectedToBottom = true
				cell(grid, x, y + 1).connectedToTop = true
		for y in range(1, 3):
			for x in range(0, 4):
				cell(grid, x, y).connectedToRight = true
				cell(grid, x + 1, y).connectedToLeft = true
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, true)
		ensure_connected_grid(grid, gx, gy, list_x, list_y)
		generate_kecleon_shop(grid, gx, gy, sKecleonShopChance)
		generate_monster_house(grid, gx, gy, sMonsterHouseChance)
		generate_extra_hallways(grid, gx, gy, p("numExtraHallways"))
		generate_room_imperfections(grid, gx, gy)

	# C: GenerateLineFloor
	func generate_line_floor() -> void:
		var list_x := PackedInt32Array([0, 11, 22, 33, 44, 56, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var list_y := PackedInt32Array([4, 15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var gx := 5
		var gy := 1
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		assign_rooms(grid, gx, gy, p("roomDensity"))
		create_rooms_and_anchors(grid, gx, gy, list_x, list_y, p("roomFlags"))
		assign_random_grid_cell_connections(grid, gx, gy)
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, true)
		ensure_connected_grid(grid, gx, gy, list_x, list_y)
		generate_kecleon_shop(grid, gx, gy, sKecleonShopChance)
		generate_monster_house(grid, gx, gy, sMonsterHouseChance)
		generate_extra_hallways(grid, gx, gy, p("numExtraHallways"))
		generate_room_imperfections(grid, gx, gy)

	# C: GenerateCrossFloor
	func generate_cross_floor() -> void:
		var list_x := PackedInt32Array([11, 22, 33, 44, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var list_y := PackedInt32Array([2, 11, 20, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var gx := 3
		var gy := 3
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		for x in gx:
			for y in gy:
				cell(grid, x, y).isRoom = true
		cell(grid, 0, 0).isInvalid = true
		cell(grid, 2, 0).isInvalid = true
		cell(grid, 0, 2).isInvalid = true
		cell(grid, 2, 2).isInvalid = true
		create_rooms_and_anchors(grid, gx, gy, list_x, list_y, p("roomFlags"))
		cell(grid, 0, 1).connectedToRight = true
		cell(grid, 1, 1).connectedToLeft = true
		cell(grid, 1, 1).connectedToRight = true
		cell(grid, 2, 1).connectedToLeft = true
		cell(grid, 1, 0).connectedToBottom = true
		cell(grid, 1, 1).connectedToTop = true
		cell(grid, 1, 1).connectedToBottom = true
		cell(grid, 1, 2).connectedToTop = true
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, true)
		ensure_connected_grid(grid, gx, gy, list_x, list_y)
		generate_kecleon_shop(grid, gx, gy, sKecleonShopChance)
		generate_monster_house(grid, gx, gy, sMonsterHouseChance)
		generate_extra_hallways(grid, gx, gy, p("numExtraHallways"))
		generate_room_imperfections(grid, gx, gy)

	# C: GenerateBeetleFloor
	func generate_beetle_floor() -> void:
		var list_x := PackedInt32Array([5, 15, 35, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var list_y := PackedInt32Array([2, 11, 20, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var gx := 3
		var gy := 3
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		for x in gx:
			for y in gy:
				cell(grid, x, y).isRoom = true
		create_rooms_and_anchors(grid, gx, gy, list_x, list_y, p("roomFlags"))
		for y in 3:
			cell(grid, 0, y).connectedToRight = true
			cell(grid, 1, y).connectedToLeft = true
			cell(grid, 1, y).connectedToRight = true
			cell(grid, 2, y).connectedToLeft = true
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, true)
		merge_rooms_vertically(1, 0, 1, grid)
		merge_rooms_vertically(1, 0, 2, grid)
		ensure_connected_grid(grid, gx, gy, list_x, list_y)
		generate_kecleon_shop(grid, gx, gy, sKecleonShopChance)
		generate_monster_house(grid, gx, gy, sMonsterHouseChance)
		generate_extra_hallways(grid, gx, gy, p("numExtraHallways"))
		generate_room_imperfections(grid, gx, gy)

	# C: MergeRoomsVertically
	func merge_rooms_vertically(room_x: int, room_y1: int, room_dy: int, grid: Array) -> void:
		var a := cell(grid, room_x, room_y1)
		var b := cell(grid, room_x, room_y1 + room_dy)
		var x_start: int = min(a.start_x, b.start_x)
		var y_start := a.start_y
		var x_end: int = max(a.end_x, b.end_x)
		var y_end := b.end_y
		var room_id := room_at(a.start_x, a.start_y)
		carve_rect(x_start, y_start, x_end, y_end, room_id)
		a.start_x = x_start
		a.end_x = x_end
		a.start_y = y_start
		a.end_y = y_end
		b.isMerged = true
		a.isMerged = true
		b.isConnected = false
		b.hasBeenMerged = true

	# C: GenerateOuterRoomsFloor
	func generate_outer_rooms_floor(gx: int, gy: int) -> void:
		var list_x := PackedInt32Array()
		var list_y := PackedInt32Array()
		list_x.resize(GRID_CELL_LEN)
		list_y.resize(GRID_CELL_LEN)
		get_grid_positions(list_x, list_y, gx, gy)
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		for x in gx:
			for y in gy:
				cell(grid, x, y).isRoom = true
		for x in range(1, gx - 1):
			for y in range(1, gy - 1):
				cell(grid, x, y).isInvalid = true
		create_rooms_and_anchors(grid, gx, gy, list_x, list_y, p("roomFlags"))
		# Original (buggy for gridSizeX <= 2) connection logic, kept as-is.
		for x in range(0, gx - 1):
			if x != 0:
				cell(grid, x, 0).connectedToRight = true
				cell(grid, x, gy - 1).connectedToRight = true
			if x < gx - 2:
				cell(grid, x + 1, 0).connectedToLeft = true
				cell(grid, x + 1, gy - 1).connectedToLeft = true
		for y in range(0, gy - 1):
			if y != 0:
				cell(grid, 0, y).connectedToTop = true
				cell(grid, gx - 1, y).connectedToTop = true
			if y < gy - 2:
				cell(grid, 0, y).connectedToBottom = true
				cell(grid, gx - 1, y).connectedToBottom = true
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, false)
		ensure_connected_grid(grid, gx, gy, list_x, list_y)
		generate_maze_room(grid, gx, gy, p("mazeRoomChance"))
		generate_kecleon_shop(grid, gx, gy, sKecleonShopChance)
		generate_monster_house(grid, gx, gy, sMonsterHouseChance)
		generate_extra_hallways(grid, gx, gy, p("numExtraHallways"))
		generate_room_imperfections(grid, gx, gy)
		generate_secondary_structures(grid, gx, gy)

	# C: GenerateOneRoomMonsterHouseFloor
	func generate_one_room_monster_house_floor() -> void:
		var grid := new_grid()
		init_dungeon_grid(grid, 1, 1)
		var c := cell(grid, 0, 0)
		c.start_x = 2
		c.end_x = W - 2
		c.start_y = 2
		c.end_y = H - 2
		c.isRoom = true
		c.isConnected = true
		c.isInvalid = false
		carve_rect(c.start_x, c.start_y, c.end_x, c.end_y, 0)
		generate_monster_house(grid, 1, 1, 999)

	# C: GenerateTwoRoomsWithMonsterHouseFloor
	func generate_two_rooms_with_monster_house_floor() -> void:
		var list_x := PackedInt32Array([2, 28, 54, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var list_y := PackedInt32Array([2, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		var gx := 2
		var gy := 1
		var curr_room := 0
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		for y in gy:
			for x in gx:
				var min_x := list_x[x] + 1
				var min_y := list_y[y] + 1
				var range_x := list_x[x + 1] - list_x[x] - 3
				var range_y := list_y[y + 1] - list_y[y] - 3
				var room_size_x := rand_range(10, range_x)
				var room_size_y := rand_range(16, range_y)
				var start_x := rand_int(range_x - room_size_x) + min_x
				var start_y := rand_int(range_y - room_size_y) + min_y
				var end_x := start_x + room_size_x
				var end_y := start_y + room_size_y
				var c := cell(grid, x, y)
				c.isRoom = true
				c.start_x = start_x
				c.end_x = end_x
				c.start_y = start_y
				c.end_y = end_y
				carve_rect(start_x, start_y, end_x, end_y, curr_room)
				curr_room += 1
		cell(grid, 0, 0).connectedToRight = true
		cell(grid, 1, 0).connectedToLeft = true
		create_grid_cell_connections(grid, gx, gy, list_x, list_y, false)
		generate_monster_house(grid, gx, gy, 999)

	# =================================================================
	# Grid helpers
	# =================================================================
	# C: GenerateExtraHallways
	func generate_extra_hallways(grid: Array, gx: int, gy: int, num_extra: int) -> void:
		if num_extra == 0:
			return
		for i in num_extra:
			var x := rand_int(gx)
			var y := rand_int(gy)
			var c := cell(grid, x, y)
			if not c.isRoom or not c.isConnected or c.isInvalid or c.isMazeRoom:
				continue
			var cur_x := rand_range(c.start_x, c.end_x)
			var cur_y := rand_range(c.start_y, c.end_y)
			var direction := rand_int(4) * 2
			for j in 3:
				if direction == DIRECTION_SOUTH and y >= gy - 1:
					direction = DIRECTION_EAST
				if direction == DIRECTION_EAST and x >= gx - 1:
					direction = DIRECTION_NORTH
				if direction == DIRECTION_NORTH and y <= 0:
					direction = DIRECTION_WEST
				if direction == DIRECTION_WEST and x <= 0:
					direction = DIRECTION_SOUTH
			var room_id := room_at(cur_x, cur_y)
			while room_id == room_at(cur_x, cur_y):
				cur_x += ADJ_X[direction]
				cur_y += ADJ_Y[direction]
			while tt(cur_x, cur_y) == TT_NORMAL:
				cur_x += ADJ_X[direction]
				cur_y += ADJ_Y[direction]
			if tt(cur_x, cur_y) == TT_SECONDARY:
				continue
			# Must be at least 2 away from the map border
			if cur_x - 2 < 0 or cur_x + 2 >= W or cur_y - 2 < 0 or cur_y + 2 >= H:
				continue
			var d1: int = (direction + 2) & DIRECTION_MASK_CARDINAL
			var d2: int = (direction - 2) & DIRECTION_MASK_CARDINAL
			if tt(cur_x + ADJ_X[d1], cur_y + ADJ_Y[d1]) == TT_NORMAL:
				continue
			if tt(cur_x + ADJ_X[d2], cur_y + ADJ_Y[d2]) == TT_NORMAL:
				continue
			var steps := rand_int(3) + 3
			while true:
				if cur_x <= 1 or cur_y <= 1 or cur_x >= W - 1 or cur_y >= H - 1:
					break
				if tt(cur_x, cur_y) == TT_NORMAL:
					break
				if flags_at(cur_x, cur_y) & TF_IMPASSABLE:
					break
				var will_not_make_square := true
				var r := tt(cur_x + 1, cur_y) == TT_NORMAL
				var l := tt(cur_x - 1, cur_y) == TT_NORMAL
				var dn := tt(cur_x, cur_y + 1) == TT_NORMAL
				var up := tt(cur_x, cur_y - 1) == TT_NORMAL
				if r and tt(cur_x + 1, cur_y + 1) == TT_NORMAL and dn:
					will_not_make_square = false
				if r and tt(cur_x + 1, cur_y - 1) == TT_NORMAL and up:
					will_not_make_square = false
				if l and tt(cur_x - 1, cur_y + 1) == TT_NORMAL and dn:
					will_not_make_square = false
				if l and tt(cur_x - 1, cur_y - 1) == TT_NORMAL and up:
					will_not_make_square = false
				if will_not_make_square:
					set_tt(cur_x, cur_y, TT_NORMAL)
				d1 = (direction + 2) & DIRECTION_MASK_CARDINAL
				d2 = (direction - 2) & DIRECTION_MASK_CARDINAL
				if tt(cur_x + ADJ_X[d1], cur_y + ADJ_Y[d1]) == TT_NORMAL:
					break
				if tt(cur_x + ADJ_X[d2], cur_y + ADJ_Y[d2]) == TT_NORMAL:
					break
				steps -= 1
				if steps == 0:
					steps = rand_int(3) + 3
					if rand_int(100) < 50:
						direction += 2
					else:
						direction -= 2
					direction &= DIRECTION_MASK_CARDINAL
					if cur_x >= 32 and sFloorSize == FLOOR_SIZE_SMALL and direction == DIRECTION_EAST:
						break
					if cur_x >= 48 and sFloorSize == FLOOR_SIZE_MEDIUM and direction == DIRECTION_EAST:
						break
				cur_x += ADJ_X[direction]
				cur_y += ADJ_Y[direction]

	# C: GetGridPositions
	func get_grid_positions(list_x: PackedInt32Array, list_y: PackedInt32Array, gx: int, gy: int) -> void:
		var s := 0
		for i in gx:
			list_x[i] = s
			s += W / gx
		list_x[gx] = s
		s = 0
		for i in gy:
			list_y[i] = s
			s += H / gy
		list_y[gy] = s

	# C: InitDungeonGrid
	func init_dungeon_grid(grid: Array, gx: int, gy: int) -> void:
		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if sFloorSize == 1 and x >= gx / 2:
					c.isInvalid = true
				elif sFloorSize == 2 and x >= (gx * 3) / 4:
					c.isInvalid = true
				else:
					c.isInvalid = false
				c.isRoom = true
				c.isConnected = false
				c.unk15 = false
				c.isMonsterHouse = false
				c.isKecleonShop = false
				c.connectedToRight = false
				c.connectedToLeft = false
				c.connectedToBottom = false
				c.connectedToTop = false
				c.shouldConnectToRight = false
				c.shouldConnectToLeft = false
				c.shouldConnectToBottom = false
				c.shouldConnectToTop = false
				c.hasSecondaryStructure = false
				c.hasBeenMerged = false
				c.isMazeRoom = false
				c.isMerged = false
				c.flagImperfect = false
				c.flagSecondaryStructure = false

	# C: AssignRooms
	func assign_rooms(grid: Array, gx: int, gy: int, rooms_number: int) -> void:
		var bits := PackedByteArray()
		bits.resize(256)
		var i := rand_int(3)
		if rooms_number < 0:
			rooms_number = -rooms_number
		else:
			rooms_number += i
		for k in min(rooms_number, 256):
			bits[k] = 1
		var max_rooms := gx * gy
		for n in 64:
			var a := rand_int(max_rooms)
			var b := rand_int(max_rooms)
			var t := bits[a]
			bits[a] = bits[b]
			bits[b] = t
		i = 0
		sNumRooms = 0
		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if c.isInvalid:
					continue
				if sNumRooms >= MAX_ROOM_COUNT:
					c.isRoom = false
				if bits[i] != 0:
					c.isRoom = true
					sNumRooms += 1
					if gx % 2 != 0 and x == (gx - 1) / 2 and y == 1:
						c.isRoom = false
				else:
					c.isRoom = false
				i += 1
		if sNumRooms >= 2:
			return
		for attempts in 200:
			var enough := false
			for x in gx:
				for y in gy:
					var c := cell(grid, x, y)
					if c.isInvalid:
						continue
					if rand_int(100) < 60:
						c.isRoom = true
						enough = true
						break
				if enough:
					break
			if enough:
				break
		sSecondSpawn = false

	# C: CreateRoomsAndAnchors
	func create_rooms_and_anchors(grid: Array, gx: int, gy: int, list_x: PackedInt32Array, list_y: PackedInt32Array, room_flags: int) -> void:
		var room_number := 0
		for y in gy:
			for x in gx:
				var min_x := list_x[x] + 2
				var min_y := list_y[y] + 2
				var range_x := list_x[x + 1] - list_x[x] - 4
				var range_y := list_y[y + 1] - list_y[y] - 3
				var c := cell(grid, x, y)
				if c.isInvalid:
					continue
				if c.isRoom:
					var room_size_x := rand_range(5, range_x)
					var room_size_y := rand_range(4, range_y)
					if (room_size_x | 1) < range_x:
						room_size_x |= 1
					if (room_size_y | 1) < range_y:
						room_size_y |= 1
					if room_size_x > (room_size_y * 3) / 2:
						room_size_x = (room_size_y * 3) / 2
					if room_size_y > (room_size_x * 3) / 2:
						room_size_y = (room_size_x * 3) / 2
					var start_x := rand_int(range_x - room_size_x) + min_x
					var start_y := rand_int(range_y - room_size_y) + min_y
					var end_x := start_x + room_size_x
					var end_y := start_y + room_size_y
					c.start_x = start_x
					c.end_x = end_x
					c.start_y = start_y
					c.end_y = end_y
					carve_rect(start_x, start_y, end_x, end_y, room_number)
					var flag_imperfect := true
					var flag_secondary := rand_int(100) < SECONDARY_STRUCTURE_FLAG_CHANCE
					if sSecondaryStructuresBudget == 0:
						flag_secondary = false
					if not (room_flags & 4):  # ROOM_FLAG_ALLOW_IMPERFECTIONS
						flag_imperfect = false
					if flag_imperfect and flag_secondary:
						if rand_int(100) < 50:
							flag_imperfect = false
						else:
							flag_secondary = false
					if flag_imperfect:
						c.flagImperfect = true
					if flag_secondary:
						c.flagSecondaryStructure = true
					room_number += 1
				else:
					var ux1 := 2
					var ux2 := 4
					var uy1 := 2
					var uy2 := 4
					if x == 0:
						ux1 = 1
					if y == 0:
						uy1 = 1
					if x == gx - 1:
						ux2 = 2
					if y == gy - 1:
						uy2 = 2
					var pt_x := rand_range(min_x + ux1, min_x + range_x - ux2)
					var pt_y := rand_range(min_y + uy1, min_y + range_y - uy2)
					c.start_x = pt_x
					c.end_x = pt_x + 1
					c.start_y = pt_y
					c.end_y = pt_y + 1
					set_tt(pt_x, pt_y, TT_NORMAL)
					set_room(pt_x, pt_y, ROOM_0xFE)

	# C: GenerateSecondaryStructures
	func generate_secondary_structures(grid: Array, gx: int, gy: int) -> void:
		for y in gy:
			for x in gx:
				var c := cell(grid, x, y)
				if not c.isInvalid and not c.isMonsterHouse and not c.isMerged and c.isRoom \
						and not c.flagImperfect and c.flagSecondaryStructure:
					generate_secondary_structure(c)

	# C: AssignRandomGridCellConnections
	func assign_random_grid_cell_connections(grid: Array, gx: int, gy: int) -> void:
		var cx := rand_int(gx)
		var cy := rand_int(gy)
		assign_grid_cell_connections(grid, gx, gy, cx, cy)

	# C: AssignGridCellConnections
	func assign_grid_cell_connections(grid: Array, gx: int, gy: int, cursor_x: int, cursor_y: int) -> void:
		var x := cursor_x
		var y := cursor_y
		var floor_connectivity := p("floorConnectivity")
		var cdir := rand_int(4)
		for i in floor_connectivity:
			var test := rand_int(8)
			var new_dir := rand_int(4)
			if test < 4:
				cdir = new_dir
			while true:
				var ok := false
				match cdir & 3:
					CARDINAL_DIR_RIGHT:
						if x < gx - 1: ok = true
						else: cdir += 1
					CARDINAL_DIR_UP:
						if y > 0: ok = true
						else: cdir += 1
					CARDINAL_DIR_LEFT:
						if x > 0: ok = true
						else: cdir += 1
					CARDINAL_DIR_DOWN:
						if y < gy - 1: ok = true
						else: cdir += 1
				if ok:
					break
			match cdir & 3:
				CARDINAL_DIR_RIGHT:
					if not cell(grid, x + 1, y).isInvalid:
						cell(grid, x, y).connectedToRight = true
						cell(grid, x + 1, y).connectedToLeft = true
						x += 1
				CARDINAL_DIR_UP:
					if not cell(grid, x, y - 1).isInvalid:
						cell(grid, x, y).connectedToTop = true
						cell(grid, x, y - 1).connectedToBottom = true
						y -= 1
				CARDINAL_DIR_LEFT:
					if not cell(grid, x - 1, y).isInvalid:
						cell(grid, x, y).connectedToLeft = true
						cell(grid, x - 1, y).connectedToRight = true
						x -= 1
				CARDINAL_DIR_DOWN:
					if not cell(grid, x, y + 1).isInvalid:
						cell(grid, x, y).connectedToBottom = true
						cell(grid, x, y + 1).connectedToTop = true
						y += 1

		if p("allowDeadEnds") != 0:
			return

		while true:
			var more := false
			for xx in gx:
				for yy in gy:
					var c := cell(grid, xx, yy)
					if c.isInvalid:
						continue
					if c.isRoom:
						continue
					var cnt := 0
					if c.connectedToTop: cnt += 1
					if c.connectedToBottom: cnt += 1
					if c.connectedToLeft: cnt += 1
					if c.connectedToRight: cnt += 1
					if cnt != 1:
						continue
					cdir = rand_int(4)
					var ok := false
					for k in 8:
						match cdir & 3:
							CARDINAL_DIR_RIGHT:
								if xx < gx - 1 and not c.connectedToRight: ok = true
								else: cdir += 1
							CARDINAL_DIR_UP:
								if yy > 0 and not c.connectedToTop: ok = true
								else: cdir += 1
							CARDINAL_DIR_LEFT:
								if xx > 0 and not c.connectedToLeft: ok = true
								else: cdir += 1
							CARDINAL_DIR_DOWN:
								if yy < gy - 1 and not c.connectedToBottom: ok = true
								else: cdir += 1
						if ok:
							break
					if not ok:
						continue
					# BUG (kept): validity is always checked on the cell to the right.
					# Cells outside the grid are zero-initialised here (garbage in Red).
					var right_valid := not cell(grid, xx + 1, yy).isInvalid
					match cdir & 3:
						CARDINAL_DIR_RIGHT:
							if right_valid:
								c.connectedToRight = true
								cell(grid, xx + 1, yy).connectedToLeft = true
								more = true
						CARDINAL_DIR_UP:
							if right_valid:
								c.connectedToTop = true
								cell(grid, xx, yy - 1).connectedToBottom = true
								more = true
						CARDINAL_DIR_LEFT:
							if right_valid:
								c.connectedToLeft = true
								cell(grid, xx - 1, yy).connectedToRight = true
								more = true
						CARDINAL_DIR_DOWN:
							if right_valid:
								c.connectedToBottom = true
								cell(grid, xx, yy + 1).connectedToTop = true
								more = true
			if not more:
				break

	# C: CreateGridCellConnections
	func create_grid_cell_connections(grid: Array, gx: int, gy: int, list_x: PackedInt32Array, list_y: PackedInt32Array, disable_room_merging: bool) -> void:
		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if c.isInvalid:
					c.shouldConnectToTop = false
					c.shouldConnectToBottom = false
					c.shouldConnectToLeft = false
					c.shouldConnectToRight = false
				else:
					if x <= 0:
						c.connectedToLeft = false
					if y <= 0:
						c.connectedToTop = false
					if x >= gx - 1:
						c.connectedToRight = false
					if y >= gy - 1:
						c.connectedToBottom = false
					c.shouldConnectToTop = c.connectedToTop
					c.shouldConnectToBottom = c.connectedToBottom
					c.shouldConnectToLeft = c.connectedToLeft
					c.shouldConnectToRight = c.connectedToRight

		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if c.isInvalid:
					continue
				var pt_x: int
				var pt_y: int
				if c.isRoom:
					pt_x = rand_range(c.start_x + 1, c.end_x - 1)
					pt_y = rand_range(c.start_y + 1, c.end_y - 1)
				else:
					pt_x = c.start_x
					pt_y = c.start_y

				if c.shouldConnectToTop:
					var o := cell(grid, x, y - 1)
					if not o.isInvalid:
						var pt2_x: int
						if o.isRoom:
							pt2_x = rand_range(o.start_x + 1, o.end_x - 1)
						else:
							pt2_x = o.start_x
						create_hallway(pt_x, c.start_y, pt2_x, o.end_y - 1, true, list_x[x], list_y[y])
					c.shouldConnectToTop = false
					o.shouldConnectToBottom = false
					c.isConnected = true
					o.isConnected = true

				if c.shouldConnectToBottom:
					var o := cell(grid, x, y + 1)
					if not o.isInvalid:
						var pt2_x: int
						if o.isRoom:
							pt2_x = rand_range(o.start_x + 1, o.end_x - 1)
						else:
							pt2_x = o.start_x
						create_hallway(pt_x, c.end_y - 1, pt2_x, o.start_y, true, list_x[x], list_y[y + 1] - 1)
					c.shouldConnectToBottom = false
					o.shouldConnectToTop = false
					c.isConnected = true
					o.isConnected = true

				if c.shouldConnectToLeft:
					var o := cell(grid, x - 1, y)
					if not o.isInvalid:
						var pt2_y: int
						if o.isRoom:
							pt2_y = rand_range(o.start_y + 1, o.end_y - 1)
						else:
							pt2_y = o.start_y
						# (o.start_x - 1) is Red's typo for (o.end_x - 1); kept.
						create_hallway(c.start_x, pt_y, o.start_x - 1, pt2_y, false, list_x[x], list_y[y])
					c.shouldConnectToLeft = false
					o.shouldConnectToRight = false
					c.isConnected = true
					o.isConnected = true

				if c.shouldConnectToRight:
					var o := cell(grid, x + 1, y)
					if not o.isInvalid:
						var pt2_y: int
						if o.isRoom:
							pt2_y = rand_range(o.start_y + 1, o.end_y - 1)
						else:
							pt2_y = o.start_y
						create_hallway(c.end_x - 1, pt_y, o.start_x, pt2_y, false, list_x[x + 1] - 1, list_y[y])
					c.shouldConnectToRight = false
					o.shouldConnectToLeft = false
					c.isConnected = true
					o.isConnected = true

		if disable_room_merging:
			return

		for x in gx:
			for y in gy:
				var chance := rand_int(100)
				var c := cell(grid, x, y)
				if chance < MERGE_ROOMS_CHANCE and not c.isInvalid and c.isConnected and not c.isMerged \
						and not c.hasSecondaryStructure and c.isRoom:
					var chance_two := rand_int(4)
					match chance_two:
						0:
							if x > 0:
								var o := cell(grid, x - 1, y)
								if o.isConnected and not o.isInvalid and o.isRoom and not o.hasSecondaryStructure and not o.isMerged:
									var src_x := o.start_x
									var src_y: int = min(o.start_y, c.start_y)
									var dst_x := c.end_x
									var dst_y: int = max(o.end_y, c.end_y)
									_carve_merge(src_x, src_y, dst_x, dst_y, room_at(c.start_x, c.start_y))
									o.start_x = src_x
									o.end_x = dst_x
									o.start_y = src_y
									o.end_y = dst_y
									c.isMerged = true
									o.isMerged = true
									c.isConnected = false
									c.hasBeenMerged = true
						1:
							if y >= 1:
								var o := cell(grid, x, y - 1)
								if o.isConnected and not o.isInvalid and o.isRoom and not o.hasSecondaryStructure and not o.isMerged:
									var src_x: int = min(o.start_x, c.start_x)
									var src_y := o.start_y
									var dst_x: int = max(o.end_x, c.end_x)
									var dst_y := c.end_y
									_carve_merge(src_x, src_y, dst_x, dst_y, room_at(c.start_x, c.start_y))
									o.start_x = src_x
									o.end_x = dst_x
									o.start_y = src_y
									o.end_y = dst_y
									c.isMerged = true
									o.isMerged = true
									c.isConnected = false
									c.hasBeenMerged = true
						2:
							if x <= gx - 2:
								var o := cell(grid, x + 1, y)
								if o.isConnected and not o.isInvalid and o.isRoom and not o.hasSecondaryStructure and not o.isMerged:
									var src_x := c.start_x
									var src_y: int = min(c.start_y, o.start_y)
									var dst_x := o.end_x
									var dst_y: int = max(c.end_y, o.end_y)
									_carve_merge(src_x, src_y, dst_x, dst_y, room_at(c.start_x, c.start_y))
									c.start_x = src_x
									c.end_x = dst_x
									c.start_y = src_y
									c.end_y = dst_y
									o.isMerged = true
									c.isMerged = true
									o.isConnected = false
									o.hasBeenMerged = true
						3:
							if y <= gy - 2:
								var o := cell(grid, x, y + 1)
								if o.isConnected and not o.isInvalid and o.isRoom and not o.hasSecondaryStructure and not o.isMerged:
									var src_x: int = min(c.start_x, o.start_x)
									var src_y := c.start_y
									var dst_x: int = max(c.end_x, o.end_x)
									var dst_y := o.end_y
									_carve_merge(src_x, src_y, dst_x, dst_y, room_at(c.start_x, c.start_y))
									c.start_x = src_x
									c.end_x = dst_x
									c.start_y = src_y
									c.end_y = dst_y
									o.isMerged = true
									c.isMerged = true
									o.isConnected = false
									o.hasBeenMerged = true

	func _carve_merge(src_x: int, src_y: int, dst_x: int, dst_y: int, room_index: int) -> void:
		carve_rect(src_x, src_y, dst_x, dst_y, room_index)

	# C: GenerateRoomImperfections
	func generate_room_imperfections(grid: Array, gx: int, gy: int) -> void:
		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if c.isInvalid or c.hasBeenMerged or c.isMerged or not c.isConnected or not c.isRoom \
						or c.hasSecondaryStructure or c.isMazeRoom or not c.flagImperfect:
					continue
				if rand_int(100) < NO_IMPERFECTIONS_CHANCE:
					continue
				var length := (c.end_x - c.start_x + (c.end_y - c.start_y)) / 4
				if length == 0:
					length = 1
				for counter in length:
					for i in 2:
						var pt_x := 0
						var pt_y := 0
						var move_x := 0
						var move_y := 0
						var corner := rand_int(4)
						match corner:
							1:
								pt_x = c.end_x - 1
								pt_y = c.start_y
								if i != 0:
									move_x = 0; move_y = 1
								else:
									move_x = -1; move_y = 0
							2:
								pt_x = c.end_x - 1
								pt_y = c.end_y - 1
								if i != 0:
									move_x = -1; move_y = 0
								else:
									move_x = 0; move_y = -1
							3:
								pt_x = c.start_x
								pt_y = c.end_y - 1
								if i != 0:
									move_x = 0; move_y = -1
								else:
									move_x = 1; move_y = 0
							_:
								pt_x = c.start_x
								pt_y = c.start_y
								if i != 0:
									move_x = 1; move_y = 0
								else:
									move_x = 0; move_y = 1
						for v in 10:
							if pt_x < c.start_x or pt_x >= c.end_x:
								break
							if pt_y < c.start_y or pt_y >= c.end_y:
								break
							if tt(pt_x, pt_y) == TT_NORMAL:
								var direction := 0
								while direction < 8:
									var nx: int = pt_x + ADJ_X[direction]
									var ny: int = pt_y + ADJ_Y[direction]
									var found := false
									for oy in range(-1, 2):
										for ox in range(-1, 2):
											if tt(nx + ox, ny + oy) != TT_NORMAL:
												continue
											if room_at(nx + ox, ny + oy) == CORRIDOR_ROOM:
												found = true
												break
										if found:
											break
									if found:
										break
									direction += 1
								if direction == 8:
									direction = 0
									while direction < 8:
										var is_open := tt(pt_x + ADJ_X[direction], pt_y + ADJ_Y[direction]) == TT_NORMAL
										if CORNER_EXPECT_OPEN[corner][direction] != is_open:
											break
										direction += 2
									if direction == 8:
										set_tt(pt_x, pt_y, TT_WALL)
								break
							else:
								pt_x += move_x
								pt_y += move_y

	# C: CreateHallway
	func create_hallway(x: int, y: int, end_x: int, end_y: int, vertical: bool, turn_x: int, turn_y: int) -> void:
		var start_x := x
		var start_y := y
		var counter := 0
		if vertical:
			counter = 0
			while y != turn_y:
				if counter >= W:
					return
				counter += 1
				if tt(x, y) != TT_NORMAL:
					set_tt(x, y, TT_NORMAL)
				elif x != start_x or y != start_y:
					return
				y += 1 if y < turn_y else -1
			counter = 0
			while x != end_x:
				if counter >= W:
					return
				counter += 1
				if tt(x, y) != TT_NORMAL:
					set_tt(x, y, TT_NORMAL)
				elif x != start_x or y != start_y:
					return
				x += 1 if x < end_x else -1
			counter = 0
			while y != end_y:
				if counter >= W:
					return
				counter += 1
				if tt(x, y) != TT_NORMAL:
					set_tt(x, y, TT_NORMAL)
				elif x != start_x or y != start_y:
					return
				y += 1 if y < end_y else -1
		else:
			counter = 0
			while x != turn_x:
				if counter >= W:
					return
				counter += 1
				if tt(x, y) != TT_NORMAL:
					set_tt(x, y, TT_NORMAL)
				elif x != start_x or y != start_y:
					return
				x += 1 if x < turn_x else -1
			counter = 0
			while y != end_y:
				if counter >= W:
					return
				counter += 1
				if tt(x, y) != TT_NORMAL:
					set_tt(x, y, TT_NORMAL)
				elif x != start_x or y != start_y:
					return
				y += 1 if y < end_y else -1
			counter = 0
			while x != end_x:
				if counter >= W:
					return
				counter += 1
				if tt(x, y) != TT_NORMAL:
					set_tt(x, y, TT_NORMAL)
				elif x != start_x or y != start_y:
					return
				x += 1 if x < end_x else -1

	# C: EnsureConnectedGrid
	func ensure_connected_grid(grid: Array, gx: int, gy: int, list_x: PackedInt32Array, list_y: PackedInt32Array) -> void:
		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if c.isInvalid or c.hasBeenMerged or c.isConnected:
					continue
				if c.isRoom and not c.hasSecondaryStructure:
					var rnd_x := rand_range(c.start_x + 1, c.end_x - 1)
					var rnd_y := rand_range(c.start_y + 1, c.end_y - 1)
					var pt_x := 0
					var pt_y := 0
					if y > 0 and not cell(grid, x, y - 1).isInvalid and not cell(grid, x, y - 1).isMerged and cell(grid, x, y - 1).isConnected:
						var o := cell(grid, x, y - 1)
						if o.isRoom:
							pt_x = rand_range(o.start_x + 1, o.end_x - 1)
							pt_y = rand_range(o.start_y + 1, o.end_y - 1)
						else:
							pt_x = o.start_x
							pt_y = o.start_y
						create_hallway(rnd_x, c.start_y, pt_x, o.end_y - 1, true, list_x[x], list_y[y])
						c.isConnected = true
						c.connectedToTop = true
						o.connectedToBottom = true
					elif y < gy - 1 and not cell(grid, x, y + 1).isInvalid and not cell(grid, x, y + 1).isMerged and cell(grid, x, y + 1).isConnected:
						var o := cell(grid, x, y + 1)
						if o.isRoom:
							pt_x = rand_range(o.start_x + 1, o.end_x - 1)
							pt_y = rand_range(o.start_y + 1, o.end_y - 1)
						else:
							pt_x = o.start_x
							pt_y = o.start_y
						create_hallway(rnd_x, c.end_y - 1, pt_x, o.start_y, true, list_x[x], list_y[y + 1] - 1)
						c.isConnected = true
						c.connectedToBottom = true
						o.connectedToTop = true
					elif x > 0 and not cell(grid, x - 1, y).isInvalid and not cell(grid, x - 1, y).isMerged and cell(grid, x - 1, y).isConnected:
						var o := cell(grid, x - 1, y)
						if o.isRoom:
							pt_x = rand_range(o.start_x + 1, o.end_x - 1)
							pt_y = rand_range(o.start_y + 1, o.end_y - 1)
						else:
							pt_x = o.start_x
							pt_y = o.start_y
						create_hallway(c.start_x, rnd_y, o.start_x - 1, pt_y, false, list_x[x], list_y[y])
						c.isConnected = true
						c.connectedToLeft = true
						o.connectedToRight = true
					elif x < gx - 1 and not cell(grid, x + 1, y).isInvalid and not cell(grid, x + 1, y).isMerged and cell(grid, x + 1, y).isConnected:
						var o := cell(grid, x + 1, y)
						if o.isRoom:
							pt_x = rand_range(o.start_x + 1, o.end_x - 1)
							pt_y = rand_range(o.start_y + 1, o.end_y - 1)
						else:
							pt_x = o.start_x
							pt_y = o.start_y
						create_hallway(c.end_x - 1, rnd_y, o.start_x, pt_y, false, list_x[x + 1] - 1, list_y[y])
						c.isConnected = true
						c.connectedToRight = true
						o.connectedToLeft = true
				else:
					set_tt(c.start_x, c.start_y, TT_WALL)
					sp_clear(c.start_x, c.start_y, SP_STAIRS | SP_ITEM | SP_TRAP)

		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if c.isInvalid or c.hasBeenMerged or c.isConnected or c.unk15:
					continue
				for cx in range(c.start_x, c.end_x):
					for cy in range(c.start_y, c.end_y):
						set_tt(cx, cy, TT_WALL)
						sp_clear(cx, cy, SP_ITEM | SP_STAIRS | SP_TRAP)
						set_room(cx, cy, CORRIDOR_ROOM)

	# C: SetTerrainObstacleChecked
	func set_terrain_obstacle_checked(x: int, y: int, use_secondary: bool, room_index: int) -> void:
		set_tt(x, y, TT_WALL)
		if use_secondary and room_at(x, y) == (room_index & 0xFF):
			set_tt(x, y, TT_SECONDARY)

	# C: FinalizeJunctions
	func finalize_junctions() -> void:
		for x in W:
			for y in H:
				var i := y * W + x
				if (tf[i] & 3) != TT_NORMAL:
					continue
				if rm[i] == CORRIDOR_ROOM:
					if x > 0:
						_mark_junction(i - 1)
					if y > 0:
						_mark_junction(i - W)
					if y < H - 1:
						_mark_junction(i + W)
					if x < W - 1:
						_mark_junction(i + 1)
				elif rm[i] == ROOM_0xFE:
					rm[i] = CORRIDOR_ROOM
		# sub_804EB30 (per-room natural junction lists) is game-layer data; not needed here.

	func _mark_junction(j: int) -> void:
		if rm[j] != CORRIDOR_ROOM:
			tf[j] |= TF_JUNCTION
			if (tf[j] & 3) == TT_SECONDARY:
				tf[j] = (tf[j] & ~3) | TT_NORMAL

	# C: GenerateKecleonShop
	func generate_kecleon_shop(grid: Array, gx: int, gy: int, chance: int) -> void:
		kecleon_mid = Vector2i(-1, -1)
		if sHasMonsterHouse or chance == 0:  # (rescue floors also excluded in Red)
			return
		if chance <= rand_int(100):
			return
		var lx := PackedInt32Array()
		var ly := PackedInt32Array()
		for i in GRID_CELL_LEN:
			lx.append(i)
			ly.append(i)
		for i in 200:
			var a := rand_int(GRID_CELL_LEN)
			var b := rand_int(GRID_CELL_LEN)
			var t := lx[a]
			lx[a] = lx[b]
			lx[b] = t
		for i in 200:
			var a := rand_int(GRID_CELL_LEN)
			var b := rand_int(GRID_CELL_LEN)
			var t := ly[a]
			ly[a] = ly[b]
			ly[b] = t
		for i in GRID_CELL_LEN:
			var x := lx[i]
			if x >= gx:
				continue
			for j in GRID_CELL_LEN:
				var y := ly[j]
				if y >= gy:
					continue
				var c := cell(grid, x, y)
				if c.isInvalid or c.hasBeenMerged or c.isMerged or not c.isConnected or not c.isRoom \
						or c.hasSecondaryStructure or c.isMazeRoom or c.flagSecondaryStructure:
					continue
				if absi(c.end_x - c.start_x) < 5 or absi(c.end_y - c.start_y) < 4:
					continue
				sHasKecleonShop = true
				c.isKecleonShop = true
				shop_min_x = c.start_x + 1
				shop_max_x = c.end_x - 1
				shop_min_y = c.start_y + 1
				shop_max_y = c.end_y - 1
				if shop_max_y - shop_min_y < 3:
					shop_max_y += 1
				for cx in range(shop_min_x, shop_max_x):
					for cy in range(shop_min_y, shop_max_y):
						tf_or(cx, cy, TF_SHOP)
						sp_clear(cx, cy, SP_MONSTER | SP_STAIRS)
				for cx in range(c.start_x, c.end_x):
					for cy in range(c.start_y, c.end_y):
						sp_or(cx, cy, SP_SPECIAL)
				kecleon_mid = Vector2i((shop_min_x + shop_max_x) / 2, (shop_min_y + shop_max_y) / 2)
				return

	func _mh_candidate(c: GridCell) -> bool:
		return not (c.isInvalid or c.hasBeenMerged or not c.isConnected or not c.isRoom \
				or c.isKecleonShop or c.unk15 or c.isMazeRoom or c.hasSecondaryStructure)

	# C: GenerateMonsterHouse
	func generate_monster_house(grid: Array, gx: int, gy: int, chance: int) -> void:
		if chance == 0 or chance <= rand_int(100):
			return
		if sHasKecleonShop:
			return
		# (gDungeon->unk644.unk44 outlaw check and non-normal floor types: assumed normal)
		var num_valid := 0
		for x in gx:
			for y in gy:
				if _mh_candidate(cell(grid, x, y)):
					num_valid += 1
		if num_valid == 0:
			return
		var values := PackedByteArray()
		values.resize(256)
		values[0] = 1
		for i in 64:
			var a := rand_int(num_valid)
			var b := rand_int(num_valid)
			var t := values[a]
			values[a] = values[b]
			values[b] = t
		var i := 0
		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if not _mh_candidate(c):
					continue
				if values[i] != 0:
					sHasMonsterHouse = true
					c.isMonsterHouse = true
					for cx in range(c.start_x, c.end_x):
						for cy in range(c.start_y, c.end_y):
							if oob(cx, cy):
								monster_house_room = CORRIDOR_ROOM
								continue
							tf[cy * W + cx] |= TF_MONSTER_HOUSE
							monster_house_room = rm[cy * W + cx]
					return
				i += 1

	func _maze_candidate(c: GridCell) -> bool:
		if c.isInvalid or c.hasBeenMerged or not c.isConnected or not c.isRoom or c.isKecleonShop \
				or c.unk15 or c.isMonsterHouse or c.hasSecondaryStructure:
			return false
		return (c.end_x - c.start_x) % 2 != 0 and (c.end_y - c.start_y) % 2 != 0

	# C: GenerateMazeRoom
	func generate_maze_room(grid: Array, gx: int, gy: int, chance: int) -> void:
		if chance == 0:
			return
		if chance <= rand_int(100):
			return
		if unk3A16 >= 0:  # Red: this check always fails, so maze rooms never come from here
			return
		var num_valid := 0
		for x in gx:
			for y in gy:
				if _maze_candidate(cell(grid, x, y)):
					num_valid += 1
		if num_valid == 0:
			return
		var values := PackedByteArray()
		values.resize(256)
		values[0] = 1
		for i in 64:
			var a := rand_int(num_valid)
			var b := rand_int(num_valid)
			var t := values[a]
			values[a] = values[b]
			values[b] = t
		var i := 0
		for x in gx:
			for y in gy:
				var c := cell(grid, x, y)
				if _maze_candidate(c):
					if values[i] != 0:
						generate_maze(c, false)
						return
					i += 1

	# C: GenerateMaze
	func generate_maze(c: GridCell, use_secondary: bool) -> void:
		sHasMaze = true
		c.isMazeRoom = true
		for mx in range(c.start_x, c.end_x):
			for my in range(c.start_y, c.end_y):
				maze[my * W + mx] = 1
		var room_index := room_at(c.start_x, c.start_y)
		var cx := c.start_x + 1
		while cx < c.end_x - 1:
			if tt(cx, c.start_y - 1) != TT_NORMAL:
				generate_maze_line(cx, c.start_y - 1, c.start_x, c.start_y, c.end_x, c.end_y, use_secondary, room_index)
			cx += 2
		var cy := c.start_y + 1
		while cy < c.end_y - 1:
			if tt(c.end_x, cy) != TT_NORMAL:
				generate_maze_line(c.end_x, cy, c.start_x, c.start_y, c.end_x, c.end_y, use_secondary, room_index)
			cy += 2
		cx = c.start_x + 1
		while cx < c.end_x - 1:
			if tt(cx, c.end_y) != TT_NORMAL:
				generate_maze_line(cx, c.end_y, c.start_x, c.start_y, c.end_x, c.end_y, use_secondary, room_index)
			cx += 2
		cy = c.start_y + 1
		while cy < c.end_y - 1:
			if tt(c.start_x - 1, cy) != TT_NORMAL:
				generate_maze_line(c.start_x - 1, cy, c.start_x, c.start_y, c.end_x, c.end_y, use_secondary, room_index)
			cy += 2
		cx = c.start_x + 3
		while cx < c.end_x - 3:
			cy = c.start_y + 3
			while cy < c.end_y - 3:
				if tt(cx, cy) == TT_NORMAL:
					if use_secondary:
						set_tt(cx - 1, cy, TT_SECONDARY)
					else:
						set_tt(cx - 1, cy, TT_WALL)
					generate_maze_line(cx, cy, c.start_x, c.start_y, c.end_x, c.end_y, use_secondary, room_index)
				cy += 2
			cx += 2

	# C: GenerateMazeLine
	func generate_maze_line(x0: int, y0: int, x_min: int, y_min: int, x_max: int, y_max: int, use_secondary: bool, room_index: int) -> void:
		while true:
			var direction := rand_int(4)
			var i := 0
			set_terrain_obstacle_checked(x0, y0, use_secondary, room_index)
			while true:
				var ox := 0
				var oy := 0
				match direction & 3:
					CARDINAL_DIR_RIGHT:
						ox = 2
					CARDINAL_DIR_UP:
						oy = -2
					CARDINAL_DIR_LEFT:
						ox = -2
					_:
						oy = 2
				var px := x0 + ox
				var found := false
				if x_min <= px and x_max > px:
					var py := y0 + oy
					if y_min <= py and y_max > py:
						if tt(px, py) == TT_NORMAL:
							found = true
				if found:
					break
				direction += 1
				i += 1
				if i >= 4:
					return
			match direction & 3:
				CARDINAL_DIR_RIGHT:
					set_terrain_obstacle_checked(x0 + 1, y0, use_secondary, room_index)
					x0 += 2
				CARDINAL_DIR_UP:
					set_terrain_obstacle_checked(x0, y0 - 1, use_secondary, room_index)
					y0 -= 2
				CARDINAL_DIR_LEFT:
					set_terrain_obstacle_checked(x0 - 1, y0, use_secondary, room_index)
					x0 -= 2
				CARDINAL_DIR_DOWN:
					set_terrain_obstacle_checked(x0, y0 + 1, use_secondary, room_index)
					y0 += 2

	# C: SetTerrainSecondaryWithFlag
	func set_secondary_with_flag(x: int, y: int, extra: int) -> void:
		set_tt(x, y, TT_SECONDARY)
		tf_or(x, y, extra)

	# C: SetSpawnFlag5
	func set_spawn_flag5(c: GridCell) -> void:
		for x in range(c.start_x, c.end_x):
			for y in range(c.start_y, c.end_y):
				sp_or(x, y, SP_UNK5)

	# C: IsNextToHallway
	func is_next_to_hallway(x: int, y: int) -> bool:
		for ox in range(-1, 2):
			var px := x + ox
			if px < 0:
				continue
			if px >= W:
				break
			for oy in range(-1, 2):
				var py := y + oy
				if py < 0:
					continue
				if py >= H:
					break
				if ox != 0 and oy != 0:
					continue
				if tt(px, py) == TT_NORMAL and room_at(px, py) == CORRIDOR_ROOM:
					return true
		return false

	# C: GenerateSecondaryStructure
	func generate_secondary_structure(c: GridCell) -> void:
		match rand_int(6):
			5:  # SECONDARY_STRUCTURE_DIVIDER
				if sSecondaryStructuresBudget != 0:
					sSecondaryStructuresBudget -= 1
					set_spawn_flag5(c)
					if rand_int(2) != 0:
						var invalid := false
						var middle_x := (c.start_x + c.end_x) / 2
						for i in range(c.start_y, c.end_y):
							if is_next_to_hallway(middle_x, i):
								invalid = true
								break
						if not invalid:
							for i in range(c.start_y, c.end_y):
								set_secondary_with_flag(middle_x, i, 0)
							for cx in range(c.start_x, middle_x):
								for cy in range(c.start_y, c.end_y):
									tf_or(cx, cy, TF_UNK_7)
							c.hasSecondaryStructure = true
					else:
						var invalid := false
						var middle_y := (c.start_y + c.end_y) / 2
						for i in range(c.start_x, c.end_x):
							if is_next_to_hallway(i, middle_y):
								invalid = true
								break
						if not invalid:
							for i in range(c.start_x, c.end_x):
								set_secondary_with_flag(i, middle_y, 0)
							for cy in range(c.start_y, middle_y):
								for cx in range(c.start_x, c.end_x):
									tf_or(cx, cy, TF_UNK_7)
							c.hasSecondaryStructure = true
			4:  # SECONDARY_STRUCTURE_ISLAND
				if (c.end_x - c.start_x) >= 6 and (c.end_y - c.start_y) >= 6:
					var mx := (c.start_x + c.end_x) / 2
					var my := (c.start_y + c.end_y) / 2
					if sSecondaryStructuresBudget != 0:
						sSecondaryStructuresBudget -= 1
						set_spawn_flag5(c)
						var cc := TF_CORNER_CUTTABLE
						set_secondary_with_flag(mx - 2, my - 2, cc)
						set_secondary_with_flag(mx - 1, my - 2, cc)
						set_secondary_with_flag(mx, my - 2, cc)
						set_secondary_with_flag(mx + 1, my - 2, cc)
						set_secondary_with_flag(mx - 2, my - 1, cc)
						set_secondary_with_flag(mx - 2, my, cc)
						set_secondary_with_flag(mx - 2, my + 1, cc)
						set_secondary_with_flag(mx - 2, my + 1, cc)
						set_secondary_with_flag(mx - 1, my + 1, cc)
						set_secondary_with_flag(mx, my + 1, cc)
						set_secondary_with_flag(mx + 1, my - 2, cc)
						set_secondary_with_flag(mx + 1, my - 1, cc)
						set_secondary_with_flag(mx + 1, my, cc)
						set_secondary_with_flag(mx + 1, my + 1, cc)
						sp_or(mx - 1, my - 1, SP_TRAP)
						sp_or(mx - 1, my - 1, SP_UNK6)  # warp tile
						sp_or(mx, my - 1, SP_ITEM)
						sp_or(mx - 1, my, SP_ITEM)
						sp_or(mx, my, SP_ITEM)
						sp_or(mx - 1, my - 1, SP_SPECIAL)
						sp_or(mx, my - 1, SP_SPECIAL)
						sp_or(mx - 1, my, SP_SPECIAL)
						sp_or(mx, my, SP_SPECIAL)
						c.hasSecondaryStructure = true
			3:  # SECONDARY_STRUCTURE_POOL
				if (c.end_x - c.start_x) >= 5 and (c.end_y - c.start_y) >= 5:
					var rx1 := rand_range(c.start_x + 2, c.end_x - 3)
					var ry1 := rand_range(c.start_y + 2, c.end_y - 3)
					var rx2 := rand_range(c.start_x + 2, c.end_x - 3)
					var ry2 := rand_range(c.start_y + 2, c.end_y - 3)
					if sSecondaryStructuresBudget != 0:
						sSecondaryStructuresBudget -= 1
						set_spawn_flag5(c)
						if rx1 > rx2:
							var t := rx1
							rx1 = rx2
							rx2 = t
						if ry1 > ry2:
							var t := ry1
							ry1 = ry2
							ry2 = t
						for cx in range(rx1, rx2 + 1):
							for cy in range(ry1, ry2 + 1):
								set_secondary_with_flag(cx, cy, 0)
						c.hasSecondaryStructure = true
			2:  # SECONDARY_STRUCTURE_CHECKERBOARD
				if (c.end_x - c.start_x) % 2 != 0 and (c.end_y - c.start_y) % 2 != 0 and sSecondaryStructuresBudget != 0:
					sSecondaryStructuresBudget -= 1
					set_spawn_flag5(c)
					for i in 64:
						var rx := rand_int(c.end_x - c.start_x)
						var ry := rand_int(c.end_y - c.start_y)
						if (rx + ry) % 2 != 0:
							set_secondary_with_flag(c.start_x + rx, c.start_y + ry, 0)
					c.hasSecondaryStructure = true
			1:  # SECONDARY_STRUCTURE_MAZE_PLUS_DOT
				if sSecondaryStructuresBudget != 0:
					sSecondaryStructuresBudget -= 1
					if (c.end_x - c.start_x) % 2 == 0 or (c.end_y - c.start_y) % 2 == 0:
						var mx := (c.start_x + c.end_x) / 2
						var my := (c.start_y + c.end_y) / 2
						if (c.end_x - c.start_x) >= 5 and (c.end_y - c.start_y) >= 5:
							set_secondary_with_flag(mx + 1, my, 0)
							set_secondary_with_flag(mx, my + 1, 0)
							set_secondary_with_flag(mx - 1, my, 0)
							set_secondary_with_flag(mx, my - 1, 0)
						set_secondary_with_flag(mx, my, 0)
					else:
						set_spawn_flag5(c)
						generate_maze(c, true)
					c.hasSecondaryStructure = true
			_:  # SECONDARY_STRUCTURE_NONE
				pass

	# C: ResolveInvalidSpawns
	func resolve_invalid_spawns() -> void:
		for i in N:
			if (tf[i] & 3) != TT_NORMAL:
				if tf[i] & (TF_UNBREAKABLE | TF_IMPASSABLE):
					sp[i] &= ~SP_ITEM
				sp[i] &= ~SP_TRAP
			if sp[i] & SP_STAIRS:
				tf[i] |= TF_STAIRS
				sp[i] &= ~SP_TRAP
			if sp[i] & SP_ITEM:
				sp[i] &= ~SP_TRAP

	# C: EnsureImpassableTilesAreWalls
	func ensure_impassable_tiles_are_walls() -> void:
		for i in N:
			if tf[i] & TF_IMPASSABLE:
				tf[i] &= ~3

	# C: ResetInnerBoundaryTileRows
	func reset_inner_boundary_tile_rows() -> void:
		for x in W:
			var i := 1 * W + x
			reset_tile(i)
			if x == 0 or x == W - 1:
				tf[i] |= TF_IMPASSABLE
			i = 30 * W + x
			reset_tile(i)
			if x == 0 or x == W - 1:
				tf[i] |= TF_IMPASSABLE

	# C: ShuffleSpawnPositions
	func shuffle_spawns(spawns: PackedInt32Array, count: int) -> void:
		for i in count * 2:
			var a := rand_int(count)
			var b := rand_int(count)
			var t := spawns[a]
			spawns[a] = spawns[b]
			spawns[b] = t

	# C: SpawnNonEnemies (valid tiles collected in x-major order, as in Red)
	func spawn_non_enemies(is_empty_mh: bool) -> void:
		var valid := PackedInt32Array()
		var count := 0
		var rand_index := 0
		# Stairs
		if stairs_spawn.x == -1 or stairs_spawn.y == -1:
			valid.clear()
			for x in W:
				for y in H:
					var i := y * W + x
					var t := tf[i]
					if (t & 3) != TT_NORMAL or rm[i] == CORRIDOR_ROOM:
						continue
					if t & (TF_SHOP | TF_JUNCTION | TF_UNBREAKABLE):
						continue
					if sp[i] & (SP_MONSTER | SP_SPECIAL):
						continue
					valid.append(i)
			count = valid.size()
			if count != 0:
				var si := valid[rand_int(count)]
				sp[si] |= SP_STAIRS
				sp[si] &= ~SP_ITEM
				sStairsRoomIndex = rm[si]
				stairs_spawn = Vector2i(si % W, si / W)
				# (rescue floors turn the stairs room into a monster house; not applicable)

		# Normal items
		valid.clear()
		for x in W:
			for y in H:
				var i := y * W + x
				var t := tf[i]
				if (t & 3) != TT_NORMAL or rm[i] == CORRIDOR_ROOM:
					continue
				if t & (TF_SHOP | TF_MONSTER_HOUSE | TF_JUNCTION | TF_UNBREAKABLE):
					continue
				valid.append(i)
		count = valid.size()
		if count != 0:
			var num_items := p("itemDensity")
			if num_items != 0:
				num_items = rand_range(num_items - 2, num_items + 2)
				if num_items <= 0:
					num_items = 1
			if num_items != 0:
				shuffle_spawns(valid, count)
				rand_index = rand_int(count)
				for k in num_items:
					sp[valid[rand_index]] |= SP_ITEM
					rand_index += 1
					if rand_index == count:
						rand_index = 0

		# Buried items
		valid.clear()
		for x in W:
			for y in H:
				var i := y * W + x
				if (tf[i] & 3) == TT_WALL:
					valid.append(i)
		count = valid.size()
		if count != 0:
			var num_items := p("buriedItemDensity")
			if num_items != 0:
				num_items = rand_range(num_items - 2, num_items + 2)
			if num_items > 0:
				shuffle_spawns(valid, count)
				rand_index = rand_int(count)
				for k in num_items:
					sp[valid[rand_index]] |= SP_ITEM
					rand_index += 1
					if rand_index == count:
						rand_index = 0

		# Monster house items / traps
		valid.clear()
		if not is_empty_mh:
			for x in W:
				for y in H:
					var i := y * W + x
					var t := tf[i]
					if t & TF_SHOP:
						continue
					if not (t & TF_MONSTER_HOUSE):
						continue
					if t & TF_JUNCTION:
						continue
					valid.append(i)
		count = valid.size()
		if count != 0:
			var n := rand_range(count / 2, (count * 8) / 10)
			if n < 6:
				n = 6
			if n >= MONSTER_HOUSE_MAX_ITEMS_TRAPS:
				n = MONSTER_HOUSE_MAX_ITEMS_TRAPS
			shuffle_spawns(valid, count)
			rand_index = rand_int(count)
			for k in n:
				if rand_int(2) != 0:
					sp[valid[rand_index]] |= SP_ITEM
				else:  # gDungeon->unk644.canChangeLeader assumed TRUE
					sp[valid[rand_index]] |= SP_TRAP
				rand_index += 1
				if rand_index == count:
					rand_index = 0

		# Normal traps
		valid.clear()
		for x in W:
			for y in H:
				var i := y * W + x
				var t := tf[i]
				if (t & 3) != TT_NORMAL or rm[i] == CORRIDOR_ROOM:
					continue
				if t & (TF_SHOP | TF_JUNCTION | TF_UNBREAKABLE):
					continue
				if sp[i] & SP_ITEM:
					continue
				valid.append(i)
		count = valid.size()
		if count != 0:
			var td := p("trapDensity")
			var num_traps := rand_range(td / 2, td)
			if num_traps > 0:
				if num_traps >= 56:
					num_traps = 56
				shuffle_spawns(valid, count)
				var trap_index := rand_int(count)
				for k in num_traps:
					sp[valid[trap_index]] |= SP_TRAP
					trap_index += 1
					if trap_index == count:
						trap_index = 0

		# Player
		if player_spawn.x == -1 or player_spawn.y == -1:
			valid.clear()
			for x in W:
				for y in H:
					var i := y * W + x
					var t := tf[i]
					if (t & 3) != TT_NORMAL or rm[i] == CORRIDOR_ROOM:
						continue
					if t & (TF_SHOP | TF_JUNCTION | TF_UNBREAKABLE):
						continue
					if sp[i] & (SP_ITEM | SP_MONSTER | SP_TRAP):
						continue
					valid.append(i)
			count = valid.size()
			if count != 0:
				var pi := valid[rand_int(count)]
				player_spawn = Vector2i(pi % W, pi / W)

	# C: SpawnEnemies
	func spawn_enemies(is_empty_mh: bool) -> void:
		var valid := PackedInt32Array()
		var num_enemies := 0
		# enemyDensity is a u8 in the struct; Red's "negative = exact" branch only
		# triggers for 0 (see the BUG comment in the decomp).
		var enemy_density := p("enemyDensity") & 0xFF
		if enemy_density > 0:
			num_enemies = rand_range(enemy_density / 2, enemy_density)
			if num_enemies < 1:
				num_enemies = 1
		else:
			num_enemies = absi(enemy_density)
		var pidx := player_spawn.y * W + player_spawn.x if player_spawn.x >= 0 else -1
		for x in W:
			for y in H:
				var i := y * W + x
				var t := tf[i]
				if (t & 3) != TT_NORMAL or rm[i] == CORRIDOR_ROOM:
					continue
				if t & (TF_SHOP | TF_JUNCTION | TF_UNBREAKABLE):
					continue
				if sp[i] & (SP_ITEM | SP_STAIRS):
					continue
				if i == pidx:
					continue
				valid.append(i)
		var count := valid.size()
		if count != 0:
			# (gDungeon->unk644.unk44 adds one outlaw spawn; not applicable)
			if num_enemies != 0:
				shuffle_spawns(valid, count)
				var rand_index := rand_int(count)
				for k in num_enemies:
					sp[valid[rand_index]] |= SP_MONSTER
					rand_index += 1
					if rand_index == count:
						rand_index = 0

		if not force_monster_house:
			return

		var num_mh := MONSTER_HOUSE_MAX_MONS
		if is_empty_mh:
			num_mh = 3
		num_mh = (num_mh * 3) / 2
		valid.clear()
		for x in W:
			for y in H:
				var i := y * W + x
				var t := tf[i]
				if (t & 3) != TT_NORMAL or rm[i] == CORRIDOR_ROOM:
					continue
				if t & (TF_SHOP | TF_UNBREAKABLE):
					continue
				if not (t & TF_MONSTER_HOUSE):
					continue
				if i == pidx:
					continue
				valid.append(i)
		count = valid.size()
		if count != 0:
			num_enemies = rand_range((7 * count) / 10, (8 * count) / 10)
			if num_enemies == 0:
				num_enemies = 1
			if num_enemies >= num_mh:
				num_enemies = num_mh
			shuffle_spawns(valid, count)
			var rand_index := rand_int(count)
			for k in num_enemies:
				sp[valid[rand_index]] |= SP_MONSTER
				rand_index += 1
				if rand_index == count:
					rand_index = 0

	# C: SetSecondaryTerrainOnWall
	func set_secondary_terrain_on_wall(x: int, y: int) -> void:
		if oob(x, y):
			return
		var i := y * W + x
		if (tf[i] & 3) == TT_WALL and not (tf[i] & TF_IMPASSABLE):
			tf[i] = (tf[i] & ~3) | TT_SECONDARY

	func _sec_neighbours(x: int, y: int) -> int:
		var n := 0
		if tt(x + 1, y + 1) == TT_SECONDARY: n += 1
		if tt(x + 1, y) == TT_SECONDARY: n += 1
		if tt(x + 1, y - 1) == TT_SECONDARY: n += 1
		if tt(x, y + 1) == TT_SECONDARY: n += 1
		if tt(x, y - 1) == TT_SECONDARY: n += 1
		if tt(x - 1, y + 1) == TT_SECONDARY: n += 1
		if tt(x - 1, y) == TT_SECONDARY: n += 1
		if tt(x - 1, y - 1) == TT_SECONDARY: n += 1
		return n

	# C: GenerateSecondaryTerrainFormations (NONMATCHING C version)
	func generate_secondary_terrain_formations(flag: int) -> void:
		if not (p("roomFlags") & flag):
			return
		var num_to_gen: int = NUM_TO_GEN_TABLE[rand_int(8)]
		while num_to_gen != 0:
			var upwards := false
			var x := 0
			var y := 0
			var dir_x := 0
			var dir_y := 0
			if rand_int(100) < 50:
				upwards = true
				y = H - 1
				dir_y = -1
			else:
				upwards = false
				y = 0
				dir_y = 1
			var steps_until_lake := rand_int(50) + 10
			x = rand_range(2, W - 2)
			dir_x = 0
			while true:
				var num_fill := rand_int(6) + 2
				var hit_secondary := false
				while num_fill != 0:
					if x >= 0 and x < W:
						if tt(x, y) == TT_SECONDARY:
							hit_secondary = true
							break
						if not oob(x, y):
							set_secondary_terrain_on_wall(x, y)
					num_fill -= 1
					x += dir_x
					y += dir_y
					if y < 0 or y >= H:
						break
					steps_until_lake -= 1
					if steps_until_lake != 0:
						continue
					# Lake
					for j in 64:
						var ox := rand_int(7) - 3
						var oy := rand_int(7) - 3
						if ox + x < 2 or ox + x >= W - 2 or oy + y < 2 or oy + y >= H - 2:
							continue
						if _sec_neighbours(ox + x, oy + y) > 0:
							if not oob(x + ox, y + oy):
								set_secondary_terrain_on_wall(ox + x, oy + y)
					for ox in range(-3, 4):
						for oy in range(-3, 4):
							if ox + x < 2 or ox + x >= W - 2 or oy + y < 2 or oy + y >= H - 2:
								continue
							if _sec_neighbours(ox + x, oy + y) >= 4 and not oob(x + ox, y + oy):
								set_secondary_terrain_on_wall(ox + x, oy + y)
				if hit_secondary:
					break  # goto LABEL
				if dir_x != 0:
					dir_y = -1 if upwards else 1
					dir_x = 0
				else:
					dir_x = -1 if rand_int(100) < 50 else 1
					dir_y = 0
				if y < 0 or y >= H:
					break
			num_to_gen -= 1

		# Standalone lakes
		for density_n in p("standaloneLakeDensity"):
			var rnd_x := 0
			var rnd_y := 0
			var n := 0
			while n < 200:
				rnd_x = rand_range(0, W)
				rnd_y = rand_range(0, H)
				if rnd_x >= 1 and rnd_x < W - 1 and rnd_y >= 1 and rnd_y < H - 1:
					break
				n += 1
			if n == 200:
				continue
			var table := PackedByteArray()
			table.resize(100)  # table[x*10+y]
			for tx in 10:
				for ty in 10:
					table[tx * 10 + ty] = 1 if (tx == 0 or tx == 9 or ty == 0 or ty == 9) else 0
			for k in 80:
				var tx := rand_int(8) + 1
				var ty := rand_int(8) + 1
				if table[(tx - 1) * 10 + ty] or table[(tx + 1) * 10 + ty] or table[tx * 10 + ty - 1] or table[tx * 10 + ty + 1]:
					table[tx * 10 + ty] = 1
			for tx in 10:
				for ty in 10:
					if not table[tx * 10 + ty]:
						set_secondary_terrain_on_wall(tx + rnd_x - 5, ty + rnd_y - 5)

		# Clean up
		for x in W:
			for y in H:
				var i := y * W + x
				if (tf[i] & 3) != TT_SECONDARY:
					continue
				if (tf[i] & (TF_SHOP | TF_MONSTER_HOUSE | TF_UNBREAKABLE)) or (sp[i] & SP_STAIRS):
					tf[i] = (tf[i] & ~3) | TT_NORMAL
				elif x <= 1 or x >= W - 1 or y <= 1 or y >= H - 1:
					tf[i] &= ~3

	# C: StairsAlwaysReachable (markUnreachable = FALSE). Red uses a repeated
	# full-map sweep; a queue BFS reaches exactly the same set of tiles.
	func stairs_always_reachable(stairs_x: int, stairs_y: int) -> bool:
		const CANNOT_CUT := 1
		const SEC_CANNOT_CUT := 2
		const VISITED := 0x20
		var test := PackedByteArray()
		test.resize(N)
		for i in N:
			var t := tf[i] & 3
			var f := 0
			if t != TT_NORMAL and not (tf[i] & TF_CORNER_CUTTABLE):
				f |= CANNOT_CUT
			if t == TT_SECONDARY and not (tf[i] & TF_CORNER_CUTTABLE):
				f |= SEC_CANNOT_CUT
			test[i] = f
		if stairs_spawn.x != stairs_x or stairs_spawn.y != stairs_y:
			return false
		var queue := PackedInt32Array()
		var start := stairs_y * W + stairs_x
		test[start] |= VISITED
		queue.append(start)
		var head := 0
		var blocked := CANNOT_CUT | SEC_CANNOT_CUT | VISITED
		while head < queue.size():
			var i := queue[head]
			head += 1
			var x := i % W
			var y := i / W
			for d in 8:
				var dx: int = ADJ_X[d]
				var dy: int = ADJ_Y[d]
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= W or ny >= H:
					continue
				var j := ny * W + nx
				if test[j] & blocked:
					continue
				if dx != 0 and dy != 0:
					if test[y * W + nx] & CANNOT_CUT:
						continue
					if test[ny * W + x] & CANNOT_CUT:
						continue
				test[j] |= VISITED
				queue.append(j)
		for i in N:
			if not (test[i] & (CANNOT_CUT | SEC_CANNOT_CUT | 4 | VISITED)):
				if not (tf[i] & TF_UNBREAKABLE):
					return false
		return true

	# C: sub_8051654 - shrink the Kecleon shop and place shop items
	func kecleon_shop_finalize() -> void:
		var range_x := 3
		var range_y := 3
		for n in 20:
			range_x = rand_range(3, (shop_max_x - shop_min_x) - 2)
			if range_x < 3:
				range_x = 3
			if range_x >= 3:
				break
		for n in 20:
			range_y = rand_range(3, (shop_max_y - shop_min_y) - 2)
			if range_y < 3:
				range_y = 3
			if range_y >= 3:
				break
		var r10 := rand_range(2, 4)
		for i in r10:
			if shop_max_x - shop_min_x <= range_x:
				break
			if rand_int(100) < 50:
				for y in range(shop_min_y, shop_max_y):
					tf_clear(shop_min_x, y, TF_SHOP)
				shop_min_x += 1
			else:
				shop_max_x -= 1
				for y in range(shop_min_y, shop_max_y):
					tf_clear(shop_max_x, y, TF_SHOP)
		for i in r10:
			if shop_max_y - shop_min_y <= range_y:
				break
			if rand_int(100) < 50:
				for x in range(shop_min_x, shop_max_x):
					tf_clear(x, shop_min_y, TF_SHOP)
				shop_min_y += 1
			else:
				shop_max_y -= 1
				for x in range(shop_min_x, shop_max_x):
					tf_clear(x, shop_max_y, TF_SHOP)
		for x in range(shop_min_x, shop_max_x):
			for y in range(shop_min_y, shop_max_y):
				var f := flags_at(x, y)
				if not (f & TF_SHOP):
					continue
				if not (f & TF_JUNCTION):
					continue
				tf_clear(x, y, TF_SHOP)
		var middle_x := (shop_min_x + shop_max_x) / 2 - 1
		var middle_y := (shop_min_y + shop_max_y) / 2 - 1
		for xi in 3:
			for yi in 3:
				var x := middle_x + xi
				var y := middle_y + yi
				var f := flags_at(x, y)
				if not (f & TF_SHOP):
					continue
				if f & TF_MONSTER_HOUSE:
					continue
				if f & TF_JUNCTION:
					continue
				if SHOP_ITEM_CHANCES[yi][xi] > rand_int(100):
					sp_or(x, y, SP_ITEM)

	# ------------------------------------------------------------ output

	# =================================================================
	# Fixed rooms (dungeon_generation.c ProcessFixedRoom / sub_8051288 / sub_804C790 / sub_8051438,
	# dungeon_generation_fixed.c PlaceFixedRoomTile). fx = {room: {w, h, flags, tiles}, entities: [...]}.
	# Spawned Pokémon / items / traps are returned as lists for the game layer.
	# =================================================================
	var fixed_floorwide := false
	var fixed_mons := []      # {pos, sp, behavior, slot}
	var team_slots := {}      # FixedRoomEntitiesInfo.unk4 -> gDungeon->unkE220: team member i stands at slot i+1
	var fixed_items := []     # {pos, id, qty}
	var fixed_traps := []     # {pos, id, visible}
	const FIRST_NON_FLOORWIDE_FIXED_ROOM := 51

	func _tt_set(i: int, t: int) -> void:
		tf[i] = (tf[i] & ~3) | t

	func process_fixed_room(fx: Dictionary) -> bool:
		var room: Dictionary = fx.room
		var n := p("fixedRoomNumber")
		var sx := int(room.w)
		var sy := int(room.h)
		fixed_mons.clear()
		fixed_items.clear()
		fixed_traps.clear()
		team_slots.clear()
		if sx == 0 or sy == 0:
			generate_one_room_monster_house_floor()
			return false
		if n < FIRST_NON_FLOORWIDE_FIXED_ROOM:
			_fixed_floorwide(fx, n)
			return true
		var gx := maxi(1, W / (sx + 4))
		var gy := maxi(1, H / (sy + 4))
		_fixed_in_grid(fx, gx, gy, sx, sy)
		return false

	# C: sub_8051288
	func _fixed_floorwide(fx: Dictionary, n: int) -> void:
		var room: Dictionary = fx.room
		var sx := int(room.w)
		var sy := int(room.h)
		var tiles: Array = room.tiles
		var k := 0
		for y in range(5, sy + 5):
			for x in range(5, sx + 5):
				var i := y * W + x
				tf[i] |= TF_UNBREAKABLE
				place_fixed_tile(x, y, int(tiles[k]), true, fx)
				k += 1
		for y in H:
			for x in W:
				if x <= 4 or x >= sx + 5 or y <= 4 or y >= sy + 5:
					var i := y * W + x
					tf[i] |= TF_IMPASSABLE
					if gUnknown_202F1A8:
						_tt_set(i, TT_NORMAL | TT_SECONDARY)
					else:
						_tt_set(i, TT_WALL)
		if n == 4:  # FIXED_ROOM_MT_BLAZE_PEAK_MOLTRES
			for y in range(5, 17):
				for x in range(2, 5):
					var i := y * W + x
					tf[i] |= TF_IMPASSABLE
					_tt_set(i, TT_WALL)
		if p("tileset") >= 64:
			for i in N:
				if (tf[i] & 3) == TT_WALL:
					tf[i] |= TF_IMPASSABLE
		finalize_junctions()

	# C: sub_804C790 + CreateRoomsAndAnchorsForFixedFloor + sub_8051438
	func _fixed_in_grid(fx: Dictionary, gx: int, gy: int, sx: int, sy: int) -> void:
		var list_x := PackedInt32Array()
		var list_y := PackedInt32Array()
		list_x.resize(GRID_CELL_LEN)
		list_y.resize(GRID_CELL_LEN)
		get_grid_positions(list_x, list_y, gx, gy)
		var grid := new_grid()
		init_dungeon_grid(grid, gx, gy)
		assign_rooms(grid, gx, gy, p("roomDensity"))
		var cx := 0
		var cy := 0
		var r10 := 0
		for t in 64:
			cx = rand_int(gx)
			cy = rand_int(gy)
			r10 = cy * gx + cx
			if cell(grid, cx, cy).isRoom:
				break
		var room_number := 0
		var var_48 := 0
		for y in gy:
			for x in gx:
				var min_x := list_x[x] + 2
				var min_y := list_y[y] + 2
				var range_x := list_x[x + 1] - list_x[x] - 4
				var range_y := list_y[y + 1] - list_y[y] - 4
				var min_rx := 5
				var min_ry := 5
				if gx <= 2:
					min_rx = 10
					range_x = 14
				if gy == 1:
					min_ry = 16
					range_y = 24
				var c := cell(grid, x, y)
				if c.isRoom:
					var start_x := 0
					var start_y := 0
					var end_x := 0
					var end_y := 0
					if var_48 != r10:
						var rsx := rand_range(min_rx, range_x)
						var rsy := rand_range(min_ry, range_y)
						if (rsx | 1) < range_x:
							rsx |= 1
						if (rsy | 1) < range_y:
							rsy |= 1
						if rsx > (rsy * 3) / 2:
							rsx = (rsy * 3) / 2
						if rsy > (rsx * 3) / 2:
							rsy = (rsx * 3) / 2
						start_x = rand_int(range_x - rsx) + min_x
						start_y = rand_int(range_y - rsy) + min_y
						end_x = start_x + rsx
						end_y = start_y + rsy
					else:
						start_x = min_x
						start_y = min_y
						end_x = start_x + sx
						end_y = start_y + sy
					c.start_x = start_x
					c.end_x = end_x
					c.start_y = start_y
					c.end_y = end_y
					carve_rect(start_x, start_y, end_x, end_y, room_number)
					if var_48 != r10:
						c.flagSecondaryStructure = true
					room_number += 1
				else:
					var ux1 := 1 if x == 0 else 2
					var uy1 := 1 if y == 0 else 2
					var ux2 := 2 if x == gx - 1 else 4
					var uy2 := 2 if y == gy - 1 else 4
					var pt_x := rand_range(min_x + ux1, min_x + range_x - ux2)
					var pt_y := rand_range(min_y + uy1, min_y + range_y - uy2)
					c.start_x = pt_x
					c.end_x = pt_x + 1
					c.start_y = pt_y
					c.end_y = pt_y + 1
					set_tt(pt_x, pt_y, TT_NORMAL)
					set_room(pt_x, pt_y, ROOM_0xFE)
				var_48 += 1
		if gx != 1 or gy != 1:
			assign_grid_cell_connections(grid, gx, gy, cx, cy)
			create_grid_cell_connections(grid, gx, gy, list_x, list_y, true)
			ensure_connected_grid(grid, gx, gy, list_x, list_y)
		# sub_8051438 (the "closed corridor" vault variant, flags & 1, is placed already opened)
		var c2 := cell(grid, cx, cy)
		var tiles: Array = fx.room.tiles
		var k := 0
		for y in range(c2.start_y, c2.end_y):
			for x in range(c2.start_x, c2.end_x):
				if k >= tiles.size():
					break
				var i := y * W + x
				var rid := rm[i]
				tf[i] |= TF_UNBREAKABLE
				place_fixed_tile(x, y, int(tiles[k]), true, fx)
				rm[i] = rid
				k += 1

	# C: PlaceFixedRoomTile
	func place_fixed_tile(x: int, y: int, a: int, spawn_trap_item: bool, fx: Dictionary) -> void:
		var i := y * W + x
		var pos := Vector2i(x, y)
		if a > 0xF:
			_tt_set(i, TT_NORMAL)
		match a:
			0, 69:
				if a == 69:
					fixed_traps.append({"pos": pos, "id": "seal", "visible": false})
				_tt_set(i, TT_NORMAL)
				rm[i] = 0
			1:
				_tt_set(i, TT_WALL)
				tf[i] &= ~TF_UNBREAKABLE
				rm[i] = CORRIDOR_ROOM
			4:
				_tt_set(i, TT_NORMAL)
				player_spawn = pos
				rm[i] = 0
			5:
				_tt_set(i, TT_SECONDARY)
				rm[i] = 0
			6:
				_tt_set(i, TT_SECONDARY | TT_NORMAL)
				rm[i] = CORRIDOR_ROOM
			7, 10:
				if a == 7:
					gUnknown_202F1A8 = true
				_tt_set(i, TT_SECONDARY | TT_NORMAL)
				tf[i] |= TF_IMPASSABLE
				rm[i] = CORRIDOR_ROOM
			8, 67:
				_tt_set(i, TT_NORMAL)
				sp[i] |= SP_STAIRS
				sp[i] &= ~SP_ITEM
				rm[i] = 0
				stairs_spawn = pos
			68:
				_tt_set(i, TT_NORMAL)
				sp[i] &= ~SP_ITEM
				rm[i] = 0
			9:
				_tt_set(i, TT_NORMAL)
				rm[i] = CORRIDOR_ROOM
			11:
				_tt_set(i, TT_NORMAL)
				rm[i] = 0
			12:
				_tt_set(i, TT_NORMAL)
				tf[i] |= TF_IMPASSABLE
				rm[i] = 0
			2, 13, 14:
				_tt_set(i, TT_WALL)
				tf[i] |= TF_IMPASSABLE
				rm[i] = CORRIDOR_ROOM
			3, 15:
				pass
			_:
				var ents: Array = fx.get("entities", [])
				if a >= 16 and a - 16 < ents.size():
					var e: Dictionary = ents[a - 16]
					rm[i] = int(e.get("room", 0))
					if str(e.get("item", "")) != "" and spawn_trap_item:
						fixed_items.append({"pos": pos, "id": str(e.item), "qty": int(e.get("qty", 0))})
					elif str(e.get("item", "")) == "" and int(e.get("slot", 0)) > 0:
						team_slots[int(e.slot) - 1] = pos
					if str(e.get("sp", "")) != "":
						fixed_mons.append({"pos": pos, "sp": str(e.sp), "behavior": str(e.get("behavior", "")),
							"red_sp": int(e.get("red_sp", 0))})
					if str(e.get("trap", "")) != "" and spawn_trap_item:
						fixed_traps.append({"pos": pos, "id": str(e.trap), "visible": bool(e.get("trap_visible", false))})
					if bool(e.get("secondary", false)):
						_tt_set(i, TT_SECONDARY)

	func build_output(moat: PackedByteArray, gen_attempts: int, spawn_attempts: int, tileset: int) -> Dictionary:
		var terrain := PackedByteArray()
		terrain.resize(N)
		var room := PackedByteArray()
		room.resize(N)
		var flags := PackedInt32Array()
		flags.resize(N)
		var items := []
		var traps := []
		var enemies := []
		var shop_min := Vector2i(9999, 9999)
		var shop_max := Vector2i(-1, -1)
		var room_min := {}
		var room_max := {}
		var any_mh := false
		for y in H:
			for x in W:
				var i := y * W + x
				var t := tf[i]
				terrain[i] = t & 3
				room[i] = rm[i] & 0xFF
				var f := 0
				if t & TF_IMPASSABLE: f |= FLAG_IMPASSABLE
				if t & TF_UNBREAKABLE: f |= FLAG_UNBREAKABLE
				if t & TF_JUNCTION: f |= FLAG_JUNCTION
				if t & TF_SHOP:
					f |= FLAG_SHOP
					shop_min = Vector2i(mini(shop_min.x, x), mini(shop_min.y, y))
					shop_max = Vector2i(maxi(shop_max.x, x), maxi(shop_max.y, y))
				if t & TF_MONSTER_HOUSE:
					f |= FLAG_MONSTER_HOUSE
					any_mh = true
				if t & TF_STAIRS: f |= FLAG_STAIRS
				if maze[i]: f |= FLAG_MAZE
				if (sp[i] & SP_TRAP) and (sp[i] & SP_UNK6): f |= FLAG_WARP
				if moat[i]: f |= FLAG_ISLAND_MOAT
				if sp[i] & SP_UNK5: f |= FLAG_SS_ROOM
				if t & TF_UNK_7: f |= FLAG_DIVIDER_HALF
				if Vector2i(x, y) == kecleon_mid: f |= FLAG_KECLEON
				flags[i] = f
				var pos := Vector2i(x, y)
				if (sp[i] & SP_ITEM) and not (t & TF_STAIRS):
					var kind := "normal"
					if t & TF_SHOP:
						kind = "shop"
					elif (t & 3) == TT_WALL:
						kind = "buried"
					elif t & TF_MONSTER_HOUSE:
						kind = "house"
					items.append({"pos": pos, "kind": kind})
				if sp[i] & SP_TRAP:
					traps.append(pos)
				if sp[i] & SP_MONSTER:
					enemies.append(pos)
				var r := rm[i]
				if r < 0xF0:
					if room_min.has(r):
						room_min[r] = Vector2i(mini(room_min[r].x, x), mini(room_min[r].y, y))
						room_max[r] = Vector2i(maxi(room_max[r].x, x), maxi(room_max[r].y, y))
					else:
						room_min[r] = pos
						room_max[r] = pos
		var rooms := []
		var max_r := -1
		for r in room_min.keys():
			max_r = maxi(max_r, r)
		for r in max_r + 1:
			if room_min.has(r):
				rooms.append(Rect2i(room_min[r], room_max[r] - room_min[r] + Vector2i.ONE))
			else:
				rooms.append(Rect2i())
		var shop := Rect2i()
		if shop_max.x >= 0:
			shop = Rect2i(shop_min, shop_max - shop_min + Vector2i.ONE)
		var sec_kind := "water"
		if LAVA_TILESETS.has(tileset):
			sec_kind = "lava"
		elif CHASM_TILESETS.has(tileset):
			sec_kind = "chasm"
		if fp.has("_sec_kind"):
			sec_kind = str(fp["_sec_kind"])      # Explorers of Sky floors: from SECONDARY_TERRAIN_TYPES
		return {
			"w": W, "h": H,
			"terrain": terrain,
			"room": room,
			"flags": flags,
			"stairs": stairs_spawn,
			"player": player_spawn,
			"items": items,
			"traps": traps,
			"enemies": enemies,
			"monster_house_room": monster_house_room if (any_mh and monster_house_room != 0xFF) else -1,
			"shop": shop,
			"kecleon": kecleon_mid,
			"rooms": rooms,
			"secondary_kind": sec_kind,
			"layout": layout_used,
			"gen_attempts": gen_attempts,
			"spawn_attempts": spawn_attempts,
			"fixed_room_skipped": p("fixedRoomNumber") != 0 and fp.get("_fixed", {}).is_empty(),
			"fixed_room": p("fixedRoomNumber") if not fp.get("_fixed", {}).is_empty() else 0,
			"fixed_floorwide": fixed_floorwide,
			"fixed_mons": fixed_mons,
			"team_slots": team_slots,
			"fixed_items": fixed_items,
			"fixed_traps": fixed_traps,
		}
