class_name LocationModal
extends Control
## The location panel, slid in from the right when a map pin is chosen.
##
## One script serves every location that has artwork of its own. The art is
## shown whole and the values painted into it -- district, stock count, price
## band -- are masked and redrawn, because all of them change with the pin you
## picked. Every rect and colour below was measured with tools/ArtProbe.gd
## rather than estimated.

signal entered(loc: Dictionary)
signal travel_requested(loc: Dictionary)
signal closed()

## Per-location artwork and geometry.
##
## `r_*` masks cover the painted value and are padded; `t_*` is where the
## replacement type sits, on the artwork's own baseline. `crop` is the panel
## within its canvas -- both PNGs are opaque black outside it.
##
## `r_location` is cut to the painted name and nothing more. It used to span
## the whole row, which reached past the dark plate the name sits on and
## flattened the lit skyline beside it into a black bar. The name's own ink
## was found by hue, so the mask covers it and leaves the art alone. Race
## track and home keep their full-row mask: their name shares a hue with the
## art right next to it, so there is no safe line to cut on.
const KINDS := {
	"DEALERSHIP": {
		"art": "res://assets/ui/dealership.png",
		"crop": Rect2(66, 52, 893, 1391),
		"r_location": Rect2(204, 469, 196, 43), "t_location": Rect2(210, 464, 296, 52),
		"r_count":    Rect2(239, 685, 59, 49),  "t_count":    Rect2(245, 677, 118, 52),
		"r_price":    Rect2(456, 684, 160, 49), "t_price":    Rect2(462, 681, 180, 50),
		"r_refresh":  Rect2(738, 688, 114, 42), "t_refresh":  Rect2(744, 679, 165, 46),
		"s_count": 51, "s_price": 38, "s_refresh": 41,
		"r_close":  Rect2(816, 104, 88, 80),
		"r_enter":  Rect2(140, 1102, 744, 100),
		"r_travel": Rect2(140, 1244, 744, 92),
		"preview": [
			Rect2(146, 886, 152, 133), Rect2(322, 886, 153, 133),
			Rect2(499, 886, 151, 133), Rect2(674, 886, 152, 133),
		],
		"r_next": Rect2(840, 916, 48, 74),
		"ink": Color("#31CDF7"),
		"fill_location": Color("#05080C"),
		"fill_stat": Color("#030608"),
		"middle": "band",
	},
	"PARTS_SHOP": {
		"art": "res://assets/ui/partshop.png",
		"crop": Rect2(62, 50, 903, 1445),
		"r_location": Rect2(206, 479, 236, 44), "t_location": Rect2(213, 472, 306, 58),
		"r_count":    Rect2(236, 708, 70, 56),  "t_count":    Rect2(244, 714, 64, 44),
		"r_price":    Rect2(500, 702, 208, 60), "t_price":    Rect2(507, 708, 196, 48),
		"r_refresh":  Rect2(740, 698, 190, 66), "t_refresh":  Rect2(748, 706, 178, 48),
		"r_close":  Rect2(818, 100, 100, 92),
		"r_enter":  Rect2(140, 1150, 750, 108),
		"r_travel": Rect2(140, 1296, 750, 96),
		"ink": Color("#FF9B03"),
		"fill_location": Color("#030505"),
		"fill_stat": Color("#040504"),
		"count": "cars", "middle": "band", "third": "none",
	},
	"IMPOUND": {
		"art": "res://assets/ui/impound.png",
		"crop": Rect2(76, 46, 937, 1371),
		"r_location": Rect2(223, 473, 211, 45), "t_location": Rect2(230, 466, 314, 58),
		"r_count":    Rect2(258, 698, 92, 54),  "t_count":    Rect2(266, 704, 82, 42),
		"r_price":    Rect2(502, 686, 202, 66), "t_price":    Rect2(510, 694, 192, 50),
		"r_refresh":  Rect2(792, 688, 196, 66), "t_refresh":  Rect2(800, 696, 186, 50),
		"r_close":  Rect2(872, 110, 76, 80),
		"r_enter":  Rect2(150, 1105, 790, 110),
		"r_travel": Rect2(155, 1242, 780, 88),
		"ink": Color("#FF3C37"),
		"fill_location": Color("#020405"),
		"fill_stat": Color("#040505"),
		"count": "impounded", "middle": "release_fee", "third": "none",
	},
	"PRACTICE": {
		"art": "res://assets/ui/racestack.png",
		"crop": Rect2(62, 48, 897, 1447),
		"r_location": Rect2(192, 398, 326, 74), "t_location": Rect2(200, 405, 312, 60),
		"r_count":    Rect2(226, 776, 90, 54),  "t_count":    Rect2(234, 782, 80, 42),
		"r_price":    Rect2(484, 768, 202, 66), "t_price":    Rect2(491, 776, 192, 50),
		"r_refresh":  Rect2(716, 766, 214, 68), "t_refresh":  Rect2(724, 774, 202, 52),
		"r_close":  Rect2(832, 104, 96, 86),
		"r_enter":  Rect2(140, 1188, 800, 112),
		"r_travel": Rect2(145, 1326, 795, 92),
		"ink": Color("#FFBA0B"),
		"fill_location": Color("#020607"),
		"fill_stat": Color("#040708"),
		"count": "events", "middle": "entry_fee", "third": "best_time",
	},
	"GARAGE": {
		"art": "res://assets/ui/home.png",
		"crop": Rect2(68, 28, 949, 1401),
		"r_location": Rect2(205, 364, 246, 68), "t_location": Rect2(213, 371, 232, 54),
		"r_count":    Rect2(248, 774, 92, 58),  "t_count":    Rect2(256, 780, 82, 46),
		"r_price":    Rect2(494, 772, 104, 58), "t_price":    Rect2(502, 778, 94, 46),
		"r_refresh":  Rect2(742, 768, 212, 70), "t_refresh":  Rect2(748, 776, 200, 54),
		"r_close":  Rect2(890, 86, 96, 84),
		"r_enter":  Rect2(148, 1132, 790, 112),
		"r_travel": Rect2(152, 1266, 815, 100),
		"ink": Color("#FF9D05"),
		"fill_location": Color("#000001"),
		"fill_stat": Color("#030607"),
		"count": "owned", "middle": "slots", "third": "active_ride",
	},
}

