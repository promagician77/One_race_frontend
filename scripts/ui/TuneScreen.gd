extends Control
## The tuning screen — the seven dials the server enforces, per-gear ratios
## and shift points, and a dyno graph that redraws on every change.
##
## Built from Design/UIKit while the tuning artwork is still being made; when
## it lands this becomes an art-overlay screen like the others, and only the
## layout code changes — every value here already comes from the server.
##
## Flow: sliders edit a local mirror for instant feedback, a short debounce
## collects the burst, then the whole tune goes to the server through
## GameState.tune_car. The stats in its reply — peak power, sync, risk, the
## dyno curve, and the headless-pass figures — are the truth the readouts
## and the graph show. Nothing on this screen computes physics.

const DEBOUNCE_S := 0.35
const SIDEBAR_W := 380.0

## Server bounds (TUNE_BOUNDS in garage.js). The server clamps anyway; the
## sliders simply refuse to ask for the impossible.
const DIALS := [
	{ "key": "afr", "label": "AIR / FUEL RATIO", "lo": 10.0, "hi": 18.0, "step": 0.1, "fmt": "ratio" },
	{ "key": "compression", "label": "COMPRESSION", "lo": 7.0, "hi": 15.0, "step": 0.1, "fmt": "ratio" },
	{ "key": "finalDrive", "label": "FINAL DRIVE", "lo": 2.5, "hi": 6.5, "step": 0.01, "fmt": "gear" },
	{ "key": "launchRpm", "label": "LAUNCH RPM", "lo": 800.0, "hi": 12000.0, "step": 50.0, "fmt": "rpm" },
	{ "key": "tirePressure", "label": "TIRE PRESSURE", "lo": 12.0, "hi": 40.0, "step": 0.5, "fmt": "psi" },
	{ "key": "clutchRelease", "label": "CLUTCH RELEASE", "lo": 0.0, "hi": 1.0, "step": 0.05, "fmt": "pct" },
	{ "key": "nitrousPoint", "label": "NITROUS AT", "lo": 0.0, "hi": 1320.0, "step": 10.0, "fmt": "ft" },
]

var _car_id := ""
var _car: Dictionary = {}
var _model: Dictionary = {}
var _stats: Dictionary = {}

## key -> {slider, label, fmt}; gears/shifts are separate parallel arrays.
var _dials: Dictionary = {}
var _gear_sliders: Array = []
var _gear_labels: Array = []
var _shift_sliders: Array = []
var _shift_labels: Array = []

var _graph: DynoGraph
var _title: Label
var _risk_strip: PanelContainer
var _risk_text: Label
var _health_note: Label
var _blocks: Dictionary = {}          # readout key -> value Label
var _sync_holder: Control
var _debounce: Timer

var _busy := false
var _pending := false
var _dirty := false


# ─────────────────────────────────────────────────────────────
# DYNO GRAPH
# The one piece of bespoke drawing: HP and torque against RPM,
# with the previous curve left as a ghost so a change reads as
# "from there to here" rather than a number blinking.
# ─────────────────────────────────────────────────────────────

