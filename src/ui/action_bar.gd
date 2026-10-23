class_name ActionBar
extends Control
## The battle hotbar at the bottom of the screen: nine group buttons laid out like a numpad
## (the user's layout), the resource cluster on the left and End Turn on the right:
##   1 Quick attacks     2 Full attacks     3 Ability/system attacks
##   4 Quick actions     5 Full actions     6 Tech (quick and full tech, invades)
##   7 Movement          8 Reactions        9 Free actions and protocols
## Clicking a group (or its keypad key: Kp7-8-9 / Kp4-5-6 / Kp1-2-3 like the grid; Kp0 is End
## Turn) opens that group's sub-bar above the buttons: a grid of its abilities, where the
## number row picks a slot (1-0 the first row, Shift the second, Ctrl the third). Esc or a click
## elsewhere closes it; opening another group swaps it. With no group open, 1-0 go through
## every filled slot in group order. Every action sorts itself by the book's action type
## (cost/activation and kind from the engine). Slots are about 60 px at 1080p, scaled by the
## screen height, Settings' UI scale and action bar size. Unlocked (the padlock), abilities drag
## between slots or onto a group button, and each group's rows and columns grow or shrink with
## + and -; right-click a slot for auto (the gold bead). The layout is saved per pilot/mech
## (user://action_layouts/) with a reset. Format in src/render/FORMATS.md.

signal action_pressed(action: Dictionary)
signal action_hovered(action: Dictionary, on: bool)
signal end_turn_pressed

const PANELS := 9
const PANEL_NAMES := ["", "Quick attacks", "Full attacks", "System attacks", "Quick actions", "Full actions",
	"Tech", "Movement", "Reactions", "Free & protocols"]
## Slot size as a fraction of the screen height (about 63 px at 1080p).
const SLOT_FRACTION := 0.058
const MAX_ROWS := 4
const MAX_COLS := 8
const LAYOUT_DIR := "user://action_layouts/"
const LAYOUT_VERSION := 2
## Basic actions that attack (they sort into the attack panels by their cost).
const ATTACK_TYPES := ["ram", "grapple", "improvised_attack", "duelist_strike", "hunter_throw", "feint", "trip", "barrage", "skirmish", "throw"]
const MOVE_TYPES := ["boost", "move", "disengage", "jump", "climb_on", "board", "disembark", "mount", "dismount", "stand_up", "teleport", "fly"]

## Extra size factor (screenshots, tests); Settings' sizes are read on top of it.
var bar_scale := 1.0:
	set(v):
		bar_scale = clampf(v, 0.6, 1.6)
		_layout()
var pilot_id := ""
var actions: Array = []
## Kept for callers of the old tabbed bar; panels show everything at once.
var tab := "all"
var resources: ResourceCluster
var card: HoverCard
## Back-compat: the full ResourceHUD can also receive previews.
var resource_hud: ResourceHUD
## Layout: {version, locked, panels: {"1": {rows, cols, slots: [action id or ""]}}, overflow: [ids]}.
var layout: Dictionary = {}

