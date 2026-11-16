class_name DoorDressing
extends RefCounted
## Fits out a bare door leaf: raised moulded panels, steel kick plates, a
## lever on a round rose on both faces, a keyhole outside and a thumb-turn
## inside, three hinges, and wear round the lever. Also builds what Juan
## barricades the door with: the plastic chair jammed under the lever, and
## LAN cable wound round it.
##
## Leaf space (the "Leaf" node): X runs from the hinge (0) to the latch edge
## (door width), Y up from the floor, Z through the leaf (thickness centred
## on 0). `inward` is the sign of Z on the room side.

const THICKNESS: float = 0.05
const HANDLE_HEIGHT: float = 0.95
const HANDLE_INSET: float = 0.085
const LEVER_LENGTH: float = 0.13

static var _materials: Dictionary = {}


## Adds the hardware to `leaf`. Returns the thumb-turn so the door can turn
## it to show it is locked.
## `panels`: add the raised moulded panels (only on the generator's plain box
## slab; a modelled leaf has its own faces).
static func dress(leaf: Node3D, width: float, height: float, gap: float, inward: float, swing: float, wood: Material, seed: float, panels: bool = true) -> Node3D:
	var face: float = THICKNESS * 0.5
	var trim: Material = _shaded(wood, 0.82)
	var steel: Material = _material(&"steel")
	var brushed: Material = _material(&"brushed")
	for side: float in [-1.0, 1.0]:
		var z: float = side * face
		# Two raised panels, each a moulded frame round a slightly darker field.
		if panels:
			for panel: Array in [[gap + 0.3, gap + 0.95], [1.15, height - 0.17]]:
				_panel(leaf, Vector2(0.14, panel[0]), Vector2(width - 0.14, panel[1]), z, side, wood, trim)
		# Brushed steel kick plate.
		_box(leaf, Vector3(width * 0.5, gap + 0.11, z + side * 0.0015), Vector3(width - 0.06, 0.2, 0.003), brushed)
		# Rose and lever, pointing back towards the hinge.
		var rose_at := Vector3(width - HANDLE_INSET, HANDLE_HEIGHT, z)
		_cylinder(leaf, rose_at + Vector3(0.0, 0.0, side * 0.006), 0.03, 0.012, steel, Basis(Vector3.RIGHT, PI * 0.5))
		var lever: Array[Vector3] = [
			rose_at + Vector3(0.0, 0.0, side * 0.01),
			rose_at + Vector3(0.0, 0.0, side * 0.05),
			rose_at + Vector3(-0.015, 0.0, side * 0.062),
			rose_at + Vector3(-0.04, 0.0, side * 0.066),
			rose_at + Vector3(-LEVER_LENGTH, -0.006, side * 0.064),
		]
		_mesh(leaf, TubeMesh.build(lever, 0.0095, 12), steel)
		_sphere(leaf, lever[-1], 0.0105, steel)
	# Keyhole escutcheon outside, thumb-turn inside.
	var outside: float = -inward
	var esc_at := Vector3(width - HANDLE_INSET, HANDLE_HEIGHT - 0.1, outside * (face + 0.003))
	_box(leaf, esc_at, Vector3(0.04, 0.07, 0.006), steel)
	_box(leaf, esc_at + Vector3(0.0, 0.006, outside * 0.0035), Vector3(0.007, 0.012, 0.002), _material(&"dark"))
	_box(leaf, esc_at + Vector3(0.0, -0.006, outside * 0.0035), Vector3(0.003, 0.016, 0.002), _material(&"dark"))
	var turn_at := Vector3(width - HANDLE_INSET, HANDLE_HEIGHT - 0.1, inward * (face + 0.003))
	_cylinder(leaf, turn_at, 0.022, 0.006, steel, Basis(Vector3.RIGHT, PI * 0.5))
	var thumb := Node3D.new()
	thumb.name = "ThumbTurn"
	thumb.position = turn_at + Vector3(0.0, 0.0, inward * 0.008)
	leaf.add_child(thumb)
	# Long enough to read past the rose: upright = open, across = locked.
	_box(thumb, Vector3.ZERO, Vector3(0.014, 0.056, 0.014), _material(&"dark_steel"))
	# Three butt hinges on the edge the door swings towards.
	for y: float in [gap + 0.18, height * 0.55, height - 0.2]:
		_cylinder(leaf, Vector3(0.0, y, swing * face), 0.008, 0.1, steel)
		_box(leaf, Vector3(0.012, y, swing * (face + 0.001)), Vector3(0.024, 0.1, 0.002), steel)
	# Wear over the slab the generator built.
	var slab := leaf.get_node_or_null("Mesh") as MeshInstance3D
	if slab != null and slab.mesh != null:
		var wear := ShaderMaterial.new()
		wear.shader = preload("res://shaders/door_wear.gdshader")
		wear.set_shader_parameter(&"handle_local", Vector2(width - HANDLE_INSET - LEVER_LENGTH * 0.4, HANDLE_HEIGHT) - Vector2(slab.position.x, slab.position.y))
		wear.set_shader_parameter(&"leaf_bottom", gap - slab.position.y)
		wear.set_shader_parameter(&"seed", seed)
		var worn: Material = (slab.mesh.surface_get_material(0) if slab.mesh.get_surface_count() > 0 else wood).duplicate()
		worn.next_pass = wear
		slab.material_override = worn
	return thumb


