extends SceneTree
## Bakes the Sketchfab "Bathroom Urinal Game-Ready" model into urinal.res, ready
## to hang on a wall: metres, front (opening) towards +Z, back on the z = 0
## plane, centred on x = 0, bottom of the china at y = 0.
##
##   godot --headless --path . --script res://tools/prepare_urinal.gd
##
## Model: "Bathroom Urinal Game-Ready" by CurlyFryWhy, CC BY 4.0 (CREDITS.md).

const SRC := "res://models/sketchfab/urinal/urinal.glb"
const OUT := "res://models/sketchfab/urinal/urinal.res"
## Source units are ~decimetres; this makes it 1.1 m tall including the valve.
const SCALE := 0.0815
## The source model's opening faces +X.
const TURN := -PI * 0.5


func _initialize() -> void:
	var scene: Node = load(SRC).instantiate()
	var mi: MeshInstance3D = scene.find_child("Object_2", true, false)
	var xf := Transform3D()
	var n: Node = mi
	while n != null and n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	var place := Transform3D(Basis(Vector3.UP, TURN).scaled(Vector3.ONE * SCALE), Vector3.ZERO) * xf
	var box := place * mi.mesh.get_aabb()
	place = Transform3D(Basis(), Vector3(-box.get_center().x, -box.position.y, -box.position.z)) * place
	var arr: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		verts[i] = place * verts[i]
		normals[i] = (place.basis * normals[i]).normalized()
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	if arr[Mesh.ARRAY_TANGENT] != null:
		var tangents: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		for i in tangents.size() / 4:
			var t := (place.basis * Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])).normalized()
			tangents[i * 4] = t.x
			tangents[i * 4 + 1] = t.y
			tangents[i * 4 + 2] = t.z
		arr[Mesh.ARRAY_TANGENT] = tangents
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, mi.get_active_material(0))
	ResourceSaver.save(mesh, OUT)
	print("[prepare_urinal] size %s" % str(mesh.get_aabb().size))
	scene.free()
	quit()
