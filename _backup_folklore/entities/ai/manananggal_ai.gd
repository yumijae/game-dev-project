class_name ManananggalAI
extends AswangBase
## The Manananggal: a winged upper torso that circles the rooftop (#28) and
## hovers outside the 4F and 3F jalousie windows.
##
## At midnight she leaves her lower half standing in one damp, dark room
## (LowerTorsoNode). She is drawn to bleeding scent and to light spilling from
## windows that are not blacked out. Pressing a Salted Garlic Poultice into the
## lower torso starts a 60-second rage - survive it and she is gone for good.

enum State { PATROL, PEER, GO_TO_WINDOW, BREAK_IN, INDOOR_HUNT, LEAVE, ROOF_HUNT }

const WINDOW_FLOORS: Array[int] = [2, 3]
const FLY_SPEED: float = 4.2
const HUNT_SPEED: float = 4.8
const RAGE_SPEED_MULTIPLIER: float = 1.25
## Outdoor travel height: clears the parapet and the stair hut.
const LANE_HEIGHT: float = Campus.ROOF_Y + 4.0
const HOVER_DISTANCE: float = 1.7
const HUNT_ALTITUDE: float = 0.5
const PEER_TIME: float = 2.8
const PEER_SIGHT_RANGE: float = 9.0
const INDOOR_HUNT_TIME: float = 12.0
const LOSE_TIME: float = 5.0
const ROOF_LOSE_TIME: float = 4.0
const WINDOWS_PER_LAP: int = 3
const SCENT_LURE_LEVEL: float = 50.0
const SCENT_CHECK_INTERVAL: float = 2.0
const DOOR_SHOVE_INTERVAL: float = 1.2
const DOOR_SHOVE_FORCE: float = 30.0
const DOOR_PATIENCE: int = 2
const FLAP_INTERVAL: float = 0.55
const FLAP_NOISE: float = 7.0

const ROOF_POINTS: Array[Vector3] = [
	Vector3(-8.0, 17.6, -4.5), Vector3(-3.0, 17.3, 4.5), Vector3(5.0, 17.3, 5.0), Vector3(6.5, 17.6, 0.5),
]

var state: State = State.PATROL
var is_enraged: bool = false
var torso: LowerTorsoNode = null

var _route: Array[Vector3] = []
var _lap: Array = []
var _window: JalousieWindow = null
var _state_time: float = 0.0
var _time_since_seen: float = 999.0
var _last_known: Vector3 = Vector3.ZERO
var _rage_left: float = 0.0
var _scent_timer: float = 0.0
var _shove_timer: float = 0.0
var _shove_count: int = 0
var _flap_timer: float = 0.0
var _wings: Array[MeshInstance3D] = []
# Joints the animation turns.
var _body: Node3D = null
var _head: Node3D = null
var _jaw: Node3D = null
var _hair: Node3D = null
var _entrails: Node3D = null
var _arms: Array[AswangRig.Limb] = []
var _arm_targets: Array[Vector3] = []
var _wing_phase: float = 0.0


func _init() -> void:
	aswang_id = &"manananggal"
	display_name = "The Manananggal"
	eye_height = 0.9
	vision_range = 16.0
	vision_fov = 160.0
	hearing = 1.1
	catch_distance = 1.3


