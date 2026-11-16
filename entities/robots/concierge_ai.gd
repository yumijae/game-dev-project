class_name ConciergeAI
extends RobotBase
## CONCIERGE - the expo's wheeled greeter. A screen face, a cheerful voice and
## a schedule it will not let go of: after hours, anyone in the building is a
## visitor to be "escorted out".
##
##   - Wheels: it never leaves its own floor (2F, where the lab, the Server Room
##     and the breaker are). Stairs stop it cold.
##   - No hands: a closed door stops it. It asks politely, then goes away.
##   - Drawn to light and noise. A flashlight in its sight carries a long way;
##     in the dark it only notices Juan up close.
##   - Its screen glows and its motor hums, so you can hear and see it coming.
##   - The body is one rigid shell on wheels, so it is animated as a whole
##     (_process): it leans into speed and turns, bobs when it talks, swivels
##     to look around, jolts when it spots Juan, rocks at a closed door and
##     shudders when sprayed. The face blinks and changes with its mood.
##     The face tells you its mood: smile (patrol), "?" (checking something),
##     "!" (chasing).

enum State { DOCKED, PATROL, INVESTIGATE, CHASE, OFF }

const PATROL_SPEED: float = 1.3
const INVESTIGATE_SPEED: float = 2.1
const CHASE_SPEED: float = 3.1
## How far a flashlight in its line of sight gives Juan away.
const LIGHT_SIGHT_RANGE: float = 22.0
const DOOR_WAIT: float = 4.0
## How long it stops to look around where a noise or a lost visitor led it.
const LOOK_TIME: float = 2.5
const LOSE_TIME: float = 4.0
const RETREAT_TIME: float = 9.0
const SPEECH_RANGE: float = 14.0
## Navmesh points sit up to ~0.2 m above the floor; anything higher is a stair.
const STAIR_TOLERANCE: float = 0.4
## Screen panel in the fitted model's space (see RobotModels).
const SCREEN_CENTER := Vector3(0.0, 1.25, 0.03) * (1.25 / 1.6)
const SCREEN_NORMAL := Vector3(0.0, 0.51, 0.86)

const LINES_PATROL: Array[String] = [
	"Welcome to the STI Tech Expo!",
	"Exhibits open at 8:00 AM. Thank you for your patience.",
	"Please keep to the marked walkways.",
	"Reminder: visitors may not remain in the building after hours.",
	"Have you seen our robotics booth? It is in the Com Sci Lab!",
]
const LINES_SPOTTED: Array[String] = [
	"Hello, visitor! Please hold still.",
	"Visitor detected after hours. I will escort you out.",
	"Oh! A guest! Please wait right there.",
]
const LINES_LOST: Array[String] = [
	"Visitor? Where did you go?",
	"Please return to the exhibit area.",
]
const LINE_DOOR := "Please open the door. I cannot reach the handle."
const LINE_HIT := "Thank you for your cooperation."
const GLOW_ENERGY: float = 0.6
## Faces shown while its sensors are scrambled.
const SCRAMBLED_FACES: Array[String] = ["x_x", "#@!?", "x_X", "%&#", ">_<", "?!?"]

var state: State = State.DOCKED
var home_floor: int = 1

var _target: Vector3 = Vector3.ZERO
var _patrol_timer: float = 0.0
var _talk_timer: float = 8.0
var _lose_timer: float = 0.0
var _door_timer: float = 0.0
var _look_timer: float = 0.0
var _retreat_timer: float = 0.0
var _screen_mat: StandardMaterial3D = null
var _face: Label3D = null
var _glow: OmniLight3D = null
var _motor: AudioStreamPlayer3D = null
# Body animation (see _process).
var _mood: String = "sleep"
var _anim_time: float = 0.0
var _last_speed: float = 0.0
var _last_yaw: float = 0.0
var _accel_smooth: float = 0.0
var _turn_smooth: float = 0.0
## One-shot gestures, each counting down from 1 to 0.
var _nod: float = 0.0
var _jolt: float = 0.0
var _lunge: float = 0.0
var _blink_timer: float = 3.0
var _scramble_timer: float = 0.0


func _init() -> void:
	display_name = "CONCIERGE"
	hostile_id = &"concierge"
	vision_range = 9.0
	hearing = 1.25
	catch_distance = 1.2
	body_radius = 0.24
	body_height = 1.2
	eye_height = 1.0
	wake_minute = 105      # 1:30 AM


func kind() -> StringName:
	return &"concierge"


## Sprayed: the screen scrambles until it recovers.
func stun(seconds: float, cause: StringName = &"") -> void:
	super(seconds, cause)
	if is_active:
		_set_face("dazed")
		_say("Sensor error. Sensor error.")
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if is_active and stun_time_left <= 0.0:
				_set_face("question" if state == State.INVESTIGATE else "smile"))


