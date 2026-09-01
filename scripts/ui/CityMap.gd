extends Control
## City map. The hub every session runs through.
##
## Hotspots are data, not scene nodes — position comes from the neighborhood
## config so the map can be re-laid-out without touching this file.

const HOTSPOT_SIZE := Vector2(56, 56)

## Locations placed on the map. `hood` gates whether the player can enter.
## Placed over the pins painted into citymap.png. Positions are the measured
## centres of the painted badges -- produced by tools/PinScan.gd, which reads
## the image and snaps each pin to the centre of mass of its coloured pixels,
## rather than being estimated off a screenshot.
##
## Each pin belongs to the district it is drawn inside, so the map reads the
## way the artwork labels it. The race track is deliberately ungated, like
## home and the impound: practice is the core loop and should not sit behind
## a move-in fee just because the track is painted in Westbay.
##
## Which neighbourhood owns which painted pin is provisional -- the art names
## its districts NORTHRIDGE / WESTBAY / DOWNTOWN / EASTPOINT / HARBOUR, and the
## game's are HARBOUR / NORTHRIDGE / EASTPOINT / WESTBAY / DOWNTOWN. Someone has to
## decide how those line up; this is a sensible guess, not a decision.
const LOCATIONS := [
	{ "id": "shop_northridge",   "hood": "NORTHRIDGE", "kind": "PARTS_SHOP", "label": "Part Shop",  "pos": Vector2(0.235, 0.151) },
	{ "id": "impound",           "hood": "",           "kind": "IMPOUND",    "label": "Impound",    "pos": Vector2(0.335, 0.082) },
	{ "id": "dealer_northridge", "hood": "NORTHRIDGE", "kind": "DEALERSHIP", "label": "Dealership", "pos": Vector2(0.527, 0.111) },
	{ "id": "dealer_eastpoint",  "hood": "EASTPOINT",  "kind": "DEALERSHIP", "label": "Dealership", "pos": Vector2(0.754, 0.168) },
	{ "id": "dealer_westbay",    "hood": "WESTBAY",    "kind": "DEALERSHIP", "label": "Dealership", "pos": Vector2(0.113, 0.351) },
	{ "id": "track",             "hood": "",           "kind": "PRACTICE",   "label": "Race Track", "district": "Westbay", "pos": Vector2(0.337, 0.435) },
	{ "id": "dealer_downtown",   "hood": "DOWNTOWN",   "kind": "DEALERSHIP", "label": "Dealership", "pos": Vector2(0.624, 0.427) },
	{ "id": "shop_eastpoint",    "hood": "EASTPOINT",  "kind": "PARTS_SHOP", "label": "Part Shop",  "pos": Vector2(0.848, 0.427) },
	{ "id": "shop_harbour",      "hood": "HARBOUR",    "kind": "PARTS_SHOP", "label": "Part Shop",  "pos": Vector2(0.713, 0.614) },
	{ "id": "home",              "hood": "",           "kind": "GARAGE",     "label": "Home",       "pos": Vector2(0.487, 0.728) },
	{ "id": "dealer_harbour",    "hood": "HARBOUR",    "kind": "DEALERSHIP", "label": "Dealership", "pos": Vector2(0.186, 0.788) },
]

@onready var _map_area: Control = $Layout/MapArea
@onready var _detail: PanelContainer = $Layout/DetailPanel

var _hotspots: Array = []
var _selected: Dictionary = {}

## Slides in from the right when a dealership is chosen.
var _modal: LocationModal = null


## Outline every pin and allow live nudging, so the LOCATIONS table can be
## corrected against the artwork instead of estimated off a screenshot.
##
##   TAB     select the next pin
##   ARROWS  move it one pixel   (SHIFT = 10)
##   ENTER   print the whole table, ready to paste back
const DEBUG_PINS := false

var _calib_index := 0


func _ready() -> void:
	GameState.neighborhood_changed.connect(_on_neighborhood_changed)
	GameState.garage_changed.connect(_refresh_hotspots)
	_build_backdrop()
	_float_detail()
	_build_modal()
	_build_hotspots()
	_show_default_detail()


