class_name ScuttleAI
extends RobotBase
## SCUTTLE - a six-legged cable-inspection crawler, built to run through
## ceiling voids and under raised floors. Small, fast and nearly blind, with
## very good hearing.
##
##   - Goes anywhere, stairs included.
##   - Closed doors don't stop it: it flattens and squeezes through the gap
##     underneath - unless something heavy is pushed against the bottom of the
##     door; nothing keeps it out.
##   - Hunts by sound. It only sees Juan within a few metres.
##   - Its skittering clicks give it away before it arrives.
##   - The model is one rigid piece (legs included), so the whole body is
##     animated (_process): it waggles and bobs as it runs, twitches when it
##     stops, hops when it spots Juan, rears up just before it strikes,
##     wriggles under doors and thrashes when sprayed.

enum State { DOCKED, ROAM, INVESTIGATE, CHASE, OFF }

const ROAM_SPEED: float = 1.8
const INVESTIGATE_SPEED: float = 2.5
## 3.2 m/s (4.0 by 5 AM): just under Juan's walk early on, well short of his
## sprint late. Nothing else keeps it out (doors, stairs), so outrunning it
## has to be possible: at 3.7 (4.6 late) it caught a walking Juan from
## anywhere and only a long sprint shook it.
const CHASE_SPEED: float = 3.2
## How long it scratches at a door gap before it squeezes under: a warning
## you can hear, and a moment to get a heavy prop across the gap.
const DIG_TIME: float = 2.6
const SQUEEZE_TIME: float = 1.3
## Out of sight this long and it stops chasing and goes to look instead.
const LOSE_TIME: float = 2.0
## Sounds fainter than this it ignores; it used to bolt towards any noise it
## could barely make out (0.1), so it was always the first robot on Juan.
const MIN_AUDIBILITY: float = 0.25
const RETREAT_TIME: float = 9.0
const CLICK_INTERVAL: float = 0.085
## In a chase it rears up once Juan is this close: the last warning.
const REAR_RANGE: float = 2.6
## It runs in bursts: after reaching a spot it holds still and listens.
const PAUSE_TIME := Vector2(0.3, 0.9)

var state: State = State.DOCKED

var _target: Vector3 = Vector3.ZERO
var _roam_timer: float = 0.0
var _lose_timer: float = 0.0
var _retreat_timer: float = 0.0
var _door_timer: float = 0.0
var _click_timer: float = 0.0
var _squeezing: bool = false
var _gait: float = 0.0
# Body animation (see _process).
var _anim_time: float = 0.0
## One-shot gestures, each counting down from 1 to 0.
var _hop: float = 0.0
var _pounce: float = 0.0
## Idle twitches: a sudden small turn, held, then another.
var _twitch_timer: float = 1.0
var _twitch_yaw: float = 0.0
var _tipped: float = 0.0
var _pause_timer: float = 0.0


## Heading for a SearchPlanner waypoint (not a random wander point).
var _searching: bool = false
## Longest it spends getting to one search waypoint.
const SEARCH_LEG_TIME: float = 20.0


func _init() -> void:
	display_name = "SCUTTLE"
	hostile_id = &"scuttle"
	# Nearly blind: 4 m (3 m in the dark, 2 m if he crouches there).
	vision_range = 4.0
	hearing = 1.0
	# Has to get right under him to strike, so a sidestep can save him.
	catch_distance = 0.85
	body_radius = 0.2
	body_height = 0.42
	eye_height = 0.3
	wake_minute = 60       # 12:45 AM
	# A tinny diagnostics speaker.
	voice_hz = 320.0
	voice_grit = 0.3
	scare_pitch = 1.45
	taunt_range = 12.0


func kind() -> StringName:
	return &"scuttle"


func get_feet_description() -> String:
	return "Thin metal legs, too many of them, tapping at the gap under the door. It wants in."


# ------------------------------------------------------------------ lifecycle

func _on_activated() -> void:
	state = State.ROAM
	_pick_roam_target()


