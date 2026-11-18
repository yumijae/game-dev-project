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
## Unwatched it moves in stop-motion: it stands dead still, then - with a
## grind of clockwork gears - it is suddenly a long stride further on, in a
## new pose. It opens unlocked doors and snaps to face its target. Every time it is caught it
## freezes in a new pose with a faint servo click. It drifts towards Juan when
## it has no lead, hunts him once it sees him, and checks noises it hears.

enum State { DOCKED, ROAM, HUNT, INVESTIGATE, OFF }

## Stop-motion movement. Each hop the body runs HOP_SPEED along its path
## for HOP_* metres while the visible model stays put, then the model snaps
## to the new spot; between hops it holds perfectly still for HOLD_*
## seconds. Average speed: ~2 m/s hunting, ~1 m/s searching.
const HOP_SPEED: float = 10.0
const HOP_HUNT: float = 1.8
const HOP_ROAM: float = 1.4
const HOLD_HUNT: float = 0.8
const HOLD_ROAM: float = 1.2
const HOP_MAX_TIME: float = 0.4
## How far each search hop pulls it from where it is towards Juan.
const DRIFT: float = 0.35
const NAKED_EYE_RANGE: float = 6.0
const ROAM_RADIUS: float = 9.0
const ROAM_REPICK: float = 9.0
const FREEZE_CLICK_RANGE: float = 10.0
const GIVE_UP_DOOR_TIME: float = 5.0
const RETREAT_TIME: float = 9.0
## Caught this close, it freezes mid-lunge.
const LUNGE_RANGE: float = 2.6

var state: State = State.DOCKED
## True while something watches it (this physics frame).
var is_observed: bool = false
var _servo_ready_ms: int = 0

var _target: Vector3 = Vector3.ZERO
var _roam_timer: float = 0.0
## Seconds left standing still before the next hop.
var _hold_timer: float = 0.0
## Metres left in the hop in progress (0 = not hopping).
var _hop_left: float = 0.0
## Seconds the hop in progress has run (a blocked hop lands after HOP_MAX_TIME).
var _hop_time: float = 0.0
## Where the model was left standing when the hop began (world space).
var _hop_from: Transform3D = Transform3D.IDENTITY
## Holds the model so it can stay behind while the body hops.
var _stopmotion: Node3D = null
var _was_moving: bool = false
var _door: InteractableDoor = null
var _door_timer: float = 0.0
var _retreat_timer: float = 0.0
var _skeleton: Skeleton3D = null
## Which leg leads in the current stride; swaps on every footfall.
var _left_leads: bool = false
## Height of the lowest foot bone with the legs straight, and the model's own
## resting height: a posed leg lifts its foot, so the body is lowered to match.
var _foot_rest_y: float = INF
var _model_rest_y: float = 0.0
var _hunch_timer: float = 30.0


## Heading for a SearchPlanner waypoint (not a random wander point).
var _searching: bool = false
## Longest it spends getting to one search waypoint.
const SEARCH_LEG_TIME: float = 24.0


## A search waypoint it could not reach in time: skip it.
func _give_up_waypoint() -> void:
	if _searching:
		_searching = false
		search.arrive()


func _init() -> void:
	display_name = "POSE"
	hostile_id = &"pose"
	vision_range = 18.0
	body_radius = 0.24
	catch_distance = 1.1
	# The booth's game-show speaker: bright, a little too slow.
	voice_hz = 175.0
	voice_grit = 0.15
	scare_pitch = 1.05


func kind() -> StringName:
	return &"pose"


func can_open_doors() -> bool:
	return true


## A taser drops it completely: the servos let go and it stays down until
## CONCIERGE comes and reboots it.
func take_taser() -> bool:
	if not is_active:
		return false
	_land()
	knock_down()
	EventBus.ui_notification.emit("POSE drops like a puppet with its strings cut. It isn't moving... for now.", 4.0)
	return true


func get_feet_description() -> String:
	return "Two smooth white plastic feet stand outside the door. Perfectly still."


# ------------------------------------------------------------------ lifecycle

