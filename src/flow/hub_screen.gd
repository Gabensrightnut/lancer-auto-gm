extends Node
## Between missions in a story campaign (the tutorial is one): the story's hub (HubScene:
## walk around, briefing, job board, debrief, level up, downtime) inside the game flow. When
## the squad puts boots on the ground the job becomes a battle (GameFlow.start_story_mission);
## after it the hub opens again with the debrief. The campaign is saved after every story
## step. A Menu button (bottom left) opens the pilot builder (talent and license picks after
## leveling up), invites friends online, settings and Save and quit.
##
## Online: the host's hub UI talks to a StoryHostEngine (every action goes through the
## StorySession, so friends see it); a friend's hub UI talks to their StoryClient and shows
## its mirror of the host's story, and follows the host into each battle.

const HUB_SCENE := "res://scenes/explore/hub.tscn"

var campaign: Campaign
var hub: HubScene
var menu_layer: Control
var room_label: Label
## A friend in the host's game (GameFlow.story_client).
var story_client: StoryClient
var client: NetClient
var _seat := "p1"


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
	var pending := GameFlow.story_events
	GameFlow.story_events = []
	if not pending.is_empty():
		hub._handle(pending)
	if GameFlow.story_host != null:
		session.resync()
		_show_room(GameFlow.story_host.room_code)


func _on_story_events(_events: Array) -> void:
	GameFlow.save_story(campaign, MenuSession.store)


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
	if client != null:
		client.lobby_updated.connect(_on_host_lobby)
		client.connection_lost.connect(_on_connection_lost)
	_show_room("")


## A new view of the host's story: copied into the objects the hub's panels already hold.
func _on_mirror(s: StoryState, c: Campaign, events: Array) -> void:
	var where := JSON.stringify([hub.story.hub.get("name", ""), hub.story.hub.get("seed", "")])
	copy_into(hub.story, s)
	copy_into(hub.campaign, c)
	if where != JSON.stringify([hub.story.hub.get("name", ""), hub.story.hub.get("seed", "")]):
		hub.rebuild()
	hub._handle(events)


func _on_refused(reason: String, _rule_ref: String) -> void:
	hub.hud.toast(reason, StoryStyle.RED)


## The host started the battle: follow them in.
func _on_host_lobby(data: Dictionary) -> void:
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
