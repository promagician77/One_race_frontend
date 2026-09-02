class_name PartDetailsPanel
extends Control
## The part details panel, filled from the server.
##
## The artwork is a template: it paints the frame, the row labels and the two
## buttons, and leaves every value slot empty. Each slot is a rect measured off
## that template with tools/ArtProbe.gd, filled with a label placed in the
## artwork's own coordinates so it scales with the panel.
##
## The before-and-after columns come from /car/:id/part/preview. They are not
## worked out here: fitting a turbo changes power, weight, airflow, boost and
## stress at once, and the airflow match folds back into the power figure, so
## anything short of running the whole spec would be a second simulation to
## drift out of step with the first.

const ART := "res://assets/ui/part_shop_modal.png"
const ART_W := 1122.0
const ART_H := 1402.0

# Header block, left of the product shot ──────────────────────────
#
# The table panel's top edge is at y=404, measured off the template. Every
# rect here stops above it: the summary line used to run to 418 and was being
# cut in half by that edge.
const HEADER_BOTTOM := 404.0

const R_NAME     := Rect2(120, 218, 620, 56)
const R_BADGE    := Rect2(120, 278, 320, 36)
const R_LOCATION := Rect2(120, 316, 430, 36)
const R_SUMMARY  := Rect2(120, 354, 620, 36)

## The product shot, filling the header's right side. It starts below the
## corner decoration, which reaches down to about y=210, and stops inside the
## right border at x=1040.
const R_SHOT := Rect2(770, 214, 270, 186)

# Value slots. Rows sit on a 85px pitch from the first. ───────────
const ROW_TOP := 495.0
const ROW_PITCH := 85.0
const ROW_H := 48.0
const COL_BEFORE := Rect2(385, 0, 200, ROW_H)
const COL_AFTER  := Rect2(600, 0, 245, ROW_H)
const COL_DELTA  := Rect2(855, 0, 155, ROW_H)

const R_PRICE := Rect2(600, 947, 410, 48)
const R_BUY := Rect2(95, 1047, 935, 102)
const R_INSTALL := Rect2(105, 1190, 915, 48)

## The five rows the artwork paints, in order, and where each value comes
## from. `lower_is_better` flips the colour: putting weight on is a cost.
const ROWS := [
	{ "key": "peakHp", "unit": "HP", "lower_is_better": false },
	{ "key": "peakTorque", "unit": "LB-FT", "lower_is_better": false },
	{ "key": "totalWeight", "unit": "LB", "lower_is_better": true },
	{ "key": "redline", "unit": "RPM", "lower_is_better": false },
	{ "key": "gearCount", "unit": "", "lower_is_better": false },
]

signal buy_requested(part_id: String)
signal install_requested(part_id: String)

var frame: Control

var _part: Dictionary = {}
var _preview: Dictionary = {}
var _name: Label
var _badge: Label
var _location: Label
var _summary: Label
var _shot: TextureRect
var _price: Label
var _buy: Button
var _install: Button
var _cells: Array = []      ## [{ before, after, delta }] per row
var _scaled: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	_build()
	resized.connect(_rescale_type)


# ─────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────

func _build() -> void:
	var fitter := AspectRatioContainer.new()
	fitter.ratio = ART_W / ART_H
	fitter.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_END
	fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_BEGIN
	fitter.set_anchors_preset(Control.PRESET_FULL_RECT)
	fitter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fitter)

	frame = Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fitter.add_child(frame)

	if ResourceLoader.exists(ART):
		var art := TextureRect.new()
		art.texture = load(ART)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		# The panel takes its own clicks rather than passing them to the shelf.
		art.mouse_filter = Control.MOUSE_FILTER_STOP
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(art)
	else:
		push_warning("Part details art missing: %s" % ART)

	_name = _label(R_NAME, Design.TEXT_PRIME, 42, HORIZONTAL_ALIGNMENT_LEFT)
	Design.apply_display(_name)
	_badge = _label(R_BADGE, Design.INFO, 24, HORIZONTAL_ALIGNMENT_LEFT)
	_location = _label(R_LOCATION, Design.AMBER, 24, HORIZONTAL_ALIGNMENT_LEFT)
	_summary = _label(R_SUMMARY, Design.TEXT_MUTED, 22, HORIZONTAL_ALIGNMENT_LEFT)

	_shot = TextureRect.new()
	_shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_shot, R_SHOT)

	for i in ROWS.size():
		var top := ROW_TOP + ROW_PITCH * float(i)
		_cells.append({
			"before": _label(_at(COL_BEFORE, top), Design.TEXT_BODY, 28,
				HORIZONTAL_ALIGNMENT_CENTER),
			"after": _label(_at(COL_AFTER, top), Design.TEXT_PRIME, 28,
				HORIZONTAL_ALIGNMENT_CENTER),
			"delta": _label(_at(COL_DELTA, top), Design.TEXT_MUTED, 26,
				HORIZONTAL_ALIGNMENT_CENTER),
		})

	_price = _label(R_PRICE, Design.AMBER, 34, HORIZONTAL_ALIGNMENT_RIGHT)
	Design.apply_display(_price)

	_buy = _hit(R_BUY, "Buy this part")
	_buy.pressed.connect(_on_buy)
	_install = _hit(R_INSTALL, "Fit it to your car")
	_install.pressed.connect(_on_install)


func _at(col: Rect2, top: float) -> Rect2:
	return Rect2(col.position.x, top, col.size.x, col.size.y)