## A woman's body from the ribs up, corpse-pale and wasted, carried on bat
## wings wider than a doorway. Hair hangs over a jaw that opens too far, the
## arms reach ahead of her, and what should be inside trails beneath the waist.
func _build_visual() -> void:
	var skin := Color(0.46, 0.43, 0.4)
	var gore := Color(0.42, 0.07, 0.08)
	var bone := Color(0.74, 0.68, 0.56)
	var look: Dictionary = {"wet": 0.45, "bump": 1.3, "veins": 0.9}
	visual.position.y = 0.2
	_body = add_joint(visual, Vector3(0.0, 0.5, 0.0), "Body")

	var torso := AswangMesh.new()
	torso.tube([Vector3.ZERO, Vector3(0.0, 0.14, 0.01), Vector3(0.0, 0.36, 0.0), Vector3(0.0, 0.56, -0.01),
		Vector3(0.0, 0.66, -0.02)],
		[Vector2(0.105, 0.08), Vector2(0.098, 0.076), Vector2(0.145, 0.1), Vector2(0.17, 0.085), Vector2(0.045, 0.045)],
		Vector3.BACK, 14)
	for side: float in [-1.0, 1.0]:
		# Collar bones.
		torso.tube([Vector3(side * 0.01, 0.565, -0.078), Vector3(side * 0.15, 0.6, -0.04)], [0.011, 0.013], Vector3.ZERO, 6, 2)
	add_flesh(_body, torso, skin, {"wet": 0.45, "bump": 1.3, "veins": 0.9, "gaunt": 0.8, "ridge_spacing": 0.045})

	# What trails beneath the severed waist.
	var stump := AswangMesh.new()
	stump.tube([Vector3(0.0, -0.015, 0.0), Vector3(0.0, 0.03, 0.0)], [Vector2(0.1, 0.075), Vector2(0.108, 0.082)],
		Vector3.BACK, 12, 2)
	add_flesh(_body, stump, gore, {"wet": 1.0, "bump": 2.2, "veins": 1.0})
	var backbone := AswangMesh.new()
	backbone.tube([Vector3(0.0, 0.03, 0.045), Vector3(0.0, -0.08, 0.05), Vector3(0.0, -0.17, 0.06)], [0.022, 0.018, 0.012],
		Vector3.ZERO, 6, 2)
	add_flesh(_body, backbone, bone, {"wet": 0.9, "veins": 0.0, "gaunt": 1.0, "ridge_spacing": 0.035})
	_entrails = add_joint(_body, Vector3.ZERO, "Entrails")
	var entrails := AswangMesh.new()
	for i: int in 6:
		var angle: float = float(i) * TAU / 6.0
		var length: float = 0.42 + 0.11 * float(i)
		var points: Array = []
		var radii: Array = []
		for k: int in 7:
			var t: float = float(k) / 6.0
			points.append(Vector3(cos(angle) * 0.05 + sin(t * 6.0 + float(i)) * 0.04 * t, -length * t,
				sin(angle) * 0.04 + cos(t * 5.0 + float(i) * 2.0) * 0.04 * t + t * 0.08))
			radii.append(lerpf(0.027, 0.013, t) + 0.006 * sin(t * 19.0 + float(i)))
		entrails.tube(points, radii, Vector3.BACK, 7, 3)
	add_sway(add_flesh(_entrails, entrails, gore, {"wet": 1.0, "bump": 1.8, "veins": 1.0, "breathe": 0.006}),
		0.9, 0.16, 22.0, 3.2, 0.03)

	_head = add_joint(_body, Vector3(0.0, 0.7, -0.03), "Head")
	var skull := AswangMesh.new()
	skull.tube([Vector3(0.0, 0.02, -0.015), Vector3(0.0, 0.08, -0.02), Vector3(0.0, 0.16, -0.012), Vector3(0.0, 0.225, 0.0),
		Vector3(0.0, 0.255, 0.005)],
		[Vector2(0.04, 0.05), Vector2(0.062, 0.078), Vector2(0.076, 0.092), Vector2(0.072, 0.09), Vector2(0.045, 0.06)],
		Vector3.BACK, 14)
	# Brow ridge and nose.
	skull.tube([Vector3(-0.055, 0.178, -0.085), Vector3(0.0, 0.172, -0.1), Vector3(0.055, 0.178, -0.085)], [0.01, 0.013, 0.01],
		Vector3.ZERO, 6, 3)
	skull.tube([Vector3(0.0, 0.165, -0.098), Vector3(0.0, 0.118, -0.118)], [0.007, 0.012], Vector3.ZERO, 6, 2)
	add_flesh(_head, skull, skin, look)
	add_part(_head, sphere_mesh(0.046), Vector3(0.0, 0.045, -0.045), Color(0.05, 0.004, 0.006))
	var fangs := AswangMesh.new()
	for x: float in [-0.036, -0.02, -0.007, 0.007, 0.02, 0.036]:
		var long_tooth: bool = absf(x) > 0.03
		fangs.spike(Vector3(x, 0.066, -0.088 + absf(x) * 0.5), Vector3(x, 0.066 - (0.04 if long_tooth else 0.018), -0.092 + absf(x) * 0.5),
			0.0055, 4)
	add_flesh(_head, fangs, bone, {"wet": 0.9, "veins": 0.0, "bump": 0.3, "breathe": 0.0})
	for side: float in [-1.0, 1.0]:
		add_eye(_head, Vector3(side * 0.031, 0.155, -0.09), 0.011, Color(1.0, 0.25, 0.1), 4.0)

	_jaw = add_joint(_head, Vector3(0.0, 0.055, 0.02), "Jaw")
	var jaw := AswangMesh.new()
	jaw.tube([Vector3(-0.055, 0.02, -0.01), Vector3(-0.042, -0.03, -0.075), Vector3(0.0, -0.047, -0.1),
		Vector3(0.042, -0.03, -0.075), Vector3(0.055, 0.02, -0.01)], [0.013, 0.016, 0.019, 0.016, 0.013], Vector3.ZERO, 7, 3)
	add_flesh(_jaw, jaw, skin, look)
	var lower_fangs := AswangMesh.new()
	for x: float in [-0.03, -0.015, 0.0, 0.015, 0.03]:
		lower_fangs.spike(Vector3(x, -0.036, -0.098 + absf(x) * 0.6), Vector3(x, -0.008, -0.1 + absf(x) * 0.6), 0.005, 4)
	add_flesh(_jaw, lower_fangs, bone, {"wet": 0.9, "veins": 0.0, "bump": 0.3, "breathe": 0.0})

	_hair = add_joint(_head, Vector3(0.0, 0.2, 0.02), "Hair")
	var hair := AswangMesh.new()
	hair.tube([Vector3(0.0, -0.03, 0.02), Vector3(0.0, 0.045, 0.005), Vector3(0.0, 0.068, -0.005)],
		[Vector2(0.08, 0.085), Vector2(0.068, 0.078), Vector2(0.03, 0.04)], Vector3.BACK, 12)
	for i: int in 22:
		# Around the back of the head, with a few strands falling across the face.
		var around: float = lerpf(-2.75, 2.75, float(i) / 21.0)
		var length: float = 0.45 + 0.4 * fposmod(sin(float(i) * 12.9898) * 43758.5453, 1.0)
		var root := Vector3(sin(around) * 0.068, 0.035 - absf(around) * 0.012, cos(around) * 0.07)
		var points: Array = []
		var radii: Array = []
		for k: int in 6:
			var t: float = float(k) / 5.0
			points.append(root + Vector3(sin(around) * 0.05 * t + sin(t * 5.0 + float(i)) * 0.03 * t, -length * t,
				cos(around) * 0.03 * t + 0.05 * t + cos(t * 4.0 + float(i) * 1.7) * 0.025 * t))
			radii.append(Vector2(lerpf(0.02, 0.007, t), lerpf(0.008, 0.003, t)))
		hair.tube(points, radii, Vector3(sin(around), 0.0, cos(around)), 5, 2)
	add_sway(add_flesh(_hair, hair, Color(0.015, 0.015, 0.02), {"wet": 0.75, "veins": 0.0, "bump": 2.4, "breathe": 0.0}),
		0.8, 0.2, 30.0, 3.6, 0.012)

	for side: float in [-1.0, 1.0]:
		var wing: MeshInstance3D = add_wing(_body, Vector3(side * 0.08, 0.52, 0.09), side, 1.55, 0.0,
			Color(0.13, 0.1, 0.1), Color(0.3, 0.27, 0.25))
		_wings.append(wing)
		var arm: AswangRig.Limb = AswangRig.make_limb(_body, Vector3(side * 0.185, 0.52, 0.0), 0.3, 0.32,
			Vector3(side * 0.6, -1.0, 0.4), Vector3(side * 0.15, 0.28, -0.32), false)
		_arms.append(arm)
		_arm_targets.append(arm.rest)
		var upper_arm := AswangMesh.new()
		upper_arm.tube([Vector3.ZERO, Vector3(0.0, -0.3, 0.0)], [0.04, 0.029], Vector3.BACK, 8)
		add_flesh(arm.root, upper_arm, skin, look)
		var forearm := AswangMesh.new()
		forearm.tube([Vector3.ZERO, Vector3(0.0, -0.32, 0.0)], [0.028, 0.02], Vector3.BACK, 8)
		add_flesh(arm.mid, forearm, skin, look)
		var hand := AswangMesh.new()
		hand.tube([Vector3(0.0, 0.02, 0.0), Vector3(0.0, -0.08, 0.0)], [0.02, Vector2(0.03, 0.014)], Vector3.BACK, 6, 2)
		for finger: int in 4:
			var spread: float = (float(finger) - 1.5) * 0.024
			var knuckle := Vector3(spread * 0.6, -0.07, 0.0)
			var tip := Vector3(spread * 1.9, -0.25, -0.05)
			hand.tube([knuckle, knuckle.lerp(tip, 0.5) + Vector3(0.0, 0.0, 0.035), tip], [0.009, 0.007, 0.005], Vector3.BACK, 5, 2)
			hand.spike(tip, tip + Vector3(spread * 0.3, -0.04, -0.045), 0.006, 4)
		add_flesh(arm.end, hand, skin, look)


