extends Node
## Manages the night clock for "Huling Kampana" from 11:45 PM to 5:30 AM.
## Autoload: TimeManager
## Handles minute increments, bell tolling events, 3:30 AM SOS window, and 5:30 AM Dawn.

# Starting time: 11:45 PM
const START_HOUR := 23
const START_MINUTE := 45

# End time: 05:30 AM (Dawn)
const END_HOUR := 5
const END_MINUTE := 30

# Rooftop SOS transmission window: 03:30 AM
const SOS_HOUR := 3
const SOS_MINUTE := 30

# Total in-game minutes from 23:45 to 05:30 = 15 + (5 * 60) + 30 = 345 minutes.
const TOTAL_MINUTES := 345

## How many real-time seconds represent 1 in-game minute.
## Default: 2.0s per minute (~11.5 minutes total real-time playthrough).
@export var real_seconds_per_game_minute: float = 2.0

## Whether the clock is actively ticking.
@export var is_running: bool = true

var current_hour: int = START_HOUR
var current_minute: int = START_MINUTE
var elapsed_game_minutes: int = 0
var _accumulator: float = 0.0

var _last_signaled_hour: int = -1
var _sos_signaled: bool = false
var _dawn_signaled: bool = false
var _event_bus: Node = null


func _get_event_bus() -> Node:
	if not _event_bus and is_inside_tree():
		_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus


func _ready() -> void:
	reset_clock()


func _process(delta: float) -> void:
	if not is_running or _dawn_signaled:
		return

	_accumulator += delta
	while _accumulator >= real_seconds_per_game_minute:
		_accumulator -= real_seconds_per_game_minute
		_advance_one_minute()


## Resets the clock to 11:45 PM.
func reset_clock() -> void:
	current_hour = START_HOUR
	current_minute = START_MINUTE
	elapsed_game_minutes = 0
	_accumulator = 0.0
	_last_signaled_hour = -1
	_sos_signaled = false
	_dawn_signaled = false
	_emit_time_update()


## Manually advance or set clock for testing/scripted events.
func set_time(hour: int, minute: int) -> void:
	current_hour = hour
	current_minute = minute
	
	# Recalculate elapsed minutes
	if hour >= START_HOUR:
		elapsed_game_minutes = (hour - START_HOUR) * 60 + (minute - START_MINUTE)
	else:
		var pre_midnight := (24 - START_HOUR) * 60 - START_MINUTE # 15 mins
		elapsed_game_minutes = pre_midnight + (hour * 60) + minute
	
	elapsed_game_minutes = clampi(elapsed_game_minutes, 0, TOTAL_MINUTES)
	_emit_time_update()
	_check_milestones()


func start_clock() -> void:
	is_running = true


func stop_clock() -> void:
	is_running = false


## Returns formatted string like "11:45 PM" or "02:15 AM".
func get_formatted_time() -> String:
	var display_hour := current_hour % 12
	if display_hour == 0:
		display_hour = 12
	var period := "AM" if (current_hour < 12 or current_hour == 24) else "PM"
	return "%02d:%02d %s" % [display_hour, current_minute, period]


## Normalized value from 0.0 (11:45 PM) to 1.0 (5:30 AM).
func get_progress() -> float:
	return clampf(float(elapsed_game_minutes) / float(TOTAL_MINUTES), 0.0, 1.0)


func is_past_sos_window() -> bool:
	return _sos_signaled


func _advance_one_minute() -> void:
	elapsed_game_minutes += 1
	current_minute += 1
	if current_minute >= 60:
		current_minute = 0
		current_hour = (current_hour + 1) % 24

	_emit_time_update()
	_check_milestones()


func _emit_time_update() -> void:
	var bus := _get_event_bus()
	if bus:
		bus.time_advanced.emit(current_hour, current_minute, get_formatted_time(), get_progress())


func _check_milestones() -> void:
	var bus := _get_event_bus()
	if not bus:
		return

	# Hourly bell tolling at :00
	if current_minute == 0 and current_hour != _last_signaled_hour:
		_last_signaled_hour = current_hour
		var bell_count := current_hour % 12
		if bell_count == 0:
			bell_count = 12
		bus.hourly_bell_tolled.emit(current_hour, bell_count)

	# 03:30 AM Rooftop SOS Window
	if current_hour == SOS_HOUR and current_minute == SOS_MINUTE and not _sos_signaled:
		_sos_signaled = true
		bus.rooftop_sos_window_opened.emit()

	# 05:30 AM Dawn Arrival
	if current_hour == END_HOUR and current_minute == END_MINUTE and not _dawn_signaled:
		_dawn_signaled = true
		is_running = false
		bus.dawn_arrived.emit()
