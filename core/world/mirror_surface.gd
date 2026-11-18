class_name MirrorSurface
extends Node3D
## A working mirror. A second camera, reflected through the glass, renders
## the room into a texture the mirror shows - but only while Juan is close
## and the mirror is on screen, so the four restroom mirrors cost nothing the
## rest of the night.
##
## Local frame: the glass lies in the XY plane facing +Z (into the room),
## `size` metres wide (X) and tall (Y), centred on the origin.
##
## The reflection camera looks straight through the glass with an off-axis
## frustum whose near plane *is* the glass, so nothing behind the wall can
## leak into the reflection. Juan has no body, so the mirror shows the room
## and his light - and nobody holding it.

const SHADER: Shader = preload("res://shaders/mirror.gdshader")
## Render layer the glass itself sits on, hidden from its own camera.
const GLASS_LAYER: int = 1 << 19
const FRAME_COLOR: Color = Color(0.44, 0.45, 0.47)

@export var size: Vector2 = Vector2(2.4, 0.8)
@export var pixels_per_metre: float = 420.0
@export var active_distance: float = 9.0

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _notifier: VisibleOnScreenNotifier3D = null
var _active: bool = false


func _ready() -> void:
	# Run after the player has moved his camera this frame.
	process_priority = 1000
	_viewport = SubViewport.new()
	_viewport.name = "Reflection"
	_fit_resolution()
	GameSettings.changed.connect(_fit_resolution)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.positional_shadow_atlas_size = 2048
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.cull_mask = 0xFFFFF & ~GLASS_LAYER & ~Viewmodel.LAYER
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_camera)
	_camera.current = true

	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"reflection", _viewport.get_texture())
	material.set_shader_parameter(&"size_m", size)
	material.set_shader_parameter(&"seed", fposmod(global_position.x * 3.1 + global_position.y * 1.7 + global_position.z * 5.3, 50.0))
	var quad := QuadMesh.new()
	quad.size = size
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = quad
	glass.material_override = material
	glass.layers = GLASS_LAYER
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
	_build_frame()

	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-size.x * 0.5, -size.y * 0.5, -0.02), Vector3(size.x, size.y, 0.06))
	add_child(_notifier)


## Reflection resolution follows the quality preset: a mirror is a second
## full render of the room, the single most expensive thing in a restroom.
func _fit_resolution() -> void:
	var density: float = pixels_per_metre * float(GameSettings.preset_value("mirror"))
	var wanted := Vector2i(maxi(int(size.x * density), 16), maxi(int(size.y * density), 16))
	if _viewport.size != wanted:
		_viewport.size = wanted


## Thin steel channel round the glass.
func _build_frame() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = FRAME_COLOR
	steel.metallic = 0.85
	steel.roughness = 0.35
	var t: float = 0.025
	var proud: float = 0.012
	for side: float in [-1.0, 1.0]:
		_frame_bar(Vector3(0.0, side * (size.y + t) * 0.5, proud * 0.5 - 0.004), Vector3(size.x + t * 2.0, t, proud + 0.008), steel)
		_frame_bar(Vector3(side * (size.x + t) * 0.5, 0.0, proud * 0.5 - 0.004), Vector3(t, size.y, proud + 0.008), steel)


func _frame_bar(at: Vector3, bar_size: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = bar_size
	var bar := MeshInstance3D.new()
	bar.mesh = box
	bar.material_override = material
	bar.position = at
	add_child(bar)


func _process(_delta: float) -> void:
	var eye: Camera3D = get_viewport().get_camera_3d()
	var normal: Vector3 = global_basis.z.normalized()
	var centre: Vector3 = global_position
	var want: bool = false
	var distance: float = 0.0
	if eye != null and _notifier.is_on_screen():
		distance = (eye.global_position - centre).dot(normal)
		want = distance > 0.03 and eye.global_position.distance_to(centre) < active_distance
	if want != _active:
		_active = want
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if want else SubViewport.UPDATE_DISABLED
		if want:
			_camera.environment = _reflection_environment()
	if not _active:
		return
	var up: Vector3 = global_basis.y.normalized()
	var right: Vector3 = global_basis.x.normalized()
	var mirrored: Vector3 = eye.global_position - normal * (2.0 * distance)
	# Looking along +normal (through the glass into the room), up = mirror up.
	_camera.global_transform = Transform3D(Basis(-right, up, -normal), mirrored)
	var to_centre: Vector3 = centre - mirrored
	_camera.set_frustum(size.y, Vector2(to_centre.dot(-right), to_centre.dot(up)), distance, 60.0)


## The world's environment, minus the steps the main view applies anyway:
## the reflection is tonemapped, graded and bloomed once, on screen.
func _reflection_environment() -> Environment:
	var world_env: Environment = get_world_3d().environment
	if world_env == null:
		return null
	var env := world_env.duplicate() as Environment
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false
	env.adjustment_enabled = false
	# Volumetric fog does not follow the off-axis frustum and smears bright
	# blotches across the glass; plain depth fog still hazes the room.
	env.volumetric_fog_enabled = false
	return env
