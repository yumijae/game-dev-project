class_name RehasGate
extends StaticBody3D
## The roll-up security gate across the 1F Main Lobby entrance.
##
## It opens when the morning guard arrives (6:00 AM, or 3:30 AM after the
## rooftop SOS). Juan can also force it early, once the night lock has
## engaged at midnight, in three stages:
##   1. the Master Gate Key opens the padlock (quiet, 2 s);
##   2. bolt cutters cut the chain (loud, 12 s, progress kept);
##   3. the combination padlock on the side: four digits, new every night.
##      The guards keep forgetting it, so the digits are written down round
##      the school (GateCodeHints). A wrong code rattles the lock loudly.
##      Right code: the gate is hauled up (loud, LIFT_TIME) and it is open.
## The loud stages wake every docked robot and the server relays Juan's
## position to all of them, so the breach is a stand, not a quick exit.

const LAYER_INTERACT: int = 2
const LAYER_DOORS: int = 8
const PADLOCK_TIME: float = 2.0
const CHAIN_TIME: float = 12.0
const LIFT_TIME: float = 4.0
const BREACH_TIME: float = PADLOCK_TIME + CHAIN_TIME + LIFT_TIME
const BREACH_NOISE: float = 30.0
const BREACH_NOISE_INTERVAL: float = 1.5
const CODE_LENGTH: int = 4
## A wrong combination: the shackle rattles against the gate.
const WRONG_CODE_NOISE: float = 12.0

@export var gate_width: float = 3.6
@export var gate_height: float = 2.5

var is_open: bool = false
var padlock_open: bool = false
var chain_progress: float = 0.0
var code_open: bool = false
var lift_progress: float = 0.0
## Seconds of breaching already done, all stages together.
var breach_progress: float = 0.0
## Tonight's combination for the side padlock.
var combination: PackedInt32Array = PackedInt32Array()

var _stage: StringName = &""
var _player: PlayerController = null
var _progress_rate: float = 1.0
var _rattle_timer: float = 0.0
var _side_lock: Node3D = null


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
	for i: int in CODE_LENGTH:
		combination.append(randi_range(0, 9))
	_build_side_lock()


