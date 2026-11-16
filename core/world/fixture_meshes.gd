extends RefCounted
## Procedural meshes for fixtures that have no downloaded model: the wall-hung
## urinal, the flat-panel monitor, keyboard + mouse, and the front-panel detail
## of a PC tower. Each mesh is built once and shared by every instance, so the
## saved building scene stores it only once.
##
## Conventions: local +Z points at the user (away from the wall / out of the
## screen / out of the tower's front), +Y is up, the origin is on the floor or
## desk surface. Used by tools/MapRefitAndGlassBuilder.gd.

static var _cache: Dictionary = {}
static var _mats: Dictionary = {}


static func _mat(key: String) -> StandardMaterial3D:
	# Separate surfaces that share a material (kept apart only so their
	# normals are not smoothed together).
	key = key.get_slice("#", 0)
	key = {"ceramic_cap": "ceramic", "rim": "ceramic", "basin_floor": "basin"}.get(key, key)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.resource_name = "fixture_" + key
	match key:
		"ceramic":
			m.albedo_color = Color(0.94, 0.94, 0.92)
			m.roughness = 0.12
			m.metallic_specular = 0.7
		"basin":
			# Same glaze as the outside, a touch less glossy so the inside
			# doesn't read as grey glass mirroring the room.
			m.albedo_color = Color(0.9, 0.9, 0.89)
			m.roughness = 0.28
			m.metallic_specular = 0.5
		"chrome":
			# Satin rather than mirror: a perfect mirror only reflects the
			# dark restroom and reads as black plastic.
			m.albedo_color = Color(0.78, 0.79, 0.81)
			m.metallic = 0.85
			m.roughness = 0.32
		"drain":
			m.albedo_color = Color(0.62, 0.63, 0.64)
			m.metallic = 0.5
			m.roughness = 0.45
		"plastic":
			m.albedo_color = Color(0.045, 0.047, 0.052)
			m.roughness = 0.45
		"plastic_light":
			m.albedo_color = Color(0.11, 0.115, 0.125)
			m.roughness = 0.4
		"keycap":
			m.albedo_color = Color(0.05, 0.052, 0.057)
			m.roughness = 0.6
		"bezel":
			m.albedo_color = Color(0.03, 0.031, 0.034)
			m.roughness = 0.6
		"stand":
			m.albedo_color = Color(0.16, 0.165, 0.175)
			m.metallic = 0.35
			m.roughness = 0.38
		"logo":
			m.albedo_color = Color(0.7, 0.71, 0.73)
			m.metallic = 0.9
			m.roughness = 0.3
		"keytop":
			m.albedo_color = Color(0.095, 0.097, 0.105)
			m.roughness = 0.55
		"cable":
			m.albedo_color = Color(0.025, 0.025, 0.028)
			m.roughness = 0.55
		"slot":
			m.albedo_color = Color(0.01, 0.01, 0.012)
			m.roughness = 0.9
		"led":
			m.albedo_color = Color(0.2, 0.5, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.25, 0.55, 1.0)
			m.emission_energy_multiplier = 1.5
	_mats[key] = m
	return m


# ------------------------------------------------------------ mesh assembly

