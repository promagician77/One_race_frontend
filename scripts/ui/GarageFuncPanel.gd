class_name GarageFuncPanel
extends Control
## The car panel on the right of the garage, filled from the server.
##
## The artwork is a template: it paints the frame, the row captions and the
## four buttons, and leaves every value slot empty. Each slot is a rect
## measured off that template with tools/ArtProbe.gd and filled with a label
## placed in the artwork's own coordinates, so it scales with the panel.
##
## Three of the six stats have no answer yet -- see ROWS.

const ART := "res://assets/ui/garage_func.png"
const ART_W := 971.0
const ART_H := 1619.0

## The file has no alpha at all -- it is fully opaque, so it arrives as a black
## slab over the garage floor. Only its chamfered corners are true black; the
## panel's own interior sits around 0.02 luminance. The key below removes the
## corners without touching the panel.
const CORNER_CUT_LOW := 0.002
const CORNER_CUT_HIGH := 0.010
const CORNER_REACH := 0.13

# The header the artwork leaves empty ─────────────────────────────
const R_NAME := Rect2(88, 34, 620, 68)
const R_CLASS := Rect2(90, 106, 620, 42)
## The square top right is the tier badge, not a picture of the car.
const R_TIER := Rect2(742, 82, 110, 104)

const R_LOCATION := Rect2(170, 258, 415, 34)

## Stat rows. `key` is what the server calls it; an empty key means the game
## has no such number yet and the row says so rather than inventing one.
##
## TOP SPEED and ACCELERATION would both mean running the simulation and
## reading the trace -- neither is a property of a car, they are results of a
## pass -- so they belong to a server endpoint that does not exist yet.
const ROWS := [
	{ "y": 371, "key": "peakHp", "unit": "HP" },
	{ "y": 447, "key": "peakTorque", "unit": "LB-FT" },
	{ "y": 524, "key": "totalWeight", "unit": "LB" },
	{ "y": 598, "key": "", "unit": "" },          # TOP SPEED
	{ "y": 673, "key": "", "unit": "" },          # ACCELERATION 0-100
	{ "y": 761, "key": "grip", "unit": "" },      # HANDLING
]
const VALUE_X := 420.0
const VALUE_W := 440.0
const VALUE_H := 40.0

const R_OWNED := Rect2(215, 916, 200, 38)
const R_SLOTS := Rect2(620, 916, 200, 38)

## Five preview slots and the arrow past them.
const PREVIEW_TOP := 1066.0
const PREVIEW_H := 158.0
const PREVIEW_X := 88.0
const PREVIEW_W := 160.0
const PREVIEW_GAP := 8.0
const PREVIEW_COUNT := 5

const R_SET_ACTIVE := Rect2(72, 1268, 400, 112)
const R_TUNE := Rect2(496, 1268, 400, 112)
const R_SELL := Rect2(86, 1422, 386, 96)
const R_EXIT := Rect2(496, 1422, 400, 96)

signal set_active_requested()
signal tune_requested()
signal sell_requested()
signal exit_requested()

var frame: Control

var _name: Label
var _class: Label
var _tier: Label
var _location: Label
var _values: Array = []
var _owned: Label
var _slots: Label
var _previews: Array = []
var _scaled: Array = []
var _set_active: Button
var _sell: Button


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_build()
	resized.connect(_rescale)


func _build() -> void:
	var fitter := AspectRatioContainer.new()
	fitter.ratio = ART_W / ART_H
	fitter.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_END
	fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
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
		# The panel takes its own clicks rather than passing them to the floor.
		art.mouse_filter = Control.MOUSE_FILTER_STOP
		art.material = _corner_key()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(art)
	else:
		push_warning("Garage panel art missing: %s" % ART)

	_name = _label(R_NAME, Design.TEXT_PRIME, 54, HORIZONTAL_ALIGNMENT_LEFT)
	Design.apply_display(_name)
	_class = _label(R_CLASS, Design.TEXT_MUTED, 30, HORIZONTAL_ALIGNMENT_LEFT)
	_tier = _label(R_TIER, Design.INFO, 56, HORIZONTAL_ALIGNMENT_CENTER)
	Design.apply_display(_tier)

	_location = _label(R_LOCATION, Design.TEXT_PRIME, 30, HORIZONTAL_ALIGNMENT_LEFT)

	for row in ROWS:
		_values.append(_label(
			Rect2(VALUE_X, float(row.y) - VALUE_H * 0.5, VALUE_W, VALUE_H),
			Design.TEXT_PRIME, 34, HORIZONTAL_ALIGNMENT_RIGHT))

	_owned = _label(R_OWNED, Design.TEXT_PRIME, 36, HORIZONTAL_ALIGNMENT_LEFT)
	_slots = _label(R_SLOTS, Design.TEXT_PRIME, 36, HORIZONTAL_ALIGNMENT_LEFT)

	for i in PREVIEW_COUNT:
		var slot := Control.new()
		slot.clip_contents = true
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_place(slot, Rect2(PREVIEW_X + (PREVIEW_W + PREVIEW_GAP) * float(i),
			PREVIEW_TOP, PREVIEW_W, PREVIEW_H))

		var img := TextureRect.new()
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		slot.add_child(img)
		_previews.append(img)

	_set_active = _hit(R_SET_ACTIVE, "Drive this car", func(): set_active_requested.emit())
	_hit(R_TUNE, "The tune screen arrives with the next milestone",
		func(): tune_requested.emit()).disabled = true
	_sell = _hit(R_SELL, "Sell it back", func(): sell_requested.emit())
	_hit(R_EXIT, "Back to the map", func(): exit_requested.emit())


