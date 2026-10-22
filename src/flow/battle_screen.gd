extends Node
## The battle screen: the 3D view and HUD from the visuals work (BattleView, EventPlayer,
## TurnOrderBar, ActionBar, PlayerTurn, RollDisplay, CombatLog) attached to a BattleSession.
## Shows the on-screen seat's view, animates events at a readable pace (the AI waits), runs
## your turn when it's yours, "I'll go" from the turn-order bar, hot-seat "Pass to" screens,
## reaction questions, and goes to the debrief when the mission ends.

const BIOME := "grassy_hills"

var session: BattleSession
var content: ContentDB
var view: BattleView
var player: EventPlayer
var rolls: RollDisplay
var combat_log: CombatLog
var order_bar: TurnOrderBar
var bar: ActionBar
var turn: PlayerTurn
var popup: SkillCheckPopup
var ui: CanvasLayer
var banner: Label
var status: Label
var handoff_layer: Control
var reaction_panel: PanelContainer
var menu_layer: Control

var _loaded := false
var _queue: Array = []
var _draining := false
var _ended := false
var _asked := ""


func _ready() -> void:
	content = MenuSession.content()
	session = GameFlow.session if GameFlow.session != null else _example_session()
	view = BattleView.new()
	view.content = content
	add_child(view)
	_build_ui()
	player = EventPlayer.new(view, rolls, combat_log)
	player.popup = popup
	player.camera = view.tactical
	player.on_banner = show_banner
	add_child(player)
	turn = PlayerTurn.new()
	turn.bar = bar
	turn.view = view
	turn.player = player
	turn.db = content
	add_child(turn)
	turn.setup(ui)
	turn.acted.connect(_refresh_hud)
	session.view_updated.connect(_on_view)
	session.handoff.connect(_on_handoff)
	session.mission_over.connect(_on_mission_over)
	session.log_line.connect(func(t: String) -> void: combat_log.add_line("[color=#9aa4b2]%s[/color]" % t))
	session.refused.connect(func(why: String, ref: String) -> void: show_banner("Not allowed: %s" % why) if ref == "" else show_banner("Not allowed: %s (%s)" % [why, ref]))
	order_bar.i_will_go.connect(_on_i_will_go)
	var speed := MenuSession.settings().animation_speed
	session.ai_interval = {"cinematic": 0.9, "normal": 0.45, "fast": 0.1}.get(speed, 0.45)
	if not session.view.is_empty():
		_on_view(session.seat, session.view, [])
	session.start()
	# Screenshot staging (tools/screenshot.gd ... battle.tscn out.png frames stage:turn).
	if "stage:turn" in OS.get_cmdline_user_args():
		_stage_turn.call_deferred()


func _stage_turn() -> void:
	for i in range(30):
		await get_tree().process_frame
		session.poll(1.0)
		if session.my_pick():
			var mine := _local_units()
			if not mine.is_empty():
				session.pick(mine[0])
			return


func _process(delta: float) -> void:
	session.busy = _draining or player.playing or turn.busy
	session.poll(delta)
	if _ended or not _loaded:
		return
	if not turn.active and not session.busy:
		var uid := session.my_turn_unit()
		if uid != "" and session.mirror.unit(uid) != null:
			turn.state = session.mirror
			turn.engine = session.engine
			player.local_units = _local_units()
			turn.begin(uid)
	var q := session.my_reaction()
	var key := str(q.get("id", ""))
	if key != _asked:
		_asked = key
		_show_reaction(q)
	_update_status()


# --- View and events -----------------------------------------------------------------------

func _on_view(_seat: String, v: Dictionary, events: Array) -> void:
	if not _loaded:
		_load(v)
		return
	_queue.append([v, events])
	if not _draining:
		_drain()


