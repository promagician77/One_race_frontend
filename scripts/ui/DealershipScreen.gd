extends Control
## The dealership floor. The sidebar lands first.
##
## The categories and sort column is one piece of artwork. Every row in it is a
## hit area measured off that artwork rather than estimated, the same way
## LocationModal works, and the selection is the artwork's own ring lifted off
## the row it was painted on and stamped wherever the selection actually is.

signal category_chosen(index: int)
signal sort_chosen(index: int)

const ART := "res://assets/ui/dealership_sidebar.png"
const ART_W := 862.0
const ART_H := 1824.0

## The showroom floor the sidebar stands on. It is a photograph rather than
## panel art, so it is covered rather than fitted -- the floor fills the whole
## content area at its own aspect and loses whatever overhangs, which keeps the
## horizon level instead of stretching it to the frame.
const BACKDROP := "res://assets/ui/dealership_background.png"

## The floor sits to the right of the column, off its real width rather than a
## guessed fraction of the screen -- the sidebar takes its width from its own
## aspect, so how much of the screen it covers changes with the window.
const FLOOR_GAP := 24
const FLOOR_MARGIN := 20

## Rows, in the artwork's own pixels. Both lists share the column's left edge
## and width; only the pitch differs.
const ROW_X := 99.0
const ROW_W := 658.0

const CATEGORY_TOP := 165.0
const CATEGORY_H := 101.0
const CATEGORY_PITCH := 101.7
const CATEGORIES := ["ALL CARS", "STREET", "SPORTS", "MUSCLE", "SUPER", "HYPER"]

const SORT_TOP := 920.0
const SORT_H := 86.0
const SORT_PITCH := 86.7
const SORTS := [
	"PRICE: LOW TO HIGH", "PRICE: HIGH TO LOW",
	"NAME: A TO Z", "NAME: Z TO A", "NEW ARRIVALS",
]

## The ring painted around ALL CARS, cut into five pieces: two end bands
## carrying the chamfered corners, two straight side lines, and the diamond.
##
## It is sliced rather than nine-patched because a NinePatchRect's margins are
## texture pixels drawn one-to-one on screen, and this panel renders at about a
## third of its own size -- 22px of margin top and bottom came to more than the
## row was tall, so the corners overlapped and smeared across the label. These
## pieces are placed in the artwork's coordinates like everything else, so they
## scale with the panel. Only the side lines stretch, and they are straight.
const RING_TOP     := Rect2(99, 156, 660, 24)
const RING_BOTTOM  := Rect2(99, 244, 660, 24)
const RING_LEFT    := Rect2(99, 190, 16, 40)
const RING_RIGHT   := Rect2(746, 184, 16, 16)
const RING_DIAMOND := Rect2(741, 202, 28, 28)

## How far the ring stands outside the row it marks.
const RING_PAD_TOP := 9.0
const RING_PAD_BOTTOM := 2.0

## The selection painted onto ALL CARS, taken back off. It is three things: a
## lift across the row's interior, the ring, and the diamond. The lift is
## subtracted out -- #000508 off the row puts its background back on #020405,
## what every other row sits at, while the icon and label give up so little of
## their own brightness that neither looks dimmed. The ring and the diamond are
## then covered outright, with the column's own fill inside its edge and the
## margin's fill past it, where the diamond overhangs.
const LIFT := Color(0, 5.0 / 255.0, 8.0 / 255.0)
const FILL_ROW := Color("#020405")
const FILL_MARGIN := Color("#000306")

var _frame: Control
var _floor: DealershipFloor
var _category_ring: Array = []
var _category := 0
var _sort := 0


func _ready() -> void:
	_build()


# ─────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────

func _build() -> void:
	_backdrop()

	# Fitting a tall panel inside a wide screen makes height the limit, so the
	# sidebar is as tall as the floor and takes its width from the art.
	var fitter := AspectRatioContainer.new()
	fitter.ratio = ART_W / ART_H
	fitter.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_BEGIN
	fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	fitter.set_anchors_preset(Control.PRESET_FULL_RECT)
	fitter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fitter)

	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fitter.add_child(_frame)

	if not ResourceLoader.exists(ART):
		push_warning("Sidebar art missing: %s" % ART)
		return

	var art := TextureRect.new()
	art.texture = load(ART)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	# The column catches its own clicks rather than letting them fall through.
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_frame.add_child(art)

	_paint_out_selection()

	_category_ring = _ring()

	for i in CATEGORIES.size():
		_hit(_category_rect(i), CATEGORIES[i], _on_category.bind(i))
	for i in SORTS.size():
		_hit(_sort_rect(i), SORTS[i], _on_sort.bind(i))

	_place_ring(_category_ring, _category_rect(_category))

	_build_floor()


## The cars, and the one picked out of them. The column and the floor talk
## through signals only -- this hands them to each other and then stays out of
## the way.
func _build_floor() -> void:
	_floor = DealershipFloor.new()
	_floor.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_floor)
	_floor.follow(self)

	# The column's width is only real once the aspect fitter has laid it out,
	# which has not happened yet, so the first placement is deferred and every
	# later one rides the column's own resize.
	_frame.resized.connect(_place_floor)
	_place_floor.call_deferred()


func _place_floor() -> void:
	if _floor == null or _frame == null:
		return
	_floor.offset_left = _frame.size.x + FLOOR_GAP
	_floor.offset_top = FLOOR_MARGIN
	_floor.offset_right = -FLOOR_MARGIN
	_floor.offset_bottom = -FLOOR_MARGIN