class DynoGraph extends Control:
	var points: Array = []
	var ghost: Array = []
	var redline := 8000.0

	const M_LEFT := 52.0
	const M_BOTTOM := 30.0
	const M_TOP := 14.0
	const M_RIGHT := 16.0

	func set_curve(new_points: Array) -> void:
		if points.size() > 0:
			ghost = points
		points = new_points
		queue_redraw()

	func _plot_rect() -> Rect2:
		return Rect2(M_LEFT, M_TOP,
			maxf(size.x - M_LEFT - M_RIGHT, 1.0),
			maxf(size.y - M_TOP - M_BOTTOM, 1.0))

	func _peak_of(curve: Array) -> float:
		var peak := 0.0
		for p in curve:
			var row: Dictionary = p
			peak = maxf(peak, maxf(float(row.get("hp", 0)), float(row.get("torque", 0))))
		return peak

	func _to_screen(curve: Array, field: String, rect: Rect2, top: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in curve:
			var row: Dictionary = p
			var rpm := float(row.get("rpm", 0))
			var x := rect.position.x + (rpm - 1000.0) / maxf(redline - 1000.0, 1.0) * rect.size.x
			var y := rect.end.y - float(row.get(field, 0)) / top * rect.size.y
			out.append(Vector2(x, y))
		return out

	func _draw() -> void:
		var rect := _plot_rect()
		var font := get_theme_default_font()

		draw_rect(rect, Design.BG_VOID)

		# Scale from whichever curve reaches higher, so the ghost never leaves
		# the frame when the new tune is weaker.
		var top := maxf(_peak_of(points), _peak_of(ghost))
		top = maxf(ceilf(top / 100.0) * 100.0, 100.0)

		# Horizontal grid with values
		for i in 5:
			var frac := float(i) / 4.0
			var y := rect.end.y - frac * rect.size.y
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y),
				Design.EDGE_LINE if i > 0 else Design.EDGE_BRIGHT, 1.0)
			draw_string(font, Vector2(6, y + 4), str(int(top * frac)),
				HORIZONTAL_ALIGNMENT_LEFT, M_LEFT - 10, Design.SIZE_MICRO, Design.TEXT_MUTED)

		# Vertical grid every 1000 RPM, labelled every other line
		var rpm := 1000.0
		while rpm <= redline:
			var x: float = rect.position.x + (rpm - 1000.0) / maxf(redline - 1000.0, 1.0) * rect.size.x
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Design.EDGE_LINE, 1.0)
			if int(rpm) % 2000 == 0:
				draw_string(font, Vector2(x - 14, rect.end.y + 16), str(int(rpm / 1000.0)) + "K",
					HORIZONTAL_ALIGNMENT_LEFT, 40, Design.SIZE_MICRO, Design.TEXT_MUTED)
			rpm += 1000.0

		if ghost.size() > 1:
			draw_polyline(_to_screen(ghost, "hp", rect, top), Design.TEXT_DIM, 1.0, true)
		if points.size() > 1:
			draw_polyline(_to_screen(points, "torque", rect, top), Design.INFO, 2.0, true)
			draw_polyline(_to_screen(points, "hp", rect, top), Design.AMBER, 2.0, true)

		# Legend
		draw_rect(Rect2(rect.position + Vector2(10, 8), Vector2(10, 3)), Design.AMBER)
		draw_string(font, rect.position + Vector2(26, 14), "HP",
			HORIZONTAL_ALIGNMENT_LEFT, 60, Design.SIZE_MICRO, Design.TEXT_BODY)
		draw_rect(Rect2(rect.position + Vector2(58, 8), Vector2(10, 3)), Design.INFO)
		draw_string(font, rect.position + Vector2(74, 14), "TORQUE",
			HORIZONTAL_ALIGNMENT_LEFT, 80, Design.SIZE_MICRO, Design.TEXT_BODY)


# ─────────────────────────────────────────────────────────────
# BUILD
# ─────────────────────────────────────────────────────────────

func _ready() -> void:
	_car_id = str(Router.context.get("car_id", GameState.active_car_id))
	_car = GameState.get_car(_car_id)
	if _car.is_empty() and GameState.garage.size() > 0:
		var first: Dictionary = GameState.garage[0]
		_car_id = str(first.get("id", ""))
		_car = first
	_model = Catalog.get_car_model(str(_car.get("model_id", "")))

	_debounce = Timer.new()
	_debounce.wait_time = DEBOUNCE_S
	_debounce.one_shot = true
	_debounce.timeout.connect(_apply)
	add_child(_debounce)

	_build()
	_load_tune_into_controls()
	_fetch_initial()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Design.BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Design.SP_5)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", Design.SP_4)
	margin.add_child(root)

	# ── header ───────────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Design.SP_4)
	root.add_child(header)

	_title = UIKit.heading("TUNING — %s" % str(_car.get("nickname", "")).to_upper(), Design.SIZE_TITLE)
	Design.apply_display(_title)
	header.add_child(_title)

	var car_class := str(_model.get("class", ""))
	header.add_child(UIKit.badge(car_class, Design.class_color(car_class)))

	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(pad)

	_health_note = UIKit.numeric("", Design.SIZE_SUB, Design.WARN)
	header.add_child(_health_note)

	var exit := UIKit.button("BACK TO GARAGE", UIKit.BtnStyle.GHOST)
	exit.pressed.connect(_on_exit)
	header.add_child(exit)

	# ── body: graph + readouts on the left, dials on the right ─
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", Design.SP_4)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", Design.SP_3)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left)

	var graph_panel := UIKit.panel()
	graph_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(graph_panel)
	_graph = DynoGraph.new()
	_graph.redline = float(_model.get("redline", 8000))
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_panel.add_child(_graph)

	left.add_child(_build_readouts())

	_risk_strip = UIKit.accent_panel(Design.RISK_SAFE)
	_risk_text = UIKit.body("", Design.TEXT_BODY)
	_risk_strip.add_child(_risk_text)
	left.add_child(_risk_strip)

	body.add_child(_build_sidebar())


