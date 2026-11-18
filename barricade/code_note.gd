class_name CodeNote
extends StaticBody3D
## Something written down with one digit of the gate's side-lock code: a
## typed memo or a sticky note lying on a desk, or a scrawl on a classroom
## board. Readable in the world (when lit) and, on "Read", shown full size
## on the HUD and copied into the phone's Notes.

enum Style { MEMO, STICKY, BOARD }

const LAYER_INTERACT: int = 2
const ORDINALS: Array[String] = ["1st", "2nd", "3rd", "4th"]

var style: Style = Style.STICKY
## Place in the code (0..3) and the digit there.
var index: int = 0
var digit: int = 0
var _read: bool = false


static func create(note_style: Style, code_index: int, code_digit: int) -> CodeNote:
	var note := CodeNote.new()
	note.style = note_style
	note.index = code_index
	note.digit = code_digit
	note.name = "Code Note %d" % (code_index + 1)
	note.collision_layer = LAYER_INTERACT
	note.collision_mask = 0
	return note


func _ready() -> void:
	add_to_group(&"code_notes")
	match style:
		Style.MEMO:
			_paper(Vector2(0.21, 0.297), Color(0.86, 0.85, 0.8), MenuKit.typed_font(), 30, Color(0.12, 0.12, 0.14), 0.00055)
		Style.STICKY:
			_paper(Vector2(0.12, 0.12), Color(0.93, 0.83, 0.36), MenuKit.hand_font(), 34, Color(0.08, 0.13, 0.42), 0.0005)
		Style.BOARD:
			_board()


## The code with only this note's digit filled in: "_ _ 7 _".
func pattern() -> String:
	var parts: PackedStringArray = []
	for i: int in 4:
		parts.append(str(digit) if i == index else "_")
	return " ".join(parts)


## What it says, short enough to fit where it is written.
func world_text() -> String:
	match style:
		Style.MEMO:
			return "MEMO - SECURITY\n\nLobby gate, side lock:\nnew combination.\nDO NOT write it down.\n\n%s digit: %d\n\n- Admin" % [ORDINALS[index], digit]
		Style.STICKY:
			return "gate side lock\n%s no. = %d\ndon't forget AGAIN" % [ORDINALS[index], digit]
	return "SIDE GATE LOCK??\n%s\n- sir R." % pattern()


func get_interactions(_player: PlayerController) -> Array[Dictionary]:
	var what: String = "the writing on the board" if style == Style.BOARD else "the note"
	return [{"id": &"read", "label": "Read %s" % what}]


func interact(_player: PlayerController, _action_id: StringName) -> void:
	var font_style: StringName = &"typed" if style == Style.MEMO else &"hand"
	EventBus.note_read.emit(world_text(), font_style)
	if not _read:
		_read = true
		EventBus.gate_code_hint_found.emit(index, digit)


## A sheet lying flat on a surface, the writing on top of it.
func _paper(size: Vector2, paper: Color, font: Font, font_size: int, ink: Color, pixel: float) -> void:
	var sheet := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = paper
	material.roughness = 0.95
	quad.material = material
	sheet.mesh = quad
	sheet.position.y = 0.002
	add_child(sheet)
	var text := _label(font, font_size, ink, pixel)
	text.width = (size.x * 0.88) / pixel
	text.rotation.x = -PI * 0.5
	text.position.y = 0.004
	add_child(text)
	_collider(Vector3(maxf(size.x, 0.18), 0.05, maxf(size.y, 0.18)), Vector3(0.0, 0.025, 0.0))


## Marker on the board, as if a teacher wrote it there.
func _board() -> void:
	var text := _label(MenuKit.hand_font(), 96, Color(0.93, 0.93, 0.9), 0.0012)
	text.width = 900.0
	add_child(text)
	_collider(Vector3(1.0, 0.5, 0.06), Vector3.ZERO)


func _label(font: Font, font_size: int, ink: Color, pixel: float) -> Label3D:
	var text := Label3D.new()
	text.text = world_text()
	text.font = font
	text.font_size = font_size
	text.modulate = ink
	text.outline_size = 0
	text.pixel_size = pixel
	text.shaded = true
	text.double_sided = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return text


func _collider(size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = at
	add_child(collider)
