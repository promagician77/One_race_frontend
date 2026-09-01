class_name PinReticle
extends Control
## The mark on the map pin the player is pointing at, or has chosen.
##
## The pins are painted into citymap.png, so nothing here may recolour or move
## one -- the mark has to do its work in the ring of map around the badge.
## Three layers, each answering a different question:
##
##   ring       is the cursor on this one?   thin, tracks hover and focus
##   brackets   is this the one chosen?      four arcs that snap in, then turn
##   ping       and is it live?              a sonar ring leaving the pin
##
## Drawn rather than textured. The pins are small and the map is dark, so a
## few arcs read more cleanly at this size than a sprite would, and they cost
## nothing to restyle or recolour per pin.

## Radians a second the brackets turn once they have closed in. Slow enough
## that it reads as a machine holding a lock, not as a spinner.
const SPIN := 0.5

## Seconds the brackets take to close, and the radius they start from.
const SNAP := 0.3
const SNAP_FROM := 1.55

## Half the angle each of the four brackets covers.
const BRACKET := 0.42

## Seconds for the hover ring to come and go.
const FADE := 0.16

## A ping every PERIOD seconds, alive for LIFE of them, run out to REACH.
## The gap matters: a ring that never stops is wallpaper, one that arrives
## every couple of seconds keeps drawing the eye back.
const PING_PERIOD := 1.9
const PING_LIFE := 1.15
const PING_FROM := 0.55
const PING_REACH := 1.75

## Radii as shares of the hit area, which is a little wider than the painted
## badge. Both clear the badge's own ring -- landing on it just makes the pin
## look recoloured, which is the one thing this cannot do.
const RING_R := 0.95
const BRACKET_R := 1.05

var tint: Color = Design.AMBER_HOT

var _selected := false
var _hovered := false
var _focused := false

var _lit := 0.0    ## 0..1, how present the hover ring is
var _snap := 0.0   ## 0..1, how far the brackets have closed
var _spin := 0.0
var _ping := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	if on:
		# Replay the lock from the top, so clicking the same pin twice still
		# reads as a fresh choice.
		_snap = 0.0
		_ping = 0.0
	_wake()


func set_hovered(on: bool) -> void:
	if _hovered != on:
		_hovered = on
		_wake()


func set_focused(on: bool) -> void:
	if _focused != on:
		_focused = on
		_wake()


## Everything animating winds down to a resting state, so the mark stops
## processing once it gets there. Eleven pins idling on the map is eleven
## _process calls a frame that draw nothing.
func _process(delta: float) -> void:
	_lit = move_toward(_lit, 1.0 if _hovered or _focused else 0.0, delta / FADE)

	if _selected:
		_snap = minf(1.0, _snap + delta / SNAP)
		_spin = fmod(_spin + SPIN * delta, TAU)
		_ping = fmod(_ping + delta, PING_PERIOD)
	else:
		_snap = maxf(0.0, _snap - delta / SNAP)

	queue_redraw()

	if not _selected and is_zero_approx(_lit) and is_zero_approx(_snap):
		set_process(false)


func _draw() -> void:
	var mid := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if r <= 0.0:
		return

	if _lit > 0.0:
		draw_arc(mid, r * RING_R, 0.0, TAU, 48, Color(tint, 0.45 * _lit), 2.0, true)

	# Under the brackets, so a ping leaves from behind the lock.
	if _selected and _ping < PING_LIFE:
		var q := _ping / PING_LIFE
		var falloff := (1.0 - q) * (1.0 - q)
		draw_arc(mid, r * lerpf(PING_FROM, PING_REACH, q), 0.0, TAU, 56,
			Color(tint, 0.5 * falloff), 2.0, true)

	if _snap > 0.0:
		var reach := r * lerpf(SNAP_FROM, BRACKET_R, _overshoot(_snap))
		# A hairline circle ties the four brackets into one instrument.
		draw_arc(mid, reach, 0.0, TAU, 48, Color(tint, 0.14 * _snap), 1.0, true)
		for i in 4:
			var at := _spin + TAU * (float(i) + 0.5) / 4.0
			draw_arc(mid, reach, at - BRACKET, at + BRACKET, 10,
				Color(tint, _snap), 3.0, true)


func _wake() -> void:
	set_process(true)
	queue_redraw()


## easeOutBack. The brackets pass their mark and settle back onto it, which
## reads as a lock closing rather than a ring sliding into place.
func _overshoot(t: float) -> float:
	const K := 1.70158
	var u := t - 1.0
	return 1.0 + u * u * ((K + 1.0) * u + K)
