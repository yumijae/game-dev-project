class_name PlayerStats
extends Node
## Juan Dela Cruz's five survival attributes:
##   1. Stamina  2. Panic  3. Footwear  4. Bleeding  5. Phone battery
## The controller feeds it context (darkness, hiding); everything else reacts
## to the signals it sends through EventBus.

enum Footwear { SCHOOL_SHOES, SOCKS, BAREFOOT }
enum PanicTier { GROUNDED, UNEASY, RATTLED, TERROR }

const MAX_VALUE: float = 100.0
## The charger in Room 402 died with the building's power at 11:44, long
## before the phone was full.
const STARTING_BATTERY: float = 35.0

const HEAVY_BREATHING_THRESHOLD: float = 30.0
const HEAVY_BREATHING_RADIUS: float = 4.0
const HEAVY_BREATHING_INTERVAL: float = 2.0
const EXHAUSTION_RECOVERY: float = 25.0

const SHAKY_HANDS_THRESHOLD: float = 70.0
const SHAKY_TIME_MULTIPLIER: float = 2.0
const SHAKY_FUMBLE_CHANCE: float = 0.35
## Panic values that other systems react to (tiers, hallucinations, sweat).
const PANIC_THRESHOLDS: Array[int] = [30, 35, 60, 70, 80, 85, 95]
const TIER_LIMITS: Array[float] = [30.0, 60.0, 85.0]
const TIER_NAMES: Array[String] = ["Grounded", "Uneasy", "Rattled", "Terror"]

## Pitch dark is most of the building: at 0.3 a player sneaking with the
## light off hit shaky hands in four minutes and gasping in five, with no way
## back short of turning the light on. Now about ten minutes to 70.
const PANIC_DARKNESS_RATE: float = 0.12
## Shut in a hiding spot with nothing close: the breathing slows.
const PANIC_HIDING_RECOVERY: float = 0.5
const PANIC_BLEEDING_RATE: float = 0.4
const PANIC_THREAT_RATE: float = 7.0
const PANIC_THREAT_RADIUS: float = 9.0
const PANIC_RECOVERY_RATE: float = 0.8
const PANIC_MIRROR_SPIKE: float = 15.0
const MIRROR_COOLDOWN: float = 10.0

## Footstep radius multiplier on floor tiles.
const FOOTWEAR_NOISE: Dictionary = {
	Footwear.SCHOOL_SHOES: 1.45,
	Footwear.SOCKS: 0.55,
	Footwear.BAREFOOT: 0.30,
}
const FOOTWEAR_NAMES: Dictionary = {
	Footwear.SCHOOL_SHOES: "School shoes",
	Footwear.SOCKS: "Socks",
	Footwear.BAREFOOT: "Barefoot",
}
const BLEEDING_SPEED_MULTIPLIER: float = 0.8

const BATTERY_DRAIN_LED: float = 0.045
const BATTERY_DRAIN_SCREEN: float = 0.012
const BATTERY_DRAIN_STANDBY: float = 0.0015

var stamina: float = MAX_VALUE
var panic: float = 0.0
var footwear: Footwear = Footwear.SCHOOL_SHOES
var is_bleeding: bool = false
var phone_battery: float = STARTING_BATTERY
var is_exhausted: bool = false
## Above 70 Panic: channels take twice as long and may be fumbled.
var has_shaky_hands: bool = false
var panic_tier: PanicTier = PanicTier.GROUNDED

## Context written by PlayerController every physics frame.
var in_darkness: bool = false
var is_hidden: bool = false

var _body: Node3D = null
var _breath_timer: float = 0.0
var _mirror_cooldown: float = 0.0


func _ready() -> void:
	_body = get_parent() as Node3D


func _process(delta: float) -> void:
	_mirror_cooldown = maxf(_mirror_cooldown - delta, 0.0)
	_update_panic(delta)
	_update_breathing(delta)


# -------------------------------------------------------------------- stamina

## Spends stamina. Returns false (spending nothing) when there is not enough.
func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	_set_stamina(stamina - amount)
	return true


## Continuous drain (sprinting, dragging). Returns false once exhausted.
func drain_stamina(amount: float) -> bool:
	_set_stamina(stamina - amount)
	return not is_exhausted


func recover_stamina(amount: float) -> void:
	_set_stamina(stamina + amount)


func can_sprint() -> bool:
	return not is_exhausted and stamina > 0.0


func _set_stamina(value: float) -> void:
	var clamped: float = clampf(value, 0.0, MAX_VALUE)
	if is_equal_approx(clamped, stamina):
		return
	stamina = clamped
	if stamina <= 0.0:
		is_exhausted = true
	elif is_exhausted and stamina >= EXHAUSTION_RECOVERY:
		is_exhausted = false
	EventBus.stamina_changed.emit(stamina)


## Below 30% Stamina Juan pants loudly enough to be heard 4 m away, every
## 2 seconds - even from inside a locker.
func _update_breathing(delta: float) -> void:
	if stamina >= HEAVY_BREATHING_THRESHOLD or _body == null:
		_breath_timer = 0.0
		return
	_breath_timer += delta
	if _breath_timer >= HEAVY_BREATHING_INTERVAL:
		_breath_timer = 0.0
		NoiseManager.emit_noise(_body.global_position, HEAVY_BREATHING_RADIUS, &"heavy_breathing", _body)


