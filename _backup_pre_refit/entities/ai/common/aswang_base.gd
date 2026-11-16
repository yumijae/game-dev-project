class_name AswangBase
extends CharacterBody3D
## Base Finite State Machine & Perception system for Philippine Aswangs in "Huling Kampana".
## Hooks into NoiseManager, ScentManager, InteractableDoor, and JalousieWindow.

signal state_changed(old_state: StringName, new_state: StringName)

@export_group("AI Identity")
@export var aswang_id: StringName = &"generic_aswang"
@export var walk_speed: float = 2.8
@export var chase_speed: float = 5.2
@export var acceleration: float = 8.0

@export_group("Perception Thresholds")
@export var hearing_threshold_db: float = 18.0
@export var scent_detection_radius: float = 14.0
@export var vision_fov_degrees: float = 110.0
@export var vision_distance: float = 16.0

# Current State & Target
var current_state: StringName = &"IDLE"
var state_timer: float = 0.0
var target_investigate_pos: Vector3 = Vector3.ZERO
var player_ref: CharacterBody3D = null

# Navigation & Raycasting
@onready var los_ray: RayCast3D = RayCast3D.new()


func _ready() -> void:
	add_child(los_ray)
	los_ray.collision_mask = 1 | 4 # World + Player
	los_ray.enabled = true
	_find_player()


func _process(delta: float) -> void:
	state_timer += delta


## Changes FSM state and emits EventBus signal.
func change_state(new_state: StringName) -> void:
	if current_state == new_state:
		return
	var old := current_state
	current_state = new_state
	state_timer = 0.0
	state_changed.emit(old, new_state)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.aswang_state_changed.emit(aswang_id, old, new_state)


## Senses recent noises across campus via NoiseManager.
func poll_audible_sounds() -> Array[Dictionary]:
	return NoiseManager.get_audible_noises_for(global_position, hearing_threshold_db)


## Senses blood and sweat trails via ScentManager.
func poll_scent_trail(target_types: Array[StringName] = [&"blood", &"sweat"]) -> Dictionary:
	return ScentManager.get_strongest_scent_near(global_position, scent_detection_radius, target_types)


## Returns true if current position is contaminated with repellent (Ahos, Suka, Lana).
func is_in_repellent_zone() -> bool:
	return ScentManager.is_in_mask_zone(global_position)


## Checks direct line-of-sight to Jude.
func has_line_of_sight_to_player() -> bool:
	if not player_ref:
		_find_player()
		if not player_ref:
			return false

	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	if dist > vision_distance:
		return false

	# FOV check
	var forward := -global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(to_player))
	if angle > (vision_fov_degrees * 0.5):
		return false

	# Raycast obstruction check
	los_ray.global_position = global_position + Vector3(0, 1.4, 0)
	los_ray.target_position = los_ray.to_local(player_ref.global_position + Vector3(0, 1.2, 0))
	los_ray.force_raycast_update()

	if los_ray.is_colliding():
		var col := los_ray.get_collider()
		return col == player_ref or col.get_parent() == player_ref

	return false


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		player_ref = players[0] as CharacterBody3D
	else:
		player_ref = get_node_or_null("../Player") as CharacterBody3D
