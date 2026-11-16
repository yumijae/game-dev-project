class_name BalbalAI
extends AswangBase
## The Balbal / Aswang nga Ayam. Patrols the 1F corridor and both stairwells.
##
## HUMAN_MIMIC - walks upright, knocks politely, jingles the guard's stolen
##               keys and calls through doors in a classmate's voice. Peeking
##               under the door shows bare muddy feet pointing backwards.
## BLACK_DOG   - Itom nga Ayam. Fast and low. Rears up to look through the wide
##               lab glass when Juan stands, and squeezes under any closed door
##               whose bottom gap is not blocked, in 3 seconds.

enum Form { HUMAN_MIMIC, BLACK_DOG }
enum State { PATROL, INVESTIGATE, AT_DOOR, CHASE, SEARCH, CHECK_HIDING, LUNGE_GLASS, RECOIL }
enum DoorPhase { MIMIC, HANDLE, SHOVE, SLIP_UNDER }

const WALK_SPEED: float = 2.3
const INVESTIGATE_SPEED: float = 2.9
const DOG_SPEED: float = 5.4
const HUMAN_EYE_HEIGHT: float = 1.55
const DOG_EYE_HEIGHT: float = 0.55
const LOSE_SIGHT_TIME: float = 0.6
const SEARCH_TIME: float = 5.0
const MIMIC_TIME: float = 4.5
const MIMIC_HEAR_RANGE: float = 9.0
const SHOVE_INTERVAL: float = 1.3
const SHOVE_FORCE: float = 34.0
const CHECK_HIDING_TIME: float = 2.5
const GLASS_LUNGE_RANGE: float = 7.0
const GLASS_WINDUP: float = 0.7
const RECOIL_TIME: float = 2.2
const KNOCK_NOISE: float = 6.0
## Metres covered by one full walking cycle (two steps) of the mimic.
const HUMAN_CYCLE: float = 1.5
## Where each leg sits in a gallop cycle: front-left, front-right, hind-left, hind-right.
const GALLOP_OFFSETS: Array[float] = [0.0, 0.7, PI + 0.4, PI + 1.1]

## 1F corridor, then up and down each stairwell. Stair points sit in the
## corridor just outside each stairwell opening.
const PATROL_ROUTE: Array[Vector3] = [
	Vector3(-6.0, 0.0, 0.0), Vector3(6.0, 0.0, 0.0),
	Vector3(10.5, 3.8, -0.6), Vector3(10.5, 7.6, -0.6), Vector3(10.5, 11.4, -0.6),
	Vector3(10.5, 0.0, -0.6), Vector3(0.0, 0.0, 0.3),
	Vector3(-10.5, 3.8, -0.6), Vector3(-10.5, 7.6, -0.6), Vector3(-10.5, 11.4, -0.6),
	Vector3(-10.5, 0.0, -0.6),
]

const MIMIC_LINES: Array[String] = [
	"Hey, open up. They left me behind.",
	"Juan? It's Mark. Come on, open the door.",
	"This is the guard. Please open the door, sir.",
	"Please... it's so cold out here. Come on.",
	"Juan, you left something in the lab. Open up.",
]

var form: Form = Form.HUMAN_MIMIC
var state: State = State.PATROL

var _patrol_index: int = 0
var _target: Vector3 = Vector3.ZERO
var _state_time: float = 0.0
var _time_since_seen: float = 999.0
var _last_known: Vector3 = Vector3.ZERO
var _trail_crumb: ScentBreadcrumb = null
var _suspect_spot: HidingSpot = null
var _glass: CorridorViewingGlass = null
var _telegraph: float = 0.0
var _windup: float = 0.0

# Door routine
var _door: InteractableDoor = null
var _door_phase: DoorPhase = DoorPhase.MIMIC
var _door_timer: float = 0.0
var _door_shoves: int = 0
var _door_is_hot: bool = false
var _resume_state: State = State.INVESTIGATE

var _human_visual: Node3D = null
var _dog_visual: Node3D = null
# Joints the animation turns. Dog legs are front-left, front-right, hind-left, hind-right.
var _h_body: Node3D = null
var _h_head: Node3D = null
var _h_legs: Array[AswangRig.Limb] = []
var _h_arms: Array[AswangRig.Limb] = []
var _h_arm_targets: Array[Vector3] = []
var _d_body: Node3D = null
var _d_ribs: MeshInstance3D = null
var _d_head: Node3D = null
var _d_jaw: Node3D = null
var _d_tail: Node3D = null
var _d_legs: Array[AswangRig.Limb] = []
var _d_phase: float = 0.0
var _d_look: Vector2 = Vector2.ZERO


func _init() -> void:
	aswang_id = &"balbal"
	display_name = "The Balbal"
	vision_range = 13.0
	hearing = 1.15
	sniff_radius = 11.0


func _build_visual() -> void:
	_build_human()
	_build_dog()
	_apply_form()


