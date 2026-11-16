class_name ScentEmitter
extends Node3D
## Attachable component that drops scent markers into ScentManager.
## Attach to Jude (emitting blood when wounded, or sweat when sprinting) or bait.

@export var scent_type: StringName = &"blood"
@export var initial_intensity: float = 1.0
@export var decay_rate: float = 0.03
@export var drop_interval: float = 1.5
@export var is_active: bool = false

var _timer: float = 0.0


func _process(delta: float) -> void:
	if not is_active:
		return

	_timer += delta
	if _timer >= drop_interval:
		_timer = 0.0
		drop_scent_now()


func drop_scent_now(intensity_override: float = -1.0) -> void:
	var intensity := initial_intensity if intensity_override < 0.0 else intensity_override
	ScentManager.drop_scent(global_position, scent_type, intensity, decay_rate)
