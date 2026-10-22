extends Node
## Between missions in a story campaign (the tutorial is one): the story's hub (HubScene:
## walk around, briefing, job board, debrief, level up, downtime) inside the game flow. When
## the squad puts boots on the ground the job becomes a battle (GameFlow.start_story_mission);
## after it the hub opens again with the debrief. The campaign is saved after every story
## step. The Menu (button bottom left, or Esc) opens the pilot builder (talent and license
## picks after leveling up), invites friends online, retires the squad (ends the campaign),
## settings and Save and quit. When the campaign ends the story's EpilogueScreen shows; from it
## the same pilots can start a new campaign (GameFlow.start_sequel) or go back to the menu.
##
## Online: the host's hub UI talks to a StoryHostEngine (every action goes through the
## StorySession, so friends see it); a friend's hub UI talks to their StoryClient and shows
## its mirror of the host's story, and follows the host into each battle. Where everyone's
## pilot is walking is shared too (cosmetic, not game state): each screen sends its own pilot's
## spot a few times a second ({"hub_pos": [x, z, facing]}), the host passes them on to everyone,
## and other players' pilots glide to where their player has them.

const HUB_SCENE := "res://scenes/explore/hub.tscn"
## Seconds between position updates sent.
const SEND_EVERY := 0.15

var campaign: Campaign
var hub: HubScene
var menu_layer: Control
var room_label: Label
## A friend in the host's game (GameFlow.story_client).
var story_client: StoryClient
var client: NetClient
var _seat := "p1"
var _send_left := 0.0
var _last_sent: Array = []
## seat -> [Vector3, facing] where other players' pilots are heading.
var _targets: Dictionary = {}


func _ready() -> void:
	var db := MenuSession.content()
	MenuSession.settings().apply_graphics(get_viewport())
	_build_menu()
	if GameFlow.story_client != null:
		_ready_as_friend(db)
		return
	campaign = MenuSession.ensure_campaign()
	if not GameFlow.is_story(campaign):
		# Opened on its own (screenshots, development): the tutorial's opening, saved apart
		# from the player's campaigns.
		MenuSession.store = SaveStore.new("user://example_saves")
		campaign = GameFlow.start_tutorial(MenuSession.store, db)
		MenuSession.campaign = campaign
	GameFlow.open_story(campaign, db)
	_seat = _my_seat()
	var session := GameFlow.open_story_session(campaign, db, [_seat])
	hub = (load(HUB_SCENE) as PackedScene).instantiate() as HubScene
	add_child(hub)
	move_child(hub, 0)
	hub.setup(StoryHostEngine.new(db, session), GameFlow.story, campaign, db, _seat)
	hub.mission_requested.connect(_on_mission_requested)
	hub.story_events.connect(_on_story_events)
	_hook_epilogue()
	var pending := GameFlow.story_events
	GameFlow.story_events = []
	if not pending.is_empty():
		hub._handle(pending)
	if GameFlow.story_host != null:
		session.resync()
		_show_room(GameFlow.story_host.room_code)
		_listen_as_host()
	_show_ending_if_over()
	# Screenshot staging: the menu (stage:menu) or the squad retired (stage:retire).
	if "stage:menu" in OS.get_cmdline_user_args():
		_open_menu.call_deferred()
	elif "stage:retire" in OS.get_cmdline_user_args():
		_retire.call_deferred()


func _on_story_events(events: Array) -> void:
	GameFlow.save_story(campaign, MenuSession.store)
	if events.any(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "campaign_ended"):
		hub.tutorial_panel.visible = false


## The epilogue's buttons go through the flow: "New campaign with the same pilots" saves and
## opens the sequel (the hub's own handler would leave it unsaved); "Main menu" leaves.
func _hook_epilogue() -> void:
	hub.menu_requested.connect(_on_menu_requested)
	if hub.epilogue.sequel_requested.is_connected(hub._sequel):
		hub.epilogue.sequel_requested.disconnect(hub._sequel)
	hub.epilogue.sequel_requested.connect(_on_sequel)


