class_name SearchPlanner
extends RefCounted
## A robot's search after it loses Juan: instead of wandering round random
## points, it works out where he probably went and checks those rooms one by
## one - into the room, then past a hiding spot or two.
##
##   - Where he went: the spot it last had him, pushed a few metres along the
##     way he was moving when it last saw him.
##   - Which rooms: those on that floor near the spot, nearest to the guess
##     first; the room he was last in counts extra.
##   - Shared memory: a room any robot searched in the last CLEARED_TIME
##     seconds is pushed to the back, so the robots spread out instead of all
##     checking the same classroom.
##
## The plan is a list of waypoints. Each robot asks next_point() whenever it
## would otherwise pick a random wander target, and reports arrive() when it
## gets there.

## How many rooms one search covers, and how far from the lead they may be.
const ROOMS_PER_SEARCH: int = 3
const ROOM_REACH: float = 16.0
## Hiding spots checked in each room.
const SPOTS_PER_ROOM: int = 2
## Furthest a robot may stand from a hiding spot to check it.
const SPOT_STAND_RANGE: float = 2.5
## How far along his heading the guess goes.
const LEAD_DISTANCE: float = 5.0
## Rooms searched this recently count as cleared.
const CLEARED_TIME: float = 60.0
const CLEARED_PENALTY: float = 14.0
const LAST_ROOM_BONUS: float = 5.0
## A plan this old is stale: the robot falls back to its own wandering.
const PLAN_LIFETIME: float = 75.0

## room id -> msec when a robot last searched it (shared by all robots).
static var cleared: Dictionary = {}

## [{"position": Vector3, "room": int, "spot": HidingSpot or null}, ...]
var waypoints: Array[Dictionary] = []
## The lead the plan was made from.
var origin: Vector3 = Vector3.INF
var _made_ms: int = 0
var _current: Dictionary = {}


static func room_cleared_recently(room_id: int) -> bool:
	return cleared.has(room_id) and Time.get_ticks_msec() - int(cleared[room_id]) < int(CLEARED_TIME * 1000.0)


static func reset_memory() -> void:
	cleared.clear()


func is_active() -> bool:
	if waypoints.is_empty() and _current.is_empty():
		return false
	if Time.get_ticks_msec() - _made_ms > int(PLAN_LIFETIME * 1000.0):
		clear()
		return false
	return true


## True when a plan already covers this lead (no need to make a new one).
func covers(lead: Vector3) -> bool:
	return is_active() and origin != Vector3.INF and origin.distance_to(lead) < 3.0


func clear() -> void:
	waypoints.clear()
	_current = {}
	origin = Vector3.INF


## Builds the search from `lead` (where it last had him) and `heading` (his
## velocity when last seen). `reachable` filters points the robot can get to
## (CONCIERGE: its own floor only).
func build(robot: RobotBase, lead: Vector3, heading: Vector3, reachable: Callable = Callable()) -> void:
	clear()
	origin = lead
	_made_ms = Time.get_ticks_msec()
	var map: RID = robot.get_world_3d().navigation_map
	var floor_index: int = Campus.floor_from_y(lead.y + 0.3)
	var flat := Vector3(heading.x, 0.0, heading.z)
	var guess: Vector3 = lead
	if flat.length() > 0.5:
		guess = lead + flat.normalized() * LEAD_DISTANCE
	var last_room: int = Campus.room_id_at(lead + Vector3.UP * 0.3)
	var scored: Array = []
	for room: Dictionary in Campus.ROOMS:
		if int(room["floor"]) != floor_index:
			continue
		var room_id: int = room["id"]
		var center: Vector3 = Campus.room_center(room_id)
		var flat_lead := Vector2(center.x - lead.x, center.z - lead.z).length()
		if flat_lead > ROOM_REACH and room_id != last_room:
			continue
		var score: float = Vector2(center.x - guess.x, center.z - guess.z).length()
		if room_id == last_room:
			score -= LAST_ROOM_BONUS
		if room_cleared_recently(room_id):
			score += CLEARED_PENALTY
		scored.append([score, room_id])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var spots_by_room: Dictionary = {}
	for node: Node in robot.get_tree().get_nodes_in_group(&"hiding_spots"):
		var spot := node as HidingSpot
		if spot == null:
			continue
		var spot_room: int = Campus.room_id_at(spot.global_position + Vector3.UP * 0.3)
		if not spots_by_room.has(spot_room):
			spots_by_room[spot_room] = []
		var list: Array = spots_by_room[spot_room]
		list.append(spot)
	var rooms_taken: int = 0
	for entry: Array in scored:
		if rooms_taken >= ROOMS_PER_SEARCH:
			break
		var room_id: int = entry[1]
		var center: Vector3 = Campus.room_center(room_id)
		var inside: Vector3 = NavigationServer3D.map_get_closest_point(map, center + Vector3.UP * 0.2)
		if absf(inside.y - center.y) > 1.0 or Campus.room_id_at(inside + Vector3.UP * 0.3) != room_id:
			continue
		if reachable.is_valid() and not reachable.call(inside):
			continue
		rooms_taken += 1
		waypoints.append({"position": inside, "room": room_id, "spot": null})
		var spots: Array = (spots_by_room.get(room_id, []) as Array).duplicate()
		spots.shuffle()
		var taken: int = 0
		for spot: HidingSpot in spots:
			if taken >= SPOTS_PER_ROOM:
				break
			var stand: Vector3 = _stand_point(robot, map, spot.get_exit_position())
			if stand == Vector3.INF:
				continue
			if reachable.is_valid() and not reachable.call(stand):
				continue
			waypoints.append({"position": stand, "room": room_id, "spot": spot})
			taken += 1


## Where a robot stands to check a hiding spot whose way out is `exit`: the
## exit itself when the tight navmesh (between PC benches and desks) reaches
## it - the robot switches to that mesh when it gets close - otherwise the
## nearest open floor on the same storey within sight range. INF if neither.
static func _stand_point(robot: RobotBase, map: RID, exit: Vector3) -> Vector3:
	var tight: RID = robot._get_tight_map()
	if tight.is_valid():
		var on_tight: Vector3 = NavigationServer3D.map_get_closest_point(tight, exit)
		if on_tight.distance_to(exit) < 0.6:
			return on_tight
	var on_main: Vector3 = NavigationServer3D.map_get_closest_point(map, exit)
	if absf(on_main.y - exit.y) < 1.0 and Vector2(on_main.x - exit.x, on_main.z - exit.z).length() < SPOT_STAND_RANGE:
		return on_main
	return Vector3.INF


## The next place to go, or Vector3.INF when the search is over.
func next_point() -> Vector3:
	if not is_active():
		return Vector3.INF
	if _current.is_empty():
		_current = waypoints.pop_front()
	return _current["position"]


## The hiding spot at the current waypoint, if it is one.
func current_spot() -> HidingSpot:
	if _current.is_empty():
		return null
	var spot: Variant = _current.get("spot")
	return spot as HidingSpot if is_instance_valid(spot) else null


## Reached the current waypoint: the room counts as searched.
func arrive() -> void:
	if _current.is_empty():
		return
	cleared[int(_current["room"])] = Time.get_ticks_msec()
	_current = {}
