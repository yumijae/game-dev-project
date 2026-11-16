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
## Last spot it stood on solid, walkable floor; where it is put back if it
## ever drops through the world (a bad physics push-out).
var _last_safe: Vector3 = Vector3.INF
const FALL_RESCUE_DROP: float = 2.0
## When it last had Juan in sight (ms): hiding in front of it fools nobody.
var _last_saw_ms: int = -1000000
const SAW_RECENTLY_MS: int = 1500
## A noise from inside a hiding spot this close gives the spot away.
const HIDING_GIVEAWAY_RANGE: float = 4.5
## It knows which spot he is in: close enough, cover no longer hides him.
const FOUND_SPOT_RANGE: float = 3.2

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
	# A new night: no room has been searched yet. (All robots spawn with the
	# level, so this only ever runs at the start of a night.)
	SearchPlanner.reset_memory()
	# Layer 2 so Juan's interaction ray can find it.
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
	search.clear()
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
## The longer Juan camps in one spot, the sharper it gets.
func hunch(error: float = 9.0) -> Vector3:
	if player == null:
		return global_position
	return random_nav_point(player.global_position, error * lerpf(1.0, 0.2, player.get_camp_level()))


## Anti-camping: once Juan has stayed put too long, every CAMP_PING seconds
## the robots get a fix on him (within a couple of metres), as if they had
## heard him there; and one that gets close finds him even in a hiding spot.
const CAMP_PING: float = 10.0
const CAMP_PING_ERROR: float = 1.5
const CAMP_FIND_RANGE: float = 4.5
var _camp_ping_timer: float = 0.0


func _camp_pressure(delta: float) -> void:
	if player == null or player.is_dead or player.get_camp_level() < 1.0:
		_camp_ping_timer = 0.0
		return
	_camp_ping_timer -= delta
	if _camp_ping_timer <= 0.0:
		_camp_ping_timer = CAMP_PING
		var guess: Vector3 = random_nav_point(player.global_position, CAMP_PING_ERROR)
		remember(guess)
		_on_heard(guess, &"camping", 0.4)
	if player.is_hidden and not player.is_hide_exposed \
			and absf(player.global_position.y - global_position.y) < 2.0 \
			and Vector2(player.global_position.x - global_position.x, player.global_position.z - global_position.z).length() <= CAMP_FIND_RANGE:
		player.expose_hiding(self)


func _physics_process(delta: float) -> void:
	super(delta)
	if not is_active:
		return
	_guard_against_falling()
	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	_camp_pressure(delta)
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


## Juan's hiding spot is known: go and get him.
func _on_found_hidden(_at: Vector3) -> void:
	pass


func _tick(_delta: float) -> void:
	pass


## A noise it could actually hear. `audibility` is 0..1.
func _on_heard(_origin: Vector3, _noise_type: StringName, _audibility: float) -> void:
	pass


# -------------------------------------------------------------------- search
# Lost him: work through the rooms he most likely went to (SearchPlanner)
# instead of wandering round random points near the last lead.

## Chance that stopping at the very hiding spot Juan is in gives him away
## (a shadow through the vents, breathing). Rises as he camps.
const HIDING_CHECK_CHANCE: float = 0.3
## His heading only steers the guess while the sighting is this fresh.
const HEADING_FRESH_MS: int = 12000

var search: SearchPlanner = SearchPlanner.new()
## Juan's velocity the last time it saw him.
var last_seen_heading: Vector3 = Vector3.ZERO


## Starts (or keeps) a search from its last lead. False when it has no lead
## or nothing reachable to search. `reachable` filters waypoints.
func begin_search(reachable: Callable = Callable()) -> bool:
	if not knows_where():
		return false
	if search.covers(last_known):
		return true
	var heading: Vector3 = last_seen_heading
	if Time.get_ticks_msec() - _last_saw_ms > HEADING_FRESH_MS:
		heading = Vector3.ZERO
	search.build(self, last_known, heading, reachable)
	return search.is_active()


## Where to go next in the search, or Vector3.INF when there is none. A
## fresh lead starts a new search; an old one keeps going after the lead
## itself has faded from memory.
func next_search_waypoint(reachable: Callable = Callable()) -> Vector3:
	if knows_where() and not search.covers(last_known):
		begin_search(reachable)
	return search.next_point()


