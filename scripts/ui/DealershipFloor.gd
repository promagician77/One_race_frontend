class_name DealershipFloor
extends Control
## The showroom floor: every car in the catalog as a preview along the bottom,
## and whichever one is picked standing above them with its specs and a price.
##
## The sidebar owns the filter and the order, this owns the cars. It listens
## rather than asks, so neither knows anything about the other -- the column
## has no idea what is in stock, and the floor has no idea where the rows were
## painted.
##
## Stock is per-neighborhood in the data, but the strip carries the whole
## catalog and marks what the player cannot buy yet. That is the same call
## Catalog.parts_available_to() already makes for parts -- window shopping was
## in the original -- and a floor with two cars on it is not a floor.

signal car_selected(model_id: String)
signal car_bought(car: Dictionary)

## Car photographs, the same numbered cutouts LocationModal previews. A shot
## named for the model's own `spriteSet` wins, so renaming a file to
## bantam_gx.png pins it to that car for good.
const CAR_SHOT_DIR := "res://assets/ui/cars/"

## The sidebar's categories against the classes the data actually carries.
## Only MUSCLE is a straight match; the rest are the column's showroom words
## for what car_models.json calls IMPORT, TRUCK, SPORT and EXOTIC.
##
## SUPER and HYPER both resolve to EXOTIC because the data draws no line
## between a supercar and a hypercar. Price is the only thing that separates
## them, so price is what splits them.
const CLASS_FOR := {
	"STREET": ["IMPORT", "TRUCK"],
	"SPORTS": ["SPORT"],
	"MUSCLE": ["MUSCLE"],
	"SUPER":  ["EXOTIC"],
	"HYPER":  ["EXOTIC"],
}
const SUPER_MAX := 200000

## The strip along the bottom, and the card that rides in it.
const STRIP_H := 172
const CARD_W := 150
const CARD_PAD := 8

## The page-forward arrow at the end of the strip.
const NEXT_W := 44

## The line a car's tyres rest on inside its own cutout, as a fraction of the
## image height, measured off each photograph.
##
## The shots are framed by hand and do not agree -- the car bottoms out
## anywhere between 88.9% and 95.3% of its frame -- so standing them all on one
## shared figure sank some into the floor and floated others above it by the
## better part of twenty pixels.
##
## These are measured rather than read back at runtime. Asking a texture for
## its pixels means Texture2D.get_image(), which on a CompressedTexture2D is a
## synchronous GPU readback; doing that from inside the layout pass stalled the
## renderer mid-frame and left the strip full of garbage. The photographs are
## fixed assets, so the numbers belong in the source next to every other
## measurement on this screen. To re-measure after changing a shot, take the
## lowest row in it carrying real alpha, as a fraction of the image height --
## the cutouts have hard edges, so any threshold between 0.06 and 0.5 lands on
## the same row to within a tenth of a percent.
const GROUND := {
	"1.png": 0.915,
	"2.png": 0.895,
	"3.png": 0.909,
	"4.png": 0.915,
	"5.png": 0.891,
	"6.png": 0.945,
	"7.png": 0.953,
	"8.png": 0.927,
}

## Where an unmeasured photograph is assumed to sit -- the middle of the range
## the eight known shots cover. A shot dropped in under a model's own
## spriteSet name lands here until it is measured and added above.
const WHEEL_LINE := 0.92

## The spec plate is one piece of artwork. Every label on it -- POWER, TORQUE,
## WEIGHT, REDLINE, GEARS, PRICE and BUY -- is painted in, so the only thing
## drawn over it is the values, each one placed in the artwork's own pixels and
## measured off the file rather than estimated.
const PLATE_ART := "res://assets/ui/function_modal.png"

## The panel within its canvas. The source is opaque black all round it -- no
## alpha at all -- so drawing the whole file laid a slab on the showroom. The
## frame's own rails run x 25..1513 and y 46..973, and cropping to them leaves
## the artwork touching all four edges.
const PLATE_CROP := Rect2(25, 46, 1489, 928)

## What is left after the crop: the black outside the four chamfered corners.
##
## LocationModal keys its corners on luminance, which cannot work here -- this
## panel's dark interior runs 9..20 and the black outside its chamfers runs
## 1..22, so no threshold separates them and any key would either leave the
## black or punch holes in the panel. The chamfer is a clean 45 degree cut
## though, so it is cut by geometry instead, exactly, corner by corner.
## Measured in the artwork's pixels: top-left, top-right, bottom-left,
## bottom-right.
const CHAMFER := Vector4(51.0, 57.0, 60.0, 56.0)

