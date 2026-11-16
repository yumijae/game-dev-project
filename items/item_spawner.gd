class_name ItemSpawner
extends Node3D
## Stocks the campus when the night starts. Its Marker3D children are written
## by the map builder and carry "room_id" and "room_type" metadata.
##
## Story-critical items always appear in the rooms the design names (the gate
## key at the Cashier, fire extinguishers in the Kitchen and offices, the
## screwdrivers in the MIT Office and Staff Room, and so on). Leftover markers then get a
## chance at a common item so no two nights are stocked quite the same.

## Chance that a spare marker receives a random common item.
@export_range(0.0, 1.0) var filler_chance: float = 0.3
## 0 = different placement every run; anything else is a fixed seed.
@export var seed_value: int = 0

## room id -> [[item id, count], ...]
const GUARANTEED: Dictionary = {
	2: [[ItemDB.BLACKOUT_KIT, 2], [ItemDB.WATER, 1]],
	3: [[ItemDB.REHAS_KEY, 1]],
	4: [[ItemDB.FIRE_EXTINGUISHER, 3], [ItemDB.WATER, 1]],
	5: [[ItemDB.CROWBAR, 1], [ItemDB.SCREWDRIVER, 1], [ItemDB.ALCOHOL, 1], [ItemDB.GAUZE, 1], [ItemDB.CHAIR, 1]],
	6: [[ItemDB.BLACKOUT_KIT, 1]],
	7: [[ItemDB.LAN_CABLE, 2], [ItemDB.LAN_CABLE, 1]],
	8: [[ItemDB.LAN_CABLE, 2], [ItemDB.CHAIR, 1]],
	9: [[ItemDB.ALCOHOL, 1]],
	10: [[ItemDB.GAUZE, 1]],
	12: [[ItemDB.BOLT_CUTTERS, 1], [ItemDB.SCREWDRIVER, 1], [ItemDB.POWERBANK, 1], [ItemDB.LAN_CABLE, 1]],
	13: [[ItemDB.LAN_CABLE, 2], [ItemDB.SCREWDRIVER, 1]],
	15: [[ItemDB.CHAIR, 1], [ItemDB.BLACKOUT_KIT, 1]],
	17: [[ItemDB.CHAIR, 1]],
	18: [[ItemDB.FIRE_EXTINGUISHER, 3], [ItemDB.BLACKOUT_KIT, 1], [ItemDB.GAUZE, 1], [ItemDB.WATER, 1]],
	19: [[ItemDB.ALCOHOL, 1]],
	21: [[ItemDB.CHAIR, 1]],
	22: [[ItemDB.CHAIR, 1], [ItemDB.BLACKOUT_KIT, 1]],
	23: [[ItemDB.WATER, 1], [ItemDB.CHAIR, 1]],
	24: [[ItemDB.FIRE_EXTINGUISHER, 3], [ItemDB.GLASS_BOTTLE, 2], [ItemDB.GLASS_BOTTLE, 1], [ItemDB.WATER, 1]],
	25: [[ItemDB.CHAIR, 1]],
	26: [[ItemDB.GLASS_BOTTLE, 2], [ItemDB.GLASS_BOTTLE, 1]],
	27: [[ItemDB.TABLECLOTH_RAG, 2], [ItemDB.TABLECLOTH_RAG, 1], [ItemDB.GLASS_BOTTLE, 1], [ItemDB.WATER, 1]],
}

## Things that belong on the floor, stood or laid against a wall, never on a
## desk: the tall extinguisher and the long gate tools.
const FLOOR_ITEMS: Array[StringName] = [ItemDB.FIRE_EXTINGUISHER, ItemDB.CROWBAR, ItemDB.BOLT_CUTTERS]
## A marker this far above the room's floor is a desk, shelf or counter top.
const SURFACE_HEIGHT: float = 0.1
## Nothing is set down closer than this to a doorway (leaves swing, robots pass).
const DOOR_CLEARANCE: float = 1.1
const SOLID_MASK: int = 1 | 8 | 16

## Where things already lie tonight: [position, footprint radius].
var _placed: Array = []
## World boxes of small set-dressing props (toolboxes, crates, laptops): they
## have no collision, so an item put "on the table" could sit inside one.
var _clutter: Array[AABB] = []
var _clutter_ready: bool = false

