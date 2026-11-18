class_name GateCodeHints
extends Node3D
## Scatters tonight's side-lock combination round the school, one digit per
## floor, so the early breach means a trip through every floor:
##   1F  a typed security memo on an office desk
##   2F  a sticky note on a desk in the labs or the MIT Office
##   3F  marker on a classroom board ("SIDE GATE LOCK??  _ _ 7 _")
##   4F  a sticky note on a desk upstairs
## Which digit goes to which floor changes every night. Keeps track of the
## digits Juan has read (the dial and the phone's Notes show them).

const MEMO_ROOMS: Array[int] = [2, 3, 4, 5]
const LAB_ROOMS: Array[int] = [7, 8, 12, 11]
const BOARD_ROOMS: Array[int] = [14, 15, 16, 17, 21]
const TOP_ROOMS: Array[int] = [22, 23, 25, 27]
## Desk/counter markers in this band above the floor take a note.
const SURFACE_MIN: float = 0.6
const SURFACE_MAX: float = 1.15
## Kept clear of loot so the note never hides an item or the other way round.
const ITEM_CLEARANCE: float = 0.35
## Stands in for a note when asking the item spawner for floor room.
const NOTE_FOOTPRINT: StringName = ItemDB.TABLECLOTH_RAG
## Walkable floor must come this close (metres, level) to a desk note.
const DESK_STAND_REACH: float = 1.6
## ... and to a note on the floor or in front of a board.
const FLOOR_STAND_REACH: float = 1.0
## Room he needs where he stands. A little under his 0.3 m radius: the tight
## navmesh's edge, where he walks up to a desk, is about that far from it.
const STAND_CLEARANCE: float = 0.25
## Along the route to it: every ROUTE_SAMPLE metres there must be at least
## this much room. Real routes keep 0.2 m or more; the bad ones pinch to
## 0.05-0.1 m.
const ROUTE_CLEARANCE: float = 0.15
const ROUTE_SAMPLE: float = 0.1
## Doors are opened on the way, so they do not count as in the way.
const LAYER_DOORS: int = 8
## How far in front of a board note the floor must be reachable.
const BOARD_STAND_OFF: float = 0.4

var _found: Dictionary = {}
## Rooms that already hold a note tonight.
var _used_rooms: Array[int] = []
var _map: RID = RID()


func _ready() -> void:
	add_to_group(&"gate_code_hints")
	EventBus.gate_code_hint_found.connect(func(index: int, digit: int) -> void: _found[index] = digit)
	# After the gate has rolled its code and the item spawner has stocked
	# the rooms (it waits two physics frames).
	for i: int in 5:
		await get_tree().physics_frame
	# Juan's navmesh is loaded on first use and answers only once synced.
	for i: int in 120:
		if not is_inside_tree() or _map_ready(_walk_map()):
			break
		await get_tree().physics_frame
	if is_inside_tree():
		_place_all()


## The digit read for place `index`, or -1.
func found_digit(index: int) -> int:
	return _found.get(index, -1)


func found_count() -> int:
	return _found.size()


func _place_all() -> void:
	var gate := get_tree().get_first_node_in_group(&"rehas_gate") as RehasGate
	if gate == null or gate.combination.size() < 4:
		return
	_used_rooms.clear()
	var order: Array = [0, 1, 2, 3]
	order.shuffle()
	_place_on_board(order[2], gate.combination[order[2]])
	_place_on_desk(MEMO_ROOMS, CodeNote.Style.MEMO, order[0], gate.combination[order[0]])
	_place_on_desk(LAB_ROOMS, CodeNote.Style.STICKY, order[1], gate.combination[order[1]])
	_place_on_desk(TOP_ROOMS, CodeNote.Style.STICKY, order[3], gate.combination[order[3]])


