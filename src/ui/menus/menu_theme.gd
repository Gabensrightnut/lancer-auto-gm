class_name MenuTheme
extends RefCounted
## The look of the menus: dark panels, strong condensed type, manufacturer accent colors (from
## lancer-data manufacturers.json) and the official Lancer icons (assets/icons/lancer/).
## Fonts: the player's own system fonts (Bahnschrift on Windows); none are bundled.

const BG := Color("0c0e12")
const PANEL := Color("15181e")
const PANEL_2 := Color("1d2129")
const LINE := Color("2d323d")
const TEXT := Color("e9e7e3")
const MUTED := Color("8e95a1")
const GOOD := Color("43c47f")
const WARN := Color("e3a43a")
const BAD := Color("ec4d55")
## GMS red: the default accent.
const ACCENT := Color("db1a2d")
const ICON_DIR := "res://assets/icons/lancer/"

const MANUFACTURER_ICONS := {"GMS": "gms", "IPS-N": "ipsn", "SSC": "ssc", "HORUS": "horus", "HA": "ha"}

static var _theme: Theme
static var _icons: Dictionary = {}
static var _maker_colors: Dictionary = {}


## The theme every menu screen uses.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "Noto Sans", "Arial"])
	t.default_font = body
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_stylebox("normal", "Button", box(PANEL_2, LINE, 1, 3))
	t.set_stylebox("hover", "Button", box(PANEL_2.lightened(0.08), ACCENT, 1, 3))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.35), ACCENT, 1, 3))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), ACCENT, 2, 3))
	t.set_stylebox("disabled", "Button", box(PANEL.darkened(0.2), LINE.darkened(0.3), 1, 3))
	for type in ["OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(PANEL_2, LINE, 1, 3))
		t.set_stylebox("hover", type, box(PANEL_2.lightened(0.08), ACCENT, 1, 3))
		t.set_stylebox("pressed", type, box(PANEL_2, ACCENT, 1, 3))
		t.set_stylebox("focus", type, box(Color(0, 0, 0, 0), ACCENT, 2, 3))
		t.set_color("font_color", type, TEXT)
	t.set_stylebox("normal", "LineEdit", box(BG, LINE, 1, 3))
	t.set_stylebox("focus", "LineEdit", box(BG, ACCENT, 2, 3))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE, 1, 0))
	t.set_stylebox("panel", "PopupPanel", box(PANEL, ACCENT, 1, 0))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, LINE, 1, 0))
	t.set_stylebox("hover", "PopupMenu", box(ACCENT.darkened(0.3), ACCENT, 0, 0))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(Color("0a0b0e"), ACCENT, 1, 0))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "ItemList", box(BG, LINE, 1, 0))
	t.set_stylebox("focus", "ItemList", box(Color(0, 0, 0, 0), LINE, 1, 0))
	t.set_stylebox("selected", "ItemList", box(ACCENT.darkened(0.45), ACCENT, 1, 0))
	t.set_stylebox("selected_focus", "ItemList", box(ACCENT.darkened(0.4), ACCENT, 1, 0))
	t.set_stylebox("hovered", "ItemList", box(PANEL_2, Color(0, 0, 0, 0), 0, 0))
	t.set_color("font_color", "ItemList", TEXT)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_constant("v_separation", "ItemList", 6)
	var slider := box(LINE, Color(0, 0, 0, 0), 0, 2)
	slider.content_margin_top = 3
	slider.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", slider)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT.lightened(0.2), Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL, ACCENT, 0, 0, 3))
	t.set_stylebox("tab_unselected", "TabContainer", box(BG, LINE, 0, 0))
	t.set_stylebox("tab_hovered", "TabContainer", box(PANEL_2, LINE, 0, 0))
	t.set_stylebox("panel", "TabContainer", box(PANEL, LINE, 1, 0))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "pressed", "hover", "hover_pressed", "focus", "disabled"]:
			var cb := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3)
			if state in ["hover", "hover_pressed"]:
				cb.bg_color = PANEL_2
			t.set_stylebox(state, type, cb)
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_pressed_color", "CheckBox", Color.WHITE)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_color", "CheckButton", TEXT)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("separator", "HSeparator", line_box())
	_theme = t
	return t


## A flat box. `top_accent` > 0 draws a colored bar on top (selected tabs, headers).
static func box(fill: Color, border: Color, border_w: int, radius: int, top_accent: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_w)
	if top_accent > 0:
		s.border_color = ACCENT
		s.border_width_top = top_accent
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s


static func line_box() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = LINE
	l.thickness = 1
	return l


