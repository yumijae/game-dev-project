class_name PrototypeAI
extends RobotBase
## PROTOTYPE - the CpE group's first build: a bare humanoid frame with exposed
## wiring, shelved on the fourth dock because it was "too unstable". It was in
## the update too, and the malfunction that tripped the breaker started in it.
##
## It runs on its own battery pack, not WARDEN's circuit. So it does NOT wake
## at midnight with the others - it wakes the moment WARDEN's power dies (the
## LP-2F breaker thrown, or the UPS empty), when the server stops holding it.
## Cutting the power kills the other three and sets this one loose.
##
##   - Hunts by sound. Its optics are burnt out: it only sees Juan up close.
##   - Stops to listen, walks towards what it heard, runs at anything loud.
##   - Opens doors, and batters down the ones it can't open.
##   - Its damaged wiring sparks and buzzes, and the emergency lights near it
##     stutter - you can tell it is close.

enum State { DORMANT, LISTEN, STALK, HUNT, OFF }

const WALK_SPEED: float = 1.4
const RUN_SPEED: float = 3.9
const CLOSE_SIGHT: float = 3.0
## Audibility above this makes it run.
const LOUD: float = 0.45
const LISTEN_TIME := Vector2(1.8, 3.5)
const SEARCH_HOP: float = 12.0
const SHOVE_FORCE: float = 22.0
const SHOVE_INTERVAL: float = 1.1
const FLICKER_RANGE: float = 7.0
const RETREAT_TIME: float = 9.0
## In a hunt its arm comes up once Juan is this close.
const WINDUP_RANGE: float = 3.0
## The model only ships an idle sway; walking and running are posed in code.
const IDLE_ANIM := &"Take 001"
## Bone indices in prototype.glb: [thigh, shin, foot] per leg, [upper, fore] per arm.
const LEG_R: Array[int] = [28, 29, 30]
const LEG_L: Array[int] = [33, 34, 35]
const ARM_R: Array[int] = [7, 8]
const ARM_L: Array[int] = [17, 18]
const SPINE: int = 3
const HEAD: int = 6

var state: State = State.DORMANT

var _woken: bool = false
var _target: Vector3 = Vector3.ZERO
var _listen_timer: float = 0.0
var _quiet_timer: float = 0.0
var _door_timer: float = 0.0
var _retreat_timer: float = 0.0
var _spark_timer: float = 2.0
var _anim: AnimationPlayer = null
var _skeleton: Skeleton3D = null
## Gait phase (radians) and how much of a stride is being taken (0 idle .. 1).
var _phase: float = 0.0
var _stride: float = 0.0
var _gait_speed: float = 0.0
# Gestures layered over the walk and the idle sway (see _process). The
# one-shot ones count down from 1 to 0.
var _anim_time: float = 0.0
var _slump: float = 1.0
var _wake: float = 0.0
var _swing: float = 0.0
var _shove: float = 0.0
var _snap: float = 0.0
var _snap_yaw: float = 0.0
var _head_yaw: float = 0.0
var _reaching: bool = false
var _sparks: CPUParticles3D = null
var _buzz: AudioStreamPlayer3D = null
var _lights: Array[OmniLight3D] = []
var _flicker_timer: float = 0.0


func _init() -> void:
	display_name = "PROTOTYPE"
	hostile_id = &"prototype"
	vision_range = CLOSE_SIGHT
	hearing = 1.5
	catch_distance = 1.25
	body_radius = 0.24
	body_height = 1.85
	eye_height = 1.8
	spray_factor = 0.8


func kind() -> StringName:
	return &"prototype"


func get_feet_description() -> String:
	return "Two metal feet, wires trailing between them. Something above them is sparking."


# ------------------------------------------------------------------ lifecycle

