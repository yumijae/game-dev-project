extends SceneTree
## Generates the STI school building as res://school/school_building.scn
##
##   godot --headless --path . --script res://tools/build_school.gd
##
## Layout (front of the building faces +Z, the street):
##   * 24 m x 16 m footprint, 4 floors of 3.8 m, walkable roof
##   * central corridor (z -1.2..1.2) on every floor
##   * front rooms z 1.2..8, back rooms z -8..-1.2 between two stairwells
##   * west + east U-shaped stairwells (east one continues to the roof)
## Edit ROOMS below to change the floor plan, then re-run this script and
## tools/build_level.gd.

const OUT := "res://school/school_building.scn"
const GLB := "res://sti_college_kalibo_4floor_bim.glb"

const X0 := -12.0
const X1 := 12.0
const Z0 := -8.0
const Z1 := 8.0
const FH := 3.8          # floor-to-floor height
const SLAB := 0.25
const EXT_T := 0.25      # exterior wall thickness
const INT_T := 0.15      # partition thickness
const LINING_T := 0.01   # plaster skin on the room side of exterior walls
const CORR := 1.2        # corridor half width
const FLOORS := 4

# Stairwells: x range of the stairwell (walls on these lines)
const STAIRS := {
	"West Stairwell": {"x0": -12.0, "x1": -9.0, "top_floor": 3}, # serves 1F-4F
	"East Stairwell": {"x0": 9.0, "x1": 12.0, "top_floor": 4},   # serves 1F-roof
}
const STAIR_EDGE := -1.6     # where flights meet the floor (corridor side)
const LANDING_EDGE := -5.6   # where flights meet the mid landing

const LAYER_WORLD := 1
const LAYER_DOORS := 8

## [floor (0 = 1F), name, type, x0, z0, x1, z1]
const ROOMS := [
	# 1F - Admissions & staff
	[0, "Admissions Office", "admissions", -12.0, 1.2, -3.0, 8.0],
	[0, "Main Lobby", "lobby", -3.0, 1.2, 3.0, 8.0],
	[0, "Cashier & Registrar", "cashier", 3.0, 1.2, 12.0, 8.0],
	[0, "Director's Office", "director", -9.0, -8.0, -3.0, -1.2],
	[0, "Staff Room", "staff", -3.0, -8.0, 3.0, -1.2],
	[0, "Records Room", "records", 3.0, -8.0, 9.0, -1.2],
	# 2F - Computer labs, MIT office, restrooms
	[1, "Computer Lab 1", "complab", -12.0, 1.2, 0.0, 8.0],
	[1, "Computer Lab 2", "complab", 0.0, 1.2, 12.0, 8.0],
	[1, "Male Restroom", "restroom", -9.0, -8.0, -6.0, -1.2],
	[1, "Female Restroom", "restroom", -6.0, -8.0, -3.0, -1.2],
	[1, "Server Room", "server", -3.0, -8.0, 0.0, -1.2],
	[1, "MIT Office", "mit", 0.0, -8.0, 3.0, -1.2],
	[1, "Com Sci Lab", "robolab", 3.0, -8.0, 9.0, -1.2],
	# 3F - Classrooms, faculty room, restrooms
	[2, "Room 301", "classroom", -12.0, 1.2, -6.0, 8.0],
	[2, "Room 302", "classroom", -6.0, 1.2, 0.0, 8.0],
	[2, "Room 303", "classroom", 0.0, 1.2, 6.0, 8.0],
	[2, "Room 304", "classroom", 6.0, 1.2, 12.0, 8.0],
	[2, "Faculty Room", "faculty", -9.0, -8.0, -3.0, -1.2],
	[2, "Male Restroom", "restroom", -3.0, -8.0, 0.0, -1.2],
	[2, "Female Restroom", "restroom", 0.0, -8.0, 3.0, -1.2],
	[2, "Room 305", "classroom", 3.0, -8.0, 9.0, -1.2],
	# 4F - Classrooms (west) / Culinary (east)
	[3, "Room 401", "classroom", -12.0, 1.2, -6.0, 8.0],
	[3, "Room 402", "classroom", -6.0, 1.2, 0.0, 8.0],
	[3, "Culinary Kitchen", "kitchen", 0.0, 1.2, 12.0, 8.0],
	[3, "Room 403", "classroom", -9.0, -8.0, 0.0, -1.2],
	[3, "Pantry", "pantry", 0.0, -8.0, 3.0, -1.2],
	[3, "Culinary Dining", "dining", 3.0, -8.0, 9.0, -1.2],
]

const FLOOR_NAMES := ["1F", "2F", "3F", "4F", "Roof"]

## Realistic CC0 textures (downloaded by tools/fetch_textures.py).
## material key -> [Poly Haven asset, tint, roughness multiplier]
const TEXTURES_INDEX := "res://textures/polyhaven/index.json"
const PBR := {
	"ext": ["white_stucco", Color(1, 1, 1), 1.0],
	# Indoors is smooth painted plaster; the rough stucco is for the facade.
	"int": ["painted_plaster_wall", Color(0.96, 0.94, 0.88), 1.0],
	"ceiling": ["painted_plaster_wall", Color(0.93, 0.93, 0.91), 1.0],
	"slab": ["grey_plaster", Color(0.85, 0.85, 0.85), 1.0],
	"wood": ["plywood", Color(1, 1, 1), 1.0],
	"door": ["lacquered_cherry_wood", Color(1, 1, 1), 1.0],
	"floor": ["interior_tiles", Color(1, 1, 1), 0.8],
	"floor_lobby": ["floor_tiles_06", Color(1, 1, 1), 0.7],
	"floor_wood": ["laminate_floor_02", Color(1, 1, 1), 1.0],
	"floor_mosaic": ["rounded_square_tiled_wall", Color(1, 1, 1), 1.0],
	"wall_tile": ["long_white_tiles", Color(1, 1, 1), 1.0],
	"floor_kitchen": ["anti_skid_tiles", Color(0.9, 0.9, 0.9), 1.0],
	"floor_rubber": ["rubber_tiles", Color(1, 1, 1), 1.0],
	"pavement": ["concrete_pavement", Color(1, 1, 1), 1.0],
}
## Floor finish per room type (default "floor").
const ROOM_FLOORS := {
	"lobby": "floor_lobby", "director": "floor_wood", "faculty": "floor_wood", "staff": "floor_wood",
	"restroom": "floor_mosaic", "kitchen": "floor_kitchen", "pantry": "floor_kitchen", "server": "floor_rubber",
	"robolab": "floor_rubber",
}

var mats := {}
var geo := {}               # material key -> {v, n, uv, i}
var shapes := {}            # size key -> BoxShape3D (shared)
var root_node: Node3D
var collision: StaticBody3D
var interactive: Node3D
var lights: Node3D
var loot_root: Node3D
var room_info := []         # for the HUD: [name, floor, x0, z0, x1, z1]
var rng := RandomNumberGenerator.new()

# Per-floor wall data
var int_edges := {}         # "axis|fixed|floor" -> [[a0, a1], ...]
var openings := []          # {floor, axis, fixed, c, w, sill, top, kind}

# Current room while furnishing
var R := {}
var footprints := []        # local rects [u0, d0, u1, d1]
var clear_rects := []
var surfaces := []          # world points on top of furniture


func _initialize() -> void:
	rng.seed = 20261114
	_load_materials()
	root_node = Node3D.new()
	root_node.name = "STI_School"
	collision = StaticBody3D.new()
	collision.name = "BuildingCollision"
	collision.collision_layer = LAYER_WORLD
	collision.collision_mask = 0
	interactive = Node3D.new()
	interactive.name = "Interactive"
	lights = Node3D.new()
	lights.name = "Lights"
	loot_root = Node3D.new()
	loot_root.name = "LootSpawns"
	loot_root.set_script(load("res://items/item_spawner.gd"))
	for n in [collision, interactive, lights, loot_root]:
		root_node.add_child(n)

	_plan_walls()
	for f in FLOORS:
		_build_floor(f)
	_build_slabs()
	for s in STAIRS:
		_build_stairwell(s)
	_build_roof()
	_build_facade()
	_build_site()
	_build_signs()
	props_root = Node3D.new()
	props_root.name = "Props"
	root_node.add_child(props_root)
	for r in ROOMS:
		_furnish(r)
	_corridor_props()
	_corridor_and_roof_loot()
	_commit_meshes()

	root_node.set_meta("rooms", room_info)
	root_node.set_meta("floor_names", FLOOR_NAMES)
	root_node.set_meta("floor_height", FH)
	root_node.add_to_group("school", true)
	_set_owner(root_node, root_node)
	var packed := PackedScene.new()
	var err := packed.pack(root_node)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://school"))
		err = ResourceSaver.save(packed, OUT)
	print("[build_school] boxes=%d shapes=%d doors=%d lights=%d loot markers=%d -> %s" % [
		_box_count, collision.get_child_count(), interactive.get_child_count(),
		lights.get_child_count(), loot_root.get_child_count(), error_string(err)])
	root_node.free()
	quit()


# ---------------------------------------------------------------- materials

func _load_materials() -> void:
	var glb: Node = load(GLB).instantiate()
	for mi in glb.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if m and m.resource_name != "" and not mats.has(m.resource_name):
				mats[m.resource_name] = m.duplicate()
	glb.free()
	var alias := {
		"ext": ["STI_Exterior_Concrete", Color(0.92, 0.93, 0.95)],
		"int": ["STI_Interior_Partition_Wall", Color(0.85, 0.87, 0.9)],
		"tile": ["STI_Interior_Ceramic_Tile", Color(0.8, 0.82, 0.85)],
		"slab": ["STI_Structural_RC_Slab", Color(0.7, 0.7, 0.7)],
		"blue": ["STI_Royal_Blue", Color(0.15, 0.3, 0.8)],
		"yellow": ["STI_Yellow_Gold", Color(0.95, 0.75, 0.1)],
		"navy": ["STI_Ground_Pillar_Navy", Color(0.25, 0.32, 0.5)],
		"glass": ["STI_Arched_Window_Glass", Color(0.5, 0.65, 0.8, 0.4)],
		"frame": ["STI_Window_Frame_Dark", Color(0.15, 0.17, 0.2)],
		"door": ["STI_Classroom_Door", Color(0.45, 0.3, 0.18)],
		"furniture": ["STI_Classroom_Furniture", Color(0.2, 0.4, 0.8)],
		"sign": ["STI_Main_Signboard", Color(0.95, 0.8, 0.1)],
		"canopy_sign": ["STI_Canopy_365_Sign", Color(0.9, 0.9, 0.9)],
		"banner": ["STI_Scholar_Banner", Color(0.2, 0.4, 0.9)],
		"ac": ["STI_AC_Unit_Case", Color(0.9, 0.9, 0.88)],
		"plant": ["STI_Tropical_Foliage", Color(0.2, 0.6, 0.35)],
	}
	for k in alias:
		if PBR.has(k):
			continue
		var src: String = alias[k][0]
		if mats.has(src):
			mats[k] = mats[src]
		else:
			mats[k] = _mat(alias[k][1])
	_load_pbr()
	_paint_flat_colours()
	if not mats.has("wood"):
		mats["wood"] = _mat(Color(0.55, 0.38, 0.22), 0.0, 0.7)
	mats["metal"] = _mat(Color(0.55, 0.58, 0.62), 0.5, 0.45)
	mats["steel"] = _mat(Color(0.78, 0.8, 0.82), 0.8, 0.25)
	mats["dark"] = _mat(Color(0.08, 0.09, 0.1), 0.2, 0.5)
	mats["white"] = _mat(Color(0.95, 0.95, 0.95), 0.0, 0.2)
	mats["board"] = _mat(Color(0.12, 0.25, 0.18), 0.0, 0.8)
	mats["rail"] = _mat(Color(0.3, 0.32, 0.35), 0.7, 0.4)
	var panel := _mat(Color(1, 1, 1), 0.0, 0.5)
	panel.emission_enabled = true
	panel.emission = Color(1.0, 0.98, 0.92)
	panel.emission_energy_multiplier = 2.5
	mats["lightpanel"] = panel
	var screen := _mat(Color(0.1, 0.15, 0.3), 0.0, 0.3)
	screen.emission_enabled = true
	screen.emission = Color(0.2, 0.35, 0.7)
	screen.emission_energy_multiplier = 0.4
	mats["screen"] = screen