## room type -> common items a spare marker may receive.
const FILLER: Dictionary = {
	"classroom": [ItemDB.WATER, ItemDB.BLACKOUT_KIT, ItemDB.GLASS_BOTTLE],
	"complab": [ItemDB.LAN_CABLE, ItemDB.WATER],
	"robolab": [ItemDB.LAN_CABLE, ItemDB.POWERBANK],
	"kitchen": [ItemDB.GLASS_BOTTLE, ItemDB.WATER],
	"pantry": [ItemDB.GLASS_BOTTLE],
	"dining": [ItemDB.TABLECLOTH_RAG, ItemDB.WATER, ItemDB.GLASS_BOTTLE],
	"faculty": [ItemDB.WATER, ItemDB.GAUZE],
	"staff": [ItemDB.WATER, ItemDB.GLASS_BOTTLE],
	"restroom": [ItemDB.GAUZE],
	"admissions": [ItemDB.BLACKOUT_KIT],
	"cashier": [ItemDB.BLACKOUT_KIT],
	"mit": [ItemDB.LAN_CABLE],
	"server": [ItemDB.LAN_CABLE],
}


func _ready() -> void:
	# Placement looks at walls, furniture and doors, which only answer physics
	# queries once the level has had a physics frame.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var by_room: Dictionary = _collect_markers(rng)
	for room_id: int in GUARANTEED:
		var markers: Array = by_room.get(room_id, [])
		var entries: Array = GUARANTEED[room_id].duplicate()
		# Bulky things first, so they get the open floor before the rest.
		entries.sort_custom(func(a: Array, b: Array) -> bool: return _footprint(a[0]) > _footprint(b[0]))
		for entry: Array in entries:
			_place(entry[0], entry[1], markers, room_id, rng)
		by_room[room_id] = markers
	for room_id: int in by_room:
		var spare: Array = by_room[room_id].duplicate()
		for marker: Marker3D in spare:
			if rng.randf() > filler_chance:
				continue
			var room_type: String = marker.get_meta("room_type", "")
			var pool: Array = FILLER.get(room_type, [])
			if pool.is_empty():
				continue
			var item_id: StringName = pool[rng.randi_range(0, pool.size() - 1)]
			var at: Vector3 = marker.global_position
			if not _is_floor_marker(marker, room_id):
				at = _clear_of_clutter(at)
				if at == Vector3.INF:
					continue
			if _is_crowded(at, _footprint(item_id)) or _near_door(at):
				continue
			if _is_floor_marker(marker, room_id):
				# Loose in the middle of the floor looks dropped by the level
				# builder: slide it to the foot of the nearest wall instead.
				var snapped: Dictionary = _against_wall(at, item_id, room_id)
				if snapped.is_empty():
					continue
				at = snapped["position"]
				_spawn(item_id, 1, at, snapped["yaw"])
				continue
			_spawn(item_id, 1, at, NAN)


## Puts one guaranteed item in its room, on the kind of spot that suits it.
func _place(item_id: StringName, count: int, markers: Array, room_id: int, rng: RandomNumberGenerator) -> void:
	var wants_floor: bool = ItemDB.is_hands_only(item_id) or item_id in FLOOR_ITEMS
	var radius: float = _footprint(item_id)
	# First choice: a marker of the right kind. Second: any free marker, for
	# small things only (an extinguisher never goes on a desk).
	for pass_index: int in 2:
		for i: int in markers.size():
			var marker: Marker3D = markers[i]
			var on_floor: bool = _is_floor_marker(marker, room_id)
			if pass_index == 0 and on_floor != wants_floor:
				continue
			if pass_index == 1 and wants_floor and not on_floor:
				continue
			var at: Vector3 = marker.global_position
			if not on_floor:
				at = _clear_of_clutter(at)
				if at == Vector3.INF:
					continue
			if _is_crowded(at, radius) or (on_floor and _near_door(at)):
				continue
			var facing: float = NAN
			if on_floor and not ItemDB.is_hands_only(item_id):
				var snapped: Dictionary = _against_wall(at, item_id, room_id)
				if not snapped.is_empty():
					at = snapped["position"]
					facing = snapped["yaw"]
			markers.remove_at(i)
			_spawn(item_id, count, at, facing)
			return
	# The room has no suitable marker left: find a clear patch of its floor.
	var spot: Dictionary = _free_floor_spot(item_id, room_id, rng)
	_spawn(item_id, count, spot["position"], spot["yaw"])


