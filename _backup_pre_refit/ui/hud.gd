extends CanvasLayer
## Crosshair, interaction prompt, loot counter and current-room readout.
## Hook it to a player with the `player_path` export.

@export var player_path: NodePath

var _prompt: Label
var _stats: Label
var _log: Label
var _log_timer := 0.0
var _location: Label
var _player: Node3D
var _school: Node3D


func _ready() -> void:
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(crosshair)

	_prompt = _make_label(Control.PRESET_CENTER_BOTTOM, 20)
	_prompt.offset_top = -140
	_prompt.offset_bottom = -110
	_stats = _make_label(Control.PRESET_TOP_LEFT, 18)
	_stats.position = Vector2(16, 12)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_log = _make_label(Control.PRESET_CENTER_BOTTOM, 18)
	_log.offset_top = -100
	_log.offset_bottom = -72
	_stats.text = "Loot: 0 items   Value: 0"
	_location = _make_label(Control.PRESET_TOP_RIGHT, 18)
	_location.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_location.offset_right = -16
	_location.offset_top = 12
	_location.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var player := get_node_or_null(player_path)
	_player = player
	if player:
		player.prompt_changed.connect(func(t): _prompt.text = t)
		player.inventory_changed.connect(_on_inventory_changed)


func _process(delta: float) -> void:
	_update_location()
	if _log_timer > 0.0:
		_log_timer -= delta
		if _log_timer <= 0.0:
			_log.text = ""


func _on_inventory_changed(items: Array, total: int) -> void:
	_stats.text = "Loot: %d items   Value: %d" % [items.size(), total]
	var last: Dictionary = items[items.size() - 1]
	_log.text = "+ %s (%d)" % [last.name, last.value]
	_log_timer = 2.0


func _update_location() -> void:
	if _player == null:
		return
	if _school == null:
		_school = get_tree().get_first_node_in_group("school")
		if _school == null:
			return
	var p := _school.to_local(_player.global_position)
	var fh: float = _school.get_meta("floor_height", 3.8)
	var names: Array = _school.get_meta("floor_names", [])
	var fl := clampi(int(floor((p.y + 0.5) / fh)), 0, names.size() - 1)
	var text := "Outside"
	for r in _school.get_meta("rooms", []):
		if r[1] == fl and p.x >= r[2] and p.x <= r[4] and p.z >= r[3] and p.z <= r[5]:
			text = "%s  ·  %s" % [names[fl], r[0]]
			break
	if text == "Outside" and fl == names.size() - 1:
		text = "Roof"
	_location.text = text


func _make_label(preset: Control.LayoutPreset, font_size: int) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l
