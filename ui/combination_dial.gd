class_name CombinationDial
extends CanvasLayer
## The side padlock up close: four number wheels Juan turns by hand.
##
##   A / D or the mouse    pick a wheel        W / S or the wheel   turn it
##   E or left click       try the shackle     Esc or right click   step back
##
## The digits he has found written round the school show faintly underneath.
## Turning is near-silent; a wrong try rattles the lock (RehasGate). Getting
## hit closes it.

const DIGIT_SIZE: int = 84
const WHEEL_WIDTH: float = 96.0

var _player: PlayerController = null
var _gate: RehasGate = null
var _digits: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])
var _selected: int = 0
var _wheels: Array[Label] = []
var _above: Array[Label] = []
var _below: Array[Label] = []
var _marks: Array[ColorRect] = []
var _known: Label = null
var _row: HBoxContainer = null
## Sideways mouse travel (px) since the last wheel change.
var _sweep: float = 0.0
const SWEEP_PER_WHEEL: float = 90.0


static func open_for(player: PlayerController, gate: RehasGate) -> void:
	if player.ui_focus != null:
		return
	var dial := CombinationDial.new()
	dial._player = player
	dial._gate = gate
	player.get_tree().current_scene.add_child(dial)
	player.ui_focus = dial


func _ready() -> void:
	layer = 5
	_build()
	_refresh()
	EventBus.player_wounded.connect(func(_s: StringName) -> void: _close())
	EventBus.game_lost.connect(func(_c: String) -> void: _close())
	EventBus.game_won.connect(func(_a: StringName, _b: String, _c: String) -> void: _close())


func _input(event: InputEvent) -> void:
	if _player == null:
		return
	var handled: bool = true
	if event.is_action_pressed(&"move_left"):
		_select(_selected - 1)
	elif event.is_action_pressed(&"move_right"):
		_select(_selected + 1)
	elif event.is_action_pressed(&"move_forward"):
		_turn(1)
	elif event.is_action_pressed(&"move_back"):
		_turn(-1)
	elif event.is_action_pressed(&"interact") or event.is_action_pressed(&"use_item"):
		_try()
	elif event.is_action_pressed(&"cancel_action") or event.is_action_pressed(&"ui_cancel"):
		_close()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button: int = (event as InputEventMouseButton).button_index
		if button == MOUSE_BUTTON_WHEEL_UP:
			_turn(1)
		elif button == MOUSE_BUTTON_WHEEL_DOWN:
			_turn(-1)
	elif event is InputEventMouseMotion:
		# Sweeping the mouse sideways moves between wheels.
		# It adds up, so a nudge while turning a wheel does not skip to the next.
		_sweep += (event as InputEventMouseMotion).relative.x
		if absf(_sweep) > SWEEP_PER_WHEEL:
			_select(_selected + (1 if _sweep > 0.0 else -1))
			_sweep = 0.0
	elif event is InputEventKey and (event as InputEventKey).pressed:
		var key: int = (event as InputEventKey).keycode
		if key >= KEY_0 and key <= KEY_9:
			# Typing a number sets the wheel and moves on.
			_digits[_selected] = key - KEY_0
			_click()
			_select(_selected + 1)
		else:
			handled = false
	else:
		handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _select(index: int) -> void:
	_selected = clampi(index, 0, _digits.size() - 1)
	_refresh()


func _turn(step: int) -> void:
	_digits[_selected] = posmod(_digits[_selected] + step, 10)
	_click()
	_refresh()


func _click() -> void:
	SfxSynth.play_ui(self, SfxSynth.click(), -20.0, randf_range(1.6, 2.0))


func _try() -> void:
	if _gate == null:
		_close()
		return
	if _gate.try_combination(_digits, _player):
		_close()
		return
	# The wheels jolt with the rattle.
	var t := create_tween()
	t.tween_property(_row, ^"position:x", _row.position.x + 10.0, 0.04)
	t.tween_property(_row, ^"position:x", _row.position.x - 10.0, 0.06)
	t.tween_property(_row, ^"position:x", _row.position.x, 0.05)


func _close() -> void:
	if _player != null and _player.ui_focus == self:
		_player.ui_focus = null
	_player = null
	queue_free()


func _refresh() -> void:
	for i: int in _wheels.size():
		var digit: int = _digits[i]
		_wheels[i].text = str(digit)
		_above[i].text = str(posmod(digit + 1, 10))
		_below[i].text = str(posmod(digit - 1, 10))
		var on: bool = i == _selected
		_wheels[i].add_theme_color_override("font_color", MenuKit.BONE if on else MenuKit.ASH)
		_marks[i].color = MenuKit.EMBER if on else Color(MenuKit.ASH, 0.25)
	var hints := get_tree().get_first_node_in_group(&"gate_code_hints") as GateCodeHints
	var known: String = ""
	for i: int in _digits.size():
		var found: int = hints.found_digit(i) if hints != null else -1
		known += ("%d" % found if found >= 0 else "_") + ("   " if i < _digits.size() - 1 else "")
	_known.text = "From your notes:   " + known


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.0, 0.0, 0.0, 0.82)
	add_child(scrim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	add_child(box)
	var title := MenuKit.label("SIDE LOCK", MenuKit.SIZE_SMALL, MenuKit.ASH, MenuKit.caps_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 16)
	box.add_child(_row)
	for i: int in 4:
		var wheel := VBoxContainer.new()
		wheel.custom_minimum_size = Vector2(WHEEL_WIDTH, 0.0)
		wheel.add_theme_constant_override("separation", 0)
		_row.add_child(wheel)
		var above := MenuKit.label("", MenuKit.SIZE_LEAD, Color(MenuKit.ASH, 0.45))
		above.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wheel.add_child(above)
		var digit := MenuKit.label("0", DIGIT_SIZE, MenuKit.BONE)
		digit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wheel.add_child(digit)
		var below := MenuKit.label("", MenuKit.SIZE_LEAD, Color(MenuKit.ASH, 0.45))
		below.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wheel.add_child(below)
		var mark := ColorRect.new()
		mark.custom_minimum_size = Vector2(WHEEL_WIDTH * 0.5, 2.0)
		mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wheel.add_child(mark)
		_wheels.append(digit)
		_above.append(above)
		_below.append(below)
		_marks.append(mark)
	_known = MenuKit.label("", MenuKit.SIZE_BODY, MenuKit.ASH, MenuKit.italic_font())
	_known.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_known)
	var keys := MenuKit.label("A / D  wheel        W / S  turn        0-9  set        E  try        ESC  step back",
		MenuKit.SIZE_SMALL, MenuKit.ASH, MenuKit.caps_font())
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(keys)
