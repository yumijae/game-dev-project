class_name PlayerController
extends CharacterBody3D
## Juan Dela Cruz, 4th-year BSIT, STI College Kalibo.
##
## First-person movement, footstep acoustics, the interaction/action wheel,
## timed "channel" interactions (which shaky hands slow down and fumble),
## hiding, peeking under doors, and item use.
##
## Controls:  WASD move - Shift sprint - Ctrl crouch - E interact - Q next action
##   F flashlight - Tab raise phone - V cameras on/off (A/D camera, W/S floor)
##   T footwear - 1-6 backpack to hand
##   LMB use held item - RMB cancel - R switch hand - X drop - G stifle a gasp
##   Esc pause (PauseMenu)

const STAND_HEIGHT: float = 1.75
const CROUCH_HEIGHT: float = 1.0
## 128: open door leaves (InteractableDoor.LAYER_OPEN_LEAF), so an open door
## can still be looked at and closed.
const INTERACT_RAY_MASK: int = 1 | 2 | 8 | 16 | 128
## Fire extinguisher: one burst reaches this far in this half-angle cone.
const EXTINGUISHER_RANGE: float = 4.5
const EXTINGUISHER_CONE: float = 28.0
const EXTINGUISHER_STUN: float = 5.0
const EXTINGUISHER_BLIND: float = 8.0
const EXTINGUISHER_NOISE: float = 9.0
const STEP_LENGTH_WALK: float = 1.7
const STEP_LENGTH_SPRINT: float = 2.1
const STEP_LENGTH_SNEAK: float = 1.2
const FOOTSTEP_RADIUS_WALK: float = 6.0
const FOOTSTEP_RADIUS_SPRINT: float = 11.0
const FOOTSTEP_RADIUS_SNEAK: float = 2.5
const SPRINT_DRAIN: float = 16.0
const STAMINA_RECOVERY_MOVING: float = 7.0
const STAMINA_RECOVERY_RESTING: float = 14.0
const FUMBLE_NOISE_RADIUS: float = 9.0
const GASP_NOISE_RADIUS: float = 8.0
const WOUND_INVULNERABILITY: float = 3.0
const FOCUS_REFRESH_INTERVAL: float = 0.15
const AMBIENT_LIGHT_FACTOR: float = 0.7

@export var walk_speed: float = 3.4
@export var sprint_speed: float = 5.6
@export var crouch_speed: float = 1.6
@export var mouse_sensitivity: float = 0.0022
@export var interact_distance: float = 2.4

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var ceiling_check: ShapeCast3D = $CeilingCheck

var stats: PlayerStats = null
var inventory: InventoryComponent = null
var phone: PlayerPhoneUI = null
## The CCTV app (V): school security camera feeds on the phone.
var cctv: CctvApp = null

var is_crouching: bool = false
var is_sprinting: bool = false
var is_peeking: bool = false
var is_dead: bool = false
## True whenever Juan is inside a HidingSpot.
var is_hidden: bool:
	get:
		return _hiding_spot != null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _hiding_spot: HidingSpot = null
## A robot knows which spot Juan is in (it watched him climb in, or heard him
## from right beside it). Hiding there protects nothing until he moves.
var is_hide_exposed: bool = false
var _focused: Node = null
var _actions: Array[Dictionary] = []
var _selected_action: int = 0
var _focus_timer: float = 0.0
var _step_distance: float = 0.0
var _invulnerable_time: float = 0.0
var _peek_camera: Camera3D = null
var _gasp_time_left: float = -1.0
var _was_moving: bool = false

# Active channel (timed interaction); empty when idle.
var _channel: Dictionary = {}

## Anti-camping: how long Juan has stayed around one spot (seconds). It only
## counts once the robots are loose. See get_camp_level().
var camp_time: float = 0.0
var _camp_anchor: Vector3 = Vector3.INF
var _camp_warned: int = 0
## Within this many metres (same floor) of the anchor he counts as staying put.
const CAMP_RADIUS: float = 12.0
## Grace before it starts to count, and how long after that until the robots
## home in on him.
const CAMP_GRACE: float = 45.0
const CAMP_RAMP: float = 60.0
## Moving on keeps this share of the clock (no resetting by shuffling between
## two lockers).
const CAMP_CARRY_OVER: float = 0.4
## 0..1: how far into "working" posture the view is (eases in and out).
var _work: float = 0.0
var _work_phase: float = 0.0
## Lean, heave and sway of the view while Juan's hands are busy (metres /
## radians); heavier for labour, shakier with shaky hands.
const WORK_DIP: float = 0.1
const WORK_DIP_LABOUR: float = 0.17
const WORK_BOB: float = 0.012
const WORK_ROLL: float = 0.012


func _ready() -> void:
	add_to_group(&"player")
	# Juan still walks into an open door leaf; robots do not (they would snag).
	collision_mask |= InteractableDoor.LAYER_OPEN_LEAF
	_ensure_input_actions()
	_build_components()
	ray.target_position = Vector3(0.0, 0.0, -interact_distance)
	ray.collision_mask = INTERACT_RAY_MASK
	ray.collide_with_areas = true
	_peek_camera = Camera3D.new()
	_peek_camera.name = "PeekCamera"
	_peek_camera.top_level = true
	_peek_camera.near = 0.01
	_peek_camera.fov = 70.0
	add_child(_peek_camera)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	camera.fov = GameSettings.fov
	GameSettings.changed.connect(func() -> void: camera.fov = GameSettings.fov)
	EventBus.game_lost.connect(_on_game_ended.unbind(1))
	EventBus.game_won.connect(_on_game_ended.unbind(3))