## Always places the note somewhere on the floor of `rooms`, in a room no
## other note uses. In order of preference: a clear desk in one of `rooms`,
## a clear desk elsewhere on that floor, the foot of a wall (those rooms
## first), any reachable patch of floor, and at worst the middle of a room.
func _place_on_desk(rooms: Array[int], style: CodeNote.Style, index: int, digit: int) -> void:
	var floor_index: int = int(Campus.room_by_id(rooms[0])["floor"])
	var preferred: Array = rooms.filter(func(id: int) -> bool: return not _used_rooms.has(id))
	preferred.shuffle()
	var others: Array = []
	for room: Dictionary in Campus.ROOMS:
		var id: int = room["id"]
		if int(room["floor"]) == floor_index and not rooms.has(id) and not _used_rooms.has(id):
			others.append(id)
	others.shuffle()
	var candidates: Array = preferred + others
	if candidates.is_empty():
		push_error("GateCodeHints: every room on %s already has a note" % Campus.floor_name(floor_index))
		return
	var spawner := _spawner()
	var spot: Dictionary = {}
	if spawner != null:
		for room_id: int in candidates:
			spot = _desk_spot(spawner, room_id)
			if not spot.is_empty():
				break
		if spot.is_empty():
			for room_id: int in candidates:
				spot = _wall_spot(spawner, room_id)
				if not spot.is_empty():
					break
		if spot.is_empty():
			for room_id: int in candidates:
				spot = _open_floor_spot(spawner, room_id)
				if not spot.is_empty():
					break
	if spot.is_empty():
		push_warning("GateCodeHints: no clear spot for digit %d, using the middle of a room" % (index + 1))
		spot = {"room": candidates[0], "position": Campus.room_center(candidates[0]), "yaw": 0.0}
	_used_rooms.append(int(spot["room"]))
	var note := CodeNote.create(style, index, digit)
	add_child(note)
	note.global_position = spot["position"]
	note.rotation.y = float(spot["yaw"]) + randf_range(-0.5, 0.5)


## A clear desk or counter marker in the room that Juan can reach.
func _desk_spot(spawner: ItemSpawner, room_id: int) -> Dictionary:
	var level: float = Campus.room_center(room_id).y
	var candidates: Array = []
	for child: Node in spawner.get_children():
		var marker := child as Marker3D
		if marker == null or int(marker.get_meta("room_id", 0)) != room_id:
			continue
		var at: Vector3 = marker.global_position
		var height: float = at.y - level
		if height < SURFACE_MIN or height > SURFACE_MAX or _near_item(at):
			continue
		# Same test the key uses: nothing over it, nothing on or beside it.
		if not spawner._key_spot_clear(at) or not spawner._can_be_reached(at):
			continue
		# A desk in the middle of a packed row can sit further from the aisle
		# than his reach.
		if not _can_stand_to_read(at, level, DESK_STAND_REACH):
			continue
		candidates.append(at)
	if candidates.is_empty():
		return {}
	return {"room": room_id, "position": candidates.pick_random(), "yaw": 0.0}


## The foot of a wall in the room, clear of doors, furniture and items.
func _wall_spot(spawner: ItemSpawner, room_id: int) -> Dictionary:
	var room: Dictionary = Campus.room_by_id(room_id)
	var level: float = Campus.room_center(room_id).y
	for _attempt: int in 60:
		var probe := Vector3(randf_range(float(room["x0"]) + 0.5, float(room["x1"]) - 0.5), level,
			randf_range(float(room["z0"]) + 0.5, float(room["z1"]) - 0.5))
		if not spawner._has_floor(probe):
			continue
		var snapped: Dictionary = spawner._against_wall(probe, NOTE_FOOTPRINT, room_id)
		if snapped.is_empty() or _near_item(snapped["position"]) \
				or not _can_stand_to_read(snapped["position"], level, FLOOR_STAND_REACH):
			continue
		return {"room": room_id, "position": snapped["position"], "yaw": snapped["yaw"]}
	return {}


## Any patch of the room's floor Juan can reach, clear of items if possible.
func _open_floor_spot(spawner: ItemSpawner, room_id: int) -> Dictionary:
	var room: Dictionary = Campus.room_by_id(room_id)
	var level: float = Campus.room_center(room_id).y
	for strict: bool in [true, false]:
		for _attempt: int in 80:
			var probe := Vector3(randf_range(float(room["x0"]) + 0.4, float(room["x1"]) - 0.4), level,
				randf_range(float(room["z0"]) + 0.4, float(room["z1"]) - 0.4))
			if not spawner._has_floor(probe) or not spawner._can_be_reached(probe) \
					or not _can_stand_to_read(probe, level, FLOOR_STAND_REACH):
				continue
			if strict and (_near_item(probe) or spawner._near_door(probe) or not spawner._fits(probe, NOTE_FOOTPRINT)):
				continue
			return {"room": room_id, "position": probe, "yaw": 0.0}
	return {}


