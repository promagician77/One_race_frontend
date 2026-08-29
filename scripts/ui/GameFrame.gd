extends Control
## The game's permanent chrome: header, footer and the two glowing edges.
##
## Every in-game screen sits inside this frame, so it is built once in Main and
## never rebuilt on navigation. The four strips are cut out of citymap.png with
## AtlasTexture rather than shipped as separate files -- the frame in that image
## IS the frame, and slicing it keeps one source of truth.
##
## The artwork has sample values painted into the header and footer. Every one
## of them is live data, so each is masked and redrawn from GameState.

const ART_PATH := "res://assets/ui/citymap.png"
const ART_W := 1672.0
const ART_H := 941.0

# Chrome strips, in source-image pixels ───────────────────────────
const S_TOP    := Rect2(0, 0, 1672, 108)
const S_BOTTOM := Rect2(0, 848, 1672, 93)
const S_LEFT   := Rect2(0, 108, 28, 740)
const S_RIGHT  := Rect2(1644, 108, 28, 740)

## Where a screen's own content goes -- inside all four strips.
const CONTENT := Rect2(28, 108, 1616, 740)

# Painted values that are really live data ────────────────────────
const R_SCREEN  := Rect2(478, 40, 300, 32)
const R_LEVEL   := Rect2(1254, 48, 100, 28)
const R_CASH    := Rect2(1438, 28, 110, 26)
const R_CREDIT  := Rect2(1438, 56, 110, 26)
const R_NOTE    := Rect2(1228, 866, 240, 30)
const R_COUNT   := Rect2(1492, 862, 96, 36)

# Painted controls ────────────────────────────────────────────────
const R_LOGO     := Rect2(30, 14, 400, 74)
const R_AVATAR   := Rect2(1558, 14, 70, 78)
const R_WAYPOINT := Rect2(56, 870, 160, 36)
const R_TRAVEL   := Rect2(230, 870, 148, 36)
const R_FILTERS  := Rect2(394, 870, 108, 36)
const R_BACK     := Rect2(516, 870, 96, 36)

const FILL_HEADER := Color("#0B1017")
const FILL_FOOTER := Color("#0A0F15")

var frame: Control
var content: Control

var _screen_label: Label
var _level_label: Label
var _cash_label: Label
var _credit_label: Label
var _note_label: Label
var _count_label: Label
var _scaled: Array = []


func _ready() -> void:
	add_to_group("game_frame")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

	GameState.cash_changed.connect(_on_state_changed)
	GameState.neighborhood_changed.connect(_on_hood_changed)
	resized.connect(_rescale_type)

	refresh()
	_rescale_type()


# ─────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────

func _build() -> void:
	var fitter := AspectRatioContainer.new()
	fitter.ratio = ART_W / ART_H
	fitter.stretch_mode = AspectRatioContainer.STRETCH_COVER
	fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	fitter.set_anchors_preset(Control.PRESET_FULL_RECT)
	fitter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fitter)

	frame = Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fitter.add_child(frame)

	# Screens are added here by Main, underneath the chrome.
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(content, CONTENT)

	for strip in [S_TOP, S_BOTTOM, S_LEFT, S_RIGHT]:
		_strip(strip)

	_screen_label = _value(R_SCREEN, FILL_HEADER, Design.TEXT_MUTED, 20, HORIZONTAL_ALIGNMENT_LEFT)
	_level_label = _value(R_LEVEL, FILL_HEADER, Design.TEXT_PRIME, 22, HORIZONTAL_ALIGNMENT_LEFT)
	_cash_label = _value(R_CASH, FILL_HEADER, Design.TEXT_PRIME, 21, HORIZONTAL_ALIGNMENT_LEFT)
	_credit_label = _value(R_CREDIT, FILL_HEADER, Design.AMBER, 21, HORIZONTAL_ALIGNMENT_LEFT)
	_note_label = _value(R_NOTE, FILL_FOOTER, Design.TEXT_BODY, 17, HORIZONTAL_ALIGNMENT_RIGHT)
	_count_label = _value(R_COUNT, FILL_FOOTER, Design.INFO, 24, HORIZONTAL_ALIGNMENT_RIGHT)

	_hit(R_LOGO, "Back to the city map", _on_home)
	_hit(R_AVATAR, "Your racer profile", _on_profile)
	_hit(R_BACK, "Back", _on_back)
	_hit(R_WAYPOINT, "Waypoints arrive with the map update", _on_todo)
	_hit(R_TRAVEL, "Fast travel arrives with the map update", _on_todo)
	_hit(R_FILTERS, "Map filters arrive with the map update", _on_todo)


## One edge of the chrome, cut straight out of the artwork.
func _strip(region: Rect2) -> void:
	if not ResourceLoader.exists(ART_PATH):
		push_warning("Frame art missing: %s" % ART_PATH)
		return

	var atlas := AtlasTexture.new()
	atlas.atlas = load(ART_PATH)
	atlas.region = region

	var tex := TextureRect.new()
	tex.texture = atlas
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(tex, region)


func _value(r: Rect2, fill: Color, color: Color, size: int, align: int) -> Label:
	var mask := ColorRect.new()
	mask.color = fill
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(mask, r)

	var label := Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = align
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	Design.apply_mono(label)
	place(label, r)

	_scaled.append({"node": label, "size": size})
	return label


func _hit(r: Rect2, tooltip: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = ""
	b.tooltip_text = tooltip
	b.flat = true

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
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(handler)
	place(b, r)
	return b


func place(node: Control, r: Rect2) -> void:
	node.anchor_left = r.position.x / ART_W
	node.anchor_top = r.position.y / ART_H
	node.anchor_right = (r.position.x + r.size.x) / ART_W
	node.anchor_bottom = (r.position.y + r.size.y) / ART_H
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	frame.add_child(node)


## The frame stretches with the window but font sizes do not, so they are
## re-derived from the frame's real height whenever it changes.
func _rescale_type() -> void:
	var factor: float = clampf(frame.size.y / ART_H, 0.4, 3.0)
	for entry in _scaled:
		var label: Label = entry["node"]
		label.add_theme_font_size_override("font_size",
			maxi(9, roundi(float(entry["size"]) * factor)))


# ─────────────────────────────────────────────────────────────
# DATA
# ─────────────────────────────────────────────────────────────

func refresh() -> void:
	_cash_label.text = Design.fmt_cash(int(GameState.player.get("cash", 0)))
	_credit_label.text = _thousands(int(GameState.player.get("street_credit", 0)))
	# The art says LEVEL 24, but the game has ranks rather than numeric levels.
	_level_label.text = str(GameState.player.get("rank", "Noob")).to_upper()


func set_screen_name(screen_id: String) -> void:
	_screen_label.text = screen_id.replace("_", " ").to_upper()


## Footer readout. Screens with nothing to count clear it, which also covers
## the sample text painted into the artwork.
func set_footer(note: String, count: String = "") -> void:
	_note_label.text = note
	_count_label.text = count


func _thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out


func _on_state_changed(_v: int) -> void:
	refresh()


func _on_hood_changed(_id: String) -> void:
	refresh()


func _on_home() -> void:
	Router.home()


func _on_profile() -> void:
	Router.go(Router.Screen.PROFILE)


func _on_back() -> void:
	Router.back()


func _on_todo() -> void:
	pass