func _build_components() -> void:
	stats = PlayerStats.new()
	stats.name = "PlayerStats"
	add_child(stats)
	inventory = InventoryComponent.new()
	inventory.name = "InventoryComponent"
	add_child(inventory)
	phone = PlayerPhoneUI.new()
	phone.name = "PlayerPhoneUI"
	phone.setup(stats)
	camera.add_child(phone)
	cctv = CctvApp.new()
	cctv.name = "CctvApp"
	cctv.setup(self)
	add_child(cctv)
	phone.attach_screen(cctv)


# ---------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_peeking and not _is_watching_cameras():
		var motion := event as InputEventMouseMotion
		var sensitivity: float = mouse_sensitivity * GameSettings.sensitivity
		rotate_y(-motion.relative.x * sensitivity)
		head.rotate_x(-motion.relative.y * sensitivity * (-1.0 if GameSettings.invert_y else 1.0))
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-88.0), deg_to_rad(88.0))
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if is_dead:
		return
	if phone.is_phone_out and phone.screen != null:
		# Phone up: the wheel and mouse buttons drive the phone.
		var mb := event as InputEventMouseButton
		if mb != null and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				phone.screen.scroll(1)
				return
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				phone.screen.scroll(-1)
				return
		if phone.screen.is_in_cameras():
			# Juan stands still while he watches, so the movement keys are
			# free: A/D step through the cameras, W/S change floor.
			if event.is_action_pressed(&"move_left"):
				phone.screen.camera_step(-1)
				return
			if event.is_action_pressed(&"move_right"):
				phone.screen.camera_step(1)
				return
			if event.is_action_pressed(&"move_forward"):
				phone.screen.camera_floor(1)
				return
			if event.is_action_pressed(&"move_back"):
				phone.screen.camera_floor(-1)
				return
		if event.is_action_pressed(&"use_item"):
			phone.screen.confirm()
			return
		if event.is_action_pressed(&"cancel_action"):
			if not phone.screen.back():
				phone.set_phone_out(false)
			return
	if event.is_action_pressed(&"toggle_cctv") and not is_channeling() and not is_peeking:
		# V toggles the Cameras app from anywhere: on from the pocket or from
		# another app, off (phone away) when the feed is already up.
		if phone.is_phone_out and phone.screen != null and phone.screen.is_in_cameras():
			phone.set_phone_out(false)
		else:
			phone.set_phone_out(true)
			if phone.is_phone_out and phone.screen != null:
				phone.screen.show_phone(PhoneScreen.Page.CAMERAS)
		return
	if event.is_action_pressed(&"stifle_gasp"):
		_stifle_gasp()
	elif event.is_action_pressed(&"cancel_action"):
		if is_channeling():
			cancel_channel()
		elif is_peeking:
			end_peek()
	elif event.is_action_pressed(&"interact"):
		_on_interact_pressed()
	elif is_channeling() or is_peeking:
		return
	elif event.is_action_pressed(&"cycle_action"):
		_cycle_action()
	elif event.is_action_pressed(&"toggle_flashlight"):
		phone.toggle_flashlight()
	elif event.is_action_pressed(&"toggle_phone"):
		phone.toggle_phone_out()
	elif event.is_action_pressed(&"cycle_footwear"):
		_change_footwear()
	elif event.is_action_pressed(&"use_item"):
		use_active_item()
	elif event.is_action_pressed(&"switch_hand"):
		inventory.switch_active_hand()
	elif event.is_action_pressed(&"drop_item"):
		drop_active_item()
	else:
		for i: int in InventoryComponent.BACKPACK_SLOTS:
			if event.is_action_pressed("slot_%d" % (i + 1)):
				inventory.swap_backpack_with_hand(i)
				break


## Eyes on the CCTV: Juan stands still and cannot look around.
func _is_watching_cameras() -> bool:
	return phone != null and phone.screen != null and phone.screen.is_in_cameras()


func _on_interact_pressed() -> void:
	if is_peeking:
		end_peek()
	elif is_channeling():
		return
	elif is_hidden:
		exit_hiding()
	elif _focused != null and not _actions.is_empty():
		var action: Dictionary = _actions[clampi(_selected_action, 0, _actions.size() - 1)]
		_focused.call("interact", self, action["id"])
		_refresh_focus(true)


func _cycle_action() -> void:
	if _actions.size() > 1:
		_selected_action = (_selected_action + 1) % _actions.size()
		EventBus.ui_prompt_changed.emit(_actions, _selected_action)


func _change_footwear() -> void:
	stats.cycle_footwear()
	EventBus.ui_notification.emit("Footwear: %s" % stats.get_footwear_name(), 1.8)


# -------------------------------------------------------------------- physics

