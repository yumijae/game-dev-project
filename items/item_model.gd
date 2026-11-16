class_name ItemModel
extends RefCounted
## Builds the object you actually see for a pickup: a bottle with a neck and
## a cap, a coil of cable, a candle with a wick - instead of a tinted block.
## Each is a few primitives sized from the item's entry in ItemDB, standing
## on the origin.

const CHAIR_SCENE: String = "res://models/polyhaven/plastic_monobloc_chair_01/plastic_monobloc_chair_01.gltf"
const BOTTLES: Array[StringName] = [ItemDB.GLASS_BOTTLE, ItemDB.WATER, ItemDB.ALCOHOL]
const CLEAR_BOTTLES: Array[StringName] = [ItemDB.GLASS_BOTTLE, ItemDB.WATER]
const STEEL: Color = Color(0.5, 0.51, 0.53)


static func build(item_id: StringName) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var size: Vector3 = ItemDB.get_size(item_id)
	var colour: Color = ItemDB.get_color(item_id)
	if item_id in BOTTLES:
		_bottle(root, size, colour, item_id in CLEAR_BOTTLES)
	elif item_id == ItemDB.FIRE_EXTINGUISHER:
		var r: float = size.x * 0.5
		_cylinder(root, Vector3(0.0, size.y * 0.42, 0.0), r, size.y * 0.84, colour, 0.35, 0.3)
		_sphere(root, Vector3(0.0, size.y * 0.84, 0.0), r * 0.98, colour, 0.35)
		_box(root, Vector3(0.0, size.y * 0.5, r + 0.001), Vector3(r * 1.3, size.y * 0.28, 0.002), Color(0.92, 0.9, 0.85), 0.8)
		_cylinder(root, Vector3(0.0, size.y * 0.95, 0.0), r * 0.32, size.y * 0.1, STEEL, 0.4, 0.8)
		var lever: MeshInstance3D = _box(root, Vector3(0.03, size.y + 0.012, 0.0), Vector3(0.09, 0.012, 0.022), Color(0.12, 0.12, 0.13), 0.5)
		lever.rotation.z = -0.25
		var hose: MeshInstance3D = _cylinder(root, Vector3(-r - 0.008, size.y * 0.62, 0.0), 0.009, size.y * 0.5, Color(0.08, 0.08, 0.08), 0.8)
		hose.rotation.z = 0.08
		_cylinder(root, Vector3(-r - 0.02, size.y * 0.36, 0.0), 0.02, 0.07, Color(0.08, 0.08, 0.08), 0.7)
	elif item_id == ItemDB.SCREWDRIVER:
		var grip: MeshInstance3D = _cylinder(root, Vector3(-0.05, 0.013, 0.0), 0.013, 0.1, colour, 0.6)
		grip.rotation.z = PI * 0.5
		var shaft: MeshInstance3D = _cylinder(root, Vector3(0.05, 0.013, 0.0), 0.0035, 0.1, STEEL, 0.3, 0.9)
		shaft.rotation.z = PI * 0.5
		_box(root, Vector3(0.101, 0.013, 0.0), Vector3(0.006, 0.002, 0.007), STEEL, 0.3, 0.9)
	elif item_id == ItemDB.TRIPWIRE:
		var coil := TorusMesh.new()
		coil.outer_radius = 0.06
		coil.inner_radius = 0.05
		_part(root, coil, Vector3(0.0, 0.006, 0.0), ItemDB.get_color(ItemDB.LAN_CABLE), 0.6)
		_bottle(root, Vector3(0.06, 0.18, 0.06), ItemDB.get_color(ItemDB.GLASS_BOTTLE), true)
	elif item_id == ItemDB.TABLECLOTH_RAG:
		for i: int in 3:
			var fold: MeshInstance3D = _box(root, Vector3(0.0, 0.005 + float(i) * 0.009, 0.0),
				Vector3(size.x * (1.0 - float(i) * 0.12), 0.009, size.z * (1.0 - float(i) * 0.08)), colour.darkened(float(i) * 0.05), 0.95)
			fold.rotation.y = float(i) * 0.14
	elif item_id == ItemDB.GAUZE:
		var roll: MeshInstance3D = _cylinder(root, Vector3(0.0, size.x * 0.5, 0.0), size.x * 0.5, size.y, colour, 0.95)
		roll.rotation.z = PI * 0.5
		var core: MeshInstance3D = _cylinder(root, Vector3(0.0, size.x * 0.5, 0.0), size.x * 0.16, size.y + 0.002, Color(0.55, 0.45, 0.3), 0.9)
		core.rotation.z = PI * 0.5
	elif item_id == ItemDB.LAN_CABLE:
		for i: int in 3:
			var coil := TorusMesh.new()
			coil.outer_radius = size.x * 0.5 - float(i) * 0.004
			coil.inner_radius = coil.outer_radius - 0.011
			coil.rings = 20
			coil.ring_segments = 6
			_part(root, coil, Vector3(float(i) * 0.004, 0.006 + float(i) * 0.011, 0.0), colour, 0.6)
		_box(root, Vector3(size.x * 0.5, 0.008, 0.02), Vector3(0.022, 0.012, 0.012), Color(0.85, 0.85, 0.8, 0.8), 0.3)
	elif item_id == ItemDB.BLACKOUT_KIT:
		for i: int in 3:
			var sheet: MeshInstance3D = _box(root, Vector3(0.0, 0.002 + float(i) * 0.003, 0.0), Vector3(size.x, 0.002, size.z), colour, 0.9)
			sheet.rotation.y = float(i) * 0.05
		var tape := TorusMesh.new()
		tape.outer_radius = 0.05
		tape.inner_radius = 0.034
		tape.rings = 18
		tape.ring_segments = 4
		var roll: MeshInstance3D = _part(root, tape, Vector3(0.03, 0.03, 0.05), Color(0.45, 0.34, 0.18), 0.4)
		roll.scale.y = 2.6
	elif item_id == ItemDB.REHAS_KEY:
		var ring := TorusMesh.new()
		ring.outer_radius = 0.02
		ring.inner_radius = 0.016
		_part(root, ring, Vector3(-0.03, 0.003, 0.0), STEEL, 0.35, 0.9)
		_box(root, Vector3(0.012, 0.003, 0.0), Vector3(0.05, 0.003, 0.007), colour, 0.35, 0.9)
		_box(root, Vector3(0.03, 0.003, 0.006), Vector3(0.012, 0.003, 0.008), colour, 0.35, 0.9)
		var bow: MeshInstance3D = _cylinder(root, Vector3(-0.012, 0.003, 0.0), 0.011, 0.003, colour, 0.35, 0.9)
		bow.scale.x = 1.2
	elif item_id == ItemDB.BOLT_CUTTERS:
		for side: float in [-1.0, 1.0]:
			var arm: MeshInstance3D = _cylinder(root, Vector3(-0.06, 0.012, side * 0.025), 0.009, 0.34, STEEL, 0.4, 0.9)
			arm.rotation = Vector3(0.0, side * 0.09, PI * 0.5)
			var grip: MeshInstance3D = _cylinder(root, Vector3(-0.16, 0.012, side * 0.034), 0.013, 0.15, colour, 0.7)
			grip.rotation = Vector3(0.0, side * 0.09, PI * 0.5)
			_box(root, Vector3(0.19, 0.012, side * 0.012), Vector3(0.07, 0.016, 0.018), STEEL.darkened(0.3), 0.4, 0.9)
		_cylinder(root, Vector3(0.13, 0.012, 0.0), 0.02, 0.02, STEEL.darkened(0.2), 0.4, 0.9)
	elif item_id == ItemDB.CROWBAR:
		var shaft: MeshInstance3D = _cylinder(root, Vector3(0.0, 0.011, 0.0), 0.011, size.x - 0.08, colour, 0.5, 0.8)
		shaft.rotation.z = PI * 0.5
		var hook: MeshInstance3D = _cylinder(root, Vector3(size.x * 0.5 - 0.035, 0.011, 0.03), 0.011, 0.08, colour, 0.5, 0.8)
		hook.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		var claw: MeshInstance3D = _box(root, Vector3(-size.x * 0.5 + 0.02, 0.009, 0.0), Vector3(0.07, 0.007, 0.028), colour.darkened(0.2), 0.45, 0.8)
		claw.rotation.z = -0.2
	elif item_id == ItemDB.POWERBANK:
		_box(root, Vector3(0.0, size.y * 0.5, 0.0), size, colour, 0.35)
		_box(root, Vector3(0.0, size.y + 0.0005, size.z * 0.3), Vector3(size.x * 0.5, 0.001, 0.006), Color(0.2, 0.6, 0.9), 0.3)
		_box(root, Vector3(0.0, size.y * 0.5, -size.z * 0.5), Vector3(0.013, 0.006, 0.002), STEEL, 0.3, 0.9)
	elif item_id == ItemDB.CHAIR and ResourceLoader.exists(CHAIR_SCENE):
		var scene: PackedScene = load(CHAIR_SCENE)
		root.add_child(scene.instantiate())
	else:
		_box(root, Vector3(0.0, size.y * 0.5, 0.0), size, colour, 0.6)
	return root


