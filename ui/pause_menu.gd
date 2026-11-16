class_name PauseMenu
extends CanvasLayer
## Esc pauses the night: resume, settings, restart, back to the title, quit.
## Added by GameDirector. Once the night has ended, Esc goes straight back to
## the title screen instead.

const MENU_SCENE: String = "res://ui/main_menu.tscn"

var director: GameDirector = null
var is_open: bool = false

var _shade: ColorRect = null
var _menu: VBoxContainer = null
var _settings: SettingsPanel = null
var _resume: Button = null


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade = ColorRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.color = Color(0.0, 0.0, 0.0, 0.78)
	add_child(_shade)

	_menu = VBoxContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.add_theme_constant_override("separation", 10)
	_shade.add_child(_menu)
	var title: Label = MenuKit.label("PAUSED", 34, MenuKit.BONE, MenuKit.caps_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(title)
	var rule: ColorRect = MenuKit.rule(70.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_menu.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 14.0)
	_menu.add_child(gap)
	_resume = _add_button("RESUME", close)
	_add_button("SETTINGS", _open_settings)
	_add_button("RESTART THE NIGHT", _on_restart)
	_add_button("MAIN MENU", go_to_main_menu)
	_add_button("QUIT GAME", func() -> void: get_tree().quit())

	_settings = SettingsPanel.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	_shade.add_child(_settings)
	_shade.visible = false


func _add_button(text: String, action: Callable) -> Button:
	var item: Button = MenuKit.button(text, 19)
	item.pressed.connect(action)
	_menu.add_child(item)
	return item


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if director != null and director.is_game_over:
		go_to_main_menu()
	elif not is_open:
		open()
	elif _settings.visible:
		_close_settings()
	else:
		close()


func open() -> void:
	if is_open:
		return
	is_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_settings.visible = false
	_menu.visible = true
	_shade.visible = true
	_resume.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_shade.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func go_to_main_menu() -> void:
	is_open = false
	TimeManager.stop()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_restart() -> void:
	is_open = false
	if director != null:
		director.restart()


func _open_settings() -> void:
	_menu.visible = false
	_settings.visible = true
	_settings.grab_initial_focus()


func _close_settings() -> void:
	_settings.visible = false
	_menu.visible = true
	_resume.grab_focus()