func _show_ending_if_over() -> void:
	var ending: Dictionary = hub.story.flags.get(Ending.KEY, {})
	if hub.story.phase == "ending" and not ending.is_empty():
		hub.epilogue.show_ending(ending)
		hub.tutorial_panel.visible = false


func _on_menu_requested() -> void:
	_leave("main")


func _on_sequel() -> void:
	if story_client != null:
		hub.hud.toast("The host starts the next campaign. Join their new room when they invite you.", StoryStyle.BLUE)
		return
	var net := MenuSession.net(self)
	if net != null and GameFlow.story_host != null:
		net.leave()  # the new campaign gets its own room (Invite friends online again)
	var c := GameFlow.start_sequel(campaign, MenuSession.store, MenuSession.content())
	MenuSession.campaign = c
	MenuSession.go(self, "hub")


## Ends the campaign now (StoryEngine end_campaign): the epilogue follows.
func _retire() -> void:
	menu_layer.visible = false
	var r := hub.engine.submit(hub.story, campaign, {"type": "end_campaign", "seat": "gm", "params": {}})
	if not r.get("ok", false):
		hub.hud.toast(str(r.get("reason", "")), StoryStyle.RED)
		return
	hub._handle(r.get("events", []))


func _confirm_retire() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "Retire the squad?"
	dlg.dialog_text = "This ends the campaign here. Every pilot gets an epilogue, and afterwards the same pilots can start a new campaign. The campaign can't be continued after this."
	dlg.ok_button_text = "Retire the squad"
	dlg.theme = MenuTheme.theme()
	dlg.confirmed.connect(_retire)
	dlg.visibility_changed.connect(func() -> void:
		if not dlg.visible:
			dlg.queue_free())
	add_child(dlg)
	dlg.popup_centered(Vector2i(620, 220))


## Esc opens the menu when nothing in the hub is open (the hub closes its own panels first).
func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE) or hub == null:
		return
	if menu_layer.visible:
		menu_layer.visible = false
		get_viewport().set_input_as_handled()
	elif not (hub.dialogue.visible or hub.downtime_screen.visible or hub.gear_panel.visible or hub.hud.board_open() or hub.epilogue.visible or hub.level_panel.visible):
		_open_menu()
		get_viewport().set_input_as_handled()


## The first seat played at this screen (AI squadmates and friends sit in the others).
func _my_seat() -> String:
	var seats := GameFlow.story.seats.keys()
	seats.sort()
	for s: String in seats:
		if not GameFlow.story.is_ai(s):
			return s
	return "p1"


func _on_mission_requested(_hook: Dictionary) -> void:
	if story_client != null:
		return  # The host starts the battle; everyone follows.
	var s := GameFlow.start_story_mission(campaign, MenuSession.content(), MenuSession.store, [_seat])
	if s == null:
		hub.hud.toast("The mission couldn't start.", StoryStyle.RED)
		return
	var net := MenuSession.net(self)
	if net != null and GameFlow.story_host != null:
		net.host = s.host  # keeps the room open; the battle drives the AI itself
		net.director = null
	MenuSession.go(self, "battle")


# --- A friend in the host's game -------------------------------------------------------------

func _ready_as_friend(db: ContentDB) -> void:
	story_client = GameFlow.story_client
	var net := MenuSession.net(self)
	client = net.client if net != null else null
	_seat = story_client.seat
	if story_client.story == null:
		await story_client.mirror_changed
	campaign = story_client.campaign
	MenuSession.campaign = campaign
	hub = (load(HUB_SCENE) as PackedScene).instantiate() as HubScene
	add_child(hub)
	move_child(hub, 0)
	hub.setup(story_client, story_client.story, campaign, db, _seat)
	story_client.mirror_changed.connect(_on_mirror)
	story_client.refused.connect(_on_refused)
	_hook_epilogue()
	_show_ending_if_over()
	if client != null:
		client.lobby_updated.connect(_on_host_lobby)
		client.connection_lost.connect(_on_connection_lost)
	_show_room("")