func get_feet_description() -> String:
	return "A soft green glow under the door, and the hum of a small motor. It is waiting."


# ------------------------------------------------------------------ lifecycle

func _on_built() -> void:
	# The screen: find its material and make it glow.
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var mat := mi.get_active_material(0) as StandardMaterial3D
		if mat != null and mat.resource_name == "Material.004":
			_screen_mat = mat.duplicate() as StandardMaterial3D
			_screen_mat.emission_enabled = true
			mi.material_override = _screen_mat
	var face_basis := Basis.looking_at(-SCREEN_NORMAL, Vector3.UP)
	_face = Label3D.new()
	_face.font_size = 96
	_face.pixel_size = 0.0022
	_face.outline_size = 0
	_face.shaded = false
	_face.double_sided = false
	_face.transform = Transform3D(face_basis, SCREEN_CENTER + SCREEN_NORMAL * 0.02)
	model.add_child(_face)
	_glow = OmniLight3D.new()
	_glow.omni_range = 2.6
	_glow.light_energy = GLOW_ENERGY
	_glow.shadow_enabled = false
	_glow.position = SCREEN_CENTER + SCREEN_NORMAL * 0.25
	model.add_child(_glow)
	_motor = AudioStreamPlayer3D.new()
	_motor.stream = SfxSynth.drone()
	_motor.unit_size = 2.0
	_motor.max_distance = 16.0
	_motor.volume_db = -60.0
	_motor.pitch_scale = 2.4
	_motor.position = Vector3.UP * 0.3
	add_child(_motor)
	_motor.finished.connect(_motor.play)
	_set_face("sleep")


func dock_at(xf: Transform3D) -> void:
	super(xf)
	home_floor = Campus.floor_from_y(xf.origin.y + 0.5)


func _on_activated() -> void:
	_set_face("smile")
	_motor.play()
	_say("Good evening! The Tech Expo is now... open.")
	state = State.PATROL
	_pick_patrol_target()


func _on_shutdown() -> void:
	state = State.OFF
	_set_face("off")
	_motor.stop()
	SfxSynth.play_at(self, SfxSynth.bell(), get_eye_position(), -14.0, 0.5, SPEECH_RANGE)


func _on_attack_landed(fatal: bool) -> void:
	SfxSynth.play_at(self, SfxSynth.thud(), global_position + Vector3.UP * 0.5, 2.0, 0.8)
	_lunge = 1.0
	if not fatal:
		_say(LINE_HIT)
		_retreat_timer = RETREAT_TIME
		state = State.PATROL
		_pick_patrol_target()


# ---------------------------------------------------------------------- tick

func _tick(delta: float) -> void:
	_retreat_timer = maxf(_retreat_timer - delta, 0.0)
	_talk_timer -= delta
	_sense(delta)
	if state != State.INVESTIGATE:
		_look_timer = 0.0
	match state:
		State.PATROL:
			if _talk_timer <= 0.0:
				_talk_timer = randf_range(16.0, 26.0)
				_say(LINES_PATROL[randi() % LINES_PATROL.size()])
			_patrol_timer -= delta
			if _drive(_target, PATROL_SPEED, delta) or _patrol_timer <= 0.0:
				_pick_patrol_target()
		State.INVESTIGATE:
			if _look_timer > 0.0:
				# Arrived and found nothing: stops and swivels for a moment.
				_look_timer -= delta
				ground_idle(delta)
				if _look_timer <= 0.0:
					_look_around_then_patrol()
			elif _drive(_target, INVESTIGATE_SPEED, delta):
				_look_timer = LOOK_TIME
		State.CHASE:
			if knows_where():
				_target = last_known
			_drive(_target, CHASE_SPEED, delta)
			if _retreat_timer <= 0.0:
				try_attack_player()
	var moving: float = clampf(Vector2(velocity.x, velocity.z).length() / CHASE_SPEED, 0.0, 1.0)
	_motor.volume_db = lerpf(-26.0, -12.0, moving)
	_motor.pitch_scale = lerpf(2.0, 2.8, moving)


func _sense(delta: float) -> void:
	if player == null or player.is_dead or _retreat_timer > 0.0:
		return
	if Campus.floor_from_y(player.global_position.y + 0.5) != home_floor:
		if state == State.CHASE:
			_lose()
		return
	var seen: bool = can_see_player() or _sees_flashlight()
	if seen:
		remember(player.global_position)
		_lose_timer = LOSE_TIME
		if state != State.CHASE:
			state = State.CHASE
			_set_face("alert")
			_jolt = 1.0
			_say(LINES_SPOTTED[randi() % LINES_SPOTTED.size()])
	elif state == State.CHASE:
		_lose_timer -= delta
		if _lose_timer <= 0.0:
			_lose()


