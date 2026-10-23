extends Node
## The battle screen: the 3D view and HUD from the visuals work (BattleView, EventPlayer,
## TurnOrderBar, ActionBar, PlayerTurn, RollPopups, CombatLog) attached to a BattleSession.
## Shows the on-screen seat's view, animates events at a readable pace (the AI waits), runs
## your turn when it's yours, "I'll go" from the turn-order bar, hot-seat "Pass to" screens,
## reaction questions, the GM's narration (a mission twist, NarrationPopup), tutorial lessons
## and first-time rule tips (Tutorial, TutorialPanel; teaching hints on/off per campaign), and
## goes to the debrief when the mission ends (story campaigns: back to the hub).

const BIOME := "grassy_hills"

var session: BattleSession
var content: ContentDB
var view: BattleView
var player: EventPlayer
var rolls: RollPopups
var combat_log: CombatLog
var order_bar: TurnOrderBar
var bar: ActionBar
var turn: PlayerTurn
var ui: CanvasLayer
var banner: Label
var status: Label
var handoff_layer: Control
var reaction_panel: PanelContainer
var menu_layer: Control
var tutorial: TutorialPanel
var narration: NarrationPopup
## AI squadmates' barks over their mechs (story campaigns).
var bubbles: BattleBarks
## The rules reference (CodexPanel): from the pause menu, or the Codex key (F1) on whatever is
## hovered (an action on the bar, or a mech's frame).
var codex: CodexPanel
var _hover_term := ""
## Story campaigns: the enemy commander's parley (Core p.60) as a conversation over the battle,
## and the squad's "Call for terms". The engine is the host's StoryHostEngine or a friend's
## StoryClient; `dlg_story`/`dlg_campaign` are the objects the dialogue shows.
var dialogue: DialogueView
## A human GM's story tools (G) over the battle, when the GM seat is played at this screen.
var gm_panel: GmPanel
var terms_button: Button
var story_engine: StoryEngine
var dlg_story: StoryState
var dlg_campaign: Campaign
## Sitrep actions the turn UI doesn't offer (SitrepActions): Extract, Survey this zone.
var sitrep_box: VBoxContainer
## "Let the AI go": the AI squadmates may act before the people's own mechs.
var ai_go_button: Button
var _sitrep_sig := ""
var _objectives_sig := ""
## The campaign's story (host), for the tutorial's lessons and which tips were shown. A friend
## in someone else's game gets a fresh one (tips only; the host keeps the campaign).
var story: StoryState
var campaign: Campaign

var _loaded := false
var _queue: Array = []
var _draining := false
var _ended := false
var _asked := ""
var _hud_sig := ""
var _nhp_asked := ""


func _ready() -> void:
	content = MenuSession.content()
	MenuSession.settings().apply_graphics(get_viewport())  # before the board is built
	session = GameFlow.session if GameFlow.session != null else _example_session()
	view = BattleView.new()
	view.content = content
	add_child(view)
	_build_ui()
	bubbles.view = view
	bubbles.read_rate *= MenuSession.settings().popup_duration
	player = EventPlayer.new(view, rolls, combat_log)
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
	bar.action_hovered.connect(func(a: Dictionary, on: bool) -> void:
		if on:
			_hover_term = str(a.get("name", "")))
	if session.is_host and MenuSession.campaign != null:
		campaign = MenuSession.campaign
		story = GameFlow.open_story(campaign, content)
	else:
		story = StoryState.new(0)
	tutorial.bind(campaign)
	session.events_seen.connect(_on_events_seen)
	_setup_story_battle()
	_setup_gm_map_edit()
	if session.is_split_fight():
		var y := Button.new()
		y.theme = MenuTheme.theme()
		y.text = "Yield"
		y.focus_mode = Control.FOCUS_NONE
		y.tooltip_text = "Give up this fight between the squad's two sides. When everyone on your side has yielded, the other side's choice stands. Nobody dies: knocked-out mechs just need repairs."
		y.position = Vector2(300, 16)
		y.pressed.connect(func() -> void:
			session.pvp_yield()
			show_banner("You yield. When everyone on your side has, the other side wins."))
		ui.add_child(y)
	SitrepActions.register(session.engine)
	var speed := MenuSession.settings().animation_speed
	session.ai_interval = {"cinematic": 0.9, "normal": 0.45, "fast": 0.1}.get(speed, 0.45)
	if not session.view.is_empty():
		_on_view(session.seat, session.view, [])
	session.start()
	# Screenshot staging (tools/screenshot.gd ... battle.tscn out.png frames stage:turn).
	if "stage:turn" in OS.get_cmdline_user_args():
		_stage_turn.call_deferred()
	if "stage:codex" in OS.get_cmdline_user_args():
		codex.open.call_deferred("Overcharge")
	if "stage:twist" in OS.get_cmdline_user_args():
		_stage_twist.call_deferred()
	if "stage:radio" in OS.get_cmdline_user_args():
		_stage_radio.call_deferred()


