class_name GameDirector
extends Node
## Runs one night at STI College Kalibo: cuts the power, puts Juan Dela Cruz at his desk
## in Room 402, keeps the Expo robots docked until midnight, tolls the hour,
## and handles winning, dying and restarting.

const START_ROOM_ID: int = 23
const EMERGENCY_LIGHT_ENERGY: float = 0.5
const EMERGENCY_LIGHT_RANGE: float = 5.5
## Lamps further than this from the camera are culled outright.
const EMERGENCY_FADE_BEGIN: float = 22.0
const EMERGENCY_FADE_LENGTH: float = 4.0
## Battery emergency lamps: the only steady light left, and it is red.
const EMERGENCY_LIGHT_COLOR: Color = Color(1.0, 0.13, 0.08)
const SERVER_HUM_POSITION: Vector3 = Vector3(-1.5, 3.8 + 1.4, -4.6)

## Debug builds only: F9 jumps to 11:59 PM, F10 skips one hour.
@export var enable_debug_keys: bool = true

## Set once WARDEN's circuit is dead: no more robots reboot after that.
var _lab_power_dead: bool = false
var is_game_over: bool = false

var _player: PlayerController = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	TimeManager.reset()
	NoiseManager.clear()
	_player = get_tree().get_first_node_in_group(&"player") as PlayerController
	_apply_night_lighting()
	var atmosphere := AtmosphereDirector.new()
	atmosphere.name = "AtmosphereDirector"
	add_child(atmosphere)
	var dresser := SetDresser.new()
	dresser.name = "SetDresser"
	add_child(dresser)
	var hints := GateCodeHints.new()
	hints.name = "GateCodeHints"
	add_child(hints)
	_place_player()
	_lock_main_entrance()
	_seal_under_stairs()
	_start_server_hum()
	_spawn_robots.call_deferred()
	EventBus.midnight_started.connect(_on_midnight)
	EventBus.lab_power_cut.connect(_on_lab_power_cut)
	EventBus.time_advanced.connect(_on_minute_for_robots)
	EventBus.noise_emitted.connect(_on_noise_for_docks)
	EventBus.hour_struck.connect(_on_hour_struck)
	EventBus.rescue_arrived.connect(_on_rescue_arrived)
	EventBus.game_won.connect(_on_game_won)
	EventBus.game_lost.connect(_on_game_lost)
	TimeManager.start()
	_wake_up_bang.call_deferred()
	# Built now, not on the first catch: an 18 ms stall mid-jumpscare shows.
	SfxSynth.screech.call_deferred()
	var culler := FloorCuller.new()
	culler.name = "FloorCuller"
	add_child(culler)
	var pause_menu := PauseMenu.new()
	pause_menu.name = "PauseMenu"
	pause_menu.director = self
	add_child(pause_menu)
	# The night's Environment and lights now exist: fit them to the player's
	# quality settings.
	GameSettings.apply_world()
	GameSettings.apply_world.call_deferred()


## The Expo robots, parked on the Com Sci Lab's charging docks (in dock order).
## Each faces into the lab. Later robots get added to ROBOT_SCRIPTS.
const ROBOT_SCRIPTS: Array[String] = ["res://entities/robots/pose_ai.gd", "res://entities/robots/concierge_ai.gd",
	"res://entities/robots/scuttle_ai.gd", "res://entities/robots/prototype_ai.gd"]
const LAB_CENTER := Vector2(6.0, -4.6)


func _spawn_robots() -> void:
	var docks: Array[Node] = get_tree().get_nodes_in_group(&"robot_docks")
	docks.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name) < String(b.name))
	var holder := Node3D.new()
	holder.name = "Robots"
	get_tree().current_scene.add_child(holder)
	for i in mini(ROBOT_SCRIPTS.size(), docks.size()):
		var dock := docks[i] as Node3D
		var robot: RobotBase = load(ROBOT_SCRIPTS[i]).new()
		holder.add_child(robot)
		var at: Vector3 = dock.global_position
		var look := Vector3(LAB_CENTER.x - at.x, 0.0, LAB_CENTER.y - at.z).normalized()
		robot.dock_at(Transform3D(Basis.looking_at(look, Vector3.UP), at))
	# The CpE group left the lab propped open while setting up; without it the
	# robots with no hands would never get out.
	for node: Node in get_tree().get_nodes_in_group(&"doors"):
		var door := node as InteractableDoor
		if door != null and String(door.name).contains("Com Sci Lab"):
			door.set_open(true)


