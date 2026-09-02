extends Node3D
## A fly-around viewer for checking a .glb before any game code depends on it.
##
##   godot --path client tools/ModelViewer.tscn                 (the track)
##   godot --path client tools/ModelViewer.tscn -- --model=car   (the car)
##   godot --path client tools/ModelViewer.tscn -- --model=res://path/to.glb
##
##   W A S D   move            Q E   down / up
##   mouse     look (hold right button, or press Tab to capture)
##   Shift     move faster     Ctrl  slower
##   R         back to the framing shot
##   Esc       quit

const MODELS := {
	"track": "res://assets/map/france.glb",
	"car": "res://assets/cars/1/1.glb",
}
const DEFAULT := "track"

const SPEED := 40.0
const FAST := 6.0
const SLOW := 0.15
const LOOK := 0.0025

var _camera: Camera3D
var _home := Transform3D()
var _yaw := 0.0
var _pitch := 0.0
var _captured := false


func _ready() -> void:
	var path := _wanted_model()
	print("\nviewer: %s" % path)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = Sky.new()
	e.sky.sky_material = ProceduralSkyMaterial.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.far = 8000.0
	add_child(_camera)

	if not ResourceLoader.exists(path):
		push_error("No such model: %s" % path)
		return

	var model: Node3D = (load(path) as PackedScene).instantiate()
	add_child(model)

	_frame(_bounds(model))
	print("controls: WASD move, Q/E down/up, hold right mouse to look, Tab to")
	print("          capture the mouse, Shift faster, Ctrl slower, R reset, Esc quit\n")


## Which model to show. A bare name picks from MODELS; anything starting with
## res:// is taken as a path, so a new export can be checked without editing
## this file.
func _wanted_model() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="):
			var want := arg.substr(8)
			return want if want.begins_with("res://") else str(MODELS.get(want, want))
	return str(MODELS[DEFAULT])


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for m in _meshes(node):
		var b: AABB = m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out


## Stand back far enough to see the whole thing, looking slightly down at it.
func _frame(box: AABB) -> void:
	if box.size == Vector3.ZERO:
		_home = Transform3D(Basis(), Vector3(0, 5, 10))
	else:
		var span: float = maxf(box.size.x, maxf(box.size.y, box.size.z))
		var eye := box.get_center() + Vector3(0, span * 0.45, span * 0.9)
		_home = Transform3D(Basis(), eye).looking_at(box.get_center(), Vector3.UP)
		print("model spans %.1f x %.1f x %.1f m, centred at (%.1f, %.1f, %.1f)"
			% [box.size.x, box.size.y, box.size.z,
			   box.get_center().x, box.get_center().y, box.get_center().z])
	_reset()


func _reset() -> void:
	_camera.transform = _home
	_yaw = _camera.rotation.y
	_pitch = _camera.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_R:
				_reset()
			KEY_TAB:
				_captured = not _captured
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _captured \
					else Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion:
		var looking: bool = _captured \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
		if looking:
			_yaw -= event.relative.x * LOOK
			_pitch = clampf(_pitch - event.relative.y * LOOK, -1.5, 1.5)
			_camera.rotation = Vector3(_pitch, _yaw, 0)


func _process(delta: float) -> void:
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): move.z -= 1.0
	if Input.is_key_pressed(KEY_S): move.z += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if Input.is_key_pressed(KEY_E): move.y += 1.0
	if Input.is_key_pressed(KEY_Q): move.y -= 1.0
	if move == Vector3.ZERO:
		return

	var speed := SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= FAST
	elif Input.is_key_pressed(KEY_CTRL):
		speed *= SLOW

	_camera.translate(move.normalized() * speed * delta)