# -------------------------------------------------------------------- helpers

static func _panel(leaf: Node3D, lo: Vector2, hi: Vector2, z: float, side: float, wood: Material, trim: Material) -> void:
	var size: Vector2 = hi - lo
	var mid: Vector2 = (lo + hi) * 0.5
	var bead: float = 0.028
	var proud: float = 0.007
	# Field, very slightly proud and darker, then the moulding round it.
	_box(leaf, Vector3(mid.x, mid.y, z + side * 0.0015), Vector3(size.x - bead, size.y - bead, 0.003), trim)
	_box(leaf, Vector3(mid.x, lo.y, z + side * proud * 0.5), Vector3(size.x + bead, bead, proud), wood)
	_box(leaf, Vector3(mid.x, hi.y, z + side * proud * 0.5), Vector3(size.x + bead, bead, proud), wood)
	_box(leaf, Vector3(lo.x, mid.y, z + side * proud * 0.5), Vector3(bead, size.y - bead, proud), wood)
	_box(leaf, Vector3(hi.x, mid.y, z + side * proud * 0.5), Vector3(bead, size.y - bead, proud), wood)


static func _shaded(base: Material, factor: float) -> Material:
	var key := StringName("wood_%d_%.2f" % [base.get_instance_id(), factor])
	if _materials.has(key):
		return _materials[key]
	var m: Material = base.duplicate()
	if m is BaseMaterial3D:
		(m as BaseMaterial3D).albedo_color = (m as BaseMaterial3D).albedo_color * Color(factor, factor, factor, 1.0)
	_materials[key] = m
	return m


static func _material(key: StringName) -> Material:
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	match key:
		&"steel":
			m.albedo_color = Color(0.74, 0.74, 0.76)
			m.metallic = 0.75
			m.roughness = 0.28
		&"brushed":
			m.albedo_color = Color(0.6, 0.6, 0.62)
			m.metallic = 0.7
			m.roughness = 0.42
			m.anisotropy_enabled = true
			m.anisotropy = 0.7
		&"dark_steel":
			m.albedo_color = Color(0.32, 0.32, 0.34)
			m.metallic = 0.7
			m.roughness = 0.35
		&"dark":
			m.albedo_color = Color(0.02, 0.02, 0.02)
			m.roughness = 0.9
		&"cable":
			m.albedo_color = Color(0.12, 0.32, 0.78)
			m.roughness = 0.45
			m.clearcoat_enabled = true
			m.clearcoat = 0.3
		&"plug":
			m.albedo_color = Color(0.85, 0.87, 0.88, 0.75)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.2
	_materials[key] = m
	return m


static func _mesh(parent: Node3D, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


static func _box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := _mesh(parent, box, material)
	instance.position = at
	return instance


static func _cylinder(parent: Node3D, at: Vector3, radius: float, tall: float, material: Material, basis := Basis.IDENTITY) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = tall
	cylinder.radial_segments = 20
	var instance := _mesh(parent, cylinder, material)
	instance.transform = Transform3D(basis, at)
	return instance


static func _sphere(parent: Node3D, at: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	var instance := _mesh(parent, sphere, material)
	instance.position = at
	return instance
