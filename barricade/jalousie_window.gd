class_name JalousieWindow
extends StaticBody3D
## A sliding window on an exterior wall (Z = +8 street side, Z = -8 creek
## side): aluminium-framed glass sashes on two tracks. The node sits at the
## centre of the opening with its local +Z pointing outdoors. (The class kept
## its old name, JalousieWindow, because the AI refers to it everywhere.)
##
##   OPEN            sashes slid aside - anything can come through quietly
##   CLOSED          sashes shut - light still leaks out
##   TAPED_BLACKOUT  cartolina taped over the glass - the flashlight cannot leak
##   SHATTERED       glass gone; a BrokenGlassHazard lies on the floor inside

enum State { OPEN, CLOSED, TAPED_BLACKOUT, SHATTERED }

const LAYER_INTERACT: int = 2
const LAYER_GLASS: int = 16
const TAPE_TIME: float = 4.0
const CRANK_NOISE: float = 4.0
const SHATTER_NOISE: float = 18.0
const SMALL_WINDOW_HEIGHT: float = 1.0
## Sliding window geometry.
const FRAME: float = 0.05            # outer frame section
const SASH_OVERLAP: float = 0.04     # meeting stiles overlap when shut
const SASH_RAIL: float = 0.035       # sash frame section
const SASH_DEPTH: float = 0.03
const TRACK_OFFSET: float = 0.018    # each track's offset from the frame centre
const LATCH_HEIGHT: float = 0.14     # crescent lock above the pull, on the meeting stile
## Motion, after real aluminium sliders: unlatch, a breakaway tug, a heavy
## glide on worn rollers with a little judder, a soft knock at the stop.
const LATCH_TIME: float = 0.16
const LATCH_OPEN_ANGLE: float = 2.5  # radians the crescent swings to release
const SLIDE_TIME: float = 0.95
const STOP_BUMP: float = 0.012       # fraction of travel the sash rebounds off the stop
const JUDDER: float = 0.0012         # metres of vertical rattle at full speed

@export var width: float = 1.6
@export var height: float = 1.7
@export var room_id: int = 0
@export var initial_state: State = State.CLOSED

var state: State = State.CLOSED

var _slats: Node3D = null
var _sashes: Node3D = null
var _slide: float = 0.0          # 0 = shut, 1 = open (visual only)
## Which half is open: -1 = the left sash slid across, +1 = the right one.
var open_side: int = 1
var _tween: Tween = null
var _tape: MeshInstance3D = null

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


