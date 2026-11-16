class_name RehasGate
extends StaticBody3D
## The roll-up security gate across the 1F Main Lobby entrance.
##
## It opens when the morning guard arrives (6:00 AM, or 3:30 AM after the
## rooftop SOS). Juan can also force it early, once the night lock has
## engaged at midnight, in three stages:
##   1. the Master Gate Key opens the padlock (quiet, 2 s);
##   2. bolt cutters cut the chain (loud, 12 s, progress kept);
##   3. a crowbar forces the jammed track (very loud, 18 s). Stop for more
##      than a moment and the track sags back down, losing progress.
## The loud stages wake every docked robot and the server relays Juan's
## position to all of them, so the breach is a stand, not a quick exit.

const LAYER_INTERACT: int = 2
const LAYER_DOORS: int = 8
const PADLOCK_TIME: float = 2.0
const CHAIN_TIME: float = 12.0
const TRACK_TIME: float = 18.0
const BREACH_TIME: float = PADLOCK_TIME + CHAIN_TIME + TRACK_TIME
const BREACH_NOISE: float = 30.0
const BREACH_NOISE_INTERVAL: float = 1.5
## Seconds off the track before it starts to sag, and how fast it sags
## (seconds of progress lost per second).
const TRACK_SAG_DELAY: float = 2.0
const TRACK_SAG_RATE: float = 1.0

@export var gate_width: float = 3.6
@export var gate_height: float = 2.5

var is_open: bool = false
var padlock_open: bool = false
var chain_progress: float = 0.0
var track_progress: float = 0.0
## Seconds of breaching already done, all stages together.
var breach_progress: float = 0.0

var _stage: StringName = &""
var _player: PlayerController = null
var _progress_rate: float = 1.0
var _rattle_timer: float = 0.0
var _idle_time: float = 0.0


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
	if TimeManager.elapsed_minutes < TimeManager.MIDNIGHT_ELAPSED:
		actions.append({"id": &"none", "label": "Security gate - the night lock is still engaging. The track won't budge until 12:00 AM."})
	elif not padlock_open:
		if inventory.has_item(ItemDB.REHAS_KEY):
			actions.append({"id": &"padlock", "label": "Unlock the gate's padlock (quiet)"})
		else:
			actions.append({"id": &"none", "label": "Security gate - padlocked, chained and jammed. Needs the Master Gate Key, bolt cutters and a crowbar."})
	elif chain_progress < CHAIN_TIME:
		if inventory.has_item(ItemDB.BOLT_CUTTERS):
			actions.append({"id": &"chain", "label": "Cut the gate's chain (%d s left - LOUD)" % int(ceil(CHAIN_TIME - chain_progress))})
		else:
			actions.append({"id": &"none", "label": "Security gate - unlocked, but chained shut. Needs bolt cutters."})
	elif inventory.has_item(ItemDB.CROWBAR):
		actions.append({"id": &"track", "label": "Force the jammed track (%d s left - VERY loud, sags back if you stop)"
			% int(ceil(TRACK_TIME - track_progress))})
	else:
		actions.append({"id": &"none", "label": "Security gate - the track is jammed. Needs a crowbar to force it."})
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	if is_open or TimeManager.elapsed_minutes < TimeManager.MIDNIGHT_ELAPSED:
		return
	_player = player
	_rattle_timer = 0.0
	match action_id:
		&"padlock":
			if padlock_open:
				return
			_stage = &"padlock"
			_progress_rate = 1.0
			player.start_channel("Unlocking the padlock", PADLOCK_TIME, _finish_padlock, {"can_fumble": true})
		&"chain":
			if not padlock_open or chain_progress >= CHAIN_TIME:
				return
			_start_loud(player, "Cutting the chain", CHAIN_TIME - chain_progress, &"chain", _finish_chain)
		&"track":
			if chain_progress < CHAIN_TIME:
				return
			_start_loud(player, "Forcing the jammed track", TRACK_TIME - track_progress, &"track", _finish_breach)


func _start_loud(player: PlayerController, label: String, remaining: float, stage: StringName, on_done: Callable) -> void:
	var channel_time: float = player.stats.get_channel_time(remaining)
	_progress_rate = remaining / maxf(channel_time, 0.01)
	_stage = stage
	player.start_channel(label, remaining, on_done, {
		"noise_type": &"gate_breach", "noise_radius": BREACH_NOISE, "noise_interval": BREACH_NOISE_INTERVAL,
		"can_fumble": false, "on_tick": _on_breach_tick,
	})


## Opens the gate. `method` is &"dawn_rescue", &"rooftop_sos" or &"gate_breach".
func open(method: StringName) -> void:
	if is_open:
		return
	is_open = true
	padlock_open = true
	chain_progress = CHAIN_TIME
	track_progress = TRACK_TIME
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


func _physics_process(delta: float) -> void:
	if is_open or track_progress <= 0.0:
		return
	_idle_time += delta
	if _idle_time > TRACK_SAG_DELAY and track_progress < TRACK_TIME:
		track_progress = maxf(track_progress - TRACK_SAG_RATE * delta, 0.0)
		_update_total()


func _on_breach_tick(delta: float) -> void:
	_idle_time = 0.0
	if _stage == &"chain":
		chain_progress = minf(chain_progress + delta * _progress_rate, CHAIN_TIME)
	elif _stage == &"track":
		track_progress = minf(track_progress + delta * _progress_rate, TRACK_TIME)
	_update_total()
	_rattle_timer -= delta
	if _rattle_timer <= 0.0:
		_rattle_timer = BREACH_NOISE_INTERVAL
		SfxSynth.play_at(self, SfxSynth.clatter(), global_position + Vector3.UP, 4.0, 0.6, 40.0)
		_raise_alarm()


## Every robot that is up hears exactly where Juan is working.
func _raise_alarm() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var robot := node as RobotBase
		if robot != null and robot.is_active:
			robot.alert_to(_player.global_position)


func _update_total() -> void:
	breach_progress = (PADLOCK_TIME if padlock_open else 0.0) + chain_progress + track_progress
	EventBus.gate_breach_progress.emit(breach_progress / BREACH_TIME)


func _finish_padlock() -> void:
	padlock_open = true
	_update_total()
	var padlock := get_node_or_null("Padlock") as Node3D
	if padlock != null:
		padlock.visible = false
	SfxSynth.play_at(self, SfxSynth.clatter(), global_position + Vector3.UP * 0.2, 1.0, 1.4, 6.0)


func _finish_chain() -> void:
	chain_progress = CHAIN_TIME
	_update_total()
	EventBus.ui_notification.emit("The chain drops. The track is still jammed - force it with a crowbar.", 4.0)


func _finish_breach() -> void:
	open(&"gate_breach")
