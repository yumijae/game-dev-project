class_name FloorCuller
extends Node
## Stops the renderer drawing floors Juan cannot see.
##
## The school holds several thousand small meshes (desks, chairs, PCs, signs,
## loot) spread over four storeys, and Godot would otherwise draw every one
## that falls inside the view cone - including the three storeys hidden behind
## concrete slabs. At start-up each static detail mesh is moved onto a render
## layer for its storey; every frame the active camera's cull mask is set to
## the storey it is on.
##
## On the storey he is on, the walls and slabs are also registered as
## occluders, so rooms behind a wall are skipped too (occlusion culling).
##
## Everything is shown again wherever more than one storey really is visible:
## in the stairwells, on the roof, and outside the building. The CCTV feed and
## the mirrors use their own cameras and are not affected. A culled mesh still
## blocks light from every lamp except Juan's own phone, whose beam would
## otherwise redraw the furniture of the storeys above and below each frame.

## Children of the school whose meshes are sorted by storey.
const DETAIL_GROUPS: Array[String] = ["Interactive", "ItemSpawns", "DoorFrames", "Signs", "Props", "Dressing"]
## Render layers 11-15: 1F, 2F, 3F, 4F, rooftop.
const FIRST_BIT: int = 10
const ALL_FLOORS: int = 0b11111 << FIRST_BIT
## Opaque shell meshes under school/Visual that hide whatever is behind them.
const OCCLUDER_MESHES: Array[String] = ["Mesh_int", "Mesh_ext", "Mesh_slab"]
## Slack when deciding which storey a mesh or the camera belongs to.
const EDGE: float = 0.15

var enabled: bool = true
var tagged_count: int = 0

var _phone_lights: Array[Light3D] = []


func _ready() -> void:
	# After the player and the peek camera have moved this frame.
	process_priority = 900
	# Deferred: the set dresser and the item spawner add meshes during _ready.
	_tag_meshes.call_deferred()


static func _storey(y: float) -> int:
	if y >= Campus.ROOF_Y - EDGE:
		return Campus.ROOF_FLOOR
	return clampi(int(floor((y + EDGE) / Campus.FLOOR_HEIGHT)), 0, Campus.FLOOR_COUNT - 1)


func _tag_meshes() -> void:
	var school: Node = get_tree().get_first_node_in_group(&"school")
	if school == null:
		return
	for group_name: String in DETAIL_GROUPS:
		var group: Node = school.get_node_or_null(group_name)
		if group == null:
			continue
		for node: Node in group.find_children("*", "GeometryInstance3D", true, false):
			var geometry := node as GeometryInstance3D
			# Anything already on a special layer (mirror glass) is left alone.
			if geometry.layers != 1:
				continue
			var box: AABB = geometry.global_transform * geometry.get_aabb()
			var centre: Vector3 = box.get_center()
			# Seen from several storeys at once: the stair shafts and anything
			# hung on the outside of the building.
			if not Campus.is_inside_footprint(centre, 0.3) or Campus.stairwell_at(centre) != "":
				continue
			var low: int = _storey(minf(box.position.y + EDGE * 2.0, centre.y))
			var high: int = _storey(maxf(box.end.y - EDGE * 2.0, centre.y))
			if low != high:
				continue
			geometry.layers = 1 << (FIRST_BIT + low)
			tagged_count += 1
	_build_occluders(school)
	var player := get_tree().get_first_node_in_group(&"player") as PlayerController
	if player != null and player.phone != null:
		for node: Node in player.phone.find_children("*", "Light3D", true, false):
			_phone_lights.append(node as Light3D)


## The building shell is a few thousand triangles of plain boxes with the door
## and window openings already cut out - cheap and exact as an occluder.
func _build_occluders(school: Node) -> void:
	var built: int = 0
	for mesh_name: String in OCCLUDER_MESHES:
		var instance := school.get_node_or_null("Visual/" + mesh_name) as MeshInstance3D
		if instance == null or instance.mesh == null or instance.has_node("Occluder"):
			continue
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		for surface: int in instance.mesh.get_surface_count():
			var arrays: Array = instance.mesh.surface_get_arrays(surface)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var base: int = vertices.size()
			vertices.append_array(surface_vertices)
			if arrays[Mesh.ARRAY_INDEX] != null:
				for index: int in arrays[Mesh.ARRAY_INDEX]:
					indices.append(base + index)
			else:
				for index: int in surface_vertices.size():
					indices.append(base + index)
		var shape := ArrayOccluder3D.new()
		shape.set_arrays(vertices, indices)
		var occluder := OccluderInstance3D.new()
		occluder.name = "Occluder"
		occluder.occluder = shape
		instance.add_child(occluder)
		built += 1
	if built > 0:
		get_viewport().use_occlusion_culling = true


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var mask: int = camera.cull_mask | ALL_FLOORS
	if enabled:
		var eye: Vector3 = camera.global_position
		var storey: int = _storey(eye.y)
		if storey < Campus.ROOF_FLOOR and Campus.is_inside_footprint(eye) and Campus.stairwell_at(eye) == "":
			mask = (mask & ~ALL_FLOORS) | (1 << (FIRST_BIT + storey))
	if camera.cull_mask != mask:
		camera.cull_mask = mask
		for light: Light3D in _phone_lights:
			if is_instance_valid(light):
				light.shadow_caster_mask = mask
