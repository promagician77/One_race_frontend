extends Control
## Placeholder for screens not yet built. Shows what lands here and when,
## so clicking into an unfinished area explains itself instead of crashing.

@export var screen_title: String = "Coming soon"
@export var milestone: String = "M2"
@export var blurb: String = ""


func _ready() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Design.SP_3)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var tag := UIKit.badge(milestone, Design.AMBER)
	tag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(tag)

	var h := UIKit.heading(screen_title, Design.SIZE_TITLE)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(h)

	if blurb != "":
		var b := UIKit.body(blurb, Design.TEXT_MUTED)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(380, 0)
		box.add_child(b)

	box.add_child(UIKit.spacer(Design.SP_2))

	var back := UIKit.button("Back to map", UIKit.BtnStyle.SECONDARY)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(Router.home)
	box.add_child(back)

	center.add_child(box)


## Context from the Router, shown so you can verify navigation is passing
## the right neighborhood through before the real screen exists.
func _enter_tree() -> void:
	if Router.context.has("neighborhood") and Router.context.neighborhood != "":
		var hood := Catalog.get_neighborhood(Router.context.neighborhood)
		blurb = "Opened from %s.\n%s" % [hood.get("name", "?"), blurb]
