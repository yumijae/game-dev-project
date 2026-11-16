class_name TripwireAlarm
extends StaticBody3D
## A glass bottle balanced on a LAN cable stretched low across a doorway or
## corridor. The first robot to walk through it knocks the bottle over: a crash
## Juan can hear from far away, so he knows something is coming - and from
## where. (It also draws the others to that spot.)

const LAYER_INTERACT: int = 2
const TRIP_RADIUS: float = 0.75
const CRASH_NOISE: float = 14.0
const CHECK_INTERVAL: float = 0.1

var _check: float = 0.0


static func place(parent: Node, at: Vector3, facing: Vector3) -> TripwireAlarm:
	var trap := TripwireAlarm.new()
	trap.name = "TripwireAlarm"
	parent.add_child(trap)
	trap.global_position = at
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length() > 0.01:
		trap.global_basis = Basis.looking_at(flat.normalized(), Vector3.UP)
	return trap


func _ready() -> void:
	add_to_group(&"tripwires")
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.3, 0.3)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.15
	add_child(collider)
	# The cable, ankle high, between two little weights.
	var cable_mat := StandardMaterial3D.new()
	cable_mat.albedo_color = ItemDB.get_color(ItemDB.LAN_CABLE)
	var cable := MeshInstance3D.new()
	var cable_mesh := BoxMesh.new()
	cable_mesh.size = Vector3(0.95, 0.006, 0.006)
	cable_mesh.material = cable_mat
	cable.mesh = cable_mesh
	cable.position.y = 0.12
	add_child(cable)
	for x: float in [-0.48, 0.48]:
		var weight := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.05, 0.12, 0.05)
		box.material = cable_mat
		weight.mesh = box
		weight.position = Vector3(x, 0.06, 0.0)
		add_child(weight)
	var bottle: Node3D = ItemModel.build(ItemDB.GLASS_BOTTLE)
	bottle.position = Vector3(0.0, 0.125, 0.0)
	add_child(bottle)
	_set_up_animation(cable, bottle)


## Juan stretches the cable out from the middle to both weights, then sets
## the bottle down on it with a little wobble and a clink.
func _set_up_animation(cable: Node3D, bottle: Node3D) -> void:
	var weights: Array[Node3D] = []
	for child: Node in get_children():
		if child is MeshInstance3D and child != cable and absf((child as Node3D).position.x) > 0.4:
			weights.append(child as Node3D)
	cable.scale.x = 0.05
	for w: Node3D in weights:
		w.position.x *= 0.05
	bottle.position.y = 0.32
	bottle.rotation.z = 0.25
	var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(cable, "scale:x", 1.0, 0.45)
	for w: Node3D in weights:
		tween.parallel().tween_property(w, "position:x", signf(w.position.x) * 0.48, 0.45)
	tween.tween_property(bottle, "position:y", 0.125, 0.25).set_trans(Tween.TRANS_BOUNCE)
	tween.parallel().tween_property(bottle, "rotation:z", 0.0, 0.35).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_callback(func() -> void:
		SfxSynth.play_at(self, SfxSynth.latch_click(), global_position + Vector3.UP * 0.12, -16.0, 1.8, 8.0))


func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	return [{"id": &"take", "label": "Take down the tripwire"}]


func interact(player: PlayerController, _action_id: StringName) -> void:
	if player.inventory.add_item(ItemDB.TRIPWIRE, 1) > 0:
		EventBus.ui_notification.emit("No room. Drop something first.", 2.0)
		return
	queue_free()


func _physics_process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_INTERVAL
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var robot := node as Hostile
		if robot != null and robot.is_active and robot.global_position.distance_to(global_position) <= TRIP_RADIUS:
			_trip()
			return


func _trip() -> void:
	NoiseManager.emit_noise(global_position, CRASH_NOISE, &"glass_shatter", self)
	SfxSynth.play_at(self, SfxSynth.glass_shatter(), global_position + Vector3.UP * 0.1, 8.0, 0.95, 60.0)
	EventBus.ui_notification.emit("Glass shatters somewhere. Your tripwire.", 3.0)
	BrokenGlassHazard.spawn(get_tree().current_scene, global_position, Vector2(0.9, 0.9))
	queue_free()
