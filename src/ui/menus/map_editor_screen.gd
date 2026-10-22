extends Node
## The map editor from the main menu (scenes/menus/map_editor_screen.tscn): the editor
## (scenes/editor/map_editor.tscn) with a way back, and "Play this map": a mission on the map
## in the open missions-only campaign, or a new one (MenuSession.map_doc goes to the lobby).

const EDITOR := "res://scenes/editor/map_editor.tscn"


func _ready() -> void:
	var editor: Node = (load(EDITOR) as PackedScene).instantiate()
	add_child(editor)
	editor.play_requested.connect(_play)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var back := Button.new()
	back.theme = MenuTheme.theme()
	back.text = "‹  Main menu"
	back.focus_mode = Control.FOCUS_NONE
	back.position = Vector2(get_viewport().get_visible_rect().size.x - 200, 16)
	back.pressed.connect(func() -> void: MenuSession.go(self, "main"))
	layer.add_child(back)


func _play(doc: MapDoc) -> void:
	MenuSession.map_doc = doc
	MenuSession.lobby = null
	if MenuSession.campaign == null or GameFlow.is_story(MenuSession.campaign):
		var c := MenuSession.new_campaign("Battle on %s" % doc.name, 4, 0, "Standard")
		MenuSession.store.save_campaign(c)
		MenuSession.campaign = c
	MenuSession.go(self, "lobby")