## How wide the plate is allowed to get. It is a landscape panel -- roughly
## 1.6:1 -- so height is what usually binds, and this only stops it eating the
## floor on a very wide window.
const PLATE_MAX_W := 440.0

# Where the values go, in the artwork's own pixels ────────────────
## The header the artwork leaves empty runs y 100..365. What fits in it is
## decided by the faces, not by taste: a label is drawn 2.0x its point size on
## the body face and 3.0x on the mono one, both measured. At the smaller plate
## these three rows only clear each other if the blurb stays on one line, so it
## ellipsises rather than wrapping.
const P_NAME   := Rect2(130, 100, 1180, 102)
const P_CLASS  := Rect2(130, 202, 380, 68)
const P_HOOD   := Rect2(524, 202, 560, 68)
const P_BLURB  := Rect2(130, 281, 1230, 68)

## The six stat plates run x 109..740 and x 805..1426, in rows at y 368, 497
## and 627. The label is painted into the left of each, so the value is
## right-aligned into what is left over.
const P_VALUES := {
	"POWER":   Rect2(370, 390, 356, 64),
	"TORQUE":  Rect2(1065, 390, 347, 64),
	"WEIGHT":  Rect2(370, 519, 356, 64),
	"REDLINE": Rect2(1065, 519, 347, 64),
	"GEARS":   Rect2(370, 649, 356, 64),
	"PRICE":   Rect2(1065, 649, 347, 64),
}

const P_BUY    := Rect2(102, 762, 1329, 126)
const P_STATUS := Rect2(109, 895, 1317, 50)

## Type sizes in the artwork's pixels, scaled to whatever the plate is drawn
## at. Fonts do not stretch with a texture, so they are re-derived on resize
## the same way GameFrame handles the header.
const T_NAME := 62
const T_CHIP := 32
const T_BLURB := 34

## The car's name, set to match the artwork's own labels: a condensed grotesque,
## heavy and slanted. Only a Regular Oswald ships, so both the weight and the
## slant are synthesised on top of it.
##
## The slant goes in the x-axis' y component. Godot hands variation_transform
## to FreeType as an FT_Matrix, which maps x' = xx*x + xy*y, and Transform2D[0]
## is the x-axis -- so xy is x_axis.y, and FreeType's y points up, which makes a
## positive value lean the tops of the glyphs forward.
const TITLE_EMBOLDEN := 0.55
const TITLE_SLANT := 0.20

## The chips, in the artwork's pixels: padding, corner and border all scale
## with the plate so they keep their proportions at any size.
const CHIP_PAD_X := 24.0
const CHIP_PAD_Y := 4.0
const CHIP_RADIUS := 7.0
const CHIP_BORDER := 3.0
const CHIP_FILL_A := 0.16
const T_VALUE := 52
const T_BUY := 64
const T_STATUS := 34

## Dropped over the painted BUY bar when the car cannot be bought, so the
## reason sits where the button was instead of beside it.
const BUY_SCRIM := Color(0, 0, 0, 0.66)

## A locked or owned card is dimmed rather than hidden -- the player should
## see what is coming, they just cannot have it yet.
const DIM_LOCKED := Color(0.45, 0.45, 0.45, 1.0)

static var _shots := -1

var _models: Array = []          ## Everything the filter let through, in order
var _page_models: Array = []     ## The slice on screen, parallel to _cards
var _cards: Array = []           ## Card buttons for the current page
var _page := 0
var _per := 0                    ## Cards per page, from the strip's real width
var _selected := ""              ## model_id, or "" when the filter came back empty

var _category := "ALL CARS"
var _sort := "PRICE: LOW TO HIGH"

var _sidebar: Node
var _row: HBoxContainer
var _next: Button
var _empty: Label

var _photo: TextureRect
var _plate: Control
var _scaled: Array = []          ## [{node, size}] -- type re-derived on resize

var _name: Label
var _class: Label
var _hood: Label
var _chips: Array = []           ## [{panel, box, label}] -- rescaled with the plate
var _blurb: Label
var _values: Dictionary = {}     ## stat key -> Label
var _buy: Button
var _buy_scrim: ColorRect
var _buy_state: Label
var _status: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameState.garage_changed.connect(_on_garage_changed)
	GameState.cash_changed.connect(_on_cash_changed)
	refresh()


# ─────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────

