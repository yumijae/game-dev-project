extends CanvasLayer
## Heads-up display, built entirely in code and driven by EventBus.
##
## It is meant to stay out of the way. Type is a quiet serif in bone white
## with dried-blood red for what can kill you; nothing is boxed or brightly
## coloured. Almost every element fades out when it has nothing to say:
##
##   * a stat line shows only while that stat is off its resting value
##   * the backpack dims a few seconds after it last changed
##   * the objective and room name surface when they change, then recede
##   * the reticle is a dot that opens into a ring over something usable
##
## Still here, as before: clock and objective, the survival stats, hands and
## backpack, the interaction list, channel progress, subtitles, the
## panel, the gasp prompt and the ending screen.

const BONE: Color = Color(0.84, 0.81, 0.74)
const ASH: Color = Color(0.56, 0.55, 0.52)
const BLOOD: Color = Color(0.6, 0.09, 0.08)
const EMBER: Color = Color(0.86, 0.22, 0.16)
const SERIF_FONTS: Array[String] = ["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"]
## How faint a resting element gets.
const IDLE_ALPHA: float = 0.3
const FADE_SPEED: float = 2.2
const OBJECTIVE_SHOW_TIME: float = 9.0
const LOCATION_SHOW_TIME: float = 5.0
const INVENTORY_SHOW_TIME: float = 5.0
const TEXT_FADE_IN: float = 0.3
const TEXT_FADE_OUT: float = 0.7

const SPEAKER_COLORS: Dictionary = {
	&"juan": Color(0.84, 0.81, 0.74),
	&"jude": Color(0.84, 0.81, 0.74),
	&"voice": Color(0.82, 0.62, 0.42),
	&"whisper": Color(0.62, 0.68, 0.8),
	&"door_voice": Color(0.82, 0.62, 0.42),
	&"CONCIERGE": Color(0.55, 0.95, 0.78),
}
const SPEAKER_PREFIX: Dictionary = {
	&"juan": "",
	&"jude": "",
	&"voice": "A voice outside  -  ",
	&"whisper": "A whisper  -  ",
	&"door_voice": "A voice behind the door  -  ",
	&"CONCIERGE": "CONCIERGE  -  ",
}
## Panic runs from a calm grey to the same red as blood.
const PANIC_COLORS: Array[Color] = [
	Color(0.56, 0.55, 0.52), Color(0.72, 0.6, 0.42), Color(0.78, 0.38, 0.22), Color(0.86, 0.22, 0.16),
]
const SLOT_KEYS: Array[String] = ["L", "R", "1", "2", "3", "4", "5", "6"]

@export var player_path: NodePath

var _player: PlayerController = null
var _root: Control = null
var _font_body: Font = null
var _font_italic: Font = null
var _font_caps: Font = null
var _clock: Label = null
var _location: Label = null
var _objective: Label = null
var _stamina_bar: ProgressBar = null
var _panic_bar: ProgressBar = null
var _panic_label: Label = null
var _battery_bar: ProgressBar = null
var _stat_rows: Dictionary = {}
var _status: Label = null
var _reticle: Panel = null
var _reticle_dot: StyleBoxFlat = null
var _reticle_ring: StyleBoxFlat = null
var _has_prompt: bool = false
var _prompt: VBoxContainer = null
var _channel_box: VBoxContainer = null
var _channel_label: Label = null
var _channel_bar: ProgressBar = null
var _subtitle: Label = null
var _notification: Label = null
var _inventory_bar: HBoxContainer = null
var _slot_names: Array[Label] = []
var _slot_rules: Array[ColorRect] = []
var _gasp_label: Label = null
var _noise_meter: NoiseMeter = null
var _vignette: ColorRect = null
var _end_panel: ColorRect = null
var _end_title: Label = null
var _end_text: Label = null
## Target opacity of every element that fades. Control -> float.
var _fade_targets: Dictionary = {}
var _subtitle_time: float = 0.0
var _subtitle_total: float = 0.0
var _notification_time: float = 0.0
var _notification_total: float = 0.0
var _objective_time: float = OBJECTIVE_SHOW_TIME
var _location_time: float = 0.0
var _inventory_time: float = INVENTORY_SHOW_TIME
var _location_timer: float = 0.0
var _gasp_time: float = 0.0
var _panic: float = 0.0
var _is_over: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_node_or_null(player_path) as PlayerController
	_make_fonts()
	_build()
	EventBus.time_advanced.connect(_on_time_advanced)
	EventBus.rescue_time_changed.connect(_on_rescue_time_changed)
	EventBus.objective_updated.connect(_on_objective_updated)
	EventBus.stamina_changed.connect(func(value: float) -> void: _stamina_bar.value = value)
	EventBus.panic_changed.connect(_on_panic_changed)
	EventBus.phone_battery_changed.connect(func(percent: float) -> void: _battery_bar.value = percent)
	EventBus.inventory_changed.connect(_on_inventory_changed)
	EventBus.ui_prompt_changed.connect(_on_prompt_changed)
	EventBus.ui_subtitle.connect(_on_subtitle)
	EventBus.ui_notification.connect(_on_notification)
	EventBus.ui_channel_started.connect(_on_channel_started)
	EventBus.ui_channel_progress.connect(func(ratio: float) -> void: _channel_bar.value = ratio)
	EventBus.ui_channel_finished.connect(func(_completed: bool) -> void: _channel_box.visible = false)
	EventBus.ui_gasp_prompt.connect(_on_gasp_prompt)
	EventBus.ui_peek_changed.connect(func(_peeking: bool) -> void: _refresh_vignette())
	EventBus.player_hidden_changed.connect(func(_hidden: bool, _spot: Node3D) -> void: _refresh_vignette())
	EventBus.game_won.connect(_on_game_won)
	EventBus.game_lost.connect(_on_game_lost)
	_clock.text = TimeManager.get_formatted_time()
	_refresh_inventory()


