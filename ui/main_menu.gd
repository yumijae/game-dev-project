extends Control
## Title screen: begin the night, change settings, or quit. The school is
## loaded on a background thread so the window never freezes on "Begin".

const GAME_SCENE: String = "res://main.tscn"
const TITLE: String = "EXPO NIGHT"

var _menu: VBoxContainer = null
var _settings: SettingsPanel = null
var _loading: Label = null
var _begin: Button = null
var _is_loading: bool = false


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_begin.grab_focus()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.008, 0.008, 0.012)
	add_child(backdrop)
	# A faint cold glow low on the left, like a monitor left on standby.
	var glow := TextureRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.1, 0.13, 0.2, 0.55), Color(0.0, 0.0, 0.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.2, 0.75)
	texture.fill_to = Vector2(0.85, 0.2)
	texture.width = 256
	texture.height = 256
	glow.texture = texture
	add_child(glow)

	_menu = VBoxContainer.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.offset_left = 110.0
	_menu.add_theme_constant_override("separation", 10)
	add_child(_menu)
	_menu.add_child(MenuKit.label(TITLE, 58, MenuKit.BONE, MenuKit.caps_font()))
	_menu.add_child(MenuKit.label("The power is out. Something in the lab just rebooted.", 17, MenuKit.ASH, MenuKit.italic_font()))
	var rule: ColorRect = MenuKit.rule(90.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_menu.add_child(rule)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, 26.0)
	_menu.add_child(gap)
	_begin = _add_button("BEGIN THE NIGHT", _on_begin)
	_add_button("SETTINGS", _on_settings)
	_add_button("QUIT", func() -> void: get_tree().quit())

	_loading = MenuKit.label("", 16, MenuKit.ASH, MenuKit.caps_font())
	_loading.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_loading.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_loading.offset_left = 116.0
	_loading.offset_bottom = -60.0
	add_child(_loading)

	var version: Label = MenuKit.label("v%s" % String(ProjectSettings.get_setting("application/config/version", "0.1.0")), 12, Color(MenuKit.ASH, 0.6))
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -24.0
	version.offset_bottom = -18.0
	add_child(version)

	_settings = SettingsPanel.new()
	_settings.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_settings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_settings.grow_vertical = Control.GROW_DIRECTION_BOTH
	_settings.visible = false
	_settings.closed.connect(_close_settings)
	add_child(_settings)


func _add_button(text: String, action: Callable) -> Button:
	var item: Button = MenuKit.button(text, 21)
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	item.pressed.connect(action)
	_menu.add_child(item)
	return item


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _settings.visible:
		_close_settings()
		get_viewport().set_input_as_handled()


func _on_settings() -> void:
	if _is_loading:
		return
	_menu.visible = false
	_settings.visible = true
	_settings.grab_initial_focus()


func _close_settings() -> void:
	_settings.visible = false
	_menu.visible = true
	_begin.grab_focus()


func _on_begin() -> void:
	if _is_loading:
		return
	_is_loading = true
	for child: Node in _menu.get_children():
		if child is Button:
			(child as Button).disabled = true
	_loading.text = "LOADING"
	if ResourceLoader.load_threaded_request(GAME_SCENE) != OK:
		get_tree().change_scene_to_file(GAME_SCENE)


func _process(_delta: float) -> void:
	if not _is_loading:
		return
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(GAME_SCENE, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_loading.text = "LOADING   %d%%" % roundi(float(progress[0]) * 100.0)
		ResourceLoader.THREAD_LOAD_LOADED:
			_is_loading = false
			_loading.text = "LOADING   100%"
			get_tree().change_scene_to_packed(ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene)
		_:
			_is_loading = false
			get_tree().change_scene_to_file(GAME_SCENE)
