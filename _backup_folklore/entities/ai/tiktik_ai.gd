class_name TiktikAI
extends AswangBase
## The Tiktik / Wakwak. Lives in the 2F and 3F ceiling crawlspaces and on the
## window ledges outside them.
##
## It is never seen while it crawls: only ceiling dust and its reversed call
## (see TiktikReverseAudio) give it away. It creeps over whatever it hears or
## smells, hangs above Juan, and drops when he stays under it too long.
## Shining the phone's white LED straight at the window or ceiling tile where
## it is perched sends it BERSERK - an immediate, glass-shattering ambush.

enum State { ROOST, CRAWL, STALK, DROP, HUNT, RETREAT }

const HOME_FLOORS: Array[int] = [1, 2]
const CEILING_OFFSET: float = 3.3
const CRAWL_SPEED: float = 2.0
const STALK_SPEED: float = 2.6
const HUNT_SPEED: float = 5.6
const BERSERK_SPEED: float = 7.2
const STALK_RADIUS: float = 3.0
const STALK_LOSE_RADIUS: float = 8.5
const STRIKE_DELAY: float = 9.0
const HUNT_TIME: float = 7.0
const BERSERK_HUNT_TIME: float = 11.0
const DROP_TIME: float = 0.6
const BERSERK_DROP_TIME: float = 0.25
const ROOST_TIME_MIN: float = 8.0
const ROOST_TIME_MAX: float = 18.0
const LINGER_TIME: float = 4.0
const DUST_INTERVAL: float = 1.3
const BEAM_CONE: float = 9.0
const BEAM_RANGE: float = 14.0
const DROP_NOISE: float = 14.0
const DOOR_CLAW_TIME: float = 1.6
const STIMULUS_MEMORY: float = 6.0
## Metres covered by one full cycle (two steps) of its stride.
const STRIDE_CYCLE: float = 1.7

var state: State = State.ROOST
var current_floor: int = 2
var is_berserk: bool = false

var _audio: TiktikReverseAudio = null
## Each perch is {"position": Vector3, "window": JalousieWindow or null, "floor": int}.
var _perches: Array[Dictionary] = []
var _perch: Dictionary = {}
var _target: Vector3 = Vector3.ZERO
var _target_is_perch: bool = false
var _state_time: float = 0.0
var _state_duration: float = 0.0
var _strike_timer: float = 0.0
var _dust_timer: float = 0.0
var _time_since_stimulus: float = 999.0
var _scent_timer: float = 0.0
var _drop_from: Vector3 = Vector3.ZERO
var _drop_to: Vector3 = Vector3.ZERO
var _claw_timer: float = 0.0

# Joints the animation turns; left before right.
var _body: Node3D = null
var _head: Node3D = null
var _jaw: Node3D = null
var _tongue: Node3D = null
var _arms: Array[AswangRig.Limb] = []
var _arm_targets: Array[Vector3] = []
var _legs: Array[AswangRig.Limb] = []
var _wings: Array[MeshInstance3D] = []
var _wing_phase: float = 0.0
var _twitch_timer: float = 0.0
var _head_target: Vector3 = Vector3.ZERO
var _wing_open: float = 0.0


func _init() -> void:
	aswang_id = &"tiktik"
	display_name = "The Tiktik"
	hearing = 1.3
	sniff_radius = 12.0
	vision_range = 12.0
	vision_fov = 200.0
	catch_distance = 1.2


