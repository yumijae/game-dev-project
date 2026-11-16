class_name HeavyProp
extends StaticBody3D
## A heavy piece of furniture (a CPU tower, a thesis stack, a spare desk).
## It used to be a door barricade; now it is just scenery that blocks the way.

const LAYER_INTERACT: int = 2
const LAYER_DOORS: int = 8

@export var prop_name: String = "CPU Tower"
@export var size: Vector3 = Vector3(0.22, 0.46, 0.48)
@export var color: Color = Color(0.12, 0.12, 0.14)


## Builds the prop with its collision and a simple mesh.
static func create(label: String, prop_size: Vector3, prop_color: Color) -> HeavyProp:
	var prop := HeavyProp.new()
	prop.prop_name = label
	prop.size = prop_size
	prop.color = prop_color
	prop.collision_layer = LAYER_INTERACT | LAYER_DOORS
	prop.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = prop_size
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position.y = prop_size.y * 0.5
	prop.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = prop_size
	var material := StandardMaterial3D.new()
	material.albedo_color = prop_color
	material.roughness = 0.7
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	instance.position.y = prop_size.y * 0.5
	prop.add_child(instance)
	return prop


func _ready() -> void:
	add_to_group(&"heavy_props")
	# Fixed scenery now, part of the world: robots route around it (the
	# navmesh bake in tools/bake_navmesh.gd counts it too).
	collision_layer |= 1