func _label(r: Rect2, colour: Color, size: int, align: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", colour)
	_place(l, r)
	_scaled.append({"node": l, "size": size})
	return l


func _hit(r: Rect2, tooltip: String) -> Button:
	var b := Button.new()
	b.text = ""
	b.flat = true
	b.tooltip_text = tooltip

	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	var hover: StyleBoxFlat = clear.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.10)
	var pressed: StyleBoxFlat = clear.duplicate()
	pressed.bg_color = Color(0, 0, 0, 0.20)
	var focus: StyleBoxFlat = clear.duplicate()
	focus.border_color = Design.AMBER
	focus.set_border_width_all(2)

	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", clear)
	b.add_theme_stylebox_override("focus", focus)
	_place(b, r)
	return b


func _place(node: Control, r: Rect2) -> void:
	node.anchor_left = r.position.x / ART_W
	node.anchor_top = r.position.y / ART_H
	node.anchor_right = (r.position.x + r.size.x) / ART_W
	node.anchor_bottom = (r.position.y + r.size.y) / ART_H
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	frame.add_child(node)


## Type is sized against the panel's real height, so it tracks the window.
func _rescale_type() -> void:
	if frame == null:
		return
	var factor: float = clampf(frame.size.y / ART_H, 0.15, 3.0)
	for entry in _scaled:
		var l: Label = entry["node"]
		l.add_theme_font_size_override("font_size",
			maxi(9, roundi(float(entry["size"]) * factor)))


# ─────────────────────────────────────────────────────────────
# FILLING
# ─────────────────────────────────────────────────────────────

## Show a part. `preview` is the server's answer for this part on this car, or
## empty when there is no car to fit it to.
func show_part(part: Dictionary, preview: Dictionary, shot_path: String) -> void:
	_part = part
	_preview = preview
	visible = true

	_name.text = str(part.get("name", "")).to_upper()
	_badge.text = "TIER %d  ·  %s" % [int(part.get("tier", 1)), str(part.get("category", ""))]

	var hood := Catalog.get_neighborhood(str(part.get("neighborhood", "")))
	_location.text = str(hood.get("name", part.get("neighborhood", ""))).to_upper()
	_summary.text = _summarise(part)

	if shot_path != "" and ResourceLoader.exists(shot_path):
		_shot.texture = load(shot_path)
		_shot.visible = true
	else:
		_shot.visible = false

	# The price shown is the price charged: a part replacing a fitted one
	# trades the old one in at 40%, and the server's preview says so.
	var already := bool(preview.get("alreadyFitted", false))
	var trade_in := int(preview.get("tradeIn", 0))
	if already:
		_price.text = "FITTED"
		_price.add_theme_color_override("font_color", Design.GOOD)
	elif trade_in > 0:
		_price.text = "%s AFTER TRADE-IN" % Design.fmt_cash(int(preview.get("netPrice", part.get("price", 0))))
		_price.add_theme_color_override("font_color", Design.AMBER)
	else:
		_price.text = Design.fmt_cash(int(part.get("price", 0)))
		_price.add_theme_color_override("font_color", Design.AMBER)

	# Nothing to buy when it is already on the car.
	if _buy != null:
		_buy.disabled = already
	if _install != null:
		_install.disabled = already

	_fill_rows()
	_rescale_type()


## A line of what the part actually is, built from its own numbers. The parts
## data carries no prose, and inventing flavour text for forty-eight parts
## would be writing fiction into a data file.
func _summarise(part: Dictionary) -> String:
	var bits := PackedStringArray()
	if int(part.get("airFlow", 0)) > 0:
		bits.append("%d cfm" % int(part.airFlow))
	if int(part.get("boostPsi", 0)) > 0:
		bits.append("%d psi" % int(part.boostPsi))
	if int(part.get("hpMod", 0)) != 0:
		bits.append("%+d hp" % int(part.hpMod))
	if int(part.get("weightMod", 0)) != 0:
		bits.append("%+d lb" % int(part.weightMod))
	if bits.is_empty():
		return "Fit and see."
	return ", ".join(bits)


func _fill_rows() -> void:
	var before: Dictionary = _preview.get("before", {})
	var after: Dictionary = _preview.get("after", {})
	var have := not before.is_empty()

	for i in ROWS.size():
		var row: Dictionary = ROWS[i]
		var cells: Dictionary = _cells[i]
		var key: String = str(row.key)
		var unit: String = str(row.unit)

		if not have:
			cells.before.text = "—"
			cells.after.text = "—"
			cells.delta.text = ""
			continue

		# Redline and gear count are answered by the server directly: no part
		# in this game alters either, but the artwork has a row for each.
		var b: int = int(before.get(key, _preview.get(key, 0)))
		var a: int = int(after.get(key, _preview.get(key, 0)))

		cells.before.text = _value(b, unit)
		cells.after.text = _value(a, unit)

		var diff := a - b
		if diff == 0:
			cells.delta.text = "—"
			cells.delta.add_theme_color_override("font_color", Design.TEXT_DIM)
		else:
			var better: bool = (diff < 0) if bool(row.lower_is_better) else (diff > 0)
			cells.delta.text = "%+d %s" % [diff, unit] if unit != "" else "%+d" % diff
			cells.delta.add_theme_color_override("font_color",
				Design.GOOD if better else Design.BAD)

		cells.after.add_theme_color_override("font_color",
			Design.TEXT_PRIME if diff == 0 else Design.GOOD)


func _value(v: int, unit: String) -> String:
	return "%d %s" % [v, unit] if unit != "" else str(v)


func hide_panel() -> void:
	visible = false


func _on_buy() -> void:
	buy_requested.emit(str(_part.get("id", "")))


func _on_install() -> void:
	install_requested.emit(str(_part.get("id", "")))