func _process(delta: float) -> void:
	_subtitle_time = _fade_text(_subtitle, _subtitle_time, _subtitle_total, delta)
	_notification_time = _fade_text(_notification, _notification_time, _notification_total, delta)
	_objective_time = maxf(_objective_time - delta, 0.0)
	_location_time = maxf(_location_time - delta, 0.0)
	_inventory_time = maxf(_inventory_time - delta, 0.0)
	_fade_targets[_objective] = 1.0 if _objective_time > 0.0 else IDLE_ALPHA
	_fade_targets[_location] = 1.0 if _location_time > 0.0 else IDLE_ALPHA
	_fade_targets[_inventory_bar] = 1.0 if _inventory_time > 0.0 else IDLE_ALPHA
	_fade_targets[_end_panel] = 1.0 if _is_over else 0.0
	_noise_meter.visible = not _is_over
	for element: Control in _fade_targets:
		var target: float = _fade_targets[element]
		element.modulate.a = move_toward(element.modulate.a, target, delta * FADE_SPEED)
	if _gasp_time > 0.0:
		_gasp_time -= delta
		_gasp_label.modulate.a = 0.55 + 0.45 * sin(float(Time.get_ticks_msec()) * 0.03)
	if _player == null or not is_instance_valid(_player):
		return
	_location_timer -= delta
	if _location_timer <= 0.0:
		_location_timer = 0.25
		var place: String = Campus.location_name(_player.global_position)
		if place != _location.text:
			_location.text = place
			_location_time = LOCATION_SHOW_TIME
		_refresh_status()
	# 60%+ Panic: the reticle will not hold still.
	var shake: float = 0.0
	if _player.stats.panic >= 60.0:
		shake = lerpf(2.0, 9.0, clampf((_player.stats.panic - 60.0) / 40.0, 0.0, 1.0))
	_reticle.position = _reticle_home() + Vector2(randf_range(-shake, shake), randf_range(-shake, shake))


## Counts a line of text down, fading it in at the start and out at the end.
func _fade_text(label: Label, remaining: float, total: float, delta: float) -> float:
	if remaining <= 0.0:
		label.modulate.a = 0.0
		return 0.0
	remaining -= delta
	label.modulate.a = clampf(minf((total - remaining) / TEXT_FADE_IN, remaining / TEXT_FADE_OUT), 0.0, 1.0)
	if remaining <= 0.0:
		label.text = ""
	return remaining


# ---------------------------------------------------------------------- build