## The mimic: a night guard's shape, nearly right. The arms hang to the knees,
## the fingers are too long, the mouth is too wide, the head sits crooked -
## and the bare muddy feet point BACKWARDS (+Z is behind the creature).
func _build_human() -> void:
	var cloth := Color(0.07, 0.08, 0.13)
	var trousers := Color(0.045, 0.045, 0.055)
	var skin := Color(0.4, 0.33, 0.27)
	var mud := Color(0.2, 0.14, 0.09)
	var fabric: Dictionary = {"wet": 0.05, "veins": 0.0, "bump": 0.7, "breathe": 0.002}
	_human_visual = add_joint(visual, Vector3.ZERO, "Human")
	_h_body = add_joint(_human_visual, Vector3(0.0, 0.95, 0.0), "Body")

	var torso := AswangMesh.new()
	torso.tube([Vector3(0.0, -0.04, 0.0), Vector3(0.0, 0.14, 0.005), Vector3(0.0, 0.36, -0.01), Vector3(0.0, 0.5, 0.0),
		Vector3(0.0, 0.56, 0.0)],
		[Vector2(0.165, 0.11), Vector2(0.15, 0.1), Vector2(0.185, 0.115), Vector2(0.2, 0.1), Vector2(0.07, 0.07)],
		Vector3.BACK, 14)
	add_flesh(_h_body, torso, cloth, fabric)
	var belt := AswangMesh.new()
	belt.tube([Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.04, 0.0)], [Vector2(0.168, 0.113), Vector2(0.166, 0.112)], Vector3.BACK, 14, 1)
	add_flesh(_h_body, belt, Color(0.02, 0.018, 0.015), {"wet": 0.6, "veins": 0.0, "bump": 0.4, "breathe": 0.002})
	add_part(_h_body, box_mesh(Vector3(0.05, 0.065, 0.012)), Vector3(0.1, 0.38, -0.118), Color(0.8, 0.7, 0.3))

	for side: float in [-1.0, 1.0]:
		var leg: AswangRig.Limb = AswangRig.make_limb(_h_body, Vector3(side * 0.09, -0.02, 0.0), 0.44, 0.42,
			Vector3.FORWARD, Vector3(side * 0.09, -0.87, 0.0))
		_h_legs.append(leg)
		var thigh := AswangMesh.new()
		thigh.tube([Vector3.ZERO, Vector3(0.0, -0.44, 0.0)], [0.085, 0.064])
		add_flesh(leg.root, thigh, trousers, fabric)
		var shin := AswangMesh.new()
		shin.tube([Vector3.ZERO, Vector3(0.0, -0.42, 0.0)], [0.062, 0.048])
		add_flesh(leg.mid, shin, trousers, fabric)
		var foot := AswangMesh.new()
		foot.tube([Vector3(0.0, 0.01, -0.03), Vector3(0.0, -0.045, 0.09), Vector3(0.0, -0.062, 0.2)],
			[0.04, Vector2(0.048, 0.03), Vector2(0.052, 0.017)], Vector3.UP)
		for toe: float in [-0.034, -0.012, 0.012, 0.034]:
			foot.tube([Vector3(toe, -0.064, 0.19), Vector3(toe * 1.2, -0.068, 0.245)], [0.012, 0.009], Vector3.UP, 5, 1)
		add_flesh(leg.end, foot, mud, {"wet": 0.7, "bump": 1.6})

		var arm: AswangRig.Limb = AswangRig.make_limb(_h_body, Vector3(side * 0.225, 0.49, 0.0), 0.3, 0.29,
			Vector3(side * 0.3, 0.0, 1.0), Vector3(side * 0.25, -0.09, -0.03), false)
		_h_arms.append(arm)
		_h_arm_targets.append(arm.rest)
		var sleeve := AswangMesh.new()
		sleeve.tube([Vector3.ZERO, Vector3(0.0, -0.3, 0.0)], [0.056, 0.046])
		add_flesh(arm.root, sleeve, cloth, fabric)
		var cuff := AswangMesh.new()
		cuff.tube([Vector3.ZERO, Vector3(0.0, -0.27, 0.0)], [0.046, 0.039])
		add_flesh(arm.mid, cuff, cloth, fabric)
		var hand := AswangMesh.new()
		hand.tube([Vector3(0.0, 0.03, 0.0), Vector3(0.0, -0.19, -0.01), Vector3(0.0, -0.28, -0.012)],
			[0.03, Vector2(0.04, 0.02), Vector2(0.036, 0.013)], Vector3.BACK)
		for finger: int in 4:
			var x: float = (float(finger) - 1.5) * 0.019
			hand.tube([Vector3(x, -0.27, -0.012), Vector3(x * 1.05, -0.35, -0.028), Vector3(x * 1.08, -0.42, -0.02)],
				[0.009, 0.007, 0.004], Vector3.BACK, 5, 2)
		add_flesh(arm.end, hand, skin, {"bump": 1.4, "veins": 0.9})

	_h_head = add_joint(_h_body, Vector3(0.0, 0.58, 0.0), "Head")
	var head := AswangMesh.new()
	head.tube([Vector3(0.0, -0.05, 0.0), Vector3(0.0, 0.06, -0.01)], [0.05, 0.048])
	head.tube([Vector3(0.0, 0.03, -0.02), Vector3(0.0, 0.09, -0.025), Vector3(0.0, 0.17, -0.015), Vector3(0.0, 0.24, 0.0),
		Vector3(0.0, 0.275, 0.005)],
		[Vector2(0.05, 0.06), Vector2(0.072, 0.085), Vector2(0.082, 0.098), Vector2(0.078, 0.095), Vector2(0.05, 0.065)],
		Vector3.BACK, 14)
	head.tube([Vector3(0.0, 0.17, -0.1), Vector3(0.0, 0.128, -0.128)], [0.008, 0.014], Vector3.ZERO, 6, 2)
	add_flesh(_h_head, head, skin, {"wet": 0.25})
	var hair := AswangMesh.new()
	hair.tube([Vector3(0.0, 0.19, 0.035), Vector3(0.0, 0.265, 0.02), Vector3(0.0, 0.292, 0.01)],
		[Vector2(0.087, 0.088), Vector2(0.072, 0.08), Vector2(0.03, 0.04)], Vector3.BACK, 12)
	add_flesh(_h_head, hair, Color(0.02, 0.02, 0.025), {"veins": 0.0, "bump": 2.5, "wet": 0.5})
	# A smile that runs most of the way to the ears.
	var mouth := AswangMesh.new()
	mouth.tube([Vector3(-0.06, 0.09, -0.082), Vector3(-0.03, 0.074, -0.103), Vector3(0.0, 0.07, -0.108),
		Vector3(0.03, 0.074, -0.103), Vector3(0.06, 0.09, -0.082)], [0.004, 0.009, 0.011, 0.009, 0.004], Vector3.ZERO, 6, 3)
	add_flesh(_h_head, mouth, Color(0.03, 0.005, 0.005), {"wet": 1.0, "veins": 0.0})
	for side: float in [-1.0, 1.0]:
		add_eye(_h_head, Vector3(side * 0.034, 0.185, -0.1), 0.011, Color(1.0, 0.9, 0.6), 1.6)