func _physics_process(delta: float) -> void:
	_invulnerable_time = maxf(_invulnerable_time - delta, 0.0)
	_update_gasp(delta)
	_update_context()
	if is_dead:
		return
	if is_channeling():
		_update_channel(delta)
	var frozen: bool = is_channeling() or is_hidden or is_peeking or _is_watching_cameras()
	if frozen:
		is_sprinting = false
		# Hard labour (dragging furniture) costs stamina; it must not also rest him.
		var labouring: bool = is_channeling() and float(_channel["stamina_cost"]) > 0.0
		if not labouring:
			stats.recover_stamina(STAMINA_RECOVERY_RESTING * delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if is_hidden:
			head.position.y = lerpf(head.position.y, _hiding_spot.eye_height, minf(10.0 * delta, 1.0))
		else:
			if not is_on_floor():
				velocity.y -= _gravity * delta
			move_and_slide()
	else:
		_move(delta)
	_update_work_motion(delta)
	_update_camping(delta)
	_focus_timer += delta
	if _focus_timer >= FOCUS_REFRESH_INTERVAL:
		_focus_timer = 0.0
		_refresh_focus(false)


## 0 while Juan keeps moving; rises to 1 when he has stayed around one spot
## for CAMP_GRACE + CAMP_RAMP seconds. The robots sharpen their guesses as it
## rises and, at 1, keep getting a fix on him (RobotBase._camp_pressure).
func get_camp_level() -> float:
	return clampf((camp_time - CAMP_GRACE) / CAMP_RAMP, 0.0, 1.0)


func _update_camping(delta: float) -> void:
	if is_dead or not TimeManager.is_night_active():
		camp_time = 0.0
		_camp_anchor = Vector3.INF
		return
	var here: Vector3 = global_position
	var moved_on: bool = _camp_anchor == Vector3.INF \
		or Campus.floor_from_y(here.y + 0.3) != Campus.floor_from_y(_camp_anchor.y + 0.3) \
		or Vector2(here.x - _camp_anchor.x, here.z - _camp_anchor.z).length() > CAMP_RADIUS
	if moved_on:
		_camp_anchor = here
		camp_time *= CAMP_CARRY_OVER
		_camp_warned = 0
		return
	camp_time += delta
	var level: float = get_camp_level()
	if level >= 0.5 and _camp_warned < 1:
		_camp_warned = 1
		EventBus.ui_subtitle.emit("I've been here too long. They'll find me.", 4.0, &"Juan")
	elif level >= 1.0 and _camp_warned < 2:
		_camp_warned = 2
		EventBus.ui_subtitle.emit("...Something is coming this way. I have to move.", 4.0, &"Juan")


## While a timed action runs, the view leans in towards the work and heaves
## gently with each effort (a heavy drag much more), then eases back.
func _update_work_motion(delta: float) -> void:
	var working: bool = is_channeling()
	_work = move_toward(_work, 1.0 if working else 0.0, delta * (3.0 if working else 4.0))
	if _work <= 0.0:
		if camera.position != Vector3.ZERO or camera.rotation.z != 0.0:
			camera.position = Vector3.ZERO
			camera.rotation.z = 0.0
		return
	var labour: bool = working and float(_channel.get("stamina_cost", 0.0)) > 0.0
	var shaky: float = 1.8 if stats.has_shaky_hands else 1.0
	_work_phase += delta * (4.2 if labour else 7.0)
	var ease: float = _work * _work * (3.0 - 2.0 * _work)
	var dip: float = (WORK_DIP_LABOUR if labour else WORK_DIP) * ease
	var bob: float = sin(_work_phase) * WORK_BOB * (2.4 if labour else 1.0) * shaky * ease
	camera.position = Vector3(sin(_work_phase * 0.5) * 0.006 * shaky * ease, -dip + bob, -0.04 * ease)
	camera.rotation.z = sin(_work_phase * 0.5 + 0.7) * WORK_ROLL * (2.0 if labour else 1.0) * shaky * ease


func _move(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_update_crouch(delta)
	var input: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var moving: bool = input.length() > 0.1
	var speed: float = walk_speed
	is_sprinting = false
	if is_crouching:
		speed = crouch_speed
	elif moving and Input.is_action_pressed(&"sprint") and stats.can_sprint() \
			and inventory.get_load() <= InventoryComponent.SPRINT_LOAD:
		is_sprinting = stats.drain_stamina(SPRINT_DRAIN * delta)
		if is_sprinting:
			speed = sprint_speed
	if not is_sprinting:
		stats.recover_stamina((STAMINA_RECOVERY_MOVING if moving else STAMINA_RECOVERY_RESTING) * delta)
	speed *= stats.get_speed_multiplier() * inventory.get_speed_multiplier()
	var direction: Vector3 = (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	var acceleration: float = (14.0 if is_on_floor() else 3.0) * speed
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	move_and_slide()
	_update_footsteps(delta)


func _update_crouch(delta: float) -> void:
	var want_crouch: bool = Input.is_action_pressed(&"crouch")
	if not want_crouch and is_crouching and ceiling_check.is_colliding():
		want_crouch = true
	is_crouching = want_crouch
	var capsule := body_shape.shape as CapsuleShape3D
	var target: float = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	capsule.height = move_toward(capsule.height, target, 4.5 * delta)
	body_shape.position.y = capsule.height * 0.5
	head.position.y = lerpf(head.position.y, capsule.height - 0.15, minf(14.0 * delta, 1.0))


## Footsteps: radius depends on gait and footwear; the Server Room hum eats 4 m.
func _update_footsteps(delta: float) -> void:
	var flat_speed: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = is_on_floor() and flat_speed > 0.3
	if not moving:
		_was_moving = false
		return
	_was_moving = true
	var step_length: float = STEP_LENGTH_WALK
	var radius: float = FOOTSTEP_RADIUS_WALK
	var noise_type: StringName = &"footstep_walk"
	if is_crouching:
		step_length = STEP_LENGTH_SNEAK
		radius = FOOTSTEP_RADIUS_SNEAK
		noise_type = &"footstep_sneak"
	elif is_sprinting:
		step_length = STEP_LENGTH_SPRINT
		radius = FOOTSTEP_RADIUS_SPRINT
		noise_type = &"footstep_sprint"
	_step_distance += flat_speed * delta
	if _step_distance >= step_length:
		_step_distance = 0.0
		var step_db: float = -15.0
		if is_crouching:
			step_db = -27.0
		elif is_sprinting:
			step_db = -8.0
		var step_sound: AudioStream = SfxSynth.shoe_step()
		if stats.footwear == PlayerStats.Footwear.SOCKS:
			step_sound = SfxSynth.sock_step()
		elif stats.footwear == PlayerStats.Footwear.BAREFOOT:
			step_sound = SfxSynth.bare_step()
		SfxSynth.play_at(self, step_sound, global_position + Vector3.UP * 0.05, step_db,
			randf_range(0.92, 1.08) * (1.08 if is_sprinting else 1.0), 24.0)
		NoiseManager.emit_footstep(global_position, radius * stats.get_noise_multiplier(), noise_type, self)


## Tells PlayerStats whether Juan is in pitch darkness and whether he is hidden.
func _update_context() -> void:
	stats.is_hidden = is_hidden
	stats.in_darkness = not is_lit()


## Lit by his own phone, an emergency light, or the open sky.
func is_lit() -> bool:
	if phone.is_flashlight_on or phone.is_phone_out:
		return true
	if Campus.floor_from_y(global_position.y) == Campus.ROOF_FLOOR and Campus.stairwell_at(global_position) == "":
		return true
	if not Campus.is_inside_footprint(global_position):
		return true
	for node: Node in get_tree().get_nodes_in_group(&"ambient_lights"):
		var light := node as OmniLight3D
		if light != null and light.visible \
				and light.global_position.distance_to(head.global_position) <= light.omni_range * AMBIENT_LIGHT_FACTOR:
			return true
	return false


# ---------------------------------------------------------------- interaction

func _refresh_focus(force: bool) -> void:
	var target: Node = null
	if not (is_hidden or is_peeking or is_channeling() or is_dead):
		target = _find_interactable()
	var actions: Array[Dictionary] = []
	if target != null:
		actions = target.call("get_interactions", self)
	if is_hidden:
		actions = [{"id": &"leave", "label": "Leave hiding spot"}]
	elif is_peeking:
		actions = [{"id": &"stop_peek", "label": "Stop peeking"}]
	if target != _focused:
		_selected_action = 0
		if target != null and target.has_method("on_looked_at"):
			target.call("on_looked_at", self)
	var changed: bool = force or target != _focused or not _same_actions(actions, _actions)
	_focused = target
	_actions = actions
	_selected_action = clampi(_selected_action, 0, maxi(_actions.size() - 1, 0))
	if changed:
		EventBus.ui_prompt_changed.emit(_actions, _selected_action)


func _find_interactable() -> Node:
	if not ray.is_colliding():
		return null
	var node: Node = ray.get_collider() as Node
	while node != null and not node.has_method("get_interactions"):
		node = node.get_parent()
	return node


func _same_actions(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i]["id"] != b[i]["id"] or a[i]["label"] != b[i]["label"]:
			return false
	return true


# ------------------------------------------------------------------- channels

func is_channeling() -> bool:
	return not _channel.is_empty()


func is_busy() -> bool:
	return is_channeling() or is_peeking or is_hidden or is_dead


## Starts a timed interaction. Juan stands still until it finishes.
## Options:
##   noise_type / noise_radius / noise_interval - noise pulsed while channeling
##   stamina_cost - total stamina spent over the channel (must be available)
##   can_fumble   - false for silent, careful work (default true)
##   on_cancel    - Callable(elapsed: float) when interrupted
##   on_tick      - Callable(delta: float) every physics frame
##   on_progress  - Callable(ratio: float) every physics frame, 0..1: drives
##                  the animation of whatever is being built (a chair swung
##                  under a handle, a cable wound round it, a prop dragged)
func start_channel(label: String, duration: float, on_complete: Callable, options: Dictionary = {}) -> bool:
	if is_channeling() or is_peeking or is_dead:
		return false
	var stamina_cost: float = options.get("stamina_cost", 0.0)
	if stats.stamina < stamina_cost:
		EventBus.ui_notification.emit("Too exhausted for that.", 2.0)
		return false
	var time: float = stats.get_channel_time(duration)
	var fumble_at: float = -1.0
	var can_fumble: bool = options.get("can_fumble", true)
	if can_fumble and stats.roll_fumble():
		fumble_at = time * randf_range(0.35, 0.8)
	_channel = {
		"label": label, "time": time, "elapsed": 0.0, "on_complete": on_complete,
		"fumble_at": fumble_at, "stamina_cost": stamina_cost, "noise_timer": 0.0,
		"noise_type": options.get("noise_type", &""), "noise_radius": options.get("noise_radius", 0.0),
		"noise_interval": options.get("noise_interval", 1.0),
		"on_cancel": options.get("on_cancel", Callable()), "on_tick": options.get("on_tick", Callable()),
		"on_progress": options.get("on_progress", Callable()),
	}
	velocity = Vector3.ZERO
	EventBus.ui_channel_started.emit(label, time)
	_emit_channel_noise()
	return true


func cancel_channel() -> void:
	if not is_channeling():
		return
	var on_cancel: Callable = _channel["on_cancel"]
	var elapsed: float = _channel["elapsed"]
	_channel = {}
	EventBus.ui_channel_finished.emit(false)
	if on_cancel.is_valid():
		on_cancel.call(elapsed)


func _update_channel(delta: float) -> void:
	var time: float = _channel["time"]
	var elapsed: float = float(_channel["elapsed"]) + delta
	_channel["elapsed"] = elapsed
	var stamina_cost: float = _channel["stamina_cost"]
	if stamina_cost > 0.0:
		stats.drain_stamina(stamina_cost * delta / time)
	var noise_timer: float = float(_channel["noise_timer"]) + delta
	var noise_interval: float = _channel["noise_interval"]
	if noise_timer >= noise_interval:
		noise_timer = 0.0
		_emit_channel_noise()
	_channel["noise_timer"] = noise_timer
	var on_tick: Callable = _channel["on_tick"]
	if on_tick.is_valid():
		on_tick.call(delta)
		if not is_channeling():
			return
	var fumble_at: float = _channel["fumble_at"]
	if fumble_at > 0.0 and elapsed >= fumble_at:
		_fumble()
		return
	var on_progress: Callable = _channel["on_progress"]
	if on_progress.is_valid():
		on_progress.call(clampf(elapsed / time, 0.0, 1.0))
	EventBus.ui_channel_progress.emit(clampf(elapsed / time, 0.0, 1.0))
	if elapsed >= time:
		var on_complete: Callable = _channel["on_complete"]
		_channel = {}
		EventBus.ui_channel_finished.emit(true)
		if on_complete.is_valid():
			on_complete.call()


func _emit_channel_noise() -> void:
	var radius: float = _channel["noise_radius"]
	if radius > 0.0:
		var noise_type: StringName = _channel["noise_type"]
		NoiseManager.emit_noise(global_position, radius, noise_type, self)


## Shaky hands: the thing slips and rings off the floor tiles.
func _fumble() -> void:
	NoiseManager.emit_noise(global_position, FUMBLE_NOISE_RADIUS, &"metal_clatter", self)
	SfxSynth.play_at(self, SfxSynth.clatter(), global_position, -4.0)
	EventBus.ui_notification.emit("Your hands are shaking - it slips and clatters!", 2.5)
	cancel_channel()


# --------------------------------------------------------------------- hiding

func get_hiding_spot() -> Node3D:
	return _hiding_spot


func enter_hiding(spot: HidingSpot) -> void:
	if is_busy():
		return
	# Anything that had eyes on him a moment ago saw where he went.
	var watcher: RobotBase = null
	for node: Node in get_tree().get_nodes_in_group(&"hostile_presence"):
		var robot := node as RobotBase
		if robot != null and robot.is_threatening() and robot.saw_player_recently():
			watcher = robot
			break
	_hiding_spot = spot
	spot.occupant = self
	is_hide_exposed = false
	velocity = Vector3.ZERO
	global_position = spot.get_hide_position()
	EventBus.player_hidden_changed.emit(true, spot)
	_refresh_focus(true)
	if watcher != null:
		expose_hiding(watcher)


## A robot has worked out which hiding spot Juan is in: it can see and reach
## him there until he gets out and finds another.
func expose_hiding(by: RobotBase = null) -> void:
	if not is_hidden or is_hide_exposed:
		return
	is_hide_exposed = true
	stats.add_panic(12.0)
	EventBus.ui_notification.emit("It knows you are in here. Get out!", 3.5)
	if by != null:
		by.on_found_hidden(global_position)


func exit_hiding() -> void:
	if _hiding_spot == null:
		return
	var spot: HidingSpot = _hiding_spot
	_hiding_spot = null
	is_hide_exposed = false
	spot.occupant = null
	global_position = _safe_exit_position(spot)
	velocity = Vector3.ZERO
	EventBus.player_hidden_changed.emit(false, spot)
	_refresh_focus(true)


## The spot's own exit point when Juan fits there; otherwise the nearest
## point that does. Some exits land in a wall, a sink counter or a chair, and
## the physics push-out then wedged Juan into gaps no robot could follow.
## A valid point has floor under it, room for the standing capsule, navmesh
## within reach (so the robots can still get to him) and no wall between it
## and the hiding spot.
func _safe_exit_position(spot: HidingSpot) -> Vector3:
	var preferred: Vector3 = spot.get_exit_position()
	var space := get_world_3d().direct_space_state
	var map: RID = get_world_3d().navigation_map
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = STAND_HEIGHT
	var fit := PhysicsShapeQueryParameters3D.new()
	fit.shape = capsule
	fit.collision_mask = collision_mask
	fit.exclude = [get_rid()]
	var origin: Vector3 = spot.global_position
	var radius: float = 0.0
	while radius <= 1.5:
		var steps: int = 1 if radius == 0.0 else 16
		for i: int in steps:
			var angle: float = TAU * float(i) / float(steps)
			var candidate: Vector3 = preferred + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var floor_query := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.5, candidate + Vector3.DOWN * 0.4, 1)
			var floor_hit: Dictionary = space.intersect_ray(floor_query)
			if floor_hit.is_empty() or (floor_hit["normal"] as Vector3).y < 0.7:
				continue
			var ground: Vector3 = floor_hit["position"]
			fit.transform = Transform3D(Basis(), ground + Vector3.UP * (STAND_HEIGHT * 0.5 + 0.04))
			if not space.intersect_shape(fit, 1).is_empty():
				continue
			var nav_point: Vector3 = NavigationServer3D.map_get_closest_point(map, ground)
			if Vector2(nav_point.x - ground.x, nav_point.z - ground.z).length() > 0.3 or absf(nav_point.y - ground.y) > 0.4:
				continue
			var sight := PhysicsRayQueryParameters3D.create(Vector3(origin.x, ground.y + 0.9, origin.z),
				ground + Vector3.UP * 0.9, collision_mask)
			sight.exclude = [get_rid()]
			if not space.intersect_ray(sight).is_empty():
				continue
			return ground + Vector3.UP * 0.02
		radius += 0.15
	return preferred


# -------------------------------------------------------------------- peeking

## Drops the view to the gap under a door. `view` is the peek camera's pose.
func begin_peek(view: Transform3D) -> void:
	if is_busy():
		return
	is_peeking = true
	_peek_camera.global_transform = view
	_peek_camera.current = true
	EventBus.ui_peek_changed.emit(true)
	_refresh_focus(true)


func end_peek() -> void:
	if not is_peeking:
		return
	is_peeking = false
	camera.current = true
	EventBus.ui_peek_changed.emit(false)
	_refresh_focus(true)


# ---------------------------------------------------------------------- items

## Left click: the held item's own action.
func use_active_item() -> void:
	if is_busy():
		return
	var item_id: StringName = inventory.get_active_item()
	match item_id:
		&"":
			return
		ItemDB.WATER:
			inventory.remove_item(item_id, 1)
			stats.reduce_panic(35.0)
			EventBus.item_used.emit(item_id)
			EventBus.ui_notification.emit("Cold water. Breathe.", 2.0)
		ItemDB.ALCOHOL, ItemDB.GAUZE, ItemDB.TABLECLOTH_RAG:
			_begin_first_aid()
		ItemDB.GLASS_BOTTLE:
			inventory.remove_item(item_id, 1)
			EventBus.item_used.emit(item_id)
			ThrownBottle.launch(get_tree().current_scene, camera.global_position - camera.global_transform.basis.z * 0.4,
				-camera.global_transform.basis.z * 12.0 + Vector3.UP * 2.5)
		ItemDB.FIRE_EXTINGUISHER:
			_spray_extinguisher()
		ItemDB.TASER:
			_fire_taser()
		ItemDB.POWERBANK:
			start_channel("Charging the phone", 5.0, _finish_powerbank, {"can_fumble": false})
		_:
			EventBus.ui_notification.emit(ItemDB.get_description(item_id), 3.5)


func drop_active_item() -> void:
	if is_busy():
		return
	var held: Dictionary = inventory.take_slot(inventory.active_hand)
	if held.is_empty():
		return
	drop_item_in_world(held["id"], held["count"])


func drop_item_in_world(item_id: StringName, count: int) -> void:
	WorldItem.spawn(get_tree().current_scene, item_id, count, _get_drop_position())


## A point on the floor just in front of Juan.
func _get_drop_position() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	var origin: Vector3 = global_position + Vector3.UP * 0.9
	var reach: Vector3 = origin + forward * 0.9
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var forward_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, reach, 1 | 8 | 16))
	if not forward_hit.is_empty():
		var hit_point: Vector3 = forward_hit["position"]
		reach = hit_point - forward * 0.25
	var down_hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(reach, reach + Vector3.DOWN * 3.0, 1))
	if down_hit.is_empty():
		return global_position
	var floor_point: Vector3 = down_hit["position"]
	return floor_point


