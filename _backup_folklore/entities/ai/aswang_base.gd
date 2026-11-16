class_name AswangBase
extends CharacterBody3D
## Shared senses and locomotion for the three Aswang of "Huling Kampana".
##
## Sight   - range, field of view and a raycast, plus the wide-lab-glass rule:
##           through a CorridorViewingGlass bay Juan is visible only while he
##           stands above the 1.0 m half-wall.
## Hearing - NoiseManager radius maths (slabs dampen, stairwells carry).
## Smell   - ScentManager breadcrumbs, followed oldest to newest.
## Subclasses implement _tick() and their own state machines.

const LAYER_ASWANG: int = 32
const MOVE_MASK: int = 1 | 8 | 16
const SIGHT_MASK: int = 1 | 8
## Eye height used when looking over a lab half-wall.
const GLASS_EYE_HEIGHT: float = 1.6
const ATTACK_COOLDOWN: float = 2.5
const SELF_NOISE_RADIUS: float = 2.2
const REPATH_INTERVAL: float = 0.3
const FLESH_SHADER: Shader = preload("res://shaders/aswang_flesh.gdshader")
const MEMBRANE_SHADER: Shader = preload("res://shaders/aswang_membrane.gdshader")
const DISSOLVE_TIME: float = 1.6
## A jump larger than this in one frame is a teleport, not a stride.
const ANIM_MAX_SPEED: float = 20.0
## How quickly the rendered figure catches up with the physics body.
const SMOOTH_RATE: float = 26.0

@export var aswang_id: StringName = &"aswang"
@export var display_name: String = "The Aswang"
@export var eye_height: float = 1.5
@export var vision_range: float = 14.0
@export var vision_fov: float = 130.0
## Multiplies the radius of every noise this creature listens to.
@export var hearing: float = 1.0
@export var sniff_radius: float = 9.0
@export var catch_distance: float = 1.15

var player: PlayerController = null
var is_active: bool = false
var is_dead: bool = false
var stun_time_left: float = 0.0
var blind_time_left: float = 0.0
var attack_cooldown: float = 0.0
var state_name: StringName = &"DORMANT"
var nav: NavigationAgent3D = null
var visual: Node3D = null
var body_shape: CollisionShape3D = null
## The viewing bay the last successful sight line passed through, if any.
var last_sight_glass: CorridorViewingGlass = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _repath_timer: float = 0.0
var _desired_direction: Vector3 = Vector3.FORWARD
var _last_crumb_serial: int = 0
var _flesh: Array[ShaderMaterial] = []
var _fx_tween: Tween = null

## Animation inputs, measured from how the body actually moved so they work
## for walking, crawling and flying alike.
var anim_speed: float = 0.0
## Metres travelled; drives stride cycles so feet keep pace with the ground.
var anim_distance: float = 0.0
var anim_time: float = 0.0
## Smoothed turning rate in radians per second; positive is to the left.
var anim_turn: float = 0.0
## Jumps to 1 when a blow is thrown and decays, for lunges and swipes.
var anim_strike: float = 0.0
var _anim_last_position: Vector3 = Vector3.ZERO
var _anim_last_yaw: float = 0.0
var _smooth: Node3D = null
var _smooth_snap: bool = true
var _sways: Array[Sway] = []


## A soft body part driven by a spring. See add_sway().
class Sway:
	var part: MeshInstance3D = null
	var material: ShaderMaterial = null
	var spring := AswangRig.Spring.new()
	var last_position: Vector3 = Vector3.ZERO
	var primed: bool = false
	var length: float = 0.5
	var drag: float = 0.1
	var stiffness: float = 60.0
	var damping: float = 7.0


