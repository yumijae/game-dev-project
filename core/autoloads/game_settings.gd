extends Node
## Player settings (autoload "GameSettings"): saved to user://settings.cfg and
## applied to the renderer, the window, the audio master and the live scene.
##
## Graphics are driven by one quality preset so the game can run on anything
## from an office laptop to a gaming PC. On the very first launch the preset is
## picked from the graphics card; after that the player's choice is kept.
##
##   Lowest - half resolution, hard shadows, no screen-space effects, no
##            grime overlay on the walls
##   Low    - 75 % resolution, cheap soft shadows, no fog volumes
##   Medium - full resolution, SSAO, smaller fog volume
##   High   - everything the scene was authored with

signal changed

const SAVE_PATH: String = "user://settings.cfg"
const PRESET_NAMES: Array[String] = ["Lowest", "Low", "Medium", "High"]
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 0]
const FOV_MIN: float = 60.0
const FOV_MAX: float = 100.0
const MIN_RENDER_SCALE: float = 0.4
## Auto quality: below this average frame rate for AUTO_WINDOW seconds of
## play, the game drops one quality step by itself.
const AUTO_MIN_FPS: float = 27.0
const AUTO_WINDOW: float = 4.0
## Ignored after loading or changing quality, while shaders and shadow maps settle.
const AUTO_GRACE: float = 6.0

## scale: 3D resolution. msaa/fxaa: anti-aliasing. dir_atlas/pos_atlas: shadow
## map sizes. soft: RenderingServer.ShadowQuality. splits: moon/lightning
## cascade count. fog: [froxel size, depth]. mirror: mirror resolution factor.
## lod: how many pixels of error are allowed before a simpler mesh LOD is used.
## decay: the procedural grime pass that redraws every wall, floor and ceiling.
const PRESETS: Array[Dictionary] = [
	{"scale": 0.5, "msaa": false, "fxaa": false, "dir_atlas": 2048, "pos_atlas": 2048, "soft": 0,
		"ssao": false, "ssao_quality": 0, "ssil": false, "vfog": false, "fog": [48, 48], "glow": false,
		"splits": 1, "mirror": 0.3, "lod": 8.0, "decay": false},
	{"scale": 0.75, "msaa": false, "fxaa": true, "dir_atlas": 2048, "pos_atlas": 2048, "soft": 1,
		"ssao": false, "ssao_quality": 0, "ssil": false, "vfog": false, "fog": [48, 48], "glow": true,
		"splits": 2, "mirror": 0.5, "lod": 4.0, "decay": true},
	{"scale": 1.0, "msaa": false, "fxaa": true, "dir_atlas": 4096, "pos_atlas": 4096, "soft": 2,
		"ssao": true, "ssao_quality": 1, "ssil": false, "vfog": true, "fog": [64, 64], "glow": true,
		"splits": 4, "mirror": 0.75, "lod": 2.0, "decay": true},
	{"scale": 1.0, "msaa": true, "fxaa": false, "dir_atlas": 8192, "pos_atlas": 8192, "soft": 4,
		"ssao": true, "ssao_quality": 3, "ssil": true, "vfog": true, "fog": [96, 80], "glow": true,
		"splits": 4, "mirror": 1.0, "lod": 1.0, "decay": true},
]

var preset: int = 3
var render_scale: float = 1.0
var fullscreen: bool = false
var vsync: bool = true
var fps_cap: int = 0
var brightness: float = 1.0
## Multiplier on the player's base mouse sensitivity.
var sensitivity: float = 1.0
var invert_y: bool = false
var fov: float = 80.0
var master_volume: float = 1.0
## Everything happening in the building: footsteps, doors, robots, glass.
var effects_volume: float = 1.0
## Rain, thunder and the low drone of the empty building.
var ambience_volume: float = 1.0
## The phone (clicks, buzzes, notifications) and the hour bell.
var interface_volume: float = 1.0
## Lower the quality automatically when the frame rate is too low to play.
var auto_quality: bool = true
## True when no settings file existed and the preset was picked automatically.
var was_auto_detected: bool = false