## Each wing beat drives the rest of her: a fast downstroke that lifts the
## body, a slower recovery in which it sinks, the wing tips trailing the
## shoulders throughout. She leans into her flight and banks into turns; her
## hair and what hangs from her waist swing behind on springs; her face and
## her hands stay on Juan.
func _animate(delta: float) -> void:
	var moving: float = clampf(anim_speed / 4.0, 0.0, 1.0)
	var hunting: bool = is_enraged or state == State.INDOOR_HUNT or state == State.ROOF_HUNT or state == State.BREAK_IN
	var strike: float = sin(anim_strike * PI)
	_wing_phase += delta * TAU / FLAP_INTERVAL * (1.0 + 0.25 * moving + (0.3 if hunting else 0.0))
	var angle: float = 0.18 + 0.5 * sin(_wing_phase) + 0.12 * sin(_wing_phase * 2.0 + 0.6)
	var curl: float = -0.34 * cos(_wing_phase - 0.9)
	var recovering: float = maxf(cos(_wing_phase), 0.0)
	for i: int in _wings.size():
		var side: float = -1.0 if i == 0 else 1.0
		_wings[i].rotation = Vector3(0.12 * cos(_wing_phase), side * 0.14 * cos(_wing_phase), side * angle)
		# The wing draws in a little on the way up.
		_wings[i].scale.x = 1.0 - 0.1 * recovering
		set_wing_curl(_wings[i], curl, 1.55)
	visual.position.y = 0.2 - sin(_wing_phase - 0.5) * 0.06
	_body.position.z = -0.1 * strike
	_body.rotation = Vector3(lerpf(_body.rotation.x, -0.12 - 0.42 * moving - 0.3 * strike, minf(delta * 4.0, 1.0)), 0.0,
		lerpf(_body.rotation.z, clampf(-anim_turn * 0.14, -0.4, 0.4), minf(delta * 4.0, 1.0)))
	_entrails.rotation.z = sin(anim_time * 1.7) * 0.06

	# Her face follows Juan wherever he is.
	var yaw: float = sin(anim_time * 0.6) * 0.3
	var pitch: float = 0.2
	var aim := Vector3(0.0, -0.1, -1.0)
	if player != null and is_instance_valid(player):
		var local: Vector3 = to_local(player.get_head_position()) - Vector3(0.0, 1.3, 0.0)
		yaw = clampf(atan2(-local.x, -local.z), -1.2, 1.2)
		pitch = clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.7, 0.6)
		aim = local.normalized()
	_head.rotation.y = lerp_angle(_head.rotation.y, yaw, minf(delta * 5.0, 1.0))
	_head.rotation.x = lerpf(_head.rotation.x, pitch - _body.rotation.x, minf(delta * 5.0, 1.0))
	_head.rotation.z = sin(anim_time * 0.9) * 0.08
	var gape: float = (0.5 + 0.18 * sin(anim_time * 2.1)) if hunting else 0.12
	_jaw.rotation.x = lerpf(_jaw.rotation.x, -maxf(gape, strike * 0.9), minf(delta * 8.0, 1.0))

	# Hands drawn up under her chin until she has him; then they go for him.
	var to_body: Transform3D = _body.transform.affine_inverse()
	for i: int in _arms.size():
		var side: float = -1.0 if i == 0 else 1.0
		var drift := Vector3(sin(anim_time * 1.3 + float(i) * 2.0), sin(anim_time * 1.9 + float(i)), 0.0) * 0.025
		var reach: Vector3 = _arms[i].rest + drift
		if hunting:
			var grasp: float = sin(anim_time * 6.0 + float(i) * 2.4) * 0.05
			reach = to_body * (Vector3(side * 0.14, 1.0, 0.0) + aim * (0.52 + grasp + 0.1 * strike))
		_arm_targets[i] = _arm_targets[i].lerp(reach, minf(delta * 7.0, 1.0))
		_arms[i].solve(_arm_targets[i])


