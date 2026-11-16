class_name SetDresser
extends Node3D
## Makes the rooms look used. The building is generated from boxes and a
## handful of scanned props; left alone it reads as a showroom: empty shelving,
## counters that are plain white blocks, props at the wrong scale.
##
##   * every shelving unit and bookcase is filled - archive boxes and binders
##     in offices, sacks, cans and bottles in the pantry and kitchen, books
##     in the bookcases - seeded from its position, so a room looks the same
##     every night
##   * counters, cabinets and fridges get door seams, a toe-kick and handles
##     (shaders/cabinet_overlay)
##   * props that were imported too large are brought to real-world size
##
## Everything here is visual only: no collision, nothing a ray can hit.

const CABINET_SHADER: Shader = preload("res://shaders/cabinet_overlay.gdshader")
## Clutter keeps this far from anything Juan can pick up, so loot is never buried.
const LOOT_CLEARANCE: float = 0.3
const STEEL_SHELF_LEVELS: Array[float] = [0.132, 0.638, 1.144, 1.652]
const STEEL_SHELF_CLEARANCE: float = 0.45
const BOOKCASE_LEVELS: Array[float] = [0.10, 0.40, 0.68, 0.96, 1.28, 1.66]
const BOOKCASE_CLEARANCE: Array[float] = [0.27, 0.25, 0.25, 0.29, 0.35, 0.36]
## Imported scale -> real-world scale, by prop scene name.
const RESCALE: Dictionary = {"classic_laptop": 0.56, "security_camera_01": 0.6}
const CABINET_MESHES: Dictionary = {"Mesh_white": 0.0, "Mesh_steel": 1.0}

const CARDBOARD: Array[Color] = [Color(0.52, 0.4, 0.26), Color(0.47, 0.36, 0.24), Color(0.56, 0.45, 0.3), Color(0.42, 0.33, 0.23)]
const BINDERS: Array[Color] = [Color(0.06, 0.06, 0.07), Color(0.1, 0.16, 0.3), Color(0.33, 0.07, 0.06), Color(0.1, 0.22, 0.14),
	Color(0.3, 0.3, 0.31), Color(0.06, 0.06, 0.07)]
const BOOKS: Array[Color] = [Color(0.3, 0.08, 0.07), Color(0.1, 0.15, 0.28), Color(0.12, 0.2, 0.13), Color(0.35, 0.28, 0.16),
	Color(0.2, 0.2, 0.2), Color(0.42, 0.38, 0.3), Color(0.24, 0.12, 0.2)]
const SACKS: Array[Color] = [Color(0.62, 0.56, 0.44), Color(0.55, 0.5, 0.4), Color(0.66, 0.62, 0.52)]
const CANS: Array[Color] = [Color(0.5, 0.1, 0.08), Color(0.62, 0.6, 0.56), Color(0.15, 0.3, 0.16), Color(0.6, 0.45, 0.12), Color(0.12, 0.2, 0.4)]
const BOTTLES: Array[Color] = [Color(0.12, 0.08, 0.04), Color(0.08, 0.16, 0.08), Color(0.3, 0.2, 0.08)]
const PAPER: Color = Color(0.8, 0.78, 0.7)

var _rng := RandomNumberGenerator.new()
var _loot: Array[Vector3] = []
## Per floor: {"box_xf": Array[Transform3D], "box_col": Array[Color], "cyl_xf": ..., "cyl_col": ...}
var _batches: Dictionary = {}