## On its dock before midnight: powered down, head bowed.
func _on_built() -> void:
	if model != null:
		_stopmotion = Node3D.new()
		_stopmotion.name = "StopMotion"
		add_child(_stopmotion)
		model.reparent(_stopmotion, false)
	_set_pose.call_deferred("slump")


func _on_activated() -> void:
	state = State.ROAM
	_pick_roam_target()
	# Rebooted where it lay (after a taser): it straightens up, servos whining.
	_set_pose("stride")
	SfxSynth.play_at(self, SfxSynth.pose_unfreeze(), get_eye_position(), -8.0, 0.8, 18.0)


func _on_shutdown() -> void:
	state = State.OFF
	_land()
	# Power gone: the servos let go and it sags where it stands.
	_set_pose("slump")
	SfxSynth.play_at(self, SfxSynth.pose_slump(), get_eye_position(), -6.0, 1.0)


func _on_attack_landed(fatal: bool) -> void:
	SfxSynth.play_at(self, SfxSynth.thud(), get_eye_position() - Vector3.UP * 0.5, 2.0, 1.3)
	SfxSynth.play_at(self, SfxSynth.pose_freeze(), get_eye_position(), 0.0, 0.8)
	if not fatal:
		# Backs off and waits for the next chance.
		_retreat_timer = RETREAT_TIME
		_searching = false
		state = State.ROAM
		_target = retreat_point()
		_roam_timer = ROAM_REPICK


# ---------------------------------------------------------------------- tick

func _tick(delta: float) -> void:
	is_observed = _check_observed()
	if is_observed:
		_land()
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
		SfxSynth.play_at(self, SfxSynth.pose_unfreeze(), get_eye_position(), -11.0, randf_range(0.9, 1.05), 18.0)
	_was_moving = true
	_retreat_timer = maxf(_retreat_timer - delta, 0.0)
	_hunch_timer -= delta
	_think(delta)
	# Answering another robot's call: off to open its door (unless it has
	# Juan in sight - he comes first).
	if state != State.HUNT and is_helping():
		if _hop_gate(delta):
			var before: Vector3 = global_position
			help_step(HOP_SPEED * get_speed_factor(), delta)
			face_direction(_desired_direction, delta, 0.0)
			_hop_moved(before, false)
		return
	if _handle_door(delta):
		_land()
		return
	if not _hop_gate(delta):
		if _retreat_timer <= 0.0 and try_attack_player():
			return
		return
	var speed: float = HOP_SPEED * get_speed_factor()
	if stuck_count >= 3:
		# This way keeps failing: go somewhere else for now.
		stuck_count = 0
		_give_up_waypoint()
		state = State.ROAM
		_target = random_nav_point(global_position, ROAM_RADIUS)
		_roam_timer = ROAM_REPICK
	var before: Vector3 = global_position
	var arrived: bool = nav_move_to(_target, speed, delta)
	face_direction(_desired_direction if not arrived else (_target - global_position), delta, 0.0)
	if state == State.HUNT and knows_where():
		face_point(last_known, delta, 0.0)
	_hop_moved(before, arrived)
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
			_give_up_waypoint()
			_pick_roam_target()


func _on_arrived() -> void:
	match state:
		State.HUNT, State.INVESTIGATE:
			# Lost him: search the rooms he most likely went to.
			state = State.ROAM
			if begin_search():
				_pick_roam_target()
			else:
				_target = random_nav_point(global_position, 5.0)
				_roam_timer = ROAM_REPICK * 0.5
		State.ROAM:
			if _searching:
				_searching = false
				search_arrived()
			_pick_roam_target()