## A starved, hunched thing between a bird and a man: a narrow beaked skull,
## arms that reach the floor, bird legs that bend the wrong way, wings folded
## against a back where every vertebra shows, and the thread-thin tongue.
func _build_visual() -> void:
	var pelt := Color(0.085, 0.075, 0.08)
	var bone := Color(0.7, 0.64, 0.5)
	var look: Dictionary = {"wet": 0.6, "bump": 1.6}
	_body = add_joint(visual, Vector3.ZERO, "Body")

	var torso := AswangMesh.new()
	torso.tube([Vector3(0.0, 0.8, 0.06), Vector3(0.0, 1.0, 0.1), Vector3(0.0, 1.2, 0.09), Vector3(0.0, 1.4, 0.0),
		Vector3(0.0, 1.5, -0.08)],
		[Vector2(0.1, 0.075), Vector2(0.072, 0.058), Vector2(0.14, 0.1), Vector2(0.13, 0.08), Vector2(0.045, 0.045)],
		Vector3.BACK, 12)
	add_flesh(_body, torso, pelt, {"wet": 0.6, "bump": 1.6, "gaunt": 0.85, "ridge_spacing": 0.05})
	var spine := AswangMesh.new()
	for i: int in 9:
		var t: float = float(i) / 8.0
		var y: float = lerpf(0.88, 1.44, t)
		var z: float = lerpf(0.13, 0.07, t) + 0.065 * sin(t * PI)
		spine.spike(Vector3(0.0, y, z - 0.02), Vector3(0.0, y + 0.012, z + 0.04), 0.017, 6)
	add_flesh(_body, spine, pelt, look)

	_head = add_joint(_body, Vector3(0.0, 1.52, -0.1), "Head")
	var skull := AswangMesh.new()
	skull.tube([Vector3(0.0, 0.02, 0.06), Vector3(0.0, 0.05, -0.02), Vector3(0.0, 0.03, -0.12), Vector3(0.0, -0.01, -0.22),
		Vector3(0.0, -0.04, -0.3)],
		[Vector2(0.06, 0.065), Vector2(0.072, 0.07), Vector2(0.05, 0.045), Vector2(0.028, 0.024), Vector2(0.012, 0.01)],
		Vector3.UP, 12)
	add_flesh(_head, skull, pelt, {"wet": 0.7, "bump": 1.2})
	var teeth := AswangMesh.new()
	for side: float in [-1.0, 1.0]:
		for i: int in 6:
			var x: float = side * (0.04 - float(i) * 0.0055)
			var z: float = -0.1 - float(i) * 0.031
			var y: float = 0.0 - float(i) * 0.0075
			teeth.spike(Vector3(x, y, z), Vector3(x, y - 0.03, z - 0.006), 0.005, 4)
	add_flesh(_head, teeth, bone, {"wet": 0.9, "veins": 0.0, "bump": 0.3, "breathe": 0.0})
	for side: float in [-1.0, 1.0]:
		add_eye(_head, Vector3(side * 0.056, 0.055, -0.075), 0.02, Color(0.9, 0.95, 0.4), 3.0)
	_jaw = add_joint(_head, Vector3(0.0, -0.005, -0.03), "Jaw")
	var jaw := AswangMesh.new()
	jaw.tube([Vector3(0.0, -0.01, 0.0), Vector3(0.0, -0.04, -0.13), Vector3(0.0, -0.055, -0.26)],
		[Vector2(0.036, 0.013), Vector2(0.022, 0.009), Vector2(0.008, 0.006)], Vector3.UP, 8)
	add_flesh(_jaw, jaw, pelt, look)
	# The long, thread-thin tongue.
	_tongue = add_joint(_jaw, Vector3(0.0, -0.015, -0.08), "Tongue")
	var tongue_points: Array = []
	var tongue_radii: Array = []
	for k: int in 8:
		var f: float = float(k)
		tongue_points.append(Vector3(sin(f * 1.3) * 0.03, -f * f * 0.012, -f * 0.1))
		tongue_radii.append(lerpf(0.007, 0.002, f / 7.0))
	var tongue := AswangMesh.new()
	tongue.tube(tongue_points, tongue_radii, Vector3.UP, 6, 3)
	add_sway(add_flesh(_tongue, tongue, Color(0.5, 0.1, 0.13), {"wet": 1.0, "veins": 0.3, "breathe": 0.0}),
		0.8, 0.06, 45.0, 4.0, 0.045)

	for side: float in [-1.0, 1.0]:
		var arm: AswangRig.Limb = AswangRig.make_limb(_body, Vector3(side * 0.16, 1.4, 0.0), 0.46, 0.5,
			Vector3(side * 0.5, 0.2, 1.0), Vector3(side * 0.24, 0.5, -0.32), false)
		_arms.append(arm)
		_arm_targets.append(arm.rest)
		var upper_arm := AswangMesh.new()
		upper_arm.tube([Vector3.ZERO, Vector3(0.0, -0.46, 0.0)], [0.04, 0.027], Vector3.BACK, 8)
		add_flesh(arm.root, upper_arm, pelt, look)
		var forearm := AswangMesh.new()
		forearm.tube([Vector3.ZERO, Vector3(0.0, -0.5, 0.0)], [0.027, 0.019], Vector3.BACK, 8)
		add_flesh(arm.mid, forearm, pelt, look)
		var hand := AswangMesh.new()
		hand.tube([Vector3(0.0, 0.02, 0.0), Vector3(0.0, -0.07, 0.0)], [0.019, Vector2(0.026, 0.014)], Vector3.BACK, 6, 2)
		for finger: int in 3:
			var spread: float = (float(finger) - 1.0) * 0.035
			var knuckle := Vector3(spread * 0.5, -0.06, 0.0)
			var tip := Vector3(spread * 1.8, -0.29, -0.05)
			hand.tube([knuckle, knuckle.lerp(tip, 0.5) + Vector3(0.0, 0.0, 0.03), tip], [0.011, 0.008, 0.006], Vector3.BACK, 5, 2)
			hand.spike(tip, tip + Vector3(spread * 0.4, -0.07, -0.03), 0.007, 4)
		add_flesh(arm.end, hand, pelt, look)

		# Bird legs: the joint you see bends backwards.
		var leg: AswangRig.Limb = AswangRig.make_limb(_body, Vector3(side * 0.085, 0.84, 0.06), 0.42, 0.42,
			Vector3.BACK, Vector3(side * 0.1, 0.06, 0.03))
		_legs.append(leg)
		var thigh := AswangMesh.new()
		thigh.tube([Vector3(0.0, 0.02, 0.0), Vector3(0.0, -0.42, 0.0)], [0.06, 0.035], Vector3.BACK, 8)
		add_flesh(leg.root, thigh, pelt, look)
		var shank := AswangMesh.new()
		shank.tube([Vector3.ZERO, Vector3(0.0, -0.42, 0.0)], [0.033, 0.021], Vector3.BACK, 8)
		add_flesh(leg.mid, shank, pelt, look)
		var foot := AswangMesh.new()
		for toe: float in [-1.0, 0.0, 1.0]:
			var heel := Vector3(toe * 0.012, -0.02, -0.01)
			var claw := Vector3(toe * 0.07, -0.04, -0.16)
			foot.tube([heel, claw], [0.014, 0.009], Vector3.UP, 5, 2)
			foot.spike(claw, claw + Vector3(toe * 0.01, -0.012, -0.05), 0.008, 4)
		foot.spike(Vector3(0.0, -0.02, 0.01), Vector3(0.0, -0.045, 0.1), 0.012, 4)
		add_flesh(leg.end, foot, pelt, look)

		var wing: MeshInstance3D = add_wing(_body, Vector3(side * 0.07, 1.36, 0.1), side, 0.95, 0.55,
			Color(0.14, 0.1, 0.1), pelt)
		_wings.append(wing)
	_audio = TiktikReverseAudio.new()
	_audio.name = "ReverseAudio"
	add_child(_audio)
	_audio.position.y = 1.2


