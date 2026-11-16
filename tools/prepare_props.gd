extends SceneTree
## Bakes downloaded prop models into single ArrayMesh resources the building
## generator can place like its own boxes: metres, origin on the floor at the
## centre of the footprint, front facing +Z, one surface per source material.
##
##   godot --headless --path . --script res://tools/prepare_props.gd
##
## Sources and licences: see CREDITS.md.

## [source scene, output .res, yaw (deg) that turns its front to +Z,
##  target height in metres (0 = keep the source's own scale)]
const SPECS := [
	["res://models/sketchfab/toilet/toilet.glb", "res://models/sketchfab/toilet/toilet.res", 0.0, 0.0],
	["res://models/sketchfab/locker/locker.glb", "res://models/sketchfab/locker/locker.res", 0.0, 1.85],
	["res://models/sketchfab/server_rack/server_rack.glb", "res://models/sketchfab/server_rack/server_rack.res", 180.0, 2.0],
	["res://models/sketchfab/old_fridge/old_fridge.glb", "res://models/sketchfab/old_fridge/old_fridge.res", 0.0, 1.6],
	["res://models/sketchfab/old_iron_safe/old_iron_safe.glb", "res://models/sketchfab/old_iron_safe/old_iron_safe.res", 0.0, 0.9],
	["res://models/polyhaven/SchoolDesk_01/SchoolDesk_01.gltf", "res://models/polyhaven/SchoolDesk_01/SchoolDesk_01.res", 0.0, 0.0],
	["res://models/polyhaven/cardboard_box_01/cardboard_box_01.gltf", "res://models/polyhaven/cardboard_box_01/cardboard_box_01.res", 0.0, 0.0],
	["res://models/polyhaven/potted_plant_01/potted_plant_01.gltf", "res://models/polyhaven/potted_plant_01/potted_plant_01.res", 0.0, 0.0],
]


func _initialize() -> void:
	for spec in SPECS:
		var scene: Node = load(spec[0]).instantiate()
		var parts: Array = []      # [MeshInstance3D, global transform]
		_collect(scene, Transform3D(), parts)
		var turn := Basis(Vector3.UP, deg_to_rad(spec[2]))
		var box := AABB()
		var first := true
		for p in parts:
			var b: AABB = (Transform3D(turn, Vector3.ZERO) * p[1]) * (p[0] as MeshInstance3D).mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var s: float = spec[3] / box.size.y if spec[3] > 0.0 else 1.0
		var place := Transform3D(turn.scaled(Vector3.ONE * s),
			-Vector3(box.get_center().x, box.position.y, box.get_center().z) * s)
		var mesh := ArrayMesh.new()
		for p in parts:
			_append(mesh, p[0], place * (p[1] as Transform3D))
		ResourceSaver.save(mesh, spec[1])
		print("[prepare_props] %s -> size %s, %d surfaces" % [spec[1].get_file(), str(mesh.get_aabb().size.snapped(Vector3.ONE * 0.01)), mesh.get_surface_count()])
		scene.free()
	quit()


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, t])
	for c in n.get_children():
		_collect(c, t, out)


func _append(mesh: ArrayMesh, mi: MeshInstance3D, xf: Transform3D) -> void:
	var nbasis := xf.basis.inverse().transposed()
	for si in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = xf * verts[i]
		arr[Mesh.ARRAY_VERTEX] = verts
		if arr[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in normals.size():
				normals[i] = (nbasis * normals[i]).normalized()
			arr[Mesh.ARRAY_NORMAL] = normals
		if arr[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in tangents.size() / 4:
				var t := (xf.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
				tangents[i * 4] = t.x
				tangents[i * 4 + 1] = t.y
				tangents[i * 4 + 2] = t.z
			arr[Mesh.ARRAY_TANGENT] = tangents
		# Skinning/blend data is not needed for static props.
		arr[Mesh.ARRAY_BONES] = null
		arr[Mesh.ARRAY_WEIGHTS] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mi.get_active_material(si))