func _on_activated() -> void:
	body_shape.disabled = true
	_spawn_lower_torso()
	if not EventBus.flashlight_leaked.is_connected(_on_flashlight_leaked):
		EventBus.flashlight_leaked.connect(_on_flashlight_leaked)
	_begin_patrol()


## Leaves the lower half in one damp, dark room: Records (#6), the 2F or 3F
## restrooms (#9, #10, #19, #20) or the Pantry (#26).
func _spawn_lower_torso() -> void:
	var spots: Array[Node] = get_tree().get_nodes_in_group(&"torso_spots")
	var at: Vector3
	var room_id: int
	if spots.is_empty():
		room_id = Campus.TORSO_ROOM_IDS[randi() % Campus.TORSO_ROOM_IDS.size()]
		at = Campus.room_center(room_id)
	else:
		var marker := spots[randi() % spots.size()] as Node3D
		at = marker.global_position
		room_id = Campus.room_id_at(at + Vector3.UP * 0.5)
	torso = LowerTorsoNode.spawn(get_tree().current_scene, at, room_id, self)
	EventBus.manananggal_torso_spawned.emit(room_id)


func get_feet_description() -> String:
	return "No feet. Only something dripping on the floor... and the beat of wings."


## Called by the LowerTorsoNode when the poultice goes on.
func enrage(duration: float) -> void:
	if not is_threatening():
		return
	is_enraged = true
	_rage_left = duration
	stun_time_left = 0.0
	blind_time_left = 0.0
	SfxSynth.play_ui(self, SfxSynth.growl(), 2.0, 0.6)
	if state in [State.PATROL, State.PEER, State.GO_TO_WINDOW]:
		_hunt_from_outside()


