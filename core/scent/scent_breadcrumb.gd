class_name ScentBreadcrumb
extends Node3D
## One point of Juan's scent trail. Aswang follow these from oldest to newest,
## which walks them straight to wherever he went to ground. Blood crumbs also
## leave a visible droplet on the floor.

const LIFETIME: float = 80.0
const BLOOD_COLOR: Color = Color(0.32, 0.02, 0.02)

## Monotonic drop order: a higher serial is a fresher crumb.
var serial: int = 0
## Scent level (0-100) at the moment it was dropped.
var strength: float = 0.0
var is_blood: bool = false
## The HidingSpot Juan was inside when this dropped, if any.
var hiding_spot: Node3D = null
var age: float = 0.0

var _droplet: MeshInstance3D = null


func _ready() -> void:
	add_to_group(&"scent_breadcrumbs")
	if is_blood:
		_build_droplet()


func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
	elif _droplet != null and age > LIFETIME - 10.0:
		_droplet.transparency = clampf((age - (LIFETIME - 10.0)) / 10.0, 0.0, 1.0)


## 1.0 when fresh, fading to 0.0 as it expires.
func get_freshness() -> float:
	return clampf(1.0 - age / LIFETIME, 0.0, 1.0)


func _build_droplet() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = randf_range(0.035, 0.07)
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.004
	mesh.radial_segments = 10
	var material := StandardMaterial3D.new()
	material.albedo_color = BLOOD_COLOR
	material.roughness = 0.25
	mesh.material = material
	_droplet = MeshInstance3D.new()
	_droplet.mesh = mesh
	_droplet.position = Vector3(randf_range(-0.12, 0.12), 0.012, randf_range(-0.12, 0.12))
	_droplet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_droplet)