## Call on reaching a search waypoint. At a hiding spot, Juan inside it may
## give himself away.
func search_arrived() -> void:
	var spot: HidingSpot = search.current_spot()
	search.arrive()
	if spot == null or player == null or spot.occupant != player or player.is_hide_exposed:
		return
	if randf() < HIDING_CHECK_CHANCE + 0.4 * player.get_camp_level():
		player.expose_hiding(self)


# ------------------------------------------------------------------- hivemind
# The rogue firmware links the robots through the server: one that is stuck
# behind a door it cannot open (CONCIERGE has no hands) calls the nearest
# robot that can, and that one comes over and opens it.

## How long a call for help stays open, and how far a helper will travel.
const HELP_TIMEOUT: float = 30.0
const HELP_MAX_PATH: float = 45.0
## The door another robot asked this one to open (null when not helping).
var help_door: InteractableDoor = null
var _help_until: float = 0.0
var _help_timer: float = 0.0


## True for robots with hands that can turn a door handle.
func can_open_doors() -> bool:
	return false


## Asks the closest robot with hands (by walking distance) to come and open
## `door`. Returns that robot, or null when none is free and near enough.
static func call_for_help(door: InteractableDoor, asker: Node3D) -> RobotBase:
	if door == null or not door.can_robot_open():
		return null
	var tree: SceneTree = asker.get_tree()
	var best: RobotBase = null
	var best_length: float = HELP_MAX_PATH
	var map: RID = asker.get_world_3d().navigation_map
	for node: Node in tree.get_nodes_in_group(&"hostiles"):
		var robot := node as RobotBase
		if robot == null or robot == asker or not robot.is_threatening() or robot.is_disabled or not robot.can_open_doors():
			continue
		if robot.help_door == door:
			return robot
		if robot.help_door != null and robot.is_helping():
			continue
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, robot.global_position,
			door.get_side_position(door.which_side(robot.global_position), 0.75), true)
		if path.size() < 2:
			continue
		var length: float = 0.0
		for i: int in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		if length < best_length:
			best_length = length
			best = robot
	if best != null:
		best.help_door = door
		best._help_until = Time.get_ticks_msec() / 1000.0 + HELP_TIMEOUT
		best._help_timer = 0.0
	return best


## The server relays an alarm: every robot learns `point` at once, however
## far away, and goes to look (one that cannot leave its floor still won't).
func alert_to(point: Vector3) -> void:
	if not is_threatening() or is_disabled:
		return
	remember(point)
	_on_heard(point, &"alarm", 1.0)


## Still on its way to open a door for another robot.
func is_helping() -> bool:
	if help_door == null:
		return false
	if not is_instance_valid(help_door) or help_door.is_passable() or not help_door.can_robot_open() \
			or Time.get_ticks_msec() / 1000.0 > _help_until:
		help_door = null
		return false
	return true


## Walks to the door it was asked to open and turns the handle. Call while
## is_helping(); returns true on the frame the door opens.
func help_step(speed: float, delta: float) -> bool:
	var door: InteractableDoor = help_door
	var center: Vector3 = door.get_center()
	var flat := Vector3(center.x - global_position.x, 0.0, center.z - global_position.z)
	if flat.length() > 1.25 or absf(center.y - global_position.y) > 1.2:
		_help_timer = 0.0
		nav_move_to(door.get_side_position(door.which_side(global_position), 0.75), speed, delta)
		return false
	ground_idle(delta)
	face_point(center, delta, 8.0)
	_help_timer += delta
	if _help_timer >= door.get_handle_delay():
		door.set_open(true)
		help_door = null
		return true
	return false


# ---------------------------------------------------------------------- taser

## A moving robot hit by the taser locks up this long (x spray_factor).
const TASER_STUN: float = 3.0


## Knocked flat (POSE after a taser hit) and waiting for another robot to
## reboot it. Not active, so it hunts nothing and hears nothing meanwhile.
var is_down: bool = false


## Juan's taser landed: it locks up for a moment. Returns true when it went
## down completely (POSE overrides this).
func take_taser() -> bool:
	if not is_active:
		return false
	stun(TASER_STUN * spray_factor, &"taser")
	blind(TASER_STUN * spray_factor)
	EventBus.ui_notification.emit("%s jolts and locks up. Go - it won't last." % display_name, 2.5)
	return false


## Shuts down where it stands until reboot() (another robot fixes it).
func knock_down() -> void:
	if not is_active:
		return
	deactivate()
	is_down = true
	add_to_group(&"downed_robots")