## No lead: wander, each hop a little closer to wherever Juan is. It always
## finds its way back to him in the end - just not straight away.
func _pick_roam_target() -> void:
	_roam_timer = ROAM_REPICK
	_searching = false
	if player == null:
		_target = random_nav_point(global_position, ROAM_RADIUS)
		return
	if _retreat_timer > 0.0:
		_target = retreat_point()
		return
	# Searches the rooms round its last lead; with no lead, a vague hunch
	# every so often, otherwise it just wanders.
	var waypoint: Vector3 = next_search_waypoint()
	if waypoint != Vector3.INF:
		_target = waypoint
		_searching = true
		_roam_timer = SEARCH_LEG_TIME
		return
	if knows_where():
		_target = random_nav_point(point_along_route(last_known, 10.0), 3.0)
	elif _hunch_timer <= 0.0:
		_hunch_timer = HUNCH_INTERVAL
		_target = random_nav_point(point_along_route(hunch(), 12.0), 3.0)
	else:
		_target = random_nav_point(global_position, ROAM_RADIUS)


func _on_found_hidden(at: Vector3) -> void:
	if state != State.OFF and _retreat_timer <= 0.0:
		state = State.HUNT
		_target = at


func _on_heard(origin: Vector3, _noise_type: StringName, audibility: float) -> void:
	if state == State.HUNT or state == State.OFF or audibility < 0.2:
		return
	_searching = false
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
	# Whatever Juan is actually looking through: his eyes, or the gap under a
	# door while he peeks (his head camera is not what he sees then).
	var cam: Camera3D = player.get_viewport().get_camera_3d()
	if cam == null:
		cam = player.camera
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
	if _door.can_robot_open():
		if _door_timer >= _door.get_handle_delay():
			_door.set_open(true)
			_door = null
		return true
	# Locked, tied or barricaded: hands are no use here.
	if _door_timer >= GIVE_UP_DOOR_TIME:
		turn_from_door(_door)
		_door = null
		_give_up_waypoint()
		state = State.ROAM
		_target = random_nav_point(global_position, ROAM_RADIUS)
		_roam_timer = ROAM_REPICK
	return true


## Stop-motion gate. While holding it stands perfectly still and returns
## false; when the hold runs out a hop starts (gears grind, the model is left
## behind) and it returns true until the hop's distance is covered.
func _hop_gate(delta: float) -> bool:
	if _hop_left > 0.0:
		_hop_time += delta
		return true
	velocity.x = 0.0
	velocity.z = 0.0
	_hold_timer -= delta
	if _hold_timer > 0.0:
		ground_idle(delta)
		return false
	_hop_left = HOP_HUNT if state == State.HUNT else HOP_ROAM
	_hop_time = 0.0
	_hop_from = _stopmotion.global_transform if _stopmotion != null else global_transform
	SfxSynth.play_at(self, SfxSynth.pose_gears(), get_eye_position(), -4.0, randf_range(0.78, 0.92), 24.0)
	return true


## Book-keeping after a hop frame: keep the model where it was, and land once
## the hop's distance is covered (or the path ends).
func _hop_moved(before: Vector3, arrived: bool) -> void:
	_hop_left -= Vector2(global_position.x - before.x, global_position.z - before.z).length()
	if _hop_left <= 0.0 or arrived or _hop_time >= HOP_MAX_TIME:
		_land(true)
	elif _stopmotion != null:
		_stopmotion.global_transform = _hop_from


## Ends any hop: the body stops dead and the model snaps to it in a new
## stride, with a dry plastic footfall.
func _land(hop_done: bool = false) -> void:
	var was_hopping: bool = hop_done or _hop_left > 0.0
	_hop_left = 0.0
	if _stopmotion != null:
		_stopmotion.transform = Transform3D.IDENTITY
	if not was_hopping:
		return
	velocity.x = 0.0
	velocity.z = 0.0
	_hold_timer = (HOLD_HUNT if state == State.HUNT else HOLD_ROAM) * randf_range(0.85, 1.2) / get_speed_factor()
	_left_leads = not _left_leads
	_set_pose("stride")
	SfxSynth.play_at(self, SfxSynth.pose_step(), global_position + Vector3.UP * 0.05, -9.0, randf_range(0.85, 1.0), 22.0)


# --------------------------------------------------------------------- poses

