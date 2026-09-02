class_name MoveDialog
extends Control
## The move-in confirmation. Opened from a district modal's TRAVEL row, it
## lays out what the move costs before anything is spent: the fee, the
## parking, and — moving down — exactly how many cars lose their space.
##
## The decision itself belongs to the server: CONFIRM goes through
## GameState.move_to and whatever comes back is the truth. The local
## can_move_to check only shapes the dialog (a disabled button with the
## reason beats a doomed round trip).

signal finished(moved: bool, message: String)

var _hood: Dictionary = {}
var _check: Dictionary = {}
var _confirm: Button
var _cancel: Button
var _reason: Label
var _impound_warn: Label = null
var _busy := false


func setup(hood_id: String) -> void:
	_hood = Catalog.get_neighborhood(hood_id)
	_check = GameState.can_move_to(hood_id)
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Dimmed map behind; clicking it is a cancel.
	var dim := Button.new()
	dim.flat = true
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim_sb := StyleBoxFlat.new()
	dim_sb.bg_color = Color(0, 0, 0, 0.55)
	for state in ["normal", "hover", "pressed", "focus"]:
		dim.add_theme_stylebox_override(state, dim_sb)
	dim.pressed.connect(_on_cancel)
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := UIKit.panel(true)
	panel.custom_minimum_size = Vector2(460, 0)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", Design.SP_3)
	panel.add_child(col)

	var hood_colour := Color(str(_hood.get("colorCode", "#8B8B8B")))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", Design.SP_3)
	var title := UIKit.heading("MOVE TO %s" % str(_hood.get("name", "")).to_upper(), Design.SIZE_HEAD)
	Design.apply_display(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UIKit.badge("TIER %d" % int(_hood.get("rank", 0)), hood_colour))
	col.add_child(head)

	var blurb := UIKit.body(str(_hood.get("blurb", "")), Design.TEXT_BODY)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(blurb)

	col.add_child(UIKit.divider())

	var cost := int(_hood.get("moveInCost", 0))
	var moving_up: bool = int(_hood.get("rank", 0)) > int(GameState.current_neighborhood().get("rank", 0))
	col.add_child(UIKit.stat_row("MOVE-IN COST",
		Design.fmt_cash(cost) if moving_up else "FREE",
		Design.CASH if not moving_up or GameState.can_afford(cost) else Design.BAD))
	col.add_child(UIKit.stat_row("PARKING",
		"%d SPACES" % int(_hood.get("parkingSpaces", 1))))
	col.add_child(UIKit.stat_row("YOU LIVE IN",
		str(GameState.current_neighborhood().get("name", "")).to_upper(), Design.TEXT_MUTED))

	# Moving down is free but not painless: the server impounds what no
	# longer fits. Say so before, not after.
	var impound := int(_check.get("impound", 0))
	if _check.get("ok", false) and impound > 0:
		var warn := UIKit.accent_panel(Design.WARN)
		_impound_warn = UIKit.body(
			"%d of your cars won't fit and will be impounded. Your oldest cars keep their spaces." % impound,
			Design.WARN)
		_impound_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.add_child(_impound_warn)
		col.add_child(warn)

	# A refusal reads here — and this same label carries any server refusal
	# that slips past the local check.
	_reason = UIKit.body(str(_check.get("reason", "")), Design.BAD)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.visible = not _check.get("ok", false)
	col.add_child(_reason)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Design.SP_3)
	_cancel = UIKit.button("STAY PUT", UIKit.BtnStyle.SECONDARY)
	_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel.pressed.connect(_on_cancel)
	row.add_child(_cancel)

	var label := "MOVE IN — %s" % Design.fmt_cash(cost) if moving_up and cost > 0 else "MOVE IN"
	_confirm = UIKit.button(label, UIKit.BtnStyle.PRIMARY)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.disabled = not _check.get("ok", false)
	_confirm.pressed.connect(_on_confirm)
	row.add_child(_confirm)
	col.add_child(row)


func _on_cancel() -> void:
	if _busy:
		return
	finished.emit(false, "")
	queue_free()


func _on_confirm() -> void:
	if _busy:
		return
	_busy = true
	_confirm.disabled = true
	_cancel.disabled = true

	var res: Dictionary = await GameState.move_to(str(_hood.get("id", "")))
	if not is_inside_tree():
		return
	if not res.get("ok", false):
		# The server said no — show its reason and hand control back.
		_busy = false
		_cancel.disabled = false
		_confirm.disabled = false
		_reason.text = str(res.get("reason", "The move was refused."))
		_reason.visible = true
		return

	var message := "WELCOME TO %s" % str(_hood.get("name", "")).to_upper()
	var impounded := int(res.get("impound", 0))
	if impounded > 0:
		message += " — %d CAR%s IMPOUNDED" % [impounded, "" if impounded == 1 else "S"]
	finished.emit(true, message)
	queue_free()
