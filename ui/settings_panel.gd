class_name SettingsPanel
extends PanelContainer
## The settings screen, shared by the main menu and the pause menu. Built in
## code; every control writes straight through to GameSettings, which applies
## and saves the change at once.

signal closed

const PAGES: Array[String] = ["GRAPHICS", "GAME", "AUDIO", "CONTROLS"]
const CONTROLS: Array = [
	["W A S D", "Move"], ["Shift", "Sprint"], ["Ctrl", "Crouch"], ["E", "Interact"],
	["Q", "Next action"], ["F", "Flashlight"], ["Tab", "Raise phone"], ["V", "Cameras app"],
	["T", "Change footwear"], ["1 - 6", "Backpack to hand"], ["R", "Switch hand"],
	["Left mouse", "Use held item"], ["Right mouse", "Cancel / back"], ["X", "Drop item"], ["G", "Stifle a gasp"],
	["Esc", "Pause"],
]

var _tabs: Array[Button] = []
var _pages: Array[Control] = []
var _scale_slider: HSlider = null
var _quality: OptionButton = null
var _auto_check: CheckButton = null
var _back: Button = null


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuKit.paper(34.0))
	custom_minimum_size = Vector2(700.0, 0.0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	add_child(column)
	column.add_child(MenuKit.label("SETTINGS", 26, MenuKit.BONE, MenuKit.caps_font()))
	var rule: ColorRect = MenuKit.rule(60.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(rule)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 22)
	column.add_child(tab_row)
	for i: int in PAGES.size():
		var tab: Button = MenuKit.button(PAGES[i], 13)
		tab.pressed.connect(_show_page.bind(i))
		tab_row.add_child(tab)
		_tabs.append(tab)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0.0, 340.0)
	column.add_child(holder)
	for build: Callable in [_build_graphics, _build_game, _build_audio, _build_controls]:
		var page := VBoxContainer.new()
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.add_theme_constant_override("separation", 12)
		holder.add_child(page)
		_pages.append(page)
		build.call(page)

	_back = MenuKit.button("BACK", 16)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back.pressed.connect(func() -> void: closed.emit())
	column.add_child(_back)
	_show_page(0)


## Call when the panel is shown: picks up anything auto quality changed while
## it was closed, and gives keyboard users a focus.
func grab_initial_focus() -> void:
	_quality.selected = GameSettings.preset
	_scale_slider.value = GameSettings.render_scale
	_auto_check.set_pressed_no_signal(GameSettings.auto_quality)
	_tabs[0].grab_focus()


func _show_page(index: int) -> void:
	for i: int in _pages.size():
		_pages[i].visible = i == index
		_tabs[i].add_theme_color_override("font_color", MenuKit.EMBER if i == index else MenuKit.ASH)
		_tabs[i].add_theme_color_override("font_focus_color", MenuKit.EMBER if i == index else MenuKit.BONE)
		_tabs[i].add_theme_color_override("font_hover_color", MenuKit.EMBER if i == index else MenuKit.BONE)


# ---------------------------------------------------------------------- pages

func _build_graphics(page: VBoxContainer) -> void:
	_quality = OptionButton.new()
	for preset_name: String in GameSettings.PRESET_NAMES:
		_quality.add_item(preset_name)
	_quality.selected = GameSettings.preset
	_quality.item_selected.connect(_on_quality_selected)
	_row(page, "Quality", _quality)

	_auto_check = _toggle(page, "Auto-lower quality if slow", GameSettings.auto_quality,
		func(on: bool) -> void: GameSettings.set_value(&"auto_quality", on))

	_scale_slider = _slider(page, "Resolution scale", GameSettings.MIN_RENDER_SCALE, 1.0, 0.05, GameSettings.render_scale,
		func(value: float) -> String: return "%d%%" % roundi(value * 100.0),
		func(value: float) -> void: GameSettings.set_value(&"render_scale", value))

	var display := OptionButton.new()
	display.add_item("Windowed")
	display.add_item("Fullscreen")
	display.selected = 1 if GameSettings.fullscreen else 0
	display.item_selected.connect(func(index: int) -> void: GameSettings.set_value(&"fullscreen", index == 1))
	_row(page, "Display", display)

	_toggle(page, "VSync", GameSettings.vsync, func(on: bool) -> void: GameSettings.set_value(&"vsync", on))

	var cap := OptionButton.new()
	for limit: int in GameSettings.FPS_CAPS:
		cap.add_item("Unlimited" if limit == 0 else "%d FPS" % limit)
	cap.selected = maxi(GameSettings.FPS_CAPS.find(GameSettings.fps_cap), 0)
	cap.item_selected.connect(func(index: int) -> void: GameSettings.set_value(&"fps_cap", GameSettings.FPS_CAPS[index]))
	_row(page, "Frame rate limit", cap)

	_slider(page, "Brightness", 0.6, 1.6, 0.05, GameSettings.brightness,
		func(value: float) -> String: return "%d%%" % roundi(value * 100.0),
		func(value: float) -> void: GameSettings.set_value(&"brightness", value))

	var note: Label = MenuKit.label("", 13, MenuKit.ASH, MenuKit.italic_font())
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Graphics card: %s.  If the game stutters, lower Quality first, then Resolution scale." % GameSettings.adapter_name()
	page.add_child(note)