## `at` if no small prop covers it, else the nearest clear spot on the same
## surface. Vector3.INF when the prop leaves no room.
func _clear_of_clutter(at: Vector3) -> Vector3:
	if not _clutter_ready:
		_clutter_ready = true
		for node: Node in get_tree().current_scene.find_children("*", "MeshInstance3D", true, false):
			var instance := node as MeshInstance3D
			if instance.mesh == null or is_ancestor_of(instance) or not instance.is_visible_in_tree():
				continue
			var box: AABB = instance.global_transform * instance.mesh.get_aabb()
			if maxf(box.size.x, box.size.z) < 0.5 and box.size.y > 0.05 and box.size.y < 0.5:
				_clutter.append(box.grow(0.04))
	if not _inside_clutter(at):
		return at
	var space := get_world_3d().direct_space_state
	for reach: float in [0.2, 0.3, 0.4]:
		for step: int in 8:
			var angle: float = TAU * float(step) / 8.0
			var spot: Vector3 = at + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
			if _inside_clutter(spot):
				continue
			# Still on the same table top, not off its edge.
			var query := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.05, spot + Vector3.DOWN * 0.03, SOLID_MASK)
			if not space.intersect_ray(query).is_empty():
				return spot
	return Vector3.INF


func _inside_clutter(at: Vector3) -> bool:
	var probe: Vector3 = at + Vector3.UP * 0.04
	for box: AABB in _clutter:
		if box.has_point(probe) and box.end.y > probe.y + 0.03:
			return true
	return false


func _spawn(item_id: StringName, count: int, at: Vector3, facing: float) -> void:
	WorldItem.spawn(self, item_id, count, at, facing)
	_placed.append([at, _footprint(item_id)])


## Half the widest side of the item, as seen from above.
func _footprint(item_id: StringName) -> float:
	var size: Vector3 = ItemDB.get_size(item_id)
	return maxf(size.x, size.z) * 0.5


func _is_floor_marker(marker: Marker3D, room_id: int) -> bool:
	return absf(marker.global_position.y - _floor_level(marker.global_position, room_id)) < SURFACE_HEIGHT


func _floor_level(at: Vector3, room_id: int) -> float:
	if not Campus.room_by_id(room_id).is_empty():
		return Campus.room_center(room_id).y
	return Campus.floor_y(Campus.floor_from_y(at.y + 0.3))


## True when something already lies where this item's footprint would be.
func _is_crowded(at: Vector3, radius: float) -> bool:
	for entry: Array in _placed:
		var other: Vector3 = entry[0]
		if absf(other.y - at.y) > 0.6:
			continue
		var gap: float = Vector2(other.x - at.x, other.z - at.z).length()
		if gap < radius + float(entry[1]) + 0.08:
			return true
	return false


func _near_door(at: Vector3) -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as InteractableDoor
		if door == null:
			continue
		var center: Vector3 = door.get_center()
		if absf(center.y - at.y) < 1.5 and Vector2(center.x - at.x, center.z - at.z).length() < DOOR_CLEARANCE:
			return true
	return false