func _ready() -> void:
	var school: Node = get_tree().get_first_node_in_group(&"school")
	if school == null:
		return
	_detail_cabinets(school)
	_grow_planters(school)
	_clear_window_glass(school)
	var props: Node = school.get_node_or_null("Props")
	if props == null:
		return
	var spawns: Node = school.get_node_or_null("ItemSpawns")
	if spawns != null:
		for marker: Node in spawns.get_children():
			if marker is Node3D:
				_loot.append((marker as Node3D).global_position)
	for node: Node in props.get_children():
		var prop := node as Node3D
		if prop == null:
			continue
		var kind: String = prop.scene_file_path.get_file().get_basename()
		if RESCALE.has(kind):
			var factor: float = RESCALE[kind]
			prop.scale *= factor
		elif kind == "steel_frame_shelves_01":
			_fill_steel_shelves(prop)
		elif kind == "wooden_bookshelf_worn":
			_fill_bookcase(prop)
	# Fittings are fixed to walls and worktops; they never bury anything.
	_loot.clear()
	_dress_restrooms()
	_commit()
	# Collision has to exist before anything can be tested for support.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if is_inside_tree():
		_seat_keyboards(school)


# ------------------------------------------------------------------- cabinets

func _detail_cabinets(school: Node) -> void:
	for mesh_name: String in CABINET_MESHES:
		var instance := school.get_node_or_null("Visual/" + mesh_name) as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var base: Material = instance.mesh.surface_get_material(0)
		if base == null:
			continue
		var overlay := ShaderMaterial.new()
		overlay.shader = CABINET_SHADER
		overlay.set_shader_parameter(&"handles", CABINET_MESHES[mesh_name])
		var detailed: Material = base.duplicate()
		detailed.next_pass = overlay
		instance.material_override = detailed


# ------------------------------------------------------------------ restrooms

## The restrooms are built as bare partitions, a white block with three discs
## on it and a sheet of glass. This fits them out: laminate cubicles with
## doors standing open, pilasters, feet and a head rail;
## soap and towel dispensers, a bin, paper in each cubicle and floor drains.
##
## Coordinates follow the building generator: u runs east from the room's west
## wall, d runs from the corridor wall towards the back of the room.
func _dress_restrooms() -> void:
	for room: Dictionary in Campus.ROOMS:
		if room["type"] != "restroom":
			continue
		var x0: float = room["x0"]
		var x1: float = room["x1"]
		var z0: float = room["z0"]
		var z1: float = room["z1"]
		var floor_index: int = room["floor"]
		var width: float = x1 - x0
		var depth: float = z1 - z0
		# Local +Z of this frame is -d, so points are written (u, y, -d).
		var frame := Transform3D(Basis.IDENTITY, Vector3(x0, Campus.floor_y(floor_index), z1))
		_rng.seed = hash(frame.origin.snappedf(0.05))
		_fit_cubicles(frame, width, depth)
		_fit_washstand(frame, depth)
		var room_name: String = room["name"]
		if room_name.begins_with("Male"):
			_fit_urinals(frame, width)
		# Floor drain.
		_box(frame, Vector3(width * 0.5, 0.003, -3.4), Vector3(0.16, 0.005, 0.16), Color(0.2, 0.2, 0.21))
		for slot: int in 4:
			_box(frame, Vector3(width * 0.5 - 0.045 + float(slot) * 0.03, 0.0062, -3.4), Vector3(0.008, 0.001, 0.12), Color(0.02, 0.02, 0.02))


