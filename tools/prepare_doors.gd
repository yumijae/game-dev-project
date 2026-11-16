extends SceneTree
## Bakes the two doors of the Sketchfab "Interior Wood Doors Pack 1" into the
## meshes the school's doors use:
##
##   door_<style>_frame.res  Frame + architraves. Origin at the middle of the
##                           doorway on the floor; X along the wall, Z through
##                           it, normalised to 1 m deep (scale the node's Z to
##                           the wall thickness).
##   door_<style>_leaf.res   The leaf, in InteractableDoor "Leaf" space: X from
##                           the hinge (0) to the latch edge (0.94 m), Y up from
##                           the floor with the 9 cm crawl gap underneath, Z
##                           through the leaf (5 cm thick). The model's own
##                           handles are removed: DoorDressing adds the lever,
##                           keyhole, thumb-turn and hinges the game uses.
##
##   godot --headless --path . --script res://tools/prepare_doors.gd
##
## Model: "Interior Wood Doors Pack 1" by Hawtor Studio, CC BY 4.0 (CREDITS.md).

const SRC := "res://models/sketchfab/doors/doors.glb"
const OUT_DIR := "res://models/sketchfab/doors/"
const LEAF_WIDTH := 0.94      # InteractableDoor door_width for a 1.0 m opening
const LEAF_TOP := 2.1
const GAP := 0.09             # InteractableDoor.GAP_HEIGHT
const LEAF_THICKNESS := 0.045
## style -> [frame node, leaf node]. In the pack D2 is the warm lacquered
## mahogany and D1 the weathered grey-brown oak.
const STYLES := {
	"wood": ["D2-Frame_D2_0", "D2-Door_D2_0"],
	"grey": ["D1-Frame_D1_0", "D1-Door_D1_0"],
}


func _initialize() -> void:
	var scene: Node = load(SRC).instantiate()
	for style in STYLES:
		var frame_mi: MeshInstance3D = scene.find_child(STYLES[style][0], true, false)
		var leaf_mi: MeshInstance3D = scene.find_child(STYLES[style][1], true, false)
		var fxf := _global(frame_mi)
		var lxf := _global(leaf_mi)
		var fbox := fxf * frame_mi.mesh.get_aabb()
		var lbox := lxf * leaf_mi.mesh.get_aabb()
		# Source axes: height Y, width Z (hinge at the leaf's low Z), depth X.
		var s_w: float = LEAF_WIDTH / lbox.size.z
		var s_h: float = LEAF_TOP / lbox.size.y
		var frame_cz: float = fbox.get_center().z
		var frame_cx: float = fbox.get_center().x
		# Frame: (x, y, z) -> ((z - cz) * s_w, y * s_h, -(x - cx) / depth)
		var fm := Basis(Vector3(0, 0, -1.0 / fbox.size.x), Vector3(0, s_h, 0), Vector3(s_w, 0, 0))
		var frame_place := Transform3D(fm, -(fm * Vector3(frame_cx, 0, frame_cz)))
		var frame := _bake(frame_mi, fxf, frame_place, func(_c: Vector3, _b: AABB) -> bool: return true)
		# Leaf slab: the central 80 % of its depth (the handles stick out).
		var slab := _slab_range(leaf_mi, lxf)
		var slab_cx: float = (slab.x + slab.y) * 0.5
		var s_t: float = LEAF_THICKNESS / (slab.y - slab.x)
		var s_ly: float = (LEAF_TOP - GAP) / lbox.size.y
		var lm := Basis(Vector3(0, 0, -s_t), Vector3(0, s_ly, 0), Vector3(s_w, 0, 0))
		var leaf_place := Transform3D(lm, Vector3(0, GAP, 0) - lm * Vector3(slab_cx, lbox.position.y, lbox.position.z))
		# Keep only pieces whose centre lies inside the slab: drops the levers.
		var keep := func(centre: Vector3, _b: AABB) -> bool:
			return centre.x > slab.x + 0.01 and centre.x < slab.y - 0.01
		var leaf := _bake(leaf_mi, lxf, leaf_place, keep)
		ResourceSaver.save(frame, OUT_DIR + "door_%s_frame.res" % style)
		ResourceSaver.save(leaf, OUT_DIR + "door_%s_leaf.res" % style)
		print("[prepare_doors] %s: frame %s, leaf %s" % [style, str(frame.get_aabb()), str(leaf.get_aabb())])
	scene.free()
	quit()


func _global(n: Node) -> Transform3D:
	var xf := Transform3D()
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


func _slab_range(mi: MeshInstance3D, xf: Transform3D) -> Vector2:
	var v: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var xs: Array[float] = []
	for p in v:
		xs.append((xf * p).x)
	xs.sort()
	return Vector2(xs[int(xs.size() * 0.1)], xs[int(xs.size() * 0.9)])


## Transforms the mesh's triangles by `place` (after the node's own `xf`),
## keeping only connected pieces for which `keep(centre, bounds)` is true
## (both in source space).
func _bake(mi: MeshInstance3D, xf: Transform3D, place: Transform3D, keep: Callable) -> ArrayMesh:
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	# Connected pieces by shared positions.
	var uf := PackedInt32Array()
	uf.resize(verts.size())
	for i in verts.size():
		uf[i] = i
	var by_pos := {}
	for i in verts.size():
		var key := verts[i].snapped(Vector3.ONE * 0.0001)
		if by_pos.has(key):
			_union(uf, i, by_pos[key])
		else:
			by_pos[key] = i
	for t in idx.size() / 3:
		_union(uf, idx[t * 3], idx[t * 3 + 1])
		_union(uf, idx[t * 3], idx[t * 3 + 2])
	var bounds := {}
	for i in verts.size():
		var r := _find(uf, i)
		var p := xf * verts[i]
		bounds[r] = (bounds[r] as AABB).expand(p) if bounds.has(r) else AABB(p, Vector3.ZERO)
	var full := place * xf
	var nbasis := full.basis.inverse().transposed()
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nt := PackedFloat32Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	for t in idx.size() / 3:
		var b: AABB = bounds[_find(uf, idx[t * 3])]
		if not keep.call(b.get_center(), b):
			continue
		var tri: Array[int] = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
		# A mirroring transform would flip the winding; ours are rotations
		# with positive scales, but keep it correct regardless.
		if full.basis.determinant() < 0.0:
			tri = [tri[0], tri[2], tri[1]]
		for old in tri:
			if not remap.has(old):
				remap[old] = nv.size()
				nv.append(full * verts[old])
				nn.append((nbasis * normals[old]).normalized())
				nuv.append(uvs[old])
				if tangents.size() > 0:
					var tg := (full.basis * Vector3(tangents[old * 4], tangents[old * 4 + 1], tangents[old * 4 + 2])).normalized()
					nt.append_array([tg.x, tg.y, tg.z, tangents[old * 4 + 3]])
			ni.append(remap[old])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_TEX_UV] = nuv
	if nt.size() > 0:
		out[Mesh.ARRAY_TANGENT] = nt
	out[Mesh.ARRAY_INDEX] = ni
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	mesh.surface_set_material(0, mi.get_active_material(0))
	return mesh


func _find(uf: PackedInt32Array, a: int) -> int:
	while uf[a] != a:
		uf[a] = uf[uf[a]]
		a = uf[a]
	return a


func _union(uf: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(uf, a)
	var rb := _find(uf, b)
	if ra != rb:
		uf[ra] = rb
