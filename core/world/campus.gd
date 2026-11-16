class_name Campus
extends RefCounted
## Static description of the STI College Kalibo building: the single source of
## truth for floor heights, the 28 numbered rooms, the corridor and both
## stairwells. Everything here is pure geometry, so it is safe to call from
## autoloads, AI and tool scripts alike.

const FLOOR_HEIGHT: float = 3.8
const FLOOR_COUNT: int = 4
const ROOF_FLOOR: int = 4
const ROOF_Y: float = 15.2
const X_MIN: float = -12.0
const X_MAX: float = 12.0
const Z_MIN: float = -8.0
const Z_MAX: float = 8.0
const CORRIDOR_HALF_WIDTH: float = 1.2
const ROOFTOP_ID: int = 28
const SERVER_ROOM_ID: int = 11

const WEST_STAIR_X0: float = -12.0
const WEST_STAIR_X1: float = -9.0
const WEST_STAIR_TOP_FLOOR: int = 3
const EAST_STAIR_X0: float = 9.0
const EAST_STAIR_X1: float = 12.0
const EAST_STAIR_TOP_FLOOR: int = 4

const ANTENNA_POSITION: Vector3 = Vector3(0.0, 15.2, 0.0)
const REHAS_GATE_POSITION: Vector3 = Vector3(0.0, 0.0, 7.8)
const FLOOR_NAMES: Array[String] = ["1F", "2F", "3F", "4F", "Rooftop"]