## Full-screen dark background with the subtle hex pattern feel.
static func backdrop(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	var mark := icon("nested-hexagons", 900, Color(1, 1, 1, 0.025))
	mark.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	mark.position = Vector2(1150, -60)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(mark)


## A panel with a header strip: returns the panel; add content to panel.get_meta("body").
static func panel(title: String, accent: Color = ACCENT, icon_name: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(PANEL, LINE, 1, 0))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	if title != "":
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		var bar := ColorRect.new()
		bar.color = accent
		bar.custom_minimum_size = Vector2(4, 26)
		head.add_child(bar)
		if icon_name != "":
			head.add_child(icon(icon_name, 26, accent))
		head.add_child(heading(title, 20))
		v.add_child(head)
	p.set_meta("body", v)
	return p


static func body(p: Control) -> VBoxContainer:
	return p.get_meta("body")


static func heading(text: String, size: int = 22, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", bold_font())
	return l


static func label(text: String, size: int = 18, color: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func bold_font() -> Font:
	var f := FontVariation.new()
	f.base_font = theme().default_font
	f.variation_embolden = 0.6
	f.spacing_glyph = 1
	return f


## A big menu button with an icon on the left.
static func big_button(text: String, icon_name: String, accent: Color = ACCENT) -> Button:
	var b := Button.new()
	b.text = "   " + text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(380, 62)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_font_override("font", bold_font())
	var normal := box(PANEL, LINE, 1, 0)
	normal.border_width_left = 4
	normal.border_color = LINE
	var hover := box(PANEL_2, accent, 1, 0)
	hover.border_width_left = 8
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_stylebox_override("pressed", box(accent.darkened(0.4), accent, 2, 0))
	if icon_name != "":
		b.icon = icon_texture(icon_name, 34, TEXT)
		b.expand_icon = false
	return b


## A small colored tag, e.g. "AI", "READY", "LL 2".
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var s := box(color.darkened(0.6), color, 1, 2)
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	s.content_margin_left = 8
	s.content_margin_right = 8
	p.add_theme_stylebox_override("panel", s)
	var l := label(text.to_upper(), 14, color.lightened(0.3))
	l.add_theme_font_override("font", bold_font())
	p.add_child(l)
	return p


## An official icon as a TextureRect in `color`.
static func icon(name: String, size: int, color: Color = TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon_texture(name, size, color)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


## The icon SVG rasterized at `size` pixels in `color` (the SVGs have no fill of their own, so
## the color is written into the shapes before rasterizing: crisp at any size).
static func icon_texture(name: String, size: int, color: Color = Color.WHITE) -> Texture2D:
	var key := "%s@%d@%s" % [name, size, color.to_html()]
	if _icons.has(key):
		return _icons[key]
	var path := ICON_DIR + name + ".svg"
	var tex: Texture2D = null
	if FileAccess.file_exists(path):
		var fill := "fill=\"#%s\" fill-opacity=\"%.3f\" " % [color.to_html(false), color.a]
		var svg := FileAccess.get_file_as_string(path)
		for tag in ["<path", "<polygon", "<circle", "<rect", "<ellipse", "<polyline"]:
			svg = svg.replace(tag + " ", tag + " " + fill).replace(tag + "
", tag + " " + fill + "
")
		# The icons only have a 24x24 viewBox; without a size they rasterize huge.
		if not "width=" in svg.substr(0, svg.find(">")):
			svg = svg.replace("<svg", "<svg width=\"24\" height=\"24\"")
		var img := Image.new()
		if img.load_svg_from_string(svg, size / 24.0) == OK:
			if img.get_width() != size:
				img.resize(size, int(size * float(img.get_height()) / img.get_width()), Image.INTERPOLATE_LANCZOS)
			tex = ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


## A manufacturer's accent color ("GMS", "IPS-N", ...) from lancer-data.
static func maker_color(source: String) -> Color:
	if _maker_colors.is_empty():
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string("res://data/lancer-data/manufacturers.json")) == OK:
			for m: Dictionary in json.data:
				_maker_colors[str(m.get("id", ""))] = Color(str(m.get("dark", "#db1a2d")))
	return _maker_colors.get(source, ACCENT)


static func maker_icon(source: String) -> String:
	return MANUFACTURER_ICONS.get(source, "manufacturer")


## Standard screen frame: backdrop + title bar with a back button. Returns the content area.
static func screen(root: Control, title: String, subtitle: String = "", on_back: Callable = Callable()) -> VBoxContainer:
	root.theme = theme()
	backdrop(root)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36 if side in ["left", "right"] else 28)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	margin.add_child(col)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	if on_back.is_valid():
		var back := Button.new()
		back.text = "‹  BACK"
		back.custom_minimum_size = Vector2(120, 44)
		back.pressed.connect(on_back)
		bar.add_child(back)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(heading(title, 34))
	if subtitle != "":
		titles.add_child(label(subtitle, 16, MUTED))
	bar.add_child(titles)
	col.add_child(bar)
	var rule := ColorRect.new()
	rule.color = ACCENT
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)
	return col
