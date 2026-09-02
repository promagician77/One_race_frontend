extends Control
## The garage: the cars you own, on the left, over the workshop floor.
##
## The sidebar artwork is an empty frame -- unlike the part shop's column it
## paints no rows -- so the whole list is built here and laid inside the
## opening. The frame is fitted the way the dealership's column is: a tall
## panel in a wide screen makes height the limit, so it stands full height and
## takes its width from its own aspect.

const BACKDROP := "res://assets/ui/garage_background.png"

const SIDEBAR := "res://assets/ui/garage_side.png"
const SIDE_W := 948.0
const SIDE_H := 1660.0

## The visible panel inside the file, measured with tools/ArtProbe.gd by alpha.
##
## The artwork carries transparent padding -- 137px left, 136 right, 42 top,
## 70 bottom -- so the frame is only 93% of the file's height and 71% of its
## width. Fitting the *file* to the content area therefore left the panel
## visibly short and floating off the border. The frame is fitted instead: the
## column is scaled and offset so this rectangle lands on the content area,
## and the empty pixels hang outside it and get clipped.
const FRAME := Rect2(137, 42, 674, 1547)

## Hand adjustment on top of the fit, in the artwork's pixels. Positive moves
## the column down. The fit puts the frame exactly on the content area; this
## is where it is wanted relative to that.
const SIDE_NUDGE_Y := 46.0

## How much of the floor the car takes. The rest is left clear on the right
## for a panel about the car it is showing.
const HERO_RIGHT := 0.62

## The frame's inner opening, inside its border. The border's inner face is a
## bright line at x=169 and x=779, y=58 and y=1557.
const OPENING := Rect2(195, 130, 560, 1390)

## Split of the opening: a heading, the list, and the sort control. In the
## artwork's pixels, so they scale with the panel like everything else.
const HEADER_H := 108.0
const FOOTER_H := 96.0

## Cards are sized in the artwork's pixels too, and converted at layout time.
const CARD_H := 250.0
const CARD_GAP := 14.0

## Type sizes in the artwork's pixels, scaled to the panel's real height. A
## fixed pixel size would be unreadable on a small window and lost on a large
## one, because the column's width follows the window.
const TYPE_HEADING := 46
const TYPE_COUNT := 44
const TYPE_CAR := 40
const TYPE_CLASS := 26
const TYPE_SORT := 30

var _list: VBoxContainer
var _count: Label
var _sort_button: Button
var _sort_plate: AngularPlate
var _side: Control
var _scaled: Array = []   ## [{ node, size }] -- type scaled with the panel
var _stats: Dictionary = {}   ## the selected car, as the server measures it

## The car being looked at, which is not the same as the one being driven.
## Clicking a card selects it; making it the active ride is a second step.
var _selected := ""

var _stage: Control          ## the floor to the right of the column
var _hero: TextureRect       ## the selected car, large
var _panel: GarageFuncPanel
var _fitter: AspectRatioContainer

## Cheapest first is a poor default in a garage -- you want to see what you
## drive. Class groups them the way the sample does.
const SORTS := ["CLASS", "NAME", "VALUE"]
var _sort := 0


func _ready() -> void:
	clip_contents = true
	GameState.garage_changed.connect(_rebuild)
	GameState.active_car_changed.connect(_on_active_changed)
	_build()
	_selected = GameState.active_car_id
	_rebuild()
	await _refresh_stats()


# ─────────────────────────────────────────────────────────────
# LAYOUT
# ─────────────────────────────────────────────────────────────

func _build() -> void:
	var ground := ColorRect.new()
	ground.color = Design.BG_VOID
	ground.set_anchors_preset(Control.PRESET_FULL_RECT)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	if ResourceLoader.exists(BACKDROP):
		var art := TextureRect.new()
		art.texture = load(BACKDROP)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(art)
	else:
		push_warning("Garage backdrop missing: %s" % BACKDROP)

	_build_sidebar()
	_build_stage()