## The chamfered corners are black inside the crop and need keying out.
##
## Keying on luminance alone was wrong: these panels have very dark interiors
## -- 30% of the part shop sits under 0.022 -- so a global cut faded a third
## of the panel to part-transparent and the map showed through. The key is now
## confined to the corner squares, where the black actually is, and the cut
## itself is far lower. The interior is never touched, however dark it gets.
const CORNER_CUT_LOW := 0.002
const CORNER_CUT_HIGH := 0.010

## How far in from each corner the key applies, as a fraction of the panel.
const CORNER_REACH := 0.18

const INK_WHITE := Color("#E8ECF0")
const INK_AMBER := Color("#F0A020")

## Type sizes for the redrawn values, in the artwork's own pixels.
##
## The location is set in the monospace face, not the display one. The name
## painted into the art is a squared fixed-width type -- its I carries
## crossbars, and C, E and D all take the same advance -- which the condensed
## display face cannot imitate at any size. Mono carries a 0.73em cap, so 42
## puts the redrawn name on the artwork's own 31px cap and, on four of the
## five panels, within a pixel of its baseline.
const LOCATION_SIZE := 42
const STAT_SIZE := 40

## The dealership's stats were measured the same way and override the default:
## the artwork sets its car count at a 37px cap, the price band and the refresh
## clock at 31 and 30. `s_*` on a kind carries that; the rest fall back.

## Where a value stops shrinking to fit its plate.
const VALUE_MIN_SIZE := 24

## Car photographs, dropped in as numbered cutouts on transparent ground.
const CAR_SHOT_DIR := "res://assets/ui/cars/"

## How many of them are there. Counted once, on first use, so another photo
## dropped in beside them needs no code change.
static var _shots := -1

## How far off-screen it starts, as a fraction of its own width.
const SLIDE_FROM := 1.06
const SLIDE_TIME := 0.28

## The preview strip's page turn. Photos leave to the left and the next ones
## arrive from the right, each box a beat behind the one before it, so the
## strip reads as one moving row rather than four boxes blinking at once.
const SHOT_OUT := 0.10
const SHOT_IN := 0.16
const SHOT_STAGGER := 0.035

## How far a photo travels on its way out, as a fraction of its own box.
const SHOT_TRAVEL := 0.35

var frame: Control

var _cfg: Dictionary = {}
var _fitter: AspectRatioContainer = null
var _location_label: Label = null
var _count_label: Label = null
var _price_label: RichTextLabel = null
var _refresh_label: Label = null
var _scaled: Array = []
var _previews: Array = []
var _shot_ring: Array = []
var _shot_page := 0
var _shot_tween: Tween = null
var _location_scale: Dictionary = {}
var _count_scale: Dictionary = {}
var _price_scale: Dictionary = {}
var _refresh_scale: Dictionary = {}
var _tween: Tween = null
var _loc: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _ready() -> void:
	resized.connect(_rescale_type)