func _stage_turn() -> void:
	for i in range(30):
		await get_tree().process_frame
		session.poll(1.0)
		if session.my_pick():
			var mine := _local_units()
			if not mine.is_empty():
				session.pick(mine[0])
			return


## Screenshot staging: an enemy commander on the open channel, clear and then Jammed.
func _stage_radio() -> void:
	for i in range(10):
		await get_tree().process_frame
	var look := PortraitSpec.for_npc({"name": "Ilse Vey", "id": "rival_demo"})
	bubbles.say({"name": "Vey", "mode": "radio", "channel": "Open channel", "face": {"portrait": look, "expression": "smug"},
		"text": "Lancers. You're a long way from your printer.", "duration": 30.0})
	bubbles.say({"name": "Vey", "mode": "radio", "channel": "Open channel", "jammed_here": true, "face": {"portrait": look, "expression": "smug"},
		"text": "You can't hear this.", "duration": 30.0})


## Screenshot staging: a twist pop-up and a tutorial lesson over the board.
func _stage_twist() -> void:
	for i in range(10):
		await get_tree().process_frame
	_narrate([{"type": "twist_revealed", "title": "Twist", "speaker": "Commander Ilse Vey", "rule_ref": GmTwist.REF,
		"twist": {"id": "third_party", "reveal": "New transponders on the scope. Not the enemy you came for. Someone else wants this too.", "question": "Who sent them, and what do they want here?"}}])
	var mates := _local_units()
	var cam := get_viewport().get_camera_3d()
	var screen := get_viewport().get_visible_rect()
	for id: String in view.units:
		var mv: MechView = view.units[id]
		var u: Dictionary = mv.unit
		if u.get("side", "") == Mission.PLAYERS and not mates.has(id) and screen.has_point(cam.unproject_position(mv.plate_anchor())):
			bubbles.say({"unit": id, "name": str(u.get("name", id)), "text": "Contact front. I'll hold this side, you push."})
			break
	var lesson: Dictionary = Tutorial.lessons()[3]
	tutorial.show_events([{"type": "tutorial_prompt", "kind": "lesson", "id": lesson["id"], "title": lesson.get("title", ""), "text": lesson.get("text", ""),
		"objective": lesson.get("objective", ""), "rule_ref": lesson.get("rule_ref", ""), "step": 4, "of": Tutorial.lessons().size()}])


## Exploring: the unit that walks when the ground is clicked, and the banner saying so.
var _explorer := ""
var _explore_label: Label


var _careful_button: Button


func _update_explore_banner() -> void:
	# Careful mode (turn-based exploring) for the host while nobody's fighting yet.
	var can_careful := _loaded and not _ended and session.is_host and (str(session.view.get("phase", "")) == GameState.PHASE_SETUP and session.mission != null and bool(session.mission.flavor.get("explore_first", false)) or session.careful())
	if can_careful and _careful_button == null:
		_careful_button = Button.new()
		_careful_button.theme = MenuTheme.theme()
		_careful_button.focus_mode = Control.FOCUS_NONE
		_careful_button.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 120, 205)
		_careful_button.tooltip_text = "Careful mode: explore in turns (for stealth and heists), the way a fight goes. Off: everyone walks in real time."
		_careful_button.pressed.connect(func() -> void:
			var why := session.set_careful(not session.careful())
			if why != "":
				show_banner(why))
		ui.add_child(_careful_button)
	if _careful_button != null:
		_careful_button.visible = can_careful
		_careful_button.text = "Careful mode: ON (turns)" if session.careful() else "Careful mode: off (real time)"
	var on := _loaded and not _ended and session.exploring() and not turn.active
	if on and _explore_label == null:
		_explore_label = MenuTheme.label("", 18, Color(0.6, 0.95, 0.75))
		_explore_label.add_theme_constant_override("outline_size", 6)
		_explore_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		_explore_label.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0 - 360, 170)
		ui.add_child(_explore_label)
	if _explore_label != null:
		_explore_label.visible = on
		if on:
			var setup := str(session.view.get("phase", "")) == GameState.PHASE_SETUP
			_explore_label.text = ("EXPLORING: click the ground to walk (no turns). The fight starts when you meet the enemy." if setup
				else "You're outside the fight: walk there and you join it from the next round.")