## The floor to the right of the column: the car you are looking at, big, with
## a line saying whether it is the one you drive.
func _build_stage() -> void:
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	_hero = TextureRect.new()
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_hero)


	# The car's own panel, on the right of the floor.
	_panel = GarageFuncPanel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.set_active_requested.connect(_on_make_active)
	_panel.sell_requested.connect(_on_sell)
	_panel.exit_requested.connect(func(): Router.home())
	add_child(_panel)

	if _side != null:
		_side.resized.connect(_place_stage)
	_place_stage.call_deferred()


## How much the artwork is scaled so its visible frame fills the content area
## exactly. Taken from the screen's own height rather than the panel's, so it
## can be worked out before the panel has been laid out.
func _frame_scale() -> float:
	if size.y <= 0.0:
		return 0.0
	return size.y / FRAME.size.y


## The visible frame's width once scaled -- where the floor beside it starts.
func _frame_width() -> float:
	return FRAME.size.x * _frame_scale()


## Push the file out so its frame, not its edges, lands on the content area.
func _fit_column() -> void:
	if _fitter == null:
		return
	var k := _frame_scale()
	if k <= 0.0:
		return
	var nudge := SIDE_NUDGE_Y * k
	_fitter.offset_left = -FRAME.position.x * k
	_fitter.offset_top = -FRAME.position.y * k + nudge
	_fitter.offset_bottom = (SIDE_H - FRAME.position.y - FRAME.size.y) * k + nudge


## Everything on the floor is placed off the column's real width, because the
## column takes its width from its own aspect and so changes with the window.
func _place_stage() -> void:
	if _stage == null or _side == null:
		return

	_fit_column()

	var left := _frame_width() + Design.SP_5
	_stage.offset_left = left
	_stage.offset_top = 0
	_stage.offset_right = -Design.SP_5
	_stage.offset_bottom = -Design.SP_5

	# The car is kept to the left; the right of the floor is the panel's.
	_hero.anchor_left = 0.0
	_hero.anchor_top = 0.0
	_hero.anchor_right = HERO_RIGHT
	_hero.anchor_bottom = 1.0
	_hero.offset_left = 0
	_hero.offset_right = 0
	_hero.offset_top = 120.0
	_hero.offset_bottom = -70.0


	# The panel takes the strip the car was pulled back from, and stands the
	# same height as the column, nudge included, so the two read as a pair.
	if _panel != null:
		var nudge_px := SIDE_NUDGE_Y * _frame_scale()
		_panel.anchor_left = HERO_RIGHT
		_panel.anchor_right = 1.0
		_panel.anchor_top = 0.0
		_panel.anchor_bottom = 1.0
		_panel.offset_left = Design.SP_4
		_panel.offset_top = nudge_px
		_panel.offset_right = -Design.SP_3
		_panel.offset_bottom = nudge_px


func _build_sidebar() -> void:
	if not ResourceLoader.exists(SIDEBAR):
		push_warning("Garage sidebar missing: %s" % SIDEBAR)
		return

	_fitter = AspectRatioContainer.new()
	_fitter.ratio = SIDE_W / SIDE_H
	_fitter.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_BEGIN
	_fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	_fitter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fitter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fitter)
	var fitter := _fitter

	_side = Control.new()
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fitter.add_child(_side)

	var panel := TextureRect.new()
	panel.texture = load(SIDEBAR)
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	# The panel takes its own clicks rather than passing them to the floor.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_side.add_child(panel)

	# ── heading ──
	var head := HBoxContainer.new()
	_place(head, Rect2(OPENING.position.x, OPENING.position.y, OPENING.size.x, HEADER_H))

	var title := UIKit.heading("OWNED CARS", Design.SIZE_HEAD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	_scaled.append({"node": title, "size": TYPE_HEADING})

	_count = UIKit.numeric("", Design.SIZE_HEAD, Design.INFO)
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_count)
	_scaled.append({"node": _count, "size": TYPE_COUNT})

	# ── the cars ──
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(scroll, Rect2(OPENING.position.x, OPENING.position.y + HEADER_H,
		OPENING.size.x, OPENING.size.y - HEADER_H - FOOTER_H))

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", int(CARD_GAP))
	scroll.add_child(_list)

	# ── sort ──
	var foot := HBoxContainer.new()
	_place(foot, Rect2(OPENING.position.x,
		OPENING.position.y + OPENING.size.y - FOOTER_H, OPENING.size.x, FOOTER_H))

	var by := UIKit.micro_label("SORT BY:")
	by.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	by.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(by)
	_scaled.append({"node": by, "size": TYPE_SORT})

	# A holder so the plate can sit behind the button rather than inside it.
	var sort_holder := Control.new()
	sort_holder.custom_minimum_size = Vector2(128, 0)
	sort_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(sort_holder)

	var sort_button := _sort_control()
	sort_holder.add_child(_sort_plate)
	sort_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	sort_holder.add_child(sort_button)

	_side.resized.connect(_rescale)
	_rescale.call_deferred()


