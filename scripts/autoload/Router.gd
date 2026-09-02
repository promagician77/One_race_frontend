extends Node
## Screen navigation. One place owns which screen is up and what context
## it was opened with. Screens never load each other directly — they call
## Router.go(). That keeps the back stack correct and makes it trivial to
## add transitions or guards later in one spot.

signal screen_changed(screen_id: String)

enum Screen {
	AUTH,
	SIGNUP,
	MAP,
	DEALERSHIP,
	PARTS_SHOP,
	GARAGE,
	TUNE,
	PRACTICE,
	PROFILE,
}

const SCENES := {
	Screen.AUTH:       "res://scenes/auth/AuthScreen.tscn",
	Screen.SIGNUP:     "res://scenes/auth/SignupScreen.tscn",
	Screen.MAP:        "res://scenes/map/CityMap.tscn",
	Screen.DEALERSHIP: "res://scenes/dealership/Dealership.tscn",
	Screen.PARTS_SHOP: "res://scenes/parts_shop/PartsShop.tscn",
	Screen.GARAGE:     "res://scenes/garage/Garage.tscn",
	Screen.TUNE:       "res://scenes/tune/TuneScreen.tscn",
	Screen.PRACTICE:   "res://scenes/practice/PracticeTrack.tscn",
	Screen.PROFILE:    "res://scenes/profile/Profile.tscn",
}

var _container: Node = null

## Optional. Main sets this so the host can depend on which screen is opening
## -- the login art is full-bleed and lives outside the game frame, everything
## else lives inside it. Resolved BEFORE the screen is added, because
## reparenting it afterwards is what produced a black screen.
var container_resolver: Callable = Callable()
var _current: Node = null
var _current_screen: Screen = Screen.MAP
var _stack: Array = []

## Context passed into the screen being opened.
## e.g. { "neighborhood": "HARBOUR" } when opening a shop from the map.
var context: Dictionary = {}


func register_container(node: Node) -> void:
	_container = node


func go(screen: Screen, ctx: Dictionary = {}) -> void:
	if _container == null:
		push_error("Router has no container. Call register_container() from Main.")
		return

	_stack.append({"screen": _current_screen, "context": context.duplicate()})
	_swap(screen, ctx)


## Replace without pushing to the stack — for lateral moves like
## switching cars inside the garage.
func replace(screen: Screen, ctx: Dictionary = {}) -> void:
	_swap(screen, ctx)


func back() -> void:
	if _stack.is_empty():
		_swap(Screen.MAP, {})
		return
	var prev: Dictionary = _stack.pop_back()
	_swap(prev.screen, prev.context)


func home() -> void:
	_stack.clear()
	_swap(Screen.MAP, {})


## Forget everything behind this point. Called on sign-out so Escape cannot
## walk back into a session that no longer exists.
func clear_stack() -> void:
	_stack.clear()


func can_go_back() -> bool:
	return not _stack.is_empty()


func _swap(screen: Screen, ctx: Dictionary) -> void:
	if container_resolver.is_valid():
		var host: Node = container_resolver.call(Screen.keys()[screen])
		if host != null:
			_container = host

	if _container == null:
		push_error("Router has no container. Call register_container() from Main.")
		return

	var path: String = SCENES.get(screen, "")
	if path == "" or not ResourceLoader.exists(path):
		push_error("Screen scene missing: %s" % path)
		return

	if _current != null:
		_current.queue_free()
		_current = null

	context = ctx
	_current_screen = screen

	var packed: PackedScene = load(path)
	_current = packed.instantiate()
	_container.add_child(_current)

	screen_changed.emit(Screen.keys()[screen])


func current() -> Screen:
	return _current_screen
