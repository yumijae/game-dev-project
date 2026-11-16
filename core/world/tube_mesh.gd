class_name TubeMesh
extends RefCounted
## A round tube swept along a path: tap spouts, cables, pipes. Rings are
## parallel-transported so the tube never twists, and every triangle is wound
## to face outwards (Godot treats clockwise as front-facing).


static func build(path: Array[Vector3], radius: float, sides: int = 14) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var count: int = path.size()
	if count < 2:
		return ArrayMesh.new()
	var tangent: Vector3 = (path[1] - path[0]).normalized()
	var normal: Vector3 = tangent.cross(Vector3.RIGHT if absf(tangent.x) < 0.9 else Vector3.FORWARD).normalized()
	for i: int in count:
		var next_tangent: Vector3 = (path[mini(i + 1, count - 1)] - path[maxi(i - 1, 0)]).normalized()
		var axis: Vector3 = tangent.cross(next_tangent)
		if axis.length() > 0.0001:
			normal = normal.rotated(axis.normalized(), tangent.angle_to(next_tangent))
		tangent = next_tangent
		var binormal: Vector3 = tangent.cross(normal).normalized()
		for k: int in sides + 1:
			var a: float = TAU * float(k) / float(sides)
			var dir: Vector3 = normal * cos(a) + binormal * sin(a)
			verts.append(path[i] + dir * radius)
			normals.append(dir)
			uvs.append(Vector2(float(k) / float(sides), float(i) / float(count - 1)))
	for i: int in count - 1:
		for k: int in sides:
			var v00: int = i * (sides + 1) + k
			var v10: int = v00 + sides + 1
			for tri: Array in [[v00, v00 + 1, v10 + 1], [v00, v10 + 1, v10]]:
				var a: int = tri[0]
				var b: int = tri[1]
				var c: int = tri[2]
				var face: Vector3 = (verts[c] - verts[a]).cross(verts[b] - verts[a])
				if face.dot(normals[a]) < 0.0:
					indices.append_array([a, c, b])
				else:
					indices.append_array([a, b, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
