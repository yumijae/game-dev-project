class_name TiktikStalker
extends AswangBase
## Acoustic stealth predator in "Huling Kampana".
## Features inverted 3D audio falloff (Loud when Far, Whispering when Close),
## ceiling/crawlspace mobility, jalousie proboscis intrusion, and light aversion.

@export_group("Tiktik Acoustic Inversion")
@export var max_trick_distance: float = 28.0
@export var min_whisper_db: float = 18.0
@export var max_echo_db: float = 76.0
@export var call_interval_idle: float = 4.5
@export var call_interval_stalk: float = 2.5

@export_group("Ceiling Locomotion")
@export var ceiling_crawl_height: float = 3.6 # Just below 3.8m ceiling slab
@export var tongue_reach: float = 4.2

var _call_timer: float = 0.0
var _target_window: JalousieWindow = null


func _ready() -> void:
	super._ready()
	aswang_id = &"tiktik"
	change_state(&"CEILING_STALK")


func _physics_process(delta: float) -> void:
	_process_reverse_audio_calls(delta)

	match current_state:
		&"CEILING_STALK":
			_state_ceiling_stalk(delta)
		&"WINDOW_PROBE":
			_state_window_probe(delta)
		&"OVERHEAD_AMBUSH":
			_state_overhead_ambush(delta)
		&"FLEE_TORCH":
			_state_flee_torch(delta)


# ==============================================================================
# INVERTED ACOUSTIC ENGINE (BALIGTAD NA TUNOG)
# ==============================================================================

func _process_reverse_audio_calls(delta: float) -> void:
	_call_timer += delta
	var interval := call_interval_stalk if current_state == &"OVERHEAD_AMBUSH" else call_interval_idle

	if _call_timer >= interval:
		_call_timer = 0.0
		_emit_inverted_tiktik_sound()


func _emit_inverted_tiktik_sound() -> void:
	var dist := 15.0
	if player_ref:
		dist = global_position.distance_to(player_ref.global_position)

	# Folklore rule:
	# Far away (dist >= max_trick_distance) -> Very Loud (max_echo_db)
	# Close to victim (dist <= 2.0m) -> Faint whisper (min_whisper_db)
	var t := clampf(dist / max_trick_distance, 0.0, 1.0)
	var perceived_db := lerpf(min_whisper_db, max_echo_db, t)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.tiktik_call_emitted.emit(global_position, perceived_db, dist)
		# Also broadcast to NoiseManager with audible radius
		var radius := lerpf(8.0, 26.0, t)
		NoiseManager.emit_noise(global_position, radius, perceived_db, &"tiktik_call")


# ==============================================================================
# FSM STATE IMPLEMENTATIONS
# ==============================================================================

func _state_ceiling_stalk(delta: float) -> void:
	if not player_ref:
		_find_player()
		return

	# Crawl along the ceiling directly above or near the player's corridor/room
	var target_pos := Vector3(player_ref.global_position.x, player_ref.global_position.y + ceiling_crawl_height, player_ref.global_position.z)
	var dir := (target_pos - global_position).normalized()
	velocity = velocity.move_toward(dir * walk_speed, acceleration * delta)
	move_and_slide()

	# Check torch beam shining directly onto Tiktik
	if _is_torch_pointed_at_me():
		change_state(&"FLEE_TORCH")
		return

	# If hovering within 3m above Jude, initiate tongue drop
	var horizontal_dist := Vector2(global_position.x - player_ref.global_position.x, global_position.z - player_ref.global_position.z).length()
	if horizontal_dist < 2.2:
		change_state(&"OVERHEAD_AMBUSH")
		return

	# Check for nearby jalousie windows to probe
	if _target_window == null and state_timer > 6.0:
		_target_window = _find_probeable_window(global_position, 5.0)
		if _target_window:
			change_state(&"WINDOW_PROBE")


func _state_window_probe(delta: float) -> void:
	if not _target_window or not _target_window.can_tiktik_probe():
		change_state(&"CEILING_STALK")
		return

	# Scent / ward check: If salted, burn tongue
	if _target_window.is_salted or _target_window.is_garlic_rubbed:
		var bus := get_node_or_null("/root/EventBus")
		if bus:
			bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 15.0, 75.0, &"tiktik_screech_pain")
		change_state(&"FLEE_TORCH")
		return

	# Crawl toward window sill
	var target := _target_window.global_position + Vector3(0, 0.8, 0)
	velocity = (target - global_position).normalized() * walk_speed
	move_and_slide()

	if global_position.distance_to(target) < 1.2:
		# Probe into room: If Jude is inside within tongue reach, strike!
		if player_ref and global_position.distance_to(player_ref.global_position) <= tongue_reach:
			_strike_with_proboscis()
		elif state_timer > 8.0:
			change_state(&"CEILING_STALK")


func _state_overhead_ambush(delta: float) -> void:
	# Hover quietly directly above player
	velocity = Vector3.ZERO
	move_and_slide()

	if _is_torch_pointed_at_me():
		change_state(&"FLEE_TORCH")
		return

	# Drop long proboscis to drain blood
	if state_timer >= 1.5:
		_strike_with_proboscis()
		change_state(&"CEILING_STALK")


func _state_flee_torch(delta: float) -> void:
	# Scramble rapidly away from the player into ceiling rafters or stairwells
	if player_ref:
		var away_dir := (global_position - player_ref.global_position).normalized()
		away_dir.y = 0.2
		velocity = away_dir.normalized() * chase_speed
		move_and_slide()

	if state_timer > 4.5:
		change_state(&"CEILING_STALK")


func _strike_with_proboscis() -> void:
	if not player_ref:
		return

	var attr := player_ref.get_node_or_null("SurvivalAttributes") as SurvivalAttributes
	if attr:
		attr.start_bleeding(0.5)
		attr.add_panic(25.0)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.player_damaged.emit(18.0, &"tiktik_proboscis")
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 10.0, 50.0, &"flesh_puncture")


func _is_torch_pointed_at_me() -> bool:
	if not player_ref:
		return false
	var attr := player_ref.get_node_or_null("SurvivalAttributes") as SurvivalAttributes
	if not attr or not attr.is_torch_active or attr.is_phone_dead:
		return false

	var cam := player_ref.get_node_or_null("Head/Camera3D") as Camera3D
	if not cam:
		return false

	var to_tiktik := (global_position - cam.global_position).normalized()
	var cam_forward := -cam.global_transform.basis.z
	var angle := rad_to_deg(cam_forward.angle_to(to_tiktik))
	return angle < 24.0 and cam.global_position.distance_to(global_position) < 12.0


func _find_probeable_window(pos: Vector3, search_radius: float) -> JalousieWindow:
	for win in get_tree().get_nodes_in_group("jalousie_windows"):
		var jw := win as JalousieWindow
		if jw and jw.can_tiktik_probe() and jw.global_position.distance_to(pos) <= search_radius:
			return jw
	return null
