extends Control
## The part shop.
##
## Backdrop only for now. The interface that stood on it has been taken out.
##
## The screen is added into GameFrame's content area, so this Control already
## has exactly the rectangle the frame leaves between its header, footer and
## edge glow. Two things keep the art inside it:
##
##   clip_contents  -- COVERED scales the photograph until it fills the box,
##                     which means it overhangs on one axis by design. Without
##                     clipping that overhang paints straight over the frame's
##                     borders instead of ending at them.
##
##   KEEP_ASPECT_COVERED -- fills the box without distorting the workshop.
##                     The overhang is cropped rather than the floor stretched.
##
## The frame is built after its content, so its chrome already draws over the
## top of whatever a screen puts here.

const BACKDROP := "res://assets/ui/partshop_back.png"

## The categories column. Transparent outside its frame, so it composites onto
## the workshop rather than arriving on a black square.
const SIDEBAR := "res://assets/ui/part_shop_side.png"
const SIDE_W := 941.0
const SIDE_H := 1672.0

## The column is fitted rather than hand-placed, the same way the dealership
## does it: a tall panel inside a wide screen makes height the limit, so it
## stands the full height of the content area and takes its width from its own
## aspect. Nothing here is a guessed fraction of the screen.
const CONTENT_W := 1616.0
const CONTENT_H := 740.0

## The shelf beside it, in the content area's pixels. Its left edge comes from
## the column's measured width at runtime, not from a constant.
const SHELF_GAP := 24.0
const SHELF_MARGIN := 20.0

## Rows, measured off the column with tools/ArtProbe.gd. The pitch came back a
## consistent 132.6 from the second row down, so the first is placed and the
## rest follow it rather than being listed one by one.
const ROW_X := 150.0
const ROW_W := 650.0
const ROW_H := 118.0
const ROW_TOP := 270.0
const ROW_PITCH := 132.6

## What the artwork offers, in the order it paints them.
const ROWS := [
	"ALL PARTS", "ENGINE", "TURBO", "ECU", "TIRES",
	"BRAKES", "SUSPENSION", "GEARBOX", "BODY KIT",
]

## Which game category each painted row selects. Empty means the artwork names
## something this game does not have -- see the note in _build_sidebar.
const ROW_CATEGORY := {
	"ALL PARTS": "ALL", "ENGINE": "ENGINE", "TURBO": "TURBO", "ECU": "",
	"TIRES": "TIRES", "BRAKES": "", "SUSPENSION": "SUSPENSION",
	"GEARBOX": "TRANS", "BODY KIT": "BODY",
}

## Product shots, one per category.
##
## Five of the renders match a category outright. The ECU render is used for
## ENGINE as a stand-in: the parts there are internals -- cams, forged pistons,
## a stroker kit -- rather than engine management, so it is the right bay and
## the wrong component. It reads better than an empty card and is meant to be
## replaced.
##
## brakes.png is not used. This game has no brake parts, and none of the three
## categories still without art -- intake, exhaust, nitrous -- would be
## honestly served by a photograph of a brake disc.
const MODULE_ART := {
	"TURBO": "res://assets/ui/modules/turbo.png",
	"TIRES": "res://assets/ui/modules/tires.png",
	"SUSPENSION": "res://assets/ui/modules/suspension.png",
	"TRANS": "res://assets/ui/modules/gearbox.png",
	"BODY": "res://assets/ui/modules/body.png",
	"ENGINE": "res://assets/ui/modules/ecu.png",
}

## The shelf, beside the column and along the bottom.
## How tall the shelf stands, in the content area's pixels.
const SHELF_H := 150.0

## The car standing in the workshop, between the column and the shelf.
##
## Three angles ship with every model; the three-quarter is the one that reads
## as a car sitting in a bay rather than a diagram of one. These are the
## procedural placeholders, so they are flat silhouettes for now -- the Blender
## renders replace the files, not this code.
const CAR_ANGLE := "three_quarter"
const CAR_SPRITE_RATIO := 420.0 / 200.0
## How much of the workshop's height the car takes.
const CAR_HEIGHT_FRACTION := 0.44
const PAGER_W := 60.0
const CARD_GAP := 12.0
const CARDS_PER_PAGE := 6

signal category_chosen(category: String)

var _category := "ALL"
var _selected := ""
var _fitting := false
var _preview_seq := 0
var _page := 0
var _side: Control
var _strip: Control
var _pager: Button
var _car: TextureRect
var _details: PartDetailsPanel
var _cards: HBoxContainer


func _ready() -> void:
	clip_contents = true
	# Buying, selling or being impounded all change which car is standing in
	# the bay, and any of them can happen while this screen is open.
	GameState.garage_changed.connect(_refresh_car)
	_build()


