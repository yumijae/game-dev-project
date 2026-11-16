extends Node
## NoiseManager (autoload) - radius-based acoustics for a concrete building.
##
## A noise has a radius in metres. Every reinforced-concrete floor slab between
## source and listener removes 9 m of that radius; when either end stands in a
## stairwell shaft that links both floors, the shaft carries the sound and the
## loss is halved to 4.5 m per floor. Listeners compare what is left against
## their horizontal distance to the source.
##
## On the same floor, sound travels through the building (hear()): straight to
## a listener with nothing solid in between; otherwise it either goes round
## the walkable route - through doorways, along corridors, losing DOOR_LOSS
## metres at every shut door - or straight through the wall, muffled as if
## THROUGH_WALL_FACTOR times further away, whichever carries better.

const SLAB_DAMPENING: float = 9.0
const STAIRWELL_DAMPENING: float = 4.5
## The 2F Server Room's rack hum masks this much of a footstep's radius.
const SERVER_HUM_REDUCTION: float = 4.0
const HISTORY_SECONDS: float = 3.0
## A wall makes a noise sound this many times further away.
const THROUGH_WALL_FACTOR: float = 2.5
## Each closed door on the route costs this many metres.
const DOOR_LOSS: float = 5.0
## A door this close to the route counts as on it.
const DOOR_ON_ROUTE: float = 0.9
## Walls and closed door leaves (open leaves are on another layer).
const SOUND_BLOCK_MASK: int = 1 | 8
const FOOTSTEP_TYPES: Array[StringName] = [&"footstep_walk", &"footstep_sprint", &"footstep_sneak"]


## One remembered noise, kept for HISTORY_SECONDS so late listeners can react.
class NoiseEvent extends RefCounted:
	var serial: int = 0
	var origin: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	var noise_type: StringName = &""
	var source: Node = null
	var time_sec: float = 0.0


var _history: Array[NoiseEvent] = []
var _serial: int = 0


func _process(_delta: float) -> void:
	var now: float = _now()
	while not _history.is_empty() and now - _history[0].time_sec > HISTORY_SECONDS:
		_history.pop_front()


## 0 = 1F, 1 = 2F, 2 = 3F, 3 = 4F, 4 = Rooftop.
func get_floor_from_y(y: float) -> int:
	return Campus.floor_from_y(y)


## "West" (X -12..-9, 1F-4F), "East" (X 9..12, 1F-Roof) or "".
func is_in_stairwell(pos: Vector3) -> String:
	return Campus.stairwell_at(pos)


func is_in_server_room(pos: Vector3) -> bool:
	return Campus.room_id_at(pos) == Campus.SERVER_ROOM_ID


## Broadcasts a noise. `radius` is how far it carries on its own floor.
func emit_noise(origin: Vector3, radius: float, noise_type: StringName, source: Node = null) -> void:
	if radius <= 0.0:
		return
	_serial += 1
	var event := NoiseEvent.new()
	event.serial = _serial
	event.origin = origin
	event.radius = radius
	event.noise_type = noise_type
	event.source = source
	event.time_sec = _now()
	_history.append(event)
	EventBus.noise_emitted.emit(origin, radius, noise_type, source)


## Footsteps are partly drowned by the server rack hum inside the Server Room.
func emit_footstep(origin: Vector3, radius: float, noise_type: StringName, source: Node = null) -> void:
	emit_noise(origin, get_footstep_radius(origin, radius), noise_type, source)


func get_footstep_radius(origin: Vector3, radius: float) -> float:
	if is_in_server_room(origin):
		return maxf(radius - SERVER_HUM_REDUCTION, 0.0)
	return radius


## Radius lost to the slabs between two points.
func get_floor_dampening(origin: Vector3, listener_pos: Vector3) -> float:
	var source_floor: int = get_floor_from_y(origin.y)
	var listener_floor: int = get_floor_from_y(listener_pos.y)
	var floor_diff: int = absi(source_floor - listener_floor)
	if floor_diff == 0:
		return 0.0
	var per_floor: float = SLAB_DAMPENING
	for stairwell: String in [is_in_stairwell(origin), is_in_stairwell(listener_pos)]:
		if stairwell != "" and Campus.stairwell_connects(stairwell, source_floor, listener_floor):
			per_floor = STAIRWELL_DAMPENING
			break
	return per_floor * float(floor_diff)