func destroy_permanently() -> void:
	if is_dead:
		return
	SfxSynth.play_ui(self, SfxSynth.growl(), 4.0, 0.45)
	die()
	EventBus.manananggal_destroyed.emit()


# ---------------------------------------------------------------- state logic

func _physics_process(delta: float) -> void:
	if is_enraged and is_threatening():
		_rage_left -= delta
		if _rage_left <= 0.0:
			destroy_permanently()
			return
	super._physics_process(delta)


func _tick(delta: float) -> void:
	_state_time += delta
	_time_since_seen += delta
	_animate_wings(delta)
	match state:
		State.PATROL:
			_tick_patrol(delta)
		State.PEER:
			_tick_peer(delta)
		State.GO_TO_WINDOW:
			_tick_go_to_window(delta)
		State.BREAK_IN:
			_tick_break_in(delta)
		State.INDOOR_HUNT:
			_tick_indoor_hunt(delta)
		State.LEAVE:
			_tick_leave(delta)
		State.ROOF_HUNT:
			_tick_roof_hunt(delta)


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	set_state(State.keys()[new_state])


func _speed(base: float) -> float:
	return base * minf(get_aggression(), 1.6) * (RAGE_SPEED_MULTIPLIER if is_enraged else 1.0)


func _begin_patrol() -> void:
	_window = null
	_build_lap()
	_enter(State.PATROL)


## One lap: the roof circuit, then a few windows on 4F and 3F.
func _build_lap() -> void:
	_lap.clear()
	for point: Vector3 in ROOF_POINTS:
		_lap.append(point)
	var windows: Array[JalousieWindow] = _get_windows(WINDOW_FLOORS)
	windows.shuffle()
	for i: int in mini(WINDOWS_PER_LAP, windows.size()):
		_lap.append(windows[i])
	_route.clear()


