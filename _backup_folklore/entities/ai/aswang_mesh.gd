class_name AswangMesh
extends RefCounted
## Procedural anatomy for the Aswang. Bodies are built from two primitives:
##
##   tube()  - an elliptical cross-section swept along a smoothed path, with
##             rounded ends. Limbs, torsos, skulls, tails, hair and entrails.
##   sheet() - skin stretched between two edges, with a scalloped far edge.
##             Wing membranes.
##
## Several calls accumulate into one mesh; commit() returns it. Everything is
## generated once when a creature is built, never per frame.

const CAP_ANGLES: Array[float] = [0.52, 1.05, 1.5]
const MIN_CAP_RADIUS: float = 0.004

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _indices := PackedInt32Array()


func commit() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Sweeps an ellipse along `points` (Vector3). Each entry of `radii` is either
## a float or a Vector2(width, depth); width lies across `up`, depth along it.
## UV.x runs around the tube, UV.y is the distance along it in metres.
func tube(points: Array, radii: Array, up: Vector3 = Vector3.ZERO, sides: int = 10, smooth: int = 4) -> AswangMesh:
	var path: Array[Vector3] = []
	var size: Array[Vector2] = []
	var count: int = points.size()
	for i: int in count - 1:
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, count - 1)]
		var r1: Vector2 = _radius(radii[i])
		var r2: Vector2 = _radius(radii[i + 1])
		for s: int in smooth:
			var t: float = float(s) / float(smooth)
			path.append(p1.cubic_interpolate(p2, p0, p3, t))
			size.append(r1.lerp(r2, t * t * (3.0 - 2.0 * t)))
	var last_point: Vector3 = points[count - 1]
	path.append(last_point)
	size.append(_radius(radii[count - 1]))
	_round_end(path, size, true)
	_round_end(path, size, false)

	var rings: int = path.size()
	var overall: Vector3 = (path[rings - 1] - path[0]).normalized()
	if up == Vector3.ZERO:
		up = Vector3.UP if absf(overall.y) < 0.75 else Vector3.BACK
	var base: int = _vertices.size()
	var ring: int = sides + 1
	var side_axis := Vector3.RIGHT
	var length: float = 0.0
	for k: int in rings:
		var before: Vector3 = path[maxi(k - 1, 0)]
		var after: Vector3 = path[mini(k + 1, rings - 1)]
		var tangent: Vector3 = (after - before).normalized()
		var candidate: Vector3 = up.cross(tangent)
		if candidate.length() > 0.05:
			side_axis = candidate.normalized()
		else:
			side_axis = (side_axis - tangent * side_axis.dot(tangent)).normalized()
		var vert_axis: Vector3 = tangent.cross(side_axis)
		var r: Vector2 = size[k]
		# How fast the tube widens along its length tilts the surface normal.
		var slope: float = 0.0
		var span: float = before.distance_to(after)
		if span > 0.0001:
			var r_before: Vector2 = size[maxi(k - 1, 0)]
			var r_after: Vector2 = size[mini(k + 1, rings - 1)]
			slope = ((r_after.x + r_after.y) - (r_before.x + r_before.y)) * 0.5 / span
		if k > 0:
			length += path[k].distance_to(path[k - 1])
		for j: int in ring:
			var angle: float = TAU * float(j) / float(sides)
			var c: float = cos(angle)
			var s: float = sin(angle)
			_vertices.append(path[k] + side_axis * (c * r.x) + vert_axis * (s * r.y))
			var radial: Vector3 = (side_axis * (c * maxf(r.y, 0.0001)) + vert_axis * (s * maxf(r.x, 0.0001))).normalized()
			_normals.append((radial - tangent * slope).normalized())
			_uvs.append(Vector2(float(j) / float(sides), length))
	for k: int in rings - 1:
		for j: int in sides:
			var a: int = base + k * ring + j
			var b: int = a + 1
			var c: int = a + ring
			var d: int = c + 1
			_indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	return self


## A cone from `from` to `to`: claws, teeth, horns.
func spike(from: Vector3, to: Vector3, radius: float, sides: int = 5) -> AswangMesh:
	return tube([from, from.lerp(to, 0.5), to], [radius, radius * 0.62, 0.0012], Vector3.ZERO, sides, 1)


## Skin between two edges (arrays of Vector3 with matching lengths, ideally
## starting at the same point). The far edge sags towards that start, giving
## the scallop of a bat wing. UV.x runs u0..u1 across, UV.y 0..1 outwards.
func sheet(edge_a: Array, edge_b: Array, sag: float = 0.18, u0: float = 0.0, u1: float = 1.0) -> AswangMesh:
	var rows: int = mini(edge_a.size(), edge_b.size())
	var first_a: Vector3 = edge_a[0]
	var first_b: Vector3 = edge_b[0]
	var origin: Vector3 = (first_a + first_b) * 0.5
	var middle: Array[Vector3] = []
	for k: int in rows:
		var a: Vector3 = edge_a[k]
		var b: Vector3 = edge_b[k]
		var f: float = float(k) / float(rows - 1)
		middle.append(((a + b) * 0.5).lerp(origin, sag * f * f))
	var base: int = _vertices.size()
	for k: int in rows:
		var a: Vector3 = edge_a[k]
		var b: Vector3 = edge_b[k]
		var f: float = float(k) / float(rows - 1)
		var along: Vector3 = middle[mini(k + 1, rows - 1)] - middle[maxi(k - 1, 0)]
		var normal: Vector3 = (b - a).cross(along)
		normal = normal.normalized() if normal.length() > 0.000001 else Vector3.BACK
		_vertices.append_array(PackedVector3Array([a, middle[k], b]))
		_normals.append_array(PackedVector3Array([normal, normal, normal]))
		_uvs.append_array(PackedVector2Array([Vector2(u0, f), Vector2((u0 + u1) * 0.5, f), Vector2(u1, f)]))
	for k: int in rows - 1:
		for column: int in 2:
			var a: int = base + k * 3 + column
			var b: int = a + 1
			var c: int = a + 3
			var d: int = c + 1
			_indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	return self


