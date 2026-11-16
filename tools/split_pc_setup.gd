extends SceneTree
## Splits the Sketchfab "PC Setup - Game Ready" model (one combined mesh) into
## the two meshes the school uses, keeping its PBR material:
##
##   pc_desk_set.res  monitor + keyboard + mouse. Origin on the desk under the
##                    monitor stand, +Z toward the user (keyboard side).
##   pc_tower.res     the tower. Origin on the floor at its centre, +Z = front.
##
##   godot --headless --path . --script res://tools/split_pc_setup.gd
##
## Model: "PC Setup - Game Ready" by Melon Polygons, CC BY 4.0 (see CREDITS.md).

const SRC := "res://models/sketchfab/pc_setup/pc_setup.glb"
const OUT_DIR := "res://models/sketchfab/pc_setup/"
## Scales the set so the tower matches the school's other props (0.44 m tall).
const SCALE := 0.93
## The tower's footprint in the source model (metres, before SCALE).
const TOWER_MIN := Vector3(0.165, -0.01, -0.31)
const TOWER_MAX := Vector3(0.442, 0.48, 0.141)


func _initialize() -> void:
	var scene: Node = load(SRC).instantiate()
	var mi: MeshInstance3D = scene.find_child("SM_PC_Box_01_1_0", true, false)
	var xf := Transform3D()
	var n: Node = mi
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var material: Material = mi.get_active_material(0)
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	# Connected pieces (triangles sharing vertex positions).
	var uf := PackedInt32Array()
	uf.resize(verts.size())
	for i in verts.size():
		uf[i] = i
	var by_pos := {}
	for i in verts.size():
		var key := (xf * verts[i]).snapped(Vector3.ONE * 0.0001)
		if by_pos.has(key):
			_union(uf, i, by_pos[key])
		else:
			by_pos[key] = i
	for t in idx.size() / 3:
		_union(uf, idx[t * 3], idx[t * 3 + 1])
		_union(uf, idx[t * 3], idx[t * 3 + 2])
	var piece_box := {}
	for t in idx.size() / 3:
		var r := _find(uf, idx[t * 3])
		for k in 3:
			var p := xf * verts[idx[t * 3 + k]]
			piece_box[r] = (piece_box[r] as AABB).expand(p) if piece_box.has(r) else AABB(p, Vector3.ZERO)
	var tower_box := AABB(TOWER_MIN, TOWER_MAX - TOWER_MIN)
	var tower_tris := PackedInt32Array()
	var desk_tris := PackedInt32Array()
	for t in idx.size() / 3:
		var pb: AABB = piece_box[_find(uf, idx[t * 3])]
		if tower_box.encloses(pb):
			tower_tris.append(t)
		else:
			desk_tris.append(t)
	# Origins: the tower's floor centre; the monitor stand's centre on the desk.
	var tower_bounds := _bounds(arr, xf, tower_tris)
	var tower_origin := Vector3(tower_bounds.get_center().x, 0.0, tower_bounds.get_center().z)
	var desk_origin := Vector3(-0.175, 0.0, -0.1015)
	var tower := _extract(arr, xf, tower_tris, tower_origin, material)
	var desk := _extract(arr, xf, desk_tris, desk_origin, material)
	ResourceSaver.save(tower, OUT_DIR + "pc_tower.res")
	ResourceSaver.save(desk, OUT_DIR + "pc_desk_set.res")
	print("[split_pc_setup] tower: %d tris, size %s | desk set: %d tris, size %s" % [
		tower_tris.size(), str(tower.get_aabb().size), desk_tris.size(), str(desk.get_aabb().size)])
	scene.free()
	quit()


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


func _bounds(arr: Array, xf: Transform3D, tris: PackedInt32Array) -> AABB:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var box := AABB(xf * verts[idx[tris[0] * 3]], Vector3.ZERO)
	for t in tris:
		for k in 3:
			box = box.expand(xf * verts[idx[t * 3 + k]])
	return box


## New mesh from the given triangles, moved so `origin` is at 0 and scaled.
func _extract(arr: Array, xf: Transform3D, tris: PackedInt32Array, origin: Vector3, material: Material) -> ArrayMesh:
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT] if arr[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var place := Transform3D(Basis.from_scale(Vector3.ONE * SCALE), -origin * SCALE) * xf
	var remap := {}
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nt := PackedFloat32Array()
	var nuv := PackedVector2Array()
	var ni := PackedInt32Array()
	for t in tris:
		for k in 3:
			var old := idx[t * 3 + k]
			if not remap.has(old):
				remap[old] = nv.size()
				nv.append(place * verts[old])
				nn.append((place.basis * normals[old]).normalized())
				nuv.append(uvs[old])
				if tangents.size() > 0:
					var tg := (place.basis * Vector3(tangents[old * 4], tangents[old * 4 + 1], tangents[old * 4 + 2])).normalized()
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
	mesh.surface_set_material(0, material)
	return mesh
