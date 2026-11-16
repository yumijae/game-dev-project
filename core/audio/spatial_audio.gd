extends Node
## Spatial audio for the whole game. Every AudioStreamPlayer3D that enters the
## tree is picked up automatically and given:
##   * Occlusion: rays from the ear to the sound. Each wall, floor slab or
##     closed door in between muffles it more (a low-pass bus) and makes it
##     quieter. Three rays (straight, left/right of it and over it) let sound
##     leak around door frames and corners, like it does in real life.
##   * Head shadow: sounds behind you lose some treble, so front and back are
##     easy to tell apart even on stereo headphones.
##   * Room acoustics: the reverb follows the space you are standing in. A
##     cubicle is dry and close, a classroom has a short slap, and the long
##     tiled corridors and stairwells ring.
##   * Hiding: inside a locker or under a desk the world outside is muffled.
## It also plays a quiet, distant soundscape of a building alone at night.

const BUS_WORLD: StringName = &"World"
## Occlusion levels 0..3: bus, low-pass cutoff (0 = no filter) and level.
const OCC_BUSES: Array[StringName] = [&"World", &"Muffle1", &"Muffle2", &"Muffle3"]
const OCC_CUTOFF: Array[float] = [0.0, 4800.0, 1500.0, 600.0]
const OCC_DB: Array[float] = [0.0, -2.5, -8.0, -14.0]

const OCC_MASK: int = 1 | 8 | 16     # the building, doors and window glass
const UPDATE_INTERVAL: float = 1.0 / 15.0
const PROBE_INTERVAL: float = 0.35
const NEAR_CLEAR: float = 1.4        # anything closer is never occluded
const END_SLACK: float = 0.6         # ignore hits this close to the source
const LEAK_OFFSET: float = 0.9       # the side/over rays for leakage
const MAX_WALLS: int = 3
const PANNING: float = 1.8           # x project 0.5 = 0.9 effective
const BEHIND_DOT: float = -0.35

const AMBIENT_MIN: float = 9.0
const AMBIENT_MAX: float = 24.0

var _players: Array[AudioStreamPlayer3D] = []
var _update_timer: float = 0.0
var _probe_timer: float = 0.0
var _ambient_timer: float = 14.0
var _reverb: AudioEffectReverb = null
var _room_target: Vector3 = Vector3(0.5, 0.2, 30.0)   # room size, wet, predelay
var _room: Vector3 = Vector3(0.5, 0.2, 30.0)
var _probe_dirs: Array[Vector3] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	for i: int in 8:
		var a: float = TAU * float(i) / 8.0
		_probe_dirs.append(Vector3(cos(a), 0.0, sin(a)))
	get_tree().node_added.connect(_on_node_added)


# ------------------------------------------------------------------ buses

func _build_buses() -> void:
	if AudioServer.get_bus_index(BUS_WORLD) >= 0:
		return
	# World: everything in the school goes through the room reverb.
	var world: int = _add_bus(BUS_WORLD, &"Master")
	_reverb = AudioEffectReverb.new()
	_reverb.dry = 1.0
	_reverb.wet = 0.2
	_reverb.room_size = 0.5
	_reverb.damping = 0.35          # hard tiles and concrete
	_reverb.spread = 0.9
	_reverb.hipass = 0.15
	_reverb.predelay_msec = 30.0
	_reverb.predelay_feedback = 0.25
	AudioServer.add_bus_effect(world, _reverb)
	# Muffled sends: each strips more treble before the reverb.
	for level: int in range(1, OCC_BUSES.size()):
		var bus: int = _add_bus(OCC_BUSES[level], BUS_WORLD)
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = OCC_CUTOFF[level]
		lp.resonance = 0.5
		AudioServer.add_bus_effect(bus, lp)
		AudioServer.set_bus_volume_db(bus, OCC_DB[level])
	# A limiter on the master, so a stack of slams can't clip.
	var master: int = AudioServer.get_bus_index(&"Master")
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(master, limiter)


func _add_bus(bus_name: StringName, send: StringName) -> int:
	var index: int = AudioServer.bus_count
	AudioServer.add_bus(index)
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, send)
	return index


