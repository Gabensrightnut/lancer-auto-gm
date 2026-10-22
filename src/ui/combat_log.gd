class_name CombatLog
extends PanelContainer
## Scrolling combat log: one plain-language line per event, newest at the bottom.

var _text: RichTextLabel


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.72)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_following = true
	_text.custom_minimum_size = Vector2(460, 170)
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 15)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_text)
	visible = false  # shown once there's something to read


func add_line(bbcode: String) -> void:
	_text.append_text(bbcode + "\n")


func clear_log() -> void:
	_text.clear()
	visible = false
