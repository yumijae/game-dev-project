class_name Jumpscare
extends Node
## The robot's face, right in Juan's.
##
##   play()  - the killing blow: the view snaps round to the robot, it lunges
##             into the camera screeching, the picture shakes and flashes red,
##             then cuts to black and `on_done` runs (the death screen).
##   sting() - a hit he survives: a short shake, flash and screech, no
##             cut-away, so the chase goes on.
##
## Juan and the robot are frozen for the length of play(); the robot's body
## animation (_process) keeps running, so it still twitches in his face.

const TURN_TIME: float = 0.12
const LUNGE_TIME: float = 0.16
const HOLD_TIME: float = 1.05
const CUT_TIME: float = 0.12
const SHAKE: float = 0.045
## Loud enough to jolt, not to hurt: the screech is a dense, clipped signal,
## so it sits well below 0 dB (it was +2 dB and -5 dB for the sting).
const SCREECH_DB: float = -11.0
const STING_DB: float = -17.0

var _player: PlayerController = null
var _camera: Camera3D = null
var _light: OmniLight3D = null
var _overlay: CanvasLayer = null
var _flash: ColorRect = null
var _shake: float = 0.0
var _rest: Transform3D = Transform3D.IDENTITY
var _playing: bool = false
## A survived hit jolts Juan's own camera (its h/v offsets, which nothing
## else moves), easing off over half a second.
var _sting: float = 0.0


func setup(player: PlayerController) -> void:
	_player = player


func is_playing() -> bool:
	return _playing


func play(robot: RobotBase, on_done: Callable) -> void:
	if _playing or _player == null:
		on_done.call()
		return
	_playing = true
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	robot.velocity = Vector3.ZERO
	robot.set_physics_process(false)
	robot.on_jumpscare()
	var view: Camera3D = _player.camera
	_camera = Camera3D.new()
	_camera.name = "JumpscareCamera"
	_camera.top_level = true
	_camera.fov = view.fov
	_camera.near = 0.02
	_camera.cull_mask &= ~Viewmodel.LAYER
	add_child(_camera)
	_camera.global_transform = view.global_transform
	_camera.current = true
	# A cold light on the lens, so its face shows even in a black room.
	_light = OmniLight3D.new()
	_light.light_color = Color(0.85, 0.9, 1.0)
	_light.light_energy = 0.45
	_light.omni_range = 1.6
	_light.position = Vector3(0.0, 0.15, 0.05)
	_camera.add_child(_light)
	_build_overlay()
	EventBus.jumpscare_started.emit()
	# The robot turns to face him square (its model looks down its -Z).
	var from: Vector3 = robot.global_position
	var to_cam := Vector3(_camera.global_position.x - from.x, 0.0, _camera.global_position.z - from.z)
	if to_cam.length() > 0.05:
		robot.look_at(from + to_cam, Vector3.UP)
	# 1. The view snaps round to it.
	var eye: Vector3 = robot.get_eye_position()
	var start: Quaternion = _camera.global_transform.basis.get_rotation_quaternion()
	var aim: Quaternion = Transform3D.IDENTITY.looking_at(eye - _camera.global_position, Vector3.UP).basis.get_rotation_quaternion()
	var turn := create_tween()
	turn.tween_method(func(w: float) -> void:
		_camera.global_basis = Basis(start.slerp(aim, w)), 0.0, 1.0, TURN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await turn.finished
	if not is_inside_tree():
		return
	# 2. It lunges into the lens.
	SfxSynth.play_ui(self, SfxSynth.screech(), SCREECH_DB, robot.scare_pitch)
	SfxSynth.play_ui(self, SfxSynth.clatter(), SCREECH_DB - 8.0, 0.7)
	# Its eyes end up level with his, just in front of the lens: a small one
	# leaps up at his face, a tall one stoops into it.
	var forward: Vector3 = -_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var face_at: Vector3 = _camera.global_position + forward * robot.scare_distance + Vector3.DOWN * 0.04
	var target: Vector3 = robot.global_position + (face_at - robot.get_eye_position())
	var look_from: Quaternion = _camera.global_basis.get_rotation_quaternion()
	var look_to: Quaternion = Transform3D.IDENTITY.looking_at(face_at - _camera.global_position, Vector3.UP).basis.get_rotation_quaternion()
	var lunge := create_tween().set_parallel(true)
	lunge.tween_property(robot, ^"global_position", target, LUNGE_TIME).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	lunge.tween_method(func(w: float) -> void:
		_camera.global_basis = Basis(look_from.slerp(look_to, w)), 0.0, 1.0, LUNGE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	lunge.tween_property(_camera, ^"fov", _camera.fov - 18.0, LUNGE_TIME + 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash.color = Color(1.0, 1.0, 1.0, 0.55)
	lunge.tween_property(_flash, ^"color", Color(0.55, 0.0, 0.0, 0.28), 0.25)
	await lunge.finished
	if not is_inside_tree():
		return
	_rest = _camera.global_transform
	_shake = 1.0
	# 3. Hold, shaking.
	await get_tree().create_timer(HOLD_TIME).timeout
	if not is_inside_tree():
		return
	# 4. Cut to black.
	var cut := create_tween()
	cut.tween_property(_flash, ^"color", Color(0.0, 0.0, 0.0, 1.0), CUT_TIME)
	await cut.finished
	_shake = 0.0
	on_done.call()
	# The death screen draws over this; let the black go so it shows.
	var fade := create_tween()
	fade.tween_property(_flash, ^"color:a", 0.0, 0.4)


## A hit he lives through: a jolt, not a cut-away.
func sting(robot: RobotBase) -> void:
	if _playing or _player == null:
		return
	SfxSynth.play_ui(self, SfxSynth.screech(), STING_DB, robot.scare_pitch * 1.15)
	if _overlay == null:
		_build_overlay()
	_flash.color = Color(1.0, 1.0, 1.0, 0.35)
	var t := create_tween()
	t.tween_property(_flash, ^"color", Color(0.6, 0.0, 0.0, 0.0), 0.45)
	_sting = 1.0


func _process(delta: float) -> void:
	if _sting > 0.0 and _player != null:
		_sting = maxf(_sting - delta * 2.2, 0.0)
		_player.camera.h_offset = randf_range(-1.0, 1.0) * 0.03 * _sting
		_player.camera.v_offset = randf_range(-1.0, 1.0) * 0.03 * _sting
	if _camera == null or _shake <= 0.0:
		return
	# Hard and fast at first, easing to a tremble.
	_shake = maxf(_shake - delta * 0.55, 0.25)
	var offset := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * SHAKE * _shake
	var roll: float = randf_range(-1.0, 1.0) * 0.05 * _shake
	_camera.global_transform = _rest * Transform3D(Basis(Vector3.BACK, roll), offset)


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "JumpscareOverlay"
	_overlay.layer = 0
	add_child(_overlay)
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0, 0, 0, 0)
	_overlay.add_child(_flash)
