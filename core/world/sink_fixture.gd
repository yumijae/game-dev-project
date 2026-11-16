class_name SinkFixture
extends Node3D
## A worktop with real basins sunk into it, drains and taps. Builds its own
## meshes on load from a few numbers the building generator stores, so the
## scene file stays small and the look lives in one place.
##
##   VANITY  - restroom washstand: speckled stone top with oval cut-outs and
##             drop-in porcelain basins, a chrome lever tap behind each.
##   KITCHEN - culinary sink: brushed steel top with a deep rectangular
##             stainless basin and a tall gooseneck tap.
##
## Local frame: origin on the floor at the middle of the counter, +Z towards
## the room (the front edge), X along the counter, Y up. The cabinet below
## the worktop, and the collision, belong to the building generator
## (MapRefitAndGlassBuilder._sink_counter); only the top `CAVITY` is built
## here, leaving room for the bowls to hang into.

enum Style { VANITY, KITCHEN }

## How much of the counter's height the generator leaves hollow for this.
const CAVITY: Dictionary = {Style.VANITY: 0.2, Style.KITCHEN: 0.25}
const TOP_THICKNESS: float = 0.03
## Oval drop-in basin, as (radius fraction, height above the worktop).
## Rim lip first, then down the bowl to the drain.
const BOWL_PROFILE: Array[Vector2] = [
	Vector2(1.0, 0.002), Vector2(0.985, 0.009), Vector2(0.95, 0.013), Vector2(0.9, 0.013),
	Vector2(0.86, 0.009), Vector2(0.84, 0.0), Vector2(0.82, -0.02), Vector2(0.77, -0.055),
	Vector2(0.69, -0.09), Vector2(0.58, -0.118), Vector2(0.45, -0.137), Vector2(0.3, -0.149),
	Vector2(0.16, -0.154), Vector2(0.1, -0.155),
]
const BOWL_SEGMENTS: int = 56
const VANITY_BASIN: Vector2 = Vector2(0.22, 0.16)
const KITCHEN_BASIN: Vector3 = Vector3(0.27, 0.2, 0.2)
const PORCELAIN_SHADER: Shader = preload("res://shaders/porcelain.gdshader")

@export var style: Style = Style.VANITY
@export var length: float = 2.6
@export var depth: float = 0.55
@export var height: float = 0.85
## Basin centres along the counter (local X).
@export var basins: PackedFloat32Array = PackedFloat32Array([0.0])

static var _materials: Dictionary = {}


func _ready() -> void:
	var holes: Array[Dictionary] = []
	var basin_z: float = 0.02 if style == Style.VANITY else 0.03
	for i: int in basins.size():
		var x: float = basins[i]
		if style == Style.VANITY:
			holes.append({"x": x, "z": basin_z, "ax": VANITY_BASIN.x * 0.9, "az": VANITY_BASIN.y * 0.9, "oval": true})
			_add_bowl(Vector3(x, height, basin_z), i)
			_add_lever_tap(Vector3(x, height, basin_z - VANITY_BASIN.y - 0.045))
		else:
			holes.append({"x": x, "z": basin_z, "ax": KITCHEN_BASIN.x, "az": KITCHEN_BASIN.y, "oval": false})
			_add_steel_basin(Vector3(x, height, basin_z))
			_add_gooseneck_tap(Vector3(x, height, basin_z - KITCHEN_BASIN.y - 0.055))
	_add_mesh(_worktop_mesh(holes), _material(&"stone" if style == Style.VANITY else &"steel_top"))


# -------------------------------------------------------------------- worktop

