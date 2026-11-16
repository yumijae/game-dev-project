class_name AtmosphereDirector
extends Node3D
## Turns the clean STI building into the place it is at 11:45 PM on a storm
## night. Everything here is cosmetic and procedural - no gameplay rule reads
## it, and nothing in it makes a sound a robot (or the player's ears) could
## mistake for a real cue.
##
##   * decay pass on walls, floors and ceilings (shaders/decay_overlay)
##   * blood, drag-smear, handprint and claw-mark decals, placed by raycast
##   * warnings scrawled on chalkboards and restroom mirrors
##   * papers on the floors, ceiling tiles hanging by their wires
##   * failing fluorescent tubes in the corridors
##   * a storm: rain, lightning that floods the rooms, thunder
##   * dust in the flashlight beam and a low drone under everything

const DECAY_SHADER: Shader = preload("res://shaders/decay_overlay.gdshader")
const DECAY_MESHES: Array[String] = [
	"Mesh_int", "Mesh_ext", "Mesh_ceiling", "Mesh_slab", "Mesh_pavement", "Mesh_wall_tile",
	"Mesh_floor", "Mesh_floor_lobby", "Mesh_floor_wood", "Mesh_floor_mosaic", "Mesh_floor_kitchen", "Mesh_floor_rubber",
]
const BLOOD: Color = Color(0.3, 0.012, 0.012)
## Writing on the classroom boards (chalk) and restroom mirrors (black marker):
## no blood anywhere in the set dressing, per user preference.
const CHALK: Color = Color(0.8, 0.8, 0.75)
const MARKER: Color = Color(0.06, 0.06, 0.08)
const DECAL_COUNT: int = 120
const DECAL_TEXTURE_SIZE: int = 128
const PAPER_COUNT: int = 520
const FLICKER_LIGHTS_PER_FLOOR: int = 2
const CORRIDOR_PANEL_X: Array[float] = [-10.5, -7.5, -4.5, -1.5, 1.5, 4.5, 7.5, 10.5]
const LIGHTNING_MIN_GAP: float = 20.0
const LIGHTNING_MAX_GAP: float = 55.0
const FLASH_SKY: Color = Color(0.32, 0.38, 0.55)
## A tube only renders while Juan's head is within this height of its floor's
## mid-height: his own floor, or both floors when he is on the stairs between.
const FLICKER_CULL_HEIGHT: float = 2.6
const FLICKER_HEIGHT: float = 3.3
## Shadows this far out are lost in the fog anyway; a short range keeps the
## two cascades sharp and the per-frame shadow pass small.
const SHADOW_DISTANCE: float = 45.0


## One failing fluorescent tube in a corridor.
class FailingTube:
	var light: OmniLight3D = null
	var timer: float = 0.0
	var burst: float = 0.0
	var lit: bool = false

const BOARD_MESSAGES: Array[String] = [
	"DON'T\nLOOK BACK",
	"IT IS IN\nTHE CEILING",
	"THAT IS NOT\nMARK",
	"WHO PUSHED\nTHE UPDATE?",
	"TIK TIK TIK\nTIK  TIK    TIK",
	"THERE IS NO\nMORNING",
	"DO NOT\nOPEN IT",
	"IT CAN\nSEE YOU",
	"ITS FEET ARE\nBACKWARDS",
]
const MIRROR_MESSAGES: Array[String] = ["LOOK", "BEHIND YOU"]

var _rng := RandomNumberGenerator.new()
var _environment: Environment = null
var _base_sky: Color = Color.BLACK
var _base_ambient: float = 0.05
var _moon: DirectionalLight3D = null
var _lightning: DirectionalLight3D = null
var _lightning_timer: float = 12.0
var _flash: float = 0.0
var _strike_tween: Tween = null
var _flickers: Array[FailingTube] = []
var _rain_audio: AudioStreamPlayer = null
var _rain_filter: AudioEffectLowPassFilter = null
var _rain_particles: CPUParticles3D = null
var _player: PlayerController = null
var _update_timer: float = 0.0
## [material, decay pass] for every decayed surface, so the pass can be
## dropped on the lowest quality preset.
var _decay_passes: Array[Array] = []


