extends TestCase
## Player settings: saving, loading with bad values, key rebinding.


func test_settings_round_trip_and_clamping() -> void:
	var path := "user://test_settings_%d.cfg" % Time.get_ticks_usec()
	var s := GameSettings.load_settings(path)
	expect_eq(s.colorblind, "off")
	expect_eq(s.keybinds["end_turn"], KEY_X)
	s.ui_scale = 1.25
	s.colorblind = "tritanopia"
	s.animation_speed = "fast"
	s.popup_duration = 1.5
	expect_eq(s.save(path), OK)
	var back := GameSettings.load_settings(path)
	expect_eq(back.ui_scale, 1.25)
	expect_eq(back.colorblind, "tritanopia")
	expect_eq(back.animation_speed, "fast")
	expect_eq(back.popup_duration, 1.5)
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("display", "ui_scale", 9.0)
	cfg.set_value("graphics", "preset", "potato")
	cfg.save(path)
	var odd := GameSettings.load_settings(path)
	expect_eq(odd.ui_scale, 1.5, "clamped")
	expect_eq(odd.graphics, "high", "unknown values fall back")
	DirAccess.remove_absolute(path)


func test_rebinding_swaps_instead_of_leaving_a_hole() -> void:
	var s := GameSettings.load_settings("user://does_not_exist.cfg")
	expect_eq(s.rebind("end_turn", KEY_Q), "cam_rotate_left", "Q was rotate-left: they swap")
	expect_eq(s.keybinds["end_turn"], KEY_Q)
	expect_eq(s.keybinds["cam_rotate_left"], KEY_X)
	expect_eq(s.rebind("end_turn", KEY_F5), "")
	s.apply_keys()
	expect(InputMap.has_action("end_turn"))
	expect_eq((InputMap.action_get_events("end_turn")[0] as InputEventKey).physical_keycode, KEY_F5)


func test_graphics_preset_drives_world_quality() -> void:
	var path := "user://test_gfx_%d.cfg" % Time.get_ticks_usec()
	var s := GameSettings.load_settings(path)
	expect_eq(s.graphics, GameSettings.default_graphics(), "a new install gets the suggested preset")
	expect(s.graphics in WorldQuality.PRESETS)
	expect_eq(GameSettings.GRAPHICS.size(), WorldQuality.PRESETS.size(), "every menu choice is a WorldQuality preset")
	s.graphics = "low"
	expect_eq(s.save(path), OK)
	var back := GameSettings.load_settings(path)
	expect_eq(back.graphics, "low", "the choice is saved")
	back.apply_graphics(null)
	expect_eq(WorldQuality.preset, "low")
	var cfg := ConfigFile.new()
	cfg.load(path)
	cfg.set_value("graphics", "preset", "ultra")
	cfg.save(path)
	expect_eq(GameSettings.load_settings(path).graphics, "high", "the old Ultra setting becomes High")
	WorldQuality.set_preset("high")
	DirAccess.remove_absolute(path)


## Every key in data/game/keybinds.json can be rebound, and no two defaults share a key.
func test_every_battle_key_is_rebindable_and_none_clash() -> void:
	var s := GameSettings.load_settings("user://does_not_exist.cfg")
	for a: String in BattleKeys.defaults():
		expect(s.keybinds.has(a), "%s is in Settings" % a)
	expect_eq(GameSettings.default_clashes(), [], "no default clashes")
	s.apply_keys()
	var up := InputMap.action_get_events("cam_pan_up").map(func(e: InputEventKey) -> int: return e.physical_keycode)
	expect(up.has(KEY_W) and up.has(KEY_UP), "second keys (arrows) stay")


func test_old_saved_keys_are_dropped_once() -> void:
	var path := "user://test_old_keys_%d.cfg" % Time.get_ticks_usec()
	var cfg := ConfigFile.new()
	cfg.set_value("keys", "end_turn", KEY_E)  # the old default, now rotate right
	cfg.save(path)
	expect_eq(GameSettings.load_settings(path).keybinds["end_turn"], KEY_X, "no clash with camera rotate right")
	DirAccess.remove_absolute(path)


## Exploring has its own keys (keybinds.json "context": "explore", story's actions): W walks
## forward and also pans the battle camera; a clash only counts within the same context.
func test_keys_by_context() -> void:
	var s := GameSettings.load_settings("user://does_not_exist.cfg")
	expect_eq(GameSettings.context_of("move_forward"), "explore")
	expect_eq(GameSettings.context_of("cam_pan_up"), "battle")
	expect_eq(GameSettings.context_of("confirm"), "both")
	s.keybinds["move_forward"] = KEY_W
	s.keybinds["cam_pan_up"] = KEY_W
	expect(not s.conflicts().has("move_forward"), "W walks (exploring) and pans (battle): no clash")
	var other := ""
	for a: String in s.keybinds:
		if a != "move_forward" and GameSettings.context_of(a) == "explore":
			other = a
			break
	expect_eq(s.rebind(other, KEY_W), "move_forward", "the same key in the same context: they swap")
	expect_eq(s.keybinds["cam_pan_up"], KEY_W, "the battle's W is untouched")
	s.keybinds["move_forward"] = KEY_W  # a file edited by hand
	expect(s.conflicts().has(other) and s.conflicts()[other].has("move_forward"), "flagged")