## 11:45 PM: the main breaker trips somewhere below with a bang. That is what
## wakes Juan; his phone had finished charging before the power died.
func _wake_up_bang() -> void:
	SfxSynth.play_ui(self, SfxSynth.thud(), 6.0, 0.5)
	SfxSynth.play_ui(self, SfxSynth.latch_click(), -2.0, 0.45)
	await get_tree().create_timer(0.35).timeout
	SfxSynth.play_ui(self, SfxSynth.thud(), -4.0, 0.38)
	await get_tree().create_timer(1.4).timeout
	EventBus.ui_subtitle.emit("...What was that bang? It's dark. 11:45. And the charger's dead - phone's only on 35%.", 6.0, &"Juan")
	EventBus.take_chatter_turn(0.0)   # story line: the small talk waits after it


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if is_game_over and key.physical_keycode == KEY_R:
		restart()
	elif enable_debug_keys and OS.is_debug_build() and not is_game_over:
		if key.physical_keycode == KEY_F9:
			TimeManager.skip_to(23, 59)
		elif key.physical_keycode == KEY_F10:
			var target: int = TimeManager.elapsed_minutes + 60
			TimeManager.skip_to(TimeManager.hour_of(target), TimeManager.minute_of(target))


func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


# ---------------------------------------------------------------------- setup

## The power is out. Only the stairwell emergency lamps stay on, and the
## computer-lab monitors keep a faint standby glow.
func _apply_night_lighting() -> void:
	var school: Node = get_tree().get_first_node_in_group(&"school")
	if school == null:
		return
	LightRig.seal_geometry(school)
	var lights: Node = school.get_node_or_null("Lights")
	if lights != null:
		for node: Node in lights.get_children():
			var light := node as OmniLight3D
			if light == null:
				continue
			if Campus.stairwell_at(light.global_position) != "":
				light.light_energy = EMERGENCY_LIGHT_ENERGY
				light.light_color = EMERGENCY_LIGHT_COLOR
				light.omni_range = EMERGENCY_LIGHT_RANGE
				# Without shadows the red glow passes straight through the
				# stairwell walls and slabs into the rooms around it. The lamps
				# never move, so their shadow maps are only redrawn when
				# something walks past.
				light.omni_attenuation = 1.5
				light.light_specular = 0.25
				LightRig.seal(light, 0.08)
				light.distance_fade_enabled = true
				light.distance_fade_begin = EMERGENCY_FADE_BEGIN
				light.distance_fade_shadow = EMERGENCY_FADE_BEGIN
				light.distance_fade_length = EMERGENCY_FADE_LENGTH
				light.add_to_group(&"ambient_lights")
			else:
				light.visible = false
	# Signs are unlit by default and would glow in the dark.
	for node: Node in school.find_children("*", "Label3D", true, false):
		(node as Label3D).shaded = true
	_kill_prop_emission(school)
	_dim_emissive(school, "Visual/Mesh_lightpanel", 0.0)
	_dim_emissive(school, "Visual/Mesh_screen", 0.12)


## Imported props (the ceiling fans' bulbs especially) ship with emission on
## and would glow in a blackout. Battery signs live under Signs and keep theirs.
func _kill_prop_emission(school: Node) -> void:
	var props: Node = school.get_node_or_null("Props")
	if props == null:
		return
	var unlit: Dictionary = {}
	for node: Node in props.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		for surface: int in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface) as BaseMaterial3D
			if material == null or not material.emission_enabled:
				continue
			if not unlit.has(material):
				var dark := material.duplicate() as BaseMaterial3D
				dark.emission_enabled = false
				unlit[material] = dark
			instance.set_surface_override_material(surface, unlit[material])


