class_name WorldItem
extends Area3D
## A pickup lying in the world. Built from ItemDB so no per-item scenes are
## needed; ItemModel builds what it looks like.

const LAYER_ITEMS: int = 2

@export var item_id: StringName = &""
@export var count: int = 1

## Which way it faces; NAN leaves it at whatever angle it was set down.
var yaw: float = NAN

var _model: Node3D = null


## Creates a pickup under `parent` at a global position.
static func spawn(parent: Node, id: StringName, amount: int, at: Vector3, facing: float = NAN) -> WorldItem:
	var item := WorldItem.new()
	item.item_id = id
	item.count = amount
	item.yaw = facing
	item.name = "Item_%s" % id
	parent.add_child(item)
	item.global_position = at
	return item


func _ready() -> void:
	collision_layer = LAYER_ITEMS
	collision_mask = 0
	monitoring = false
	add_to_group(&"world_items")
	var size: Vector3 = ItemDB.get_size(item_id)
	# The object itself, set down at whatever angle it was left.
	_model = ItemModel.build(item_id)
	_model.position.y = 0.003
	_model.rotation.y = randf() * TAU if is_nan(yaw) else yaw
	add_child(_model)
	var shape := BoxShape3D.new()
	shape.size = size.max(Vector3(0.22, 0.18, 0.22))
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.size.y * 0.5
	add_child(collider)


func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	var label: String = ItemDB.get_item_name(item_id)
	if count > 1:
		label += " x%d" % count
	return [{"id": &"take", "label": "Take %s" % label}]


func interact(player: PlayerController, _action_id: StringName) -> void:
	var leftover: int = player.inventory.add_item(item_id, count)
	if leftover >= count:
		var reason: String = "Both hands are full." if ItemDB.is_hands_only(item_id) else "No room. Drop something first."
		if player.inventory.last_refusal == &"weight":
			reason = "Too heavy - you are already carrying %.1f of %d kg." % [player.inventory.get_load(), int(InventoryComponent.MAX_LOAD)]
		EventBus.ui_notification.emit(reason, 2.5)
		return
	if leftover > 0 and player.inventory.last_refusal == &"weight":
		EventBus.ui_notification.emit("You can only carry %d of them." % (count - leftover), 2.5)
	EventBus.item_picked_up.emit(item_id)
	EventBus.ui_notification.emit("Took %s" % ItemDB.get_item_name(item_id), 1.6)
	if leftover <= 0:
		queue_free()
	else:
		count = leftover