func _load_pbr() -> void:
	if not FileAccess.file_exists(TEXTURES_INDEX):
		push_warning("No textures found - run: python tools/fetch_textures.py (using flat colours)")
		for k in ["ceiling", "floor", "floor_lobby", "floor_wood", "floor_mosaic", "wall_tile", "floor_kitchen", "floor_rubber", "pavement"]:
			if not mats.has(k):
				mats[k] = _mat(Color(0.85, 0.85, 0.85))
		return
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEXTURES_INDEX))
	for key in PBR:
		var spec: Array = PBR[key]
		var e: Dictionary = index.get(spec[0], {})
		if e.is_empty():
			continue
		var m := StandardMaterial3D.new()
		m.resource_name = key
		m.albedo_texture = load(e.maps.diff)
		m.albedo_color = spec[1]
		m.normal_enabled = true
		m.normal_texture = load(e.maps.nor_gl)
		m.roughness_texture = load(e.maps.rough)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = spec[2]
		# Box UVs are world metres * 0.5, so this makes one texture repeat
		# match the texture's real-world size.
		var size_m: float = e.size_m[0]
		m.uv1_scale = Vector3(2.0 / size_m, 2.0 / size_m, 1.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mats[key] = m


## The facade trim (STI blue and gold bands, navy pillars, the stair-hut fascia,
## the sign boards) and the AC casings came in as flat untextured colours,
## which read as plastic next to the textured stucco. Repaint them: the same
## brand colours over the stucco's own albedo, bump and roughness, i.e. paint
## on render (and a lighter bump for the sheet-metal AC cases).
const PAINTED := {
	# key: [bump strength, roughness multiplier on the stucco roughness map]
	"blue": [0.8, 1.0], "yellow": [0.8, 1.0], "navy": [0.8, 1.0], "ac": [0.25, 0.75],
}


func _paint_flat_colours() -> void:
	if not FileAccess.file_exists(TEXTURES_INDEX):
		return
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEXTURES_INDEX))
	var e: Dictionary = index.get("white_stucco", {})
	if e.is_empty():
		return
	for key in PAINTED:
		var src = mats.get(key)
		var colour: Color = src.albedo_color if src is BaseMaterial3D else Color(0.8, 0.8, 0.8)
		# Some of the BIM materials carry their colour in a texture with a
		# white albedo_color: use the texture's average instead.
		if src is BaseMaterial3D and src.albedo_texture != null:
			var img: Image = src.albedo_texture.get_image()
			if img != null:
				img = img.duplicate()
				if img.is_compressed():
					img.decompress()
				img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
				colour = img.get_pixel(0, 0) * colour
		var m := StandardMaterial3D.new()
		m.resource_name = "painted_" + key
		m.albedo_texture = load(e.maps.diff)
		# The stucco albedo averages ~0.84; lift the tint so the paint keeps
		# its colour instead of going muddy.
		m.albedo_color = Color(minf(colour.r / 0.84, 1.0), minf(colour.g / 0.84, 1.0), minf(colour.b / 0.84, 1.0))
		m.normal_enabled = true
		m.normal_texture = load(e.maps.nor_gl)
		m.normal_scale = PAINTED[key][0]
		m.roughness_texture = load(e.maps.rough)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.roughness = PAINTED[key][1]
		var size_m: float = e.size_m[0]
		m.uv1_scale = Vector3(2.0 / size_m, 2.0 / size_m, 1.0)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mats[key] = m


func _mat(c: Color, metal := 0.0, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# ---------------------------------------------------------------- geometry

var _box_count := 0

## Axis-aligned box. Visual geometry is merged per material; collision is a
## BoxShape3D on the building's single StaticBody3D.
func box(center: Vector3, size: Vector3, mk: String, collide := true, fit_uv := false) -> void:
	if size.x <= 0.005 or size.y <= 0.005 or size.z <= 0.005:
		return
	_box_count += 1
	if not geo.has(mk):
		geo[mk] = {"v": [], "n": [], "uv": [], "t": [], "i": []}
	var g: Dictionary = geo[mk]
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP],
		[Vector3.LEFT, Vector3(0, 0, 1), Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3(0, 0, -1)],
		[Vector3.DOWN, Vector3.RIGHT, Vector3(0, 0, 1)],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var tu: Vector3 = f[1]
		var tv: Vector3 = f[2]
		var fc: Vector3 = center + n * h
		var hu: float = (tu * h).length()
		var hv: float = (tv * h).length()
		var base: int = g.v.size()
		# Tangent frame for the normal maps: U grows along tu, V along -tv.
		# Without it Godot assumes a tangent along +X, which on the walls
		# facing +-X lies along the normal itself and turns them black under
		# the flashlight (every room corner looked half unlit).
		var t_sign: float = signf(n.cross(tu).dot(-tv))
		if t_sign == 0.0:
			t_sign = 1.0
		for k in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
			g.t.append_array([tu.x, tu.y, tu.z, t_sign])
			var p: Vector3 = fc + tu * hu * k[0] + tv * hv * k[1]
			g.v.append(p)
			g.n.append(n)
			if fit_uv:
				g.uv.append(Vector2((k[0] + 1) * 0.5, 1.0 - (k[1] + 1) * 0.5))
			else:
				g.uv.append(Vector2(p.dot(tu), -p.dot(tv)) * 0.5)
		g.i.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	if collide:
		_shape(Transform3D(Basis(), center), size, LAYER_WORLD)


func _shape(xf: Transform3D, size: Vector3, _layer: int) -> void:
	var key := "%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not shapes.has(key):
		var bs := BoxShape3D.new()
		bs.size = size
		shapes[key] = bs
	var cs := CollisionShape3D.new()
	cs.shape = shapes[key]
	cs.transform = xf
	collision.add_child(cs, true)


func _commit_meshes() -> void:
	var visual := Node3D.new()
	visual.name = "Visual"
	root_node.add_child(visual)
	root_node.move_child(visual, 0)
	for mk in geo:
		var g: Dictionary = geo[mk]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array(g.v)
		arr[Mesh.ARRAY_NORMAL] = PackedVector3Array(g.n)
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array(g.uv)
		arr[Mesh.ARRAY_TANGENT] = PackedFloat32Array(g.t)
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array(g.i)
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		am.surface_set_material(0, mats[mk])
		var mi := MeshInstance3D.new()
		mi.name = "Mesh_" + mk
		mi.mesh = am
		if mk == "glass":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			# Both faces cast, as LightRig.seal_geometry() does at run time, so
			# the editor shows no light leaking through wall/slab seams either.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		visual.add_child(mi)


## Wall along `axis` ("x" or "z") on line `fixed`, from a0 to a1, with openings
## [{c, w, sill, top, kind}] cut out (kind: window, door, open, pass).
func wall(axis: String, fixed: float, a0: float, a1: float, y0: float, h: float, t: float, mk: String, ops: Array) -> void:
	ops = ops.duplicate()
	ops.sort_custom(func(a, b): return a.c < b.c)
	var cur := a0
	for op in ops:
		var o0: float = max(a0, op.c - op.w * 0.5)
		var o1: float = min(a1, op.c + op.w * 0.5)
		if o1 <= o0:
			continue
		_wall_piece(axis, fixed, cur, o0, y0, 0.0, h, t, mk)
		if op.sill > 0.0:
			_wall_piece(axis, fixed, o0, o1, y0, 0.0, op.sill, t, mk)
		if op.top < h:
			_wall_piece(axis, fixed, o0, o1, y0, op.top, h, t, mk)
		if op.kind == "window":
			_window(axis, fixed, o0, o1, y0 + op.sill, y0 + op.top)
		cur = o1
	_wall_piece(axis, fixed, cur, a1, y0, 0.0, h, t, mk)


## Visual-only 1 cm plaster skin over the inside face of an exterior wall
## (box() drops anything under 5 mm, so the old 4 mm skin never rendered),
## with the same openings cut out. No collision: the wall already has it.
func _lining(axis: String, fixed: float, a0: float, a1: float, y0: float, h: float, ops: Array) -> void:
	var t := LINING_T
	var cur := a0
	var sorted := ops.duplicate()
	sorted.sort_custom(func(a, b): return a.c < b.c)
	for op in sorted:
		var o0: float = max(a0, op.c - op.w * 0.5)
		var o1: float = min(a1, op.c + op.w * 0.5)
		if o1 <= o0:
			continue
		_skin(axis, fixed, cur, o0, y0, 0.0, h, t)
		if op.sill > 0.0:
			_skin(axis, fixed, o0, o1, y0, 0.0, op.sill, t)
		if op.top < h:
			_skin(axis, fixed, o0, o1, y0, op.top, h, t)
		_reveal(axis, fixed, o0, o1, y0, op.sill, minf(op.top, h))
		cur = o1
	_skin(axis, fixed, cur, a1, y0, 0.0, h, t)


## Plaster on the room-side half of an exterior opening's reveals (jambs, sill
## and head). Without it the bright facade stucco frames every window and door
## indoors, which doesn't match the painted walls around it. `fixed` is the
## lining's line; the facade's centre line lies further out by EXT_T/2 + LINING_T/2.
func _reveal(axis: String, fixed: float, o0: float, o1: float, y0: float, sill: float, top: float) -> void:
	var t := LINING_T
	var out := signf(fixed)
	var n0 := fixed + out * (EXT_T * 0.5 + LINING_T * 0.5)  # facade centre line
	var n1 := fixed - out * LINING_T * 0.5         # room face of the lining
	var nc := (n0 + n1) * 0.5
	var depth := absf(n0 - n1)
	var pieces := [
		[o0 + t * 0.5, t, sill, top],                 # jambs
		[o1 - t * 0.5, t, sill, top],
	]
	if sill > 0.0:
		pieces.append([(o0 + o1) * 0.5, o1 - o0, sill, sill + t])    # sill
	pieces.append([(o0 + o1) * 0.5, o1 - o0, top - t, top])          # head
	for p in pieces:
		var a: float = p[0]
		var len: float = p[1]
		var yb: float = p[2]
		var ye: float = p[3]
		if ye - yb < 0.003:
			continue
		var c := Vector3(a, y0 + (yb + ye) * 0.5, nc) if axis == "x" else Vector3(nc, y0 + (yb + ye) * 0.5, a)
		var sz := Vector3(len, ye - yb, depth) if axis == "x" else Vector3(depth, ye - yb, len)
		box(c, sz, "int", false)


func _skin(axis: String, fixed: float, a0: float, a1: float, y0: float, b: float, e: float, t: float) -> void:
	if a1 - a0 < 0.01 or e - b < 0.01:
		return
	var mid := (a0 + a1) * 0.5
	var c := Vector3(mid, y0 + (b + e) * 0.5, fixed) if axis == "x" else Vector3(fixed, y0 + (b + e) * 0.5, mid)
	var sz := Vector3(a1 - a0, e - b, t) if axis == "x" else Vector3(t, e - b, a1 - a0)
	box(c, sz, "int", false)


func _wall_piece(axis: String, fixed: float, a0: float, a1: float, y0: float, b: float, e: float, t: float, mk: String) -> void:
	if a1 - a0 < 0.01 or e - b < 0.01:
		return
	var mid := (a0 + a1) * 0.5
	var c := Vector3(mid, y0 + (b + e) * 0.5, fixed) if axis == "x" else Vector3(fixed, y0 + (b + e) * 0.5, mid)
	var s := Vector3(a1 - a0, e - b, t) if axis == "x" else Vector3(t, e - b, a1 - a0)
	box(c, s, mk)


func _window(axis: String, fixed: float, a0: float, a1: float, yb: float, yt: float) -> void:
	var mid := (a0 + a1) * 0.5
	var w := a1 - a0
	var h := yt - yb
	var fr := 0.06
	if axis == "x":
		box(Vector3(mid, (yb + yt) * 0.5, fixed), Vector3(w, h, 0.03), "glass")
		box(Vector3(mid, yb + fr * 0.5, fixed), Vector3(w, fr, 0.12), "frame", false)
		box(Vector3(mid, yt - fr * 0.5, fixed), Vector3(w, fr, 0.12), "frame", false)
		box(Vector3(a0 + fr * 0.5, (yb + yt) * 0.5, fixed), Vector3(fr, h, 0.12), "frame", false)
		box(Vector3(a1 - fr * 0.5, (yb + yt) * 0.5, fixed), Vector3(fr, h, 0.12), "frame", false)
		box(Vector3(mid, (yb + yt) * 0.5, fixed), Vector3(0.04, h, 0.1), "frame", false)
	else:
		box(Vector3(fixed, (yb + yt) * 0.5, mid), Vector3(0.03, h, w), "glass")
		box(Vector3(fixed, yb + fr * 0.5, mid), Vector3(0.12, fr, w), "frame", false)
		box(Vector3(fixed, yt - fr * 0.5, mid), Vector3(0.12, fr, w), "frame", false)
		box(Vector3(fixed, (yb + yt) * 0.5, a0 + fr * 0.5), Vector3(0.12, h, fr), "frame", false)
		box(Vector3(fixed, (yb + yt) * 0.5, a1 - fr * 0.5), Vector3(0.12, h, fr), "frame", false)
		box(Vector3(fixed, (yb + yt) * 0.5, mid), Vector3(0.1, h, 0.04), "frame", false)


