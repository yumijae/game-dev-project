extends "res://tools/build_school.gd"
## MapRefitAndGlassBuilder - regenerates res://school/school_building.scn with
## the "Huling Kampana" refit on top of the base 28-room generator:
##
##   godot --headless --path . --script res://tools/MapRefitAndGlassBuilder.gd
##   godot --headless --path . --script res://tools/build_level.gd
##
## What it changes compared with build_school.gd:
##   * Furniture orientation. Every prop is placed from the wall it stands
##     against, using that wall's inward normal: cabinets, lockers, racks,
##     fridges and ranges have their backs flush to the wall and their doors
##     facing the room; desks have their kneehole on the side of their chair;
##     monitors and keyboards face whoever sits at them.
##   * Wide corridor viewing glass for the 2F Computer Labs (#7, #8, #13) and
##     the 4F Culinary Kitchen (#24) and Dining (#27): a 1.0 m concrete
##     half-wall, a 1.0-2.8 m plate-glass bay 3.5-5.0 m wide, and a header.
##   * Gameplay nodes: InteractableDoor, JalousieWindow, CorridorViewingGlass,
##     HeavyProp, HidingSpot, RestroomFixture, the Rehas gate, the rooftop SOS
##     antenna, item markers, torso spots and Juan's spawn point.
##
## Room-local coordinates (see build_school.gd): u runs along X from the
## room's "W" wall, d runs from the corridor wall "C" to the outside wall "O".

const GLASS_ROOM_TYPES := ["complab", "kitchen", "dining"]
const GLASS_SILL := 1.0
const GLASS_TOP := 2.8
const GLASS_MAX_BAY := 5.0
const GLASS_PIER := 0.3
## Inward normal of each wall, as (du, dd).
const NORMALS := {"W": Vector2(1, 0), "E": Vector2(-1, 0), "C": Vector2(0, 1), "O": Vector2(0, -1)}
const WALL_GAP := 0.02

var markers_root: Node3D

# Gameplay classes use the autoloads, which do not exist yet while this tool
# script is being compiled - so they are loaded at run time, not referenced
# by class name.
var _glass_script: GDScript
var _jalousie_script: GDScript
var _gate_script: GDScript
var _spot_script: GDScript
var _heavy_script: GDScript
var _fixture_script: GDScript


func _initialize() -> void:
	rng.seed = 20261114
	_glass_script = load("res://barricade/corridor_viewing_glass.gd")
	_jalousie_script = load("res://barricade/jalousie_window.gd")
	_gate_script = load("res://core/managers/rehas_gate.gd")
	_spot_script = load("res://barricade/hiding_spot.gd")
	_heavy_script = load("res://barricade/heavy_prop.gd")
	_fixture_script = load("res://barricade/restroom_fixture.gd")
	_load_materials()
	var beacon := _mat(Color(0.9, 0.1, 0.08), 0.0, 0.4)
	beacon.emission_enabled = true
	beacon.emission = Color(1.0, 0.1, 0.05)
	beacon.emission_energy_multiplier = 3.0
	mats["beacon"] = beacon
	mats["paper"] = _mat(Color(0.86, 0.82, 0.7), 0.0, 0.9)
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
	loot_root.name = "ItemSpawns"
	loot_root.set_script(load("res://items/item_spawner.gd"))
	markers_root = Node3D.new()
	markers_root.name = "Markers"
	for n in [collision, interactive, lights, loot_root, markers_root]:
		root_node.add_child(n)

	_plan_walls()
	for f in FLOORS:
		_build_floor(f)
	_build_viewing_glass()
	_build_slabs()
	for s in STAIRS:
		_build_stairwell(s)
	_build_roof()
	_build_facade()
	_build_rehas_gate()
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
	var counts := {}
	for n in interactive.get_children():
		var key: String = n.get_script().resource_path.get_file().get_basename()
		counts[key] = counts.get(key, 0) + 1
	print("[MapRefitAndGlassBuilder] boxes=%d shapes=%d lights=%d item markers=%d -> %s" % [
		_box_count, collision.get_child_count(), lights.get_child_count(), loot_root.get_child_count(), error_string(err)])
	print("[MapRefitAndGlassBuilder] interactive: ", counts)
	root_node.free()
	quit()


# ------------------------------------------------------ corridor viewing glass

## Replaces the small lab windows with wide viewing bays on the corridor wall.
func _plan_walls() -> void:
	super()
	var kept := []
	for op in openings:
		if op.kind == "window" and op.axis == "x" and absf(absf(op.fixed) - CORR) < 0.01:
			continue
		kept.append(op)
	openings = kept
	for r in ROOMS:
		if not GLASS_ROOM_TYPES.has(r[2]):
			continue
		var x0: float = r[3]
		var x1: float = r[5]
		var front: bool = r[4] >= CORR - 0.01
		var corridor_z: float = r[4] if front else r[6]
		# Leave the door (centred 1.0 m from the corner) and its frame solid.
		var a0: float = x0 + 1.8
		var a1: float = x1 - 1.8 if x1 - x0 >= 8.9 else x1 - 0.3
		var span: float = a1 - a0
		var bays: int = int(ceil(span / GLASS_MAX_BAY))
		var bay_w: float = (span - (bays - 1) * GLASS_PIER) / bays
		for i in bays:
			openings.append({"floor": r[0], "axis": "x", "fixed": corridor_z,
				"c": a0 + bay_w * 0.5 + i * (bay_w + GLASS_PIER), "w": bay_w,
				"sill": GLASS_SILL, "top": GLASS_TOP, "kind": "viewglass", "room": r})


