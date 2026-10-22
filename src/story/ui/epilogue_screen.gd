class_name EpilogueScreen
extends Control
## The end of a campaign: how it ended (triumph, bittersweet or defeat), what the squad did,
## who fell, and one epilogue card per pilot with their portrait. Then: a new campaign with
## the same pilots, or back to the menu.

signal sequel_requested
signal menu_requested

var _box: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.012, 0.02, 0.92)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 60
	scroll.offset_right = -60
	scroll.offset_top = 30
	scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 14)
	scroll.add_child(_box)


func show_ending(ending: Dictionary) -> void:
	for ch in _box.get_children():
		ch.queue_free()
	var kind := str(ending.get("kind", ""))
	var col: Color = {"triumph": StoryStyle.GOLD, "bittersweet": StoryStyle.BLUE, "defeat": StoryStyle.RED}.get(kind, StoryStyle.TEXT)
	var head := StoryStyle.label("%s  ·  %s" % [str(ending.get("name", "")).to_upper(), str(ending.get("label", "")).to_upper()], 30, col)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(head)
	var title := StoryStyle.label(str(ending.get("title", "")), 20, StoryStyle.TEXT, 1100)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var sm: Dictionary = ending.get("summary", {})
	var fallen: Array = sm.get("fallen", [])
	var n := int(sm.get("missions", 0))
	var won := int(sm.get("arcs_won", 0))
	var line := "%d mission%s  ·  %d situation%s won, %d lost" % [n, "" if n == 1 else "s", won, "" if won == 1 else "s", int(sm.get("arcs_lost", 0))]
	if not fallen.is_empty():
		line += "  ·  in memory of " + ", ".join(PackedStringArray(fallen))
	var sub := StoryStyle.label(line, 16, StoryStyle.DIM, 1100)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	_box.add_child(grid)
	for ep: Dictionary in ending.get("epilogues", []):
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", StoryStyle.panel(col if bool(ep.get("alive", true)) else Color(0.4, 0.4, 0.45)))
		card.custom_minimum_size.x = 640
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var face := PortraitArt.new()
		face.custom_minimum_size = Vector2(120, 150)
		var f: Dictionary = ep.get("face", {})
		face.set_look(f.get("portrait", {}), str(f.get("expression", "neutral")))
		face.lit = bool(ep.get("alive", true))
		row.add_child(face)
		var info := VBoxContainer.new()
		row.add_child(info)
		info.add_child(StoryStyle.label("%s%s" % [ep.get("callsign", ""), "" if bool(ep.get("alive", true)) else "  (fallen)"], 20, col if bool(ep.get("alive", true)) else StoryStyle.DIM))
		info.add_child(StoryStyle.label("%s  ·  LL%d" % [ep.get("name", ""), int(ep.get("ll", 0))], 13, StoryStyle.DIM))
		info.add_child(StoryStyle.label(str(ep.get("text", "")), 15, StoryStyle.TEXT, 460))
		grid.add_child(card)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	_box.add_child(buttons)
	var again := StoryStyle.button("New campaign with the same pilots", 17)
	again.pressed.connect(func() -> void: sequel_requested.emit())
	again.disabled = (ending.get("epilogues", []) as Array).all(func(e: Dictionary) -> bool: return not bool(e.get("alive", false)))
	buttons.add_child(again)
	var menu := StoryStyle.button("Main menu", 17)
	menu.pressed.connect(func() -> void: menu_requested.emit())
	buttons.add_child(menu)
	visible = true