## Visual-only square bar of side `w` from p0 to p1 at any angle (box() is
## axis-aligned only). Used for the sloped stair handrails.
func _bar(p0: Vector3, p1: Vector3, w: float, mk: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Handrail"
	var bm := BoxMesh.new()
	bm.size = Vector3(w, w, p0.distance_to(p1))
	bm.material = mats[mk]
	mi.mesh = bm
	mi.transform = Transform3D(Basis.looking_at(p1 - p0, Vector3.UP), (p0 + p1) * 0.5)
	root_node.add_child(mi, true)


func _ramp(p0: Vector3, p1: Vector3, width: float, extend_bottom: float) -> void:
	var dir := (p1 - p0).normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	var a := p0 - dir * extend_bottom
	var length := a.distance_to(p1)
	var thick := 0.15
	var center := (a + p1) * 0.5 - up * thick * 0.5
	_shape(Transform3D(Basis(side, up, -dir), center), Vector3(width, thick, length), LAYER_WORLD)


## Hinged door in an opening centred at `c` (floor level) on a wall running
## along `along` (unit X or Z). It swings towards the side containing `toward`.
func add_door(label: String, c: Vector3, along: Vector3, opening_w: float, toward: Vector3, mk := "door") -> void:
	var w := opening_w - 0.06
	var h := 2.1
	var hinge := c - along * w * 0.5
	var closed_yaw := atan2(-along.z, along.x)
	var normal := Vector3(-along.z, 0, along.x)
	var side := signf((toward - c).dot(normal))
	if side == 0.0:
		side = 1.0
	var door := Node3D.new()
	door.name = label.validate_node_name()
	door.set_script(load("res://building/door.gd"))
	door.set("closed_yaw", closed_yaw)
	door.set("open_yaw", closed_yaw - side * PI * 0.5)
	door.transform = Transform3D(Basis(Vector3.UP, closed_yaw), hinge + Vector3.UP * 0.01)
	interactive.add_child(door, true)
	var leaf := AnimatableBody3D.new()
	leaf.name = "Leaf"
	leaf.collision_layer = LAYER_DOORS
	leaf.collision_mask = 0
	leaf.sync_to_physics = false
	door.add_child(leaf)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, h, 0.05)
	cs.shape = bs
	cs.position = Vector3(w * 0.5, h * 0.5, 0)
	leaf.add_child(cs)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var bm := BoxMesh.new()
	bm.size = bs.size
	bm.material = mats[mk]
	mesh.mesh = bm
	mesh.position = cs.position
	leaf.add_child(mesh)
	var knob := MeshInstance3D.new()
	knob.name = "Handle"
	var km := BoxMesh.new()
	km.size = Vector3(0.12, 0.04, 0.14)
	km.material = mats["metal"]
	knob.mesh = km
	knob.position = Vector3(w - 0.12, 1.0, 0)
	leaf.add_child(knob)


# ---------------------------------------------------------------- floor plan

func _plan_walls() -> void:
	for r in ROOMS:
		var f: int = r[0]
		var t: String = r[2]
		var x0: float = r[3]
		var z0: float = r[4]
		var x1: float = r[5]
		var z1: float = r[6]
		var front := z0 >= CORR - 0.01
		var corridor_z := z0 if front else z1
		# Edges (exterior lines are built by the facade).
		_edge("x", z0, x0, x1, f, t == "lobby" and front)
		_edge("x", z1, x0, x1, f, t == "lobby" and not front)
		_edge("z", x0, z0, z1, f, false)
		_edge("z", x1, z0, z1, f, false)
		# Doors on the corridor wall.
		if t != "lobby":
			var centers := [x0 + 1.0]
			if x1 - x0 >= 8.9:
				centers.append(x1 - 1.0)
			for i in centers.size():
				openings.append({"floor": f, "axis": "x", "fixed": corridor_z, "c": centers[i], "w": 1.0, "sill": 0.0, "top": 2.2, "kind": "door",
					"room": r, "label": "Door %s %s %d" % [FLOOR_NAMES[f], r[1], i + 1]})
		# Computer labs: glass panels in the corridor wall so you can see in.
		if t == "complab":
			var doors_x := [x0 + 1.0]
			if x1 - x0 >= 8.9:
				doors_x.append(x1 - 1.0)
			var c := x0 + 1.2
			while c + 0.9 <= x1 - 0.3:
				var clear := true
				for dx in doors_x:
					if absf(c - dx) < 1.6:
						clear = false
				if clear:
					openings.append({"floor": f, "axis": "x", "fixed": corridor_z, "c": c, "w": 1.8, "sill": 0.9, "top": 2.3, "kind": "window"})
					c += 2.2
				else:
					c += 0.1
		# Service windows from the offices into the lobby.
		if t == "admissions":
			openings.append({"floor": f, "axis": "z", "fixed": x1, "c": 4.6, "w": 2.0, "sill": 1.0, "top": 2.1, "kind": "pass"})
		if t == "cashier":
			openings.append({"floor": f, "axis": "z", "fixed": x0, "c": 4.6, "w": 2.0, "sill": 1.0, "top": 2.1, "kind": "pass"})
		room_info.append([r[1], f, x0, z0, x1, z1])
	for f in FLOORS:
		room_info.append(["Corridor", f, X0, -CORR, X1, CORR])
	for s in STAIRS:
		var sd: Dictionary = STAIRS[s]
		var top: int = sd.top_floor
		for f in min(top + 1, FLOORS):
			var inner_x: float = sd.x1 if sd.x0 < 0 else sd.x0
			_edge("z", inner_x, Z0, -CORR, f, false)
			_edge("x", -CORR, sd.x0, sd.x1, f, false)
			openings.append({"floor": f, "axis": "x", "fixed": -CORR, "c": (sd.x0 + sd.x1) * 0.5, "w": 2.4, "sill": 0.0, "top": 2.6, "kind": "open"})
			room_info.append([s, f, sd.x0, Z0, sd.x1, -CORR])


func _edge(axis: String, fixed: float, a0: float, a1: float, f: int, skip: bool) -> void:
	if skip:
		return
	if axis == "x" and (absf(fixed - Z0) < 0.01 or absf(fixed - Z1) < 0.01):
		return
	if axis == "z" and (absf(fixed - X0) < 0.01 or absf(fixed - X1) < 0.01):
		return
	var key := "%s|%.2f|%d" % [axis, fixed, f]
	if not int_edges.has(key):
		int_edges[key] = []
	int_edges[key].append([a0, a1])


func _build_floor(f: int) -> void:
	var y0 := f * FH
	var h := FH - SLAB
	for key in int_edges:
		var parts: PackedStringArray = key.split("|")
		if int(parts[2]) != f:
			continue
		var axis := parts[0]
		var fixed := float(parts[1])
		var spans: Array = int_edges[key]
		spans.sort_custom(func(a, b): return a[0] < b[0])
		var merged := []
		for s in spans:
			if merged.size() > 0 and s[0] <= merged[-1][1] + 0.01:
				merged[-1][1] = max(merged[-1][1], s[1])
			else:
				merged.append([s[0], s[1]])
		for m in merged:
			var ops := []
			for op in openings:
				if op.floor == f and op.axis == axis and absf(op.fixed - fixed) < 0.01 and op.c > m[0] and op.c < m[1]:
					ops.append(op)
			wall(axis, fixed, m[0], m[1], y0, h, INT_T, "int", ops)
			for op in ops:
				if op.kind == "door":
					_room_door(op, y0)
				elif op.kind == "pass":
					# Ledge sits ON the sill (y0 + sill .. +4 cm); sinking it into
					# the sill made its top coplanar with the wall's and flicker.
					var c: Vector3 = Vector3(fixed, y0 + op.sill + 0.02, op.c)
					box(c, Vector3(0.45, 0.04, op.w), "wood")


func _room_door(op: Dictionary, y0: float) -> void:
	var r: Array = op.room
	var inside := Vector3((r[3] + r[5]) * 0.5, y0, (r[4] + r[6]) * 0.5)
	var c := Vector3(op.c, y0, op.fixed)
	# Hinge on the side nearest the room's corner so the open door folds
	# against the side wall instead of blocking the room.
	var near_west: bool = op.c - r[3] < r[5] - op.c
	add_door(op.label, c, Vector3.RIGHT if near_west else Vector3.LEFT, op.w, inside)


func _build_slabs() -> void:
	# Ground slab
	box(Vector3(0, -SLAB * 0.5, 0), Vector3(X1 - X0, SLAB, Z1 - Z0), "slab")
	for lvl in range(1, FLOORS + 1):
		var holes := []
		for s in STAIRS:
			var sd: Dictionary = STAIRS[s]
			if lvl <= sd.top_floor:
				holes.append(_stair_hole(sd))
		var y := lvl * FH - SLAB * 0.5
		for cell in _rect_minus(Rect2(X0, Z0, X1 - X0, Z1 - Z0), holes):
			box(Vector3(cell.get_center().x, y, cell.get_center().y), Vector3(cell.size.x, SLAB, cell.size.y), "ceiling")
		if lvl == FLOORS:
			# roof deck finish
			for cell in _rect_minus(Rect2(X0, Z0, X1 - X0, Z1 - Z0), holes):
				box(Vector3(cell.get_center().x, lvl * FH + 0.005, cell.get_center().y), Vector3(cell.size.x, 0.01, cell.size.y), "pavement", false)
	# corridor + stairwell floor finishes
	for f in FLOORS:
		_floor_finish(Rect2(X0, -CORR, X1 - X0, 2 * CORR), f, "floor")
		for sname in STAIRS:
			var sd: Dictionary = STAIRS[sname]
			if f > sd.top_floor:
				continue
			if f == 0:
				_floor_finish(Rect2(sd.x0, Z0, sd.x1 - sd.x0, -CORR - Z0), f, "floor_kitchen")
			else:
				_floor_finish(Rect2(sd.x0, STAIR_EDGE, sd.x1 - sd.x0, -CORR - STAIR_EDGE), f, "floor_kitchen")


## Thin, non-colliding floor finish (tiles, laminate...) on top of a slab.
func _floor_finish(r: Rect2, f: int, mk: String) -> void:
	box(Vector3(r.get_center().x, f * FH + 0.005, r.get_center().y), Vector3(r.size.x, 0.01, r.size.y), mk, false)


func _stair_interior(sd: Dictionary) -> Vector2:
	var ix0: float = sd.x0 + (EXT_T * 0.5 if absf(sd.x0 - X0) < 0.01 else INT_T * 0.5)
	var ix1: float = sd.x1 - (EXT_T * 0.5 if absf(sd.x1 - X1) < 0.01 else INT_T * 0.5)
	return Vector2(ix0, ix1)


## Opening in the slabs above a stairwell. Edges on an exterior wall run to the
## wall's centre line: stopping at its inner face would leave a slab sliver
## buried in the wall whose end face z-fights with the wall's inner face.
func _stair_hole(sd: Dictionary) -> Rect2:
	var ix := _stair_interior(sd)
	var hx0: float = X0 if absf(sd.x0 - X0) < 0.01 else ix.x
	var hx1: float = X1 if absf(sd.x1 - X1) < 0.01 else ix.y
	return Rect2(hx0, Z0, hx1 - hx0, STAIR_EDGE - Z0)


func _rect_minus(r: Rect2, holes: Array) -> Array:
	var xs := [r.position.x, r.end.x]
	var zs := [r.position.y, r.end.y]
	for h in holes:
		xs.append_array([h.position.x, h.end.x])
		zs.append_array([h.position.y, h.end.y])
	xs.sort()
	zs.sort()
	var out := []
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var cell := Rect2(xs[i], zs[j], xs[i + 1] - xs[i], zs[j + 1] - zs[j])
			if cell.size.x < 0.01 or cell.size.y < 0.01:
				continue
			var inside_hole := false
			for h in holes:
				if h.has_point(cell.get_center()):
					inside_hole = true
			if not inside_hole:
				out.append(cell)
	return out


# ---------------------------------------------------------------- stairs