## wall() has already left the half-wall below and the header above each bay.
func _build_viewing_glass() -> void:
	for op in openings:
		if op.kind != "viewglass":
			continue
		var r: Array = op.room
		var front: bool = r[4] >= CORR - 0.01
		var glass: Node3D = _glass_script.create(op.w, GLASS_TOP - GLASS_SILL, Vector3(0, 0, 1.0 if front else -1.0), _room_id(r))
		glass.name = ("Viewing Glass %s %s" % [FLOOR_NAMES[r[0]], r[1]]).validate_node_name()
		glass.position = Vector3(op.c, op.floor * FH + (GLASS_SILL + GLASS_TOP) * 0.5, op.fixed)
		interactive.add_child(glass, true)


func _room_id(r: Array) -> int:
	return Campus.room_id_at(Vector3((r[3] + r[5]) * 0.5, r[0] * FH + 0.5, (r[4] + r[6]) * 0.5))


# -------------------------------------------------- doors, windows, gate, roof

## Exterior windows become interactive jalousies; interior ones stay plain.
func _window(axis: String, fixed: float, a0: float, a1: float, yb: float, yt: float) -> void:
	var exterior := (axis == "x" and (absf(fixed - Z0) < 0.01 or absf(fixed - Z1) < 0.01)) \
		or (axis == "z" and (absf(fixed - X0) < 0.01 or absf(fixed - X1) < 0.01))
	if not exterior or yb >= FLOORS * FH:
		super(axis, fixed, a0, a1, yb, yt)
		return
	var mid := (a0 + a1) * 0.5
	var cy := (yb + yt) * 0.5
	var center := Vector3(mid, cy, fixed) if axis == "x" else Vector3(fixed, cy, mid)
	var outward := Vector3(0, 0, signf(fixed)) if axis == "x" else Vector3(signf(fixed), 0, 0)
	var probe := center - outward * 1.0
	probe.y = floorf(yb / FH) * FH + 0.5
	var window: Node3D = _jalousie_script.create(a1 - a0, yt - yb, outward, Campus.room_id_at(probe))
	window.name = "Jalousie"
	window.position = center
	interactive.add_child(window, true)


## Same hinge maths as the base builder, but every door is an InteractableDoor.
func add_door(label: String, c: Vector3, along: Vector3, opening_w: float, toward: Vector3, mk := "door") -> void:
	var w := opening_w - 0.06
	var h := 2.1
	var hinge := c - along * w * 0.5
	var closed_yaw := atan2(-along.z, along.x)
	var normal := Vector3(-along.z, 0, along.x)
	var side := signf((toward - c).dot(normal))
	if side == 0.0:
		side = 1.0
	# The "room" is the side Juan barricades from. For the roof door that is
	# the stair hut, not the open deck it swings onto.
	var room_side := normal * side * (-1.0 if label == "Roof Door" else 1.0)
	var door := Node3D.new()
	door.name = label.validate_node_name()
	door.set_script(load("res://barricade/interactable_door.gd"))
	door.set("door_label", label)
	door.set("closed_yaw", closed_yaw)
	door.set("open_yaw", closed_yaw - side * PI * 0.5)
	door.set("door_width", w)
	door.set("room_side", room_side)
	door.set("room_id", Campus.room_id_at(c + room_side + Vector3.UP * 0.5))
	door.set("permanently_locked", label.begins_with("Fire Exit"))
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
	# The 9 cm gap under the leaf is what the Balbal's Black Dog crawls through.
	bs.size = Vector3(w, h - 0.09, 0.05)
	cs.shape = bs
	cs.position = Vector3(w * 0.5, 0.09 + (h - 0.09) * 0.5, 0)
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


## Rehas roll-up gate just inside the Main Lobby entrance, at (0, 0, 7.8).
func _build_rehas_gate() -> void:
	var gate: Node3D = _gate_script.create(3.8, 2.5)
	gate.name = "Rehas Gate"
	gate.position = Campus.REHAS_GATE_POSITION
	interactive.add_child(gate, true)


## Adds the SOS antenna mast at the centre of the roof deck.
func _build_roof() -> void:
	super()
	var y := FLOORS * FH
	box(Vector3(0, y + 0.15, 0), Vector3(0.7, 0.3, 0.7), "metal")
	box(Vector3(0, y + 2.3, 0), Vector3(0.09, 4.0, 0.09), "rail")
	for h in [2.6, 3.3, 3.9]:
		box(Vector3(0, y + h, 0), Vector3(1.2 - (h - 2.6) * 0.5, 0.03, 0.03), "rail", false)
		box(Vector3(0, y + h, 0), Vector3(0.03, 0.03, 0.7 - (h - 2.6) * 0.3), "rail", false)
	box(Vector3(0, y + 4.36, 0), Vector3(0.12, 0.12, 0.12), "beacon", false)


