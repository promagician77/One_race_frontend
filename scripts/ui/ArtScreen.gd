class_name ArtScreen
extends Control
## Base for screens whose artwork already contains the interface.
##
## The image is shown whole and interactive parts are transparent controls
## placed exactly over the painted ones. Hit areas are declared in source-image
## pixels and converted to anchors, so the overlay tracks the art at any window
## size. Subclasses set `art_path` / `art_w` / `art_h`, then call `build_art()`.

## Interior of a painted input box, sampled from the artwork. The patch that
## hides the placeholder painted into the box is filled with it, so the box
## reads as untouched art while the live field supplies the words itself.
const FIELD_MASK := Color("#030B16")

## How far the painted words clear the box border. The patch stops there too:
## nearer the edge the interior picks up the box glow and a flat fill shows.
const FIELD_MASK_INSET := 8.0

## Matches the cap height painted into the boxes. Design.SIZE_SUB.
const FIELD_FONT_SIZE := 17

# How much amber a hit area washes itself with, by state. Kept low: the paint
# underneath is already the button, and this only has to acknowledge a touch.
const HIT_HOVER := 0.07
const HIT_PRESSED := 0.18
const HIT_FOCUS := 0.13

## How hard a painted icon lights when touched, as a share of its own colour
## added back over itself. See make_icon_hit.
const ICON_LIT := 0.30

# ── Notice panel ─────────────────────────────────────────────
const NOTICE_ART := "res://assets/ui/notification.png"
const NOTICE_ART_W := 2508.0
const NOTICE_ART_H := 627.0

## Top right, clear of the logo and hard against the corner. In source-image
## pixels like every other rect here.
const R_NOTICE := Rect2(976, 28, 660, 165)

## The two compartments painted into the banner, in its own pixels.
const R_NOTICE_MARK := Rect2(150, 140, 330, 300)
const R_NOTICE_TEXT := Rect2(700, 170, 1570, 290)

const NOTICE_FONT_SIZE := 19
const NOTICE_MARK_SIZE := 44
const NOTICE_SLIDE := 0.32
const NOTICE_HOLD := 4.5

## Outline every hit area and enable live nudging. See _unhandled_key_input.
const DEBUG_HITBOXES := false

var art_path := ""
var art_w := 1672.0
var art_h := 941.0

var art_texture: Texture2D
var frame: Control
var notice: Control
var notice_label: Label
var notice_mark: Label
var _notice_tween: Tween

## Whether whatever holds focus now was given it by the keyboard. One flag for
## the screen is enough -- only one control holds focus at a time.
var _focus_by_key := false

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

		art_texture = load(art_path)

		var art := TextureRect.new()
		art.texture = art_texture
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(art)
	else:
		push_warning("Screen art missing: %s" % art_path)


## The notice panel: its own painted banner rather than a patch over the
## tagline strip, parked in the top right corner of every art screen.
##
## Nothing about it is per-screen -- a message belongs in the same place
## wherever the player reads it -- so the rect lives here, not in a subclass.
func build_notice() -> void:
	notice = Control.new()
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.visible = false
	place(notice, R_NOTICE)

	if ResourceLoader.exists(NOTICE_ART):
		var body := TextureRect.new()
		body.texture = load(NOTICE_ART)
		body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		body.stretch_mode = TextureRect.STRETCH_SCALE
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.set_anchors_preset(Control.PRESET_FULL_RECT)
		notice.add_child(body)
	else:
		push_warning("Notice art missing: %s" % NOTICE_ART)

	# The banner is painted with an empty compartment on the left, where the
	# tagline strip carries its trophy. One character of severity fills it.
	notice_mark = Label.new()
	notice_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_mark.add_theme_font_size_override("font_size", NOTICE_MARK_SIZE)
	notice_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Design.apply_display(notice_mark)
	_fit_notice(notice_mark, R_NOTICE_MARK)
	notice.add_child(notice_mark)

	notice_label = Label.new()
	notice_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.add_theme_font_size_override("font_size", NOTICE_FONT_SIZE)
	notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fit_notice(notice_label, R_NOTICE_TEXT)
	notice.add_child(notice_label)


