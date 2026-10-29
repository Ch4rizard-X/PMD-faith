extends Node
## --pickshot: screenshots of the new-game choice menus (how to choose, Who will you be?).
func _ready() -> void:
	var m = get_parent()
	await get_tree().create_timer(0.5).timeout
	m.story_choose_team()
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://pick_how.png")
	for k in 2:
		var ev := InputEventAction.new(); ev.action = "ui_down"; ev.pressed = true; Input.parse_input_event(ev)
		await get_tree().create_timer(0.1).timeout
		var eu := InputEventAction.new(); eu.action = "ui_down"; eu.pressed = false; Input.parse_input_event(eu)
		await get_tree().create_timer(0.1).timeout
	var e2 := InputEventAction.new(); e2.action = "ui_accept"; e2.pressed = true; Input.parse_input_event(e2)
	await get_tree().create_timer(0.1).timeout
	var e3 := InputEventAction.new(); e3.action = "ui_accept"; e3.pressed = false; Input.parse_input_event(e3)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png("user://pick_who.png")
	for k in 10:
		var ev := InputEventAction.new(); ev.action = "ui_down"; ev.pressed = true; Input.parse_input_event(ev)
		await get_tree().create_timer(0.1).timeout
		var eu := InputEventAction.new(); eu.action = "ui_down"; eu.pressed = false; Input.parse_input_event(eu)
		await get_tree().create_timer(0.1).timeout
	get_viewport().get_texture().get_image().save_png("user://pick_who2.png")
	var a := InputEventAction.new(); a.action = "ui_accept"; a.pressed = true; Input.parse_input_event(a)
	await get_tree().create_timer(0.1).timeout
	var b := InputEventAction.new(); b.action = "ui_accept"; b.pressed = false; Input.parse_input_event(b)
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://pick_confirm.png")
	get_tree().quit()