func _fit_cubicles(frame: Transform3D, width: float, depth: float) -> void:
	var laminate := Color(0.25, 0.32, 0.36)
	var steel := Color(0.42, 0.43, 0.45)
	# The generator's cubicle fronts stand 1.63 m in front of the back wall.
	var front: float = depth - 1.63
	var face: float = -(front - 0.028)
	var stalls: int = int((width - 0.3) / 1.1)
	for i: int in stalls + 1:
		var u: float = 0.15 + float(i) * 1.1
		# Laminate over the bare partition, on feet, with a pilaster edge.
		_box(frame, Vector3(u, 1.05, -(depth - 0.8)), Vector3(0.062, 1.92, 1.52), laminate.darkened(_rng.randf_range(0.0, 0.08)))
		_cylinder(frame, Vector3(u, 0.05, -front), 0.016, 0.1, steel)
		_cylinder(frame, Vector3(u, 0.004, -front), 0.04, 0.008, steel)
	# Head rail tying the fronts together.
	_box(frame, Vector3(0.15 + float(stalls) * 0.55, 2.025, -front), Vector3(float(stalls) * 1.1 + 0.1, 0.04, 0.05), steel)
	for i: int in stalls:
		var centre: float = 0.15 + 0.55 + float(i) * 1.1
		# The front panel becomes a door between two fixed pilasters: laminate
		# facing, a shadow gap either side of the door, hinges and a latch.
		_box(frame, Vector3(centre, 1.05, -front), Vector3(1.1, 1.92, 0.054), laminate.lightened(_rng.randf_range(0.0, 0.05)))
		for side: float in [-1.0, 1.0]:
			_box(frame, Vector3(centre + side * 0.34, 1.05, face), Vector3(0.007, 1.92, 0.004), Color(0.02, 0.02, 0.02))
		for hinge_y: float in [0.4, 1.7]:
			_cylinder(frame, Vector3(centre - 0.34, hinge_y, face + 0.006), 0.011, 0.1, steel)
		_cylinder(frame, Vector3(centre + 0.27, 1.05, face + 0.004), 0.03, 0.012, steel, Basis(Vector3.RIGHT, PI * 0.5))
		_box(frame, Vector3(centre + 0.27, 1.05, face + 0.011), Vector3(0.036, 0.008, 0.003), Color(0.5, 0.08, 0.06))
		_box(frame, Vector3(centre + 0.27, 0.93, face + 0.012), Vector3(0.02, 0.1, 0.02), steel)
		# Paper on the partition beside the pan, and a brush behind it.
		var paper_at := Vector3(0.15 + float(i) * 1.1 + 0.075, 0.72, -(depth - 0.75))
		if _rng.randf() < 0.8:
			_cylinder(frame, paper_at, 0.05, 0.1, Color(0.82, 0.8, 0.76), Basis(Vector3.RIGHT, PI * 0.5))
		_box(frame, paper_at + Vector3(-0.03, 0.06, 0.0), Vector3(0.02, 0.02, 0.13), steel)
		# (The toilet model has its own cistern and flush lever; the lever and
		# pipe that used to be added here were for the old placeholder pan.)


func _fit_washstand(frame: Transform3D, depth: float) -> void:
	# The worktop, basins, taps and the mirror are real fixtures now
	# (core/world/sink_fixture.gd, core/world/mirror_surface.gd); this only
	# adds the dispensers and the bin around them.
	var porcelain := Color(0.82, 0.82, 0.8)
	var middle: float = depth * 0.5
	var length: float = depth - 3.4
	for k: int in 2:
		var d: float = 2.3 + float(k) * 0.9
		# Soap dispenser on the wall between the basins.
		_box(frame, Vector3(0.11, 1.12, -(d + 0.45)), Vector3(0.07, 0.16, 0.09), porcelain)
		_box(frame, Vector3(0.15, 1.05, -(d + 0.45)), Vector3(0.03, 0.02, 0.03), Color(0.1, 0.1, 0.1))
	# Towel dispenser and a bin at the far end of the stand.
	var beyond: float = middle + length * 0.5 + 0.3
	_box(frame, Vector3(0.09, 1.35, -beyond), Vector3(0.1, 0.34, 0.28), porcelain.darkened(0.08))
	_box(frame, Vector3(0.1, 1.17, -beyond), Vector3(0.012, 0.08, 0.2), Color(0.8, 0.79, 0.74))
	_cylinder(frame, Vector3(0.24, 0.22, -(beyond + 0.02)), 0.15, 0.44, Color(0.16, 0.17, 0.18))
	_cylinder(frame, Vector3(0.24, 0.441, -(beyond + 0.02)), 0.135, 0.004, Color(0.02, 0.02, 0.02))
	for k: int in 3:
		_box(frame, Vector3(0.24 + _rng.randf_range(-0.06, 0.06), 0.447 + float(k) * 0.004, -(beyond + _rng.randf_range(-0.05, 0.08))),
			Vector3(0.1, 0.004, 0.11), PAPER, _rng.randf() * TAU)


