extends SceneTree
## Re-bakes res://school/school_navmesh.res (and the tight variant robots use
## to get between desks) from the current school building
## without rebuilding main.tscn (build_level.gd does both). Run after
## tools/MapRefitAndGlassBuilder.gd whenever walls or furniture change:
##   godot --headless --path . --script res://tools/bake_navmesh.gd
## Same settings as build_level.gd's _bake_navmesh().

const BUILDING := "res://school/school_building.scn"
const NAVMESH := "res://school/school_navmesh.res"
const NAVMESH_TIGHT := "res://school/school_navmesh_tight.res"

var main: Node3D
var frame := 0


func _initialize() -> void:
	main = Node3D.new()
	var building: Node3D = load(BUILDING).instantiate()
	building.process_mode = Node.PROCESS_MODE_DISABLED
	main.add_child(building)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120, 0.2, 120)
	shape.shape = box
	shape.position.y = -0.1
	ground.add_child(shape)
	main.add_child(ground)
	root.add_child(main)


func _physics_process(_delta: float) -> bool:
	frame += 1
	if frame < 2:
		return false
	# Main mesh: robots keep 0.4 m from walls so their arms and bodies never
	# clip through them (doorways are 1.0 m, so this still leaves a lane;
	# keep it a multiple of cell_size).
	_bake(0.4, NAVMESH)
	# Tight mesh: 0.25 m, reaches between desks. Robots switch to it only
	# when their target is somewhere the main mesh cannot reach.
	_bake(0.25, NAVMESH_TIGHT)
	return true


func _bake(radius: float, path: String) -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.05
	nm.cell_height = 0.1
	nm.agent_radius = radius
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 50.0
	nm.region_min_size = 28.0
	nm.filter_baking_aabb = AABB(Vector3(-20, -1, -16), Vector3(40, 22, 36))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, main)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var err := ResourceSaver.save(nm, path)
	print("[bake_navmesh] ", path.get_file(), " radius ", radius, ": ", nm.get_polygon_count(), " polygons, ", error_string(err))