## Three layers, none of them stacked in a box container.
##
## A box honours its children's minimum heights over its own size, so a spec
## panel taller than the floor used to push the strip clean off the bottom of
## the screen -- the previews, the point of the floor, went first. Everything
## here is anchored instead: the strip owns the bottom edge, the specs own the
## right, and the photograph stands on the floor between them.
func _build() -> void:
	_photo = TextureRect.new()
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# The box is sized to the photograph's own aspect below, so a straight
	# scale into it is already undistorted -- and unlike KEEP_ASPECT_CENTERED
	# it leaves no slack to guess at when standing the car on the disc.
	_photo.stretch_mode = TextureRect.STRETCH_SCALE
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_photo)

	var spec := _spec()
	spec.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(spec)

	add_child(_strip())

	resized.connect(_on_resized)


## The spec plate, held against the right edge and centred in the room above
## the strip.
##
## The artwork is shown whole and only the values are drawn over it, the same
## way LocationModal treats its panels. Every rect below is in the art's own
## pixels, so the whole plate scales as one piece and nothing drifts off its
## painted box when the window changes.
func _spec() -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_plate = Control.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_plate)

	if not ResourceLoader.exists(PLATE_ART):
		push_warning("Spec plate art missing: %s" % PLATE_ART)
		return holder

	# Cropped to the panel: the source is opaque black above and below it, and
	# that black would sit on the showroom as a slab.
	var atlas := AtlasTexture.new()
	atlas.atlas = load(PLATE_ART)
	atlas.region = PLATE_CROP

	var art := TextureRect.new()
	art.texture = atlas
	art.material = _chamfer_cut()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The plate catches its own clicks rather than letting them fall through to
	# whatever card is behind it.
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	_plate.add_child(art)

	_name = _text(P_NAME, T_NAME, Design.TEXT_PRIME, HORIZONTAL_ALIGNMENT_LEFT, false)
	_name.add_theme_font_override("font", _title_face())

	_class = _chip(P_CLASS, Design.TEXT_BODY)
	_hood = _chip(P_HOOD, Design.INFO)
	# One line, trimmed if it runs long. Wrapping it to two would push the
	# header past the first row of painted plates at this size.
	_blurb = _text(P_BLURB, T_BLURB, Design.TEXT_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
	_blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	for key in P_VALUES:
		_values[key] = _text(P_VALUES[key], T_VALUE, Design.TEXT_PRIME,
			HORIZONTAL_ALIGNMENT_RIGHT, true)

	# The painted BUY bar, dimmed and relabelled when the car is out of reach.
	_buy_scrim = ColorRect.new()
	_buy_scrim.color = BUY_SCRIM
	_buy_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buy_scrim.visible = false
	_place_at(_buy_scrim, P_BUY)

	_buy_state = _text(P_BUY, T_BUY, Design.TEXT_MUTED, HORIZONTAL_ALIGNMENT_CENTER, false)
	_buy_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_buy_state.visible = false

	_buy = Button.new()
	_buy.flat = true
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	var hover: StyleBoxFlat = clear.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.12)
	var pressed: StyleBoxFlat = clear.duplicate()
	pressed.bg_color = Color(0, 0, 0, 0.20)
	var focus: StyleBoxFlat = clear.duplicate()
	focus.border_color = Design.AMBER_HOT
	focus.set_border_width_all(2)
	_buy.add_theme_stylebox_override("normal", clear)
	_buy.add_theme_stylebox_override("hover", hover)
	_buy.add_theme_stylebox_override("pressed", pressed)
	_buy.add_theme_stylebox_override("focus", focus)
	_buy.add_theme_stylebox_override("disabled", clear)
	_buy.pressed.connect(_on_buy)
	_place_at(_buy, P_BUY)

	_status = _text(P_STATUS, T_STATUS, Design.TEXT_MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)

	return holder


## Cuts the black triangle outside each chamfered corner, by geometry rather
## than by colour. Which corner a pixel is nearest decides how deep the cut
## goes, so all four keep their own measured chamfer.
func _chamfer_cut() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec2 art_px = vec2(1489.0, 928.0);
uniform vec4 chamfer = vec4(51.0, 57.0, 60.0, 56.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);

	vec2 px = UV * art_px;
	vec2 d = min(px, art_px - px);

	float top = step(px.y, art_px.y * 0.5);
	float left = step(px.x, art_px.x * 0.5);
	float cut = mix(mix(chamfer.w, chamfer.z, left),
					mix(chamfer.y, chamfer.x, left), top);

	// Only the corners can satisfy this -- along a straight edge one distance
	// is small but the other is half the panel, so the sum stays well clear.
	c.a *= smoothstep(cut - 1.5, cut + 1.5, d.x + d.y);
	COLOR = c;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("art_px", PLATE_CROP.size)
	mat.set_shader_parameter("chamfer", CHAMFER)
	return mat


