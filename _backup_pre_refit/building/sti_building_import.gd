@tool
extends EditorScenePostImport
## Post-import script for sti_college_kalibo_4floor_bim.glb.
##
## The GLB's "-colonly" helper meshes import with empty shapes, and most of the
## visible geometry (walls, glass, partitions, furniture) has no collision at all.
## This script rebuilds collision from the real geometry every time the file is
## (re)imported, so the building is fully solid and walkable:
##   * simple box meshes            -> BoxShape3D (cheap, solid)
##   * complex meshes (arched walls, slabs with stair holes) -> exact trimesh
##   * Col_* helper meshes (stair ramps, landings, outer walls) -> BoxShape3D
##   * individual stair steps       -> skipped (smooth ramps are used instead)
##   * decorations (signs, foliage, window frames, AC grilles) -> no collision
## Everything lands in a single StaticBody3D named "BuildingCollision".

## Materials that never get collision (purely decorative / covered by other parts).
const SKIP_MATERIALS := [
	"STI_Window_Frame_Dark",
	"STI_AC_Front_Grille",
	"STI_Tropical_Foliage",
	"STI_Canopy_365_Sign",
	"STI_Scholar_Banner",
	"STI_Main_Signboard",
	"STI_Blade_Sign",
	"STI_Heart_Red",
	"Godot_Collision_Preview",
]

## Model bugs: these bands were exported as solid plates/blocks. They are
## rebuilt as hollow bands. value = [band width, skip the edge facing inwards]
##  * Floor2_Yellow_Cornice: a solid 20x15 m plate that sealed the F2->F3 stairwell.
##  * Floor3_Balcony_Parapet: a solid 1.5 m block filling the F3 front rooms.
const BAND_FIXES := {
	"Floor2_Yellow_Cornice": [0.4, false],
	"Floor3_Balcony_Parapet": [0.2, true],
}

## Physics layers used by the game (see project.godot layer names).
const LAYER_WORLD := 1
const LAYER_DOORS := 8 # layer 4: doors & shutters (not baked into the nav mesh)

const DoorScript := preload("res://building/door.gd")
const ShutterScript := preload("res://building/rollup_shutter.gd")


