extends Node3D
## The neighbourhood around the school, built once at runtime (deterministic):
##
##   * the campus perimeter - a low concrete wall with a painted iron fence on
##     top around the flat pad, open at the front walkway with the sliding
##     gate pushed aside (the Rehas grille at the entrance is the real gate)
##   * across the street: a sidewalk and a row of modest houses and shops
##     (sari-sari store, two-storey concrete houses, a shuttered carinderia),
##     mostly dark, a couple of warm windows
##   * utility poles with sagging wires and sodium street lamps (one flickers,
##     one is dead), a parked tricycle
##   * behind the school: a concrete footbridge over the creek and a few
##     shanties beyond it
##   * far off on the hills: house silhouettes, a water tower and a cell tower
##     with a slow red beacon
##
## Everything is merged into a handful of meshes per material; only the
## perimeter has collision (layer 1). Ground heights come from Terrain.

const SEED: int = 7731
const LAYER_WORLD: int = 1
## Front fence line, just behind the street's near edge.
const FENCE_FRONT_Z: float = Campus.Z_MAX + 7.5
## Half width of the opening in the front fence (the walkway to the doors).
const GATE_HALF: float = 4.5
const WALL_H: float = 1.0
const FENCE_H: float = 2.2
## Far side of the street.
const FAR_EDGE_Z: float = Terrain.STREET_Z + Terrain.STREET_WIDTH * 0.5
const SIDEWALK_W: float = 2.2
const HOUSE_FRONT_Z: float = FAR_EDGE_Z + SIDEWALK_W + 0.6
const ROW_X: float = 38.0
const SODIUM: Color = Color(1.0, 0.6, 0.27)
const FAR_RANGE: float = 160.0

var _rng := RandomNumberGenerator.new()
var _mats: Dictionary = {}
## group ("near"/"far") -> material key -> SurfaceTool
var _tools: Dictionary = {}
var _body: StaticBody3D = null
var _flicker_light: OmniLight3D = null
var _flicker_bulb: StandardMaterial3D = null
var _flicker_t: float = 0.0
var _beacon: StandardMaterial3D = null
var _time: float = 0.0


func _ready() -> void:
	_rng.seed = SEED
	_make_materials()
	_body = StaticBody3D.new()
	_body.name = "PerimeterCollision"
	_body.collision_layer = LAYER_WORLD
	_body.collision_mask = 0
	add_child(_body)
	_build_perimeter()
	_build_far_sidewalk()
	_build_house_row()
	_build_poles_and_lamps()
	_build_tricycle(Vector3(-7.5, 0.0, FAR_EDGE_Z - 0.9))
	_build_footbridge(7.0)
	_build_shanties()
	_build_far_silhouettes()
	_commit()


func _process(delta: float) -> void:
	_time += delta
	if _flicker_light != null:
		_flicker_t -= delta
		if _flicker_t <= 0.0:
			# Mostly on, with stuttering drop-outs like a dying sodium tube.
			var on: bool = _rng.randf() > 0.3
			_flicker_light.light_energy = 1.1 if on else 0.05
			_flicker_bulb.emission_energy_multiplier = 3.0 if on else 0.2
			_flicker_t = _rng.randf_range(0.04, 0.18) if _rng.randf() < 0.6 else _rng.randf_range(0.8, 3.5)
	if _beacon != null:
		_beacon.emission_energy_multiplier = 6.0 * maxf(sin(_time * 1.6), 0.0)


# ------------------------------------------------------------------ materials

func _make_materials() -> void:
	var index: Dictionary = {}
	var path := "res://textures/polyhaven/index.json"
	if FileAccess.file_exists(path):
		index = JSON.parse_string(FileAccess.get_file_as_string(path))
	_mats["concrete"] = _pbr(index, "grey_plaster", Color(0.72, 0.72, 0.7))
	_mats["sidewalk"] = _pbr(index, "concrete_pavement", Color(0.75, 0.75, 0.73))
	_mats["wall"] = _pbr(index, "white_stucco", Color(0.86, 0.85, 0.8))
	# Pastel paints of provincial houses, gone chalky.
	_mats["paint_green"] = _pbr(index, "white_stucco", Color(0.66, 0.78, 0.66))
	_mats["paint_peach"] = _pbr(index, "white_stucco", Color(0.9, 0.74, 0.6))
	_mats["paint_blue"] = _pbr(index, "white_stucco", Color(0.62, 0.72, 0.82))
	_mats["paint_yellow"] = _pbr(index, "white_stucco", Color(0.9, 0.84, 0.58))
	_mats["wood"] = _pbr(index, "plywood", Color(0.62, 0.5, 0.38))
	_mats["roof"] = _corrugated(Color(0.42, 0.4, 0.37), 0.55)
	_mats["roof_rust"] = _corrugated(Color(0.42, 0.26, 0.17), 0.8)
	_mats["iron"] = _flat(Color(0.12, 0.2, 0.15), 0.4, 0.55)
	_mats["dark_metal"] = _flat(Color(0.08, 0.08, 0.09), 0.5, 0.5)
	_mats["glass"] = _flat(Color(0.03, 0.035, 0.045), 0.0, 0.15)
	_mats["wire"] = _flat(Color(0.02, 0.02, 0.02), 0.0, 0.8)
	_mats["tarp"] = _flat(Color(0.12, 0.25, 0.5), 0.0, 0.7)
	_mats["sign_red"] = _flat(Color(0.55, 0.08, 0.06), 0.0, 0.6)
	_mats["bamboo"] = _flat(Color(0.45, 0.38, 0.22), 0.0, 0.85)
	_mats["silhouette"] = _flat(Color(0.05, 0.055, 0.065), 0.0, 1.0)
	_mats["lit"] = _emissive(Color(1.0, 0.72, 0.4), 2.2)
	_mats["tv"] = _emissive(Color(0.45, 0.6, 1.0), 1.4)
	_mats["bulb"] = _emissive(SODIUM, 3.0)
	_mats["bulb_dead"] = _flat(Color(0.25, 0.22, 0.18), 0.0, 0.3)
	_flicker_bulb = _emissive(SODIUM, 3.0)
	_mats["bulb_flicker"] = _flicker_bulb
	_beacon = _emissive(Color(1.0, 0.05, 0.03), 6.0)
	_mats["beacon"] = _beacon


func _pbr(index: Dictionary, asset: String, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = 0.9
	var e: Dictionary = index.get(asset, {})
	if e.is_empty():
		return m
	m.albedo_texture = load(e.maps.diff)
	m.normal_enabled = true
	m.normal_texture = load(e.maps.nor_gl)
	m.roughness_texture = load(e.maps.rough)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var s: float = 1.0 / float(e.size_m[0])
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(s, s, s)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _flat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	return m


## Galvanised iron sheet: a procedural ridged normal map, world triplanar.
func _corrugated(c: Color, rough: float) -> StandardMaterial3D:
	var w := 64
	var img := Image.create(w, 4, false, Image.FORMAT_RGB8)
	for x in w:
		var slope: float = cos(TAU * float(x) / float(w)) * 0.7
		var n := Vector3(-slope, 0.0, 1.0).normalized()
		for y in 4:
			img.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))
	img.generate_mipmaps()
	var m := _flat(c, 0.55, rough)
	m.normal_enabled = true
	m.normal_texture = ImageTexture.create_from_image(img)
	m.normal_scale = 1.0
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(1.0 / 0.076, 1.0 / 0.076, 1.0 / 0.076)  # 7.6 cm corrugation pitch
	return m


# ----------------------------------------------------------------- geometry

func _st(group: String, key: String) -> SurfaceTool:
	if not _tools.has(group):
		_tools[group] = {}
	var g: Dictionary = _tools[group]
	if not g.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		g[key] = st
	return g[key]


## Box centred at `c`, size `s`, turned `yaw` radians about Y.
func box(key: String, c: Vector3, s: Vector3, yaw: float = 0.0, group: String = "near") -> void:
	_box_xf(key, Transform3D(Basis(Vector3.UP, yaw), c), s, group)


func _box_xf(key: String, xf: Transform3D, s: Vector3, group: String = "near") -> void:
	var h := s * 0.5
	var st := _st(group, key)
	# Six faces, outward normals.
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c: Vector3 = n * h
		var hu: Vector3 = u * absf(u.dot(h))
		var hv: Vector3 = v * absf(v.dot(h))
		var p := [c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv]
		var wn: Vector3 = (xf.basis * n).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(wn)
			st.add_vertex(xf * (p[i] as Vector3))


## Thin bar from `a` to `b` (wires, poles, legs, rails).
func bar(key: String, a: Vector3, b: Vector3, thick: float, group: String = "near") -> void:
	var d := b - a
	var length: float = d.length()
	if length < 0.001:
		return
	var y := d / length
	var x := y.cross(Vector3.UP) if absf(y.dot(Vector3.UP)) < 0.99 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	_box_xf(key, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(thick, length, thick), group)


## Gable roof: ridge along local X, eaves at `y`, ridge `rise` higher.
func gable(key: String, c: Vector3, w: float, d: float, rise: float, yaw: float = 0.0, group: String = "near") -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw), c)
	var hw := w * 0.5
	var hd := d * 0.5
	var ridge_a := Vector3(-hw, rise, 0.0)
	var ridge_b := Vector3(hw, rise, 0.0)
	var st := _st(group, key)
	for side in [-1.0, 1.0]:
		var e_a := Vector3(-hw, 0.0, hd * side)
		var e_b := Vector3(hw, 0.0, hd * side)
		var n: Vector3 = (xf.basis * Vector3(0.0, hd, rise * side)).normalized()
		var tri := [e_a, e_b, ridge_b, e_a, ridge_b, ridge_a] if side > 0.0 else [e_a, ridge_b, e_b, e_a, ridge_a, ridge_b]
		for p in tri:
			st.set_normal(n)
			st.add_vertex(xf * (p as Vector3))
		# A thin underside so the roof is not paper from below.
	for side in [-1.0, 1.0]:
		var n2: Vector3 = (xf.basis * Vector3(side, 0.0, 0.0)).normalized()
		var g := [Vector3(hw * side, 0.0, -hd), Vector3(hw * side, 0.0, hd), Vector3(hw * side, rise, 0.0)]
		var order := [0, 2, 1] if side > 0.0 else [0, 1, 2]
		for i in order:
			st.set_normal(n2)
			st.add_vertex(xf * (g[i] as Vector3))


func _collider(c: Vector3, s: Vector3, yaw: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = s
	cs.shape = shape
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), c)
	_body.add_child(cs)


func _commit() -> void:
	for group in _tools:
		var g: Dictionary = _tools[group]
		for key in g:
			var st: SurfaceTool = g[key]
			var mesh: ArrayMesh = st.commit()
			if mesh == null or mesh.get_surface_count() == 0:
				continue
			mesh.surface_set_material(0, _mats[key])
			var mi := MeshInstance3D.new()
			mi.name = "%s_%s" % [group, key]
			mi.mesh = mesh
			if group == "far":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = FAR_RANGE
			elif key in ["wire", "bulb", "bulb_dead", "bulb_flicker", "lit", "tv", "beacon"]:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
	_tools.clear()


func _ground(x: float, z: float) -> float:
	return Terrain.height(x, z)


# ----------------------------------------------------------------- perimeter

## Low concrete wall with an iron fence on top from `a` to `b` (on the pad,
## so y = 0), pilasters every ~3 m, collision up to the fence top.
func _fence_run(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length: float = d.length()
	var dir := d / length
	var yaw: float = atan2(-dir.z, dir.x)
	var mid := (a + b) * 0.5
	box("wall", mid + Vector3(0, WALL_H * 0.5, 0), Vector3(length, WALL_H, 0.22), yaw)
	box("concrete", mid + Vector3(0, WALL_H + 0.03, 0), Vector3(length + 0.1, 0.06, 0.3), yaw)
	box("iron", mid + Vector3(0, FENCE_H - 0.05, 0), Vector3(length, 0.05, 0.05), yaw)
	box("iron", mid + Vector3(0, WALL_H + 0.25, 0), Vector3(length, 0.04, 0.04), yaw)
	var bars: int = int(length / 0.16)
	for i in bars:
		var p := a + dir * (float(i) + 0.5) * (length / float(bars))
		bar("iron", p + Vector3(0, WALL_H + 0.06, 0), p + Vector3(0, FENCE_H + 0.06, 0), 0.025)
	var posts: int = maxi(1, int(round(length / 3.0)))
	for i in posts + 1:
		var p := a + dir * float(i) * (length / float(posts))
		box("wall", p + Vector3(0, (FENCE_H + 0.15) * 0.5, 0), Vector3(0.34, FENCE_H + 0.15, 0.34), yaw)
		box("concrete", p + Vector3(0, FENCE_H + 0.2, 0), Vector3(0.42, 0.08, 0.42), yaw)
	_collider(mid + Vector3(0, 1.25, 0), Vector3(length + 0.2, 2.5, 0.4), yaw)


func _build_perimeter() -> void:
	var x: float = Terrain.PAD_X - 1.0
	var zb: float = Terrain.PAD_Z_MIN + 1.0
	var zf: float = FENCE_FRONT_Z
	_fence_run(Vector3(-x, 0, zb), Vector3(x, 0, zb))                    # back
	_fence_run(Vector3(-x, 0, zb), Vector3(-x, 0, zf))                   # west
	_fence_run(Vector3(x, 0, zb), Vector3(x, 0, zf))                     # east
	_fence_run(Vector3(-x, 0, zf), Vector3(-GATE_HALF, 0, zf))           # front, west of the gate
	_fence_run(Vector3(GATE_HALF, 0, zf), Vector3(x, 0, zf))             # front, east of the gate
	# Gate pillars, and the sliding iron gate pushed open behind the east run.
	for s in [-1.0, 1.0]:
		box("wall", Vector3(GATE_HALF * s, 1.4, zf), Vector3(0.6, 2.8, 0.6))
		box("concrete", Vector3(GATE_HALF * s, 2.84, zf), Vector3(0.72, 0.1, 0.72))
	var gx0: float = GATE_HALF + 0.4
	var gz: float = zf - 0.32
	box("iron", Vector3(gx0 + 2.0, 0.08, gz), Vector3(4.0, 0.06, 0.06))
	box("iron", Vector3(gx0 + 2.0, 2.0, gz), Vector3(4.0, 0.06, 0.06))
	box("iron", Vector3(gx0 + 2.0, 1.05, gz), Vector3(4.0, 0.04, 0.04))
	for i in 26:
		var px: float = gx0 + 0.08 + float(i) * 0.15
		bar("iron", Vector3(px, 0.05, gz), Vector3(px, 2.15, gz), 0.03)
	box("dark_metal", Vector3(gx0 + 2.0, 0.02, gz), Vector3(9.0, 0.04, 0.08))  # rail in the ground


# ------------------------------------------------------------- far side row

func _build_far_sidewalk() -> void:
	var z: float = FAR_EDGE_Z + SIDEWALK_W * 0.5
	var seg: float = 4.0
	var x: float = -ROW_X - 6.0
	while x < ROW_X + 6.0:
		var y: float = maxf(_ground(x + seg * 0.5, z), 0.0)
		box("sidewalk", Vector3(x + seg * 0.5, y + 0.06, z), Vector3(seg - 0.02, 0.24, SIDEWALK_W))
		box("concrete", Vector3(x + seg * 0.5, y + 0.07, FAR_EDGE_Z + 0.08), Vector3(seg - 0.02, 0.26, 0.16))  # kerb
		x += seg


func _build_house_row() -> void:
	var kinds := ["sari", "house2", "bungalow", "carinderia", "house2", "bungalow", "house2", "sari", "bungalow", "house2"]
	var paints := ["paint_green", "paint_peach", "paint_blue", "paint_yellow", "wall"]
	var lit_left := 2  # only a couple of windows still lit at midnight
	var x: float = -ROW_X
	var i := 0
	while x < ROW_X - 5.0:
		var w: float = _rng.randf_range(6.5, 9.0)
		var kind: String = kinds[i % kinds.size()]
		var paint: String = paints[_rng.randi() % paints.size()]
		var lit: bool = lit_left > 0 and (i == 2 or i == 6)
		if lit:
			lit_left -= 1
		_house(x, w, kind, paint, lit)
		x += w + (_rng.randf_range(1.0, 2.2) if i != 4 else 3.4)  # an alley after the fifth lot
		i += 1


## One lot: front at HOUSE_FRONT_Z (facing the school, -Z), from x0 to x0 + w.
func _house(x0: float, w: float, kind: String, paint: String, lit: bool) -> void:
	var fz: float = HOUSE_FRONT_Z
	var d: float = _rng.randf_range(6.5, 8.5)
	var cx: float = x0 + w * 0.5
	var cz: float = fz + d * 0.5
	var y: float = _ground(cx, fz)
	# Plinth deep enough to meet ground that rises behind.
	box("concrete", Vector3(cx, y - 0.7, cz), Vector3(w + 0.2, 1.7, d + 0.2))
	var h1: float = 3.0
	match kind:
		"house2":
			box(paint, Vector3(cx, y + 0.15 + h1 * 0.5, cz), Vector3(w, h1, d))
			var h2: float = 2.8
			box("concrete", Vector3(cx, y + 0.15 + h1 + 0.1, cz - 0.4), Vector3(w + 0.1, 0.2, d + 0.8))  # floor slab / balcony
			box(paint, Vector3(cx, y + 0.35 + h1 + h2 * 0.5, cz + 0.4), Vector3(w - 0.3, h2, d - 0.8))
			# Balcony railing.
			var rz: float = fz - 0.75
			box("iron", Vector3(cx, y + 0.25 + h1 + 1.0, rz), Vector3(w, 0.05, 0.05))
			for k in int(w / 0.25):
				var px: float = x0 + 0.12 + float(k) * 0.25
				bar("iron", Vector3(px, y + 0.25 + h1, rz), Vector3(px, y + 0.25 + h1 + 1.0, rz), 0.025)
			gable("roof" if _rng.randf() < 0.5 else "roof_rust", Vector3(cx, y + 0.35 + h1 + h2, cz + 0.4), w + 0.6, d + 0.2, 1.3)
			_windows(x0, w, fz + 0.75, y + 0.35 + h1 + 0.9, 2, lit, false)
			_door(cx - w * 0.25, fz, y + 0.15)
			_windows(cx, w * 0.5, fz, y + 0.15 + 1.0, 1, false, true)
		"bungalow":
			box(paint, Vector3(cx, y + 0.15 + h1 * 0.5, cz), Vector3(w, h1, d))
			gable("roof_rust" if _rng.randf() < 0.6 else "roof", Vector3(cx, y + 0.15 + h1, cz), w + 0.7, d + 0.7, 1.4)
			_door(x0 + 1.4, fz, y + 0.15)
			_windows(x0 + 2.4, w - 2.6, fz, y + 0.15 + 1.0, 2, lit, true)
		"sari":
			box(paint, Vector3(cx, y + 0.15 + h1 * 0.5, cz), Vector3(w, h1, d))
			# Lean-to roof sloping to the street, with an awning over the counter.
			box("roof", Vector3(cx, y + 0.15 + h1 + 0.35, cz + 0.3), Vector3(w + 0.4, 0.05, d + 0.8), 0.0)
			box("roof_rust", Vector3(cx, y + 2.6, fz - 0.8), Vector3(w * 0.7, 0.04, 1.7))
			bar("wood", Vector3(cx - w * 0.33, y, fz - 1.55), Vector3(cx - w * 0.33, y + 2.6, fz - 1.55), 0.08)
			bar("wood", Vector3(cx + w * 0.33, y, fz - 1.55), Vector3(cx + w * 0.33, y + 2.6, fz - 1.55), 0.08)
			# Store window: counter, dark shelves, iron grille.
			box("wood", Vector3(cx, y + 0.6, fz - 0.15), Vector3(w * 0.6, 0.9, 0.3))
			box("glass", Vector3(cx, y + 1.65, fz - 0.02), Vector3(w * 0.6, 1.2, 0.04))
			for k in int(w * 0.6 / 0.12):
				var px: float = cx - w * 0.3 + float(k) * 0.12
				bar("iron", Vector3(px, y + 1.05, fz - 0.07), Vector3(px, y + 2.25, fz - 0.07), 0.02)
			box("sign_red", Vector3(cx, y + 2.85, fz - 0.05), Vector3(w * 0.75, 0.5, 0.06))
			_label("SARI-SARI STORE", Vector3(cx, y + 2.85, fz - 0.1), 0.012)
			if lit:
				box("lit", Vector3(cx + w * 0.38, y + 1.7, fz - 0.03), Vector3(0.8, 0.9, 0.03))
		"carinderia":
			box(paint, Vector3(cx, y + 0.15 + h1 * 0.5, cz), Vector3(w, h1, d))
			box("roof", Vector3(cx, y + 0.15 + h1 + 0.3, cz), Vector3(w + 0.4, 0.05, d + 0.6))
			# Rolled-down shutter and a blue tarp awning on bamboo poles.
			box("roof", Vector3(cx, y + 1.35, fz - 0.03), Vector3(w * 0.75, 2.4, 0.04))
			box("tarp", Vector3(cx, y + 2.65, fz - 1.3), Vector3(w * 0.9, 0.03, 2.6), 0.0)
			for s in [-1.0, 1.0]:
				bar("bamboo", Vector3(cx + s * w * 0.43, y, fz - 2.5), Vector3(cx + s * w * 0.43, y + 2.65, fz - 2.5), 0.07)
			box("sign_red", Vector3(cx, y + 2.95, fz - 0.05), Vector3(w * 0.6, 0.4, 0.06))
			_label("CARINDERIA", Vector3(cx, y + 2.95, fz - 0.1), 0.011)
			# A stack of monobloc chairs and a table left outside.
			box("paint_blue", Vector3(cx + w * 0.3, y + 0.4, fz - 1.2), Vector3(0.9, 0.05, 0.9))
			bar("dark_metal", Vector3(cx + w * 0.3, y, fz - 1.2), Vector3(cx + w * 0.3, y + 0.4, fz - 1.2), 0.05)
			box("wall", Vector3(cx - w * 0.3, y + 0.6, fz - 1.0), Vector3(0.5, 1.2, 0.5))
	# Back fence of the lot, bamboo.
	box("bamboo", Vector3(cx, _ground(cx, fz + d + 1.0) + 0.7, fz + d + 1.0), Vector3(w, 1.4, 0.08))


func _windows(x0: float, w: float, fz: float, y: float, n: int, lit: bool, from_x0: bool) -> void:
	var span: float = w
	for k in n:
		var wx: float = (x0 + span * (float(k) + 0.5) / float(n)) if from_x0 else (x0 + w * (float(k) + 0.5) / float(n))
		var key: String = "glass"
		if lit and k == 0:
			key = "lit"
		elif lit and k == 1 and _rng.randf() < 0.5:
			key = "tv"
		box(key, Vector3(wx, y + 0.6, fz - 0.03), Vector3(1.1, 1.2, 0.04))
		box("concrete", Vector3(wx, y - 0.02, fz - 0.07), Vector3(1.3, 0.06, 0.12))  # sill
		for b in 5:
			var bx: float = wx - 0.5 + float(b) * 0.25
			bar("iron", Vector3(bx, y, fz - 0.09), Vector3(bx, y + 1.2, fz - 0.09), 0.02)


func _door(x: float, fz: float, y: float) -> void:
	box("wood", Vector3(x, y + 1.05, fz - 0.03), Vector3(0.95, 2.1, 0.05))
	box("concrete", Vector3(x, y + 0.08 - 0.15, fz - 0.35), Vector3(1.3, 0.16, 0.7))  # step


func _label(text: String, at: Vector3, pixel: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = pixel
	l.font_size = 48
	l.modulate = Color(0.95, 0.92, 0.85)
	l.outline_size = 0
	l.position = at
	l.rotation.y = PI  # face the street (-Z)
	l.shaded = true
	add_child(l)


# --------------------------------------------------------- poles and lamps

func _build_poles_and_lamps() -> void:
	var pz: float = FAR_EDGE_Z + 0.45
	var xs := [-36.0, -18.0, 0.0, 18.0, 36.0]
	# lamp state per pole: lit, flicker, dead
	var lamps := ["lit", "lit", "flicker", "lit", "dead"]
	var tops: Array[Vector3] = []
	for i in xs.size():
		var x: float = xs[i]
		var y: float = maxf(_ground(x, pz), 0.0)
		var top := Vector3(x, y + 8.5, pz)
		bar("concrete", Vector3(x, y - 0.3, pz), top, 0.26)
		box("wood", top + Vector3(0, -0.3, 0), Vector3(1.6, 0.12, 0.12))   # crossarm
		tops.append(top + Vector3(0, -0.25, 0))
		# Transformer can on every other pole.
		if i % 2 == 1:
			box("dark_metal", top + Vector3(0, -1.6, 0.25), Vector3(0.45, 0.8, 0.45))
		# Lamp on an arm reaching over the street.
		var arm_end := Vector3(x, y + 6.6, pz - 2.2)
		bar("dark_metal", Vector3(x, y + 6.2, pz), arm_end, 0.07)
		box("dark_metal", arm_end + Vector3(0, -0.05, 0), Vector3(0.35, 0.14, 0.6))
		var state: String = lamps[i]
		var bulb_key: String = "bulb" if state == "lit" else ("bulb_flicker" if state == "flicker" else "bulb_dead")
		box(bulb_key, arm_end + Vector3(0, -0.14, 0), Vector3(0.24, 0.04, 0.44))
		if state != "dead":
			var light := OmniLight3D.new()
			light.name = "StreetLamp%d" % i
			light.light_color = SODIUM
			light.light_energy = 1.1
			light.omni_range = 11.0
			light.omni_attenuation = 1.4
			light.shadow_enabled = false
			light.position = arm_end + Vector3(0, -0.4, 0)
			light.distance_fade_enabled = true
			light.distance_fade_begin = 50.0
			light.distance_fade_length = 15.0
			add_child(light)
			if state == "flicker":
				_flicker_light = light
	# Three sagging conductors between neighbouring poles.
	for i in tops.size() - 1:
		for off in [-0.6, 0.0, 0.6]:
			_wire(tops[i] + Vector3(off, 0, 0), tops[i + 1] + Vector3(off, 0, 0), 0.9)
	# Service drops to a few houses.
	for i in [0, 1, 3]:
		var t: Vector3 = tops[i] + Vector3(0, -0.8, 0)
		var house_pt := Vector3(t.x + 3.0, maxf(_ground(t.x + 3.0, HOUSE_FRONT_Z), 0.0) + 2.9, HOUSE_FRONT_Z)
		_wire(t, house_pt, 0.5)


func _wire(a: Vector3, b: Vector3, sag: float) -> void:
	var n := 8
	var prev := a
	for k in range(1, n + 1):
		var t: float = float(k) / float(n)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		bar("wire", prev, p, 0.018)
		prev = p


func _build_tricycle(at: Vector3) -> void:
	var y: float = maxf(_ground(at.x, at.z), 0.0)
	var o := Vector3(at.x, y, at.z)
	# Motorcycle on the street side, sidecar cab towards the kerb.
	box("dark_metal", o + Vector3(0.0, 0.55, -0.55), Vector3(1.6, 0.35, 0.35))
	box("sign_red", o + Vector3(0.1, 0.85, -0.55), Vector3(0.7, 0.2, 0.3))
	box("sign_red", o + Vector3(0.0, 1.05, 0.25), Vector3(1.7, 1.3, 1.1))      # cab body
	box("glass", o + Vector3(-0.86, 1.25, 0.25), Vector3(0.03, 0.5, 0.9))
	box("dark_metal", o + Vector3(0.0, 1.75, 0.0), Vector3(2.0, 0.06, 1.7))    # roof
	for wp in [Vector3(0.75, 0.28, -0.55), Vector3(-0.75, 0.28, -0.55), Vector3(0.0, 0.28, 0.85)]:
		box("dark_metal", o + wp, Vector3(0.56, 0.56, 0.12))


# ----------------------------------------------------------- behind school

func _build_footbridge(x: float) -> void:
	var za: float = Terrain.CREEK_Z + Terrain.CREEK_HALF_WIDTH + 1.6
	var zb: float = Terrain.CREEK_Z - Terrain.CREEK_HALF_WIDTH - 1.6
	var ya: float = _ground(x, za)
	var yb: float = _ground(x, zb)
	var deck_y: float = maxf(ya, yb) + 0.35
	var len: float = za - zb
	var mid := Vector3(x, deck_y, (za + zb) * 0.5)
	box("concrete", mid, Vector3(1.6, 0.25, len))
	for e in [[za, ya], [zb, yb]]:
		box("concrete", Vector3(x, (e[1] + deck_y) * 0.5 - 0.2, e[0]), Vector3(2.0, deck_y - e[1] + 0.6, 1.2))
	box("concrete", Vector3(x, (deck_y - Terrain.CREEK_DEPTH) * 0.5 - 0.3, Terrain.CREEK_Z), Vector3(0.6, deck_y + Terrain.CREEK_DEPTH + 0.4, 1.0))
	for s in [-1.0, 1.0]:
		var rx: float = x + s * 0.74
		box("iron", Vector3(rx, deck_y + 1.0, mid.z), Vector3(0.05, 0.05, len))
		var k := 0.0
		while k <= len:
			bar("iron", Vector3(rx, deck_y + 0.1, zb + k), Vector3(rx, deck_y + 1.0, zb + k), 0.04)
			k += 1.2


func _build_shanties() -> void:
	var z0: float = Terrain.CREEK_Z - Terrain.CREEK_HALF_WIDTH - 6.0
	var spots := [-32.0, -21.0, -12.0, 18.0, 27.0, 38.0]
	for x in spots:
		var w: float = _rng.randf_range(3.5, 5.0)
		var d: float = _rng.randf_range(3.0, 4.0)
		var z: float = z0 - _rng.randf_range(0.0, 4.0) - d * 0.5
		var y: float = _ground(x, z)
		box("concrete", Vector3(x, y - 0.5, z), Vector3(w + 0.2, 1.2, d + 0.2))
		box("wood" if _rng.randf() < 0.6 else "paint_blue", Vector3(x, y + 0.1 + 1.2, z), Vector3(w, 2.4, d))
		box("roof_rust", Vector3(x, y + 2.75, z), Vector3(w + 0.5, 0.05, d + 0.5), 0.0)
		box("glass", Vector3(x - w * 0.2, y + 1.5, z + d * 0.5 + 0.02), Vector3(0.8, 0.7, 0.03))
		# Bamboo fence beside it.
		box("bamboo", Vector3(x + w * 0.5 + 1.6, _ground(x + w * 0.5 + 1.6, z) + 0.6, z), Vector3(3.0, 1.2, 0.07))


# ------------------------------------------------------------- far horizon

func _build_far_silhouettes() -> void:
	var count := 22
	for i in count:
		var a: float = TAU * (float(i) + _rng.randf_range(-0.3, 0.3)) / float(count)
		var r: float = _rng.randf_range(62.0, 96.0)
		var x: float = sin(a) * r
		var z: float = cos(a) * r
		# Keep the street axis in front open (the road runs off both ways).
		if absf(z - Terrain.STREET_Z) < 10.0:
			continue
		var y: float = _ground(x, z)
		var w: float = _rng.randf_range(5.0, 9.0)
		var d: float = _rng.randf_range(5.0, 8.0)
		var h: float = _rng.randf_range(3.0, 6.0)
		var yaw: float = _rng.randf_range(-0.4, 0.4)
		box("silhouette", Vector3(x, y + h * 0.5 - 0.5, z), Vector3(w, h + 1.0, d), yaw, "far")
		gable("silhouette", Vector3(x, y + h, z), w + 0.6, d + 0.6, 1.5, yaw, "far")
		if _rng.randf() < 0.12:
			box("lit", Vector3(x + sin(yaw) * 0.0, y + h * 0.55, z - d * 0.5 - 0.02), Vector3(0.9, 0.8, 0.03), yaw, "far")
	# Water tower on the western hill.
	var tw := Vector3(-58.0, 0.0, -48.0)
	tw.y = _ground(tw.x, tw.z)
	for lx in [-1.6, 1.6]:
		for lz in [-1.6, 1.6]:
			bar("silhouette", tw + Vector3(lx, -0.5, lz), tw + Vector3(lx * 0.6, 11.0, lz * 0.6), 0.3, "far")
	box("silhouette", tw + Vector3(0, 12.6, 0), Vector3(4.2, 3.4, 4.2), 0.0, "far")
	gable("silhouette", tw + Vector3(0, 14.3, 0), 4.4, 4.4, 1.0, 0.0, "far")
	# Cell tower on the eastern hill, with a slow red beacon.
	var ct := Vector3(64.0, 0.0, -30.0)
	ct.y = _ground(ct.x, ct.z)
	var top := ct + Vector3(0, 30.0, 0)
	for lx in [-1.8, 1.8]:
		for lz in [-1.8, 1.8]:
			bar("silhouette", ct + Vector3(lx, -0.5, lz), top + Vector3(lx * 0.15, 0, lz * 0.15), 0.22, "far")
	var k := 3.0
	while k < 30.0:
		var s: float = lerpf(1.8, 0.27, k / 30.0)
		box("silhouette", ct + Vector3(0, k, 0), Vector3(s * 2.0, 0.1, s * 2.0), 0.0, "far")
		k += 3.0
	for side in [0.0, 2.1, 4.2]:
		box("silhouette", top + Vector3(sin(side) * 0.6, -2.0, cos(side) * 0.6), Vector3(0.35, 1.6, 0.12), side, "far")
	box("beacon", top + Vector3(0, 0.35, 0), Vector3(0.35, 0.35, 0.35), 0.0, "far")