## Collects primitives per material and commits them as one ArrayMesh.
class _Builder:
	var tools: Dictionary = {}
	var order: Array[String] = []

	func _st(key: String) -> SurfaceTool:
		if not tools.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[key] = st
			order.append(key)
		return tools[key]

	func prim(key: String, mesh: PrimitiveMesh, xf: Transform3D) -> void:
		_st(key).append_from(mesh, 0, xf)

	func box(key: String, center: Vector3, size: Vector3, basis := Basis()) -> void:
		var bm := BoxMesh.new()
		bm.size = size
		prim(key, bm, Transform3D(basis, center))

	## Cylinder of radius r and length h, centred at `center`, axis along `axis`.
	func cyl(key: String, center: Vector3, r: float, h: float, axis: Vector3, segments := 16) -> void:
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = segments
		cm.rings = 1
		prim(key, cm, Transform3D(_basis_y_to(axis), center))

	## Slab with rounded corners: w x h in its local XY plane, d thick along
	## local Z, corner radius r, placed by `basis` at `center`. Flat faces and
	## smoothly shaded edges.
	func rrect(key: String, center: Vector3, w: float, h: float, d: float, r: float, basis: Basis, segments := 6) -> void:
		# Its own surface: append_from() switches a surface to indexed
		# geometry, which would drop vertices added one by one before it.
		var st := _st(key + "#r")
		r = minf(r, minf(w, h) * 0.5 - 0.0005)
		var outline: Array[Vector2] = []
		var normals: Array[Vector2] = []
		var corners := [Vector2(w * 0.5 - r, h * 0.5 - r), Vector2(-w * 0.5 + r, h * 0.5 - r),
			Vector2(-w * 0.5 + r, -h * 0.5 + r), Vector2(w * 0.5 - r, -h * 0.5 + r)]
		for ci in 4:
			for k in segments + 1:
				var a := (float(ci) + float(k) / segments) * PI * 0.5
				var dir := Vector2(cos(a), sin(a))
				outline.append(corners[ci] + dir * r)
				normals.append(dir)
		var fz := Vector3(0, 0, d * 0.5)
		var nf := (basis * Vector3.BACK).normalized()
		var nb := -nf
		var n := outline.size()
		for i in n:
			var a2: Vector2 = outline[i]
			var b2: Vector2 = outline[(i + 1) % n]
			var pa := Vector3(a2.x, a2.y, 0)
			var pb := Vector3(b2.x, b2.y, 0)
			# front and back faces (fan from the centre)
			for side in [[fz, nf], [-fz, nb]]:
				var off: Vector3 = side[0]
				var nn: Vector3 = side[1]
				var tri_p := [center + basis * off, center + basis * (pa + off), center + basis * (pb + off)]
				if (tri_p[1] - tri_p[0]).cross(tri_p[2] - tri_p[0]).dot(nn) > 0.0:
					tri_p = [tri_p[0], tri_p[2], tri_p[1]]
				for q in tri_p:
					st.set_normal(nn)
					st.add_vertex(q)
			# edge band
			var na := (basis * Vector3(normals[i].x, normals[i].y, 0)).normalized()
			var nbb := (basis * Vector3(normals[(i + 1) % n].x, normals[(i + 1) % n].y, 0)).normalized()
			var quad := [[center + basis * (pa + fz), na], [center + basis * (pb + fz), nbb],
				[center + basis * (pb - fz), nbb], [center + basis * (pa - fz), na]]
			for idx in [[0, 1, 2], [0, 2, 3]]:
				var v0: Array = quad[idx[0]]
				var v1: Array = quad[idx[1]]
				var v2: Array = quad[idx[2]]
				var out: Vector3 = v0[1] + v1[1] + v2[1]
				if (v1[0] - v0[0]).cross(v2[0] - v0[0]).dot(out) > 0.0:
					var t: Array = v1
					v1 = v2
					v2 = t
				for v in [v0, v1, v2]:
					st.set_normal(v[1])
					st.add_vertex(v[0])

	## Smooth triangle; the winding is fixed so the face points along `outward`.
	func tri(key: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
		var st := _st(key)
		# Godot front faces wind so that (b - a) x (c - a) points *into* the face.
		if (b - a).cross(c - a).dot(outward) > 0.0:
			var t := b
			b = c
			c = t
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)

	func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
		tri(key, a, b, c, outward)
		tri(key, a, c, d, outward)

	## Quad with explicit per-corner normals (for analytically smooth surfaces).
	func quad_n(key: String, p: Array[Vector3], n: Array[Vector3]) -> void:
		var st := _st(key)
		var outward: Vector3 = n[0] + n[1] + n[2] + n[3]
		for idx in [[0, 1, 2], [0, 2, 3]]:
			var i0: int = idx[0]
			var i1: int = idx[1]
			var i2: int = idx[2]
			if (p[i1] - p[i0]).cross(p[i2] - p[i0]).dot(outward) > 0.0:
				var t := i1
				i1 = i2
				i2 = t
			for k in [i0, i1, i2]:
				st.set_normal(n[k])
				st.add_vertex(p[k])

	func commit(materials: Callable, smooth: Array[String] = []) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for key in order:
			var st: SurfaceTool = tools[key]
			if smooth.has(key):
				st.index()
				st.generate_normals()
			st.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, materials.call(key))
		return mesh

	static func _basis_y_to(axis: Vector3) -> Basis:
		axis = axis.normalized()
		if axis.is_equal_approx(Vector3.UP):
			return Basis()
		if axis.is_equal_approx(Vector3.DOWN):
			return Basis(Vector3.RIGHT, PI)
		var rot_axis := Vector3.UP.cross(axis).normalized()
		return Basis(rot_axis, Vector3.UP.angle_to(axis))