## The host's room: friends' walking positions come in through the lobby channel.
func _listen_as_host() -> void:
	if not GameFlow.story_host.lobby_message.is_connected(_on_friend_message):
		GameFlow.story_host.lobby_message.connect(_on_friend_message)


func _on_friend_message(seat: String, msg: Dictionary) -> void:
	var at := HubScreenPositions.parse(msg.get("hub_pos"))
	if at.is_empty() or seat == _seat:
		return
	_targets[seat] = at
	GameFlow.story_host.send_lobby({"hub_pos": {seat: msg["hub_pos"]}})


## Everyone's pilots on the host's screen and the friends' (the host passes each one on).
func _process(delta: float) -> void:
	if hub == null or hub.avatars.is_empty() or (story_client == null and GameFlow.story_host == null):
		return
	_send_left -= delta
	if _send_left <= 0.0:
		_send_left = SEND_EVERY
		_send_position()
	for seat: String in _targets:
		var fig: PilotFigure = hub.avatars.get(seat)
		if fig == null or seat == _seat:
			continue
		var goal: Array = _targets[seat]
		var pos: Vector3 = fig.position.move_toward(goal[0], HubScene.WALK_SPEED * 1.4 * delta)
		hub.set_avatar_position(seat, pos, lerp_angle(fig.rotation.y, float(goal[1]), 0.3))


func _send_position() -> void:
	var me: PilotFigure = hub.avatars.get(_seat)
	if me == null:
		return
	var data := HubScreenPositions.pack(me.position, me.rotation.y)
	if data == _last_sent:
		return
	_last_sent = data
	if story_client != null:
		if client != null:
			client.transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.LOBBY, "hub_pos": data})
	else:
		GameFlow.story_host.send_lobby({"hub_pos": {_seat: data}})


## A new view of the host's story: copied into the objects the hub's panels already hold.
func _on_mirror(s: StoryState, c: Campaign, events: Array) -> void:
	var where := JSON.stringify([hub.story.hub.get("name", ""), hub.story.hub.get("seed", "")])
	copy_into(hub.story, s)
	copy_into(hub.campaign, c)
	if where != JSON.stringify([hub.story.hub.get("name", ""), hub.story.hub.get("seed", "")]):
		hub.rebuild()
	hub._handle(events)
	if hub.story.phase == "ending":
		hub.tutorial_panel.visible = false


func _on_refused(reason: String, _rule_ref: String) -> void:
	hub.hud.toast(reason, StoryStyle.RED)


## The host started the battle: follow them in.
func _on_host_lobby(data: Dictionary) -> void:
	if data.get("hub_pos") is Dictionary:
		for seat: String in data["hub_pos"]:
			var at := HubScreenPositions.parse(data["hub_pos"][seat])
			if not at.is_empty() and seat != _seat:
				_targets[seat] = at
		return
	if data.get("started", false) and client != null:
		GameFlow.session = BattleSession.for_client(client)
		MenuSession.go(self, "battle")


func _on_connection_lost(_retrying: bool) -> void:
	if hub != null:
		hub.hud.toast("Lost the connection to the host. Rejoin from Join online.", StoryStyle.RED)


## Copies every script variable of `src` onto `dst` (same class), keeping `dst` the object
## other code holds.
static func copy_into(dst: Object, src: Object) -> void:
	for prop: Dictionary in src.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			dst.set(prop["name"], src.get(prop["name"]))


# --- Menu ------------------------------------------------------------------------------------

func _build_menu() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var row := HBoxContainer.new()
	row.theme = MenuTheme.theme()
	row.add_theme_constant_override("separation", 14)
	row.position = Vector2(16, get_viewport().get_visible_rect().size.y - 64)
	ui.add_child(row)
	var menu := Button.new()
	menu.text = "≡  Menu"
	menu.pressed.connect(_open_menu)
	row.add_child(menu)
	room_label = MenuTheme.label("", 17, MenuTheme.TEXT)
	room_label.add_theme_constant_override("outline_size", 6)
	room_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	row.add_child(room_label)
	menu_layer = Control.new()
	menu_layer.theme = MenuTheme.theme()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.visible = false
	ui.add_child(menu_layer)