func _marker(label: String, p: Vector3, t: String, room: String) -> void:
	super(label, p, t, room)
	var m: Node = loot_root.get_child(loot_root.get_child_count() - 1)
	m.set_meta("room_id", Campus.room_id_at(p + Vector3.UP * 0.3))


# ------------------------------------------------------------ placement tools

## Distance from a room edge line to the inner face of that wall.
func _inset(side: String) -> float:
	if side == "C":
		return INT_T * 0.5
	if side == "O":
		return EXT_T * 0.5
	var mirrored: bool = R.mirror
	var x: float = R.x0 if (side == "W") != mirrored else R.x1
	return EXT_T * 0.5 if (absf(x - X0) < 0.01 or absf(x - X1) < 0.01) else INT_T * 0.5


## Centre (u, d) of something `depth` deep standing with its back flush
## against `side`, at coordinate `t` along that wall.
func _flush(side: String, t: float, depth: float) -> Vector2:
	var off: float = _inset(side) + WALL_GAP + depth * 0.5
	match side:
		"W":
			return Vector2(off, t)
		"E":
			return Vector2(R.w - off, t)
		"C":
			return Vector2(t, off)
	return Vector2(t, R.dep - off)


## Box size for something `along` long on its wall, `thick` deep.
func _sz(side: String, along: float, y: float, thick: float) -> Vector3:
	return Vector3(thick, y, along) if side == "W" or side == "E" else Vector3(along, y, thick)


## Model with its back flush to a wall and its front facing the room.
func flush_prop(model_name: String, side: String, t: float, y_off := 0.0, collide := true, surface := false, scale := 1.0) -> AABB:
	if _model(model_name) == null:
		return AABB()
	var depth: float = _model_aabbs[model_name].size.z * scale * MODEL_SCALE.get(model_name, 1.0)
	var c := _flush(side, t, depth)
	return prop(model_name, c.x, c.y, NORMALS[side], y_off, collide, surface, scale)


## Furniture box flush to a wall. Returns its centre, or (-1, -1) if blocked.
func flush_furn(side: String, t: float, length: float, depth: float, h: float, mk: String, surface := false, y_off := 0.0) -> Vector2:
	var c := _flush(side, t, depth)
	var along_d := side == "W" or side == "E"
	if furn(c.x, c.y, depth if along_d else length, length if along_d else depth, h, mk, surface, y_off):
		return c
	return Vector2(-1, -1)


## Reserves a floor rectangle (bounds + doorway clearance), like furn() does.
func _claim(u0: float, d0: float, u1: float, d1: float) -> bool:
	if u0 < 0.05 or u1 > R.w - 0.05 or d0 < 0.05 or d1 > R.dep - 0.05:
		return false
	for c in clear_rects:
		if u0 < c[2] and u1 > c[0] and d0 < c[3] and d1 > c[1]:
			return false
	footprints.append([u0, d0, u1, d1])
	return true


## World transform at room-local (u, d) whose local +Z points along `face`.
func _xf(u: float, d: float, y: float, face: Vector2) -> Transform3D:
	var dir := Vector3(-face.x if R.mirror else face.x, 0.0, R.sgn * face.y)
	return Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), L(u, d, y))


## Monitor, stand and keyboard. `face` points from the screen to its user.
func monitor_at(u: float, d: float, y: float, face: Vector2) -> void:
	var side := "C" if absf(face.y) > 0.5 else "W"
	box(L(u, d, y + 0.24), _sz(side, 0.54, 0.34, 0.03), "dark", false)
	box(L(u + face.x * 0.018, d + face.y * 0.018, y + 0.245), _sz(side, 0.5, 0.3, 0.01), "screen", false)
	box(L(u, d, y + 0.04), Vector3(0.05, 0.1, 0.05), "dark", false)
	box(L(u, d, y + 0.005), _sz(side, 0.22, 0.01, 0.16), "dark", false)
	box(L(u + face.x * 0.3, d + face.y * 0.3, y + 0.01), _sz(side, 0.44, 0.02, 0.14), "dark", false)


func _spot(kind: StringName, u: float, d: float, face: Vector2, volume: Vector3, hide_at: Vector3, exit_at: Vector3, eye := 1.5) -> void:
	var spot: Node3D = _spot_script.create(kind, volume, hide_at, exit_at, eye)
	spot.name = ("Hide %s %s" % [kind, R.name]).validate_node_name()
	spot.transform = _xf(u, d, 0.0, face)
	interactive.add_child(spot, true)


## A HeavyProp that can be dragged against a door to block its bottom gap.
func _heavy(label: String, u: float, d: float, size: Vector3, color: Color, reserve := true) -> void:
	if reserve and not _claim(u - size.x * 0.5, d - size.z * 0.5, u + size.x * 0.5, d + size.z * 0.5):
		return
	var heavy: Node3D = _heavy_script.create(label, size, color)
	heavy.name = ("%s %s" % [label, R.name]).validate_node_name()
	heavy.position = L(u, d, 0.0)
	interactive.add_child(heavy, true)


