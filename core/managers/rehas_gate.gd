class_name RehasGate
extends StaticBody3D
## The roll-up security gate across the 1F Main Lobby entrance.
##
## It opens when the morning guard arrives (6:00 AM, or 3:30 AM after the
## rooftop SOS). Juan can also force it early: with the Master Gate Key for
## the padlock and bolt cutters or a crowbar for the chained track, a 20-second
## breach that everything in the building can hear. Progress is kept if he has
## to break off and fight.

const LAYER_INTERACT: int = 2
const LAYER_DOORS: int = 8
const BREACH_TIME: float = 20.0
const BREACH_NOISE: float = 30.0
const BREACH_NOISE_INTERVAL: float = 1.5

@export var gate_width: float = 3.6
@export var gate_height: float = 2.5

var is_open: bool = false
## Seconds of breaching already done.
var breach_progress: float = 0.0

var _progress_rate: float = 1.0
var _rattle_timer: float = 0.0


static func create(width: float, height: float) -> RehasGate:
	var gate := RehasGate.new()
	gate.gate_width = width
	gate.gate_height = height
	gate.collision_layer = LAYER_INTERACT | LAYER_DOORS
	gate.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, 0.08)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position.y = height * 0.5
	gate.add_child(collider)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.44, 0.47)
	steel.metallic = 0.8
	steel.roughness = 0.4
	var grille := Node3D.new()
	grille.name = "Grille"
	gate.add_child(grille)
	var slat_count: int = int(height / 0.14)
	for i: int in slat_count:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, 0.035, 0.03)
		mesh.material = steel
		var slat := MeshInstance3D.new()
		slat.mesh = mesh
		slat.position.y = 0.07 + float(i) * 0.14
		grille.add_child(slat, true)
	var bar_count: int = int(width / 0.3)
	for i: int in bar_count + 1:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.025, height, 0.025)
		mesh.material = steel
		var bar := MeshInstance3D.new()
		bar.mesh = mesh
		bar.position = Vector3(-width * 0.5 + float(i) * width / float(bar_count), height * 0.5, 0.0)
		grille.add_child(bar, true)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.75, 0.6, 0.2)
	brass.metallic = 0.9
	brass.roughness = 0.35
	var lock_mesh := BoxMesh.new()
	lock_mesh.size = Vector3(0.1, 0.13, 0.06)
	lock_mesh.material = brass
	var padlock := MeshInstance3D.new()
	padlock.name = "Padlock"
	padlock.mesh = lock_mesh
	padlock.position = Vector3(0.0, 0.2, -0.05)
	gate.add_child(padlock)
	return gate


func _ready() -> void:
	add_to_group(&"rehas_gate")


func get_interactions(player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_open:
		return actions
	var inventory: InventoryComponent = player.inventory
	var has_key: bool = inventory.has_item(ItemDB.REHAS_KEY)
	var has_tool: bool = inventory.has_item(ItemDB.BOLT_CUTTERS) or inventory.has_item(ItemDB.CROWBAR)
	if has_key and has_tool:
		actions.append({"id": &"breach", "label": "Unlock and force the security gate (%d s left - VERY loud)"
			% int(ceil(BREACH_TIME - breach_progress))})
	elif has_key:
		actions.append({"id": &"none", "label": "Security gate - the track is chained. Needs bolt cutters or a crowbar."})
	elif has_tool:
		actions.append({"id": &"none", "label": "Security gate - padlocked. Needs the Master Gate Key."})
	else:
		actions.append({"id": &"none", "label": "Security gate - padlocked and chained until the morning guard comes."})
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	if action_id != &"breach" or is_open:
		return
	var remaining: float = BREACH_TIME - breach_progress
	var channel_time: float = player.stats.get_channel_time(remaining)
	_progress_rate = remaining / maxf(channel_time, 0.01)
	_rattle_timer = 0.0
	player.start_channel("Forcing the security gate", remaining, _finish_breach, {
		"noise_type": &"gate_breach", "noise_radius": BREACH_NOISE, "noise_interval": BREACH_NOISE_INTERVAL,
		"can_fumble": false, "on_tick": _on_breach_tick,
	})


## Opens the gate. `method` is &"dawn_rescue", &"rooftop_sos" or &"gate_breach".
func open(method: StringName) -> void:
	if is_open:
		return
	is_open = true
	breach_progress = BREACH_TIME
	var collider := get_node_or_null("Shape") as CollisionShape3D
	if collider != null:
		collider.set_deferred("disabled", true)
	var padlock := get_node_or_null("Padlock") as Node3D
	if padlock != null:
		padlock.visible = false
	var grille := get_node_or_null("Grille") as Node3D
	if grille != null:
		var tween: Tween = create_tween().set_trans(Tween.TRANS_SINE)
		tween.tween_property(grille, "scale:y", 0.04, 1.6)
		tween.parallel().tween_property(grille, "position:y", gate_height * 0.96, 1.6)
	SfxSynth.play_at(self, SfxSynth.scrape(), global_position + Vector3.UP * 1.5, 6.0, 0.7)
	for node: Node in get_tree().get_nodes_in_group(&"main_entrance"):
		if node.has_method("force_open"):
			node.call("force_open")
	EventBus.gate_opened.emit(method)


func _on_breach_tick(delta: float) -> void:
	breach_progress = minf(breach_progress + delta * _progress_rate, BREACH_TIME)
	EventBus.gate_breach_progress.emit(breach_progress / BREACH_TIME)
	_rattle_timer -= delta
	if _rattle_timer <= 0.0:
		_rattle_timer = BREACH_NOISE_INTERVAL
		SfxSynth.play_at(self, SfxSynth.clatter(), global_position + Vector3.UP, 4.0, 0.6, 40.0)


func _finish_breach() -> void:
	open(&"gate_breach")
