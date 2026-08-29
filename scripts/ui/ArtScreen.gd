class_name ArtScreen
extends Control
## Base for screens whose artwork already contains the interface.
##
## The image is shown whole and interactive parts are transparent controls
## placed exactly over the painted ones. Hit areas are declared in source-image
## pixels and converted to anchors, so the overlay tracks the art at any window
## size. Subclasses set `art_path` / `art_w` / `art_h`, then call `build_art()`.

## Interior of a painted input box, shown only while a field is in use.
const FIELD_FILL := Color("#131C28")
const FIELD_FONT_SIZE := 19

## Outline every hit area and enable live nudging. See _unhandled_key_input.
const DEBUG_HITBOXES := false

var art_path := ""
var art_w := 1672.0
var art_h := 941.0

var frame: Control
var status_label: Label
var status_bg: ColorRect

## Calibration bookkeeping: name -> { "node": Control, "rect": Rect2 }.
var _placed: Dictionary = {}
var _placed_order: Array = []
var _calib_index := 0


# ─────────────────────────────────────────────────────────────
# ART
# ─────────────────────────────────────────────────────────────

func build_art() -> void:
	var ground := ColorRect.new()
	ground.color = Design.BG_VOID
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	# Art and window are both 16:9, so cover fills edge to edge with no bars.
	# On an unusually wide display this crops a sliver top and bottom rather
	# than showing black, which is the right trade for a full-bleed splash.
	var fitter := AspectRatioContainer.new()
	fitter.ratio = art_w / art_h
	fitter.stretch_mode = AspectRatioContainer.STRETCH_COVER
	fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	fitter.set_anchors_preset(Control.PRESET_FULL_RECT)
	fitter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fitter)

	frame = Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fitter.add_child(frame)

	if ResourceLoader.exists(art_path):
		var backing := ColorRect.new()
		backing.color = Design.BG_VOID
		backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backing.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(backing)

		var art := TextureRect.new()
		art.texture = load(art_path)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(art)
	else:
		push_warning("Screen art missing: %s" % art_path)


## Message line. The artwork has no error state, so this takes over the
## decorative tagline strip -- the one place with room to read a sentence.
func build_status(rect: Rect2) -> void:
	status_bg = ColorRect.new()
	status_bg.color = Color(0.02, 0.03, 0.05, 0.93)
	status_bg.visible = false
	status_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(status_bg, rect)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", Design.BAD)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(status_label, rect)


func show_status(message: String, color: Color) -> void:
	status_label.add_theme_color_override("font_color", color)
	status_label.text = message
	status_bg.visible = true


func clear_status() -> void:
	status_label.text = ""
	status_bg.visible = false


# ─────────────────────────────────────────────────────────────
# CONTROLS
# ─────────────────────────────────────────────────────────────

## A field over a painted input box.
##
## The placeholder is part of the artwork, so this draws none of its own and
## stays fully transparent while empty and unfocused -- at rest the box is
## pixel-for-pixel the mockup. The mask appears only once there is something
## to hide behind: a caret, or typed text.
func make_field(secret: bool) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = ""
	f.secret = secret
	f.add_theme_font_size_override("font_size", FIELD_FONT_SIZE)
	f.add_theme_color_override("font_color", Design.TEXT_PRIME)
	f.add_theme_color_override("caret_color", Design.AMBER)

	f.add_theme_stylebox_override("normal", _field_box(false))
	f.add_theme_stylebox_override("focus", _field_box(false))
	f.add_theme_stylebox_override("read_only", _field_box(false))

	f.text_changed.connect(_on_field_changed.bind(f))
	f.focus_entered.connect(sync_field_mask.bind(f))
	f.focus_exited.connect(sync_field_mask.bind(f))
	return f