func _build_stairwell(sname: String) -> void:
	var sd: Dictionary = STAIRS[sname]
	var ix := _stair_interior(sd)
	var mid := (ix.x + ix.y) * 0.5
	var west: bool = sd.x0 < 0
	# Band A (inner, goes up from the floor), band B (outer, up from landing).
	var band_a := Vector2(mid + 0.1, ix.y) if west else Vector2(ix.x, mid - 0.1)
	var band_b := Vector2(ix.x, mid - 0.1) if west else Vector2(mid + 0.1, ix.y)
	var zb := Z0 + EXT_T * 0.5
	var n_steps := 12
	var run := STAIR_EDGE - LANDING_EDGE
	var rise := FH * 0.5 / n_steps
	var tread := run / n_steps
	var top: int = sd.top_floor
	for f in top:
		var y0 := f * FH
		var ym := y0 + FH * 0.5
		var y1 := y0 + FH
		var ca := (band_a.x + band_a.y) * 0.5
		var cb := (band_b.x + band_b.y) * 0.5
		var wa := band_a.y - band_a.x
		var wb := band_b.y - band_b.x
		for i in n_steps:
			# Flight A: corridor side -> landing
			var za := STAIR_EDGE - (i + 0.5) * tread
			var ta := y0 + (i + 1) * rise
			var ba := y0 if f == 0 else ta - 0.3
			box(Vector3(ca, (ta + ba) * 0.5, za), Vector3(wa, ta - ba, tread), "slab", false)
			_stair_tread(ca, ta, za, wa, tread, 1.0)
			# Flight B: landing -> next floor
			var zbb := LANDING_EDGE + (i + 0.5) * tread
			var tb := ym + (i + 1) * rise
			box(Vector3(cb, tb - 0.15, zbb), Vector3(wb, 0.3, tread), "slab", false)
			_stair_tread(cb, tb, zbb, wb, tread, -1.0)
		_ramp(Vector3(ca, y0, STAIR_EDGE), Vector3(ca, ym, LANDING_EDGE), wa, 0.3)
		_ramp(Vector3(cb, ym, LANDING_EDGE), Vector3(cb, y1, STAIR_EDGE), wb, 0.3)
		# Landing
		box(Vector3((ix.x + ix.y) * 0.5, ym - 0.1, (zb + LANDING_EDGE) * 0.5), Vector3(ix.y - ix.x, 0.2, LANDING_EDGE - zb), "slab")
		box(Vector3((ix.x + ix.y) * 0.5, ym + 0.005, (zb + LANDING_EDGE) * 0.5), Vector3(ix.y - ix.x, 0.01, LANDING_EDGE - zb), "floor_kitchen", false)
		# Divider between the flights (taller on the last flight = guard rail)
		var dh := FH + (1.05 if f == top - 1 else 0.0)
		box(Vector3(mid, y0 + dh * 0.5, (STAIR_EDGE + LANDING_EDGE) * 0.5), Vector3(0.2, dh, run), "int")
		# Handrail on the outer wall, following flight B's pitch 0.9 m above the
		# nosings (it used to be a level bar at mid-flight height, 1.9 m above
		# the landing). Wall brackets at both ends.
		var rx: float = band_b.x + 0.06 if west else band_b.y - 0.06
		var wx: float = band_b.x if west else band_b.y
		var r0 := Vector3(rx, ym + 0.9, LANDING_EDGE + 0.15)
		var r1 := Vector3(rx, y1 + 0.9, STAIR_EDGE - 0.15)
		_bar(r0, r1, 0.05, "rail")
		for t: float in [0.1, 0.9]:
			var bp := r0.lerp(r1, t) + Vector3.DOWN * 0.04
			box(Vector3((bp.x + wx) * 0.5, bp.y, bp.z), Vector3(absf(bp.x - wx), 0.02, 0.02), "rail", false)
		_light(Vector3(mid, ym + 2.3, (zb + LANDING_EDGE) * 0.5), 6.0, 0.7)
	# Guard rail where the top floor overlooks flight A below.
	var ytop := top * FH
	var ca2 := (band_a.x + band_a.y) * 0.5
	box(Vector3(ca2, ytop + 0.525, STAIR_EDGE - 0.03), Vector3(band_a.y - band_a.x, 1.05, 0.06), "rail")
	# Exterior fire exit on 1F (side wall, under flight B).
	var side_x: float = X0 if west else X1
	var exit_c := Vector3(side_x, 0.0, -2.6)
	var outward := Vector3(side_x + (-3.0 if west else 3.0), 0, -2.6)
	add_door("Fire Exit %s" % sname, exit_c, Vector3.BACK, 1.0, outward)


## Tiled tread on a concrete step: straight-laid anti-skid tiles (the
## corridors' diagonal tiles looked wrong cut to 33 cm treads) with a dark
## anti-slip nosing strip along its front edge. `down` is the
## direction along Z towards the step below (+1 or -1).
func _stair_tread(cx: float, top: float, cz: float, w: float, depth: float, down: float) -> void:
	box(Vector3(cx, top + 0.005, cz), Vector3(w, 0.01, depth), "floor_kitchen", false)
	var nose := 0.035
	box(Vector3(cx, top + 0.013, cz + down * (depth * 0.5 - nose * 0.5)), Vector3(w - 0.04, 0.006, nose), "dark", false)


# ---------------------------------------------------------------- roof

func _build_roof() -> void:
	var y := FLOORS * FH
	# Parapet
	var ph := 1.1
	for side in [[Vector3(0, 0, Z1), Vector3(X1 - X0, 0, 0)], [Vector3(0, 0, Z0), Vector3(X1 - X0, 0, 0)],
			[Vector3(X0, 0, 0), Vector3(0, 0, Z1 - Z0)], [Vector3(X1, 0, 0), Vector3(0, 0, Z1 - Z0)]]:
		var c: Vector3 = side[0]
		var len: Vector3 = side[1]
		var size := Vector3(max(len.x, EXT_T), ph, max(len.z, EXT_T))
		box(Vector3(c.x, y + ph * 0.5, c.z), size, "ext")
		box(Vector3(c.x, y + ph + 0.04, c.z), size * Vector3(1, 0, 1) + Vector3(0.1 if len.x == 0 else 0.0, 0.08, 0.1 if len.z == 0 else 0.0), "yellow")
	# Stair hut over the east stairwell
	var sd: Dictionary = STAIRS["East Stairwell"]
	var hh := 3.0
	var hx0: float = sd.x0
	var hx1: float = sd.x1
	var ix := _stair_interior(sd)
	var door_x := (ix.x + ix.y) * 0.5 + 0.1 + ((ix.y - ((ix.x + ix.y) * 0.5 + 0.1)) * 0.5)
	wall("z", hx0, Z0, -CORR, y, hh, INT_T, "ext", [{"c": -6.7, "w": 1.2, "sill": 1.2, "top": 2.2, "kind": "window"}])
	wall("x", -CORR, hx0, hx1, y, hh, INT_T, "ext", [{"c": door_x, "w": 1.0, "sill": 0.0, "top": 2.2, "kind": "door"}])
	wall("z", hx1, Z0, -CORR, y, hh, EXT_T, "ext", [])
	wall("x", Z0, hx0, hx1, y, hh, EXT_T, "ext", [])
	box(Vector3((hx0 + hx1) * 0.5, y + hh + 0.12, (Z0 - CORR) * 0.5), Vector3(hx1 - hx0 + 0.3, 0.25, -CORR - Z0 + 0.3), "slab")
	box(Vector3((hx0 + hx1) * 0.5, y + hh - 0.25, (Z0 - CORR) * 0.5 + 0.0), Vector3(hx1 - hx0 + 0.32, 0.5, -CORR - Z0 + 0.32), "blue", false)
	add_door("Roof Door", Vector3(door_x, y, -CORR), Vector3.RIGHT, 1.0, Vector3(door_x, y, 2.0))
	# Water tank + AC condensers (cover on the roof)
	box(Vector3(-8.0, y + 0.3, -5.0), Vector3(2.4, 0.6, 2.4), "metal")
	box(Vector3(-8.0, y + 1.5, -5.0), Vector3(2.0, 1.8, 2.0), "blue")
	for i in 4:
		box(Vector3(-3.0 + i * 2.2, y + 0.45, -6.8), Vector3(1.0, 0.9, 0.6), "ac")
	box(Vector3(4.0, y + 0.5, 4.0), Vector3(3.0, 1.0, 1.5), "metal")
	_light(Vector3((hx0 + hx1) * 0.5, y + 2.5, -4.5), 5.0, 0.6)


# ---------------------------------------------------------------- facade

func _build_facade() -> void:
	var slots := []
	var s := X0 + 1.5
	while s < X1:
		slots.append(s)
		s += 3.0
	for f in FLOORS:
		var y0 := f * FH
		var front_ops := []
		var rear_ops := []
		var west_ops := []
		var east_ops := []
		for sx in slots:
			var rf = _room_at(f, sx, 5.0)
			if rf != null:
				if rf[2] == "lobby":
					if sx < 0.0:
						front_ops.append({"c": 0.0, "w": 3.6, "sill": 0.0, "top": 2.5, "kind": "door"})
						_sliding_door()
				else:
					front_ops.append(_window_spec(rf[2]))
					front_ops[-1].c = sx
			var rr = _room_at(f, sx, -5.0)
			if rr != null:
				var spec := _window_spec(rr[2])
				spec.c = sx
				rear_ops.append(spec)
			elif _stair_at(f, sx) != "":
				rear_ops.append({"c": sx, "w": 0.8, "sill": 2.45, "top": 3.4, "kind": "window"})
		for side in [[X0, west_ops], [X1, east_ops]]:
			var x: float = side[0]
			var ops: Array = side[1]
			var rf2 = _room_at(f, x * 0.99, 4.6)
			if rf2 != null:
				var spec2 := _window_spec(rf2[2])
				spec2.c = 4.6
				ops.append(spec2)
			ops.append({"c": 0.0, "w": 1.0, "sill": 0.5, "top": 2.8, "kind": "window"}) # corridor end: tall and narrow
			if _stair_at(f, x * 0.99) != "":
				ops.append({"c": -6.7, "w": 0.8, "sill": 2.45, "top": 3.4, "kind": "window"})
				if f == 0:
					ops.append({"c": -2.6, "w": 1.0, "sill": 0.0, "top": 2.2, "kind": "door"})
			elif f > 0:
				ops.append({"c": -4.6, "w": 2.4, "sill": 0.9, "top": 2.4, "kind": "window"})
		wall("x", Z1, X0, X1, y0, FH, EXT_T, "ext", front_ops)
		wall("x", Z0, X0, X1, y0, FH, EXT_T, "ext", rear_ops)
		wall("z", X0, Z0 + EXT_T * 0.5, Z1 - EXT_T * 0.5, y0, FH, EXT_T, "ext", west_ops)
		wall("z", X1, Z0 + EXT_T * 0.5, Z1 - EXT_T * 0.5, y0, FH, EXT_T, "ext", east_ops)
		# The facade is stucco on both faces of one box; line the room side
		# with painted plaster so no room shows rough render indoors.
		var inner := EXT_T * 0.5 + LINING_T * 0.5
		_lining("x", Z1 - inner, X0 + EXT_T * 0.5, X1 - EXT_T * 0.5, y0, FH, front_ops)
		_lining("x", Z0 + inner, X0 + EXT_T * 0.5, X1 - EXT_T * 0.5, y0, FH, rear_ops)
		_lining("z", X0 + inner, Z0 + EXT_T * 0.5, Z1 - EXT_T * 0.5, y0, FH, west_ops)
		_lining("z", X1 - inner, Z0 + EXT_T * 0.5, Z1 - EXT_T * 0.5, y0, FH, east_ops)
		# Floor bands
		if f > 0:
			_band(y0 - 0.3, 0.35, "yellow", 0.1)
		# AC units under some front windows on the upper floors
		if f > 0:
			for i in slots.size():
				if i % 2 == 1 and _room_at(f, slots[i], 5.0) != null:
					box(Vector3(slots[i], y0 + 0.55, Z1 + 0.35), Vector3(0.75, 0.45, 0.5), "ac")
	_band(FLOORS * FH - 0.35, 0.95, "blue", 0.1)  # 0.12 put its face 5 mm from the pillars' -> flicker
	# Navy pillars on the front (the centre one starts above the entrance canopy)
	var ptop := FLOORS * FH + 1.2
	for px in [X0, -6.0, 0.0, 6.0, X1]:
		var pb := 3.1 if px == 0.0 else 0.0
		box(Vector3(px, (pb + ptop) * 0.5, Z1 + 0.25), Vector3(0.5, ptop - pb, 0.5), "navy")
	for pz in [Z0]:
		for px in [X0, X1]:
			box(Vector3(px, (FLOORS * FH + 1.2) * 0.5, pz), Vector3(0.5, FLOORS * FH + 1.2, 0.5), "navy")
	# Entrance canopy (signs are added in _build_signs)
	box(Vector3(0, 3.0, Z1 + 1.0), Vector3(7.0, 0.2, 2.0), "slab")
	box(Vector3(0, 3.0, Z1 + 1.98), Vector3(7.0, 0.3, 0.06), "yellow", false)


