class_name CampaignMap
extends Control
## The sector map (Sector): the systems the squad works in, joined by blink gates, each with
## its worlds. Shows where the squad is, which worlds it has been to, the jobs and situation
## where it is, and how the factions it has dealt with feel about it (standing: this game's own
## bookkeeping, not a book rule). Pick a world for its details; "Travel here" moves the squad
## (StoryEngine "travel"). Opened from the hub with M.

signal travelled(events: Array)
signal closed

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var selected := ""

var _canvas: Control
var _detail: VBoxContainer
var _msg: Label
var _spots: Dictionary = {}  # world id -> Vector2 (canvas position)


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.96)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_canvas_input)
	add_child(_canvas)
	var panel := PanelContainer.new()
	panel.name = "Detail"
	panel.add_theme_stylebox_override("panel", StoryStyle.panel())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(440, 0)
	panel.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	scroll.add_child(_detail)


func bind(e: StoryEngine, s: StoryState, c: Campaign) -> void:
	engine = e
	story = s
	campaign = c


func open() -> void:
	Sector.ensure(story, campaign)
	selected = str(Sector.get_sector(story).get("at", ""))
	visible = true
	_refresh()


func close() -> void:
	visible = false
	closed.emit()


func _process(_d: float) -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	_canvas.position = Vector2(24, 70)
	_canvas.size = Vector2(vp.x - 520, vp.y - 110)
	var panel := get_node("Detail") as PanelContainer
	panel.position = Vector2(vp.x - 484, 70)
	panel.size = Vector2(460, vp.y - 110)
	(panel.get_child(0) as ScrollContainer).custom_minimum_size.y = vp.y - 140


func _unhandled_input(ev: InputEvent) -> void:
	if visible and ev is InputEventKey and ev.pressed and not ev.echo and ((ev as InputEventKey).keycode in [KEY_ESCAPE, KEY_M]):
		close()
		get_viewport().set_input_as_handled()


# --- The map -----------------------------------------------------------------------------

func _layout() -> void:
	_spots.clear()
	var sec := Sector.get_sector(story)
	var systems: Array = sec.get("systems", [])
	var w := _canvas.size.x
	var h := _canvas.size.y
	for i in range(systems.size()):
		var sys: Dictionary = systems[i]
		var c := Vector2(w * (i + 0.5) / systems.size(), h * (0.42 if i % 2 == 0 else 0.6))
		_spots[sys["id"]] = c
		var ws: Array = sys["worlds"]
		for j in range(ws.size()):
			var a := -PI / 2.0 + TAU * j / ws.size() + 0.4
			_spots[ws[j]] = c + Vector2(cos(a), sin(a)) * minf(130.0, w / systems.size() * 0.36)