## What remains of `radius` once the slabs have taken their share.
func get_effective_radius(origin: Vector3, radius: float, listener_pos: Vector3) -> float:
	return maxf(radius - get_floor_dampening(origin, listener_pos), 0.0)


## `hearing` scales the listener's ears (1.0 = normal, 1.5 = keen).
func can_hear(listener_pos: Vector3, origin: Vector3, radius: float, hearing: float = 1.0) -> bool:
	var effective: float = get_effective_radius(origin, radius * hearing, listener_pos)
	if effective <= 0.0:
		return false
	var offset: Vector3 = listener_pos - origin
	if get_floor_from_y(origin.y) != get_floor_from_y(listener_pos.y):
		offset.y = 0.0
	return offset.length() <= effective


## 0..1 - how clearly `listener` (ears at `ears`) hears a noise, with the
## building in the way: 0 when it does not carry that far. Same-floor noises
## go round walls and doors; across floors the slab rules apply as before.
func hear(listener: Node3D, ears: Vector3, origin: Vector3, radius: float, hearing: float = 1.0) -> float:
	var effective: float = get_effective_radius(origin, radius * hearing, ears)
	if effective <= 0.0:
		return 0.0
	var flat: float = Vector2(ears.x - origin.x, ears.z - origin.z).length()
	# Every route is at least the straight line: too far even for that.
	if flat > effective:
		return 0.0
	if get_floor_from_y(origin.y) != get_floor_from_y(ears.y):
		return clampf(1.0 - flat / effective, 0.01, 1.0)
	var distance: float = travel_distance(listener, ears, origin, flat)
	if distance > effective:
		return 0.0
	# Never quite silent once it is in range.
	return clampf(1.0 - distance / effective, 0.01, 1.0)


## How far a noise effectively travels from `origin` to `ears` on one floor.
func travel_distance(listener: Node3D, ears: Vector3, origin: Vector3, flat: float = -1.0) -> float:
	if flat < 0.0:
		flat = Vector2(ears.x - origin.x, ears.z - origin.z).length()
	var world: World3D = listener.get_world_3d()
	var mouth: Vector3 = origin + Vector3.UP * 0.6
	var query := PhysicsRayQueryParameters3D.create(mouth, ears, SOUND_BLOCK_MASK)
	if world.direct_space_state.intersect_ray(query).is_empty():
		return flat
	var through_wall: float = flat * THROUGH_WALL_FACTOR
	var map: RID = world.navigation_map
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map,
		NavigationServer3D.map_get_closest_point(map, origin),
		NavigationServer3D.map_get_closest_point(map, ears), true)
	if path.size() < 2:
		return through_wall
	var around: float = 0.0
	for i: int in range(1, path.size()):
		around += path[i - 1].distance_to(path[i])
		if around >= through_wall:
			return through_wall
	around += DOOR_LOSS * float(_closed_doors_on(path))
	return minf(around, through_wall)


## Shut doors the route passes through.
func _closed_doors_on(path: PackedVector3Array) -> int:
	var count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as InteractableDoor
		if door == null or door.is_passable():
			continue
		var center: Vector3 = door.get_center()
		var at := Vector2(center.x, center.z)
		for i: int in range(1, path.size()):
			var a: Vector3 = path[i - 1]
			var b: Vector3 = path[i]
			if absf(a.y - center.y) > 2.0:
				continue
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(at, Vector2(a.x, a.z), Vector2(b.x, b.z))
			if closest.distance_to(at) < DOOR_ON_ROUTE:
				count += 1
				break
	return count


## 0..1 - how clearly the listener hears it (1 = right on top of the source).
func get_audibility(listener_pos: Vector3, origin: Vector3, radius: float, hearing: float = 1.0) -> float:
	var effective: float = get_effective_radius(origin, radius * hearing, listener_pos)
	if effective <= 0.0:
		return 0.0
	var flat := Vector3(listener_pos.x - origin.x, 0.0, listener_pos.z - origin.z)
	return clampf(1.0 - flat.length() / effective, 0.0, 1.0)


## Remembered noises the listener can still hear, newest last. Pass the serial
## of the last event already handled to receive only newer ones.
func get_recent_audible(listener_pos: Vector3, hearing: float = 1.0, after_serial: int = 0) -> Array[NoiseEvent]:
	var audible: Array[NoiseEvent] = []
	for event: NoiseEvent in _history:
		if event.serial > after_serial and can_hear(listener_pos, event.origin, event.radius, hearing):
			audible.append(event)
	return audible


func clear() -> void:
	_history.clear()


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
