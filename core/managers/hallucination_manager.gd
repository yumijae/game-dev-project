class_name HallucinationManager
extends Node
## Juan Dela Cruz's nerves. Two jobs:
##
## 1. Diegetic monologue - his thoughts as subtitles, across four Panic
##    tiers (Grounded / Uneasy / Rattled / Terror).
## 2. Mechanical hallucinations that grow with Panic. None of them are real,
##    and the game never lies about that to the tools that tell truth:
##    a hallucination makes no noise a robot can hear, never shows on the
##    CCTV, and casts NO shadow under a door.
##
##    35%+  phantom phone vibrations; a footstep that echoes one step late
##    60%+  a servo whirring close by that is not there; shaky reticle (HUD)
##    85%+  a greeter's voice behind a closed door; a standby light in the
##          dark ahead that fades when he looks at it
##    95%+  an involuntary gasp every 20 s unless stifled in time

const MONOLOGUE: Dictionary = {
	PlayerStats.PanicTier.GROUNDED: [
		"Okay. I just fell asleep in 402. The guard opens up at six. I only have to last till then.",
		"Breathe. One thing at a time. I know this building.",
		"I should have been home hours ago. Thesis, thesis, always the thesis.",
		"Morning is a long way off. But I can do this.",
	],
	PlayerStats.PanicTier.UNEASY: [
		"Why does it feel like someone is walking in step with me?",
		"Don't look back. Don't.",
		"What was that? ...Nothing. Probably just the wind.",
		"My shoes are so loud on these tiles. I should have taken them off.",
	],
	PlayerStats.PanicTier.RATTLED: [
		"My hands are shaking. I can't hold anything properly.",
		"Was that a servo? Near or far? I can't tell any more.",
		"It's a school project. It's just a school project.",
		"I am so afraid. This isn't real. This isn't real.",
	],
	PlayerStats.PanicTier.TERROR: [
		"I can't. I can't. I can't breathe.",
		"It moved. I looked away for one second and it moved.",
		"Please. Please. I just want to go home.",
		"Don't blink. Don't blink. Don't blink.",
	],
}

## The greeter robot's canned lines, heard through a door nothing stands behind.
const DOOR_VOICE_LINES: Array[String] = [
	"Welcome to the Tech Expo. May I see your visitor pass?",
	"Good evening. This room is closed. Please step outside.",
	"Hello. I can see you. Would you like directions?",
	"Please remain where you are. An attendant is on the way.",
]

const VIBRATION_PANIC: float = 35.0
const SERVO_PANIC: float = 60.0
const WHISPER_PANIC: float = 85.0
const GASP_PANIC: float = 95.0
const GASP_INTERVAL: float = 20.0
const GASP_WINDOW: float = 1.6
const FALSE_SERVO_TIME: float = 3.0
const FALSE_LIGHT_TIME: float = 3.0
## Phantom servo whirs, a few steps off in the dark.
const FALSE_SERVO_INTERVAL: float = 0.9
const FALSE_SERVO_VOLUME_DB: float = -20.0
## A robot's standby LED: the orange of PROTOTYPE's eye.
## Brighter than white so it blooms like a real LED instead of a flat dot.
const FALSE_LIGHT_COLOR: Color = Color(4.0, 1.5, 0.3)
const FALSE_LIGHT_MAX_DISTANCE: float = 9.0
const WHISPER_DOOR_RANGE: float = 8.0
const WHISPER_TIME: float = 8.0
const ECHO_DELAY: float = 0.55

var _player: PlayerController = null
var _monologue_timer: float = 6.0
var _vibration_timer: float = 20.0
var _servo_timer: float = 18.0
var _whisper_timer: float = 12.0
var _light_timer: float = 9.0
var _gasp_timer: float = GASP_INTERVAL
var _echo_pending: bool = false
var _echo_timer: float = 0.0
var _false_servo_left: float = 0.0
var _false_servo_timer: float = 0.0
var _false_servo_bearing: float = 0.0
var _last_line: String = ""


func _ready() -> void:
	EventBus.panic_tier_changed.connect(_on_panic_tier_changed)
	EventBus.noise_emitted.connect(_on_noise_emitted)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as PlayerController
		return
	if _player.is_dead:
		return
	var panic: float = _player.stats.panic
	_update_monologue(delta)
	_update_echo(delta, panic)
	_update_false_servo(delta)
	if panic >= VIBRATION_PANIC:
		_vibration_timer -= delta
		if _vibration_timer <= 0.0:
			_vibration_timer = randf_range(25.0, 45.0)
			_player.phone.phantom_vibrate()
			EventBus.hallucination_started.emit(&"phantom_vibration", _player.global_position)
	if panic >= SERVO_PANIC:
		_servo_timer -= delta
		if _servo_timer <= 0.0:
			_servo_timer = randf_range(28.0, 48.0)
			_start_false_servo()
	if panic >= WHISPER_PANIC:
		_whisper_timer -= delta
		if _whisper_timer <= 0.0:
			_whisper_timer = randf_range(24.0, 38.0)
			_whisper_at_door()
		_light_timer -= delta
		if _light_timer <= 0.0:
			_light_timer = randf_range(18.0, 28.0)
			_spawn_false_light()
	if panic >= GASP_PANIC:
		_gasp_timer -= delta
		if _gasp_timer <= 0.0:
			_gasp_timer = GASP_INTERVAL
			_player.request_gasp(GASP_WINDOW)
	else:
		_gasp_timer = GASP_INTERVAL


