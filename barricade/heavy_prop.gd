class_name HeavyProp
extends StaticBody3D
## Something heavy enough to block the gap under a door: a 2F CPU tower, a
## 1F/3F thesis stack, or a desk. Dragging it against a door takes 6 seconds,
## costs 25% Stamina and scrapes loudly - but the Balbal's Black Dog form can
## no longer crawl underneath.

const LAYER_INTERACT: int = 2
const LAYER_DOORS: int = 8
const DRAG_TIME: float = 6.0
const DRAG_STAMINA: float = 25.0
const DRAG_NOISE: float = 13.0
const PULL_TIME: float = 3.0
const PULL_NOISE: float = 9.0
const MAX_DOOR_DISTANCE: float = 11.0

@export var prop_name: String = "CPU Tower"
@export var size: Vector3 = Vector3(0.22, 0.46, 0.48)
@export var color: Color = Color(0.12, 0.12, 0.14)

var blocked_door: InteractableDoor = null

var _tween: Tween = null


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


func get_interactions(player: PlayerController) -> Array[Dictionary]:
	if blocked_door != null:
		return [{"id": &"pull", "label": "Drag the %s away from the door (3 s)" % prop_name}]
	var door: InteractableDoor = find_door()
	if door == null or door.which_side(player.global_position) < 0.0:
		return [{"id": &"none", "label": "%s - no door close enough to block" % prop_name}]
	if door.is_open:
		return [{"id": &"none", "label": "%s - close the door first" % prop_name}]
	return [{"id": &"drag", "label": "Drag the %s against the door (6 s, loud)" % prop_name}]


func interact(player: PlayerController, action_id: StringName) -> void:
	match action_id:
		&"drag":
			var door: InteractableDoor = find_door()
			if door != null and not door.is_open:
				_begin_drag(player, door)
		&"pull":
			begin_pull_away(player)


## The nearest working door of the room this prop stands in.
func find_door() -> InteractableDoor:
	var best: InteractableDoor = null
	var best_distance: float = MAX_DOOR_DISTANCE
	var my_room: int = Campus.room_id_at(global_position + Vector3.UP * 0.3)
	for node: Node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as InteractableDoor
		if door == null or door.is_broken or door.permanently_locked or door.blocking_prop != null:
			continue
		var center: Vector3 = door.get_center()
		if absf(center.y - global_position.y) > 1.0 or door.which_side(global_position) < 0.0:
			continue
		if door.room_id != my_room:
			continue
		var distance: float = center.distance_to(global_position)
		if distance < best_distance:
			best_distance = distance
			best = door
	return best


func begin_pull_away(player: PlayerController) -> void:
	if blocked_door == null:
		return
	var started: bool = player.start_channel("Dragging the %s away" % prop_name, PULL_TIME, _finish_pull, {
		"noise_type": &"furniture_scrape", "noise_radius": PULL_NOISE, "noise_interval": 1.0, "can_fumble": false,
	})
	if started:
		SfxSynth.play_at(self, SfxSynth.scrape(), global_position, -2.0)


## Called by the door when it is broken open.
func release_from_door() -> void:
	blocked_door = null


func _begin_drag(player: PlayerController, door: InteractableDoor) -> void:
	var started: bool = player.start_channel("Dragging the %s against the door" % prop_name, DRAG_TIME,
		_finish_drag.bind(door), {
			"stamina_cost": DRAG_STAMINA, "noise_type": &"furniture_scrape", "noise_radius": DRAG_NOISE,
			"noise_interval": 1.0, "can_fumble": false, "on_cancel": _on_drag_cancelled,
		})
	if not started:
		return
	SfxSynth.play_at(self, SfxSynth.scrape(), global_position, 0.0)
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "global_position", door.get_block_position(), player.stats.get_channel_time(DRAG_TIME))


func _on_drag_cancelled(_elapsed: float) -> void:
	if _tween != null:
		_tween.kill()


func _finish_drag(door: InteractableDoor) -> void:
	if _tween != null:
		_tween.kill()
	if not is_instance_valid(door) or door.is_broken or door.is_open:
		return
	global_position = door.get_block_position()
	blocked_door = door
	door.set_gap_blocked(self)
	EventBus.ui_notification.emit("The gap under the door is blocked.", 2.5)


func _finish_pull() -> void:
	if blocked_door == null:
		return
	var door: InteractableDoor = blocked_door
	blocked_door = null
	door.clear_gap_block()
	global_position = door.get_side_position(1.0, 1.3) + door.get_along() * 0.8