## One burst of CO2 in a cone ahead: every robot caught in it has its sensors
## whited out - it stops dead and loses track of Juan.
func _spray_extinguisher() -> void:
	inventory.remove_item(ItemDB.FIRE_EXTINGUISHER, 1)
	EventBus.item_used.emit(ItemDB.FIRE_EXTINGUISHER)
	var eye: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	SfxSynth.play_at(self, SfxSynth.spray(), eye + forward * 0.6, -4.0, 1.0, 20.0)
	NoiseManager.emit_noise(global_position, EXTINGUISHER_NOISE, &"extinguisher", self)
	_spray_cloud(eye + forward * 0.5, forward)
	var hit_any: bool = false
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var robot := node as Hostile
		if robot == null or not robot.is_active:
			continue
		var centre: Vector3 = robot.global_position + Vector3.UP * 0.6
		var to_robot: Vector3 = centre - eye
		if to_robot.length() > EXTINGUISHER_RANGE or rad_to_deg(forward.angle_to(to_robot)) > EXTINGUISHER_CONE:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, centre, 1 | 8)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		var factor: float = robot.get(&"spray_factor") if robot.get(&"spray_factor") != null else 1.0
		robot.stun(EXTINGUISHER_STUN * factor, &"extinguisher")
		robot.blind(EXTINGUISHER_BLIND * factor)
		hit_any = true
	if inventory.count_of(ItemDB.FIRE_EXTINGUISHER) <= 0:
		EventBus.ui_notification.emit("The extinguisher coughs and runs empty.", 2.5)
	elif hit_any:
		EventBus.ui_notification.emit("Direct hit. It's blinded - move.", 2.0)