## It stalks crouched on bird legs with its knuckles walking beside them, and
## comes up reaching when it hunts. Nothing about it moves smoothly except
## the tongue.
func _animate(delta: float) -> void:
	var moving: float = clampf(anim_speed / 1.2, 0.0, 1.0)
	var hunting: bool = state == State.HUNT or state == State.DROP
	var phase: float = anim_distance / STRIDE_CYCLE * TAU
	var stride: float = minf(STRIDE_CYCLE * 0.5, 0.8) * moving
	var strike: float = sin(anim_strike * PI)
	var crouch: float = 0.06 if hunting else 0.16
	_body.position = Vector3(-sin(phase) * 0.03 * moving,
		-crouch - 0.04 * moving + cos(phase * 2.0) * 0.022 * moving + sin(anim_time * 2.9) * 0.006, -0.12 * strike)
	_body.rotation = Vector3(-0.1 - 0.12 * moving - 0.25 * strike, sin(phase) * 0.1 * moving, -anim_turn * 0.05)
	var to_body: Transform3D = _body.transform.affine_inverse()
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var offset: float = 0.0 if i == 0 else PI
		var step: Vector3 = AswangRig.step_offset(phase + offset, stride, 0.2 * moving)
		_legs[i].solve(to_body * (Vector3(side * 0.1, 0.06, 0.03) + step), -step.y * 2.0)
		# Each hand goes down as the opposite foot does.
		var hand_step: Vector3 = AswangRig.step_offset(phase + offset + PI, stride * 0.7, 0.14 * moving)
		var reach: Vector3 = to_body * (Vector3(side * 0.26, 0.34 + sin(anim_time * 1.2 + float(i) * 2.0) * 0.02, -0.34) + hand_step)
		if hunting and player != null and is_instance_valid(player):
			# Arms up and out for him, fingers working.
			var aim: Vector3 = (to_local(player.get_head_position()) - Vector3(0.0, 1.3, 0.0)).limit_length(0.75)
			reach = to_body * (Vector3(side * 0.2, 1.25 + sin(anim_time * 7.0 + float(i) * 3.0) * 0.04, -0.15) + aim * 0.8)
		# A swipe: both claws rake down and across.
		reach += Vector3(-side * 0.18, -0.45, -0.1) * strike
		_arm_targets[i] = _arm_targets[i].lerp(reach, minf(delta * 9.0, 1.0))
		_arms[i].solve(_arm_targets[i])

	# The head never drifts: it snaps from one angle to the next, like a bird's.
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(0.12, 1.3)
		_head_target = Vector3(randf_range(-0.3, 0.25), randf_range(-0.75, 0.75), randf_range(-0.55, 0.55))
		if hunting and player != null and is_instance_valid(player):
			# On the hunt every snap lands back on Juan.
			var local: Vector3 = to_local(player.get_head_position())
			_head_target.y = clampf(atan2(-local.x, -local.z), -1.2, 1.2) + randf_range(-0.12, 0.12)
			_head_target.x = randf_range(-0.05, 0.3)
	_head.rotation = _head.rotation.lerp(_head_target - Vector3(_body.rotation.x, 0.0, 0.0), minf(delta * 26.0, 1.0))
	_jaw.rotation.x = -maxf(0.12 + 0.07 * sin(anim_time * 13.0), strike * 0.8)
	_tongue.rotation.y = sin(anim_time * 5.0) * 0.2
	_tongue.rotation.x = sin(anim_time * 3.1) * 0.12

	# Wings stay folded on the stalk and come open for the kill.
	_wing_open = move_toward(_wing_open, 1.0 if hunting else 0.0, delta * 3.0)
	_wing_phase += delta * lerpf(2.3, 17.0, _wing_open)
	var beat: float = sin(_wing_phase) * lerpf(0.03, 0.28, _wing_open)
	var curl: float = -cos(_wing_phase - 0.9) * lerpf(0.02, 0.3, _wing_open)
	for i: int in _wings.size():
		var side: float = -1.0 if i == 0 else 1.0
		_wings[i].rotation.y = -side * lerpf(0.95, 0.2, _wing_open)
		_wings[i].rotation.z = side * (lerpf(-0.5, 0.1, _wing_open) + beat)
		set_wing_curl(_wings[i], curl, 0.95)