# ------------------------------------------------------------------ monologue

func _update_monologue(delta: float) -> void:
	_monologue_timer -= delta
	if _monologue_timer <= 0.0:
		_monologue_timer = randf_range(28.0, 45.0)
		_speak(_player.stats.panic_tier)


func _on_panic_tier_changed(tier: int) -> void:
	# Say something the moment his state of mind shifts.
	_monologue_timer = randf_range(28.0, 45.0)
	_speak(tier)


func _speak(tier: int) -> void:
	var lines: Array = MONOLOGUE[tier]
	var line: String = lines[randi() % lines.size()]
	if line == _last_line:
		line = lines[(lines.find(line) + 1) % lines.size()]
	_last_line = line
	EventBus.ui_subtitle.emit(line, 4.5, &"Juan")


# ------------------------------------------------------------ 35%+ footsteps

func _on_noise_emitted(_origin: Vector3, _radius: float, noise_type: StringName, source: Node) -> void:
	if source == _player and NoiseManager.FOOTSTEP_TYPES.has(noise_type):
		_echo_pending = true
		_echo_timer = ECHO_DELAY


## One extra footfall, a beat after Juan stops. Audio only - nothing hears it.
func _update_echo(delta: float, panic: float) -> void:
	if not _echo_pending:
		return
	_echo_timer -= delta
	if _echo_timer > 0.0:
		return
	_echo_pending = false
	if panic < VIBRATION_PANIC:
		return
	var behind: Vector3 = _player.global_position + _player.global_transform.basis.z * 1.6
	SfxSynth.play_at(self, SfxSynth.footstep(), behind, -9.0, 0.9, 12.0)
	EventBus.hallucination_started.emit(&"echo_footstep", behind)


# ---------------------------------------------------------- 60%+ false servo

## A motor whirring a few steps away, from one direction, for three seconds.
## Audio only: nothing is there, and no robot hears it.
func _start_false_servo() -> void:
	_false_servo_left = FALSE_SERVO_TIME
	_false_servo_timer = 0.0
	_false_servo_bearing = randf() * TAU
	EventBus.hallucination_started.emit(&"false_servo", _false_servo_point())


func _false_servo_point() -> Vector3:
	return _player.global_position + Vector3(cos(_false_servo_bearing), 0.0, sin(_false_servo_bearing)) * 3.5 + Vector3.UP * 0.9


func _update_false_servo(delta: float) -> void:
	if _false_servo_left <= 0.0:
		return
	_false_servo_left -= delta
	_false_servo_timer -= delta
	if _false_servo_timer <= 0.0:
		_false_servo_timer = FALSE_SERVO_INTERVAL * randf_range(0.8, 1.2)
		SfxSynth.play_at(self, SfxSynth.servo(), _false_servo_point(), FALSE_SERVO_VOLUME_DB, randf_range(0.85, 1.0), 10.0)


# -------------------------------------------------------- 85%+ doors & light

## The greeter's voice comes through a nearby closed door. Nothing stands
## outside: peeking under it shows no shadow at all.
func _whisper_at_door() -> void:
	var best: InteractableDoor = null
	var best_distance: float = WHISPER_DOOR_RANGE
	for node: Node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as InteractableDoor
		if door == null or door.is_passable() or door.permanently_locked:
			continue
		var distance: float = door.get_center().distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = door
	if best == null:
		return
	best.hallucination_time_left = WHISPER_TIME
	var at: Vector3 = best.get_center() + Vector3.UP * 1.2
	SfxSynth.play_at(self, SfxSynth.servo(), at, -10.0, 0.7, 14.0)
	EventBus.ui_subtitle.emit(DOOR_VOICE_LINES[randi() % DOOR_VOICE_LINES.size()], 4.5, &"door_voice")
	EventBus.hallucination_started.emit(&"whisper_door", at)


## A small orange standby light at robot head height in the dark ahead,
## gone three seconds later. It is placed short of the first wall in the way,
## so it never shines through one.
func _spawn_false_light() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var eye: Vector3 = _player.head.global_position
	var forward: Vector3 = -_player.global_transform.basis.z
	var distance: float = FALSE_LIGHT_MAX_DISTANCE
	var query := PhysicsRayQueryParameters3D.create(eye, eye + forward * FALSE_LIGHT_MAX_DISTANCE, 1 | 8)
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		distance = eye.distance_to(hit["position"]) - 0.4
	# Too close to be anything but a dot on the wall in front of him.
	if distance < 3.0:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = FALSE_LIGHT_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# An LED cuts through the haze; fog would swallow it at this size.
	material.disable_fog = true
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = material
	var dot := MeshInstance3D.new()
	dot.name = "FalseLight"
	dot.mesh = mesh
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(dot)
	dot.global_position = eye + forward * distance + Vector3(randf_range(-0.6, 0.6), randf_range(-0.25, 0.1), 0.0)
	var tween: Tween = dot.create_tween()
	tween.tween_interval(FALSE_LIGHT_TIME * 0.6)
	tween.tween_property(material, "albedo_color:a", 0.0, FALSE_LIGHT_TIME * 0.4)
	tween.tween_callback(dot.queue_free)
	EventBus.hallucination_started.emit(&"false_light", dot.global_position)