const TASER_REACH: float = 1.9
const TASER_CONE: float = 40.0
const TASER_NOISE: float = 7.0


## Jabs the robot in front of Juan, if one is within arm's reach. The taser
## is single use: it is spent only when it connects.
func _fire_taser() -> void:
	var eye: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z
	var target: RobotBase = null
	var best: float = INF
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var robot := node as RobotBase
		if robot == null or not robot.is_active:
			continue
		var centre: Vector3 = robot.global_position + Vector3.UP * minf(robot.body_height * 0.6, 1.0)
		var to_robot: Vector3 = centre - eye
		var flat_gap: float = Vector2(robot.global_position.x - global_position.x, robot.global_position.z - global_position.z).length()
		if flat_gap - robot.body_radius > TASER_REACH or rad_to_deg(forward.angle_to(to_robot)) > TASER_CONE:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, centre, 1 | 8)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		if flat_gap < best:
			best = flat_gap
			target = robot
	var tip: Vector3 = eye + forward * 0.55 + Vector3.DOWN * 0.18
	if target == null:
		# A dry crackle: nothing in reach, and the shot is kept.
		SfxSynth.play_at(self, SfxSynth.zap(), tip, -12.0, 1.3, 12.0)
		EventBus.ui_notification.emit("Nothing in reach. Get closer.", 1.6)
		return
	inventory.remove_item(ItemDB.TASER, 1)
	EventBus.item_used.emit(ItemDB.TASER)
	var hit_at: Vector3 = target.global_position + Vector3.UP * minf(target.body_height * 0.6, 1.0)
	SfxSynth.play_at(self, SfxSynth.zap(), hit_at, 2.0, 1.0, 26.0)
	NoiseManager.emit_noise(global_position, TASER_NOISE, &"taser", self)
	_taser_flash(hit_at)
	var dropped: bool = target.take_taser()
	if dropped:
		SfxSynth.play_at(self, SfxSynth.thud(), target.global_position + Vector3.UP * 0.3, 0.0, 0.7)


