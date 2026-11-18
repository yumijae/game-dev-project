class_name WorldItem
extends Area3D
## A pickup lying in the world. Built from ItemDB so no per-item scenes are
## needed; ItemModel builds what it looks like.

const LAYER_ITEMS: int = 2

@export var item_id: StringName = &""
@export var count: int = 1

## Which way it faces; NAN leaves it at whatever angle it was set down.
var yaw: float = NAN

var _model: Node3D = null


## Creates a pickup under `parent` at a global position.
static func spawn(parent: Node, id: StringName, amount: int, at: Vector3, facing: float = NAN) -> WorldItem:
	var item := WorldItem.new()
	item.item_id = id
	item.count = amount
	item.yaw = facing
	item.name = "Item_%s" % id
	parent.add_child(item)
	item.global_position = at
	return item


func _ready() -> void:
	collision_layer = LAYER_ITEMS
	collision_mask = 0
	monitoring = false
	add_to_group(&"world_items")
	var size: Vector3 = ItemDB.get_size(item_id)
	# The object itself, set down at whatever angle it was left.
	_model = ItemModel.build(item_id)
	_model.position.y = 0.003
	_model.rotation.y = randf() * TAU if is_nan(yaw) else yaw
	add_child(_model)
	var shape := BoxShape3D.new()
	shape.size = size.max(Vector3(0.22, 0.18, 0.22))
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.size.y * 0.5
	add_child(collider)
	if item_id == ItemDB.REHAS_KEY:
		_add_shimmer()
	else:
		set_process(false)


# ------------------------------------------------------------------ shimmer
# The Master Gate Key is tiny and the school is dark: the brass catches the
# light now and then - a faint warm sheen all the time, and every few seconds
# a short glint with a small twinkle. Easy to spot once you look round the
# room, too slight to see from the corridor.

const GLINT_PERIOD: float = 3.2      # seconds between glints (jittered)
const GLINT_LENGTH: float = 0.55     # how long one glint lasts
const SHEEN_ENERGY: float = 0.08     # resting emission on the brass
const GLINT_ENERGY: float = 0.9      # emission at the peak of a glint
const SHEEN_COLOR: Color = Color(1.0, 0.8, 0.42)

var _shimmer_materials: Array[StandardMaterial3D] = []
var _twinkle: MeshInstance3D = null
var _glow: OmniLight3D = null
var _glint_clock: float = 0.0
var _next_glint: float = 0.0


func _add_shimmer() -> void:
	for part: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var material := (part as MeshInstance3D).material_override as StandardMaterial3D
		if material == null:
			continue
		material.emission_enabled = true
		material.emission = SHEEN_COLOR
		material.emission_energy_multiplier = SHEEN_ENERGY
		_shimmer_materials.append(material)
	# A small soft star that blooms over the key during a glint.
	var star_texture := GradientTexture2D.new()
	star_texture.fill = GradientTexture2D.FILL_RADIAL
	star_texture.fill_from = Vector2(0.5, 0.5)
	star_texture.fill_to = Vector2(0.5, 0.0)
	star_texture.width = 64
	star_texture.height = 64
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.95, 0.8, 1.0))
	gradient.set_color(1, Color(1.0, 0.85, 0.5, 0.0))
	gradient.add_point(0.18, Color(1.0, 0.9, 0.65, 0.55))
	star_texture.gradient = gradient
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_material.albedo_texture = star_texture
	star_material.albedo_color = Color(1, 1, 1, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	_twinkle = MeshInstance3D.new()
	_twinkle.name = "Twinkle"
	_twinkle.mesh = quad
	_twinkle.material_override = star_material
	_twinkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_twinkle.position = Vector3(0.0, 0.025, 0.0)
	_twinkle.visible = false
	add_child(_twinkle)
	# A glint throws the faintest flicker of light on what it lies on; off
	# between glints (a steady glow lit up whole shelves like a candle).
	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = SHEEN_COLOR
	_glow.omni_range = 0.25
	_glow.light_energy = 0.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0.0, 0.05, 0.0)
	_glow.visible = false
	add_child(_glow)
	_next_glint = randf_range(0.5, GLINT_PERIOD)


func _process(delta: float) -> void:
	_glint_clock += delta
	var strength: float = 0.0
	if _glint_clock >= _next_glint:
		var t: float = (_glint_clock - _next_glint) / GLINT_LENGTH
		if t >= 1.0:
			_glint_clock = 0.0
			_next_glint = GLINT_PERIOD * randf_range(0.75, 1.3)
		else:
			strength = sin(t * PI)
			strength *= strength
	# A slow breathing under the glints so the sheen never looks switched on.
	var breathe: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.0017)
	var energy: float = SHEEN_ENERGY * (0.7 + 0.3 * breathe) + GLINT_ENERGY * strength
	for material: StandardMaterial3D in _shimmer_materials:
		material.emission_energy_multiplier = energy
	_glow.visible = strength > 0.02
	_glow.light_energy = 0.04 * strength
	_twinkle.visible = strength > 0.02
	if _twinkle.visible:
		var star := _twinkle.material_override as StandardMaterial3D
		star.albedo_color.a = strength * 0.7
		_twinkle.scale = Vector3.ONE * (0.4 + 0.6 * strength)


func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	var label: String = ItemDB.get_item_name(item_id)
	if count > 1:
		label += " x%d" % count
	return [{"id": &"take", "label": "Take %s" % label}]


func interact(player: PlayerController, _action_id: StringName) -> void:
	var leftover: int = player.inventory.add_item(item_id, count)
	if leftover >= count:
		var reason: String = "Both hands are full." if ItemDB.is_hands_only(item_id) else "No room. Drop something first."
		if player.inventory.last_refusal == &"weight":
			reason = "Too heavy - you are already carrying %.1f of %d kg." % [player.inventory.get_load(), int(InventoryComponent.MAX_LOAD)]
		EventBus.ui_notification.emit(reason, 2.5)
		return
	if leftover > 0 and player.inventory.last_refusal == &"weight":
		EventBus.ui_notification.emit("You can only carry %d of them." % (count - leftover), 2.5)
	EventBus.item_picked_up.emit(item_id)
	EventBus.ui_notification.emit("Took %s" % ItemDB.get_item_name(item_id), 1.6)
	if leftover <= 0:
		queue_free()
	else:
		count = leftover