## Builds a complete window node (collision, slats, tape, frame). Used by the
## map builder so the result is saved into the building scene.
static func create(window_width: float, window_height: float, outward: Vector3, room: int) -> JalousieWindow:
	var window := JalousieWindow.new()
	window.width = window_width
	window.height = window_height
	window.room_id = room
	window.basis = Basis(Vector3.UP, atan2(outward.x, outward.z))
	window.collision_layer = LAYER_INTERACT | LAYER_GLASS
	window.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(window_width, window_height, 0.08)
	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	window.add_child(collider)
	# Sliding sashes. Their glass panes live under "Slats" (the shatter state
	# hides that node and SetDresser retints its glass at night); each pane
	# moves with its sash frame. Narrow windows have two sashes, wide ones
	# four in two pairs; in each pair the second sash rides the inner track
	# and slides over the first to open.
	var slats := Node3D.new()
	slats.name = "Slats"
	window.add_child(slats)
	var sashes := Node3D.new()
	sashes.name = "Sashes"
	window.add_child(sashes)
	var inner_w: float = window_width - FRAME * 2.0
	var inner_h: float = window_height - FRAME * 2.0
	# Two sashes on every window, left on the outer track and right on the
	# inner one. Either can be slid across behind/over the other, so the
	# player opens the left half or the right half (one at a time).
	var count: int = 2
	var sash_w: float = (inner_w + SASH_OVERLAP) * 0.5
	var travel: float = sash_w - SASH_OVERLAP
	for i: int in count:
		var x: float = -inner_w * 0.5 + sash_w * 0.5 + float(i) * travel
		var z: float = TRACK_OFFSET if i == 0 else -TRACK_OFFSET
		var sash := Node3D.new()
		sash.name = "Sash%d" % i
		sash.position = Vector3(x, 0.0, z)
		sash.set_meta(&"closed_x", x)
		# Left sash slides right to open the left half; right slides left.
		sash.set_meta(&"open_x", x + travel if i == 0 else x - travel)
		sash.set_meta(&"side", -1 if i == 0 else 1)
		sashes.add_child(sash)
		var rail: float = SASH_RAIL
		for part: Array in [
				[Vector3(sash_w, rail, SASH_DEPTH), Vector3(0.0, inner_h * 0.5 - rail * 0.5, 0.0)],
				[Vector3(sash_w, rail * 1.4, SASH_DEPTH), Vector3(0.0, -inner_h * 0.5 + rail * 0.7, 0.0)],
				[Vector3(rail, inner_h, SASH_DEPTH), Vector3(-sash_w * 0.5 + rail * 0.5, 0.0, 0.0)],
				[Vector3(rail, inner_h, SASH_DEPTH), Vector3(sash_w * 0.5 - rail * 0.5, 0.0, 0.0)]]:
			var bar := MeshInstance3D.new()
			bar.mesh = _box_mesh(part[0], &"frame")
			bar.position = part[1]
			sash.add_child(bar)
		var outer_stile: float = (-1.0 if i == 0 else 1.0) * (sash_w * 0.5 - rail * 0.5)
		if i == 0:
			# Outer-track sash: a flush finger pull (the inner sash slides
			# over this face, so nothing may stick out of it).
			var grip := MeshInstance3D.new()
			grip.name = "Pull"
			grip.mesh = _box_mesh(Vector3(0.014, 0.09, 0.002), &"slot")
			grip.position = Vector3(outer_stile, 0.0, -SASH_DEPTH * 0.5 - 0.001)
			sash.add_child(grip)
		else:
			# Inner sash: a pull handle on its jamb stile, and the crescent
			# cam lock on the meeting stile that hooks over the left sash.
			var pull := MeshInstance3D.new()
			pull.name = "Pull"
			pull.mesh = _box_mesh(Vector3(0.018, 0.12, 0.02), &"handle")
			pull.position = Vector3(outer_stile, 0.0, -SASH_DEPTH * 0.5 - 0.01)
			sash.add_child(pull)
			var latch_base := MeshInstance3D.new()
			latch_base.name = "LatchBase"
			latch_base.mesh = _box_mesh(Vector3(0.026, 0.05, 0.01), &"handle")
			latch_base.position = Vector3(-sash_w * 0.5 + rail * 0.5, LATCH_HEIGHT, -SASH_DEPTH * 0.5 - 0.005)
			sash.add_child(latch_base)
			var latch := Node3D.new()
			latch.name = "Latch"
			latch.position = latch_base.position + Vector3(0.0, 0.0, -0.008)
			sash.add_child(latch)
			var arm := MeshInstance3D.new()
			arm.mesh = _box_mesh(Vector3(0.05, 0.012, 0.006), &"handle")
			arm.position = Vector3(-0.022, 0.0, 0.0)
			latch.add_child(arm)
		var pane := MeshInstance3D.new()
		pane.name = "Pane%d" % i
		pane.mesh = _box_mesh(Vector3(sash_w - rail * 2.0, inner_h - rail * 2.4, 0.006), &"glass")
		pane.position = Vector3(x, -rail * 0.2, z)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pane.set_meta(&"sash", i)
		slats.add_child(pane)
	# Outer frame, with the double track along the sill and head.
	var frame_parts: Array[Array] = [
		[Vector3(window_width, FRAME, 0.12), Vector3(0.0, window_height * 0.5 - FRAME * 0.5, 0.0)],
		[Vector3(window_width, FRAME, 0.12), Vector3(0.0, -window_height * 0.5 + FRAME * 0.5, 0.0)],
		[Vector3(FRAME, window_height, 0.12), Vector3(-window_width * 0.5 + FRAME * 0.5, 0.0, 0.0)],
		[Vector3(FRAME, window_height, 0.12), Vector3(window_width * 0.5 - FRAME * 0.5, 0.0, 0.0)],
	]
	frame_parts.append([Vector3(inner_w, 0.014, 0.006), Vector3(0.0, -inner_h * 0.5 + 0.007, 0.0)])   # track divider
	for i: int in frame_parts.size():
		var part := MeshInstance3D.new()
		part.name = "Frame%d" % i
		part.mesh = _box_mesh(frame_parts[i][0], &"frame")
		part.position = frame_parts[i][1]
		window.add_child(part)
	var tape := MeshInstance3D.new()
	tape.name = "Tape"
	tape.mesh = _box_mesh(Vector3(window_width - 0.06, window_height - 0.06, 0.012), &"tape")
	tape.position.z = -0.065   # in front of the sash pulls
	tape.visible = false
	window.add_child(tape)
	return window


func _ready() -> void:
	add_to_group(&"jalousie_windows")
	_slats = get_node_or_null("Slats") as Node3D
	_sashes = get_node_or_null("Sashes") as Node3D
	_tape = get_node_or_null("Tape") as MeshInstance3D
	state = initial_state
	_apply_state()


