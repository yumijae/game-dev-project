class_name CorridorViewingGlass
extends StaticBody3D
## One bay of the wide plate-glass viewing window that STI laboratories have
## along the corridor: 2F Computer Labs (#7, #8, #13) and the 4F Culinary
## Kitchen (#24) and Dining room (#27).
##
## The wall under it is a 1.0 m concrete half-wall and the pane runs from 1.0 m
## to 2.8 m. Anything in the corridor sees straight into the lab - unless Juan
## is crouched below the half-wall or behind furniture. A creature that lunges
## through shatters the pane and leaves a large BrokenGlassHazard.

const LAYER_GLASS: int = 16
const SILL_HEIGHT: float = 1.0
const PANE_COLOR: Color = Color(0.75, 0.88, 0.95, 0.22)
# Dark anodised aluminium, the same as every other window frame in the school
# (it was a saturated blue that glowed under the flashlight).
const FRAME_COLOR: Color = Color(0.14, 0.16, 0.19)
const SHATTER_NOISE: float = 20.0
const HAZARD_DEPTH: float = 1.8

@export var width: float = 4.0
@export var height: float = 1.8
@export var room_id: int = 0
## Unit vector pointing from the pane into the lab.
@export var room_side: Vector3 = Vector3.BACK

var is_shattered: bool = false

static var _pane_material: StandardMaterial3D = null
static var _frame_material: StandardMaterial3D = null


## Builds a bay: glass pane, aluminium frame with mullions, and collision.
static func create(bay_width: float, bay_height: float, into_room: Vector3, room: int) -> CorridorViewingGlass:
	var glass := CorridorViewingGlass.new()
	glass.width = bay_width
	glass.height = bay_height
	glass.room_side = into_room
	glass.room_id = room
	glass.collision_layer = LAYER_GLASS
	glass.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(bay_width, bay_height, 0.05)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	glass.add_child(collider)
	var pane_mesh := BoxMesh.new()
	pane_mesh.size = Vector3(bay_width - 0.06, bay_height - 0.06, 0.012)
	pane_mesh.material = _get_pane_material()
	var pane := MeshInstance3D.new()
	pane.name = "Pane"
	pane.mesh = pane_mesh
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.add_child(pane)
	var frame := Node3D.new()
	frame.name = "Frame"
	glass.add_child(frame)
	var rail: float = 0.05
	_add_bar(frame, Vector3(bay_width, rail, 0.09), Vector3(0.0, bay_height * 0.5 - rail * 0.5, 0.0))
	_add_bar(frame, Vector3(bay_width, rail, 0.09), Vector3(0.0, -bay_height * 0.5 + rail * 0.5, 0.0))
	_add_bar(frame, Vector3(rail, bay_height, 0.09), Vector3(-bay_width * 0.5 + rail * 0.5, 0.0, 0.0))
	_add_bar(frame, Vector3(rail, bay_height, 0.09), Vector3(bay_width * 0.5 - rail * 0.5, 0.0, 0.0))
	var panes: int = maxi(2, int(round(bay_width / 1.35)))
	for i: int in range(1, panes):
		var x: float = -bay_width * 0.5 + bay_width * float(i) / float(panes)
		_add_bar(frame, Vector3(0.03, bay_height - rail * 2.0, 0.06), Vector3(x, 0.0, 0.0))
	return glass


func _ready() -> void:
	add_to_group(&"corridor_glass")


## The bay (if any) that a straight sight line between two points passes through.
static func find_crossed(tree: SceneTree, from: Vector3, to: Vector3) -> CorridorViewingGlass:
	for node: Node in tree.get_nodes_in_group(&"corridor_glass"):
		var glass := node as CorridorViewingGlass
		if glass != null and glass.is_crossed_by(from, to):
			return glass
	return null


## True when the segment crosses this bay's wall plane within its width, on
## this floor. Height is ignored on purpose: the half-wall rule decides sight.
func is_crossed_by(from: Vector3, to: Vector3) -> bool:
	var plane_z: float = global_position.z
	var a: float = from.z - plane_z
	var b: float = to.z - plane_z
	if a * b >= 0.0:
		return false
	var point: Vector3 = from.lerp(to, a / (a - b))
	return absf(point.x - global_position.x) <= width * 0.5 and absf(point.y - global_position.y) <= 2.0


## Whether something in the corridor can see a target through this bay.
## A crouched target is below the 1.0 m half-wall and cannot be seen.
func allows_sight(target_is_crouched: bool) -> bool:
	return not target_is_crouched


## Height of the top of the concrete half-wall under the pane.
func get_sill_y() -> float:
	return global_position.y - height * 0.5


## The glass is clear, so flashlight beams pass into the corridor.
func leaks_light() -> bool:
	return not is_shattered


## +1.0 if `pos` is on the lab side of the pane, -1.0 on the corridor side.
func which_side(pos: Vector3) -> float:
	return 1.0 if (pos - global_position).dot(room_side) >= 0.0 else -1.0


## A floor point `distance` metres from the pane (side: +1 lab, -1 corridor).
func get_floor_point(side: float, distance: float) -> Vector3:
	var point: Vector3 = global_position + room_side * side * distance
	point.y = get_sill_y() - SILL_HEIGHT
	return point


## Smashes the pane. Shards land on the side the creature is lunging towards.
func shatter(landing_side: float = 1.0) -> void:
	if is_shattered:
		return
	is_shattered = true
	var pane := get_node_or_null("Pane") as MeshInstance3D
	if pane != null:
		pane.visible = false
	var collider := get_node_or_null("Shape") as CollisionShape3D
	if collider != null:
		collider.set_deferred("disabled", true)
	NoiseManager.emit_noise(global_position, SHATTER_NOISE, &"glass_shatter", self)
	SfxSynth.play_at(self, SfxSynth.glass_shatter(), global_position, 6.0, 0.85)
	BrokenGlassHazard.spawn(get_tree().current_scene, get_floor_point(landing_side, HAZARD_DEPTH * 0.5 + 0.1),
		Vector2(width, HAZARD_DEPTH))
	EventBus.glass_shattered.emit(self, global_position)


static func _add_bar(parent: Node3D, size: Vector3, at: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _get_frame_material()
	var bar := MeshInstance3D.new()
	bar.mesh = mesh
	bar.position = at
	parent.add_child(bar, true)


static func _get_pane_material() -> StandardMaterial3D:
	if _pane_material == null:
		_pane_material = StandardMaterial3D.new()
		_pane_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_pane_material.albedo_color = PANE_COLOR
		_pane_material.roughness = 0.1
		var grime := ShaderMaterial.new()
		grime.shader = load("res://shaders/glass_grime.gdshader")
		grime.set_shader_parameter(&"grime", 0.05)   # cleaned regularly; just a faint film
		_pane_material.next_pass = grime
	return _pane_material


static func _get_frame_material() -> StandardMaterial3D:
	if _frame_material == null:
		_frame_material = StandardMaterial3D.new()
		_frame_material.albedo_color = FRAME_COLOR
		_frame_material.metallic = 0.6
		_frame_material.roughness = 0.45
	return _frame_material