var _root: Panel
var _panels: Array = []  # index 1..9 -> {box: Panel, header: Label, buttons: HBoxContainer, slots: [Control]}
var _lock: Button
var _reset: Button
var _overflow: Button
var _end_turn: Button
var _buttons: Dictionary = {}  # id -> ActionButton
var _settings_scale := 1.0
var _note: Label
var _groups: Array = []  # index 1..9 -> ActionGroupButton
## The group whose sub-bar is open (0 = none).
var open_group := 0
const GROUP_ICONS := ["", "range", "barrage", "system", "activation_quick", "activation_full", "tech_quick", "marker", "reaction", "protocol"]
## Keypad keys for the groups, laid out like the grid (top row Kp7-9).
const KEYPAD := {KEY_KP_7: 1, KEY_KP_8: 2, KEY_KP_9: 3, KEY_KP_4: 4, KEY_KP_5: 5, KEY_KP_6: 6, KEY_KP_1: 7, KEY_KP_2: 8, KEY_KP_3: 9}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var gs := GameSettings.load_settings() if FileAccess.file_exists(GameSettings.FILE) else null
	if gs:
		_settings_scale = clampf(gs.ui_scale * gs.action_bar_scale, 0.5, 2.25)
	_root = Panel.new()
	_root.add_theme_stylebox_override("panel", _box(Color(0.03, 0.04, 0.055, 0.9), Color(0.35, 0.55, 0.75, 0.6)))
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	_panels.append({})
	_groups.append(null)
	for p in range(1, PANELS + 1):
		var gb := ActionGroupButton.new(p, self, PANEL_NAMES[p], GROUP_ICONS[p])
		gb.hotkey = "Kp" + str(KEYPAD.find_key(p) - KEY_KP_0)
		gb.pressed.connect(toggle_group)
		_root.add_child(gb)
		_groups.append(gb)
		# The group's sub-bar: shown above the buttons while the group is open.
		var box := Panel.new()
		box.add_theme_stylebox_override("panel", _box(Color(0.04, 0.055, 0.075, 0.95), Color(0.4, 0.62, 0.85, 0.8), 2))
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.visible = false
		add_child(box)
		box.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
		var header := Label.new()
		header.text = PANEL_NAMES[p]
		header.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		header.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		header.add_theme_constant_override("outline_size", 3)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(header)
		var tools := HBoxContainer.new()
		tools.add_theme_constant_override("separation", 1)
		box.add_child(tools)
		for spec: Array in [["−r", -1, 0], ["+r", 1, 0], ["−c", 0, -1], ["+c", 0, 1]]:
			var b := _small_button(String(spec[0]))
			b.tooltip_text = {"−r": "One row less", "+r": "One row more", "−c": "One column less", "+c": "One column more"}[spec[0]]
			b.pressed.connect(resize_panel.bind(p, int(spec[1]), int(spec[2])))
			tools.add_child(b)
		_panels.append({"box": box, "header": header, "tools": tools, "slots": []})
	_lock = _small_button("🔒")
	_lock.tooltip_text = "Lock the bar: no dragging. Unlock to move actions and resize panels."
	_lock.pressed.connect(func() -> void: set_locked(not is_locked()))
	_root.add_child(_lock)
	_reset = _small_button("Reset")
	_reset.tooltip_text = "Reset to the default order"
	_reset.pressed.connect(reset_layout)
	_root.add_child(_reset)
	_overflow = _small_button("+0")
	_overflow.tooltip_text = "Actions that don't fit in their panels"
	_overflow.pressed.connect(_show_overflow)
	_root.add_child(_overflow)
	resources = ResourceCluster.new()
	add_child(resources)
	resources.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	_end_turn = Button.new()
	_end_turn.text = "END\nTURN"
	_end_turn.focus_mode = Control.FOCUS_NONE
	_end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())
	var eb := _box(Color(0.35, 0.12, 0.08, 0.95), Color(1.0, 0.55, 0.3), 2)
	_end_turn.add_theme_stylebox_override("normal", eb)
	var ebh := eb.duplicate() as StyleBoxFlat
	ebh.bg_color = Color(0.55, 0.2, 0.1, 0.98)
	_end_turn.add_theme_stylebox_override("hover", ebh)
	_end_turn.add_theme_stylebox_override("pressed", ebh)
	add_child(_end_turn)
	_end_turn.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	card = HoverCard.new()
	add_child(card)