# ------------------------------------------------------------------ urinal
#
# The body is a stack of rows (height fraction v) of half-superellipse
# cross-sections against the wall, parametrised by theta (-90 deg at the wall
# on the left, 0 at the front, +90 deg at the wall on the right). The front
# opening removes the middle columns of the rows between OPEN_ROW0 (the front
# lip of the trough) and OPEN_ROW1 (the edge of the hood).
#
# The hollow inside is a separate surface built from the rim inwards: a
# U-shaped bowl whose back is CAVITY_BACK from the wall, a trough below the
# front lip (closed by a front wall one china-thickness behind the body) down
# to BASIN_ROW0, and a hollow up inside the hood to BASIN_ROW1. The rim is a
# URINAL_RIM-wide lip all the way round the opening.

const URINAL_H := 0.68
const URINAL_ROWS := 45
const URINAL_OPEN_ROW0 := 9     # front lip of the trough   (v = 0.2)
const URINAL_OPEN_ROW1 := 37    # edge of the hood          (v ~ 0.82)
const URINAL_BASIN_ROW0 := 4    # floor of the trough, below the lip
const URINAL_BASIN_ROW1 := 41   # top of the hollow inside the hood
const URINAL_RIM := 0.028       # thickness of the china at the rim
const URINAL_CAVITY_BACK := 0.07  # back of the bowl, out from the wall
const URINAL_SQUARENESS := 2.7  # body cross-section: 2 = ellipse, higher = boxier
const URINAL_CAVITY_SQUARENESS := 2.3
const URINAL_SIDE_COLS := 12
const URINAL_MID_COLS := 16


## Half width and depth (out from the wall) of the body at height fraction v.
static func _urinal_ab(v: float) -> Vector2:
	# Rounded bottom: width and depth ease in over the lowest 14 %.
	var k := clampf(v / 0.14, 0.0, 1.0)
	var round_bottom := sqrt(1.0 - (1.0 - k) * (1.0 - k)) * 0.6 + 0.4
	var a := (0.17 + 0.02 * sin(PI * v)) * round_bottom
	# Deepest at the trough, the front sloping back to a 0.25 m hood on top.
	var b: float
	if v < 0.3:
		b = 0.21 + 0.13 * sin(v / 0.3 * PI * 0.5)
	else:
		b = 0.34 - 0.09 * pow((v - 0.3) / 0.7, 1.3)
	return Vector2(a, b * (0.55 + 0.45 * round_bottom))


static func _v(row: int) -> float:
	return float(row) / URINAL_ROWS


## Half-angle of the front opening at height fraction v (0 outside it).
static func _urinal_open(v: float) -> float:
	var v0 := _v(URINAL_OPEN_ROW0)
	var v1 := _v(URINAL_OPEN_ROW1)
	if v < v0 - 1e-6 or v > v1 + 1e-6:
		return 0.0
	var s := clampf((v - v0) / (v1 - v0), 0.0, 1.0)
	# The rim lies where the body reaches fraction r of its depth. On a
	# superellipse z = b * cos(theta)^(2/n), so cos(theta) = r^(n/2). The
	# opening keeps 40 % of its width at the lip and the hood edge, so it has
	# straight ends with rounded corners (elliptical in s).
	var w := sqrt(maxf(0.0, 1.0 - pow((s - 0.5) / 0.5, 2.0)))
	var r := 1.0 - 0.48 * (0.4 + 0.6 * pow(w, 0.7))
	return acos(pow(r, URINAL_SQUARENESS * 0.5))