func _load(v: Dictionary) -> void:
	_loaded = true
	view.set_map(BattleMap.from_dict(v.get("map", {})), BIOME)
	view.clear_units()
	for id: String in v.get("units", {}):
		var u: Dictionary = v["units"][id]
		if not u.get("hidden", false) and not u.get("destroyed", false):
			view.add_unit(u)
	var mine := _local_units()
	var center := Vector3.ZERO
	for mv: MechView in view.units.values():
		center += mv.global_position
	if not view.units.is_empty():
		center /= view.units.size()
	for mv: MechView in view.units.values():
		mv.face(center)
	var focus: MechView = view.units.get(mine[0]) if not mine.is_empty() else null
	view.tactical.look_at_point((focus.global_position if focus else center) + Vector3.UP * 0.5, 16.0)
	view.tactical.snap()
	player.local_units = mine
	_render_portraits(v)
	_refresh_hud()


func _drain() -> void:
	_draining = true
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var events: Array = item[1]
		if not events.is_empty():
			await player.play(events)
		_sync(item[0])
	_draining = false


## Copies what the view says onto the board: stats, new units (reinforcements, revealed
## Hidden units), units that vanished (became Hidden), then the HUD.
func _sync(v: Dictionary) -> void:
	var units: Dictionary = v.get("units", {})
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("hidden", false):
			if view.units.has(id):
				(view.units[id] as MechView).queue_free()
				view.units.erase(id)
			continue
		if not view.units.has(id):
			if not u.get("destroyed", false):
				view.add_unit(u)
			continue
		var mv: MechView = view.units[id]
		for k: String in ["hp", "max_hp", "heat", "heat_cap", "structure", "max_structure", "overshield", "statuses", "burn"]:
			if u.has(k):
				mv.unit[k] = u[k]
		mv.refresh()
	_refresh_hud()


func _refresh_hud() -> void:
	var v := session.view
	var list: Array = []
	var my_side := _my_side()
	for id: String in v.get("units", {}):
		var u: Dictionary = v["units"][id]
		if u.get("hidden", false):
			continue
		var e := {"id": id, "name": u.get("name", id), "side": u.get("side", ""), "frame": u.get("content_id", ""),
			"acted": (v.get("acted", []) as Array).has(id) or u.get("destroyed", false), "active": v.get("active_unit", "") == id}
		if u.has("hp"):
			e["hp"] = [int(u["hp"]), int(u.get("max_hp", 0))]
		list.append(e)
	var active: Dictionary = v.get("units", {}).get(v.get("active_unit", ""), {})
	order_bar.set_data({"round": maxi(1, int(v.get("round", 1))), "picking_side": v.get("turn_side", ""),
		"local_side": my_side if session.my_pick() else "", "active_name": str(active.get("name", "")), "units": list})


func _render_portraits(v: Dictionary) -> void:
	for id: String in view.units:
		var u: Dictionary = (view.units[id] as MechView).unit
		var model := MechBuilder.build(content.frame(str(u.get("content_id", ""))), u.get("loadout", {}), content)
		order_bar.portraits[id] = TurnOrderBar.render_portrait(self, model, model.height)


func _on_i_will_go(uid: String) -> void:
	var why := session.pick(uid)
	if why != "":
		show_banner(why)


func _local_units() -> Array:
	var out: Array = []
	var seats := session.local_humans() if session.is_host else [session.seat]
	for id: String in session.view.get("units", {}):
		var u: Dictionary = session.view["units"][id]
		if str(u.get("controller", "")) in seats:
			out.append(id)
	return out


func _my_side() -> String:
	return str(session.view.get("seats", {}).get(session.seat, {}).get("side", "players"))


# --- Overlays ------------------------------------------------------------------------------

func _update_status() -> void:
	var w := session.waiting()
	var text := str(w.get("text", ""))
	if turn.active:
		text = ""
	elif session.my_pick():
		text = "Your squad's pick: click \"I'll go\" on a portrait above (yours or an AI squadmate's)."
	status.text = text
	status.visible = text != ""