## Anchors a compartment inside the notice by its place in the banner art, so
## the two stay registered to the paint at whatever size the panel is drawn.
func _fit_notice(node: Control, r: Rect2) -> void:
	node.anchor_left = r.position.x / NOTICE_ART_W
	node.anchor_top = r.position.y / NOTICE_ART_H
	node.anchor_right = (r.position.x + r.size.x) / NOTICE_ART_W
	node.anchor_bottom = (r.position.y + r.size.y) / NOTICE_ART_H
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0


## Streams the notice in from off the right edge, holds it long enough to
## read, and streams it back out.
##
## A message arriving while one is up does not restart the entrance -- the
## slide runs from wherever the panel already is, which is a no-op when it is
## parked, so the text swaps in place and only the clock starts over.
func show_status(message: String, color: Color) -> void:
	notice_label.add_theme_color_override("font_color", color)
	notice_label.text = message
	notice_mark.add_theme_color_override("font_color", color)
	notice_mark.text = "!" if color == Design.BAD or color == Design.WARN else "i"

	if not notice.visible:
		_slide_notice(_notice_travel())
		notice.modulate.a = 0.0
		notice.visible = true

	var t := _restart_notice_tween()
	t.tween_method(_slide_notice, notice.offset_left, 0.0, NOTICE_SLIDE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(notice, "modulate:a", 1.0, NOTICE_SLIDE)
	t.tween_interval(NOTICE_HOLD)
	# Parked by the time this runs, whatever the panel was doing before.
	_stream_notice_out(t, 0.0)


func clear_status() -> void:
	if not notice.visible:
		return
	_stream_notice_out(_restart_notice_tween(), notice.offset_left)


## The way out, shared by the auto-dismiss and by clearing: back the way it
## came, easing in this time so it leaves faster than it arrived. `from` is
## passed in because a tweener is built long before it runs -- reading the
## offset here would read where the panel sits now, not where it will be.
func _stream_notice_out(t: Tween, from: float) -> void:
	t.tween_method(_slide_notice, from, _notice_travel(), NOTICE_SLIDE) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(notice, "modulate:a", 0.0, NOTICE_SLIDE)
	t.tween_callback(_hide_notice)


func _restart_notice_tween() -> Tween:
	if _notice_tween and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	return _notice_tween


## How far right the panel has to go to clear the screen. Measured off the
## live frame, so it is right at any window size.
func _notice_travel() -> float:
	return frame.size.x * (1.0 - notice.anchor_left)


func _slide_notice(dx: float) -> void:
	notice.offset_left = dx
	notice.offset_right = dx


func _hide_notice() -> void:
	notice.visible = false
	notice_label.text = ""


# ─────────────────────────────────────────────────────────────
# CONTROLS
# ─────────────────────────────────────────────────────────────

## A field over a painted input box.
##
## The box is part of the artwork, so the field draws no background of its own
## in any state. The prompt is a different matter: painted words cannot clear
## when the player types, so the field owns them and `place_field` hides the
## painted pair behind a patch the colour of the box interior.
func make_field(placeholder: String, secret: bool) -> LineEdit:
	var f := LineEdit.new()
	f.placeholder_text = placeholder
	f.secret = secret
	f.add_theme_font_size_override("font_size", FIELD_FONT_SIZE)
	f.add_theme_color_override("font_color", Design.TEXT_PRIME)
	f.add_theme_color_override("font_placeholder_color", Design.TEXT_MUTED)
	f.add_theme_color_override("caret_color", Design.AMBER)

	f.add_theme_stylebox_override("normal", _field_box())
	f.add_theme_stylebox_override("focus", _field_box())
	f.add_theme_stylebox_override("read_only", _field_box())
	return f


## Places a field over a painted box. `rect` is the interior of the box, so
## the whole box is clickable and the text lands on the painted line.
##
## The patch rides along as a child drawn behind the field, which keeps it
## on the box when a rect is nudged during calibration. It is anchored rather
## than offset so the inset scales with the art like everything else.
func place_field(f: LineEdit, rect: Rect2, tag: String = "") -> void:
	var inset := FIELD_MASK_INSET / rect.size.y

	var mask := ColorRect.new()
	mask.color = FIELD_MASK
	mask.show_behind_parent = true
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.anchor_left = 0.0
	mask.anchor_right = 1.0
	mask.anchor_top = inset
	mask.anchor_bottom = 1.0 - inset
	mask.offset_left = 0
	mask.offset_top = 0
	mask.offset_right = 0
	mask.offset_bottom = 0
	f.add_child(mask)

	place(f, rect, tag)


## The left margin carries the text clear of the painted icon, onto the column
## the artwork starts its own prompt on.
func _field_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0)
	box.content_margin_left = 6
	box.content_margin_right = 6
	return box