var _save_timer: float = -1.0
var _auto_time: float = 0.0
var _auto_frames: int = 0
var _auto_grace: float = AUTO_GRACE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Editor runs stay windowed unless the developer chooses otherwise.
	fullscreen = not OS.has_feature("editor")
	_load()
	apply_all()


func _process(delta: float) -> void:
	if _save_timer >= 0.0:
		_save_timer -= delta
		if _save_timer < 0.0:
			save()
	if auto_quality:
		_watch_frame_rate(delta)


## Counts real frames during play; a slow average drops one quality step,
## then the resolution scale once the lowest preset is reached.
func _watch_frame_rate(delta: float) -> void:
	var tree: SceneTree = get_tree()
	if tree.paused or not tree.root.has_focus() or tree.get_first_node_in_group(&"player") == null:
		_auto_time = 0.0
		_auto_frames = 0
		_auto_grace = AUTO_GRACE
		return
	if _auto_grace > 0.0:
		_auto_grace -= delta
		return
	_auto_time += delta
	_auto_frames += 1
	if _auto_time < AUTO_WINDOW:
		return
	var fps: float = float(_auto_frames) / _auto_time
	_auto_time = 0.0
	_auto_frames = 0
	var floor_fps: float = AUTO_MIN_FPS if fps_cap <= 0 else minf(AUTO_MIN_FPS, float(fps_cap) * 0.85)
	if fps >= floor_fps:
		return
	if preset > 0:
		preset -= 1
		render_scale = float(preset_value("scale"))
	elif render_scale > MIN_RENDER_SCALE + 0.01:
		render_scale = maxf(render_scale - 0.1, MIN_RENDER_SCALE)
	else:
		return
	_auto_grace = AUTO_GRACE
	apply_all()
	_save_timer = 0.4
	EventBus.ui_notification.emit("Graphics lowered to %s (%d%%) for a smoother frame rate." % [PRESET_NAMES[preset], roundi(render_scale * 100.0)], 5.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _save_timer >= 0.0:
		save()


# -------------------------------------------------------------------- values

func preset_value(key: String) -> Variant:
	return PRESETS[clampi(preset, 0, PRESETS.size() - 1)][key]


## Changes one setting by property name, applies it and schedules a save.
func set_value(key: StringName, value: Variant) -> void:
	if get(key) == value:
		return
	set(key, value)
	if key == &"preset":
		render_scale = float(preset_value("scale"))
	apply_all()
	_save_timer = 0.4


func adapter_name() -> String:
	return RenderingServer.get_video_adapter_name()


## Best guess for a first launch: integrated graphics start on Low, a real
## graphics card on High, software or OpenGL-fallback rendering on Lowest.
func detect_preset() -> int:
	if String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")) == "gl_compatibility" \
			or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return 0
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return 3
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return 1
		RenderingDevice.DEVICE_TYPE_CPU:
			return 0
	return 2


# ---------------------------------------------------------------------- apply

func apply_all() -> void:
	_apply_window()
	_apply_renderer()
	_apply_audio()
	apply_world()
	changed.emit()


## Applies the settings that live on scene nodes (the Environment and the
## directional lights). GameDirector calls this once the night is built.
func apply_world() -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	for node: Node in scene.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env == null:
			continue
		env.ssao_enabled = bool(preset_value("ssao"))
		env.ssil_enabled = bool(preset_value("ssil"))
		env.volumetric_fog_enabled = bool(preset_value("vfog"))
		env.glow_enabled = bool(preset_value("glow"))
		env.adjustment_enabled = true
		env.adjustment_brightness = brightness
	var mode: int = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	match int(preset_value("splits")):
		1:
			mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		2:
			mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	for node: Node in scene.find_children("*", "DirectionalLight3D", true, false):
		(node as DirectionalLight3D).directional_shadow_mode = mode


func _apply_window() -> void:
	var window: Window = get_tree().root
	if not window.is_embedded() and DisplayServer.get_name() != "headless":
		var is_full: bool = window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
		if fullscreen and not is_full:
			window.mode = Window.MODE_FULLSCREEN
		elif not fullscreen and is_full:
			window.mode = Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = fps_cap


func _apply_renderer() -> void:
	var viewport: Viewport = get_tree().root
	viewport.scaling_3d_scale = clampf(render_scale, MIN_RENDER_SCALE, 1.0)
	# FSR 1 upscaling keeps edges sharp when rendering below native resolution.
	var can_fsr: bool = RenderingServer.get_current_rendering_method() == "forward_plus"
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if can_fsr and render_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.msaa_3d = Viewport.MSAA_2X if bool(preset_value("msaa")) else Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(preset_value("fxaa")) else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.mesh_lod_threshold = float(preset_value("lod"))
	viewport.positional_shadow_atlas_size = int(preset_value("pos_atlas"))
	RenderingServer.directional_shadow_atlas_set_size(int(preset_value("dir_atlas")), true)
	var soft: int = int(preset_value("soft"))
	RenderingServer.directional_soft_shadow_filter_set_quality(soft as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft as RenderingServer.ShadowQuality)
	var ssao_quality: int = int(preset_value("ssao_quality"))
	RenderingServer.environment_set_ssao_quality(ssao_quality as RenderingServer.EnvironmentSSAOQuality, true, 0.5, 2, 50.0, 300.0)
	var fog: Array = preset_value("fog")
	RenderingServer.environment_set_volumetric_fog_volume_size(int(fog[0]), int(fog[1]))


func _apply_audio() -> void:
	_ensure_bus(&"Ambience")
	_ensure_bus(&"Interface")
	_set_bus_level(&"Master", master_volume)
	# "World" belongs to SpatialAudio (every 3D sound, muffled or not).
	_set_bus_level(&"World", effects_volume)
	_set_bus_level(&"Ambience", ambience_volume)
	_set_bus_level(&"Interface", interface_volume)


func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	var index: int = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")


func _set_bus_level(bus_name: StringName, level: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_mute(index, level <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.001)))