func _make_fonts() -> void:
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(SERIF_FONTS)
	_font_body = serif
	var italic := SystemFont.new()
	italic.font_names = PackedStringArray(SERIF_FONTS)
	italic.font_italic = true
	_font_italic = italic
	# Small headings: the same face, set wide.
	var caps := FontVariation.new()
	caps.base_font = serif
	caps.spacing_glyph = 3
	_font_caps = caps


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_vignette = ColorRect.new()
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(0.0, 0.0, 0.0, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_vignette)

	# Top left: the hour, where you are, what you are trying to do.
	var top_left := VBoxContainer.new()
	top_left.position = Vector2(28.0, 22.0)
	top_left.add_theme_constant_override("separation", 4)
	_root.add_child(top_left)
	_clock = _label(top_left, 17, BONE, _font_caps)
	_rule(top_left, 46.0, Color(BLOOD, 0.9))
	_location = _label(top_left, 15, ASH, _font_italic)
	_objective = _label(top_left, 15, BONE, _font_body)
	_objective.custom_minimum_size = Vector2(360.0, 0.0)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Bottom left: the body. Each line appears only while it matters.
	var stats := VBoxContainer.new()
	stats.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stats.offset_left = 28.0
	# Sits clear of the backpack row along the bottom edge.
	stats.offset_top = -104.0
	stats.offset_bottom = -104.0
	stats.add_theme_constant_override("separation", 9)
	_root.add_child(stats)
	_status = _label(stats, 13, ASH, _font_italic)
	_stamina_bar = _stat_row(stats, &"stamina", "Breath", BONE, 100.0)
	_panic_bar = _stat_row(stats, &"panic", "Fear", PANIC_COLORS[0], 0.0)
	_panic_label = (_stat_rows[&"panic"] as Control).get_child(0) as Label
	_battery_bar = _stat_row(stats, &"battery", "Phone", ASH, PlayerStats.STARTING_BATTERY)

	# The reticle: a dot, or a ring over something you can use.
	_reticle_dot = _disc(Color(BONE, 0.55), Color(0.0, 0.0, 0.0, 0.0), 0)
	_reticle_ring = _disc(Color(0.0, 0.0, 0.0, 0.0), Color(BONE, 0.85), 1)
	_reticle = Panel.new()
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_reticle)
	_set_reticle(false)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BEGIN
	center.offset_bottom = -26.0
	center.alignment = BoxContainer.ALIGNMENT_END
	center.add_theme_constant_override("separation", 14)
	_root.add_child(center)
	_subtitle = _label(center, 21, BONE, _font_italic)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.custom_minimum_size = Vector2(720.0, 0.0)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.modulate.a = 0.0
	_prompt = VBoxContainer.new()
	_prompt.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("separation", 3)
	center.add_child(_prompt)
	_channel_box = VBoxContainer.new()
	_channel_box.visible = false
	_channel_box.add_theme_constant_override("separation", 6)
	center.add_child(_channel_box)
	_channel_label = _label(_channel_box, 14, ASH, _font_italic)
	_channel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_channel_bar = _bar(_channel_box, BONE, 0.0)
	_channel_bar.max_value = 1.0
	_channel_bar.custom_minimum_size = Vector2(260.0, 2.0)
	_channel_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Hands and backpack: a name over a hairline, red under the hand in use.
	_inventory_bar = HBoxContainer.new()
	_inventory_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_inventory_bar.add_theme_constant_override("separation", 16)
	center.add_child(_inventory_bar)
	for i: int in InventoryComponent.TOTAL_SLOTS:
		if i == InventoryComponent.HAND_SLOTS:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(18.0, 0.0)
			_inventory_bar.add_child(gap)
		var slot := VBoxContainer.new()
		slot.custom_minimum_size = Vector2(98.0, 0.0)
		slot.add_theme_constant_override("separation", 2)
		_inventory_bar.add_child(slot)
		var key: Label = _label(slot, 10, ASH, _font_caps)
		key.text = SLOT_KEYS[i] if i < SLOT_KEYS.size() else str(i - InventoryComponent.HAND_SLOTS + 1)
		var item: Label = _label(slot, 13, BONE, _font_body)
		item.custom_minimum_size = Vector2(98.0, 34.0)
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_slot_names.append(item)
		_slot_rules.append(_rule(slot, 98.0, Color(ASH, 0.35)))

	# Bottom right: how loud Juan just was; red when a robot heard it.
	_noise_meter = NoiseMeter.new()
	_noise_meter.bone = BONE
	_noise_meter.ash = ASH
	_noise_meter.ember = EMBER
	_noise_meter.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_noise_meter.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_noise_meter.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_noise_meter.offset_right = -32.0
	_noise_meter.offset_bottom = -104.0
	_noise_meter.set_player(_player)
	_root.add_child(_noise_meter)

	_notification = _label(_root, 16, BONE, _font_caps)
	_notification.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notification.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notification.offset_top = 92.0
	_notification.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification.modulate.a = 0.0

	_gasp_label = _label(_root, 26, EMBER, _font_caps)
	_gasp_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_gasp_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_gasp_label.offset_top = -130.0
	_gasp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gasp_label.text = "G     STIFLE IT"
	_gasp_label.visible = false


	_end_panel = ColorRect.new()
	_end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_end_panel.color = Color(0.0, 0.0, 0.0, 0.94)
	_end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_panel.modulate.a = 0.0
	_root.add_child(_end_panel)
	var end_box := VBoxContainer.new()
	end_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	end_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	end_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	end_box.add_theme_constant_override("separation", 22)
	_end_panel.add_child(end_box)
	_end_title = _label(end_box, 38, BONE, _font_caps)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var end_rule: ColorRect = _rule(end_box, 70.0, Color(BLOOD, 0.9))
	end_rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_end_text = _label(end_box, 18, BONE, _font_body)
	_end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_text.custom_minimum_size = Vector2(640.0, 0.0)
	_end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint: Label = _label(end_box, 12, ASH, _font_caps)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "R     BEGIN THE NIGHT AGAIN          ESC     MAIN MENU"


