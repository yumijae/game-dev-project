class_name MenuKit
extends RefCounted
## Shared look for the menus and the HUD: one bundled serif in bone white,
## ash for secondary text, and dried-blood red as the only accent - for
## whatever is selected or can kill you.

const BONE: Color = Color(0.84, 0.81, 0.74)
const ASH: Color = Color(0.56, 0.55, 0.52)
const BLOOD: Color = Color(0.6, 0.09, 0.08)
const EMBER: Color = Color(0.86, 0.22, 0.16)
## Bundled typefaces (res://fonts, SIL OFL / Apache 2.0), so the game looks
## the same on every machine instead of falling back to whatever serif the
## PC has. One family for all UI text - Crimson Pro - at a few fixed weights;
## two more only for things written in the world.
const SERIF_PATH: String = "res://fonts/CrimsonPro.ttf"
const SERIF_ITALIC_PATH: String = "res://fonts/CrimsonPro-Italic.ttf"
const HAND_PATH: String = "res://fonts/Caveat.ttf"
const TYPED_PATH: String = "res://fonts/SpecialElite.ttf"

## The type scale: every UI size comes from here (px at 1080p).
const SIZE_SMALL: int = 14
const SIZE_BODY: int = 18
const SIZE_LEAD: int = 22
const SIZE_TITLE: int = 40

static var _body: Font = null
static var _italic: Font = null
static var _caps: Font = null
static var _hand: Font = null
static var _typed: Font = null


static func _variable(path: String, weight: int) -> Font:
	var face := FontVariation.new()
	face.base_font = load(path) as FontFile
	face.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return face


static func body_font() -> Font:
	if _body == null:
		_body = _variable(SERIF_PATH, 450)
	return _body


static func italic_font() -> Font:
	if _italic == null:
		_italic = _variable(SERIF_ITALIC_PATH, 450)
	return _italic


## Small headings and buttons: semibold, lightly tracked (wide tracking at
## small sizes made the stat names unreadable).
static func caps_font() -> Font:
	if _caps == null:
		var caps := _variable(SERIF_PATH, 600) as FontVariation
		caps.spacing_glyph = 1
		_caps = caps
	return _caps


## Handwriting: sticky notes, marker on a whiteboard.
static func hand_font() -> Font:
	if _hand == null:
		_hand = _variable(HAND_PATH, 500)
	return _hand


## Typewritten / printed: memos, labels, notices.
static func typed_font() -> Font:
	if _typed == null:
		_typed = load(TYPED_PATH) as FontFile
	return _typed


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
		# Vertical room for the hit area; none at the sides, so the label
		# lines up with the text above it.
		box.content_margin_top = 6.0
		box.content_margin_bottom = 6.0
		box.content_margin_left = 0.0
		box.content_margin_right = 0.0
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
