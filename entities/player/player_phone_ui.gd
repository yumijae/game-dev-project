class_name PlayerPhoneUI
extends Node3D
## Juan Dela Cruz's smartphone: the white LED flashlight, the screen he raises to send
## the rooftop SOS, and the battery both of them eat. Lives under the camera.
##
## The LED is the only light strong enough to carry: shining it through an
## exterior jalousie window or a corridor viewing pane reports a light leak,
## and the Aswang come to look.

const LED_RANGE: float = 18.0
## Higher than a bare cone needs: the cookie dims everything but the core.
const LED_ENERGY: float = 3.2
const LEAK_CHECK_INTERVAL: float = 0.2
const LEAK_REPORT_COOLDOWN: float = 1.5
const LOW_BATTERY: float = 5.0
const RAY_MASK: int = 1 | 8 | 16

var is_flashlight_on: bool = false
var is_phone_out: bool = false

var _stats: PlayerStats = null
var _led: SpotLight3D = null
var _screen_glow: OmniLight3D = null
var _canvas: CanvasLayer = null
## The handset on screen (status bar, home screen, apps).
var screen: PhoneScreen = null
var _leak_timer: float = 0.0
var _leak_cooldown: float = 0.0
var _flicker_timer: float = 0.0
var _tremor_phase: float = 0.0


func setup(stats: PlayerStats) -> void:
	_stats = stats


func _ready() -> void:
	_led = SpotLight3D.new()
	_led.name = "Led"
	_led.light_color = Color(0.93, 0.96, 1.0)
	_led.light_energy = LED_ENERGY
	_led.spot_range = LED_RANGE
	_led.spot_angle = 38.0
	_led.spot_attenuation = 1.1
	_led.spot_angle_attenuation = 1.0
	_led.light_projector = LightRig.led_cookie()
	_led.light_specular = 0.35
	# A faint beam in the haze; froxels cannot carry it through a wall
	# now that the beam's own shadow is sealed.
	# A phone LED is a few millimetres across: contact-hardening shadows,
	# razor sharp where things touch and softening as they fall away.
	LightRig.seal(_led, 0.012, 0.6)
	_led.visible = false
	add_child(_led)
	_screen_glow = OmniLight3D.new()
	_screen_glow.name = "ScreenGlow"
	_screen_glow.light_color = Color(0.6, 0.8, 1.0)
	_screen_glow.light_energy = 0.25
	_screen_glow.omni_range = 1.6
	_screen_glow.omni_attenuation = 1.6
	_screen_glow.light_specular = 0.1
	# It used to have no shadow at all and lit the next room through the wall.
	LightRig.seal(_screen_glow, 0.04)
	_screen_glow.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	_screen_glow.position = Vector3(0.15, -0.2, -0.3)
	_screen_glow.visible = false
	add_child(_screen_glow)
	_build_screen()
	EventBus.time_advanced.connect(_on_time_advanced)
	EventBus.phone_battery_changed.connect(_on_battery_changed)
	EventBus.sos_progress_changed.connect(_on_sos_progress)
	EventBus.sos_sent.connect(_on_sos_sent)
	_on_battery_changed(_stats.phone_battery if _stats != null else PlayerStats.STARTING_BATTERY)


func _physics_process(delta: float) -> void:
	if _stats == null:
		return
	var drain: float = PlayerStats.BATTERY_DRAIN_STANDBY
	if is_flashlight_on:
		drain += PlayerStats.BATTERY_DRAIN_LED
	if is_phone_out:
		drain += PlayerStats.BATTERY_DRAIN_SCREEN
	_stats.drain_battery(drain * delta)
	if _stats.is_phone_dead():
		if is_flashlight_on:
			set_flashlight(false)
		if is_phone_out:
			set_phone_out(false)
		return
	_leak_cooldown = maxf(_leak_cooldown - delta, 0.0)
	if is_flashlight_on:
		_update_beam(delta)
		_leak_timer += delta
		if _leak_timer >= LEAK_CHECK_INTERVAL:
			_leak_timer = 0.0
			_check_light_leak()


func toggle_flashlight() -> void:
	set_flashlight(not is_flashlight_on)


