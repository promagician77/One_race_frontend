extends Control
## Root scene. Owns the permanent chrome and hosts whichever screen the Router
## has active.
##
## There are two hosts. In-game screens go inside the frame's content area, so
## the header, footer and edge glow stay put across navigation. The login and
## sign-up screens are their own full-bleed artwork and take the whole window
## instead, with the frame hidden.

@onready var _fullscreen: Control = $Fullscreen
@onready var _frame: Control      = $Frame

## Screens that render before there is a session. These own the whole window.
const CHROMELESS := ["AUTH", "SIGNUP"]


func _ready() -> void:
	Router.screen_changed.connect(_on_screen_changed)
	Api.auth_changed.connect(_on_auth_changed)
	GameState.cash_changed.connect(_on_cash_changed)

	# The frame builds its content host in _ready, so it is available by now.
	Router.container_resolver = _host_for
	Router.register_container(_frame.content)

	await _boot()


## Decide the first screen. A stored token is only a claim -- it may have
## expired or been revoked -- so it is checked against the server before we
## trust it. Anything other than a clean yes drops the player on the login
## screen rather than into a session that fails on its first real request.
func _boot() -> void:
	if not Api.is_signed_in():
		Router.replace(Router.Screen.AUTH)
		return

	var res: Dictionary = await Api.refresh_me()
	if res.get("ok", false):
		# The session is good — now pull the truth. Without this the whole
		# client ran off the local save file: another account's cash, cars
		# that don't exist, purchases refused on phantom numbers.
		await GameState.hydrate()
		Router.home()
		return

	# A network outage should not silently discard a good session, so only an
	# actual rejection clears the stored token.
	if str(res.get("code", "")) != "NETWORK":
		Api.sign_out()
	Router.replace(Router.Screen.AUTH)


## Which host a screen belongs in. Called by the Router before it parents the
## screen, so a full-bleed login page is never added inside a frame that is
## about to be hidden.
func _host_for(screen_id: String) -> Node:
	return _fullscreen if screen_id in CHROMELESS else _frame.content


func _on_screen_changed(screen_id: String) -> void:
	var chromeless := screen_id in CHROMELESS
	_frame.visible = not chromeless

	if not chromeless:
		_frame.set_screen_name(screen_id)
		_frame.set_footer("")
		_frame.refresh()


func _on_auth_changed(signed_in: bool) -> void:
	if signed_in:
		_frame.refresh()
	else:
		# The session is gone: drop the cached world with it, and clear the
		# back stack so Escape cannot navigate into a signed-out game.
		GameState.reset()
		Router.clear_stack()
		Router.replace(Router.Screen.AUTH)


func _on_cash_changed(_amount: int) -> void:
	# Brief flash so the player notices money moving. The frame pulls the new
	# figure itself; this is only the emphasis.
	var t := create_tween()
	t.tween_property(_frame, "modulate", Color(1.4, 1.4, 1.4), Design.T_INSTANT)
	t.tween_property(_frame, "modulate", Color.WHITE, Design.T_FAST)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and Router.can_go_back():
			Router.back()
			get_viewport().set_input_as_handled()
