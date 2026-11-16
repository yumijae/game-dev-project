extends Node3D
## Hinged classroom door. The node sits on the hinge; look at the door and
## press E to open/close. Set up automatically by sti_building_import.gd.

signal toggled(is_open: bool)

@export var closed_yaw := 0.0
@export var open_yaw := 0.0
@export var start_open := false
@export var locked := false
@export var swing_time := 0.35

var is_open := false
var _tween: Tween


func _ready() -> void:
	is_open = start_open
	rotation.y = open_yaw if is_open else closed_yaw


func get_prompt() -> String:
	if locked:
		return "Locked"
	return "[E] Close door" if is_open else "[E] Open door"


func interact(_player: Node) -> void:
	if locked:
		return
	is_open = not is_open
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation:y", open_yaw if is_open else closed_yaw, swing_time)
	toggled.emit(is_open)