func _field_box(masked: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = FIELD_FILL if masked else Color(0, 0, 0, 0)
	box.content_margin_left = 6
	box.content_margin_right = 6
	return box


func _on_field_changed(_text: String, f: LineEdit) -> void:
	sync_field_mask(f)


func sync_field_mask(f: LineEdit) -> void:
	var mask := f.has_focus() or f.text != ""
	f.add_theme_stylebox_override("normal", _field_box(mask))
	f.add_theme_stylebox_override("focus", _field_box(mask))


## A transparent button sized to a painted one. The art supplies the look;
## this supplies the click, the hover lift and keyboard focus.
func make_hit(tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = ""
	b.tooltip_text = tooltip
	b.flat = true

	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)

	var hover: StyleBoxFlat = clear.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.10)

	var pressed: StyleBoxFlat = clear.duplicate()
	pressed.bg_color = Color(0, 0, 0, 0.18)

	var focus: StyleBoxFlat = clear.duplicate()
	focus.border_color = Design.AMBER
	focus.set_border_width_all(2)

	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", clear)
	b.add_theme_stylebox_override("focus", focus)
	return b


# ─────────────────────────────────────────────────────────────
# PLACEMENT
# ─────────────────────────────────────────────────────────────

## Position a control over a rect measured in source-image pixels.
func place(node: Control, r: Rect2, tag: String = "") -> void:
	apply_rect(node, r)
	frame.add_child(node)

	if DEBUG_HITBOXES:
		var outline := ReferenceRect.new()
		outline.border_color = Design.AMBER
		outline.editor_only = false
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.set_anchors_preset(Control.PRESET_FULL_RECT)
		node.add_child(outline)

		var key := tag if tag != "" else "rect_%d" % _placed_order.size()
		_placed[key] = {"node": node, "rect": r}
		_placed_order.append(key)


func apply_rect(node: Control, r: Rect2) -> void:
	node.anchor_left = r.position.x / art_w
	node.anchor_top = r.position.y / art_h
	node.anchor_right = (r.position.x + r.size.x) / art_w
	node.anchor_bottom = (r.position.y + r.size.y) / art_h
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0


# ─────────────────────────────────────────────────────────────
# CALIBRATION  (only live while DEBUG_HITBOXES is on)
#
#   TAB          select the next hit area
#   ARROWS       move it by one source pixel   (SHIFT = 10)
#   CTRL+ARROWS  resize it
#   ENTER        print every rect, ready to paste back into the constants
# ─────────────────────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not DEBUG_HITBOXES or _placed_order.is_empty():
		return
	if not (event is InputEventKey) or not event.pressed:
		return

	var key := event as InputEventKey

	if key.keycode == KEY_TAB:
		_calib_index = (_calib_index + 1) % _placed_order.size()
		_highlight_selection()
		get_viewport().set_input_as_handled()
		return

	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_dump_rects()
		get_viewport().set_input_as_handled()
		return

	var step := 10.0 if key.shift_pressed else 1.0
	var delta := Vector2.ZERO
	match key.keycode:
		KEY_LEFT:  delta = Vector2(-step, 0)
		KEY_RIGHT: delta = Vector2(step, 0)
		KEY_UP:    delta = Vector2(0, -step)
		KEY_DOWN:  delta = Vector2(0, step)
		_:         return

	var rect_name: String = _placed_order[_calib_index]
	var entry: Dictionary = _placed[rect_name]
	var r: Rect2 = entry["rect"]
	if key.ctrl_pressed:
		r.size += delta
	else:
		r.position += delta
	entry["rect"] = r
	apply_rect(entry["node"], r)

	print("  %s  Rect2(%d, %d, %d, %d)"
		% [rect_name, r.position.x, r.position.y, r.size.x, r.size.y])
	get_viewport().set_input_as_handled()


func _highlight_selection() -> void:
	for i in _placed_order.size():
		var entry: Dictionary = _placed[_placed_order[i]]
		var node: Control = entry["node"]
		for child in node.get_children():
			if child is ReferenceRect:
				child.border_color = Design.GOOD if i == _calib_index else Design.AMBER
	print("  selected: %s" % _placed_order[_calib_index])


func _dump_rects() -> void:
	print("\n--- paste into the screen script ---")
	for rect_name in _placed_order:
		var r: Rect2 = _placed[rect_name]["rect"]
		print("const %s := Rect2(%d, %d, %d, %d)"
			% [rect_name, r.position.x, r.position.y, r.size.x, r.size.y])
	print("--- end ---\n")