func _thesis_stack(u: float, d: float) -> void:
	_heavy("Thesis Stack", u, d, Vector3(0.45, 0.55, 0.35), Color(0.82, 0.78, 0.66))


## Where the Manananggal may leave her lower torso.
func _torso_spot(u: float, d: float) -> void:
	var m := Marker3D.new()
	m.name = ("Torso Spot %s %s" % [FLOOR_NAMES[R.floor], R.name]).validate_node_name()
	m.position = L(u, d, 0.0)
	m.add_to_group("torso_spots", true)
	markers_root.add_child(m, true)
	footprints.append([u - 0.3, d - 0.3, u + 0.3, d + 0.3])


## A kneehole to hide in on the sitter's side of a desk at (u, d).
func _desk_spot(u: float, d: float, face: Vector2, exit_at: Vector3) -> void:
	_spot(&"desk", u + face.x * 0.42, d + face.y * 0.42, face, Vector3(0.62, 0.68, 0.2), Vector3(0, 0, -0.3), exit_at, 0.5)


## Row of steel lockers, backs to the wall, doors to the room. Each hides Juan.
func _locker_bank(side: String, t_center: float, count: int) -> void:
	var lw := 0.5
	var depth := 0.5
	var n: Vector2 = NORMALS[side]
	var a := Vector2(absf(n.y), absf(n.x))
	for i in count:
		var t: float = t_center + (i - (count - 1) * 0.5) * lw
		var c := flush_furn(side, t, lw, depth, 1.9, "metal")
		if c.x < 0.0:
			continue
		var f := c + n * (depth * 0.5 + 0.004)
		box(L(f.x, f.y, 0.97), _sz(side, lw - 0.05, 1.8, 0.006), "steel", false)
		for vy in [1.55, 1.62, 1.69]:
			box(L(f.x + n.x * 0.004, f.y + n.y * 0.004, vy), _sz(side, lw - 0.2, 0.02, 0.004), "dark", false)
		var hp := f + a * (lw * 0.3) + n * 0.01
		box(L(hp.x, hp.y, 1.0), _sz(side, 0.03, 0.12, 0.02), "dark", false)
		_spot(&"locker", c.x, c.y, n, Vector3(lw - 0.02, 1.9, depth + 0.1), Vector3.ZERO, Vector3(0, 0, 0.9))


## Fridge with its back to a wall and its door (seam + handles) to the room.
func _fridge_at(side: String, t: float) -> void:
	var c := flush_furn(side, t, 0.7, 0.7, 1.8, "white")
	if c.x < 0.0:
		return
	var n: Vector2 = NORMALS[side]
	var a := Vector2(absf(n.y), absf(n.x))
	var f := c + n * 0.355
	box(L(f.x, f.y, 1.2), _sz(side, 0.66, 0.01, 0.01), "dark", false)
	var hp := f + a * 0.25 + n * 0.015
	box(L(hp.x, hp.y, 1.45), _sz(side, 0.03, 0.3, 0.03), "steel", false)
	box(L(hp.x, hp.y, 0.75), _sz(side, 0.03, 0.4, 0.03), "steel", false)


# ---------------------------------------------------------------- room layouts

## Lecture rooms 301-305 and 401-403. The board and the teacher's desk are on
## the room's interior partition wall ("W" in local space); armchairs sit in
## rows facing it with 0.84 m aisles and a clear doorway.
func _f_classroom() -> void:
	var w: float = R.w
	var dep: float = R.dep
	var mid := dep * 0.5
	var wi := _inset("W")
	box(L(wi + 0.03, mid, 1.5), Vector3(0.05, 1.2, 3.4), "board", false)
	box(L(wi + 0.07, mid, 0.88), Vector3(0.1, 0.03, 3.4), "frame", false)               # chalk ledge
	wall_prop("wall_clock", wi + 0.03, mid, Vector2(1, 0), 2.35)
	# Teacher sits between the board and the desk, facing the class: the
	# desk's kneehole/drawer side (+Z of the model) therefore faces the board.
	if prop("metal_office_desk", 1.55, mid, Vector2(-1, 0), 0.0, true, true).has_volume():
		_desk_spot(1.55, mid, Vector2(-1, 0), Vector3(1.35, 0, 0.25))
	prop("dining_chair_02", 0.7, mid, Vector2(1, 0))
	var u := 2.9
	while u + 0.95 < w - 0.1:
		var d := 1.7
		while d + 0.4 < dep:
			if prop("SchoolDesk_01", u, d, Vector2(-1, 0), 0.0, true, true).has_volume():
				prop("SchoolChair_01", u + 0.55, d, Vector2(-1, 0))
			d += 1.55
		u += 1.6
	if R.floor == 2:
		_thesis_stack(0.5, dep - 0.55)
	else:
		_heavy("Spare Desk", 0.55, dep - 0.55, Vector3(0.7, 0.74, 0.5), Color(0.5, 0.36, 0.22))
	if R.name == "Room 402":
		var spawn := Marker3D.new()
		spawn.name = "PlayerSpawn"
		# In the aisle beside his armchair, looking at the board.
		spawn.transform = _xf(3.75, 2.475, 0.05, Vector2(1, 0))
		spawn.add_to_group("player_spawn", true)
		markers_root.add_child(spawn)
	ceiling_prop("ceiling_fan", w * 0.35, mid)
	ceiling_prop("ceiling_fan", w * 0.75, mid)
	_ceiling_grid()