## The top slab with its cut-outs, sliced into strips along X: every strip
## that crosses a hole becomes a back piece and a front piece.
func _worktop_mesh(holes: Array[Dictionary]) -> ArrayMesh:
	var m := _Mesher.new()
	var half_l: float = length * 0.5
	var back: float = -depth * 0.5
	var front: float = depth * 0.5
	var y: float = height
	var xs: Array[float] = [-half_l, half_l]
	for hole: Dictionary in holes:
		var steps: int = 28 if hole["oval"] else 1
		for i: int in steps + 1:
			xs.append(hole["x"] - hole["ax"] + 2.0 * hole["ax"] * float(i) / float(steps))
	xs.sort()
	for i: int in xs.size() - 1:
		var x0: float = xs[i]
		var x1: float = xs[i + 1]
		if x1 - x0 < 0.0005:
			continue
		var mid: float = (x0 + x1) * 0.5
		var cut: Dictionary = {}
		for hole: Dictionary in holes:
			if absf(mid - hole["x"]) < hole["ax"]:
				cut = hole
		if cut.is_empty():
			m.quad(Vector3(x0, y, back), Vector3(x1, y, back), Vector3(x1, y, front), Vector3(x0, y, front), Vector3.UP)
			continue
		var f0: float = _half_width(cut, x0)
		var f1: float = _half_width(cut, x1)
		var cz: float = cut["z"]
		m.quad(Vector3(x0, y, back), Vector3(x1, y, back), Vector3(x1, y, cz - f1), Vector3(x0, y, cz - f0), Vector3.UP)
		m.quad(Vector3(x0, y, cz + f0), Vector3(x1, y, cz + f1), Vector3(x1, y, front), Vector3(x0, y, front), Vector3.UP)
	# Front edge and the two ends (the back is against the wall).
	var y0: float = y - TOP_THICKNESS
	m.quad(Vector3(-half_l, y0, front), Vector3(half_l, y0, front), Vector3(half_l, y, front), Vector3(-half_l, y, front), Vector3.BACK)
	for side: float in [-1.0, 1.0]:
		var x: float = side * half_l
		m.quad(Vector3(x, y0, back), Vector3(x, y0, front), Vector3(x, y, front), Vector3(x, y, back), Vector3(side, 0.0, 0.0))
	return m.commit()


func _half_width(hole: Dictionary, x: float) -> float:
	if not hole["oval"]:
		return hole["az"]
	var t: float = clampf((x - hole["x"]) / hole["ax"], -1.0, 1.0)
	return hole["az"] * sqrt(maxf(1.0 - t * t, 0.0))


# --------------------------------------------------------------------- basins

## Drop-in oval porcelain basin, lathed from BOWL_PROFILE.
func _add_bowl(centre: Vector3, index: int) -> void:
	var m := _Mesher.new()
	var rings: int = BOWL_PROFILE.size()
	var above: Vector3 = centre + Vector3.UP
	for i: int in rings:
		var s: float = BOWL_PROFILE[i].x
		var a: Vector2 = BOWL_PROFILE[maxi(i - 1, 0)]
		var b: Vector2 = BOWL_PROFILE[mini(i + 1, rings - 1)]
		for j: int in BOWL_SEGMENTS + 1:
			var theta: float = TAU * float(j) / float(BOWL_SEGMENTS)
			var c: float = cos(theta)
			var sn: float = sin(theta)
			var p := centre + Vector3(c * VANITY_BASIN.x * s, BOWL_PROFILE[i].y, sn * VANITY_BASIN.y * s)
			var along := Vector3(c * VANITY_BASIN.x * (b.x - a.x), b.y - a.y, sn * VANITY_BASIN.y * (b.x - a.x))
			var round_dir := Vector3(-sn * VANITY_BASIN.x, 0.0, c * VANITY_BASIN.y)
			var normal: Vector3 = round_dir.cross(along).normalized()
			if normal.dot(above - p) < 0.0:
				normal = -normal
			m.vertex(p, normal, Vector2(float(j) / float(BOWL_SEGMENTS), float(i) / float(rings - 1)))
	for i: int in rings - 1:
		for j: int in BOWL_SEGMENTS:
			var v00: int = i * (BOWL_SEGMENTS + 1) + j
			var v01: int = v00 + 1
			var v10: int = v00 + BOWL_SEGMENTS + 1
			var v11: int = v10 + 1
			m.index_quad(v00, v01, v11, v10, above)
	var material := ShaderMaterial.new()
	material.shader = PORCELAIN_SHADER
	material.set_shader_parameter(&"seed", float(index) * 13.7 + global_position.x + global_position.z)
	material.set_shader_parameter(&"wear", 0.7 + 0.3 * float((index * 7 + 3) % 4) / 3.0)
	_add_mesh(m.commit(), material)
	_add_drain(centre + Vector3(0.0, -0.1545, 0.0))