## Exploring: left click on the ground walks your unit there (a click on one of your units
## picks which one walks).
func _explore_click(ev: InputEvent) -> bool:
	if not (ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT):
		return false
	if turn.active or not session.exploring():
		return false
	var mine := session.exploring_units()
	if mine.is_empty():
		return false
	var cell: Variant = turn.cell_at_screen((ev as InputEventMouseButton).position)
	if cell == null:
		return false
	for id: String in mine:
		var u: Dictionary = session.view["units"][id]
		if Vector2i(int(u["cell"][0]), int(u["cell"][1])) == cell:
			_explorer = id
			return true
	if not _explorer in mine:
		_explorer = str(mine[0])
	var why := session.walk_to(_explorer, cell)
	if why != "":
		show_banner(why)
	return true


func _process(delta: float) -> void:
	_update_explore_banner()
	# The in-battle menu really pauses the AI when everyone in the game is at this screen.
	session.busy = _draining or player.playing or turn.busy or narration.visible or (dialogue != null and dialogue.visible) or (menu_layer.visible and _can_pause())
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
	# Keep the turn-order bar in step with the game (whose pick, who acted, "I'll go").
	if not _draining:
		var v := session.view
		var sig := "%s|%s|%s|%s|%s" % [v.get("round", 0), v.get("turn_side", ""), v.get("active_unit", ""), (v.get("acted", []) as Array).size(), session.my_pick()]
		if sig != _hud_sig:
			_hud_sig = sig
			_refresh_hud()
	var q := session.my_reaction()
	var key := str(q.get("id", ""))
	if key != _asked:
		_asked = key
		_show_reaction(q)
	var nq := session.nhp_question()
	var nkey := JSON.stringify(nq)
	if nkey != _nhp_asked:
		_nhp_asked = nkey
		_show_nhp(nq)
	_update_sitrep_buttons()
	ai_go_button.visible = not session.ai_squadmates_waiting().is_empty() and not turn.active
	_update_status()


# --- View and events -----------------------------------------------------------------------

func _on_view(_seat: String, v: Dictionary, events: Array) -> void:
	if not _loaded:
		_load(v)
		return
	_queue.append([v, events])
	if not _draining:
		_drain()


## Every batch the seat on screen sees (its own actions too): tutorial lessons and tips.
func _on_events_seen(_seat: String, events: Array) -> void:
	for e: Dictionary in events:
		if str(e.get("type", "")) == "house_rule_changed":
			var text := HouseRules.announce(str(e.get("id", "")), bool(e.get("on", false)))
			combat_log.add_line("[color=#c9a0ff]%s[/color]" % text)  # every switch is announced
			show_banner(text)
	tutorial.show_events(Tutorial.observe_battle(story, campaign, events, _local_units()))


