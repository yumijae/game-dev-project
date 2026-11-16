class_name BreakerPanel
extends StaticBody3D
## LP-2F, the 2F Server Room panel fed by the UPS. When the robots' malfunction
## tripped the building's main breaker at 11:44 PM, this circuit stayed alive on
## the UPS: the server (and the virus on it), the CCTV and the Com Sci Lab's
## robot docks. Its red-handled main cuts all of that at once.
##
## Open the door, then hold to throw the main (slow and loud: the old switch
## sticks, then bangs over with a spark). Afterwards:
##   EventBus.lab_power_cut - every Hostile's on_power_cut() runs (robots on
##                            mains shut down), and the CCTV goes to NO SIGNAL.
##
## Built from boxes at run time; the generator only places the node with its
## back on the wall and its front (+Z) facing the room.

const LAYER_INTERACT: int = 2
const SIZE := Vector3(0.62, 0.86, 0.16)
const CUT_TIME: float = 3.5
const CUT_NOISE: float = 16.0
const DOOR_OPEN_DEG: float = -105.0
const LEVER_ON_DEG: float = -35.0
const LEVER_OFF_DEG: float = 40.0

var is_door_open: bool = false
var is_power_cut: bool = false

var _door_pivot: Node3D = null
var _lever_pivot: Node3D = null
var _led: MeshInstance3D = null
var _led_mat: StandardMaterial3D = null
var _sparks: CPUParticles3D = null
var _hum: AudioStreamPlayer3D = null
var _tween: Tween = null
var _strain: float = 0.0


static func create() -> BreakerPanel:
	var panel := BreakerPanel.new()
	panel.collision_layer = LAYER_INTERACT
	panel.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = SIZE + Vector3(0.04, 0.04, 0.06)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position = Vector3(0, SIZE.y * 0.5, SIZE.z * 0.5 + 0.03)
	panel.add_child(collider)
	return panel


func _ready() -> void:
	add_to_group(&"breaker_panel")
	_build()
	EventBus.lab_power_cut.connect(_on_power_cut)


# ------------------------------------------------------------ interaction

func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if not is_door_open:
		actions.append({"id": &"open", "label": "Open the breaker panel"})
		return actions
	if not is_power_cut:
		actions.append({"id": &"cut", "label": "Throw the UPS OUTPUT main breaker (%d s, loud)" % int(CUT_TIME)})
	actions.append({"id": &"close", "label": "Close the panel door"})
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	match action_id:
		&"open":
			_swing_door(true)
		&"close":
			_swing_door(false)
		&"cut":
			if is_power_cut:
				return
			var started: bool = player.start_channel("Forcing the main breaker", CUT_TIME, _finish_cut, {
				"noise_type": &"metal_clatter", "noise_radius": CUT_NOISE * 0.5, "noise_interval": 1.2,
				"can_fumble": false, "on_tick": _on_cut_tick, "on_cancel": _on_cut_cancel,
			})
			if started:
				SfxSynth.play_at(self, SfxSynth.scrape(), _lever_pivot.global_position, -8.0, 0.6)


func _swing_door(open: bool) -> void:
	is_door_open = open
	if _tween != null:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if open else Tween.EASE_IN_OUT)
	_tween.tween_property(_door_pivot, ^"rotation_degrees:y", DOOR_OPEN_DEG if open else 0.0, 0.55 if open else 0.4)
	SfxSynth.play_at(self, SfxSynth.latch_click(), global_position + global_basis.z * 0.2 + Vector3.UP, -6.0)
	if not open:
		_tween.tween_callback(func() -> void:
			SfxSynth.play_at(self, SfxSynth.knock(), global_position + Vector3.UP, -12.0, 1.6))


## The handle strains a little further the longer you lean on it.
func _on_cut_tick(delta: float) -> void:
	_strain = minf(_strain + delta / CUT_TIME, 1.0)
	_lever_pivot.rotation_degrees.x = LEVER_ON_DEG + 14.0 * _strain + randf_range(-1.5, 1.5)


func _on_cut_cancel(_elapsed: float) -> void:
	_strain = 0.0
	var t := create_tween()
	t.tween_property(_lever_pivot, ^"rotation_degrees:x", LEVER_ON_DEG, 0.25)


