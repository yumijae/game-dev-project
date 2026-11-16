class_name MenuKit
extends RefCounted
## Shared look for the menus: the HUD's quiet serif in bone white, with
## dried-blood red for whatever is selected.

const BONE: Color = Color(0.84, 0.81, 0.74)
const ASH: Color = Color(0.56, 0.55, 0.52)
const BLOOD: Color = Color(0.6, 0.09, 0.08)
const EMBER: Color = Color(0.86, 0.22, 0.16)
const SERIF_FONTS: Array[String] = ["Georgia", "Palatino Linotype", "Book Antiqua", "Times New Roman", "serif"]

static var _body: Font = null
static var _italic: Font = null
static var _caps: Font = null


static func body_font() -> Font:
	if _body == null:
		var serif := SystemFont.new()
		serif.font_names = PackedStringArray(SERIF_FONTS)
		_body = serif
	return _body


static func italic_font() -> Font:
	if _italic == null:
		var italic := SystemFont.new()
		italic.font_names = PackedStringArray(SERIF_FONTS)
		italic.font_italic = true
		_italic = italic
	return _italic


## Small headings and buttons: the same face, set wide.
static func caps_font() -> Font:
	if _caps == null:
		var caps := FontVariation.new()
		caps.base_font = body_font()
		caps.spacing_glyph = 3
		_caps = caps
	return _caps


static func label(text: String, font_size: int, color: Color = BONE, font: Font = null) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font", font if font != null else body_font())
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	return item


## A text-only button: ash at rest, bone under the cursor, ember when pressed.
static func button(text: String, font_size: int = 20) -> Button:
	var item := Button.new()
	item.text = text
	item.flat = true
	item.focus_mode = Control.FOCUS_ALL
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.add_theme_font_override("font", caps_font())
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", ASH)
	item.add_theme_color_override("font_hover_color", BONE)
	item.add_theme_color_override("font_focus_color", BONE)
	item.add_theme_color_override("font_pressed_color", EMBER)
	item.add_theme_color_override("font_hover_pressed_color", EMBER)
	item.add_theme_color_override("font_disabled_color", Color(ASH, 0.35))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxEmpty.new()
		box.set_content_margin_all(6.0)
		item.add_theme_stylebox_override(state, box)
	return item


static func rule(width: float, color: Color = Color(BLOOD, 0.9)) -> ColorRect:
	var line := ColorRect.new()
	line.color = color
	line.custom_minimum_size = Vector2(width, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Near-black sheet of paper behind a block of menu content.
static func paper(margin: float = 30.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.025, 0.022, 0.022, 0.96)
	box.border_color = Color(BONE, 0.2)
	box.set_border_width_all(1)
	box.set_content_margin_all(margin)
	return box