## A lit flashlight is a beacon: seen from far off if nothing blocks the view.
func _sees_flashlight() -> bool:
	if not player.phone.is_flashlight_on or player.is_concealed():
		return false
	var eye: Vector3 = get_eye_position()
	var head: Vector3 = player.get_head_position()
	if eye.distance_to(head) > LIGHT_SIGHT_RANGE:
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, head, SIGHT_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _lose() -> void:
	_say(LINES_LOST[randi() % LINES_LOST.size()])
	state = State.INVESTIGATE
	_set_face("question")
	_target = _on_my_floor(last_known) if knows_where() else global_position


func _look_around_then_patrol() -> void:
	state = State.PATROL
	_set_face("smile")
	_pick_patrol_target()


func _on_found_hidden(at: Vector3) -> void:
	if state == State.OFF or state == State.DOCKED or _retreat_timer > 0.0:
		return
	if Campus.floor_from_y(at.y + 0.3) != home_floor:
		return
	_target = _on_my_floor(at)
	_lose_timer = LOSE_TIME
	if state != State.CHASE:
		state = State.CHASE
		_set_face("alert")
		_say("There you are, visitor. Please step out.")


func _on_heard(origin: Vector3, _noise_type: StringName, audibility: float) -> void:
	if state == State.CHASE or state == State.OFF or state == State.DOCKED or audibility < 0.15:
		return
	if Campus.floor_from_y(origin.y + 0.3) != home_floor:
		return
	state = State.INVESTIGATE
	_set_face("question")
	_target = _on_my_floor(origin)
	_look_timer = 0.0


# ----------------------------------------------------------------- movement

## Drives towards `goal` on its own floor. Waits at closed doors, asks, then
## gives up on that goal. Returns true on arrival or when giving up.
func _drive(goal: Vector3, speed: float, delta: float) -> bool:
	var door: InteractableDoor = find_blocking_door()
	if door != null:
		_door_timer += delta
		ground_idle(delta)
		face_point(door.get_center(), delta, 4.0)
		if _door_timer > 0.6 and _door_timer - delta <= 0.6:
			_say(LINE_DOOR)
		if _door_timer >= DOOR_WAIT:
			_door_timer = 0.0
			_avoid_door(door)
			return true
		return false
	_door_timer = 0.0
	if stuck_count >= 3:
		stuck_count = 0
		return true
	var arrived: bool = nav_move_to(goal, speed * get_speed_factor(), delta)
	face_direction(_desired_direction, delta, 4.0)
	return arrived


## Turned away by a closed door: pick somewhere on this side of it.
func _avoid_door(door: InteractableDoor) -> void:
	var side: float = door.which_side(global_position)
	turn_from_door(door)
	_target = _on_my_floor(door.get_side_position(side, 4.0))
	if state == State.CHASE:
		state = State.INVESTIGATE
		_set_face("question")


func _pick_patrol_target() -> void:
	_patrol_timer = 22.0
	for _attempt in 8:
		var p: Vector3 = random_nav_point(global_position, 12.0)
		if _route_stays(p):
			_target = p
			return
	_target = global_position


## `p` pulled onto this robot's floor (the nearest navmesh point at its height).
func _on_my_floor(p: Vector3) -> Vector3:
	var map: RID = get_world_3d().navigation_map
	var q: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(p.x, _floor_height(), p.z))
	return q if _route_stays(q) else global_position


## Height of the floor its dock is on.
func _floor_height() -> float:
	return Campus.floor_y(home_floor)


## True when the walkable route to `p` never takes a staircase. Heights are
## measured from its own floor, not from where it stands: measured from itself
## it could climb a little with every new target and end up on the stairs.
func _route_stays(p: Vector3) -> bool:
	var map: RID = get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, global_position, p, true)
	for point: Vector3 in path:
		if absf(point.y - _floor_height()) > STAIR_TOLERANCE:
			return false
	return not path.is_empty()


# ---------------------------------------------------------------- animation

