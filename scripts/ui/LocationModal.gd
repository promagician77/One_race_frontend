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
const KINDS := {
	"DEALERSHIP": {
		"art": "res://assets/ui/dealership.png",
		"crop": Rect2(66, 52, 893, 1391),
		"r_location": Rect2(204, 462, 302, 66), "t_location": Rect2(210, 469, 290, 52),
		"r_count":    Rect2(238, 684, 64, 52),  "t_count":    Rect2(245, 690, 60, 40),
		"r_price":    Rect2(506, 681, 196, 56), "t_price":    Rect2(512, 688, 184, 42),
		"r_refresh":  Rect2(752, 681, 178, 56), "t_refresh":  Rect2(760, 688, 170, 42),
		"r_close":  Rect2(816, 104, 88, 80),
		"r_enter":  Rect2(140, 1102, 744, 100),
		"r_travel": Rect2(140, 1244, 744, 92),
		"ink": Color("#31CDF7"),
		"fill_location": Color("#05080C"),
		"fill_stat": Color("#05090B"),
		"middle": "band",
	},
	"PARTS_SHOP": {
		"art": "res://assets/ui/partshop.png",
		"crop": Rect2(62, 50, 903, 1445),
		"r_location": Rect2(206, 464, 320, 74), "t_location": Rect2(213, 472, 306, 58),
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
		"r_location": Rect2(222, 458, 328, 74), "t_location": Rect2(230, 466, 314, 58),
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

## How far off-screen it starts, as a fraction of its own width.
const SLIDE_FROM := 1.06
const SLIDE_TIME := 0.28

var frame: Control

var _cfg: Dictionary = {}
var _fitter: AspectRatioContainer = null
var _location_label: Label = null
var _count_label: Label = null
var _price_label: RichTextLabel = null
var _refresh_label: Label = null
var _scaled: Array = []
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
		_cfg["fill_location"], ink, 52)
	_count_label = _value(_cfg["r_count"], _cfg["t_count"], _cfg["fill_stat"], ink, 40)
	_price_label = _rich_value(_cfg["r_price"], _cfg["t_price"], _cfg["fill_stat"], 40)
	_refresh_label = _value(_cfg["r_refresh"], _cfg["t_refresh"], _cfg["fill_stat"], ink, 40)

	_hit(_cfg["r_close"], "Close", _on_close)
	_hit(_cfg["r_enter"], "Enter this location", _on_enter)
	_hit(_cfg["r_travel"], "Fast travel is not available yet", _on_travel)

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
	Design.apply_display(label)
	_place(label, type_rect)

	_scaled.append({"node": label, "size": size, "rich": false})
	return label


## The price band is two colours in the artwork -- white for the floor, amber
## for the ceiling -- so it needs markup rather than a single font colour.
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

	_scaled.append({"node": rtl, "size": size, "rich": true})
	return rtl


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
	if frame == null or _cfg.is_empty():
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
	if shown != "":
		_location_label.text = shown.to_upper()
	elif hood_id == "":
		_location_label.text = "YOUR HOME"
	else:
		var hood: Dictionary = Catalog.get_neighborhood(hood_id)
		_location_label.text = str(hood.get("name", hood_id)).to_upper()

	match str(_cfg.get("count", "cars")):
		"impounded":
			_count_label.text = str(_impounded_cars())
		"events":
			# Practice is the only event the game has. Saying 1 is honest;
			# the artwork's 6 is not.
			_count_label.text = "1"
		"owned":
			_count_label.text = str(GameState.garage.size())
		_:
			_count_label.text = str(_stock_for(loc, hood_id).size())

	match str(_cfg.get("middle", "band")):
		"release_fee":
			_price_label.text = _plain(Design.fmt_cash(_impounded_cars() * _fee_per_car()))
		"entry_fee":
			# Practice runs cost nothing -- no wager, no risk, as the panel's
			# own subtitle says.
			_price_label.text = _plain("FREE")
		"slots":
			_price_label.text = _plain(str(GameState.parking_limit()))
		_:
			_price_label.text = _price_band(_stock_for(loc, hood_id))

	if str(_cfg.get("third", "none")) == "best_time":
		_refresh_label.text = _best_time()
	elif str(_cfg.get("third", "none")) == "active_ride":
		_refresh_label.text = _active_ride()
	else:
		# Every panel advertises a stock refresh timer. Nothing rotates stock
		# yet, so this says so rather than counting down to nothing.
		_refresh_label.text = "--"


func _plain(text: String) -> String:
	return "[color=#%s]%s[/color]" % [INK_WHITE.to_html(false), text]


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
func _price_band(stock: Array) -> String:
	if stock.is_empty():
		return "[color=#%s]--[/color]" % INK_WHITE.to_html(false)

	var low: int = stock[0].get("price", 0)
	var high: int = low
	for item in stock:
		var p: int = item.get("price", 0)
		low = mini(low, p)
		high = maxi(high, p)

	return "[color=#%s]%s[/color] - [color=#%s]%s[/color]" % [
		INK_WHITE.to_html(false), _dollars(low),
		INK_AMBER.to_html(false), _dollars(high),
	]


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


func _on_close() -> void:
	close()
	closed.emit()


func _on_enter() -> void:
	entered.emit(_loc)


func _on_travel() -> void:
	travel_requested.emit(_loc)