## Point on the outer body.
static func _urinal_point(v: float, theta: float) -> Vector3:
	var ab := _urinal_ab(v)
	var sn := sin(theta)
	var cs := maxf(cos(theta), 0.0)
	var e := 2.0 / URINAL_SQUARENESS
	return Vector3(ab.x * signf(sn) * pow(absf(sn), e), v * URINAL_H, ab.y * pow(cs, e))


## Outward normal of the body at (v, theta), from finite differences.
static func _urinal_normal(v: float, theta: float) -> Vector3:
	var h := 0.002
	var t := clampf(theta, -PI * 0.5 + h, PI * 0.5 - h)
	var dv := _urinal_point(v + h, t) - _urinal_point(v - h, t)
	var dt := _urinal_point(v, t + h) - _urinal_point(v, t - h)
	var n := dt.cross(dv).normalized()
	var p := _urinal_point(v, t)
	if n.dot(Vector3(p.x, 0.0, p.z + 0.001)) < 0.0:
		n = -n
	return n


## A body point pulled one china-thickness inwards (towards the wall line).
static func _urinal_inset(v: float, theta: float) -> Vector3:
	var p := _urinal_point(v, theta)
	var r := Vector2(p.x, p.z)
	var k := 1.0 - URINAL_RIM / maxf(r.length(), URINAL_RIM * 2.0)
	return Vector3(p.x * k, p.y, p.z * k)


## Rim half-angle that shapes the hollow at height v: the opening's own in the
## open rows, the lip's below them and the hood edge's above.
static func _cavity_theta(v: float) -> float:
	return _urinal_open(clampf(v, _v(URINAL_OPEN_ROW0), _v(URINAL_OPEN_ROW1)))


## The U-shaped bowl at height v. phi runs +90..-90 deg from the right-hand
## rim edge round the back to the left-hand one (the edges are inset rim
## points, so the bowl meets the lip exactly).
static func _cavity_point(v: float, phi: float) -> Vector3:
	var edge := _urinal_inset(v, _cavity_theta(v))
	var back := URINAL_CAVITY_BACK
	var sn := sin(phi)
	var cs := maxf(cos(phi), 0.0)
	var e := 2.0 / URINAL_CAVITY_SQUARENESS
	return Vector3(edge.x * signf(sn) * pow(absf(sn), e), edge.y, edge.z - (edge.z - back) * pow(cs, e))


## The body's column angles in one row: left side, opening, right side.
static func _urinal_thetas(v: float) -> Array[float]:
	var m := _urinal_open(v)
	var out: Array[float] = []
	for i in URINAL_SIDE_COLS:
		out.append(lerpf(-PI * 0.5, -m, float(i) / URINAL_SIDE_COLS))
	for i in URINAL_MID_COLS:
		out.append(lerpf(-m, m, float(i) / URINAL_MID_COLS))
	for i in URINAL_SIDE_COLS + 1:
		out.append(lerpf(m, PI * 0.5, float(i) / URINAL_SIDE_COLS))
	return out