## Oswald, emboldened and slanted to sit with the artwork's own type. Neither
## a bold nor an italic file ships -- all three faces are Regular only -- so
## FontVariation thickens and shears the outlines instead.
func _title_face() -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = Design.font_display
	fv.variation_embolden = TITLE_EMBOLDEN
	fv.variation_transform = Transform2D(
		Vector2(1.0, TITLE_SLANT), Vector2(0.0, 1.0), Vector2.ZERO)
	return fv


## A chip: the label on a tinted plate of its own colour, outlined in it.
##
## It hugs its text rather than filling the rect it is given -- both anchors
## sit on the box's left edge and it grows right, so IMPORT and HARBOUR each
## end up only as wide as they need while staying pinned where they belong.
func _chip(r: Rect2, colour: Color) -> Label:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(colour.r, colour.g, colour.b, CHIP_FILL_A)
	box.border_color = colour

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", box)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var l := Label.new()
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", colour)
	panel.add_child(l)

	_place_at(panel, r)
	panel.anchor_right = panel.anchor_left
	panel.offset_right = 0
	panel.grow_horizontal = Control.GROW_DIRECTION_END

	var mid: float = (panel.anchor_top + panel.anchor_bottom) * 0.5
	panel.anchor_top = mid
	panel.anchor_bottom = mid
	panel.offset_top = 0
	panel.offset_bottom = 0
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	_chips.append({"panel": panel, "box": box, "label": l})
	_scaled.append({"node": l, "size": T_CHIP})
	return l


## Repaints a chip when the car changes -- the class colour is the car's, so
## the plate and the outline move with it.
func _tint(label: Label, colour: Color) -> void:
	label.add_theme_color_override("font_color", colour)
	for chip in _chips:
		if chip["label"] == label:
			var box: StyleBoxFlat = chip["box"]
			box.bg_color = Color(colour.r, colour.g, colour.b, CHIP_FILL_A)
			box.border_color = colour
			return


## One value drawn over the artwork. `mono` is for the numbers, so a 105 and a
## 3550 keep the same digit width and the column does not jitter between cars.
func _text(r: Rect2, size: int, colour: Color, align: int, mono: bool) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", colour)
	if mono:
		Design.apply_mono(l)
	_place_at(l, r)

	# A Control cannot be drawn shorter than its own minimum, and these faces
	# bill roughly three times their point size per line -- an 18px value
	# reports a 54px box. Anchored top-and-bottom to the painted box, the label
	# therefore overflowed it downward and sat about a sixth of a plate low,
	# leaning into the row beneath. Pinning both anchors to the box's middle
	# and letting it grow either way centres the text on the plate whatever
	# height the font decides it needs.
	var mid: float = (l.anchor_top + l.anchor_bottom) * 0.5
	l.anchor_top = mid
	l.anchor_bottom = mid
	l.offset_top = 0
	l.offset_bottom = 0
	l.grow_vertical = Control.GROW_DIRECTION_BOTH

	_scaled.append({"node": l, "size": size})
	return l


## Rects are written in the artwork's full-image pixels for legibility, then
## rebased onto the cropped region actually drawn.
func _place_at(node: Control, r: Rect2) -> void:
	node.anchor_left = (r.position.x - PLATE_CROP.position.x) / PLATE_CROP.size.x
	node.anchor_top = (r.position.y - PLATE_CROP.position.y) / PLATE_CROP.size.y
	node.anchor_right = (r.position.x + r.size.x - PLATE_CROP.position.x) / PLATE_CROP.size.x
	node.anchor_bottom = (r.position.y + r.size.y - PLATE_CROP.position.y) / PLATE_CROP.size.y
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	_plate.add_child(node)


## The plate keeps the artwork's aspect and is pinned to the right, centred in
## the room above the strip. Type is re-derived from the size it actually got,
## because a font does not scale with the texture under it.
func _place_plate() -> void:
	if _plate == null:
		return
	var room_h: float = maxf(0.0, size.y - STRIP_H - Design.SP_3)
	var aspect: float = PLATE_CROP.size.x / PLATE_CROP.size.y
	var pw: float = minf(PLATE_MAX_W, minf(room_h * aspect, size.x))
	var ph: float = pw / aspect

	_plate.position = Vector2(size.x - pw, (room_h - ph) * 0.5)
	_plate.size = Vector2(pw, ph)
	_rescale_type()


