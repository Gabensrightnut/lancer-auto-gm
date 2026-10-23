extends Control
## Settings: display (UI scale, text size, action bar size, colorblind mode), graphics preset,
## story text (StorySettings: size, skip lines already read),
## gameplay pacing (animation speed, pop-up time), key bindings and house rules (saved and
## applied the moment they flip). Saved to user://settings.cfg.

var s: GameSettings
var waiting_for_key := ""
var keys_box: VBoxContainer
var saved_label: Label


func _ready() -> void:
	s = MenuSession.settings()
	var col := MenuTheme.screen(self, "Settings", "Changes apply when you press Save.", _back)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 20)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left)
	var display := MenuTheme.panel("Display", MenuTheme.ACCENT, "reticle")
	var d := MenuTheme.body(display)
	d.add_child(_slider("UI scale", s.ui_scale, 0.75, 1.5, func(v: float) -> void: s.ui_scale = v, "Makes every menu and the HUD bigger or smaller."))
	d.add_child(_slider("Text size", s.text_size, 0.8, 1.5, func(v: float) -> void: s.text_size = v, "Text only, on top of the UI scale."))
	d.add_child(_slider("Action bar size", s.action_bar_scale, 0.75, 1.5, func(v: float) -> void: s.action_bar_scale = v, "The battle's action bar at the bottom of the screen."))
	d.add_child(_choice("Colorblind mode", GameSettings.COLORBLIND, s.colorblind, func(v: String) -> void: s.colorblind = v,
		{"off": "Off", "deuteranopia": "Deuteranopia (red-green)", "protanopia": "Protanopia (red-green)", "tritanopia": "Tritanopia (blue-yellow)"}))
	d.add_child(_roll_sample())
	left.add_child(display)
	var gfx := MenuTheme.panel("Graphics", MenuTheme.maker_color("SSC"), "eclipse")
	var gb := MenuTheme.body(gfx)
	gb.add_child(_choice("Quality preset", GameSettings.GRAPHICS, s.graphics, func(v: String) -> void: s.graphics = v,
		{"low": "Low (older PCs)", "medium": "Medium (laptops, built-in graphics)", "high": "High (full look)"}))
	gb.add_child(MenuTheme.label("Medium and Low turn off some lighting effects and thin out grass, trees and particles; Low also renders at 75%% and sharpens it back up. Takes effect on the next battlefield. Suggested for this PC: %s." % GameSettings.default_graphics().capitalize(), 15, MenuTheme.MUTED, true))
	left.add_child(gfx)
	var play := MenuTheme.panel("Pacing", MenuTheme.maker_color("HORUS"), "activate")
	var pb := MenuTheme.body(play)
	pb.add_child(_choice("Animation speed", GameSettings.ANIMATION, s.animation_speed, func(v: String) -> void: s.animation_speed = v,
		{"cinematic": "Cinematic", "normal": "Normal", "fast": "Fast"}))
	pb.add_child(_slider("Roll and damage pop-ups stay up", s.popup_duration, 0.5, 2.0, func(v: float) -> void: s.popup_duration = v, "×1 is normal; ×2 gives you twice as long to read them."))
	var auto := CheckButton.new()
	auto.text = "AI squadmates take their turns on their own (solo and hot-seat)"
	auto.tooltip_text = "Once only AI squadmates are left to act, they go by themselves, best pick first. You can still send one earlier with \"I'll go\". Online games start with this off."
	auto.button_pressed = s.ai_squad_auto
	auto.toggled.connect(func(on: bool) -> void: s.ai_squad_auto = on)
	pb.add_child(auto)
	pb.add_child(_slider("Split vote: seconds before the fight", s.split_countdown, 15.0, 30.0, func(v: float) -> void: s.split_countdown = roundf(v),
		"When a squad vote splits, the two sides fight it out after this countdown (host)."))
	left.add_child(play)
	# Story text (StorySettings: kept on this computer, applied right away).
	var story_panel := MenuTheme.panel("Story text", MenuTheme.maker_color("SSC").lightened(0.2), "compendium")
	var sb := MenuTheme.body(story_panel)
	sb.add_child(_slider("Story text size", StorySettings.text_scale(), 0.8, 1.6, func(v: float) -> void: StorySettings.set_text_scale(v),
		"Conversations, the hub and other story text. Changes the next time story text appears."))
	var skip := CheckButton.new()
	skip.text = "Skip lines I've already read (they go by on their own)"
	skip.button_pressed = StorySettings.skip_seen()
	skip.toggled.connect(func(on: bool) -> void: StorySettings.set_skip_seen(on))
	sb.add_child(skip)
	sb.add_child(_slider("Mouse look speed (walking, first person)", StorySettings.look_sensitivity(), 0.25, 3.0, func(v: float) -> void: StorySettings.set_look_sensitivity(v),
		"How fast the view turns when you move the mouse while walking around in first person."))
	var inv := CheckButton.new()
	inv.text = "Invert mouse up/down (walking, first person)"
	inv.button_pressed = StorySettings.invert_y()
	inv.toggled.connect(func(on: bool) -> void: StorySettings.set_invert_y(on))
	sb.add_child(inv)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 20)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var keys := MenuTheme.panel("Controls", MenuTheme.maker_color("IPS-N"), "system")
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(keys)
	right.add_child(story_panel)
	var kb := MenuTheme.body(keys)
	kb.add_child(MenuTheme.label("Click a key, then press the new one. A key already in use swaps over.", 15, MenuTheme.MUTED, true))
	var keys_scroll := ScrollContainer.new()
	keys_scroll.custom_minimum_size = Vector2(0, 540)
	keys_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	kb.add_child(keys_scroll)
	keys_box = VBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 4)
	keys_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys_scroll.add_child(keys_box)
	var reset := Button.new()
	reset.text = "Reset keys to defaults"
	reset.pressed.connect(func() -> void:
		for a: String in GameSettings.actions():
			s.keybinds[a] = int(GameSettings.actions()[a][1])
		_refresh_keys())
	kb.add_child(reset)
	_refresh_keys()
	# House rules (HouseRulesPanel): applied the moment a switch flips, not on Save.
	var third := VBoxContainer.new()
	third.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(third)
	var lobby := MenuSession.lobby
	third.add_child(HouseRulesPanel.build(s, MenuSession.campaign, lobby.client if lobby != null and not lobby.is_host else null))

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 14)
	saved_label = MenuTheme.label("", 16, MenuTheme.GOOD)
	bottom.add_child(saved_label)
	var save := Button.new()
	save.text = "SAVE"
	save.custom_minimum_size = Vector2(220, 56)
	save.add_theme_font_override("font", MenuTheme.bold_font())
	save.add_theme_font_size_override("font_size", 22)
	save.pressed.connect(func() -> void:
		s.save()
		s.apply(get_tree())
		saved_label.text = "Saved.")
	bottom.add_child(save)
	col.add_child(bottom)