## Juan can walk up to `at` and read it: the nearest point of his navmesh
## (the tight one, between desks) is on this floor, within `reach` of it,
## has room for him and is joined to the corridor. Without it a note could
## end up in a pocket only the navmesh fits into, or one walled off.
func _can_stand_to_read(at: Vector3, level: float, reach: float) -> bool:
	var map: RID = _walk_map()
	if not _map_ready(map):
		return true
	var stand: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(at.x, level, at.z))
	if absf(stand.y - level) > 0.5 or Vector2(stand.x - at.x, stand.z - at.z).length() > reach:
		return false
	if not _has_room(stand, STAND_CLEARANCE):
		return false
	var corridor: Vector3 = NavigationServer3D.map_get_closest_point(map, Vector3(0.0, level, 0.0))
	var route: PackedVector3Array = NavigationServer3D.map_get_path(map, corridor, stand, true)
	if route.size() < 2 or route[route.size() - 1].distance_to(stand) >= 0.3:
		return false
	# The tight navmesh also climbs onto low platforms over steps he cannot
	# take (1F Director's Office): follow the route and look for a pinch.
	for i: int in range(1, route.size()):
		var from: Vector3 = route[i - 1]
		var to: Vector3 = route[i]
		var steps: int = maxi(int(ceil(from.distance_to(to) / ROUTE_SAMPLE)), 1)
		for k: int in steps + 1:
			if not _has_room(from.lerp(to, float(k) / float(steps)), ROUTE_CLEARANCE):
				return false
	return true


## Nothing solid within `radius` of a standing body at `at` (a navmesh point).
func _has_room(at: Vector3, radius: float) -> bool:
	var body := CapsuleShape3D.new()
	body.radius = radius
	body.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.95)
	query.collision_mask = ItemSpawner.SOLID_MASK & ~LAYER_DOORS
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## The navmesh Juan fits: the robots' tight one, or the main one without it.
func _walk_map() -> RID:
	if _map.is_valid():
		return _map
	var robot := get_tree().get_first_node_in_group(&"hostiles") as RobotBase
	if robot != null:
		_map = robot._get_tight_map()
	if not _map.is_valid():
		_map = get_world_3d().navigation_map
	return _map


## True once the map's polygons answer queries: it reports a first
## iteration before the navmesh in it is synced.
func _map_ready(map: RID) -> bool:
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var probe := Vector3(0.0, Campus.floor_y(1), 0.0)
	return NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 1.0


func _spawner() -> ItemSpawner:
	var school: Node = get_tree().get_first_node_in_group(&"school")
	if school == null:
		return null
	return school.get_node_or_null("ItemSpawns") as ItemSpawner


## On a classroom board, off to one side of its middle, where Juan can step
## up to it (a teacher's desk or cabinet may stand in front of part of it).
func _place_on_board(index: int, digit: int) -> void:
	var rooms: Array = BOARD_ROOMS.filter(func(id: int) -> bool: return not _used_rooms.has(id))
	rooms.shuffle()
	var spawner := _spawner()
	var spot: Dictionary = {}
	for attempt: int in 32:
		var candidate: Dictionary = _board_spot(rooms[attempt % rooms.size()])
		if spot.is_empty():
			spot = candidate
		var front: Vector3 = candidate["front"]
		if spawner == null or (spawner._can_be_reached(front) and _can_stand_to_read(front, front.y, FLOOR_STAND_REACH)):
			spot = candidate
			break
	_used_rooms.append(int(spot["room"]))
	var note := CodeNote.create(CodeNote.Style.BOARD, index, digit)
	add_child(note)
	note.global_position = spot["position"]
	note.rotation.y = spot["yaw"]


## A random place on the room's board, and the floor just in front of it.
func _board_spot(room_id: int) -> Dictionary:
	var room: Dictionary = Campus.room_by_id(room_id)
	# The corner rooms (x0 on the outside wall) are mirrored: board on x1.
	var mirrored: bool = absf(float(room["x0"]) - Campus.X_MIN) < 0.01
	var x: float = float(room["x1"]) - 0.135 if mirrored else float(room["x0"]) + 0.135
	var z: float = (float(room["z0"]) + float(room["z1"])) * 0.5 + randf_range(-0.9, 0.9)
	var level: float = Campus.floor_y(int(room["floor"]))
	var into_room: float = -1.0 if mirrored else 1.0
	return {
		"room": room_id,
		"position": Vector3(x, level + 1.55, z),
		"yaw": -PI * 0.5 if mirrored else PI * 0.5,
		"front": Vector3(x + into_room * BOARD_STAND_OFF, level, z),
	}


func _near_item(at: Vector3) -> bool:
	for item: Node in get_tree().get_nodes_in_group(&"world_items"):
		if (item as Node3D).global_position.distance_to(at) < ITEM_CLEARANCE:
			return true
	return false