func _ready() -> void:
	add_to_group(&"aswang")
	collision_layer = LAYER_ASWANG
	collision_mask = MOVE_MASK
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(55.0)
	var capsule := CapsuleShape3D.new()
	# Must stay below the navmesh agent radius (0.25, tools/build_level.gd)
	# or they get wedged in gaps the navmesh says are open.
	capsule.radius = 0.24
	capsule.height = 1.7
	body_shape = CollisionShape3D.new()
	body_shape.shape = capsule
	body_shape.position.y = 0.85
	add_child(body_shape)
	nav = NavigationAgent3D.new()
	nav.path_desired_distance = 0.45
	nav.target_desired_distance = 0.55
	nav.radius = 0.25
	nav.height = 1.7
	nav.path_max_distance = 3.0
	add_child(nav)
	_smooth = Node3D.new()
	_smooth.name = "Smooth"
	_smooth.top_level = true
	add_child(_smooth)
	visual = Node3D.new()
	visual.name = "Visual"
	_smooth.add_child(visual)
	_build_visual()
	EventBus.noise_emitted.connect(_on_noise_emitted)
	visible = false
	body_shape.disabled = true


# ------------------------------------------------------------------ lifecycle

## Wakes the creature at a position. Called at midnight.
func activate(at: Vector3) -> void:
	player = get_tree().get_first_node_in_group(&"player") as PlayerController
	global_position = at
	is_active = true
	is_dead = false
	visible = true
	set_flesh_parameter(0.0, &"dissolve")
	set_flesh_parameter(0.0, &"burn")
	body_shape.disabled = false
	add_to_group(&"aswang_presence")
	_on_activated()


## A live, hunting creature (not dormant, not destroyed).
func is_threatening() -> bool:
	return is_active and not is_dead


func is_incapacitated() -> bool:
	return stun_time_left > 0.0 or blind_time_left > 0.0


## Burned by salt (or any other hard stop). The creature cannot act.
func stun(duration: float, _reason: StringName = &"") -> void:
	if not is_threatening():
		return
	stun_time_left = maxf(stun_time_left, duration)
	velocity = Vector3.ZERO
	set_flesh_parameter(1.0, &"burn")
	SfxSynth.play_at(self, SfxSynth.growl(), global_position + Vector3.UP, 4.0, 1.5)
	EventBus.aswang_stunned.emit(aswang_id, duration)
	set_state(&"STUNNED")
	_on_stunned()


## Sinamak in the eyes: blind, and the chase is forgotten.
func blind(duration: float) -> void:
	if not is_threatening():
		return
	blind_time_left = maxf(blind_time_left, duration)
	velocity = Vector3.ZERO
	set_flesh_parameter(0.6, &"burn")
	SfxSynth.play_at(self, SfxSynth.growl(), global_position + Vector3.UP, 4.0, 1.7)
	set_state(&"BLINDED")
	_on_blinded()


func die() -> void:
	if is_dead:
		return
	is_dead = true
	is_active = false
	remove_from_group(&"aswang_presence")
	body_shape.set_deferred("disabled", true)
	set_state(&"DEAD")
	# Burn away rather than blink out.
	set_flesh_parameter(1.0, &"burn")
	if _fx_tween != null:
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.tween_method(set_flesh_parameter.bind(&"dissolve"), 0.0, 1.0, DISSOLVE_TIME)
	_fx_tween.tween_callback(hide)


## Sets a uniform on every body part (value first, so tweens can bind the name).
func set_flesh_parameter(value: float, parameter: StringName) -> void:
	for material: ShaderMaterial in _flesh:
		material.set_shader_parameter(parameter, value)


func set_state(new_state: StringName) -> void:
	if new_state == state_name:
		return
	state_name = new_state
	EventBus.aswang_state_changed.emit(aswang_id, new_state)


func get_aggression() -> float:
	return TimeManager.get_aggression_multiplier()


## What Juan sees of this creature through the gap under a door.
func get_feet_description() -> String:
	return "Something is standing outside. Those are not human feet."


func _physics_process(delta: float) -> void:
	if not is_threatening():
		return
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	if stun_time_left > 0.0:
		stun_time_left -= delta
		_incapacitated_tick(delta)
		if stun_time_left <= 0.0:
			_on_recovered()
		return
	if blind_time_left > 0.0:
		blind_time_left -= delta
		_incapacitated_tick(delta)
		if blind_time_left <= 0.0:
			_on_recovered()
		return
	_tick(delta)