## Deep rectangular stainless basin hung under the cut-out.
func _add_steel_basin(centre: Vector3) -> void:
	var steel: Material = _material(&"steel_basin")
	var hx: float = KITCHEN_BASIN.x
	var hz: float = KITCHEN_BASIN.y
	var deep: float = KITCHEN_BASIN.z
	var wall: float = 0.006
	var top: float = centre.y - 0.002
	var bottom: float = centre.y - deep
	var mid_y: float = (top + bottom) * 0.5
	var h: float = top - bottom
	_add_box(Vector3(centre.x, bottom - wall * 0.5, centre.z), Vector3(hx * 2.0 + wall * 2.0, wall, hz * 2.0 + wall * 2.0), steel)
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(centre.x + side * (hx + wall * 0.5), mid_y, centre.z), Vector3(wall, h, hz * 2.0 + wall * 2.0), steel)
		_add_box(Vector3(centre.x, mid_y, centre.z + side * (hz + wall * 0.5)), Vector3(hx * 2.0, h, wall), steel)
	_add_drain(Vector3(centre.x, bottom + 0.001, centre.z + 0.04))


func _add_drain(at: Vector3) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.017
	ring.outer_radius = 0.028
	ring.rings = 24
	ring.ring_segments = 8
	var ring_instance := _add_mesh(ring, _material(&"chrome"))
	ring_instance.position = at
	ring_instance.scale = Vector3(1.0, 0.25, 1.0)
	var hole := CylinderMesh.new()
	hole.top_radius = 0.019
	hole.bottom_radius = 0.019
	hole.height = 0.002
	hole.radial_segments = 20
	var hole_instance := _add_mesh(hole, _material(&"drain"))
	hole_instance.position = at
	# Cross bars over the drain hole.
	for angle: float in [0.0, PI * 0.5]:
		var bar := _add_box(at + Vector3(0.0, 0.0015, 0.0), Vector3(0.036, 0.002, 0.004), _material(&"chrome"))
		bar.rotation.y = angle


# ----------------------------------------------------------------------- taps

## Deck-mounted single-lever tap with a short curved spout over the bowl.
func _add_lever_tap(base: Vector3) -> void:
	var chrome: Material = _material(&"chrome")
	_add_cylinder(base + Vector3(0.0, 0.006, 0.0), 0.03, 0.012, chrome)
	var path: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.1, 0.0)]
	for k: int in 7:
		var a: float = PI * 0.5 * float(k + 1) / 7.0
		path.append(Vector3(0.0, 0.1 + sin(a) * 0.04, 0.04 - cos(a) * 0.04 + 0.0))
	path.append(path[-1] + Vector3(0.0, -0.004, 0.03))
	path.append(path[-1] + Vector3(0.0, -0.012, 0.03))
	for k: int in path.size():
		path[k] += base
	_add_mesh(TubeMesh.build(path, 0.0135), chrome)
	_add_aerator(path[-1], (path[-1] - path[-2]).normalized(), 0.0135)
	var lever := _add_box(base + Vector3(0.0, 0.125, -0.025), Vector3(0.014, 0.01, 0.075), chrome)
	# Each lever left at a slightly different angle, the same every night.
	var global_base: Vector3 = to_global(base)
	lever.rotation = Vector3(0.35, fposmod(global_base.x * 13.1 + global_base.z * 7.3, 0.5) - 0.25, 0.0)
	_add_cylinder(base + Vector3(0.0, 0.11, 0.0), 0.02, 0.03, chrome)


## Tall swan-neck tap for the culinary sinks, with a side lever.
func _add_gooseneck_tap(base: Vector3) -> void:
	var chrome: Material = _material(&"chrome")
	_add_cylinder(base + Vector3(0.0, 0.01, 0.0), 0.032, 0.02, chrome)
	var path: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.16, 0.0), Vector3(0.0, 0.2, 0.0)]
	var r: float = 0.085
	for k: int in 13:
		var a: float = PI * float(k + 1) / 13.0
		path.append(Vector3(0.0, 0.2 + sin(a) * r, r - cos(a) * r))
	path.append(path[-1] + Vector3(0.0, -0.05, 0.0))
	for k: int in path.size():
		path[k] += base
	_add_mesh(TubeMesh.build(path, 0.0125), chrome)
	_add_aerator(path[-1], Vector3.DOWN, 0.0125)
	var lever := _add_box(base + Vector3(0.045, 0.1, 0.0), Vector3(0.07, 0.012, 0.014), chrome)
	lever.rotation.z = 0.25
	_add_cylinder(base + Vector3(0.022, 0.1, 0.0), 0.016, 0.03, chrome, Basis(Vector3.BACK, PI * 0.5))