## Automatic sliding glass entrance: two leaves slide behind fixed side panels.
func _sliding_door() -> void:
	var node := Node3D.new()
	node.name = "Main Entrance"
	node.set_script(load("res://building/sliding_door.gd"))
	node.position = Vector3(0, 0, Z1)
	interactive.add_child(node, true)
	var h := 2.45
	for side in [-1, 1]:
		var leaf := AnimatableBody3D.new()
		leaf.name = "LeftLeaf" if side < 0 else "RightLeaf"
		leaf.collision_layer = LAYER_DOORS
		leaf.collision_mask = 0
		leaf.sync_to_physics = false
		leaf.position = Vector3(side * 0.45, 0, -0.05)
		node.add_child(leaf)
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.9, h, 0.04)
		cs.shape = bs
		cs.position = Vector3(0, h * 0.5, 0)
		leaf.add_child(cs)
		_mesh_child(leaf, "Glass", Vector3(0.9, h, 0.03), Vector3(0, h * 0.5, 0), "glass")
		_mesh_child(leaf, "FrameTop", Vector3(0.9, 0.06, 0.05), Vector3(0, h - 0.03, 0), "frame")
		_mesh_child(leaf, "FrameBottom", Vector3(0.9, 0.1, 0.05), Vector3(0, 0.05, 0), "frame")
		_mesh_child(leaf, "FrameEdge", Vector3(0.05, h, 0.05), Vector3(-side * 0.425, h * 0.5, 0), "frame")
		_mesh_child(leaf, "Handle", Vector3(0.03, 0.6, 0.06), Vector3(-side * 0.35, 1.05, 0), "metal")
		# fixed side panel (the open leaf slides behind it)
		box(Vector3(side * 1.35, h * 0.5, Z1 + 0.05), Vector3(0.9, h, 0.03), "glass")
		box(Vector3(side * 1.775, h * 0.5, Z1), Vector3(0.05, h, 0.2), "frame", false)
	box(Vector3(0, h + 0.03, Z1), Vector3(3.6, 0.08, 0.22), "frame", false)
	var sensor := Area3D.new()
	sensor.name = "Sensor"
	sensor.collision_layer = 0
	sensor.collision_mask = 4 # player (put AI characters on this layer too)
	sensor.monitorable = false
	node.add_child(sensor)
	var scs := CollisionShape3D.new()
	scs.name = "CollisionShape3D"
	var sb := BoxShape3D.new()
	sb.size = Vector3(4.0, 2.4, 5.0)
	scs.shape = sb
	scs.position = Vector3(0, 1.2, 0)
	sensor.add_child(scs)


func _mesh_child(parent: Node3D, label: String, size: Vector3, pos: Vector3, mk: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = label
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mats[mk]
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)


## Decorative band wrapped around the outside of the building. It starts at the
## wall's centre line so it never shows on the inside face.
func _band(y: float, h: float, mk: String, out: float) -> void:
	var t := EXT_T * 0.5 + out
	var o := t * 0.5
	box(Vector3(0, y + h * 0.5, Z1 + o), Vector3(X1 - X0 + t * 2, h, t), mk, false)
	box(Vector3(0, y + h * 0.5, Z0 - o), Vector3(X1 - X0 + t * 2, h, t), mk, false)
	box(Vector3(X0 - o, y + h * 0.5, 0), Vector3(t, h, Z1 - Z0), mk, false)
	box(Vector3(X1 + o, y + h * 0.5, 0), Vector3(t, h, Z1 - Z0), mk, false)


## Exterior window shapes. Rooms get wide ribbon windows (split into louvre
## panels by JalousieWindow); service rooms get a high privacy strip. Stair
## landings and corridor ends have their own tall, narrow ones (see
## _build_facade). Keep the strips under JalousieWindow.SMALL_WINDOW_HEIGHT
## (1.0 m) and the room windows over it: the AI uses that to decide which
## windows a creature can climb through.
func _window_spec(t: String) -> Dictionary:
	if t in ["restroom", "server", "pantry"]:
		return {"c": 0.0, "w": 1.6, "sill": 1.9, "top": 2.5, "kind": "window"}
	return {"c": 0.0, "w": 2.4, "sill": 0.9, "top": 2.4, "kind": "window"}


func _room_at(f: int, x: float, z: float):
	for r in ROOMS:
		if r[0] == f and x > r[3] and x < r[5] and z > r[4] and z < r[6]:
			return r
	return null


func _stair_at(f: int, x: float) -> String:
	for s in STAIRS:
		var sd: Dictionary = STAIRS[s]
		if x > sd.x0 and x < sd.x1 and f <= min(sd.top_floor, FLOORS - 1):
			return s
	return ""


func _build_site() -> void:
	# Sidewalk in front, planters between the pillars
	box(Vector3(0, -0.04, Z1 + 3.5), Vector3(X1 - X0 + 6.0, 0.1, 7.0), "pavement")
	for px in [-9.0, -3.8, 3.8, 9.0]:
		box(Vector3(px, 0.4, Z1 + 1.6), Vector3(1.6, 0.8, 0.7), "ext")
		var plant: Mesh = baked_prop("res://models/polyhaven/potted_plant_01/potted_plant_01.res")
		if plant == null:
			box(Vector3(px, 0.95, Z1 + 1.6), Vector3(1.3, 0.35, 0.5), "plant", false)
			continue
		# Two shrubs growing out of the concrete planter (pots sunk inside it).
		for k in [-0.38, 0.38]:
			static_mesh("Planter Shrub", plant, Transform3D(Basis(Vector3.UP, px * 1.7 + k * 3.0), Vector3(px + k, 0.8 - 0.32, Z1 + 1.6)))


## A baked prop mesh (tools/prepare_props.gd), or null when it is missing so
## callers can fall back to their box.
var _baked_props := {}


func baked_prop(path: String) -> Mesh:
	if not _baked_props.has(path):
		_baked_props[path] = load(path) if ResourceLoader.exists(path) else null
	return _baked_props[path]


## A static, non-colliding mesh in the building scene (under "Dressing").
func static_mesh(label: String, mesh: Mesh, xf: Transform3D) -> MeshInstance3D:
	var parent: Node3D = root_node.get_node_or_null("Dressing")
	if parent == null:
		parent = Node3D.new()
		parent.name = "Dressing"
		root_node.add_child(parent)
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = mesh
	mi.transform = xf
	parent.add_child(mi, true)
	return mi


# ---------------------------------------------------------------- signs

var signs: Node3D


func _build_signs() -> void:
	signs = Node3D.new()
	signs.name = "Signs"
	root_node.add_child(signs)
	var navy := Color(0.07, 0.16, 0.45)
	var gold := Color(1.0, 0.8, 0.15)
	# Building name board, in front of the pillars at the roof band
	var yb := FLOORS * FH + 0.45
	box(Vector3(0, yb, Z1 + 0.58), Vector3(11.0, 1.3, 0.12), "blue", false)
	box(Vector3(0, yb - 0.68, Z1 + 0.6), Vector3(11.0, 0.08, 0.14), "yellow", false)
	box(Vector3(0, yb + 0.68, Z1 + 0.6), Vector3(11.0, 0.08, 0.14), "yellow", false)
	_label("STI COLLEGE KALIBO", Vector3(0, yb, Z1 + 0.65), 0.0, 0.016, 64, Color.WHITE)
	# Entrance canopy sign
	box(Vector3(0, 3.48, Z1 + 1.96), Vector3(5.6, 0.75, 0.08), "blue", false)
	_label("STI College Kalibo", Vector3(0, 3.6, Z1 + 2.01), 0.0, 0.0065, 64, gold)
	_label("MAIN ENTRANCE  -  ADMISSIONS", Vector3(0, 3.27, Z1 + 2.01), 0.0, 0.003, 48, Color.WHITE)
	# Inside the lobby: exit sign over the entrance + building directory
	_exit_sign(Vector3(0, 2.75, Z1 - EXT_T * 0.5 - 0.03), PI)
	_directory(Vector3(-3.0 + INT_T * 0.5 + 0.02, 1.75, 2.4), PI * 0.5)
	# Room name plates over every room door (corridor side)
	for op in openings:
		if op.kind != "door" or not op.has("room"):
			continue
		var r: Array = op.room
		var front: bool = r[4] >= CORR - 0.01
		var face_z: float = op.fixed + (-1.0 if front else 1.0) * (INT_T * 0.5 + 0.02)
		var yaw := PI if front else 0.0
		var y: float = op.floor * FH + 2.48
		var board := navy
		var text: String = r[1]
		var icon := ""
		if text.begins_with("Male"):
			text = "Men's Restroom"
			board = Color(0.1, 0.35, 0.8)
			icon = "men"
		elif text.begins_with("Female"):
			text = "Women's Restroom"
			board = Color(0.85, 0.25, 0.55)
			icon = "women"
		_plate(Vector3(op.c, y, face_z), yaw, text.to_upper(), board, icon)
	# Stairwell signs (corridor side, above the opening)
	for sname in STAIRS:
		var sd: Dictionary = STAIRS[sname]
		for f in min(sd.top_floor + 1, FLOORS):
			var parts := ["STAIRS"]
			if f < sd.top_floor:
				parts.append("UP %s" % FLOOR_NAMES[f + 1])
			if f > 0:
				parts.append("DOWN %s" % FLOOR_NAMES[f - 1])
			_plate(Vector3((sd.x0 + sd.x1) * 0.5, f * FH + 2.9, -CORR + INT_T * 0.5 + 0.02), 0.0,
				"  -  ".join(parts), Color(0.1, 0.45, 0.25))
	# Big floor numbers on the corridor end walls
	for f in FLOORS:
		for side in [-1.0, 1.0]:
			var x: float = side * (X1 - EXT_T * 0.5 - 0.02)
			_label(FLOOR_NAMES[f], Vector3(x, f * FH + 3.05, 0), -side * PI * 0.5, 0.008, 64, navy)
	# Fire exits
	for side in [-1.0, 1.0]:
		var x2: float = side * (X1 - EXT_T * 0.5 - 0.03)
		_exit_sign(Vector3(x2, 2.45, -2.6), -side * PI * 0.5)
	# Roof access sign on the stair hut
	var sd2: Dictionary = STAIRS["East Stairwell"]
	var hx: float = (sd2.x0 + sd2.x1) * 0.5 - 0.6
	_plate(Vector3(hx, FLOORS * FH + 2.5, -CORR + INT_T * 0.5 + 0.02), 0.0, "ROOF ACCESS", Color(0.35, 0.36, 0.4))


var _sign_font: SystemFont = null


## Bold sans-serif for every sign; falls back through common system fonts.
func _font() -> SystemFont:
	if _sign_font == null:
		_sign_font = SystemFont.new()
		_sign_font.font_names = PackedStringArray(["Arial", "Segoe UI", "Helvetica", "Liberation Sans", "DejaVu Sans"])
		_sign_font.font_weight = 700
		_sign_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_sign_font.generate_mipmaps = true
	return _sign_font


## Rendered width of `text` in metres at a given cap size.
func _text_width(text: String, px: float, font_px: int) -> float:
	return _font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x * px


func _label(text: String, pos: Vector3, yaw: float, px: float, font_px: int, color: Color, width_m := 0.0) -> Label3D:
	# Rasterise at twice the size for crisp edges, same size in the world.
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation.y = yaw
	l.pixel_size = px * 0.5
	l.font_size = font_px * 2
	l.font = _font()
	l.outline_size = 0
	l.modulate = color
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if width_m > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = width_m / l.pixel_size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	signs.add_child(l, true)
	return l