func _rescale_type() -> void:
	var k: float = _plate.size.y / PLATE_CROP.size.y
	for entry in _scaled:
		var l: Label = entry["node"]
		l.add_theme_font_size_override("font_size",
			maxi(8, roundi(float(entry["size"]) * k)))

	# A stylebox is measured in screen pixels, so a chip drawn at a third of
	# the artwork keeps its proportions only if its padding, corner and border
	# come down with it.
	for chip in _chips:
		var box: StyleBoxFlat = chip["box"]
		box.content_margin_left = CHIP_PAD_X * k
		box.content_margin_right = CHIP_PAD_X * k
		box.content_margin_top = CHIP_PAD_Y * k
		box.content_margin_bottom = CHIP_PAD_Y * k
		box.set_corner_radius_all(maxi(1, roundi(CHIP_RADIUS * k)))
		box.set_border_width_all(maxi(1, roundi(CHIP_BORDER * k)))


## The preview strip: one page of cars and an arrow to the next.
##
## It pages rather than scrolls. A scrollbar under the cards is a second thing
## to aim at in a row that is already all targets, and it hid whichever car sat
## under it; the arrow moves a whole page and wraps at the end, so every car is
## still reachable without the strip ever growing a chrome of its own.
func _strip() -> Control:
	var wrap := Control.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_top = -STRIP_H
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_row = HBoxContainer.new()
	_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row.offset_right = -(NEXT_W + Design.SP_3)
	_row.add_theme_constant_override("separation", Design.SP_3)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(_row)

	_next = UIKit.button(">", UIKit.BtnStyle.SECONDARY)
	_next.add_theme_font_size_override("font_size", Design.SIZE_TITLE)
	_next.tooltip_text = "Next cars"
	_next.anchor_left = 1.0
	_next.anchor_right = 1.0
	_next.anchor_top = 0.0
	_next.anchor_bottom = 1.0
	_next.offset_left = -NEXT_W
	_next.offset_right = 0
	_next.offset_top = 0
	_next.offset_bottom = 0
	_next.pressed.connect(_on_next)
	wrap.add_child(_next)

	_empty = UIKit.body("", Design.TEXT_MUTED)
	_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty.visible = false
	wrap.add_child(_empty)

	return wrap


# ─────────────────────────────────────────────────────────────
# LAYOUT
# ─────────────────────────────────────────────────────────────

## How many cards the strip can hold at its current width.
func _per_page() -> int:
	var avail: float = size.x - NEXT_W - Design.SP_3
	return maxi(1, int((avail + Design.SP_3) / (CARD_W + Design.SP_3)))


func _page_count() -> int:
	if _models.is_empty():
		return 0
	return int(ceil(float(_models.size()) / float(maxi(1, _per_page()))))


## A resize moves everything and can change how many cards fit. Refilling
## the strip is deferred because this runs inside the layout pass that sized
## us, and adding children back into it from here would re-enter it.
func _on_resized() -> void:
	_place_plate()
	_place_photo()
	if _per_page() != _per:
		_fill_strip.call_deferred()


## Stands the car on the floor: centred in whatever the plate leaves it, with
## its tyres on a line just above the strip.
##
## It used to be centred on a turntable painted into the backdrop, measured off
## the art. That backdrop has since been replaced with a showroom that has no
## disc in it -- the floor is flat marble -- so there is nothing left to align
## to and the car simply stands in the middle of its own space. Every shot
## still lands on the same line, which is what GROUND is for.
func _place_photo() -> void:
	if _photo == null or _photo.texture == null:
		return
	var tex: Vector2 = _photo.texture.get_size()
	if tex.x <= 0.0 or tex.y <= 0.0:
		return

	var ground: float = _ground_line(_photo.texture)
	var room_w: float = maxf(0.0, _plate_left() - Design.SP_5)
	var contact: float = size.y - STRIP_H - Design.SP_3

	var w: float = room_w
	var h: float = w * tex.y / tex.x

	# A car too tall for the room above the strip is scaled down until it fits,
	# keeping its tyres on the same line.
	if contact > 0.0 and h * ground > contact:
		var k: float = contact / (h * ground)
		w *= k
		h *= k

	_photo.position = Vector2((room_w - w) * 0.5, contact - h * ground)
	_photo.size = Vector2(w, h)