func _build() -> void:
	var ground := ColorRect.new()
	ground.color = Design.BG_VOID
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	if not ResourceLoader.exists(BACKDROP):
		push_warning("Part shop backdrop missing: %s" % BACKDROP)
		return

	var art := TextureRect.new()
	art.texture = load(BACKDROP)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(art)

	_build_sidebar()
	_build_car_view()
	_build_strip()
	_build_details()
	_rebuild_cards()
	_refresh_car()


## The categories column, top-left, with a transparent hit area over each
## painted row.
##
## The artwork and the game disagree about what the categories are. It paints
## ECU and BRAKES, which this game has no parts for, and it has no row for
## INTAKE, EXHAUST or NITROUS. The first two of those are the flow-sync pair --
## the mechanic the whole game rests on -- so as it stands a player cannot
## reach them from this column. The rows that do map are wired; the two that
## do not are left inert rather than pointed at the wrong shelf.
func _build_sidebar() -> void:
	if not ResourceLoader.exists(SIDEBAR):
		push_warning("Part shop sidebar missing: %s" % SIDEBAR)
		return

	# Fitting a tall panel inside a wide screen makes height the limit, so the
	# column is as tall as the content area and takes its width from the art.
	var fitter := AspectRatioContainer.new()
	fitter.ratio = SIDE_W / SIDE_H
	fitter.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_BEGIN
	fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	fitter.set_anchors_preset(Control.PRESET_FULL_RECT)
	fitter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fitter)

	_side = Control.new()
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fitter.add_child(_side)

	var panel := TextureRect.new()
	panel.texture = load(SIDEBAR)
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	# The column catches its own clicks rather than letting them fall through
	# to the workshop behind it.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_side.add_child(panel)

	for i in ROWS.size():
		var label: String = ROWS[i]
		var category: String = str(ROW_CATEGORY.get(label, ""))
		var hit := _row_hit(label, category)
		_place_on_side(hit, Rect2(ROW_X, ROW_TOP + ROW_PITCH * float(i), ROW_W, ROW_H))


func _row_hit(label: String, category: String) -> Button:
	var b := Button.new()
	b.text = ""
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL

	if category == "":
		b.disabled = true
		b.tooltip_text = "%s is not a part category in this game yet" % label
	else:
		b.tooltip_text = label
		b.pressed.connect(_on_row.bind(category))

	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	var hover: StyleBoxFlat = clear.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.09)
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


## Position a control over a rect measured in the column's own pixels.
func _place_on_side(node: Control, r: Rect2) -> void:
	node.anchor_left = r.position.x / SIDE_W
	node.anchor_top = r.position.y / SIDE_H
	node.anchor_right = (r.position.x + r.size.x) / SIDE_W
	node.anchor_bottom = (r.position.y + r.size.y) / SIDE_H
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	_side.add_child(node)


func _on_row(category: String) -> void:
	_category = category
	_page = 0
	_rebuild_cards()
	category_chosen.emit(category)


# ─────────────────────────────────────────────────────────────
# THE SHELF
# ─────────────────────────────────────────────────────────────

## The player's own car, standing in the bay. Built empty and filled by
## _refresh_car, so it can appear and disappear with the active car without
## the screen being rebuilt.
func _build_car_view() -> void:
	_car = TextureRect.new()
	_car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_car.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car.visible = false
	add_child(_car)

	GameState.active_car_changed.connect(_on_active_car_changed)


## Which picture, if any. The same photograph the showroom sells the car with,
## so the bay and the dealership agree about what a Bantam GX looks like.
func _car_picture() -> Texture2D:
	var car := GameState.get_active_car()
	if car.is_empty():
		return null
	return Catalog.car_shot(Catalog.get_car_model(str(car.get("model_id", ""))))


func _refresh_car() -> void:
	if _car == null:
		return
	var picture := _car_picture()
	if picture == null:
		_car.visible = false
		return
	_car.texture = picture
	_car.visible = true
	_place_car()


func _on_active_car_changed(_car_id: String) -> void:
	_refresh_car()


## Centred in the workshop: right of the column, above the shelf. Placed off
## the column's real width for the same reason the shelf is.
func _place_car() -> void:
	if _car == null or _side == null or not _car.visible:
		return

	var left := _side.size.x + SHELF_GAP
	var right := size.x - SHELF_MARGIN
	var bottom := size.y - SHELF_MARGIN - size.y * (SHELF_H / CONTENT_H)

	var height := size.y * CAR_HEIGHT_FRACTION
	var width := height * CAR_SPRITE_RATIO
	# Never wider than the bay it stands in.
	var available := right - left
	if width > available:
		width = available
		height = width / CAR_SPRITE_RATIO

	var mid_x := left + available * 0.5
	var mid_y := bottom * 0.5

	_car.anchor_left = 0.0
	_car.anchor_top = 0.0
	_car.anchor_right = 0.0
	_car.anchor_bottom = 0.0
	_car.offset_left = mid_x - width * 0.5
	_car.offset_top = mid_y - height * 0.5
	_car.offset_right = mid_x + width * 0.5
	_car.offset_bottom = mid_y + height * 0.5