## Itom nga Ayam: a starved black dog, every rib and vertebra showing, with
## its paws on backwards.
func _build_dog() -> void:
	var skin := Color(0.06, 0.055, 0.055)
	var bone := Color(0.72, 0.66, 0.52)
	var hide: Dictionary = {"wet": 0.55, "bump": 1.4}
	_dog_visual = add_joint(visual, Vector3.ZERO, "Dog")
	_d_body = add_joint(_dog_visual, Vector3.ZERO, "Body")

	var torso := AswangMesh.new()
	torso.tube([Vector3(0.0, 0.6, 0.5), Vector3(0.0, 0.66, 0.28), Vector3(0.0, 0.67, 0.0), Vector3(0.0, 0.63, -0.28),
		Vector3(0.0, 0.62, -0.42)],
		[Vector2(0.07, 0.08), Vector2(0.105, 0.12), Vector2(0.09, 0.1), Vector2(0.135, 0.17), Vector2(0.1, 0.13)],
		Vector3.UP, 14)
	_d_ribs = add_flesh(_d_body, torso, skin, {"wet": 0.55, "bump": 1.4, "gaunt": 0.8, "ridge_spacing": 0.055})
	var spine := AswangMesh.new()
	for i: int in 9:
		var z: float = 0.42 - float(i) * 0.095
		var top: float = 0.76 + 0.035 * clampf(-z / 0.28, 0.0, 1.0)
		spine.tube([Vector3(0.0, top - 0.03, z), Vector3(0.0, top + 0.002, z)], [0.022, 0.013], Vector3.BACK, 6, 2)
	for side: float in [-1.0, 1.0]:
		# Hip bones and shoulder blades pushing against the skin.
		spine.tube([Vector3(side * 0.06, 0.7, 0.36), Vector3(side * 0.085, 0.765, 0.3)], [0.03, 0.022], Vector3.ZERO, 6, 2)
		spine.tube([Vector3(side * 0.09, 0.66, -0.3), Vector3(side * 0.07, 0.805, -0.26)], [Vector2(0.03, 0.05), 0.02],
			Vector3.BACK, 6, 2)
	add_flesh(_d_body, spine, skin, hide)

	_d_tail = add_joint(_d_body, Vector3(0.0, 0.62, 0.5), "Tail")
	var tail := AswangMesh.new()
	tail.tube([Vector3.ZERO, Vector3(0.0, -0.08, 0.14), Vector3(0.0, -0.24, 0.24), Vector3(0.0, -0.38, 0.26)],
		[0.03, 0.022, 0.014, 0.006], Vector3.ZERO, 6)
	add_sway(add_flesh(_d_tail, tail, skin, hide), 0.45, 0.07, 70.0, 6.0)

	_d_head = add_joint(_d_body, Vector3(0.0, 0.68, -0.4), "Head")
	var head := AswangMesh.new()
	head.tube([Vector3(0.0, -0.03, 0.05), Vector3(0.0, 0.06, -0.1), Vector3(0.0, 0.1, -0.2)],
		[Vector2(0.085, 0.1), 0.07, 0.062], Vector3.UP)
	head.tube([Vector3(0.0, 0.11, -0.16), Vector3(0.0, 0.12, -0.26), Vector3(0.0, 0.092, -0.36), Vector3(0.0, 0.078, -0.46)],
		[Vector2(0.07, 0.065), Vector2(0.075, 0.068), Vector2(0.045, 0.04), Vector2(0.03, 0.026)], Vector3.UP, 12)
	for side: float in [-1.0, 1.0]:
		head.spike(Vector3(side * 0.055, 0.16, -0.2), Vector3(side * 0.085, 0.275, -0.15), 0.03)
	add_flesh(_d_head, head, skin, hide)
	add_part(_d_head, sphere_mesh(0.017), Vector3(0.0, 0.082, -0.478), Color(0.01, 0.01, 0.01))
	var teeth := AswangMesh.new()
	for side: float in [-1.0, 1.0]:
		for i: int in 5:
			var x: float = side * (0.036 - float(i) * 0.004)
			var z: float = -0.31 - float(i) * 0.03
			var length: float = 0.05 if i == 4 else 0.022 + 0.004 * float(i % 2)
			teeth.spike(Vector3(x, 0.066, z), Vector3(x, 0.066 - length, z - 0.004), 0.0065)
	add_flesh(_d_head, teeth, bone, {"wet": 0.9, "veins": 0.0, "bump": 0.3, "breathe": 0.0})
	for side: float in [-1.0, 1.0]:
		add_eye(_d_head, Vector3(side * 0.046, 0.135, -0.3), 0.014, Color(1.0, 0.1, 0.05), 4.0)

	_d_jaw = add_joint(_d_head, Vector3(0.0, 0.07, -0.22), "Jaw")
	var jaw := AswangMesh.new()
	jaw.tube([Vector3(0.0, -0.01, 0.0), Vector3(0.0, -0.025, -0.12), Vector3(0.0, -0.02, -0.225)],
		[Vector2(0.045, 0.022), Vector2(0.034, 0.016), Vector2(0.02, 0.012)], Vector3.UP)
	add_flesh(_d_jaw, jaw, skin, hide)
	var lower_teeth := AswangMesh.new()
	for side: float in [-1.0, 1.0]:
		for i: int in 4:
			var x: float = side * (0.029 - float(i) * 0.004)
			var z: float = -0.1 - float(i) * 0.032
			lower_teeth.spike(Vector3(x, -0.014, z), Vector3(x, 0.012 + (0.016 if i == 3 else 0.0), z), 0.006)
	add_flesh(_d_jaw, lower_teeth, bone, {"wet": 0.9, "veins": 0.0, "bump": 0.3, "breathe": 0.0})
	var tongue := AswangMesh.new()
	tongue.tube([Vector3(0.0, -0.004, -0.05), Vector3(0.0, -0.004, -0.2), Vector3(0.012, -0.045, -0.27)],
		[Vector2(0.02, 0.006), Vector2(0.018, 0.005), Vector2(0.012, 0.004)], Vector3.UP, 8)
	add_sway(add_flesh(_d_jaw, tongue, Color(0.4, 0.07, 0.09), {"wet": 1.0, "veins": 0.2}), 0.25, 0.03, 90.0, 8.0)

	# Front pair, then hind pair; left before right.
	for front: bool in [true, false]:
		for side: float in [-1.0, 1.0]:
			var at := Vector3(side * 0.11, 0.6, -0.3) if front else Vector3(side * 0.1, 0.6, 0.38)
			var leg: AswangRig.Limb = AswangRig.make_limb(_d_body, at, 0.29, 0.29, Vector3.BACK, at + Vector3(0.0, -0.555, 0.0))
			_d_legs.append(leg)
			var upper := AswangMesh.new()
			upper.tube([Vector3(0.0, 0.05, 0.0), Vector3(0.0, -0.29, 0.0)],
				[Vector2(0.05, 0.07) if front else Vector2(0.06, 0.095), 0.034 if front else 0.04], Vector3.BACK, 8)
			add_flesh(leg.root, upper, skin, hide)
			var lower := AswangMesh.new()
			lower.tube([Vector3.ZERO, Vector3(0.0, -0.29, 0.0)], [0.032 if front else 0.036, 0.024], Vector3.BACK, 8)
			add_flesh(leg.mid, lower, skin, hide)
			# Paws turned backwards.
			var paw := AswangMesh.new()
			paw.tube([Vector3(0.0, 0.0, -0.02), Vector3(0.0, -0.02, 0.06)],
				[Vector2(0.03, 0.022), Vector2(0.037, 0.014)], Vector3.UP, 8, 2)
			for claw: float in [-0.022, 0.0, 0.022]:
				paw.spike(Vector3(claw, -0.021, 0.07), Vector3(claw * 1.2, -0.033, 0.125), 0.008)
			add_flesh(leg.end, paw, skin, hide)