# ---------------------------------------------------------------- players

func _on_node_added(node: Node) -> void:
	var player := node as AudioStreamPlayer3D
	if player == null or player.has_meta(&"sa_skip") or _players.has(player):
		return
	player.bus = BUS_WORLD
	player.panning_strength = PANNING
	# Air soaks up the highs over distance.
	player.attenuation_filter_cutoff_hz = 6000.0
	player.attenuation_filter_db = -18.0
	player.set_meta(&"sa_level", 0)
	_players.append(player)
	player.tree_exiting.connect(_forget.bind(player), CONNECT_ONE_SHOT)


func _forget(player: AudioStreamPlayer3D) -> void:
	_players.erase(player)


# ------------------------------------------------------------------ update

func _physics_process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or not camera.is_inside_tree():
		return
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_update_occlusion(camera)
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = PROBE_INTERVAL
		_probe_room(camera)
	_room = _room.lerp(_room_target, minf(delta * 2.5, 1.0))
	if _reverb != null:
		_reverb.room_size = _room.x
		_reverb.wet = _room.y
		_reverb.predelay_msec = _room.z
	_ambient(delta, camera)


func _update_occlusion(camera: Camera3D) -> void:
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ear: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var muffled_floor: int = 1 if _player_is_hiding() else 0
	for player: AudioStreamPlayer3D in _players:
		if not player.playing or not player.is_inside_tree():
			continue
		var source: Vector3 = player.global_position
		var to_source: Vector3 = source - ear
		var distance: float = to_source.length()
		if player.max_distance > 0.0 and distance > player.max_distance + 2.0:
			continue
		var level: int = 0
		if distance > NEAR_CLEAR:
			level = _walls_between(space, ear, source, to_source / distance, distance)
			if to_source.normalized().dot(forward) < BEHIND_DOT:
				level = maxi(level, 1)
		level = clampi(maxi(level, muffled_floor), 0, OCC_BUSES.size() - 1)
		# A little hysteresis, so a sound on the edge of a door frame doesn't flutter.
		var current: int = player.get_meta(&"sa_level", 0)
		if level != current:
			var pending: int = player.get_meta(&"sa_pending", -1)
			if pending == level:
				player.set_meta(&"sa_level", level)
				player.bus = OCC_BUSES[level]
				player.set_meta(&"sa_pending", -1)
			else:
				player.set_meta(&"sa_pending", level)
		else:
			player.set_meta(&"sa_pending", -1)


## How many solid things stand between the ear and the sound, taking the
## easiest of three paths (straight, around the side, over the top).
func _walls_between(space: PhysicsDirectSpaceState3D, ear: Vector3, source: Vector3,
		direction: Vector3, distance: float) -> int:
	var side: Vector3 = direction.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var best: int = _count_hits(space, ear, source, distance)
	if best == 0:
		return 0
	for offset: Vector3 in [side * LEAK_OFFSET, -side * LEAK_OFFSET, Vector3.UP * LEAK_OFFSET * 0.6]:
		# A detour costs a little: leaked sound is never as clear as direct.
		var hits: int = _count_hits(space, ear, source + offset, distance)
		best = mini(best, hits + 1) if hits > 0 else mini(best, 1)
		if best <= 1:
			break
	return best


func _count_hits(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, distance: float) -> int:
	var hits: int = 0
	var origin: Vector3 = from
	var direction: Vector3 = (to - from).normalized()
	while hits < MAX_WALLS:
		var query := PhysicsRayQueryParameters3D.create(origin, to, OCC_MASK)
		query.hit_from_inside = false
		query.hit_back_faces = false
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			break
		var at: Vector3 = hit.position
		if at.distance_to(to) < END_SLACK:
			break   # the thing the sound is coming from, not a wall
		# A concrete floor slab stops far more than a partition wall.
		var normal: Vector3 = hit.normal
		hits += 2 if absf(normal.y) > 0.7 else 1
		origin = at + direction * 0.05
		if from.distance_to(origin) >= distance:
			break
	return mini(hits, MAX_WALLS)


func _player_is_hiding() -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as PlayerController
	return player != null and player.is_hidden


