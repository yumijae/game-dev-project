class_name Viewmodel
extends Node3D
## Juan's own arms in the first-person view, and whatever he holds in them.
##
## A whole Quaternius mannequin hangs under the camera with its head bone at
## the eye. Its head, neck and legs are collapsed to nothing every frame, and
## a pose modifier lifts the arms into a "ready" carry so the hands sit in the
## lower corners of the view; action clips (reaching, throwing, working) drive
## the arms themselves for as long as they play.
##
## Everything here is drawn with a shader that pulls its depth up close to
## the lens without changing where it lands on screen, so the hands never
## sink into a wall Juan is pressed against. It lives on its own render layer
## that the mirrors, the CCTV and the peek / jumpscare cameras leave out.

## Render layer 16 (bit 15): only Juan's own camera draws it.
const LAYER: int = 1 << 15
const MODEL: PackedScene = preload("res://models/quaternius/ual/ual_standard.glb")

const SKIN: Color = Color(0.62, 0.43, 0.30)
const SKIN_ROUGHNESS: float = 0.6
const POLO: Color = Color(0.9, 0.9, 0.88)
const POLO_ROUGHNESS: float = 0.85

## Where the eye sits in the model's own frame, relative to the head bone
## (+Z is the way the model faces). A little low and back, so the short
## mannequin arms reach far enough into the view.
const EYE_OFFSET: Vector3 = Vector3(0.0, 0.02, -0.06)
## Crossfade between clips.
const BLEND: float = 0.2
## How fast an arm hands over between the carry pose and a clip (per second).
const ARM_BLEND_RATE: float = 5.0

## Carry pose, for the right arm in the model's frame (+X is inward for the
## right arm, +Y up, +Z ahead). Low: hands just peeking in at the bottom
## corners; high: an item held up where he can see it.
const UPPER_LOW: Vector3 = Vector3(-0.12, -0.85, 0.5)
const UPPER_HIGH: Vector3 = Vector3(-0.1, -0.6, 0.8)
const FORE_LOW: Vector3 = Vector3(0.06, -0.15, 1.0)
const FORE_HIGH: Vector3 = Vector3(0.1, 0.22, 0.95)
## Working pose for timed jobs (barricading, first aid, the gate): both hands
## brought together low in front, busy. None of the clips does this without
## kneeling or reaching off screen, so it is posed here.
const UPPER_WORK: Vector3 = Vector3(-0.02, -0.6, 0.8)
const FORE_WORK: Vector3 = Vector3(0.55, 0.05, 0.85)

## The shader: projection is untouched, but each vertex is slid along its own
## line of sight towards the lens, so it lands on the same pixel at a depth
## a wall cannot be in front of. Lighting still uses the true position.
const SHADER_CODE: String = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque%s;

uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.6;
uniform float metallic = 0.0;
uniform float depth_scale = 0.15;
uniform float depth_bias = 0.055;

