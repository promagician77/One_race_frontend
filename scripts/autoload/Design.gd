extends Node
## Design tokens. Every color, size, and spacing value in the game comes from here.
## Change a value once, it changes everywhere. No hardcoded colors in scene files.

# ─────────────────────────────────────────────────────────────
# PALETTE
# Dark automotive metal. Cool gunmetal base, warm amber for
# anything the player acts on, and the NHRA tree colors reserved
# strictly for the tree so they never lose meaning.
# ─────────────────────────────────────────────────────────────

# Surfaces — darkest to lightest
const BG_VOID       := Color("#070809")  # behind everything
const BG_DEEP       := Color("#0E1114")  # screen background
const BG_PANEL      := Color("#161A1F")  # cards, panels
const BG_RAISED     := Color("#1E242B")  # inputs, list rows
const BG_HOVER      := Color("#272E37")  # hover state

# Borders — brushed aluminum edges
const EDGE_DARK     := Color("#0A0C0E")
const EDGE_LINE     := Color("#2E363F")
const EDGE_BRIGHT   := Color("#4A555F")

# Text
const TEXT_PRIME    := Color("#E8ECF0")
const TEXT_BODY     := Color("#A8B2BC")
const TEXT_MUTED    := Color("#68727C")
const TEXT_DIM      := Color("#454E57")

# Action — amber. Used only for things the player can act on.
const AMBER         := Color("#F0A020")
const AMBER_HOT     := Color("#FFB93D")
const AMBER_DIM     := Color("#8A5C10")

# Staging tree — reserved. Never used for general UI.
const TREE_BULB_OFF := Color("#1A1410")
const TREE_PRESTAGE := Color("#FFD34D")
const TREE_AMBER    := Color("#FF9500")
const TREE_GREEN    := Color("#22DD55")
const TREE_RED      := Color("#FF2D2D")

# Semantic
const GOOD          := Color("#22DD55")
const WARN          := Color("#FF9500")
const BAD           := Color("#FF3B30")
const INFO          := Color("#3D9BE9")
const CASH          := Color("#4ADE80")

# System chat messages render red, matching the original game
const CHAT_SYSTEM   := Color("#FF4444")
const CHAT_PLAYER   := Color("#C8D2DC")
const CHAT_SELF     := Color("#F0A020")

# Risk levels — tuning feedback
const RISK_SAFE     := Color("#22DD55")
const RISK_MODERATE := Color("#C9D22B")
const RISK_HIGH     := Color("#FF9500")
const RISK_EXTREME  := Color("#FF3B30")

# Car class accents
const CLASS_COLORS := {
	"IMPORT": Color("#3D9BE9"),
	"MUSCLE": Color("#E9563D"),
	"SPORT":  Color("#C9A227"),
	"TRUCK":  Color("#7A8B5C"),
	"EXOTIC": Color("#B8A6D9"),
}

# ─────────────────────────────────────────────────────────────
# TYPE SCALE
# Condensed grotesque for numbers and labels — reads like an
# instrument cluster. Monospace for anything timed, so digits
# don't shift width as they tick.
# ─────────────────────────────────────────────────────────────

const FONT_DISPLAY_PATH := "res://assets/fonts/display.ttf"   # condensed, headers + big numbers
const FONT_BODY_PATH    := "res://assets/fonts/body.ttf"      # UI text
const FONT_MONO_PATH    := "res://assets/fonts/mono.ttf"      # ET/RT/TS/RPM — tabular figures

var font_display: FontFile
var font_body: FontFile
var font_mono: FontFile


func _ready() -> void:
	font_display = _load_font(FONT_DISPLAY_PATH)
	font_body = _load_font(FONT_BODY_PATH)
	font_mono = _load_font(FONT_MONO_PATH)


## Missing fonts fall back to Godot's default rather than crashing — a
## missing asset should degrade the look, not stop the game booting.
func _load_font(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		push_warning("Font missing, falling back to default: %s" % path)
		return null
	return load(path)


## Apply the monospace face to a label. Use for anything timed or compared,
## so digits keep a constant width and readouts do not jitter.
func apply_mono(label: Label) -> void:
	if font_mono:
		label.add_theme_font_override("font", font_mono)


func apply_display(label: Label) -> void:
	if font_display:
		label.add_theme_font_override("font", font_display)

const SIZE_HERO   := 52   # ET on results screen
const SIZE_TITLE  := 30
const SIZE_HEAD   := 22
const SIZE_SUB    := 17
const SIZE_BODY   := 14
const SIZE_SMALL  := 12
const SIZE_MICRO  := 10   # labels above data

const TRACK_LABEL := 1.5  # letter-spacing on uppercase micro labels

# ─────────────────────────────────────────────────────────────
# SPACING — 4px base grid
# ─────────────────────────────────────────────────────────────

const SP_1 := 4
const SP_2 := 8
const SP_3 := 12
const SP_4 := 16
const SP_5 := 24
const SP_6 := 32
const SP_7 := 48
const SP_8 := 64

const RADIUS_SM := 2
const RADIUS_MD := 4
const RADIUS_LG := 6

const BORDER_W := 1

# ─────────────────────────────────────────────────────────────
# MOTION
# Fast and mechanical. Nothing floats or bounces — this is a
# machine, not a phone app.
# ─────────────────────────────────────────────────────────────

const T_INSTANT := 0.08
const T_FAST    := 0.15
const T_NORMAL  := 0.25
const T_SLOW     := 0.40

const EASE_OUT := Tween.EASE_OUT
const TRANS_CUBIC := Tween.TRANS_CUBIC

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

func class_color(car_class: String) -> Color:
	return CLASS_COLORS.get(car_class, TEXT_BODY)


func risk_color(risk_label: String) -> Color:
	match risk_label:
		"SAFE":     return RISK_SAFE
		"MODERATE": return RISK_MODERATE
		"HIGH":     return RISK_HIGH
		"EXTREME":  return RISK_EXTREME
	return TEXT_MUTED


## Sync score 0-100 -> color. Red when starved or over-flowed, green in the band.
func sync_color(score: float) -> Color:
	if score >= 85.0:
		return GOOD
	elif score >= 65.0:
		return WARN
	return BAD


## Money with thousands separators: 1234567 -> "1,234,567"
func fmt_cash(amount: int) -> String:
	var s := str(abs(amount))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if amount < 0 else "$") + out


## Elapsed time to 3 decimals: 11.4372 -> "11.437"
func fmt_et(seconds: float) -> String:
	return "%.3f" % seconds


## Reaction time, 3 decimals, sign-aware. Negative = red light.
func fmt_rt(seconds: float) -> String:
	if seconds < 0.0:
		return "-%.3f" % abs(seconds)
	return "%.3f" % seconds


## Trap speed: 142.7 -> "142.7"
func fmt_ts(mph: float) -> String:
	return "%.1f" % mph
