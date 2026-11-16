class_name ManananggalFlying
extends AswangBase
## Flying upper torso of the Manananggal.
## Hunts the 4F corridors, exterior jalousie windows, and rooftop.
## Senses fresh blood trails, breaks windows to enter classrooms, and fears garlic/salt.

@export_group("Flight Physics")
@export var flight_altitude: float = 16.5 # Rooftop height
@export var swoop_speed: float = 7.5
@export var flap_interval: float = 1.8

var _flap_timer: float = 0.0
var _target_window: JalousieWindow = null
var _is_burning: bool = false


func _ready() -> void:
	super._ready()
	aswang_id = &"manananggal"
	change_state(&"CIRCLING_ROOF")

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.manananggal_torso_salted.connect(_on_torso_salted)


func _physics_process(delta: float) -> void:
	if _is_burning:
		_process_burning_fall(delta)
		return

	_process_wing_flap_noise(delta)

	match current_state:
		&"CIRCLING_ROOF":
			_state_circling_roof(delta)
		&"TRACKING_SCENT":
			_state_tracking_scent(delta)
		&"WINDOW_BREACH":
			_state_window_breach(delta)
		&"CHASE_DIVE":
			_state_chase_dive(delta)
		&"FLEE_WARD":
			_state_flee_ward(delta)


func _process_wing_flap_noise(delta: float) -> void:
	_flap_timer += delta
	if _flap_timer >= flap_interval:
		_flap_timer = 0.0
		var db := 62.0 if current_state == &"CHASE_DIVE" else 48.0
		NoiseManager.emit_noise(global_position, 16.0, db, &"leathery_wing_flap")


# ==============================================================================
# FSM STATE IMPLEMENTATIONS
# ==============================================================================

func _state_circling_roof(delta: float) -> void:
	# Patrol circular path around roof perimeter [-12 to 12, -8 to 8]
	var t := state_timer * 0.4
	var target := Vector3(cos(t) * 11.0, flight_altitude, sin(t) * 7.0)
	velocity = (target - global_position).normalized() * walk_speed
	move_and_slide()

	# Check for blood trails
	var blood_scent := poll_scent_trail([&"blood"])
	if not blood_scent.is_empty():
		target_investigate_pos = blood_scent["position"]
		change_state(&"TRACKING_SCENT")
		return

	# Check direct line of sight to player (e.g. if Jude is on rooftop)
	if has_line_of_sight_to_player():
		change_state(&"CHASE_DIVE")


func _state_tracking_scent(delta: float) -> void:
	# Follow scent gradient downward
	var gradient := ScentManager.get_scent_trail_gradient(global_position, 16.0, &"blood")
	if gradient != Vector3.ZERO:
		velocity = velocity.move_toward(gradient * walk_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
	move_and_slide()

	# Check for jalousie windows between exterior and prey
	if _target_window == null:
		_target_window = _find_nearest_window(global_position, 4.0)
		if _target_window:
			change_state(&"WINDOW_BREACH")
			return

	if has_line_of_sight_to_player():
		change_state(&"CHASE_DIVE")
	elif state_timer > 12.0:
		change_state(&"CIRCLING_ROOF")


func _state_window_breach(delta: float) -> void:
	if not _target_window or _target_window.broken_slats >= _target_window.total_slats:
		change_state(&"CHASE_DIVE")
		return

	# Check if window sill is warded with salt/garlic
	if _target_window.is_salted or _target_window.is_garlic_rubbed:
		change_state(&"FLEE_WARD")
		return

	# Dive directly into the window frame
	var dir := (_target_window.global_position - global_position).normalized()
	velocity = dir * swoop_speed
	move_and_slide()

	if global_position.distance_to(_target_window.global_position) < 1.8:
		# Smash through window
		_target_window.smash_window(&"manananggal")
		_target_window = null
		change_state(&"CHASE_DIVE")


func _state_chase_dive(delta: float) -> void:
	if not player_ref:
		_find_player()
		return

	# If player is in garlic/lana mask zone, repel immediately
	if is_in_repellent_zone():
		change_state(&"FLEE_WARD")
		return

	var target := player_ref.global_position + Vector3(0, 1.2, 0)
	var dir := (target - global_position).normalized()
	velocity = velocity.move_toward(dir * chase_speed, acceleration * 1.5 * delta)
	move_and_slide()

	# Melee claw strike
	if global_position.distance_to(target) < 1.9:
		_perform_swoop_attack()


func _state_flee_ward(delta: float) -> void:
	# Retreat upward toward high open sky
	var flee_dir := (Vector3(0, flight_altitude + 4.0, 0) - global_position).normalized()
	velocity = velocity.move_toward(flee_dir * swoop_speed, acceleration * delta)
	move_and_slide()

	if state_timer > 6.0:
		change_state(&"CIRCLING_ROOF")


func _perform_swoop_attack() -> void:
	if not player_ref:
		return
	
	var attr := player_ref.get_node_or_null("SurvivalAttributes") as SurvivalAttributes
	if attr:
		attr.start_bleeding(0.8) # Inflicts severe bleed wound
		attr.add_panic(35.0)     # Massive panic spike

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.player_damaged.emit(30.0, &"manananggal_talons")
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 18.0, 85.0, &"flesh_tear")

	# Swoop up and circle after striking
	change_state(&"CIRCLING_ROOF")


func _process_burning_fall(delta: float) -> void:
	# Crashes down to ground in flames
	velocity.y -= 14.0 * delta
	move_and_slide()
	if is_on_floor():
		set_physics_process(false)


func _on_torso_salted(progress: float) -> void:
	if progress >= 1.0:
		_is_burning = true
		change_state(&"BURNING_DEATH")
		var bus := get_node_or_null("/root/EventBus")
		if bus:
			bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 30.0, 95.0, &"manananggal_death_scream")
	else:
		# Sizzles and recoils in flight
		change_state(&"FLEE_WARD")


func _find_nearest_window(pos: Vector3, search_radius: float) -> JalousieWindow:
	for win in get_tree().get_nodes_in_group("jalousie_windows"):
		var jw := win as JalousieWindow
		if jw and jw.global_position.distance_to(pos) <= search_radius:
			return jw
	return null