func _animate(delta: float) -> void:
	if form == Form.BLACK_DOG:
		_animate_dog(delta)
	else:
		_animate_human(delta)


## A walk with planted feet, weight shifting over each one - and arms that
## barely swing. People notice that before they know why.
func _animate_human(delta: float) -> void:
	var moving: float = clampf(anim_speed / 1.2, 0.0, 1.0)
	var phase: float = anim_distance / HUMAN_CYCLE * TAU
	var stride: float = HUMAN_CYCLE * 0.5 * moving
	_h_body.position = Vector3(-sin(phase) * 0.022 * moving,
		0.95 - 0.025 * moving + cos(phase * 2.0) * 0.014 * moving + sin(anim_time * 1.4) * 0.003, 0.0)
	_h_body.rotation = Vector3(-0.05 * moving, sin(phase) * 0.08 * moving, sin(phase) * 0.025 * moving - anim_turn * 0.03)
	var to_body: Transform3D = _h_body.transform.affine_inverse()
	for i: int in 2:
		var side: float = -1.0 if i == 0 else 1.0
		var offset: float = 0.0 if i == 0 else PI
		var step: Vector3 = AswangRig.step_offset(phase + offset, stride, 0.1 * moving)
		_h_legs[i].solve(to_body * (Vector3(side * 0.09, 0.08, 0.0) + step))
		var reach: Vector3 = _h_arms[i].rest + Vector3(0.0, 0.0, cos(phase + offset) * 0.04 * moving)
		if i == 1 and state == State.AT_DOOR and _door_phase == DoorPhase.MIMIC:
			# Knuckles on the door: three polite raps, a pause, again.
			var rap: float = maxf(sin(anim_time * 10.0), 0.0) if fmod(anim_time, 2.6) < 0.95 else 0.0
			reach = Vector3(0.14, 0.4, -0.4 - rap * 0.07)
		_h_arm_targets[i] = _h_arm_targets[i].lerp(reach, minf(delta * 7.0, 1.0))
		_h_arms[i].solve(_h_arm_targets[i])
	# The head hangs to one side, sweeps slowly, and now and then snaps over.
	var snap: bool = fmod(anim_time, 6.3) < 0.14
	_h_head.rotation.z = lerpf(_h_head.rotation.z, -0.55 if snap else 0.22, minf(delta * 22.0, 1.0))
	_h_head.rotation.y = sin(anim_time * 0.45) * 0.3 - _h_body.rotation.y