## The GM's narration in a batch: the pop-up, and a line in the combat log.
func _narrate(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"twist_revealed":
				combat_log.add_line("[color=#ffd166][b]Twist:[/b][/color] %s" % e["twist"].get("reveal", ""))
			"gm_narration":
				combat_log.add_line("[color=#ffd166]%s:[/color] %s" % [e.get("title", "GM"), e.get("text", "")])
	narration.show_events(events)


## AI squadmates speak up as things happen (Squadmate.barks_for: their persona and what they
## remember). Story campaigns only: the host's story, or a friend's mirror of it.
func _barks(events: Array) -> void:
	var st: StoryState = story if campaign != null else (GameFlow.story_client.story if GameFlow.story_client != null else null)
	var c: Campaign = campaign if campaign != null else (GameFlow.story_client.campaign if GameFlow.story_client != null else null)
	if st == null or c == null or st.seats.is_empty():
		return
	var unit_pilot := {}
	var seat_of := {}
	for id: String in session.view.get("units", {}):
		var u: Dictionary = session.view["units"][id]
		var seat := str(u.get("controller", ""))
		if str(u.get("kind", "")) == Unit.KIND_MECH and st.seats.has(seat):
			unit_pilot[id] = st.pilot_of_seat(seat)
			seat_of[id] = seat
	for e: Dictionary in events:
		for line: Dictionary in Squadmate.barks_for(st, c, e, unit_pilot, seat_of):
			var who := str(line.get("who", c.pilots.get(str(line.get("pilot", "")), {}).get("callsign", "")))
			var bark := line.duplicate()
			bark["name"] = who
			if line.get("jammed") is Array:
				# Radio to a Jammed pilot on this screen: static instead of the words.
				bark["jammed_here"] = (line["jammed"] as Array).has(st.pilot_of_seat(session.seat))  # pilot ids
			bubbles.say(bark)
			combat_log.add_line("[color=#9fc3e8]%s:[/color] %s" % [who, line["text"]])


# --- Sitrep objectives -----------------------------------------------------------------------

## The sitrep's zones and deployment on the board, as this seat knows them (ViewFilter.objectives_for): Recon's
## four zones (the True one named once found), Escort/Extraction's Extraction Zone.
func _show_objectives(v: Dictionary) -> void:
	var o: Dictionary = v.get("objectives", {})
	var setup := str(v.get("phase", "")) == GameState.PHASE_SETUP
	var sig := JSON.stringify([o.get("zones", {}).keys(), o.get("true_zone", ""), o.get("surveyed", {}), setup])
	if sig == _objectives_sig or view.terrain == null:
		return
	_objectives_sig = sig
	var zones := {}
	var src: Dictionary = o.get("zones", {})
	for name: String in src:
		var label := name
		if name.begins_with("zone_") and str(o.get("sitrep", "")) == "sitrep_recon":
			var known: Dictionary = (o.get("surveyed", {}) as Dictionary).get(_my_side(), {})
			label = ("TRUE ZONE" if name == str(o.get("true_zone", "")) else ("not it" if known.has(name) else name.replace("_", " ")))
		zones[label] = src[name]
	# Deployment zones are tinted while the battle is being set up.
	view.terrain.show_objectives(zones, o.get("deployment", {}), setup)


## Extract / Survey this zone, when the rules allow them for the unit whose turn it is here.
func _update_sitrep_buttons() -> void:
	var uid: String = turn.unit_id if turn.active else ""
	var offers: Array = []
	if uid != "" and session.mirror != null and session.mirror.unit(uid) != null:
		for t: String in ["extract", "survey_zone"]:
			var r := session.engine.validate(session.mirror, {"type": t, "actor": uid, "params": {}})
			if r.ok:
				offers.append(t)
	var sig := "%s|%s" % [uid, ",".join(PackedStringArray(offers))]
	if sig == _sitrep_sig:
		return
	_sitrep_sig = sig
	for c in sitrep_box.get_children():
		c.queue_free()
	for t: String in offers:
		var b := Button.new()
		b.theme = MenuTheme.theme()
		b.custom_minimum_size = Vector2(300, 46)
		if t == "extract":
			b.text = "Extract (ends your turn)"
			b.tooltip_text = "Free action at the end of your turn while in the Extraction Zone: your mech leaves the battlefield. An adjacent Objective that no enemy is next to goes with you (sitreps: Escort, Extraction)."
		else:
			b.text = "Survey this zone (full action)"
			b.tooltip_text = "Find out whether this is the True Control Zone. Only your side learns the answer (sitreps: Recon)."
		var action := {"type": t, "actor": uid, "params": {}}
		b.pressed.connect(func() -> void:
			if t == "extract":
				turn.cancel()
				turn.active = false
				bar.visible = false
			session.engine.submit(session.mirror, action)
			_sitrep_sig = "")
		sitrep_box.add_child(b)


# --- Story campaigns: the enemy commander and parley -------------------------------------

func _setup_story_battle() -> void:
	if session.is_host and campaign != null and GameFlow.is_story(campaign) and not story.seats.is_empty():
		var sess := GameFlow.open_story_session(campaign, content, session.local_humans())
		story_engine = StoryHostEngine.new(content, sess)
		dlg_story = story
		dlg_campaign = campaign
		session.host_events.connect(_on_host_events)
		sess.updated.connect(_on_story_update)
	elif not session.is_host and GameFlow.story_client != null and GameFlow.story_client.story != null:
		story_engine = GameFlow.story_client
		dlg_story = GameFlow.story_client.story
		dlg_campaign = GameFlow.story_client.campaign
		GameFlow.story_client.mirror_changed.connect(_on_story_mirror)
		GameFlow.story_client.refused.connect(_on_story_refused)
	if story_engine == null:
		return
	dialogue = DialogueView.new()
	ui.add_child(dialogue)
	ui.move_child(dialogue, codex.get_index())  # under the codex, over the board and HUD
	dialogue.bind(story_engine, dlg_story, dlg_campaign, _story_seat())
	dialogue.story_events.connect(_on_dialogue_events)
	terms_button = Button.new()
	terms_button.theme = MenuTheme.theme()
	terms_button.text = "Call for terms"
	terms_button.focus_mode = Control.FOCUS_NONE
	terms_button.tooltip_text = "Call on the enemy commander to stand down. Only once the fight's outcome is clear: the GM ends a fight early only then (Core p.60)."
	terms_button.position = Vector2(150, 16)
	terms_button.pressed.connect(_call_for_terms)
	ui.add_child(terms_button)
	if _gm_here():
		terms_button.visible = _story_seat() != NetHost.GM_SEAT  # the squad calls for terms, not the GM
		gm_panel = GmPanel.new()
		ui.add_child(gm_panel)
		ui.move_child(gm_panel, codex.get_index())
		gm_panel.bind(story_engine, dlg_story, dlg_campaign)
		# Host: the story session's update brings the GM's events (with everyone else's).
		gm_panel.story_events.connect(func(evs: Array) -> void:
			if not session.is_host:
				_story_events(evs))


# --- A human GM edits the map live ---------------------------------------------------------

## "Edit map" for a human GM at the host: the map editor (MapEditor.start_live) on this
## battle's engine and state; every edit is a GM action, and each batch goes to every seat.
func _setup_gm_map_edit() -> void:
	if not session.is_host or not session.gm_here:
		return
	var b := Button.new()
	b.theme = MenuTheme.theme()
	b.text = "Edit map"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "GM: change the battlefield now (height, terrain, zones). Every player sees the changes."
	b.position = Vector2(300, 16)
	b.pressed.connect(_open_map_editor)
	ui.add_child(b)


var _map_editor: Node


func _open_map_editor() -> void:
	if _map_editor != null:
		return
	_map_editor = (load("res://scenes/editor/map_editor.tscn") as PackedScene).instantiate()
	add_child(_map_editor)
	_map_editor.start_live(session.host.engine, session.host.state, BIOME)
	_map_editor.edited.connect(func(events: Array) -> void: session.host.send_updates(events))
	ui.visible = false
	var layer := CanvasLayer.new()
	layer.layer = 30
	_map_editor.add_child(layer)
	var done := Button.new()
	done.theme = MenuTheme.theme()
	done.text = "Done editing: back to the battle"
	done.position = Vector2(get_viewport().get_visible_rect().size.x - 340, 16)
	done.pressed.connect(_close_map_editor)
	layer.add_child(done)


func _close_map_editor() -> void:
	if _map_editor == null:
		return
	_map_editor.queue_free()
	_map_editor = null
	ui.visible = true
	view.tactical.camera.make_current()


## The GM seat is played at this screen (campaign option "Human GM").
func _gm_here() -> bool:
	return session.gm_here if session.is_host else session.seat == NetHost.GM_SEAT


func _story_seat() -> String:
	if not session.is_host:
		return session.seat
	var humans := session.local_humans()
	return str(humans[0]) if not humans.is_empty() else session.seat


## Host: each batch of rules events goes to the story (the commander may open a parley).
func _on_host_events(events: Array) -> void:
	GameFlow.story_battle_events(dlg_campaign, events)  # its story events reach _on_story_update


## Host: everything the story reports, from any seat (a friend's parley choice too).
func _on_story_update(_view: Dictionary, events: Array) -> void:
	_story_events(events)


## A friend: a new view of the host's story.
func _on_story_mirror(s: StoryState, c: Campaign, events: Array) -> void:
	GameFlow.copy_into(dlg_story, s)
	GameFlow.copy_into(dlg_campaign, c)
	_story_events(events)


func _on_story_refused(reason: String, _ref: String) -> void:
	show_banner(reason)
	combat_log.add_line("[color=#ff8a7a]%s[/color]" % reason)


func _on_dialogue_events(events: Array) -> void:
	if session.is_host:
		return  # the session's update brings them (with everyone else's)
	_story_events(events)


func _story_events(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"rival_defiant":
				combat_log.add_line("[color=#ff8a7a]%s[/color]" % e.get("text", ""))
			"battle_end_requested":
				session.end_by_parley(e)
			"house_rule_changed":
				# A story house rule switched mid-battle (the story announces its own).
				combat_log.add_line("[color=#c9a0ff]%s[/color]" % HouseRules.announce(str(e.get("id", "")), bool(e.get("on", false))))
			"twist_revealed":
				if session.is_host and bool(e.get("by_gm", false)) and e.get("twist") is Dictionary:
					session.gm_reveal_twist(e["twist"])  # a human GM revealed it: narrate it in the battle
	if dialogue != null:
		dialogue.refresh()


## "Call for terms": the engine says no, with the book's reason, while the fight's in question.
func _call_for_terms() -> void:
	var r := story_engine.submit(dlg_story, dlg_campaign, {"type": "parley", "seat": _story_seat(), "params": {}})
	if not r.get("ok", false):
		_on_story_refused(str(r.get("reason", "")), str(r.get("rule_ref", "")))
		return
	if dialogue != null:
		dialogue.refresh()


func _load(v: Dictionary) -> void:
	_loaded = true
	view.set_map(BattleMap.from_dict(v.get("map", {})), BIOME)
	view.clear_units()
	for id: String in v.get("units", {}):
		var u: Dictionary = v["units"][id]
		if not u.get("hidden", false) and not u.get("destroyed", false) and _on_board(v, u):
			if not VisibleParts.is_deployable(u):
				view.add_unit(u)
	for id: String in v.get("units", {}):  # deployables after their owners (they take their colors)
		var u: Dictionary = v["units"][id]
		if VisibleParts.is_deployable(u) and not u.get("hidden", false) and not u.get("destroyed", false) and _on_board(v, u):
			view.add_unit(u)
	view.sync_parts(v.get("units", {}))
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
	_show_objectives(v)
	_refresh_hud()


func _drain() -> void:
	_draining = true
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		var events: Array = item[1]
		if not events.is_empty():
			await player.play(events)
			_narrate(events)
			_barks(events)
		_sync(item[0])
	_draining = false


## Copies what the view says onto the board: stats, new units (reinforcements, revealed
## Hidden units), units that vanished (became Hidden), then the HUD.
func _sync(v: Dictionary) -> void:
	var units: Dictionary = v.get("units", {})
	for id: String in units:
		var u: Dictionary = units[id]
		if u.get("hidden", false) or not _on_board(v, u):
			# Hidden from this seat, extracted, or a pilot inside their mech.
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
	view.sync_parts(units)  # drones out of the body, destroyed or thrown weapons, recalled units gone
	_show_objectives(v)
	_refresh_hud()


## Whether a unit stands on the board: not extracted, and a pilot only when out of their mech
## (or their mech is a wreck: Core p.74).
static func _on_board(v: Dictionary, u: Dictionary) -> bool:
	var c: Dictionary = u.get("counters", {})
	if c.has("extracted"):
		return false
	var inside := str(c.get("mounted_in", c.get("passenger_in", "")))
	if inside == "":
		return true
	return bool(v.get("units", {}).get(inside, {}).get("destroyed", false))


func _refresh_hud() -> void:
	var v := session.view
	var list: Array = []
	var my_side := _my_side()
	for id: String in v.get("units", {}):
		var u: Dictionary = v["units"][id]
		if u.get("hidden", false) or str(u.get("kind", "")) == Unit.KIND_DEPLOYABLE or not _on_board(v, u):
			continue  # objects take no turns; pilots inside their mechs and extracted mechs aren't on the board
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


## Units the people here may send next: their own, or (host) AI squadmates.
func _pickable() -> Array:
	var out: Array = []
	var mine := _local_units()
	for id: Variant in session.waiting().get("units", []):
		var u: Dictionary = session.view.get("units", {}).get(str(id), {})
		if str(id) in mine or (session.is_host and session.host.is_ai_seat(str(u.get("controller", "")))):
			out.append(str(id))
	return out


func _other_pickers() -> String:
	var names := PackedStringArray()
	var here := session.local_humans() if session.is_host else [session.seat]
	for seat: Variant in session.waiting().get("seats", []):
		if not str(seat) in here:
			names.append(str(session.view.get("seats", {}).get(str(seat), {}).get("name", seat)))
	return ", ".join(names) if not names.is_empty() else "another player"


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
	if turn.active or _draining:
		text = ""  # While events animate, the board is behind the game: say nothing yet.
	elif session.my_pick():
		if _pickable().is_empty():
			text = "Waiting for %s to say \"I'll go\"." % _other_pickers()
			if session.is_host:
				text += "  (Away? The Menu can let the AI fly their mech.)"
		else:
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


## An AI drives one of your mechs (a cascading NHP, SEKHMET, a COMP/CON): its pilot's choice
## at the start of its turn, with the options the rules leave to the pilot.
func _show_nhp(q: Dictionary) -> void:
	for c in reaction_panel.get_children():
		c.queue_free()
	if q.is_empty():
		reaction_panel.visible = not session.my_reaction().is_empty()
		if reaction_panel.visible:
			_show_reaction(session.my_reaction())
		return
	reaction_panel.visible = true
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	reaction_panel.add_child(v)
	var title: String = {"cascade": "Your NHP has cascaded", "sekhmet": "SEKHMET is in control", "compcon": "Command your COMP/CON"}.get(str(q.get("kind", "")), "Your AI")
	v.add_child(MenuTheme.heading(title, 22, MenuTheme.BAD if q.get("kind", "") == "cascade" else MenuTheme.WARN))
	var text := MenuTheme.label(str(q.get("text", "")), 16, MenuTheme.TEXT, true)
	text.custom_minimum_size = Vector2(590, 0)
	v.add_child(text)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	row.custom_minimum_size = Vector2(590, 0)
	for o: Dictionary in q.get("options", []):
		var b := Button.new()
		b.text = str(o.get("label", ""))
		b.tooltip_text = str(o.get("tip", ""))
		var action: Dictionary = o.get("action", {})
		b.pressed.connect(func() -> void:
			reaction_panel.visible = false
			session.answer_nhp(action))
		row.add_child(b)
	v.add_child(row)
	_place_reaction.call_deferred()


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
	# The player's version of the reaction (lancer-data actions: act_brace, act_overwatch).
	var act := content.get_entry("actions", "act_" + reaction)
	var trigger := BuilderModel._plain(str(act.get("trigger", ""))).replace("<br>", " ")
	var detail := BuilderModel._plain(str(act.get("detail", "")).replace("<br>", " "))
	var who_name := str(who.get("name", "Your mech"))
	var text := MenuTheme.label("%s can %s now.%s" % [who_name, reaction, "  Trigger: " + trigger if trigger != "" else ""], 16, MenuTheme.TEXT, true)
	text.custom_minimum_size = Vector2(590, 0)
	v.add_child(text)
	if detail != "":
		var d := MenuTheme.label(detail, 15, MenuTheme.MUTED, true)
		d.custom_minimum_size = Vector2(590, 0)
		v.add_child(d)
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
	_place_reaction.call_deferred()


## Sized after the new text has laid out (otherwise it keeps an old, larger size).
func _place_reaction() -> void:
	reaction_panel.size = Vector2.ZERO
	reaction_panel.reset_size()
	var vp := reaction_panel.get_viewport_rect().size
	reaction_panel.position = Vector2((vp.x - reaction_panel.size.x) / 2.0, vp.y * 0.55)


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
	while narration.visible:
		await get_tree().process_frame
	if session.is_host and MenuSession.campaign != null:
		var d := GameFlow.finish_mission(session, MenuSession.campaign, MenuSession.store, content)
		if d.get("story", false):
			MenuSession.go(self, "hub")
			return
	elif GameFlow.story_client != null:
		MenuSession.go(self, "hub")  # a friend in a story campaign: the host's debrief is at the hub
		return
	else:
		GameFlow.debrief = {"outcome": outcome, "reason": reason, "title": GameFlow.title_for(outcome), "pilots": [], "client": true}
	MenuSession.go(self, "debrief")


# --- Building the screen -------------------------------------------------------------------

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	rolls = RollPopups.new()
	ui.add_child(rolls)
	combat_log = CombatLog.new()
	ui.add_child(combat_log)
	combat_log.position = Vector2(1920 - 500, 160)
	order_bar = TurnOrderBar.new()
	ui.add_child(order_bar)
	bar = ActionBar.new()
	bar.visible = false
	ui.add_child(bar)
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
	bubbles = BattleBarks.new()
	ui.add_child(bubbles)
	ui.move_child(bubbles, 0)
	ai_go_button = Button.new()
	ai_go_button.theme = MenuTheme.theme()
	ai_go_button.text = "Let the AI go"
	ai_go_button.focus_mode = Control.FOCUS_NONE
	ai_go_button.tooltip_text = "An AI squadmate takes its turn now (the AI picks which). Or click \"I'll go\" on the one you want."
	ai_go_button.position = Vector2(1920 / 2.0 - 90, 192)
	ai_go_button.custom_minimum_size = Vector2(180, 40)
	ai_go_button.visible = false
	ai_go_button.pressed.connect(func() -> void: session.let_ai_go())
	ui.add_child(ai_go_button)
	sitrep_box = VBoxContainer.new()
	sitrep_box.add_theme_constant_override("separation", 8)
	sitrep_box.position = Vector2(1920 - 320, 1080 - 330)
	ui.add_child(sitrep_box)
	narration = NarrationPopup.new()
	narration.theme = MenuTheme.theme()
	ui.add_child(narration)
	codex = CodexPanel.new()
	tutorial = TutorialPanel.new()
	ui.add_child(tutorial)
	var menu := Button.new()
	menu.theme = MenuTheme.theme()
	menu.text = "≡  Menu"
	menu.focus_mode = Control.FOCUS_NONE
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
	var codex_dim := ColorRect.new()
	codex_dim.color = Color(0, 0, 0, 0.6)
	codex_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	codex_dim.visible = false
	ui.add_child(codex_dim)
	ui.add_child(codex)  # above everything else
	codex.visibility_changed.connect(func() -> void: codex_dim.visible = codex.visible)


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
	var p := MenuTheme.panel("Paused" if _can_pause() else "Menu", MenuTheme.ACCENT)
	p.custom_minimum_size = Vector2(520, 0)
	var b := MenuTheme.body(p)
	b.add_child(MenuTheme.label("The mission is saved after every turn. Continue it from the main menu any time.", 16, MenuTheme.MUTED, true))
	if session.is_host:
		for seat: String in session.local_seats():
			var callsign := str(session.host.state.seats.get(seat, {}).get("name", seat))
			var ai := session.host.is_ai_seat(seat)
			var toggle := Button.new()
			toggle.text = ("Take back control of %s" if ai else "Let the AI fly %s") % callsign
			toggle.custom_minimum_size = Vector2(0, 50)
			toggle.tooltip_text = "Switch any time. The AI follows the same rules and only knows what your squad knows."
			toggle.pressed.connect(func() -> void:
				session.set_ai(seat, not ai)
				if not ai and turn.active and session.host.state.unit(turn.unit_id) != null and session.host.state.unit(turn.unit_id).controller == seat:
					turn.cancel()
					turn.active = false
					bar.visible = false
				menu_layer.visible = false)
			b.add_child(toggle)
	if session.is_host:
		# A friend who dropped out: the AI can fly their mech until they reconnect.
		var table := session.host.seat_table()
		for seat: String in table:
			var row: Dictionary = table[seat]
			if row.get("where", "") == "remote" and not row.get("connected", false):
				var ai_now := session.host.is_ai_seat(seat)
				var b2 := Button.new()
				b2.text = ("Stop the AI flying %s" if ai_now else "Let the AI fly %s until %s is back") % [row.get("name", seat), row.get("player", "they")] if not ai_now else "Stop the AI flying %s (wait for %s)" % [row.get("name", seat), row.get("player", "them")]
				b2.custom_minimum_size = Vector2(0, 50)
				b2.pressed.connect(func() -> void:
					session.host.set_seat_ai(seat, not ai_now)
					menu_layer.visible = false)
				b.add_child(b2)
	if session.is_host:
		var auto := CheckButton.new()
		auto.text = "AI squadmates take their turns on their own"
		auto.button_pressed = session.host.ai_squad_auto
		auto.toggled.connect(func(on: bool) -> void: session.host.ai_squad_auto = on)
		b.add_child(auto)
	if campaign != null:
		var hints := CheckButton.new()
		hints.text = "Teaching hints (explain each rule the first time)"
		hints.button_pressed = Tutorial.hints_on(campaign)
		hints.toggled.connect(func(on: bool) -> void: campaign.options["teaching_hints"] = on)
		b.add_child(hints)
	var term := hovered_term()
	var codex_btn := Button.new()
	codex_btn.text = "Codex: look up \"%s\"" % term if term != "" else "Codex (rules reference)"
	codex_btn.custom_minimum_size = Vector2(0, 50)
	codex_btn.tooltip_text = "Search any rule, status, action, frame or piece of gear. In battle, F1 opens it on whatever you're pointing at."
	codex_btn.pressed.connect(func() -> void:
		menu_layer.visible = false
		codex.open(term))
	b.add_child(codex_btn)
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


## What the player last pointed at, for the Codex: a mech under the mouse (its frame or
## name), else the last action hovered on the action bar.
func hovered_term() -> String:
	var id := view.labels.hover_unit if view != null and view.labels != null else ""
	if id != "" and view.units.has(id):
		var u: Dictionary = (view.units[id] as MechView).unit
		var frame := content.frame(str(u.get("content_id", "")))
		return str(frame.get("name", u.get("name", ""))) if not frame.is_empty() else str(u.get("name", ""))
	return _hover_term


func _unhandled_input(ev: InputEvent) -> void:
	if _explore_click(ev):
		get_viewport().set_input_as_handled()
		return
	if gm_panel != null and ev is InputEventKey and ev.pressed and not ev.echo and (ev as InputEventKey).keycode == KEY_G:
		gm_panel.visible = not gm_panel.visible
		if gm_panel.visible:
			gm_panel.open()
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("end_turn") and ev.is_action_pressed("end_turn") and turn.active and not turn.busy:
		turn.end_turn()  # the End turn key (Settings)
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("toggle_log") and ev.is_action_pressed("toggle_log"):
		combat_log.visible = not combat_log.visible
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("codex") and ev.is_action_pressed("codex"):
		if codex.visible:
			codex.visible = false
		else:
			codex.open(hovered_term())
		get_viewport().set_input_as_handled()
	elif codex.visible and ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		codex.visible = false
		get_viewport().set_input_as_handled()


## Nobody plays from another computer, so stopping the AI keeps nobody waiting.
func _can_pause() -> bool:
	if not session.is_host:
		return false
	for seat: String in session.host.state.seats:
		if session.host.seat_table().get(seat, {}).get("where", "") == "remote":
			return false
	return true


func _leave(screen: String) -> void:
	if session.is_host and session.autosave != null and not session.over:
		session.autosave.save_now()
	if campaign != null and not session.over:
		GameFlow.save_story(campaign, MenuSession.store)  # tutorial progress, tips seen, hints
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
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("sitrep:"):  # screenshots: a given sitrep
			lobby.options["sitrep"] = "sitrep_" + a.substr(7)
			lobby.set_shape(str(lobby.options["shape"]))
	lobby.set_local_ready(true)
	var s := GameFlow.start_mission(lobby, SaveStore.new("user://example_saves"))
	return s