## The 27 interior rooms. Room #28 is the open rooftop deck.
const ROOMS: Array[Dictionary] = [
	{"id": 1, "floor": 0, "name": "Main Lobby", "type": "lobby", "x0": -3.0, "z0": 1.2, "x1": 3.0, "z1": 8.0},
	{"id": 2, "floor": 0, "name": "Admissions Office", "type": "admissions", "x0": -12.0, "z0": 1.2, "x1": -3.0, "z1": 8.0},
	{"id": 3, "floor": 0, "name": "Cashier & Registrar", "type": "cashier", "x0": 3.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"id": 4, "floor": 0, "name": "Director's Office", "type": "director", "x0": -9.0, "z0": -8.0, "x1": -3.0, "z1": -1.2},
	{"id": 5, "floor": 0, "name": "Staff Room", "type": "staff", "x0": -3.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"id": 6, "floor": 0, "name": "Records Room", "type": "records", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
	{"id": 7, "floor": 1, "name": "Computer Lab 1", "type": "complab", "x0": -12.0, "z0": 1.2, "x1": 0.0, "z1": 8.0},
	{"id": 8, "floor": 1, "name": "Computer Lab 2", "type": "complab", "x0": 0.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"id": 9, "floor": 1, "name": "Male Restroom", "type": "restroom", "x0": -9.0, "z0": -8.0, "x1": -6.0, "z1": -1.2},
	{"id": 10, "floor": 1, "name": "Female Restroom", "type": "restroom", "x0": -6.0, "z0": -8.0, "x1": -3.0, "z1": -1.2},
	{"id": 11, "floor": 1, "name": "Server Room", "type": "server", "x0": -3.0, "z0": -8.0, "x1": 0.0, "z1": -1.2},
	{"id": 12, "floor": 1, "name": "MIT Office", "type": "mit", "x0": 0.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"id": 13, "floor": 1, "name": "Com Sci Lab", "type": "robolab", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
	{"id": 14, "floor": 2, "name": "Room 301", "type": "classroom", "x0": -12.0, "z0": 1.2, "x1": -6.0, "z1": 8.0},
	{"id": 15, "floor": 2, "name": "Room 302", "type": "classroom", "x0": -6.0, "z0": 1.2, "x1": 0.0, "z1": 8.0},
	{"id": 16, "floor": 2, "name": "Room 303", "type": "classroom", "x0": 0.0, "z0": 1.2, "x1": 6.0, "z1": 8.0},
	{"id": 17, "floor": 2, "name": "Room 304", "type": "classroom", "x0": 6.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"id": 18, "floor": 2, "name": "Faculty Room", "type": "faculty", "x0": -9.0, "z0": -8.0, "x1": -3.0, "z1": -1.2},
	{"id": 19, "floor": 2, "name": "Male Restroom", "type": "restroom", "x0": -3.0, "z0": -8.0, "x1": 0.0, "z1": -1.2},
	{"id": 20, "floor": 2, "name": "Female Restroom", "type": "restroom", "x0": 0.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"id": 21, "floor": 2, "name": "Room 305", "type": "classroom", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
	{"id": 22, "floor": 3, "name": "Room 401", "type": "classroom", "x0": -12.0, "z0": 1.2, "x1": -6.0, "z1": 8.0},
	{"id": 23, "floor": 3, "name": "Room 402", "type": "classroom", "x0": -6.0, "z0": 1.2, "x1": 0.0, "z1": 8.0},
	{"id": 24, "floor": 3, "name": "Culinary Kitchen", "type": "kitchen", "x0": 0.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"id": 25, "floor": 3, "name": "Room 403", "type": "classroom", "x0": -9.0, "z0": -8.0, "x1": 0.0, "z1": -1.2},
	{"id": 26, "floor": 3, "name": "Pantry", "type": "pantry", "x0": 0.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"id": 27, "floor": 3, "name": "Culinary Dining", "type": "dining", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
]

## Rooms whose corridor wall is a half-wall with wide plate-glass viewing bays.
const GLASS_LAB_ROOM_IDS: Array[int] = [7, 8, 13, 24, 27]


## 0 = 1F, 1 = 2F, 2 = 3F, 3 = 4F, 4 = Rooftop.
static func floor_from_y(y: float) -> int:
	if y >= ROOF_Y - 0.6:
		return ROOF_FLOOR
	return clampi(int(floor((y + 0.6) / FLOOR_HEIGHT)), 0, FLOOR_COUNT - 1)


static func floor_y(floor_index: int) -> float:
	return float(clampi(floor_index, 0, ROOF_FLOOR)) * FLOOR_HEIGHT


static func floor_name(floor_index: int) -> String:
	return FLOOR_NAMES[clampi(floor_index, 0, ROOF_FLOOR)]


static func is_inside_footprint(pos: Vector3, margin: float = 0.0) -> bool:
	return pos.x >= X_MIN - margin and pos.x <= X_MAX + margin \
		and pos.z >= Z_MIN - margin and pos.z <= Z_MAX + margin


## "West", "East" or "" - the stairwell shaft containing `pos`, if any.
static func stairwell_at(pos: Vector3) -> String:
	if pos.z < Z_MIN or pos.z > -CORRIDOR_HALF_WIDTH:
		return ""
	var floor_index: int = floor_from_y(pos.y)
	if pos.x >= WEST_STAIR_X0 and pos.x <= WEST_STAIR_X1 and floor_index <= WEST_STAIR_TOP_FLOOR:
		return "West"
	if pos.x >= EAST_STAIR_X0 and pos.x <= EAST_STAIR_X1 and floor_index <= EAST_STAIR_TOP_FLOOR:
		return "East"
	return ""


## True when the named stairwell shaft physically links both floors.
static func stairwell_connects(stairwell: String, floor_a: int, floor_b: int) -> bool:
	var top: int = -1
	if stairwell == "West":
		top = WEST_STAIR_TOP_FLOOR
	elif stairwell == "East":
		top = EAST_STAIR_TOP_FLOOR
	return top >= 0 and floor_a <= top and floor_b <= top


static func is_in_corridor(pos: Vector3) -> bool:
	return floor_from_y(pos.y) < ROOF_FLOOR and absf(pos.z) <= CORRIDOR_HALF_WIDTH \
		and pos.x >= X_MIN and pos.x <= X_MAX


## The room dictionary containing `pos`, or an empty dictionary.
static func room_at(pos: Vector3) -> Dictionary:
	if not is_inside_footprint(pos):
		return {}
	var floor_index: int = floor_from_y(pos.y)
	if floor_index >= ROOF_FLOOR:
		return {}
	for room: Dictionary in ROOMS:
		if room["floor"] != floor_index:
			continue
		if pos.x >= room["x0"] and pos.x <= room["x1"] and pos.z >= room["z0"] and pos.z <= room["z1"]:
			return room
	return {}


## Room number 1..27, 28 for the rooftop deck, 0 for corridors/stairs/outside.
static func room_id_at(pos: Vector3) -> int:
	if is_inside_footprint(pos) and floor_from_y(pos.y) == ROOF_FLOOR:
		return ROOFTOP_ID
	var room: Dictionary = room_at(pos)
	if room.is_empty():
		return 0
	return room["id"]


static func room_by_id(room_id: int) -> Dictionary:
	for room: Dictionary in ROOMS:
		if room["id"] == room_id:
			return room
	return {}


static func room_center(room_id: int) -> Vector3:
	if room_id == ROOFTOP_ID:
		return Vector3(0.0, ROOF_Y, 0.0)
	var room: Dictionary = room_by_id(room_id)
	if room.is_empty():
		return Vector3.ZERO
	var x: float = (float(room["x0"]) + float(room["x1"])) * 0.5
	var z: float = (float(room["z0"]) + float(room["z1"])) * 0.5
	return Vector3(x, floor_y(room["floor"]), z)


## Front rooms face the street (+Z); back rooms face the creek (-Z).
static func is_front_room(room: Dictionary) -> bool:
	return float(room["z0"]) >= CORRIDOR_HALF_WIDTH - 0.01


## Human-readable location, e.g. "4F - Room 402 (#23)".
static func location_name(pos: Vector3) -> String:
	if not is_inside_footprint(pos, 0.2):
		return "Outside"
	var floor_index: int = floor_from_y(pos.y)
	if floor_index == ROOF_FLOOR:
		var hut: String = stairwell_at(pos)
		return "Rooftop - Stair Hut" if hut == "East" else "Rooftop (#28)"
	var stair: String = stairwell_at(pos)
	if stair != "":
		return "%s - %s Stairwell" % [floor_name(floor_index), stair]
	var room: Dictionary = room_at(pos)
	if not room.is_empty():
		return "%s - %s (#%d)" % [floor_name(floor_index), room["name"], room["id"]]
	return "%s - Corridor" % floor_name(floor_index)
