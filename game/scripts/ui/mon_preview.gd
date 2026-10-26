class_name MonPreview
extends Node2D
## Big idle sprite + name/type card used on the starter pick screen.

var spr: MonSprite
var label: Label
var mon: Mon

func _ready() -> void:
	label = Label.new()
	label.theme = UITheme.theme()
	label.position = Vector2(-60, 40)
	label.size = Vector2(120, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)

func show_species(sp: String) -> void:
	if spr:
		spr.queue_free()
	mon = DB.make_mon(sp, 5, "team")
	spr = MonSprite.new()
	spr.scale = Vector2(3, 3)
	add_child(spr)
	spr.setup(mon)
	var S: Dictionary = DB.species[sp]
	label.text = "%s\n%s" % [S.name, "/".join(S.types)]