func _on_built() -> void:
	_anim = RobotModels.animation_player(model)
	if _anim != null and _anim.has_animation(IDLE_ANIM):
		_anim.get_animation(IDLE_ANIM).loop_mode = Animation.LOOP_LINEAR
		_anim.play(IDLE_ANIM)
		# Stepped by hand in _process, so gestures can be posed on top of it.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var found := model.find_children("*", "Skeleton3D", true, false)
	if not found.is_empty():
		_skeleton = found[0]
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 24
	_sparks.lifetime = 0.5
	_sparks.explosiveness = 0.9
	_sparks.direction = Vector3(0, 0.5, -1)
	_sparks.spread = 80.0
	_sparks.initial_velocity_min = 0.8
	_sparks.initial_velocity_max = 2.4
	_sparks.gravity = Vector3(0, -9.8, 0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.005, 0.005, 0.025)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(0.75, 0.85, 1.0)
	spark_mesh.material = spark_mat
	_sparks.mesh = spark_mesh
	_sparks.particle_flag_align_y = true
	_sparks.position = Vector3(0, 1.45, -0.05)
	add_child(_sparks)
	_buzz = AudioStreamPlayer3D.new()
	_buzz.stream = SfxSynth.server_hum()
	_buzz.unit_size = 1.6
	_buzz.max_distance = 14.0
	_buzz.volume_db = -14.0
	_buzz.pitch_scale = 1.9
	_buzz.position = Vector3.UP * 1.4
	add_child(_buzz)
	_buzz.finished.connect(_buzz.play)


## The midnight wake-up does not reach it: it is not on WARDEN's circuit.
func activate(at: Vector3 = Vector3.INF) -> void:
	if not _woken:
		return
	super(at)


## WARDEN lost power - the server let go of it, and it runs on its own battery.
func on_power_cut(_cause: StringName) -> void:
	if _woken or state == State.OFF or is_disabled:
		return
	_woken = true
	activate()


func _on_activated() -> void:
	player = get_tree().get_first_node_in_group(&"player") as PlayerController
	_gather_lights()
	_spark()
	SfxSynth.play_at(self, SfxSynth.thud(), get_eye_position(), 4.0, 0.5, 30.0)
	SfxSynth.play_at(self, SfxSynth.metal_creak(), get_eye_position(), 0.0, 0.7, 30.0)
	SfxSynth.play_at(self, SfxSynth.servo(), get_eye_position(), -4.0, 0.45, 30.0)
	_buzz.play()
	_wake = 1.0
	state = State.LISTEN
	_listen_timer = 2.5
	# It knows roughly where the last sound in the building came from.
	_target = global_position


func _on_shutdown() -> void:
	state = State.OFF
	_buzz.stop()
	_restore_lights()


func _on_attack_landed(fatal: bool) -> void:
	_spark()
	SfxSynth.play_at(self, SfxSynth.thud(), get_eye_position() - Vector3.UP * 0.5, 4.0, 0.7)
	_swing = 1.0
	if not fatal:
		_retreat_timer = RETREAT_TIME
		state = State.LISTEN
		_listen_timer = RETREAT_TIME


# ---------------------------------------------------------------------- tick

func _tick(delta: float) -> void:
	_retreat_timer = maxf(_retreat_timer - delta, 0.0)
	_quiet_timer += delta
	_ambient(delta)
	if _retreat_timer <= 0.0 and can_see_player():
		state = State.HUNT
		remember(player.global_position)
		_target = last_known
	match state:
		State.LISTEN:
			ground_idle(delta)
			_gait(0.0, delta)
			_listen_timer -= delta
			if _listen_timer <= 0.0:
				# Nothing heard: wander a stretch of the way towards Juan.
				state = State.STALK
				var lead: Vector3 = last_known if knows_where() else hunch(12.0)
				_target = random_nav_point(point_along_route(lead, SEARCH_HOP), 3.0)
		State.STALK:
			_move(WALK_SPEED, delta)
		State.HUNT:
			_move(RUN_SPEED, delta)
			if _retreat_timer <= 0.0:
				try_attack_player()


func _move(speed: float, delta: float) -> void:
	if _handle_door(delta):
		_gait(0.0, delta)
		return
	if stuck_count >= 3:
		stuck_count = 0
		_stop_and_listen()
		return
	var arrived: bool = nav_move_to(_target, speed * get_speed_factor(), delta)
	face_direction(_desired_direction, delta, 6.0 if state == State.STALK else 10.0)
	_gait(Vector2(velocity.x, velocity.z).length(), delta)
	if arrived:
		_stop_and_listen()


func _stop_and_listen() -> void:
	state = State.LISTEN
	_listen_timer = randf_range(LISTEN_TIME.x, LISTEN_TIME.y)