## Trots on diagonal pairs, then opens into a bounding gallop as it closes:
## the spine flexes, the hips and shoulders rise and fall over planted paws,
## and the head stays locked on Juan while the body moves under it.
func _animate_dog(delta: float) -> void:
	var moving: float = clampf(anim_speed / 0.8, 0.0, 1.0)
	var gallop: float = smoothstep(3.0, 4.6, anim_speed)
	var cycle: float = lerpf(0.9, 2.1, gallop)
	_d_phase += anim_speed * delta / cycle * TAU
	var stride: float = minf(cycle * 0.5, 0.62) * moving
	var lift: float = lerpf(0.07, 0.17, gallop) * moving
	var hunting: bool = state == State.CHASE or state == State.LUNGE_GLASS
	var lunge: float = anim_strike * anim_strike
	var bounce: float = lerpf(cos(_d_phase * 2.0) * 0.012, sin(_d_phase + 0.6) * 0.055, gallop) * moving
	var pitch: float = sin(_d_phase + 2.0) * 0.13 * gallop * moving
	_d_body.position = Vector3(0.0, bounce - 0.04 * gallop - 0.05 * lunge + sin(anim_time * 2.4) * 0.003, -0.22 * lunge)
	_d_body.rotation = Vector3(pitch - 0.2 * lunge, sin(_d_phase) * 0.06 * moving * (1.0 - gallop), -anim_turn * 0.05)
	# Panting shows in the ribs.
	_d_ribs.scale.x = 1.0 + sin(anim_time * (10.0 if hunting else 3.2)) * 0.022
	var to_body: Transform3D = _d_body.transform.affine_inverse()
	for i: int in 4:
		var front: bool = i < 2
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var trot: float = 0.0 if (i == 0 or i == 3) else PI
		var offset: float = lerpf(trot, GALLOP_OFFSETS[i], gallop)
		var rest: Vector3 = Vector3(side * 0.11, 0.045, -0.3) if front else Vector3(side * 0.1, 0.045, 0.4)
		var step: Vector3 = AswangRig.step_offset(_d_phase + offset, stride, lift)
		# A lifted paw hangs from the wrist.
		_d_legs[i].solve(to_body * (rest + step), step.y * 3.0)

	# Nose to the floor and casting about when it has lost him; eyes on him when it has not.
	var look := Vector2(-0.42 + sin(anim_time * 6.0) * 0.03, sin(anim_time * 1.1) * 0.45 * (1.0 - 0.6 * moving))
	if hunting and player != null and is_instance_valid(player):
		var local: Vector3 = to_local(player.get_head_position()) - Vector3(0.0, 0.8, -0.5)
		look = Vector2(clampf(atan2(local.y, Vector2(local.x, local.z).length()), -0.4, 0.7),
			clampf(atan2(-local.x, -local.z), -0.9, 0.9))
	_d_look = _d_look.lerp(look, minf(delta * 6.0, 1.0))
	_d_head.rotation = Vector3(_d_look.x - _d_body.rotation.x * 0.8, _d_look.y, -anim_turn * 0.06)
	var gape: float = 0.05 + 0.04 * maxf(sin(anim_time * 3.2), 0.0)
	if hunting:
		gape = 0.22 + 0.1 * sin(anim_time * 10.0)
	_d_jaw.rotation.x = -maxf(gape, sin(anim_strike * PI) * 0.75)
	_d_tail.rotation.x = lerpf(_d_tail.rotation.x, -0.9 if hunting else 0.15, minf(delta * 3.0, 1.0))
	_d_tail.rotation.y = sin(anim_time * 2.6) * 0.15