func _ready() -> void:
	_rng.randomize()
	_player = get_tree().get_first_node_in_group(&"player") as PlayerController
	_apply_decay()
	_tune_environment()
	_build_lightning()
	_build_flicker_lights()
	# _write_on_boards() - disabled per user preference (no messages scrawled on
	# the classroom blackboards or the restroom mirrors)
	_scatter_paper()
	# _hang_ceiling_debris() - disabled per user preference (no dangling ceiling panels)
	_start_audio()
	_build_dust_and_rain()
	# _dress_with_decals() - disabled per user preference (no blood splats,
	# smears, handprints or claw marks on the walls and floors)


func _process(delta: float) -> void:
	_update_flickers(delta)
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = _rng.randf_range(LIGHTNING_MIN_GAP, LIGHTNING_MAX_GAP)
		_strike()
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = 0.4
		_update_weather_for_player()


# ---------------------------------------------------------------------- decay

func _apply_decay() -> void:
	var school: Node = get_tree().get_first_node_in_group(&"school")
	if school == null:
		return
	for mesh_name: String in DECAY_MESHES:
		var instance := school.get_node_or_null("Visual/" + mesh_name) as MeshInstance3D
		if instance == null or instance.mesh == null:
			continue
		var base: Material = instance.mesh.surface_get_material(0)
		if base == null:
			continue
		# One overlay per mesh: plastered walls get a skirting board, the
		# ceiling its tile grid.
		var decay := ShaderMaterial.new()
		decay.shader = DECAY_SHADER
		decay.set_shader_parameter(&"baseboard", 1.0 if mesh_name in ["Mesh_int", "Mesh_ext"] else 0.0)
		decay.set_shader_parameter(&"ceiling_grid", 0.0)
		var rotten: Material = base.duplicate()
		rotten.next_pass = decay
		instance.material_override = rotten
		_decay_passes.append([rotten, decay])
	_fit_decay()
	GameSettings.changed.connect(_fit_decay)


## The grime overlay is a second, fully lit, noise-heavy draw of nearly every
## pixel on screen. Weak graphics chips cannot afford it.
func _fit_decay() -> void:
	var wanted: bool = bool(GameSettings.preset_value("decay"))
	for pair: Array in _decay_passes:
		(pair[0] as Material).next_pass = (pair[1] as Material) if wanted else null


func _tune_environment() -> void:
	var scene: Node = get_tree().current_scene
	var world := scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		# Work on a private copy. The scene's Environment is a shared resource
		# that survives reload_current_scene(), so a restart in the middle of
		# a lightning flash would otherwise keep the flash sky as the new base.
		_environment = world.environment.duplicate() as Environment
		world.environment = _environment
		_environment.ambient_light_energy = 0.05
		_environment.fog_density = 0.028
		_environment.volumetric_fog_density = 0.045
		_base_sky = _environment.background_color
		_base_ambient = _environment.ambient_light_energy
	# A little more moon, so pale shafts fall through the jalousies into the haze.
	_moon = scene.get_node_or_null("Moon") as DirectionalLight3D
	if _moon != null:
		_moon.light_energy = 0.13
		_moon.light_volumetric_fog_energy = 0.0
		_moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_moon.directional_shadow_blend_splits = true
		_moon.directional_shadow_max_distance = SHADOW_DISTANCE
		_moon.shadow_bias = 0.01
		_moon.shadow_normal_bias = 0.2
		_moon.shadow_blur = 0.3


# ------------------------------------------------------------------ lightning

func _build_lightning() -> void:
	_lightning = DirectionalLight3D.new()
	_lightning.name = "Lightning"
	_lightning.light_color = Color(0.75, 0.82, 1.0)
	_lightning.light_energy = 0.0
	_lightning.shadow_enabled = true
	_lightning.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_lightning.directional_shadow_blend_splits = true
	_lightning.directional_shadow_max_distance = SHADOW_DISTANCE
	_lightning.shadow_bias = 0.01
	_lightning.shadow_normal_bias = 0.2
	_lightning.shadow_blur = 0.2
	_lightning.shadow_opacity = 1.0
	_lightning.light_volumetric_fog_energy = 0.0
	_lightning.visible = false
	add_child(_lightning)