## Blue-white arc light and a spray of sparks where the prongs land.
func _taser_flash(at: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	var flash := OmniLight3D.new()
	flash.light_color = Color(0.6, 0.75, 1.0)
	flash.light_energy = 3.0
	flash.omni_range = 3.0
	LightRig.seal(flash, 0.02)
	scene.add_child(flash)
	flash.global_position = at
	var tween: Tween = flash.create_tween()
	for i: int in 3:
		tween.tween_property(flash, "light_energy", 0.4, 0.04)
		tween.tween_property(flash, "light_energy", 3.0, 0.03)
	tween.tween_property(flash, "light_energy", 0.0, 0.12)
	tween.tween_callback(flash.queue_free)
	var sparks := CPUParticles3D.new()
	sparks.one_shot = true
	sparks.explosiveness = 0.95
	sparks.amount = 28
	sparks.lifetime = 0.45
	sparks.spread = 90.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 3.0
	sparks.gravity = Vector3(0, -9.8, 0)
	var spark := BoxMesh.new()
	spark.size = Vector3(0.004, 0.004, 0.022)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.85, 1.0)
	spark.material = mat
	sparks.mesh = spark
	sparks.particle_flag_align_y = true
	scene.add_child(sparks)
	sparks.global_position = at
	sparks.emitting = true
	get_tree().create_timer(1.0).timeout.connect(sparks.queue_free)


