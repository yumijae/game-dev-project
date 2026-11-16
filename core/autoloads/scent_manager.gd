extends Node
## ScentManager (autoload) - how strongly Juan smells, and the trail he leaves.
##
## scent_level (0-100) is the sum of three sources:
##   * Bleeding: jumps to 50 the moment it starts, then climbs 5 per second.
##   * Panic sweat: +25 while Panic is above 80.
##   * Exhaustion: +15 while Stamina is below 20.
## Above 30 a ScentBreadcrumb drops every 3 seconds. Aswang follow the crumbs in
## order, so a trail that ends at a locker or a restroom stall gives him away.

const BLEED_BASE: float = 50.0
const BLEED_RATE: float = 5.0
const PANIC_SWEAT_THRESHOLD: float = 80.0
const PANIC_SWEAT_SCENT: float = 25.0
const EXHAUSTION_THRESHOLD: float = 20.0
const EXHAUSTION_SCENT: float = 15.0
const BREADCRUMB_THRESHOLD: float = 30.0
const BREADCRUMB_INTERVAL: float = 3.0
const MAX_BREADCRUMBS: int = 60
const GARLIC_RUB_DURATION: float = 60.0

## What the Aswang can smell right now (0 while a garlic rub is active).
var scent_level: float = 0.0
## Scent before masking; shown on the HUD.
var raw_scent_level: float = 0.0
var mask_time_left: float = 0.0

var _player: Node3D = null
var _stats: PlayerStats = null
var _bleed_scent: float = 0.0
var _was_bleeding: bool = false
var _drop_timer: float = 0.0
var _serial: int = 0
var _crumb_root: Node3D = null


## Called by the player on spawn. `stats` is read every frame.
func register_player(player: Node3D, stats: PlayerStats) -> void:
	_player = player
	_stats = stats
	reset()


func reset() -> void:
	scent_level = 0.0
	raw_scent_level = 0.0
	mask_time_left = 0.0
	_bleed_scent = 0.0
	_was_bleeding = false
	_drop_timer = 0.0
	clear_breadcrumbs()


func _process(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_stats):
		return
	if mask_time_left > 0.0:
		mask_time_left = maxf(mask_time_left - delta, 0.0)
	_update_level(delta)
	_drop_timer += delta
	if _drop_timer >= BREADCRUMB_INTERVAL:
		_drop_timer = 0.0
		if scent_level > BREADCRUMB_THRESHOLD:
			_drop_breadcrumb()


func is_masked() -> bool:
	return mask_time_left > 0.0


## Crushed garlic rubbed into the uniform: 60 s during which nothing can smell Juan.
func apply_garlic_rub(duration: float = GARLIC_RUB_DURATION) -> void:
	mask_time_left = maxf(mask_time_left, duration)
	EventBus.scent_masked.emit(duration)


## Disinfecting and bandaging: scent drops to 0 and the old trail goes cold.
func reset_scent() -> void:
	_bleed_scent = 0.0
	_was_bleeding = false
	scent_level = 0.0
	raw_scent_level = 0.0
	clear_breadcrumbs()
	EventBus.scent_level_changed.emit(0.0)


func clear_breadcrumbs() -> void:
	if is_instance_valid(_crumb_root):
		for crumb: Node in _crumb_root.get_children():
			crumb.queue_free()


func get_breadcrumbs() -> Array[ScentBreadcrumb]:
	var crumbs: Array[ScentBreadcrumb] = []
	if is_instance_valid(_crumb_root):
		for node: Node in _crumb_root.get_children():
			var crumb := node as ScentBreadcrumb
			if crumb != null and not crumb.is_queued_for_deletion():
				crumbs.append(crumb)
	return crumbs


## The newest crumb with a serial above `after_serial` that the seeker can
## smell from where it stands. Slabs block scent, so only the seeker's own
## floor counts unless it is sniffing from a stairwell. Null when none.
func find_next_breadcrumb(seeker_pos: Vector3, sniff_radius: float, after_serial: int = 0) -> ScentBreadcrumb:
	var seeker_floor: int = Campus.floor_from_y(seeker_pos.y)
	var in_stairwell: bool = Campus.stairwell_at(seeker_pos) != ""
	var best: ScentBreadcrumb = null
	for crumb: ScentBreadcrumb in get_breadcrumbs():
		if crumb.serial <= after_serial:
			continue
		var crumb_floor: int = Campus.floor_from_y(crumb.global_position.y)
		if crumb_floor != seeker_floor and not in_stairwell:
			continue
		var reach: float = sniff_radius * (0.5 + 0.5 * crumb.get_freshness()) * (0.6 + crumb.strength / 100.0)
		var flat := Vector3(crumb.global_position.x - seeker_pos.x, 0.0, crumb.global_position.z - seeker_pos.z)
		if flat.length() > reach:
			continue
		if best == null or crumb.serial > best.serial:
			best = crumb
	return best


## The crumb dropped right after `serial` - the next step along the trail.
func get_following_breadcrumb(serial: int) -> ScentBreadcrumb:
	var next: ScentBreadcrumb = null
	for crumb: ScentBreadcrumb in get_breadcrumbs():
		if crumb.serial > serial and (next == null or crumb.serial < next.serial):
			next = crumb
	return next


func _update_level(delta: float) -> void:
	if _stats.is_bleeding:
		if not _was_bleeding:
			_bleed_scent = maxf(_bleed_scent, BLEED_BASE)
		_bleed_scent = minf(_bleed_scent + BLEED_RATE * delta, 100.0)
	_was_bleeding = _stats.is_bleeding
	var level: float = _bleed_scent
	if _stats.panic > PANIC_SWEAT_THRESHOLD:
		level += PANIC_SWEAT_SCENT
	if _stats.stamina < EXHAUSTION_THRESHOLD:
		level += EXHAUSTION_SCENT
	level = clampf(level, 0.0, 100.0)
	var masked_level: float = 0.0 if is_masked() else level
	if not is_equal_approx(level, raw_scent_level) or not is_equal_approx(masked_level, scent_level):
		raw_scent_level = level
		scent_level = masked_level
		EventBus.scent_level_changed.emit(scent_level)


func _drop_breadcrumb() -> void:
	var root: Node3D = _get_crumb_root()
	if root == null:
		return
	if root.get_child_count() >= MAX_BREADCRUMBS:
		root.get_child(0).queue_free()
	_serial += 1
	var crumb := ScentBreadcrumb.new()
	crumb.serial = _serial
	crumb.strength = scent_level
	crumb.is_blood = _stats.is_bleeding
	if _player.has_method("get_hiding_spot"):
		crumb.hiding_spot = _player.call("get_hiding_spot") as Node3D
	root.add_child(crumb)
	crumb.global_position = _player.global_position
	EventBus.scent_breadcrumb_dropped.emit(crumb)


func _get_crumb_root() -> Node3D:
	if is_instance_valid(_crumb_root):
		return _crumb_root
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	_crumb_root = Node3D.new()
	_crumb_root.name = "ScentTrail"
	scene.add_child(_crumb_root)
	return _crumb_root