## Drops the black behind the panel's chamfered corners without eating into
## the panel itself, which is nearly black too. Confined to the corners for
## exactly that reason: a key applied across the whole face would fade the
## interior as well.
func _corner_key() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float cut_low = 0.002;
uniform float cut_high = 0.010;
uniform float reach = 0.13;

void fragment() {
	vec4 c = texture(TEXTURE, UV);

	vec2 edge = min(UV, vec2(1.0) - UV);
	float in_corner = step(edge.x, reach) * step(edge.y, reach);

	float lum = max(c.r, max(c.g, c.b));
	float keyed = smoothstep(cut_low, cut_high, lum);

	c.a *= mix(1.0, keyed, in_corner);
	COLOR = c;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("cut_low", CORNER_CUT_LOW)
	mat.set_shader_parameter("cut_high", CORNER_CUT_HIGH)
	mat.set_shader_parameter("reach", CORNER_REACH)
	return mat


## A car's tier, from what it costs.
##
## The game has no tier of its own -- cars carry a class and a price -- so the
## badge is banded off price, the same way the dealership splits SUPER from
## HYPER. It is a reading of the data, not a new field.
func _tier_for(model: Dictionary) -> String:
	var price := int(model.get("price", 0))
	if price >= 200000:
		return "S"
	if price >= 100000:
		return "A"
	if price >= 30000:
		return "B"
	if price >= 8000:
		return "C"
	return "D"


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


func _hit(r: Rect2, tooltip: String, handler: Callable) -> Button:
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
	b.pressed.connect(handler)
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


func _rescale() -> void:
	if frame == null or frame.size.y <= 0.0:
		return
	var factor: float = frame.size.y / ART_H
	for entry in _scaled:
		var l: Label = entry["node"]
		if is_instance_valid(l):
			l.add_theme_font_size_override("font_size",
				maxi(9, roundi(float(entry["size"]) * factor)))


# ─────────────────────────────────────────────────────────────
# FILLING
# ─────────────────────────────────────────────────────────────

## A car's figures with the dealership's fallback underneath.
##
## The dealership plate never shows blank because it reads the catalog, which
## is always loaded. The same baseline applies here: the model carries the
## car's base figures, and the server's stats -- which fold in whatever parts
## are fitted -- override them whenever they arrive. Only the two rows with no
## source anywhere stay as dashes.
func _effective_stats(model: Dictionary, stats: Dictionary) -> Dictionary:
	var merged := {
		"peakHp": int(model.get("baseHp", 0)),
		"peakTorque": int(model.get("baseTorque", 0)),
		"totalWeight": int(model.get("baseWeight", 0)),
		"grip": 1.0,   # a stock car's grip multiplier; tires and body move it
	}
	for key in stats.keys():
		merged[key] = stats[key]
	return merged


## Show a car. `stats` is the server's answer for it, or empty -- the model's
## own figures stand in until it arrives.
func show_car(car: Dictionary, stats: Dictionary) -> void:
	if car.is_empty():
		visible = false
		return
	visible = true

	var model := Catalog.get_car_model(str(car.get("model_id", "")))
	_name.text = str(car.get("nickname", "")).to_upper()
	_class.text = "%s CLASS" % str(model.get("class", ""))
	_tier.text = _tier_for(model)

	var hood := Catalog.get_neighborhood(str(GameState.player.get("neighborhood", "")))
	_location.text = str(hood.get("name", "")).to_upper()

	var eff := _effective_stats(model, stats)
	for i in ROWS.size():
		var row: Dictionary = ROWS[i]
		var key: String = str(row.key)
		var label: Label = _values[i]
		if key == "" or not eff.has(key):
			# Nothing to say rather than a number nobody measured.
			label.text = "—"
			label.add_theme_color_override("font_color", Design.TEXT_DIM)
		else:
			var unit: String = str(row.unit)
			label.text = "%d %s" % [int(eff[key]), unit] if unit != "" \
				else str(eff[key])
			label.add_theme_color_override("font_color", Design.TEXT_PRIME)

	_owned.text = str(GameState.garage.size())
	_slots.text = str(GameState.parking_limit())

	# The preview strip is the rest of the garage, this car first.
	var others: Array = [car]
	for c in GameState.garage:
		if str(c.get("id", "")) != str(car.get("id", "")):
			others.append(c)

	for i in _previews.size():
		var img: TextureRect = _previews[i]
		if i < others.size():
			img.texture = Catalog.car_shot(
				Catalog.get_car_model(str(others[i].get("model_id", ""))))
			img.visible = img.texture != null
		else:
			img.visible = false

	var active: bool = str(car.get("id", "")) == GameState.active_car_id
	var impounded: bool = bool(car.get("impounded", false))
	_set_active.disabled = active or impounded
	_sell.disabled = impounded
	_rescale()
