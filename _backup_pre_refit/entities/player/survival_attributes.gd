class_name SurvivalAttributes
extends Node
## Manages the 5 core survival attributes for protagonist Jude Villanueva:
## 1. Stamina (locomotion, sprint fatigue, heavy breathing noise)
## 2. Panic (0-100%, 4 Tiers, heart rate, camera sway, sensory distortion)
## 3. Footwear & Noise (Shoes vs Socks vs Barefoot, glass cut risk)
## 4. Bleeding & Scent (Blood trail emission, health attrition)
## 5. Phone Battery (Torch drain, low-battery flicker, charging)

# ==============================================================================
# 1. STAMINA
# ==============================================================================
@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_sprint_drain: float = 18.0     # per second while sprinting
@export var stamina_jump_cost: float = 15.0
@export var stamina_recovery_walk: float = 10.0    # per second walking
@export var stamina_recovery_idle: float = 16.0    # per second stationary
@export var stamina_recovery_crouch: float = 22.0  # per second crouching
@export var exhaustion_noise_interval: float = 2.0 # heavy panting sound when stamina=0

var current_stamina: float = 100.0
var is_exhausted: bool = false
var _exhaustion_timer: float = 0.0

# ==============================================================================
# 2. PANIC & HEART RATE
# ==============================================================================
@export_group("Panic")
@export var max_panic: float = 100.0
@export var panic_passive_recovery: float = 1.5    # recedes slowly in safe lighted areas
@export var panic_darkness_increase: float = 2.0   # increases per second in total dark
@export var panic_bleeding_increase: float = 1.0   # increases per second while bleeding

# 4 Tiers:
# 0: Calm (0 - 24%)
# 1: Uneasy (25 - 49%)
# 2: Paranoid (50 - 74%)
# 3: Hallucinating (75 - 100%)
var current_panic: float = 0.0
var current_panic_tier: int = 0

# ==============================================================================
# 3. FOOTWEAR & NOISE MULTIPLIER
# ==============================================================================
@export_group("Footwear")
# "shoes" = normal speed, louder steps on tile (1.0x noise, 1.0x speed)
# "socks" = quieter, slight traction loss (0.45x noise, 0.95x speed)
# "barefoot" = stealthiest, but fragile to glass (0.22x noise, 0.90x speed, glass bleed danger)
@export var footwear_type: StringName = &"shoes"

# ==============================================================================
# 4. BLEEDING & SCENT
# ==============================================================================
@export_group("Bleeding & Health")
@export var max_health: float = 100.0
@export var bleed_damage_per_sec: float = 1.5
@export var blood_scent_drop_interval: float = 2.0 # seconds between blood drops on floor

var current_health: float = 100.0
var is_bleeding: bool = false
var bleed_severity: float = 0.0 # 0.0 to 1.0
var _blood_drop_timer: float = 0.0

# ==============================================================================
# 5. PHONE BATTERY
# ==============================================================================
@export_group("Phone Battery")
@export var battery_max: float = 100.0
@export var battery_torch_drain_per_sec: float = 0.25 # ~400 seconds (6.6 mins) of continuous torch
@export var battery_standby_drain_per_sec: float = 0.02
@export var low_battery_threshold: float = 15.0

var battery_percentage: float = 88.0 # starts at 88% at 11:45 PM
var is_torch_active: bool = false
var is_phone_dead: bool = false

# Scent and Noise references
var _owner_body: CharacterBody3D


func _ready() -> void:
	current_stamina = max_stamina
	current_health = max_health
	current_panic = 0.0
	_update_panic_tier()
	_owner_body = get_parent() as CharacterBody3D


func _process(delta: float) -> void:
	_process_battery(delta)
	_process_bleeding(delta)
	_process_panic(delta)
	_process_exhaustion_breathing(delta)


# ==============================================================================
# STAMINA SYSTEM
# ==============================================================================

func consume_sprint_stamina(delta: float) -> bool:
	if current_stamina <= 0.0:
		is_exhausted = true
		return false

	current_stamina = maxf(0.0, current_stamina - stamina_sprint_drain * delta)
	if current_stamina <= 0.0:
		is_exhausted = true
	
	EventBus.stamina_changed.emit(current_stamina, max_stamina)
	return not is_exhausted


func consume_jump_stamina() -> bool:
	if current_stamina < stamina_jump_cost:
		return false

	current_stamina -= stamina_jump_cost
	EventBus.stamina_changed.emit(current_stamina, max_stamina)
	return true


func recover_stamina(delta: float, is_crouching: bool, is_moving: bool) -> void:
	var rate := stamina_recovery_walk
	if not is_moving:
		rate = stamina_recovery_crouch if is_crouching else stamina_recovery_idle

	current_stamina = minf(max_stamina, current_stamina + rate * delta)
	if is_exhausted and current_stamina >= (max_stamina * 0.35):
		is_exhausted = false

	EventBus.stamina_changed.emit(current_stamina, max_stamina)