func _on_activated() -> void:
	_collect_perches()
	body_shape.disabled = true
	if _perches.is_empty():
		_perch = {"position": global_position, "window": null, "floor": current_floor}
	else:
		_perch = _nearest_perch(global_position)
	_begin_roost()
	_audio.is_calling = true


## Sensing happens from the room below, not from inside the ceiling.
func get_eye_position() -> Vector3:
	if state == State.HUNT:
		return super.get_eye_position()
	return Vector3(global_position.x, Campus.floor_y(current_floor) + 2.6, global_position.z)


func get_feet_description() -> String:
	return "Long fingers on the floor. Scratching. Those are not feet."


# ---------------------------------------------------------------- state logic

func _tick(delta: float) -> void:
	_state_time += delta
	_time_since_stimulus += delta
	if state in [State.ROOST, State.CRAWL, State.STALK]:
		_scent_timer += delta
		if _scent_timer >= 2.0:
			_scent_timer = 0.0
			_sniff()
		if _check_flashlight():
			return
	match state:
		State.ROOST:
			_tick_roost()
		State.CRAWL:
			_tick_crawl(delta)
		State.STALK:
			_tick_stalk(delta)
		State.DROP:
			_tick_drop()
		State.HUNT:
			_tick_hunt(delta)
		State.RETREAT:
			_tick_retreat()


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	set_state(State.keys()[new_state])