func _post_import(scene: Node) -> Object:
	var body := StaticBody3D.new()
	body.name = "BuildingCollision"
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	scene.add_child(body)
	body.owner = scene

	var interactive := Node3D.new()
	interactive.name = "Interactive"
	scene.add_child(interactive)
	interactive.owner = scene

	var meshes: Array[Node] = scene.find_children("*", "MeshInstance3D", true, false)
	var fire_escape_steps: Array[Vector3] = []
	var to_free: Array[Node] = []
	var counts := {"box": 0, "trimesh": 0, "helper": 0, "skipped": 0, "doors": 0, "shutters": 0, "bands": 0}
	counts.moved_doorways = _clear_doorways(scene, meshes)

	# Door headers (the short partition piece above each doorway), used to
	# find where each door's frame is.
	var headers: Array[AABB] = []
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh and _material_name(mi) == "STI_Interior_Partition_Wall":
			var b := _xform_to_root(scene, mi) * mi.mesh.get_aabb()
			if b.size.y > 1.3 and b.size.y < 1.7 and max(b.size.x, b.size.z) < 1.2:
				headers.append(b)

	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _xform_to_root(scene, mi)
		var aabb := mi.mesh.get_aabb()

		if BAND_FIXES.has(String(mi.name)):
			var fix: Array = BAND_FIXES[String(mi.name)]
			_rebuild_band(scene, body, mi, xf, fix[0], fix[1])
			to_free.append(mi)
			counts.bands += 1
			continue
		if _material_name(mi) == "STI_Classroom_Door":
			if _build_door(scene, interactive, mi, xf, headers):
				to_free.append(mi)
				counts.doors += 1
				continue
		if String(mi.name).begins_with("F1_Commercial_Stall"):
			_build_shutter(scene, interactive, mi, xf)
			to_free.append(mi)
			counts.shutters += 1
			continue

		# --- Helper collision meshes from the GLB (named Col_*-colonly) ---
		if String(mi.name).begins_with("Col_"):
			to_free.append(mi)
			# Floors come from the real slab meshes (exact stair holes), so the
			# helper slab boxes are not needed.
			if String(mi.name).contains("_Slab"):
				continue
			# The ramps stop ~12 cm short of the floor-slab openings, leaving a
			# gap at the floor end (the end facing the front of the building,
			# away from the mid-flight landing).
			#  * bottom flight end: lengthen the ramp 30 cm (the extra part is
			#    buried in the floor, so it is seamless)
			#  * top flight end: add a flat bridge plate at floor level, so the
			#    ramp doesn't stick up above the floor
			if String(mi.name).contains("StairRamp"):
				var long_axis := aabb.size.max_axis_index()
				var thick_axis := aabb.size.min_axis_index()
				var width_axis := 3 - long_axis - thick_axis
				var sgn := 1.0 if xf.basis[long_axis].z > 0.0 else -1.0
				var front_local := aabb.get_center()
				front_local[long_axis] += sgn * aabb.size[long_axis] * 0.5
				var back_local := aabb.get_center()
				back_local[long_axis] -= sgn * aabb.size[long_axis] * 0.5
				var front_world := xf * front_local
				if front_world.y < (xf * back_local).y:
					if sgn < 0.0:
						aabb.position[long_axis] -= 0.3
					aabb.size[long_axis] += 0.3
				else:
					var top_y := front_world.y + absf(xf.basis[thick_axis].y) * aabb.size[thick_axis] * 0.5
					var width := (xf.basis[width_axis] * aabb.size[width_axis]).length()
					var size := Vector3(width, 0.1, 0.45)
					var center := Vector3(front_world.x, top_y - 0.05, front_world.z + 0.15)
					_add_box(body, Transform3D(Basis(), center), AABB(-size * 0.5, size), "Bridge_" + _clean(mi.name))
			_add_box(body, xf, aabb, "Helper_" + _clean(mi.name))
			counts.helper += 1
			continue

		var mat_name := _material_name(mi)
		var scaled := aabb.size * xf.basis.get_scale()

		if mat_name in SKIP_MATERIALS:
			counts.skipped += 1
			continue
		# Paper-thin planes (decals) and the 4 cm tile overlay on the ground slab.
		if min(scaled.x, min(scaled.y, scaled.z)) < 0.02 \
				or (mat_name == "STI_Interior_Ceramic_Tile" and scaled.y < 0.06):
			counts.skipped += 1
			continue
		# Individual stair steps: replaced by ramps for smooth movement.
		if _is_step(mi, scaled):
			if _has_ancestor_named(mi, "Fire_Escape"):
				fire_escape_steps.append(xf * aabb.get_center())
			counts.skipped += 1
			continue

		if _vertex_count(mi.mesh) <= 24:
			_add_box(body, xf, aabb, _clean(mi.name))
			counts.box += 1
		else:
			_add_trimesh(body, xf, mi.mesh, _clean(mi.name))
			counts.trimesh += 1

	if fire_escape_steps.size() >= 2:
		_add_step_ramp(body, fire_escape_steps, 1.3, "Ramp_Fire_Escape")

	# Remove the broken auto-generated helper bodies and the helper meshes.
	for n in to_free:
		n.get_parent().remove_child(n)
		n.free()
	var old := scene.find_child("Godot_Collision_Shapes", true, false)
	if old:
		old.get_parent().remove_child(old)
		old.free()

	print("[sti_building_import] %s" % counts)
	return scene


