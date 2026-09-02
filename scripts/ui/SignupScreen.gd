extends ArtScreen

# Painted element positions, measured off signup.png ──────────────
# The field rects are the interiors of the painted boxes, from just past the
# icon divider to the border (to the eye, where there is one).
const R_NAME_TEXT    := Rect2(205, 382, 434, 42)
const R_EMAIL_TEXT   := Rect2(205, 467, 434, 41)
const R_PASS_TEXT    := Rect2(205, 551, 385, 42)
const R_PASS_EYE     := Rect2(596, 556, 46, 33)
const R_CONFIRM_TEXT := Rect2(205, 634, 385, 42)
const R_CONFIRM_EYE  := Rect2(596, 640, 46, 33)
const R_CREATE       := Rect2(155, 705, 490, 45)
# Both are painted hexagons; the rects are their full extents, points included.
const R_SETTINGS     := Rect2(1262, 764, 140, 118)
const R_EXIT         := Rect2(1427, 764, 138, 118)

## Matches the server: 3-20 characters, letters, numbers and underscore.
const NAME_MIN := 3
const PASSWORD_MIN := 8

var _busy := false

var _name_field: LineEdit
var _email_field: LineEdit
var _pass_field: LineEdit
var _confirm_field: LineEdit
var _hit_create: Button

func _ready() -> void:
	art_path = "res://assets/ui/signup.png"
	art_w = 1672.0
	art_h = 941.0

	build_art()
	_build_fields()
	_build_buttons()
	build_notice()

	_name_field.grab_focus()


func _build_fields() -> void:
	_name_field = make_field("Enter your racer name", false)
	place_field(_name_field, R_NAME_TEXT, "R_NAME_TEXT")

	_email_field = make_field("Enter your email", false)
	place_field(_email_field, R_EMAIL_TEXT, "R_EMAIL_TEXT")

	_pass_field = make_field("Enter your password", true)
	place_field(_pass_field, R_PASS_TEXT, "R_PASS_TEXT")

	_confirm_field = make_field("Confirm your password", true)
	place_field(_confirm_field, R_CONFIRM_TEXT, "R_CONFIRM_TEXT")

	for f in [_name_field, _email_field, _pass_field, _confirm_field]:
		f.text_submitted.connect(_on_field_submit)

	var pass_eye := make_hit("Show or hide your password")
	pass_eye.pressed.connect(_toggle_secret.bind(_pass_field))
	place(pass_eye, R_PASS_EYE, "R_PASS_EYE")

	var confirm_eye := make_hit("Show or hide your password")
	confirm_eye.pressed.connect(_toggle_secret.bind(_confirm_field))
	place(confirm_eye, R_CONFIRM_EYE, "R_CONFIRM_EYE")


func _build_buttons() -> void:
	_hit_create = make_hit("Create your racer")
	_hit_create.pressed.connect(_on_submit)
	place(_hit_create, R_CREATE, "R_CREATE")

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


func _toggle_secret(field: LineEdit) -> void:
	field.secret = not field.secret


func _on_settings() -> void:
	show_status("Settings arrive with the options screen.", Design.TEXT_BODY)


func _on_quit() -> void:
	get_tree().quit()


## The artwork has no back control, so Escape returns to the login screen.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not _busy:
			Router.replace(Router.Screen.AUTH)
			get_viewport().set_input_as_handled()


func _on_submit() -> void:
	if _busy:
		return

	var username := _name_field.text.strip_edges()
	var email := _email_field.text.strip_edges()
	var password := _pass_field.text
	var confirm := _confirm_field.text

	var problem := _validate(username, email, password, confirm)
	if problem != "":
		show_status(problem, Design.BAD)
		return

	_set_busy(true)
	show_status("Creating your racer...", Design.TEXT_BODY)

	var res: Dictionary = await Api.register(username, password, email)

	_set_busy(false)

	if not res.get("ok", false):
		show_status(str(res.get("message", "Could not create your account.")), Design.BAD)
		return

	show_status("Loading your garage...", Design.TEXT_BODY)
	await GameState.hydrate()
	clear_status()
	Router.home()


## Caught here rather than at the server so the player is told immediately,
## and so a mistyped confirmation never becomes a real account.
func _validate(username: String, email: String, password: String, confirm: String) -> String:
	if username.is_empty():
		return "Choose a racer name."
	if username.length() < NAME_MIN:
		return "Racer names are at least %d characters." % NAME_MIN
	if email.is_empty():
		return "Enter your email."
	if not _looks_like_email(email):
		return "That email does not look right."
	if password.is_empty():
		return "Choose a password."
	if password.length() < PASSWORD_MIN:
		return "Passwords are at least %d characters." % PASSWORD_MIN
	if confirm.is_empty():
		return "Confirm your password."
	if password != confirm:
		return "Those passwords do not match."
	return ""


## Deliberately loose. Anything stricter rejects valid addresses, and only
## sending mail proves an address works.
func _looks_like_email(value: String) -> bool:
	var at := value.find("@")
	if at <= 0 or at == value.length() - 1:
		return false
	var domain := value.substr(at + 1)
	return domain.contains(".") and not domain.begins_with(".") \
		and not domain.ends_with(".") and not value.contains(" ")


func _set_busy(busy: bool) -> void:
	_busy = busy
	_hit_create.disabled = busy
	for f in [_name_field, _email_field, _pass_field, _confirm_field]:
		f.editable = not busy