func _begin_roost() -> void:
	global_position = _perch["position"]
	current_floor = _perch["floor"]
	visible = _perch["window"] != null
	body_shape.disabled = true
	is_berserk = false
	_state_duration = randf_range(ROOST_TIME_MIN, ROOST_TIME_MAX) / get_aggression()
	_enter(State.ROOST)


func _tick_roost() -> void:
	if _state_time < _state_duration:
		return
	# Nothing stirring here; move to another perch.
	var next: Dictionary = _random_perch()
	if next.is_empty():
		_state_time = 0.0
		return
	_begin_crawl(next["position"], true, next)


func _begin_crawl(target: Vector3, to_perch: bool, perch: Dictionary = {}) -> void:
	_target = target
	_target_is_perch = to_perch
	if to_perch:
		_perch = perch
	visible = false
	_enter(State.CRAWL)


func _tick_crawl(delta: float) -> void:
	var speed: float = CRAWL_SPEED * get_aggression()
	var arrived: bool = _ceiling_move(_target, speed, delta)
	_drop_dust(delta)
	if not arrived:
		return
	if _target_is_perch:
		_begin_roost()
		return
	if _player_is_below(STALK_RADIUS * 1.6):
		_strike_timer = 0.0
		_enter(State.STALK)
	elif _state_time >= LINGER_TIME:
		_go_to_perch(_nearest_perch(global_position))


func _tick_stalk(delta: float) -> void:
	if player == null:
		_go_to_perch(_nearest_perch(global_position))
		return
	var player_floor: int = Campus.floor_from_y(player.global_position.y)
	var flat_distance: float = _flat_distance(player.global_position)
	var lost: bool = not HOME_FLOORS.has(player_floor) or flat_distance > STALK_LOSE_RADIUS \
		or (ScentManager.is_masked() and _time_since_stimulus > STIMULUS_MEMORY) \
		or (player.is_concealed() and _time_since_stimulus > STIMULUS_MEMORY * 2.0)
	if lost:
		_go_to_perch(_nearest_perch(global_position))
		return
	current_floor = player_floor
	var above := Vector3(player.global_position.x, Campus.floor_y(current_floor) + CEILING_OFFSET, player.global_position.z)
	_ceiling_move(above, STALK_SPEED * get_aggression(), delta)
	_drop_dust(delta)
	if flat_distance <= STALK_RADIUS and not player.is_concealed():
		_strike_timer += delta
	else:
		_strike_timer = maxf(_strike_timer - delta * 0.5, 0.0)
	if _strike_timer >= STRIKE_DELAY / get_aggression():
		_begin_drop(false)


## Comes down through the ceiling tiles on top of Juan.
func _begin_drop(berserk: bool) -> void:
	is_berserk = berserk
	_drop_from = global_position
	_drop_to = Vector3(global_position.x, Campus.floor_y(current_floor) + 0.05, global_position.z)
	_state_duration = BERSERK_DROP_TIME if berserk else DROP_TIME
	visible = true
	_spawn_dust(Vector3(global_position.x, Campus.floor_y(current_floor) + 3.5, global_position.z), 40)
	NoiseManager.emit_noise(_drop_to, DROP_NOISE, &"ceiling_crash", self)
	SfxSynth.play_at(self, SfxSynth.thud(), _drop_to + Vector3.UP * 2.0, 4.0)
	_enter(State.DROP)


func _tick_drop() -> void:
	var ratio: float = clampf(_state_time / _state_duration, 0.0, 1.0)
	global_position = _drop_from.lerp(_drop_to, ratio * ratio)
	if ratio >= 1.0:
		_begin_hunt()