func _show_room(code: String) -> void:
	if story_client != null:
		room_label.text = "Playing in the host's game"
	elif code != "":
		room_label.text = "Room code:  %s   (friends pick Join online and type it)" % code


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
	var p := MenuTheme.panel("Menu", MenuTheme.ACCENT)
	p.custom_minimum_size = Vector2(520, 0)
	var b := MenuTheme.body(p)
	var items: Array = [["Back to the hub", func() -> void: menu_layer.visible = false],
		["Pilot builder (talents, licenses, gear)", func() -> void: _leave("builder")]]
	if story_client != null:
		b.add_child(MenuTheme.label("The host keeps the campaign. Your pilot's build is checked and saved by the host.", 16, MenuTheme.MUTED, true))
		items.append(["Settings", func() -> void: _leave("settings")])
		items.append(["Leave the game", func() -> void: _leave("main")])
	else:
		b.add_child(MenuTheme.label("The campaign is saved after every step. Continue it from the main menu any time.", 16, MenuTheme.MUTED, true))
		var hints := CheckButton.new()
		hints.text = "Teaching hints (explain each rule the first time it comes up)"
		hints.button_pressed = Tutorial.hints_on(campaign)
		hints.toggled.connect(func(on: bool) -> void:
			campaign.options["teaching_hints"] = on
			GameFlow.save_story(campaign, MenuSession.store))
		b.add_child(hints)
		if GameFlow.story_host == null:
			items.append(["Invite friends online", _host_online])
		items.append(["Settings", func() -> void: _leave("settings")])
		items.append(["Save and quit to main menu", func() -> void: _leave("main")])
	for item: Array in items:
		var btn := Button.new()
		btn.text = item[0]
		btn.custom_minimum_size = Vector2(0, 50)
		btn.pressed.connect(item[1])
		b.add_child(btn)
	if story_client == null and hub.story.phase != "ending":
		var why := GameFlow.retire_refusal(campaign)
		var retire := Button.new()
		retire.text = "Retire the squad (end the campaign)"
		retire.custom_minimum_size = Vector2(0, 50)
		retire.add_theme_color_override("font_color", MenuTheme.WARN)
		retire.disabled = not why.is_empty()
		retire.tooltip_text = str(why.get("reason", "")) if not why.is_empty() else "End the campaign here: an epilogue for every pilot, then the same pilots can start a new campaign."
		retire.pressed.connect(_confirm_retire)
		b.add_child(retire)
	center.add_child(p)
	menu_layer.visible = true


## Opens a room: friends who join take AI squadmates' seats.
func _host_online() -> void:
	menu_layer.visible = false
	var net := MenuSession.net(self)
	if net == null or not net.online_available():
		room_label.text = "Online play isn't available in this build."
		return
	var host := GameFlow.host_story_online(campaign, MenuSession.content(), MenuSession.store, [_seat])
	net.host = host
	host.room_opened.connect(_show_room)
	_listen_as_host()
	host.open_failed.connect(func(why: String) -> void: room_label.text = why)
	room_label.text = "Opening a room..."
	net.open_online(host)


func _leave(screen: String) -> void:
	if story_client == null:
		GameFlow.save_story(campaign, MenuSession.store)
	MenuSession.back_to = "hub" if screen != "main" else "main"
	if screen == "builder":
		MenuSession.builder_pilot = hub.story.pilot_of_seat(_seat)
	if screen == "main":
		var net := MenuSession.net(self)
		if net != null and (story_client != null or GameFlow.story_host != null):
			net.leave()
		GameFlow.leave_story_online()
	MenuSession.go(self, screen)