func _process(delta: float) -> void:
	if not visible or delta <= 0.0:
		_anim_last_position = global_position
		_anim_last_yaw = rotation.y
		_smooth_snap = true
		return
	var speed: float = global_position.distance_to(_anim_last_position) / delta
	_anim_last_position = global_position
	if speed > ANIM_MAX_SPEED:
		speed = 0.0
		_smooth_snap = true
	anim_speed = lerpf(anim_speed, speed, minf(delta * 8.0, 1.0))
	anim_distance += anim_speed * delta
	anim_time += delta
	var turn: float = wrapf(rotation.y - _anim_last_yaw, -PI, PI) / delta
	_anim_last_yaw = rotation.y
	anim_turn = lerpf(anim_turn, clampf(turn, -6.0, 6.0), minf(delta * 6.0, 1.0))
	anim_strike = move_toward(anim_strike, 0.0, delta * 2.2)
	# The body is moved in 60 Hz physics steps; the rendered figure glides
	# after it so it does not judder on a faster display or snap when turning.
	if _smooth_snap:
		_smooth_snap = false
		_smooth.global_transform = global_transform
	else:
		_smooth.global_transform = _smooth.global_transform.interpolate_with(global_transform, 1.0 - exp(-delta * SMOOTH_RATE))
	_animate(delta)
	_update_sways(delta)


## Makes a soft part trail behind movement and hang plumb however the body
## leans. `length` is how far along the strand (metres) the full sway applies.
func add_sway(part: MeshInstance3D, length: float, drag: float = 0.1, stiffness: float = 60.0, damping: float = 7.0,
		writhe: float = 0.0) -> void:
	var sway := Sway.new()
	sway.part = part
	sway.material = part.material_override as ShaderMaterial
	sway.length = length
	sway.drag = drag
	sway.stiffness = stiffness
	sway.damping = damping
	sway.material.set_shader_parameter(&"sway_length", length)
	sway.material.set_shader_parameter(&"writhe", writhe)
	_sways.append(sway)


func _update_sways(delta: float) -> void:
	for sway: Sway in _sways:
		var at: Vector3 = sway.part.global_position
		var basis: Basis = sway.part.global_transform.basis.orthonormalized()
		var velocity: Vector3 = (at - sway.last_position) / delta if sway.primed else Vector3.ZERO
		sway.last_position = at
		sway.primed = true
		if velocity.length() > ANIM_MAX_SPEED:
			velocity = Vector3.ZERO
		# Dragged back by movement, and pulled from wherever the body points
		# its "down" towards the real one.
		var target: Vector3 = -velocity * sway.drag + (Vector3.DOWN + basis.y) * sway.length * 0.6
		var offset: Vector3 = sway.spring.step(target, sway.stiffness, sway.damping, delta)
		sway.material.set_shader_parameter(&"sway", basis.inverse() * offset.limit_length(sway.length * 0.9))


# ------------------------------------------------------- virtuals for children

func _build_visual() -> void:
	pass


## Poses the body every rendered frame while visible. Purely cosmetic.
func _animate(_delta: float) -> void:
	pass


func _on_activated() -> void:
	pass


## Called every physics frame while awake and able to act.
func _tick(_delta: float) -> void:
	pass


## Called every physics frame while stunned or blinded.
func _incapacitated_tick(delta: float) -> void:
	ground_idle(delta)
	visual.rotation.z = sin(float(Time.get_ticks_msec()) * 0.02) * 0.12


func _on_stunned() -> void:
	pass


func _on_blinded() -> void:
	pass


func _on_recovered() -> void:
	visual.rotation.z = 0.0
	set_flesh_parameter(0.0, &"burn")


## A noise this creature could actually hear. `audibility` is 0..1.
func _on_heard(_origin: Vector3, _noise_type: StringName, _audibility: float) -> void:
	pass


# --------------------------------------------------------------------- senses

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * eye_height


func get_player_distance() -> float:
	if player == null:
		return INF
	return global_position.distance_to(player.global_position)