static func _box(bg: Color, border: Color, w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(4)
	return sb


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.flat = false
	return b


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


# --- sorting ---------------------------------------------------------------------------

## Which panel (1-9) an action belongs to, from its book action type (cost/activation),
## kind and type.
static func panel_of(a: Dictionary) -> int:
	var cost := String(a.get("cost", "quick")).to_lower()
	var kind := String(a.get("kind", ""))
	var type := String(a.get("type", ""))
	var group := String(a.get("group", ""))
	var text := (String(a.get("text", "")) + " " + String(a.get("name", ""))).to_lower()
	var id := String(a.get("id", ""))
	if kind == "" and (id.begins_with("w:") or id.begins_with("w_") or group == "weapons"):
		kind = "attack"
	if id == "act_barrage":
		kind = "barrage"
	if id == "act_boost":
		kind = "move_boost"
	if id in ["act_lock_on", "act_lockon", "act_scan", "act_bolster", "act_invade", "act_fragment_signal"]:
		kind = "tech"
	if kind == "move_boost" or type in MOVE_TYPES:
		return 7
	if cost == "reaction" or group == "reactions":
		return 8
	if "tech" in cost or kind == "tech" or group == "tech" or String(a.get("icon", "")).begins_with("tech"):
		return 6
	if kind == "attack" or kind == "barrage" or type in ATTACK_TYPES:
		return 2 if cost == "full" else 1
	if group in ["systems", "core"] and (" attack" in text or text.begins_with("attack")):
		return 3
	if cost in ["free", "protocol"]:
		return 9
	if cost == "full":
		return 5
	return 4


# --- actions ---------------------------------------------------------------------------

func set_actions(list: Array, pilot: String = "") -> void:
	actions = list
	if pilot != "":
		pilot_id = pilot
	_load_layout()
	_place_all()
	_rebuild()


## Updates actions in place (e.g. after a turn passes) so lockout sweeps animate.
func update_actions(list: Array) -> void:
	actions = list
	for a: Dictionary in list:
		var b: ActionButton = _buttons.get(a.get("id", ""))
		if b:
			b.set_action(a)


func set_tab(t: String) -> void:
	tab = t


func _action(id: String) -> Dictionary:
	for a: Dictionary in actions:
		if String(a.get("id", "")) == id:
			return a
	return {}


func _panel_data(p: int) -> Dictionary:
	var panels: Dictionary = layout.get("panels", {})
	if not panels.has(str(p)):
		panels[str(p)] = {"rows": 1, "cols": 4, "slots": []}
		layout["panels"] = panels
	var d: Dictionary = panels[str(p)]
	var n := int(d["rows"]) * int(d["cols"])
	var slots: Array = d.get("slots", [])
	while slots.size() < n:
		slots.append("")
	d["slots"] = slots
	return d


## Where an action sits: [panel, index] or [0, -1].
func slot_of(id: String) -> Array:
	for p in range(1, PANELS + 1):
		var i := (_panel_data(p)["slots"] as Array).find(id)
		if i >= 0 and i < int(_panel_data(p)["rows"]) * int(_panel_data(p)["cols"]):
			return [p, i]
	return [0, -1]


## Every action gets a slot: its saved one, else the first free slot in its panel (growing
## the panel's rows, then columns), else the overflow list. Nothing is ever lost.
func _place_all() -> void:
	var overflow: Array = []
	for a: Dictionary in actions:
		var id := String(a.get("id", ""))
		if slot_of(id)[0] != 0:
			continue
		if not _place(id, panel_of(a)):
			overflow.append(id)
	layout["overflow"] = overflow


func _place(id: String, p: int) -> bool:
	var d := _panel_data(p)
	while true:
		var n := int(d["rows"]) * int(d["cols"])
		var slots: Array = d["slots"]
		for i in range(n):
			if String(slots[i]) == "" or _action(String(slots[i])).is_empty() and not _known_id(String(slots[i])):
				slots[i] = id
				return true
		if int(d["cols"]) < 4:
			d["cols"] = int(d["cols"]) + 1
		elif int(d["rows"]) < 2:
			d["rows"] = int(d["rows"]) + 1
		elif int(d["cols"]) < MAX_COLS:
			d["cols"] = int(d["cols"]) + 1
		elif int(d["rows"]) < MAX_ROWS:
			d["rows"] = int(d["rows"]) + 1
		else:
			return false
		_panel_data(p)
	return false


## Ids saved in the layout stay reserved while their action is away (e.g. used up this scene).
func _known_id(id: String) -> bool:
	return id != "" and layout.get("reserved", {}).has(id)


## Moves an action to a panel slot; whatever was there takes its old place.
func move_action(id: String, p: int, i: int) -> void:
	var from := slot_of(id)
	var d := _panel_data(p)
	var slots: Array = d["slots"]
	if i < 0 or i >= slots.size():
		return
	var there := String(slots[i])
	slots[i] = id
	if from[0] != 0:
		(_panel_data(from[0])["slots"] as Array)[from[1]] = there
	elif there != "":
		_place(there, panel_of(_action(there)))
	(layout["overflow"] as Array).erase(id)
	_save_layout()
	_rebuild()


## + / - rows or columns on a panel; actions that no longer fit move to the next free slot.
func resize_panel(p: int, drows: int, dcols: int) -> void:
	var d := _panel_data(p)
	var old_cols := int(d["cols"])
	var rows := clampi(int(d["rows"]) + drows, 1, MAX_ROWS)
	var cols := clampi(old_cols + dcols, 1, MAX_COLS)
	var keep: Array = []
	var dropped: Array = []
	var slots: Array = d["slots"]
	for r in range(int(d["rows"])):
		for c in range(old_cols):
			var id := String(slots[r * old_cols + c]) if r * old_cols + c < slots.size() else ""
			if r < rows and c < cols:
				continue
			if id != "":
				dropped.append(id)
	var fresh: Array = []
	for r in range(rows):
		for c in range(cols):
			fresh.append(String(slots[r * old_cols + c]) if c < old_cols and r * old_cols + c < slots.size() and r < int(d["rows"]) else "")
	d["rows"] = rows
	d["cols"] = cols
	d["slots"] = fresh
	for id: String in dropped:
		var placed := false
		for i in range(fresh.size()):
			if String(fresh[i]) == "":
				fresh[i] = id
				placed = true
				break
		if not placed:
			(layout["overflow"] as Array).append(id)
	_save_layout()
	_rebuild()


## Right-click: auto-use on or off (AutoActions says what may be). One auto reaction per unit:
## turning one on turns the other off.
func toggle_auto(a: Dictionary) -> void:
	var id := String(a.get("id", ""))
	var autos: Dictionary = layout.get("auto", {})
	if bool(autos.get(id, false)):
		autos.erase(id)
		show_note("Auto off: %s" % a.get("name", id))
	else:
		var why := AutoActions.can_auto(a)
		if why != "":
			show_note("%s: %s" % [a.get("name", id), why])
			return
		if AutoActions.is_reaction(a):
			for other: String in autos.keys():
				if AutoActions.is_reaction(_action(other)):
					autos.erase(other)
		autos[id] = true
		show_note("Auto on: %s" % a.get("name", id))
	layout["auto"] = autos
	_save_layout()
	_rebuild()


## A one-line note above the bar that fades (auto toggles, skipped autos).
func show_note(text: String) -> void:
	if _note == null:
		_note = Label.new()
		_note.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
		_note.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_note.add_theme_constant_override("outline_size", 5)
		_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_note)
	_note.text = text
	_note.add_theme_font_size_override("font_size", int(maxf(14.0, slot_size() * 0.3)))
	_note.reset_size()
	_note.position = Vector2(_root.position.x, _root.position.y - _note.size.y - 4)
	_note.modulate.a = 1.0
	if is_inside_tree():
		var tw := _note.create_tween()
		tw.tween_interval(2.5)
		tw.tween_property(_note, "modulate:a", 0.0, 0.6)