func _spray_cloud(from: Vector3, forward: Vector3) -> void:
	var cloud := CPUParticles3D.new()
	cloud.one_shot = true
	cloud.explosiveness = 0.2
	cloud.amount = 60
	cloud.lifetime = 1.4
	cloud.direction = Vector3.FORWARD
	cloud.spread = 14.0
	cloud.initial_velocity_min = 4.0
	cloud.initial_velocity_max = 7.0
	cloud.damping_min = 4.0
	cloud.damping_max = 6.0
	cloud.gravity = Vector3(0, 0.3, 0)
	cloud.scale_amount_min = 0.4
	cloud.scale_amount_max = 1.4
	var puff := SphereMesh.new()
	puff.radius = 0.18
	puff.height = 0.36
	puff.radial_segments = 8
	puff.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.94, 0.96, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = mat
	cloud.mesh = puff
	get_tree().current_scene.add_child(cloud)
	cloud.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), from)
	cloud.emitting = true
	get_tree().create_timer(2.0).timeout.connect(cloud.queue_free)


## Rubbing alcohol + gauze or a tablecloth rag: 7 s to stop the bleeding.
func _begin_first_aid() -> void:
	if not inventory.has_item(ItemDB.ALCOHOL):
		EventBus.ui_notification.emit("You need rubbing alcohol to disinfect it.", 2.5)
		return
	if not inventory.has_item(ItemDB.GAUZE) and not inventory.has_item(ItemDB.TABLECLOTH_RAG):
		EventBus.ui_notification.emit("You need gauze or a tablecloth rag to bind it.", 2.5)
		return
	if not stats.is_bleeding:
		EventBus.ui_notification.emit("Nothing to treat.", 2.0)
		return
	start_channel("Disinfecting and bandaging", 7.0, _finish_first_aid)