func _plate_left() -> float:
	return size.x if _plate == null else _plate.position.x


# ─────────────────────────────────────────────────────────────
# WHAT THE SIDEBAR SAYS
# ─────────────────────────────────────────────────────────────

## Wire the column to the floor. It reads the starting filter off the column
## rather than assuming one, so the two cannot drift apart.
##
## The signals carry a row index, but the floor asks the sidebar what that
## index means instead of keeping its own copy of the row names. The column
## updates its selection before it emits, so the answer is always current.
func follow(sidebar: Node) -> void:
	_sidebar = sidebar
	sidebar.category_chosen.connect(_on_category)
	sidebar.sort_chosen.connect(_on_sort)
	_category = sidebar.selected_category()
	_sort = sidebar.selected_sort()
	refresh()


func _on_category(_index: int) -> void:
	_category = _sidebar.selected_category()
	refresh()


func _on_sort(_index: int) -> void:
	_sort = _sidebar.selected_sort()
	refresh()


# ─────────────────────────────────────────────────────────────
# THE CARS
# ─────────────────────────────────────────────────────────────

## Rebuilds the list from the current filter and order, holding onto the
## selected car if it survived and falling to the first one if not. The page
## resets, because a filter change makes the old page number meaningless.
func refresh() -> void:
	var keep := _selected
	_models = _sorted(_filtered())
	_page = 0
	_fill_strip()
	_select(keep if _has(keep) else _first_id())


## Lays one page of cars into the strip. Everything about the strip that can
## change -- which cars, how many fit, whether the arrow is needed -- is
## settled here, so there is one place to look when the row is wrong.
func _fill_strip() -> void:
	for card in _cards:
		card.queue_free()
	_cards.clear()
	_page_models.clear()

	_per = _per_page()
	var pages := _page_count()
	_page = 0 if pages == 0 else clampi(_page, 0, pages - 1)

	var start := _page * _per
	for i in range(start, mini(start + _per, _models.size())):
		var model: Dictionary = _models[i]
		var card := _card(model)
		_row.add_child(card)
		_cards.append(card)
		_page_models.append(model)

	_empty.visible = _models.is_empty()
	if _models.is_empty():
		_empty.text = "No %s in the catalog." % _category.to_lower()

	# The arrow earns its place only when there is somewhere to go.
	_next.visible = pages > 1
	_next.tooltip_text = "Next cars (%d of %d)" % [_page + 1, maxi(1, pages)]
	_restyle()


## Wraps rather than stopping at the end: the strip is a carousel of at most a
## couple of pages, and a dead arrow at the last page is a worse answer than
## coming back round to the first.
func _on_next() -> void:
	var pages := _page_count()
	if pages <= 1:
		return
	_page = (_page + 1) % pages
	_fill_strip()


func _filtered() -> Array:
	if _category == "ALL CARS":
		return Catalog.all_car_models().duplicate()

	var classes: Array = CLASS_FOR.get(_category, [])
	return Catalog.all_car_models().filter(func(m):
		if not str(m.get("class", "")) in classes:
			return false
		# Only the exotics need splitting, and only on price.
		if _category == "SUPER":
			return int(m.get("price", 0)) < SUPER_MAX
		if _category == "HYPER":
			return int(m.get("price", 0)) >= SUPER_MAX
		return true
	)


## The five orders the artwork paints. NEW ARRIVALS has no date to sort on --
## nothing in car_models.json is timestamped -- so it runs the catalog
## backwards, newest entry first, which is the order cars are appended in.
func _sorted(models: Array) -> Array:
	var out := models.duplicate()
	match _sort:
		"PRICE: LOW TO HIGH":
			out.sort_custom(func(a, b): return a.price < b.price)
		"PRICE: HIGH TO LOW":
			out.sort_custom(func(a, b): return a.price > b.price)
		"NAME: A TO Z":
			out.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
		"NAME: Z TO A":
			out.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) > 0)
		"NEW ARRIVALS":
			out.reverse()
	return out