func _sign_box(b: Basis, at: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.transform = Transform3D(b, at)
	signs.add_child(mi, true)


## Room / stair name plate: brushed aluminium frame, coloured face with a
## fine white keyline, bold white lettering sized to the text, two screws,
## and a pictogram for the restrooms (icon "men" / "women").
func _plate(pos: Vector3, yaw: float, text: String, color: Color, icon := "") -> void:
	var b := Basis(Vector3.UP, yaw)
	var px := 0.0024
	var font_px := 48
	var icon_w: float = 0.13 if icon != "" else 0.0
	var face_w: float = maxf(0.6, _text_width(text, px, font_px) + 0.17 + icon_w)
	var face_h := 0.26
	var alu := _mat(Color(0.7, 0.71, 0.73), 0.8, 0.38)
	var face := _mat(color, 0.0, 0.45)
	var white := _mat(Color(0.93, 0.93, 0.9), 0.0, 0.55)
	# `pos` is 2 cm off the wall: frame on the wall, face on the frame.
	_sign_box(b, pos + b * Vector3(0, 0, -0.014), Vector3(face_w + 0.03, face_h + 0.03, 0.012), alu)
	_sign_box(b, pos + b * Vector3(0, 0, -0.004), Vector3(face_w, face_h, 0.008), face)
	var inset := 0.016
	var line := 0.004
	for k in [-1.0, 1.0]:
		_sign_box(b, pos + b * Vector3(0, k * (face_h * 0.5 - inset), 0.0005), Vector3(face_w - inset * 2.0, line, 0.001), white)
		_sign_box(b, pos + b * Vector3(k * (face_w * 0.5 - inset), 0, 0.0005), Vector3(line, face_h - inset * 2.0, 0.001), white)
		var screw := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.006
		cm.bottom_radius = 0.006
		cm.height = 0.003
		cm.radial_segments = 12
		cm.material = alu
		screw.mesh = cm
		screw.transform = Transform3D(b * Basis(Vector3.RIGHT, PI * 0.5), pos + b * Vector3(k * (face_w * 0.5 - 0.035), 0, 0.0015))
		signs.add_child(screw, true)
	var text_x := icon_w * 0.5
	if icon != "":
		var ix: float = -face_w * 0.5 + 0.035 + icon_w * 0.5
		_pictogram(b, pos + b * Vector3(ix, 0.0, 0.001), icon, white)
	_label(text, pos + b * Vector3(text_x, 0, 0.0012), yaw, px, font_px, Color.WHITE)


## Standing figure for the restroom plates, about 14 cm tall.
func _pictogram(b: Basis, at: Vector3, icon: String, mat: Material) -> void:
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.016
	sm.height = 0.032
	sm.material = mat
	head.mesh = sm
	head.transform = Transform3D(b * Basis.from_scale(Vector3(1, 1, 0.15)), at + b * Vector3(0, 0.05, 0))
	signs.add_child(head, true)
	if icon == "women":
		var dress := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.012
		cm.bottom_radius = 0.034
		cm.height = 0.06
		cm.radial_segments = 16
		cm.material = mat
		dress.mesh = cm
		dress.transform = Transform3D(b * Basis.from_scale(Vector3(1, 1, 0.08)), at + b * Vector3(0, 0.002, 0))
		signs.add_child(dress, true)
	else:
		_sign_box(b, at + b * Vector3(0, 0.005, 0), Vector3(0.036, 0.05, 0.002), mat)
	for k in [-1.0, 1.0]:
		_sign_box(b, at + b * Vector3(k * 0.009, -0.05, 0), Vector3(0.012, 0.045, 0.002), mat)
		_sign_box(b, at + b * Vector3(k * 0.026, 0.01, 0), Vector3(0.008, 0.042, 0.002), mat)


func _exit_sign(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var mat := _mat(Color(0.05, 0.6, 0.25), 0.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.9, 0.35)
	mat.emission_energy_multiplier = 0.8
	# White housing, glowing green face.
	_sign_box(b, pos + b * Vector3(0, 0, -0.008), Vector3(0.64, 0.26, 0.05), _mat(Color(0.9, 0.9, 0.88), 0.0, 0.5))
	_sign_box(b, pos + b * Vector3(0, 0, 0.0), Vector3(0.6, 0.22, 0.04), mat)
	_label("EXIT", pos + b * Vector3(0, 0, 0.0215), yaw, 0.003, 48, Color.WHITE)


func _directory(pos: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.9, 1.5, 0.03)
	bm.material = _mat(Color(0.07, 0.16, 0.45), 0.0, 0.6)
	mi.mesh = bm
	mi.transform = Transform3D(b, pos)
	signs.add_child(mi, true)
	# Aluminium frame round the board.
	var alu := _mat(Color(0.7, 0.71, 0.73), 0.8, 0.38)
	for k in [-1.0, 1.0]:
		_sign_box(b, pos + b * Vector3(0, k * 0.765, 0.005), Vector3(1.96, 0.03, 0.04), alu)
		_sign_box(b, pos + b * Vector3(k * 0.965, 0, 0.005), Vector3(0.03, 1.5, 0.04), alu)
	var lines := ["BUILDING DIRECTORY", ""]
	lines.append("ROOF  -  Roof Deck (via East Stairs)")
	for f in range(FLOORS - 1, -1, -1):
		var names := []
		for r in ROOMS:
			if r[0] != f or r[2] == "lobby":
				continue
			var n: String = r[1]
			if r[2] == "restroom":
				n = "Restrooms"
			if not names.has(n):
				names.append(n)
		lines.append("%s  -  %s" % [FLOOR_NAMES[f], ", ".join(names)])
	_label("\n".join(lines), pos + b * Vector3(-0.85, 0.65, 0.02), yaw, 0.0016, 40, Color.WHITE, 1.7)


# ---------------------------------------------------------------- furniture

func _furnish(r: Array) -> void:
	var f: int = r[0]
	var front: bool = r[4] >= CORR - 0.01
	R = {"floor": f, "name": r[1], "type": r[2], "x0": r[3], "x1": r[5], "z0": r[4], "z1": r[6],
		"w": r[5] - r[3], "dep": r[6] - r[4], "cz": r[4] if front else r[6], "sgn": 1.0 if front else -1.0, "y": f * FH}
	R.mirror = R.type == "classroom" and absf(R.x0 - X0) < 0.01
	footprints = []
	surfaces = []
	clear_rects = []
	for op in openings:
		if op.kind == "door" and op.has("room") and op.room == r:
			var u: float = (R.x1 - op.c) if R.mirror else (op.c - R.x0)
			clear_rects.append([u - 0.7, -0.1, u + 0.7, 1.5])
	if R.type == "lobby":
		clear_rects.append([1.0, R.dep - 2.2, R.w - 1.0, R.dep + 0.1]) # sliding entrance
		clear_rects.append([-0.1, -0.1, R.w + 0.1, 1.4]) # open to the corridor
	_floor_finish(Rect2(R.x0, R.z0, R.w, R.dep), f, ROOM_FLOORS.get(R.type, "floor"))
	if R.type == "restroom":
		_wainscot(true)
	elif R.type == "kitchen":
		_wainscot(false)
	call("_f_" + R.type)
	var cx: float = (R.x0 + R.x1) * 0.5
	var cz: float = (R.z0 + R.z1) * 0.5
	_light(Vector3(cx, R.y + FH - SLAB - 0.35, cz), max(R.w, R.dep) * 0.85, 1.0)
	_place_loot()


## White wall tiles up to 1.5 m on the side walls (and the outside wall when
## include_outer, i.e. restrooms whose windows are high enough).
func _wainscot(include_outer: bool) -> void:
	var h := 1.5
	var y: float = R.y + h * 0.5
	for x in [R.x0, R.x1]:
		# Exterior walls carry the plaster lining, so tiles sit on top of it.
		var inset: float = EXT_T * 0.5 + LINING_T if (absf(x - X0) < 0.01 or absf(x - X1) < 0.01) else INT_T * 0.5
		var xi: float = x + (inset + 0.006) * (1.0 if x == R.x0 else -1.0)
		box(Vector3(xi, y, (R.z0 + R.z1) * 0.5), Vector3(0.01, h, R.dep - 0.2), "wall_tile", false)
	if include_outer:
		var zo: float = R.z1 if R.sgn > 0 else R.z0
		var zi: float = zo - R.sgn * (EXT_T * 0.5 + LINING_T + 0.006)
		box(Vector3((R.x0 + R.x1) * 0.5, y, zi), Vector3(R.w - 0.2, h, 0.01), "wall_tile", false)


func L(u: float, d: float, y: float) -> Vector3:
	var x: float = (R.x1 - u) if R.mirror else (R.x0 + u)
	return Vector3(x, R.y + y, R.cz + R.sgn * d)


## Furniture box in room-local coordinates: u along X from the room's west
## wall, d from the corridor wall towards the outside wall.
func furn(u: float, d: float, su: float, sd: float, h: float, mk: String, surface := false, y_off := 0.0, collide := true) -> bool:
	var rect := [u - su * 0.5, d - sd * 0.5, u + su * 0.5, d + sd * 0.5]
	if rect[0] < 0.05 or rect[2] > R.w - 0.05 or rect[1] < 0.05 or rect[3] > R.dep - 0.05:
		return false
	if y_off < 0.01:
		for c in clear_rects:
			if rect[0] < c[2] and rect[2] > c[0] and rect[1] < c[3] and rect[3] > c[1]:
				return false
		footprints.append(rect)
	box(L(u, d, y_off + h * 0.5), Vector3(su, h, sd), mk, collide)
	if surface:
		surfaces.append(L(u, d, y_off + h))
	return true


func monitor(u: float, d: float, y: float) -> void:
	box(L(u, d, y + 0.24), Vector3(0.54, 0.34, 0.03), "dark", false)
	box(L(u, d + 0.017 * 0.0, y + 0.245), Vector3(0.5, 0.3, 0.035), "screen", false)
	box(L(u, d, y + 0.04), Vector3(0.05, 0.1, 0.05), "dark", false)
	box(L(u, d, y + 0.005), Vector3(0.22, 0.01, 0.16), "dark", false)
	box(L(u, d - 0.3, y + 0.01), Vector3(0.44, 0.02, 0.14), "dark", false)


# ---------------------------------------------------------------- 3D models

const MODEL_INDEX := "res://models/polyhaven/index.json"
## Some downloads are authored at the wrong scale.
const MODEL_SCALE := {"steel_frame_shelves_01": 0.1}

var props_root: Node3D
var _model_index := {}
var _models := {}
var _model_aabbs := {}


func _model(model_name: String) -> PackedScene:
	if _models.has(model_name):
		return _models[model_name]
	if _model_index.is_empty() and FileAccess.file_exists(MODEL_INDEX):
		_model_index = JSON.parse_string(FileAccess.get_file_as_string(MODEL_INDEX))
	var ps: PackedScene = null
	if _model_index.has(model_name):
		ps = load(_model_index[model_name])
	_models[model_name] = ps
	if ps:
		var inst: Node = ps.instantiate()
		var first := true
		var a := AABB()
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var t := Transform3D()
			var p: Node = mi
			while p != inst:
				if p is Node3D:
					t = p.transform * t
				p = p.get_parent()
			var b: AABB = t * mi.get_aabb()
			a = b if first else a.merge(b)
			first = false
		_model_aabbs[model_name] = a
		inst.free()
	return ps


## Places a model at room-local (u, d), standing on y_off, turned so its front
## (+Z in glTF) faces local direction `face` (Vector2(du, dd)). Adds box
## collision and an optional loot surface on top. Returns the world AABB, or
## an empty AABB when the model is missing or the spot is blocked.
func prop(model_name: String, u: float, d: float, face: Vector2, y_off := 0.0, collide := true, surface := false, scale := 1.0, check := true) -> AABB:
	var ps := _model(model_name)
	if ps == null:
		return AABB()
	var s: float = scale * MODEL_SCALE.get(model_name, 1.0)
	var a: AABB = _model_aabbs[model_name]
	var wdir := Vector3(-face.x if R.mirror else face.x, 0.0, R.sgn * face.y)
	var basis := Basis(Vector3.UP, atan2(wdir.x, wdir.z)) * Basis.from_scale(Vector3.ONE * s)
	var base := a.get_center()
	base.y = a.position.y
	var xf := Transform3D(basis, L(u, d, y_off) - basis * base)
	var wa: AABB = xf * a
	if check:
		var ua: float = (R.x1 - wa.end.x) if R.mirror else (wa.position.x - R.x0)
		var ub: float = (R.x1 - wa.position.x) if R.mirror else (wa.end.x - R.x0)
		var da: float = (wa.position.z - R.cz) * R.sgn
		var db: float = (wa.end.z - R.cz) * R.sgn
		var rect := [ua, min(da, db), ub, max(da, db)]
		if rect[0] < 0.03 or rect[2] > R.w - 0.03 or rect[1] < 0.03 or rect[3] > R.dep - 0.03:
			return AABB()
		if y_off < 0.01:
			for c in clear_rects:
				if rect[0] < c[2] and rect[2] > c[0] and rect[1] < c[3] and rect[3] > c[1]:
					return AABB()
			footprints.append(rect)
	var inst: Node3D = ps.instantiate()
	inst.name = model_name
	inst.transform = xf
	props_root.add_child(inst, true)
	if collide:
		_shape(Transform3D(Basis(), wa.get_center()), wa.size, LAYER_WORLD)
	if surface:
		surfaces.append(Vector3(wa.get_center().x, wa.end.y, wa.get_center().z))
	return wa


## Wall-mounted model (clock, camera, fire alarm): no collision, no footprint.
func wall_prop(model_name: String, u: float, d: float, face: Vector2, y: float) -> void:
	prop(model_name, u, d, face, y, false, false, 1.0, false)


## Ceiling-hung model (fan): hangs from the underside of the slab above.
func ceiling_prop(model_name: String, u: float, d: float) -> void:
	if _model(model_name) == null:
		return
	var h: float = _model_aabbs[model_name].size.y
	prop(model_name, u, d, Vector2(0, 1), FH - SLAB - h, false, false, 1.0, false)


## Flat fluorescent ceiling panel (cheap, glowing).
func ceiling_light(u: float, d: float) -> void:
	box(L(u, d, FH - SLAB - 0.03), Vector3(1.25, 0.05, 0.32), "frame", false)
	box(L(u, d, FH - SLAB - 0.06), Vector3(1.15, 0.01, 0.24), "lightpanel", false)


func _ceiling_grid(step := 3.0) -> void:
	var nu := maxi(1, int(round(R.w / step)))
	var nd := maxi(1, int(round(R.dep / step)))
	for i in nu:
		for j in nd:
			ceiling_light((i + 0.5) * R.w / nu, (j + 0.5) * R.dep / nd)


## Toilet built from rounded primitives (Poly Haven has no toilet model).
func toilet(u: float, d: float, face: Vector2) -> void:
	var wdir := Vector3(-face.x if R.mirror else face.x, 0.0, R.sgn * face.y).normalized()
	var p := L(u, d, 0.0)
	var white: Material = mats["white"]
	_prim(CylinderMesh.new(), p + wdir * 0.05 + Vector3(0, 0.2, 0), Vector3(0.36, 0.4, 0.46), wdir, white, 0.17, 0.13)
	_prim(CylinderMesh.new(), p + wdir * 0.05 + Vector3(0, 0.42, 0), Vector3(0.4, 0.04, 0.5), wdir, white, 0.2, 0.2)
	_prim(BoxMesh.new(), p - wdir * 0.2 + Vector3(0, 0.62, 0), Vector3(0.4, 0.38, 0.16), wdir, white)
	_shape(Transform3D(Basis(), p + Vector3(0, 0.4, 0)), Vector3(0.45, 0.8, 0.45), LAYER_WORLD)
	footprints.append([u - 0.25, d - 0.3, u + 0.25, d + 0.3])


func urinal(u: float, d: float, face: Vector2) -> void:
	var wdir := Vector3(-face.x if R.mirror else face.x, 0.0, R.sgn * face.y).normalized()
	var p := L(u, d, 0.0)
	_prim(CapsuleMesh.new(), p + Vector3(0, 0.85, 0), Vector3(0.36, 0.7, 0.3), wdir, mats["white"], 0.18, 0.18, 0.7)
	_prim(CylinderMesh.new(), p - wdir * 0.12 + Vector3(0, 1.3, 0), Vector3(0.03, 0.12, 0.03), wdir, mats["steel"], 0.015, 0.015)


func sink_basin(pos: Vector3) -> void:
	_prim(CylinderMesh.new(), pos + Vector3(0, 0.01, 0), Vector3(0.36, 0.02, 0.36), Vector3.BACK, mats["steel"], 0.18, 0.18)
	_prim(CylinderMesh.new(), pos + Vector3(0, 0.12, 0), Vector3(0.03, 0.22, 0.03), Vector3.BACK, mats["steel"], 0.015, 0.015)


func _prim(mesh: PrimitiveMesh, pos: Vector3, size: Vector3, facing: Vector3, mat: Material, top_r := -1.0, bottom_r := -1.0, height := -1.0) -> void:
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
	elif mesh is CylinderMesh:
		var cm := mesh as CylinderMesh
		cm.top_radius = top_r
		cm.bottom_radius = bottom_r
		cm.height = size.y
		cm.radial_segments = 24
	elif mesh is CapsuleMesh:
		var cap := mesh as CapsuleMesh
		cap.radius = top_r
		cap.height = height
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sx := 1.0
	var sz := 1.0
	if mesh is CylinderMesh or mesh is CapsuleMesh:
		sx = size.x / (top_r * 2.0)
		sz = size.z / (top_r * 2.0)
	mi.transform = Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)) * Basis.from_scale(Vector3(sx, 1, sz)), pos)
	props_root.add_child(mi, true)