func _finish_first_aid() -> void:
	var dressing: StringName = ItemDB.GAUZE if inventory.has_item(ItemDB.GAUZE) else ItemDB.TABLECLOTH_RAG
	if not inventory.has_item(ItemDB.ALCOHOL) or not inventory.has_item(dressing):
		return
	inventory.remove_item(ItemDB.ALCOHOL, 1)
	inventory.remove_item(dressing, 1)
	stats.stop_bleeding()
	EventBus.item_used.emit(ItemDB.ALCOHOL)
	EventBus.ui_notification.emit("Clean and bound. The bleeding has stopped.", 3.0)


func _finish_powerbank() -> void:
	if inventory.remove_item(ItemDB.POWERBANK, 1):
		stats.charge_battery(30.0)
		EventBus.item_used.emit(ItemDB.POWERBANK)
		EventBus.ui_notification.emit("Phone charged to %d%%." % int(stats.phone_battery), 2.5)


# ----------------------------------------------------------- gasp (95% Panic)

## HallucinationManager calls this: press G in time or gasp out loud.
func request_gasp(window: float) -> void:
	if is_dead or _gasp_time_left > 0.0:
		return
	_gasp_time_left = window
	EventBus.ui_gasp_prompt.emit(true, window)


func _stifle_gasp() -> void:
	if _gasp_time_left > 0.0:
		_gasp_time_left = -1.0
		EventBus.ui_gasp_prompt.emit(false, 0.0)


func _update_gasp(delta: float) -> void:
	if _gasp_time_left <= 0.0:
		return
	_gasp_time_left -= delta
	if _gasp_time_left <= 0.0:
		_gasp_time_left = -1.0
		EventBus.ui_gasp_prompt.emit(false, 0.0)
		if not is_dead:
			NoiseManager.emit_noise(global_position, GASP_NOISE_RADIUS, &"gasp", self)
			SfxSynth.play_at(self, SfxSynth.gasp(), head.global_position, -6.0)


# ------------------------------------------------------------ what the AI sees

func get_head_position() -> Vector3:
	return head.global_position


## Scales a robot's sight range: lights give Juan away, darkness and a
## crouch hide him.
func get_visibility_factor() -> float:
	if phone.is_flashlight_on:
		return 1.5
	if phone.is_phone_out:
		return 1.2
	if stats.in_darkness:
		return 0.5 if is_crouching else 0.75
	return 1.0


## Hidden from sight: inside a hiding spot with the flashlight off, and no
## robot knows he is in it.
func is_concealed() -> bool:
	return is_hidden and not phone.is_flashlight_on and not is_hide_exposed


# --------------------------------------------------------------------- damage

## A robot reached Juan. The first hit wounds him (Bleeding); a hit while he
## is already bleeding kills. Returns true when the blow was fatal.
func take_attack(attacker: Hostile) -> bool:
	if is_dead or _invulnerable_time > 0.0:
		return false
	if is_hidden:
		exit_hiding()
	if is_peeking:
		end_peek()
	cancel_channel()
	if stats.is_bleeding:
		die("%s caught you." % attacker.display_name)
		return true
	_invulnerable_time = WOUND_INVULNERABILITY
	stats.start_bleeding(attacker.hostile_id)
	stats.add_panic(35.0)
	var away: Vector3 = global_position - attacker.global_position
	away.y = 0.0
	velocity = away.normalized() * 6.0 + Vector3.UP * 2.0
	EventBus.player_wounded.emit(attacker.hostile_id)
	EventBus.ui_notification.emit("It struck you hard. You are bleeding - one more hit and it is over.", 4.0)
	return false


func die(cause: String) -> void:
	if is_dead:
		return
	is_dead = true
	phone.set_flashlight(false)
	EventBus.game_lost.emit(cause)


func _on_game_ended() -> void:
	is_dead = true
	cancel_channel()
	# The handset is drawn above the HUD and would cover the ending screen.
	phone.set_phone_out(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- input setup

static func _ensure_input_actions() -> void:
	var keys: Dictionary = {
		&"move_forward": [KEY_W, KEY_UP], &"move_back": [KEY_S, KEY_DOWN],
		&"move_left": [KEY_A, KEY_LEFT], &"move_right": [KEY_D, KEY_RIGHT],
		&"sprint": [KEY_SHIFT], &"crouch": [KEY_CTRL],
		&"interact": [KEY_E], &"cycle_action": [KEY_Q],
		&"toggle_flashlight": [KEY_F], &"toggle_phone": [KEY_TAB], &"toggle_cctv": [KEY_V],
		&"cycle_footwear": [KEY_T],
		&"switch_hand": [KEY_R], &"drop_item": [KEY_X], &"stifle_gasp": [KEY_G],
		&"slot_1": [KEY_1], &"slot_2": [KEY_2], &"slot_3": [KEY_3],
		&"slot_4": [KEY_4], &"slot_5": [KEY_5], &"slot_6": [KEY_6],
	}
	for action: StringName in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var codes: Array = keys[action]
		for code: Key in codes:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = code
			InputMap.action_add_event(action, key_event)
	var buttons: Dictionary = {&"use_item": MOUSE_BUTTON_LEFT, &"cancel_action": MOUSE_BUTTON_RIGHT}
	for action: StringName in buttons:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var button_event := InputEventMouseButton.new()
		button_event.button_index = buttons[action]
		InputMap.action_add_event(action, button_event)
