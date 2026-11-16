class_name PoseAI
extends RobotBase
## POSE - a retail mannequin the CpE group fitted with servos for the expo
## booth's red-light/green-light game. The rogue firmware kept the one rule:
## it only moves while nothing is watching it.
##
## Watching means any of:
##   - Juan's eyes: it is on screen, nothing blocks the line of sight, and he
##     can make it out - close by (NAKED_EYE_RANGE) or in the flashlight beam.
##     Not while he is staring at the CCTV on his phone.
##   - the CCTV feed Juan is looking at on his phone.
##
## Unwatched it is fast and silent apart from plastic footfalls, opens
## unlocked doors, and snaps to face its target. Every time it is caught it
## freezes in a new pose with a faint servo click. It drifts towards Juan when
## it has no lead, hunts him once it sees him, and checks noises it hears.

enum State { DOCKED, ROAM, HUNT, INVESTIGATE, OFF }

## Hunting (it has seen or heard Juan) and searching speeds, m/s.
const SPEED: float = 3.9
const SEARCH_SPEED: float = 2.2
## How far each search hop pulls it from where it is towards Juan.
const DRIFT: float = 0.35
const NAKED_EYE_RANGE: float = 6.0
const ROAM_RADIUS: float = 9.0
const ROAM_REPICK: float = 9.0
const STEP_INTERVAL: float = 0.32
const FREEZE_CLICK_RANGE: float = 10.0
const GIVE_UP_DOOR_TIME: float = 5.0
const RETREAT_TIME: float = 9.0

var state: State = State.DOCKED
## True while something watches it (this physics frame).
var is_observed: bool = false
var _servo_ready_ms: int = 0

var _target: Vector3 = Vector3.ZERO
var _roam_timer: float = 0.0
var _step_timer: float = 0.0
var _was_moving: bool = false
var _door: InteractableDoor = null
var _door_timer: float = 0.0
var _retreat_timer: float = 0.0
var _skeleton: Skeleton3D = null
var _hunch_timer: float = 30.0


func _init() -> void:
	display_name = "POSE"
	hostile_id = &"pose"
	vision_range = 18.0
	body_radius = 0.24
	catch_distance = 1.1


func kind() -> StringName:
	return &"pose"


## Frozen under Juan's gaze is as good as stunned.
func can_be_pried() -> bool:
	return is_active and (is_observed or stun_time_left > 0.0)


func get_feet_description() -> String:
	return "Two smooth white plastic feet stand outside the door. Perfectly still."


# ------------------------------------------------------------------ lifecycle

func _on_activated() -> void:
	state = State.ROAM
	_pick_roam_target()


func _on_shutdown() -> void:
	state = State.OFF
	# Power gone: the servos let go and it sags where it stands.
	_set_pose("slump")
	SfxSynth.play_at(self, SfxSynth.latch_click(), get_eye_position(), -6.0, 0.4)


func _on_attack_landed(fatal: bool) -> void:
	SfxSynth.play_at(self, SfxSynth.thud(), get_eye_position() - Vector3.UP * 0.5, 2.0, 1.3)
	SfxSynth.play_at(self, SfxSynth.latch_click(), get_eye_position(), 0.0, 0.6)
	if not fatal:
		# Backs off and waits for the next chance.
		_retreat_timer = RETREAT_TIME
		state = State.ROAM
		_target = random_nav_point(global_position, ROAM_RADIUS)


# ---------------------------------------------------------------------- tick

func _tick(delta: float) -> void:
	is_observed = _check_observed()
	if is_observed:
		if _was_moving:
			_freeze()
		_was_moving = false
		velocity = Vector3(0.0, velocity.y, 0.0)
		_apply_gravity(delta)
		move_and_slide()
		return
	if not _was_moving and Time.get_ticks_msec() > _servo_ready_ms:
		# The moment you look away: a whir in the dark.
		_servo_ready_ms = Time.get_ticks_msec() + 1800
		SfxSynth.play_at(self, SfxSynth.servo(), get_eye_position(), -11.0, randf_range(0.85, 1.05), 18.0)
	_was_moving = true
	_retreat_timer = maxf(_retreat_timer - delta, 0.0)
	_hunch_timer -= delta
	_think(delta)
	if _handle_door(delta):
		return
	var speed: float = (SEARCH_SPEED if state == State.ROAM else SPEED) * get_speed_factor()
	if stuck_count >= 3:
		# This way keeps failing: go somewhere else for now.
		stuck_count = 0
		state = State.ROAM
		_target = random_nav_point(global_position, ROAM_RADIUS)
		_roam_timer = ROAM_REPICK
	var arrived: bool = nav_move_to(_target, speed, delta)
	face_direction(_desired_direction if not arrived else (_target - global_position), delta, 0.0)
	if state == State.HUNT and knows_where():
		face_point(last_known, delta, 0.0)
	_footsteps(delta)
	if _retreat_timer <= 0.0 and try_attack_player():
		return
	if arrived:
		_on_arrived()


