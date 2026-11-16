class_name HallucinationManager
extends Node
## Juan Dela Cruz's nerves. Two jobs:
##
## 1. Diegetic monologue - his thoughts as subtitles, across four Panic
##    tiers (Grounded / Uneasy / Rattled / Terror).
## 2. Mechanical hallucinations that grow with Panic. None of them are real,
##    and the game never lies about that to the tools that tell truth:
##    a hallucination spawns NO ceiling dust, casts NO shadow under a door,
##    and NEVER makes the Flask of Lana boil.
##
##    35%+  phantom phone vibrations; a footstep that echoes one step late
##    60%+  3 seconds of quiet Tiktik clicking overhead; shaky reticle (HUD)
##    85%+  doors whispering in groupmates' voices; blood drops that fade
##    95%+  an involuntary gasp every 20 s unless stifled in time

const MONOLOGUE: Dictionary = {
	PlayerStats.PanicTier.GROUNDED: [
		"Okay. I just fell asleep in 402. I only have to find the night guard.",
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
		"Something is ticking in the ceiling. Near or far? I can't tell any more.",
		"Excuse me... just passing through... excuse me...",
		"I am so afraid. This isn't real. This isn't real.",
	],
	PlayerStats.PanicTier.KULBA: [
		"I can't. I can't. I can't breathe.",
		"Was that Mark? No. That was not Mark.",
		"Lord, help me.",
		"Our Father, who art in heaven... who art in heaven...",
	],
}

const WHISPER_LINES: Array[String] = [
	"Juan... open up. It's us.",
	"Juan, the defense is over. Let's go home.",
	"We're right outside, man. Why are you hiding?",
	"Juan... Juan... the door is open, isn't it?",
]

const VIBRATION_PANIC: float = 35.0
const TIKTIK_PANIC: float = 60.0
const WHISPER_PANIC: float = 85.0
const GASP_PANIC: float = 95.0
const GASP_INTERVAL: float = 20.0
const GASP_WINDOW: float = 1.6
const FALSE_TIKTIK_TIME: float = 3.0
const FALSE_BLOOD_TIME: float = 3.0
## Phantom ticks overhead (what the old Tiktik sounded like up close).
const FALSE_CLICK_INTERVAL: float = 0.8
const FALSE_CLICK_VOLUME_DB: float = -22.0
const FALSE_CLICK_PITCH: float = 0.82
const WHISPER_DOOR_RANGE: float = 8.0
const WHISPER_TIME: float = 8.0
const ECHO_DELAY: float = 0.55

var _player: PlayerController = null
var _monologue_timer: float = 6.0
var _vibration_timer: float = 20.0
var _tiktik_timer: float = 18.0
var _whisper_timer: float = 12.0
var _blood_timer: float = 9.0
var _gasp_timer: float = GASP_INTERVAL
var _echo_pending: bool = false
var _echo_timer: float = 0.0
var _false_tiktik_left: float = 0.0
var _false_click_timer: float = 0.0
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
	_update_false_tiktik(delta)
	if panic >= VIBRATION_PANIC:
		_vibration_timer -= delta
		if _vibration_timer <= 0.0:
			_vibration_timer = randf_range(25.0, 45.0)
			_player.phone.phantom_vibrate()
			EventBus.hallucination_started.emit(&"phantom_vibration", _player.global_position)
	if panic >= TIKTIK_PANIC:
		_tiktik_timer -= delta
		if _tiktik_timer <= 0.0:
			_tiktik_timer = randf_range(28.0, 48.0)
			_start_false_tiktik()
	if panic >= WHISPER_PANIC:
		_whisper_timer -= delta
		if _whisper_timer <= 0.0:
			_whisper_timer = randf_range(24.0, 38.0)
			_whisper_at_door()
		_blood_timer -= delta
		if _blood_timer <= 0.0:
			_blood_timer = randf_range(18.0, 28.0)
			_spawn_false_blood()
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


# --------------------------------------------------------- 60%+ false Tiktik

## Close-sounding clicks overhead. No dust falls and the Lana stays still.
func _start_false_tiktik() -> void:
	_false_tiktik_left = FALSE_TIKTIK_TIME
	_false_click_timer = 0.0
	EventBus.hallucination_started.emit(&"false_tiktik", _player.global_position + Vector3.UP * 2.6)


func _update_false_tiktik(delta: float) -> void:
	if _false_tiktik_left <= 0.0:
		return
	_false_tiktik_left -= delta
	_false_click_timer -= delta
	if _false_click_timer <= 0.0:
		_false_click_timer = FALSE_CLICK_INTERVAL * randf_range(0.8, 1.1)
		var overhead: Vector3 = _player.global_position + Vector3(randf_range(-0.8, 0.8), 2.6, randf_range(-0.8, 0.8))
		SfxSynth.play_at(self, SfxSynth.click(), overhead, FALSE_CLICK_VOLUME_DB, FALSE_CLICK_PITCH, 10.0)


# -------------------------------------------------------- 85%+ doors & blood

## A nearby closed door whispers in a groupmate's voice. Nothing stands
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
	SfxSynth.play_at(self, SfxSynth.whisper(), at, -4.0, 1.0, 14.0)
	EventBus.ui_subtitle.emit(WHISPER_LINES[randi() % WHISPER_LINES.size()], 4.5, &"whisper")
	EventBus.hallucination_started.emit(&"whisper_door", at)


## Blood drops on the floor ahead that are gone three seconds later.
func _spawn_false_blood() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var forward: Vector3 = -_player.global_transform.basis.z
	var material := StandardMaterial3D.new()
	material.albedo_color = ScentBreadcrumb.BLOOD_COLOR
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.25
	var holder := Node3D.new()
	holder.name = "FalseBlood"
	scene.add_child(holder)
	holder.global_position = _player.global_position
	for i: int in randi_range(5, 8):
		var mesh := CylinderMesh.new()
		mesh.top_radius = randf_range(0.03, 0.07)
		mesh.bottom_radius = mesh.top_radius
		mesh.height = 0.004
		mesh.radial_segments = 10
		mesh.material = material
		var drop := MeshInstance3D.new()
		drop.mesh = mesh
		drop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(drop)
		drop.position = forward * (1.0 + 0.45 * float(i)) + Vector3(randf_range(-0.2, 0.2), 0.014, randf_range(-0.2, 0.2))
	var tween: Tween = holder.create_tween()
	tween.tween_interval(FALSE_BLOOD_TIME * 0.6)
	tween.tween_property(material, "albedo_color:a", 0.0, FALSE_BLOOD_TIME * 0.4)
	tween.tween_callback(holder.queue_free)
	EventBus.hallucination_started.emit(&"false_blood", holder.global_position)