func _dim_emissive(school: Node, path: String, energy: float) -> void:
	var instance := school.get_node_or_null(path) as MeshInstance3D
	if instance == null or instance.mesh == null:
		return
	var material := instance.mesh.surface_get_material(0) as StandardMaterial3D
	if material == null:
		return
	var night_material := material.duplicate() as StandardMaterial3D
	night_material.emission_energy_multiplier = energy
	if energy <= 0.0:
		night_material.albedo_color = Color(0.5, 0.5, 0.5)
	else:
		# A screen on standby is black glass with the faintest glow, not a
		# flat blue panel.
		night_material.albedo_color = Color(0.012, 0.014, 0.02)
		night_material.roughness = 0.08
		night_material.metallic_specular = 0.6
		night_material.emission_energy_multiplier = energy * 0.05
	instance.material_override = night_material


## Juan wakes at a desk in Room 402 (#23) on the fourth floor.
func _place_player() -> void:
	if _player == null:
		return
	var spawn := get_tree().get_first_node_in_group(&"player_spawn") as Node3D
	if spawn != null:
		_player.global_transform = spawn.global_transform
	else:
		_player.global_position = Campus.room_center(START_ROOM_ID) + Vector3(0.0, 0.05, -2.0)
	_player.velocity = Vector3.ZERO


## On 1F the space under each stair landing (and, through it, the hollow
## under the bottom flight) was open: only 1.7 m high, yet Juan could squeeze
## in past the fire exit and end up inside the stairs' concrete, seeing
## through the walls. Closes it off: a solid block under the landing and a
## plastered wall facing anyone who walks under the upper flight.
func _seal_under_stairs() -> void:
	var school: Node = get_tree().get_first_node_in_group(&"school")
	if school == null:
		return
	var plaster: Material = null
	var walls := school.get_node_or_null("Visual/Mesh_int") as MeshInstance3D
	if walls != null and walls.mesh != null and walls.mesh.get_surface_count() > 0:
		plaster = walls.mesh.surface_get_material(0)
	if plaster == null:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.74, 0.71, 0.66)
		flat.roughness = 0.95
		plaster = flat
	# Stairwell interiors (inside the walls) and where the landing begins.
	const LANDING_EDGE: float = -5.6
	const BACK_WALL: float = -7.875
	const UNDERSIDE: float = 1.69
	for span: Vector2 in [Vector2(-11.875, -9.075), Vector2(9.075, 11.875)]:
		var width: float = span.y - span.x
		var depth: float = LANDING_EDGE - BACK_WALL
		var centre := Vector3((span.x + span.y) * 0.5, UNDERSIDE * 0.5, (LANDING_EDGE + BACK_WALL) * 0.5)
		var block := StaticBody3D.new()
		block.name = "UnderStairSeal"
		block.collision_layer = 1
		block.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(width, UNDERSIDE, depth)
		shape.shape = box
		block.add_child(shape)
		var face := MeshInstance3D.new()
		var panel := BoxMesh.new()
		panel.size = Vector3(width, UNDERSIDE, 0.02)
		panel.material = plaster
		face.mesh = panel
		face.position = Vector3(0.0, 0.0, depth * 0.5 - 0.01)
		block.add_child(face)
		school.add_child(block)
		block.global_position = centre


func _lock_main_entrance() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"main_entrance"):
		node.set("locked", true)


func _start_server_hum() -> void:
	var hum := AudioStreamPlayer3D.new()
	hum.name = "ServerHum"
	hum.stream = SfxSynth.server_hum()
	hum.volume_db = -8.0
	hum.max_distance = 9.0
	hum.unit_size = 2.5
	add_child(hum)
	hum.global_position = SERVER_HUM_POSITION
	hum.play()


# --------------------------------------------------------------------- events