func is_locked() -> bool:
	return bool(layout.get("locked", true))


func set_locked(on: bool) -> void:
	layout["locked"] = on
	ActionButton.drag_enabled = not on
	_save_layout()
	_rebuild()


func reset_layout() -> void:
	var locked := is_locked()
	layout = {"version": LAYOUT_VERSION, "locked": locked, "panels": {}, "overflow": [], "auto": layout.get("auto", {})}
	_place_all()
	_save_layout()
	_rebuild()


# --- building -------------------------------------------------------------------------

func _rebuild() -> void:
	_buttons.clear()
	ActionButton.drag_enabled = not is_locked()
	var hot := 0
	for p in range(1, PANELS + 1):
		var info: Dictionary = _panels[p]
		for s: Control in info["slots"]:
			s.queue_free()
		info["slots"] = []
		var d := _panel_data(p)
		var n := int(d["rows"]) * int(d["cols"])
		var any := false
		for i in range(n):
			var id := String(d["slots"][i])
			var a := _action(id)
			var slot: Control
			if a.is_empty():
				slot = ActionSlot.new(p, i, self)
			else:
				var b := ActionButton.new(a)
				b.panel = p
				b.index = i
				b.pressed.connect(func(x: Dictionary) -> void:
					action_pressed.emit(x)
					close_group())
				b.hovered.connect(_hover)
				b.move_requested.connect(move_action)
				b.auto_requested.connect(toggle_auto)
				b.auto = bool((layout.get("auto", {}) as Dictionary).get(id, false))
				_buttons[id] = b
				slot = b
				any = true
			(info["box"] as Panel).add_child(slot)
			(info["slots"] as Array).append(slot)
		info["empty"] = not any
		(info["tools"] as Control).visible = not is_locked()
		# Slot hotkeys by position inside the open sub-bar: 1-0, Shift for row 2, Ctrl for row 3.
		var cols := int(d["cols"])
		for i in range((info["slots"] as Array).size()):
			var sl: Control = info["slots"][i]
			if sl is ActionButton:
				(sl as ActionButton).hotkey = slot_key_label(i / cols, i % cols)
		# The group button: how many, how many usable now, and the cooldown sweep.
		var gb: ActionGroupButton = _groups[p]
		var count := 0
		var usable := 0
		var lock_sum := 0.0
		for i in range(n):
			var a := _action(String(d["slots"][i]))
			if a.is_empty():
				continue
			count += 1
			if not ActionButton.locked(a):
				usable += 1
			lock_sum += ActionButton.lock_fraction(a)
		gb.count = count
		gb.usable = usable
		gb.lock_fraction = lock_sum / maxf(1.0, count)
		gb.open = p == open_group
		gb.queue_redraw()
		(info["box"] as Panel).visible = p == open_group
	_lock.text = "🔒" if is_locked() else "🔓"
	_reset.visible = not is_locked()
	var over: Array = layout.get("overflow", [])
	_overflow.visible = not over.is_empty()
	_overflow.text = "+%d" % over.size()
	_layout()