## Type and card heights are written in the artwork's pixels; this converts
## them to the panel's real size, and again whenever the window changes.
func _rescale() -> void:
	if _side == null or _side.size.y <= 0.0:
		return
	var factor: float = _side.size.y / SIDE_H

	for entry in _scaled:
		var node: Control = entry["node"]
		if is_instance_valid(node):
			node.add_theme_font_size_override("font_size",
				maxi(8, roundi(float(entry["size"]) * factor)))

	for card in _list.get_children():
		if card is Control:
			card.custom_minimum_size = Vector2(0, CARD_H * factor)


## The sort control, built to sit in this panel rather than on top of it.
##
## A stock button read as a grey slab, and a plain dark rectangle was no
## better: the frame around it is angular, with cut corners and a lit edge, so
## a square-cornered box still looked pasted on. The plate is drawn to match
## that, and the button itself is transparent over the top of it.
func _sort_control() -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(128, 0)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(_on_sort)
	b.add_theme_color_override("font_color", Design.TEXT_PRIME)
	b.add_theme_color_override("font_hover_color", Design.AMBER)
	b.add_theme_color_override("font_pressed_color", Design.AMBER)

	var clear := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, clear)

	# The plate cannot be a child of the button: a Control draws its own text
	# first and its children after, so the plate painted straight over the
	# label. It goes behind the button as a sibling instead.
	_sort_plate = AngularPlate.new()
	_sort_plate.set_anchors_preset(Control.PRESET_FULL_RECT)

	b.mouse_entered.connect(_on_sort_hover.bind(true))
	b.mouse_exited.connect(_on_sort_hover.bind(false))
	b.focus_entered.connect(_on_sort_hover.bind(true))
	b.focus_exited.connect(_on_sort_hover.bind(false))

	_sort_button = b
	_scaled.append({"node": b, "size": TYPE_SORT})
	return b


func _on_sort_hover(lit: bool) -> void:
	if _sort_plate == null:
		return
	_sort_plate.edge = Design.AMBER if lit else Design.EDGE_LINE
	_sort_plate.accent = Design.AMBER_HOT if lit else Design.AMBER_DIM


## Position a control inside the sidebar, in the artwork's own pixels.
func _place(node: Control, r: Rect2) -> void:
	node.anchor_left = r.position.x / SIDE_W
	node.anchor_top = r.position.y / SIDE_H
	node.anchor_right = (r.position.x + r.size.x) / SIDE_W
	node.anchor_bottom = (r.position.y + r.size.y) / SIDE_H
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	_side.add_child(node)


# ─────────────────────────────────────────────────────────────
# THE LIST
# ─────────────────────────────────────────────────────────────

func _rebuild() -> void:
	if _list == null:
		return

	# Detached before freeing: queue_free runs at the end of the frame, so
	# rebuilding twice in one frame would stack the new cards on the old.
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	# Card labels are recreated every rebuild; drop the dead ones or the list
	# grows without bound and starts writing to freed nodes.
	_scaled = _scaled.filter(func(e): return is_instance_valid(e["node"]))

	_count.text = "%d / %d" % [GameState.garage.size(), GameState.parking_limit()]
	_sort_button.text = "%s   ▾" % SORTS[_sort]

	if GameState.garage.is_empty():
		_list.add_child(UIKit.empty_state("Nothing parked here",
			"Buy something from a dealership and it turns up in this garage."))
		return

	for car in _sorted():
		_list.add_child(_card(car))

	_rescale()
	_refresh_stage()