func _on_shutdown() -> void:
	state = State.OFF
	if model != null:
		# Legs give way; it settles flat.
		var t := create_tween()
		t.tween_property(model, ^"position:y", -0.12, 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	SfxSynth.play_at(self, SfxSynth.clatter(), global_position, -10.0, 1.6)


func _on_attack_landed(fatal: bool) -> void:
	SfxSynth.play_at(self, SfxSynth.clatter(), global_position + Vector3.UP * 0.3, 0.0, 1.8)
	_pounce = 1.0
	if not fatal:
		_retreat_timer = RETREAT_TIME
		state = State.ROAM
		_searching = false
		_target = retreat_point()
		_roam_timer = RETREAT_TIME


# ---------------------------------------------------------------------- tick

func _tick(delta: float) -> void:
	if _squeezing:
		return
	_retreat_timer = maxf(_retreat_timer - delta, 0.0)
	_sense(delta)
	var speed: float = ROAM_SPEED
	match state:
		State.ROAM:
			_roam_timer -= delta
			if _roam_timer <= 0.0:
				_give_up_waypoint()
				_pick_roam_target()
		State.INVESTIGATE:
			speed = INVESTIGATE_SPEED
		State.CHASE:
			speed = CHASE_SPEED
			if knows_where():
				_target = last_known
	if state == State.CHASE:
		_pause_timer = 0.0
	elif _pause_timer > 0.0:
		_pause_timer -= delta
		ground_idle(delta)
		return
	if _handle_door(delta):
		return
	if stuck_count >= 3:
		stuck_count = 0
		_give_up_waypoint()
		_pick_roam_target()
	var arrived: bool = nav_move_to(_target, speed * get_speed_factor(), delta)
	face_direction(_desired_direction, delta, 14.0)
	_skitter(delta)
	if state == State.CHASE and _retreat_timer <= 0.0:
		try_attack_player()
	if arrived:
		_pause_timer = randf_range(PAUSE_TIME.x, PAUSE_TIME.y)
		if state == State.INVESTIGATE:
			# Nothing here: search the rooms he most likely went to.
			state = State.ROAM
			if begin_search():
				_pick_roam_target()
			else:
				_target = random_nav_point(global_position, 4.0)
				_roam_timer = 6.0
		elif state == State.ROAM:
			if _searching:
				_searching = false
				search_arrived()
			_pick_roam_target()


func _sense(delta: float) -> void:
	if player == null or player.is_dead or _retreat_timer > 0.0:
		return
	if can_see_player():
		if state != State.CHASE:
			_hop = 1.0
		state = State.CHASE
		remember(player.global_position)
		_lose_timer = LOSE_TIME
	elif state == State.CHASE:
		_lose_timer -= delta
		if _lose_timer <= 0.0:
			state = State.INVESTIGATE
			_target = last_known if knows_where() else global_position


func _on_found_hidden(at: Vector3) -> void:
	if state == State.OFF or state == State.DOCKED or _retreat_timer > 0.0:
		return
	state = State.CHASE
	_target = at
	_lose_timer = LOSE_TIME
	_pause_timer = 0.0


func _on_heard(origin: Vector3, _noise_type: StringName, audibility: float) -> void:
	if state == State.CHASE or state == State.OFF or state == State.DOCKED or audibility < MIN_AUDIBILITY:
		return
	state = State.INVESTIGATE
	_target = origin
	_searching = false
	_pause_timer = 0.0


func _pick_roam_target() -> void:
	_roam_timer = randf_range(6.0, 12.0)
	_searching = false
	if _retreat_timer > 0.0:
		_target = retreat_point()
		return
	var waypoint: Vector3 = next_search_waypoint()
	if waypoint != Vector3.INF:
		_target = waypoint
		_searching = true
		_roam_timer = SEARCH_LEG_TIME
		return
	var around: Vector3 = global_position
	if knows_where():
		around = point_along_route(last_known, 10.0)
	elif randf() < 0.15:
		# A vague hunch now and then, so it never just sits in one place.
		around = point_along_route(hunch(12.0), 10.0)
	_target = random_nav_point(around, 8.0)


## A search waypoint it could not reach in time: skip it.
func _give_up_waypoint() -> void:
	if _searching:
		_searching = false
		search.arrive()


# --------------------------------------------------------------------- doors

## Closed door ahead: squeeze under it, or give up if the gap is blocked.
func _handle_door(delta: float) -> bool:
	var door: InteractableDoor = find_blocking_door(1.0)
	if door == null:
		_door_timer = 0.0
		return false
	ground_idle(delta)
	_door_timer += delta
	var exit_at: Vector3 = _squeeze_exit(door) if door.can_slip_under() else Vector3.INF
	if exit_at != Vector3.INF:
		# Digs at the gap first: scratching you can hear through the door.
		if fmod(_door_timer, 0.4) < delta:
			SfxSynth.play_at(self, SfxSynth.scrape(), door.get_center() + Vector3.UP * 0.1, -9.0, randf_range(1.9, 2.4), 12.0)
		if _door_timer >= DIG_TIME:
			_squeeze_under(door, exit_at)
		return true
	# Blocked at the bottom (or something stands right behind the door, so
	# there is nowhere to come out): scratch at it, then go elsewhere.
	if fmod(_door_timer, 0.7) < delta:
		SfxSynth.play_at(self, SfxSynth.scrape(), door.get_center() + Vector3.UP * 0.1, -10.0, randf_range(1.9, 2.3), 10.0)
	if _door_timer >= 2.5:
		_door_timer = 0.0
		var side: float = door.which_side(global_position)
		turn_from_door(door)
		_target = random_nav_point(door.get_side_position(side, 4.0), 3.0)
		state = State.ROAM
		_roam_timer = 8.0
	return true


## Where it can come out on the far side of `door`: walkable floor with room
## for its body, close behind the door. Vector3.INF when there is none. It
## used to always pop out 0.9 m past the door, even inside a crate or CPU
## tower standing there; the physics push-out then drove it through the floor
## and it fell out of the world.
func _squeeze_exit(door: InteractableDoor) -> Vector3:
	var side: float = door.which_side(global_position)
	var map: RID = get_world_3d().navigation_map
	var space := get_world_3d().direct_space_state
	var body := CapsuleShape3D.new()
	body.radius = body_radius + 0.04
	body.height = maxf(body_height, body.radius * 2.0 + 0.02)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body
	query.collision_mask = MOVE_MASK
	query.exclude = [get_rid()]
	for distance: float in [0.9, 1.2, 0.7, 1.5]:
		for lateral: float in [0.0, 0.3, -0.3]:
			var probe: Vector3 = door.get_side_position(-side, distance) + door.get_along() * lateral
			probe.y = global_position.y
			var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, probe)
			if Vector2(on_mesh.x - probe.x, on_mesh.z - probe.z).length() > 0.25 or absf(on_mesh.y - probe.y) > 0.4:
				continue
			if door.which_side(on_mesh) == side:
				continue
			var spot := Vector3(on_mesh.x, global_position.y, on_mesh.z)
			query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * (body.height * 0.5 + 0.03))
			if space.intersect_shape(query, 1).is_empty():
				return spot
	return Vector3.INF