## The details panel, on the right above the shelf. It stays hidden until a
## part is chosen.
func _build_details() -> void:
	_details = PartDetailsPanel.new()
	_details.buy_requested.connect(_on_buy_part)
	_details.install_requested.connect(_on_install_part)
	add_child(_details)
	_place_details.call_deferred()


func _place_details() -> void:
	if _details == null:
		return
	# It occupies the strip of screen above the shelf, right aligned. The
	# aspect fitter inside it does the rest.
	var shelf := size.y * (SHELF_H / CONTENT_H) + SHELF_MARGIN * 2.0
	_details.anchor_left = 0.0
	_details.anchor_top = 0.0
	_details.anchor_right = 1.0
	_details.anchor_bottom = 1.0
	_details.offset_left = SHELF_MARGIN
	_details.offset_top = SHELF_MARGIN
	_details.offset_right = -SHELF_MARGIN
	_details.offset_bottom = -shelf


func _build_strip() -> void:
	_strip = Control.new()
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_strip)

	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", int(CARD_GAP))
	_cards.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip.add_child(_cards)

	# Paging rather than scrolling: the shelf is a fixed row of six, and a
	# scrollbar across the bottom of a photograph looks like a mistake.
	_pager = UIKit.button(">", UIKit.BtnStyle.SECONDARY)
	_pager.pressed.connect(_on_next_page)
	add_child(_pager)

	# The column's width is only real once the aspect fitter has laid it out,
	# which has not happened yet, so the first placement is deferred and every
	# later one rides the column's own resize.
	if _side != null:
		_side.resized.connect(_place_strip)
		_side.resized.connect(_place_car)
	_place_strip.call_deferred()
	_place_car.call_deferred()
	_place_details.call_deferred()


## The shelf sits to the right of the column, off its real width rather than a
## guessed fraction of the screen -- the column takes its width from its own
## aspect, so how much of the screen it covers changes with the window.
func _place_strip() -> void:
	if _strip == null or _side == null:
		return

	var left := _side.size.x + SHELF_GAP
	var height := size.y * (SHELF_H / CONTENT_H)

	_strip.offset_left = left
	_strip.offset_top = -height - SHELF_MARGIN
	_strip.offset_right = -SHELF_MARGIN - _pager_width()
	_strip.offset_bottom = -SHELF_MARGIN
	_strip.anchor_top = 1.0
	_strip.anchor_bottom = 1.0

	if _pager != null:
		_pager.anchor_top = 1.0
		_pager.anchor_bottom = 1.0
		_pager.offset_left = -SHELF_MARGIN - _pager_width() + 8.0
		_pager.offset_right = -SHELF_MARGIN
		_pager.offset_top = -height * 0.75
		_pager.offset_bottom = -height * 0.25


func _pager_width() -> float:
	return size.x * (PAGER_W / CONTENT_W)


## What the shelf is showing. A shop displays its stock whether or not you
## have a car to put it on -- fitting is what needs one.
func _stock() -> Array:
	# The shop the player walked into sells ITS stock — the map modal's count
	# and the shelf must agree. With no district in the context (tests, direct
	# navigation) the full catalog stands in.
	var hood := str(Router.context.get("neighborhood", ""))
	var all: Array = Catalog.parts_in(hood) if hood != "" else Catalog.all_parts()
	if _category == "ALL":
		# One of each kind, cheapest first, so the shelf reads as a spread
		# rather than five variations of the same part.
		var seen := {}
		var spread: Array = []
		for part in all:
			var cat: String = str(part.category)
			if seen.has(cat):
				continue
			seen[cat] = true
			spread.append(part)
		return spread
	return all.filter(func(p): return str(p.category) == _category)


func _rebuild_cards() -> void:
	if _cards == null:
		return
	# Detached before freeing, not just queued: queue_free() runs at the end of
	# the frame, so rebuilding twice in one frame -- switching category and
	# then selecting -- would stack the new cards on top of the old ones.
	for c in _cards.get_children():
		_cards.remove_child(c)
		c.queue_free()

	var stock := _stock()
	if stock.is_empty():
		return

	var pages: int = int(ceil(float(stock.size()) / float(CARDS_PER_PAGE)))
	_page = _page % maxi(1, pages)
	var from: int = _page * CARDS_PER_PAGE
	var slice: Array = stock.slice(from, mini(from + CARDS_PER_PAGE, stock.size()))

	for part in slice:
		_cards.add_child(_card(part))

	# The cards share the shelf by expanding, so a page with three of them
	# would make each one twice as wide as on a full page. Empty holders keep
	# every card the same width whatever the page holds.
	for _i in range(slice.size(), CARDS_PER_PAGE):
		var filler := Control.new()
		filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cards.add_child(filler)