# ----------------------------------------------------------------------- disk

func _load() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		was_auto_detected = true
		preset = detect_preset()
		render_scale = float(preset_value("scale"))
		return
	preset = clampi(int(file.get_value("graphics", "preset", preset)), 0, PRESETS.size() - 1)
	render_scale = clampf(float(file.get_value("graphics", "render_scale", preset_value("scale"))), MIN_RENDER_SCALE, 1.0)
	auto_quality = bool(file.get_value("graphics", "auto_quality", auto_quality))
	fullscreen = bool(file.get_value("graphics", "fullscreen", fullscreen))
	vsync = bool(file.get_value("graphics", "vsync", vsync))
	fps_cap = maxi(int(file.get_value("graphics", "fps_cap", fps_cap)), 0)
	brightness = clampf(float(file.get_value("graphics", "brightness", brightness)), 0.6, 1.6)
	sensitivity = clampf(float(file.get_value("game", "sensitivity", sensitivity)), 0.2, 3.0)
	invert_y = bool(file.get_value("game", "invert_y", invert_y))
	fov = clampf(float(file.get_value("game", "fov", fov)), FOV_MIN, FOV_MAX)
	master_volume = clampf(float(file.get_value("audio", "master_volume", master_volume)), 0.0, 1.0)
	effects_volume = clampf(float(file.get_value("audio", "effects_volume", effects_volume)), 0.0, 1.0)
	ambience_volume = clampf(float(file.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0)
	interface_volume = clampf(float(file.get_value("audio", "interface_volume", interface_volume)), 0.0, 1.0)


func save() -> void:
	_save_timer = -1.0
	var file := ConfigFile.new()
	file.set_value("graphics", "preset", preset)
	file.set_value("graphics", "render_scale", render_scale)
	file.set_value("graphics", "auto_quality", auto_quality)
	file.set_value("graphics", "fullscreen", fullscreen)
	file.set_value("graphics", "vsync", vsync)
	file.set_value("graphics", "fps_cap", fps_cap)
	file.set_value("graphics", "brightness", brightness)
	file.set_value("game", "sensitivity", sensitivity)
	file.set_value("game", "invert_y", invert_y)
	file.set_value("game", "fov", fov)
	file.set_value("audio", "master_volume", master_volume)
	file.set_value("audio", "effects_volume", effects_volume)
	file.set_value("audio", "ambience_volume", ambience_volume)
	file.set_value("audio", "interface_volume", interface_volume)
	file.save(SAVE_PATH)