## Moves the whole shell: lean, roll, swivel and bounce, on top of wherever
## the AI has driven it. Runs even while stunned, docked or switched off.
func _process(delta: float) -> void:
	if model == null or _face == null:
		return
	_anim_time += delta
	var t: float = _anim_time
	var step: float = maxf(delta, 0.001)
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_accel_smooth = lerpf(_accel_smooth, (speed - _last_speed) / step, minf(delta * 6.0, 1.0))
	_turn_smooth = lerpf(_turn_smooth, angle_difference(_last_yaw, rotation.y) / step, minf(delta * 6.0, 1.0))
	_last_speed = speed
	_last_yaw = rotation.y
	_nod = move_toward(_nod, 0.0, delta * 2.6)
	_jolt = move_toward(_jolt, 0.0, delta * 2.2)
	_lunge = move_toward(_lunge, 0.0, delta * 2.0)
	# Top-heavy on small wheels: tips forward as it speeds up, back as it
	# brakes, and leans into its turns.
	var pitch: float = clampf(_accel_smooth * 0.035, -0.12, 0.13) + speed * 0.018
	var roll: float = clampf(-_turn_smooth * 0.05, -0.1, 0.1)
	var yaw: float = 0.0
	var lift: float = 0.0
	match _mood:
		"sleep":
			# Docked: bowed, breathing slowly.
			pitch = 0.1 + sin(t * 0.9) * 0.012
		"off":
			pitch = 0.17
			roll = 0.05
		"dazed":
			var shake: float = clampf(stun_time_left / 1.5, 0.25, 1.0)
			yaw = sin(t * 38.0) * 0.2 * shake
			roll += sin(t * 31.0) * 0.07 * shake
			pitch -= 0.06
		"question":
			roll += 0.06
			if _look_timer > 0.0:
				# Stopped to check something: swivels left, then right.
				yaw = sin((LOOK_TIME - _look_timer) / LOOK_TIME * TAU) * 0.7
		"alert":
			lift = absf(sin(t * 9.0)) * 0.012
		_:
			if speed < 0.2:
				roll += sin(t * 1.3) * 0.022
	# A bob with every line it speaks.
	pitch += sin(_nod * PI) * 0.1
	# Spotted him: rears back and hops.
	pitch -= sin(_jolt * PI) * 0.2
	lift += sin(_jolt * PI) * 0.06
	# Ramming him.
	pitch += sin(_lunge * PI) * 0.38
	# Kept out by a door: rocks against it.
	if _door_timer > 0.0 and _mood != "off":
		pitch += maxf(sin(t * 7.0), 0.0) * 0.07
	var ease_in: float = minf(delta * 14.0, 1.0)
	model.rotation.x = lerpf(model.rotation.x, pitch, ease_in)
	model.rotation.z = lerpf(model.rotation.z, roll, ease_in)
	model.rotation.y = PI + yaw
	model.position.y = lerpf(model.position.y, lift, ease_in)
	_animate_face(delta)


func _animate_face(delta: float) -> void:
	var t: float = _anim_time
	match _mood:
		"smile":
			_blink_timer -= delta
			if _blink_timer <= 0.0:
				_blink_timer = randf_range(2.5, 6.0)
			_face.text = "|)" if _blink_timer < 0.13 else ":)"
		"sleep":
			_face.text = ["z", "z z", "z z z"][int(t * 0.8) % 3]
			_glow.light_energy = GLOW_ENERGY * (0.55 + 0.25 * sin(t * 1.2))
		"question":
			_face.scale = Vector3.ONE * (1.0 + 0.06 * sin(t * 4.0))
		"alert":
			var pulse: float = absf(sin(t * 8.0))
			_face.scale = Vector3.ONE * (1.0 + 0.2 * pulse)
			_glow.light_energy = GLOW_ENERGY * (1.0 + 0.8 * pulse)
		"dazed":
			_scramble_timer -= delta
			if _scramble_timer <= 0.0:
				_scramble_timer = 0.09
				_face.text = SCRAMBLED_FACES.pick_random()
			_glow.light_energy = GLOW_ENERGY * randf_range(0.3, 1.2)


# --------------------------------------------------------------------- face

func _say(line: String) -> void:
	if player == null or get_player_distance() > SPEECH_RANGE:
		return
	SfxSynth.play_at(self, SfxSynth.bell(), get_eye_position(), -12.0, 2.2, SPEECH_RANGE)
	EventBus.ui_subtitle.emit(line, 3.5, &"CONCIERGE")
	_nod = 1.0


func _set_face(mood: String) -> void:
	_mood = mood
	_face.scale = Vector3.ONE
	_glow.light_energy = GLOW_ENERGY
	var col := Color(0.35, 1.0, 0.75)
	var text := ":)"
	match mood:
		"sleep":
			col = Color(0.25, 0.5, 0.45)
			text = "z z z"
		"question":
			col = Color(1.0, 0.75, 0.2)
			text = "?"
		"alert":
			col = Color(1.0, 0.25, 0.2)
			text = "!"
		"dazed":
			col = Color(0.85, 0.85, 0.9)
			text = "x_x"
		"off":
			col = Color(0, 0, 0)
			text = ""
	_face.text = text
	_face.modulate = col
	_glow.light_color = col
	_glow.visible = mood != "off"
	if _screen_mat != null:
		_screen_mat.albedo_color = col * 0.25 if mood != "off" else Color(0.02, 0.02, 0.02)
		_screen_mat.emission = col * 0.35
		_screen_mat.emission_energy_multiplier = 0.0 if mood == "off" else 1.2