## A double flash that throws window-shaped light across the rooms, then
## thunder after a delay that tells you how far away it was.
func _strike() -> void:
	if _strike_tween != null and _strike_tween.is_valid():
		_strike_tween.kill()
	_lightning.rotation_degrees = Vector3(_rng.randf_range(-48.0, -22.0), _rng.randf_range(0.0, 360.0), 0.0)
	_lightning.visible = true
	# The moon is 25x dimmer than the bolt: drop it for the flash so only one
	# directional light is casting shadows at a time.
	if _moon != null:
		_moon.visible = false
	_strike_tween = create_tween()
	_strike_tween.tween_method(_set_flash, 0.0, 0.8, 0.04)
	_strike_tween.tween_method(_set_flash, 0.8, 0.1, 0.09)
	_strike_tween.tween_method(_set_flash, 0.1, 1.0, 0.05)
	_strike_tween.tween_method(_set_flash, 1.0, 0.0, 0.55)
	_strike_tween.tween_callback(_end_strike)
	var distance: float = _rng.randf_range(0.3, 2.6)
	await get_tree().create_timer(distance).timeout
	if is_inside_tree():
		SfxSynth.play_ui(self, SfxSynth.thunder(), lerpf(-3.0, -15.0, distance / 2.6), _rng.randf_range(0.8, 1.1), &"Ambience")


func _end_strike() -> void:
	_set_flash(0.0)
	_lightning.visible = false
	if _moon != null:
		_moon.visible = true


func _set_flash(value: float) -> void:
	_flash = value
	_lightning.light_energy = value * 3.2
	if _environment != null:
		_environment.background_color = _base_sky.lerp(FLASH_SKY, value)
		# Ambient light has no shadows in Godot - do not boost it during flash or it bleeds through all walls.
		_environment.ambient_light_energy = _base_ambient


# ------------------------------------------------------------ failing tubes

func _build_flicker_lights() -> void:
	for floor_index: int in Campus.FLOOR_COUNT:
		var spots: Array[float] = CORRIDOR_PANEL_X.duplicate()
		for i: int in FLICKER_LIGHTS_PER_FLOOR:
			var x: float = spots.pop_at(_rng.randi_range(0, spots.size() - 1))
			var light := OmniLight3D.new()
			light.name = "FailingTube"
			light.light_color = Color(0.78, 1.0, 0.88)
			light.light_energy = 1.1
			light.omni_range = 5.0
			light.omni_attenuation = 1.4
			# A 1.2 m tube, not a point: slightly soft shadows.
			LightRig.seal(light, 0.12)
			light.visible = false
			add_child(light)
			light.global_position = Vector3(x, Campus.floor_y(floor_index) + FLICKER_HEIGHT, 0.0)
			# While lit it really does light the corridor, so it counts for Panic.
			light.add_to_group(&"ambient_lights")
			var tube := FailingTube.new()
			tube.light = light
			tube.timer = _rng.randf_range(1.0, 9.0)
			_flickers.append(tube)


## Long dark gaps, then a stuttering burst as the starter tries to catch.
##
## The light node stays visible for the whole burst and stutters through its
## energy: toggling visibility would free and re-render its shadow map on every
## flick. Tubes on floors Juan cannot see keep their timing but never render.
func _update_flickers(delta: float) -> void:
	var has_eye: bool = _player != null and is_instance_valid(_player)
	var eye_y: float = _player.head.global_position.y if has_eye else 0.0
	for tube: FailingTube in _flickers:
		tube.timer -= delta
		if tube.burst > 0.0:
			tube.burst -= delta
			if tube.burst <= 0.0:
				tube.light.visible = false
				tube.timer = _rng.randf_range(3.0, 14.0)
			elif tube.timer <= 0.0:
				tube.lit = not tube.lit
				tube.light.light_energy = _rng.randf_range(0.5, 1.3) if tube.lit else 0.0
				tube.timer = _rng.randf_range(0.03, 0.16)
		elif tube.timer <= 0.0:
			tube.burst = _rng.randf_range(0.3, 1.8)
			tube.timer = 0.0
			tube.lit = false
			tube.light.light_energy = 0.0
			var floor_mid_y: float = tube.light.global_position.y - FLICKER_HEIGHT + Campus.FLOOR_HEIGHT * 0.5
			tube.light.visible = not has_eye or absf(floor_mid_y - eye_y) < FLICKER_CULL_HEIGHT


# -------------------------------------------------------------------- writing

