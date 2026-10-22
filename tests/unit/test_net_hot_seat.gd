extends TestCase
## Hot-seat: two seats at one screen, on opposite sides, each seeing only its own view.

const HIDDEN_CELL := Vector2i(1234, 5678)


class HiddenMoveHandler:
	extends ActionHandler

	func type() -> String:
		return "test_sneak"

	func validate(_s: GameState, _a: Dictionary) -> RuleResult:
		return RuleResult.allow()

	func resolve(s: GameState, a: Dictionary) -> Array[Dictionary]:
		var u := s.unit(a["actor"])
		u.cell = HIDDEN_CELL
		return [{"type": "moved", "unit": u.id, "path": [[HIDDEN_CELL.x, HIDDEN_CELL.y, 0]], "mode": "walk"}] as Array[Dictionary]


var hot: HotSeat
var handoffs: Array = []
var shown: Array = []  # [seat, view, events]


func _setup() -> void:
	var s := GameState.new(5)
	s.seats = {"blue": {"name": "Blue player", "side": "blue"}, "red": {"name": "Red player", "side": "red"}}
	for spec in [["b1", "blue"], ["r1", "red"]]:
		var u := Unit.new()
		u.id = spec[0]
		u.side = spec[1]
		u.controller = spec[1]
		s.add_unit(u)
	s.unit("r1").statuses = {"Hidden": {}}
	var engine := RulesEngine.new()
	engine.register(HiddenMoveHandler.new())
	hot = HotSeat.new(NetHost.new(s, engine), ["blue", "red"])
	handoffs.clear()
	shown.clear()
	hot.handoff_requested.connect(_on_handoff)
	hot.view_updated.connect(_on_view)


func test_start_asks_for_handoff_before_showing_anything() -> void:
	_setup()
	hot.start("blue")
	expect_eq(handoffs, [["blue", "Blue player"]])
	expect(shown.is_empty(), "nothing on screen until the player is ready")
	hot.confirm_handoff()
	expect_eq(shown.size(), 1)
	expect_eq(shown[0][0], "blue")
	expect(not shown[0][1]["units"]["r1"].has("cell"), "blue can't see red's Hidden mech")


func test_turn_change_hands_the_screen_over() -> void:
	_setup()
	hot.start("blue")
	hot.confirm_handoff()
	hot.host.state.active_unit = "b1"
	hot.submit({"type": "end_turn", "actor": "b1"})
	expect_eq(shown[-1][2][0]["type"], "turn_ended", "blue sees its own turn end first")
	hot.host.state.active_unit = "r1"
	hot.host.send_updates()
	expect_eq(handoffs[-1], ["red", "Red player"], "red's unit is up, so pass the screen")
	expect(hot.awaiting_handoff)
	var before := shown.size()
	hot.confirm_handoff()
	expect_eq(shown.size(), before + 1)
	expect_eq(shown[-1][0], "red")
	var missed: Array = shown[-1][2]
	var missed_types := missed.map(func(e): return e["type"])
	expect("turn_ended" in missed_types, "red catches up on what happened while blue played")


func test_secret_moves_stay_with_their_seat() -> void:
	_setup()
	hot.start("red")
	hot.confirm_handoff()
	hot.submit({"type": "test_sneak", "actor": "r1"})
	expect_eq(shown[-1][2][0]["type"], "moved", "red sees its own sneaky move")
	expect_eq(hot.submit({"type": "test_sneak", "actor": "b1"})["result"].ok, false, "red can't move blue's unit")
	hot.pass_to("blue")
	hot.confirm_handoff()
	expect_eq(shown[-1][0], "blue")
	expect(shown[-1][2].is_empty(), "blue never hears about the Hidden move")
	var text := JSON.stringify(shown[-1][1])
	expect(not str(HIDDEN_CELL.x) in text and not str(HIDDEN_CELL.y) in text)
	expect(not "dice_state" in text)


func test_updates_wait_while_the_screen_is_being_passed() -> void:
	_setup()
	hot.start("blue")
	hot.confirm_handoff()
	hot.pass_to("red")
	var before := shown.size()
	hot.host.send_updates([{"type": "turn_ended", "unit": "b1"}])
	expect_eq(shown.size(), before, "no view drawn while the handoff screen is up")
	hot.confirm_handoff()
	expect_eq(shown[-1][0], "red")
	expect_eq(shown[-1][2].size(), 1)



func _on_handoff(seat: String, name: String) -> void:
	handoffs.append([seat, name])


func _on_view(seat: String, view: Dictionary, events: Array) -> void:
	shown.append([seat, view, events])