## A bat wing whose shoulder is the origin and which opens along side * X
## (side is -1 for the left wing, +1 for the right). `fold` 0..1 draws the
## fingers in. Returns [membrane, bones].
static func bat_wing(side: float, span: float, fold: float = 0.0) -> Array[ArrayMesh]:
	var open: float = 1.0 - fold * 0.65
	var shoulder := Vector3.ZERO
	var elbow := Vector3(side * 0.26 * span * open, 0.14 * span, 0.05 * span)
	var wrist := Vector3(side * 0.46 * span * open, 0.3 * span, 0.0)
	var tips: Array[Vector3] = [
		Vector3(side * 1.0 * span * open, 0.16 * span, 0.04 * span),
		Vector3(side * 0.86 * span * open, -0.28 * span, 0.08 * span),
		Vector3(side * 0.6 * span * open, -0.52 * span, 0.1 * span),
		Vector3(side * 0.34 * span * open, -0.6 * span, 0.08 * span),
	]
	var anchor := Vector3(side * 0.03 * span, -0.5 * span, 0.02 * span)
	var rows: int = 6
	var fingers: Array[Array] = []
	for tip: Vector3 in tips:
		# Each finger bows up and back a little, like a strung bow.
		var control: Vector3 = (wrist + tip) * 0.5 + Vector3(0.0, 0.07 * span, 0.05 * span)
		var ray: Array = []
		for k: int in rows:
			var t: float = float(k) / float(rows - 1)
			ray.append(wrist.lerp(control, t).lerp(control.lerp(tip, t), t))
		fingers.append(ray)
	var body_edge: Array = _resample([wrist, elbow, shoulder, anchor], rows)

	var membrane := AswangMesh.new()
	for i: int in fingers.size() - 1:
		membrane.sheet(fingers[i], fingers[i + 1], 0.36, float(i) * 0.25, float(i + 1) * 0.25)
	membrane.sheet(fingers[fingers.size() - 1], body_edge, 0.1, 0.75, 1.0)

	var bones := AswangMesh.new()
	bones.tube([shoulder, elbow, wrist], [0.03 * span, 0.02 * span, 0.015 * span], Vector3.BACK, 6, 3)
	for ray: Array in fingers:
		bones.tube([ray[0], ray[2], ray[4], ray[5]], [0.011 * span, 0.008 * span, 0.005 * span, 0.002 * span], Vector3.BACK, 5, 2)
	bones.spike(wrist, wrist + Vector3(side * 0.03 * span, 0.11 * span, -0.05 * span), 0.012 * span)
	return [membrane.commit(), bones.commit()]


static func _resample(polyline: Array, count: int) -> Array:
	var lengths: Array[float] = [0.0]
	for i: int in range(1, polyline.size()):
		var a: Vector3 = polyline[i - 1]
		var b: Vector3 = polyline[i]
		lengths.append(lengths[i - 1] + a.distance_to(b))
	var total: float = lengths[lengths.size() - 1]
	var result: Array = []
	var segment: int = 0
	for k: int in count:
		var target: float = total * float(k) / float(count - 1)
		while segment < polyline.size() - 2 and lengths[segment + 1] < target:
			segment += 1
		var a: Vector3 = polyline[segment]
		var b: Vector3 = polyline[segment + 1]
		var segment_length: float = maxf(lengths[segment + 1] - lengths[segment], 0.00001)
		result.append(a.lerp(b, clampf((target - lengths[segment]) / segment_length, 0.0, 1.0)))
	return result


static func _radius(value: Variant) -> Vector2:
	if value is Vector2:
		var pair: Vector2 = value
		return pair
	var uniform: float = value
	return Vector2(uniform, uniform)


## Extends one end of a path with a few shrinking rings so it closes in a dome.
static func _round_end(path: Array[Vector3], size: Array[Vector2], at_start: bool) -> void:
	var index: int = 0 if at_start else path.size() - 1
	var neighbour: int = 1 if at_start else path.size() - 2
	var r: Vector2 = size[index]
	var depth: float = minf(r.x, r.y)
	if depth < MIN_CAP_RADIUS:
		return
	var tip: Vector3 = path[index]
	var outward: Vector3 = (tip - path[neighbour]).normalized()
	for angle: float in CAP_ANGLES:
		var point: Vector3 = tip + outward * depth * sin(angle)
		var scaled: Vector2 = r * cos(angle)
		if at_start:
			path.insert(0, point)
			size.insert(0, scaled)
		else:
			path.append(point)
			size.append(scaled)
