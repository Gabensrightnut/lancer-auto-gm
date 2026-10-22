extends Node
## Between missions in a story campaign (the tutorial is one): the story's hub (HubScene:
## walk around, briefing, job board, debrief, level up, downtime) inside the game flow. When
## the squad puts boots on the ground the job becomes a battle (GameFlow.start_story_mission);
## after it the hub opens again with the debrief. The campaign is saved after every story
## step. A Menu button (bottom left) opens the pilot builder (talent and license picks after
## leveling up), settings and Save and quit.

const HUB_SCENE := "res://scenes/explore/hub.tscn"

var campaign: Campaign
var hub: HubScene
var menu_layer: Control


func _ready() -> void:
	campaign = MenuSession.ensure_campaign()
	var db := MenuSession.content()
	if not GameFlow.is_story(campaign):
		# Opened on its own (screenshots, development): the tutorial's opening, saved apart
		# from the player's campaigns.
		MenuSession.store = SaveStore.new("user://example_saves")
		campaign = GameFlow.start_tutorial(MenuSession.store, db)
		MenuSession.campaign = campaign
	GameFlow.open_story(campaign, db)
	MenuSession.settings().apply_graphics(get_viewport())
	hub = (load(HUB_SCENE) as PackedScene).instantiate() as HubScene
	add_child(hub)
	hub.setup(GameFlow.story_engine, GameFlow.story, campaign, db, _my_seat())
	hub.mission_requested.connect(_on_mission_requested)
	hub.story_events.connect(func(_events: Array) -> void: GameFlow.save_story(campaign, MenuSession.store))
	var pending := GameFlow.story_events
	GameFlow.story_events = []
	if not pending.is_empty():
		hub._handle(pending)
	_build_menu()


## The first seat played at this screen (AI squadmates sit in the others).
func _my_seat() -> String:
	var seats := GameFlow.story.seats.keys()
	seats.sort()
	for s: String in seats:
		if not GameFlow.story.is_ai(s):
			return s
	return "p1"


func _on_mission_requested(_hook: Dictionary) -> void:
	var s := GameFlow.start_story_mission(campaign, MenuSession.content(), MenuSession.store)
	if s == null:
		hub.hud.toast("The mission couldn't start.", StoryStyle.RED)
		return
	MenuSession.go(self, "battle")


func _build_menu() -> void:
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	var menu := Button.new()
	menu.theme = MenuTheme.theme()
	menu.text = "≡  Menu"
	menu.position = Vector2(16, get_viewport().get_visible_rect().size.y - 64)
	menu.pressed.connect(_open_menu)
	ui.add_child(menu)
	menu_layer = Control.new()
	menu_layer.theme = MenuTheme.theme()
	menu_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.visible = false
	ui.add_child(menu_layer)


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
	b.add_child(MenuTheme.label("The campaign is saved after every step. Continue it from the main menu any time.", 16, MenuTheme.MUTED, true))
	var hints := CheckButton.new()
	hints.text = "Teaching hints (explain each rule the first time it comes up)"
	hints.button_pressed = Tutorial.hints_on(campaign)
	hints.toggled.connect(func(on: bool) -> void:
		campaign.options["teaching_hints"] = on
		GameFlow.save_story(campaign, MenuSession.store))
	b.add_child(hints)
	for item in [["Back to the hub", func() -> void: menu_layer.visible = false],
			["Pilot builder (talents, licenses, gear)", func() -> void: _leave("builder")],
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
	GameFlow.save_story(campaign, MenuSession.store)
	MenuSession.back_to = "hub" if screen != "main" else "main"
	if screen == "builder":
		MenuSession.builder_pilot = GameFlow.story.pilot_of_seat(_my_seat())
	MenuSession.go(self, screen)
