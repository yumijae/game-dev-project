class_name SinamakBottle
extends Node3D
## A thrown bottle of sinamak (spiced cane vinegar). Where it bursts, every
## Aswang within 4 metres is blinded for 6 seconds and loses the chase - even
## one staring in through the wide lab glass.

const BLIND_RADIUS: float = 4.0
const BLIND_TIME: float = 6.0
const SHATTER_NOISE: float = 10.0
const GRAVITY: float = 9.8
const MAX_FLIGHT_TIME: float = 5.0
## World, doors, glass and Aswang bodies.
const HIT_MASK: int = 1 | 8 | 16 | 32

var velocity: Vector3 = Vector3.ZERO

var _flight_time: float = 0.0


static func launch(parent: Node, origin: Vector3, initial_velocity: Vector3) -> SinamakBottle:
	var bottle := SinamakBottle.new()
	bottle.name = "SinamakBottle"
	bottle.velocity = initial_velocity
	parent.add_child(bottle)
	bottle.global_position = origin
	return bottle


func _ready() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.035
	mesh.height = 0.22
	var material := StandardMaterial3D.new()
	material.albedo_color = ItemDB.get_color(ItemDB.SINAMAK)
	material.roughness = 0.15
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	add_child(instance)


func _physics_process(delta: float) -> void:
	_flight_time += delta
	velocity.y -= GRAVITY * delta
	var next: Vector3 = global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, HIT_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var point: Vector3 = hit["position"]
		_burst(point)
		return
	global_position = next
	rotate_x(delta * 9.0)
	if _flight_time >= MAX_FLIGHT_TIME:
		_burst(global_position)


func _burst(point: Vector3) -> void:
	NoiseManager.emit_noise(point, SHATTER_NOISE, &"glass_shatter", self)
	SfxSynth.play_at(self, SfxSynth.glass_shatter(), point, 0.0, 1.35)
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var aswang := node as Hostile
		if aswang != null and aswang.is_threatening() and aswang.global_position.distance_to(point) <= BLIND_RADIUS:
			aswang.blind(BLIND_TIME)
	_spawn_splash(point)
	queue_free()


func _spawn_splash(point: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.6, 0.2, 0.35)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	var splash := MeshInstance3D.new()
	splash.mesh = mesh
	splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(splash)
	splash.global_position = point
	splash.scale = Vector3.ONE * 0.2
	var tween: Tween = splash.create_tween()
	tween.tween_property(splash, "scale", Vector3.ONE * (BLIND_RADIUS / 0.5), 0.35)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(splash.queue_free)
