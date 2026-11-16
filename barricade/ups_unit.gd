class_name UpsUnit
extends StaticBody3D
## The Server Room UPS: the backup battery that kept WARDEN's circuit (server,
## CCTV, the Com Sci Lab's robot docks) alive when the robots' malfunction
## tripped the building's main breaker at 11:44 PM.
##
## It starts the night at START_CHARGE and drains every game minute: a base
## load (server + cameras) plus extra for every robot recharging on a dock.
## With nothing docked it runs out around 3 AM. When it is empty, or when
## LP-2F's main breaker cuts its output, EventBus.lab_power_cut fires.
##
## The front LCD shows charge and time left; it beeps, faster when low.

const LAYER_INTERACT: int = 2
const SIZE := Vector3(0.22, 0.46, 0.5)
const START_CHARGE: float = 70.0
## % per game minute: server + CCTV, and each robot charging on a dock.
const BASE_DRAIN: float = 0.36
const DOCKED_DRAIN: float = 0.04
const LOW: float = 20.0
const CRITICAL: float = 10.0

var charge: float = START_CHARGE
## True once the load is gone: battery empty or output cut at the breaker.
var is_output_off: bool = false

var _lcd: Label3D = null
var _lcd_glow: MeshInstance3D = null
var _lcd_mat: StandardMaterial3D = null
var _bar: Array[MeshInstance3D] = []
var _beep_timer: float = 4.0
var _warned_low: bool = false
var _warned_critical: bool = false


static func create() -> UpsUnit:
	var ups := UpsUnit.new()
	ups.collision_layer = 1 | LAYER_INTERACT   # solid, and lookable
	ups.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = SIZE
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position = Vector3(0, SIZE.y * 0.5, SIZE.z * 0.5)
	ups.add_child(collider)
	return ups


## The one in the building, or null.
static func find(tree: SceneTree) -> UpsUnit:
	return tree.get_first_node_in_group(&"ups") as UpsUnit


func _ready() -> void:
	add_to_group(&"ups")
	_build()
	EventBus.time_advanced.connect(_on_minute)
	EventBus.lab_power_cut.connect(_on_power_cut)
	_refresh_display()


# ------------------------------------------------------------ state

## Current drain in % per game minute.
func drain_rate() -> float:
	var docked: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"hostiles"):
		if node.get(&"is_docked") == true:
			docked += 1
	return BASE_DRAIN + DOCKED_DRAIN * docked


## Game minutes until empty at the current rate.
func minutes_left() -> int:
	if is_output_off:
		return 0
	return int(ceil(charge / maxf(drain_rate(), 0.001)))


## "2h 14m", for the display and the phone.
func time_left_text() -> String:
	var m: int = minutes_left()
	return "%dh %02dm" % [m / 60, m % 60] if m >= 60 else "%dm" % m


func _on_minute(_h: int, _m: int, _f: String, _p: float) -> void:
	if is_output_off:
		return
	charge = maxf(charge - drain_rate(), 0.0)
	_refresh_display()
	if charge <= LOW and not _warned_low:
		_warned_low = true
		EventBus.ui_notification.emit("Somewhere on 2F, a UPS starts beeping faster.", 4.0)
	if charge <= CRITICAL and not _warned_critical:
		_warned_critical = true
		EventBus.ui_notification.emit("The UPS alarm is a constant whine now.", 4.0)
	if charge <= 0.0:
		SfxSynth.play_at(self, SfxSynth.ups_beep(), _lcd.global_position, -2.0, 0.5, 18.0)
		EventBus.lab_power_cut.emit(&"ups_empty")


func _on_power_cut(cause: StringName) -> void:
	is_output_off = true
	_refresh_display(cause)


func _process(delta: float) -> void:
	if is_output_off and charge <= 0.0:
		return
	_beep_timer -= delta
	if _beep_timer > 0.0:
		return
	# On battery a UPS chirps now and then; low, it nags; critical, it never stops.
	_beep_timer = 30.0 if charge > LOW else (6.0 if charge > CRITICAL else 1.6)
	if is_output_off:
		_beep_timer = 45.0
	SfxSynth.play_at(self, SfxSynth.ups_beep(), _lcd.global_position, -16.0 if charge > LOW else -9.0, 1.0, 14.0)


# ------------------------------------------------------------ interaction

func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	return [{"id": &"read", "label": "Read the UPS display"}]