func _refresh_keys() -> void:
	for c in keys_box.get_children():
		c.queue_free()
	var table := GameSettings.actions()
	var clash := s.conflicts()
	for ctx: Array in [["battle", "IN BATTLE"], ["explore", "EXPLORING"], ["both", "EVERYWHERE"]]:
		var ids := table.keys().filter(func(a: String) -> bool: return GameSettings.context_of(a) == ctx[0])
		if ids.is_empty():
			continue
		keys_box.add_child(MenuTheme.label(ctx[1], 13, MenuTheme.MUTED))
		for a: String in ids:
			_key_row(a, table, clash)


func _key_row(a: String, table: Dictionary, clash: Dictionary) -> void:
	var h := HBoxContainer.new()
	var l := MenuTheme.label(str(table[a][0]), 17, MenuTheme.BAD if clash.has(a) else MenuTheme.TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if clash.has(a):
		l.tooltip_text = "Same key as: %s" % ", ".join(PackedStringArray((clash[a] as Array).map(func(o: String) -> String: return str(table[o][0]))))
	h.add_child(l)
	var b := Button.new()
	b.custom_minimum_size = Vector2(200, 34)
	b.text = "Press a key…" if waiting_for_key == a else GameSettings.key_name(int(s.keybinds[a])) + ("  (clash)" if clash.has(a) else "")
	b.pressed.connect(func() -> void:
		waiting_for_key = a
		_refresh_keys())
	h.add_child(b)
	keys_box.add_child(h)


func _unhandled_key_input(event: InputEvent) -> void:
	if waiting_for_key == "" or not event.is_pressed():
		return
	var key := (event as InputEventKey).physical_keycode
	var swapped := s.rebind(waiting_for_key, key)
	saved_label.text = "Swapped with \"%s\"." % GameSettings.actions()[swapped][0] if swapped != "" else ""
	waiting_for_key = ""
	get_viewport().set_input_as_handled()
	_refresh_keys()


func _slider(title: String, value: float, lo: float, hi: float, on_change: Callable, hint: String) -> Control:
	var v := VBoxContainer.new()
	var h := HBoxContainer.new()
	var l := MenuTheme.label(title.to_upper(), 14, MenuTheme.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var val := MenuTheme.label("×%.2f" % value, 16)
	h.add_child(val)
	v.add_child(h)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = value
	sl.custom_minimum_size = Vector2(0, 24)
	sl.value_changed.connect(func(x: float) -> void:
		val.text = "×%.2f" % x
		on_change.call(x))
	v.add_child(sl)
	v.add_child(MenuTheme.label(hint, 14, MenuTheme.MUTED, true))
	return v


func _choice(title: String, values: Array, current: String, on_change: Callable, labels: Dictionary) -> Control:
	var v := VBoxContainer.new()
	v.add_child(MenuTheme.label(title.to_upper(), 14, MenuTheme.MUTED))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for x: String in values:
		var b := Button.new()
		b.text = labels.get(x, x)
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = x == current
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func() -> void: on_change.call(x))
		h.add_child(b)
	v.add_child(h)
	return v


## Shows how Accuracy and Difficulty look: they differ by symbol and shape, not only color.
func _roll_sample() -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.add_child(MenuTheme.label("Rolls show Accuracy and Difficulty as", 15, MenuTheme.MUTED))
	h.add_child(MenuTheme.icon("accuracy", 26, Color("3b8ee8")))
	h.add_child(MenuTheme.label("+1 Accuracy", 16, Color("8ec0ff")))
	h.add_child(MenuTheme.icon("difficulty", 26, Color("e5484d")))
	h.add_child(MenuTheme.label("−1 Difficulty", 16, Color("ff9a9e")))
	return h


func _back() -> void:
	MenuSession.go(self, MenuSession.back_to if MenuSession.back_to in MenuSession.SCREENS else "main")
