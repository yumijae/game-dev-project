class_name HeavyProp
extends StaticBody3D
## Something heavy enough to block the gap under a door: a 2F CPU tower, a
## 1F/3F thesis stack, or a desk. Dragging it against a door takes 6 seconds,
## costs 25% Stamina and scrapes loudly - but SCUTTLE can
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
## Where the current drag runs from and to, its resting orientation, and how
## many heaves have already been heard (one scrape each).
var _haul_from: Vector3 = Vector3.ZERO
var _haul_to: Vector3 = Vector3.ZERO
var _haul_basis: Basis = Basis.IDENTITY
var _pulls_heard: int = 0


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
	var door: InteractableDoor = blocked_door
	_haul_from = global_position
	_haul_to = door.get_side_position(1.0, 1.3) + door.get_along() * 0.8
	_haul_basis = global_basis
	_pulls_heard = 0
	player.start_channel("Dragging the %s away" % prop_name, PULL_TIME, _finish_pull, {
		"noise_type": &"furniture_scrape", "noise_radius": PULL_NOISE, "noise_interval": 1.0, "can_fumble": false,
		"on_progress": _haul.bind(3), "on_cancel": _on_drag_cancelled,
	})


## Called by the door when it is broken open.
func release_from_door() -> void:
	blocked_door = null


func _begin_drag(player: PlayerController, door: InteractableDoor) -> void:
	if _tween != null:
		_tween.kill()
	_haul_from = global_position
	_haul_to = door.get_block_position()
	_haul_basis = global_basis
	_pulls_heard = 0
	player.start_channel("Dragging the %s against the door" % prop_name, DRAG_TIME,
		_finish_drag.bind(door), {
			"stamina_cost": DRAG_STAMINA, "noise_type": &"furniture_scrape", "noise_radius": DRAG_NOISE,
			"noise_interval": 1.0, "can_fumble": false, "on_cancel": _on_drag_cancelled,
			"on_progress": _haul.bind(5),
		})


## Heavy things do not glide: Juan heaves them a short way, rests, heaves
## again. Each of `pulls` heaves takes most of its share of the time; the
## prop rocks up on its far edge while it moves and drops back with a scrape.
## Driven by the channel's progress, so an interruption leaves it where it is.
func _haul(ratio: float, pulls: int) -> void:
	var span: float = ratio * float(pulls)
	var index: int = mini(int(span), pulls - 1)
	var local: float = clampf(span - float(index), 0.0, 1.0)
	# 80% of each heave is movement (eased), the rest a pause for breath.
	var move: float = clampf(local / 0.8, 0.0, 1.0)
	var eased: float = move * move * (3.0 - 2.0 * move)
	var travelled: float = (float(index) + eased) / float(pulls)
	if ratio >= 1.0:
		travelled = 1.0
	global_position = _haul_from.lerp(_haul_to, travelled)
	# Rocks onto the edge away from Juan while it moves, a little yaw wobble.
	var direction: Vector3 = _haul_to - _haul_from
	direction.y = 0.0
	var lift: float = sin(move * PI) * (0.06 if local < 0.8 else 0.0)
	var tilt_axis: Vector3 = Vector3.UP.cross(direction.normalized()) if direction.length() > 0.01 else Vector3.RIGHT
	var wobble: float = sin(move * PI * 2.0) * 0.03 * (1.0 if index % 2 == 0 else -1.0)
	global_basis = Basis(tilt_axis, -lift) * Basis(Vector3.UP, wobble) * _haul_basis
	if index >= _pulls_heard and local > 0.02 and ratio < 1.0:
		_pulls_heard = index + 1
		SfxSynth.play_at(self, SfxSynth.scrape(), global_position, -4.0, randf_range(0.8, 1.0))
	_clear_robots()


func _on_drag_cancelled(_elapsed: float) -> void:
	if _tween != null:
		_tween.kill()
	global_basis = _haul_basis


func _finish_drag(door: InteractableDoor) -> void:
	if _tween != null:
		_tween.kill()
	global_basis = _haul_basis
	if not is_instance_valid(door) or door.is_broken or door.is_open:
		return
	global_position = door.get_block_position()
	SfxSynth.play_at(self, SfxSynth.thud(), global_position + Vector3.UP * 0.2, -6.0, 0.8)
	_clear_robots()
	blocked_door = door
	door.set_gap_blocked(self)
	EventBus.ui_notification.emit("The gap under the door is blocked.", 2.5)


func _finish_pull() -> void:
	if blocked_door == null:
		return
	var door: InteractableDoor = blocked_door
	blocked_door = null
	door.clear_gap_block()
	global_basis = _haul_basis
	global_position = door.get_side_position(1.0, 1.3) + door.get_along() * 0.8
	_clear_robots()


## Moves any robot the prop is sliding into out of its way, onto clear floor.
## A static body moved by hand does not push characters: it ended up inside
## SCUTTLE, and the physics push-out shot it through the floor slab, so it
## seemed to vanish.
func _clear_robots() -> void:
	var reach: float = Vector2(size.x, size.z).length() * 0.5
	var map: RID = get_world_3d().navigation_map
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var robot := node as Node3D
		if robot == null or absf(robot.global_position.y - global_position.y) > 1.0:
			continue
		var flat := Vector3(robot.global_position.x - global_position.x, 0.0, robot.global_position.z - global_position.z)
		var radius: float = float(robot.get(&"body_radius")) if robot.get(&"body_radius") != null else 0.3
		if flat.length() >= reach + radius:
			continue
		if flat.length() < 0.05:
			flat = Vector3.FORWARD
		var away: Vector3 = flat.normalized()
		for extra: float in [0.15, 0.4, 0.8]:
			var aim: Vector3 = global_position + away * (reach + radius + extra)
			aim.y = robot.global_position.y
			var spot: Vector3 = NavigationServer3D.map_get_closest_point(map, aim)
			var gap := Vector2(spot.x - global_position.x, spot.z - global_position.z).length()
			if absf(spot.y - robot.global_position.y) < 0.5 and gap >= reach + radius:
				robot.global_position = Vector3(spot.x, robot.global_position.y, spot.z)
				if robot is CharacterBody3D:
					(robot as CharacterBody3D).velocity = Vector3.ZERO
				break