func _card(part: Dictionary) -> Control:
	var chosen: bool = str(part.id) == _selected

	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _card_box(chosen))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	frame.add_child(col)

	# The render, cropped to the card rather than letterboxed inside it.
	var shot := Control.new()
	shot.clip_contents = true
	shot.custom_minimum_size = Vector2(0, 74)
	shot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(shot)

	var art_path: String = str(MODULE_ART.get(str(part.category), ""))
	if art_path != "" and ResourceLoader.exists(art_path):
		var img := TextureRect.new()
		img.texture = load(art_path)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		shot.add_child(img)

	var name_label := UIKit.heading(str(part.name).to_upper(), Design.SIZE_SMALL)
	name_label.clip_text = true
	col.add_child(name_label)

	var cat := UIKit.micro_label(str(part.category),
		Design.AMBER if chosen else Design.INFO)
	col.add_child(cat)

	col.add_child(UIKit.numeric(Design.fmt_cash(int(part.get("price", 0))),
		Design.SIZE_SUB, Design.AMBER if chosen else Design.TEXT_PRIME))

	# The whole card is the target, laid over it so the labels stay readable.
	var hit := Button.new()
	hit.text = ""
	hit.flat = true
	hit.tooltip_text = str(part.name)
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	var hover: StyleBoxFlat = clear.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.08)
	hit.add_theme_stylebox_override("normal", clear)
	hit.add_theme_stylebox_override("hover", hover)
	hit.add_theme_stylebox_override("pressed", clear)
	hit.add_theme_stylebox_override("focus", clear)
	hit.pressed.connect(_on_card.bind(str(part.id)))
	frame.add_child(hit)

	return frame


## Amber ring on the chosen card, matching how the sidebar marks its row.
func _card_box(chosen: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Design.BG_PANEL, 0.86)
	sb.border_color = Design.AMBER if chosen else Design.EDGE_LINE
	sb.set_border_width_all(2 if chosen else 1)
	sb.set_corner_radius_all(Design.RADIUS_MD)
	sb.content_margin_left = Design.SP_2
	sb.content_margin_right = Design.SP_2
	sb.content_margin_top = Design.SP_2
	sb.content_margin_bottom = Design.SP_2
	return sb


func _on_card(part_id: String) -> void:
	_selected = part_id
	_rebuild_cards()
	await _show_details(part_id)


func _footer(note: String) -> void:
	var frame := get_tree().get_first_node_in_group("game_frame")
	if frame != null:
		frame.set_footer(note)


## Fill the panel for a part. The before-and-after figures come from the
## server; with no car there is nothing to compare against, so the panel shows
## the part and leaves the columns blank rather than inventing a baseline.
func _show_details(part_id: String) -> void:
	if _details == null:
		return
	var part := Catalog.get_part(part_id)
	if part.is_empty():
		return

	var shot: String = str(MODULE_ART.get(str(part.category), ""))
	var car := GameState.get_active_car()
	if car.is_empty():
		_details.show_part(part, {}, shot)
		return

	# Previews race: clicking two cards inside one round trip must land the
	# panel on the LAST click, not on whichever response was slower.
	_preview_seq += 1
	var seq := _preview_seq
	var res: Dictionary = await Api.preview_part(str(car.id), part_id)
	if not is_inside_tree() or seq != _preview_seq:
		return
	_details.show_part(part, res.data if res.get("ok", false) else {}, shot)


func _on_buy_part(part_id: String) -> void:
	await _fit(part_id)


func _on_install_part(part_id: String) -> void:
	await _fit(part_id)


## Buying and fitting are the same transaction here: the server takes the money
## and puts the part on the car in one step, so both buttons do the same thing
## rather than pretending to a two-stage flow the API does not have.
func _fit(part_id: String) -> void:
	var car := GameState.get_active_car()
	if car.is_empty():
		_footer("YOU NEED A CAR TO FIT PARTS TO")
		return
	if _fitting:
		return
	_fitting = true
	var res: Dictionary = await GameState.install_part(str(car.id), part_id)
	_fitting = false
	if not is_inside_tree():
		return
	if res.get("ok", false):
		_footer("FITTED")
		_rebuild_cards()
		await _show_details(part_id)
	else:
		# A refusal in silence reads as a dead button; say why.
		_footer(str(res.get("reason", "That didn't go through.")).to_upper())


func _on_next_page() -> void:
	_page += 1
	_rebuild_cards()