static func hotkey_label(i: int) -> String:
	if i < 10:
		return str((i + 1) % 10)
	if i < 20:
		return "⇧" + str((i - 9) % 10)
	if i < 30:
		return "^" + str((i - 19) % 10)
	return ""


## Slot size in pixels for the current screen.
func slot_size() -> float:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	return clampf(vp.y * SLOT_FRACTION * bar_scale * _settings_scale, 32.0, 120.0)


func _layout() -> void:
	if _root == null or _panels.size() <= PANELS:
		return
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var s := slot_size()
	for attempt in range(6):
		var gap := maxf(3.0, s * 0.06)
		var gw := s * 2.3  # group button
		var gh := s * 0.95
		var strip := s * 0.34  # padlock, reset, overflow
		var bar_w := gw * 3 + gap * 4
		var bar_h := strip + gh * 3 + gap * 4
		var cluster_w := s * 4.6
		var end_w := s * 1.3
		var total := cluster_w + gap * 2 + bar_w + gap * 2 + end_w
		if total > vp.x - 16.0 and attempt < 5:
			s *= (vp.x - 16.0) / total
			continue
		var x0 := (vp.x - total) / 2.0
		var y0 := vp.y - bar_h - 8.0
		resources.position = Vector2(x0, y0)
		resources.size = Vector2(cluster_w, bar_h)
		_root.position = Vector2(x0 + cluster_w + gap * 2, y0)
		_root.size = Vector2(bar_w, bar_h)
		_end_turn.position = Vector2(_root.position.x + bar_w + gap * 2, y0)
		_end_turn.size = Vector2(end_w, bar_h)
		_end_turn.add_theme_font_size_override("font_size", int(s * 0.3))
		var fs := int(maxf(12.0, s * 0.24))
		for b: Button in [_lock, _reset, _overflow]:
			b.add_theme_font_size_override("font_size", fs)
			b.custom_minimum_size = Vector2(0, strip - 2)
			b.size = Vector2.ZERO
		_lock.position = Vector2(gap, 1)
		_reset.position = Vector2(_lock.position.x + s * 0.7, 1)
		_overflow.position = Vector2(bar_w - s * 0.9, 1)
		for p in range(1, PANELS + 1):
			var gb: ActionGroupButton = _groups[p]
			gb.position = Vector2(gap + ((p - 1) % 3) * (gw + gap), strip + gap + ((p - 1) / 3) * (gh + gap))
			gb.size = Vector2(gw, gh)
			# The sub-bar: the group's grid, above the buttons, starting over its button.
			var info: Dictionary = _panels[p]
			var d := _panel_data(p)
			var cols := int(d["cols"])
			var rows := int(d["rows"])
			var head := s * 0.36
			var box: Panel = info["box"]
			box.size = Vector2(maxf(cols * (s + gap) + gap, s * 3.6), head + rows * (s + gap) + gap)
			var bx := clampf(_root.position.x + gb.position.x, 8.0, vp.x - box.size.x - 8.0)
			box.position = Vector2(bx, y0 - box.size.y - gap * 2)
			var hl: Label = info["header"]
			hl.add_theme_font_size_override("font_size", int(maxf(13.0, s * 0.26)))
			hl.position = Vector2(gap + 2, 0)
			var tools: HBoxContainer = info["tools"]
			for tb: Button in tools.get_children():
				tb.add_theme_font_size_override("font_size", int(maxf(10.0, s * 0.18)))
				tb.custom_minimum_size = Vector2(s * 0.34, head * 0.85)
			tools.position = Vector2(box.size.x - s * 1.5, 1)
			var slots: Array = info["slots"]
			for i in range(slots.size()):
				var sl: Control = slots[i]
				sl.position = Vector2(gap + (i % cols) * (s + gap), head + (i / cols) * (s + gap))
				sl.size = Vector2(s, s)
				sl.custom_minimum_size = Vector2(s, s)
		return


