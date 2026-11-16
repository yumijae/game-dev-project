class_name RobotModels
extends RefCounted
## Builds the visual body of each Expo robot from its downloaded model: right
## size, standing on y = 0, facing +Z. The AI scripts (one per robot) parent
## this under their CharacterBody3D. Model credits: CREDITS.md.
##
##   POSE       mannequin, arms lowered from the model's T-pose
##   CONCIERGE  wheeled display robot with a screen face
##   SCUTTLE    six-legged spider bot
##   PROTOTYPE  battered dark robot frame with exposed wiring (idle sway only;
##              PrototypeAI walks it procedurally)

const SPECS: Dictionary = {
	&"pose": {"path": "res://models/robots/pose/pose.glb", "height": 1.78, "yaw": 0.0},
	&"concierge": {"path": "res://models/robots/concierge/concierge.glb", "height": 1.25, "yaw": 0.0},
	&"scuttle": {"path": "res://models/robots/scuttle/scuttle.glb", "height": 0.42, "yaw": 180.0},
	&"prototype": {"path": "res://models/robots/prototype/prototype.glb", "height": 2.15, "yaw": 0.0},
}


## A Node3D holding the robot's model, `kind` one of SPECS' keys.
static func make(kind: StringName) -> Node3D:
	var spec: Dictionary = SPECS[kind]
	var holder := Node3D.new()
	holder.name = "Model"
	var model: Node3D = (load(spec["path"]) as PackedScene).instantiate()
	holder.add_child(model)
	if kind == &"pose":
		# Posing only sticks once the skeleton is in the scene tree.
		model.ready.connect(_lower_arms.bind(model), CONNECT_ONE_SHOT)
		model.tree_entered.connect(func() -> void: _lower_arms.call_deferred(model), CONNECT_ONE_SHOT)
	var anim := _animation_player(model)
	if anim != null and anim.has_animation(&"IDLE"):
		anim.play(&"IDLE")
		anim.advance(0.0)
	# Fit: scale to the target height, feet on the floor, centred. Rigged
	# models are measured from their posed bones (a skinned mesh's AABB does
	# not follow the animation); the head reaches ~8 % above the top bone.
	var box := _fit_bounds(model, Transform3D())
	var s: float = float(spec["height"]) / maxf(box.size.y, 0.001)
	model.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(spec["yaw"])).scaled(Vector3.ONE * s), Vector3.ZERO)
	box = _fit_bounds(model, model.transform)
	model.position -= Vector3(box.get_center().x, box.position.y, box.get_center().z)
	return holder


static func animation_player(holder: Node3D) -> AnimationPlayer:
	return _animation_player(holder)


static func _animation_player(n: Node) -> AnimationPlayer:
	var found := n.find_children("*", "AnimationPlayer", true, false)
	return found[0] as AnimationPlayer if found.size() > 0 else null


## The mannequin ships in a T-pose; drop its arms to its sides. Each upper arm
## is turned (in its parent's frame) until its forearm hangs 75 degrees below
## the shoulder line, whatever axes the rig happens to use.
static func _lower_arms(model: Node) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var sk: Skeleton3D = skels[0]
	sk.force_update_all_bone_transforms()
	for arm: String in ["LeftArm_", "RightArm_"]:
		for i in sk.get_bone_count():
			if not sk.get_bone_name(i).begins_with(arm):
				continue
			var kids := sk.get_bone_children(i)
			if kids.is_empty():
				continue
			var parent_basis: Basis = sk.get_bone_global_pose(sk.get_bone_parent(i)).basis.orthonormalized()
			var along: Vector3 = (sk.get_bone_global_pose(kids[0]).origin - sk.get_bone_global_pose(i).origin).normalized()
			var down: Vector3 = (Vector3(along.x, 0.0, along.z).normalized() * cos(deg_to_rad(75.0)) + Vector3.DOWN * sin(deg_to_rad(75.0))).normalized()
			# The same turn expressed in the parent bone's space.
			var local_from: Vector3 = (parent_basis.inverse() * along).normalized()
			var local_to: Vector3 = (parent_basis.inverse() * down).normalized()
			var turn := Quaternion(local_from, local_to)
			sk.set_bone_pose_rotation(i, turn * sk.get_bone_pose_rotation(i))
	sk.force_update_all_bone_transforms()


static func _fit_bounds(n: Node, xf: Transform3D) -> AABB:
	var skels := n.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return _bounds(n, xf)
	var sk: Skeleton3D = skels[0]
	var to_root := xf * _relative(sk, n)
	var out := AABB(to_root * sk.get_bone_global_pose(0).origin, Vector3.ZERO)
	for i in sk.get_bone_count():
		out = out.expand(to_root * sk.get_bone_global_pose(i).origin)
	out.size.y *= 1.08
	return out


static func _bounds(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var t := xf * _relative(m, n)
		var b: AABB = t * m.mesh.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


static func _relative(node: Node3D, root: Node) -> Transform3D:
	var t := Transform3D()
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