func _build_readouts() -> PanelContainer:
	var panel := UIKit.panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Design.SP_6)
	panel.add_child(row)

	for spec in [
		["peak", "PEAK HP"], ["torque", "TORQUE"], ["et", "QUARTER ET"],
		["trap", "TRAP MPH"], ["top", "TOP SPEED"], ["accel", "0-100 KM/H"],
	]:
		var pair: Array = spec
		var block := UIKit.stat_block(str(pair[1]), "—", Design.TEXT_PRIME, 26)
		row.add_child(block)
		# stat_block's value label is its second child.
		_blocks[str(pair[0])] = block.get_child(1)

	var pad := Control.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pad)

	# Flow sync gets a meter, rebuilt on refresh since a meter's fill is fixed
	# at construction.
	var sync_box := VBoxContainer.new()
	sync_box.add_theme_constant_override("separation", 2)
	sync_box.custom_minimum_size = Vector2(150, 0)
	sync_box.add_child(UIKit.micro_label("FLOW SYNC"))
	var sync_val := UIKit.numeric("—", 26, Design.TEXT_PRIME)
	sync_box.add_child(sync_val)
	_blocks["sync"] = sync_val
	_sync_holder = VBoxContainer.new()
	sync_box.add_child(_sync_holder)
	row.add_child(sync_box)

	return panel


func _build_sidebar() -> PanelContainer:
	var panel := UIKit.panel(true)
	panel.custom_minimum_size = Vector2(SIDEBAR_W, 0)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Design.SP_3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)

	col.add_child(UIKit.heading("ENGINE", Design.SIZE_HEAD))
	for d in DIALS.slice(0, 2):
		col.add_child(_dial_row(d))

	col.add_child(UIKit.divider())
	col.add_child(UIKit.heading("DRIVETRAIN", Design.SIZE_HEAD))
	for d in DIALS.slice(2, 6):
		col.add_child(_dial_row(d))

	col.add_child(UIKit.divider())
	col.add_child(UIKit.heading("GEARING", Design.SIZE_HEAD))
	var gears := int(_model.get("gearCount", 5))
	for i in gears:
		col.add_child(_gear_row(i))
	for i in gears - 1:
		col.add_child(_shift_row(i))

	col.add_child(UIKit.divider())
	col.add_child(UIKit.heading("NITROUS", Design.SIZE_HEAD))
	var nitrous_dial: Control = _dial_row(DIALS[6])
	col.add_child(nitrous_dial)
	var fitted: Dictionary = _car.get("installed", {})
	if str(fitted.get("nitrous", "")) == "":
		var slider_meta: Dictionary = _dials["nitrousPoint"]
		var s: HSlider = slider_meta.slider
		s.editable = false
		var note := UIKit.body("No nitrous kit fitted.", Design.TEXT_DIM)
		note.add_theme_font_size_override("font_size", Design.SIZE_SMALL)
		col.add_child(note)

	return panel


func _dial_row(spec: Dictionary) -> VBoxContainer:
	var key := str(spec.key)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var head := HBoxContainer.new()
	var name_l := UIKit.micro_label(str(spec.label))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_l := UIKit.numeric("", Design.SIZE_SUB, Design.AMBER)
	head.add_child(name_l)
	head.add_child(val_l)
	box.add_child(head)

	var s := HSlider.new()
	s.min_value = float(spec.lo)
	s.max_value = float(spec.hi)
	# Launch RPM past the limiter is dead slider travel with a lying readout.
	if key == "launchRpm":
		s.max_value = minf(s.max_value, float(_model.get("redline", 8000)))
	s.step = float(spec.step)
	s.custom_minimum_size = Vector2(0, 20)
	s.value_changed.connect(_on_dial_changed.bind(key))
	box.add_child(s)

	_dials[key] = { "slider": s, "label": val_l, "fmt": str(spec.fmt) }
	return box