# ------------------------------------------------------------------- geometry

func get_outward() -> Vector3:
	return global_transform.basis.z.normalized()


func get_floor_index() -> int:
	return Campus.floor_from_y(global_position.y - 1.0)


## A point `distance` metres outside the building, level with the window.
func get_outside_point(distance: float) -> Vector3:
	return global_position + get_outward() * distance


## A point `distance` metres inside the room, level with the window.
func get_inside_point(distance: float) -> Vector3:
	return global_position - get_outward() * distance


## High vent windows (restrooms, pantry, server room) are too small to enter.
func is_small() -> bool:
	return height < SMALL_WINDOW_HEIGHT


## Light from inside escapes unless the glass is blacked out.
func leaks_light() -> bool:
	return state != State.TAPED_BLACKOUT


func is_breached() -> bool:
	return state == State.OPEN or state == State.SHATTERED


# --------------------------------------------------------------- interactions

func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	match state:
		State.CLOSED:
			actions.append({"id": &"open_left", "label": "Slide the left pane open"})
			actions.append({"id": &"open_right", "label": "Slide the right pane open"})
		State.OPEN:
			actions.append({"id": &"close", "label": "Slide the window shut"})
		State.TAPED_BLACKOUT:
			actions.append({"id": &"untape", "label": "Tear the black card off"})
		State.SHATTERED:
			pass
	return actions


func interact(player: PlayerController, action_id: StringName) -> void:
	match action_id:
		# Left/right as seen from inside the room: the window's local +Z points
		# outdoors, so its local -X half is on the right of someone facing it.
		&"open", &"open_right":
			open_side = -1
			_crank(State.OPEN)
		&"open_left":
			open_side = 1
			_crank(State.OPEN)
		&"close":
			_crank(State.CLOSED)
		&"tape":
			player.start_channel("Taping black card over the window", TAPE_TIME, _finish_tape.bind(player))
		&"untape":
			set_state(State.CLOSED)


func set_state(new_state: State) -> void:
	if state == State.SHATTERED or new_state == state:
		return
	state = new_state
	_apply_state()


func _crank(new_state: State) -> void:
	if state == State.SHATTERED or new_state == state:
		return
	state = new_state
	_animate_slide()
	NoiseManager.emit_noise(global_position, CRANK_NOISE, &"jalousie_crank", self)


func _finish_tape(player: PlayerController) -> void:
	if state != State.CLOSED or not player.inventory.remove_item(ItemDB.BLACKOUT_KIT, 1):
		return
	set_state(State.TAPED_BLACKOUT)
	EventBus.ui_notification.emit("Blacked out. No light gets through this window.", 2.5)


# ------------------------------------------------------------------ Robot API

## Smashes the glass and scatters shards on the floor just inside.
func shatter(_attacker: Node3D = null) -> void:
	if state == State.SHATTERED:
		return
	state = State.SHATTERED
	_apply_state()
	NoiseManager.emit_noise(global_position, SHATTER_NOISE, &"glass_shatter", self)
	SfxSynth.play_at(self, SfxSynth.glass_shatter(), global_position, 4.0)
	var floor_point: Vector3 = get_inside_point(0.9)
	floor_point.y = Campus.floor_y(get_floor_index())
	BrokenGlassHazard.spawn(get_tree().current_scene, floor_point, Vector2(width + 0.6, 1.5), rotation.y)
	EventBus.glass_shattered.emit(self, global_position)


# -------------------------------------------------------------------- visuals

## Snaps the visuals to the current state (load, shatter, tape).
func _apply_state() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	if _slats != null:
		_slats.visible = state != State.SHATTERED
	var open: bool = state == State.OPEN
	_set_slide(1.0 if open else 0.0)
	_set_latch(1.0 if open else 0.0)
	if _tape != null:
		_tape.visible = state == State.TAPED_BLACKOUT


