extends Node
## Physics and architectural acoustic simulation for "Huling Kampana".
## Autoload: NoiseManager
## Simulates spatial falloff, heavy solid concrete floor attenuation, and stairwell acoustic chimneys.

const FLOOR_HEIGHT := 3.8
const SLAB_THICKNESS := 0.25

# Acoustic attenuation constants (in Decibels)
const DB_PER_FLOOR_SLAB := 24.0        # Heavy dampening through solid concrete floor/ceiling
const DB_PER_STAIRWELL_FLOOR := 5.0     # Chimney effect: open vertical stairwell shaft
const DB_PER_WALL_OBSTRUCTION := 8.0    # Sound crossing interior room partitions
const DB_REFERENCE_DISTANCE := 1.0      # 1 meter reference distance
const STAIRWELL_PROXIMITY_RADIUS := 4.0 # Distance to stairwell to catch acoustic funneling

# Stairwell bounding areas
const WEST_STAIRS := {
	"x0": -12.0, "x1": -9.0,
	"z0": -8.0,  "z1": -1.2,
	"min_floor": 0, "max_floor": 3 # 1F to 4F
}

const EAST_STAIRS := {
	"x0": 9.0,   "x1": 12.0,
	"z0": -8.0,  "z1": -1.2,
	"min_floor": 0, "max_floor": 4 # 1F to Roof
}

