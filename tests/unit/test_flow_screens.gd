extends TestCase
## Every menu and flow screen loads and its script compiles. Catches a screen breaking when an
## API it uses changes elsewhere (as when the battle HUD swapped RollDisplay for RollPopups).
## (Tests run before the scene tree starts, so screens aren't added to it here; the real-window
## playtest driver, src/flow/dev/playtest_driver.gd, runs them for real.)

const SCREENS := [
	"res://scenes/menus/main_menu.tscn", "res://scenes/menus/lobby.tscn", "res://scenes/menus/builder.tscn",
	"res://scenes/menus/settings.tscn", "res://scenes/flow/battle.tscn", "res://scenes/flow/debrief.tscn",
	"res://scenes/flow/hub.tscn",
]


func test_every_screen_compiles() -> void:
	for path: String in SCREENS:
		var packed: PackedScene = load(path)
		expect(packed != null, "%s loads" % path)
		if packed == null:
			continue
		var node := packed.instantiate()
		var script: Script = node.get_script() if node != null else null
		expect(script != null and script.can_instantiate(), "%s script compiles" % path)
		if node != null:
			node.free()