func _think(delta: float) -> void:
	if player == null or player.is_dead:
		return
	if _retreat_timer <= 0.0 and can_see_player():
		state = State.HUNT
		remember(player.global_position)
		_target = last_known
		return
	if state == State.ROAM:
		_roam_timer -= delta
		if _roam_timer <= 0.0:
			_pick_roam_target()


func _on_arrived() -> void:
	match state:
		State.HUNT, State.INVESTIGATE:
			# Lost him: search around the spot.
			state = State.ROAM
			_target = random_nav_point(global_position, 5.0)
			_roam_timer = ROAM_REPICK * 0.5
		State.ROAM:
			_pick_roam_target()


## No lead: wander, each hop a little closer to wherever Juan is. It always
## finds its way back to him in the end - just not straight away.
func _pick_roam_target() -> void:
	_roam_timer = ROAM_REPICK
	if player == null:
		_target = random_nav_point(global_position, ROAM_RADIUS)
		return
	# Heads for where it last saw or heard him; with no lead, a vague hunch
	# every so often, otherwise it just wanders.
	if knows_where():
		_target = random_nav_point(point_along_route(last_known, 10.0), 3.0)
	elif _hunch_timer <= 0.0:
		_hunch_timer = HUNCH_INTERVAL
		_target = random_nav_point(point_along_route(hunch(), 12.0), 3.0)
	else:
		_target = random_nav_point(global_position, ROAM_RADIUS)


func _on_heard(origin: Vector3, _noise_type: StringName, audibility: float) -> void:
	if state == State.HUNT or state == State.OFF or audibility < 0.2:
		return
	state = State.INVESTIGATE
	_target = origin
	remember(origin)


# --------------------------------------------------------------- observation

func _check_observed() -> bool:
	if player == null or player.is_dead:
		return false
	var points: Array[Vector3] = [global_position + Vector3.UP * 1.55, global_position + Vector3.UP * 1.0,
		global_position + Vector3.UP * 0.3]
	var cctv: CctvApp = player.cctv
	var on_cameras: bool = player.phone.screen != null and player.phone.screen.is_in_cameras()
	var cam: Camera3D = player.camera
	for p: Vector3 in points:
		if cctv != null and cctv.is_watching(p):
			return true
		if on_cameras or not cam.is_position_in_frustum(p):
			continue
		var distance: float = cam.global_position.distance_to(p)
		if distance > NAKED_EYE_RANGE and not _in_flashlight(p, distance):
			continue
		var query := PhysicsRayQueryParameters3D.create(cam.global_position, p, SIGHT_MASK)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or (hit["position"] as Vector3).distance_to(p) < 0.3:
			return true
	return false


func _in_flashlight(p: Vector3, distance: float) -> bool:
	var phone: PlayerPhoneUI = player.phone
	if not phone.is_flashlight_on or phone._led == null:
		return false
	var led: SpotLight3D = phone._led
	if distance > led.spot_range:
		return false
	var beam: Vector3 = -led.global_basis.z
	return rad_to_deg(beam.angle_to(p - led.global_position)) <= led.spot_angle


# ----------------------------------------------------------------- movement

## Closed door in the way: turn the handle if it can, otherwise give up on
## that route for a while. Returns true while busy with a door.
func _handle_door(delta: float) -> bool:
	if _door == null:
		_door = find_blocking_door()
		_door_timer = 0.0
		if _door == null:
			return false
	if not is_instance_valid(_door) or _door.is_passable():
		_door = null
		return false
	_door_timer += delta
	ground_idle(delta)
	if _door.can_aswang_open():
		if _door_timer >= _door.get_handle_delay():
			_door.set_open(true)
			_door = null
		return true
	# Locked, tied or barricaded: hands are no use here.
	if _door_timer >= GIVE_UP_DOOR_TIME:
		_door = null
		state = State.ROAM
		_target = random_nav_point(global_position, ROAM_RADIUS)
		_roam_timer = ROAM_REPICK
	return true


func _footsteps(delta: float) -> void:
	if Vector2(velocity.x, velocity.z).length() < 0.5:
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	_step_timer = STEP_INTERVAL
	SfxSynth.play_at(self, SfxSynth.metal_step(), global_position + Vector3.UP * 0.05, -9.0, randf_range(1.15, 1.35), 22.0)


# --------------------------------------------------------------------- poses