func _begin_hunt() -> void:
	visible = true
	body_shape.disabled = false
	velocity = Vector3.ZERO
	_claw_timer = 0.0
	_state_duration = (BERSERK_HUNT_TIME if is_berserk else HUNT_TIME) * get_aggression()
	_enter(State.HUNT)


func _tick_hunt(delta: float) -> void:
	if player == null or _state_time >= _state_duration:
		_begin_retreat()
		return
	if try_attack_player():
		return
	var goal: Vector3 = player.global_position
	if player.is_concealed():
		var spot := player.get_hiding_spot() as HidingSpot
		if spot != null:
			goal = spot.get_exit_position()
			if _flat_distance(goal) < 0.9:
				# It watched him hide: drag him out.
				attack_cooldown = 0.0
				player.take_attack(self)
				_begin_retreat()
				return
	nav_move_to(goal, BERSERK_SPEED if is_berserk else HUNT_SPEED, delta)
	var door: InteractableDoor = find_blocking_door()
	if door == null:
		_claw_timer = 0.0
		return
	# No hands for handles: it claws at the wood, then gives up.
	_claw_timer += delta
	if door.trigger_salt(self):
		return
	if _claw_timer >= DOOR_CLAW_TIME:
		door.shove(12.0)
		_begin_retreat()


func _begin_retreat() -> void:
	body_shape.disabled = true
	velocity = Vector3.ZERO
	current_floor = clampi(Campus.floor_from_y(global_position.y), HOME_FLOORS[0], HOME_FLOORS[1])
	_drop_from = global_position
	_drop_to = Vector3(global_position.x, Campus.floor_y(current_floor) + CEILING_OFFSET, global_position.z)
	_enter(State.RETREAT)


func _tick_retreat() -> void:
	var ratio: float = clampf(_state_time / DROP_TIME, 0.0, 1.0)
	global_position = _drop_from.lerp(_drop_to, ratio)
	if ratio >= 1.0:
		_go_to_perch(_farthest_perch(global_position))


func _on_attack_landed(fatal: bool) -> void:
	if not fatal:
		_begin_retreat()


# ------------------------------------------------------------------- stimuli

func _on_heard(origin: Vector3, _noise_type: StringName, _audibility: float) -> void:
	_take_interest(origin)


func _sniff() -> void:
	var nose := Vector3(global_position.x, Campus.floor_y(current_floor), global_position.z)
	var crumb: ScentBreadcrumb = ScentManager.find_next_breadcrumb(nose, sniff_radius * get_aggression(), _last_crumb_serial)
	if crumb != null:
		remember_crumb(crumb)
		_take_interest(crumb.global_position)


func _take_interest(point: Vector3) -> void:
	var floor_index: int = Campus.floor_from_y(point.y)
	if not HOME_FLOORS.has(floor_index):
		return
	_time_since_stimulus = 0.0
	if state == State.ROOST or state == State.CRAWL:
		current_floor = floor_index
		EventBus.aswang_alerted.emit(aswang_id, point)
		_begin_crawl(Vector3(point.x, Campus.floor_y(floor_index) + CEILING_OFFSET, point.z), false)


## The white LED on its perch: BERSERK. Blacked-out windows keep the beam in.
func _check_flashlight() -> bool:
	if player == null or not player.phone.is_flashlight_on:
		return false
	var window: JalousieWindow = null
	if state == State.ROOST:
		window = _perch["window"] as JalousieWindow
	if window != null and not window.leaks_light():
		return false
	var lit_point: Vector3 = global_position + Vector3.UP * 0.2
	if not player.phone.is_beam_on(lit_point, BEAM_CONE, BEAM_RANGE):
		return false
	var query := PhysicsRayQueryParameters3D.create(player.phone.get_beam_origin(), lit_point, 1)
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	_go_berserk(window)
	return true


func _go_berserk(window: JalousieWindow) -> void:
	EventBus.tiktik_berserk.emit(global_position)
	EventBus.ui_notification.emit("The light! It saw the light!", 2.5)
	if window != null:
		if window.trigger_salt(self):
			return
		window.shatter(self)
		current_floor = window.get_floor_index()
		global_position = window.get_inside_point(0.6)
	else:
		current_floor = clampi(Campus.floor_from_y(player.global_position.y), HOME_FLOORS[0], HOME_FLOORS[1])
	_begin_drop(true)