## Full sight test: concealment, range (scaled by how visible Juan makes
## himself), field of view, the lab-glass half-wall rule, then a raycast.
func can_see_player() -> bool:
	last_sight_glass = null
	if player == null or player.is_dead or player.is_concealed() or blind_time_left > 0.0:
		return false
	var eye: Vector3 = get_eye_position()
	var head: Vector3 = player.get_head_position()
	var to_head: Vector3 = head - eye
	var distance: float = to_head.length()
	if distance > vision_range * player.get_visibility_factor():
		return false
	if distance > 2.0:
		var forward: Vector3 = -global_transform.basis.z
		var flat := Vector3(to_head.x, 0.0, to_head.z)
		if flat.length() > 0.1 and rad_to_deg(forward.angle_to(flat)) > vision_fov * 0.5:
			return false
	var glass: CorridorViewingGlass = CorridorViewingGlass.find_crossed(get_tree(), eye, head)
	if glass != null:
		if not glass.allows_sight(player.is_crouching):
			return false
		# Rear up (or stand back) far enough to look over the half-wall.
		eye.y = maxf(eye.y, glass.get_sill_y() - CorridorViewingGlass.SILL_HEIGHT + GLASS_EYE_HEIGHT)
	var query := PhysicsRayQueryParameters3D.create(eye, head, SIGHT_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return false
	last_sight_glass = glass
	return true


## The next scent crumb worth walking to, or null.
func sniff_trail() -> ScentBreadcrumb:
	var crumb: ScentBreadcrumb = ScentManager.find_next_breadcrumb(global_position, sniff_radius * get_aggression(),
		_last_crumb_serial)
	return crumb


func remember_crumb(crumb: ScentBreadcrumb) -> void:
	_last_crumb_serial = maxi(_last_crumb_serial, crumb.serial)


func _on_noise_emitted(origin: Vector3, radius: float, noise_type: StringName, source: Node) -> void:
	if not is_threatening() or is_incapacitated():
		return
	if source is AswangBase or origin.distance_to(global_position) < SELF_NOISE_RADIUS:
		return
	var ears: Vector3 = get_eye_position()
	if NoiseManager.can_hear(ears, origin, radius, hearing):
		_on_heard(origin, noise_type, NoiseManager.get_audibility(ears, origin, radius, hearing))


# ----------------------------------------------------------------- locomotion

## Walks the navmesh towards `target`. Returns true on arrival (or when the
## path simply ends).
func nav_move_to(target: Vector3, speed: float, delta: float) -> bool:
	_repath_timer -= delta
	if _repath_timer <= 0.0 or nav.target_position.distance_to(target) > 1.0:
		nav.target_position = target
		_repath_timer = REPATH_INTERVAL
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var level: bool = absf(target.y - global_position.y) < 1.3
	if flat.length() < 0.6 and level:
		ground_idle(delta)
		return true
	var next: Vector3
	if nav.is_navigation_finished():
		# The path ran out a step short (the target is wedged against
		# furniture): close the last metre or two directly, sliding along
		# whatever is in the way, instead of standing there out of reach.
		if not level or flat.length() > 2.0 or not _clear_step_to(target):
			ground_idle(delta)
			return true
		next = target
	else:
		next = nav.get_next_path_position()
	var direction := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	if direction.length() > 0.01:
		direction = direction.normalized()
		_desired_direction = direction
		velocity.x = move_toward(velocity.x, direction.x * speed, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, speed * 8.0 * delta)
		face_direction(direction, delta)
	_apply_gravity(delta)
	move_and_slide()
	return false


## Nothing solid between this body and `target` at knee and waist height, so
## stepping straight at it will not just grind against a wall.
func _clear_step_to(target: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	for height: float in [0.35, 0.9]:
		var lift := Vector3.UP * height
		var query := PhysicsRayQueryParameters3D.create(global_position + lift,
			Vector3(target.x, global_position.y, target.z) + lift, MOVE_MASK)
		query.exclude = [get_rid()]
		if not space.intersect_ray(query).is_empty():
			return false
	return true


## Stands still on the ground.
func ground_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	_apply_gravity(delta)
	move_and_slide()


func face_direction(direction: Vector3, delta: float, turn_speed: float = 9.0) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return
	var target_yaw: float = atan2(-flat.x, -flat.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))


func face_point(point: Vector3, delta: float) -> void:
	face_direction(point - global_position, delta)


## The closed door standing in the way of where this creature wants to go.
func find_blocking_door(reach: float = 1.4) -> InteractableDoor:
	for node: Node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as InteractableDoor
		if door == null or door.is_passable():
			continue
		var center: Vector3 = door.get_center()
		if absf(center.y - global_position.y) > 1.2:
			continue
		var to_door := Vector3(center.x - global_position.x, 0.0, center.z - global_position.z)
		if to_door.length() > reach:
			continue
		if to_door.length() > 0.3 and to_door.normalized().dot(_desired_direction) < 0.25:
			continue
		return door
	return null


## Strikes Juan if he is within reach. Returns true when a blow landed.
func try_attack_player() -> bool:
	if player == null or player.is_dead or attack_cooldown > 0.0:
		return false
	var reach_point: Vector3 = player.global_position + Vector3.UP * 0.8
	if (global_position + Vector3.UP * 0.8).distance_to(reach_point) > catch_distance:
		return false
	attack_cooldown = ATTACK_COOLDOWN
	anim_strike = 1.0
	SfxSynth.play_at(self, SfxSynth.growl(), global_position + Vector3.UP, 6.0)
	var fatal: bool = player.take_attack(self)
	_on_attack_landed(fatal)
	return true


func _on_attack_landed(_fatal: bool) -> void:
	pass


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta


# -------------------------------------------------------------- visual helpers

func add_part(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, glow: float = 0.0,
		shader: Shader = FLESH_SHADER) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(&"albedo", color)
	material.set_shader_parameter(&"glow", glow)
	_flesh.append(material)
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part


## Adds everything accumulated in `builder` as one body part. `look` overrides
## flesh shader uniforms, e.g. {"wet": 0.8, "gaunt": 0.6}.
func add_flesh(parent: Node3D, builder: AswangMesh, color: Color, look: Dictionary = {}) -> MeshInstance3D:
	var part: MeshInstance3D = add_part(parent, builder.commit(), Vector3.ZERO, color)
	var material := part.material_override as ShaderMaterial
	for key: String in look:
		material.set_shader_parameter(key, look[key])
	return part


## A glowing eye sunk in a dark socket.
func add_eye(parent: Node3D, at: Vector3, radius: float, color: Color, glow: float) -> void:
	var socket: MeshInstance3D = add_part(parent, sphere_mesh(radius * 1.9), at + Vector3(0.0, 0.0, radius * 1.2),
		Color(0.015, 0.01, 0.01))
	(socket.material_override as ShaderMaterial).set_shader_parameter(&"breathe", 0.0)
	var eye: MeshInstance3D = add_part(parent, sphere_mesh(radius), at, color, glow)
	var material := eye.material_override as ShaderMaterial
	material.set_shader_parameter(&"bump", 0.0)
	material.set_shader_parameter(&"breathe", 0.0)
	material.set_shader_parameter(&"veins", 0.0)
	material.set_shader_parameter(&"wet", 1.0)


## Bends a wing (membrane and bones together) towards its tip. See add_wing().
func set_wing_curl(wing: MeshInstance3D, curl: float, span: float) -> void:
	var membrane := wing.material_override as ShaderMaterial
	membrane.set_shader_parameter(&"curl", curl)
	membrane.set_shader_parameter(&"curl_span", span)
	var bones := wing.get_child(0) as MeshInstance3D
	var bone_material := bones.material_override as ShaderMaterial
	bone_material.set_shader_parameter(&"curl", curl)
	bone_material.set_shader_parameter(&"curl_span", span)


## An empty pivot that body parts hang from and the animation turns.
func add_joint(parent: Node3D, at: Vector3, joint_name: String = "Joint") -> Node3D:
	var joint := Node3D.new()
	joint.name = joint_name
	joint.position = at
	parent.add_child(joint)
	return joint


## Wing membrane plus its bones, pivoting at the shoulder. Returns the membrane
## node; the bones ride along as its child.
func add_wing(parent: Node3D, at: Vector3, side: float, span: float, fold: float, membrane_color: Color,
		bone_color: Color) -> MeshInstance3D:
	var meshes: Array[ArrayMesh] = AswangMesh.bat_wing(side, span, fold)
	var wing: MeshInstance3D = add_part(parent, meshes[0], at, membrane_color, 0.0, MEMBRANE_SHADER)
	var bones: MeshInstance3D = add_part(wing, meshes[1], Vector3.ZERO, bone_color)
	(bones.material_override as ShaderMaterial).set_shader_parameter(&"breathe", 0.0)
	return wing


static func capsule_mesh(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	return mesh


static func box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func sphere_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh
