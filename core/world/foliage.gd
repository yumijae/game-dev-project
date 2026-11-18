class_name Foliage
extends Node3D
## The vegetation around the school, grown procedurally at load time from a
## fixed seed: broadleaf (mango/acacia-like) trees on the hills, a few coconut
## palms, banana clumps and reeds along the creek, cogon grass, grass tufts,
## bushes and rocks. Every placement reads the ground from Terrain so it sits
## on whatever terrain mesh is built from the same height field.
##
## Everything is low-poly geometry with vertex colours and one sway shader
## (stronger gusts for the storm). Repeats are MultiMeshes split into spatial
## chunks so each chunk can be culled by distance; only chunks close to the
## school cast shadows. Nothing has collision except the trunks of the few
## shade trees planted on the campus pad.

const SEED: int = 4417
## Chunk sizes (m) and the distance each kind stops drawing at.
const TREE_CHUNK: float = 40.0
const SMALL_CHUNK: float = 24.0
const TREE_RANGE: float = 140.0
const BUSH_RANGE: float = 70.0
const GRASS_RANGE: float = 42.0
## Chunks whose centre is this close to the school cast shadows.
const SHADOW_RADIUS: float = 45.0
## Clear strip along the pad edge (agent C's perimeter fence).
const EDGE_STRIP: float = 3.0
## House lots across the street (Surroundings): nothing grows there.
const LOTS_HALF_X: float = 40.0
const LOTS_HALF_Z: float = 18.0
## Keep clear around the creek footbridge at x = 0.
const BRIDGE_CLEAR_X: float = 6.0

const SWAY_SHADER: String = """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform float sway = 0.3;
uniform float gust = 1.0;
uniform float translucency = 0.25;
uniform float roughness_value = 0.9;

varying float shade;

void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = COLOR.a;
	float phase = dot(origin.xz, vec2(0.13, 0.071)) + INSTANCE_CUSTOM.y * 6.2831;
	// Slow gust envelope rolling across the land, plus quicker flutter.
	float g = 0.55 + 0.45 * sin(TIME * 0.33 + origin.x * 0.025 + origin.z * 0.011);
	g = g * g * gust;
	float s = sin(TIME * 1.6 + phase) * 0.55 + sin(TIME * 2.9 + phase * 1.7) * 0.25
		+ sin(TIME * 7.1 + VERTEX.x * 3.0 + VERTEX.z * 2.0) * 0.08 * w;
	vec3 wind = normalize((vec4(normalize(vec3(1.0, 0.0, 0.35)), 0.0) * MODEL_MATRIX).xyz);
	VERTEX += wind * w * sway * (0.25 + g) * (0.65 + s);
	VERTEX.y -= w * w * sway * 0.12 * g;
	shade = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec3 c = COLOR.rgb * shade;
	ALBEDO = c;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
	BACKLIGHT = c * translucency;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
"""

var _rng := RandomNumberGenerator.new()
var _cluster := FastNoiseLite.new()
var _bumps := FastNoiseLite.new()
var _ico_verts := PackedVector3Array()
var _ico_faces := PackedInt32Array()
var _sway_mat: ShaderMaterial
var _stiff_mat: ShaderMaterial
var _rock_mat: StandardMaterial3D
## Instance counts per kind, for tests.
var counts: Dictionary = {}


func _ready() -> void:
	_rng.seed = SEED
	_cluster.seed = SEED
	_cluster.frequency = 0.035
	_bumps.seed = SEED + 1
	_bumps.frequency = 1.6
	_build_ico()
	var shader := Shader.new()
	shader.code = SWAY_SHADER
	_sway_mat = ShaderMaterial.new()
	_sway_mat.shader = shader
	_stiff_mat = ShaderMaterial.new()
	_stiff_mat.shader = shader
	_stiff_mat.set_shader_parameter("sway", 0.12)
	_stiff_mat.set_shader_parameter("translucency", 0.1)
	_rock_mat = StandardMaterial3D.new()
	_rock_mat.vertex_color_use_as_albedo = true
	_rock_mat.roughness = 0.95
	_grow()


# ------------------------------------------------------------------ placement

func _grow() -> void:
	var broad: Array[Mesh] = [_broadleaf_mesh(0), _broadleaf_mesh(1), _broadleaf_mesh(2)]
	var palm: Mesh = _palm_mesh()
	var banana: Mesh = _banana_mesh()
	var tuft: Mesh = _grass_mesh(7, 0.32, 0.55, Color(0.2, 0.32, 0.1), Color(0.42, 0.5, 0.2))
	var cogon: Mesh = _grass_mesh(9, 0.85, 1.35, Color(0.32, 0.36, 0.16), Color(0.62, 0.6, 0.38))
	var reed: Mesh = _grass_mesh(6, 1.3, 1.9, Color(0.18, 0.28, 0.1), Color(0.36, 0.42, 0.2))
	var bush: Mesh = _bush_mesh()
	var rock: Mesh = _rock_mesh()

	var trees: Array = [[], [], []]
	var palms: Array = []
	var bananas: Array = []
	# Trees: jittered grid, thicker on the hills and in clumps.
	var step := 6.5
	var e: float = Terrain.EXTENT - 3.0
	var x := -e
	while x <= e:
		var z := -e
		while z <= e:
			var px: float = x + _rng.randf_range(-2.8, 2.8)
			var pz: float = z + _rng.randf_range(-2.8, 2.8)
			z += step
			var d: float = Terrain.pad_distance(px, pz)
			if d < EDGE_STRIP + 4.0 or _blocked(px, pz, 2.5):
				continue
			var creek: float = absf(pz - Terrain.CREEK_Z)
			if creek < Terrain.CREEK_HALF_WIDTH + 2.5:
				continue
			var p: float = smoothstep(EDGE_STRIP + 4.0, 30.0, d) * (0.45 + 0.55 * clampf(_cluster.get_noise_2d(px, pz) + 0.5, 0.0, 1.0))
			if _rng.randf() > p:
				continue
			var roll: float = _rng.randf()
			if creek < 18.0 and roll < 0.45:
				bananas.append(_place(px, pz, 0.85, 1.25, 0.1))
			elif roll < (0.55 if creek < 18.0 else 0.1):
				palms.append(_place(px, pz, 0.85, 1.15, 0.15, true))
			else:
				trees[_rng.randi() % 3].append(_place(px, pz, 0.75, 1.3, 0.2))
		x += step
	# Planted shade trees on the campus lawns (trunks are solid).
	var shade_spots: Array[Vector2] = [
		Vector2(-19.0, 3.5), Vector2(19.0, 3.5), Vector2(-19.0, -12.5), Vector2(19.0, -12.5),
		Vector2(-6.0, Campus.Z_MIN - 5.0), Vector2(6.0, Campus.Z_MIN - 5.0)]
	var shade_trees: Array = []
	for s in shade_spots:
		var xf: Transform3D = _place(s.x, s.y, 0.8, 0.9, 0.2)
		shade_trees.append(xf)
		_trunk_collider(xf.origin)

	for i in 3:
		_scatter("BroadleafTrees%d" % i, broad[i], trees[i], TREE_CHUNK, TREE_RANGE, true)
	_scatter("ShadeTrees", broad[0], shade_trees, TREE_CHUNK, TREE_RANGE, true)
	_scatter("CoconutPalms", palm, palms, TREE_CHUNK, TREE_RANGE, true)
	_scatter("Bananas", banana, bananas, TREE_CHUNK, BUSH_RANGE, true)

	# Ground cover.
	var tufts: Array = []
	var cogons: Array = []
	var bushes: Array = []
	var reeds: Array = []
	var rocks: Array = []
	var span_x: float = Terrain.PAD_X + 60.0
	for i in 32000:
		var px: float = _rng.randf_range(-span_x, span_x)
		var pz: float = _rng.randf_range(Terrain.PAD_Z_MIN - 60.0, Terrain.PAD_Z_MAX + 60.0)
		var d: float = Terrain.pad_distance(px, pz)
		if d < EDGE_STRIP + 0.5 or d > 58.0 or _blocked(px, pz, 0.0) or Terrain.is_creek(px, pz):
			continue
		if _cluster.get_noise_2d(px * 2.0, pz * 2.0) < -0.25:
			continue
		tufts.append(_place(px, pz, 0.7, 1.3, 0.04))
	for i in 9000:
		var px: float = _rng.randf_range(-Terrain.EXTENT + 3.0, Terrain.EXTENT - 3.0)
		var pz: float = _rng.randf_range(-Terrain.EXTENT + 3.0, Terrain.EXTENT - 3.0)
		var d: float = Terrain.pad_distance(px, pz)
		if d < 9.0 or _blocked(px, pz, 0.0) or absf(pz - Terrain.CREEK_Z) < Terrain.CREEK_HALF_WIDTH + 1.0:
			continue
		if _cluster.get_noise_2d(px + 300.0, pz) < 0.15:
			continue
		cogons.append(_place(px, pz, 0.75, 1.25, 0.05))
	for i in 2600:
		var px: float = _rng.randf_range(-Terrain.EXTENT + 3.0, Terrain.EXTENT - 3.0)
		var pz: float = _rng.randf_range(-Terrain.EXTENT + 3.0, Terrain.EXTENT - 3.0)
		var d: float = Terrain.pad_distance(px, pz)
		if d < EDGE_STRIP + 1.5 or d > 75.0 or _blocked(px, pz, 1.0) or Terrain.is_creek(px, pz):
			continue
		if _cluster.get_noise_2d(px, pz + 500.0) < 0.0:
			continue
		bushes.append(_place(px, pz, 0.7, 1.4, 0.12))
	# Reeds and rocks along both creek banks.
	for i in 1500:
		var px: float = _rng.randf_range(-Terrain.EXTENT + 3.0, Terrain.EXTENT - 3.0)
		if absf(px) < BRIDGE_CLEAR_X:
			continue
		var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
		var pz: float = Terrain.CREEK_Z + side * (Terrain.CREEK_HALF_WIDTH + _rng.randf_range(0.1, 2.4))
		if _blocked(px, pz, 0.0) or Terrain.pad_distance(px, pz) < EDGE_STRIP:
			continue
		reeds.append(_place(px, pz, 0.8, 1.2, 0.05))
	for i in 420:
		var px: float = _rng.randf_range(-Terrain.EXTENT + 3.0, Terrain.EXTENT - 3.0)
		var pz: float
		if i % 2 == 0:
			if absf(px) < BRIDGE_CLEAR_X:
				continue
			var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
			pz = Terrain.CREEK_Z + side * (Terrain.CREEK_HALF_WIDTH + _rng.randf_range(-0.6, 1.6))
		else:
			pz = _rng.randf_range(-Terrain.EXTENT + 3.0, Terrain.EXTENT - 3.0)
			if Terrain.pad_distance(px, pz) < 10.0:
				continue
		if _blocked(px, pz, 0.5) or Terrain.pad_distance(px, pz) < EDGE_STRIP:
			continue
		var xf: Transform3D = _place(px, pz, 0.35, 1.6, 0.0)
		xf.basis = Basis(Vector3(_rng.randf(), 1.0, _rng.randf()).normalized(), _rng.randf() * TAU) * Basis.from_scale(Vector3(1.0, _rng.randf_range(0.5, 0.9), 1.0)) * Basis.from_scale(Vector3.ONE * xf.basis.get_scale().x)
		xf.origin.y -= 0.15 * xf.basis.get_scale().y
		rocks.append(xf)

	_scatter("GrassTufts", tuft, tufts, SMALL_CHUNK, GRASS_RANGE, false)
	_scatter("CogonGrass", cogon, cogons, SMALL_CHUNK, BUSH_RANGE, false)
	_scatter("Bushes", bush, bushes, SMALL_CHUNK, BUSH_RANGE, false)
	_scatter("Reeds", reed, reeds, SMALL_CHUNK, BUSH_RANGE, false)
	_scatter("Rocks", rock, rocks, SMALL_CHUNK, BUSH_RANGE, false)


## Areas nothing may grow in: the street and its verges everywhere, the
## house lots across the street, the edge of the world.
func _blocked(x: float, z: float, margin: float) -> bool:
	var e: float = Terrain.EXTENT - 2.0 - margin
	if absf(x) > e or absf(z) > e:
		return true
	var sz: float = absf(z - Terrain.STREET_Z)
	if sz < Terrain.STREET_WIDTH * 0.5 + 4.0 + margin:
		return true
	if sz < LOTS_HALF_Z + margin and absf(x) < LOTS_HALF_X + margin:
		return true
	if absf(x) < BRIDGE_CLEAR_X + margin and absf(z - Terrain.CREEK_Z) < Terrain.CREEK_HALF_WIDTH + 4.0:
		return true
	return false


## A random upright transform on the ground at (x, z), sunk `sink` metres so
## it never floats where the terrain mesh cuts below the true height.
func _place(x: float, z: float, s0: float, s1: float, sink: float, lean: bool = false) -> Transform3D:
	var s: float = _rng.randf_range(s0, s1)
	var basis := Basis(Vector3.UP, _rng.randf() * TAU)
	if lean:
		basis = Basis(Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)).normalized(), _rng.randf_range(0.02, 0.12)) * basis
	basis = basis * Basis.from_scale(Vector3.ONE * s)
	return Transform3D(basis, Vector3(x, Terrain.height(x, z) - sink * s, z))


func _trunk_collider(at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "ShadeTreeTrunk"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.28
	cyl.height = 3.0
	shape.shape = cyl
	shape.position.y = 1.5
	body.add_child(shape)
	add_child(body)
	body.global_position = at


## Buckets transforms into chunks and makes one MultiMeshInstance per chunk.
func _scatter(label: String, mesh: Mesh, xforms: Array, chunk: float, range_end: float, shadows: bool) -> void:
	counts[label] = xforms.size()
	if xforms.is_empty():
		return
	var buckets: Dictionary = {}
	for xf: Transform3D in xforms:
		var key := Vector2i(floori(xf.origin.x / chunk), floori(xf.origin.z / chunk))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(xf)
	var group := Node3D.new()
	group.name = label
	add_child(group)
	for key: Vector2i in buckets:
		var list: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_custom_data(i, Color(_rng.randf_range(0.75, 1.12), _rng.randf(), 0.0, 0.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var centre := Vector2((key.x + 0.5) * chunk, (key.y + 0.5) * chunk)
		mmi.visibility_range_end = range_end
		mmi.visibility_range_end_margin = range_end * 0.12
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var near: bool = centre.length() < SHADOW_RADIUS + chunk * 0.7
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (shadows and near) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		group.add_child(mmi)


# --------------------------------------------------------------------- meshes

## Broadleaf tree ~6-8 m: a leaning, forking trunk under a wide crown of
## lumpy leaf clusters (mango / acacia silhouette). Three variants.
func _broadleaf_mesh(variant: int) -> Mesh:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 100 + variant
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bark := Color(0.2, 0.15, 0.1, 0.0)
	var fork := Vector3(r.randf_range(-0.3, 0.3), r.randf_range(2.2, 2.9), r.randf_range(-0.3, 0.3))
	_tube(st, [Vector3(0, -0.3, 0), Vector3(fork.x * 0.4, fork.y * 0.5, fork.z * 0.4), fork], [0.32, 0.26, 0.2], 7, bark, [0.0, 0.02, 0.06])
	var crown_y: float = fork.y + r.randf_range(2.0, 2.8)
	var width: float = [3.4, 2.8, 3.8][variant]
	var blobs: int = [7, 6, 8][variant]
	for i in blobs:
		var a: float = TAU * float(i) / blobs + r.randf_range(-0.3, 0.3)
		var rad: float = width * r.randf_range(0.35, 0.8)
		var c := Vector3(cos(a) * rad, crown_y + r.randf_range(-0.7, 0.7) - rad * 0.15, sin(a) * rad)
		# A branch out to each outer cluster.
		_tube(st, [fork, fork.lerp(c, 0.55) + Vector3.UP * 0.4, c - Vector3.UP * 0.5], [0.13, 0.09, 0.05], 5, bark, [0.06, 0.15, 0.3])
		_blob(st, c, Vector3(r.randf_range(1.4, 2.0), r.randf_range(0.9, 1.3), r.randf_range(1.4, 2.0)), _leaf_colour(r), 0.55, r)
	_blob(st, Vector3(0, crown_y + 0.8, 0), Vector3(width * 0.55, 1.4, width * 0.55), _leaf_colour(r), 0.6, r)
	return _commit(st, _sway_mat)


## Coconut palm ~7-9 m: a curved ringed trunk, a crown of drooping fronds and
## a few coconuts.
func _palm_mesh() -> Mesh:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 200
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array = []
	var radii: Array = []
	var ws: Array = []
	var h := 8.0
	for i in 9:
		var t: float = float(i) / 8.0
		pts.append(Vector3(sin(t * 1.4) * 1.3, -0.3 + t * h, 0.0))
		radii.append(lerpf(0.24, 0.15, t))
		ws.append(t * t * 0.25)
	_tube(st, pts, radii, 7, Color(0.3, 0.26, 0.2, 0.0), ws)
	var top: Vector3 = pts[8]
	for i in 11:
		var a: float = TAU * float(i) / 11.0 + r.randf_range(-0.15, 0.15)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var length: float = r.randf_range(3.2, 4.0)
		var rise: float = r.randf_range(0.6, 1.2)
		var fp: Array = []
		var fw: Array = []
		var fwt: Array = []
		for k in 9:
			var t: float = float(k) / 8.0
			fp.append(top + dir * (t * length) + Vector3.UP * (rise * sin(t * PI * 0.8) - t * t * 1.9))
			fw.append(sin(t * PI) * 0.55 + 0.05)
			fwt.append(0.3 + t * 0.7)
		_strip(st, fp, fw, Vector3(-dir.z, 0, dir.x), Color(0.2, 0.32, 0.12), fwt, 0.18)
	for i in 4:
		var a: float = TAU * float(i) / 4.0
		_blob(st, top + Vector3(cos(a) * 0.28, -0.35, sin(a) * 0.28), Vector3(0.18, 0.2, 0.18), Color(0.28, 0.24, 0.1), 0.25, r)
	return _commit(st, _sway_mat)


## Banana clump ~2.5-3.5 m: a few pseudo-stems with big arching paddle leaves.
func _banana_mesh() -> Mesh:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 300
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in 4:
		var base := Vector3(r.randf_range(-0.5, 0.5), -0.2, r.randf_range(-0.5, 0.5))
		var h: float = r.randf_range(1.5, 2.4)
		var top := base + Vector3(r.randf_range(-0.2, 0.2), h, r.randf_range(-0.2, 0.2))
		_tube(st, [base, base.lerp(top, 0.5), top], [0.13, 0.11, 0.08], 6, Color(0.3, 0.36, 0.16, 0.0), [0.0, 0.1, 0.2])
		for i in 5:
			var a: float = r.randf() * TAU
			var dir := Vector3(cos(a), 0.0, sin(a))
			var length: float = r.randf_range(1.5, 2.1)
			var fp: Array = []
			var fw: Array = []
			var fwt: Array = []
			for k in 7:
				var t: float = float(k) / 6.0
				fp.append(top + dir * (t * length) + Vector3.UP * (0.9 * sin(t * PI * 0.7) - t * t * 0.8))
				fw.append(sin(t * PI) * 0.32 + 0.03)
				fwt.append(0.35 + t * 0.65)
			_strip(st, fp, fw, Vector3(-dir.z, 0, dir.x), Color(0.24, 0.4, 0.14), fwt, 0.05)
	return _commit(st, _sway_mat)


## A tuft of `blades` blades between h0 and h1 metres tall.
func _grass_mesh(blades: int, h0: float, h1: float, base: Color, tip: Color) -> Mesh:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 400 + blades
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var a: float = r.randf() * TAU
		var out := Vector3(cos(a), 0.0, sin(a))
		var root := out * r.randf_range(0.0, 0.12)
		var h: float = r.randf_range(h0, h1)
		var lean: float = r.randf_range(0.1, 0.35) * h
		var side := Vector3(-out.z, 0.0, out.x) * r.randf_range(0.025, 0.045) * (1.0 + h * 0.3)
		var mid := root + out * lean * 0.35 + Vector3.UP * h * 0.55
		var top := root + out * lean + Vector3.UP * h
		var cb := Color(base.r, base.g, base.b, 0.0)
		var cm := Color(lerpf(base.r, tip.r, 0.5), lerpf(base.g, tip.g, 0.5), lerpf(base.b, tip.b, 0.5), 0.35)
		var ct := Color(tip.r, tip.g, tip.b, 1.0)
		_quad(st, root - side, root + side, mid + side * 0.7, mid - side * 0.7, cb, cb, cm, cm)
		_tri(st, mid - side * 0.7, mid + side * 0.7, top, cm, cm, ct)
	return _commit(st, _sway_mat)


## Low shrub: a few leaf clusters hugging the ground.
func _bush_mesh() -> Mesh:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 500
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: float = TAU * float(i) / 4.0 + r.randf_range(-0.4, 0.4)
		var c := Vector3(cos(a) * 0.35, r.randf_range(0.35, 0.6), sin(a) * 0.35)
		_blob(st, c, Vector3(r.randf_range(0.45, 0.65), r.randf_range(0.35, 0.5), r.randf_range(0.45, 0.65)), _leaf_colour(r) * 0.9, 0.25, r)
	return _commit(st, _stiff_mat)


func _rock_mesh() -> Mesh:
	var r := RandomNumberGenerator.new()
	r.seed = SEED + 600
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blob(st, Vector3(0, 0.25, 0), Vector3(0.55, 0.4, 0.45), Color(0.36, 0.34, 0.31), 0.0, r, 0.35)
	return _commit(st, _rock_mat)


func _leaf_colour(r: RandomNumberGenerator) -> Color:
	return Color(r.randf_range(0.1, 0.16), r.randf_range(0.22, 0.3), r.randf_range(0.07, 0.11))


func _commit(st: SurfaceTool, mat: Material) -> Mesh:
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


# ------------------------------------------------------------ mesh primitives

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri(st, a, b, c, ca, cb, cc)
	_tri(st, a, c, d, ca, cc, cd)


## Tapered tube through `points`; `weights` is the sway weight (COLOR.a) at
## each ring.
func _tube(st: SurfaceTool, points: Array, radii: Array, sides: int, colour: Color, weights: Array) -> void:
	var rings: Array = []
	for i in points.size():
		var p: Vector3 = points[i]
		var nxt: Vector3 = points[mini(i + 1, points.size() - 1)]
		var prv: Vector3 = points[maxi(i - 1, 0)]
		var axis: Vector3 = (nxt - prv).normalized()
		var u: Vector3 = axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
		var v: Vector3 = axis.cross(u)
		var ring: Array = []
		for s in sides:
			var a: float = TAU * float(s) / sides
			ring.append(p + (u * cos(a) + v * sin(a)) * float(radii[i]))
		rings.append(ring)
	for i in rings.size() - 1:
		var c0 := Color(colour.r, colour.g, colour.b, float(weights[i]))
		var c1 := Color(colour.r * 1.08, colour.g * 1.08, colour.b * 1.08, float(weights[i + 1]))
		for s in sides:
			var s2: int = (s + 1) % sides
			_quad(st, rings[i][s], rings[i][s2], rings[i + 1][s2], rings[i + 1][s], c0, c0, c1, c1)


## Leaf strip (frond / blade) along `points`, `widths` across `side`, folded
## down by `fold` along its rib.
func _strip(st: SurfaceTool, points: Array, widths: Array, side: Vector3, colour: Color, weights: Array, fold: float) -> void:
	for i in points.size() - 1:
		var p0: Vector3 = points[i]
		var p1: Vector3 = points[i + 1]
		var w0: float = widths[i]
		var w1: float = widths[i + 1]
		var d0 := Vector3.DOWN * fold * w0
		var d1 := Vector3.DOWN * fold * w1
		var c0 := Color(colour.r, colour.g, colour.b, float(weights[i]))
		var c1 := Color(colour.r * 1.1, colour.g * 1.1, colour.b * 1.05, float(weights[i + 1]))
		var e0 := Color(colour.r * 0.85, colour.g * 0.85, colour.b * 0.85, float(weights[i]))
		var e1 := Color(colour.r * 0.9, colour.g * 0.9, colour.b * 0.9, float(weights[i + 1]))
		_quad(st, p0, p0 + side * w0 + d0, p1 + side * w1 + d1, p1, c0, e0, e1, c1)
		_quad(st, p0 - side * w0 + d0, p0, p1, p1 - side * w1 + d1, e0, c0, c1, e1)


## Lumpy ellipsoid (leaf cluster, coconut, rock) from a noise-bumped
## icosphere, lighter on top.
func _blob(st: SurfaceTool, centre: Vector3, radius: Vector3, colour: Color, weight: float, r: RandomNumberGenerator, bump: float = 0.28) -> void:
	var offset := Vector3(r.randf() * 50.0, r.randf() * 50.0, r.randf() * 50.0)
	var pts := PackedVector3Array()
	var cols: Array[Color] = []
	for v: Vector3 in _ico_verts:
		var k: float = 1.0 + bump * _bumps.get_noise_3dv(v * 1.3 + offset)
		pts.append(centre + v * radius * k)
		var light: float = 0.8 + 0.3 * (v.y * 0.5 + 0.5)
		cols.append(Color(colour.r * light, colour.g * light, colour.b * light, weight * (0.6 + 0.4 * (v.y * 0.5 + 0.5))))
	for f in range(0, _ico_faces.size(), 3):
		var a: int = _ico_faces[f]
		var b: int = _ico_faces[f + 1]
		var c: int = _ico_faces[f + 2]
		_tri(st, pts[a], pts[b], pts[c], cols[a], cols[b], cols[c])


## Unit icosphere, one subdivision (42 vertices, 80 faces).
func _build_ico() -> void:
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces: Array[int] = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2,
		10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	var mids: Dictionary = {}
	var out: Array[int] = []
	for f in range(0, faces.size(), 3):
		var tri: Array[int] = [faces[f], faces[f + 1], faces[f + 2]]
		var m: Array[int] = []
		for k in 3:
			var a: int = tri[k]
			var b: int = tri[(k + 1) % 3]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not mids.has(key):
				verts.append(((verts[a] + verts[b]) * 0.5).normalized())
				mids[key] = verts.size() - 1
			m.append(mids[key])
		out.append_array([tri[0], m[0], m[2], tri[1], m[1], m[0], tri[2], m[2], m[1], m[0], m[1], m[2]])
	_ico_verts = PackedVector3Array(verts)
	_ico_faces = PackedInt32Array(out)
