extends Node3D
## Roll-up shop shutter on the ground-floor stalls. Look at it and press E to
## roll it up (or down). The node sits at the top edge of the shutter.

signal toggled(is_open: bool)

@export var start_open := false
@export var locked := false
@export var roll_time := 1.2

var is_open := false
var _tween: Tween

@onready var _roll: Node3D = $Body/Roll
@onready var _shape: CollisionShape3D = $Body/CollisionShape3D


func _ready() -> void:
	is_open = start_open
	_apply(1.0 if is_open else 0.0)


func get_prompt() -> String:
	if locked:
		return "Locked"
	return "[E] Pull shutter down" if is_open else "[E] Roll shutter up"


func interact(_player: Node) -> void:
	if locked or (_tween and _tween.is_running()):
		return
	is_open = not is_open
	_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_tween.tween_method(_apply, 0.0 if is_open else 1.0, 1.0 if is_open else 0.0, roll_time)
	toggled.emit(is_open)


func _apply(amount: float) -> void:
	_roll.scale.y = lerp(1.0, 0.06, amount)
	_shape.disabled = amount > 0.5
