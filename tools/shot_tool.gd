extends SceneTree
## Dev utility: renders still images of a scene from fixed camera positions.
##   godot --path . --script res://tools/shot_tool.gd -- <out_dir> <scene.tscn|scn> name:px,py,pz:tx,ty,tz [more shots...]
## Adds flat ambient light so interiors are readable; it never saves the scene.

var _shots: Array[Dictionary] = []
var _out_dir: String = ""
var _frame: int = 0
var _index: int = 0
var _cam: Camera3D


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out_dir = args[0]
	var scene: Node = (load(args[1]) as PackedScene).instantiate()
	for n: Node in scene.find_children("*", "Camera3D", true, false):
		(n as Camera3D).current = false
	for n: Node in scene.find_children("*", "WorldEnvironment", true, false):
		n.free()
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(scene)
	for i: int in range(2, args.size()):
		var parts: PackedStringArray = args[i].split(":")
		var p: PackedStringArray = parts[1].split(",")
		var t: PackedStringArray = parts[2].split(",")
		_shots.append({"name": parts[0], "pos": Vector3(float(p[0]), float(p[1]), float(p[2])),
			"target": Vector3(float(t[0]), float(t[1]), float(t[2]))})
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.55, 0.65)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.9
	env.environment = e
	root.add_child(env)
	_cam = Camera3D.new()
	_cam.fov = 85.0
	root.add_child(_cam)
	_cam.current = true


func _process(_delta: float) -> bool:
	_frame += 1
	var phase: int = _frame % 8
	if phase == 1:
		if _index >= _shots.size():
			return true
		_cam.global_position = _shots[_index]["pos"]
		_cam.look_at(_shots[_index]["target"])
	elif phase == 7:
		root.get_texture().get_image().save_png("%s/%s.png" % [_out_dir, _shots[_index]["name"]])
		_index += 1
	return false