func _squeeze_under(door: InteractableDoor, out: Vector3) -> void:
	_squeezing = true
	_door_timer = 0.0
	velocity = Vector3.ZERO
	body_shape.disabled = true
	var side: float = door.which_side(global_position)
	var under: Vector3 = door.get_side_position(0.0, 0.0)
	under.y = global_position.y
	face_point(out, 1.0, 0.0)
	# Now heading away from this door, so it is not "ahead" any more.
	_desired_direction = (out - under).normalized()
	nav.target_position = _target
	SfxSynth.play_at(self, SfxSynth.scrape(), under + Vector3.UP * 0.1, -6.0, 1.8)
	var t := create_tween()
	t.tween_property(model, ^"scale", Vector3(1.15, 0.35, 1.15), 0.25)
	t.tween_property(self, ^"global_position", under, SQUEEZE_TIME * 0.5)
	t.tween_property(self, ^"global_position", out, SQUEEZE_TIME * 0.5)
	t.tween_property(model, ^"scale", Vector3.ONE, 0.2)
	t.tween_callback(func() -> void:
		body_shape.disabled = false
		_squeezing = false)


# ------------------------------------------------------------------ movement

## Clicks while it runs; the gait phase drives the body animation.
func _skitter(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	if speed < 0.4:
		return
	_gait += delta * speed * 9.0
	_click_timer -= delta
	if _click_timer <= 0.0:
		_click_timer = CLICK_INTERVAL * (CHASE_SPEED / maxf(speed, 1.0)) * 0.6
		SfxSynth.play_at(self, SfxSynth.click(), global_position + Vector3.UP * 0.1, -22.0, randf_range(1.3, 1.9), 12.0)


# ---------------------------------------------------------------- animation

## Moves the whole body on top of wherever the AI has put it. Runs even while
## stunned or squeezing under a door. (Positive pitch tips the nose down.)
func _process(delta: float) -> void:
	if model == null:
		return
	_anim_time += delta
	var t: float = _anim_time
	if state == State.OFF or state == State.DOCKED:
		if state == State.OFF:
			# Dead on the floor, tipped onto one set of legs.
			_tipped = move_toward(_tipped, 1.0, delta * 3.0)
			model.rotation = Vector3(0.0, PI, 0.3 * _tipped)
		return
	_tipped = 0.0
	_hop = move_toward(_hop, 0.0, delta * 3.2)
	_pounce = move_toward(_pounce, 0.0, delta * 3.0)
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var run: float = clampf(speed / CHASE_SPEED, 0.0, 1.0)
	var pitch: float = 0.0
	var roll: float = 0.0
	var yaw: float = 0.0
	var lift: float = 0.0
	if stun_time_left > 0.0:
		# Sensors whited out: it thrashes on the spot.
		var fade: float = clampf(stun_time_left / 1.2, 0.3, 1.0)
		roll = sin(t * 41.0) * 0.28 * fade
		pitch = sin(t * 29.0) * 0.16 * fade
		yaw = sin(t * 17.0) * 0.5 * fade
		lift = absf(sin(t * 23.0)) * 0.03 * fade
	elif _squeezing:
		# Flat under the door, wriggling through.
		yaw = sin(t * 26.0) * 0.22
		roll = sin(t * 19.0) * 0.05
	elif speed > 0.4:
		# Running: the body swings side to side over its legs, nose down.
		yaw = sin(_gait * 0.5) * lerpf(0.07, 0.16, run)
		roll = sin(_gait * 0.5 + 1.2) * lerpf(0.04, 0.09, run)
		pitch = 0.1 * run
		lift = absf(sin(_gait)) * lerpf(0.012, 0.022, run)
	else:
		# Stopped: holds dead still, then snaps a little way round.
		_twitch_timer -= delta
		if _twitch_timer <= 0.0:
			_twitch_timer = randf_range(0.25, 1.4)
			_twitch_yaw = randf_range(-0.5, 0.5)
		yaw = _twitch_yaw
		lift = -0.01
		if _door_timer > 0.0:
			# Gap blocked: digs at the bottom of the door.
			pitch = 0.18 + maxf(sin(t * 16.0), 0.0) * 0.14
	if state == State.CHASE and _retreat_timer <= 0.0 and stun_time_left <= 0.0 and not _squeezing \
			and player != null and get_player_distance() < REAR_RANGE:
		# About to strike: front legs up.
		var close: float = 1.0 - clampf((get_player_distance() - catch_distance) / (REAR_RANGE - catch_distance), 0.0, 1.0)
		pitch -= 0.55 * close
		lift += 0.05 * close
	# Spotted him: a startled hop.
	pitch -= sin(_hop * PI) * 0.35
	lift += sin(_hop * PI) * 0.09
	# The strike itself: slams forward and down.
	pitch += sin(_pounce * PI) * 0.6
	var snap: float = minf(delta * 22.0, 1.0)
	model.rotation.x = lerpf(model.rotation.x, pitch, snap)
	model.rotation.z = lerpf(model.rotation.z, roll, snap)
	# Twitches are instant; everything else eases.
	model.rotation.y = PI + (yaw if speed <= 0.4 and stun_time_left <= 0.0 and not _squeezing else lerpf(model.rotation.y - PI, yaw, snap))
	model.position.y = lerpf(model.position.y, lift, snap)


# ----------------------------------------------------------------- taunts

## Its inspection firmware, reporting.
func taunt_lines() -> Dictionary:
	return {
		&"spotted": ["Fault located.", "Foreign object detected."],
		&"chase": ["Clearing obstruction.", "Do not resist inspection.", "Tracking. Tracking. Tracking."],
		&"lost": ["Signal lost. Rescanning.", "Re-routing through the walls."],
		&"hiding": ["I fit where you fit.", "Scanning crawl spaces.", "Your breathing is a fault."],
		&"roam": ["Inspection in progress.", "Checking the cables.", "Every gap. Every gap."],
		&"hit": ["Obstruction damaged."],
	}


## Leaps up at his face, front legs raised (it is close, so it rears).
func on_jumpscare() -> void:
	_hop = 1.0
