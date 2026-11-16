class_name ThrownBottle
extends Node3D
## A thrown glass bottle. It shatters where it lands with a loud crash: every
## robot that can hear it goes to look. Throw it away from where you are going.

const SHATTER_NOISE: float = 18.0
const GRAVITY: float = 9.8
const MAX_FLIGHT_TIME: float = 5.0
## World, doors, glass and robot bodies.
const HIT_MASK: int = 1 | 8 | 16 | 32

var velocity: Vector3 = Vector3.ZERO

var _flight_time: float = 0.0


static func launch(parent: Node, origin: Vector3, initial_velocity: Vector3) -> ThrownBottle:
	var bottle := ThrownBottle.new()
	bottle.name = "ThrownBottle"
	bottle.velocity = initial_velocity
	parent.add_child(bottle)
	bottle.global_position = origin
	return bottle


func _ready() -> void:
	var model: Node3D = ItemModel.build(ItemDB.GLASS_BOTTLE)
	model.position.y = -0.1
	add_child(model)


func _physics_process(delta: float) -> void:
	_flight_time += delta
	velocity.y -= GRAVITY * delta
	var next: Vector3 = global_position + velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next, HIT_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_burst(hit["position"])
		return
	global_position = next
	rotate_x(delta * 9.0)
	if _flight_time >= MAX_FLIGHT_TIME:
		_burst(global_position)


func _burst(point: Vector3) -> void:
	NoiseManager.emit_noise(point, SHATTER_NOISE, &"glass_shatter", self)
	SfxSynth.play_at(self, SfxSynth.glass_shatter(), point, 4.0, 1.1, 40.0)
	_spawn_shards(point)
	_leave_glass(point)
	queue_free()


## The pieces stay where they fell: loud to walk over, and they cut bare feet.
func _leave_glass(point: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.1, point + Vector3.DOWN * 2.5, 1)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
		return
	BrokenGlassHazard.spawn(scene, hit["position"], Vector2(1.0, 1.0), randf() * TAU)


## A few glints of glass on the floor where it broke.
func _spawn_shards(point: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var shards := CPUParticles3D.new()
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.amount = 18
	shards.lifetime = 0.7
	shards.direction = Vector3.UP
	shards.spread = 75.0
	shards.initial_velocity_min = 1.0
	shards.initial_velocity_max = 2.6
	shards.gravity = Vector3(0, -9.8, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.004, 0.012)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.85, 0.8, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.05
	mesh.material = mat
	shards.mesh = mesh
	scene.add_child(shards)
	shards.global_position = point + Vector3.UP * 0.05
	shards.emitting = true
	scene.get_tree().create_timer(1.5).timeout.connect(shards.queue_free)