func _on_handoff(_next_seat: String, display_name: String) -> void:
	turn.cancel()
	for c in handoff_layer.get_children():
		c.queue_free()
	var bg := ColorRect.new()
	bg.color = MenuTheme.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	handoff_layer.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	handoff_layer.add_child(center)
	var p := MenuTheme.panel("Pass the screen", MenuTheme.ACCENT, "pilot")
	p.custom_minimum_size = Vector2(640, 0)
	var b := MenuTheme.body(p)
	b.add_child(MenuTheme.heading("Pass to %s" % display_name, 40))
	b.add_child(MenuTheme.label("The board is hidden so each player only sees what their pilot knows. Hand over the controls, then press Ready.", 18, MenuTheme.MUTED, true))
	var ready := Button.new()
	ready.text = "READY  ›"
	ready.custom_minimum_size = Vector2(0, 60)
	ready.add_theme_font_override("font", MenuTheme.bold_font())
	ready.add_theme_font_size_override("font_size", 24)
	ready.pressed.connect(func() -> void:
		handoff_layer.visible = false
		session.confirm_handoff())
	b.add_child(ready)
	center.add_child(p)
	handoff_layer.visible = true


func _show_reaction(q: Dictionary) -> void:
	for c in reaction_panel.get_children():
		c.queue_free()
	reaction_panel.visible = not q.is_empty()
	if q.is_empty():
		return
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	reaction_panel.add_child(v)
	var who: Dictionary = session.view.get("units", {}).get(str(q.get("unit", "")), {})
	var reaction := str(q.get("reaction", "react"))
	v.add_child(MenuTheme.heading("Reaction: %s" % reaction.capitalize(), 22, MenuTheme.WARN))
	var explain := content.rule_text(reaction.capitalize())
	if explain == "":
		explain = str(content.get_entry("actions", reaction.capitalize()).get("detail", ""))
	v.add_child(MenuTheme.label("%s can %s now. %s" % [who.get("name", "Your mech"), reaction, BuilderModel._plain(explain).left(260)], 16, MenuTheme.TEXT, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var weapons: Array = q.get("context", {}).get("weapons", [])
	if reaction == "overwatch" and not weapons.is_empty():
		for wkey: Variant in weapons:
			var b := Button.new()
			b.text = "Overwatch with %s" % _weapon_name(who, str(wkey))
			b.pressed.connect(func() -> void: session.answer_reaction(true, str(wkey)))
			row.add_child(b)
	else:
		var yes := Button.new()
		yes.text = "Yes, %s" % reaction
		yes.pressed.connect(func() -> void: session.answer_reaction(true))
		row.add_child(yes)
	var no := Button.new()
	no.text = "No"
	no.pressed.connect(func() -> void: session.answer_reaction(false))
	row.add_child(no)
	v.add_child(row)
	reaction_panel.reset_size()
	var vp := reaction_panel.get_viewport_rect().size
	reaction_panel.position = Vector2((vp.x - 620) / 2.0, vp.y * 0.55)


static func _weapon_name(u: Dictionary, key: String) -> String:
	for w: Dictionary in u.get("loadout", {}).get("weapons", []):
		if str(w.get("key", "")) == key:
			return str(w.get("name", key))
	return key


func show_banner(text: String) -> void:
	var vp := banner.get_viewport_rect().size
	banner.text = text.to_upper()
	banner.add_theme_font_size_override("font_size", int(vp.y * 0.04))
	banner.position = Vector2(0, vp.y * 0.24)
	banner.size = Vector2(vp.x, vp.y * 0.08)
	var tw := banner.create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, Fx.t(0.25))
	tw.tween_interval(Fx.t(1.2))
	tw.tween_property(banner, "modulate:a", 0.0, Fx.t(0.4))


func _on_mission_over(outcome: String, reason: String) -> void:
	_ended = true
	turn.cancel()
	bar.visible = false
	while _draining:
		await get_tree().process_frame
	var won := outcome == _my_side()
	show_banner(GameFlow.title_for(outcome) if session.is_host else ("Mission complete" if won else GameFlow.title_for(outcome)))
	combat_log.add_line("[b]%s[/b] %s" % [GameFlow.title_for(outcome), reason])
	await get_tree().create_timer(2.5).timeout
	if session.is_host and MenuSession.campaign != null:
		GameFlow.finish_mission(session, MenuSession.campaign, MenuSession.store)
	else:
		GameFlow.debrief = {"outcome": outcome, "reason": reason, "title": GameFlow.title_for(outcome), "pilots": [], "client": true}
	MenuSession.go(self, "debrief")


# --- Building the screen -------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	rolls = RollDisplay.new()
	ui.add_child(rolls)
	combat_log = CombatLog.new()
	ui.add_child(combat_log)
	combat_log.position = Vector2(1920 - 500, 160)
	order_bar = TurnOrderBar.new()
	ui.add_child(order_bar)
	bar = ActionBar.new()
	bar.visible = false
	ui.add_child(bar)
	popup = SkillCheckPopup.new()
	ui.add_child(popup)
	banner = Label.new()
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 10)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(banner)
	status = MenuTheme.label("", 20, MenuTheme.TEXT)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_constant_override("outline_size", 8)
	status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	status.position = Vector2(0, 1080 - 250)
	status.size = Vector2(1920, 34)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(status)
	reaction_panel = PanelContainer.new()
	reaction_panel.theme = MenuTheme.theme()
	reaction_panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.04, 0.05, 0.07, 0.96), MenuTheme.WARN, 2, 4))
	reaction_panel.custom_minimum_size = Vector2(620, 0)
	reaction_panel.visible = false
	ui.add_child(reaction_panel)
	var menu := Button.new()
	menu.theme = MenuTheme.theme()
	menu.text = "≡  Menu"
	menu.position = Vector2(16, 16)
	menu.pressed.connect(_open_menu)
	ui.add_child(menu)
	menu_layer = Control.new()
	menu_layer.theme = MenuTheme.theme()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.visible = false
	ui.add_child(menu_layer)
	handoff_layer = Control.new()
	handoff_layer.theme = MenuTheme.theme()
	handoff_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	handoff_layer.visible = false
	ui.add_child(handoff_layer)