func _fit_urinals(frame: Transform3D, width: float) -> void:
	for k: int in 3:
		var d: float = 2.4 + float(k) * 0.8
		# The urinal models carry their own flush valve and drain (the old
		# placeholder capsule needed a pipe up the wall and a drain cover here,
		# which now stuck out of the bowl), so only the divider facing remains.
		if k < 2:
			_box(frame, Vector3(width - 0.31, 0.9, -(d + 0.4)), Vector3(0.56, 1.24, 0.06), Color(0.25, 0.32, 0.36))
	_box(frame, Vector3(width - 0.55, 0.003, -3.2), Vector3(0.1, 0.005, 1.9), Color(0.2, 0.2, 0.21))


# ----------------------------------------------------------------- keyboards

## The generator puts every keyboard 30 cm in front of its monitor, whatever
## it is standing on. On the narrow service counters that leaves it hanging in
## the air. Each one is slid the shortest distance that puts all four corners
## on something solid.
func _seat_keyboards(school: Node) -> void:
	var instance := school.get_node_or_null("Visual/Mesh_dark") as MeshInstance3D
	if instance == null or instance.mesh == null or instance.mesh.get_surface_count() != 1:
		return
	var arrays: Array = instance.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var to_world: Transform3D = instance.global_transform
	var moved: int = 0
	# The mesh is a list of boxes, 24 vertices each.
	for start: int in range(0, vertices.size() - 23, 24):
		var box := AABB(vertices[start], Vector3.ZERO)
		for i: int in range(start, start + 24):
			box = box.expand(vertices[i])
		var size: Vector3 = box.size
		var is_keyboard: bool = absf(size.y - 0.02) < 0.002 \
			and ((absf(size.x - 0.44) < 0.005 and absf(size.z - 0.14) < 0.005) or (absf(size.x - 0.14) < 0.005 and absf(size.z - 0.44) < 0.005))
		if not is_keyboard or _is_supported(space, to_world, box, Vector3.ZERO):
			continue
		var best := Vector3.ZERO
		var best_distance: float = INF
		for ix: int in range(-16, 17):
			for iz: int in range(-16, 17):
				var shift := Vector3(float(ix) * 0.03, 0.0, float(iz) * 0.03)
				if shift.length() < best_distance and _is_supported(space, to_world, box, shift):
					best = shift
					best_distance = shift.length()
		if best_distance == INF:
			continue
		for i: int in range(start, start + 24):
			vertices[i] += best
		moved += 1
	if moved == 0:
		return
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var rebuilt := ArrayMesh.new()
	rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	rebuilt.surface_set_material(0, instance.mesh.surface_get_material(0))
	instance.mesh = rebuilt


## True when something solid lies directly under all four corners of `box`
## (shifted by `shift`), at the height the box is resting at.
func _is_supported(space: PhysicsDirectSpaceState3D, to_world: Transform3D, box: AABB, shift: Vector3) -> bool:
	for fx: float in [0.04, 0.96]:
		for fz: float in [0.04, 0.96]:
			var from: Vector3 = to_world * (Vector3(box.position.x + box.size.x * fx, box.end.y + 0.05, box.position.z + box.size.z * fz) + shift)
			var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 0.1, 1))
			if hit.is_empty():
				return false
			var point: Vector3 = hit["position"]
			if point.y < from.y - 0.085:
				return false
	return true


# -------------------------------------------------------------------- windows

