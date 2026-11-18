extends StaticBody3D
## The land around the school, built at load from Terrain.height(): rolling
## grass and mud in 20 m chunks (1 m cells near the campus, coarser further
## out, skirts hiding the seams), a matching HeightMapShape3D, and the creek's
## water surface behind the school. The flat campus pad stays at y = 0; the
## level builder also keeps a flat box collider under it so the navmesh bake
## never depends on this script.

const TERRAIN_SHADER: Shader = preload("res://shaders/terrain.gdshader")
const WATER_SHADER: Shader = preload("res://shaders/creek_water.gdshader")
const TEXTURES_INDEX: String = "res://textures/polyhaven/index.json"
const CHUNK: int = 20
const SKIRT: float = 0.8
## Water level in the creek cut (the bed is at -Terrain.CREEK_DEPTH).
const WATER_Y: float = -0.75

## Heights on the 1 m grid, (2N+1)^2 values, row-major in z then x.
var _h: PackedFloat32Array
var _n: int = 0


func _ready() -> void:
	_n = int(Terrain.EXTENT)
	_sample_heights()
	var material := _terrain_material()
	var half: int = _n
	for cz in range(-half, half, CHUNK):
		for cx in range(-half, half, CHUNK):
			_build_chunk(cx, cz, material)
	_build_collision()
	_build_water()


func _sample_heights() -> void:
	var side: int = 2 * _n + 1
	_h.resize(side * side)
	for iz in side:
		for ix in side:
			_h[iz * side + ix] = Terrain.height(float(ix - _n), float(iz - _n))


func _hget(x: int, z: int) -> float:
	var side: int = 2 * _n + 1
	return _h[clampi(z + _n, 0, side - 1) * side + clampi(x + _n, 0, side - 1)]


func _normal_at(x: int, z: int) -> Vector3:
	var hx: float = _hget(x + 1, z) - _hget(x - 1, z)
	var hz: float = _hget(x, z + 1) - _hget(x, z - 1)
	return Vector3(-hx, 2.0, -hz).normalized()


## One 20 m chunk; cell size by distance from the school.
func _build_chunk(cx: int, cz: int, material: Material) -> void:
	var centre := Vector2(cx + CHUNK * 0.5, cz + CHUNK * 0.5)
	var d: float = maxf(absf(centre.x), absf(centre.y))
	var step: int = 1 if d < 45.0 else (2 if d < 75.0 else 5)
	# Entirely flat (the campus pad): two triangles are enough.
	var flat := true
	for z in range(cz, cz + CHUNK + 1):
		for x in range(cx, cx + CHUNK + 1):
			if absf(_hget(x, z)) > 0.0001:
				flat = false
				break
		if not flat:
			break
	if flat:
		step = CHUNK
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells: int = CHUNK / step
	for j in cells:
		for i in cells:
			var x0: int = cx + i * step
			var z0: int = cz + j * step
			var x1: int = x0 + step
			var z1: int = z0 + step
			_quad(st, [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x1, z1), Vector2i(x0, z1)])
	if not flat:
		# Skirts down from every edge so a finer neighbour leaves no crack.
		for k in cells:
			var a: int = k * step
			var b: int = a + step
			_skirt(st, Vector2i(cx + a, cz), Vector2i(cx + b, cz))
			_skirt(st, Vector2i(cx + b, cz + CHUNK), Vector2i(cx + a, cz + CHUNK))
			_skirt(st, Vector2i(cx + CHUNK, cz + a), Vector2i(cx + CHUNK, cz + b))
			_skirt(st, Vector2i(cx, cz + b), Vector2i(cx, cz + a))
	var mi := MeshInstance3D.new()
	mi.name = "Chunk_%d_%d" % [cx, cz]
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _vert(st: SurfaceTool, p: Vector2i, y_off: float = 0.0) -> void:
	st.set_normal(_normal_at(p.x, p.y))
	st.set_uv(Vector2(p.x, p.y))
	st.add_vertex(Vector3(p.x, _hget(p.x, p.y) + y_off, p.y))


func _quad(st: SurfaceTool, c: Array) -> void:
	# Clockwise seen from above, which is Godot's front face.
	for idx in [0, 1, 2, 0, 2, 3]:
		_vert(st, c[idx])


func _skirt(st: SurfaceTool, a: Vector2i, b: Vector2i) -> void:
	_vert(st, a)
	_vert(st, b, -SKIRT)
	_vert(st, b)
	_vert(st, a)
	_vert(st, a, -SKIRT)
	_vert(st, b, -SKIRT)


func _build_collision() -> void:
	var side: int = 2 * _n + 1
	var shape := HeightMapShape3D.new()
	shape.map_width = side
	shape.map_depth = side
	shape.map_data = _h
	var cs := CollisionShape3D.new()
	cs.name = "TerrainCollision"
	cs.shape = shape
	add_child(cs)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	water.name = "Creek"
	var pm := PlaneMesh.new()
	pm.size = Vector2(Terrain.EXTENT * 2.0, Terrain.CREEK_HALF_WIDTH * 2.0 + 4.0)
	pm.subdivide_width = 0
	water.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	water.material_override = m
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0.0, WATER_Y, Terrain.CREEK_Z)
	add_child(water)


func _terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TERRAIN_SHADER
	m.set_shader_parameter("creek_z", Terrain.CREEK_Z)
	m.set_shader_parameter("creek_half", Terrain.CREEK_HALF_WIDTH)
	if FileAccess.file_exists(TEXTURES_INDEX):
		var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEXTURES_INDEX))
		var e: Dictionary = index.get("grass_ground", {})
		if not e.is_empty():
			m.set_shader_parameter("grass_albedo", load(e.maps.diff))
			m.set_shader_parameter("grass_normal", load(e.maps.nor_gl))
			m.set_shader_parameter("grass_rough", load(e.maps.rough))
			m.set_shader_parameter("tile_m", float(e.size_m[0]))
			m.set_shader_parameter("has_textures", true)
	return m
