class_name RobotBase
extends Hostile
## Shared body, senses and locomotion for the Expo Night robots.
##
## Each robot starts the night on a Com Sci Lab charging dock (is_docked),
## wakes at midnight when the rogue firmware finishes, and shuts down when
## WARDEN's circuit loses power (Hostile.on_power_cut) unless it overrides that.
##
## Locomotion walks the baked navmesh (res://school/school_navmesh.res).
## Sight is a range + raycast test; hearing uses NoiseManager's radius maths.
## Subclasses implement kind() and _tick().

const LAYER_ROBOT: int = 32
const MOVE_MASK: int = 1 | 8 | 16
const SIGHT_MASK: int = 1 | 8
const REPATH_INTERVAL: float = 0.3
const ATTACK_COOLDOWN: float = 3.0
## How long a sighting or a sound stays worth following.
const MEMORY_TIME: float = 40.0
const HUNCH_INTERVAL: float = 75.0
const SELF_NOISE_RADIUS: float = 2.2

@export var eye_height: float = 1.6
@export var vision_range: float = 16.0
@export var hearing: float = 1.0
@export var catch_distance: float = 1.15
@export var body_radius: float = 0.24
@export var body_height: float = 1.7

var player: PlayerController = null
var nav: NavigationAgent3D = null
var body_shape: CollisionShape3D = null
## The fitted model (RobotModels), turned to face -Z like the body.
var model: Node3D = null
var state_name: StringName = &"DOCKED"
var attack_cooldown: float = 0.0
## How hard an extinguisher burst lands (PROTOTYPE shrugs some of it off).
var spray_factor: float = 1.0
## Its battery was pried out: off for good.
var is_disabled: bool = false
## Game minutes after 11:45 PM when it reboots and starts hunting (the rogue
## update brings the robots back one at a time). PROTOTYPE ignores this.
var wake_minute: int = 15
## Where it last saw or heard Juan, and how long ago (s). Robots hunt this,
## never his live position: hiding and moving quietly actually lose them.
var last_known: Vector3 = Vector3.INF
var last_known_age: float = INF
## The dock it charges on; where it stands before midnight.
var home: Transform3D = Transform3D.IDENTITY

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _repath_timer: float = 0.0
var _desired_direction: Vector3 = Vector3.FORWARD
## Second navigation map built from the tight (0.25 m) mesh, shared by all
## robots: used only when a target is off the main (0.4 m) mesh.
static var _tight_map: RID = RID()
const TIGHT_NAVMESH := "res://school/school_navmesh_tight.res"
const OFF_MESH: float = 0.6
const TIGHT_SWITCH_RANGE: float = 3.0
## Stuck recovery: grinding against an open door leaf or a chair leg.
var stuck_count: int = 0
var _stuck_time: float = 0.0
var _sidestep_time: float = 0.0
var _sidestep: Vector3 = Vector3.ZERO


## Which RobotModels entry this robot wears.
func kind() -> StringName:
	return &""


func _ready() -> void:
	# Layer 2 so Juan's interaction ray can find it (screwdriver).
	collision_layer = LAYER_ROBOT | 2
	collision_mask = MOVE_MASK
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(55.0)
	var capsule := CapsuleShape3D.new()
	# Below the tight navmesh radius (0.25) so it fits every gap either mesh
	# allows. Walls are kept away by the main mesh (0.4), not by this body.
	capsule.radius = body_radius
	capsule.height = body_height
	body_shape = CollisionShape3D.new()
	body_shape.shape = capsule
	body_shape.position.y = body_height * 0.5
	add_child(body_shape)
	nav = NavigationAgent3D.new()
	# Small, so corners are followed instead of cut (cutting them is what
	# brought robots' arms through walls).
	nav.path_desired_distance = 0.22
	# Path points sit ~0.2 m above the floor (navmesh cell height); bring
	# them down to the feet so the distance check above can be met.
	nav.path_height_offset = 0.2
	nav.target_desired_distance = 0.55
	nav.radius = 0.4
	nav.height = body_height
	nav.path_max_distance = 3.0
	add_child(nav)
	if kind() != &"":
		model = RobotModels.make(kind())
		model.rotation.y = PI
		add_child(model)
	EventBus.noise_emitted.connect(_on_noise_emitted)
	_on_built()