func _write_on_boards() -> void:
	var messages: Array[String] = BOARD_MESSAGES.duplicate()
	for room: Dictionary in Campus.ROOMS:
		var x0: float = room["x0"]
		var x1: float = room["x1"]
		var z0: float = room["z0"]
		var z1: float = room["z1"]
		var floor_index: int = room["floor"]
		var y: float = Campus.floor_y(floor_index)
		if room["type"] == "classroom" and not messages.is_empty() and _rng.randf() < 0.75:
			# The board hangs on the west partition, except in the end rooms
			# that are built mirrored.
			var mirrored: bool = absf(x0 - Campus.X_MIN) < 0.01
			var x: float = x1 - 0.14 if mirrored else x0 + 0.14
			var text: String = messages.pop_at(_rng.randi_range(0, messages.size() - 1))
			_scrawl(text, Vector3(x, y + 1.5 + _rng.randf_range(-0.1, 0.15), (z0 + z1) * 0.5 + _rng.randf_range(-0.6, 0.6)),
				-PI * 0.5 if mirrored else PI * 0.5, 0.0034, _rng.randf_range(-0.08, 0.08),
				CHALK)
		elif room["type"] == "restroom" and _rng.randf() < 0.6:
			var text: String = MIRROR_MESSAGES[_rng.randi_range(0, MIRROR_MESSAGES.size() - 1)]
			_scrawl(text, Vector3(x0 + 0.105, y + 1.65, z1 - 3.2), PI * 0.5, 0.0022, _rng.randf_range(-0.12, 0.12), MARKER)


func _scrawl(text: String, at: Vector3, yaw: float, pixel_size: float, tilt: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.shaded = true
	label.double_sided = false
	label.line_spacing = -12.0
	add_child(label)
	label.global_position = at
	label.rotation = Vector3(0.0, yaw, tilt)


# -------------------------------------------------------------------- clutter

## Loose bond paper everywhere: thesis drafts, exam sheets, enrolment forms.
func _scatter_paper() -> void:
	var sheet := BoxMesh.new()
	sheet.size = Vector3(0.21, 0.002, 0.297)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.78, 0.76, 0.68)
	material.roughness = 0.95
	sheet.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = sheet
	multimesh.instance_count = PAPER_COUNT
	for i: int in PAPER_COUNT:
		var floor_index: int = _rng.randi_range(0, Campus.FLOOR_COUNT - 1)
		var at := Vector3(_rng.randf_range(-11.6, 11.6), 0.0, _rng.randf_range(-7.6, 7.6))
		if _rng.randf() < 0.4:
			at.z = _rng.randf_range(-1.05, 1.05)
		at.y = Campus.floor_y(floor_index) + 0.013 + _rng.randf() * 0.004
		if Campus.stairwell_at(at) != "":
			at.z = _rng.randf_range(-1.05, 1.05)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU)
		multimesh.set_instance_transform(i, Transform3D(basis, at))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Papers"
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Ceiling tiles hanging by one edge and wires dangling out of the plenum (disabled).
func _hang_ceiling_debris() -> void:
	return


# --------------------------------------------------------------------- decals

## Blood on the floors; handprints and claw marks on the walls.
## Surfaces are found by raycast, so the marks land on real geometry -
## including desks, counters and lockers.
func _dress_with_decals() -> void:
	var splat: ImageTexture = _make_decal_texture(0, BLOOD)
	var smear: ImageTexture = _make_decal_texture(1, BLOOD)
	var claws: ImageTexture = _make_decal_texture(2, Color(0.03, 0.02, 0.02))
	var hand: ImageTexture = _make_decal_texture(3, BLOOD)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var placed: int = 0
	var attempts: int = 0
	while placed < DECAL_COUNT and attempts < DECAL_COUNT * 4:
		attempts += 1
		var floor_index: int = _rng.randi_range(0, Campus.FLOOR_COUNT - 1)
		var origin := Vector3(_rng.randf_range(-11.5, 11.5), Campus.floor_y(floor_index) + _rng.randf_range(0.5, 1.7),
			_rng.randf_range(-7.5, 7.5))
		if _rng.randf() < 0.45:
			origin.z = _rng.randf_range(-1.0, 1.0)
		var onto_floor: bool = _rng.randf() < 0.45
		var angle: float = _rng.randf() * TAU
		var direction: Vector3 = Vector3.DOWN if onto_floor else Vector3(cos(angle), 0.0, sin(angle))
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + direction * 4.0, 1))
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		var point: Vector3 = hit["position"]
		if onto_floor:
			if normal.y < 0.9:
				continue
			if _rng.randf() < 0.6:
				var size: float = _rng.randf_range(0.5, 1.5)
				_add_decal(splat, point, normal, Vector2(size, size), _rng.randf() * TAU)
			else:
				_add_decal(smear, point, normal, Vector2(_rng.randf_range(1.6, 3.4), _rng.randf_range(0.4, 0.8)), _rng.randf() * TAU)
		else:
			if absf(normal.y) > 0.1:
				continue
			var roll: float = _rng.randf()
			if roll < 0.5:
				_add_decal(hand, point, normal, Vector2(0.24, 0.3), _rng.randf_range(-0.5, 0.5))
			else:
				_add_decal(claws, point, normal, Vector2(0.55, 0.9), _rng.randf_range(-0.4, 0.4))
		placed += 1


