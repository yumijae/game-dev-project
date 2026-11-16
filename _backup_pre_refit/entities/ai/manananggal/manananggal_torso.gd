class_name ManananggalTorso
extends Node3D
## The hidden lower half of the Manananggal.
## Stationary, hidden in dark school rooms (4F Pantry, 3F Faculty, 2F Server Room, 1F Records).
## Emits a rotting flesh odor. Vulnerable to Asin (Salt) and Ahos (Garlic).

signal torso_purified()
signal salt_applied(current_progress: float)

@export var room_location: String = "4F Pantry"
@export var purification_progress: float = 0.0 # 0.0 to 1.0 (1.0 = fully destroyed)
@export var scent_interval: float = 3.0

var is_destroyed: bool = false
var _scent_timer: float = 0.0


func _ready() -> void:
	add_to_group("manananggal_torso")
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.manananggal_torso_discovered.emit(self)


func _process(delta: float) -> void:
	if is_destroyed:
		return

	# Emits rotting flesh odor to ScentManager
	_scent_timer += delta
	if _scent_timer >= scent_interval:
		_scent_timer = 0.0
		ScentManager.drop_scent(global_position, &"flesh", 0.9, 0.02)


func get_interaction_prompt() -> String:
	if is_destroyed:
		return "Severed Lower Torso (Burned to Ash)"
	return "[E] Smear Asin (Salt) & Ahos on Severed Waist"


func interact(actor: Node) -> void:
	if is_destroyed:
		return

	# Check if Jude has Asin in inventory or apply directly
	apply_salt_damage(0.35)


## Inflicts salt/garlic burning on the open severed waist.
func apply_salt_damage(amount: float) -> void:
	if is_destroyed:
		return

	purification_progress = clampf(purification_progress + amount, 0.0, 1.0)
	salt_applied.emit(purification_progress)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.manananggal_torso_salted.emit(purification_progress)
		# Shriek of sizzling flesh
		NoiseManager.emit_noise(global_position, 18.0, 80.0, &"flesh_sizzle_screech")

	if purification_progress >= 1.0:
		is_destroyed = true
		torso_purified.emit()