## Opens a group's sub-bar (or closes it if it's already open); another open one swaps.
func toggle_group(p: int) -> void:
	open_group = 0 if open_group == p else p
	card.visible = false
	_rebuild()


func close_group() -> void:
	if open_group != 0:
		open_group = 0
		card.visible = false
		_rebuild()


## Drops an ability onto a group button: into that group's first free slot.
func move_to_group(id: String, p: int) -> void:
	var d := _panel_data(p)
	var slots: Array = d["slots"]
	var at := slots.find("")
	if at < 0:
		if int(d["cols"]) < MAX_COLS:
			resize_panel(p, 0, 1)
		else:
			resize_panel(p, 1, 0)
		at = (_panel_data(p)["slots"] as Array).find("")
	if at >= 0:
		move_action(id, p, at)


## A slot's key inside the open sub-bar: row 0 "1".."0", row 1 Shift, row 2 Ctrl.
static func slot_key_label(row: int, col: int) -> String:
	if col > 9 or row > 2:
		return ""
	return ["", "⇧", "^"][row] + str((col + 1) % 10)


func _hover(a: Dictionary, on: bool) -> void:
	if not on:
		card.visible = false
		resources.set_preview({})
		if resource_hud:
			resource_hud.set_preview({})
		action_hovered.emit(a, false)
		return
	var vp := get_viewport_rect().size
	var shown := a
	if AutoActions.can_auto(a) == "":
		shown = a.duplicate()
		shown["text"] = String(a.get("text", "")) + "\nRight-click: auto-use this whenever it's allowed."
	card.show_action(shown, clampf(vp.y / 1080.0, 0.75, 1.5) * _settings_scale)
	var b: ActionButton = _buttons.get(a.get("id", ""))
	var x := (b.global_position.x if b else _root.position.x)
	card.position = Vector2(clampf(x, 8, vp.x - card.size.x - 8), (b.global_position.y if b else _root.position.y) - card.size.y - 8)
	var p: Dictionary = a.get("preview", {}) if not ActionButton.locked(a) else {}
	resources.set_preview(p)
	if resource_hud:
		resource_hud.set_preview(p)
	action_hovered.emit(a, true)