func _process_exhaustion_breathing(delta: float) -> void:
	if is_exhausted and _owner_body:
		_exhaustion_timer += delta
		if _exhaustion_timer >= exhaustion_noise_interval:
			_exhaustion_timer = 0.0
			# Heavy panting sound alert
			NoiseManager.emit_noise(_owner_body.global_position, 7.0, 42.0, &"exhaustion_gasp")


# ==============================================================================
# PANIC SYSTEM
# ==============================================================================

func add_panic(amount: float) -> void:
	current_panic = clampf(current_panic + amount, 0.0, max_panic)
	_update_panic_tier()


func reduce_panic(amount: float) -> void:
	current_panic = clampf(current_panic - amount, 0.0, max_panic)
	_update_panic_tier()


func _process_panic(delta: float) -> void:
	# If torch is off and in dark room, panic creeps up
	if not is_torch_active:
		add_panic(panic_darkness_increase * delta)
	else:
		reduce_panic(panic_passive_recovery * delta)

	if is_bleeding:
		add_panic(panic_bleeding_increase * delta)


func _update_panic_tier() -> void:
	var new_tier := 0
	if current_panic >= 75.0:
		new_tier = 3 # Hallucinating
	elif current_panic >= 50.0:
		new_tier = 2 # Paranoid
	elif current_panic >= 25.0:
		new_tier = 1 # Uneasy
	else:
		new_tier = 0 # Calm

	if new_tier != current_panic_tier:
		current_panic_tier = new_tier
		EventBus.panic_tier_entered.emit(current_panic_tier)

	EventBus.panic_changed.emit(current_panic, max_panic, current_panic_tier)


# ==============================================================================
# FOOTWEAR & STEP NOISE
# ==============================================================================

func set_footwear(new_footwear: StringName) -> void:
	footwear_type = new_footwear
	var mult := get_noise_multiplier()
	EventBus.footwear_changed.emit(footwear_type, mult)


func get_noise_multiplier() -> float:
	match footwear_type:
		&"shoes": return 1.0
		&"socks": return 0.45
		&"barefoot": return 0.22
		_: return 1.0


func get_speed_multiplier() -> float:
	match footwear_type:
		&"shoes": return 1.0
		&"socks": return 0.95
		&"barefoot": return 0.90
		_: return 1.0


## Triggered when stepping on broken jalousie glass or debris
func step_on_glass_hazard() -> void:
	if footwear_type == &"barefoot":
		start_bleeding(0.7)
		add_panic(20.0)
		if _owner_body:
			NoiseManager.emit_noise(_owner_body.global_position, 10.0, 58.0, &"scream_pain")
	elif footwear_type == &"socks":
		# Socks protect slightly, but make crunch noise
		if _owner_body:
			NoiseManager.emit_noise(_owner_body.global_position, 12.0, 50.0, &"glass_crunch")


# ==============================================================================
# BLEEDING & SCENT SYSTEM
# ==============================================================================

func start_bleeding(severity: float = 0.5) -> void:
	is_bleeding = true
	bleed_severity = clampf(severity, 0.1, 1.0)
	EventBus.bleeding_changed.emit(true, bleed_severity)


func stop_bleeding() -> void:
	is_bleeding = false
	bleed_severity = 0.0
	EventBus.bleeding_changed.emit(false, 0.0)


func _process_bleeding(delta: float) -> void:
	if not is_bleeding:
		return

	# Damage over time
	current_health -= bleed_damage_per_sec * bleed_severity * delta
	if current_health <= 0.0:
		current_health = 0.0
		EventBus.player_died.emit("Exsanguination (Bled out)")
		return

	# Drop blood scent in ScentManager periodically
	_blood_drop_timer += delta
	if _blood_drop_timer >= blood_scent_drop_interval:
		_blood_drop_timer = 0.0
		if _owner_body:
			ScentManager.drop_scent(_owner_body.global_position, &"blood", bleed_severity, 0.02)


# ==============================================================================
# PHONE BATTERY SYSTEM
# ==============================================================================

func set_torch_state(active: bool) -> void:
	if is_phone_dead:
		is_torch_active = false
	else:
		is_torch_active = active
	EventBus.phone_battery_changed.emit(battery_percentage, is_torch_active)


func toggle_torch() -> void:
	set_torch_state(not is_torch_active)


func recharge_battery(amount: float) -> void:
	battery_percentage = clampf(battery_percentage + amount, 0.0, battery_max)
	if battery_percentage > 0.0 and is_phone_dead:
		is_phone_dead = false
	EventBus.phone_battery_changed.emit(battery_percentage, is_torch_active)


func _process_battery(delta: float) -> void:
	if is_phone_dead:
		return

	var drain := battery_torch_drain_per_sec if is_torch_active else battery_standby_drain_per_sec
	battery_percentage = maxf(0.0, battery_percentage - drain * delta)

	if battery_percentage <= 0.0:
		battery_percentage = 0.0
		is_phone_dead = true
		is_torch_active = false
		EventBus.phone_battery_changed.emit(0.0, false)