## Model bug: some doorways were placed right on a structural column, leaving
## ~25 cm on each side. Slide those doorways along their wall until the column
## is hidden inside the wall, resizing the wall pieces and moving the header.
## Returns how many doorways were moved.
func _clear_doorways(scene: Node, meshes: Array[Node]) -> int:
	var columns: Array[AABB] = []
	var parts: Array[MeshInstance3D] = []
	for node in meshes:
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		if String(mi.name).begins_with("RC_Column"):
			columns.append(_xform_to_root(scene, mi) * mi.mesh.get_aabb())
		elif _material_name(mi) == "STI_Interior_Partition_Wall":
			parts.append(mi)

	var moved := 0
	for header in parts:
		var hb := _xform_to_root(scene, header) * header.mesh.get_aabb()
		if not (hb.size.y > 1.3 and hb.size.y < 1.7 and max(hb.size.x, hb.size.z) < 1.2):
			continue
		var ax := 0 if hb.size.x > hb.size.z else 2 # wall direction (x or z)
		var perp := 2 - ax
		var g0: float = hb.position[ax]
		var g1: float = hb.end[ax]
		var col := AABB()
		var hit := false
		for c in columns:
			if c.position[perp] < hb.end[perp] and c.end[perp] > hb.position[perp] \
					and c.position[ax] < g1 and c.end[ax] > g0 \
					and c.position.y < hb.position.y and c.end.y > hb.position.y:
				col = c
				hit = true
				break
		if not hit:
			continue
		# Wall pieces on the same line that end at either side of the gap.
		var left: MeshInstance3D = null
		var right: MeshInstance3D = null
		for p in parts:
			if p == header or p.get_parent() != header.get_parent():
				continue
			var pb := _xform_to_root(scene, p) * p.mesh.get_aabb()
			if pb.size.y < 3.0 or absf(pb.get_center()[perp] - hb.get_center()[perp]) > 0.05:
				continue
			if absf(pb.end[ax] - g0) < 0.05:
				left = p
			elif absf(pb.position[ax] - g1) < 0.05:
				right = p
		if left == null or right == null:
			continue
		var lb := _xform_to_root(scene, left) * left.mesh.get_aabb()
		var rb := _xform_to_root(scene, right) * right.mesh.get_aabb()
		var gap := g1 - g0
		var margin := 0.12
		# Candidate gaps just past either side of the column; keep >= 0.4 m of wall.
		var options := []
		var pos_start: float = col.end[ax] + margin
		if pos_start + gap <= rb.end[ax] - 0.4:
			options.append(pos_start)
		var neg_start: float = col.position[ax] - margin - gap
		if neg_start >= lb.position[ax] + 0.4:
			options.append(neg_start)
		if options.is_empty():
			continue
		options.sort_custom(func(a, b): return absf(a - g0) < absf(b - g0))
		var n0: float = options[0]
		var n1: float = n0 + gap
		var new_l := lb
		new_l.size[ax] = n0 - lb.position[ax]
		var new_r := rb
		new_r.position[ax] = n1
		new_r.size[ax] = rb.end[ax] - n1
		var new_h := hb
		new_h.position[ax] = n0
		_reshape_box(scene, left, new_l)
		_reshape_box(scene, right, new_r)
		_reshape_box(scene, header, new_h)
		# Move the door leaf mesh along with its opening (keeps hinge/swing side).
		for sib in header.get_parent().get_children():
			if sib is MeshInstance3D and _material_name(sib) == "STI_Classroom_Door":
				var shift := Vector3.ZERO
				shift[ax] = n0 - g0
				sib.transform.origin += _parent_basis_inv(scene, sib) * shift
		moved += 1
	return moved


## Replaces a box mesh with a BoxMesh filling `world_box` (root space).
func _reshape_box(scene: Node, mi: MeshInstance3D, world_box: AABB) -> void:
	var box := BoxMesh.new()
	box.size = world_box.size
	box.material = mi.get_active_material(0)
	var parent_xf := _xform_to_root(scene, mi) * mi.transform.affine_inverse()
	mi.mesh = box
	mi.transform = parent_xf.affine_inverse() * Transform3D(Basis(), world_box.get_center())


func _parent_basis_inv(scene: Node, n: Node3D) -> Basis:
	return (_xform_to_root(scene, n) * n.transform.affine_inverse()).basis.inverse()


## Replaces a solid extruded plate with a hollow band that follows its outline.
func _rebuild_band(scene: Node, body: StaticBody3D, mi: MeshInstance3D, xf: Transform3D, width: float, skip_inner_edge: bool) -> void:
	var pts := PackedVector2Array()
	var y0 := INF
	var y1 := -INF
	for f in mi.mesh.get_faces():
		var w := xf * f
		y0 = min(y0, w.y)
		y1 = max(y1, w.y)
		pts.append(Vector2(w.x, w.z))
	var hull := Geometry2D.convex_hull(pts) # closed loop (last == first)
	var min_z := INF
	for p in hull:
		min_z = min(min_z, p.y)
	var mat := mi.get_active_material(0)
	var holder := Node3D.new()
	holder.name = String(mi.name) + "_Band"
	scene.add_child(holder)
	holder.owner = scene
	var h := y1 - y0
	for i in hull.size() - 1:
		var a := hull[i]
		var b := hull[i + 1]
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		if skip_inner_edge and absf(a.y - min_z) < 0.01 and absf(b.y - min_z) < 0.01:
			continue
		var d := (b - a) / length
		var inward := Vector2(-d.y, d.x)
		if not Geometry2D.is_point_in_polygon((a + b) * 0.5 + inward * 0.05, hull):
			inward = -inward
		var c2 := (a + b) * 0.5 + inward * width * 0.5
		var xdir := Vector3(d.x, 0, d.y)
		var basis := Basis(xdir, Vector3.UP, xdir.cross(Vector3.UP))
		var center := Vector3(c2.x, (y0 + y1) * 0.5, c2.y)
		var box := BoxMesh.new()
		box.size = Vector3(length, h, width)
		box.material = mat
		var seg := MeshInstance3D.new()
		seg.name = "Segment%d" % i
		seg.mesh = box
		seg.transform = Transform3D(basis, center)
		holder.add_child(seg)
		seg.owner = scene
		_add_box(body, Transform3D(basis, center), AABB(-box.size * 0.5, box.size), "%s_%d" % [holder.name, i])