func _gear_row(index: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var name_l := UIKit.micro_label("GEAR %d RATIO" % (index + 1))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_l := UIKit.numeric("", Design.SIZE_SUB, Design.AMBER)
	head.add_child(name_l)
	head.add_child(val_l)
	box.add_child(head)

	var s := HSlider.new()
	s.min_value = 0.4
	s.max_value = 6.0
	s.step = 0.01
	s.custom_minimum_size = Vector2(0, 20)
	s.value_changed.connect(_on_gear_changed.bind(index))
	box.add_child(s)

	_gear_sliders.append(s)
	_gear_labels.append(val_l)
	return box


func _shift_row(index: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var name_l := UIKit.micro_label("SHIFT %d → %d" % [index + 1, index + 2])
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val_l := UIKit.numeric("", Design.SIZE_SUB, Design.AMBER)
	head.add_child(name_l)
	head.add_child(val_l)
	box.add_child(head)

	var s := HSlider.new()
	s.min_value = 1000.0
	s.max_value = float(_model.get("redline", 8000))
	s.step = 50.0
	s.custom_minimum_size = Vector2(0, 20)
	s.value_changed.connect(_on_shift_changed.bind(index))
	box.add_child(s)

	_shift_sliders.append(s)
	_shift_labels.append(val_l)
	return box


# ─────────────────────────────────────────────────────────────
# STATE IN
# ─────────────────────────────────────────────────────────────

## Seed every control from the car's saved tune. set_value_no_signal so
## seeding does not fire a wave of "changes" at the server.
func _load_tune_into_controls() -> void:
	var tune: Dictionary = _car.get("tune", {})
	var seed := {
		"afr": float(tune.get("afr", 14.7)),
		"compression": float(tune.get("compression", 9.5)),
		"finalDrive": float(tune.get("final_drive", 4.10)),
		"launchRpm": float(tune.get("launch_rpm", 3000)),
		"tirePressure": float(tune.get("tire_pressure", 32.0)),
		"clutchRelease": float(tune.get("clutch_release", 0.5)),
		"nitrousPoint": float(tune.get("nitrous_point", 0.0)),
	}
	for key in _dials.keys():
		var meta: Dictionary = _dials[key]
		var s: HSlider = meta.slider
		s.set_value_no_signal(float(seed.get(key, s.min_value)))
		_show_dial_value(str(key))

	var ratios: Array = tune.get("gear_ratios", [])
	for i in _gear_sliders.size():
		var s: HSlider = _gear_sliders[i]
		s.set_value_no_signal(float(ratios[i]) if i < ratios.size() else 1.0)
		_gear_labels[i].text = "%.2f" % s.value

	var shifts: Array = tune.get("shift_points", [])
	for i in _shift_sliders.size():
		var s: HSlider = _shift_sliders[i]
		s.set_value_no_signal(float(shifts[i]) if i < shifts.size() else s.max_value * 0.92)
		_shift_labels[i].text = "%d RPM" % int(s.value)


func _fetch_initial() -> void:
	var res: Dictionary = await Api.fetch_stats(_car_id)
	if res.get("ok", false):
		_stats = res.data
		_refresh_readouts()


# ─────────────────────────────────────────────────────────────
# EDITS OUT
# ─────────────────────────────────────────────────────────────

func _on_dial_changed(_value: float, key: String) -> void:
	_show_dial_value(key)
	_dirty = true
	_debounce.start()


func _on_gear_changed(value: float, index: int) -> void:
	_gear_labels[index].text = "%.2f" % value
	_dirty = true
	_debounce.start()


func _on_shift_changed(value: float, index: int) -> void:
	_shift_labels[index].text = "%d RPM" % int(value)
	_dirty = true
	_debounce.start()


func _show_dial_value(key: String) -> void:
	var meta: Dictionary = _dials[key]
	var s: HSlider = meta.slider
	var label: Label = meta.label
	match str(meta.fmt):
		"ratio": label.text = "%.1f:1" % s.value
		"gear":  label.text = "%.2f" % s.value
		"rpm":   label.text = "%d RPM" % int(s.value)
		"psi":   label.text = "%.1f PSI" % s.value
		"pct":   label.text = "%d%%" % int(round(s.value * 100.0))
		"ft":    label.text = "OFF" if s.value <= 0.0 else "%d FT" % int(s.value)
		_:       label.text = str(s.value)


func _payload() -> Dictionary:
	var out := {}
	for key in _dials.keys():
		var meta: Dictionary = _dials[key]
		var s: HSlider = meta.slider
		out[key] = s.value
	var ratios: Array = []
	for s in _gear_sliders:
		var slider: HSlider = s
		ratios.append(slider.value)
	var shifts: Array = []
	for s in _shift_sliders:
		var slider: HSlider = s
		shifts.append(slider.value)
	out["gearRatios"] = ratios
	out["shiftPoints"] = shifts
	return out


## Send the whole tune. Serialised: a change made while a request is in
## flight queues exactly one follow-up carrying the latest values.
func _apply() -> void:
	if _busy:
		_pending = true
		return
	_busy = true
	_dirty = false
	var res: Dictionary = await GameState.tune_car(_car_id, _payload())
	_busy = false
	# The tune itself landed in GameState; only this screen's nodes are at
	# risk if the player navigated away mid-request.
	if not is_inside_tree():
		return
	if res.get("ok", false):
		_stats = res.get("stats", {})
		_car = GameState.get_car(_car_id)
		_refresh_readouts()
	else:
		_risk_text.text = str(res.get("reason", "The tune was refused."))
		_risk_text.add_theme_color_override("font_color", Design.BAD)
	if _pending:
		_pending = false
		_apply()


# ─────────────────────────────────────────────────────────────
# READOUTS
# ─────────────────────────────────────────────────────────────

func _refresh_readouts() -> void:
	if _stats.is_empty():
		return

	_blocks["peak"].text = "%d HP" % int(_stats.get("peakHp", 0))
	_blocks["torque"].text = "%d LB-FT" % int(_stats.get("peakTorque", 0))

	var sim_et = _stats.get("simEt", null)
	_blocks["et"].text = "—" if sim_et == null else "%.3f S" % float(sim_et)
	var sim_ts = _stats.get("simTs", null)
	_blocks["trap"].text = "—" if sim_ts == null else "%.1f" % float(sim_ts)
	var top = _stats.get("topSpeedMph", null)
	_blocks["top"].text = "—" if top == null \
		else "%d KM/H" % int(round(float(top) * 1.60934))
	var accel = _stats.get("zeroToHundredKmh", null)
	_blocks["accel"].text = "—" if accel == null else "%.1f S" % float(accel)

	var score := float(_stats.get("syncScore", 0))
	_blocks["sync"].text = str(int(score))
	_blocks["sync"].add_theme_color_override("font_color", Design.sync_color(score))
	for child in _sync_holder.get_children():
		_sync_holder.remove_child(child)
		child.queue_free()
	_sync_holder.add_child(UIKit.meter(score / 100.0, Design.sync_color(score), 4))

	var risk_label := str(_stats.get("riskLabel", "SAFE"))
	var chance := float(_stats.get("damageChancePerPass", 0.0)) * 100.0
	var colour := Design.risk_color(risk_label)
	_risk_text.text = "RISK: %s (%d/100)" % [risk_label, int(_stats.get("riskLevel", 0))] \
		+ ("" if chance <= 0.0 else " — %.1f%% chance of engine damage per pass" % chance)
	_risk_text.add_theme_color_override("font_color", colour)
	var sb: StyleBoxFlat = _risk_strip.get_theme_stylebox("panel")
	sb.border_color = colour

	var health := float(_stats.get("engineHealth", 100))
	_health_note.text = "" if health >= 100.0 else "ENGINE %d%%" % int(health)
	_health_note.add_theme_color_override("font_color",
		Design.BAD if health <= 30.0 else Design.WARN)

	_graph.set_curve(_stats.get("dynoCurve", []))


func _on_exit() -> void:
	# A change made in the last third of a second is still waiting on the
	# debounce; leaving must not silently discard it.
	if _dirty or not _debounce.is_stopped():
		_debounce.stop()
		await _apply()
	if Router.can_go_back():
		Router.back()
	else:
		Router.home()
