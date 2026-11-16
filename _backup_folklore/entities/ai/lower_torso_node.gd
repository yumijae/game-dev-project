class_name LowerTorsoNode
extends StaticBody3D
## The Manananggal's abandoned lower half, left standing in one damp, dark
## room. It is her only weakness: press a Salted Garlic Poultice (pangontra sa
## katunga) into the raw waist and she cannot rejoin it. She will know at once,
## and she has 60 seconds to kill whoever did it before the dawn she can no
## longer hide from takes her.

const LAYER_WORLD: int = 1
const LAYER_INTERACT: int = 2
const APPLY_TIME: float = 4.0
const RITUAL_TIME: float = 60.0

var room_id: int = 0
var is_burning: bool = false
var is_destroyed: bool = false
var time_left: float = 0.0

var _manananggal: ManananggalAI = null
var _waist_material: StandardMaterial3D = null
var _smoke: CPUParticles3D = null
var _parts: Node3D = null
var _skin: ShaderMaterial = null


static func spawn(parent: Node, at: Vector3, room: int, manananggal: ManananggalAI) -> LowerTorsoNode:
	var torso := LowerTorsoNode.new()
	torso.name = "LowerTorsoNode"
	torso.room_id = room
	torso._manananggal = manananggal
	parent.add_child(torso)
	torso.global_position = at
	return torso


func _ready() -> void:
	# A real piece of a real Aswang: the Lana boils and the candle turns blue.
	add_to_group(&"aswang_presence")
	add_to_group(&"lower_torso")
	collision_layer = LAYER_WORLD | LAYER_INTERACT
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 1.05, 0.35)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.52
	add_child(collider)
	_parts = Node3D.new()
	add_child(_parts)
	var skin := ShaderMaterial.new()
	skin.shader = AswangBase.FLESH_SHADER
	skin.set_shader_parameter(&"albedo", Color(0.5, 0.47, 0.44))
	_skin = skin
	skin.set_shader_parameter(&"veins", 0.9)
	skin.set_shader_parameter(&"wet", 0.45)
	skin.set_shader_parameter(&"bump", 1.3)
	skin.set_shader_parameter(&"breathe", 0.0015)
	# Hips and two legs, standing on their own.
	var body := AswangMesh.new()
	body.tube([Vector3(0.0, 0.8, 0.0), Vector3(0.0, 0.88, 0.005), Vector3(0.0, 0.94, 0.0)],
		[Vector2(0.165, 0.115), Vector2(0.168, 0.112), Vector2(0.15, 0.1)], Vector3.BACK, 14)
	for side: float in [-1.0, 1.0]:
		body.tube([Vector3(side * 0.09, 0.86, 0.0), Vector3(side * 0.095, 0.5, -0.02), Vector3(side * 0.09, 0.08, 0.015)],
			[0.088, 0.056, 0.04], Vector3.BACK, 10)
		body.tube([Vector3(side * 0.09, 0.07, 0.03), Vector3(side * 0.095, 0.03, -0.08), Vector3(side * 0.1, 0.02, -0.17)],
			[0.038, Vector2(0.046, 0.028), Vector2(0.046, 0.016)], Vector3.UP, 8)
		for toe: float in [-0.03, -0.01, 0.01, 0.03]:
			body.tube([Vector3(side * 0.1 + toe, 0.018, -0.16), Vector3(side * 0.1 + toe * 1.2, 0.014, -0.21)], [0.011, 0.008],
				Vector3.UP, 5, 1)
	var flesh := MeshInstance3D.new()
	flesh.mesh = body.commit()
	flesh.material_override = skin
	_parts.add_child(flesh)
	_waist_material = StandardMaterial3D.new()
	_waist_material.albedo_color = Color(0.28, 0.03, 0.04)
	_waist_material.roughness = 0.25
	_waist_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_waist_material.emission_enabled = true
	_waist_material.emission = Color(0.5, 0.05, 0.05)
	_waist_material.emission_energy_multiplier = 0.25
	var waist_mesh := CylinderMesh.new()
	# The raw cut, shaped to the hips beneath it rather than a round plate.
	waist_mesh.top_radius = 0.135
	waist_mesh.bottom_radius = 0.15
	waist_mesh.height = 0.1
	waist_mesh.material = _waist_material
	var waist := MeshInstance3D.new()
	waist.mesh = waist_mesh
	waist.scale = Vector3(1.0, 1.0, 0.66)
	waist.position.y = 1.0
	_parts.add_child(waist)


