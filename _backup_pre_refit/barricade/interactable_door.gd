class_name InteractableDoor
extends Node3D
## Modular door component for STI College Kalibo classroom and office doors.
## Supports locking, LAN-cable handle ties, bottom-gap sealing against the Balbal,
## and physical breach destruction.

signal door_state_changed(is_open: bool)
signal door_damaged(current_health: float, max_health: float)
signal door_breached(attacker_type: StringName)

@export_group("Door State")
@export var door_name: String = "Classroom Door"
@export var is_open: bool = false
@export var is_locked: bool = false
@export var required_key_id: StringName = &""

@export_group("Barricade Upgrades")
## Whether the handle is tied with a Cat6 LAN cable from 2F computer labs
@export var handle_tied_with_lan: bool = false
## Whether the bottom 3-inch gap is sealed with towels/cloth soaked in salt or garlic
@export var bottom_gap_sealed: bool = false
@export var bottom_gap_substance: StringName = &"" # &"asin", &"ahos", &"cloth"

@export_group("Durability")
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var is_destroyed: bool = false

@export_group("Animation")
@export var closed_yaw: float = 0.0
@export var open_yaw: float = 1.5708 # 90 degrees
@export var swing_speed: float = 0.35

var _tween: Tween


func _ready() -> void:
	rotation.y = open_yaw if is_open else closed_yaw
	current_health = max_health


func get_interaction_prompt() -> String:
	if is_destroyed:
		return "Door Frame (Shattered)"
	if is_locked:
		return "[E] Door is Locked"
	if handle_tied_with_lan:
		return "[E] Tied with LAN Cable"
	return "[E] Close Door" if is_open else "[E] Open Door"


func interact(_actor: Node) -> void:
	if is_destroyed or is_locked or handle_tied_with_lan:
		var bus := get_node_or_null("/root/EventBus")
		if bus:
			bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 8.0, 52.0, &"door_rattle")
		return

	set_open(not is_open)


func set_open(open_state: bool) -> void:
	if is_locked or handle_tied_with_lan or is_destroyed:
		return

	is_open = open_state
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation:y", open_yaw if is_open else closed_yaw, swing_speed)

	door_state_changed.emit(is_open)
	
	# Acoustic emission
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		var db := 60.0 if not is_open else 45.0
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 10.0, db, &"door_swing")


## Inflicts physical damage from an attacking Aswang (Balbal / Manananggal).
## Returns true if the door was breached and destroyed.
func apply_breach_damage(damage: float, attacker_type: StringName) -> bool:
	if is_destroyed or is_open:
		return false

	current_health = maxf(0.0, current_health - damage)
	door_damaged.emit(current_health, max_health)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 14.0, 72.0, &"barricade_bang")
		bus.door_breach_progress.emit(self, current_health, attacker_type)

	if current_health <= 0.0:
		is_destroyed = true
		is_open = true
		is_locked = false
		handle_tied_with_lan = false
		if _tween:
			_tween.kill()
		_tween = create_tween().set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "rotation:y", open_yaw, 0.15)
		
		door_breached.emit(attacker_type)
		if bus:
			bus.door_breached.emit(self, attacker_type)
			bus.noise_emitted.emit(global_position, NoiseManager.get_floor_index(global_position.y), 20.0, 85.0, &"door_slam")
		return true

	return false


## Checks if the Balbal in Black Dog form can slip under the bottom door gap.
func can_black_dog_slip_through() -> bool:
	if is_open or is_destroyed:
		return true
	# Blocked if Jude has sealed the gap with cloth or salted/garlic-soaked towels
	return not bottom_gap_sealed


## Fastens door handle with LAN cables gathered from 2F Computer Labs.
func tie_handle_with_lan_cable() -> bool:
	if is_open or is_destroyed:
		return false
	handle_tied_with_lan = true
	max_health += 80.0
	current_health += 80.0
	return true


## Seals bottom 3-inch gap with cloth or folk repellent.
func seal_bottom_gap(substance: StringName = &"asin") -> void:
	bottom_gap_sealed = true
	bottom_gap_substance = substance