## The map itself, cut out of citymap.png. The frame around it is drawn by
## GameFrame, so only the interior is taken here -- the same region the
## Router drops every screen into.
func _build_backdrop() -> void:
	const ART := "res://assets/ui/citymap.png"
	if not ResourceLoader.exists(ART):
		push_warning("Map art missing: %s" % ART)
		return

	var atlas := AtlasTexture.new()
	atlas.atlas = load(ART)
	atlas.region = Rect2(28, 108, 1616, 740)

	var tex := TextureRect.new()
	tex.texture = atlas
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_area.add_child(tex)
	_map_area.move_child(tex, 0)


## The detail panel was a column beside the map. With the map painted edge to
## edge it becomes a floating card instead, so nothing squashes the artwork.
func _float_detail() -> void:
	var parent := _detail.get_parent()
	if parent != null:
		parent.remove_child(_detail)
	add_child(_detail)
	_detail.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_detail.anchor_left = 0.68
	_detail.anchor_top = 0.42
	_detail.anchor_right = 0.985
	_detail.anchor_bottom = 0.97
	_detail.offset_left = 0
	_detail.offset_top = 0
	_detail.offset_right = 0
	_detail.offset_bottom = 0


func _build_hotspots() -> void:
	for loc in LOCATIONS:
		var spot := _make_hotspot(loc)
		_map_area.add_child(spot)
		_hotspots.append({ "node": spot, "data": loc, "mark": spot.get_node("Mark") })
	_refresh_hotspots()


