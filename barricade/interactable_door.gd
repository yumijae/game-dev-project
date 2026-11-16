class_name InteractableDoor
extends Node3D
## A hinged room door: open, shut, or peeked under. There are no barricades -
## nothing holds a door shut except the chained fire exits.
##
## The node sits on the hinge; its child "Leaf" (AnimatableBody3D) is the door.
## The robots talk to it through can_robot_open(), shove() and can_slip_under().

const HANDLE_TURN_TIME: float = 0.8
const MAX_HEALTH: float = 100.0
const SWING_TIME: float = 0.4
const NOISE_OPEN: float = 5.0
const NOISE_CLOSE: float = 6.5
const NOISE_RATTLE: float = 7.0
const NOISE_SHOVE: float = 15.0
const NOISE_BREAK: float = 22.0
const GAP_HEIGHT: float = 0.09
## Collision layers of the leaf. Shut, it is a door (8) to everyone. Open it
## stands straight out from the wall - and the walking mesh the robots plan
## their routes on knows nothing of it, so they ground to a halt against it
## (5 trips in 16 in testing). Open, it moves to its own layer (128): Juan
## still bumps into it and can aim at it to close it; robots pass by.
const LAYER_DOORS: int = 8
const LAYER_OPEN_LEAF: int = 128

@export var door_label: String = "Door"
@export var closed_yaw: float = 0.0
@export var open_yaw: float = 1.5708
@export var door_width: float = 0.94
@export var room_id: int = 0
## Unit vector pointing from the doorway into the room this door protects.
@export var room_side: Vector3 = Vector3.BACK
## Fire exits: chained from outside, nobody opens them tonight.
@export var permanently_locked: bool = false
@export var start_open: bool = false

var is_open: bool = false
var is_broken: bool = false
var health: float = MAX_HEALTH
## While a "voice behind the door" hallucination plays, nothing is really outside.
var hallucination_time_left: float = 0.0

var _tween: Tween = null
var _leaf: Node3D = null


func _ready() -> void:
	add_to_group(&"doors")
	_leaf = get_node_or_null("Leaf") as Node3D
	is_open = start_open
	rotation.y = open_yaw if is_open else closed_yaw
	_update_leaf_collision()
	_dress_leaf()


## Swaps the generator's box handle for real hardware (barricade/door_dressing.gd).
func _dress_leaf() -> void:
	if _leaf == null:
		return
	var old_handle: Node = _leaf.get_node_or_null("Handle")
	if old_handle != null:
		old_handle.queue_free()
	var slab := _leaf.get_node_or_null("Mesh") as MeshInstance3D
	var wood: Material = null
	var height: float = 2.1
	# A plain box slab gets moulded panels; a modelled leaf keeps its own.
	var boxed: bool = slab != null and slab.mesh is BoxMesh
	if boxed:
		wood = (slab.mesh as BoxMesh).material
		height = slab.position.y + (slab.mesh as BoxMesh).size.y * 0.5
	elif slab != null and slab.mesh != null and slab.mesh.get_surface_count() > 0:
		wood = slab.mesh.surface_get_material(0)
		height = slab.position.y + slab.mesh.get_aabb().end.y
	if wood == null:
		wood = StandardMaterial3D.new()
	# The leaf swings towards local -Z when the open yaw is larger.
	var swing: float = -signf(open_yaw - closed_yaw)
	var seed: float = fposmod(global_position.x * 7.1 + global_position.z * 3.3 + global_position.y, 40.0)
	DoorDressing.dress(_leaf, door_width, height, GAP_HEIGHT, _local_room_sign(), swing, wood, seed, boxed)


func _process(delta: float) -> void:
	if hallucination_time_left > 0.0:
		hallucination_time_left = maxf(hallucination_time_left - delta, 0.0)


# ------------------------------------------------------------------- geometry

## Direction along the closed door, from hinge to latch.
func get_along() -> Vector3:
	return Basis(Vector3.UP, closed_yaw) * Vector3.RIGHT


## Middle of the doorway at floor level.
func get_center() -> Vector3:
	return global_position + get_along() * door_width * 0.5


## +1.0 when `pos` is on the room side of the doorway, -1.0 otherwise.
func which_side(pos: Vector3) -> float:
	return 1.0 if (pos - get_center()).dot(room_side) >= 0.0 else -1.0


## A floor point `distance` metres from the doorway (side: +1 room, -1 outside).
func get_side_position(side: float, distance: float) -> Vector3:
	return get_center() + room_side * side * distance


func is_passable() -> bool:
	return is_open or is_broken


# --------------------------------------------------------------- interactions

func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	if permanently_locked:
		return [{"id": &"rattle", "label": "%s - chained shut" % door_label}]
	if is_broken:
		return []
	if is_open:
		return [{"id": &"close", "label": "Close door"}]
	return [{"id": &"open", "label": "Open door"}, {"id": &"peek", "label": "Peek under the door"}]


