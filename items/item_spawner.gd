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
	var rng := RandomNumberGenerator.new()
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var by_room: Dictionary = _collect_markers(rng)
	for room_id: int in GUARANTEED:
		var markers: Array = by_room.get(room_id, [])
		var entries: Array = GUARANTEED[room_id]
		var used: Array[Vector3] = []
		for entry: Array in entries:
			var item_id: StringName = entry[0]
			var count: int = entry[1]
			var position: Vector3 = _take_position(markers, used, room_id, item_id, rng)
			used.append(position)
			WorldItem.spawn(self, item_id, count, position)
		by_room[room_id] = markers
	for room_id: int in by_room:
		var spare: Array = by_room[room_id]
		for marker: Marker3D in spare:
			if rng.randf() > filler_chance:
				continue
			var room_type: String = marker.get_meta("room_type", "")
			var pool: Array = FILLER.get(room_type, [])
			if pool.is_empty():
				continue
			var item_id: StringName = pool[rng.randi_range(0, pool.size() - 1)]
			WorldItem.spawn(self, item_id, 1, marker.global_position)


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


## Pops a marker for the item. Bulky items need a floor marker; when a room
## runs out of markers the item goes beside one that is already used.
func _take_position(markers: Array, used: Array[Vector3], room_id: int, item_id: StringName,
		rng: RandomNumberGenerator) -> Vector3:
	var floor_level: float = Campus.room_center(room_id).y
	var needs_floor: bool = ItemDB.is_hands_only(item_id)
	for i: int in markers.size():
		var marker: Marker3D = markers[i]
		var on_floor: bool = absf(marker.global_position.y - floor_level) < 0.1
		if needs_floor and not on_floor:
			continue
		markers.remove_at(i)
		return marker.global_position
	var angle: float = rng.randf() * TAU
	var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.3
	if not used.is_empty():
		var anchor: Vector3 = used[rng.randi_range(0, used.size() - 1)]
		if needs_floor:
			anchor.y = floor_level
		return anchor + offset
	return Campus.room_center(room_id) + offset
