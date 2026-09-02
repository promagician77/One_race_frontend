extends ArtScreen
## Racer login. First screen of the game and the only one that renders
## before there is a session. CREATE ACCOUNT hands off to the sign-up page.

# Painted element positions, measured off screen.png ──────────────
# The field rects are the interiors of the painted boxes, from just past the
# icon divider to the border (to the eye, where there is one).
const R_NAME_TEXT  := Rect2(205, 382, 434, 42)
const R_PASS_TEXT  := Rect2(205, 467, 385, 42)
const R_EYE        := Rect2(596, 472, 46, 33)
const R_START      := Rect2(150, 532, 495, 68)
const R_LOGIN      := Rect2(148, 623, 244, 45)
const R_GUEST      := Rect2(400, 623, 245, 45)
const R_CREATE     := Rect2(148, 683, 497, 45)
# Both are painted hexagons; the rects are their full extents, points included.
const R_SETTINGS   := Rect2(1262, 764, 140, 118)
const R_EXIT       := Rect2(1427, 764, 138, 118)

var _busy := false

var _name_field: LineEdit
var _pass_field: LineEdit
var _hit_start: Button
var _hit_login: Button
var _hit_create: Button


func _ready() -> void:
	art_path = "res://assets/ui/screen.png"
	art_w = 1672.0
	art_h = 941.0

	build_art()
	_build_fields()
	_build_buttons()
	build_notice()

	_name_field.grab_focus()


func _build_fields() -> void:
	_name_field = make_field("Enter your racer name", false)
	_name_field.text_submitted.connect(_on_field_submit)
	place_field(_name_field, R_NAME_TEXT, "R_NAME_TEXT")

	_pass_field = make_field("Enter your password", true)
	_pass_field.text_submitted.connect(_on_field_submit)
	place_field(_pass_field, R_PASS_TEXT, "R_PASS_TEXT")

	var eye := make_hit("Show or hide your password")
	eye.pressed.connect(_on_reveal)
	place(eye, R_EYE, "R_EYE")


func _build_buttons() -> void:
	# START and LOGIN both sign in -- the art gives them equal weight and a
	# player will reach for whichever they read first.
	_hit_start = make_hit("Sign in")
	_hit_start.pressed.connect(_on_submit)
	place(_hit_start, R_START, "R_START")

	_hit_login = make_hit("Sign in")
	_hit_login.pressed.connect(_on_submit)
	place(_hit_login, R_LOGIN, "R_LOGIN")

	_hit_create = make_hit("Create a new racer")
	_hit_create.pressed.connect(_on_create_account)
	place(_hit_create, R_CREATE, "R_CREATE")

	# GUEST is painted into the art but the server has no guest path, so it
	# says so rather than doing nothing when clicked.
	var guest := make_hit("Guest racing is not available yet")
	guest.pressed.connect(_on_guest)
	place(guest, R_GUEST, "R_GUEST")

	# Painted hexagons, so these light themselves instead of taking a wash.
	var settings := place_icon_hit(R_SETTINGS,
		"Settings arrive with the options screen", "R_SETTINGS")
	settings.pressed.connect(_on_settings)

	var quit := place_icon_hit(R_EXIT, "Quit the game", "R_EXIT")
	quit.pressed.connect(_on_quit)


# ─────────────────────────────────────────────────────────────
# ACTIONS
# ─────────────────────────────────────────────────────────────

func _on_field_submit(_text: String) -> void:
	_on_submit()


func _on_reveal() -> void:
	_pass_field.secret = not _pass_field.secret


func _on_create_account() -> void:
	Router.go(Router.Screen.SIGNUP)


func _on_guest() -> void:
	show_status("Guest racing is not available yet. Create an account to start.",
		Design.WARN)


func _on_settings() -> void:
	show_status("Settings arrive with the options screen.", Design.TEXT_BODY)


func _on_quit() -> void:
	get_tree().quit()


func _on_submit() -> void:
	if _busy:
		return

	var username := _name_field.text.strip_edges()
	var password := _pass_field.text

	if username.is_empty() or password.is_empty():
		show_status("Enter a racer name and password.", Design.BAD)
		return

	_set_busy(true)
	show_status("Signing in...", Design.TEXT_BODY)

	var res: Dictionary = await Api.login(username, password)

	_set_busy(false)

	if not res.get("ok", false):
		show_status(str(res.get("message", "Sign in failed.")), Design.BAD)
		return

	show_status("Loading your garage...", Design.TEXT_BODY)
	await GameState.hydrate()
	clear_status()
	Router.home()


func _set_busy(busy: bool) -> void:
	_busy = busy
	_hit_start.disabled = busy
	_hit_login.disabled = busy
	_hit_create.disabled = busy
	_name_field.editable = not busy
	_pass_field.editable = not busy