func _incapacitated_tick(delta: float) -> void:
	# Stunned in the crawlspace or on a ledge it simply clings where it is.
	if state == State.HUNT:
		super._incapacitated_tick(delta)


func _on_recovered() -> void:
	super._on_recovered()
	if state == State.HUNT:
		_begin_retreat()
	else:
		_go_to_perch(_nearest_perch(global_position))


func _on_blinded() -> void:
	_strike_timer = 0.0
	_time_since_stimulus = 999.0


# -------------------------------------------------------------------- helpers

## Straight-line movement through the crawlspace. Returns true on arrival.
func _ceiling_move(target: Vector3, speed: float, delta: float) -> bool:
	var offset: Vector3 = target - global_position
	if offset.length() <= speed * delta + 0.05:
		global_position = target
		return true
	global_position += offset.normalized() * speed * delta
	face_direction(offset, delta)
	return false


func _flat_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _player_is_below(radius: float) -> bool:
	if player == null or player.is_concealed():
		return false
	return Campus.floor_from_y(player.global_position.y) == current_floor and _flat_distance(player.global_position) <= radius


func _go_to_perch(perch: Dictionary) -> void:
	if perch.is_empty():
		_begin_roost()
		return
	_begin_crawl(perch["position"], true, perch)


## Dust shaken loose from the ceiling tiles under a real Tiktik.
func _drop_dust(delta: float) -> void:
	_dust_timer += delta
	if _dust_timer >= DUST_INTERVAL and Campus.is_inside_footprint(global_position):
		_dust_timer = 0.0
		_spawn_dust(Vector3(global_position.x, Campus.floor_y(current_floor) + 3.5, global_position.z), 12)


func _spawn_dust(at: Vector3, amount: int) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var dust := CPUParticles3D.new()
	dust.amount = amount
	dust.lifetime = 1.8
	dust.one_shot = true
	dust.explosiveness = 0.7
	dust.direction = Vector3.DOWN
	dust.spread = 25.0
	dust.gravity = Vector3(0.0, -1.6, 0.0)
	dust.initial_velocity_min = 0.1
	dust.initial_velocity_max = 0.5
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(0.25, 0.01, 0.25)
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.2
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.03, 0.03)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.75, 0.72, 0.66, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	dust.mesh = mesh
	scene.add_child(dust)
	dust.global_position = at
	dust.emitting = true
	get_tree().create_timer(3.0).timeout.connect(dust.queue_free)


## Window ledges and ceiling tiles on 2F and 3F.
func _collect_perches() -> void:
	_perches.clear()
	for node: Node in get_tree().get_nodes_in_group(&"jalousie_windows"):
		var window := node as JalousieWindow
		if window == null or window.is_small() or not HOME_FLOORS.has(window.get_floor_index()):
			continue
		_perches.append({"position": window.get_outside_point(0.4) + Vector3.DOWN * 0.6, "window": window,
			"floor": window.get_floor_index()})
	for room: Dictionary in Campus.ROOMS:
		var floor_index: int = room["floor"]
		if not HOME_FLOORS.has(floor_index):
			continue
		var room_id: int = room["id"]
		var center: Vector3 = Campus.room_center(room_id)
		_perches.append({"position": center + Vector3.UP * CEILING_OFFSET, "window": null, "floor": floor_index})
	for floor_index: int in HOME_FLOORS:
		for x: float in [-7.0, 0.0, 7.0]:
			_perches.append({"position": Vector3(x, Campus.floor_y(floor_index) + CEILING_OFFSET, 0.0), "window": null,
				"floor": floor_index})


func _nearest_perch(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = INF
	for perch: Dictionary in _perches:
		var position: Vector3 = perch["position"]
		var distance: float = position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = perch
	return best


func _farthest_perch(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance: float = -1.0
	for perch: Dictionary in _perches:
		var position: Vector3 = perch["position"]
		var distance: float = position.distance_to(point)
		if distance > best_distance:
			best_distance = distance
			best = perch
	return best


func _random_perch() -> Dictionary:
	if _perches.is_empty():
		return {}
	return _perches[randi() % _perches.size()]