## One preview. The card is a Button so it carries hover, press and focus
## without any of it being drawn by hand; its contents ride on top and take
## no clicks of their own.
func _card(model: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD_W, 0)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.tooltip_text = _tooltip(model)
	card.focus_mode = Control.FOCUS_ALL
	card.pressed.connect(_select.bind(str(model.id)))
	_style_card(card, false)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = CARD_PAD
	col.offset_top = CARD_PAD
	col.offset_right = -CARD_PAD
	col.offset_bottom = -CARD_PAD
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)

	var shot := TextureRect.new()
	shot.texture = _car_shot(model)
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(shot)

	var name_label := UIKit.body(str(model.name), Design.TEXT_PRIME)
	name_label.add_theme_font_size_override("font_size", Design.SIZE_SMALL)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true
	col.add_child(name_label)

	var price := UIKit.numeric(Design.fmt_cash(int(model.price)),
		Design.SIZE_SMALL, Design.CASH)
	col.add_child(price)

	# Owned and locked read differently: one is a fact about the player's
	# garage, the other about where they are allowed to shop.
	if _owns(model):
		card.modulate = DIM_LOCKED
		price.text = "OWNED"
		price.add_theme_color_override("font_color", Design.TEXT_MUTED)
	elif not GameState.can_shop_in(str(model.dealership)):
		card.modulate = DIM_LOCKED
		price.add_theme_color_override("font_color", Design.TEXT_DIM)

	return card


func _tooltip(model: Dictionary) -> String:
	if _owns(model):
		return "%s — already in your garage" % model.name
	if not GameState.can_shop_in(str(model.dealership)):
		return "%s — sold in %s, out of your reach for now" % [model.name, model.dealership]
	return "%s — %s" % [model.name, Design.fmt_cash(int(model.price))]


# ─────────────────────────────────────────────────────────────
# SELECTION
# ─────────────────────────────────────────────────────────────

func _select(model_id: String) -> void:
	_selected = model_id
	_restyle()
	_paint_hero()
	if model_id != "":
		car_selected.emit(model_id)


## Rings whichever card on this page is the chosen one. The selected car can
## be on another page entirely -- picking a category then paging away leaves it
## selected and simply unringed, which is what the plate above still shows.
func _restyle() -> void:
	for i in _cards.size():
		_style_card(_cards[i], str(_page_models[i].id) == _selected)


## Everything the artwork leaves blank, redrawn for whichever car is up. The
## labels beside them -- POWER, TORQUE and the rest -- are painted into the
## plate, so only the numbers are drawn here.
func _paint_hero() -> void:
	var model := Catalog.get_car_model(_selected)
	var showing := not model.is_empty()

	_photo.texture = _car_shot(model) if showing else null
	_place_photo()

	if _plate == null:
		return

	_plate.visible = showing
	if not showing:
		return

	var car_class := str(model.get("class", ""))
	_name.text = str(model.get("name", ""))
	_class.text = car_class
	_tint(_class, Design.class_color(car_class))
	_hood.text = str(model.get("dealership", ""))
	_blurb.text = str(model.get("blurb", ""))

	_values["POWER"].text = "%d HP" % int(model.get("baseHp", 0))
	_values["TORQUE"].text = "%d LB-FT" % int(model.get("baseTorque", 0))
	_values["WEIGHT"].text = "%d LB" % int(model.get("baseWeight", 0))
	_values["REDLINE"].text = "%d RPM" % int(model.get("redline", 0))
	_values["GEARS"].text = str(int(model.get("gearCount", 0)))
	_values["PRICE"].text = Design.fmt_cash(int(model.get("price", 0)))

	_paint_buy(model)


## Whether the painted BUY bar can be pressed, and what covers it when it
## cannot. Every refusal here is one GameState.buy_car() would make anyway --
## this only says it before the player commits instead of after.
func _paint_buy(model: Dictionary) -> void:
	if _owns(model):
		_block("IN YOUR GARAGE", "You already own this one.", Design.TEXT_MUTED)
		return

	if not GameState.can_shop_in(str(model.dealership)):
		_block("LOCKED", "Sold in %s. Move up before you can buy here." % model.dealership,
			Design.WARN)
		return

	if not GameState.has_parking_space():
		_block("NO SPACE", "Your %s %s full. Sell a car or move up." % [
			_spaces(GameState.parking_limit()),
			"is" if GameState.parking_limit() == 1 else "are"], Design.WARN)
		return

	var price := int(model.get("price", 0))
	if not GameState.can_afford(price):
		_block("CAN'T AFFORD", "Short %s." % Design.fmt_cash(
			price - int(GameState.player.get("cash", 0))), Design.BAD)
		return

	# Buyable: the artwork's own BUY shows through, uncovered.
	_buy_scrim.visible = false
	_buy_state.visible = false
	_buy.disabled = false
	_say("%d of %s used." % [GameState.parking_used(), _spaces(GameState.parking_limit())],
		Design.TEXT_MUTED)