func interact(player: PlayerController, action_id: StringName) -> void:
	match action_id:
		&"open":
			set_open(true)
		&"close":
			set_open(false)
		&"peek":
			peek_under_door(player)
		&"rattle":
			_rattle()


## Lowers the camera to the gap under the door and reports what stands outside:
## wheels, feet or claws mean a robot is really there, and no shadow at all
## means the voice was in Juan's head.
func peek_under_door(player: PlayerController) -> void:
	var side: float = which_side(player.global_position)
	var center: Vector3 = get_center()
	var eye: Vector3 = center + room_side * side * 0.3 + Vector3.UP * 0.045
	var target: Vector3 = center - room_side * side * 2.0 + Vector3.UP * 0.045
	player.begin_peek(Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye))
	EventBus.ui_subtitle.emit(_describe_far_side(-side), 5.0, &"Juan")


func _describe_far_side(side: float) -> String:
	var far_point: Vector3 = get_side_position(side, 1.0)
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var hostile := node as Hostile
		if hostile == null or not hostile.is_threatening():
			continue
		if absf(hostile.global_position.y - far_point.y) > 1.5:
			continue
		if hostile.global_position.distance_to(far_point) > 2.6 or which_side(hostile.global_position) != side:
			continue
		return hostile.get_feet_description()
	if hallucination_time_left > 0.0:
		return "No shadow under the door. No feet. ...There is no one out there."
	return "Only the floor. Nothing is standing outside."


func set_open(open: bool) -> void:
	if is_broken or open == is_open:
		return
	if open and permanently_locked:
		return
	is_open = open
	_update_leaf_collision()
	_swing(open_yaw if open else closed_yaw, SWING_TIME)
	var handle: Vector3 = get_center() + Vector3.UP * 1.0
	if open:
		SfxSynth.play_at(self, SfxSynth.door_open(), handle, -9.0, randf_range(0.92, 1.06), 22.0)
	else:
		# The latch catches as the leaf arrives, not when the swing starts.
		get_tree().create_timer(SWING_TIME * 0.85).timeout.connect(func() -> void:
			if is_inside_tree() and not is_open:
				SfxSynth.play_at(self, SfxSynth.door_close(), handle, -7.0, randf_range(0.92, 1.06), 26.0))
	NoiseManager.emit_noise(get_center(), NOISE_OPEN if open else NOISE_CLOSE, &"door_swing", self)
	EventBus.door_state_changed.emit(self)


func _rattle() -> void:
	NoiseManager.emit_noise(get_center(), NOISE_RATTLE, &"door_rattle", self)
	SfxSynth.play_at(self, SfxSynth.clatter(), get_center() + Vector3.UP, -12.0, 0.7)


# ------------------------------------------------------------------ Robot API

## True when something with hands can simply turn the handle (any shut door
## but the chained fire exits).
func can_robot_open() -> bool:
	return not is_passable() and not permanently_locked


## How long it takes to turn the handle.
func get_handle_delay() -> float:
	return HANDLE_TURN_TIME


## SCUTTLE can crawl under any shut door except the fire exits.
func can_slip_under() -> bool:
	return not permanently_locked


## One heavy blow; the door bursts once its health is gone. Returns true when
## the door has given way. (Nothing holds a door shut any more, so robots
## open rather than batter; kept for anything that does hit one.)
func shove(force: float) -> bool:
	if is_passable() or permanently_locked:
		return is_passable()
	NoiseManager.emit_noise(get_center(), NOISE_SHOVE, &"door_bang", self)
	SfxSynth.play_at(self, SfxSynth.thud(), get_center() + Vector3.UP, 0.0)
	_shake()
	health -= force
	if health <= 0.0:
		break_open()
		return true
	return false


func break_open() -> void:
	if is_broken:
		return
	is_broken = true
	is_open = true
	_update_leaf_collision()
	_swing(open_yaw, 0.12)
	NoiseManager.emit_noise(get_center(), NOISE_BREAK, &"door_break", self)
	SfxSynth.play_at(self, SfxSynth.thud(), get_center() + Vector3.UP, 4.0, 0.8)
	EventBus.door_breached.emit(self)
	EventBus.door_state_changed.emit(self)


# -------------------------------------------------------------------- visuals

func _swing(target_yaw: float, time: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation:y", target_yaw, time)


func _shake() -> void:
	if _tween != null and _tween.is_running():
		return
	_tween = create_tween()
	_tween.tween_property(self, "rotation:y", closed_yaw + signf(open_yaw - closed_yaw) * 0.05, 0.05)
	_tween.tween_property(self, "rotation:y", closed_yaw, 0.12)


func _update_leaf_collision() -> void:
	var body := _leaf as CollisionObject3D
	if body != null:
		body.collision_layer = LAYER_OPEN_LEAF if (is_open or is_broken) else LAYER_DOORS


## Sign of the room side along the closed door's local Z axis.
func _local_room_sign() -> float:
	var local_normal: Vector3 = Basis(Vector3.UP, closed_yaw) * Vector3.BACK
	return 1.0 if local_normal.dot(room_side) >= 0.0 else -1.0