func _draw_map() -> void:
	if story == null:
		return
	_layout()
	var font := get_theme_default_font()
	var sec := Sector.get_sector(story)
	# Blink gates between systems.
	for link: Array in sec.get("links", []):
		var a: Vector2 = _spots.get(link[0], Vector2.ZERO)
		var b: Vector2 = _spots.get(link[1], Vector2.ZERO)
		_canvas.draw_dashed_line(a, b, Color(0.45, 0.7, 1.0, 0.6), 2.0, 10.0)
		_canvas.draw_string(font, (a + b) / 2.0 + Vector2(-34, -8), "blink gate", HORIZONTAL_ALIGNMENT_LEFT, -1, StorySettings.size(13), Color(0.55, 0.75, 1.0, 0.8))
	for sys: Dictionary in sec.get("systems", []):
		var c: Vector2 = _spots[sys["id"]]
		_canvas.draw_arc(c, minf(130.0, _canvas.size.x / 3.0 * 0.36), 0, TAU, 64, Color(0.4, 0.5, 0.6, 0.35), 1.0)
		_canvas.draw_circle(c, 16, Color(1.0, 0.85, 0.5))
		_canvas.draw_circle(c, 24, Color(1.0, 0.8, 0.4, 0.18))
		_canvas.draw_string(font, c + Vector2(-80, 46), "%s system" % sys["name"], HORIZONTAL_ALIGNMENT_CENTER, 160, StorySettings.size(15), Color(1.0, 0.85, 0.55))
		_canvas.draw_string(font, c + Vector2(-80, 64), str(sys["star"]), HORIZONTAL_ALIGNMENT_CENTER, 160, StorySettings.size(12), Color(0.6, 0.65, 0.72))
	var at := str(sec.get("at", ""))
	for wd: Dictionary in sec.get("worlds", []):
		var p: Vector2 = _spots[wd["id"]]
		var col := _world_color(wd)
		var r := 9.0 if str(wd["kind"]) != "station" else 7.0
		if str(wd["kind"]) == "station":
			_canvas.draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), col)
		else:
			_canvas.draw_circle(p, r, col if bool(wd["visited"]) else col.darkened(0.45))
		if str(wd["id"]) == selected:
			_canvas.draw_arc(p, r + 6, 0, TAU, 32, Color.WHITE, 2.0)
		if str(wd["id"]) == at:
			_canvas.draw_arc(p, r + 11, 0, TAU, 32, StoryStyle.GOLD, 3.0)
			_canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r - 16), p + Vector2(-7, -r - 28), p + Vector2(7, -r - 28)]), StoryStyle.GOLD)
		var label := str(wd["name"])
		var dy := 16.0 if str(wd["id"]) == at else 0.0
		_canvas.draw_string(font, p + Vector2(-90, r + 20 + dy), label, HORIZONTAL_ALIGNMENT_CENTER, 180, StorySettings.size(14), Color(0.9, 0.93, 0.97) if bool(wd["visited"]) else Color(0.6, 0.66, 0.74))
		var tag := "you are here" if str(wd["id"]) == at else ("visited" if bool(wd["visited"]) else "")
		if tag != "":
			_canvas.draw_string(font, p + Vector2(-90, r + 36 + dy), tag, HORIZONTAL_ALIGNMENT_CENTER, 180, StorySettings.size(11), StoryStyle.GOLD if tag == "you are here" else StoryStyle.DIM)
	_canvas.draw_string(font, Vector2(8, 22), "SECTOR MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, StorySettings.size(24), StoryStyle.GOLD)
	_canvas.draw_string(font, Vector2(8, 46), "Click a world for details. M or Esc to close.", HORIZONTAL_ALIGNMENT_LEFT, -1, StorySettings.size(14), StoryStyle.DIM)


## A world's dot is colored by how the squad stands with its people (blue friendly, red hostile).
func _world_color(wd: Dictionary) -> Color:
	var fs := Sector.factions_of(story, wd)
	if fs.is_empty():
		return Color(0.55, 0.62, 0.7)
	var best := 0
	for f: String in fs:
		if absi(story.get_standing(f)) > absi(best):
			best = story.get_standing(f)
	return StoryStyle.BLUE if best > 0 else (StoryStyle.RED if best < 0 else Color(0.8, 0.84, 0.9))


func _canvas_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		for id: String in _spots:
			if not id.begins_with("w_"):
				continue
			if (_spots[id] as Vector2).distance_to((ev as InputEventMouseButton).position) < 22.0:
				selected = id
				_refresh()
				return


# --- Details -----------------------------------------------------------------------------

func _refresh() -> void:
	_canvas.queue_redraw()
	for ch in _detail.get_children():
		ch.queue_free()
	var wd := Sector.world(story, selected)
	if wd.is_empty():
		return
	var sys := Sector.system_of(story, wd)
	var here := str(Sector.get_sector(story).get("at", "")) == selected
	_detail.add_child(StoryStyle.label(str(wd["name"]), 24, StoryStyle.GOLD))
	_detail.add_child(StoryStyle.label("%s in the %s system, around %s" % [Sector.data().get("kind_names", {}).get(str(wd["kind"]), "World"), sys.get("name", ""), sys.get("star", "a star")], 14, StoryStyle.DIM, 420))
	_detail.add_child(StoryStyle.label("%s. %s" % [wd.get("culture_name", ""), wd.get("summary", "")], 15, StoryStyle.TEXT, 420))
	_detail.add_child(StoryStyle.label("Land: %s" % str(wd.get("landscape", "")).replace("_", " "), 14, StoryStyle.DIM))
	if bool(wd["visited"]):
		_detail.add_child(StoryStyle.label("Hub: %s" % wd.get("hub_name", ""), 15, StoryStyle.TEXT))
	else:
		_detail.add_child(StoryStyle.label("You haven't been here yet. Nobody knows your squad.", 15, StoryStyle.DIM, 420))
	# House rules (the user's own ideas): printers and the price of passage.
	if StoryHouseRules.on(campaign, Economy.R_PRINTERS):
		_detail.add_child(StoryStyle.label("Printer: %s  (house rule)" % ("yes" if Economy.has_printer(story, wd) else "none on this world"), 14, StoryStyle.TEXT))
	if not here:
		var fare := Economy.passage(story, campaign, wd)
		if not fare.is_empty():
			_detail.add_child(StoryStyle.label("Passage: %s  (house rule)" % (fare["text"] if StoryHouseRules.on(campaign, Economy.R_WALLET) else "a favor owed"), 14, StoryStyle.TEXT))
		elif StoryHouseRules.on(campaign, Economy.R_TRAVEL):
			_detail.add_child(StoryStyle.label("Passage: free, your patron's ship  (house rule)", 14, StoryStyle.TEXT))
	var fs := Sector.factions_of(story, wd)
	if not fs.is_empty():
		_detail.add_child(StoryStyle.label("STANDING", 15, StoryStyle.GOLD))
		for f: String in fs:
			var v := story.get_standing(f)
			_detail.add_child(StoryStyle.label("%s: %s" % [f, StoryText.standing_label(v)], 15, StoryStyle.BLUE if v > 0 else (StoryStyle.RED if v < 0 else StoryStyle.TEXT), 420))
		_detail.add_child(StoryStyle.label("Standing is this game's own way of remembering who you've helped or crossed. It's not a book rule and never changes a roll.", 12, StoryStyle.DIM, 420))
	var hub: Dictionary = story.hub if here else story.flags.get(Sector.HUBS, {}).get(str(wd.get("hub_id", "")), {})
	var arc: Dictionary = story.arc if here else hub.get("arc_state", {})
	if not arc.is_empty():
		_detail.add_child(StoryStyle.label("SITUATION", 15, StoryStyle.GOLD))
		_detail.add_child(StoryStyle.label("%s (stage %d)" % [arc.get("name", ""), int(arc.get("stage", 0)) + 1], 15, StoryStyle.TEXT, 420))
	var board: Array = story.hooks if here else hub.get("board", [])
	if not board.is_empty():
		_detail.add_child(StoryStyle.label("JOBS" + ("" if here else " (when you left)"), 15, StoryStyle.GOLD))
		for hk: Dictionary in board:
			_detail.add_child(StoryStyle.label("• %s" % hk.get("title", ""), 14, StoryStyle.TEXT, 420))
	_msg = StoryStyle.label("", 14, StoryStyle.RED, 420)
	_detail.add_child(_msg)
	if not here:
		var why := Sector.travel_refusal(story, selected)
		if why == "":
			why = Economy.travel_refusal(story, campaign, wd)
		var go := StoryStyle.button("Travel here" + ("  (through the blink gate)" if str(wd["system"]) != str(Sector.current(story).get("system", "")) else ""), 16)
		go.name = "TravelButton"
		go.disabled = why != ""
		go.tooltip_text = why if why != "" else "Travel is part of the story: no cost, and your mechs come with you (Core p.10)."
		go.pressed.connect(_travel)
		_detail.add_child(go)
		if why != "":
			_msg.text = why
	var back := StoryStyle.button("Close (M)", 14)
	back.pressed.connect(close)
	_detail.add_child(back)


func _travel() -> void:
	var r := engine.submit(story, campaign, {"type": "travel", "seat": "gm", "params": {"world": selected}})
	if not r["ok"]:
		_msg.text = "✕ " + str(r["reason"])
		return
	visible = false
	travelled.emit(r["events"])


## godot --path . -s res://tools/screenshot.gd -- res://scenes/story/campaign_map.tscn out.png 20
func screenshot_setup(_args: Array) -> Variant:
	var d := HubDemo.make(21)
	bind(d["engine"], d["story"], d["campaign"])
	StoryEffects.apply({"standing": str(story.hub.get("conflict", {}).get("b", "")), "add": -2}, story, campaign, {})
	engine.submit(story, campaign, {"type": "travel", "seat": "gm", "params": {"world": "w_1_0"}})
	StoryEffects.apply({"standing": str(story.hub.get("faction", "")), "add": 1}, story, campaign, {})
	engine.submit(story, campaign, {"type": "travel", "seat": "gm", "params": {"world": "w_0_0"}})
	open()
	selected = "w_1_0"
	_refresh()
	return null