## True when the item standing at `at` touches nothing solid. With a `facing`
## its real outline is tested, turned that way; without, a square that covers
## it at any angle.
func _fits(at: Vector3, item_id: StringName, facing: float = NAN) -> bool:
	var size: Vector3 = ItemDB.get_size(item_id)
	var shape := BoxShape3D.new()
	var basis := Basis.IDENTITY
	if is_nan(facing):
		var side: float = maxf(size.x, size.z)
		shape.size = Vector3(side, maxf(size.y, 0.06), side)
	else:
		shape.size = Vector3(maxf(size.x - 0.02, 0.02), maxf(size.y, 0.06), maxf(size.z - 0.02, 0.02))
		basis = Basis(Vector3.UP, facing)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(basis, at + Vector3.UP * (shape.size.y * 0.5 + 0.04))
	query.collision_mask = SOLID_MASK
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## The spot at the foot of the wall nearest to `at`, in the same room, where
## the item stands clear of doors, furniture and other items. Empty when there
## is none within reach. "yaw" turns the item's face into the room, which lays
## a long tool along the wall.
func _against_wall(at: Vector3, item_id: StringName, room_id: int) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var size: Vector3 = ItemDB.get_size(item_id)
	# Its long side lies along the wall, so only its depth (z) stands off it.
	var depth: float = size.z * 0.5 + 0.05
	var hits: Array = []
	for step: int in 8:
		var angle: float = TAU * float(step) / 8.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var from: Vector3 = at + Vector3.UP * 0.3
		var query := PhysicsRayQueryParameters3D.create(from, from + direction * 3.0, 1)
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if absf(normal.y) > 0.2:
			continue
		var point: Vector3 = hit["position"]
		hits.append([from.distance_to(point), point, normal])
	hits.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for entry: Array in hits:
		var normal: Vector3 = entry[2]
		var flat := Vector3(normal.x, 0.0, normal.z).normalized()
		var point: Vector3 = entry[1]
		var spot := Vector3(point.x + flat.x * depth, at.y, point.z + flat.z * depth)
		if not Campus.room_by_id(room_id).is_empty() and Campus.room_id_at(spot + Vector3.UP * 0.3) != room_id:
			continue
		var facing: float = atan2(flat.x, flat.z)
		if _near_door(spot) or _is_crowded(spot, _footprint(item_id)) or not _fits(spot, item_id, facing):
			continue
		if not _has_floor(spot) or not _can_be_reached(spot):
			continue
		return {"position": spot, "yaw": facing}
	return {}


func _has_floor(at: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.2, at + Vector3.DOWN * 0.1, 1)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Somewhere within arm's length has standing room for Juan and a clear line
## to the item, so nothing ends up walled in behind furniture.
func _can_be_reached(at: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var body := CapsuleShape3D.new()
	body.radius = 0.3
	body.height = 1.6
	for ring: float in [0.7, 1.1, 1.5]:
		for step: int in 8:
			var angle: float = TAU * float(step) / 8.0
			var stand: Vector3 = at + Vector3(cos(angle) * ring, 0.0, sin(angle) * ring)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = body
			query.transform = Transform3D(Basis.IDENTITY, stand + Vector3.UP * 0.95)
			query.collision_mask = SOLID_MASK
			if not space.intersect_shape(query, 1).is_empty() or not _has_floor(stand):
				continue
			var eye: Vector3 = stand + Vector3.UP * 1.6
			var sight := PhysicsRayQueryParameters3D.create(eye, at + Vector3.UP * 0.1, SOLID_MASK)
			if space.intersect_ray(sight).is_empty():
				return true
	return false


## A clear patch of the room's own floor for something that found no marker,
## against a wall if possible. Falls back to the middle of the room.
func _free_floor_spot(item_id: StringName, room_id: int, rng: RandomNumberGenerator) -> Dictionary:
	var room: Dictionary = Campus.room_by_id(room_id)
	var level: float = Campus.room_center(room_id).y
	if not room.is_empty():
		var x0: float = float(room["x0"]) + 0.7
		var x1: float = float(room["x1"]) - 0.7
		var z0: float = float(room["z0"]) + 0.7
		var z1: float = float(room["z1"]) - 0.7
		for _attempt: int in 60:
			var probe := Vector3(rng.randf_range(x0, x1), level, rng.randf_range(z0, z1))
			if not _has_floor(probe):
				continue
			var snapped: Dictionary = _against_wall(probe, item_id, room_id)
			if not snapped.is_empty():
				return snapped
		for _attempt: int in 60:
			var probe := Vector3(rng.randf_range(x0, x1), level, rng.randf_range(z0, z1))
			if _has_floor(probe) and _fits(probe, item_id) and not _near_door(probe) \
					and not _is_crowded(probe, _footprint(item_id)) and _can_be_reached(probe):
				return {"position": probe, "yaw": NAN}
	return {"position": Campus.room_center(room_id), "yaw": NAN}


func _collect_markers(rng: RandomNumberGenerator) -> Dictionary:
	var by_room: Dictionary = {}
	for child: Node in get_children():
		var marker := child as Marker3D
		if marker == null:
			continue
		var room_id: int = marker.get_meta("room_id", 0)
		if not by_room.has(room_id):
			by_room[room_id] = []
		var list: Array = by_room[room_id]
		list.append(marker)
	for room_id: int in by_room:
		var list: Array = by_room[room_id]
		for i: int in range(list.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swap: Variant = list[i]
			list[i] = list[j]
			list[j] = swap
	return by_room
