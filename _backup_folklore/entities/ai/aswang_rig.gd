class_name AswangRig
extends RefCounted
## Animation tools shared by the Aswang.
##
##   Limb   - a two-bone limb (hip-knee-ankle, shoulder-elbow-wrist) posed by
##            inverse kinematics: say where the foot or hand should be and the
##            knee or elbow bends to put it there.
##   Spring - a damped spring, for anything that should lag and overshoot.
##   step_offset() - where a foot is at a given point in its stride: planted
##            and carried back under the body, then lifted and swung forward.


class Limb:
	## Hip or shoulder. Its parent is the space targets are given in.
	var root: Node3D = null
	## Knee or elbow.
	var mid: Node3D = null
	## Ankle or wrist; feet and hands hang from it.
	var end: Node3D = null
	var upper: float = 0.4
	var lower: float = 0.4
	## The way the knee or elbow points, in the space of the root's parent.
	var pole: Vector3 = Vector3.FORWARD
	## Where the end sits at rest, in the space of the root's parent.
	var rest: Vector3 = Vector3.ZERO
	## Feet stay level with the body; hands follow the forearm.
	var level_end: bool = true

	## Bends the limb so its end reaches `target` (in the root's parent space).
	## `end_pitch` tips a level foot toe-down (negative) or toe-up.
	func solve(target: Vector3, end_pitch: float = 0.0) -> void:
		var to_target: Vector3 = target - root.position
		var reach: float = clampf(to_target.length(), absf(upper - lower) + 0.01, upper + lower - 0.002)
		var direction: Vector3 = to_target.normalized() if to_target.length() > 0.0001 else Vector3.DOWN
		var bend: Vector3 = pole - direction * pole.dot(direction)
		if bend.length() < 0.001:
			bend = Vector3.FORWARD - direction * Vector3.FORWARD.dot(direction)
		bend = bend.normalized()
		var cos_root: float = clampf((upper * upper + reach * reach - lower * lower) / (2.0 * upper * reach), -1.0, 1.0)
		var upper_dir: Vector3 = direction * cos_root + bend * sqrt(1.0 - cos_root * cos_root)
		var lower_dir: Vector3 = (direction * reach - upper_dir * upper).normalized()
		# Keep each bone's own X axis on the same side so the mesh never flips.
		var hinge: Vector3 = direction.cross(bend).normalized()
		if hinge.x < 0.0:
			hinge = -hinge
		var upper_basis := Basis(hinge, -upper_dir, hinge.cross(-upper_dir))
		var lower_basis := Basis(hinge, -lower_dir, hinge.cross(-lower_dir))
		root.basis = upper_basis
		mid.basis = upper_basis.inverse() * lower_basis
		if level_end:
			end.basis = lower_basis.inverse() * Basis(Vector3.RIGHT, end_pitch)
		else:
			end.basis = Basis.IDENTITY


class Spring:
	var value: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO

	func step(target: Vector3, stiffness: float, damping: float, delta: float) -> Vector3:
		var dt: float = minf(delta, 1.0 / 30.0)
		velocity += ((target - value) * stiffness - velocity * damping) * dt
		value += velocity * dt
		return value


## Builds the three joints of a limb under `parent`. Body parts are added by
## the caller: upper segment under root, lower under mid, foot/hand under end,
## each modelled hanging straight down (-Y) from its joint.
static func make_limb(parent: Node3D, at: Vector3, upper: float, lower: float, pole: Vector3, rest: Vector3,
		level_end: bool = true) -> Limb:
	var limb := Limb.new()
	limb.upper = upper
	limb.lower = lower
	limb.pole = pole.normalized()
	limb.rest = rest
	limb.level_end = level_end
	limb.root = Node3D.new()
	limb.root.name = "Limb"
	limb.root.position = at
	parent.add_child(limb.root)
	limb.mid = Node3D.new()
	limb.mid.name = "Mid"
	limb.mid.position = Vector3(0.0, -upper, 0.0)
	limb.root.add_child(limb.mid)
	limb.end = Node3D.new()
	limb.end.name = "End"
	limb.end.position = Vector3(0.0, -lower, 0.0)
	limb.mid.add_child(limb.end)
	limb.solve(rest)
	return limb


## Offset of a foot from its rest spot, `phase` radians through a stride.
## First half: planted, carried from the front of the stride to the back at
## the speed the body moves forward, so it does not slide. Second half: lifted
## and swung forward again. Forward is -Z.
static func step_offset(phase: float, stride: float, lift: float) -> Vector3:
	var p: float = fposmod(phase, TAU) / TAU
	if p < 0.5:
		return Vector3(0.0, 0.0, lerpf(-stride * 0.5, stride * 0.5, p * 2.0))
	var s: float = (p - 0.5) * 2.0
	var eased: float = s * s * (3.0 - 2.0 * s)
	return Vector3(0.0, sin(s * PI) * lift, lerpf(stride * 0.5, -stride * 0.5, eased))