## Shows the hover card and preview for an action without the mouse (tutorial, screenshots).
func hover(id: String) -> void:
	for a: Dictionary in actions:
		if a.get("id") == id:
			_hover(a, true)


func _show_overflow() -> void:
	var menu := PopupMenu.new()
	add_child(menu)
	var ids: Array = layout.get("overflow", [])
	for i in range(ids.size()):
		var a := _action(String(ids[i]))
		menu.add_item(String(a.get("name", ids[i])), i)
		menu.set_item_disabled(i, a.is_empty() or ActionButton.locked(a))
	menu.id_pressed.connect(func(i: int) -> void: action_pressed.emit(_action(String(ids[i]))))
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(_root.global_position + _overflow.position + Vector2(0, -menu.size.y))
	menu.popup()


## The filled slots in hotkey order.
func hotkey_order() -> Array:
	var out: Array = []
	for p in range(1, PANELS + 1):
		var d := _panel_data(p)
		for i in range(int(d["rows"]) * int(d["cols"])):
			var a := _action(String(d["slots"][i]))
			if not a.is_empty():
				out.append(a)
	return out


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not visible:
		return
	if k.keycode == KEY_ESCAPE and open_group != 0:
		close_group()
		get_viewport().set_input_as_handled()
		return
	if KEYPAD.has(k.keycode):
		toggle_group(int(KEYPAD[k.keycode]))
		get_viewport().set_input_as_handled()
		return
	if k.keycode == KEY_KP_0:
		end_turn_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if k.keycode >= KEY_0 and k.keycode <= KEY_9 and not k.alt_pressed:
		var col := (k.keycode - KEY_1 + 10) % 10
		var row := 1 if k.shift_pressed else (2 if k.ctrl_pressed else 0)
		var pick := {}
		if open_group != 0:
			var d := _panel_data(open_group)
			var i := row * int(d["cols"]) + col
			if col < int(d["cols"]) and i < (d["slots"] as Array).size():
				pick = _action(String(d["slots"][i]))
		else:
			var order := hotkey_order()
			var idx := col + row * 10
			if idx < order.size():
				pick = order[idx]
		if not pick.is_empty() and not ActionButton.locked(pick):
			action_pressed.emit(pick)
			close_group()
			get_viewport().set_input_as_handled()


## A click anywhere outside the open sub-bar and the group buttons closes it.
func _input(event: InputEvent) -> void:
	if open_group == 0 or not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
		return
	var p := (event as InputEventMouseButton).position
	var box: Panel = _panels[open_group]["box"]
	if not box.get_global_rect().has_point(p) and not _root.get_global_rect().has_point(p):
		close_group()


# --- per-pilot layout ------------------------------------------------------------------

func _layout_path() -> String:
	return LAYOUT_DIR + (pilot_id if pilot_id != "" else "default") + ".json"


func _load_layout() -> void:
	layout = {}
	if FileAccess.file_exists(_layout_path()):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_layout_path()))
		if d is Dictionary and int((d as Dictionary).get("version", 1)) == LAYOUT_VERSION:
			layout = d
	if layout.is_empty():
		layout = {"version": LAYOUT_VERSION, "locked": true, "panels": {}, "overflow": []}
	# Drop ids saved for actions that no longer exist for this unit at all.
	var ids := {}
	for a: Dictionary in actions:
		ids[String(a.get("id", ""))] = true
	for p in range(1, PANELS + 1):
		var slots: Array = _panel_data(p)["slots"]
		for i in range(slots.size()):
			if not ids.has(String(slots[i])):
				slots[i] = ""
	layout["overflow"] = []


func _save_layout() -> void:
	DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)
	var f := FileAccess.open(_layout_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(layout))


## Rows a panel shows: an empty panel shrinks to its header while the bar is locked (unlocked,
## its slots show so actions can be dropped into it).
func _rows_shown(p: int) -> int:
	if bool((_panels[p] as Dictionary).get("empty", false)) and is_locked():
		return 0
	return int(_panel_data(p)["rows"])