## Caught: stop dead in a pose that fits what it was doing, staring straight
## at Juan, with a faint servo click if he is near.
##   within arm's reach      -> lunging at him
##   hunting or checking     -> frozen mid-run, reaching or pointing
##   wandering               -> one of the booth's display poses
func _freeze() -> void:
	velocity = Vector3.ZERO
	var pose: String
	if get_player_distance() < LUNGE_RANGE:
		pose = "lunge"
	elif state == State.HUNT or state == State.INVESTIGATE:
		pose = ["stride_reach", "stride_point", "stride_reach", "stride"].pick_random()
	else:
		pose = ["point", "arms_out", "one_up", "lowered", "reach", "stride"].pick_random()
	_set_pose(pose, true)
	if get_player_distance() < FREEZE_CLICK_RANGE:
		SfxSynth.play_at(self, SfxSynth.pose_freeze(), get_eye_position(), -16.0, randf_range(0.9, 1.1), 12.0)


## Limb directions per pose, in the robot's own frame: -Z is forward, +X its
## left, +Y up. With `look_at_juan` the head turns to stare at him.
func _set_pose(pose: String, look_at_juan: bool = false) -> void:
	var sk: Skeleton3D = _get_skeleton()
	if sk == null:
		return
	var left_arm := Vector3(0.12, -1.0, -0.12)
	var right_arm := Vector3(-0.12, -1.0, -0.12)
	var left_fore := left_arm
	var right_fore := right_arm
	var head_roll: float = randf_range(-0.35, 0.35)
	var head_nod: float = randf_range(-0.15, 0.2)
	var lean: float = 0.0
	var striding: bool = false
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
			head_roll = 0.0
			head_nod = 0.6
		"stride":
			# A runner's arms: the one opposite the leading leg swings forward.
			striding = true
			lean = 0.16
			var fwd_arm := Vector3(0.0, -0.75, -0.65)
			var back_arm := Vector3(0.0, -0.85, 0.5)
			var fwd_fore := Vector3(0.0, -0.1, -1.0)
			var back_fore := Vector3(0.0, -1.0, 0.1)
			left_arm = (back_arm if _left_leads else fwd_arm) + Vector3(0.12, 0.0, 0.0)
			right_arm = (fwd_arm if _left_leads else back_arm) + Vector3(-0.12, 0.0, 0.0)
			left_fore = back_fore if _left_leads else fwd_fore
			right_fore = fwd_fore if _left_leads else back_fore
		"stride_reach":
			striding = true
			lean = 0.2
			left_arm = Vector3(0.18, -0.1, -1.0)
			right_arm = Vector3(-0.18, -0.25, -1.0)
			left_fore = Vector3(0.05, 0.1, -1.0)
			right_fore = Vector3(-0.05, -0.05, -1.0)
		"stride_point":
			striding = true
			lean = 0.12
			right_arm = Vector3(-0.1, 0.1, -1.0)
			right_fore = right_arm
			left_arm = Vector3(0.2, -0.9, 0.35)
			left_fore = Vector3(0.1, -1.0, 0.0)
		"lunge":
			# Both hands out for his throat, weight thrown forward.
			striding = true
			lean = 0.34
			left_arm = Vector3(0.22, 0.12, -1.0)
			right_arm = Vector3(-0.22, 0.12, -1.0)
			left_fore = Vector3(-0.12, 0.2, -1.0)
			right_fore = Vector3(0.12, 0.2, -1.0)
			head_roll = randf_range(0.2, 0.45) * (1.0 if randf() < 0.5 else -1.0)
	# Spine first: the arms and head are aimed in body space on top of it.
	_tilt_bone(sk, "Spine_", 0.0, lean, 0.0)
	_aim_bone(sk, "LeftArm_", left_arm)
	_aim_bone(sk, "RightArm_", right_arm)
	_aim_bone(sk, "LeftForeArm_", left_fore)
	_aim_bone(sk, "RightForeArm_", right_fore)
	_pose_legs(sk, striding)
	var head_yaw: float = 0.0
	if look_at_juan and player != null:
		var to_juan: Vector3 = global_basis.inverse() * (player.get_head_position() - (global_position + Vector3.UP * 1.6))
		head_yaw = clampf(atan2(-to_juan.x, -to_juan.z), -1.3, 1.3)
		head_nod = clampf(-atan2(to_juan.y, Vector2(to_juan.x, to_juan.z).length()), -0.6, 0.7) - lean
	_tilt_bone(sk, "Head_", head_roll, head_nod, head_yaw)