## The jalousie slats are saved in the building scene with a pale, fairly
## opaque blue material. From indoors the flashlight turns that into a flat
## milky panel. Real glass at night is nearly black: you see the dark through
## it, the grime on it, and the glint of your own light.
func _clear_window_glass(school: Node) -> void:
	var interactive: Node = school.get_node_or_null("Interactive")
	if interactive == null:
		return
	var done: Dictionary = {}
	for window: Node in interactive.get_children():
		var slats: Node = window.get_node_or_null("Slats")
		if slats == null:
			continue
		for node: Node in slats.get_children():
			var slat := node as MeshInstance3D
			if slat == null:
				continue
			var glass := slat.get_active_material(0) as StandardMaterial3D
			if glass == null or done.has(glass):
				continue
			done[glass] = true
			glass.albedo_color = Color(0.2, 0.27, 0.28, 0.12)
			glass.roughness = 0.05
			glass.metallic_specular = 0.8


# ------------------------------------------------------------------- planters

## The planting outside the ground-floor windows is built as flat mint-green
## blocks, which is what you see through the glass from the front offices.
## Each block is replaced by an overgrown clump of dark shrubs.
func _grow_planters(school: Node) -> void:
	var blocks := school.get_node_or_null("Visual/Mesh_plant") as MeshInstance3D
	if blocks == null or blocks.mesh == null:
		return
	var faces: PackedVector3Array = blocks.mesh.get_faces()
	var to_world: Transform3D = blocks.global_transform
	var leaf := StandardMaterial3D.new()
	leaf.vertex_color_use_as_albedo = true
	leaf.vertex_color_is_srgb = true
	leaf.roughness = 0.9
	var clump := SphereMesh.new()
	clump.radius = 0.5
	clump.height = 1.0
	clump.radial_segments = 7
	clump.rings = 4
	clump.material = leaf
	var transforms: Array = []
	var colours: Array = []
	# One box is 12 triangles, 36 vertices.
	for start: int in range(0, faces.size(), 36):
		var box := AABB(to_world * faces[start], Vector3.ZERO)
		for i: int in range(start, mini(start + 36, faces.size())):
			box = box.expand(to_world * faces[i])
		_rng.seed = hash(box.position.snappedf(0.05))
		for k: int in int(box.size.x * 22.0):
			var radius: float = _rng.randf_range(0.11, 0.24)
			var at := Vector3(_rng.randf_range(box.position.x + 0.08, box.end.x - 0.08),
				box.position.y + _rng.randf_range(0.05, box.size.y + 0.22),
				_rng.randf_range(box.position.z + 0.06, box.end.z - 0.06))
			var squash := Vector3(radius * 2.0, radius * _rng.randf_range(1.3, 2.0), radius * 2.0)
			transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled_local(squash), at))
			colours.append(Color(0.05, 0.13, 0.06).lerp(Color(0.12, 0.2, 0.07), _rng.randf()))
	blocks.visible = false
	_add_multimesh("Shrubs", clump, transforms, colours)


# -------------------------------------------------------------------- shelves

func _fill_steel_shelves(prop: Node3D) -> void:
	var frame: Transform3D = _frame_of(prop)
	_rng.seed = hash(frame.origin.snappedf(0.05))
	var room_type: String = _room_type(frame.origin)
	var food: bool = room_type in ["pantry", "kitchen", "dining"]
	for i: int in STEEL_SHELF_LEVELS.size():
		if food:
			_row_of_food(frame, STEEL_SHELF_LEVELS[i], 0.5, STEEL_SHELF_CLEARANCE)
		else:
			_row_of_records(frame, STEEL_SHELF_LEVELS[i], 0.5, STEEL_SHELF_CLEARANCE)


func _fill_bookcase(prop: Node3D) -> void:
	var frame: Transform3D = _frame_of(prop)
	_rng.seed = hash(frame.origin.snappedf(0.05))
	for i: int in BOOKCASE_LEVELS.size():
		_row_of_books(frame, BOOKCASE_LEVELS[i], 0.6, BOOKCASE_CLEARANCE[i])


