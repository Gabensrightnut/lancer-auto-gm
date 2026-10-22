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
