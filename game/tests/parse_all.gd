extends SceneTree
func _init():
	for f in ["res://scripts/core/db.gd","res://scripts/core/game.gd","res://scripts/core/audio.gd","res://scripts/core/mon.gd","res://scripts/core/combat.gd","res://scripts/dungeon/floor_state.gd","res://scripts/dungeon/terrain_view.gd","res://scripts/dungeon/mon_sprite.gd","res://scripts/ui/ui_theme.gd","res://scripts/ui/list_menu.gd","res://scripts/ui/hud.gd","res://scripts/ui/mon_preview.gd"]:
		var s = load(f)
		print(f, " -> ", "OK" if s and s.can_instantiate() else "FAIL")
	quit()