func _on_heard(origin: Vector3, _noise_type: StringName, audibility: float) -> void:
	if not _woken or state == State.OFF or _retreat_timer > 0.0:
		return
	_quiet_timer = 0.0
	_target = origin
	# Its head whips round to the sound before the body follows.
	var to_sound: Vector3 = global_basis.inverse() * (origin - global_position)
	_snap_yaw = clampf(atan2(-to_sound.x, -to_sound.z), -1.3, 1.3)
	_snap = 1.0
	if audibility >= LOUD or state == State.HUNT:
		state = State.HUNT
	else:
		state = State.STALK


# --------------------------------------------------------------------- doors

## Opens a door if it can; otherwise batters it until it gives way.
func _handle_door(delta: float) -> bool:
	var door: InteractableDoor = find_blocking_door()
	_reaching = false
	if door == null:
		_door_timer = 0.0
		return false
	ground_idle(delta)
	face_point(door.get_center(), delta, 8.0)
	_door_timer += delta
	if door.can_robot_open():
		_reaching = true
		if _door_timer >= door.get_handle_delay():
			door.set_open(true)
			_door_timer = 0.0
		return true
	if door.permanently_locked:
		if _door_timer > 2.0:
			_door_timer = 0.0
			_stop_and_listen()
		return true
	if _door_timer >= SHOVE_INTERVAL:
		_door_timer = 0.0
		_spark()
		_shove = 1.0
		door.shove(SHOVE_FORCE * get_aggression())
	return true


# --------------------------------------------------------------------- looks

## Walk timing: stride length, phase, footfalls and the body's bob. The bones
## themselves are posed in _process.
func _gait(speed: float, delta: float) -> void:
	if _skeleton == null:
		return
	var moving: bool = speed > 0.2
	_gait_speed = speed
	_stride = move_toward(_stride, clampf(speed / RUN_SPEED * 1.4, 0.0, 1.0) if moving else 0.0, delta * 4.0)
	if not moving and _stride <= 0.0:
		model.position.y = move_toward(model.position.y, 0.0, delta * 0.3)
		return
	var half_before: int = int(_phase / PI)
	_phase += delta * (4.2 + speed * 1.9)
	if int(_phase / PI) != half_before and _stride > 0.3:
		var run_db: float = lerpf(-6.0, 0.0, clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0))
		SfxSynth.play_at(self, SfxSynth.metal_step(), global_position + Vector3.UP * 0.05, run_db, randf_range(0.72, 0.85), 34.0)
	model.position.y = absf(cos(_phase)) * 0.035 * _stride


