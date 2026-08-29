class_name UIKit
extends RefCounted
## Builders for the recurring UI pieces. Every screen composes from these
## so the theme stays consistent and a visual change lands in one file.
##
## Usage:  var panel := UIKit.panel()
##         panel.add_child(UIKit.stat_row("PEAK HP", "412"))

# ─────────────────────────────────────────────────────────────
# SURFACES
# ─────────────────────────────────────────────────────────────

## Standard dark panel with a hairline border.
static func panel(raised: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Design.BG_RAISED if raised else Design.BG_PANEL
	sb.border_color = Design.EDGE_LINE
	sb.set_border_width_all(Design.BORDER_W)
	sb.set_corner_radius_all(Design.RADIUS_MD)
	sb.content_margin_left = Design.SP_4
	sb.content_margin_right = Design.SP_4
	sb.content_margin_top = Design.SP_3
	sb.content_margin_bottom = Design.SP_3
	p.add_theme_stylebox_override("panel", sb)
	return p


## Panel with a colored left edge — used for callouts and warnings.
static func accent_panel(accent: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Design.BG_PANEL
	sb.border_color = accent
	sb.border_width_left = 2
	sb.set_corner_radius_all(0)   # no rounding with a single-sided border
	sb.content_margin_left = Design.SP_3
	sb.content_margin_right = Design.SP_3
	sb.content_margin_top = Design.SP_2
	sb.content_margin_bottom = Design.SP_2
	p.add_theme_stylebox_override("panel", sb)
	return p


static func divider() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxLine.new()
	sb.color = Design.EDGE_LINE
	sb.thickness = 1
	s.add_theme_stylebox_override("separator", sb)
	return s


static func spacer(size: int = 16) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, size)
	return c

# ─────────────────────────────────────────────────────────────
# TEXT
# ─────────────────────────────────────────────────────────────

## Small uppercase label that sits above a value. Letter-spaced.
static func micro_label(text: String, color: Color = Color("#68727C")) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", Design.SIZE_MICRO)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("line_spacing", 0)
	return l


static func heading(text: String, size: int = 22) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Design.TEXT_PRIME)
	return l


static func body(text: String, color: Color = Color("#A8B2BC")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Design.SIZE_BODY)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Monospace numeric readout. Use for anything that ticks or is compared.
static func numeric(text: String, size: int = 17,
		color: Color = Color("#E8ECF0")) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	Design.apply_mono(l)
	return l

# ─────────────────────────────────────────────────────────────
# BUTTONS
# ─────────────────────────────────────────────────────────────

enum BtnStyle { PRIMARY, SECONDARY, GHOST, DANGER }


static func button(text: String, style: BtnStyle = BtnStyle.SECONDARY) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", Design.SIZE_BODY)
	b.custom_minimum_size = Vector2(0, 34)

	var fg: Color
	var bg: Color
	var edge: Color

	match style:
		BtnStyle.PRIMARY:
			fg = Design.BG_VOID
			bg = Design.AMBER
			edge = Design.AMBER
		BtnStyle.SECONDARY:
			fg = Design.TEXT_PRIME
			bg = Design.BG_RAISED
			edge = Design.EDGE_BRIGHT
		BtnStyle.GHOST:
			fg = Design.TEXT_BODY
			bg = Color(0, 0, 0, 0)
			edge = Color(0, 0, 0, 0)
		BtnStyle.DANGER:
			fg = Design.BAD
			bg = Design.BG_RAISED
			edge = Design.BAD

	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Design.TEXT_DIM)

	b.add_theme_stylebox_override("normal", _btn_box(bg, edge))
	b.add_theme_stylebox_override("hover", _btn_box(_lift(bg), edge))
	b.add_theme_stylebox_override("pressed", _btn_box(_sink(bg), edge))
	b.add_theme_stylebox_override("disabled", _btn_box(Design.BG_PANEL, Design.EDGE_LINE))
	b.add_theme_stylebox_override("focus", _focus_box())

	return b


static func _btn_box(bg: Color, edge: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(Design.BORDER_W)
	sb.set_corner_radius_all(Design.RADIUS_SM)
	sb.content_margin_left = Design.SP_4
	sb.content_margin_right = Design.SP_4
	sb.content_margin_top = Design.SP_2
	sb.content_margin_bottom = Design.SP_2
	return sb


static func _focus_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Design.AMBER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(Design.RADIUS_SM)
	return sb


static func _lift(c: Color) -> Color:
	return c.lightened(0.10)


static func _sink(c: Color) -> Color:
	return c.darkened(0.10)

# ─────────────────────────────────────────────────────────────
# COMPOSITES
# ─────────────────────────────────────────────────────────────

## Label on the left, value right-aligned. The workhorse of every spec panel.
static func stat_row(label: String, value: String,
		value_color: Color = Color("#E8ECF0")) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", Design.SIZE_SMALL)
	l.add_theme_color_override("font_color", Design.TEXT_MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", Design.SIZE_SMALL)
	v.add_theme_color_override("font_color", value_color)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	row.add_child(l)
	row.add_child(v)
	return row


## Micro label stacked over a large value. Used in headers and result screens.
static func stat_block(label: String, value: String,
		value_color: Color = Color("#E8ECF0"),
		value_size: int = 30) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(micro_label(label))

	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", value_size)
	v.add_theme_color_override("font_color", value_color)
	box.add_child(v)
	return box


## Horizontal bar for scores like flow sync. Value 0..1.
## Uses a plain Control so the fill can be sized by ratio — a PanelContainer
## would force the child to fill and the bar would always read 100%.
static func meter(value: float, fill: Color, height: int = 4) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, height)
	wrap.clip_contents = true

	var track := ColorRect.new()
	track.color = Color("#070809")
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(track)

	var bar := ColorRect.new()
	bar.color = fill
	bar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	bar.anchor_right = clampf(value, 0.0, 1.0)
	bar.offset_right = 0.0
	wrap.add_child(bar)

	return wrap


## Small colored pill — car class, tier, lock state.
static func badge(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.15)
	sb.border_color = color
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(Design.RADIUS_SM)
	sb.content_margin_left = Design.SP_2
	sb.content_margin_right = Design.SP_2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)

	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", Design.SIZE_MICRO)
	l.add_theme_color_override("font_color", color)
	p.add_child(l)
	return p


## Empty state. An invitation, not an apology.
static func empty_state(headline: String, body_text: String,
		action_text: String = "") -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", Design.SP_3)

	var h := heading(headline, Design.SIZE_SUB)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(h)

	var b := body(body_text, Design.TEXT_MUTED)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(b)

	if action_text != "":
		var btn := button(action_text, BtnStyle.PRIMARY)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.name = "ActionButton"
		box.add_child(btn)

	return box