func interact(_player: PlayerController, _action_id: StringName) -> void:
	if charge <= 0.0:
		EventBus.ui_notification.emit("The UPS is dead. Its screen is black.", 3.0)
	elif is_output_off:
		EventBus.ui_notification.emit("UPS %d%%. OUTPUT OFF - the breaker upstairs cut the load." % int(ceil(charge)), 3.5)
	else:
		EventBus.ui_notification.emit("UPS on battery: %d%%, about %s left. It's keeping the lab and the cameras alive."
			% [int(ceil(charge)), time_left_text()], 4.0)


# ------------------------------------------------------------ display

func _refresh_display(cause: StringName = &"") -> void:
	if _lcd == null:
		return
	var col: Color = Color(0.35, 0.95, 1.0)
	if charge <= CRITICAL:
		col = Color(1.0, 0.25, 0.2)
	elif charge <= LOW:
		col = Color(1.0, 0.7, 0.15)
	if charge <= 0.0 or cause == &"ups_empty":
		_lcd.visible = false
		_lcd_mat.emission_energy_multiplier = 0.0
		_lcd_mat.albedo_color = Color(0.02, 0.025, 0.03)
		for seg: MeshInstance3D in _bar:
			seg.visible = false
		return
	if is_output_off:
		_lcd.text = "ON BATTERY  %d%%\nOUTPUT OFF" % int(ceil(charge))
	else:
		_lcd.text = "ON BATTERY  %d%%\n%s LEFT" % [int(ceil(charge)), time_left_text()]
	_lcd.modulate = col
	_lcd_mat.emission = col * 0.25
	var lit: int = int(ceil(charge / 20.0))
	for i in _bar.size():
		_bar[i].visible = i < lit
		(_bar[i].material_override as StandardMaterial3D).emission = col


func _build() -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.06, 0.065, 0.07)
	shell.roughness = 0.45
	shell.metallic = 0.2
	var w: float = SIZE.x
	var h: float = SIZE.y
	var d: float = SIZE.z
	_box(Vector3(w, h, d), Vector3(0, h * 0.5, d * 0.5), shell)
	# Front fascia: slightly lighter, with vent slots.
	var fascia := StandardMaterial3D.new()
	fascia.albedo_color = Color(0.12, 0.125, 0.13)
	fascia.roughness = 0.6
	_box(Vector3(w - 0.01, h - 0.01, 0.012), Vector3(0, h * 0.5, d + 0.006), fascia)
	var slot := StandardMaterial3D.new()
	slot.albedo_color = Color(0.015, 0.015, 0.018)
	for i in 7:
		_box(Vector3(w - 0.07, 0.008, 0.004), Vector3(0, 0.05 + i * 0.022, d + 0.013), slot)
	# LCD panel and its readout.
	_lcd_mat = StandardMaterial3D.new()
	_lcd_mat.albedo_color = Color(0.03, 0.08, 0.1)
	_lcd_mat.emission_enabled = true
	_lcd_mat.emission = Color(0.1, 0.3, 0.35)
	_lcd_mat.emission_energy_multiplier = 1.0
	_lcd_glow = _box(Vector3(0.16, 0.07, 0.004), Vector3(0, h - 0.09, d + 0.014), _lcd_mat)
	_lcd = Label3D.new()
	_lcd.font_size = 32
	_lcd.pixel_size = 0.00042
	_lcd.shaded = false
	_lcd.double_sided = false
	_lcd.outline_size = 0
	_lcd.position = Vector3(0, h - 0.09, d + 0.0165)
	add_child(_lcd)
	# Five-segment charge bar under the LCD.
	for i in 5:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.05, 0.05)
		m.emission_enabled = true
		m.emission_energy_multiplier = 2.0
		var seg := _box(Vector3(0.024, 0.008, 0.004), Vector3(-0.056 + i * 0.028, h - 0.145, d + 0.014), null)
		seg.material_override = m
		_bar.append(seg)
	# Power button and the cable up to the breaker panel.
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.3, 0.31, 0.33)
	_box(Vector3(0.03, 0.03, 0.008), Vector3(0, h - 0.19, d + 0.014), grey)
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.02, 0.02, 0.02)
	cable.roughness = 0.7
	_box(Vector3(0.025, 0.6, 0.025), Vector3(0.05, h + 0.3, 0.03), cable)
	var label := Label3D.new()
	label.text = "SMART-UPS 3000"
	label.font_size = 32
	label.pixel_size = 0.0004
	label.modulate = Color(0.75, 0.76, 0.78)
	label.position = Vector3(0, h - 0.03, d + 0.0135)
	add_child(label)


func _box(sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = sz
	if mat != null:
		mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
	return mi