# ------------------------------------------------------------------ lifecycle

## Parks the robot on its charging dock (before midnight).
func dock_at(xf: Transform3D) -> void:
	home = xf
	global_transform = xf
	is_docked = true
	set_state(&"DOCKED")


func activate(_at: Vector3 = Vector3.INF) -> void:
	if is_active:
		return
	super(_at)
	player = get_tree().get_first_node_in_group(&"player") as PlayerController
	is_docked = false
	_on_activated()


func deactivate() -> void:
	var was_active: bool = is_active
	super()
	velocity = Vector3.ZERO
	is_docked = false
	set_state(&"OFF")
	if was_active or state_name == &"OFF":
		_on_shutdown()


func set_state(new_state: StringName) -> void:
	state_name = new_state


func get_aggression() -> float:
	return TimeManager.get_aggression_multiplier()


## Movement speed only creeps up through the night (+4 % an hour, at most
## +24 %): fast enough to stay scary, never faster than Juan's sprint.
func get_speed_factor() -> float:
	return 1.0 + 0.04 * float(TimeManager.aggression_level)


func remember(point: Vector3) -> void:
	last_known = point
	last_known_age = 0.0


func knows_where() -> bool:
	return last_known != Vector3.INF and last_known_age < MEMORY_TIME


## A rough idea of where Juan might be, for when it has lost him: his floor
## and the general area, off by up to `error` metres. Robots get one of these
## every HUNCH_INTERVAL seconds so a night never stalls, without homing in.
func hunch(error: float = 9.0) -> Vector3:
	if player == null:
		return global_position
	return random_nav_point(player.global_position, error)


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_active:
		return
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	last_known_age += delta
	if stun_time_left > 0.0:
		ground_idle(delta)
		return
	_tick(delta)


# ------------------------------------------------------------------ overrides

func _on_built() -> void:
	pass


func _on_activated() -> void:
	pass


func _on_shutdown() -> void:
	pass


func _tick(_delta: float) -> void:
	pass


## A noise it could actually hear. `audibility` is 0..1.
func _on_heard(_origin: Vector3, _noise_type: StringName, _audibility: float) -> void:
	pass


# ---------------------------------------------------------------- screwdriver

const PRY_TIME: float = 3.5
const PRY_NOISE: float = 5.0


## True while it cannot move, so Juan can get his hands on its battery.
func can_be_pried() -> bool:
	return is_active and stun_time_left > 0.0


