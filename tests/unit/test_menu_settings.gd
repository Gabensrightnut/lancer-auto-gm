extends TestCase
## Player settings: saving, loading with bad values, key rebinding.


func test_settings_round_trip_and_clamping() -> void:
	var path := "user://test_settings_%d.cfg" % Time.get_ticks_usec()
	var s := GameSettings.load_settings(path)
	expect_eq(s.colorblind, "off")
	expect_eq(s.keybinds["end_turn"], KEY_E)
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
	expect_eq(s.rebind("end_turn", KEY_Q), "camera_left", "Q was rotate-left: they swap")
	expect_eq(s.keybinds["end_turn"], KEY_Q)
	expect_eq(s.keybinds["camera_left"], KEY_E)
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