## PC bench for two: monitors and keyboards on top facing the chairs, chairs
## tucked facing the monitors, a CPU tower under each end, and a crawl space.
## Students face the corridor (-d), so the bench's back panel hides anyone
## underneath from the viewing glass.
func _pc_bench(cu: float, d: float) -> void:
	if not _claim(cu - 1.2, d - 0.35, cu + 1.2, d + 0.35):
		return
	box(L(cu, d, 0.73), Vector3(2.4, 0.04, 0.7), "wood")
	box(L(cu, d - 0.33, 0.36), Vector3(2.4, 0.7, 0.03), "wood")
	for e in [-1.185, 1.185]:
		box(L(cu + e, d, 0.355), Vector3(0.03, 0.71, 0.7), "wood", false)
	surfaces.append(L(cu, d + 0.1, 0.75))
	for k in [-1.0, 1.0]:
		var su: float = cu + k * 0.7
		monitor_at(su, d - 0.12, 0.75, Vector2(0, 1))
		prop("plastic_monobloc_chair_01", su, d + 0.68, Vector2(0, -1))
		_heavy("CPU Tower", cu + k * 1.05, d + 0.05, Vector3(0.2, 0.44, 0.45), Color(0.1, 0.1, 0.12), false)
	_spot(&"bench", cu, d + 0.37, Vector2(0, 1), Vector3(0.6, 0.66, 0.1), Vector3(0, 0, -0.35), Vector3(0, 0, 0.5), 0.45)


func _f_complab() -> void:
	var w: float = R.w
	var dep: float = R.dep
	var mid := dep * 0.5
	if prop("metal_office_desk", 1.55, mid, Vector2(-1, 0), 0.0, true, true).has_volume():
		monitor_at(1.65, mid - 0.45, 0.79, Vector2(-1, 0))
	prop("dining_chair_02", 0.7, mid, Vector2(1, 0))
	var d := 1.85
	while d + 1.0 < dep - 0.05:
		var u := 2.9
		while u + 2.4 < w - 0.3:
			_pc_bench(u + 1.2, d)
			u += 3.0
		d += 1.9
	wall_prop("security_camera_01", w - 0.25, dep - 0.3, Vector2(-1, -1).normalized(), 2.9)
	_ceiling_grid()


func _f_server() -> void:
	var dep: float = R.dep
	var rx := _flush("E", 0.0, 0.65).x
	var d := 2.0
	while d < dep - 0.5:
		if furn(rx, d, 0.65, 0.8, 2.0, "dark"):
			box(L(rx - 0.33, d, 1.2), Vector3(0.02, 1.4, 0.6), "screen", false)       # rack doors face the room
		d += 0.85
	var c := flush_furn("W", dep * 0.6, 2.0, 0.7, 0.76, "metal", true)
	if c.x > 0.0:
		monitor_at(c.x - 0.1, dep * 0.6, 0.76, Vector2(1, 0))
		prop("dining_chair_02", c.x + 0.78, dep * 0.6, Vector2(-1, 0))
		prop("metal_toolbox", c.x, dep * 0.6 + 0.7, Vector2(1, 0), 0.76, false, true, 1.0, false)
	wall_prop("security_camera_01", 0.25, 0.25, Vector2(1, 1).normalized(), 2.9)
	_ceiling_grid()


func _f_restroom() -> void:
	var w: float = R.w
	var dep: float = R.dep
	var n := int((w - 0.3) / 1.1)
	var stall_front := dep - 1.63
	for i in n + 1:
		furn(0.15 + i * 1.1, dep - 0.88, 0.05, 1.5, 1.9, "int", false, 0.1)
	for i in n:
		var su: float = 0.7 + i * 1.1
		toilet(su, dep - 0.5, Vector2(0, -1))
		box(L(su, stall_front, 1.05), Vector3(1.05, 1.9, 0.04), "int")                  # stall door
		box(L(su + 0.4, stall_front - 0.03, 1.0), Vector3(0.05, 0.05, 0.03), "steel", false)
		_spot(&"stall", su, stall_front - 0.02, Vector2(0, -1), Vector3(1.0, 1.9, 0.12), Vector3(0, 0, -0.62), Vector3(0, 0, 0.6))
	# Sinks and mirror on the "W" wall, both facing the room.
	var sink_d := 3.2
	var c := flush_furn("W", sink_d, 2.6, 0.55, 0.85, "white", true)
	if c.x > 0.0:
		for k in 3:
			sink_basin(L(c.x, sink_d - 0.9 + k * 0.9, 0.85))
		var sink: Node3D = _fixture_script.create(0, Vector3(0.62, 0.3, 2.6))
		sink.name = ("Sink %s" % R.name).validate_node_name()
		sink.position = L(c.x, sink_d, 1.0)
		interactive.add_child(sink, true)
	var wi := _inset("W")
	box(L(wi + 0.012, sink_d, 1.65), Vector3(0.02, 0.8, 2.4), "glass", false)
	var mirror: Node3D = _fixture_script.create(1, Vector3(0.08, 0.8, 2.4))
	mirror.name = ("Mirror %s" % R.name).validate_node_name()
	mirror.position = L(wi + 0.05, sink_d, 1.65)
	interactive.add_child(mirror, true)
	if String(R.name).begins_with("Male"):
		var ux: float = w - _inset("E") - 0.2
		for k in 3:
			urinal(ux, 2.4 + k * 0.8, Vector2(-1, 0))
			if k < 2:
				furn(w - 0.38, 2.8 + k * 0.8, 0.5, 0.04, 1.2, "int", false, 0.3)
	prop("plunger", 2.65, dep - 0.4, Vector2(0, -1), 0.0, false, false, 1.0, false)
	_torso_spot(1.6, 3.3)
	_ceiling_grid()