## Poses the skeleton from scratch every frame: the walk or the model's idle
## sway first, then whatever it is doing on top. Angles are gathered per bone
## as (pitch, yaw, roll) in the robot's own frame - positive pitch swings a
## hanging limb forward and tips an upright bone back - and applied once.
##
##   docked / shut down   slumped forward, head on its chest
##   waking               unfolds from the slump, head jerking
##   listening            head ticks from side to side in steps
##   heard something      head whips round to the sound
##   closing on Juan      right arm comes up over its head
##   the strike           the arm comes down, the body follows it
##   a door               reaches for the handle, or shoulders it
##   sprayed              arms over its face, head shaking, staggering
func _process(delta: float) -> void:
	if _skeleton == null:
		return
	_anim_time += delta
	var t: float = _anim_time
	_wake = move_toward(_wake, 0.0, delta * 0.55)
	_swing = move_toward(_swing, 0.0, delta * 1.8)
	_shove = move_toward(_shove, 0.0, delta * 1.7)
	_snap = move_toward(_snap, 0.0, delta * 1.3)
	var pose: Dictionary = {}
	_skeleton.reset_bone_poses()
	if state == State.DORMANT or state == State.OFF:
		_slump = move_toward(_slump, 1.0, delta * 1.4)
		_add_slump(pose, _slump)
		_apply_pose(pose)
		return
	_slump = 0.0
	if _stride > 0.0:
		_add_walk(pose)
	elif _anim != null:
		_anim.advance(delta)
	if _wake > 0.0:
		# Power back in the servos one joint at a time.
		_add_slump(pose, pow(_wake, 1.5))
		_turn(pose, HEAD, Vector3(0.0, sin(t * 31.0) * 0.18 * _wake, sin(t * 23.0) * 0.1 * _wake))
	var target_yaw: float = 0.0
	if stun_time_left > 0.0:
		# Whited out: throws its arms over its optics and reels.
		for arm: Array[int] in [ARM_R, ARM_L]:
			pose[arm[0]] = Vector3(2.0, 0.0, 0.0)
			pose[arm[1]] = Vector3(1.6, 0.0, 0.0)
		_turn(pose, SPINE, Vector3(0.2, 0.0, sin(t * 5.0) * 0.1))
		_turn(pose, HEAD, Vector3(0.15, sin(t * 24.0) * 0.35, 0.0))
	else:
		if _snap > 0.0:
			target_yaw = _snap_yaw
		elif state == State.LISTEN and _wake <= 0.0:
			# Sweeps in steps, like a camera on a ratchet.
			target_yaw = snappedf(sin(t * 0.9) * 0.95, 0.32)
			_turn(pose, HEAD, Vector3(0.0, 0.0, sin(t * 0.6) * 0.14))
		if _swing > 0.0:
			# Overhead, then down through him.
			var p: float = 1.0 - _swing
			var down: float = smoothstep(0.12, 0.4, p)
			pose[ARM_R[0]] = Vector3(lerpf(2.7, 0.45, down) * (1.0 - smoothstep(0.65, 1.0, p)), 0.0, 0.0)
			pose[ARM_R[1]] = Vector3(lerpf(0.7, 0.15, down), 0.0, 0.0)
			_turn(pose, SPINE, Vector3(-0.42 * sin(down * PI * 0.5) * (1.0 - smoothstep(0.65, 1.0, p)), 0.0, 0.0))
		elif state == State.HUNT and _retreat_timer <= 0.0 and player != null and get_player_distance() < WINDUP_RANGE:
			# Close enough to hit: the arm goes up. The only warning there is.
			var close: float = 1.0 - clampf((get_player_distance() - catch_distance) / (WINDUP_RANGE - catch_distance), 0.0, 1.0)
			pose[ARM_R[0]] = Vector3(lerpf(float((pose.get(ARM_R[0], Vector3.ZERO) as Vector3).x), 2.7, close), 0.0, 0.0)
			pose[ARM_R[1]] = Vector3(lerpf(0.4, 0.7, close), 0.0, 0.0)
		if _shove > 0.0:
			# Rocks back, then puts its shoulder through the door.
			var q: float = 1.0 - _shove
			var hit: float = sin(clampf((q - 0.2) / 0.5, 0.0, 1.0) * PI)
			_turn(pose, SPINE, Vector3(0.2 * (1.0 - smoothstep(0.0, 0.25, q)) - 0.5 * hit, 0.0, 0.0))
			for arm: Array[int] in [ARM_R, ARM_L]:
				pose[arm[0]] = Vector3(1.1, 0.0, 0.0)
				pose[arm[1]] = Vector3(0.9, 0.0, 0.0)
		elif _reaching:
			pose[ARM_R[0]] = Vector3(1.25, 0.0, 0.0)
			pose[ARM_R[1]] = Vector3(0.25, 0.0, 0.0)
	# The neck moves in sharp, quick steps, never smoothly.
	_head_yaw = lerpf(_head_yaw, target_yaw, minf(delta * 16.0, 1.0))
	_turn(pose, HEAD, Vector3(0.0, _head_yaw, 0.0))
	_apply_pose(pose)