## Canonical STI College Kalibo 28-room definitions:
## [floor (0=1F..4=Roof), name, type, x0, z0, x1, z1]
const ROOM_MAP: Array[Dictionary] = [
	# 1F
	{"floor": 0, "name": "Admissions Office", "x0": -12.0, "z0": 1.2, "x1": -3.0, "z1": 8.0},
	{"floor": 0, "name": "Main Lobby", "x0": -3.0, "z0": 1.2, "x1": 3.0, "z1": 8.0},
	{"floor": 0, "name": "Cashier & Registrar", "x0": 3.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"floor": 0, "name": "Director's Office", "x0": -9.0, "z0": -8.0, "x1": -3.0, "z1": -1.2},
	{"floor": 0, "name": "Staff Room", "x0": -3.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"floor": 0, "name": "Records Room", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
	# 2F
	{"floor": 1, "name": "Computer Lab 1", "x0": -12.0, "z0": 1.2, "x1": 0.0, "z1": 8.0},
	{"floor": 1, "name": "Computer Lab 2", "x0": 0.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"floor": 1, "name": "Male Restroom 2F", "x0": -9.0, "z0": -8.0, "x1": -6.0, "z1": -1.2},
	{"floor": 1, "name": "Female Restroom 2F", "x0": -6.0, "z0": -8.0, "x1": -3.0, "z1": -1.2},
	{"floor": 1, "name": "Server Room", "x0": -3.0, "z0": -8.0, "x1": 0.0, "z1": -1.2},
	{"floor": 1, "name": "MIT Office", "x0": 0.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"floor": 1, "name": "Computer Lab 3", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
	# 3F
	{"floor": 2, "name": "Room 301", "x0": -12.0, "z0": 1.2, "x1": -6.0, "z1": 8.0},
	{"floor": 2, "name": "Room 302", "x0": -6.0, "z0": 1.2, "x1": 0.0, "z1": 8.0},
	{"floor": 2, "name": "Room 303", "x0": 0.0, "z0": 1.2, "x1": 6.0, "z1": 8.0},
	{"floor": 2, "name": "Room 304", "x0": 6.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"floor": 2, "name": "Faculty Room", "x0": -9.0, "z0": -8.0, "x1": -3.0, "z1": -1.2},
	{"floor": 2, "name": "Male Restroom 3F", "x0": -3.0, "z0": -8.0, "x1": 0.0, "z1": -1.2},
	{"floor": 2, "name": "Female Restroom 3F", "x0": 0.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"floor": 2, "name": "Room 305", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
	# 4F
	{"floor": 3, "name": "Room 401", "x0": -12.0, "z0": 1.2, "x1": -6.0, "z1": 8.0},
	{"floor": 3, "name": "Room 402", "x0": -6.0, "z0": 1.2, "x1": 0.0, "z1": 8.0},
	{"floor": 3, "name": "Culinary Kitchen", "x0": 0.0, "z0": 1.2, "x1": 12.0, "z1": 8.0},
	{"floor": 3, "name": "Room 403", "x0": -9.0, "z0": -8.0, "x1": 0.0, "z1": -1.2},
	{"floor": 3, "name": "Pantry", "x0": 0.0, "z0": -8.0, "x1": 3.0, "z1": -1.2},
	{"floor": 3, "name": "Culinary Dining", "x0": 3.0, "z0": -8.0, "x1": 9.0, "z1": -1.2},
]

# Structure for recent active sound events (retained for 2.0 seconds)
class NoiseEvent:
	var origin: Vector3
	var floor_level: int
	var loudness_db: float
	var noise_type: StringName
	var timestamp: float

var _recent_noises: Array[NoiseEvent] = []
const NOISE_RETENTION_TIME := 2.0
var _event_bus: Node = null


func _get_event_bus() -> Node:
	if not _event_bus and is_inside_tree():
		_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Prune old noise events
	while not _recent_noises.is_empty() and (now - _recent_noises[0].timestamp) > NOISE_RETENTION_TIME:
		_recent_noises.pop_front()


# ==============================================================================
# NOISE EMISSION & PROPAGATION
# ==============================================================================

## Emits a sound into the campus acoustics and notifies EventBus.
func emit_noise(origin: Vector3, radius: float, loudness_db: float, noise_type: StringName) -> void:
	var floor_idx := get_floor_index(origin.y)
	
	var ev := NoiseEvent.new()
	ev.origin = origin
	ev.floor_level = floor_idx
	ev.loudness_db = loudness_db
	ev.noise_type = noise_type
	ev.timestamp = Time.get_ticks_msec() / 1000.0
	_recent_noises.append(ev)

	var bus := _get_event_bus()
	if bus:
		bus.noise_emitted.emit(origin, floor_idx, radius, loudness_db, noise_type)


## Calculates the perceived loudness (in dB) received at `listener_pos`.
## Returns decibels (audible threshold is typically >= 10 dB).
func calculate_perceived_loudness(listener_pos: Vector3, noise_origin: Vector3, initial_db: float) -> float:
	var dist := listener_pos.distance_to(noise_origin)
	if dist < 0.1:
		return initial_db

	# 1. Distance attenuation (Inverse square law: -20 * log10(d / d0))
	var distance_loss: float = 20.0 * log(maxf(dist, DB_REFERENCE_DISTANCE)) / log(10.0)
	var perceived_db: float = initial_db - distance_loss

	# 2. Floor slab & Stairwell chimney attenuation
	var source_floor := get_floor_index(noise_origin.y)
	var listener_floor := get_floor_index(listener_pos.y)
	var floor_diff := absi(listener_floor - source_floor)

	if floor_diff > 0:
		var stairwell_conduit := _check_stairwell_acoustic_conduit(noise_origin, listener_pos, source_floor, listener_floor)
		if stairwell_conduit != &"":
			# Chimney effect: sound traveled through the stair shaft
			perceived_db -= (DB_PER_STAIRWELL_FLOOR * floor_diff)
		else:
			# Blocked by solid concrete floor slabs
			perceived_db -= (DB_PER_FLOOR_SLAB * floor_diff)

	# 3. Room partition attenuation (if on same floor but in different rooms)
	if floor_diff == 0:
		var source_room := get_room_name(noise_origin)
		var listener_room := get_room_name(listener_pos)
		if source_room != listener_room and source_room != "Corridor" and listener_room != "Corridor":
			perceived_db -= DB_PER_WALL_OBSTRUCTION

	return perceived_db


## Returns all recent noises that exceed `hearing_threshold_db` at `listener_pos`.
func get_audible_noises_for(listener_pos: Vector3, hearing_threshold_db: float = 15.0) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for ev in _recent_noises:
		var perceived := calculate_perceived_loudness(listener_pos, ev.origin, ev.loudness_db)
		if perceived >= hearing_threshold_db:
			results.append({
				"origin": ev.origin,
				"floor": ev.floor_level,
				"noise_type": ev.noise_type,
				"perceived_db": perceived,
				"age": (Time.get_ticks_msec() / 1000.0) - ev.timestamp
			})
	return results


# ==============================================================================
# SPATIAL & ARCHITECTURAL UTILITIES
# ==============================================================================

## Returns floor index: 0=1F, 1=2F, 2=3F, 3=4F, 4=Roof.
func get_floor_index(y_pos: float) -> int:
	if y_pos >= (FLOOR_HEIGHT * 4.0):
		return 4 # Roof
	return clampi(int(floor(y_pos / FLOOR_HEIGHT)), 0, 3)


## Returns the room name at a given 3D position or "Corridor" / "Exterior" / "Stairwell".
func get_room_name(pos: Vector3) -> String:
	var stair := is_in_stairwell(pos)
	if stair != &"":
		return String(stair)

	var floor_idx := get_floor_index(pos.y)
	if floor_idx == 4:
		return "Rooftop"

	# Check central corridor
	if pos.z >= -1.2 and pos.z <= 1.2 and pos.x >= -12.0 and pos.x <= 12.0:
		return "Corridor %s" % _floor_name(floor_idx)

	# Check rooms
	for r in ROOM_MAP:
		if r["floor"] == floor_idx:
			if pos.x >= r["x0"] and pos.x <= r["x1"] and pos.z >= r["z0"] and pos.z <= r["z1"]:
				return r["name"]

	return "Exterior / Yard"


## Returns &"West Stairwell", &"East Stairwell", or &"".
func is_in_stairwell(pos: Vector3) -> StringName:
	var fl := get_floor_index(pos.y)
	if pos.z >= WEST_STAIRS["z0"] and pos.z <= WEST_STAIRS["z1"] and pos.x >= WEST_STAIRS["x0"] and pos.x <= WEST_STAIRS["x1"]:
		if fl <= WEST_STAIRS["max_floor"]:
			return &"West Stairwell"

	if pos.z >= EAST_STAIRS["z0"] and pos.z <= EAST_STAIRS["z1"] and pos.x >= EAST_STAIRS["x0"] and pos.x <= EAST_STAIRS["x1"]:
		if fl <= EAST_STAIRS["max_floor"]:
			return &"East Stairwell"

	return &""


## Checks if both origin and listener have an open acoustic path through a stairwell.
func _check_stairwell_acoustic_conduit(src: Vector3, dst: Vector3, src_floor: int, dst_floor: int) -> StringName:
	var min_fl := mini(src_floor, dst_floor)
	var max_fl := maxi(src_floor, dst_floor)

	# Check West Stairwell validity
	if max_fl <= WEST_STAIRS["max_floor"]:
		var w_center := Vector2((WEST_STAIRS["x0"] + WEST_STAIRS["x1"]) * 0.5, (WEST_STAIRS["z0"] + WEST_STAIRS["z1"]) * 0.5)
		var d_src := Vector2(src.x, src.z).distance_to(w_center)
		var d_dst := Vector2(dst.x, dst.z).distance_to(w_center)
		if d_src <= STAIRWELL_PROXIMITY_RADIUS and d_dst <= STAIRWELL_PROXIMITY_RADIUS:
			return &"West Stairwell"

	# Check East Stairwell validity
	if max_fl <= EAST_STAIRS["max_floor"]:
		var e_center := Vector2((EAST_STAIRS["x0"] + EAST_STAIRS["x1"]) * 0.5, (EAST_STAIRS["z0"] + EAST_STAIRS["z1"]) * 0.5)
		var d_src := Vector2(src.x, src.z).distance_to(e_center)
		var d_dst := Vector2(dst.x, dst.z).distance_to(e_center)
		if d_src <= STAIRWELL_PROXIMITY_RADIUS and d_dst <= STAIRWELL_PROXIMITY_RADIUS:
			return &"East Stairwell"

	return &""


func _floor_name(idx: int) -> String:
	match idx:
		0: return "1F"
		1: return "2F"
		2: return "3F"
		3: return "4F"
		4: return "Roof"
		_: return "Unknown"