# ---------------------------------------------------------------- room layouts

func _f_classroom() -> void:
	var w: float = R.w
	var dep: float = R.dep
	furn(0.1, dep * 0.5, 0.05, 3.4, 1.2, "board", false, 0.9)
	box(L(0.13, dep * 0.5, 0.88), Vector3(0.08, 0.03, 3.4), "frame", false)          # chalk ledge
	wall_prop("wall_clock", 0.09, dep * 0.5, Vector2(1, 0), 2.35)
	prop("metal_office_desk", 1.3, dep * 0.5, Vector2(1, 0), 0.0, true, true)        # teacher's desk
	prop("dining_chair_02", 0.55, dep * 0.5, Vector2(1, 0))
	# Student desks (facing the board) in columns with ~0.7 m aisles.
	var u := 2.9
	while u + 0.95 < w - 0.1:
		var d := 1.9
		while d + 0.4 < dep:
			if prop("SchoolDesk_01", u, d, Vector2(-1, 0), 0.0, true, true).has_volume():
				prop("SchoolChair_01", u + 0.55, d, Vector2(-1, 0))
			d += 1.4
		u += 1.9
	ceiling_prop("ceiling_fan", w * 0.35, dep * 0.5)
	ceiling_prop("ceiling_fan", w * 0.75, dep * 0.5)
	_ceiling_grid()


## Com Sci Lab: the refit builder furnishes it properly; the base builder
## treats it as a computer lab.
func _f_robolab() -> void:
	_f_complab()


func _f_complab() -> void:
	var w: float = R.w
	var dep: float = R.dep
	prop("metal_office_desk", 0.8, dep * 0.5, Vector2(1, 0), 0.0, true, true)
	monitor(0.75, dep * 0.5 - 0.4, 0.79)
	var d := 2.0
	while d < dep - 0.5:
		var u := 2.0
		while u + 2.4 < w - 0.3:
			if furn(u + 1.2, d, 2.4, 0.7, 0.75, "wood", true):
				for k in 2:
					monitor(u + 0.6 + k * 1.2, d + 0.12, 0.75)
					prop("plastic_monobloc_chair_01", u + 0.6 + k * 1.2, d - 0.68, Vector2(0, 1))
			u += 3.0
		d += 1.95
	wall_prop("security_camera_01", w - 0.2, 0.2, Vector2(-1, 1).normalized(), 2.9)
	_ceiling_grid()


func _f_server() -> void:
	var dep: float = R.dep
	var d := 2.0
	while d < dep - 0.5:
		furn(R.w - 0.6, d, 0.65, 0.8, 2.0, "dark")
		box(L(R.w - 0.6 - 0.33, d, 1.2), Vector3(0.02, 1.4, 0.6), "screen", false)
		d += 0.85
	furn(0.5, dep * 0.6, 0.7, 2.0, 0.76, "metal", true)
	monitor(0.5, dep * 0.6, 0.76)
	prop("metal_toolbox", 0.5, dep * 0.6 + 0.6, Vector2(1, 0), 0.76, false, true, 1.0, false)
	wall_prop("security_camera_01", 0.2, 0.2, Vector2(1, 1).normalized(), 2.9)
	_ceiling_grid()


func _f_restroom() -> void:
	var w: float = R.w
	var dep: float = R.dep
	var n := int((w - 0.3) / 1.1)
	for i in n + 1:
		furn(0.15 + i * 1.1, dep - 0.8, 0.05, 1.5, 1.9, "int", false, 0.1)
	for i in n:
		toilet(0.15 + 0.55 + i * 1.1, dep - 0.42, Vector2(0, -1))
	furn(0.33, (1.7 + dep - 1.7) * 0.5, 0.55, dep - 3.4, 0.85, "white", true)
	for k in 3:
		sink_basin(L(0.33, 2.3 + k * 0.9, 0.85))
	box(L(0.03, dep * 0.5, 1.6), Vector3(0.02, 0.8, dep - 3.6), "glass", false)
	if String(R.name).begins_with("Male"):
		for k in 3:
			urinal(w - 0.2, 2.4 + k * 0.8, Vector2(-1, 0))
			if k < 2:
				furn(w - 0.3, 2.8 + k * 0.8, 0.5, 0.04, 1.2, "int", false, 0.3)
	prop("plunger", 0.15 + 1.05, dep - 0.2, Vector2(0, -1), 0.0, false, false, 1.0, false)
	prop("plastic_broom", w - 0.3, 1.6, Vector2(-1, 0), 0.0, false)
	_ceiling_grid()


func _f_mit() -> void:
	var w: float = R.w
	var dep: float = R.dep
	if prop("metal_office_desk", w - 0.55, 3.0, Vector2(-1, 0), 0.0, true, true).has_volume():
		monitor(w - 0.45, 2.55, 0.79)
		monitor(w - 0.45, 3.2, 0.79)
		prop("classic_laptop", w - 0.55, 3.75, Vector2(-1, 0), 0.79, false, false, 1.0, false)
		prop("dining_chair_02", w - 1.45, 3.0, Vector2(1, 0))
	prop("steel_frame_shelves_01", w * 0.5, dep - 0.3, Vector2(0, -1), 0.0, true, false)
	prop("tool_cart", 0.5, dep * 0.55, Vector2(1, 0), 0.0, true, true)
	prop("metal_toolbox", 0.5, dep * 0.55 + 0.1, Vector2(1, 0), 0.97, false, false, 1.0, false)
	prop("cardboard_box_01", w - 0.4, dep - 0.4, Vector2(-1, 0), 0.0, true, true)
	_ceiling_grid()


func _f_records() -> void:
	var u := 1.3
	while u < R.w - 0.4:
		var d := 2.0
		while d < R.dep - 0.6:
			prop("steel_frame_shelves_01", u, d, Vector2(1, 0), 0.0, true, false)
			d += 1.15
		u += 1.5
	prop("drawer_cabinet", R.w - 0.35, 0.9, Vector2(-1, 0), 0.0, true, true)
	prop("cardboard_box_01", 0.45, R.dep - 0.4, Vector2(1, 0), 0.0, true, true)
	_ceiling_grid()


func _f_director() -> void:
	var w: float = R.w
	var dep: float = R.dep
	var dd := dep * 0.62
	if prop("metal_office_desk", w * 0.5, dd, Vector2(0, -1), 0.0, true, true).has_volume():
		prop("classic_laptop", w * 0.5 - 0.4, dd + 0.05, Vector2(0, -1), 0.79, false, false, 1.0, false)
		prop("stationery_supplies", w * 0.5 + 0.55, dd + 0.1, Vector2(0, -1), 0.79, false, false, 1.0, false)
	prop("modern_arm_chair_01", w * 0.5, dd + 1.05, Vector2(0, -1))
	prop("dining_chair_02", w * 0.5 - 0.6, dd - 0.95, Vector2(0, 1))
	prop("dining_chair_02", w * 0.5 + 0.6, dd - 0.95, Vector2(0, 1))
	prop("wooden_bookshelf_worn", w - 0.36, dep * 0.45, Vector2(-1, 0))
	prop("Sofa_01", 0.4, dep * 0.45, Vector2(1, 0))
	prop("modern_coffee_table_01", 1.35, dep * 0.45, Vector2(1, 0), 0.0, true, true)
	furn(w - 0.5, dep - 0.45, 0.7, 0.6, 1.0, "dark", true)   # the safe
	wall_prop("wall_clock", w * 0.5, 0.09, Vector2(0, 1), 2.4)
	wall_prop("security_camera_01", 0.2, dep - 0.2, Vector2(1, -1).normalized(), 2.9)
	_ceiling_grid()