## Legs: straight, or split in a stride with the leading knee bent. The body
## is then lowered until the lower foot is back on the floor.
func _pose_legs(sk: Skeleton3D, striding: bool) -> void:
	if _foot_rest_y == INF:
		_model_rest_y = model.position.y
		_foot_rest_y = _lowest_foot(sk)
	var lead: String = "Left" if _left_leads else "Right"
	var trail: String = "Right" if _left_leads else "Left"
	var side: float = 1.0 if _left_leads else -1.0
	if striding:
		_aim_bone(sk, lead + "UpLeg_", Vector3(0.06 * side, -1.0, -0.62))
		_aim_bone(sk, lead + "Leg_", Vector3(0.0, -1.0, 0.18))
		_aim_bone(sk, trail + "UpLeg_", Vector3(-0.06 * side, -1.0, 0.38))
		_aim_bone(sk, trail + "Leg_", Vector3(0.0, -0.85, 0.6))
	else:
		for prefix: String in ["LeftUpLeg_", "LeftLeg_", "RightUpLeg_", "RightLeg_"]:
			var i: int = _bone(sk, prefix)
			if i >= 0:
				sk.reset_bone_pose(i)
		sk.force_update_all_bone_transforms()
	model.position.y = _model_rest_y - (_lowest_foot(sk) - _foot_rest_y)


## Height of the lowest foot or toe bone, in the robot's own frame, as if the
## model sat at its resting height.
func _lowest_foot(sk: Skeleton3D) -> float:
	var lowest: float = INF
	var to_body: Transform3D = global_transform.affine_inverse() * sk.global_transform
	for i in sk.get_bone_count():
		var bone_name: String = sk.get_bone_name(i)
		if bone_name.contains("Foot_") or bone_name.contains("ToeBase_"):
			lowest = minf(lowest, (to_body * sk.get_bone_global_pose(i).origin).y)
	return lowest - (model.position.y - _model_rest_y)


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


## Turns bone `prefix` from its rest pose, in the robot's own frame: `roll`
## tips it sideways, `nod` forward, `yaw` to its left. Radians.
func _tilt_bone(sk: Skeleton3D, prefix: String, roll: float, nod: float, yaw: float) -> void:
	var i: int = _bone(sk, prefix)
	if i < 0:
		return
	var rest: Quaternion = sk.get_bone_rest(i).basis.get_rotation_quaternion()
	var parent_basis: Basis = sk.get_bone_global_pose(sk.get_bone_parent(i)).basis.orthonormalized()
	var to_skel: Basis = sk.global_basis.orthonormalized().inverse() * global_basis.orthonormalized()
	var forward: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.FORWARD)).normalized()
	var side: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.RIGHT)).normalized()
	var up: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.UP)).normalized()
	var q := Quaternion(up, yaw) * Quaternion(forward, roll) * Quaternion(side, -nod)
	sk.set_bone_pose_rotation(i, q * rest)
	sk.force_update_all_bone_transforms()


# ----------------------------------------------------------------- taunts

## It still runs the booth's red-light / green-light game.
func taunt_lines() -> Dictionary:
	return {
		&"spotted": ["Red light. ...I saw you move.", "There you are. Don't. Move.", "Found you. Now we play."],
		&"chase": ["Green light. Green light. Green light.", "You can't watch me forever.", "Blink for me.",
			"Every time you look away, I get closer."],
		&"lost": ["Hide, then. I don't get tired.", "The game isn't over until I tag you."],
		&"hiding": ["Still as a statue... just like me.", "I can stand here all night.", "Come out. It's your turn."],
		&"roam": ["Red light... green light...", "Who wants to play?", "Hold your pose."],
		&"hit": ["Tag. One more and you're out."],
	}
