class_name CodexPanel
extends PanelContainer
## The searchable rules reference (Codex): type to search every rule term, status, action,
## tag, frame, manufacturer, trigger, background, downtime action, reserve, pilot gear and
## talent, or browse by category. Text is Massif's lancer-data; "This game" entries explain
## our own story features.

var _search: LineEdit
var _cats: OptionButton
var _list: VBoxContainer
var _title: Label
var _source: Label
var _text: RichTextLabel


func _init() -> void:
	add_theme_stylebox_override("panel", StoryStyle.panel())
	custom_minimum_size = Vector2(1100, 680)
	visible = false
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	root.add_child(top)
	top.add_child(StoryStyle.label("CODEX", 24, StoryStyle.GOLD))
	_search = LineEdit.new()
	_search.placeholder_text = "Search rules, statuses, frames, gear... (e.g. engaged, overcharge, Everest)"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t: String) -> void: _refresh())
	top.add_child(_search)
	_cats = OptionButton.new()
	_cats.add_item("All")
	for c: String in Codex.categories():
		_cats.add_item(c)
	_cats.item_selected.connect(func(_i: int) -> void: _refresh())
	top.add_child(_cats)
	var close := StoryStyle.button("Close (Esc)", 14)
	close.pressed.connect(func() -> void: visible = false)
	top.add_child(close)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	_title = StoryStyle.label("", 22, StoryStyle.GOLD, 700)
	right.add_child(_title)
	_source = StoryStyle.label("", 13, StoryStyle.DIM)
	right.add_child(_source)
	_text = RichTextLabel.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(720, 560)
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.selection_enabled = true
	right.add_child(_text)


## Opens the codex, optionally at a search (e.g. from a tutorial tip or a "?" button).
func open(query: String = "") -> void:
	visible = true
	_search.text = query
	_refresh()
	_search.grab_focus()


func _refresh() -> void:
	for ch in _list.get_children():
		ch.queue_free()
	var cat := "" if _cats.selected <= 0 else _cats.get_item_text(_cats.selected)
	var found := Codex.search(_search.text, cat, 80)
	for e: Dictionary in found:
		var b := StoryStyle.button("%s  [%s]" % [e["title"], e["category"]], 14)
		b.custom_minimum_size.x = 310
		var entry := e
		b.pressed.connect(func() -> void: show_entry(entry))
		_list.add_child(b)
	if not found.is_empty():
		show_entry(found[0])
	else:
		_title.text = "Nothing found"
		_source.text = ""
		_text.text = "Try another word, or pick a category."


func show_entry(e: Dictionary) -> void:
	_title.text = str(e["title"])
	_source.text = "%s  ·  %s" % [e["category"], e["source"]]
	_text.text = str(e["text"])


func _process(_delta: float) -> void:
	if visible:
		var vp := get_viewport_rect().size
		position = ((vp - size) / 2.0).max(Vector2(8, 8))