## A transparent hit area over a painted pin. The artwork draws the icon and
## the caption; this catches the click, carries the tooltip, and hangs the
## reticle that marks it.
##
## `flat` is off deliberately. A flat Button skips its state styleboxes
## entirely, which is why the scrim over a locked pin never used to appear.
func _make_hotspot(loc: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = HOTSPOT_SIZE
	btn.tooltip_text = _tooltip_for(loc)
	btn.focus_mode = Control.FOCUS_ALL
	btn.name = "Dot"
	btn.pressed.connect(_on_hotspot_pressed.bind(loc))

	# Nothing is drawn on the button itself but the locked scrim, set by
	# _refresh_hotspots. Every other state is the reticle's job.
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(1, 1, 1, 0)
	clear.set_corner_radius_all(999)
	btn.add_theme_stylebox_override("focus", clear)
	btn.add_theme_stylebox_override("disabled", clear)

	var mark := PinReticle.new()
	mark.name = "Mark"
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(mark)

	btn.mouse_entered.connect(mark.set_hovered.bind(true))
	btn.mouse_exited.connect(mark.set_hovered.bind(false))
	btn.focus_entered.connect(mark.set_focused.bind(true))
	btn.focus_exited.connect(mark.set_focused.bind(false))

	if DEBUG_PINS:
		var outline := ReferenceRect.new()
		outline.border_color = Design.AMBER
		outline.editor_only = false
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		outline.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_child(outline)

	return btn


## Position + color hotspots against current player state.
func _refresh_hotspots() -> void:
	var area_size := _map_area.size
	if area_size == Vector2.ZERO:
		await get_tree().process_frame
		area_size = _map_area.size

	for h in _hotspots:
		var loc: Dictionary = h.data
		var node: Button = h.node

		node.position = Vector2(
			loc.pos.x * area_size.x - HOTSPOT_SIZE.x * 0.5,
			loc.pos.y * area_size.y - HOTSPOT_SIZE.y * 0.5
		)

		# The pin is painted, so a locked one cannot be recoloured -- it gets
		# a dark scrim over it instead, which reads the same way. Every state
		# carries it, or the scrim would blink off under the cursor.
		var accessible := _is_accessible(loc)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			node.add_theme_stylebox_override(state, _pin_box(accessible))
		node.tooltip_text = _tooltip_for(loc)

		# A gated pin locks on in warning colour: the mark says which pin the
		# player picked, and the colour says they cannot walk into it yet.
		var mark: PinReticle = h.mark
		mark.tint = Design.AMBER_HOT if accessible else Design.WARN

	_update_footer()


## Locked pins are dimmed because the artwork owns the pin and cannot be
## recoloured. Reachable ones draw nothing at all -- the reticle is the
## feedback, not a disc behind the icon.
func _pin_box(accessible: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(999)
	sb.bg_color = Color(0.02, 0.03, 0.04, 0.62) if not accessible else Color(1, 1, 1, 0)
	return sb


## The frame's footer carries the map's readout, replacing the sample text
## painted into the artwork.
func _update_footer() -> void:
	var frame := get_tree().get_first_node_in_group("game_frame")
	if frame == null:
		return
	var open_count := 0
	for h in _hotspots:
		if _is_accessible(h.data):
			open_count += 1
	frame.set_footer("LOCATIONS UNLOCKED",
		"%d / %d" % [open_count, _hotspots.size()])



func _dot_box(tint: Color, accessible: bool, hover: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Design.BG_HOVER if hover else Design.BG_PANEL
	sb.border_color = tint if accessible else Design.EDGE_LINE
	sb.set_border_width_all(2 if hover else 1)
	sb.set_corner_radius_all(17)
	return sb


func _color_for(loc: Dictionary) -> Color:
	if loc.hood == "":
		return Design.AMBER
	var hood := Catalog.get_neighborhood(loc.hood)
	return Color(hood.get("colorCode", "#8B8B8B"))


func _is_accessible(loc: Dictionary) -> bool:
	# Home and impound are always reachable
	if loc.hood == "":
		return true
	# Dealerships and shops follow the shop-down rule
	return GameState.can_shop_in(loc.hood)


func _tooltip_for(loc: Dictionary) -> String:
	if loc.hood == "":
		return loc.label
	var hood_name: String = Catalog.get_neighborhood(loc.hood).get("name", loc.hood)
	if _is_accessible(loc):
		return "%s — %s" % [loc.label, hood_name]
	return "%s — %s (move up to shop here)" % [loc.label, hood_name]

# ─────────────────────────────────────────────────────────────
# INTERACTION
# ─────────────────────────────────────────────────────────────

func _on_hotspot_pressed(loc: Dictionary) -> void:
	_selected = loc
	for h in _hotspots:
		h.mark.set_selected(h.data.id == loc.id)

	# Locations with artwork of their own get the panel; the rest use the card.
	if _modal != null and LocationModal.handles(str(loc.get("kind", ""))):
		_detail.hide()
		_modal.open_for(loc)
		return

	if _modal != null:
		_modal.close()
	_detail.show()
	_show_detail(loc)


func _build_modal() -> void:
	_modal = LocationModal.new()
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.entered.connect(_on_modal_enter)
	_modal.travel_requested.connect(_on_modal_travel)
	_modal.closed.connect(_on_modal_closed)
	add_child(_modal)


func _on_modal_enter(loc: Dictionary) -> void:
	_modal.close()
	_enter_location(loc, not _is_accessible(loc))


## Fast travel is painted into the artwork but the game has no travel
## mechanic -- moving neighbourhood is a paid, permanent decision made from
## the map, not a shortcut. Say so rather than doing something surprising.
func _on_modal_travel(_loc: Dictionary) -> void:
	var frame := get_tree().get_first_node_in_group("game_frame")
	if frame != null:
		frame.set_footer("FAST TRAVEL NOT AVAILABLE YET")


func _on_modal_closed() -> void:
	_detail.show()


func _show_detail(loc: Dictionary) -> void:
	for c in _detail.get_children():
		c.queue_free()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Design.SP_3)

	var hood_name: String = "Your home" if loc.hood == "" \
		else Catalog.get_neighborhood(loc.hood).get("name", loc.hood)

	box.add_child(UIKit.micro_label(hood_name))
	box.add_child(UIKit.heading(loc.label, Design.SIZE_SUB))

	var accessible := _is_accessible(loc)

	if accessible:
		box.add_child(UIKit.body(_blurb_for(loc), Design.TEXT_MUTED))
		box.add_child(UIKit.spacer(Design.SP_2))

		var enter := UIKit.button("Enter", UIKit.BtnStyle.PRIMARY)
		enter.pressed.connect(_enter_location.bind(loc))
		box.add_child(enter)
	else:
		var hood := Catalog.get_neighborhood(loc.hood)
		var warn := UIKit.accent_panel(Design.WARN)
		var wl := UIKit.body(
			"You need to live in %s to shop here. Moving in costs %s." % [
				hood.get("name", loc.hood),
				Design.fmt_cash(hood.get("moveInCost", 0))
			], Design.TEXT_BODY)
		warn.add_child(wl)
		box.add_child(warn)
		box.add_child(UIKit.spacer(Design.SP_2))

		var peek := UIKit.button("Window shop", UIKit.BtnStyle.SECONDARY)
		peek.pressed.connect(_enter_location.bind(loc, true))
		box.add_child(peek)

	_detail.add_child(box)


func _blurb_for(loc: Dictionary) -> String:
	match loc.kind:
		"DEALERSHIP": return "Buy and sell cars. Stock changes by neighborhood."
		"PARTS_SHOP": return "Performance and aesthetic parts. Match your air system before adding boost."
		"PRACTICE":   return "Run solo passes. No wager, no risk to your record."
		"GARAGE":     return "Your cars, your tunes, your active ride."
		"IMPOUND":    return "Cars seized when you moved down. Pay the fee to get them back."
	return ""


func _enter_location(loc: Dictionary, window_only: bool = false) -> void:
	var ctx := {
		"neighborhood": loc.hood,
		"window_only": window_only,
		"origin": loc.id,
	}

	match loc.kind:
		"DEALERSHIP": Router.go(Router.Screen.DEALERSHIP, ctx)
		"PARTS_SHOP": Router.go(Router.Screen.PARTS_SHOP, ctx)
		"GARAGE":     Router.go(Router.Screen.GARAGE, ctx)
		"PRACTICE":   Router.go(Router.Screen.PRACTICE, ctx)
		"IMPOUND":    _show_impound()


func _show_impound() -> void:
	# M1: impound is reachable but empty until the economy lands in M2.
	for c in _detail.get_children():
		c.queue_free()
	_detail.add_child(UIKit.empty_state(
		"Nothing impounded",
		"Cars end up here when you move to a smaller neighborhood."))


func _show_default_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()

	var hood := GameState.current_neighborhood()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", Design.SP_3)

	box.add_child(UIKit.micro_label("You live in"))
	box.add_child(UIKit.heading(hood.get("name", "Harbour District"), Design.SIZE_SUB))
	box.add_child(UIKit.body(hood.get("blurb", ""), Design.TEXT_MUTED))
	box.add_child(UIKit.divider())

	box.add_child(UIKit.stat_row("Parking",
		"%d / %d" % [GameState.parking_used(), GameState.parking_limit()]))
	box.add_child(UIKit.stat_row("Cash",
		Design.fmt_cash(GameState.player.cash), Design.CASH))
	box.add_child(UIKit.stat_row("Street credit",
		str(GameState.player.street_credit)))

	_detail.add_child(box)


func _on_neighborhood_changed(_id: String) -> void:
	_refresh_hotspots()
	_show_default_detail()


func _notification(what: int) -> void:
	# Fires during construction too, before _ready has built the hotspot list.
	if what == NOTIFICATION_RESIZED and not _hotspots.is_empty():
		_refresh_hotspots()


# ─────────────────────────────────────────────────────────────
# PIN CALIBRATION  (only live while DEBUG_PINS is on)
# ─────────────────────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not DEBUG_PINS or _hotspots.is_empty():
		return
	if not (event is InputEventKey) or not event.pressed:
		return

	var key := event as InputEventKey

	if key.keycode == KEY_TAB:
		_calib_index = (_calib_index + 1) % _hotspots.size()
		print("  selected: %s" % _hotspots[_calib_index].data.get("id", "?"))
		get_viewport().set_input_as_handled()
		return

	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		_dump_locations()
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

	var area := _map_area.size
	if area.x <= 0.0 or area.y <= 0.0:
		return

	var entry: Dictionary = _hotspots[_calib_index].data
	entry.pos += Vector2(delta.x / area.x, delta.y / area.y)
	_refresh_hotspots()

	print("  %s  Vector2(%.3f, %.3f)" % [entry.get("id", "?"), entry.pos.x, entry.pos.y])
	get_viewport().set_input_as_handled()


func _dump_locations() -> void:
	print("\n--- paste into CityMap.gd ---")
	for h in _hotspots:
		var d: Dictionary = h.data
		print('\t{ "id": "%s", "hood": "%s", "kind": "%s", "label": "%s", "pos": Vector2(%.3f, %.3f) },'
			% [d.get("id", ""), d.get("hood", ""), d.get("kind", ""), d.get("label", ""),
			   d.pos.x, d.pos.y])
	print("--- end ---\n")
