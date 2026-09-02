class_name AngularPlate
extends Control
## A chamfered plate, drawn to match the artwork's own edges.
##
## The frames in this game are angular: corners are cut, not rounded, and the
## lit edge is heavier on one side. A StyleBoxFlat cannot do that -- its
## corners are either square or round -- so a control that has to sit *in* the
## artwork rather than on top of it is drawn instead.

var fill: Color = Color("#05080C"):
	set(v):
		fill = v
		queue_redraw()

var edge: Color = Color("#2E363F"):
	set(v):
		edge = v
		queue_redraw()

## The lit line along the bottom, the way the panels carry theirs.
var accent: Color = Color("#F0A020"):
	set(v):
		accent = v
		queue_redraw()

## How far the corners are cut, in pixels.
var cut := 10.0:
	set(v):
		cut = v
		queue_redraw()

var thickness := 1.0:
	set(v):
		thickness = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return

	var c: float = minf(cut, minf(w, h) * 0.4)

	# Cut at the two left corners and the two right, so it reads as machined
	# rather than as a rounded button.
	var shape := PackedVector2Array([
		Vector2(c, 0), Vector2(w - c, 0),
		Vector2(w, c), Vector2(w, h - c),
		Vector2(w - c, h), Vector2(c, h),
		Vector2(0, h - c), Vector2(0, c),
	])

	draw_colored_polygon(shape, fill)

	var outline := shape.duplicate()
	outline.append(shape[0])
	draw_polyline(outline, edge, thickness, true)

	# The lit underline, inset past the chamfers so it stops where the cut
	# begins rather than running into the corner.
	draw_line(Vector2(c, h - thickness), Vector2(w - c, h - thickness),
		accent, thickness * 2.0, true)
