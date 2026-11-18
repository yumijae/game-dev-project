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

var _found: Dictionary = {}


func _ready() -> void:
	add_to_group(&"gate_code_hints")
	EventBus.gate_code_hint_found.connect(func(index: int, digit: int) -> void: _found[index] = digit)
	# After the gate has rolled its code and the item spawner has stocked
	# the rooms (it waits two physics frames).
	for i: int in 5:
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
	var order: Array = [0, 1, 2, 3]
	order.shuffle()
	_place_on_desk(MEMO_ROOMS, CodeNote.Style.MEMO, order[0], gate.combination[order[0]])
	_place_on_desk(LAB_ROOMS, CodeNote.Style.STICKY, order[1], gate.combination[order[1]])
	_place_on_board(order[2], gate.combination[order[2]])
	_place_on_desk(TOP_ROOMS, CodeNote.Style.STICKY, order[3], gate.combination[order[3]])


func _place_on_desk(rooms: Array[int], style: CodeNote.Style, index: int, digit: int) -> void:
	var candidates: Array = []
	var shuffled: Array = rooms.duplicate()
	shuffled.shuffle()
	var spawns: Node = get_tree().get_first_node_in_group(&"school").get_node_or_null("ItemSpawns")
	if spawns == null:
		return
	for room_id: int in shuffled:
		var level: float = Campus.room_center(room_id).y
		for child: Node in spawns.get_children():
			var marker := child as Marker3D
			if marker == null or int(marker.get_meta("room_id", 0)) != room_id:
				continue
			var height: float = marker.global_position.y - level
			if height < SURFACE_MIN or height > SURFACE_MAX or _near_item(marker.global_position):
				continue
			# Same test the key uses: nothing over it, nothing on or beside it.
			if spawns.has_method("_key_spot_clear") and not spawns.call("_key_spot_clear", marker.global_position):
				continue
			candidates.append(marker.global_position)
		if not candidates.is_empty():
			break
	if candidates.is_empty():
		push_warning("GateCodeHints: nowhere to put digit %d" % (index + 1))
		return
	var note := CodeNote.create(style, index, digit)
	add_child(note)
	note.global_position = candidates.pick_random()
	note.rotation.y = randf_range(-0.5, 0.5)


## On the classroom board, off to one side of its middle.
func _place_on_board(index: int, digit: int) -> void:
	var room: Dictionary = Campus.room_by_id(BOARD_ROOMS.pick_random())
	# The corner rooms (x0 on the outside wall) are mirrored: board on x1.
	var mirrored: bool = absf(float(room["x0"]) - Campus.X_MIN) < 0.01
	var x: float = float(room["x1"]) - 0.135 if mirrored else float(room["x0"]) + 0.135
	var z: float = (float(room["z0"]) + float(room["z1"])) * 0.5 + randf_range(-0.9, 0.9)
	var note := CodeNote.create(CodeNote.Style.BOARD, index, digit)
	add_child(note)
	note.global_position = Vector3(x, Campus.floor_y(int(room["floor"])) + 1.55, z)
	note.rotation.y = -PI * 0.5 if mirrored else PI * 0.5


func _near_item(at: Vector3) -> bool:
	for item: Node in get_tree().get_nodes_in_group(&"world_items"):
		if (item as Node3D).global_position.distance_to(at) < ITEM_CLEARANCE:
			return true
	return false