func _add_aerator(at: Vector3, direction: Vector3, radius: float) -> void:
	var cap := CylinderMesh.new()
	cap.top_radius = radius * 0.8
	cap.bottom_radius = radius * 0.8
	cap.height = 0.003
	cap.radial_segments = 16
	var instance := _add_mesh(cap, _material(&"drain"))
	var up := direction.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	instance.transform = Transform3D(Basis(side, up, side.cross(up)), at)


# -------------------------------------------------------------------- helpers

func _add_mesh(mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)
	return instance


func _add_box(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var instance := _add_mesh(box, material)
	instance.position = at
	return instance


func _add_cylinder(at: Vector3, radius: float, tall: float, material: Material, basis := Basis.IDENTITY) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = tall
	cylinder.radial_segments = 20
	var instance := _add_mesh(cylinder, material)
	instance.transform = Transform3D(basis, at)
	return instance


## Materials are shared by every sink in the building.
static func _material(key: StringName) -> Material:
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	match key:
		&"chrome":
			# Not mirror chrome: in a blackout that reflects only darkness and
			# reads as black. Slightly worn plating catches the flashlight.
			m.albedo_color = Color(0.86, 0.87, 0.89)
			m.metallic = 0.72
			m.roughness = 0.24
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
			m.clearcoat_roughness = 0.1
		&"steel_basin":
			m.albedo_color = Color(0.66, 0.67, 0.69)
			m.metallic = 0.9
			m.roughness = 0.3
			m.anisotropy_enabled = true
			m.anisotropy = 0.6
		&"steel_top":
			m.albedo_color = Color(0.72, 0.73, 0.75)
			m.metallic = 0.85
			m.roughness = 0.27
		&"drain":
			m.albedo_color = Color(0.03, 0.03, 0.03)
			m.metallic = 0.4
			m.roughness = 0.5
		&"stone":
			# Dark speckled granite.
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_CELLULAR
			noise.frequency = 0.09
			noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
			var ramp := Gradient.new()
			ramp.offsets = PackedFloat32Array([0.0, 0.55, 0.8, 0.93, 1.0])
			ramp.colors = PackedColorArray([Color(0.07, 0.07, 0.075), Color(0.12, 0.12, 0.125),
				Color(0.2, 0.2, 0.2), Color(0.42, 0.41, 0.39), Color(0.62, 0.6, 0.57)])
			var texture := NoiseTexture2D.new()
			texture.noise = noise
			texture.color_ramp = ramp
			texture.width = 512
			texture.height = 512
			texture.seamless = true
			m.albedo_texture = texture
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
			m.roughness = 0.28
			m.clearcoat_enabled = true
			m.clearcoat = 0.4
			m.clearcoat_roughness = 0.2
	_materials[key] = m
	return m


## Accumulates vertices and triangles; every triangle is wound so its front
## face points where it should (Godot treats clockwise as front-facing).
class _Mesher:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func vertex(p: Vector3, n: Vector3, uv: Vector2) -> int:
		verts.append(p)
		normals.append(n)
		uvs.append(uv)
		return verts.size() - 1

	## Quad a-b-c-d; `toward` is a point the front face looks at, or with
	## `use_normals` the stored vertex normals decide.
	func index_quad(a: int, b: int, c: int, d: int, toward: Vector3, use_normals := false) -> void:
		_tri(a, b, c, toward, use_normals)
		_tri(a, c, d, toward, use_normals)

	func _tri(a: int, b: int, c: int, toward: Vector3, use_normals: bool) -> void:
		var pa: Vector3 = verts[a]
		var face: Vector3 = (verts[c] - pa).cross(verts[b] - pa)
		var want: Vector3 = normals[a] if use_normals else toward - pa
		if face.dot(want) < 0.0:
			indices.append_array([a, c, b])
		else:
			indices.append_array([a, b, c])

	## Flat quad facing `normal`.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
		var base: int = verts.size()
		for p: Vector3 in [a, b, c, d]:
			vertex(p, normal, Vector2(p.x, p.z))
		index_quad(base, base + 1, base + 2, base + 3, Vector3.ZERO, true)

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return mesh