func _finish_cut() -> void:
	if is_power_cut:
		return
	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_lever_pivot, ^"rotation_degrees:x", LEVER_OFF_DEG, 0.09)
	NoiseManager.emit_noise(global_position, CUT_NOISE, &"metal_clatter", self)
	EventBus.lab_power_cut.emit(&"breaker")


func _on_power_cut(cause: StringName) -> void:
	is_power_cut = true
	if cause != &"breaker":
		# The UPS ran dry: no bang, the panel just goes dead.
		_led_mat.albedo_color = Color(0.03, 0.03, 0.03)
		_led_mat.emission_enabled = false
		_fade_hum()
		return
	_lever_pivot.rotation_degrees.x = LEVER_OFF_DEG
	var where: Vector3 = _lever_pivot.global_position
	SfxSynth.play_at(self, SfxSynth.thud(), where, 2.0, 0.8)
	SfxSynth.play_at(self, SfxSynth.latch_click(), where, 0.0, 0.5)
	_sparks.restart()
	_sparks.emitting = true
	_led_mat.albedo_color = Color(0.9, 0.08, 0.05)
	_led_mat.emission = Color(1.0, 0.1, 0.05)
	_fade_hum()


func _fade_hum() -> void:
	if _hum != null:
		var fade := create_tween()
		fade.tween_property(_hum, ^"pitch_scale", 0.35, 1.8)
		fade.parallel().tween_property(_hum, ^"volume_db", -60.0, 1.8)
		fade.tween_callback(_hum.stop)


# ------------------------------------------------------------ build

