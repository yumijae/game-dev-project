class_name LanaCandle
extends StaticBody3D
## A candle anointed with Good Friday coconut oil. Its warm flame calms Juan
## without the hard white glare that provokes the Tiktik, and it burns pale
## blue whenever a real Aswang is within 8 metres.

const LAYER_INTERACT: int = 2
const LIGHT_RADIUS: float = 5.0
const CALM_RADIUS: float = 5.0
const ASWANG_RADIUS: float = 8.0
const BURN_TIME: float = 240.0
const WARM_COLOR: Color = Color(1.0, 0.72, 0.38)
const WARNING_COLOR: Color = Color(0.62, 0.82, 1.0)
const FLAME_SHADER: Shader = preload("res://shaders/candle_flame.gdshader")

var is_lit: bool = true
var is_warning: bool = false

var _light: OmniLight3D = null
var _flame: MeshInstance3D = null
var _flame_material: ShaderMaterial = null
var _time_left: float = BURN_TIME
var _phase: float = 0.0


static func place(parent: Node, at: Vector3) -> LanaCandle:
	var candle := LanaCandle.new()
	candle.name = "LanaCandle"
	parent.add_child(candle)
	candle.global_position = at
	return candle


func _ready() -> void:
	add_to_group(&"lana_candles")
	collision_layer = LAYER_INTERACT
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.25, 0.3, 0.25)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.15
	add_child(collider)
	var wax := CylinderMesh.new()
	wax.top_radius = 0.02
	wax.bottom_radius = 0.022
	wax.height = 0.16
	var wax_material := StandardMaterial3D.new()
	wax_material.albedo_color = Color(0.95, 0.9, 0.75)
	wax.material = wax_material
	var body := MeshInstance3D.new()
	body.mesh = wax
	body.position.y = 0.08
	add_child(body)
	var flame_mesh := QuadMesh.new()
	flame_mesh.size = Vector2(0.07, 0.13)
	_flame_material = ShaderMaterial.new()
	_flame_material.shader = FLAME_SHADER
	flame_mesh.material = _flame_material
	_flame = MeshInstance3D.new()
	_flame.mesh = flame_mesh
	_flame.position.y = 0.22
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)
	_light = OmniLight3D.new()
	_light.light_color = WARM_COLOR
	_light.light_energy = 0.9
	_light.omni_range = LIGHT_RADIUS
	_light.omni_attenuation = 1.6
	_light.light_specular = 0.3
	# A real flame: soft-edged shadows and a warm glow in the haze around it.
	LightRig.seal(_light, 0.03, 0.35)
	# Candles left burning on other floors stop costing anything.
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 22.0
	_light.distance_fade_shadow = 22.0
	_light.distance_fade_length = 4.0
	_light.position.y = 0.25
	add_child(_light)


func _process(delta: float) -> void:
	if not is_lit:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_snuff()
		return
	is_warning = _is_aswang_near()
	var color: Color = WARNING_COLOR if is_warning else WARM_COLOR
	_light.light_color = _light.light_color.lerp(color, minf(delta * 4.0, 1.0))
	_flame_material.set_shader_parameter(&"flame_color", _light.light_color)
	_flame_material.set_shader_parameter(&"agitation", 2.4 if is_warning else 1.0)
	_phase += delta * (17.0 if is_warning else 9.0)
	_light.light_energy = 0.9 + sin(_phase) * 0.08 + sin(_phase * 2.7) * 0.05
	# The flame sways, so the shadows it throws breathe with it.
	var sway: float = 0.006 if not is_warning else 0.014
	_light.position = Vector3(sin(_phase * 0.7) * sway, 0.25 + sin(_phase * 1.9) * sway * 0.5, cos(_phase * 0.9) * sway)


func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	if is_lit:
		return [{"id": &"take", "label": "Snuff the candle and take it"}]
	return [{"id": &"none", "label": "Burnt-out candle"}]


func interact(player: PlayerController, action_id: StringName) -> void:
	if action_id != &"take" or not is_lit:
		return
	if player.inventory.add_item(ItemDB.LANA_CANDLE, 1) > 0:
		EventBus.ui_notification.emit("No room. Drop something first.", 2.0)
		return
	queue_free()


## Only real Aswang turn the flame - hallucinations never do.
func _is_aswang_near() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"hostile_presence"):
		var presence := node as Node3D
		if presence != null and presence.global_position.distance_to(global_position) <= ASWANG_RADIUS:
			return true
	return false


func _snuff() -> void:
	is_lit = false
	is_warning = false
	_light.visible = false
	_flame.visible = false