## A transparent button sized to a painted one. The art supplies the look;
## this supplies the click, the hover lift and keyboard focus.
##
## Feedback is a wash of amber inside the painted button, never an outline
## around it: the painted buttons are rounded and glowing, and a hard
## rectangle laid over one reads as a defect rather than a cue. `flat` stays
## off so the hover and pressed washes actually draw -- a flat Button skips
## its state styleboxes.
func make_hit(tooltip: String = "") -> Button:
	var b := Button.new()
	b.text = ""
	b.tooltip_text = tooltip

	b.add_theme_stylebox_override("normal", _hit_box(0.0))
	b.add_theme_stylebox_override("disabled", _hit_box(0.0))
	b.add_theme_stylebox_override("hover", _hit_box(HIT_HOVER))
	b.add_theme_stylebox_override("pressed", _hit_box(HIT_PRESSED))
	# Held under the cursor is its own state, and an unstyled one falls back
	# to Godot's default panel -- the loudest thing that could land on the art.
	b.add_theme_stylebox_override("hover_pressed", _hit_box(HIT_PRESSED))
	b.add_theme_stylebox_override("focus", _hit_box(0.0))

	# Both, because focus_entered misses a click on the already-focused button.
	b.focus_entered.connect(_sync_hit_focus.bind(b))
	b.button_down.connect(_sync_hit_focus.bind(b))
	return b


## Focus is worth showing to someone tabbing through the screen and nothing
## but litter to someone who just clicked -- they know what they hit, and the
## old outline stayed on the button long after the click that put it there.
## A held mouse button separates the two: a click takes focus on the way down.
func _sync_hit_focus(b: Button) -> void:
	_focus_by_key = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	b.add_theme_stylebox_override("focus", _hit_box(HIT_FOCUS if _focus_by_key else 0.0))


func _hit_box(amber: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Design.AMBER, amber)
	box.set_corner_radius_all(Design.RADIUS_MD)
	return box


## A hit area over a painted icon rather than a painted button.
##
## These are cut-out shapes -- hexagons, on the auth screens -- and a wash
## boxes in something that is not a box. So nothing is washed. The icon lights
## itself instead: its own patch of the artwork is drawn back over itself with
## additive blending, which brightens the lit pixels and adds nothing at all
## to the dark ones, most of the rect. The glow is exactly the icon's shape
## because it *is* the icon.
func place_icon_hit(rect: Rect2, tooltip: String, tag: String = "") -> Button:
	var b := Button.new()
	b.text = ""
	b.tooltip_text = tooltip
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, _hit_box(0.0))

	var patch := AtlasTexture.new()
	patch.atlas = art_texture
	patch.region = rect

	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	var glow := TextureRect.new()
	glow.texture = patch
	glow.material = blend
	glow.modulate = Color(1, 1, 1, 0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(glow)

	b.focus_entered.connect(_on_icon_focus.bind(b, glow))
	b.button_down.connect(_on_icon_focus.bind(b, glow))
	for changed in [b.focus_exited, b.mouse_entered, b.mouse_exited]:
		changed.connect(_sync_icon_glow.bind(b, glow))

	place(b, rect, tag)
	return b


func _on_icon_focus(b: Button, glow: TextureRect) -> void:
	_focus_by_key = not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_sync_icon_glow(b, glow)


## `is_hovered()` is no use here: Control emits mouse_exited before BaseButton
## clears its own hover flag, so the button still reads as hovered inside the
## handler. Where the pointer actually is does not have that problem.
func _sync_icon_glow(b: Button, glow: TextureRect) -> void:
	var under_pointer := b.get_global_rect().has_point(b.get_global_mouse_position())
	var lit := under_pointer or (b.has_focus() and _focus_by_key)
	glow.modulate = Color(1, 1, 1, ICON_LIT if lit else 0.0)


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
