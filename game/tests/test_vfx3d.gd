extends Node
## --vfx3d [--cam=0|1|2] [--old]: the 3D view with a move animation on a Pokémon standing under a wall:
## user://vfx3d_<cam>_<n>.png. Checks that effects sit on the figure and figures stay in front of walls / floor.
var m

func _ready() -> void:
	m = get_parent()
	var cam := 1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam="):
			cam = int(a.substr(6))
	Game.new_game("0004", "Charmander", "0007", "Squirtle", "Q")
	Game.settings.vox_view = 1
	Game.settings.vox_cam = cam
	Game.settings.zoom = 2.0
	await m.start_dungeon("tiny_woods", 0)
	await get_tree().create_timer(2.0).timeout
	var d = m.dungeon
	var fs = d.fs
	var L = fs.leader
	# a floor tile with a wall to the north and floor to the east and west
	var spot := Vector2i(-1, -1)
	for y in range(2, fs.h - 2):
		for x in range(2, fs.w - 2):
			var p := Vector2i(x, y)
			if fs.walkable(p) and fs.is_wall(p + Vector2i(0, -1)) and fs.walkable(p + Vector2i(1, 0)) and fs.walkable(p + Vector2i(-1, 0)) and fs.walkable(p + Vector2i(0, 1)):
				spot = p
				break
		if spot.x >= 0:
			break
	var foe = null
	for o in fs.mons:
		if o != L and not o.is_team():
			foe = o
			break
	for o in fs.mons:
		if o != L and o != foe:
			o.pos = Vector2i(1, 1)
			if o.visual:
				o.visual.visible = false
	L.pos = spot + Vector2i(-1, 0)
	if foe:
		foe.pos = spot
		foe.facing = 0
	L.facing = 2
	d._snap_visuals()
	d.cam.position = d._px(spot)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://vfx3d_%d_0.png" % cam)
	var mv: Dictionary = DB.moves.get("ember", {}) if DB.moves.has("ember") else {}
	MoveFx.play(d, L, "Ember", mv, 2, [foe])
	for i in 4:
		await get_tree().create_timer(0.12).timeout
		get_viewport().get_texture().get_image().save_png("user://vfx3d_%d_%d.png" % [cam, i + 1])
	print("VFX3D cam=", cam, " spot=", spot, " fig_k=", MonSprite.fig_k)
	get_tree().quit()