## In-battle menu: the game is saved after every turn, so leaving is safe.
func _open_menu() -> void:
	for c in menu_layer.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(center)
	var p := MenuTheme.panel("Paused" if session.is_host and session.local_humans().size() == session.hot.seats.size() else "Menu", MenuTheme.ACCENT)
	p.custom_minimum_size = Vector2(520, 0)
	var b := MenuTheme.body(p)
	b.add_child(MenuTheme.label("The mission is saved after every turn. Continue it from the main menu any time.", 16, MenuTheme.MUTED, true))
	for item in [["Back to the battle", func() -> void: menu_layer.visible = false],
			["Settings", func() -> void: _leave("settings")],
			["Save and quit to main menu", func() -> void: _leave("main")]]:
		var btn := Button.new()
		btn.text = item[0]
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(item[1])
		b.add_child(btn)
	center.add_child(p)
	menu_layer.visible = true


func _leave(screen: String) -> void:
	if session.is_host and session.autosave != null and not session.over:
		session.autosave.save_now()
	var net := MenuSession.net(self)
	if net != null:
		net.leave()
	GameFlow.session = null
	MenuSession.back_to = "main"
	MenuSession.go(self, screen)


## Opened on its own (screenshots, development): an unsaved example battle.
func _example_session() -> BattleSession:
	MenuSession.ensure_campaign()
	var lobby := LobbyModel.for_host(MenuSession.campaign, MenuSession.content(), 4242)
	if "stage:hotseat" in OS.get_cmdline_user_args():
		lobby.set_mode("p2", "you")
	lobby.set_local_ready(true)
	var s := GameFlow.start_mission(lobby, SaveStore.new("user://example_saves"))
	return s