func _tick_patrol(delta: float) -> void:
	if _react_to_player_outside():
		return
	_scent_timer += delta
	if _scent_timer >= SCENT_CHECK_INTERVAL:
		_scent_timer = 0.0
		if _follow_blood():
			return
	if _route.is_empty():
		if _lap.is_empty():
			_build_lap()
		var stop: Variant = _lap[0]
		if stop is JalousieWindow:
			_window = stop as JalousieWindow
			_lap.pop_front()
			_set_outdoor_route(_window.get_outside_point(HOVER_DISTANCE))
			_enter(State.GO_TO_WINDOW)
			return
		var point: Vector3 = stop
		_lap.pop_front()
		_set_outdoor_route(point)
	_follow_route(_speed(FLY_SPEED), delta)


func _tick_go_to_window(delta: float) -> void:
	if _window == null or not is_instance_valid(_window):
		_begin_patrol()
		return
	if not is_enraged and _react_to_player_outside():
		return
	if _follow_route(_speed(FLY_SPEED), delta):
		_enter(State.BREAK_IN if is_enraged else State.PEER)


## Hovers at the glass and looks for a reason to come in.
func _tick_peer(delta: float) -> void:
	face_point(_window.global_position, delta)
	if _is_lured_by(_window):
		_enter(State.BREAK_IN)
	elif _state_time >= PEER_TIME:
		_window = null
		_enter(State.PATROL)


func _tick_break_in(delta: float) -> void:
	if _window == null or not is_instance_valid(_window):
		_begin_patrol()
		return
	face_point(_window.global_position, delta)
	if _state_time < 0.6:
		return
	if _window.is_small():
		_begin_patrol()
		return
	if _window.trigger_salt(self):
		# Burned on the sill: she hangs there, stunned, then tries elsewhere.
		_lap.clear()
		state = State.PATROL
		return
	if not _window.is_breached():
		_window.shatter(self)
	var inside: Vector3 = _window.get_inside_point(1.0)
	inside.y = Campus.floor_y(_window.get_floor_index()) + HUNT_ALTITUDE
	global_position = inside
	_time_since_seen = 0.0
	_last_known = player.global_position if player != null else inside
	_shove_count = 0
	_enter(State.INDOOR_HUNT)


func _tick_indoor_hunt(delta: float) -> void:
	if player == null:
		_enter(State.LEAVE)
		return
	if try_attack_player():
		return
	var sees: bool = can_see_player()
	if sees:
		_time_since_seen = 0.0
		_last_known = player.global_position
	var out_of_time: bool = _state_time >= INDOOR_HUNT_TIME * get_aggression()
	if not is_enraged and (out_of_time or _time_since_seen >= LOSE_TIME):
		_enter(State.LEAVE)
		return
	# In her rage she always knows where he is.
	var goal: Vector3 = player.global_position if (sees or is_enraged) else _last_known
	if is_enraged and Campus.floor_from_y(player.global_position.y) == Campus.ROOF_FLOOR \
			and Campus.stairwell_at(player.global_position) == "":
		_enter(State.ROOF_HUNT)
		return
	_nav_fly_to(goal, _speed(HUNT_SPEED), delta)
	_handle_door(delta)


func _tick_leave(delta: float) -> void:
	if _window == null or not is_instance_valid(_window):
		global_position.y = LANE_HEIGHT
		_begin_patrol()
		return
	var inside: Vector3 = _window.get_inside_point(1.0)
	inside.y = Campus.floor_y(_window.get_floor_index()) + HUNT_ALTITUDE
	if _nav_fly_to(inside, _speed(FLY_SPEED), delta) or _state_time > 12.0:
		global_position = _window.get_outside_point(HOVER_DISTANCE)
		_begin_patrol()


## On the open roof deck she simply flies at him while she can see him.
func _tick_roof_hunt(delta: float) -> void:
	if player == null:
		_begin_patrol()
		return
	if try_attack_player():
		return
	var on_deck: bool = Campus.floor_from_y(player.global_position.y) == Campus.ROOF_FLOOR \
		and Campus.stairwell_at(player.global_position) == ""
	var sees: bool = on_deck and can_see_player()
	if sees:
		_time_since_seen = 0.0
		_last_known = player.global_position
	elif _time_since_seen >= ROOF_LOSE_TIME:
		if is_enraged:
			_hunt_from_outside()
		else:
			_begin_patrol()
		return
	var goal: Vector3 = _last_known + Vector3.UP * HUNT_ALTITUDE
	_fly_to(goal, _speed(HUNT_SPEED), delta)