## Covers the painted bar with the reason it cannot be pressed.
func _block(label: String, why: String, colour: Color) -> void:
	_buy_scrim.visible = true
	_buy_state.visible = true
	_buy_state.text = label
	_buy_state.add_theme_color_override("font_color", colour)
	_buy.disabled = true
	_say(why, colour)


func _on_buy() -> void:
	var model := Catalog.get_car_model(_selected)
	if model.is_empty():
		return

	# GameState is the authority on whether this is allowed. The button being
	# enabled is a prediction; this is the decision.
	var res: Dictionary = GameState.buy_car(str(model.id))
	if not res.get("ok", false):
		_say(str(res.get("reason", "That didn't go through.")), Design.BAD)
		return

	_say("%s is yours. Plate %s." % [model.name, res.car.plate], Design.GOOD)
	car_bought.emit(res.car)


## The starting neighborhood has exactly one parking space, so the plural is
## wrong for the player who most needs to read this line.
func _spaces(n: int) -> String:
	return "1 parking space" if n == 1 else "%d parking spaces" % n


func _say(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


# ─────────────────────────────────────────────────────────────
# STATE CHANGES
# ─────────────────────────────────────────────────────────────

## Buying a car changes two things the strip draws -- what is owned and what
## is still affordable -- so the whole strip is rebuilt rather than patched.
func _on_garage_changed() -> void:
	refresh()


## Cash moves without the garage changing (selling parts, prize money), and
## that alone can flip the BUY button. The strip's prices do not change, so
## only the plate is redrawn.
func _on_cash_changed(_amount: int) -> void:
	var model := Catalog.get_car_model(_selected)
	if not model.is_empty():
		_paint_buy(model)


# ─────────────────────────────────────────────────────────────
# BITS
# ─────────────────────────────────────────────────────────────

func _owns(model: Dictionary) -> bool:
	for car in GameState.garage:
		if str(car.get("model_id", "")) == str(model.get("id", "")):
			return true
	return false


func _has(model_id: String) -> bool:
	if model_id == "":
		return false
	for m in _models:
		if str(m.id) == model_id:
			return true
	return false


func _first_id() -> String:
	return "" if _models.is_empty() else str(_models[0].id)


## The selected card is ringed in amber, the rest sit flat on the floor. Both
## states are built from the same box so only the edge differs.
func _style_card(card: Button, chosen: bool) -> void:
	var normal := _card_box(Color(Design.BG_PANEL, 0.82),
		Design.AMBER if chosen else Design.EDGE_LINE, 2 if chosen else 1)
	var hover := _card_box(Color(Design.BG_HOVER, 0.90),
		Design.AMBER if chosen else Design.EDGE_BRIGHT, 2 if chosen else 1)

	card.add_theme_stylebox_override("normal", normal)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	card.add_theme_stylebox_override("focus", _card_box(
		Color(0, 0, 0, 0), Design.AMBER_HOT, 1))


## Cards are translucent so the showroom reads through them -- a solid row of
## panels along the bottom would hide the floor the backdrop is there for.
func _card_box(bg: Color, edge: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(Design.RADIUS_MD)
	return sb


## A shot named for the model's own `spriteSet` wins. Failing that the
## catalog's order picks one of the numbered shots: stable for a given car,
## and consecutive, so neighbours in the strip never land on the same photo.
func _car_shot(model: Dictionary) -> Texture2D:
	if model.is_empty():
		return null

	var named := "%s%s.png" % [CAR_SHOT_DIR, str(model.get("spriteSet", ""))]
	if ResourceLoader.exists(named):
		return load(named)

	var total := _shot_total()
	if total == 0:
		return null
	return load("%s%d.png" % [CAR_SHOT_DIR, (_model_index(model) % total) + 1])


## Which tyre line to stand this photograph on.
func _ground_line(tex: Texture2D) -> float:
	if tex == null:
		return WHEEL_LINE
	return GROUND.get(tex.resource_path.get_file(), WHEEL_LINE)


func _model_index(model: Dictionary) -> int:
	var models: Array = Catalog.all_car_models()
	for i in models.size():
		if str(models[i].get("id", "")) == str(model.get("id", "")):
			return i
	return 0


static func _shot_total() -> int:
	if _shots < 0:
		_shots = 0
		while ResourceLoader.exists("%s%d.png" % [CAR_SHOT_DIR, _shots + 1]):
			_shots += 1
	return _shots