func _build() -> void:
	var paint := _mat(Color(0.52, 0.55, 0.55), 0.45, 0.5)
	var inside := _mat(Color(0.74, 0.75, 0.74), 0.6, 0.45)
	var black := _mat(Color(0.05, 0.05, 0.055), 0.0, 0.6)
	var w: float = SIZE.x
	var h: float = SIZE.y
	var d: float = SIZE.z
	var t: float = 0.015
	# Cabinet: back plate and four sides, so the inside shows with the door open.
	_box(Vector3(w, h, t), Vector3(0, h * 0.5, t * 0.5), paint)
	_box(Vector3(w, t, d), Vector3(0, t * 0.5, d * 0.5), paint)
	_box(Vector3(w, t, d), Vector3(0, h - t * 0.5, d * 0.5), paint)
	_box(Vector3(t, h, d), Vector3(-w * 0.5 + t * 0.5, h * 0.5, d * 0.5), paint)
	_box(Vector3(t, h, d), Vector3(w * 0.5 - t * 0.5, h * 0.5, d * 0.5), paint)
	# Conduit up into the ceiling void.
	var pipe := _mat(Color(0.6, 0.62, 0.63), 0.7, 0.35)
	for x: float in [-0.18, 0.0, 0.18]:
		_cyl(0.022, 1.4, Vector3(x, h + 0.7, 0.07), pipe)
	# Inside: zinc mounting plate, two DIN rails of branch breakers.
	_box(Vector3(w - 0.06, h - 0.06, 0.01), Vector3(0, h * 0.5, t + 0.005), inside)
	var white := _mat(Color(0.9, 0.9, 0.88), 0.0, 0.5)
	for row: float in [0.66, 0.46]:
		_box(Vector3(w - 0.1, 0.035, 0.012), Vector3(0, row, 0.03), _mat(Color(0.7, 0.72, 0.73), 0.8, 0.3))
		for i in 10:
			var x: float = -0.225 + i * 0.05
			_box(Vector3(0.042, 0.085, 0.055), Vector3(x, row, 0.055), white)
			var flip: float = 0.012 if (i * 7 + int(row * 10.0)) % 5 != 0 else -0.012
			_box(Vector3(0.014, 0.022, 0.016), Vector3(x, row + flip, 0.088), black)
	_label3d("LP-2F   BRANCH CIRCUITS", Vector3(0, 0.77, 0.04), 0.012, Color(0.15, 0.15, 0.15))
	# Main breaker: black housing with a red lever (up = ON).
	_box(Vector3(0.2, 0.24, 0.09), Vector3(0.12, 0.17, 0.06), black)
	_label3d("MAIN\nUPS OUTPUT\nSERVER + LAB", Vector3(-0.13, 0.19, 0.035), 0.013, Color(0.1, 0.1, 0.1))
	_label3d("ON\n\n\nOFF", Vector3(0.245, 0.17, 0.106), 0.009, Color(0.85, 0.85, 0.85))
	_lever_pivot = Node3D.new()
	_lever_pivot.name = "Lever"
	_lever_pivot.position = Vector3(0.12, 0.17, 0.095)
	_lever_pivot.rotation_degrees.x = LEVER_ON_DEG
	add_child(_lever_pivot)
	var red := _mat(Color(0.75, 0.05, 0.04), 0.0, 0.35)
	_box(Vector3(0.03, 0.03, 0.05), Vector3(0, 0, 0.025), _mat(Color(0.2, 0.2, 0.21), 0.8, 0.3), _lever_pivot)
	_box(Vector3(0.12, 0.035, 0.03), Vector3(0, 0, 0.05), red, _lever_pivot)
	# Door on its left hinge.
	_door_pivot = Node3D.new()
	_door_pivot.name = "Door"
	_door_pivot.position = Vector3(-w * 0.5, 0, d + 0.012)
	add_child(_door_pivot)
	_box(Vector3(w, h, 0.016), Vector3(w * 0.5, h * 0.5, 0), paint, _door_pivot)
	_box(Vector3(0.025, 0.09, 0.025), Vector3(w - 0.05, h * 0.5, 0.018), black, _door_pivot)
	for y: float in [0.12, h - 0.12]:
		_cyl(0.008, 0.06, Vector3(0.0, y, 0.0), _mat(Color(0.4, 0.4, 0.4), 0.8, 0.3), _door_pivot)
	# Warning plate and label on the door.
	var yellow := _mat(Color(0.95, 0.75, 0.08), 0.0, 0.5)
	_box(Vector3(0.22, 0.13, 0.002), Vector3(w * 0.5, h - 0.17, 0.009), yellow, _door_pivot)
	_label3d("DANGER\nHIGH VOLTAGE", Vector3(w * 0.5, h - 0.17, 0.011), 0.016, Color(0.05, 0.05, 0.05), _door_pivot)
	_box(Vector3(0.2, 0.045, 0.002), Vector3(w * 0.5, h * 0.42, 0.009), white, _door_pivot)
	_label3d("LP-2F  UPS FED", Vector3(w * 0.5, h * 0.42, 0.011), 0.011, Color(0.1, 0.1, 0.1), _door_pivot)
	# Power LED: green, red once the main is thrown.
	_led_mat = _mat(Color(0.1, 0.8, 0.2), 0.0, 0.3)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(0.1, 1.0, 0.25)
	_led_mat.emission_energy_multiplier = 2.5
	_led = _box(Vector3(0.012, 0.012, 0.008), Vector3(w * 0.5, h * 0.3, 0.012), _led_mat, _door_pivot)
	_sparks = CPUParticles3D.new()
	_sparks.emitting = false
	_sparks.one_shot = true
	_sparks.amount = 40
	_sparks.lifetime = 0.6
	_sparks.explosiveness = 0.95
	_sparks.direction = Vector3(0, 0.4, 1)
	_sparks.spread = 70.0
	_sparks.initial_velocity_min = 1.0
	_sparks.initial_velocity_max = 3.0
	_sparks.gravity = Vector3(0, -9.8, 0)
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.006, 0.006, 0.03)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.albedo_color = Color(1.0, 0.75, 0.3)
	spark_mesh.material = spark_mat
	_sparks.mesh = spark_mesh
	_sparks.particle_flag_align_y = true
	_sparks.position = Vector3(0.12, 0.2, 0.12)
	add_child(_sparks)
	# Mains hum, until the main is thrown.
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = SfxSynth.server_hum()
	_hum.volume_db = -26.0
	_hum.unit_size = 1.5
	_hum.max_distance = 6.0
	_hum.position = Vector3(0, h * 0.5, 0.1)
	_hum.autoplay = true
	add_child(_hum)


func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


func _box(sz: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	(parent if parent != null else self).add_child(mi)
	return mi


func _cyl(radius: float, height: float, pos: Vector3, mat: Material, parent: Node3D = null) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	(parent if parent != null else self).add_child(mi)


func _label3d(text: String, pos: Vector3, pixel: float, color: Color, parent: Node3D = null) -> void:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = pixel * 0.06
	l.font_size = 48
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = pos
	(parent if parent != null else self).add_child(l)
