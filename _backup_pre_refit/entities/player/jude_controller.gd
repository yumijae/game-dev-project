class_name JudeController
extends CharacterBody3D
## Protagonist Controller for Jude Villanueva in "Huling Kampana".
## Incorporates 5 survival attributes, acoustic step physics, footwear swapping,
## flashlight manipulation, and interaction raycasting.

signal interaction_prompt_changed(text: String)

@export_group("Locomotion")
@export var walk_speed: float = 3.6
@export var sprint_speed: float = 6.2
@export var crouch_speed: float = 1.8
@export var jump_velocity: float = 4.2
@export var mouse_sensitivity: float = 0.0022
@export var interact_distance: float = 2.4

const STAND_HEIGHT := 1.75
const CROUCH_HEIGHT := 1.05

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var shape: CollisionShape3D = $CollisionShape3D
@onready var ceiling_check: ShapeCast3D = $CeilingCheck

var attributes: SurvivalAttributes
var phone_flashlight: PhoneFlashlight

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _crouching: bool = false
var _focused_interactable: Node = null

# Footstep tracking for NoiseManager
var _step_distance_traveled: float = 0.0
const STEP_DISTANCE_WALK := 1.8
const STEP_DISTANCE_SPRINT := 2.2
const STEP_DISTANCE_CROUCH := 1.2


func _ready() -> void:
	_ensure_components()
	_ensure_input_actions()
	ray.target_position = Vector3(0, 0, -interact_distance)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ensure_components() -> void:
	# Ensure SurvivalAttributes child
	attributes = get_node_or_null("SurvivalAttributes") as SurvivalAttributes
	if not attributes:
		attributes = SurvivalAttributes.new()
		attributes.name = "SurvivalAttributes"
		add_child(attributes)

	# Ensure PhoneFlashlight on Camera3D
	phone_flashlight = camera.get_node_or_null("PhoneFlashlight") as PhoneFlashlight
	if not phone_flashlight:
		phone_flashlight = PhoneFlashlight.new()
		phone_flashlight.name = "PhoneFlashlight"
		camera.add_child(phone_flashlight)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clampf(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			attributes.toggle_torch()

	elif event.is_action_pressed("interact"):
		if _focused_interactable and _focused_interactable.has_method("interact"):
			_focused_interactable.interact(self)

	elif event.is_action_pressed("toggle_torch"):
		attributes.toggle_torch()

	elif event.is_action_pressed("cycle_footwear"):
		_cycle_footwear()

	elif event.is_action_pressed("grounding_breath"):
		_perform_grounding_breath()


func _physics_process(delta: float) -> void:
	# Gravity & Jump
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and not _crouching:
		if attributes.consume_jump_stamina():
			velocity.y = jump_velocity
			# Noise on jump
			var noise_db := 40.0 * attributes.get_noise_multiplier()
			NoiseManager.emit_noise(global_position, 6.0, noise_db, &"jump_grunt")

	_update_crouch(delta)

	# Speed and Locomotion Input
	var is_sprinting := false
	var speed := walk_speed

	if _crouching:
		speed = crouch_speed
		attributes.recover_stamina(delta, true, velocity.length() > 0.1)
	elif Input.is_action_pressed("sprint") and not attributes.is_exhausted:
		var has_stamina := attributes.consume_sprint_stamina(delta)
		if has_stamina:
			speed = sprint_speed
			is_sprinting = true
		else:
			speed = walk_speed
	else:
		speed = walk_speed
		attributes.recover_stamina(delta, false, velocity.length() > 0.1)

	# Footwear speed adjustment
	speed *= attributes.get_speed_multiplier()

	# Panic speed penalty if in Tier 3
	if attributes.current_panic_tier == 3:
		speed *= 0.85

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var accel := 14.0 if is_on_floor() else 3.5

	velocity.x = move_toward(velocity.x, move_dir.x * speed, accel * speed * delta)
	velocity.z = move_toward(velocity.z, move_dir.z * speed, accel * speed * delta)

	var was_on_floor := is_on_floor()
	move_and_slide()

	# Landing noise
	if not was_on_floor and is_on_floor() and velocity.y < -2.0:
		var land_db := 65.0 * attributes.get_noise_multiplier()
		NoiseManager.emit_noise(global_position, 12.0, land_db, &"landing_thud")

	# Footstep generation
	_process_footstep_noise(delta, is_sprinting)

	# Focus raycast for interaction
	_update_interaction_focus()


func _update_crouch(delta: float) -> void:
	var want_crouch := Input.is_action_pressed("crouch")
	if not want_crouch and _crouching and ceiling_check.is_colliding():
		want_crouch = true # Obstructed ceiling overhead
	_crouching = want_crouch

	var target_height := CROUCH_HEIGHT if _crouching else STAND_HEIGHT
	var capsule := shape.shape as CapsuleShape3D
	capsule.height = move_toward(capsule.height, target_height, 4.5 * delta)
	shape.position.y = capsule.height * 0.5
	head.position.y = lerpf(head.position.y, capsule.height - 0.15, 14.0 * delta)


func _process_footstep_noise(_delta: float, is_sprinting: bool) -> void:
	if not is_on_floor():
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.2:
		return

	var step_limit := STEP_DISTANCE_WALK
	var base_db := 45.0
	var noise_type := &"footstep_walk"

	if _crouching:
		step_limit = STEP_DISTANCE_CROUCH
		base_db = 22.0
		noise_type = &"footstep_sneak"
	elif is_sprinting:
		step_limit = STEP_DISTANCE_SPRINT
		base_db = 68.0
		noise_type = &"footstep_sprint"

	_step_distance_traveled += horizontal_speed * _delta
	if _step_distance_traveled >= step_limit:
		_step_distance_traveled = 0.0

		var final_db := base_db * attributes.get_noise_multiplier()
		var audible_radius := 14.0 if is_sprinting else (8.0 if not _crouching else 3.5)
		audible_radius *= attributes.get_noise_multiplier()

		NoiseManager.emit_noise(global_position, audible_radius, final_db, noise_type)


func _update_interaction_focus() -> void:
	var target: Node = null
	if ray.is_colliding():
		var col := ray.get_collider()
		while col and not col.has_method("interact"):
			col = col.get_parent()
		target = col

	if target != _focused_interactable:
		_focused_interactable = target
		var prompt := ""
		if _focused_interactable and _focused_interactable.has_method("get_interaction_prompt"):
			prompt = _focused_interactable.get_interaction_prompt()
		elif _focused_interactable and _focused_interactable.has_method("get_prompt"):
			prompt = _focused_interactable.get_prompt()
		interaction_prompt_changed.emit(prompt)


func _cycle_footwear() -> void:
	match attributes.footwear_type:
		&"shoes":
			attributes.set_footwear(&"socks")
		&"socks":
			attributes.set_footwear(&"barefoot")
		&"barefoot":
			attributes.set_footwear(&"shoes")


func _perform_grounding_breath() -> void:
	if velocity.length() < 0.5:
		attributes.reduce_panic(12.0)
		NoiseManager.emit_noise(global_position, 4.0, 20.0, &"deep_exhale")


static func _ensure_input_actions() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"sprint": [KEY_SHIFT],
		"crouch": [KEY_CTRL, KEY_C],
		"interact": [KEY_E],
		"toggle_torch": [KEY_F],
		"cycle_footwear": [KEY_T],
		"grounding_breath": [KEY_G],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			for key in binds[action]:
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