func _f_mit() -> void:
	var w: float = R.w
	var dep: float = R.dep
	# Desk against the "E" wall; the technician sits on the room side of it.
	var dc := _flush("E", 3.0, 0.95)
	if flush_prop("metal_office_desk", "E", 3.0, 0.0, true, true).has_volume():
		monitor_at(dc.x + 0.15, 2.55, 0.79, Vector2(-1, 0))
		monitor_at(dc.x + 0.15, 3.2, 0.79, Vector2(-1, 0))
		prop("classic_laptop", dc.x - 0.05, 3.75, Vector2(-1, 0), 0.79, false, false, 1.0, false)
		prop("dining_chair_02", dc.x - 0.9, 3.0, Vector2(1, 0))
	flush_prop("steel_frame_shelves_01", "O", w * 0.5)
	if flush_prop("tool_cart", "W", 5.2, 0.0, true, true).has_volume():
		prop("metal_toolbox", 0.5, 5.2, Vector2(1, 0), 0.97, false, false, 1.0, false)
	flush_prop("cardboard_box_01", "E", 5.5, 0.0, true, true)
	_ceiling_grid()


func _f_records() -> void:
	var u := 1.3
	while u < R.w - 1.0:
		var d := 2.0
		while d < R.dep - 1.4:
			prop("steel_frame_shelves_01", u, d, Vector2(1, 0), 0.0, true, false)
			d += 1.15
		u += 1.5
	# Filing cabinets line the walls, drawers to the room.
	flush_prop("drawer_cabinet", "E", 0.9, 0.0, true, true)
	flush_prop("drawer_cabinet", "E", 3.4, 0.0, true, true)
	for cu in [2.6, 3.8]:
		flush_prop("drawer_cabinet", "C", cu, 0.0, true, true)
	flush_prop("cardboard_box_01", "W", R.dep - 0.5, 0.0, true, true)
	_thesis_stack(0.45, 2.2)
	_thesis_stack(5.45, 5.6)
	_torso_spot(2.05, R.dep - 0.75)
	_ceiling_grid()


func _f_director() -> void:
	var w: float = R.w
	var dep: float = R.dep
	var dd := 4.2
	# The director sits on the window side facing the door.
	if prop("metal_office_desk", w * 0.5, dd, Vector2(0, 1), 0.0, true, true).has_volume():
		prop("classic_laptop", w * 0.5 - 0.4, dd - 0.05, Vector2(0, 1), 0.79, false, false, 1.0, false)
		prop("stationery_supplies", w * 0.5 + 0.55, dd - 0.1, Vector2(0, 1), 0.79, false, false, 1.0, false)
		_desk_spot(w * 0.5, dd, Vector2(0, 1), Vector3(1.4, 0, 0.3))
	prop("modern_arm_chair_01", w * 0.5, dd + 1.1, Vector2(0, -1))
	prop("dining_chair_02", w * 0.5 - 0.6, dd - 0.95, Vector2(0, 1))
	prop("dining_chair_02", w * 0.5 + 0.6, dd - 0.95, Vector2(0, 1))
	flush_prop("wooden_bookshelf_worn", "E", 3.0)
	if flush_prop("Sofa_01", "W", 3.2).has_volume():
		prop("modern_coffee_table_01", 1.3, 3.2, Vector2(0, 1), 0.0, true, true)
	flush_furn("O", w - 0.6, 0.7, 0.6, 1.0, "dark", true)                                # the safe
	_thesis_stack(0.5, 5.6)
	wall_prop("wall_clock", w * 0.5, _inset("C") + 0.03, Vector2(0, 1), 2.4)
	wall_prop("security_camera_01", 0.25, dep - 0.3, Vector2(1, -1).normalized(), 2.9)
	_ceiling_grid()