func _build_game(page: VBoxContainer) -> void:
	_slider(page, "Mouse sensitivity", 0.2, 3.0, 0.05, GameSettings.sensitivity,
		func(value: float) -> String: return "%.2fx" % value,
		func(value: float) -> void: GameSettings.set_value(&"sensitivity", value))
	_toggle(page, "Invert mouse Y", GameSettings.invert_y, func(on: bool) -> void: GameSettings.set_value(&"invert_y", on))
	_slider(page, "Field of view", GameSettings.FOV_MIN, GameSettings.FOV_MAX, 1.0, GameSettings.fov,
		func(value: float) -> String: return "%d" % roundi(value),
		func(value: float) -> void: GameSettings.set_value(&"fov", value))
	_toggle(page, "Jumpscares", GameSettings.jumpscares, func(on: bool) -> void: GameSettings.set_value(&"jumpscares", on))
	_toggle(page, "Robot taunts", GameSettings.taunts, func(on: bool) -> void: GameSettings.set_value(&"taunts", on))
	_toggle(page, "Show arms", GameSettings.show_arms, func(on: bool) -> void: GameSettings.set_value(&"show_arms", on))


func _build_audio(page: VBoxContainer) -> void:
	for knob: Array in [["Master volume", &"master_volume"], ["Effects", &"effects_volume"],
			["Ambience (rain, thunder)", &"ambience_volume"], ["Phone & interface", &"interface_volume"]]:
		var key: StringName = knob[1]
		_slider(page, knob[0], 0.0, 1.0, 0.05, float(GameSettings.get(key)),
			func(value: float) -> String: return "%d%%" % roundi(value * 100.0),
			func(value: float) -> void: GameSettings.set_value(key, value))


func _build_controls(page: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 9)
	page.add_child(grid)
	for entry: Array in CONTROLS:
		var key: Label = MenuKit.label(String(entry[0]), 15, MenuKit.BONE, MenuKit.caps_font())
		key.custom_minimum_size = Vector2(120.0, 0.0)
		grid.add_child(key)
		var action: Label = MenuKit.label(String(entry[1]), 15, MenuKit.ASH)
		action.custom_minimum_size = Vector2(170.0, 0.0)
		grid.add_child(action)


func _on_quality_selected(index: int) -> void:
	GameSettings.set_value(&"preset", index)
	# A preset brings its own resolution scale; show it.
	_scale_slider.value = GameSettings.render_scale


# -------------------------------------------------------------------- helpers

func _row(page: VBoxContainer, title: String, control: Control, value_label: Label = null) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	page.add_child(row)
	var name_label: Label = MenuKit.label(title, 17, MenuKit.BONE)
	name_label.custom_minimum_size = Vector2(250.0, 0.0)
	row.add_child(name_label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.add_theme_font_override("font", MenuKit.body_font())
	row.add_child(control)
	if value_label == null:
		value_label = MenuKit.label("", 15, MenuKit.ASH)
	value_label.custom_minimum_size = Vector2(70.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)


func _slider(page: VBoxContainer, title: String, from: float, to: float, step: float, value: float,
		format: Callable, on_changed: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = from
	slider.max_value = to
	slider.step = step
	slider.value = value
	var readout: Label = MenuKit.label(format.call(value), 15, MenuKit.ASH)
	slider.value_changed.connect(func(new_value: float) -> void:
		readout.text = format.call(new_value)
		on_changed.call(new_value))
	_row(page, title, slider, readout)
	return slider


func _toggle(page: VBoxContainer, title: String, on: bool, on_changed: Callable) -> CheckButton:
	var box := HBoxContainer.new()
	var check := CheckButton.new()
	check.button_pressed = on
	check.toggled.connect(on_changed)
	box.add_child(check)
	_row(page, title, box)
	return check
