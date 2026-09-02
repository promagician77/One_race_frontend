extends Node
## Reports what is actually inside a .glb: its node tree, how many meshes and
## triangles it carries, and the size of the thing in metres.
##
## Worth knowing before building a viewer around it -- a model exported at the
## wrong scale or facing the wrong way looks like a broken camera otherwise.
##
##   godot --headless --path client tools/ModelInspect.tscn

const MODELS := [
	"res://assets/map/france.glb",
	"res://assets/cars/1/1.glb",
]


func _ready() -> void:
	for path in MODELS:
		_inspect(path)
	get_tree().quit()


func _inspect(path: String) -> void:
	print("\n" + "=".repeat(60))
	print(path)
	print("=".repeat(60))

	if not ResourceLoader.exists(path):
		print("  not imported")
		return

	var packed: PackedScene = load(path)
	if packed == null:
		print("  failed to load")
		return

	var root: Node = packed.instantiate()
	add_child(root)

	var meshes: Array = []
	_collect(root, meshes)

	var tris := 0
	var surfaces := 0
	var bounds := AABB()
	var first := true

	for m: MeshInstance3D in meshes:
		var mesh: Mesh = m.mesh
		if mesh == null:
			continue
		surfaces += mesh.get_surface_count()
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			tris += (idx.size() / 3) if idx.size() > 0 else (verts.size() / 3)

		# Global bounds, so a part parented deep still counts.
		var box := m.get_aabb()
		box = m.global_transform * box
		bounds = box if first else bounds.merge(box)
		first = false

	print("  nodes      %d" % _count(root))
	print("  meshes     %d  (%d surfaces, %d triangles)" % [meshes.size(), surfaces, tris])
	if not first:
		print("  size       %.2f x %.2f x %.2f metres"
			% [bounds.size.x, bounds.size.y, bounds.size.z])
		print("  centre     (%.2f, %.2f, %.2f)"
			% [bounds.get_center().x, bounds.get_center().y, bounds.get_center().z])
		print("  sits on y  %.2f" % bounds.position.y)

	print("  tree:")
	_print_tree(root, 2, 0)

	root.queue_free()


func _collect(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect(c, out)


func _count(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count(c)
	return n


## Only the first couple of levels -- a track can carry hundreds of parts.
func _print_tree(node: Node, indent: int, depth: int) -> void:
	if depth > 2:
		return
	var extra := ""
	if node is MeshInstance3D and node.mesh != null:
		extra = "  [%d surfaces]" % node.mesh.get_surface_count()
	print("%s- %s (%s)%s" % [" ".repeat(indent), node.name, node.get_class(), extra])
	var shown := 0
	for c in node.get_children():
		if shown >= 8:
			print("%s  ... and %d more" % [" ".repeat(indent), node.get_child_count() - shown])
			break
		_print_tree(c, indent + 2, depth + 1)
		shown += 1