# --------------------------------------------------------------------- lures

## Sees or hears Juan out on the roof deck.
func _react_to_player_outside() -> bool:
	if player == null:
		return false
	var on_deck: bool = Campus.floor_from_y(player.global_position.y) == Campus.ROOF_FLOOR \
		and Campus.stairwell_at(player.global_position) == ""
	if on_deck and can_see_player():
		_time_since_seen = 0.0
		_last_known = player.global_position
		EventBus.aswang_alerted.emit(aswang_id, _last_known)
		_enter(State.ROOF_HUNT)
		return true
	return false


## Light behind unblackened glass, or Juan plainly visible through it.
func _is_lured_by(window: JalousieWindow) -> bool:
	if player == null or window.is_small():
		return false
	if Campus.room_id_at(player.global_position) != window.room_id:
		return false
	if ScentManager.scent_level >= SCENT_LURE_LEVEL:
		return true
	if not window.leaks_light():
		return false
	if player.phone.is_flashlight_on or _is_candle_lit_in(window.room_id):
		return true
	return global_position.distance_to(player.global_position) <= PEER_SIGHT_RANGE and can_see_player()


func _is_candle_lit_in(room_id: int) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"lana_candles"):
		var candle := node as LanaCandle
		if candle != null and candle.is_lit and Campus.room_id_at(candle.global_position) == room_id:
			return true
	return false


## Blood on the air: go straight to the window of the room he is bleeding in.
func _follow_blood() -> bool:
	if player == null or ScentManager.scent_level < SCENT_LURE_LEVEL:
		return false
	var floor_index: int = Campus.floor_from_y(player.global_position.y)
	if not WINDOW_FLOORS.has(floor_index):
		return false
	var window: JalousieWindow = _nearest_window(player.global_position, [floor_index], 9.0)
	if window == null:
		return false
	_head_for_window(window)
	return true


func _on_flashlight_leaked(_point: Vector3, surface: Node3D) -> void:
	var window := surface as JalousieWindow
	if window == null or not is_threatening() or is_incapacitated():
		return
	if state != State.PATROL and state != State.PEER:
		return
	if not WINDOW_FLOORS.has(window.get_floor_index()) or window.is_small():
		return
	EventBus.aswang_alerted.emit(aswang_id, window.global_position)
	_head_for_window(window)


func _on_heard(origin: Vector3, _noise_type: StringName, _audibility: float) -> void:
	if state != State.PATROL:
		return
	if Campus.floor_from_y(origin.y) == Campus.ROOF_FLOOR and Campus.stairwell_at(origin) == "":
		_last_known = origin
		_time_since_seen = 0.0
		_enter(State.ROOF_HUNT)


func _head_for_window(window: JalousieWindow) -> void:
	_window = window
	_set_outdoor_route(window.get_outside_point(HOVER_DISTANCE))
	_enter(State.GO_TO_WINDOW)


## Rage: find the nearest way in on whatever floor he is hiding on.
func _hunt_from_outside() -> void:
	if player == null:
		return
	var floor_index: int = Campus.floor_from_y(player.global_position.y)
	if floor_index == Campus.ROOF_FLOOR:
		_last_known = player.global_position
		_time_since_seen = 0.0
		_enter(State.ROOF_HUNT)
		return
	var window: JalousieWindow = _nearest_window(player.global_position, [floor_index], INF)
	if window == null:
		window = _nearest_window(player.global_position, [0, 1, 2, 3], INF)
	if window != null:
		_head_for_window(window)


# ------------------------------------------------------------------- movement

func _incapacitated_tick(_delta: float) -> void:
	visual.rotation.z = sin(float(Time.get_ticks_msec()) * 0.02) * 0.2


func _on_recovered() -> void:
	super._on_recovered()
	if state == State.INDOOR_HUNT and not is_enraged:
		_enter(State.LEAVE)
	elif state == State.PATROL or state == State.PEER or state == State.BREAK_IN:
		if is_enraged:
			_hunt_from_outside()
		else:
			_begin_patrol()


func _on_blinded() -> void:
	_time_since_seen = 999.0