## Archive boxes with a paper label, runs of lever-arch binders, and gaps.
func _row_of_records(frame: Transform3D, y: float, half_width: float, clearance: float) -> void:
	var x: float = -half_width + _rng.randf_range(0.01, 0.06)
	while x < half_width - 0.08:
		var roll: float = _rng.randf()
		if roll < 0.42:
			var size := Vector3(_rng.randf_range(0.3, 0.35), minf(_rng.randf_range(0.24, 0.27), clearance - 0.04), 0.39)
			if x + size.x > half_width:
				break
			var at := Vector3(x + size.x * 0.5, y + size.y * 0.5, _rng.randf_range(-0.02, 0.02))
			var yaw: float = _rng.randf_range(-0.04, 0.04)
			_box(frame, at, size, _pick(CARDBOARD), yaw)
			# A darker lid, and a label on each open side of the shelving.
			_box(frame, at + Vector3(0.0, size.y * 0.5 - 0.02, 0.0), Vector3(size.x + 0.012, 0.045, size.z + 0.012),
				_pick(CARDBOARD).darkened(0.18), yaw)
			for face: float in [-1.0, 1.0]:
				_box(frame, at + Vector3(0.0, -0.01, face * (size.z * 0.5 + 0.003)), Vector3(0.15, 0.08, 0.003), PAPER, yaw)
			x += size.x + _rng.randf_range(0.01, 0.05)
		elif roll < 0.8:
			var colour: Color = _pick(BINDERS)
			for k: int in _rng.randi_range(3, 7):
				var width: float = _rng.randf_range(0.05, 0.078)
				if x + width > half_width:
					break
				var height: float = minf(_rng.randf_range(0.3, 0.32), clearance - 0.03)
				var at := Vector3(x + width * 0.5, y + height * 0.5, _rng.randf_range(-0.015, 0.015))
				if _rng.randf() < 0.25:
					colour = _pick(BINDERS)
				_box(frame, at, Vector3(width - 0.004, height, 0.28), colour)
				for face: float in [-1.0, 1.0]:
					_box(frame, at + Vector3(0.0, height * 0.18, face * 0.142), Vector3(width * 0.62, 0.1, 0.003), PAPER)
				x += width
			x += _rng.randf_range(0.0, 0.04)
		else:
			# A loose pile of folders lying flat, or nothing.
			if _rng.randf() < 0.5 and x + 0.32 < half_width:
				var pile: float = 0.0
				for k: int in _rng.randi_range(2, 6):
					var thick: float = _rng.randf_range(0.008, 0.03)
					_box(frame, Vector3(x + 0.16 + _rng.randf_range(-0.015, 0.015), y + pile + thick * 0.5, _rng.randf_range(-0.03, 0.03)),
						Vector3(0.23, thick, 0.31), PAPER.darkened(_rng.randf_range(0.0, 0.3)), _rng.randf_range(-0.2, 0.2))
					pile += thick
				x += 0.3
			x += _rng.randf_range(0.08, 0.22)


