class_name StoryStyle
extends RefCounted
## Shared look for the story UI, matching the battle HUD (dark panels, blue edges).

const BG := Color(0.035, 0.045, 0.06, 0.94)
const EDGE := Color(0.4, 0.62, 0.82, 0.85)
const TEXT := Color(0.86, 0.9, 0.95)
const DIM := Color(0.6, 0.68, 0.78)
const GOLD := Color(1.0, 0.82, 0.4)
const BLUE := Color(0.45, 0.72, 1.0)
const RED := Color(1.0, 0.42, 0.36)
const GREEN := Color(0.5, 0.9, 0.6)


static func panel(edge: Color = EDGE, bg: Color = BG, top: int = 3, radius: int = 4, margin: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = edge
	sb.set_border_width_all(1)
	sb.border_width_top = top
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


## A label; give `wrap` (a width in pixels) for text that should wrap. Wrapping labels with
## no width blow up container heights, so they only wrap when asked.
static func label(text: String, size: int = 16, color: Color = TEXT, wrap: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", StorySettings.size(size))
	l.add_theme_color_override("font_color", color)
	if wrap > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = wrap
	return l


## A button; `wrap` = long text wraps (only inside a container that gives it a width).
static func button(text: String, size: int = 16, wrap: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if wrap:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", StorySettings.size(size))
	b.add_theme_stylebox_override("normal", panel(Color(0.3, 0.45, 0.6, 0.6), Color(0.06, 0.08, 0.11, 0.95), 1, 3, 8))
	b.add_theme_stylebox_override("hover", panel(Color(0.55, 0.78, 1.0), Color(0.09, 0.14, 0.2, 0.98), 1, 3, 8))
	b.add_theme_stylebox_override("pressed", panel(GOLD, Color(0.14, 0.16, 0.12, 0.98), 1, 3, 8))
	b.add_theme_stylebox_override("disabled", panel(Color(0.25, 0.28, 0.32, 0.5), Color(0.05, 0.05, 0.06, 0.8), 1, 3, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.48, 0.52))
	return b