func set_flashlight(enabled: bool) -> void:
	if enabled and (_stats == null or _stats.is_phone_dead()):
		EventBus.ui_notification.emit("The phone is dead.", 2.0)
		return
	if enabled == is_flashlight_on:
		return
	is_flashlight_on = enabled
	_led.visible = enabled
	EventBus.flashlight_toggled.emit(enabled)


## Raising the phone shows the clock, battery and SOS status.
func set_phone_out(enabled: bool) -> void:
	if enabled and (_stats == null or _stats.is_phone_dead()):
		EventBus.ui_notification.emit("The phone is dead.", 2.0)
		return
	if enabled == is_phone_out:
		return
	is_phone_out = enabled
	_screen_glow.visible = enabled
	if screen != null:
		if enabled:
			screen.show_phone()
		else:
			screen.hide_phone()
	EventBus.phone_raised.emit(enabled)


func toggle_phone_out() -> void:
	set_phone_out(not is_phone_out)


func get_beam_origin() -> Vector3:
	return global_position


func get_beam_direction() -> Vector3:
	return -global_transform.basis.z.normalized()


## True when the LED is on and pointed at `target` within `cone_degrees`.
func is_beam_on(target: Vector3, cone_degrees: float = 10.0, max_distance: float = LED_RANGE) -> bool:
	if not is_flashlight_on:
		return false
	var to_target: Vector3 = target - get_beam_origin()
	if to_target.length() > max_distance or to_target.length() < 0.01:
		return false
	return rad_to_deg(get_beam_direction().angle_to(to_target)) <= cone_degrees


## Hallucination: the phone seems to vibrate. Nothing actually happened.
func phantom_vibrate() -> void:
	SfxSynth.play_ui(self, SfxSynth.phone_buzz(), -14.0)
	if screen != null:
		screen.buzz()
	EventBus.ui_notification.emit("Bzzt... bzzt...", 1.4)


func _update_beam(delta: float) -> void:
	var energy: float = LED_ENERGY
	if _stats.phone_battery <= LOW_BATTERY:
		_flicker_timer -= delta
		if _flicker_timer <= 0.0:
			_flicker_timer = randf_range(0.05, 0.5)
			energy = LED_ENERGY * (randf_range(0.15, 0.6) if randf() < 0.4 else 1.0)
			_led.light_energy = energy
	else:
		_led.light_energy = energy
	if _stats.has_shaky_hands:
		_tremor_phase += delta * 14.0
		var amplitude: float = deg_to_rad(1.6)
		_led.rotation = Vector3(sin(_tremor_phase * 1.3) * amplitude, cos(_tremor_phase * 1.7) * amplitude, 0.0)
	else:
		_led.rotation = Vector3.ZERO


## Reports the beam hitting glass that lets light out of the room.
func _check_light_leak() -> void:
	if _leak_cooldown > 0.0:
		return
	var origin: Vector3 = get_beam_origin()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + get_beam_direction() * LED_RANGE, RAY_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var surface := hit["collider"] as Node3D
	if surface == null or not surface.has_method("leaks_light"):
		return
	var leaks: bool = surface.call("leaks_light")
	if leaks:
		_leak_cooldown = LEAK_REPORT_COOLDOWN
		var point: Vector3 = hit["position"]
		EventBus.flashlight_leaked.emit(point, surface)


func _build_screen() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 2
	add_child(_canvas)


## Called by the player once its CCTV app exists.
func attach_screen(cctv: CctvApp) -> void:
	screen = PhoneScreen.new()
	screen.name = "PhoneScreen"
	screen.setup(self, cctv)
	_canvas.add_child(screen)


func _make_label(parent: Control, font_size: int, color: Color) -> Label:
	var label := Label.new()
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"])
	label.add_theme_font_override("font", serif)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _on_time_advanced(_hour: int, _minute: int, _formatted: String, _progress: float) -> void:
	pass


func _on_battery_changed(percent: float) -> void:
	if percent <= 0.0 and is_phone_out:
		set_phone_out(false)


func _on_sos_progress(_seconds: float, _required: float) -> void:
	pass


func _on_sos_sent() -> void:
	pass