## Wall-hung urinal. Origin on the wall face at the bowl's bottom; +Z out of
## the wall. Includes the flush valve and its pipe up the wall.
static func urinal() -> ArrayMesh:
	if _cache.has("urinal"):
		return _cache["urinal"]
	var b := _Builder.new()
	var rows: Array = []
	for r in URINAL_ROWS + 1:
		rows.append(_urinal_thetas(_v(r)))
	var mid0 := URINAL_SIDE_COLS
	var mid1 := URINAL_SIDE_COLS + URINAL_MID_COLS
	# --- Body, with the opening left out.
	for r in URINAL_ROWS:
		var va := _v(r)
		var vb := _v(r + 1)
		var open := r >= URINAL_OPEN_ROW0 and r < URINAL_OPEN_ROW1
		for c in rows[r].size() - 1:
			if open and c >= mid0 and c < mid1:
				continue
			var ts: Array[float] = [rows[r][c], rows[r][c + 1], rows[r + 1][c + 1], rows[r + 1][c]]
			var vs: Array[float] = [va, va, vb, vb]
			var ps: Array[Vector3] = []
			var ns: Array[Vector3] = []
			for k in 4:
				ps.append(_urinal_point(vs[k], ts[k]))
				ns.append(_urinal_normal(vs[k], ts[k]))
			b.quad_n("ceramic", ps, ns)
	_flat_cap(b, "ceramic_cap", rows[0], 0.0, Vector3.DOWN)
	_flat_cap(b, "ceramic_cap", rows[URINAL_ROWS], 1.0, Vector3.UP)
	# --- Rim: a china-thickness lip round the opening.
	for r in range(URINAL_OPEN_ROW0, URINAL_OPEN_ROW1):
		var va := _v(r)
		var vb := _v(r + 1)
		for c in [mid0, mid1]:
			var into := 1.0 if c == mid0 else -1.0
			var ta: float = rows[r][c]
			var tb: float = rows[r + 1][c]
			b.quad("rim", _urinal_point(va, ta), _urinal_point(vb, tb), _urinal_inset(vb, tb), _urinal_inset(va, ta), Vector3(into, 0, 0.4))
	for edge in [[URINAL_OPEN_ROW0, Vector3.UP], [URINAL_OPEN_ROW1, Vector3.DOWN]]:
		var er: int = edge[0]
		var ev := _v(er)
		for c in range(mid0, mid1):
			var ta: float = rows[er][c]
			var tb: float = rows[er][c + 1]
			b.quad("rim", _urinal_point(ev, ta), _urinal_point(ev, tb), _urinal_inset(ev, tb), _urinal_inset(ev, ta), edge[1] + Vector3(0, 0, 0.4))
	# --- The hollow: the U-shaped bowl from the trough floor to the top of
	# the hood's hollow, and the front walls that close it below the lip and
	# above the hood edge (one china-thickness behind the body).
	var phis: Array[float] = []
	for i in URINAL_MID_COLS + 1:
		phis.append(lerpf(PI * 0.5, -PI * 0.5, float(i) / URINAL_MID_COLS))
	for r in range(URINAL_BASIN_ROW0, URINAL_BASIN_ROW1):
		var va := _v(r)
		var vb := _v(r + 1)
		for i in URINAL_MID_COLS:
			var p0 := _cavity_point(va, phis[i])
			var p1 := _cavity_point(va, phis[i + 1])
			var p2 := _cavity_point(vb, phis[i + 1])
			var p3 := _cavity_point(vb, phis[i])
			var mid := (p0 + p2) * 0.5
			var front := Vector3(0.0, mid.y, _urinal_inset((va + vb) * 0.5, 0.0).z)
			b.quad("basin", p0, p1, p2, p3, front - mid)
		if r < URINAL_OPEN_ROW0 or r >= URINAL_OPEN_ROW1:
			var ma := _cavity_theta(va)
			var mb := _cavity_theta(vb)
			for i in URINAL_MID_COLS:
				var sa := float(i) / URINAL_MID_COLS
				var sb := float(i + 1) / URINAL_MID_COLS
				var q0 := _urinal_inset(va, lerpf(-ma, ma, sa))
				var q1 := _urinal_inset(va, lerpf(-ma, ma, sb))
				var q2 := _urinal_inset(vb, lerpf(-mb, mb, sb))
				var q3 := _urinal_inset(vb, lerpf(-mb, mb, sa))
				b.quad("basin", q0, q1, q2, q3, -Vector3(q0.x + q2.x, 0.0, q0.z + q2.z))
	# Trough floor (dished 1.5 cm to the drain) and the hood hollow's ceiling.
	var drain := _cavity_cap(b, "basin_floor", _v(URINAL_BASIN_ROW0), Vector3.UP, -0.015)
	_cavity_cap(b, "basin_floor", _v(URINAL_BASIN_ROW1), Vector3.DOWN, 0.01)
	b.cyl("drain", drain + Vector3(0, 0.003, 0), 0.03, 0.006, Vector3.UP, 20)
	for k in range(-2, 3):
		b.box("slot", drain + Vector3(k * 0.009, 0.0062, 0), Vector3(0.0035, 0.001, 0.044 - absf(k) * 0.008))
	# --- Flush valve: spud into the top, valve body, lever, pipe into the wall.
	var top := URINAL_H
	b.cyl("chrome", Vector3(0, top + 0.03, 0.07), 0.013, 0.06, Vector3.UP)
	b.cyl("chrome", Vector3(0, top + 0.1, 0.07), 0.028, 0.09, Vector3.UP, 20)
	b.cyl("chrome", Vector3(0.05, top + 0.11, 0.07), 0.006, 0.08, Vector3.RIGHT, 10)
	b.cyl("chrome", Vector3(0, top + 0.28, 0.07), 0.013, 0.27, Vector3.UP)
	b.cyl("chrome", Vector3(0, top + 0.415, 0.035), 0.013, 0.07, Vector3.BACK)
	b.cyl("chrome", Vector3(0, top + 0.415, 0.004), 0.03, 0.008, Vector3.BACK, 20)   # wall escutcheon
	var elbow := SphereMesh.new()
	elbow.radius = 0.0135
	elbow.height = 0.027
	elbow.radial_segments = 16
	elbow.rings = 8
	b.prim("chrome", elbow, Transform3D(Basis(), Vector3(0, top + 0.415, 0.07)))
	var mesh := b.commit(_mat, ["basin", "rim", "basin_floor", "ceramic_cap"])
	_cache["urinal"] = mesh
	return mesh