## The player's cars in whichever order the sort control asks for.
func _sorted() -> Array:
	var cars := GameState.garage.duplicate()
	match SORTS[_sort]:
		"NAME":
			cars.sort_custom(func(a, b): return str(a.nickname) < str(b.nickname))
		"VALUE":
			cars.sort_custom(func(a, b): return _price(a) > _price(b))
		_:
			cars.sort_custom(func(a, b): return _class_of(a) < _class_of(b))
	return cars


func _model(car: Dictionary) -> Dictionary:
	return Catalog.get_car_model(str(car.get("model_id", "")))


func _class_of(car: Dictionary) -> String:
	return str(_model(car).get("class", ""))


func _price(car: Dictionary) -> int:
	return int(_model(car).get("price", 0))


func _card(car: Dictionary) -> Control:
	var model := _model(car)
	var car_class := str(model.get("class", ""))
	var active: bool = str(car.get("id", "")) == GameState.active_car_id
	var chosen: bool = str(car.get("id", "")) == _selected
	var impounded: bool = bool(car.get("impounded", false))

	# A Control, not a PanelContainer: a PanelContainer lays out every child
	# to fill it, which stretched the ACTIVE badge across the whole card
	# instead of leaving it in the corner. The background is a Panel behind
	# everything else instead.
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0, CARD_H * 0.4)

	var bg := Panel.new()
	bg.add_theme_stylebox_override("panel", _card_box(active, impounded, chosen))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(bg)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = Design.SP_3
	col.offset_right = -Design.SP_3
	col.offset_top = Design.SP_2
	col.offset_bottom = -Design.SP_2
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(col)

	# The car itself, cropped into the card.
	var shot := Control.new()
	shot.clip_contents = true
	shot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(shot)

	# The same photograph the showroom sells this car with. Asking Catalog
	# rather than reaching for the procedural sprite is what stops the garage
	# showing a flat silhouette of a car the dealership has a picture of.
	var picture := Catalog.car_shot(model)
	if picture != null:
		var img := TextureRect.new()
		img.texture = picture
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# Contained, inside a small inset: the whole car shows at a size that
		# leaves air around it, rather than being blown up and cropped by the
		# card's edges.
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.anchor_left = 0.06
		img.anchor_top = 0.06
		img.anchor_right = 0.94
		img.anchor_bottom = 0.94
		img.offset_left = 0
		img.offset_top = 0
		img.offset_right = 0
		img.offset_bottom = 0
		if impounded:
			# Seized cars are shown, greyed, so a player can see what they
			# have lost rather than wondering where it went.
			img.modulate = Color(0.45, 0.45, 0.5, 1.0)
		shot.add_child(img)

	var name_label := UIKit.heading(str(car.get("nickname", "")).to_upper(),
		Design.SIZE_SUB)
	name_label.clip_text = true
	col.add_child(name_label)
	_scaled.append({"node": name_label, "size": TYPE_CAR})

	var class_label := UIKit.micro_label("%s CLASS" % car_class,
		Design.CLASS_COLORS.get(car_class, Design.TEXT_MUTED))
	col.add_child(class_label)
	_scaled.append({"node": class_label, "size": TYPE_CLASS})

	# Top-right marker: a chip for the car you drive or one that has been
	# seized, a class-coloured dot for the rest.
	#
	# The old badge was anchored top-right with fixed offsets, but its label's
	# minimum size grew past that box at panel scale, and a Control expands
	# rightward and downward by default -- which dragged it into the middle of
	# the card. Growing from the END pins it to the corner: any expansion goes
	# leftward instead.
	var marker: Control
	if impounded or active:
		var chip := Label.new()
		chip.text = "IMPOUNDED" if impounded else "ACTIVE"
		chip.add_theme_color_override("font_color", Design.BG_VOID)
		var chip_box := StyleBoxFlat.new()
		chip_box.bg_color = Design.BAD if impounded else Design.AMBER
		chip_box.set_corner_radius_all(2)
		chip_box.content_margin_left = 8
		chip_box.content_margin_right = 8
		chip_box.content_margin_top = 2
		chip_box.content_margin_bottom = 2
		chip.add_theme_stylebox_override("normal", chip_box)
		_scaled.append({"node": chip, "size": 24})
		marker = chip
	else:
		var dot := ColorRect.new()
		dot.color = Design.CLASS_COLORS.get(car_class, Design.TEXT_MUTED)
		dot.custom_minimum_size = Vector2(12, 12)
		marker = dot

	marker.anchor_left = 1.0
	marker.anchor_right = 1.0
	marker.anchor_top = 0.0
	marker.anchor_bottom = 0.0
	marker.offset_left = -10.0
	marker.offset_right = -10.0
	marker.offset_top = 8.0
	marker.offset_bottom = 8.0
	marker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	marker.grow_vertical = Control.GROW_DIRECTION_END
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(marker)

	var hit := Button.new()
	hit.text = ""
	hit.flat = true
	hit.tooltip_text = "Release it from the impound" if impounded \
		else "Look at this one"
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)

	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	var hover: StyleBoxFlat = clear.duplicate()
	hover.bg_color = Color(1, 1, 1, 0.08)
	hit.add_theme_stylebox_override("normal", clear)
	hit.add_theme_stylebox_override("hover", hover)
	hit.add_theme_stylebox_override("pressed", clear)
	hit.add_theme_stylebox_override("disabled", clear)
	hit.add_theme_stylebox_override("focus", clear)
	hit.pressed.connect(_on_car.bind(str(car.get("id", "")), impounded))
	frame.add_child(hit)

	return frame