## WARDEN's circuit died: thrown at the LP-2F breaker, or the UPS ran dry.
func _on_lab_power_cut(cause: StringName) -> void:
	_lab_power_dead = true
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var hostile := node as Hostile
		if hostile != null:
			hostile.on_power_cut(cause)
	if cause == &"breaker":
		EventBus.ui_notification.emit("Next door, the lab's servos wind down. The cameras are dead.", 5.0)
	else:
		EventBus.ui_notification.emit("A long last beep from the Server Room. The backup power is gone - and the cameras with it.", 5.0)
	EventBus.objective_updated.emit(&"power_cut", "The server and the cameras are dead. Something in the lab still has its own battery. Get out.", 1.0)


## 12:00 AM: the update finishes and the robots reboot one at a time (each
## RobotBase.wake_minute): POSE now, SCUTTLE at 12:45, CONCIERGE at 1:30.
## PROTOTYPE is not on WARDEN's circuit and waits for the power to die.
func _on_midnight() -> void:
	_wake_due_robots()
	EventBus.ui_subtitle.emit("12:00. Somewhere downstairs, something just... whirred.", 4.5, &"Juan")
	EventBus.take_chatter_turn(0.0)   # story line: the small talk waits after it


func _on_minute_for_robots(_h: int, _m: int, _f: String, _p: float) -> void:
	if TimeManager.elapsed_minutes >= TimeManager.MIDNIGHT_ELAPSED:
		_wake_due_robots()


## Forcing the gate shakes the whole building. The docks' wake-on-vibration
## trips and every robot still charging reboots at once, update finished or
## not - so the gate cannot be had for free in the quiet minutes before
## midnight (or before the later robots are due).
func _on_noise_for_docks(_origin: Vector3, _radius: float, noise_type: StringName, _source: Node) -> void:
	if noise_type != &"gate_breach" or _lab_power_dead or is_game_over:
		return
	var woke: bool = false
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var robot := node as RobotBase
		if robot == null or robot.is_active or robot.is_disabled or not robot.is_docked or robot is PrototypeAI:
			continue
		robot.activate()
		EventBus.robot_online.emit(robot.display_name)
		woke = true
	if woke:
		EventBus.ui_notification.emit("Upstairs, docks unlatch one after another. The noise woke them.", 5.0)


func _wake_due_robots() -> void:
	if _lab_power_dead:
		return
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		var robot := node as RobotBase
		if robot == null or robot.is_active or robot.is_disabled or not robot.is_docked:
			continue
		if robot is PrototypeAI or TimeManager.elapsed_minutes < robot.wake_minute:
			continue
		robot.activate()
		EventBus.robot_online.emit(robot.display_name)


## The bell tolls once per hour on the clock (12 at midnight).
func _on_hour_struck(hour: int, _aggression_level: int) -> void:
	var tolls: int = 12 if hour % 12 == 0 else hour % 12
	_toll(tolls)


func _toll(count: int) -> void:
	for i: int in count:
		if not is_inside_tree() or is_game_over:
			return
		SfxSynth.play_ui(self, SfxSynth.bell(), -7.0)
		await get_tree().create_timer(1.5).timeout


## Dawn: the building powers down its threats. A 3:30 AM rescue does not.
func _on_rescue_arrived() -> void:
	if TimeManager.elapsed_minutes >= TimeManager.DAWN_ELAPSED:
		for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
			var hostile := node as Hostile
			if hostile != null:
				hostile.deactivate()
		EventBus.ui_notification.emit("6:00 AM. First light. The robots have stopped. The guard is at the gate.", 6.0)
	else:
		EventBus.ui_notification.emit("Headlights on the street. Rescue is at the Main Lobby gate!", 6.0)


func _on_game_won(_ending_id: StringName, _title: String, _description: String) -> void:
	_end_game()


func _on_game_lost(_cause: String) -> void:
	_end_game()


func _end_game() -> void:
	if is_game_over:
		return
	is_game_over = true
	TimeManager.stop()
	await get_tree().create_timer(0.6).timeout
	if is_inside_tree():
		get_tree().paused = true