## The stiff, jerky stride: longer and faster at a run, with a forward lean.
func _add_walk(pose: Dictionary) -> void:
	var run: float = clampf((_gait_speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var swing: float = lerpf(0.42, 0.7, run) * _stride
	# Legs: thigh swings, the knee folds on the way through, the foot stays flat-ish.
	for leg: Array[int] in [LEG_R, LEG_L]:
		var p: float = _phase + (0.0 if leg == LEG_R else PI)
		pose[leg[0]] = Vector3(-sin(p) * swing, 0.0, 0.0)
		pose[leg[1]] = Vector3(-maxf(0.0, -cos(p)) * swing * 1.6, 0.0, 0.0)
		pose[leg[2]] = Vector3(maxf(0.0, -cos(p)) * swing * 0.5, 0.0, 0.0)
	# Arms swing against the legs; the elbows stay bent like a guard.
	for arm: Array[int] in [ARM_R, ARM_L]:
		var p: float = _phase + (PI if arm == ARM_R else 0.0)
		pose[arm[0]] = Vector3(-sin(p) * swing * 0.7, 0.0, 0.0)
		pose[arm[1]] = Vector3(0.35 + run * 0.4, 0.0, 0.0)
	pose[SPINE] = Vector3(-run * 0.22, 0.0, 0.0)
	# Something in the neck is loose: the head ticks and twitches.
	pose[HEAD] = Vector3(sin(_phase * 3.7) * 0.05 + (randf_range(-0.12, 0.12) if randf() < 0.04 else 0.0), 0.0, 0.0)


## Power off: folded forward at the waist, head down, arms hanging.
func _add_slump(pose: Dictionary, amount: float) -> void:
	_turn(pose, SPINE, Vector3(-0.42 * amount, 0.0, 0.0))
	_turn(pose, HEAD, Vector3(-0.55 * amount, 0.0, 0.07 * amount))
	for arm: Array[int] in [ARM_R, ARM_L]:
		_turn(pose, arm[0], Vector3(0.3 * amount, 0.0, 0.0))
		_turn(pose, arm[1], Vector3(0.12 * amount, 0.0, 0.0))


## Adds `angles` (pitch, yaw, roll) to whatever bone `i` is already doing.
func _turn(pose: Dictionary, i: int, angles: Vector3) -> void:
	pose[i] = (pose.get(i, Vector3.ZERO) as Vector3) + angles


## Sets every posed bone from its rest pose, parents before children.
func _apply_pose(pose: Dictionary) -> void:
	var bones: Array = pose.keys()
	bones.sort()
	var to_skel: Basis = _skeleton.global_basis.orthonormalized().inverse() * global_basis.orthonormalized()
	for i: int in bones:
		if i >= _skeleton.get_bone_count():
			continue
		var angles: Vector3 = pose[i]
		var parent: int = _skeleton.get_bone_parent(i)
		var parent_basis: Basis = _skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
		var side: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.RIGHT)).normalized()
		var up: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.UP)).normalized()
		var forward: Vector3 = (parent_basis.inverse() * (to_skel * Vector3.FORWARD)).normalized()
		var rest: Quaternion = _skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		_skeleton.set_bone_pose_rotation(i, Quaternion(up, angles.y) * Quaternion(forward, angles.z) * Quaternion(side, angles.x) * rest)
		_skeleton.force_update_bone_child_transform(i)


func _spark() -> void:
	_sparks.restart()
	_sparks.emitting = true
	SfxSynth.play_at(self, SfxSynth.latch_click(), _sparks.global_position, -6.0, randf_range(1.6, 2.2), 14.0)


## Random sparks, and emergency lights stuttering as it passes.
func _ambient(delta: float) -> void:
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = randf_range(1.5, 4.5)
		_spark()
	_flicker_timer -= delta
	if _flicker_timer > 0.0:
		return
	_flicker_timer = 0.06
	for light: OmniLight3D in _lights:
		var base: float = light.get_meta(&"proto_base_energy")
		var d: float = light.global_position.distance_to(global_position)
		if d < FLICKER_RANGE:
			light.light_energy = base * (0.0 if randf() < 0.35 * (1.0 - d / FLICKER_RANGE) + 0.1 else randf_range(0.4, 1.0))
		else:
			light.light_energy = base


func _gather_lights() -> void:
	_lights.clear()
	var school: Node = get_tree().get_first_node_in_group(&"school")
	var root: Node = school.get_node_or_null("Lights") if school != null else null
	if root == null:
		return
	for node: Node in root.get_children():
		var light := node as OmniLight3D
		if light != null and light.visible and light.light_energy > 0.0:
			light.set_meta(&"proto_base_energy", light.light_energy)
			_lights.append(light)


func _restore_lights() -> void:
	for light: OmniLight3D in _lights:
		light.light_energy = light.get_meta(&"proto_base_energy")