func get_interactions(player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_active and can_be_pried() and player.inventory.has_item(ItemDB.SCREWDRIVER):
		actions.append({"id": &"pry", "label": "Pry out its battery (%d s)" % int(ceil(PRY_TIME))})
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	if action_id != &"pry":
		return
	player.start_channel("Prying out %s's battery" % display_name, PRY_TIME, _finish_pry.bind(player), {
		"noise_type": &"metal_clatter", "noise_radius": PRY_NOISE, "noise_interval": 1.0,
	})


func _finish_pry(player: PlayerController) -> void:
	if not is_active:
		return
	if not can_be_pried():
		EventBus.ui_notification.emit("It moved. The screwdriver skids off the panel.", 2.5)
		return
	player.inventory.remove_item(ItemDB.SCREWDRIVER, 1)
	is_disabled = true
	SfxSynth.play_at(self, SfxSynth.latch_click(), get_eye_position() - Vector3.UP * 0.5, 0.0, 0.7)
	deactivate()
	EventBus.ui_notification.emit("The battery pops loose. %s goes limp. The screwdriver tip snapped." % display_name, 4.0)


# --------------------------------------------------------------------- senses

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * eye_height


func get_player_distance() -> float:
	if player == null:
		return INF
	return global_position.distance_to(player.global_position)


## Range (scaled by how visible Juan makes himself) and a clear sight line.
## `fov` <= 0 means it sees all around (a head that turns without warning).
func can_see_player(fov: float = 0.0) -> bool:
	if player == null or player.is_dead or player.is_concealed() or is_blind():
		return false
	var eye: Vector3 = get_eye_position()
	var head: Vector3 = player.get_head_position()
	var to_head: Vector3 = head - eye
	if to_head.length() > vision_range * player.get_visibility_factor():
		return false
	if fov > 0.0 and to_head.length() > 2.0:
		var forward: Vector3 = -global_transform.basis.z
		var flat := Vector3(to_head.x, 0.0, to_head.z)
		if flat.length() > 0.1 and rad_to_deg(forward.angle_to(flat)) > fov * 0.5:
			return false
	var query := PhysicsRayQueryParameters3D.create(eye, head, SIGHT_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _on_noise_emitted(origin: Vector3, radius: float, noise_type: StringName, source: Node) -> void:
	if not is_threatening() or source is Hostile or origin.distance_to(global_position) < SELF_NOISE_RADIUS:
		return
	var ears: Vector3 = get_eye_position()
	if NoiseManager.can_hear(ears, origin, radius, hearing):
		if source is PlayerController or source is ThrownBottle or source is TripwireAlarm:
			remember(origin)
		_on_heard(origin, noise_type, NoiseManager.get_audibility(ears, origin, radius, hearing))


# ----------------------------------------------------------------- locomotion

## Walks the navmesh towards `target`. Returns true on arrival (or when the
## path simply ends).
func nav_move_to(target: Vector3, speed: float, delta: float) -> bool:
	_repath_timer -= delta
	if _repath_timer <= 0.0 or nav.target_position.distance_to(target) > 1.0:
		nav.target_position = _pick_map(target)
		_repath_timer = REPATH_INTERVAL
	var flat := Vector3(target.x - global_position.x, 0.0, target.z - global_position.z)
	var level: bool = absf(target.y - global_position.y) < 1.3
	if flat.length() < 0.6 and level:
		ground_idle(delta)
		return true
	var next: Vector3
	if nav.is_navigation_finished():
		# The path ran out a step short: close the last metre or two directly.
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
		if _sidestep_time > 0.0:
			_sidestep_time -= delta
			direction = (_sidestep * 0.8 + direction * 0.2).normalized()
		velocity.x = move_toward(velocity.x, direction.x * speed, speed * 22.0 * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, speed * 22.0 * delta)
	_apply_gravity(delta)
	move_and_slide()
	_check_stuck(speed, delta)
	return false


## Barely moving while trying to: step sideways for a moment and re-path.
## `stuck_count` lets a subclass give up on a target that keeps failing.
func _check_stuck(speed: float, delta: float) -> void:
	var real: Vector3 = get_real_velocity()
	if Vector2(real.x, real.z).length() < speed * 0.15:
		_stuck_time += delta
	else:
		_stuck_time = maxf(_stuck_time - delta * 2.0, 0.0)
		if _stuck_time == 0.0 and _sidestep_time <= 0.0:
			stuck_count = 0
	if _stuck_time > 0.5:
		_stuck_time = 0.0
		stuck_count += 1
		var side: float = 1.0 if randf() < 0.5 else -1.0
		_sidestep = Vector3(-_desired_direction.z, 0.0, _desired_direction.x) * side
		_sidestep_time = 0.45
		_repath_timer = 0.0


## Which mesh to walk and where to aim on it. Normally the main mesh, which
## keeps robots clear of walls. When the target sits somewhere only the tight
## mesh reaches (between desks), travel on the main mesh to the nearest point
## it does reach, and switch to the tight mesh for the last few metres.
func _pick_map(target: Vector3) -> Vector3:
	var main_map: RID = get_world_3d().navigation_map
	var on_main: Vector3 = NavigationServer3D.map_get_closest_point(main_map, target)
	var want: RID = main_map
	var aim: Vector3 = target
	if on_main.distance_to(target) > OFF_MESH:
		var tight: RID = _get_tight_map()
		if tight.is_valid() and global_position.distance_to(on_main) < TIGHT_SWITCH_RANGE:
			want = tight
		else:
			aim = on_main
	if nav.get_navigation_map() != want:
		nav.set_navigation_map(want)
	return aim


func _get_tight_map() -> RID:
	if _tight_map.is_valid():
		return _tight_map
	if not ResourceLoader.exists(TIGHT_NAVMESH):
		return RID()
	_tight_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(_tight_map, 0.05)
	NavigationServer3D.map_set_cell_height(_tight_map, 0.1)
	NavigationServer3D.map_set_up(_tight_map, Vector3.UP)
	NavigationServer3D.map_set_active(_tight_map, true)
	var region: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, _tight_map)
	NavigationServer3D.region_set_navigation_mesh(region, load(TIGHT_NAVMESH))
	NavigationServer3D.region_set_transform(region, Transform3D.IDENTITY)
	return _tight_map


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


func ground_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	_apply_gravity(delta)
	move_and_slide()


## Turns to face `direction`; `turn_speed` <= 0 snaps at once.
func face_direction(direction: Vector3, delta: float, turn_speed: float = 9.0) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length() < 0.01:
		return
	var target_yaw: float = atan2(-flat.x, -flat.z)
	if turn_speed <= 0.0:
		rotation.y = target_yaw
	else:
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))


