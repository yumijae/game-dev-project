class_name BalbalGhoul
extends AswangBase
## The Corpse-Snatcher & Mimic in "Huling Kampana".
## Senses blood/sweat trails, lures Jude with vocal mimicry,
## and transforms into a Black Dog to slip under unsealed classroom door gaps.

@export_group("Mimicry Engine")
@export var mimic_interval_min: float = 8.0
@export var mimic_interval_max: float = 16.0

@export_group("Black Dog Morph")
@export var morph_duration: float = 1.2
@export var is_in_dog_form: bool = false

@export_group("Door Breach")
@export var claw_breach_damage: float = 28.0
@export var breach_attack_interval: float = 1.6

var _mimic_timer: float = 10.0
var _breach_timer: float = 0.0
var _target_door: InteractableDoor = null


func _ready() -> void:
	super._ready()
	aswang_id = &"balbal"
	change_state(&"CORRIDOR_PROWL")


func _physics_process(delta: float) -> void:
	_process_mimicry_cooldown(delta)

	match current_state:
		&"CORRIDOR_PROWL":
			_state_corridor_prowl(delta)
		&"TRACKING_SCENT":
			_state_tracking_scent(delta)
		&"HUNT_CHASE":
			_state_hunt_chase(delta)
		&"BLACK_DOG_BREACH":
			_state_black_dog_breach(delta)
		&"DOOR_CLAW_BASH":
			_state_door_claw_bash(delta)
		&"REPELLED_RETREAT":
			_state_repelled_retreat(delta)


# ==============================================================================
# MIMICRY LURE ENGINE
# ==============================================================================

func _process_mimicry_cooldown(delta: float) -> void:
	if current_state == &"HUNT_CHASE" or current_state == &"BLACK_DOG_BREACH":
		return

	_mimic_timer -= delta
	if _mimic_timer <= 0.0:
		_mimic_timer = randf_range(mimic_interval_min, mimic_interval_max)
		_trigger_voice_mimicry()


func _trigger_voice_mimicry() -> void:
	var phrases: Array[StringName] = [
		&"whisper_tulong",
		&"whisper_open_door",
		&"distant_student_crying",
		&"hallway_keys_jangling"
	]
	var phrase := phrases.pick_random()

	# Emit from a slightly offset position down the hall to mislead Jude
	var offset_dist := randf_range(4.0, 10.0)
	var fake_pos := global_position + (global_transform.basis.x * (offset_dist if randf() > 0.5 else -offset_dist))

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.balbal_mimicry_triggered.emit(phrase, fake_pos)
		NoiseManager.emit_noise(fake_pos, 16.0, 52.0, phrase)


# ==============================================================================
# FSM STATE IMPLEMENTATIONS
# ==============================================================================

func _state_corridor_prowl(delta: float) -> void:
	# Prowl along the central corridor (-12 to 12 along X)
	var floor_y := global_position.y
	var target_x := sin(state_timer * 0.3) * 10.0
	var target := Vector3(target_x, floor_y, 0.0)

	var dir := (target - global_position).normalized()
	velocity = velocity.move_toward(dir * walk_speed, acceleration * delta)
	move_and_slide()

	# Check for blood or sweat trails
	var scent := poll_scent_trail([&"blood", &"sweat"])
	if not scent.is_empty():
		target_investigate_pos = scent["position"]
		change_state(&"TRACKING_SCENT")
		return

	# Hearing check
	var sounds := poll_audible_sounds()
	if not sounds.is_empty():
		target_investigate_pos = sounds[0]["origin"]
		change_state(&"TRACKING_SCENT")
		return

	if has_line_of_sight_to_player():
		change_state(&"HUNT_CHASE")


