class_name JalousieWindow
extends Node3D
## Jalousie louvered window component for classroom exterior walls.
## Features breakable glass slats, crank opening, and salt/garlic windowsill warding.

signal slat_broken(remaining_slats: int)
signal window_smashed(attacker: StringName)
signal window_warded(substance: StringName)

@export var total_slats: int = 8
@export var broken_slats: int = 0
@export var is_cranked_open: bool = false
@export var is_salted: bool = false
@export var is_garlic_rubbed: bool = false

# Glass hazard on the ground
@export var glass_hazard_radius: float = 1.6


func get_interaction_prompt() -> String:
	if broken_slats >= total_slats:
		return "Shattered Jalousie Window"
	return "[E] Crank Window Closed" if is_cranked_open else "[E] Crank Window Open"


func interact(_actor: Node) -> void:
	if broken_slats >= total_slats:
		return
	is_cranked_open = not is_cranked_open
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 6.0, 32.0, &"jalousie_crank")


## Breaks one or more glass slats (from Tiktik intrusion or rock impact).
func break_slat(count: int = 1) -> void:
	broken_slats = clampi(broken_slats + count, 0, total_slats)
	slat_broken.emit(total_slats - broken_slats)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 16.0, 75.0, &"glass_shatter")
		bus.jalousie_slat_broken.emit(self, total_slats - broken_slats)


## Smashes the entire window frame (Manananggal body dive).
func smash_window(attacker_type: StringName) -> void:
	broken_slats = total_slats
	window_smashed.emit(attacker_type)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 24.0, 92.0, &"window_crash")


## Checks if Tiktik's long proboscis/tongue can reach through.
func can_tiktik_probe() -> bool:
	return is_cranked_open or broken_slats >= 1


## Wards the window sill with salt (*Asin*) or garlic (*Ahos*).
func apply_ward(substance: StringName) -> void:
	if substance == &"asin":
		is_salted = true
	elif substance == &"ahos":
		is_garlic_rubbed = true
	window_warded.emit(substance)
