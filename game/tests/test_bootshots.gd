extends Node
## --bootshots: run the normal boot, press A once at 4 s (the health screen) and save a frame every 0.5 s
## to user://boot_NNN.png (60 s).
var t := 0.0
var total := 0.0
var n := 0
var pressed := false
func _ready() -> void:
	GAction.trace = true
func _process(dt: float) -> void:
	t += dt
	total += dt
	if total > 4.0 and not pressed:
		pressed = true
		var e := InputEventAction.new()
		e.action = "ui_accept"
		e.pressed = true
		Input.parse_input_event(e)
		var r := InputEventAction.new()
		r.action = "ui_accept"
		r.pressed = false
		get_tree().create_timer(0.1).timeout.connect(func(): Input.parse_input_event(r))
	if t >= 0.5:
		t = 0.0
		get_viewport().get_texture().get_image().save_png("user://boot_%03d.png" % n)
		print("SHOT %d" % n)
		n += 1
		if n >= 120:
			get_tree().quit()
