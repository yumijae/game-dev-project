extends SceneTree
## Rebuilds res://main.tscn: the school building, lighting, ground, player,
## HUD and a baked navigation mesh for AI.
## Run after tools/build_school.gd:
##   godot --headless --path . --script res://tools/build_level.gd
## Hand-edits to main.tscn are overwritten.

const BUILDING := "res://school/school_building.scn"
const NAVMESH := "res://school/school_navmesh.res"
const PLAYER_SPAWN := Vector3(0.0, 0.05, 14.0) # on the sidewalk, facing the entrance

var main: Node3D
var region: NavigationRegion3D
var frame := 0


func _initialize() -> void:
	main = Node3D.new()
	main.name = "Main"

	var building: Node3D = load(BUILDING).instantiate()
	building.name = "STI_School"
	_own(main, building)

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	_own(main, env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.directional_shadow_max_distance = 120.0
	_own(main, sun)

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
	# Street in front of the school
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

	var player: Node3D = load("res://player/player.tscn").instantiate()
	player.position = PLAYER_SPAWN
	_own(main, player)

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://ui/hud.gd"))
	_own(main, hud)
	hud.set("player_path", NodePath("../Player"))

	root.add_child(main)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	building.get_node("LootSpawns").process_mode = Node.PROCESS_MODE_DISABLED


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	_bake_navmesh()
	main.get_node("Player").process_mode = Node.PROCESS_MODE_INHERIT
	main.get_node("STI_School/LootSpawns").process_mode = Node.PROCESS_MODE_INHERIT
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
	nm.geometry_collision_mask = 1 # world only: doors are left out so AI paths through doorways
	nm.cell_size = 0.1
	nm.cell_height = 0.1
	nm.agent_radius = 0.3
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 50.0
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