## Flat top or bottom of the body, closed along the wall.
static func _flat_cap(b: _Builder, key: String, thetas: Array, v: float, outward: Vector3) -> void:
	var centre := Vector3(0, v * URINAL_H, _urinal_ab(v).y * 0.4)
	var ring: Array[Vector3] = []
	for t in thetas:
		ring.append(_urinal_point(v, t))
	_fan_ring(b, key, centre, ring, outward)


## Floor or ceiling of the hollow at height v: the D shape of the front wall
## and the bowl. Returns the (dished) centre.
static func _cavity_cap(b: _Builder, key: String, v: float, outward: Vector3, dip: float) -> Vector3:
	var m := _cavity_theta(v)
	var ring: Array[Vector3] = []
	for i in URINAL_MID_COLS + 1:
		ring.append(_urinal_inset(v, lerpf(-m, m, float(i) / URINAL_MID_COLS)))
	for i in range(1, URINAL_MID_COLS):
		ring.append(_cavity_point(v, lerpf(PI * 0.5, -PI * 0.5, float(i) / URINAL_MID_COLS)))
	var centre := Vector3.ZERO
	for p in ring:
		centre += p
	centre = centre / ring.size() + Vector3(0, dip, 0)
	_fan_ring(b, key, centre, ring, outward)
	return centre


static func _fan_ring(b: _Builder, key: String, centre: Vector3, ring: Array[Vector3], outward: Vector3) -> void:
	for i in ring.size():
		b.tri(key, centre, ring[i], ring[(i + 1) % ring.size()], outward)


# ---------------------------------------------------------------- computer

## Flat-panel monitor without its screen face: a slim rounded bezel with a
## thicker chin, logo and power LED, a stepped rear housing, an angled neck
## and a rounded base plate. Origin on the desk under the panel, +Z toward
## the user. The screen face (0.505 x 0.285 m, centre y 0.307, z 0.012) is
## added by the builder to the shared emissive "screen" mesh so the night
## dimming in GameDirector still finds it.
static func monitor() -> ArrayMesh:
	if _cache.has("monitor"):
		return _cache["monitor"]
	var b := _Builder.new()
	var up := Basis()
	# Bezel: 9.5 mm round the top and sides, a 23 mm chin.
	b.rrect("bezel", Vector3(0, 0.30, 0.0), 0.528, 0.318, 0.018, 0.007, up)
	b.box("logo", Vector3(0, 0.152, 0.0095), Vector3(0.034, 0.005, 0.001))
	b.box("led", Vector3(0.236, 0.149, 0.0093), Vector3(0.005, 0.0025, 0.001))
	# Rear housing, stepped like a real panel's electronics bulge.
	b.rrect("plastic", Vector3(0, 0.29, -0.017), 0.44, 0.25, 0.016, 0.012, up)
	b.rrect("plastic", Vector3(0, 0.285, -0.031), 0.27, 0.16, 0.014, 0.02, up)
	b.rrect("plastic", Vector3(0, 0.27, -0.041), 0.1, 0.1, 0.008, 0.008, up)      # VESA hinge plate
	for k in [-1.0, 1.0]:
		for i in 6:
			b.box("slot", Vector3(k * (0.08 + i * 0.012), 0.36, -0.0385), Vector3(0.004, 0.035, 0.002))  # vents
	# Neck: leans back 14 deg from the base up to the hinge.
	var lean := Basis(Vector3.RIGHT, deg_to_rad(-14.0))
	b.rrect("stand", Vector3(0, 0.145, -0.075), 0.05, 0.25, 0.016, 0.006, lean)
	b.box("stand", Vector3(0, 0.27, -0.05), Vector3(0.05, 0.03, 0.016))
	# Base plate: a rounded rectangle lying flat, with a dark rubber foot ring.
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	b.rrect("stand", Vector3(0, 0.007, -0.05), 0.23, 0.17, 0.012, 0.035, flat)
	b.rrect("slot", Vector3(0, 0.0005, -0.05), 0.21, 0.15, 0.001, 0.03, flat)
	var mesh := b.commit(_mat)
	_cache["monitor"] = mesh
	return mesh