func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _shot_tween != null and _shot_tween.is_valid():
		_shot_tween.kill()
	_shot_tween = null


## Does this location have artwork of its own?
static func handles(kind: String) -> bool:
	return KINDS.has(kind)


# ─────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────

## Rebuilt per kind rather than kept around for each, because only one panel
## is ever on screen and the layouts differ in more than a few pixels.
func _build(kind: String) -> void:
	if _fitter != null:
		_fitter.queue_free()
	_scaled.clear()
	_previews.clear()

	_cfg = KINDS[kind]
	var crop: Rect2 = _cfg["crop"]

	_fitter = AspectRatioContainer.new()
	_fitter.ratio = crop.size.x / crop.size.y
	_fitter.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_fitter.alignment_horizontal = AspectRatioContainer.ALIGNMENT_END
	_fitter.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	_fitter.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fitter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fitter)

	frame = Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The fitter has not sorted its children yet, so the frame is still zero
	# sized while this runs. Type is sized off the frame, so it has to be
	# redone the moment the frame gets its real size -- otherwise every value
	# on the panel stays at the floor of the scale and reads as a caption.
	frame.resized.connect(_on_frame_resized)
	_fitter.add_child(frame)

	var art_path: String = _cfg["art"]
	if ResourceLoader.exists(art_path):
		var atlas := AtlasTexture.new()
		atlas.atlas = load(art_path)
		atlas.region = crop

		var art := TextureRect.new()
		art.texture = atlas
		art.material = _corner_key()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		# The panel catches clicks so they do not fall through to the map.
		art.mouse_filter = Control.MOUSE_FILTER_STOP
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.add_child(art)
	else:
		push_warning("Location art missing: %s" % art_path)

	var ink: Color = _cfg["ink"]
	_location_label = _value(_cfg["r_location"], _cfg["t_location"],
		_cfg["fill_location"], ink, _size("s_location", LOCATION_SIZE))
	_location_scale = _scaled[_scaled.size() - 1]
	_count_label = _value(_cfg["r_count"], _cfg["t_count"], _cfg["fill_stat"], ink,
		_size("s_count", STAT_SIZE))
	_count_scale = _scaled[_scaled.size() - 1]
	_price_label = _rich_value(_cfg["r_price"], _cfg["t_price"], _cfg["fill_stat"],
		_size("s_price", STAT_SIZE))
	_price_scale = _scaled[_scaled.size() - 1]
	_refresh_label = _value(_cfg["r_refresh"], _cfg["t_refresh"], _cfg["fill_stat"], ink,
		_size("s_refresh", STAT_SIZE))
	_refresh_scale = _scaled[_scaled.size() - 1]

	for slot in _cfg.get("preview", []):
		_previews.append(_shot_slot(slot))
	if _cfg.has("r_next"):
		_hit(_cfg["r_next"], "Next car", _on_next_shot)

	_hit(_cfg["r_close"], "Close", _on_close)
	_hit(_cfg["r_enter"], "Enter this location", _on_enter)
	_hit(_cfg["r_travel"],
		"Move to this district" if str(_loc.get("hood", "")) != ""
			else "Not a district you can live in",
		_on_travel)

	_rescale_type()


## Drops the flat black behind the panel's chamfered corners without eating
## into the panel itself.
func _corner_key() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float cut_low = 0.002;
uniform float cut_high = 0.010;
uniform float reach = 0.18;