## Caught: stop dead in a new pose, with a faint servo click if Juan is near.
func _freeze() -> void:
	velocity = Vector3.ZERO
	var poses: Array[String] = ["reach", "point", "arms_out", "one_up", "lowered", "reach"]
	_set_pose(poses[randi() % poses.size()])
	if get_player_distance() < FREEZE_CLICK_RANGE:
		SfxSynth.play_at(self, SfxSynth.latch_click(), get_eye_position(), -16.0, randf_range(0.6, 0.8), 12.0)


## Arm and head directions per pose, in the robot's own frame: -Z is forward,
## +X its left, +Y up.
func _set_pose(pose: String) -> void:
	var sk: Skeleton3D = _get_skeleton()
	if sk == null:
		return
	var left_arm := Vector3(0.12, -1.0, -0.12)
	var right_arm := Vector3(-0.12, -1.0, -0.12)
	var left_fore := left_arm
	var right_fore := right_arm
	var head_tilt: float = randf_range(-0.35, 0.35)
	match pose:
		"reach":
			left_arm = Vector3(0.15, -0.05, -1.0)
			right_arm = Vector3(-0.15, -0.05, -1.0)
			left_fore = Vector3(0.05, 0.0, -1.0)
			right_fore = Vector3(-0.05, 0.0, -1.0)
		"point":
			right_arm = Vector3(-0.1, 0.25, -1.0)
			right_fore = right_arm
			left_fore = Vector3(0.1, -1.0, 0.1)
		"arms_out":
			left_arm = Vector3(1.0, -0.4, -0.25)
			right_arm = Vector3(-1.0, -0.4, -0.25)
			left_fore = Vector3(0.7, -0.7, -0.6)
			right_fore = Vector3(-0.7, -0.7, -0.6)
		"one_up":
			left_arm = Vector3(0.3, 1.0, -0.2)
			left_fore = Vector3(0.1, 1.0, -0.4)
		"slump":
			left_arm = Vector3(0.05, -1.0, -0.05)
			right_arm = Vector3(-0.05, -1.0, -0.05)
			left_fore = Vector3(0.0, -1.0, -0.2)
			right_fore = Vector3(0.0, -1.0, -0.2)
			head_tilt = 0.0
	_aim_bone(sk, "LeftArm_", left_arm)
	_aim_bone(sk, "RightArm_", right_arm)
	_aim_bone(sk, "LeftForeArm_", left_fore)
	_aim_bone(sk, "RightForeArm_", right_fore)
	_turn_head(sk, head_tilt, 0.6 if pose == "slump" else randf_range(-0.15, 0.2))


func _get_skeleton() -> Skeleton3D:
	if _skeleton == null and model != null:
		var found := model.find_children("*", "Skeleton3D", true, false)
		if not found.is_empty():
			_skeleton = found[0]
	return _skeleton


func _bone(sk: Skeleton3D, prefix: String) -> int:
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).begins_with(prefix):
			return i
	return -1


## Points bone `prefix` (towards its first child) along `body_dir`.
func _aim_bone(sk: Skeleton3D, prefix: String, body_dir: Vector3) -> void:
	var i: int = _bone(sk, prefix)
	if i < 0 or sk.get_bone_children(i).is_empty():
		return
	sk.set_bone_pose_rotation(i, sk.get_bone_rest(i).basis.get_rotation_quaternion())
	sk.force_update_all_bone_transforms()
	var child: int = sk.get_bone_children(i)[0]
	var along: Vector3 = (sk.get_bone_global_pose(child).origin - sk.get_bone_global_pose(i).origin).normalized()
	var want: Vector3 = (sk.global_basis.inverse() * (global_basis * body_dir)).normalized()
	var parent_basis: Basis = sk.get_bone_global_pose(sk.get_bone_parent(i)).basis.orthonormalized()
	var turn := Quaternion((parent_basis.inverse() * along).normalized(), (parent_basis.inverse() * want).normalized())
	sk.set_bone_pose_rotation(i, turn * sk.get_bone_pose_rotation(i))
	sk.force_update_all_bone_transforms()


## Tilts the head sideways (`roll`) and forward (`nod`), radians.
func _turn_head(sk: Skeleton3D, roll: float, nod: float) -> void:
	var i: int = _bone(sk, "Head_")
	if i < 0:
		return
	var rest: Quaternion = sk.get_bone_rest(i).basis.get_rotation_quaternion()
	var parent_basis: Basis = sk.get_bone_global_pose(sk.get_bone_parent(i)).basis.orthonormalized()
	var to_skel: Basis = sk.global_basis.inverse() * global_basis
	var forward: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.FORWARD)).normalized()
	var side: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.RIGHT)).normalized()
	var q := Quaternion(forward, roll) * Quaternion(side, -nod)
	sk.set_bone_pose_rotation(i, q * rest)