# ---------------------------------------------------------------------- panic

func add_panic(amount: float) -> void:
	_set_panic(panic + amount)


func reduce_panic(amount: float) -> void:
	_set_panic(panic - amount)


func get_tier_name() -> String:
	return TIER_NAMES[panic_tier]


## Looking into a restroom mirror while already Rattled makes it worse.
func look_in_mirror() -> bool:
	if panic_tier < PanicTier.RATTLED or _mirror_cooldown > 0.0:
		return false
	_mirror_cooldown = MIRROR_COOLDOWN
	add_panic(PANIC_MIRROR_SPIKE)
	return true


## How long an interaction really takes with the hands Juan has right now.
func get_channel_time(base_time: float) -> float:
	return base_time * (SHAKY_TIME_MULTIPLIER if has_shaky_hands else 1.0)


func roll_fumble() -> bool:
	return has_shaky_hands and randf() < SHAKY_FUMBLE_CHANCE


func _update_panic(delta: float) -> void:
	var rate: float = 0.0
	# Hidden, the dark is cover, not a threat.
	if in_darkness and not is_hidden:
		rate += PANIC_DARKNESS_RATE
	if is_bleeding:
		rate += PANIC_BLEEDING_RATE
	var threat: float = _get_threat_pressure()
	rate += threat * PANIC_THREAT_RATE
	if rate <= 0.0:
		rate = -PANIC_RECOVERY_RATE
	elif is_hidden and threat <= 0.0:
		rate -= PANIC_HIDING_RECOVERY
	if rate != 0.0:
		_set_panic(panic + rate * delta)


## 0..1 for the closest active robot within 9 m.
func _get_threat_pressure() -> float:
	if _body == null:
		return 0.0
	var pressure: float = 0.0
	for node: Node in get_tree().get_nodes_in_group(&"hostile_presence"):
		var threat := node as Hostile
		if threat == null or not threat.is_threatening():
			continue
		var distance: float = threat.global_position.distance_to(_body.global_position)
		pressure = maxf(pressure, 1.0 - distance / PANIC_THREAT_RADIUS)
	return clampf(pressure, 0.0, 1.0)


func _set_panic(value: float) -> void:
	var clamped: float = clampf(value, 0.0, MAX_VALUE)
	if is_equal_approx(clamped, panic):
		return
	var previous: float = panic
	panic = clamped
	for threshold: int in PANIC_THRESHOLDS:
		var limit: float = float(threshold)
		if previous < limit and panic >= limit:
			EventBus.panic_threshold_crossed.emit(threshold, true)
		elif previous >= limit and panic < limit:
			EventBus.panic_threshold_crossed.emit(threshold, false)
	var tier: PanicTier = PanicTier.GROUNDED
	if panic >= TIER_LIMITS[2]:
		tier = PanicTier.TERROR
	elif panic >= TIER_LIMITS[1]:
		tier = PanicTier.RATTLED
	elif panic >= TIER_LIMITS[0]:
		tier = PanicTier.UNEASY
	if tier != panic_tier:
		panic_tier = tier
		EventBus.panic_tier_changed.emit(panic_tier)
	var shaky: bool = panic > SHAKY_HANDS_THRESHOLD
	if shaky != has_shaky_hands:
		has_shaky_hands = shaky
		EventBus.shaky_hands_changed.emit(shaky)
	EventBus.panic_changed.emit(panic, panic_tier)


# ------------------------------------------------------------------- footwear

func set_footwear(value: Footwear) -> void:
	if value == footwear:
		return
	footwear = value
	EventBus.footwear_changed.emit(footwear)


func cycle_footwear() -> void:
	set_footwear(((footwear + 1) % Footwear.size()) as Footwear)


func get_footwear_name() -> String:
	return FOOTWEAR_NAMES[footwear]


func get_noise_multiplier() -> float:
	return FOOTWEAR_NOISE[footwear]


# ------------------------------------------------------------------- bleeding

func start_bleeding(_source: StringName = &"") -> void:
	if is_bleeding:
		return
	is_bleeding = true
	EventBus.bleeding_changed.emit(true)


## Disinfected and bandaged.
func stop_bleeding() -> void:
	if not is_bleeding:
		return
	is_bleeding = false
	EventBus.bleeding_changed.emit(false)


func get_speed_multiplier() -> float:
	return BLEEDING_SPEED_MULTIPLIER if is_bleeding else 1.0


## Stepping on a BrokenGlassHazard. Only bare feet are cut.
func step_on_glass() -> bool:
	if footwear != Footwear.BAREFOOT or is_bleeding:
		return false
	start_bleeding(&"glass")
	add_panic(12.0)
	return true


# -------------------------------------------------------------------- battery

func drain_battery(amount: float) -> void:
	_set_battery(phone_battery - amount)


func charge_battery(amount: float) -> void:
	_set_battery(phone_battery + amount)


func is_phone_dead() -> bool:
	return phone_battery <= 0.0


func _set_battery(value: float) -> void:
	var clamped: float = clampf(value, 0.0, MAX_VALUE)
	if is_equal_approx(clamped, phone_battery):
		return
	var whole_changed: bool = int(ceil(clamped)) != int(ceil(phone_battery))
	phone_battery = clamped
	if whole_changed or phone_battery <= 0.0:
		EventBus.phone_battery_changed.emit(phone_battery)