## Turns a static (modelled half-open) door into a hinged, interactive door.
func _build_door(scene: Node, parent: Node3D, mi: MeshInstance3D, xf: Transform3D, headers: Array[AABB]) -> bool:
	var aabb := mi.mesh.get_aabb()
	var world := xf * aabb
	var dc := world.get_center()
	var header := AABB()
	var best := INF
	for hb in headers:
		var d := Vector2(hb.get_center().x - dc.x, hb.get_center().z - dc.z).length()
		if d < best and absf(hb.position.y - world.end.y) < 0.4:
			best = d
			header = hb
	if best > 1.5:
		return false
	var along_x := header.size.x > header.size.z
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	var c := header.get_center()
	c.y = world.position.y
	var gap: float = header.size.x if along_x else header.size.z
	# Hinge on the jamb nearest to where the modelled door stands.
	var jamb_a := c - axis * gap * 0.5
	var jamb_b := c + axis * gap * 0.5
	var hinge_side := jamb_a if Vector2(jamb_a.x - dc.x, jamb_a.z - dc.z).length() < Vector2(jamb_b.x - dc.x, jamb_b.z - dc.z).length() else jamb_b
	var d := (c - hinge_side).normalized()

	# Leaf dimensions from the mesh (largest horizontal = width, smallest = thickness).
	var scale := xf.basis.get_scale()
	var dims := aabb.size * scale
	var height_axis := 1
	var hz := [0, 2]
	var w_axis: int = hz[0] if dims[hz[0]] >= dims[hz[1]] else hz[1]
	var t_axis: int = hz[1] if w_axis == hz[0] else hz[0]
	var w: float = dims[w_axis]
	var h: float = dims[height_axis]
	var t: float = dims[t_axis]
	var hinge := c - d * w * 0.5

	var door := Node3D.new()
	door.name = "Door_" + String(mi.get_parent().name)
	door.set_script(DoorScript)
	var closed_yaw := atan2(-d.z, d.x)
	# Open towards the side the modelled door swung to.
	var normal := Vector3(-d.z, 0, d.x)
	var side := signf((dc - c).dot(normal))
	if side == 0.0:
		side = 1.0
	door.set("closed_yaw", closed_yaw)
	door.set("open_yaw", closed_yaw - side * PI * 0.5)
	door.transform = Transform3D(Basis(Vector3.UP, closed_yaw), hinge)
	parent.add_child(door)
	door.owner = scene

	var leaf := AnimatableBody3D.new()
	leaf.name = "Leaf"
	leaf.collision_layer = LAYER_DOORS
	leaf.collision_mask = 0
	leaf.sync_to_physics = false # follow the hinge node when it rotates
	door.add_child(leaf)
	leaf.owner = scene
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, max(t, 0.05))
	cs.shape = shape
	cs.position = Vector3(w * 0.5, h * 0.5, 0)
	leaf.add_child(cs)
	cs.owner = scene

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mi.mesh
	for s in mi.get_surface_override_material_count():
		mesh_node.set_surface_override_material(s, mi.get_surface_override_material(s))
	var cols := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	cols[w_axis] = Vector3.RIGHT * scale[w_axis]
	cols[height_axis] = Vector3.UP * scale[height_axis]
	cols[t_axis] = Vector3.BACK * scale[t_axis]
	var mb := Basis(cols[0], cols[1], cols[2])
	if mb.determinant() < 0:
		cols[t_axis] = -cols[t_axis]
		mb = Basis(cols[0], cols[1], cols[2])
	mesh_node.transform = Transform3D(mb, Vector3(w * 0.5, h * 0.5, 0) - mb * aabb.get_center())
	leaf.add_child(mesh_node)
	mesh_node.owner = scene
	return true