func _on_activated() -> void:
	set_form(Form.HUMAN_MIMIC)
	_enter(State.PATROL)


func get_feet_description() -> String:
	if form == Form.BLACK_DOG:
		return "A dog's claws. Black, wet with mud... and the prints point backwards. That is no dog."
	return "Feet. Bare, muddy. But backwards - the toes point behind it. That is not Mark."


func set_form(new_form: Form) -> void:
	if new_form == form:
		return
	form = new_form
	_apply_form()
	EventBus.balbal_form_changed.emit(form)


func _apply_form() -> void:
	var is_dog: bool = form == Form.BLACK_DOG
	if _human_visual != null:
		_human_visual.visible = not is_dog
		_dog_visual.visible = is_dog
	eye_height = DOG_EYE_HEIGHT if is_dog else HUMAN_EYE_HEIGHT
	if body_shape != null:
		var capsule := body_shape.shape as CapsuleShape3D
		capsule.height = 0.95 if is_dog else 1.7
		body_shape.position.y = capsule.height * 0.5


# ---------------------------------------------------------------- state logic

func _tick(delta: float) -> void:
	_state_time += delta
	_time_since_seen += delta
	var sees: bool = can_see_player()
	if sees:
		_time_since_seen = 0.0
		_last_known = player.global_position
		if state != State.CHASE and state != State.LUNGE_GLASS and state != State.RECOIL:
			EventBus.aswang_alerted.emit(aswang_id, _last_known)
			_begin_chase()
	elif state == State.CHASE and player != null and player.is_hidden and _time_since_seen < 1.2:
		# Watched him climb in.
		_begin_check_hiding(player.get_hiding_spot() as HidingSpot, 1.0)
	match state:
		State.PATROL:
			_tick_patrol(delta)
		State.INVESTIGATE:
			_tick_investigate(delta)
		State.AT_DOOR:
			_tick_door(delta)
		State.CHASE:
			_tick_chase(delta, sees)
		State.SEARCH:
			_tick_search(delta)
		State.CHECK_HIDING:
			_tick_check_hiding(delta)
		State.LUNGE_GLASS:
			_tick_lunge_glass(delta)
		State.RECOIL:
			ground_idle(delta)
			if _state_time >= RECOIL_TIME:
				_begin_chase()


func _enter(new_state: State) -> void:
	state = new_state
	_state_time = 0.0
	set_state(State.keys()[new_state])


func _tick_patrol(delta: float) -> void:
	if _follow_scent():
		return
	if nav_move_to(PATROL_ROUTE[_patrol_index], WALK_SPEED, delta):
		_patrol_index = (_patrol_index + 1) % PATROL_ROUTE.size()


func _tick_investigate(delta: float) -> void:
	var speed: float = minf(INVESTIGATE_SPEED * get_aggression(), DOG_SPEED)
	if _move_or_door(_target, speed, delta, false, State.INVESTIGATE):
		return
	if not _arrived(_target):
		return
	if _trail_crumb != null and is_instance_valid(_trail_crumb):
		var spot := _trail_crumb.hiding_spot as HidingSpot
		if spot != null and spot.is_occupied():
			_begin_check_hiding(spot, CHECK_HIDING_TIME)
			return
		var next: ScentBreadcrumb = ScentManager.get_following_breadcrumb(_trail_crumb.serial)
		if next != null:
			_set_trail(next)
			return
	_trail_crumb = null
	if _suspect_spot != null and is_instance_valid(_suspect_spot) and _suspect_spot.is_occupied():
		_begin_check_hiding(_suspect_spot, CHECK_HIDING_TIME)
		return
	_enter(State.SEARCH)


