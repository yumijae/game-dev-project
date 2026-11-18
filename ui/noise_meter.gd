class_name NoiseMeter
extends Control
## How loud Juan just was, and whether anything heard it.
##
## A small speaker with five bars, bottom right of the HUD. Every noise Juan
## makes himself (footsteps, panting, a gasp, an extinguisher burst) lights
## bars by how far it carries; they hold a moment, then drain. When a robot
## actually hears one of them - walls and doors included, see
## NoiseManager.hear() - the whole meter flushes red and slowly cools back.
## Noises Juan causes at a distance (a thrown bottle) are decoys and do not
## count: the meter is about Juan himself.

const BARS: int = 5
## A noise this big (metres) fills every bar. School-shoe sprinting is ~16.
const FULL_RADIUS: float = 16.0
## Lit bars hold this long before they start to drain, and drain this fast
## (whole meter per second).
const HOLD_TIME: float = 0.35
const DRAIN_RATE: float = 1.1
## How long the red "heard" state takes to cool back to bone.
const HEARD_TIME: float = 1.6
const BAR_WIDTH: float = 5.0
const BAR_GAP: float = 4.0
const BAR_MIN_HEIGHT: float = 6.0
const BAR_MAX_HEIGHT: float = 22.0
const ICON_WIDTH: float = 22.0
const IDLE_ALPHA: float = 0.3

var bone: Color = Color(0.84, 0.81, 0.74)
var ash: Color = Color(0.56, 0.55, 0.52)
var ember: Color = Color(0.86, 0.22, 0.16)

## 0..1 of the meter currently lit.
var _level: float = 0.0
var _hold: float = 0.0
## 1 right after a robot heard Juan, falling to 0.
var _heard: float = 0.0
var _player: Node = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(ICON_WIDTH + 10.0 + BARS * (BAR_WIDTH + BAR_GAP), BAR_MAX_HEIGHT + 4.0)
	EventBus.noise_emitted.connect(_on_noise_emitted)
	EventBus.player_noise_heard.connect(_on_heard)


func set_player(player: Node) -> void:
	_player = player


func _on_noise_emitted(_origin: Vector3, radius: float, _noise_type: StringName, source: Node) -> void:
	if source == null or source != _player:
		return
	var level: float = clampf(radius / FULL_RADIUS, 0.08, 1.0)
	if level >= _level:
		_level = level
		_hold = HOLD_TIME


func _on_heard(_robot: Node) -> void:
	_heard = 1.0
	_level = maxf(_level, 1.0 / float(BARS))
	_hold = maxf(_hold, HOLD_TIME)


func _process(delta: float) -> void:
	if _hold > 0.0:
		_hold -= delta
	else:
		_level = maxf(_level - DRAIN_RATE * delta, 0.0)
	_heard = maxf(_heard - delta / HEARD_TIME, 0.0)
	var active: bool = _level > 0.0 or _heard > 0.0
	modulate.a = move_toward(modulate.a, 1.0 if active else IDLE_ALPHA, delta * (6.0 if active else 1.5))
	queue_redraw()


func _draw() -> void:
	var tint: Color = bone.lerp(ember, _heard)
	var base_y: float = size.y - 2.0
	# The speaker: a small box and its cone.
	var mid: float = base_y - BAR_MAX_HEIGHT * 0.5
	var box := Rect2(Vector2(0.0, mid - 4.0), Vector2(6.0, 8.0))
	draw_rect(box, tint)
	draw_colored_polygon(PackedVector2Array([
		Vector2(6.0, mid - 4.0), Vector2(14.0, mid - 9.0), Vector2(14.0, mid + 9.0), Vector2(6.0, mid + 4.0),
	]), tint)
	# Sound waves, brighter when loud.
	var wave_alpha: float = 0.35 + 0.65 * clampf(_level * 1.5, 0.0, 1.0)
	draw_arc(Vector2(14.0, mid), 4.5, -0.9, 0.9, 8, Color(tint, wave_alpha), 1.5, true)
	draw_arc(Vector2(14.0, mid), 8.0, -0.9, 0.9, 10, Color(tint, wave_alpha * 0.7), 1.5, true)
	# The bars: lit up to the current level, outlines beyond it.
	var lit: int = int(ceil(_level * float(BARS) - 0.001))
	var x: float = ICON_WIDTH + 10.0
	for i: int in BARS:
		var height: float = lerpf(BAR_MIN_HEIGHT, BAR_MAX_HEIGHT, float(i) / float(BARS - 1))
		var bar := Rect2(Vector2(x, base_y - height), Vector2(BAR_WIDTH, height))
		if i < lit:
			draw_rect(bar, tint)
		else:
			draw_rect(bar, Color(ash.lerp(ember, _heard * 0.6), 0.45), false, 1.0)
		x += BAR_WIDTH + BAR_GAP
