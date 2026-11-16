extends Area3D
## A pick-up. Look at it and press E. Built entirely from code so the spawner
## can create any item from the loot table without separate scenes.

const RARITY_COLORS := {
	"common": Color(0.85, 0.85, 0.85),
	"uncommon": Color(0.3, 0.9, 0.35),
	"rare": Color(0.25, 0.55, 1.0),
	"epic": Color(0.75, 0.35, 1.0),
	"legendary": Color(1.0, 0.7, 0.15),
}

@export var item_name := "Item"
@export var value := 10
@export var rarity := "common"
@export var size := Vector3(0.3, 0.1, 0.2)

var _mesh: MeshInstance3D
var _t := randf() * TAU


func _ready() -> void:
	collision_layer = 2 # "loot" layer, only hit by the player's interact ray
	collision_mask = 0
	monitoring = false

	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	var col: Color = RARITY_COLORS.get(rarity, Color.WHITE)
	mat.albedo_color = col
	mat.emission_enabled = rarity != "common"
	mat.emission = col
	mat.emission_energy_multiplier = 0.6
	box.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = box
	_mesh.position.y = size.y * 0.5 + 0.02
	add_child(_mesh)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size.max(Vector3.ONE * 0.25) # generous hitbox for small items
	cs.shape = shape
	cs.position = _mesh.position
	add_child(cs)

	if rarity in ["epic", "legendary"]:
		var light := OmniLight3D.new()
		light.light_color = col
		light.omni_range = 1.5
		light.light_energy = 0.8
		light.position.y = 0.3
		add_child(light)


func _process(delta: float) -> void:
	_t += delta
	_mesh.rotation.y = _t * 0.8
	_mesh.position.y = size.y * 0.5 + 0.02 + sin(_t * 2.0) * 0.02


func get_prompt() -> String:
	return "[E] Take %s  (%s, %d)" % [item_name, rarity, value]


func interact(player: Node) -> void:
	if player.has_method("add_loot"):
		player.add_loot(item_name, value, rarity)
	queue_free()