func _f_staff() -> void:
	var w: float = R.w
	var dep: float = R.dep
	var td := 3.6
	furn(w * 0.5 - 0.3, td, 2.4, 1.0, 0.76, "wood", true)
	for k in 3:
		prop("plastic_monobloc_chair_01", w * 0.5 - 1.1 + k * 0.8, td - 0.85, Vector2(0, 1))
		prop("plastic_monobloc_chair_01", w * 0.5 - 1.1 + k * 0.8, td + 0.85, Vector2(0, -1))
	_locker_bank("E", 3.4, 5)
	_fridge_at("O", 0.65)
	var c := flush_furn("O", 3.0, 2.2, 0.6, 0.9, "white", true)                          # pantry counter
	if c.x > 0.0:
		prop("vintage_microwave", c.x + 0.5, c.y, Vector2(0, -1), 0.9, false, false, 0.6, false)
	_thesis_stack(0.45, 2.2)
	_ceiling_grid()


func _f_admissions() -> void:
	_office(true)


func _f_cashier() -> void:
	_office(false)


## Admissions (#2) and Cashier & Registrar (#3). Staff sit BEHIND both
## counters: the service window onto the lobby, and the reception counter that
## faces the corridor doors with the waiting chairs in front of it.
func _office(lobby_east: bool) -> void:
	var w: float = R.w
	var dep: float = R.dep
	var lobby := "E" if lobby_east else "W"
	var far := "W" if lobby_east else "E"
	var n: Vector2 = NORMALS[lobby]
	var win_d := 4.6 - CORR
	var c := flush_furn(lobby, win_d, 3.0, 0.6, 0.98, "wood", true)                      # under the pass window
	if c.x > 0.0:
		prop("dining_chair_02", c.x + n.x * 0.75, win_d, -n)
		monitor_at(c.x, win_d - 1.0, 0.98, n)
	if furn(w * 0.5, 2.6, 3.0, 0.55, 1.05, "wood", true):                                # reception counter
		box(L(w * 0.5, 2.6 - 0.29, 0.55), Vector3(3.0, 1.0, 0.02), "blue", false)
		prop("dining_chair_02", w * 0.5, 3.3, Vector2(0, -1))
		monitor_at(w * 0.5 + 0.9, 2.68, 1.05, Vector2(0, 1))
	for k in 3:
		flush_prop("plastic_monobloc_chair_01", "C", w * 0.5 + (k - 1) * 0.75)             # waiting chairs
	for i in 3:
		var u: float = 1.6 + i * 2.4 if lobby_east else w - 1.6 - i * 2.4
		if prop("metal_office_desk", u, dep - 1.8, Vector2(0, 1), 0.0, true, true).has_volume():
			monitor_at(u - 0.4, dep - 1.9, 0.79, Vector2(0, 1))
			prop("dining_chair_02", u, dep - 0.85, Vector2(0, -1))
	for k in 2:
		flush_prop("drawer_cabinet", far, 2.4 + k * 1.25, 0.0, true, true)
	wall_prop("wall_clock", w * 0.5, _inset("C") + 0.03, Vector2(0, 1), 2.4)
	_ceiling_grid()


func _f_lobby() -> void:
	var w: float = R.w
	var dep: float = R.dep
	# Guard / reception counter facing the entrance: the guard sits behind it
	# (corridor side) and visitors stand in front (entrance side).
	if furn(w * 0.5, 2.5, 2.2, 0.6, 1.05, "wood", true):
		box(L(w * 0.5, 2.5 + 0.31, 0.55), Vector3(2.2, 1.0, 0.02), "blue", false)
		prop("dining_chair_02", w * 0.5, 1.85, Vector2(0, 1))
		monitor_at(w * 0.5 + 0.6, 2.42, 1.05, Vector2(0, -1))
	# Benches clear of the two service windows.
	flush_prop("painted_wooden_bench", "W", 5.5, 0.0, true, true)
	flush_prop("painted_wooden_bench", "E", 5.5, 0.0, true, true)
	for u in [0.6, w - 0.6]:
		var a := flush_prop("planter_box_01", "O", u)
		if a.has_volume():
			box(Vector3(a.get_center().x, a.end.y + 0.14, a.get_center().z), Vector3(0.75, 0.3, 0.3), "plant", false)
	wall_prop("security_camera_01", 0.25, dep - 0.3, Vector2(1, -1).normalized(), 2.9)
	wall_prop("wall_clock", w * 0.5, dep - _inset("O") - 0.03, Vector2(0, -1), 2.75)
	_ceiling_grid()


func _f_faculty() -> void:
	var w: float = R.w
	var dep: float = R.dep
	for row in [2.5, 4.7]:
		for col in [1.75, 4.25]:
			if prop("metal_office_desk", col, row, Vector2(0, 1), 0.0, true, true).has_volume():
				monitor_at(col - 0.4, row - 0.12, 0.79, Vector2(0, 1))
				prop("stationery_supplies", col + 0.5, row - 0.1, Vector2(0, 1), 0.79, false, false, 1.0, false)
				prop("dining_chair_02", col, row + 0.85, Vector2(0, -1))
	# Lockers on the solid pier between the two windows, doors to the room.
	_locker_bank("O", w * 0.5, 2)
	flush_prop("drawer_cabinet", "W", 5.9, 0.0, true, true)
	flush_prop("wooden_bookshelf_worn", "E", 5.85)
	_thesis_stack(0.45, 2.3)
	wall_prop("wall_clock", w * 0.5, _inset("C") + 0.03, Vector2(0, 1), 2.4)
	_ceiling_grid()