## Turns a roll-up shutter into one that can be opened (rolled up).
func _build_shutter(scene: Node, parent: Node3D, mi: MeshInstance3D, xf: Transform3D) -> void:
	var world := xf * mi.mesh.get_aabb()
	var top := Vector3(world.get_center().x, world.end.y, world.get_center().z)
	var shutter := Node3D.new()
	shutter.name = "Shutter_" + String(mi.name).replace("F1_Commercial_", "")
	shutter.set_script(ShutterScript)
	shutter.position = top
	parent.add_child(shutter)
	shutter.owner = scene

	var body := AnimatableBody3D.new()
	body.name = "Body"
	body.collision_layer = LAYER_DOORS
	body.collision_mask = 0
	body.sync_to_physics = false
	shutter.add_child(body)
	body.owner = scene
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = world.size
	cs.shape = shape
	cs.position = Vector3(0, -world.size.y * 0.5, 0)
	body.add_child(cs)
	cs.owner = scene

	var roll := Node3D.new()
	roll.name = "Roll" # scaled on Y to roll the shutter up
	body.add_child(roll)
	roll.owner = scene
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = mi.mesh
	mesh_node.transform = Transform3D(xf.basis, xf.origin - top)
	roll.add_child(mesh_node)
	mesh_node.owner = scene


func _add_box(body: StaticBody3D, xf: Transform3D, aabb: AABB, label: String) -> void:
	var scale := xf.basis.get_scale()
	var shape := BoxShape3D.new()
	shape.size = (aabb.size * scale).max(Vector3.ONE * 0.02)
	var cs := CollisionShape3D.new()
	cs.name = label
	cs.shape = shape
	cs.transform = Transform3D(xf.basis.orthonormalized(), xf * aabb.get_center())
	body.add_child(cs)
	cs.owner = body.owner


func _add_trimesh(body: StaticBody3D, xf: Transform3D, mesh: Mesh, label: String) -> void:
	var faces := mesh.get_faces()
	for i in faces.size():
		faces[i] = xf * faces[i]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.name = label
	cs.shape = shape
	body.add_child(cs)
	cs.owner = body.owner


## Builds one smooth ramp running through the centres of a flight of steps.
func _add_step_ramp(body: StaticBody3D, steps: Array[Vector3], width: float, label: String) -> void:
	steps.sort_custom(func(a, b): return a.y < b.y)
	var lo := steps[0]
	var hi := steps[steps.size() - 1]
	var run := hi - lo
	var step_len := run.length() / float(steps.size() - 1)
	var dir := run.normalized()
	# Bottom end continues one step into the ground (buried, seamless); the top
	# end stops exactly at the last tread so it is flush with the landing.
	var a := lo - dir * step_len
	var b := hi
	var length := a.distance_to(b)
	var thickness := 0.12
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	var basis := Basis(side, up, -dir)
	# Step centres sit 5 cm below the tread surface.
	var center := (a + b) * 0.5 + Vector3.UP * 0.05 - up * (thickness * 0.5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thickness, length)
	var cs := CollisionShape3D.new()
	cs.name = label
	cs.shape = shape
	cs.transform = Transform3D(basis, center)
	body.add_child(cs)
	cs.owner = body.owner


func _is_step(mi: MeshInstance3D, scaled: Vector3) -> bool:
	if not (_has_ancestor_named(mi, "Stairwell") or _has_ancestor_named(mi, "Fire_Escape")):
		return false
	var flat := Vector2(scaled.x, scaled.z)
	return scaled.y <= 0.16 and max(flat.x, flat.y) <= 1.6 and min(flat.x, flat.y) <= 0.35


func _has_ancestor_named(n: Node, part: String) -> bool:
	var p := n.get_parent()
	while p:
		if String(p.name).contains(part):
			return true
		p = p.get_parent()
	return false


func _xform_to_root(root: Node, n: Node3D) -> Transform3D:
	var t := n.transform
	var p := n.get_parent()
	while p and p != root:
		if p is Node3D:
			t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


func _material_name(mi: MeshInstance3D) -> String:
	var m: Material = mi.get_surface_override_material(0)
	if m == null and mi.mesh.get_surface_count() > 0:
		m = mi.mesh.surface_get_material(0)
	return m.resource_name if m else ""


func _vertex_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
	return n


func _clean(n: StringName) -> String:
	return String(n).replace("-colonly", "")
