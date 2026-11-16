extends SceneTree
## Rebuilds res://main.tscn for "Huling Kampana": the school building, night
## lighting, ground, a baked navigation mesh, Juan, the HUD and the three
## night managers (GameDirector, HallucinationManager, EscapeManager).
## Run after tools/MapRefitAndGlassBuilder.gd:
##   godot --headless --path . --script res://tools/build_level.gd
## Hand-edits to main.tscn are overwritten.

const BUILDING := "res://school/school_building.scn"
const NAVMESH := "res://school/school_navmesh.res"

var main: Node3D
var region: NavigationRegion3D
var frame := 0


func _initialize() -> void:
	main = Node3D.new()
	main.name = "Main"

	var building: Node3D = load(BUILDING).instantiate()
	building.name = "STI_School"
	_own(main, building)

	# A moonless provincial night: almost no ambient light, thin fog.
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.008, 0.01, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.32, 0.38, 0.55)
	e.ambient_light_energy = 0.07
	# Keep in step with the Environment in main.tscn (lighting pass: no glow
	# halos, short volumetric range so lit haze cannot smear through walls,
	# screen-space bounce that only ever uses what the camera can see).
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.45
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 0.8
	e.ssao_intensity = 2.2
	e.ssao_detail = 0.6
	e.ssao_light_affect = 0.25
	e.ssil_enabled = true
	e.ssil_radius = 3.0
	e.ssil_intensity = 0.7
	e.ssil_normal_rejection = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.02, 0.025, 0.04)
	e.fog_density = 0.018
	e.glow_enabled = true
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 0.6)
	e.set_glow_level(2, 1.0)
	e.set_glow_level(3, 0.6)
	e.set_glow_level(4, 0.25)
	e.glow_intensity = 0.5
	e.glow_strength = 0.9
	e.glow_bloom = 0.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.glow_hdr_threshold = 1.1
	e.glow_hdr_scale = 1.6
	# Thin haze so the phone LED throws a visible cone through the dark.
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.03
	e.volumetric_fog_albedo = Color(0.62, 0.68, 0.78)
	e.volumetric_fog_ambient_inject = 0.0
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 22.0
	e.volumetric_fog_detail_spread = 1.6
	e.volumetric_fog_temporal_reprojection_amount = 0.75
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.1
	e.adjustment_saturation = 0.9
	env.environment = e
	_own(main, env)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.shadow_enabled = true
	moon.light_color = Color(0.55, 0.65, 0.9)
	moon.light_energy = 0.06
	moon.rotation_degrees = Vector3(-38, -150, 0)
	moon.directional_shadow_max_distance = 80.0
	# Same tight biases as LightRig.seal(): Godot's defaults push the shadow
	# lookup through the 15 cm partitions and moonlight tints indoor walls blue.
	moon.shadow_opacity = 1.0
	moon.shadow_bias = 0.03
	moon.shadow_normal_bias = 0.45
	_own(main, moon)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	_own(main, ground)
	var gm := MeshInstance3D.new()
	gm.name = "GroundMesh"
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	pm.material = _pbr("grass_ground", 120.0, Color(0.9, 0.95, 0.85))
	gm.mesh = pm
	_own(ground, gm)
	var road := MeshInstance3D.new()
	road.name = "Street"
	var rm := PlaneMesh.new()
	rm.size = Vector2(120, 9)
	rm.material = _pbr("asphalt_02", 120.0, Color(0.8, 0.8, 0.8), 9.0)
	road.mesh = rm
	road.position = Vector3(0, 0.01, 20.5)
	_own(ground, road)
	var gc := CollisionShape3D.new()
	gc.name = "GroundCollision"
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(120, 0.2, 120)
	gc.shape = gbox
	gc.position.y = -0.1
	_own(ground, gc)

	region = NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	_own(main, region)

	# Only static geometry goes into the tree for the bake; gameplay nodes are
	# added afterwards so none of their _ready() code runs inside this tool.
	building.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(main)


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	_bake_navmesh()
	root.remove_child(main)
	main.get_node("STI_School").process_mode = Node.PROCESS_MODE_INHERIT

	var player: Node3D = load("res://player/player.tscn").instantiate()
	player.position = Vector3(-3.0, 11.45, 4.6) # Room 402; GameDirector snaps to the PlayerSpawn marker
	_own(main, player)

	var post_fx := CanvasLayer.new()
	post_fx.name = "PostFX"
	post_fx.set_script(load("res://ui/post_fx.gd"))
	_own(main, post_fx)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://ui/hud.gd"))
	_own(main, hud)
	hud.set("player_path", NodePath("../Player"))

	for entry in [["HallucinationManager", "res://core/managers/hallucination_manager.gd"],
			["EscapeManager", "res://core/managers/escape_manager.gd"],
			["GameDirector", "res://core/managers/game_director.gd"]]:
		var manager := Node.new()
		manager.name = entry[0]
		manager.set_script(load(entry[1]))
		_own(main, manager)

	var packed := PackedScene.new()
	var err := packed.pack(main)
	if err == OK:
		err = ResourceSaver.save(packed, "res://main.tscn")
	print("[build_level] saved main.tscn: ", error_string(err))
	main.free()
	return true


func _bake_navmesh() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 # world only: doors, glass and props are left out so AI paths through doorways
	# 5 cm cells so the 0.25 m agent radius is exact (it is rounded up to
	# whole cells). Must match navigation/3d/default_cell_size in project.godot.
	nm.cell_size = 0.05
	nm.cell_height = 0.1
	# Smaller than Juan's 0.3 m capsule: wherever he can stand there is
	# navmesh, so no gap between furniture is ever out of the Aswang's reach.
	# Their bodies (aswang_base.gd) are 0.24 m so they fit what the mesh allows.
	nm.agent_radius = 0.4  # see tools/bake_navmesh.gd
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 50.0
	# Drop the little islands baked on desk, bench and counter tops. Targets
	# used to snap onto them and the Aswang stopped short of Juan.
	nm.region_min_size = 28.0 # in cells, squared: 784 x 5 cm cells ~ 2 m²
	nm.filter_baking_aabb = AABB(Vector3(-20, -1, -16), Vector3(40, 22, 36))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, main)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	ResourceSaver.save(nm, NAVMESH)
	region.navigation_mesh = load(NAVMESH)
	print("[build_level] navmesh polygons: ", nm.get_polygon_count())


## Tiled PBR material for a PlaneMesh of the given size (metres).
func _pbr(asset: String, size_x: float, tint := Color.WHITE, size_y := -1.0) -> Material:
	var path := "res://textures/polyhaven/index.json"
	if not FileAccess.file_exists(path):
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.35, 0.37, 0.33)
		return flat
	var e: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))[asset]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(e.maps.diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(e.maps.nor_gl)
	m.roughness_texture = load(e.maps.rough)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	var tile: float = e.size_m[0]
	m.uv1_scale = Vector3(size_x / tile, (size_y if size_y > 0 else size_x) / tile, 1)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _own(parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = main