func _on_attack_landed(fatal: bool) -> void:
	if fatal or is_enraged:
		return
	if state == State.ROOF_HUNT:
		global_position.y += 2.5
		_begin_patrol()
	else:
		_enter(State.LEAVE)


## Straight-line flight. Returns true on arrival.
func _fly_to(target: Vector3, speed: float, delta: float) -> bool:
	var offset: Vector3 = target - global_position
	if offset.length() <= speed * delta + 0.05:
		global_position = target
		return true
	global_position += offset.normalized() * speed * delta
	face_direction(offset, delta, 5.0)
	return false


func _follow_route(speed: float, delta: float) -> bool:
	if _route.is_empty():
		return true
	if _fly_to(_route[0], speed, delta):
		_route.pop_front()
	return _route.is_empty()


## Outdoor travel never cuts through the building: climb to the lane height,
## cross above the roof, then descend onto the target.
func _set_outdoor_route(target: Vector3) -> void:
	_route.clear()
	var flat_distance: float = Vector2(target.x - global_position.x, target.z - global_position.z).length()
	if flat_distance > 2.5:
		_route.append(Vector3(global_position.x, LANE_HEIGHT, global_position.z))
		_route.append(Vector3(target.x, LANE_HEIGHT, target.z))
	_route.append(target)


## Indoors she follows the navmesh, hovering just above the floor.
func _nav_fly_to(target: Vector3, speed: float, delta: float) -> bool:
	_repath_timer -= delta
	if _repath_timer <= 0.0 or nav.target_position.distance_to(target) > 1.0:
		nav.target_position = target
		_repath_timer = REPATH_INTERVAL
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	if (flat.length() < 0.7 and absf(target.y - global_position.y) < 1.5) or nav.is_navigation_finished():
		return true
	var next: Vector3 = nav.get_next_path_position()
	var step := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	if step.length() > 0.01:
		_desired_direction = step.normalized()
		if find_blocking_door(1.1) == null:
			global_position += _desired_direction * speed * delta
		face_direction(_desired_direction, delta)
	global_position.y = lerpf(global_position.y, next.y + HUNT_ALTITUDE, minf(delta * 6.0, 1.0))
	return false


## Closed doors stop her - briefly. Enraged, she goes through them.
func _handle_door(delta: float) -> void:
	var door: InteractableDoor = find_blocking_door(1.2)
	if door == null:
		_shove_timer = 0.0
		return
	_shove_timer += delta
	if _shove_timer < DOOR_SHOVE_INTERVAL:
		return
	_shove_timer = 0.0
	if door.trigger_salt(self):
		return
	if door.can_aswang_open() and door.handle_state == InteractableDoor.HandleState.UNLOCKED:
		door.set_open(true)
		return
	_shove_count += 1
	var broke: bool = door.shove(DOOR_SHOVE_FORCE * get_aggression() * (1.5 if is_enraged else 1.0))
	if not broke and not is_enraged and _shove_count >= DOOR_PATIENCE + TimeManager.aggression_level / 2:
		_enter(State.LEAVE)


## The sound of the wings. Their motion is posed in _animate().
func _animate_wings(delta: float) -> void:
	_flap_timer += delta
	if _flap_timer >= FLAP_INTERVAL:
		_flap_timer = 0.0
		SfxSynth.play_at(self, SfxSynth.wing_flap(), global_position, -10.0, randf_range(0.85, 1.1), 18.0)
		if state == State.INDOOR_HUNT or state == State.ROOF_HUNT:
			NoiseManager.emit_noise(global_position, FLAP_NOISE, &"wing_flap", self)


func _get_windows(floors: Array) -> Array[JalousieWindow]:
	var windows: Array[JalousieWindow] = []
	for node: Node in get_tree().get_nodes_in_group(&"jalousie_windows"):
		var window := node as JalousieWindow
		if window != null and not window.is_small() and floors.has(window.get_floor_index()):
			windows.append(window)
	return windows


func _nearest_window(point: Vector3, floors: Array, max_distance: float) -> JalousieWindow:
	var best: JalousieWindow = null
	var best_distance: float = max_distance
	for window: JalousieWindow in _get_windows(floors):
		var distance: float = window.global_position.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = window
	return best