void fragment() {
	vec4 c = texture(TEXTURE, UV);

	// Only the four corner squares are keyed. Everywhere else keeps its
	// alpha, no matter how dark the artwork is there.
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


func _value(mask_rect: Rect2, type_rect: Rect2, fill: Color,
		color: Color, size: int) -> Label:
	_mask(mask_rect, fill)

	var label := Label.new()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	Design.apply_mono(label)
	_place(label, type_rect)

	_scaled.append({"node": label, "size": size, "rich": false, "font": Design.font_mono})
	return label


## The price band is two colours in the artwork -- white for the floor, amber
## for the ceiling -- so it needs markup rather than a single font colour.
##
## It is also the one value the artwork does not set in the squared face. Its
## dollar signs are narrow and tall -- 17 by 37 pixels, a 0.46 ratio -- which
## is the display face's $ (16 by 37) and not the mono one's (19 by 43). Set
## in mono the widest band runs 280px into a 180px plate and has to shrink
## away to nothing; in the display face it measures 180 and never shrinks.
func _rich_value(mask_rect: Rect2, type_rect: Rect2, fill: Color, size: int) -> RichTextLabel:
	_mask(mask_rect, fill)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Design.font_display:
		rtl.add_theme_font_override("normal_font", Design.font_display)
	_place(rtl, type_rect)

	_scaled.append({"node": rtl, "size": size, "rich": true, "font": Design.font_display})
	return rtl


## One of the artwork's empty inventory boxes, waiting for a car. The photo is
## fitted whole rather than filled, because the cutouts are shot at their own
## proportions -- anywhere from 1.41 to 2.34 wide -- and cropping to a common
## box would cut the nose off the long ones.
func _shot_slot(slot: Rect2) -> TextureRect:
	var shot := TextureRect.new()
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.visible = false
	_place(shot, slot)
	return shot


func _mask(r: Rect2, fill: Color) -> void:
	var mask := ColorRect.new()
	mask.color = fill
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(mask, r)


func _hit(r: Rect2, tooltip: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = ""
	b.tooltip_text = tooltip
	b.flat = true

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
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(handler)
	_place(b, r)
	return b


## Rects are written in full-image coordinates for legibility, then rebased
## onto the cropped region actually being drawn.
func _place(node: Control, r: Rect2) -> void:
	var crop: Rect2 = _cfg["crop"]
	node.anchor_left = (r.position.x - crop.position.x) / crop.size.x
	node.anchor_top = (r.position.y - crop.position.y) / crop.size.y
	node.anchor_right = (r.position.x + r.size.x - crop.position.x) / crop.size.x
	node.anchor_bottom = (r.position.y + r.size.y - crop.position.y) / crop.size.y
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0
	frame.add_child(node)


func _rescale_type() -> void:
	if frame == null or _cfg.is_empty() or frame.size.y <= 0.0:
		return
	var crop: Rect2 = _cfg["crop"]
	var factor: float = clampf(frame.size.y / crop.size.y, 0.2, 3.0)
	for entry in _scaled:
		var node: Control = entry["node"]
		var px: int = maxi(9, roundi(float(entry["size"]) * factor))
		if entry["rich"]:
			node.add_theme_font_size_override("normal_font_size", px)
		else:
			node.add_theme_font_size_override("font_size", px)


# ─────────────────────────────────────────────────────────────
# DATA
# ─────────────────────────────────────────────────────────────

## Fill the panel for one location and slide it in.
func open_for(loc: Dictionary) -> void:
	var kind: String = str(loc.get("kind", ""))
	if not KINDS.has(kind):
		return

	_loc = loc
	_build(kind)
	_refresh(loc)
	_slide_in()


func _refresh(loc: Dictionary) -> void:
	var hood_id: String = str(loc.get("hood", ""))
	var shown: String = str(loc.get("district", ""))
	var district := ""
	if shown != "":
		district = shown.to_upper()
	elif hood_id == "":
		district = "YOUR HOME"
	else:
		var hood: Dictionary = Catalog.get_neighborhood(hood_id)
		district = str(hood.get("name", hood_id)).to_upper()
	_set_value(_location_label, _location_scale, "t_location",
		_size("s_location", LOCATION_SIZE), district)

	var count := ""
	match str(_cfg.get("count", "cars")):
		"impounded":
			count = str(_impounded_cars())
		"events":
			# Practice is the only event the game has. Saying 1 is honest;
			# the artwork's 6 is not.
			count = "1"
		"owned":
			count = str(GameState.garage.size())
		_:
			count = str(_stock_for(loc, hood_id).size())
	_set_value(_count_label, _count_scale, "t_count", _size("s_count", STAT_SIZE), count)

	var band := {}
	match str(_cfg.get("middle", "band")):
		"release_fee":
			band = _flat(Design.fmt_cash(_impounded_cars() * _fee_per_car()))
		"entry_fee":
			# Practice runs cost nothing -- no wager, no risk, as the panel's
			# own subtitle says.
			band = _flat("FREE")
		"slots":
			band = _flat(str(GameState.parking_limit()))
		_:
			band = _price_band(_stock_for(loc, hood_id))
	_set_value(_price_label, _price_scale, "t_price", _size("s_price", STAT_SIZE),
		str(band["rich"]), str(band["plain"]))

	# Every panel advertises a stock refresh timer. Nothing rotates stock yet,
	# so the dash says so rather than counting down to nothing.
	var third := "--"
	if str(_cfg.get("third", "none")) == "best_time":
		third = _best_time()
	elif str(_cfg.get("third", "none")) == "active_ride":
		third = _active_ride()
	_set_value(_refresh_label, _refresh_scale, "t_refresh",
		_size("s_refresh", STAT_SIZE), third)

	_fill_previews(_stock_for(loc, hood_id))


## The artwork leaves four empty boxes under INVENTORY PREVIEW, and all four
## are filled. The cars this dealership stocks come first, cheapest first, the
## same order the list behind the panel uses. Westbay sells two, so the last
## two boxes carry on through the folder from where its stock left off --
## those are shots, not stock, and no photo repeats inside one panel.
func _fill_previews(stock: Array) -> void:
	_shot_ring.clear()
	_shot_page = 0

	var total := _shot_total()
	var base := _model_index(stock[0]) if not stock.is_empty() else 0
	for i in stock.size():
		var art := _car_shot(stock[i])
		if art != null:
			_shot_ring.append(art)
	for k in range(_shot_ring.size(), total):
		_shot_ring.append(load("%s%d.png" % [CAR_SHOT_DIR, ((base + k) % total) + 1]))

	_paint_previews()


## Drops the current window of the ring into the four boxes.
func _paint_previews() -> void:
	for i in _previews.size():
		var shot: TextureRect = _previews[i]
		var art: Texture2D = null
		if not _shot_ring.is_empty():
			art = _shot_ring[(_shot_page + i) % _shot_ring.size()]
		shot.texture = art
		shot.visible = art != null


## The chevron at the end of the strip. Each press walks the window on by one
## car and wraps at the end, so the strip streams instead of dead-ending.
func _on_next_shot() -> void:
	if _previews.is_empty() or _shot_ring.size() <= _previews.size():
		return
	# A second press mid-slide would skip a car and leave a box parked.
	if _shot_tween != null and _shot_tween.is_valid():
		return

	_shot_page = (_shot_page + 1) % _shot_ring.size()

	var travel: float = _previews[0].size.x * SHOT_TRAVEL
	_shot_tween = create_tween().set_parallel(true)
	for i in _previews.size():
		var shot: TextureRect = _previews[i]
		var delay: float = i * SHOT_STAGGER
		_shot_tween.tween_property(shot, "modulate:a", 0.0, SHOT_OUT).set_delay(delay)
		_shot_tween.tween_property(shot, "position:x", shot.position.x - travel, SHOT_OUT) \
			.set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_shot_tween.chain().tween_callback(_enter_shots.bind(travel))


## The second half of the turn: the next window is dealt in from the right.
func _enter_shots(travel: float) -> void:
	_paint_previews()
	for shot in _previews:
		shot.position.x += travel * 2.0

	var enter := create_tween().set_parallel(true)
	for i in _previews.size():
		var shot: TextureRect = _previews[i]
		var delay: float = i * SHOT_STAGGER
		enter.tween_property(shot, "modulate:a", 1.0, SHOT_IN).set_delay(delay)
		enter.tween_property(shot, "position:x", shot.position.x - travel, SHOT_IN) \
			.set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	enter.chain().tween_callback(_settle_shots)
	_shot_tween = enter


## Hands the boxes back to the layout. The slide drives `position`, which sets
## offsets of its own; clearing them puts each photo back on its anchors, so
## the next resize places it from the artwork's rect and not from wherever the
## animation left it.
func _settle_shots() -> void:
	for shot in _previews:
		shot.offset_left = 0
		shot.offset_top = 0
		shot.offset_right = 0
		shot.offset_bottom = 0
		shot.modulate.a = 1.0


## A resize outranks a page turn in flight -- the boxes move with the panel,
## and a half-finished slide would leave a photo off its slot.
func _on_frame_resized() -> void:
	_rescale_type()
	if _shot_tween != null and _shot_tween.is_valid():
		_shot_tween.kill()
		_paint_previews()
	_settle_shots()


## A car's photograph. A shot named for the model's own `spriteSet` wins, so
## renaming a file to bantam_gx.png pins it to that car for good. Failing
## that the catalog's order picks one of the numbered shots: stable for a
## given car, and consecutive, so the two or three cars in any one dealership
## never land on the same photo.
func _car_shot(model: Dictionary) -> Texture2D:
	var named := "%s%s.png" % [CAR_SHOT_DIR, str(model.get("spriteSet", ""))]
	if ResourceLoader.exists(named):
		return load(named)

	var total := _shot_total()
	if total == 0:
		return null
	return load("%s%d.png" % [CAR_SHOT_DIR, (_model_index(model) % total) + 1])


## Where a model sits in the catalog, which is what picks its numbered shot.
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


## The size the artwork sets a value at, where it was measured, or the shared
## default on the panels that have not been measured value by value.
func _size(key: String, fallback: int) -> int:
	return int(_cfg.get(key, fallback))


## Writes one redrawn value and steps its type down if the string would spill
## past the plate the artwork leaves for it -- the mono face runs about a fifth
## wider per glyph than the type painted into the art, so a sixteen-character
## district or a four-tier price band needs the room. `measure` is the string
## as it prints, without the colour markup the price band carries.
func _set_value(node: Control, entry: Dictionary, box_key: String, base: int,
		text: String, measure := "") -> void:
	node.set("text", text)

	var box: Rect2 = _cfg[box_key]
	var shown := measure if measure != "" else text
	var size := base
	var face: FontFile = entry.get("font", null)
	if face != null:
		while size > VALUE_MIN_SIZE and face.get_string_size(
				shown, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > box.size.x:
			size -= 1
	entry["size"] = size
	_rescale_type()


## A single-colour value, in the artwork's own white, paired with the plain
## string to measure it by.
func _flat(text: String) -> Dictionary:
	return {
		"rich": "[color=#%s]%s[/color]" % [INK_WHITE.to_html(false), text],
		"plain": text,
	}


## Quickest pass the player has run, across every car they own.
func _best_time() -> String:
	var best: float = 0.0
	for car in GameState.garage:
		var et = car.get("best_et", null)
		if et == null:
			continue
		var v := float(et)
		if v <= 0.0:
			continue
		if best == 0.0 or v < best:
			best = v
	return "--" if best == 0.0 else "%.2f" % best


## The car the player is currently running, by the name they gave it.
func _active_ride() -> String:
	var car: Dictionary = GameState.get_active_car()
	if car.is_empty():
		return "NONE"
	return str(car.get("nickname", "")).to_upper()


## Cars the player currently has seized. The panel reports what they are
## facing, not what the artwork happens to show.
func _impounded_cars() -> int:
	var held := 0
	for car in GameState.garage:
		if car.get("impounded", false):
			held += 1
	return held


func _fee_per_car() -> int:
	return int(Catalog.impound_config().get("feePerCar", 0))


func _stock_for(loc: Dictionary, hood_id: String) -> Array:
	if loc.get("kind", "") == "PARTS_SHOP":
		return Catalog.parts_in(hood_id)
	return Catalog.cars_in(hood_id)


## Cheapest to dearest, as the artwork's dollar signs.
func _price_band(stock: Array) -> Dictionary:
	if stock.is_empty():
		return _flat("--")

	var low: int = stock[0].get("price", 0)
	var high: int = low
	for item in stock:
		var p: int = item.get("price", 0)
		low = mini(low, p)
		high = maxi(high, p)

	return {
		"rich": "[color=#%s]%s[/color] - [color=#%s]%s[/color]" % [
			INK_WHITE.to_html(false), _dollars(low),
			INK_AMBER.to_html(false), _dollars(high),
		],
		"plain": "%s - %s" % [_dollars(low), _dollars(high)],
	}


func _dollars(price: int) -> String:
	if price >= 100000:
		return "$$$$"
	if price >= 30000:
		return "$$$"
	if price >= 5000:
		return "$$"
	return "$"


# ─────────────────────────────────────────────────────────────
# ANIMATION
# ─────────────────────────────────────────────────────────────

func _slide_in() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	show()
	modulate.a = 0.0
	position.x = size.x * SLIDE_FROM

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:x", 0.0, SLIDE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", 1.0, SLIDE_TIME * 0.7)


func close() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:x", size.x * SLIDE_FROM, SLIDE_TIME * 0.8) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tween.tween_property(self, "modulate:a", 0.0, SLIDE_TIME * 0.6)
	_tween.chain().tween_callback(hide)
	# Every close announces itself — the map hid its detail card when this
	# panel opened, and a close() that skipped the signal left it hidden for
	# the rest of the session.
	closed.emit()


func _on_close() -> void:
	close()


func _on_enter() -> void:
	entered.emit(_loc)


func _on_travel() -> void:
	travel_requested.emit(_loc)