func _label(parent: Control, font_size: int, color: Color, font: Font) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# A soft dark halo instead of a hard outline keeps it legible over a lit wall.
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_constant_override("shadow_outline_size", 6)
	label.uppercase = font == _font_caps
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## A one-pixel line.
func _rule(parent: Control, width: float, color: Color) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(width, 1.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return rule


## A small heading over a hairline bar. The whole row fades as one.
func _stat_row(parent: Control, id: StringName, title: String, color: Color, value: float) -> ProgressBar:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.modulate.a = 0.0
	parent.add_child(row)
	var heading: Label = _label(row, 10, ASH, _font_caps)
	heading.text = title
	_stat_rows[id] = row
	_fade_targets[row] = 0.0
	return _bar(row, color, value)


func _bar(parent: Control, color: Color, value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150.0, 2.0)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.add_theme_stylebox_override("background", _flat(Color(BONE, 0.14)))
	bar.add_theme_stylebox_override("fill", _flat(color))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _flat(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style


func _disc(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(12)
	style.anti_aliasing = true
	return style


func _set_reticle(over_something: bool) -> void:
	_reticle.add_theme_stylebox_override("panel", _reticle_ring if over_something else _reticle_dot)
	var extent: float = 11.0 if over_something else 4.0
	_reticle.custom_minimum_size = Vector2(extent, extent)
	_reticle.size = Vector2(extent, extent)


func _reticle_home() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5 - _reticle.size * 0.5


# -------------------------------------------------------------------- updates

func _on_time_advanced(_hour: int, _minute: int, formatted: String, _progress: float) -> void:
	_clock.text = formatted


func _on_rescue_time_changed(_hour: int, _minute: int) -> void:
	_notify("Help comes at %s" % TimeManager.get_rescue_time_text(), 5.0)


func _on_objective_updated(_objective_id: StringName, text: String, _progress: float) -> void:
	if text != _objective.text:
		_objective_time = OBJECTIVE_SHOW_TIME
	_objective.text = text


func _on_panic_changed(value: float, tier: int) -> void:
	_panic = value
	_panic_bar.value = value
	_panic_label.text = "Fear  -  %s" % PlayerStats.TIER_NAMES[tier]
	_panic_label.add_theme_color_override("font_color", PANIC_COLORS[tier])
	_panic_bar.add_theme_stylebox_override("fill", _flat(PANIC_COLORS[tier]))


func _refresh_status() -> void:
	var stats: PlayerStats = _player.stats
	# A stat only earns its place on screen while it is off its resting value.
	_fade_targets[_stat_rows[&"stamina"]] = 1.0 if stats.stamina < 99.0 else 0.0
	_fade_targets[_stat_rows[&"panic"]] = 1.0 if _panic >= 5.0 else 0.0
	_fade_targets[_stat_rows[&"battery"]] = 1.0 if _player.phone.is_flashlight_on or _player.phone.is_phone_out \
		or stats.phone_battery <= 20.0 else 0.0

	var parts: Array[String] = [stats.get_footwear_name()]
	if stats.is_bleeding:
		parts.append("Bleeding")
	if stats.has_shaky_hands:
		parts.append("Hands shaking")
	if stats.stamina < PlayerStats.HEAVY_BREATHING_THRESHOLD:
		parts.append("Breathing hard")
	if stats.in_darkness:
		parts.append("In the dark")
	var load: float = _player.inventory.get_load()
	if load >= 1.0:
		var heavy: bool = load > InventoryComponent.SLOW_LOAD
		parts.append("Carrying %.1f / %d kg%s" % [load, int(InventoryComponent.MAX_LOAD),
			"  (too heavy to run)" if load > InventoryComponent.SPRINT_LOAD else ("  (slowed)" if heavy else "")])
	_status.text = "\n".join(parts)
	var alarmed: bool = stats.is_bleeding
	_status.add_theme_color_override("font_color", EMBER if alarmed else ASH)


func _on_inventory_changed() -> void:
	_inventory_time = INVENTORY_SHOW_TIME
	_refresh_inventory()


func _refresh_inventory() -> void:
	if _player == null or _player.inventory == null:
		return
	var inventory: InventoryComponent = _player.inventory
	for i: int in InventoryComponent.TOTAL_SLOTS:
		var content: String = ""
		if not inventory.is_slot_empty(i):
			content = ItemDB.get_item_name(inventory.get_slot_id(i))
			if inventory.get_slot_count(i) > 1:
				content += "  x%d" % inventory.get_slot_count(i)
		_slot_names[i].text = content
		var active: bool = i == inventory.active_hand
		_slot_rules[i].color = Color(BLOOD, 1.0) if active else Color(ASH, 0.35)
		_slot_rules[i].custom_minimum_size.y = 2.0 if active else 1.0


func _on_prompt_changed(actions: Array, selected: int) -> void:
	for child: Node in _prompt.get_children():
		child.queue_free()
	_has_prompt = not actions.is_empty()
	_set_reticle(_has_prompt)
	for i: int in actions.size():
		var action: Dictionary = actions[i]
		var is_selected: bool = i == selected
		var line: Label = _label(_prompt, 17 if is_selected else 14, BONE if is_selected else Color(ASH, 0.75), _font_body)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var label: String = action["label"]
		line.text = ("E     %s" % label) if is_selected else label
	if actions.size() > 1:
		var hint: Label = _label(_prompt, 10, ASH, _font_caps)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.text = "Q     other actions"


func _on_subtitle(text: String, duration: float, speaker: StringName) -> void:
	var prefix: String = SPEAKER_PREFIX.get(speaker, "")
	_subtitle.text = prefix + text
	_subtitle.add_theme_color_override("font_color", SPEAKER_COLORS.get(speaker, BONE))
	_subtitle_time = duration
	_subtitle_total = duration


func _on_notification(text: String, duration: float) -> void:
	_notify(text, duration)


func _notify(text: String, duration: float) -> void:
	_notification.text = text
	_notification_time = duration
	_notification_total = duration


func _on_channel_started(label: String, duration: float) -> void:
	_channel_label.text = "%s  -  %.0f s  -  right click to stop" % [label, duration]
	_channel_bar.value = 0.0
	_channel_box.visible = true


func _on_gasp_prompt(active: bool, window: float) -> void:
	_gasp_label.visible = active
	_gasp_time = window if active else 0.0


## Darkens the screen while hiding or peeking under a door.
func _refresh_vignette() -> void:
	if _player == null:
		return
	if _player.is_peeking:
		_vignette.color = Color(0.0, 0.0, 0.0, 0.25)
	elif _player.is_hidden:
		_vignette.color = Color(0.0, 0.0, 0.0, 0.55)
	else:
		_vignette.color = Color(0.0, 0.0, 0.0, 0.0)


func _on_game_won(_ending_id: StringName, title: String, description: String) -> void:
	_end_title.text = title
	_end_title.add_theme_color_override("font_color", BONE)
	_end_text.text = description
	_is_over = true


func _on_game_lost(cause: String) -> void:
	_end_title.text = "You did not see the morning"
	_end_title.add_theme_color_override("font_color", EMBER)
	_end_text.text = "%s\n\n%s" % [cause, TimeManager.get_formatted_time()]
	_is_over = true