## Rice sacks, stacked cans, bottles and delivery boxes.
func _row_of_food(frame: Transform3D, y: float, half_width: float, clearance: float) -> void:
	var x: float = -half_width + _rng.randf_range(0.01, 0.06)
	while x < half_width - 0.08:
		var roll: float = _rng.randf()
		if roll < 0.22:
			# Sacks slump: two or three flat, one on another.
			var width: float = _rng.randf_range(0.34, 0.4)
			if x + width > half_width:
				break
			var pile: float = 0.0
			for k: int in _rng.randi_range(1, 3):
				var thick: float = _rng.randf_range(0.1, 0.13)
				if pile + thick > clearance - 0.03:
					break
				_box(frame, Vector3(x + width * 0.5 + _rng.randf_range(-0.01, 0.01), y + pile + thick * 0.5, _rng.randf_range(-0.02, 0.02)),
					Vector3(width, thick, 0.4), _pick(SACKS), _rng.randf_range(-0.06, 0.06))
				pile += thick
			x += width + _rng.randf_range(0.02, 0.06)
		elif roll < 0.55:
			# Cans, three deep, some stacked two high.
			var radius: float = _rng.randf_range(0.037, 0.05)
			var height: float = radius * _rng.randf_range(2.2, 2.9)
			var colour: Color = _pick(CANS)
			for column: int in _rng.randi_range(2, 4):
				if x + radius * 2.0 > half_width:
					break
				for depth: int in 3:
					if _rng.randf() < 0.12:
						continue
					var z: float = (float(depth) - 1.0) * (radius * 2.0 + 0.012)
					for layer: int in (2 if _rng.randf() < 0.45 and height * 2.0 < clearance - 0.03 else 1):
						var at := Vector3(x + radius, y + height * (float(layer) + 0.5), z)
						_cylinder(frame, at, radius, height, Color(0.6, 0.6, 0.58))
						_cylinder(frame, at, radius + 0.0015, height * 0.72, colour)
				x += radius * 2.0 + 0.008
			x += _rng.randf_range(0.02, 0.06)
		elif roll < 0.75:
			var colour: Color = _pick(BOTTLES)
			for column: int in _rng.randi_range(2, 5):
				if x + 0.08 > half_width:
					break
				for depth: int in 2:
					if _rng.randf() < 0.2:
						continue
					var at := Vector3(x + 0.04, y, (float(depth) - 0.5) * 0.11)
					var height: float = _rng.randf_range(0.2, 0.25)
					_cylinder(frame, at + Vector3(0.0, height * 0.5, 0.0), 0.034, height, colour)
					_cylinder(frame, at + Vector3(0.0, height + 0.035, 0.0), 0.013, 0.07, colour)
					_cylinder(frame, at + Vector3(0.0, height + 0.075, 0.0), 0.015, 0.014, Color(0.5, 0.42, 0.12))
					_cylinder(frame, at + Vector3(0.0, height * 0.5, 0.0), 0.0355, height * 0.42, PAPER.darkened(0.1))
				x += 0.085
			x += _rng.randf_range(0.02, 0.06)
		elif roll < 0.9:
			var size := Vector3(_rng.randf_range(0.26, 0.36), minf(_rng.randf_range(0.18, 0.3), clearance - 0.04), _rng.randf_range(0.28, 0.38))
			if x + size.x > half_width:
				break
			_box(frame, Vector3(x + size.x * 0.5, y + size.y * 0.5, _rng.randf_range(-0.03, 0.03)), size, _pick(CARDBOARD),
				_rng.randf_range(-0.08, 0.08))
			# Packing tape across the flaps.
			_box(frame, Vector3(x + size.x * 0.5, y + size.y + 0.001, 0.0), Vector3(size.x * 0.98, 0.002, 0.05), Color(0.6, 0.5, 0.3))
			x += size.x + _rng.randf_range(0.02, 0.06)
		else:
			x += _rng.randf_range(0.1, 0.28)


## Books upright with the odd one leaning into a gap, and a flat stack or two.
func _row_of_books(frame: Transform3D, y: float, half_width: float, clearance: float) -> void:
	var x: float = -half_width + 0.01
	while x < half_width - 0.03:
		var roll: float = _rng.randf()
		if roll < 0.74:
			for k: int in _rng.randi_range(4, 14):
				var width: float = _rng.randf_range(0.018, 0.05)
				if x + width > half_width:
					break
				var height: float = clearance * _rng.randf_range(0.62, 0.93)
				var depth: float = _rng.randf_range(0.14, 0.2)
				_box(frame, Vector3(x + width * 0.5, y + height * 0.5, 0.2 - depth * 0.5 - _rng.randf_range(0.0, 0.02)),
					Vector3(width - 0.002, height, depth), _pick(BOOKS).darkened(_rng.randf_range(0.0, 0.35)))
				x += width
			# The last one in a run has fallen against its neighbours.
			if _rng.randf() < 0.5 and x + 0.1 < half_width:
				var height: float = clearance * 0.8
				_box(frame, Vector3(x + 0.045, y + height * 0.47, 0.1), Vector3(0.03, height, 0.17), _pick(BOOKS).darkened(0.2), 0.0, 0.3)
				x += 0.1
		elif roll < 0.86 and x + 0.24 < half_width:
			var pile: float = 0.0
			for k: int in _rng.randi_range(2, 5):
				var thick: float = _rng.randf_range(0.02, 0.045)
				if pile + thick > clearance - 0.02:
					break
				_box(frame, Vector3(x + 0.11, y + pile + thick * 0.5, 0.08), Vector3(0.21, thick, 0.15), _pick(BOOKS).darkened(0.2),
					_rng.randf_range(-0.15, 0.15))
				pile += thick
			x += 0.24
		else:
			x += _rng.randf_range(0.05, 0.16)