func _tick_chase(delta: float, sees: bool) -> void:
	set_form(Form.BLACK_DOG)
	if try_attack_player():
		return
	var speed: float = DOG_SPEED * minf(get_aggression(), 1.5)
	if sees and last_sight_glass != null and TimeManager.aggression_level >= 2 \
			and not last_sight_glass.is_shattered \
			and global_position.distance_to(last_sight_glass.global_position) <= GLASS_LUNGE_RANGE:
		_glass = last_sight_glass
		_enter(State.LUNGE_GLASS)
		return
	var goal: Vector3 = player.global_position if sees or _time_since_seen < LOSE_SIGHT_TIME else _last_known
	if _move_or_door(goal, speed, delta, true, State.CHASE):
		return
	if not sees and _time_since_seen >= LOSE_SIGHT_TIME and _arrived(_last_known):
		if not _follow_scent():
			_enter(State.SEARCH)


func _tick_search(delta: float) -> void:
	ground_idle(delta)
	rotation.y += delta * 1.4
	if _follow_scent():
		return
	if _state_time >= SEARCH_TIME:
		set_form(Form.HUMAN_MIMIC)
		_enter(State.PATROL)


func _tick_check_hiding(delta: float) -> void:
	if _suspect_spot == null or not is_instance_valid(_suspect_spot):
		_enter(State.SEARCH)
		return
	var stand: Vector3 = _suspect_spot.get_exit_position()
	if not _arrived(stand):
		if _move_or_door(stand, INVESTIGATE_SPEED, delta, true, State.CHECK_HIDING):
			return
		_state_time = 0.0
		return
	ground_idle(delta)
	face_point(_suspect_spot.global_position, delta)
	if _state_time < _telegraph:
		return
	if _suspect_spot.is_occupied() and player != null:
		attack_cooldown = 0.0
		SfxSynth.play_at(self, SfxSynth.thud(), _suspect_spot.global_position, 2.0)
		var fatal: bool = player.take_attack(self)
		_on_attack_landed(fatal)
	else:
		_suspect_spot = null
		_enter(State.SEARCH)


## Runs to the corridor side of the pane, gathers, and goes through the glass.
func _tick_lunge_glass(delta: float) -> void:
	if _glass == null or not is_instance_valid(_glass):
		_begin_chase()
		return
	var my_side: float = _glass.which_side(global_position)
	var launch: Vector3 = _glass.get_floor_point(my_side, 0.9)
	if not _arrived(launch) and _state_time < 4.0:
		nav_move_to(launch, DOG_SPEED, delta)
		_windup = 0.0
		return
	ground_idle(delta)
	face_point(_glass.global_position, delta)
	_windup += delta
	if _windup < GLASS_WINDUP:
		return
	_glass.shatter(-my_side)
	global_position = _glass.get_floor_point(-my_side, 1.3)
	velocity = Vector3.ZERO
	_glass = null
	_begin_chase()


# ----------------------------------------------------------------- transitions

func _begin_chase() -> void:
	_trail_crumb = null
	set_form(Form.BLACK_DOG)
	_enter(State.CHASE)


func _begin_investigate(point: Vector3) -> void:
	_target = point
	if state != State.AT_DOOR:
		_enter(State.INVESTIGATE)
	else:
		_resume_state = State.INVESTIGATE


func _begin_check_hiding(spot: HidingSpot, telegraph: float) -> void:
	if spot == null:
		_enter(State.SEARCH)
		return
	_suspect_spot = spot
	_telegraph = telegraph
	_enter(State.CHECK_HIDING)


## Picks up Juan's trail if one is within sniffing range.
func _follow_scent() -> bool:
	var crumb: ScentBreadcrumb = sniff_trail()
	if crumb == null:
		return false
	_set_trail(crumb)
	return true


func _set_trail(crumb: ScentBreadcrumb) -> void:
	_trail_crumb = crumb
	remember_crumb(crumb)
	_begin_investigate(crumb.global_position)


func _arrived(point: Vector3) -> bool:
	var flat := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	return flat.length() < 0.75 and absf(point.y - global_position.y) < 1.3


func _on_heard(origin: Vector3, noise_type: StringName, _audibility: float) -> void:
	if state == State.CHASE or state == State.LUNGE_GLASS or state == State.RECOIL or state == State.CHECK_HIDING:
		return
	_trail_crumb = null
	_suspect_spot = null
	if noise_type == &"heavy_breathing" or noise_type == &"gasp" or noise_type == &"pain_gasp":
		_suspect_spot = _find_hiding_spot_near(origin)
	EventBus.aswang_alerted.emit(aswang_id, origin)
	_begin_investigate(origin)


func _find_hiding_spot_near(point: Vector3) -> HidingSpot:
	for node: Node in get_tree().get_nodes_in_group(&"hiding_spots"):
		var spot := node as HidingSpot
		if spot != null and spot.is_occupied() and spot.get_hide_position().distance_to(point) < 1.5:
			return spot
	return null


