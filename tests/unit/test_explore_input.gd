extends TestCase
## Walking around out of combat (ExploreInput): keys to directions relative to the view,
## mouse look, run and sneak speeds, jumps, and explore keys kept apart from battle keys.


func _near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.001


func test_keys_move_relative_to_where_you_look() -> void:
	expect(_near(ExploreInput.direction(0.0, 1.0, 0.0), Vector3(0, 0, -1)), "W: forward is where you look")
	expect(_near(ExploreInput.direction(0.0, -1.0, 0.0), Vector3(0, 0, 1)), "S: back")
	expect(_near(ExploreInput.direction(0.0, 0.0, 1.0), Vector3(1, 0, 0)), "D: step right")
	expect(_near(ExploreInput.direction(0.0, 0.0, -1.0), Vector3(-1, 0, 0)), "A: step left")
	expect(_near(ExploreInput.direction(PI / 2.0, 1.0, 0.0), Vector3(-1, 0, 0)), "turned left a quarter: forward is now -X")
	expect(_near(ExploreInput.direction(PI / 2.0, 0.0, 1.0), Vector3(0, 0, -1)), "and right is where forward used to be")
	expect(absf(ExploreInput.direction(0.3, 1.0, 1.0).length() - 1.0) < 0.001, "diagonals aren't faster")
	expect(_near(ExploreInput.direction(1.0, 0.0, 0.0), Vector3.ZERO), "no keys, no movement")


func test_mouse_look_and_invert() -> void:
	var v := ExploreInput.look(0.0, 0.0, Vector2(100, 0), 1.0, false)
	expect(v.x < 0.0, "mouse right turns right")
	v = ExploreInput.look(0.0, 0.0, Vector2(0, -50), 1.0, false)
	expect(v.y > 0.0, "mouse up looks up")
	expect(ExploreInput.look(0.0, 0.0, Vector2(0, -50), 1.0, true).y < 0.0, "inverted: mouse up looks down")
	var slow := ExploreInput.look(0.0, 0.0, Vector2(100, 0), 1.0, false).x
	var fast := ExploreInput.look(0.0, 0.0, Vector2(100, 0), 2.0, false).x
	expect(absf(fast - 2.0 * slow) < 0.0001, "sensitivity scales it")
	expect(ExploreInput.look(0.0, 0.0, Vector2(0, -100000), 1.0, false).y <= ExploreInput.PITCH_MAX, "can't look past straight up")


func test_run_sneak_and_jump() -> void:
	expect(ExploreInput.speed(true, false) > ExploreInput.speed(false, false), "Shift runs")
	expect(ExploreInput.speed(true, true) < ExploreInput.speed(false, false), "sneaking is slow even holding Shift")
	var h := Vector2(0.001, ExploreInput.JUMP_SPEED)
	var top := 0.0
	var steps := 0
	while (h.x > 0.0 or h.y > 0.0) and steps < 200:
		h = ExploreInput.jump_step(h.x, h.y, 1.0 / 60.0)
		top = maxf(top, h.x)
		steps += 1
	expect(top > 0.4 and top < 1.0, "a hop, not a leap (%.2f m)" % top)
	expect(steps < 120, "and you land again")


func test_explore_keys_are_their_own() -> void:
	BattleKeys.ensure()
	for a: String in ExploreInput.MOVE + ["run", "jump", "use", "turn_left", "turn_right"]:
		expect(InputMap.has_action(a), "%s is a key you can rebind" % a)
		expect_eq(BattleKeys.context(a), "explore")
	expect_eq(BattleKeys.context("cam_pan_up"), "battle")
	expect_eq(GameSettings.default_clashes(), [], "W walks in town and pans the battle camera without clashing")
	var s := GameSettings.new()
	for a: String in GameSettings.actions():
		s.keybinds[a] = int(GameSettings.actions()[a][1])
	var swapped := s.rebind("use", KEY_W)
	expect_eq(swapped, "move_forward", "rebinding swaps within walking keys")
	expect_eq(int(s.keybinds["cam_pan_up"]), KEY_W, "and leaves the battle keys alone")
	expect(not InputMap.action_get_events("use").any(func(e: InputEvent) -> bool: return e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Q), "Q doesn't use things")