func face_point(point: Vector3, delta: float, turn_speed: float = 9.0) -> void:
	face_direction(point - global_position, delta, turn_speed)


## The closed door standing in the way of where this robot wants to go.
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
		# Only a door the route actually goes through: the way ahead crosses
		# the doorway's line, inside its width (not one it is walking past).
		var ahead: Vector3 = global_position + _desired_direction * (reach + 0.6)
		if door.which_side(global_position) == door.which_side(ahead):
			continue
		var lateral: float = absf((global_position - center).dot(door.get_along()))
		if lateral > door.door_width * 0.75:
			continue
		return door
	return null


## Strikes Juan if he is within reach. Returns true when a blow landed.
func try_attack_player() -> bool:
	if player == null or player.is_dead or attack_cooldown > 0.0:
		return false
	# Shut inside a locker or under a table with the light off, he is safe.
	if player.is_concealed():
		return false
	var reach_point: Vector3 = player.global_position + Vector3.UP * 0.8
	if (global_position + Vector3.UP * 0.8).distance_to(reach_point) > catch_distance:
		return false
	attack_cooldown = ATTACK_COOLDOWN
	var fatal: bool = player.take_attack(self)
	_on_attack_landed(fatal)
	return true


func _on_attack_landed(_fatal: bool) -> void:
	pass


## A random reachable point on the navmesh within `radius` of `around`.
func random_nav_point(around: Vector3, radius: float) -> Vector3:
	var map: RID = get_world_3d().navigation_map
	for _attempt in 6:
		var offset := Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
		var p: Vector3 = NavigationServer3D.map_get_closest_point(map, around + offset)
		if absf(p.y - around.y) < 2.5:
			return p
	return NavigationServer3D.map_get_closest_point(map, around)


## The point `distance` metres along the walkable route towards `target`
## (or the end of the route if it is shorter). Works across floors.
func point_along_route(target: Vector3, distance: float) -> Vector3:
	var map: RID = get_world_3d().navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, global_position, target, true)
	if path.size() < 2:
		return target
	var left: float = distance
	for i in range(1, path.size()):
		var seg: float = path[i - 1].distance_to(path[i])
		if seg >= left:
			return path[i - 1].lerp(path[i], left / maxf(seg, 0.001))
		left -= seg
	return path[path.size() - 1]


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