func _on_attack_landed(fatal: bool) -> void:
	if not fatal:
		_enter(State.RECOIL)


func _on_blinded() -> void:
	# Sinamak breaks the chase outright.
	_time_since_seen = 999.0
	_trail_crumb = null
	_suspect_spot = null
	_door = null


func _on_recovered() -> void:
	super._on_recovered()
	set_form(Form.HUMAN_MIMIC)
	_enter(State.SEARCH)


# --------------------------------------------------------------- door routine

## Moves towards `goal`; if a closed door is in the way, starts the door
## routine and returns true.
func _move_or_door(goal: Vector3, speed: float, delta: float, hot: bool, resume: State) -> bool:
	nav_move_to(goal, speed, delta)
	var door: InteractableDoor = find_blocking_door()
	if door == null:
		return false
	_door = door
	_door_is_hot = hot
	_resume_state = resume
	_door_shoves = 0
	_door_timer = 0.0
	_door_phase = DoorPhase.HANDLE if hot else DoorPhase.MIMIC
	if _door_phase == DoorPhase.MIMIC:
		set_form(Form.HUMAN_MIMIC)
		_play_mimic()
	_enter(State.AT_DOOR)
	return true


func _tick_door(delta: float) -> void:
	ground_idle(delta)
	if _door == null or not is_instance_valid(_door) or _door.is_passable():
		_leave_door()
		return
	face_point(_door.get_center(), delta)
	_door_timer += delta
	match _door_phase:
		DoorPhase.MIMIC:
			if _door_timer >= MIMIC_TIME:
				_door_phase = DoorPhase.HANDLE
				_door_timer = 0.0
		DoorPhase.HANDLE:
			_tick_door_handle()
		DoorPhase.SHOVE:
			_tick_door_shove()
		DoorPhase.SLIP_UNDER:
			_tick_door_slip()


func _tick_door_handle() -> void:
	if not _door.can_aswang_open():
		# Locked, tied or blocked: no hands will open it. Go under, or through.
		set_form(Form.BLACK_DOG)
		_door_phase = DoorPhase.SLIP_UNDER if _door.can_slip_under() else DoorPhase.SHOVE
		_door_timer = 0.0
		return
	if _door_timer < _door.get_handle_delay():
		return
	if _door.handle_state == InteractableDoor.HandleState.CHAIR_WEDGED:
		_door_phase = DoorPhase.SHOVE
		_door_timer = SHOVE_INTERVAL
		return
	if _door.trigger_salt(self):
		_door = null
		return
	_door.set_open(true)
	_leave_door()


func _tick_door_shove() -> void:
	if _door_timer < SHOVE_INTERVAL:
		return
	_door_timer = 0.0
	_door_shoves += 1
	if _door.shove(SHOVE_FORCE * get_aggression()):
		if _door.trigger_salt(self):
			_door = null
			return
		_leave_door()
		return
	# A fully barricaded door only keeps it out while it is unsure Juan is inside.
	var patience: int = 2 + TimeManager.aggression_level + (3 if _door_is_hot else 0)
	if _door_shoves >= patience:
		_door = null
		set_form(Form.HUMAN_MIMIC)
		_enter(State.PATROL)


func _tick_door_slip() -> void:
	if not _door.can_slip_under():
		_door_phase = DoorPhase.SHOVE
		_door_timer = 0.0
		return
	if _door_timer < InteractableDoor.SLIP_UNDER_TIME:
		return
	if _door.trigger_salt(self):
		_door = null
		return
	var far_side: float = -_door.which_side(global_position)
	global_position = _door.get_side_position(far_side, 0.95)
	velocity = Vector3.ZERO
	_leave_door()


func _leave_door() -> void:
	_door = null
	if _resume_state == State.CHASE:
		_begin_chase()
	else:
		_enter(_resume_state)


## Polite knocking, the guard's keys, and a borrowed voice.
func _play_mimic() -> void:
	var at: Vector3 = _door.get_center() + Vector3.UP
	NoiseManager.emit_noise(at, KNOCK_NOISE, &"knock", self)
	for i: int in 3:
		_delayed_sfx(0.35 * float(i), SfxSynth.knock(), at, 0.0)
	_delayed_sfx(1.6, SfxSynth.keys_jingle(), at, -6.0)
	var line: String = MIMIC_LINES[randi() % MIMIC_LINES.size()]
	EventBus.balbal_mimic_line.emit(_door, line)
	if player != null and player.global_position.distance_to(at) <= MIMIC_HEAR_RANGE:
		_delayed_subtitle(2.0, line)


func _delayed_sfx(delay: float, stream: AudioStream, at: Vector3, volume_db: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if is_inside_tree() and is_threatening():
		SfxSynth.play_at(self, stream, at, volume_db, 1.0, 20.0)


func _delayed_subtitle(delay: float, line: String) -> void:
	await get_tree().create_timer(delay).timeout
	if is_inside_tree() and is_threatening():
		EventBus.ui_subtitle.emit(line, 4.0, &"voice")