## Keyboard with stepped keycaps on a slightly tilted case, a mouse with a
## scroll wheel, and both cables running back behind the monitor. Origin on
## the desk at the keyboard's centre, +Z toward the user (the monitor's neck
## is 0.3 m behind it).
static func keyboard() -> ArrayMesh:
	if _cache.has("keyboard"):
		return _cache["keyboard"]
	var b := _Builder.new()
	# Case: rear edge 9 mm higher than the front (folded-out feet).
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(3.5))
	var origin := Vector3(0, 0.011, 0.0)
	var flat := Basis(Vector3.RIGHT, -PI * 0.5)
	b.rrect("plastic", origin, 0.445, 0.145, 0.014, 0.01, tilt * flat)
	for k in [-1.0, 1.0]:
		b.box("plastic", Vector3(k * 0.19, 0.005, -0.06), Vector3(0.03, 0.01, 0.012))   # feet
	var top := 0.007   # case top above origin
	var pitch := 0.019
	var keys: Array = []   # [x, z, width]
	var x0 := -0.205
	for row in 5:
		var z := -0.045 + row * pitch
		if row == 4:
			for c in [0, 1, 2]:
				keys.append([x0 + c * pitch + pitch * 0.5, z, 1.0])
			keys.append([x0 + 7.0 * pitch, z, 7.0])
			for c in [11, 12, 13]:
				keys.append([x0 + c * pitch + pitch * 0.5, z, 1.0])
			continue
		for c in 14:
			var wide := 1.0
			if (row == 1 and c == 0) or (row == 2 and c == 13) or (row == 3 and c == 0):
				wide = 1.4
			if wide > 1.0 and c == 13:
				keys.append([x0 + c * pitch + pitch * 0.5 - pitch * 0.2, z, wide])
			elif wide > 1.0:
				keys.append([x0 + c * pitch + pitch * 0.5 + pitch * 0.2, z, wide])
			elif not ((row == 1 and c == 1) or (row == 2 and c == 12) or (row == 3 and c == 1)):
				keys.append([x0 + c * pitch + pitch * 0.5, z, 1.0])
	for c in 12:
		keys.append([x0 + 0.02 + c * pitch + (c / 4) * 0.008, -0.066, 0.85])
	var ax := x0 + 14.6 * pitch
	keys.append([ax + pitch, -0.045 + 3 * pitch, 1.0])
	for c in 3:
		keys.append([ax + c * pitch, -0.045 + 4 * pitch, 1.0])
	var nx := ax + 3.6 * pitch
	for row in 5:
		for c in 4:
			keys.append([nx + c * pitch, -0.045 + row * pitch, 1.0])
	for k in keys:
		var w: float = k[2] * pitch - 0.0025
		var p := origin + tilt * Vector3(k[0], top, k[1])
		b.box("keycap", p + tilt * Vector3(0, 0.003, 0), Vector3(w, 0.006, 0.0165), tilt)        # skirt
		b.box("keytop", p + tilt * Vector3(0, 0.0068, 0.0005), Vector3(w - 0.0035, 0.0018, 0.0128), tilt)  # dished top
	# Mouse: a stretched dome with a scroll wheel and a button split.
	var mouse := Vector3(0.31, 0.0, 0.02)
	var shell := SphereMesh.new()
	shell.radius = 0.03
	shell.height = 0.03
	shell.is_hemisphere = true
	shell.radial_segments = 32
	shell.rings = 12
	b.prim("plastic", shell, Transform3D(Basis.from_scale(Vector3(0.95, 1.15, 1.75)), mouse))
	b.cyl("keytop", mouse + Vector3(0, 0.031, -0.014), 0.0065, 0.005, Vector3.RIGHT, 16)
	# Cables: down off the back of each device, across the desk and away
	# behind the monitor's base.
	_cable(b, [Vector3(0, 0.012, -0.073), Vector3(0, 0.003, -0.11), Vector3(0.03, 0.003, -0.22), Vector3(0.0, 0.003, -0.4)])
	_cable(b, mouse + Vector3(0, 0.008, -0.052), [Vector3(0.0, -0.005, -0.03), Vector3(-0.06, -0.005, -0.12), Vector3(-0.22, -0.005, -0.3), Vector3(-0.28, -0.005, -0.42)])
	var mesh := b.commit(_mat)
	_cache["keyboard"] = mesh
	return mesh