## Stainless prep table with open legs: loot on top, a place to hide below.
func _prep_island(u: float, d: float) -> void:
	if not _claim(u - 1.3, d - 0.5, u + 1.3, d + 0.5):
		return
	box(L(u, d, 0.875), Vector3(2.6, 0.05, 1.0), "steel")
	for e in [Vector2(-1.22, -0.42), Vector2(1.22, -0.42), Vector2(-1.22, 0.42), Vector2(1.22, 0.42)]:
		box(L(u + e.x, d + e.y, 0.425), Vector3(0.05, 0.85, 0.05), "steel", false)
	box(L(u, d - 0.42, 0.15), Vector3(2.44, 0.03, 0.03), "steel", false)
	box(L(u, d + 0.42, 0.15), Vector3(2.44, 0.03, 0.03), "steel", false)
	surfaces.append(L(u, d, 0.9))
	surfaces.append(L(u + 1.0, d, 0.9))
	prop("pot_enamel_01", u - 0.85, d, Vector2(0, 1), 0.9, false, false, 1.0, false)
	prop("wooden_cutting_board", u + 0.5, d, Vector2(0, 1), 0.9, false, false, 1.0, false)
	_spot(&"island", u, d + 0.52, Vector2(0, 1), Vector3(1.8, 0.8, 0.1), Vector3(0, 0, -0.5), Vector3(0, 0, 0.5), 0.45)


## 4F Culinary Kitchen (#24): prep tables form the centre island; ranges with
## exhaust hoods stand on the solid piers of the exterior wall and sinks under
## its windows, all facing inward; fridges back onto the solid east wall.
func _f_kitchen() -> void:
	var w: float = R.w
	var dep: float = R.dep
	for u in [3.9, 8.1]:
		for d in [2.7, 4.6]:
			_prep_island(u, d)
	var oi := _inset("O")
	for u in [1.5, 4.5, 7.5, 10.5]:                                                      # sinks under the windows
		var c := flush_furn("O", u, 1.4, 0.65, 0.88, "steel", true)
		if c.x > 0.0:
			sink_basin(L(c.x, c.y, 0.88))
	for u in [3.0, 6.0, 9.0]:                                                            # ranges on the piers
		for k in [-0.27, 0.27]:
			flush_prop("electric_stove", "O", u + k, 0.0, true, true)
		box(L(u, dep - oi - 0.37, 2.05), Vector3(1.3, 0.4, 0.72), "steel", false)      # exhaust hood
		box(L(u, dep - oi - 0.2, 2.9), Vector3(0.4, 1.3, 0.36), "steel", false)        # duct to the ceiling
	_fridge_at("E", 4.7)
	_fridge_at("E", 5.45)
	var ec := flush_furn("E", 3.4, 1.6, 0.65, 0.88, "steel", true)                       # under the east window
	if ec.x > 0.0:
		sink_basin(L(ec.x, 3.4, 0.88))
	var wc := flush_furn("W", 3.6, 3.0, 0.65, 0.9, "steel", true)                        # dry store counter
	if wc.x > 0.0:
		prop("vintage_microwave", wc.x, 2.8, Vector2(1, 0), 0.9, false, false, 0.6, false)
	_ceiling_grid()


func _f_pantry() -> void:
	var dep: float = R.dep
	var d := 2.0
	while d < dep - 0.9:
		flush_prop("steel_frame_shelves_01", "W", d)
		flush_prop("steel_frame_shelves_01", "E", d)
		d += 1.15
	flush_prop("plastic_crate_01", "O", R.w * 0.5, 0.0, true, true)
	prop("cardboard_box_01", R.w * 0.5, dep - 1.5, Vector2(0, 1), 0.0, true, true)
	_torso_spot(R.w * 0.5, 4.0)
	_ceiling_grid()


## 4F Culinary Dining (#27): four clothed tables centred in the room, each
## with four chairs turned inward to the centre of its table.
func _f_dining() -> void:
	var w: float = R.w
	var dep: float = R.dep
	for u in [1.5, 4.5]:
		for d in [2.5, 4.85]:
			if not _claim(u - 0.45, d - 0.45, u + 0.45, d + 0.45):
				continue
			box(L(u, d, 0.36), Vector3(0.12, 0.72, 0.12), "wood")
			box(L(u, d, 0.02), Vector3(0.5, 0.04, 0.5), "wood", false)
			box(L(u, d, 0.735), Vector3(0.9, 0.03, 0.9), "wood")
			box(L(u, d, 0.752), Vector3(0.94, 0.006, 0.94), "white", false)             # tablecloth
			surfaces.append(L(u, d, 0.756))
			for n in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				prop("plastic_monobloc_chair_01", u + n.x * 0.62, d + n.y * 0.62, -n)
	flush_furn("O", w * 0.5, 3.0, 0.6, 0.9, "steel", true)                               # service counter
	_ceiling_grid()
