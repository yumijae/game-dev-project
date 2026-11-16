class_name HidingSpot
extends StaticBody3D
## A place to go to ground: a locker (Staff Room #5, Faculty Room #18), a
## restroom stall (#9, #10, #19, #20), the kneehole of a teacher's desk, or the
## space under a PC bench.
##
## Hiding breaks line of sight, but not the nose or the ears: a scent trail
## that ends here, or ragged breathing below 30% Stamina, still leads an
## Aswang to the door.

const LAYER_INTERACT: int = 2

const LABELS: Dictionary = {
	&"locker": "Hide inside the locker",
	&"stall": "Hide in the stall",
	&"desk": "Crawl under the desk",
	&"bench": "Crawl under the PC bench",
	&"island": "Crawl under the prep table",
}

@export var kind: StringName = &"locker"
## Where Juan ends up, in this node's local space.
@export var hide_offset: Vector3 = Vector3.ZERO
## Where he steps back out to, in this node's local space.
@export var exit_offset: Vector3 = Vector3(0.0, 0.0, 0.8)
## Camera height while hidden (low under desks and benches).
@export var eye_height: float = 1.5

var occupant: PlayerController = null


## `volume` is the clickable box, centred `volume.y / 2` above the node.
static func create(spot_kind: StringName, volume: Vector3, hide_at: Vector3, exit_at: Vector3,
		eye: float = 1.5) -> HidingSpot:
	var spot := HidingSpot.new()
	spot.kind = spot_kind
	spot.eye_height = eye
	spot.hide_offset = hide_at
	spot.exit_offset = exit_at
	spot.collision_layer = LAYER_INTERACT
	spot.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = volume
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position.y = volume.y * 0.5
	spot.add_child(collider)
	return spot


func _ready() -> void:
	add_to_group(&"hiding_spots")


func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	var label: String = LABELS.get(kind, "Hide here")
	return [{"id": &"hide", "label": label}]


func interact(player: PlayerController, _action_id: StringName) -> void:
	player.enter_hiding(self)


func get_hide_position() -> Vector3:
	return to_global(hide_offset)


func get_exit_position() -> Vector3:
	return to_global(exit_offset)


func is_occupied() -> bool:
	return occupant != null
