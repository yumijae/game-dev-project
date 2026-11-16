class_name NoiseEmitter
extends Node3D
## Attachable component that broadcasts noise events to NoiseManager and EventBus.
## Can be attached to the Player (footsteps, landing), Doors, Barricades, or Glass.

@export var default_radius: float = 8.0
@export var default_loudness_db: float = 50.0
@export var default_noise_type: StringName = &"generic"


## Emits a sound at this node's global transform.
func emit_sound(radius: float = -1.0, loudness_db: float = -1.0, noise_type: StringName = &"") -> void:
	var r := default_radius if radius < 0.0 else radius
	var db := default_loudness_db if loudness_db < 0.0 else loudness_db
	var nt := default_noise_type if noise_type == &"" else noise_type

	NoiseManager.emit_noise(global_position, r, db, nt)
