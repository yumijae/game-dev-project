class_name PostFX
extends CanvasLayer
## Drives res://shaders/post_horror.gdshader from Juan's state. Sits under the
## HUD so the interface itself is never distorted.
##
##   Panic     -> heartbeat pulse, tunnel vision, colour drain, wobble
##   Bleeding  -> blood veins at the screen edge
##   Wounded   -> a red flash and a jolt of static
##   Glass shattering / Tiktik berserk -> a burst of static

const SHADER: Shader = preload("res://shaders/post_horror.gdshader")
const CALM_HEART_RATE: float = 1.0
const KULBA_HEART_RATE: float = 2.4

var _material: ShaderMaterial = null
var _panic: float = 0.0
var _panic_target: float = 0.0
var _bleeding: float = 0.0
var _bleeding_target: float = 0.0
var _hit_flash: float = 0.0
var _static_burst: float = 0.0
var _heartbeat_phase: float = 0.0


func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var rect := ColorRect.new()
	rect.name = "Grade"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _material
	add_child(rect)
	EventBus.panic_changed.connect(_on_panic_changed)
	EventBus.bleeding_changed.connect(_on_bleeding_changed)
	EventBus.player_wounded.connect(_on_player_wounded)
	EventBus.glass_shattered.connect(_on_glass_shattered)
	EventBus.tiktik_berserk.connect(_on_tiktik_berserk)
	EventBus.game_lost.connect(_on_game_lost)


func _process(delta: float) -> void:
	_panic = move_toward(_panic, _panic_target, delta * 0.6)
	_bleeding = move_toward(_bleeding, _bleeding_target, delta * 0.8)
	_hit_flash = move_toward(_hit_flash, 0.0, delta * 1.4)
	_static_burst = move_toward(_static_burst, 0.0, delta * 2.2)
	_heartbeat_phase = fmod(_heartbeat_phase + delta * lerpf(CALM_HEART_RATE, KULBA_HEART_RATE, _panic), 1.0)
	_material.set_shader_parameter(&"panic", _panic)
	_material.set_shader_parameter(&"bleeding", _bleeding)
	_material.set_shader_parameter(&"hit_flash", _hit_flash)
	_material.set_shader_parameter(&"static_burst", _static_burst)
	_material.set_shader_parameter(&"heartbeat_phase", _heartbeat_phase)


func _on_panic_changed(value: float, _tier: int) -> void:
	_panic_target = clampf(value / 100.0, 0.0, 1.0)


func _on_bleeding_changed(is_bleeding: bool) -> void:
	_bleeding_target = 1.0 if is_bleeding else 0.0


func _on_player_wounded(_source: StringName) -> void:
	_hit_flash = 1.0
	_static_burst = maxf(_static_burst, 0.6)


func _on_glass_shattered(_glass: Node3D, _point: Vector3) -> void:
	_static_burst = maxf(_static_burst, 0.45)


func _on_tiktik_berserk(_position: Vector3) -> void:
	_static_burst = 1.0


func _on_game_lost(_cause: String) -> void:
	_hit_flash = 1.0
	_bleeding_target = 1.0