# -------------------------------------------------------------------- batches

## The prop's placement without its import scale.
func _frame_of(prop: Node3D) -> Transform3D:
	return Transform3D(prop.global_transform.basis.orthonormalized(), prop.global_position)


func _room_type(at: Vector3) -> String:
	var room_id: int = Campus.room_id_at(at + Vector3.UP * 0.5)
	for room: Dictionary in Campus.ROOMS:
		if room["id"] == room_id:
			return room["type"]
	return ""


func _pick(palette: Array[Color]) -> Color:
	return palette[_rng.randi_range(0, palette.size() - 1)]


func _batch(world: Vector3) -> Dictionary:
	var floor_index: int = Campus.floor_from_y(world.y)
	if not _batches.has(floor_index):
		_batches[floor_index] = {"box_xf": [], "box_col": [], "cyl_xf": [], "cyl_col": []}
	return _batches[floor_index]


func _near_loot(world: Vector3) -> bool:
	for spot: Vector3 in _loot:
		if spot.distance_squared_to(world) < LOOT_CLEARANCE * LOOT_CLEARANCE:
			return true
	return false


func _box(frame: Transform3D, at: Vector3, size: Vector3, colour: Color, yaw: float = 0.0, lean: float = 0.0) -> void:
	var world: Vector3 = frame * at
	if _near_loot(world):
		return
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, lean)
	var batch: Dictionary = _batch(world)
	batch["box_xf"].append(frame * Transform3D(basis.scaled_local(size), at))
	batch["box_col"].append(colour)


## `tilt` turns the cylinder's axis away from vertical (it is applied before
## the room or prop frame).
func _cylinder(frame: Transform3D, at: Vector3, radius: float, height: float, colour: Color, tilt: Basis = Basis.IDENTITY) -> void:
	var world: Vector3 = frame * at
	if _near_loot(world):
		return
	var batch: Dictionary = _batch(world)
	batch["cyl_xf"].append(frame * Transform3D(tilt.scaled_local(Vector3(radius * 2.0, height, radius * 2.0)), at))
	batch["cyl_col"].append(colour)


## One MultiMesh of boxes and one of cylinders per floor, so a floor Juan is
## not on is culled as a whole.
func _commit() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.82
	var unit_box := BoxMesh.new()
	unit_box.size = Vector3.ONE
	unit_box.material = material
	var unit_cylinder := CylinderMesh.new()
	unit_cylinder.top_radius = 0.5
	unit_cylinder.bottom_radius = 0.5
	unit_cylinder.height = 1.0
	unit_cylinder.radial_segments = 10
	unit_cylinder.rings = 1
	unit_cylinder.material = material
	for floor_index: int in _batches:
		var batch: Dictionary = _batches[floor_index]
		_add_multimesh("Clutter%dF" % (floor_index + 1), unit_box, batch["box_xf"], batch["box_col"])
		_add_multimesh("Cans%dF" % (floor_index + 1), unit_cylinder, batch["cyl_xf"], batch["cyl_col"])
	_batches.clear()


func _add_multimesh(node_name: String, mesh: Mesh, transforms: Array, colours: Array) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i: int in transforms.size():
		var transform: Transform3D = transforms[i]
		var colour: Color = colours[i]
		multimesh.set_instance_transform(i, transform)
		multimesh.set_instance_color(i, colour)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	add_child(instance)
