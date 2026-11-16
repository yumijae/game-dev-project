class_name BrokenGlassHazard
extends Area3D
## Shards left on the floor by a shattered jalousie window or viewing pane.
## Bare feet are cut open (Bleeding); shoes and socks only crunch - loudly.

const LAYER_HAZARD: int = 64
const LAYER_PLAYER: int = 4
const CRUNCH_INTERVAL: float = 0.7
const CRUNCH_RADIUS_SHOES: float = 8.0
const CRUNCH_RADIUS_SOCKS: float = 5.0
const CUT_NOISE_RADIUS: float = 7.0

## Footprint on the floor (x, z) in metres.
var extents: Vector2 = Vector2(1.6, 1.2)

var _crunch_timer: float = 0.0


static func spawn(parent: Node, at: Vector3, size: Vector2, yaw: float = 0.0) -> BrokenGlassHazard:
	var hazard := BrokenGlassHazard.new()
	hazard.extents = size
	hazard.name = "BrokenGlassHazard"
	parent.add_child(hazard)
	hazard.global_position = at
	hazard.rotation.y = yaw
	return hazard


func _ready() -> void:
	add_to_group(&"glass_hazards")
	collision_layer = LAYER_HAZARD
	collision_mask = LAYER_PLAYER
	monitoring = true
	monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(extents.x, 0.4, extents.y)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.2
	add_child(collider)
	_build_shards()
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_crunch_timer = maxf(_crunch_timer - delta, 0.0)
	if _crunch_timer > 0.0:
		return
	for body: Node3D in get_overlapping_bodies():
		var player := body as PlayerController
		if player != null and Vector2(player.velocity.x, player.velocity.z).length() > 0.4:
			_step(player)


func _on_body_entered(body: Node3D) -> void:
	var player := body as PlayerController
	if player != null:
		_step(player)


func _step(player: PlayerController) -> void:
	_crunch_timer = CRUNCH_INTERVAL
	var stats: PlayerStats = player.stats
	if stats.footwear == PlayerStats.Footwear.BAREFOOT:
		if stats.step_on_glass():
			NoiseManager.emit_noise(player.global_position, CUT_NOISE_RADIUS, &"pain_gasp", player)
			SfxSynth.play_at(self, SfxSynth.gasp(), player.global_position, -4.0)
			EventBus.ui_notification.emit("Glass! Your bare foot is cut open - you are bleeding.", 3.5)
		return
	var radius: float = CRUNCH_RADIUS_SOCKS if stats.footwear == PlayerStats.Footwear.SOCKS else CRUNCH_RADIUS_SHOES
	if player.is_crouching:
		radius *= 0.6
	NoiseManager.emit_noise(player.global_position, radius, &"glass_crunch", player)
	SfxSynth.play_at(self, SfxSynth.glass_crunch(), player.global_position, -8.0, randf_range(0.9, 1.15))


func _build_shards() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.9, 0.95, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.08
	material.metallic_specular = 0.9
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, 0.006, 0.07)
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var count: int = clampi(int(extents.x * extents.y * 28.0), 20, 160)
	multimesh.instance_count = count
	for i: int in count:
		var position := Vector3(randf_range(-0.5, 0.5) * extents.x, 0.012, randf_range(-0.5, 0.5) * extents.y)
		var basis := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * randf_range(0.4, 1.5))
		multimesh.set_instance_transform(i, Transform3D(basis, position))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