## The showroom behind everything else. It is added first so it sits at the
## bottom of the draw order, and it takes no clicks -- the rows above it own
## every hit area on this screen.
func _backdrop() -> void:
	if not ResourceLoader.exists(BACKDROP):
		push_warning("Dealership backdrop missing: %s" % BACKDROP)
		return

	var floor_art := TextureRect.new()
	floor_art.texture = load(BACKDROP)
	floor_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	floor_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	floor_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	floor_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(floor_art)


## Everything the artwork paints onto the ALL CARS row to mark it as chosen.
## Order matters: the lift is taken off first, then the covers go over the top
## of it, so they are not darkened along with the row underneath.
func _paint_out_selection() -> void:
	var row := _category_rect(0)
	_subtract(Rect2(row.position.x + 2, row.position.y + 2, row.size.x - 4, row.size.y - 4))

	_fill(Rect2(99, 154, 658, 24), FILL_ROW)     # top line and its glow
	_fill(Rect2(99, 250, 658, 20), FILL_ROW)     # bottom line and its glow
	_fill(Rect2(99, 154, 22, 116), FILL_ROW)     # left line, corners included
	_fill(Rect2(738, 154, 19, 116), FILL_ROW)    # right line and the diamond
	_fill(Rect2(757, 154, 14, 116), FILL_MARGIN) # the overhang past the edge


## The five pieces of the ring, ready to be laid around whichever category is
## chosen. The ring belongs to that list alone -- the sort rows track their own
## choice and say so when asked, but the artwork marks no sort, and neither do
## we. Each piece stretches with the panel because it is placed in the
## artwork's own coordinates.
func _ring() -> Array:
	var pieces: Array = []
	for region in [RING_TOP, RING_BOTTOM, RING_LEFT, RING_RIGHT, RING_DIAMOND]:
		var atlas := AtlasTexture.new()
		atlas.atlas = load(ART)
		atlas.region = region

		var piece := TextureRect.new()
		piece.texture = atlas
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_SCALE
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_frame.add_child(piece)
		pieces.append(piece)
	return pieces


## Lays the ring around one row. The column's rows all share the artwork's own
## width, so the end bands are never stretched sideways; only the two side
## lines stretch, and being straight lines they take any row height.
func _place_ring(pieces: Array, row: Rect2) -> void:
	if pieces.size() < 5:
		return

	var top: float = row.position.y - RING_PAD_TOP
	var bottom: float = row.position.y + row.size.y + RING_PAD_BOTTOM
	var band_top: float = bottom - RING_BOTTOM.size.y
	var line_top: float = top + RING_TOP.size.y

	_place(pieces[0], Rect2(RING_TOP.position.x, top, RING_TOP.size.x, RING_TOP.size.y))
	_place(pieces[1], Rect2(RING_BOTTOM.position.x, band_top,
		RING_BOTTOM.size.x, RING_BOTTOM.size.y))
	_place(pieces[2], Rect2(RING_LEFT.position.x, line_top,
		RING_LEFT.size.x, band_top - line_top))
	_place(pieces[3], Rect2(RING_RIGHT.position.x, line_top,
		RING_RIGHT.size.x, band_top - line_top))
	_place(pieces[4], Rect2(RING_DIAMOND.position.x,
		row.position.y + row.size.y * 0.5 - RING_DIAMOND.size.y * 0.5,
		RING_DIAMOND.size.x, RING_DIAMOND.size.y))


func _fill(r: Rect2, colour: Color) -> void:
	var patch := ColorRect.new()
	patch.color = colour
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(patch, r)


## Takes a flat amount of light back off whatever is underneath, rather than
## laying more paint over it.
func _subtract(r: Rect2) -> void:
	var patch := ColorRect.new()
	patch.color = LIFT
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	patch.material = mat
	_place(patch, r)


func _hit(r: Rect2, tooltip: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = ""
	b.tooltip_text = tooltip
	b.flat = true

	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	var hover: StyleBoxFlat = clear.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.06)
	var pressed: StyleBoxFlat = clear.duplicate()
	pressed.bg_color = Color(0, 0, 0, 0.20)
	var focus: StyleBoxFlat = clear.duplicate()
	focus.border_color = Design.AMBER
	focus.set_border_width_all(2)

	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(handler)
	_place(b, r)
	return b


## Rects are written in the artwork's pixels for legibility, then rebased onto
## the panel actually being drawn.
func _place(node: Control, r: Rect2) -> void:
	node.anchor_left = r.position.x / ART_W
	node.anchor_top = r.position.y / ART_H
	node.anchor_right = (r.position.x + r.size.x) / ART_W
	node.anchor_bottom = (r.position.y + r.size.y) / ART_H
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	if node.get_parent() == null:
		_frame.add_child(node)


# ─────────────────────────────────────────────────────────────
# ROWS
# ─────────────────────────────────────────────────────────────

func _category_rect(i: int) -> Rect2:
	return Rect2(ROW_X, CATEGORY_TOP + CATEGORY_PITCH * i, ROW_W, CATEGORY_H)


func _sort_rect(i: int) -> Rect2:
	return Rect2(ROW_X, SORT_TOP + SORT_PITCH * i, ROW_W, SORT_H)


func _on_category(index: int) -> void:
	if index == _category:
		return
	_category = index
	_place_ring(_category_ring, _category_rect(index))
	category_chosen.emit(index)


func _on_sort(index: int) -> void:
	if index == _sort:
		return
	_sort = index
	sort_chosen.emit(index)


## What the floor is filtered and ordered by. The list reads these when it
## lands; nothing else on the screen exists yet.
func selected_category() -> String:
	return CATEGORIES[_category]


func selected_sort() -> String:
	return SORTS[_sort]
