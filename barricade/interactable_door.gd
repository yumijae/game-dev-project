class_name InteractableDoor
extends Node3D
## A hinged room door and everything Juan can do to hold it shut.
##
## The node sits on the hinge; its child "Leaf" (AnimatableBody3D) is the door.
##   handle_state        UNLOCKED / LOCKED / CHAIR_WEDGED / CABLE_TIED
##   bottom_gap_blocked  a HeavyProp dragged against it - stops SCUTTLE
## The robots talk to it through can_robot_open(), shove() and can_slip_under().

enum HandleState { UNLOCKED, LOCKED, CHAIR_WEDGED, CABLE_TIED }

## A wedged chair holds the handle for this long before it starts to give.
const WEDGE_HANDLE_DELAY: float = 5.0
const WEDGE_SHOVES: int = 2
const HANDLE_TURN_TIME: float = 0.8
const LOCK_TIME: float = 1.0
const WEDGE_TIME: float = 2.0
const CABLE_TIE_TIME: float = 4.0
## Seconds SCUTTLE needs to squeeze under an unblocked door.
const SLIP_UNDER_TIME: float = 3.0
const MAX_HEALTH: float = 100.0
const SWING_TIME: float = 0.4
const NOISE_OPEN: float = 5.0
const NOISE_CLOSE: float = 6.5
const NOISE_RATTLE: float = 7.0
const NOISE_SHOVE: float = 15.0
const NOISE_BREAK: float = 22.0
const GAP_HEIGHT: float = 0.09

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

var handle_state: HandleState = HandleState.UNLOCKED
var bottom_gap_blocked: bool = false
var is_open: bool = false
var is_broken: bool = false
var health: float = MAX_HEALTH
var wedge_shoves_left: int = 0
var blocking_prop: HeavyProp = null
## While a "voice behind the door" hallucination plays, nothing is really outside.
var hallucination_time_left: float = 0.0

var _tween: Tween = null
var _leaf: Node3D = null
var _wedge_mesh: Node3D = null
var _cable_mesh: Node3D = null
var _thumb_turn: Node3D = null
var _wedge_rest: Transform3D = Transform3D.IDENTITY
## Progress last seen by a barricade animation, so its sounds fire once.
var _anim_mark: float = 0.0
var _cable_wound: float = -1.0


func _ready() -> void:
	add_to_group(&"doors")
	_leaf = get_node_or_null("Leaf") as Node3D
	is_open = start_open
	rotation.y = open_yaw if is_open else closed_yaw
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
	_thumb_turn = DoorDressing.dress(_leaf, door_width, height, GAP_HEIGHT, _local_room_sign(), swing, wood, seed, boxed)
	_update_thumb_turn()


func _update_thumb_turn() -> void:
	if _thumb_turn != null:
		_thumb_turn.rotation.z = PI * 0.5 if handle_state == HandleState.LOCKED else 0.0


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


## Where a HeavyProp sits when it blocks the gap.
func get_block_position() -> Vector3:
	return get_side_position(1.0, 0.42)


func is_passable() -> bool:
	return is_open or is_broken


# --------------------------------------------------------------- interactions

