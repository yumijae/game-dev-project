class_name InventoryComponent
extends Node
## Juan's carrying capacity: two hand slots and a six-slot backpack.
## Slots 0 and 1 are the left and right hand; slots 2-7 are the backpack.

const HAND_SLOTS: int = 2
const BACKPACK_SLOTS: int = 6
const TOTAL_SLOTS: int = HAND_SLOTS + BACKPACK_SLOTS
const LEFT_HAND: int = 0
const RIGHT_HAND: int = 1

## Each slot is {} when empty or {"id": StringName, "count": int}.
var slots: Array[Dictionary] = []
var active_hand: int = RIGHT_HAND
## The STI ID lanyard is worn, not carried, so it uses no slot.
var has_lanyard: bool = true
## Most Juan can carry, in kg: he cannot hoard every extinguisher and tool.
const MAX_LOAD: float = 20.0
## Above this he slows down, more the heavier the load; above SPRINT_LOAD he
## cannot run at all.
const SLOW_LOAD: float = 6.0
const SPRINT_LOAD: float = 14.0
## Why the last add_item() took less than offered: &"weight" or &"space".
var last_refusal: StringName = &""


func _init() -> void:
	slots.resize(TOTAL_SLOTS)
	for i: int in TOTAL_SLOTS:
		slots[i] = {}


func is_slot_empty(index: int) -> bool:
	return slots[index].is_empty()


func get_slot_id(index: int) -> StringName:
	if slots[index].is_empty():
		return &""
	return slots[index]["id"]


func get_slot_count(index: int) -> int:
	if slots[index].is_empty():
		return 0
	return slots[index]["count"]


func get_active_item() -> StringName:
	return get_slot_id(active_hand)


func count_of(item_id: StringName) -> int:
	var total: int = 0
	for i: int in TOTAL_SLOTS:
		if get_slot_id(i) == item_id:
			total += get_slot_count(i)
	return total


func has_item(item_id: StringName, count: int = 1) -> bool:
	return count_of(item_id) >= count


func has_in_hands(item_id: StringName) -> bool:
	return get_slot_id(LEFT_HAND) == item_id or get_slot_id(RIGHT_HAND) == item_id


## Adds up to `count` items and returns how many did NOT fit.
## Stacks first, then empty backpack slots, then empty hands.
func add_item(item_id: StringName, count: int = 1) -> int:
	if not ItemDB.has(item_id) or count <= 0:
		return count
	last_refusal = &""
	var kg: float = ItemDB.get_weight(item_id)
	var allowed: int = count
	if kg > 0.0:
		allowed = mini(count, int(floor((MAX_LOAD - get_load() + 0.0001) / kg)))
	if allowed <= 0:
		last_refusal = &"weight"
		return count
	var refused_for_weight: int = count - allowed
	var remaining: int = allowed
	var max_stack: int = ItemDB.get_max_stack(item_id)
	for i: int in TOTAL_SLOTS:
		if remaining <= 0:
			break
		if get_slot_id(i) == item_id and get_slot_count(i) < max_stack:
			var added: int = mini(max_stack - get_slot_count(i), remaining)
			slots[i]["count"] = get_slot_count(i) + added
			remaining -= added
	var order: Array[int] = [RIGHT_HAND, LEFT_HAND]
	if not ItemDB.is_hands_only(item_id):
		order = [2, 3, 4, 5, 6, 7, RIGHT_HAND, LEFT_HAND]
	for i: int in order:
		if remaining <= 0:
			break
		if is_slot_empty(i):
			var added: int = mini(max_stack, remaining)
			slots[i] = {"id": item_id, "count": added}
			remaining -= added
	if remaining > 0:
		last_refusal = &"space"
	elif refused_for_weight > 0:
		last_refusal = &"weight"
	if remaining < allowed:
		EventBus.inventory_changed.emit()
	return remaining + refused_for_weight


## Removes `count` of an item from anywhere. False (and no change) if short.
## Total weight carried, in kg.
func get_load() -> float:
	var total: float = 0.0
	for i: int in TOTAL_SLOTS:
		if not slots[i].is_empty():
			total += ItemDB.get_weight(slots[i]["id"]) * float(slots[i]["count"])
	return total


## True when one more `item_id` fits under the weight limit.
func can_lift(item_id: StringName) -> bool:
	return get_load() + ItemDB.get_weight(item_id) <= MAX_LOAD + 0.0001


## 1.0 when lightly loaded, down to 0.6 at the limit.
func get_speed_multiplier() -> float:
	var load: float = get_load()
	if load <= SLOW_LOAD:
		return 1.0
	return lerpf(1.0, 0.6, clampf((load - SLOW_LOAD) / (MAX_LOAD - SLOW_LOAD), 0.0, 1.0))


func remove_item(item_id: StringName, count: int = 1) -> bool:
	if count_of(item_id) < count:
		return false
	var remaining: int = count
	for i: int in range(TOTAL_SLOTS - 1, -1, -1):
		if remaining <= 0:
			break
		if get_slot_id(i) != item_id:
			continue
		var taken: int = mini(get_slot_count(i), remaining)
		remaining -= taken
		if get_slot_count(i) - taken <= 0:
			slots[i] = {}
		else:
			slots[i]["count"] = get_slot_count(i) - taken
	EventBus.inventory_changed.emit()
	return true


## Empties a slot and returns what it held ({} if it was empty).
func take_slot(index: int) -> Dictionary:
	var held: Dictionary = slots[index]
	slots[index] = {}
	if not held.is_empty():
		EventBus.inventory_changed.emit()
	return held


## Swaps a backpack slot (0-5) with the active hand.
func swap_backpack_with_hand(backpack_index: int) -> bool:
	var index: int = HAND_SLOTS + backpack_index
	if index < HAND_SLOTS or index >= TOTAL_SLOTS:
		return false
	if ItemDB.is_hands_only(get_slot_id(active_hand)):
		EventBus.ui_notification.emit("That will not fit in the backpack.", 1.8)
		return false
	var from_hand: Dictionary = slots[active_hand]
	slots[active_hand] = slots[index]
	slots[index] = from_hand
	EventBus.inventory_changed.emit()
	return true


func switch_active_hand() -> void:
	active_hand = LEFT_HAND if active_hand == RIGHT_HAND else RIGHT_HAND
	EventBus.inventory_changed.emit()


func clear() -> void:
	for i: int in TOTAL_SLOTS:
		slots[i] = {}
	EventBus.inventory_changed.emit()


