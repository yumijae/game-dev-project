extends Node
## Scent propagation, trail decay, and repellent masking for "Huling Kampana".
## Autoload: ScentManager
## Enables Balbal and Manananggal to hunt Jude via blood/sweat trails,
## and allows Jude to break trails using folk remedies (Ahos, Suka, Lana).

# Structure for an individual scent deposit point
class ScentMarker:
	var position: Vector3
	var floor_level: int
	var intensity: float        # 1.0 to 0.0
	var decay_rate: float       # intensity loss per second
	var scent_type: StringName  # "blood", "sweat", "raw_meat"
	var is_masked: bool = false

# Structure for masking/repellent zones (e.g. spilled vinegar, crushed garlic, holy coconut oil)
class MaskZone:
	var position: Vector3
	var radius: float
	var duration: float         # Remaining life in seconds
	var mask_type: StringName   # "ahos", "suka", "lana"

var _markers: Array[ScentMarker] = []
var _mask_zones: Array[MaskZone] = []

# Maximum simultaneous markers to prevent memory bloat
const MAX_MARKERS := 150
# Minimum spacing between new markers from the same emitter (meters)
const MIN_MARKER_SPACING := 1.2
const FLOOR_HEIGHT := 3.8

var _event_bus: Node = null


func _get_event_bus() -> Node:
	if not _event_bus and is_inside_tree():
		_event_bus = get_node_or_null("/root/EventBus")
	return _event_bus


func _ready() -> void:
	var bus := _get_event_bus()
	if bus:
		bus.scent_dropped.connect(_on_eventbus_scent_dropped)
		bus.scent_mask_applied.connect(_on_eventbus_mask_applied)


func _process(delta: float) -> void:
	# 1. Decay and prune mask zones
	for i in range(_mask_zones.size() - 1, -1, -1):
		var zone := _mask_zones[i]
		zone.duration -= delta
		if zone.duration <= 0.0:
			_mask_zones.remove_at(i)

	# 2. Decay and prune scent markers
	for i in range(_markers.size() - 1, -1, -1):
		var m := _markers[i]
		m.intensity -= m.decay_rate * delta
		if m.intensity <= 0.05:
			_markers.remove_at(i)


# ==============================================================================
# SCENT DEPOSITION & MASKING API
# ==============================================================================

## Drops a scent marker at `pos`.
func drop_scent(pos: Vector3, scent_type: StringName, initial_intensity: float = 1.0, decay_rate: float = 0.03) -> void:
	var floor_idx := get_floor_index(pos.y)

	# Check if this drop point is already inside an active masking zone
	var masked := is_in_mask_zone(pos)

	# Check spacing against last dropped marker of same type
	if not _markers.is_empty():
		var last := _markers[_markers.size() - 1]
		if last.scent_type == scent_type and last.position.distance_to(pos) < MIN_MARKER_SPACING:
			last.intensity = maxf(last.intensity, initial_intensity)
			return

	var m := ScentMarker.new()
	m.position = pos
	m.floor_level = floor_idx
	m.intensity = initial_intensity
	m.decay_rate = decay_rate
	m.scent_type = scent_type
	m.is_masked = masked

	_markers.append(m)
	if _markers.size() > MAX_MARKERS:
		_markers.pop_front()

	var bus := _get_event_bus()
	if bus:
		bus.scent_dropped.emit(pos, floor_idx, initial_intensity, scent_type, masked)


## Creates a temporary repellent / scent-masking zone.
func apply_mask_zone(pos: Vector3, radius: float, duration: float, mask_type: StringName) -> void:
	var z := MaskZone.new()
	z.position = pos
	z.radius = radius
	z.duration = duration
	z.mask_type = mask_type
	_mask_zones.append(z)

	# Instantly mask all existing markers within this zone
	for m in _markers:
		if m.position.distance_to(pos) <= radius:
			m.is_masked = true

	var bus := _get_event_bus()
	if bus:
		bus.scent_mask_applied.emit(pos, radius, duration, mask_type)


## Checks whether a position is covered by any active mask zone.
func is_in_mask_zone(pos: Vector3) -> bool:
	for z in _mask_zones:
		if z.position.distance_to(pos) <= z.radius:
			return true
	return false


## Returns the repellent type at `pos` if an aswang-repelling substance is present.
func get_repellent_at(pos: Vector3) -> StringName:
	for z in _mask_zones:
		if z.position.distance_to(pos) <= z.radius:
			return z.mask_type
	return &""


# ==============================================================================
# AI QUERY & GRADIENT TRACKING
# ==============================================================================

## Finds the strongest unmasked scent marker within `radius` on the same floor.
func get_strongest_scent_near(seeker_pos: Vector3, radius: float, allowed_types: Array[StringName] = []) -> Dictionary:
	var seeker_floor := get_floor_index(seeker_pos.y)
	var best_marker: ScentMarker = null
	var best_score := 0.0

	for m in _markers:
		if m.is_masked or m.floor_level != seeker_floor:
			continue
		if not allowed_types.is_empty() and not allowed_types.has(m.scent_type):
			continue

		var dist := seeker_pos.distance_to(m.position)
		if dist <= radius:
			# Score is high if fresh and close
			var score := m.intensity * (1.0 - (dist / radius))
			if score > best_score:
				best_score = score
				best_marker = m

	if best_marker != null:
		return {
			"position": best_marker.position,
			"intensity": best_marker.intensity,
			"scent_type": best_marker.scent_type,
			"score": best_score
		}

	return {}


## Calculates a normalized direction vector pointing towards fresher scent markers.
## Used by Balbal and Manananggal to track prey fluidly without cheating.
func get_scent_trail_gradient(seeker_pos: Vector3, sample_radius: float, target_type: StringName) -> Vector3:
	var seeker_floor := get_floor_index(seeker_pos.y)
	var weighted_vector := Vector3.ZERO
	var total_weight := 0.0

	for m in _markers:
		if m.is_masked or m.floor_level != seeker_floor or m.scent_type != target_type:
			continue

		var dist := seeker_pos.distance_to(m.position)
		if dist <= sample_radius and dist > 0.2:
			var weight := m.intensity / (dist * dist)
			var dir := (m.position - seeker_pos).normalized()
			weighted_vector += dir * weight
			total_weight += weight

	if total_weight > 0.001:
		return (weighted_vector / total_weight).normalized()

	return Vector3.ZERO


func get_floor_index(y_pos: float) -> int:
	if y_pos >= (FLOOR_HEIGHT * 4.0):
		return 4 # Roof
	return clampi(int(floor(y_pos / FLOOR_HEIGHT)), 0, 3)


# ==============================================================================
# EVENT BUS HANDLERS
# ==============================================================================

func _on_eventbus_scent_dropped(pos: Vector3, _fl: int, intensity: float, s_type: StringName, _masked: bool) -> void:
	# Avoid infinite loop if invoked internally
	pass


func _on_eventbus_mask_applied(_pos: Vector3, _rad: float, _dur: float, _m_type: StringName) -> void:
	pass