func _f_staff() -> void:
	var w: float = R.w
	var dep: float = R.dep
	furn(w * 0.5, dep * 0.55, 2.4, 1.0, 0.76, "wood", true)
	for k in 3:
		prop("plastic_monobloc_chair_01", w * 0.5 - 0.8 + k * 0.8, dep * 0.55 - 0.85, Vector2(0, 1))
		prop("plastic_monobloc_chair_01", w * 0.5 - 0.8 + k * 0.8, dep * 0.55 + 0.85, Vector2(0, -1))
	furn(w - 0.28, dep * 0.5, 0.45, 3.0, 1.9, "metal")                 # lockers
	for k in 6:
		box(L(w - 0.5, dep * 0.5 - 1.25 + k * 0.5, 1.0), Vector3(0.01, 1.8, 0.01), "dark", false)
	_fridge(0.45, dep - 0.45)
	furn(w * 0.5, dep - 0.35, 2.2, 0.6, 0.9, "white", true)            # counter
	prop("vintage_microwave", w * 0.5 + 0.5, dep - 0.38, Vector2(0, -1), 0.9, false, false, 0.6, false)
	prop("CoffeeCart_01", 1.3, 1.9, Vector2(1, 0), 0.0, true, true)
	_ceiling_grid()


func _fridge(u: float, d: float) -> void:
	if furn(u, d, 0.7, 0.7, 1.8, "white"):
		box(L(u, d - 0.355, 1.2), Vector3(0.66, 0.01, 0.01), "dark", false)
		box(L(u + 0.25, d - 0.37, 1.45), Vector3(0.03, 0.3, 0.03), "steel", false)
		box(L(u + 0.25, d - 0.37, 0.75), Vector3(0.03, 0.4, 0.03), "steel", false)


func _f_admissions() -> void:
	_office(true)


func _f_cashier() -> void:
	_office(false)


func _office(lobby_east: bool) -> void:
	var w: float = R.w
	var dep: float = R.dep
	var cu := w - 0.75 if lobby_east else 0.75
	var win_d := 4.6 - CORR
	furn(cu, win_d, 0.6, 3.0, 1.05, "wood", true)                     # service counter
	prop("dining_chair_02", cu + (-0.7 if lobby_east else 0.7), win_d, Vector2(1 if lobby_east else -1, 0))
	for i in 3:
		var u := 1.6 + i * 2.4 if lobby_east else w - 1.6 - i * 2.4
		if prop("metal_office_desk", u, dep - 1.6, Vector2(0, -1), 0.0, true, true).has_volume():
			monitor(u - 0.4, dep - 1.45, 0.79)
			prop("dining_chair_02", u, dep - 0.75, Vector2(0, -1))
	var fu := 0.3 if lobby_east else w - 0.3
	for k in 2:
		prop("drawer_cabinet", fu, 2.2 + k * 1.25, Vector2(1 if lobby_east else -1, 0), 0.0, true, true)
	for k in 3:
		prop("plastic_monobloc_chair_01", w * 0.5 + (k - 1) * 0.75, 2.2, Vector2(0, 1))
	wall_prop("wall_clock", w * 0.5, 0.09, Vector2(0, 1), 2.4)
	_ceiling_grid()


func _f_lobby() -> void:
	var w: float = R.w
	var dep: float = R.dep
	prop("metal_office_desk", w - 1.3, dep - 3.4, Vector2(-1, 0), 0.0, true, true)   # guard desk
	prop("dining_chair_02", w - 0.45, dep - 3.4, Vector2(-1, 0))
	prop("painted_wooden_bench", 0.3, dep * 0.4, Vector2(1, 0), 0.0, true, true)
	prop("painted_wooden_bench", 0.3, dep * 0.4 + 1.3, Vector2(1, 0), 0.0, true, true)
	for u in [0.55, w - 0.55]:
		if prop("planter_box_01", u, dep - 0.3, Vector2(0, -1)).has_volume():
			box(L(u, dep - 0.3, 0.55), Vector3(0.75, 0.3, 0.3), "plant", false)
	wall_prop("security_camera_01", 0.2, dep - 0.2, Vector2(1, -1).normalized(), 2.9)
	wall_prop("wall_clock", w * 0.5, dep - 0.09, Vector2(0, -1), 2.75)
	_ceiling_grid()


func _f_faculty() -> void:
	var w: float = R.w
	var dep: float = R.dep
	for row in [2.3, 4.5]:
		for col in [1.65, 4.05]:
			if prop("metal_office_desk", col, row, Vector2(0, -1), 0.0, true, true).has_volume():
				monitor(col - 0.4, row + 0.15, 0.79)
				prop("stationery_supplies", col + 0.5, row + 0.1, Vector2(0, -1), 0.79, false, false, 1.0, false)
				prop("dining_chair_02", col, row + 0.85, Vector2(0, -1))
	prop("drawer_cabinet", 0.28, dep * 0.75, Vector2(1, 0), 0.0, true, true)
	prop("wooden_bookshelf_worn", w - 0.36, dep * 0.75, Vector2(-1, 0))
	prop("office_notepads", w * 0.5, 1.0, Vector2(0, 1), 0.0, false, false, 1.0, false)
	wall_prop("wall_clock", w * 0.5, 0.09, Vector2(0, 1), 2.4)
	_ceiling_grid()


func _f_kitchen() -> void:
	var w: float = R.w
	var dep: float = R.dep
	furn(0.4, (1.6 + dep - 0.15) * 0.5, 0.7, dep - 1.75, 0.9, "steel", true)
	furn(w - 0.4, (1.6 + dep - 0.15) * 0.5, 0.7, dep - 1.75, 0.9, "steel", true)
	for u in [w * 0.32, w * 0.68]:
		for d in [2.9, 5.0]:
			if furn(u, d, 2.6, 1.0, 0.9, "steel", true):
				box(L(u - 0.6, d, 0.92), Vector3(1.0, 0.04, 0.7), "dark", false)
				prop("pot_enamel_01", u - 0.85, d, Vector2(0, 1), 0.94, false, false, 1.0, false)
				prop("wooden_cutting_board", u + 0.6, d, Vector2(0, 1), 0.9, false, false, 1.0, false)
	for u in [1.6, w - 1.6]:
		_fridge(u, dep - 0.45)
	for u in [3.4, w - 3.4]:
		prop("electric_stove", u, dep - 0.4, Vector2(0, -1), 0.0, true, true)
	furn(w * 0.5, dep - 0.4, 2.4, 0.65, 0.9, "steel", true)
	prop("vintage_microwave", 0.4, 2.4, Vector2(1, 0), 0.9, false, false, 0.6, false)
	prop("vintage_microwave", w - 0.4, 2.4, Vector2(-1, 0), 0.9, false, false, 0.6, false)
	_ceiling_grid()


func _f_pantry() -> void:
	var dep: float = R.dep
	var d := 2.0
	while d < dep - 0.6:
		prop("steel_frame_shelves_01", 0.28, d, Vector2(1, 0), 0.0, true, false)
		prop("steel_frame_shelves_01", R.w - 0.28, d, Vector2(-1, 0), 0.0, true, false)
		d += 1.15
	prop("plastic_crate_01", R.w * 0.5, dep - 0.5, Vector2(0, 1), 0.0, true, true)
	prop("cardboard_box_01", R.w * 0.5, dep - 1.6, Vector2(0, 1), 0.0, true, true)
	_ceiling_grid()


func _f_dining() -> void:
	var w: float = R.w
	var dep: float = R.dep
	for u in [1.9, 4.2]:
		for d in [2.6, 4.7]:
			if furn(u, d, 1.1, 1.1, 0.75, "wood", true):
				prop("plastic_monobloc_chair_01", u + 0.8, d, Vector2(-1, 0))
				prop("plastic_monobloc_chair_01", u - 0.8, d, Vector2(1, 0))
				prop("plastic_monobloc_chair_01", u, d + 0.8, Vector2(0, -1))
				prop("plastic_monobloc_chair_01", u, d - 0.8, Vector2(0, 1))
	furn(w * 0.5, dep - 0.4, 3.0, 0.6, 0.9, "steel", true)
	_ceiling_grid()


## Corridor fittings on every floor: lights, cameras, fire alarms.
func _corridor_props() -> void:
	for f in FLOORS:
		R = {"floor": f, "name": "Corridor", "type": "corridor", "x0": X0, "x1": X1, "z0": -CORR, "z1": CORR,
			"w": X1 - X0, "dep": 2 * CORR, "cz": -CORR, "sgn": 1.0, "y": f * FH, "mirror": false}
		footprints = []
		clear_rects = []
		surfaces = []
		var x := 1.5
		var i := 0
		while x < R.w:
			ceiling_light(x, CORR)
			# The panels only glow; without a real light here the corridor was lit
			# solely by room lights through the lab glass, which left the lab-side
			# wall in the blue ambient. One light per pair of panels.
			if i % 2 == 1:
				_light(L(x, CORR, FH - SLAB - 0.2), 5.0, 0.8)
				var cl: OmniLight3D = lights.get_child(lights.get_child_count() - 1)
				cl.name = "Corridor Light %s" % FLOOR_NAMES[f]
				cl.shadow_enabled = true
				cl.shadow_bias = 0.03
				cl.shadow_normal_bias = 0.45
			x += 3.0
			i += 1
		wall_prop("security_camera_01", 0.2, 0.25, Vector2(1, 0.4).normalized(), 2.95)
		wall_prop("security_camera_01", R.w - 0.2, 2 * CORR - 0.25, Vector2(-1, -0.4).normalized(), 2.95)
		for fx in [4.6, R.w - 4.6]:
			wall_prop("fire_alarm", fx, 0.09, Vector2(0, 1), 1.4)
	# Outside: bins by the entrance and a camera over the door
	R = {"floor": 0, "name": "Outside", "type": "outside", "x0": X0, "x1": X1, "z0": Z1, "z1": Z1 + 7.0,
		"w": X1 - X0, "dep": 7.0, "cz": Z1, "sgn": 1.0, "y": 0.0, "mirror": false}
	prop("metal_trash_can", 18.0, 1.6, Vector2(0, 1), 0.0, true, false, 1.0, false)
	wall_prop("security_camera_01", 14.2, 0.2, Vector2(-0.5, 1).normalized(), 2.7)


# ---------------------------------------------------------------- loot

func _place_loot() -> void:
	var area: float = R.w * R.dep
	var picked := []
	# On furniture
	var cand := surfaces.duplicate()
	_shuffle(cand)
	var n_surf := clampi(int(area / 9.0), 2, 7)
	for p in cand:
		if picked.size() >= n_surf:
			break
		if picked.any(func(q): return q.distance_to(p) < 1.1):
			continue
		picked.append(p)
	# On the floor (clear of furniture and doorways)
	var floor_pts := []
	var u := 0.7
	while u < R.w - 0.6:
		var d := 0.9
		while d < R.dep - 0.6:
			if _floor_free(u, d):
				floor_pts.append(L(u, d, 0.0))
			d += 0.5
		u += 0.5
	_shuffle(floor_pts)
	var n_floor := clampi(int(area / 15.0), 1, 4)
	var nf := 0
	for p in floor_pts:
		if nf >= n_floor:
			break
		if picked.any(func(q): return q.distance_to(p) < 1.8):
			continue
		picked.append(p)
		nf += 1
	for i in picked.size():
		_marker("%s %s %d" % [FLOOR_NAMES[R.floor], R.name, i + 1], picked[i], R.type, R.name)


func _floor_free(u: float, d: float) -> bool:
	for r in footprints + clear_rects:
		if u > r[0] - 0.45 and u < r[2] + 0.45 and d > r[1] - 0.45 and d < r[3] + 0.45:
			return false
	return true


func _corridor_and_roof_loot() -> void:
	for f in FLOORS:
		for x in [-6.0, 6.0]:
			_marker("%s Corridor %d" % [FLOOR_NAMES[f], 1 if x < 0 else 2], Vector3(x + rng.randf_range(-1.5, 1.5), f * FH, rng.randf_range(-0.6, 0.6)), "corridor", "Corridor")
	var y := FLOORS * FH
	for p in [Vector3(-6.2, y, -5.0), Vector3(4.0, y + 1.0, 4.0), Vector3(-2.0, y, 3.0), Vector3(7.0, y, -6.0)]:
		_marker("Roof %d" % (loot_root.get_child_count() + 1), p, "roof", "Roof")


func _marker(label: String, p: Vector3, t: String, room: String) -> void:
	var m := Marker3D.new()
	m.name = label.validate_node_name()
	m.position = p
	m.gizmo_extents = 0.3
	m.set_meta("room_type", t)
	m.set_meta("room", room)
	loot_root.add_child(m, true)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _light(p: Vector3, range_m: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.omni_range = range_m
	l.light_energy = energy
	l.light_color = Color(1.0, 0.97, 0.9)
	l.omni_attenuation = 0.8
	lights.add_child(l, true)


func _set_owner(n: Node, owner_node: Node) -> void:
	for c in n.get_children():
		c.owner = owner_node
		if c.scene_file_path == "":
			_set_owner(c, owner_node)