void vertex() {
	vec3 view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = -view.z;
	if (d > 0.001) {
		view *= (depth_bias + d * depth_scale) / d;
	}
	POSITION = PROJECTION_MATRIX * vec4(view, 1.0);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;%s
}
"""

static var _opaque_shader: Shader = null
static var _clear_shader: Shader = null

## Clip and speed per base state. Crouching keeps the standing clips: the
## crouch clips hunch the shoulders so far forward that the arms splay out
## of the bottom corners, and the camera already does the ducking.
enum Base { IDLE, WALK, SPRINT, CROUCH_IDLE, CROUCH_WALK, TORCH, CHANNEL }
const BASE_CLIPS: Dictionary[int, StringName] = {
	Base.IDLE: &"Idle", Base.WALK: &"Walk", Base.SPRINT: &"Sprint",
	Base.CROUCH_IDLE: &"Idle", Base.CROUCH_WALK: &"Walk",
	Base.TORCH: &"Idle_Torch", Base.CHANNEL: &"Idle",
}
const BASE_SPEEDS: Dictionary[int, float] = {
	Base.IDLE: 1.0, Base.WALK: 1.0, Base.SPRINT: 1.0, Base.CROUCH_IDLE: 0.8,
	Base.CROUCH_WALK: 0.6, Base.TORCH: 1.0, Base.CHANNEL: 1.0,
}

var _player: PlayerController = null
var _pivot: Node3D = null
var _skeleton: Skeleton3D = null
var _anim: AnimationPlayer = null
var _pose: ArmPose = null
var _skin_material: ShaderMaterial = null
var _hands: Array[BoneAttachment3D] = [null, null]
var _held_ids: Array[StringName] = [&"", &""]
var _base: int = -1
## The one-shot clip playing over the base state, and how long it has left.
var _action: StringName = &""
var _action_left: float = 0.0
## Which arms the one-shot drives itself: [left, right].
var _action_arms: Array[bool] = [false, false]
## The hand that just threw shows nothing for this long.
var _hide_item_for: float = 0.0
var _bob_phase: float = 0.0


func setup(player: PlayerController) -> void:
	_player = player


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var model: Node3D = MODEL.instantiate()
	# The model faces +Z; the camera looks down -Z.
	model.rotation.y = PI
	_pivot.add_child(model)
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	_skin_material = make_material(SKIN, SKIN_ROUGHNESS)
	var joints: ShaderMaterial = make_material(SKIN.darkened(0.08), SKIN_ROUGHNESS)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface: int in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, _skin_material if surface == 0 else joints)
		_prepare_mesh(mesh)
	_add_sleeve(&"DEF-upper_arm.L")
	_add_sleeve(&"DEF-upper_arm.R")
	for side: int in 2:
		var hand := BoneAttachment3D.new()
		hand.name = "HandL" if side == InventoryComponent.LEFT_HAND else "HandR"
		hand.bone_name = "DEF-hand.L" if side == InventoryComponent.LEFT_HAND else "DEF-hand.R"
		_skeleton.add_child(hand)
		_hands[side] = hand
	_pose = ArmPose.new()
	_pose.name = "ArmPose"
	_pose.viewmodel = self
	_skeleton.add_child(_pose)
	_pose.bind(_skeleton)
	EventBus.inventory_changed.connect(_refresh_held)
	EventBus.item_used.connect(_on_item_used)
	EventBus.player_wounded.connect(_on_wounded.unbind(1))
	if _player != null:
		_player.interacted.connect(_on_interacted)
	_refresh_held.call_deferred()
	_set_base(Base.IDLE, 0.0)


## A no-clip material for anything drawn as part of the arms.
static func make_material(colour: Color, roughness: float, metallic: float = 0.0) -> ShaderMaterial:
	if _opaque_shader == null:
		_opaque_shader = Shader.new()
		_opaque_shader.code = SHADER_CODE % ["", ""]
		_clear_shader = Shader.new()
		_clear_shader.code = SHADER_CODE % [", blend_mix", "\n\tALPHA = albedo.a;"]
	var material := ShaderMaterial.new()
	material.shader = _clear_shader if colour.a < 1.0 else _opaque_shader
	material.set_shader_parameter(&"albedo", colour)
	material.set_shader_parameter(&"roughness", roughness)
	material.set_shader_parameter(&"metallic", metallic)
	return material


func _prepare_mesh(mesh: MeshInstance3D) -> void:
	mesh.layers = LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Its true place can be well off screen while it draws right in front.
	mesh.extra_cull_margin = 1.0


## A short white polo sleeve over the top of the upper arm.
func _add_sleeve(bone: StringName) -> void:
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	_skeleton.add_child(attach)
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.08
	cylinder.bottom_radius = 0.066
	cylinder.height = 0.14
	cylinder.radial_segments = 12
	cylinder.rings = 1
	var sleeve := MeshInstance3D.new()
	sleeve.mesh = cylinder
	# The bone runs along its own +Y from the shoulder.
	sleeve.position = Vector3(0.0, 0.065, 0.0)
	sleeve.material_override = make_material(POLO, POLO_ROUGHNESS)
	_prepare_mesh(sleeve)
	attach.add_child(sleeve)


# ------------------------------------------------------------------- state

func _process(delta: float) -> void:
	var show: bool = _should_show()
	if visible != show:
		visible = show
		_anim.active = show
	if not show:
		return
	_action_left -= delta
	if _action != &"" and _action_left <= 0.0:
		_action = &""
		_action_arms = [false, false]
		_base = -1
	var moving: bool = Vector2(_player.velocity.x, _player.velocity.z).length() > 0.4
	var base: int = Base.IDLE
	if _player.is_channeling():
		base = Base.CHANNEL
	elif _player.phone.is_flashlight_on or _player.phone.is_phone_out:
		# The phone hand stays up whatever his legs are doing.
		base = Base.TORCH
	elif _player.is_crouching:
		base = Base.CROUCH_WALK if moving else Base.CROUCH_IDLE
	elif moving and _player.is_sprinting:
		base = Base.SPRINT
	elif moving:
		base = Base.WALK
	var working: bool = base == Base.CHANNEL
	if working and _action != &"":
		_action = &""
		_action_arms = [false, false]
	if _action == &"" and base != _base:
		_set_base(base, BLEND)
	# Which arms the clip drives, and which are posed: the phone hand (left)
	# is raised by the torch clip.
	for side: int in 2:
		var clip_driven: bool = _action_arms[side]
		if side == InventoryComponent.LEFT_HAND and base == Base.TORCH and _action == &"":
			clip_driven = true
		var target: float = 0.0 if clip_driven else 1.0
		_pose.weights[side] = move_toward(_pose.weights[side], target, ARM_BLEND_RATE * delta)
		var lift: float = 1.0 if _held_ids[side] != &"" else 0.35
		_pose.lifts[side] = lerpf(_pose.lifts[side], lift, minf(1.0, delta * 6.0))
	_pose.work = move_toward(_pose.work, 1.0 if working else 0.0, ARM_BLEND_RATE * 0.6 * delta)
	# A gentle sway of the carried hands as he walks; a quicker fiddle while
	# his hands are busy.
	var speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	_bob_phase = fmod(_bob_phase + delta * (speed * 2.2 + (7.0 if working else 0.0)), TAU)
	_pose.sway = sin(_bob_phase) * clampf(speed / 5.0 + (0.6 if working else 0.0), 0.0, 1.0)
	if _hide_item_for > 0.0:
		_hide_item_for -= delta
		if _hide_item_for <= 0.0:
			_hands[0].visible = true
			_hands[1].visible = true


func _should_show() -> bool:
	if _player == null or not GameSettings.show_arms:
		return false
	if _player.is_dead or _player.is_hidden or _player.is_peeking or _player.ui_focus != null:
		return false
	var camera: Camera3D = get_parent() as Camera3D
	return camera == null or camera.current


func _set_base(base: int, blend: float) -> void:
	_base = base
	_anim.play(BASE_CLIPS[base], blend, BASE_SPEEDS[base])


## Plays a clip once over the base state. `arms` [left, right] says which
## arms the clip moves itself; the others stay in the carry pose.
func play_action(clip: StringName, arms: Array[bool], speed: float = 1.0) -> void:
	if not visible or _player.is_channeling():
		return
	_action = clip
	_action_arms = arms
	_anim.play(clip, BLEND, speed)
	_action_left = maxf(0.1, _anim.get_animation(clip).length / speed - BLEND)


func _on_interacted(target: Node) -> void:
	if target is WorldItem:
		# PickUp_Table reaches down below the view; the plain reach reads better.
		play_action(&"Interact", [true, false], 2.0)
	else:
		play_action(&"Interact", [true, false], 1.6)


func _on_item_used(item_id: StringName) -> void:
	match item_id:
		ItemDB.GLASS_BOTTLE:
			# The cross is a right-hand throw; the bottle has left the hand at
			# the clip's full reach.
			play_action(&"Punch_Cross", [false, true], 1.3)
			_hands[_player.inventory.active_hand].visible = false
			_hide_item_for = 0.6
		ItemDB.FIRE_EXTINGUISHER, ItemDB.TASER:
			play_action(&"Pistol_Shoot", [true, true], 1.0)
		ItemDB.WATER:
			play_action(&"Interact", [true, false], 1.6)


func _on_wounded() -> void:
	play_action(&"Hit_Chest", [false, false], 1.0)


# ------------------------------------------------------------------- items

func _refresh_held() -> void:
	if _player == null or _player.inventory == null:
		return
	for side: int in 2:
		var item_id: StringName = _player.inventory.get_slot_id(side)
		if item_id == _held_ids[side]:
			continue
		_held_ids[side] = item_id
		var hand: BoneAttachment3D = _hands[side]
		for child: Node in hand.get_children():
			child.queue_free()
		if item_id != &"":
			hand.add_child(_build_held(item_id, side))


## The item as it sits in the palm: its long axis across the hand, centred
## on the grip.
func _build_held(item_id: StringName, side: int) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Held"
	var model: Node3D = ItemModel.build(item_id)
	holder.add_child(model)
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var source := mesh.material_override as StandardMaterial3D
		if source != null:
			mesh.material_override = make_material(source.albedo_color, source.roughness, source.metallic)
		_prepare_mesh(mesh)
	var bounds := AABB()
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = _local_transform(model, mesh) * mesh.get_aabb()
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	var size: Vector3 = bounds.size
	# Upright items grip along their Y; long flat ones (crowbar, cutters)
	# along their X, so turn those to stand up first.
	if size.x > size.y and size.x >= size.z:
		model.basis = Basis(Vector3.BACK, PI * 0.5)
	model.position = -(model.basis * bounds.get_center())
	# The hand bone runs along its +Y to the fingers; the grip crosses the
	# palm along its X, and the palm faces its +Z.
	var mirror: float = 1.0 if side == InventoryComponent.RIGHT_HAND else -1.0
	holder.basis = Basis(Vector3.RIGHT, PI * 0.5 * mirror)
	holder.position = Vector3(0.0, 0.07, 0.035)
	return holder


static func _local_transform(root: Node3D, node: Node3D) -> Transform3D:
	var xform: Transform3D = Transform3D.IDENTITY
	var at: Node = node
	while at != null and at != root:
		if at is Node3D:
			xform = (at as Node3D).transform * xform
		at = at.get_parent()
	return xform


# --------------------------------------------------------------- pose hook

## Called by ArmPose once the clip has posed the skeleton this frame: puts
## the eye at the camera.
func _place(head: Vector3) -> void:
	_pivot.position = -(Basis(Vector3.UP, PI) * (head + EYE_OFFSET))


## Runs after the AnimationPlayer every frame: collapses what Juan cannot see
## of himself, lifts the arms into the carry pose, and keeps the eye on the
## camera.
class ArmPose extends SkeletonModifier3D:
	var viewmodel: Viewmodel = null
	## [left, right]: 1 = carry pose, 0 = the clip's own arm.
	var weights: Array[float] = [1.0, 1.0]
	## [left, right]: 0 = hands low, 1 = held up.
	var lifts: Array[float] = [0.35, 0.35]
	var sway: float = 0.0
	## 0..1: blend into the working pose.
	var work: float = 0.0
	var _collapse: PackedInt32Array = []
	var _head: int = -1
	var _upper: PackedInt32Array = []
	var _fore: PackedInt32Array = []

	func bind(skeleton: Skeleton3D) -> void:
		_head = skeleton.find_bone("DEF-head")
		for bone: String in ["DEF-neck", "DEF-thigh.L", "DEF-thigh.R"]:
			_collapse.append(skeleton.find_bone(bone))
		_upper = PackedInt32Array([skeleton.find_bone("DEF-upper_arm.L"), skeleton.find_bone("DEF-upper_arm.R")])
		_fore = PackedInt32Array([skeleton.find_bone("DEF-forearm.L"), skeleton.find_bone("DEF-forearm.R")])

	func _process_modification() -> void:
		var skeleton: Skeleton3D = get_skeleton()
		if skeleton == null or _head < 0:
			return
		viewmodel._place(skeleton.get_bone_global_pose(_head).origin)
		for bone: int in _collapse:
			skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.001)
		for side: int in 2:
			var weight: float = weights[side]
			if weight <= 0.001:
				continue
			# Mirror the right-arm pose for the left (+X is the model's left).
			var flip: float = -1.0 if side == InventoryComponent.LEFT_HAND else 1.0
			var lift: float = lifts[side]
			var swing: float = sway * (1.0 if side == InventoryComponent.LEFT_HAND else -1.0)
			var upper: Vector3 = UPPER_LOW.lerp(UPPER_HIGH, lift).lerp(UPPER_WORK, work) + Vector3(0.0, 0.02 * swing, 0.06 * swing)
			var fore: Vector3 = FORE_LOW.lerp(FORE_HIGH, lift).lerp(FORE_WORK, work) + Vector3(0.0, (0.05 + 0.1 * work) * swing, 0.0)
			upper.x *= flip
			fore.x *= flip
			var bone: int = _upper[side]
			var parent: Transform3D = skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
			var upper_pose: Transform3D = _aim(skeleton, bone, parent, upper.normalized(), weight)
			_aim(skeleton, _fore[side], upper_pose, fore.normalized(), weight)

	## Turns `bone` so it points along `direction` (skeleton space), blended
	## by `weight`, and returns its new global pose.
	func _aim(skeleton: Skeleton3D, bone: int, parent: Transform3D, direction: Vector3, weight: float) -> Transform3D:
		var local: Transform3D = skeleton.get_bone_pose(bone)
		var current: Basis = parent.basis * local.basis
		var arc := Quaternion(current.y.normalized(), direction)
		var aimed: Basis = parent.basis.inverse() * (Basis(arc) * current)
		var from: Quaternion = local.basis.get_rotation_quaternion()
		var rotation: Quaternion = from.slerp(aimed.get_rotation_quaternion(), weight)
		skeleton.set_bone_pose_rotation(bone, rotation)
		return parent * Transform3D(Basis(rotation), local.origin)