## Animates the sashes to the current open/shut state: unlatch -> slide ->
## knock on the stop, or slide -> knock -> latch. Gameplay state has already
## changed; this is only what the player sees and hears.
func _animate_slide() -> void:
	if _sashes == null:
		_apply_state()
		return
	if _tween != null:
		_tween.kill()
	var open: bool = state == State.OPEN
	var target: float = 1.0 if open else 0.0
	var travel: float = absf(target - _slide)
	_tween = create_tween()
	if open:
		_tween.tween_callback(_play.bind(SfxSynth.latch_click(), -14.0))
		_tween.tween_method(_set_latch, 0.0, 1.0, LATCH_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_interval(0.06)
	if travel > 0.001:
		_tween.tween_callback(_play.bind(SfxSynth.window_slide(), -12.0, randf_range(0.92, 1.06)))
		# Breakaway: the first few percent come slowly while the rollers unstick.
		var breakaway: float = lerpf(_slide, target, 0.06)
		_tween.tween_method(_set_slide, _slide, breakaway, SLIDE_TIME * 0.22 * travel).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_method(_set_slide, breakaway, target, SLIDE_TIME * 0.78 * travel).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		# Knock against the stop and a small rebound.
		var rebound: float = target - signf(target - 0.5) * STOP_BUMP
		_tween.tween_callback(_play.bind(SfxSynth.knock(), -20.0, 1.7))
		_tween.tween_method(_set_slide, target, rebound, 0.05).set_ease(Tween.EASE_OUT)
		_tween.tween_method(_set_slide, rebound, target, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if not open:
		_tween.tween_interval(0.05)
		_tween.tween_callback(_play.bind(SfxSynth.latch_click(), -13.0, 0.9))
		_tween.tween_method(_set_latch, _latch_amount(), 0.0, LATCH_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Places every sliding sash (and its glass) `amount` of the way open, with a
## little vertical rattle while it is moving.
func _set_slide(amount: float) -> void:
	var speed: float = sin(PI * clampf(amount, 0.0, 1.0)) if _tween != null and _tween.is_running() else 0.0
	_slide = amount
	if _sashes == null:
		return
	var t: float = float(Time.get_ticks_msec()) * 0.001
	var rattle: float = (sin(t * 91.0) * 0.6 + sin(t * 53.0) * 0.4) * JUDDER * speed
	for sash: Node in _sashes.get_children():
		var s3 := sash as Node3D
		var closed_x: float = s3.get_meta(&"closed_x", s3.position.x)
		var open_x: float = s3.get_meta(&"open_x", closed_x)
		var moving: bool = int(s3.get_meta(&"side", open_side)) == open_side
		s3.position.x = lerpf(closed_x, open_x, amount) if moving else closed_x
		s3.position.y = rattle if moving else 0.0
		if _slats != null:
			var pane := _slats.get_node_or_null("Pane" + String(sash.name).trim_prefix("Sash")) as Node3D
			if pane != null:
				pane.position.x = s3.position.x
				pane.position.y = s3.position.y - SASH_RAIL * 0.2


## Swings every crescent lock: 0 = hooked shut, 1 = released.
func _set_latch(amount: float) -> void:
	if _sashes == null:
		return
	for sash: Node in _sashes.get_children():
		var latch := sash.get_node_or_null("Latch") as Node3D
		if latch != null:
			latch.rotation.z = -LATCH_OPEN_ANGLE * amount


func _latch_amount() -> float:
	if _sashes != null:
		for sash: Node in _sashes.get_children():
			var latch := sash.get_node_or_null("Latch") as Node3D
			if latch != null:
				return -latch.rotation.z / LATCH_OPEN_ANGLE
	return 0.0


func _play(stream: AudioStream, volume_db: float, pitch: float = 1.0) -> void:
	SfxSynth.play_at(self, stream, global_position, volume_db, pitch, 14.0)


static func _box_mesh(size: Vector3, material_key: StringName) -> BoxMesh:
	var key: String = "%s|%.3f|%.3f|%.3f" % [material_key, size.x, size.y, size.z]
	if _meshes.has(key):
		return _meshes[key]
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(material_key)
	_meshes[key] = mesh
	return mesh


static func _material(key: StringName) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	match key:
		&"glass":
			# Clear glass with a faint green-grey tint. Anything paler turns
			# into a milky panel the moment the flashlight hits it.
			material.albedo_color = Color(0.2, 0.27, 0.28, 0.12)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.roughness = 0.05
			material.metallic_specular = 0.8
			var grime := ShaderMaterial.new()
			grime.shader = load("res://shaders/glass_grime.gdshader")
			# A normal school's windows: a light film, not years of streaks.
			grime.set_shader_parameter(&"grime", 0.12)
			grime.set_shader_parameter(&"sheen", 0.25)
			material.next_pass = grime
		&"frame":
			material.albedo_color = Color(0.14, 0.16, 0.19)
			material.metallic = 0.6
			material.roughness = 0.45
		&"slot":
			material.albedo_color = Color(0.05, 0.05, 0.055)
			material.metallic = 0.4
			material.roughness = 0.5
		&"handle":
			material.albedo_color = Color(0.55, 0.56, 0.58)
			material.metallic = 0.8
			material.roughness = 0.35
		&"tape":
			material.albedo_color = Color(0.03, 0.03, 0.035)
			material.roughness = 0.95
	_materials[key] = material
	return material