func _state_tracking_scent(delta: float) -> void:
	var gradient := ScentManager.get_scent_trail_gradient(global_position, 14.0, &"blood")
	if gradient == Vector3.ZERO:
		gradient = ScentManager.get_scent_trail_gradient(global_position, 14.0, &"sweat")

	if gradient != Vector3.ZERO:
		velocity = velocity.move_toward(gradient * walk_speed, acceleration * delta)
	elif target_investigate_pos != Vector3.ZERO:
		var dir := (target_investigate_pos - global_position).normalized()
		velocity = velocity.move_toward(dir * walk_speed, acceleration * delta)
	move_and_slide()

	# Check if blocked by a closed door
	_target_door = _find_blocking_door(global_position, 1.8)
	if _target_door and not _target_door.is_open and not _target_door.is_destroyed:
		if _target_door.can_black_dog_slip_through():
			change_state(&"BLACK_DOG_BREACH")
		else:
			change_state(&"DOOR_CLAW_BASH")
		return

	if has_line_of_sight_to_player():
		change_state(&"HUNT_CHASE")
	elif state_timer > 15.0:
		change_state(&"CORRIDOR_PROWL")


func _state_hunt_chase(delta: float) -> void:
	if not player_ref:
		_find_player()
		return

	# Check repellent mask
	if is_in_repellent_zone():
		change_state(&"REPELLED_RETREAT")
		return

	var target := player_ref.global_position
	var dir := (target - global_position).normalized()
	velocity = velocity.move_toward(dir * chase_speed, acceleration * 1.6 * delta)
	move_and_slide()

	# Check door obstruction between Balbal and Jude
	_target_door = _find_blocking_door(global_position, 1.6)
	if _target_door and not _target_door.is_open and not _target_door.is_destroyed:
		if _target_door.can_black_dog_slip_through():
			change_state(&"BLACK_DOG_BREACH")
		else:
			change_state(&"DOOR_CLAW_BASH")
		return

	# Claws attack
	if global_position.distance_to(target) < 1.6:
		_perform_claw_attack()


func _state_black_dog_breach(delta: float) -> void:
	if not _target_door or _target_door.is_open or _target_door.is_destroyed:
		is_in_dog_form = false
		change_state(&"HUNT_CHASE")
		return

	if not is_in_dog_form:
		is_in_dog_form = true
		# Emits bone-cracking transformation sound
		var bus := get_node_or_null("/root/EventBus")
		if bus:
			bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 12.0, 58.0, &"bone_crack_morph")

	# Slip under the door: Move through the door plane
	var to_door := (_target_door.global_position - global_position).normalized()
	velocity = to_door * 3.5
	move_and_slide()

	if state_timer >= morph_duration:
		# Slithered past door into the room
		global_position = _target_door.global_position + (to_door * 1.5)
		is_in_dog_form = false
		
		var bus := get_node_or_null("/root/EventBus")
		if bus:
			bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 14.0, 65.0, &"ghoul_growl")
		change_state(&"HUNT_CHASE")


func _state_door_claw_bash(delta: float) -> void:
	if not _target_door or _target_door.is_open or _target_door.is_destroyed:
		change_state(&"HUNT_CHASE")
		return

	velocity = Vector3.ZERO
	move_and_slide()

	_breach_timer += delta
	if _breach_timer >= breach_attack_interval:
		_breach_timer = 0.0
		var breached := _target_door.apply_breach_damage(claw_breach_damage, &"balbal")
		if breached:
			change_state(&"HUNT_CHASE")


func _state_repelled_retreat(delta: float) -> void:
	# Backpedal away from vinegar/garlic contamination
	if player_ref:
		var away := (global_position - player_ref.global_position).normalized()
		velocity = away * walk_speed
		move_and_slide()

	if state_timer > 5.0 and not is_in_repellent_zone():
		change_state(&"CORRIDOR_PROWL")


func _perform_claw_attack() -> void:
	if not player_ref:
		return

	var attr := player_ref.get_node_or_null("SurvivalAttributes") as SurvivalAttributes
	if attr:
		attr.start_bleeding(0.6) # Cuts Jude with razor claws
		attr.add_panic(30.0)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.player_damaged.emit(25.0, &"balbal_claws")
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 15.0, 78.0, &"claw_slash")


func _find_blocking_door(pos: Vector3, radius: float) -> InteractableDoor:
	for door in get_tree().get_nodes_in_group("doors"):
		var id := door as InteractableDoor
		if id and id.global_position.distance_to(pos) <= radius:
			return id
	return null
