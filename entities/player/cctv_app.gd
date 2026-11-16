class_name CctvApp
extends Node
## The school's CCTV on Juan's phone. Every security camera mounted in the
## building is a feed; the view is the camera's own infrared night vision, so
## rooms that are pitch black in person show up grey and grainy on screen.
## Watching costs battery and keeps the phone screen glowing in Juan's hand,
## and the robots know when a lens is on them (`is_watching`).
##
## Shown inside the phone's Cameras app (PhoneScreen); V opens it directly.

const BATTERY_DRAIN: float = 0.035          # %/s on top of the phone's standby drain
const FEED_SIZE: Vector2i = Vector2i(640, 360)
const LOOK_DOWN_DEGREES: float = 24.0
const FEED_FOV: float = 78.0
const SIGHT_MASK: int = 1                   # walls and furniture block a camera's view

var is_open: bool = false
## The Server Room breaker killed the CCTV server: every feed is static.
var is_offline: bool = false

var _player: PlayerController = null
var _feeds: Array[Dictionary] = []          # {"xf": Transform3D, "name": String}
var _index: int = 0
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _title_text: String = ""
var _static: float = 0.0


func setup(player: PlayerController) -> void:
	_player = player


func _ready() -> void:
	EventBus.lab_power_cut.connect(_on_lab_power_cut)
	_viewport = SubViewport.new()
	_viewport.name = "CctvFeed"
	_viewport.size = FEED_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.audio_listener_enable_3d = false
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = FEED_FOV
	_camera.near = 0.05
	_camera.far = 40.0
	_camera.environment = _night_vision()
	_viewport.add_child(_camera)
	# The building is instanced before the player; scan once everything exists.
	_scan_cameras.call_deferred()


# ------------------------------------------------------------------- feeds

func _scan_cameras() -> void:
	_feeds.clear()
	var school: Node = get_tree().get_first_node_in_group(&"school")
	if school == null:
		return
	var props: Node = school.get_node_or_null("Props")
	if props == null:
		return
	for node: Node in props.get_children():
		var cam := node as Node3D
		if cam == null or not String(cam.scene_file_path).contains("security_camera"):
			continue
		var forward: Vector3 = cam.global_basis.z.normalized()
		var down: float = deg_to_rad(LOOK_DOWN_DEGREES)
		var view: Vector3 = (forward * cos(down) + Vector3.DOWN * sin(down)).normalized()
		var lens: Vector3 = cam.global_position + forward * 0.14 + Vector3.DOWN * 0.06
		_feeds.append({
			"xf": Transform3D(Basis.looking_at(view, Vector3.UP), lens),
			"name": _feed_name(lens),
			"floor": Campus.floor_from_y(lens.y - 1.0),
		})
	_feeds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["floor"] < b["floor"] or (a["floor"] == b["floor"] and String(a["name"]) < String(b["name"])))


func _feed_name(pos: Vector3) -> String:
	if not Campus.is_inside_footprint(pos, 0.3):
		return "MAIN ENTRANCE"
	var where: String = Campus.location_name(pos).get_slice(" (#", 0)
	if Campus.is_in_corridor(pos):
		where += " (WEST)" if pos.x < 0.0 else " (EAST)"
	return where.to_upper()


# ------------------------------------------------------------------ control

func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open or _feeds.is_empty() or _player == null:
		return
	if _player.stats.is_phone_dead():
		EventBus.ui_notification.emit("The phone is dead.", 2.0)
		return
	is_open = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_show_feed()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func step(direction: int) -> void:
	if not is_open or _feeds.is_empty():
		return
	_index = posmod(_index + direction, _feeds.size())
	_show_feed()


func _show_feed() -> void:
	var feed: Dictionary = _feeds[_index]
	_camera.global_transform = feed["xf"]
	_title_text = "\u25CF REC   CAM %02d   %s" % [_index + 1, feed["name"]]
	# A burst of static while the feed switches.
	_static = 1.0


func _process(delta: float) -> void:
	if not is_open:
		return
	if _player == null or _player.is_dead or _player.stats.is_phone_dead():
		close()
		return
	_player.stats.drain_battery(BATTERY_DRAIN * delta)
	_static = maxf(_static - delta * 4.0, 0.0)


## True when the open feed can see `point`: inside the lens frustum and with
## no wall in between. Robots that freeze under observation ask this.
func is_watching(point: Vector3) -> bool:
	if not is_open or is_offline or not _camera.is_position_in_frustum(point):
		return false
	var from: Vector3 = _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, point, SIGHT_MASK)
	var hit: Dictionary = _camera.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(point) < 0.6


# ----------------------------------------------------------------------- look

func _night_vision() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	# The camera's infrared illuminator: flat, even light everywhere it looks.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 0.85)
	env.ambient_light_energy = 1.25
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.fog_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.0
	env.adjustment_contrast = 1.15
	return env


func get_feed_texture() -> Texture2D:
	return _viewport.get_texture()


func get_title() -> String:
	return _title_text


func get_static() -> float:
	return 1.0 if is_offline else _static


func _on_lab_power_cut(_cause: StringName) -> void:
	is_offline = true


func feed_index() -> int:
	return _index


func feed_count() -> int:
	return _feeds.size()


func feed_name() -> String:
	return String(_feeds[_index]["name"]) if not _feeds.is_empty() else ""


func feed_floor() -> int:
	return int(_feeds[_index]["floor"]) if not _feeds.is_empty() else 0