func _add_decal(texture: Texture2D, point: Vector3, normal: Vector3, size: Vector2, roll: float) -> void:
	var decal := Decal.new()
	decal.texture_albedo = texture
	decal.size = Vector3(size.x, 0.35, size.y)
	decal.albedo_mix = 1.0
	decal.normal_fade = 0.3
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = 16.0
	decal.distance_fade_length = 4.0
	var basis: Basis
	if absf(normal.y) > 0.9:
		basis = Basis(Vector3.UP, roll)
	else:
		var x: Vector3 = Vector3.UP.cross(normal).normalized()
		basis = Basis(x, normal, x.cross(normal)).rotated(normal, roll)
	add_child(decal)
	decal.global_transform = Transform3D(basis, point)


## kind: 0 splat, 1 drag smear, 2 claw marks, 3 handprint.
func _make_decal_texture(kind: int, color: Color) -> ImageTexture:
	var size: int = DECAL_TEXTURE_SIZE
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = _rng.randi()
	noise.frequency = 0.03
	for py: int in size:
		for px: int in size:
			var u: float = float(px) / float(size) * 2.0 - 1.0
			var v: float = float(py) / float(size) * 2.0 - 1.0
			var fx: float = float(px)
			var fy: float = float(py)
			var alpha: float = 0.0
			match kind:
				0:
					var radius: float = sqrt(u * u + v * v)
					alpha = 1.0 - smoothstep(0.3, 0.55, radius + noise.get_noise_2d(fx * 2.0, fy * 2.0) * 0.4)
					var drops: float = smoothstep(0.5, 0.65, noise.get_noise_2d(fx * 7.0 + 100.0, fy * 7.0))
					alpha = maxf(alpha, drops * (1.0 - smoothstep(0.55, 0.95, radius)))
				1:
					var width: float = 0.3 + noise.get_noise_2d(fx * 1.5, 7.0) * 0.2
					var centre: float = noise.get_noise_2d(fx * 0.8, 50.0) * 0.25
					alpha = (1.0 - smoothstep(width * 0.4, width, absf(v - centre))) * (1.0 - smoothstep(0.65, 1.0, absf(u)))
					alpha *= 0.45 + 0.55 * (noise.get_noise_2d(fx * 1.0, fy * 9.0) * 0.5 + 0.5)
				2:
					for k: int in 4:
						var line_x: float = -0.45 + float(k) * 0.3 + v * 0.12 + noise.get_noise_2d(fy * 1.2, float(k) * 40.0) * 0.06
						var line_width: float = 0.04 * (1.0 - absf(v)) + 0.004
						alpha = maxf(alpha, 1.0 - smoothstep(line_width * 0.4, line_width, absf(u - line_x)))
					alpha *= 1.0 - smoothstep(0.75, 1.0, absf(v))
				3:
					alpha = _ellipse(u, v, 0.0, 0.32, 0.34, 0.38)
					for finger: float in [-0.27, -0.09, 0.09, 0.27]:
						alpha = maxf(alpha, _ellipse(u, v, finger, -0.42 + absf(finger) * 0.35, 0.075, 0.36))
					alpha = maxf(alpha, _ellipse(u, v, -0.5, 0.12, 0.09, 0.24))
					alpha *= 0.5 + 0.5 * smoothstep(-0.3, 0.3, noise.get_noise_2d(fx * 5.0, fy * 5.0))
			var shade: float = 0.75 + noise.get_noise_2d(fx * 3.0 + 9.0, fy * 3.0) * 0.35
			image.set_pixel(px, py, Color(color.r * shade, color.g * shade, color.b * shade, clampf(alpha, 0.0, 1.0)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _ellipse(u: float, v: float, cx: float, cy: float, rx: float, ry: float) -> float:
	var dx: float = (u - cx) / rx
	var dy: float = (v - cy) / ry
	return 1.0 - smoothstep(0.75, 1.0, sqrt(dx * dx + dy * dy))


# ------------------------------------------------------------- air and storm

## Rain gets its own bus with a low-pass, so walls can take the hiss out of it.
func _rain_bus() -> StringName:
	var index: int = AudioServer.get_bus_index(&"Rain")
	if index < 0:
		index = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, &"Rain")
		AudioServer.set_bus_send(index, &"Ambience" if AudioServer.get_bus_index(&"Ambience") >= 0 else &"Master")
		_rain_filter = AudioEffectLowPassFilter.new()
		_rain_filter.cutoff_hz = 900.0
		AudioServer.add_bus_effect(index, _rain_filter)
	else:
		_rain_filter = AudioServer.get_bus_effect(index, 0) as AudioEffectLowPassFilter
	return &"Rain"


func _start_audio() -> void:
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "Rain"
	_rain_audio.stream = SfxSynth.rain()
	_rain_audio.volume_db = -32.0
	_rain_audio.bus = _rain_bus()
	add_child(_rain_audio)
	_rain_audio.play()
	var drone := AudioStreamPlayer.new()
	drone.name = "Drone"
	drone.stream = SfxSynth.drone()
	drone.volume_db = -17.0
	if AudioServer.get_bus_index(&"Ambience") >= 0:
		drone.bus = &"Ambience"
	add_child(drone)
	drone.play()


func _build_dust_and_rain() -> void:
	if _player == null:
		return
	# Dust is lit, not glowing: you only see it where the LED or a candle hits.
	var dust := CPUParticles3D.new()
	dust.name = "Dust"
	dust.amount = 170
	dust.lifetime = 9.0
	dust.preprocess = 9.0
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(3.5, 1.6, 3.5)
	dust.direction = Vector3(0.3, -1.0, 0.1)
	dust.spread = 180.0
	dust.gravity = Vector3(0.0, -0.01, 0.0)
	dust.initial_velocity_min = 0.01
	dust.initial_velocity_max = 0.06
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.5
	var mote := QuadMesh.new()
	mote.size = Vector2(0.012, 0.012)
	var mote_material := StandardMaterial3D.new()
	mote_material.albedo_color = Color(0.95, 0.93, 0.85, 0.7)
	# A soft round speck, not a hard-edged square: radial falloff to clear.
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var speck := GradientTexture2D.new()
	speck.gradient = falloff
	speck.fill = GradientTexture2D.FILL_RADIAL
	speck.fill_from = Vector2(0.5, 0.5)
	speck.fill_to = Vector2(0.5, 0.0)
	speck.width = 32
	speck.height = 32
	mote_material.albedo_texture = speck
	mote_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote.material = mote_material
	dust.mesh = mote
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.camera.add_child(dust)

	_rain_particles = CPUParticles3D.new()
	_rain_particles.name = "RainStreaks"
	_rain_particles.amount = 600
	_rain_particles.lifetime = 0.8
	_rain_particles.local_coords = false
	_rain_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain_particles.emission_box_extents = Vector3(9.0, 0.3, 9.0)
	_rain_particles.direction = Vector3(0.12, -1.0, 0.05)
	_rain_particles.spread = 2.0
	_rain_particles.gravity = Vector3(0.0, -9.8, 0.0)
	_rain_particles.initial_velocity_min = 11.0
	_rain_particles.initial_velocity_max = 14.0
	var streak := BoxMesh.new()
	streak.size = Vector3(0.006, 0.32, 0.006)
	var streak_material := StandardMaterial3D.new()
	streak_material.albedo_color = Color(0.62, 0.68, 0.8, 0.3)
	streak_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material = streak_material
	_rain_particles.mesh = streak
	_rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_particles.emitting = false
	add_child(_rain_particles)


## Rain is loud on the roof, dull under four floors of concrete, and only
## falls on Juan when there is sky above him.
func _update_weather_for_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var at: Vector3 = _player.global_position
	var floor_index: int = Campus.floor_from_y(at.y)
	var under_sky: bool = not Campus.is_inside_footprint(at) \
		or (floor_index == Campus.ROOF_FLOOR and Campus.stairwell_at(at) == "")
	# Indoors it's a faint, muffled patter through the slab and the glass.
	var target: float = -9.0 if under_sky else lerpf(-34.0, -27.0, float(floor_index) / float(Campus.ROOF_FLOOR))
	_rain_audio.volume_db = move_toward(_rain_audio.volume_db, target, 2.5)
	if _rain_filter != null:
		var cutoff: float = 9000.0 if under_sky else 900.0
		_rain_filter.cutoff_hz = move_toward(_rain_filter.cutoff_hz, cutoff, 1500.0)
	if _rain_particles != null:
		_rain_particles.emitting = under_sky
		_rain_particles.global_position = at + Vector3.UP * 7.0
