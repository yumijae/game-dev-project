class_name PhoneFlashlight
extends Node3D
## Smartphone flashlight & screen illumination for Jude Villanueva.
## Features realistic mobile LED beam, screen glow, low-battery brownout flicker,
## and panic hand-tremor simulation.

@export var spot_light_path: NodePath
@export var screen_glow_path: NodePath

var spot_light: SpotLight3D
var screen_glow: OmniLight3D

var _survival_attr: SurvivalAttributes
var _flicker_timer: float = 0.0
var _base_energy: float = 2.2
var _target_energy: float = 2.2

# Panic trembling
var _noise_seed: float = 0.0


func _ready() -> void:
	# Ensure SpotLight3D exists
	if has_node(spot_light_path):
		spot_light = get_node(spot_light_path) as SpotLight3D
	else:
		spot_light = SpotLight3D.new()
		spot_light.name = "PhoneTorch"
		spot_light.light_color = Color(0.92, 0.95, 1.0) # Cold LED
		spot_light.light_energy = _base_energy
		spot_light.spot_range = 18.0
		spot_light.spot_angle = 38.0
		spot_light.spot_attenuation = 1.3
		spot_light.shadow_enabled = true
		add_child(spot_light)

	# Ensure OmniLight3D (screen glow) exists
	if has_node(screen_glow_path):
		screen_glow = get_node(screen_glow_path) as OmniLight3D
	else:
		screen_glow = OmniLight3D.new()
		screen_glow.name = "ScreenGlow"
		screen_glow.light_color = Color(0.65, 0.85, 1.0) # Dim blue screen backlight
		screen_glow.light_energy = 0.35
		screen_glow.omni_range = 1.8
		screen_glow.omni_attenuation = 1.8
		screen_glow.shadow_enabled = false
		add_child(screen_glow)

	# Locate SurvivalAttributes
	_survival_attr = get_parent().get_node_or_null("SurvivalAttributes") as SurvivalAttributes
	if not _survival_attr:
		_survival_attr = get_node_or_null("../SurvivalAttributes") as SurvivalAttributes
	if not _survival_attr and get_parent().get_parent():
		_survival_attr = get_parent().get_parent().get_node_or_null("SurvivalAttributes") as SurvivalAttributes

	EventBus.phone_battery_changed.connect(_on_battery_changed)


func _process(delta: float) -> void:
	if not _survival_attr or not spot_light:
		return

	# Handle torch visibility
	spot_light.visible = _survival_attr.is_torch_active and not _survival_attr.is_phone_dead
	screen_glow.visible = not _survival_attr.is_phone_dead

	if spot_light.visible:
		_process_low_battery_flicker(delta)
		_process_panic_tremor(delta)


func _process_low_battery_flicker(delta: float) -> void:
	if _survival_attr.battery_percentage <= _survival_attr.low_battery_threshold:
		_flicker_timer -= delta
		if _flicker_timer <= 0.0:
			# Random brownouts
			var severity := 1.0 - (_survival_attr.battery_percentage / _survival_attr.low_battery_threshold)
			if randf() < (0.2 + severity * 0.4):
				_target_energy = randf_range(0.2, _base_energy * 0.6)
				_flicker_timer = randf_range(0.04, 0.15)
			else:
				_target_energy = _base_energy
				_flicker_timer = randf_range(0.2, 0.8)
		spot_light.light_energy = lerpf(spot_light.light_energy, _target_energy, 20.0 * delta)
	else:
		spot_light.light_energy = _base_energy


func _process_panic_tremor(delta: float) -> void:
	var tier := _survival_attr.current_panic_tier
	if tier < 2:
		rotation = Vector3.ZERO
		return

	_noise_seed += delta * (8.0 if tier == 2 else 16.0)
	var amplitude := deg_to_rad(0.8) if tier == 2 else deg_to_rad(2.2)
	
	rotation.x = sin(_noise_seed * 1.3) * amplitude
	rotation.y = cos(_noise_seed * 1.7) * amplitude
	rotation.z = sin(_noise_seed * 2.1) * (amplitude * 0.5)


func _on_battery_changed(_pct: float, _is_on: bool) -> void:
	# Responds to sudden battery drain / death
	pass