func _process(delta: float) -> void:
	if not is_burning or is_destroyed:
		return
	time_left -= delta
	_waist_material.emission_energy_multiplier = 1.5 + sin(float(Time.get_ticks_msec()) * 0.02) * 0.8
	# The char creeps through the flesh as the minute runs out.
	_skin.set_shader_parameter(&"burn", 1.0)
	_skin.set_shader_parameter(&"dissolve", (1.0 - time_left / RITUAL_TIME) * 0.4)
	if time_left <= 0.0:
		_crumble()


func get_interactions(player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if is_destroyed:
		return actions
	if is_burning:
		actions.append({"id": &"none", "label": "It is burning. Survive %d more seconds." % int(ceil(time_left))})
	elif player.inventory.has_item(ItemDB.POULTICE):
		actions.append({"id": &"apply", "label": "Press the Salted Garlic Poultice into the waist (4 s)"})
	else:
		actions.append({"id": &"examine", "label": "Examine the severed lower half"})
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	match action_id:
		&"apply":
			player.start_channel("Pressing the poultice into the raw waist", APPLY_TIME, _apply_poultice.bind(player))
		&"examine":
			EventBus.ui_subtitle.emit(
				"Half a body. Still standing. ...Salt, garlic and cloth. I need to make the ward before she comes back.",
				6.0, &"Juan")


func _apply_poultice(player: PlayerController) -> void:
	if is_burning or is_destroyed or not player.inventory.remove_item(ItemDB.POULTICE, 1):
		return
	is_burning = true
	time_left = RITUAL_TIME
	_start_smoke()
	EventBus.item_used.emit(ItemDB.POULTICE)
	EventBus.torso_ritual_started.emit(RITUAL_TIME)
	EventBus.ui_notification.emit("The flesh hisses and blackens. She knows. SURVIVE 60 SECONDS.", 5.0)
	if is_instance_valid(_manananggal):
		_manananggal.enrage(RITUAL_TIME)


func _crumble() -> void:
	is_destroyed = true
	is_burning = false
	remove_from_group(&"aswang_presence")
	collision_layer = 0
	if _smoke != null:
		_smoke.emitting = false
	var tween: Tween = create_tween()
	tween.tween_method(_set_dissolve, 0.4, 1.0, 1.4)
	tween.parallel().tween_property(_waist_material, "albedo_color:a", 0.0, 1.4)
	tween.tween_callback(_parts.hide)
	if is_instance_valid(_manananggal):
		_manananggal.destroy_permanently()


func _set_dissolve(value: float) -> void:
	_skin.set_shader_parameter(&"dissolve", value)


func _start_smoke() -> void:
	_smoke = CPUParticles3D.new()
	_smoke.amount = 40
	_smoke.lifetime = 2.2
	_smoke.direction = Vector3.UP
	_smoke.spread = 18.0
	_smoke.gravity = Vector3(0.0, 0.6, 0.0)
	_smoke.initial_velocity_min = 0.3
	_smoke.initial_velocity_max = 0.8
	_smoke.scale_amount_min = 0.6
	_smoke.scale_amount_max = 1.6
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.15, 0.14, 0.14, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	_smoke.mesh = mesh
	_smoke.position.y = 1.08
	add_child(_smoke)
	_smoke.emitting = true
