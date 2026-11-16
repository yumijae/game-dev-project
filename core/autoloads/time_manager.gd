extends Node
## TimeManager (autoload) - the night clock, 11:45 PM to 6:00 AM.
##
## 11:45 PM - 11:59 PM is the quiet setup window. At 12:00 AM `midnight_started`
## reboots the first robot, and they get faster on every hour after that until
## rescue arrives (6:00 AM, or 3:30 AM once the rooftop SOS is sent).

const START_HOUR: int = 23
const START_MINUTE: int = 45
## Elapsed in-game minutes since 11:45 PM for each milestone.
const MIDNIGHT_ELAPSED: int = 15
const SOS_RESCUE_ELAPSED: int = 225
const DAWN_ELAPSED: int = 375
## Rescue can never arrive sooner than this many game minutes after the SOS.
const SOS_MINIMUM_WAIT: int = 20
const MAX_AGGRESSION: int = 6

## Real seconds per in-game minute before midnight (15 minutes = 2 real minutes).
@export var pre_midnight_seconds_per_minute: float = 8.0
## Real seconds per in-game minute after midnight (6 hours = 24 real minutes).
@export var night_seconds_per_minute: float = 4.0

var is_running: bool = false
var elapsed_minutes: int = 0
var aggression_level: int = 0
var rescue_elapsed: int = DAWN_ELAPSED
var is_sos_sent: bool = false

var _accumulator: float = 0.0
var _midnight_signaled: bool = false
var _rescue_signaled: bool = false


func _ready() -> void:
	reset()


func _process(delta: float) -> void:
	if not is_running or _rescue_signaled:
		return
	_accumulator += delta
	var step: float = _seconds_per_minute()
	while _accumulator >= step and not _rescue_signaled:
		_accumulator -= step
		_advance_minute()
		step = _seconds_per_minute()


## Back to 11:45 PM with everything dormant. Does not start the clock.
func reset() -> void:
	is_running = false
	elapsed_minutes = 0
	aggression_level = 0
	rescue_elapsed = DAWN_ELAPSED
	is_sos_sent = false
	_accumulator = 0.0
	_midnight_signaled = false
	_rescue_signaled = false


func start() -> void:
	is_running = true
	_emit_time()


func stop() -> void:
	is_running = false


func get_hour() -> int:
	return hour_of(elapsed_minutes)


func get_minute() -> int:
	return minute_of(elapsed_minutes)


static func hour_of(elapsed: int) -> int:
	return ((START_HOUR * 60 + START_MINUTE + elapsed) / 60) % 24


static func minute_of(elapsed: int) -> int:
	return (START_HOUR * 60 + START_MINUTE + elapsed) % 60


## Minutes since 11:45 PM for a wall-clock time on this night.
static func elapsed_from_clock(hour: int, minute: int) -> int:
	var total: int = hour * 60 + minute
	var start: int = START_HOUR * 60 + START_MINUTE
	if total < start:
		total += 24 * 60
	return total - start


static func format_clock(hour: int, minute: int) -> String:
	var display: int = hour % 12
	if display == 0:
		display = 12
	return "%d:%02d %s" % [display, minute, "AM" if hour < 12 else "PM"]


func get_formatted_time() -> String:
	return format_clock(get_hour(), get_minute())


func get_rescue_time_text() -> String:
	return format_clock(hour_of(rescue_elapsed), minute_of(rescue_elapsed))


## 0.0 at 11:45 PM, 1.0 when rescue arrives.
func get_progress() -> float:
	return clampf(float(elapsed_minutes) / float(maxi(rescue_elapsed, 1)), 0.0, 1.0)


func is_night_active() -> bool:
	return _midnight_signaled and not _rescue_signaled


func has_rescue_arrived() -> bool:
	return _rescue_signaled


## 1.0 before midnight, +18% per aggression level (2.08x at 5:00 AM).
func get_aggression_multiplier() -> float:
	return 1.0 + 0.18 * float(aggression_level)


## Called by EscapeManager when the SOS text goes out: rescue moves up to
## 3:30 AM (or a little after "now" if it is already later than that).
func complete_rooftop_sos() -> void:
	if is_sos_sent:
		return
	is_sos_sent = true
	var target: int = maxi(SOS_RESCUE_ELAPSED, elapsed_minutes + SOS_MINIMUM_WAIT)
	if target < rescue_elapsed:
		rescue_elapsed = target
		EventBus.rescue_time_changed.emit(hour_of(rescue_elapsed), minute_of(rescue_elapsed))


## Debug / scripted jump forward. Fires every milestone that gets crossed.
func skip_to(hour: int, minute: int) -> void:
	var target: int = mini(elapsed_from_clock(hour, minute), rescue_elapsed)
	while elapsed_minutes < target and not _rescue_signaled:
		_advance_minute()


func _seconds_per_minute() -> float:
	var seconds: float = pre_midnight_seconds_per_minute if elapsed_minutes < MIDNIGHT_ELAPSED \
		else night_seconds_per_minute
	return maxf(seconds, 0.05)


func _advance_minute() -> void:
	elapsed_minutes += 1
	_emit_time()
	if not _midnight_signaled and elapsed_minutes >= MIDNIGHT_ELAPSED:
		_midnight_signaled = true
		EventBus.midnight_started.emit()
	if _midnight_signaled and get_minute() == 0:
		_strike_hour()
	if elapsed_minutes >= rescue_elapsed:
		_rescue_signaled = true
		is_running = false
		EventBus.rescue_arrived.emit()


func _strike_hour() -> void:
	var hour: int = get_hour()
	# 12 AM -> level 1, 1 AM -> 2 ... 5 AM -> 6.
	var level: int = clampi(hour + 1, 1, MAX_AGGRESSION)
	if level != aggression_level:
		aggression_level = level
		EventBus.aggression_escalated.emit(aggression_level)
	EventBus.hour_struck.emit(hour, aggression_level)


func _emit_time() -> void:
	EventBus.time_advanced.emit(get_hour(), get_minute(), get_formatted_time(), get_progress())