## A thin cable along a smooth curve through `points` (or, with `start`, through
## start + each offset).
static func _cable(b: _Builder, a, c = null) -> void:
	var pts: Array[Vector3] = []
	if c == null:
		for p in a:
			pts.append(p)
	else:
		for p in c:
			pts.append(a + p)
	var curve := Curve3D.new()
	for i in pts.size():
		var tangent := Vector3.ZERO
		if i > 0 and i < pts.size() - 1:
			tangent = (pts[i + 1] - pts[i - 1]) * 0.25
		curve.add_point(pts[i], -tangent, tangent)
	var length := curve.get_baked_length()
	var steps := maxi(6, int(length / 0.02))
	var prev := curve.sample_baked(0.0)
	for i in range(1, steps + 1):
		var cur := curve.sample_baked(length * float(i) / steps)
		b.cyl("cable", (prev + cur) * 0.5, 0.0022, prev.distance_to(cur) + 0.001, cur - prev, 8)
		prev = cur


## Front panel, drive bay, power button, ports, vents and feet for a PC tower
## of `size` (origin on the floor at its centre, +Z = front).
static func tower_details(size: Vector3) -> ArrayMesh:
	var key := "tower_%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if _cache.has(key):
		return _cache[key]
	var b := _Builder.new()
	var fz := size.z * 0.5
	b.box("plastic_light", Vector3(0, size.y * 0.5, fz + 0.006), Vector3(size.x - 0.01, size.y - 0.01, 0.012))
	var front := fz + 0.012
	b.box("slot", Vector3(0, size.y - 0.065, front + 0.001), Vector3(size.x * 0.75, 0.042, 0.003))       # optical bay
	b.box("plastic", Vector3(size.x * 0.28, size.y - 0.078, front + 0.003), Vector3(0.012, 0.005, 0.004)) # eject
	b.cyl("plastic", Vector3(0, size.y - 0.13, front + 0.003), 0.013, 0.006, Vector3.BACK, 24)              # power
	b.cyl("led", Vector3(0, size.y - 0.13, front + 0.0065), 0.004, 0.002, Vector3.BACK, 12)
	for k in [-1.0, 1.0]:
		b.box("slot", Vector3(k * 0.018, size.y - 0.175, front + 0.001), Vector3(0.014, 0.006, 0.003))      # USB
	b.cyl("slot", Vector3(0.05, size.y - 0.175, front + 0.001), 0.003, 0.003, Vector3.BACK, 10)             # audio
	var vy := 0.05
	while vy < size.y * 0.45:
		b.box("slot", Vector3(0, vy, front + 0.001), Vector3(size.x * 0.6, 0.004, 0.003))
		vy += 0.012
	# Side vent grille on both side panels.
	for sx in [-1.0, 1.0]:
		for row in 6:
			for col in 6:
				b.box("slot", Vector3(sx * (size.x * 0.5 + 0.001), size.y * 0.55 + row * 0.022, -0.06 + col * 0.022 - fz * 0.2), Vector3(0.003, 0.012, 0.012))
	var mesh := b.commit(_mat)
	_cache[key] = mesh
	return mesh