## Brought back by another robot (CONCIERGE).
func reboot() -> void:
	if not is_down:
		return
	is_down = false
	remove_from_group(&"downed_robots")
	activate()
	EventBus.robot_online.emit(display_name)


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
	var seen: bool = _sight_test(fov)
	if seen:
		_last_saw_ms = Time.get_ticks_msec()
		last_seen_heading = player.velocity
		search.clear()
	return seen


func saw_player_recently() -> bool:
	return Time.get_ticks_msec() - _last_saw_ms <= SAW_RECENTLY_MS


## It has worked out which hiding spot Juan is in (PlayerController.expose_hiding).
func on_found_hidden(at: Vector3) -> void:
	remember(at)
	_on_found_hidden(at)


func _sight_test(fov: float) -> bool:
	if player == null or player.is_dead or player.is_concealed() or is_blind():
		return false
	var eye: Vector3 = get_eye_position()
	var head: Vector3 = player.get_head_position()
	var to_head: Vector3 = head - eye
	# A locker door or a desk front between them no longer matters.
	if player.is_hidden and player.is_hide_exposed and absf(to_head.y) < 2.0 \
			and Vector2(to_head.x, to_head.z).length() < FOUND_SPOT_RANGE:
		return true
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
	if not is_threatening() or source is Hostile:
		return
	# Ignore the racket it makes itself (a door it just opened) - but never
	# Juan: that also deafened every robot to a gasp or a step right beside it.
	if not (source is PlayerController) and origin.distance_to(global_position) < SELF_NOISE_RADIUS:
		return
	var ears: Vector3 = get_eye_position()
	if NoiseManager.can_hear(ears, origin, radius, hearing):
		if source is PlayerController or source is ThrownBottle:
			remember(origin)
		var juan := source as PlayerController
		if juan != null and juan.is_hidden and absf(origin.y - global_position.y) < 2.0 \
				and origin.distance_to(global_position) <= HIDING_GIVEAWAY_RANGE:
			# A gasp or panting from inside the locker it is standing next to.
			juan.expose_hiding(self)
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


func _guard_against_falling() -> void:
	if _last_safe != Vector3.INF and global_position.y < _last_safe.y - FALL_RESCUE_DROP:
		var map: RID = get_world_3d().navigation_map
		global_position = NavigationServer3D.map_get_closest_point(map, _last_safe) + Vector3.UP * 0.05
		velocity = Vector3.ZERO
		return
	if is_on_floor() and not body_shape.disabled:
		_last_safe = global_position


## Points its heading along the route to a new `goal` before it has moved.
## find_blocking_door() judges "in the way" by that heading; left over from
## the last trip, a robot that had been waiting at a closed door still
## "faced" it, judged every new destination blocked and never set off.
func aim_heading_at(goal: Vector3) -> void:
	nav.target_position = _pick_map(goal)
	_repath_timer = REPATH_INTERVAL
	var next: Vector3 = nav.get_next_path_position()
	var direction := Vector3(next.x - global_position.x, 0.0, next.z - global_position.z)
	if direction.length() < 0.05:
		direction = Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	if direction.length() > 0.05:
		_desired_direction = direction.normalized()


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
		# Chained fire exits lead nowhere the navmesh goes: never "in the way".
		if door == null or door.is_passable() or door.permanently_locked:
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


## Call when giving up on a closed door. Turns its heading away from the
## doorway, so find_blocking_door() stops reporting that door and the robot
## can walk off to its new target. (The heading only updates while moving;
## left pointing at the door, the robot stood there waiting on it forever.)
func turn_from_door(door: InteractableDoor) -> void:
	var away: Vector3 = global_position - door.get_center()
	away.y = 0.0
	if away.length() < 0.05:
		away = door.room_side * door.which_side(global_position)
	_desired_direction = away.normalized()
	_repath_timer = 0.0


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


## Where to wait out the pause after a hit: a reachable spot `distance`
## metres further from Juan than it is now. Without this a robot wandered
## straight back and stood over him until its next strike came off cooldown.
func retreat_point(distance: float = 9.0) -> Vector3:
	if player == null:
		return random_nav_point(global_position, distance)
	var away := Vector3(global_position.x - player.global_position.x, 0.0, global_position.z - player.global_position.z)
	if away.length() < 0.1:
		away = Vector3.FORWARD
	return random_nav_point(global_position + away.normalized() * distance, 3.0)


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
