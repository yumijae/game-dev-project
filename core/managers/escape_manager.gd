class_name EscapeManager
extends Node
## The ways the night ends well.
##
##   1. Dawn Rescue       - survive to 6:00 AM; the morning guard unlocks the
##                          Main Lobby (#1) security gate at (0, 0, 7.8).
##   2. Rooftop SOS       - 45 cumulative seconds at the rooftop antenna
##                          (0, 15.2, 0) with the phone out sends an SOS text
##                          and moves rescue up to 3:30 AM.
##   3. Gate Breach       - Master Gate Key (Cashier #3) plus bolt cutters
##                          (MIT Office #12) or a crowbar (Staff Room #5), and
##                          a loud 20-second breach at the gate.
## In every case the run is won by walking out through the open gate.

const SOS_REQUIRED_SECONDS: float = 45.0
const SOS_RADIUS: float = 3.5
const LAYER_PLAYER: int = 4

const ENDINGS: Dictionary = {
	&"dawn_rescue": {
		"title": "DAWN RESCUE",
		"text": "6:00 AM. The morning guard rolls up the security gate, yawning, and finds you on the lobby floor. The sun is already on the street. Behind you the robots have stopped wherever the daylight found them, as if they had never moved at all.",
	},
	&"rooftop_sos": {
		"title": "ROOFTOP SOS",
		"text": "One bar of signal was enough. At {rescue_time} headlights sweep the street and the gate rattles open hours early. Somewhere upstairs, a motor is still whirring.",
	},
	&"gate_breach": {
		"title": "EARLY GATE BREACH",
		"text": "The padlock turns, the chain gives, and the gate screams up its track. You are through it and running down the street before the echo dies. Behind you, something taps on the glass and asks, politely, for your visitor pass.",
	},
}

var sos_seconds: float = 0.0
var is_sos_sent: bool = false
var is_gate_open: bool = false
var has_won: bool = false
## How the gate came to be open.
var escape_route: StringName = &""

var _player: PlayerController = null
var _gate: RehasGate = null
var _exit_area: Area3D = null
var _last_reported_second: int = -1


func _ready() -> void:
	EventBus.midnight_started.connect(_on_midnight)
	EventBus.rescue_arrived.connect(_on_rescue_arrived)
	EventBus.gate_opened.connect(_on_gate_opened)
	_build_exit_area()
	_set_objective.call_deferred(&"setup", "11:45 PM. The robots finish updating at midnight. Check the cameras (V) and gather supplies while it is quiet.", 0.0)


func _physics_process(delta: float) -> void:
	if has_won:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as PlayerController
		return
	if _gate == null or not is_instance_valid(_gate):
		_gate = get_tree().get_first_node_in_group(&"rehas_gate") as RehasGate
	_update_sos(delta)


## True while Juan stands at the antenna with a live phone raised.
func is_transmitting() -> bool:
	if _player == null or is_sos_sent or _player.is_dead:
		return false
	if not _player.phone.is_phone_out or _player.stats.is_phone_dead():
		return false
	if Campus.floor_from_y(_player.global_position.y) != Campus.ROOF_FLOOR:
		return false
	var flat := Vector2(_player.global_position.x - Campus.ANTENNA_POSITION.x,
		_player.global_position.z - Campus.ANTENNA_POSITION.z)
	return flat.length() <= SOS_RADIUS


func _update_sos(delta: float) -> void:
	if not is_transmitting():
		return
	sos_seconds = minf(sos_seconds + delta, SOS_REQUIRED_SECONDS)
	if int(sos_seconds) != _last_reported_second:
		_last_reported_second = int(sos_seconds)
		EventBus.sos_progress_changed.emit(sos_seconds, SOS_REQUIRED_SECONDS)
		_set_objective(&"sos", "Sending SOS from the rooftop antenna...", sos_seconds / SOS_REQUIRED_SECONDS)
	if sos_seconds >= SOS_REQUIRED_SECONDS:
		is_sos_sent = true
		TimeManager.complete_rooftop_sos()
		EventBus.sos_sent.emit()
		_set_objective(&"rescue", "SOS sent. Rescue reaches the Main Lobby gate at %s. Stay alive."
			% TimeManager.get_rescue_time_text(), 1.0)


func _on_midnight() -> void:
	_set_objective(&"survive", "Midnight. The robots are loose. Survive until the guard comes at 6:00 AM - or find another way out.", 0.0)


## The guard (or the rescuers) open the gate from outside.
func _on_rescue_arrived() -> void:
	var route: StringName = &"rooftop_sos" if TimeManager.is_sos_sent else &"dawn_rescue"
	if _gate != null and not _gate.is_open:
		_gate.open(route)
	elif _gate == null:
		_on_gate_opened(route)


func _on_gate_opened(method: StringName) -> void:
	is_gate_open = true
	if escape_route == &"":
		escape_route = method
	_set_objective(&"exit", "The security gate is open. Get out through the Main Lobby.", 1.0)
	# Already standing in the doorway when it opened.
	if _exit_area != null:
		for body: Node3D in _exit_area.get_overlapping_bodies():
			_on_exit_entered(body)


func _on_exit_entered(body: Node3D) -> void:
	if has_won or not is_gate_open or not (body is PlayerController):
		return
	var player := body as PlayerController
	if player.is_dead:
		return
	has_won = true
	var ending_id: StringName = escape_route
	var ending: Dictionary = ENDINGS.get(ending_id, ENDINGS[&"dawn_rescue"])
	var title: String = ending["title"]
	var text: String = String(ending["text"]).replace("{rescue_time}", TimeManager.get_rescue_time_text())
	EventBus.game_won.emit(ending_id, title, text)


## A trigger volume just outside the entrance doors.
func _build_exit_area() -> void:
	_exit_area = Area3D.new()
	_exit_area.name = "ExitArea"
	_exit_area.collision_layer = 0
	_exit_area.collision_mask = LAYER_PLAYER
	_exit_area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = Vector3(5.0, 2.6, 2.6)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_exit_area.add_child(collider)
	add_child(_exit_area)
	_exit_area.global_position = Vector3(Campus.REHAS_GATE_POSITION.x, 1.3, Campus.Z_MAX + 1.9)
	_exit_area.body_entered.connect(_on_exit_entered)


func _set_objective(objective_id: StringName, text: String, progress: float) -> void:
	EventBus.objective_updated.emit(objective_id, text, progress)