func get_interactions(player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_open:
		return actions
	var inventory: InventoryComponent = player.inventory
	if TimeManager.elapsed_minutes < TimeManager.MIDNIGHT_ELAPSED:
		actions.append({"id": &"none", "label": "Security gate - the night lock is still engaging. Nothing will budge until 12:00 AM."})
	elif not padlock_open:
		if inventory.has_item(ItemDB.REHAS_KEY):
			actions.append({"id": &"padlock", "label": "Unlock the gate's padlock (quiet)"})
		else:
			actions.append({"id": &"none", "label": "Security gate - padlocked, chained, and a combination lock on the side. The padlock needs the Master Gate Key."})
	elif chain_progress < CHAIN_TIME:
		if inventory.has_item(ItemDB.BOLT_CUTTERS):
			actions.append({"id": &"chain", "label": "Cut the gate's chain (%d s left - LOUD)" % int(ceil(CHAIN_TIME - chain_progress))})
		else:
			actions.append({"id": &"none", "label": "Security gate - unlocked, but chained shut. Needs bolt cutters."})
	elif not code_open:
		actions.append({"id": &"dial", "label": "Dial the side lock's combination (a wrong code rattles - loud)"})
	else:
		actions.append({"id": &"lift", "label": "Haul the gate up (%d s left - VERY loud)" % int(ceil(LIFT_TIME - lift_progress))})
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
		&"dial":
			if chain_progress < CHAIN_TIME or code_open:
				return
			CombinationDial.open_for(player, self)
		&"lift":
			if not code_open:
				return
			_start_loud(player, "Hauling the gate up", LIFT_TIME - lift_progress, &"lift", _finish_breach)


## The dial's answer. True when it was tonight's code.
func try_combination(digits: PackedInt32Array, by: Node) -> bool:
	if code_open or chain_progress < CHAIN_TIME:
		return code_open
	if digits == combination:
		code_open = true
		_update_total()
		SfxSynth.play_at(self, SfxSynth.latch_click(), _side_lock.global_position, 2.0, 0.8, 8.0)
		SfxSynth.play_at(self, SfxSynth.clatter(), _side_lock.global_position, -4.0, 1.3, 8.0)
		(_side_lock.get_node("Shackle") as Node3D).position.y += 0.025
		EventBus.ui_notification.emit("The lock springs open. Now haul the gate up.", 3.5)
		return true
	NoiseManager.emit_noise(_side_lock.global_position, WRONG_CODE_NOISE, &"metal_clatter", by if by != null else self)
	SfxSynth.play_at(self, SfxSynth.clatter(), _side_lock.global_position, 0.0, 1.1, 20.0)
	EventBus.ui_notification.emit("Wrong combination. The lock rattles against the gate.", 2.5)
	return false


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
	code_open = true
	lift_progress = LIFT_TIME
	breach_progress = BREACH_TIME
	var collider := get_node_or_null("Shape") as CollisionShape3D
	if collider != null:
		collider.set_deferred("disabled", true)
	var padlock := get_node_or_null("Padlock") as Node3D
	if padlock != null:
		padlock.visible = false
	if _side_lock != null:
		_side_lock.visible = false
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
	if _stage == &"chain":
		chain_progress = minf(chain_progress + delta * _progress_rate, CHAIN_TIME)
	elif _stage == &"lift":
		lift_progress = minf(lift_progress + delta * _progress_rate, LIFT_TIME)
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
	breach_progress = (PADLOCK_TIME if padlock_open else 0.0) + chain_progress + lift_progress
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
	EventBus.ui_notification.emit("The chain drops. One lock left: the combination padlock on the side.", 4.0)


func _finish_breach() -> void:
	open(&"gate_breach")


## A heavy brass four-wheel combination padlock through a steel hasp bolted
## across the gate's east edge and the wall, its dial window (four white
## digits) facing into the lobby at waist height. Sized up from a real
## padlock so it reads from across the lobby by flashlight.
func _build_side_lock() -> void:
	_side_lock = Node3D.new()
	_side_lock.name = "SideLock"
	_side_lock.position = Vector3(gate_width * 0.5 - 0.06, 1.05, -0.07)
	add_child(_side_lock)
	var brass := _lock_mat(Color(0.72, 0.56, 0.2), 0.85, 0.32)
	var steel := _lock_mat(Color(0.6, 0.61, 0.63), 0.9, 0.3)
	var dark := _lock_mat(Color(0.05, 0.05, 0.05), 0.0, 0.6)
	# Hasp: a steel plate across the gap between the gate and the wall, with
	# four bolt heads and the staple the shackle goes through.
	_lock_box(Vector3(0.24, 0.09, 0.012), Vector3(0.0, 0.11, 0.022), steel)
	for x: float in [-0.095, -0.06, 0.06, 0.095]:
		var bolt := MeshInstance3D.new()
		var head := CylinderMesh.new()
		head.top_radius = 0.008
		head.bottom_radius = 0.008
		head.height = 0.008
		head.material = steel
		bolt.mesh = head
		bolt.rotation.x = PI * 0.5
		bolt.position = Vector3(x, 0.11, 0.012)
		_side_lock.add_child(bolt)
	# Body.
	_lock_box(Vector3(0.11, 0.13, 0.045), Vector3.ZERO, brass)
	# Shackle through the staple.
	var shackle := MeshInstance3D.new()
	shackle.name = "Shackle"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.032
	torus.outer_radius = 0.042
	torus.material = steel
	shackle.mesh = torus
	shackle.rotation.x = PI * 0.5
	shackle.position.y = 0.085
	_side_lock.add_child(shackle)
	# The dial window: a dark strip with four number wheels showing through.
	_lock_box(Vector3(0.092, 0.036, 0.004), Vector3(0.0, -0.02, -0.0235), dark)
	var digits := Label3D.new()
	digits.name = "Digits"
	digits.text = "0  0  0  0"
	digits.font = MenuKit.caps_font()
	digits.font_size = 40
	digits.pixel_size = 0.0006
	digits.modulate = Color(0.92, 0.9, 0.84)
	digits.outline_size = 0
	digits.shaded = true
	digits.double_sided = false
	# Label3D faces +Z; the window faces -Z (the lobby).
	digits.rotation.y = PI
	digits.position = Vector3(0.0, -0.02, -0.0262)
	_side_lock.add_child(digits)
	# A worn brand stamp above the window.
	var stamp := Label3D.new()
	stamp.text = "SECURE"
	stamp.font = MenuKit.caps_font()
	stamp.font_size = 22
	stamp.pixel_size = 0.0006
	stamp.modulate = Color(0.35, 0.26, 0.08)
	stamp.outline_size = 0
	stamp.shaded = true
	stamp.double_sided = false
	stamp.rotation.y = PI
	stamp.position = Vector3(0.0, 0.03, -0.0228)
	_side_lock.add_child(stamp)


func _lock_mat(colour: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.metallic = metallic
	material.roughness = roughness
	return material


func _lock_box(size: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	box.mesh = mesh
	box.position = at
	_side_lock.add_child(box)
	return box