## Body, shoulder, neck and cap; clear glass for the empty and the water bottle.
static func _bottle(root: Node3D, size: Vector3, colour: Color, clear: bool) -> void:
	var radius: float = size.x * 0.5
	var body_height: float = size.y * 0.6
	var glass: Color = colour
	if clear:
		glass = Color(colour.r, colour.g, colour.b, 0.38)
	_cylinder(root, Vector3(0.0, body_height * 0.5, 0.0), radius, body_height, glass, 0.12)
	var shoulder := CylinderMesh.new()
	shoulder.bottom_radius = radius
	shoulder.top_radius = radius * 0.36
	shoulder.height = size.y * 0.16
	shoulder.radial_segments = 14
	_part(root, shoulder, Vector3(0.0, body_height + size.y * 0.08, 0.0), glass, 0.12)
	_cylinder(root, Vector3(0.0, size.y * 0.85, 0.0), radius * 0.36, size.y * 0.2, glass, 0.12)
	_cylinder(root, Vector3(0.0, size.y * 0.97, 0.0), radius * 0.42, size.y * 0.06, Color(0.75, 0.74, 0.7) if clear else colour.darkened(0.5), 0.5)
	# A paper label, except on the flask of oil.
	if size.y > 0.16:
		_cylinder(root, Vector3(0.0, body_height * 0.5, 0.0), radius + 0.0008, body_height * 0.5, Color(0.82, 0.8, 0.72), 0.9)


static func _box(root: Node3D, at: Vector3, size: Vector3, colour: Color, roughness: float, metallic: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _part(root, mesh, at, colour, roughness, metallic)


static func _cylinder(root: Node3D, at: Vector3, radius: float, height: float, colour: Color, roughness: float,
		metallic: float = 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	return _part(root, mesh, at, colour, roughness, metallic)


static func _sphere(root: Node3D, at: Vector3, radius: float, colour: Color, roughness: float) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	return _part(root, mesh, at, colour, roughness)


static func _part(root: Node3D, mesh: Mesh, at: Vector3, colour: Color, roughness: float, metallic: float = 0.0) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = roughness
	material.metallic = metallic
	if colour.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	root.add_child(part)
	return part