# -------------------------------------------------------------- room probe

## Feels out the space around the ear and sets the reverb to match it.
func _probe_room(camera: Camera3D) -> void:
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	var ear: Vector3 = camera.global_position
	var total: float = 0.0
	var longest: float = 0.0
	for dir: Vector3 in _probe_dirs:
		var d: float = _ray_length(space, ear, dir, 30.0)
		total += d
		longest = maxf(longest, d)
	var ceiling: float = _ray_length(space, ear, Vector3.UP, 12.0)
	var average: float = total / float(_probe_dirs.size())
	# Size from the average reach; long corridors and tall stairwells ring more.
	var size: float = clampf((average - 1.2) / 9.0, 0.0, 1.0)
	var length: float = clampf((longest - 6.0) / 20.0, 0.0, 1.0)
	var height: float = clampf((ceiling - 2.0) / 6.0, 0.0, 1.0)
	var room_size: float = clampf(0.18 + size * 0.45 + length * 0.25 + height * 0.15, 0.1, 0.95)
	var wet: float = clampf(0.08 + size * 0.14 + length * 0.12 + height * 0.06, 0.06, 0.38)
	var predelay: float = lerpf(6.0, 70.0, clampf(size * 0.6 + length * 0.4, 0.0, 1.0))
	if ceiling >= 11.9:
		# Open sky (rooftop, courtyard): sound just leaves.
		room_size = 0.25
		wet = 0.05
		predelay = 20.0
	if _player_is_hiding():
		room_size *= 0.4
		wet *= 0.5
		predelay = 4.0
	_room_target = Vector3(room_size, wet, predelay)


func _ray_length(space: PhysicsDirectSpaceState3D, from: Vector3, direction: Vector3, reach: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * reach, OCC_MASK)
	var hit: Dictionary = space.intersect_ray(query)
	return reach if hit.is_empty() else from.distance_to(hit.position)


# --------------------------------------------------------------- ambience

## Now and then the empty building makes a sound somewhere out of sight:
## a duct ticking as it cools, a creak, a drip, something settling.
func _ambient(delta: float, camera: Camera3D) -> void:
	if get_tree().get_first_node_in_group(&"player") == null:
		return
	_ambient_timer -= delta
	if _ambient_timer > 0.0:
		return
	_ambient_timer = randf_range(12.0, 30.0)
	var map: RID = camera.get_world_3d().navigation_map
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	var ear: Vector3 = camera.global_position
	var angle: float = randf() * TAU
	var reach: float = randf_range(AMBIENT_MIN, AMBIENT_MAX)
	var guess: Vector3 = ear + Vector3(cos(angle), randf_range(-0.6, 0.3), sin(angle)) * reach
	var spot: Vector3 = NavigationServer3D.map_get_closest_point(map, guess)
	if spot.distance_to(ear) < AMBIENT_MIN * 0.7:
		return
	var pick: int = randi() % 6
	match pick:
		0:
			SfxSynth.play_at(self, SfxSynth.metal_creak(), spot + Vector3.UP * 2.6, -8.0, randf_range(0.7, 1.2), 32.0)
		1:
			SfxSynth.play_at(self, SfxSynth.knock(), spot + Vector3.UP * 2.8, -12.0, randf_range(2.2, 2.8), 26.0)
			SfxSynth.play_at(self, SfxSynth.knock(), spot + Vector3.UP * 2.8, -15.0, randf_range(2.2, 2.8), 26.0)
		2:
			SfxSynth.play_at(self, SfxSynth.drip(), spot + Vector3.UP * 0.05, -14.0, randf_range(0.8, 1.3), 18.0)
		3:
			SfxSynth.play_at(self, SfxSynth.thud(), spot + Vector3.UP * 0.5, -10.0, randf_range(0.5, 0.7), 34.0)
		4:
			SfxSynth.play_at(self, SfxSynth.scrape(), spot + Vector3.UP * 0.3, -18.0, randf_range(0.5, 0.8), 26.0)
		5:
			SfxSynth.play_at(self, SfxSynth.clatter(), spot + Vector3.UP * 0.2, -20.0, randf_range(0.6, 0.9), 24.0)
