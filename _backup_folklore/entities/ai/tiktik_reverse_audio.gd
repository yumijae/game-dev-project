class_name TiktikReverseAudio
extends AudioStreamPlayer3D
## The Tiktik's lie: its call gets QUIETER the closer it is.
##
##   25 m or more -> loud, rapid "tik-tik-tik"  (-2 dB,  1.25x pitch)
##   under 3 m    -> whisper-quiet, slow clicks (-26 dB, 0.82x pitch)
## Godot's own distance attenuation is switched off and replaced by this curve.

const FAR_DISTANCE: float = 25.0
const NEAR_DISTANCE: float = 3.0
const FAR_VOLUME_DB: float = -2.0
const NEAR_VOLUME_DB: float = -26.0
const FAR_PITCH: float = 1.25
const NEAR_PITCH: float = 0.82
const FAR_INTERVAL: float = 0.13
const NEAR_INTERVAL: float = 0.8
const BURST_SIZE: int = 3

## Clicks only while this is true.
var is_calling: bool = false

var _timer: float = 0.0
var _burst_left: int = BURST_SIZE


func _ready() -> void:
	stream = SfxSynth.click()
	attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	max_distance = 0.0
	panning_strength = 0.45
	max_polyphony = 4


func _process(delta: float) -> void:
	if not is_calling:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance: float = camera.global_position.distance_to(global_position)
	volume_db = get_volume_db_for(distance)
	pitch_scale = get_pitch_for(distance)
	_timer -= delta
	if _timer > 0.0:
		return
	play()
	var interval: float = get_interval_for(distance)
	_burst_left -= 1
	if _burst_left <= 0:
		_burst_left = BURST_SIZE
		_timer = interval * randf_range(3.0, 5.0)
	else:
		_timer = interval * randf_range(0.85, 1.15)


## 0.0 at 25 m or beyond, 1.0 at 3 m or closer.
static func get_closeness(distance: float) -> float:
	return clampf((FAR_DISTANCE - distance) / (FAR_DISTANCE - NEAR_DISTANCE), 0.0, 1.0)


static func get_volume_db_for(distance: float) -> float:
	return lerpf(FAR_VOLUME_DB, NEAR_VOLUME_DB, smoothstep(0.0, 1.0, get_closeness(distance)))


static func get_pitch_for(distance: float) -> float:
	return lerpf(FAR_PITCH, NEAR_PITCH, get_closeness(distance))


static func get_interval_for(distance: float) -> float:
	return lerpf(FAR_INTERVAL, NEAR_INTERVAL, get_closeness(distance))
