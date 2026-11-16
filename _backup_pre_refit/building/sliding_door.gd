extends Node3D
## Automatic sliding glass doors (main entrance). Two leaves slide apart when a
## character (player or AI CharacterBody3D) enters the Sensor area, and close
## again shortly after everyone has left it.

signal toggled(is_open: bool)

@export var slide_distance := 0.9
@export var open_time := 0.45
@export var close_delay := 0.8
@export var locked := false

var is_open := false
var _inside := 0
var _close_timer := 0.0
var _closed_left := 0.0
var _closed_right := 0.0
var _tween: Tween

@onready var _left: Node3D = $LeftLeaf
@onready var _right: Node3D = $RightLeaf
@onready var _sensor: Area3D = $Sensor


func _ready() -> void:
	_closed_left = _left.position.x
	_closed_right = _right.position.x
	_sensor.body_entered.connect(_on_body_entered)
	_sensor.body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	if _close_timer > 0.0:
		_close_timer -= delta
		if _close_timer <= 0.0 and _inside == 0:
			_move(false)


func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		_inside += 1
		_close_timer = 0.0
		if not locked:
			_move(true)


func _on_body_exited(body: Node) -> void:
	if body is CharacterBody3D:
		_inside = max(0, _inside - 1)
		if _inside == 0:
			_close_timer = close_delay


func _move(open: bool) -> void:
	if open == is_open:
		return
	is_open = open
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_left, "position:x", _closed_left - (slide_distance if open else 0.0), open_time)
	_tween.tween_property(_right, "position:x", _closed_right + (slide_distance if open else 0.0), open_time)
	toggled.emit(open)