## Amber ring on the car you drive, red on anything seized.
func _card_box(active: bool, impounded: bool, chosen: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Design.BG_PANEL, 0.92 if chosen else 0.82)
	if impounded:
		sb.border_color = Design.BAD
	elif active:
		sb.border_color = Design.AMBER
	elif chosen:
		# Looking at a car you do not drive: marked, but not in the colour
		# that means "this is the one you race".
		sb.border_color = Design.INFO
	else:
		sb.border_color = Design.EDGE_LINE
	sb.set_border_width_all(2 if (active or impounded or chosen) else 1)
	sb.set_corner_radius_all(Design.RADIUS_MD)
	sb.content_margin_left = Design.SP_3
	sb.content_margin_right = Design.SP_3
	sb.content_margin_top = Design.SP_2
	sb.content_margin_bottom = Design.SP_2
	return sb


# ─────────────────────────────────────────────────────────────
# ACTIONS
# ─────────────────────────────────────────────────────────────

## Clicking a card looks at that car. Driving it is a separate decision, so a
## misclick in the list cannot change which car a race would use.
func _on_car(car_id: String, impounded: bool) -> void:
	if impounded:
		await GameState.release_from_impound(car_id)
		_rebuild()
		return
	_selected = car_id
	_rebuild()
	await _refresh_stats()


## Stats are the server's. Fetched when the selection changes rather than on
## every rebuild, so sorting the list does not cost a request.
func _refresh_stats() -> void:
	_stats = {}
	var car := GameState.get_car(_selected)
	if car.is_empty():
		return
	var res: Dictionary = await Api.fetch_stats(str(car.id))
	if res.get("ok", false):
		_stats = res.data
	_refresh_stage()


func _on_sell() -> void:
	var car := GameState.get_car(_selected)
	if car.is_empty():
		return
	await GameState.sell_car(str(car.id))
	_selected = GameState.active_car_id
	await _refresh_stats()
	_rebuild()


func _on_make_active() -> void:
	if _selected == "" or _selected == GameState.active_car_id:
		return
	await GameState.set_active_car(_selected)
	_rebuild()


func _on_active_changed(_car_id: String) -> void:
	_rebuild()


## Fill the floor for whichever car is being looked at.
func _refresh_stage() -> void:
	if _hero == null:
		return

	# A selection that no longer exists -- sold, or the garage reloaded --
	# falls back to the active car rather than showing a blank floor.
	if GameState.get_car(_selected).is_empty():
		_selected = GameState.active_car_id

	var car := GameState.get_car(_selected)
	if car.is_empty():
		_hero.visible = false
		return

	var model := _model(car)
	_hero.texture = Catalog.car_shot(model)
	_hero.visible = _hero.texture != null

	var is_active: bool = _selected == GameState.active_car_id
	var impounded: bool = bool(car.get("impounded", false))

	if _panel != null:
		_panel.show_car(car, _stats)


func _on_sort() -> void:
	_sort = (_sort + 1) % SORTS.size()
	_rebuild()