func get_interactions(player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if permanently_locked:
		return [{"id": &"rattle", "label": "%s - chained shut" % door_label}]
	if is_broken:
		return actions
	var inside: bool = which_side(player.global_position) > 0.0
	var inventory: InventoryComponent = player.inventory
	if is_open:
		actions.append({"id": &"close", "label": "Close door"})
	else:
		match handle_state:
			HandleState.UNLOCKED:
				if blocking_prop == null:
					actions.append({"id": &"open", "label": "Open door"})
				if inside:
					actions.append({"id": &"lock", "label": "Lock door"})
					if inventory.has_in_hands(ItemDB.CHAIR):
						actions.append({"id": &"wedge", "label": "Wedge chair under handle"})
					if inventory.has_item(ItemDB.LAN_CABLE):
						actions.append({"id": &"tie", "label": "Tie handle with LAN cable (4 s, silent)"})
			HandleState.LOCKED:
				if inside:
					actions.append({"id": &"unlock", "label": "Unlock door"})
				else:
					actions.append({"id": &"rattle", "label": "Locked from inside"})
			HandleState.CHAIR_WEDGED:
				if inside:
					actions.append({"id": &"unwedge", "label": "Pull the chair away"})
				else:
					actions.append({"id": &"rattle", "label": "Something is wedged against it"})
			HandleState.CABLE_TIED:
				if inside:
					actions.append({"id": &"untie", "label": "Untie the LAN cable"})
				else:
					actions.append({"id": &"rattle", "label": "The handle is tied shut"})
		if blocking_prop != null and inside:
			actions.append({"id": &"unblock", "label": "Drag the %s away (3 s)" % blocking_prop.prop_name})
		actions.append({"id": &"peek", "label": "Peek under the door"})
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	match action_id:
		&"open":
			set_open(true)
		&"close":
			set_open(false)
		&"lock":
			_anim_mark = 0.0
			player.start_channel("Locking the door", LOCK_TIME, _set_handle.bind(HandleState.LOCKED), {"can_fumble": false,
				"on_progress": _turn_thumb.bind(true), "on_cancel": _restore_barricade_look.unbind(1)})
		&"unlock":
			_anim_mark = 0.0
			player.start_channel("Unlocking the door", LOCK_TIME, _set_handle.bind(HandleState.UNLOCKED), {"can_fumble": false,
				"on_progress": _turn_thumb.bind(false), "on_cancel": _restore_barricade_look.unbind(1)})
		&"wedge":
			_anim_mark = 0.0
			player.start_channel("Wedging the chair under the handle", WEDGE_TIME, _finish_wedge.bind(player), {
				"on_progress": _wedge_in, "on_cancel": _restore_barricade_look.unbind(1)})
		&"unwedge":
			_anim_mark = 0.0
			player.start_channel("Pulling the chair away", 1.5, _finish_unwedge.bind(player), {
				"on_progress": _wedge_out, "on_cancel": _restore_barricade_look.unbind(1)})
		&"tie":
			_anim_mark = 0.0
			player.start_channel("Tying the handle with LAN cable", CABLE_TIE_TIME, _finish_tie.bind(player), {"can_fumble": false,
				"on_progress": _wind_cable.bind(true), "on_cancel": _restore_barricade_look.unbind(1)})
		&"untie":
			_anim_mark = 0.0
			player.start_channel("Untying the LAN cable", 2.0, _finish_untie.bind(player), {"can_fumble": false,
				"on_progress": _wind_cable.bind(false), "on_cancel": _restore_barricade_look.unbind(1)})
		&"unblock":
			if blocking_prop != null:
				blocking_prop.begin_pull_away(player)
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
	if open and (handle_state != HandleState.UNLOCKED or blocking_prop != null or permanently_locked):
		return
	is_open = open
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


func _set_handle(state: HandleState) -> void:
	if is_open or is_broken:
		_restore_barricade_look()
		return
	handle_state = state
	_update_thumb_turn()
	SfxSynth.play_at(self, SfxSynth.latch_click(), get_center() + Vector3.UP, -10.0, 1.15 if state == HandleState.LOCKED else 1.0, 14.0)
	EventBus.door_state_changed.emit(self)


func _finish_wedge(player: PlayerController) -> void:
	if is_open or is_broken or handle_state != HandleState.UNLOCKED or not player.inventory.remove_item(ItemDB.CHAIR, 1):
		_restore_barricade_look()
		return
	handle_state = HandleState.CHAIR_WEDGED
	wedge_shoves_left = WEDGE_SHOVES
	_show_wedge(true)
	EventBus.door_state_changed.emit(self)


func _finish_unwedge(player: PlayerController) -> void:
	if handle_state != HandleState.CHAIR_WEDGED:
		return
	handle_state = HandleState.UNLOCKED
	_show_wedge(false)
	if player.inventory.add_item(ItemDB.CHAIR, 1) > 0:
		player.drop_item_in_world(ItemDB.CHAIR, 1)
	EventBus.door_state_changed.emit(self)


func _finish_tie(player: PlayerController) -> void:
	if is_open or is_broken or handle_state != HandleState.UNLOCKED or not player.inventory.remove_item(ItemDB.LAN_CABLE, 1):
		_restore_barricade_look()
		return
	handle_state = HandleState.CABLE_TIED
	_show_cable(true)
	EventBus.door_state_changed.emit(self)


func _finish_untie(player: PlayerController) -> void:
	if handle_state != HandleState.CABLE_TIED:
		return
	handle_state = HandleState.UNLOCKED
	_show_cable(false)
	if player.inventory.add_item(ItemDB.LAN_CABLE, 1) > 0:
		player.drop_item_in_world(ItemDB.LAN_CABLE, 1)
	EventBus.door_state_changed.emit(self)


# ------------------------------------------------------------- gap barricade

func set_gap_blocked(prop: HeavyProp) -> void:
	blocking_prop = prop
	bottom_gap_blocked = true
	EventBus.door_state_changed.emit(self)


func clear_gap_block() -> void:
	blocking_prop = null
	bottom_gap_blocked = false
	EventBus.door_state_changed.emit(self)


# ------------------------------------------------------------------ Robot API

## True when something with hands can simply turn the handle.
func can_robot_open() -> bool:
	return not is_passable() and not permanently_locked and blocking_prop == null \
		and handle_state in [HandleState.UNLOCKED, HandleState.CHAIR_WEDGED]


## How long the handle resists before the door can be opened or shoved.
func get_handle_delay() -> float:
	return WEDGE_HANDLE_DELAY if handle_state == HandleState.CHAIR_WEDGED else HANDLE_TURN_TIME


## SCUTTLE can crawl under any closed door whose gap is not blocked.
func can_slip_under() -> bool:
	return not bottom_gap_blocked and not permanently_locked


## One heavy blow. A wedged chair fails after two; a locked or tied door loses
## health until it bursts. Returns true when the door has given way.
func shove(force: float) -> bool:
	if is_passable() or permanently_locked:
		return is_passable()
	NoiseManager.emit_noise(get_center(), NOISE_SHOVE, &"door_bang", self)
	SfxSynth.play_at(self, SfxSynth.thud(), get_center() + Vector3.UP, 0.0)
	_shake()
	if handle_state == HandleState.CHAIR_WEDGED:
		wedge_shoves_left -= 1
		if wedge_shoves_left > 0:
			_wedge_slip()
			return false
		handle_state = HandleState.UNLOCKED
		_show_wedge(false)
		WorldItem.spawn(get_tree().current_scene, ItemDB.CHAIR, 1, get_side_position(1.0, 1.1))
		if blocking_prop == null:
			set_open(true)
			return true
	health -= force * (0.6 if blocking_prop != null else 1.0)
	if health <= 0.0:
		break_open()
		return true
	return false


func break_open() -> void:
	if is_broken:
		return
	is_broken = true
	is_open = true
	handle_state = HandleState.UNLOCKED
	_update_thumb_turn()
	_show_wedge(false)
	_show_cable(false)
	if blocking_prop != null:
		blocking_prop.release_from_door()
		clear_gap_block()
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


func _show_wedge(visible_now: bool) -> void:
	if _wedge_mesh == null and visible_now and _leaf != null:
		_wedge_mesh = DoorDressing.build_wedge(_leaf, door_width, _local_room_sign())
		_wedge_rest = _wedge_mesh.transform
	if _wedge_mesh != null:
		if visible_now:
			_wedge_mesh.transform = _wedge_rest
		_wedge_mesh.visible = visible_now


## A blow on the door jolts the jammed chair: it skids a few centimetres and
## tips further back, so Juan can see it will not take another.
func _wedge_slip() -> void:
	if _wedge_mesh == null or not _wedge_mesh.visible:
		return
	var away: float = _local_room_sign()
	var slipped := _wedge_mesh.transform
	slipped.origin += Vector3(0.0, -0.025, away * 0.06)
	slipped.basis = Basis(Vector3.RIGHT, -away * 0.06) * slipped.basis
	var jolt := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	jolt.tween_property(_wedge_mesh, "transform", slipped, 0.18)


func _show_cable(visible_now: bool) -> void:
	if _cable_mesh == null and visible_now and _leaf != null:
		_cable_mesh = DoorDressing.build_cable(_leaf, door_width, _local_room_sign())
		_cable_wound = 1.0
	if _cable_mesh != null:
		if visible_now and not is_equal_approx(_cable_wound, 1.0):
			_cable_wound = 1.0
			DoorDressing.fill_cable(_cable_mesh, door_width, _local_room_sign(), 1.0)
		_cable_mesh.visible = visible_now


# ----------------------------------------------------- barricade animations
# Each runs off the channel's progress (PlayerController "on_progress"), so it
# keeps pace with shaky hands and stops dead if Juan is interrupted.

## True on the frame the animation passes `mark` (0..1).
func _passed(ratio: float, mark: float) -> bool:
	return _anim_mark < mark and ratio >= mark


## The chair's pose: 0 = held upright a step into the room, 1 = jammed.
func _wedge_pose(amount: float) -> Transform3D:
	var away: float = _local_room_sign()
	var e: float = 1.0 - pow(1.0 - clampf(amount, 0.0, 1.0), 3.0)
	var held := Transform3D(Basis(Vector3.RIGHT, away * 0.55), Vector3(0.0, 0.12, away * 0.42))
	return held.interpolate_with(Transform3D.IDENTITY, e) * _wedge_rest


## Swings the chair in and tips it under the lever (first 70%), then three
## shoves bed it home, each a little smaller, with a creak; a thunk to finish.
func _wedge_in(ratio: float) -> void:
	if _leaf == null:
		return
	_show_wedge(true)
	var xf: Transform3D = _wedge_pose(ratio / 0.7)
	if ratio > 0.7:
		var shove: float = (ratio - 0.7) / 0.3 * 3.0
		var kick: float = maxf(sin(fposmod(shove, 1.0) * PI), 0.0) * (0.035 - 0.009 * floorf(shove))
		xf.origin += Vector3(0.0, 0.0, _local_room_sign() * kick)
	_wedge_mesh.transform = xf
	var at: Vector3 = get_center() + Vector3.UP * 0.9
	if _passed(ratio, 0.05):
		SfxSynth.play_at(self, SfxSynth.scrape(), get_center() + Vector3.UP * 0.1, -14.0, 1.4, 12.0)
	for mark: float in [0.78, 0.88, 0.97]:
		if _passed(ratio, mark):
			SfxSynth.play_at(self, SfxSynth.chair_creak(), at, -10.0, randf_range(0.9, 1.1), 14.0)
	if _passed(ratio, 0.995):
		SfxSynth.play_at(self, SfxSynth.thud(), at, -12.0, 1.5, 14.0)
	_anim_mark = ratio


func _wedge_out(ratio: float) -> void:
	if _wedge_mesh == null:
		return
	_wedge_mesh.transform = _wedge_pose(1.0 - ratio)
	if _passed(ratio, 0.02):
		SfxSynth.play_at(self, SfxSynth.chair_creak(), get_center() + Vector3.UP * 0.9, -10.0, 1.2, 14.0)
	_anim_mark = ratio


## Winds the cable round the lever turn by turn (or off again), with the soft
## rasp of the cable every quarter.
func _wind_cable(ratio: float, tying: bool) -> void:
	if _leaf == null:
		return
	var wound: float = maxf(floorf((ratio if tying else 1.0 - ratio) * 28.0) / 28.0, 0.04)
	if _cable_mesh == null:
		_cable_mesh = DoorDressing.build_cable(_leaf, door_width, _local_room_sign(), wound)
		_cable_wound = wound
	_cable_mesh.visible = true
	if not is_equal_approx(wound, _cable_wound):
		_cable_wound = wound
		DoorDressing.fill_cable(_cable_mesh, door_width, _local_room_sign(), minf(wound, 0.999))
	for mark: float in [0.02, 0.27, 0.52, 0.77]:
		if _passed(ratio, mark):
			SfxSynth.play_at(self, SfxSynth.scrape(), get_center() + Vector3.UP, -18.0, randf_range(2.2, 2.6), 8.0)
	_anim_mark = ratio


## Turns the thumb-turn a quarter as Juan locks or unlocks.
func _turn_thumb(ratio: float, locking: bool) -> void:
	if _thumb_turn == null:
		return
	var e: float = ratio * ratio * (3.0 - 2.0 * ratio)
	_thumb_turn.rotation.z = PI * 0.5 * (e if locking else 1.0 - e)


## Puts the barricade visuals back to match the door's real state (after an
## interrupted or refused action).
func _restore_barricade_look() -> void:
	_anim_mark = 0.0
	_update_thumb_turn()
	if _wedge_mesh != null:
		_wedge_mesh.transform = _wedge_rest
		_wedge_mesh.visible = handle_state == HandleState.CHAIR_WEDGED and not is_open
	if _cable_mesh != null:
		var tied: bool = handle_state == HandleState.CABLE_TIED and not is_open
		_cable_mesh.visible = tied
		if tied and not is_equal_approx(_cable_wound, 1.0):
			_cable_wound = 1.0
			DoorDressing.fill_cable(_cable_mesh, door_width, _local_room_sign(), 1.0)


## Sign of the room side along the closed door's local Z axis.
func _local_room_sign() -> float:
	var local_normal: Vector3 = Basis(Vector3.UP, closed_yaw) * Vector3.BACK
	return 1.0 if local_normal.dot(room_side) >= 0.0 else -1.0
