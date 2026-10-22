extends TestCase
## Heat, stress and structure tables, Stabilize, Brace, Hide/Search, Scan, Invade, burn,
## dangerous terrain, Shut Down.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup() -> void:
	s = F.state()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", Vector2i(3, 0))
	F.begin(e, s, a)


func _next_turn(u: Unit) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_overheating_takes_stress_and_rolls_the_table() -> void:
	_setup()
	F.load_dice(s, [6])
	var ev := Combat.apply_heat(s, a, 7, "test")
	expect_eq(a.stress, 3)
	expect_eq(a.heat, 0, "all heat cleared")
	var types: Array = ev.map(func(x: Dictionary) -> String: return x["type"])
	expect(types.has("stress_check"))
	expect(a.has_status("Impaired"), "5-6: Emergency Shunt")


func test_stress_results() -> void:
	_setup()
	a.stress = 3
	F.load_dice(s, [3])
	Combat.stress_check(s, a)
	expect(a.has_status("Exposed"), "2-4: Destabilized Power Plant")
	a.statuses.clear()
	a.stress = 2
	F.load_dice(s, [1, 1])
	var ev := Combat.stress_check(s, a)
	expect_eq(ev[0]["outcome"], "Irreversible Meltdown", "two 1s")
	expect(a.counters.has("meltdown"))
	F.act(e, s, "end_turn", "a")
	_next_turn(a)
	F.act(e, s, "end_turn", "a")
	expect(a.destroyed, "meltdown at the end of the next turn")


func test_danger_zone_from_heat() -> void:
	_setup()
	Combat.apply_heat(s, a, 3, "test")
	expect(a.has_status("Danger Zone"), "half heat cap")


func test_no_heat_cap_takes_energy_damage() -> void:
	_setup()
	t.heat_cap = 0
	Combat.apply_heat(s, t, 3, "a")
	expect_eq(t.hp, 7)
	expect_eq(t.heat, 0)


func test_structure_results() -> void:
	_setup()
	t.structure = 3
	F.load_dice(s, [1, 6])
	Combat.structure_check(s, t)
	expect(t.has_status("Stunned"), "Direct Hit with 3 structure: Stunned")
	t.statuses.clear()
	t.structure = 2
	F.load_dice(s, [6, 6, 2])  # marked 2: lowest 6? no: dice [6, 6] -> Glancing; use explicit
	t.structure = 2
	F.load_dice(s, [1, 4, 3])  # lowest 1 -> Direct Hit; Hull check d20 3 fails
	Combat.structure_check(s, t)
	expect(t.destroyed, "Direct Hit at 2 structure + failed Hull check")


func test_crushing_hit_and_system_trauma() -> void:
	_setup()
	t.structure = 2
	F.load_dice(s, [1, 1])
	Combat.structure_check(s, t)
	expect(t.destroyed, "two 1s: Crushing Hit")
	var t2 := F.mech(s, "t2", "enemies", Vector2i(5, 5))
	t2.structure = 3
	F.load_dice(s, [3, 2])  # System Trauma, sub-roll 2: a mount's weapons
	var ev := Combat.structure_check(s, t2)
	expect_eq(ev[0]["outcome"], "System Trauma")
	expect(Weapons.state_of(t2, Weapons.find(t2, "0:0"))["destroyed"])


func test_stabilize_cool_and_repair() -> void:
	_setup()
	a.heat = 4
	a.statuses["Exposed"] = {"source": "x"}
	a.burn = 2
	expect(F.ok(F.act(e, s, "stabilize", "a", {"main": "cool", "extra": "clear_burn"})))
	expect_eq(a.heat, 0)
	expect(not a.has_status("Exposed"))
	expect_eq(a.burn, 0)
	_next_turn(a)
	a.hp = 2
	a.statuses["Impaired"] = {"source": "t"}
	expect(F.ok(F.act(e, s, "stabilize", "a", {"main": "repair", "extra": "clear_condition", "condition": "Impaired"})))
	expect_eq(a.hp, 10)
	expect_eq(a.repairs, 3)
	expect(not a.has_status("Impaired"))


func test_brace_policy_resists_the_hit_and_limits_next_turn() -> void:
	_setup()
	F.act(e, s, "set_brace_policy", "t", {"policy": "on_structure"})
	t.hp = 4
	F.load_dice(s, [15, 6])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "reaction").size(), 1)
	expect_eq(t.hp, 1, "Brace: 6 damage halved to 3")
	expect(t.has_status("Braced"))
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "t")["difficulty"], 1, "+1 Difficulty on other attacks")
	_next_turn(t)
	expect(F.ok(F.act(e, s, "lock_on", "t", {"target": "a"})))
	expect(not F.ok(F.act(e, s, "boost", "t", {"to": [4, 1]})), "only one quick action")
	expect(not F.ok(F.act(e, s, "move", "t", {"to": [4, 1]})), "no normal movement")
	F.act(e, s, "end_turn", "t")
	expect(not t.has_status("Braced"), "ends at the end of its next turn")


func test_hide_needs_no_line_of_sight_and_breaks_on_attack() -> void:
	_setup()
	expect(not F.ok(F.act(e, s, "hide", "a")), "the enemy can see you")
	s.map.set_column(Vector2i(1, 0), 3)
	s.map.set_column(Vector2i(1, 1), 3)
	expect(F.ok(F.act(e, s, "hide", "a")))
	expect(a.has_status("Hidden"))
	var view := ViewFilter.new().view_for(s, "enemy_seat") if false else {}
	s.seats = {"enemy_seat": {"side": "enemies"}}
	view = ViewFilter.new().view_for(s, "enemy_seat")
	expect(view["units"]["a"].get("hidden", false), "hidden from the enemy's view")
	expect(not RulesQueries.attack_preview(s, "t", "0:0", "a")["ok"], "can't be targeted")
	# The enemy walks around the wall: line of sight, Hidden is lost.
	t.cell = Vector2i(0, 3)
	Combat.after_movement(s)
	expect(not a.has_status("Hidden"))


func test_search_finds_hidden() -> void:
	_setup()
	t.statuses["Hidden"] = {"source": "t"}
	F.load_dice(s, [15, 3])
	var out := F.act(e, s, "search", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(F.events_of(out, "searched")[0]["found"])
	expect(not t.has_status("Hidden"))


func test_scan_reveals_stats_to_the_side() -> void:
	_setup()
	s.seats = {"p": {"side": "players"}}
	var f := ViewFilter.new()
	expect(not f.view_for(s, "p")["units"]["t"].has("hp"))
	expect(F.ok(F.act(e, s, "scan", "a", {"target": "t"})))
	expect_eq(f.view_for(s, "p")["units"]["t"]["hp"], 10)
	expect(GameState.from_dict(s.to_dict()).intel["players"].has("t"), "intel is saved with the game")


func test_invade_heat_impaired_slowed() -> void:
	_setup()
	F.load_dice(s, [15])
	var out := F.act(e, s, "invade", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "tech_attack")[0]["result"], "hit")
	expect_eq(t.heat, 2)
	expect(t.has_status("Impaired") and t.has_status("Slowed"))
	expect(F.ok(F.act(e, s, "lock_on", "a", {"target": "t"})), "a different Quick Tech option")
	expect(not F.ok(F.act(e, s, "invade", "a", {"target": "t"})), "no quick actions left")
	_next_turn(t)
	F.act(e, s, "end_turn", "t")
	expect(not t.has_status("Impaired"), "until the end of its next turn")


func test_jammed_cannot_use_tech() -> void:
	_setup()
	a.statuses["Jammed"] = {"source": "x"}
	expect(not F.ok(F.act(e, s, "lock_on", "a", {"target": "t"})))


func test_burn_at_end_of_turn() -> void:
	_setup()
	Combat.deal_damage(s, a, [{"type": "Burn", "amount": 2}], {"source": "x"})
	expect_eq(a.hp, 8)
	expect_eq(a.burn, 2)
	F.load_dice(s, [3])  # failed Engineering check
	F.act(e, s, "end_turn", "a")
	expect_eq(a.hp, 6, "takes the marked burn again")
	expect_eq(a.burn, 2, "and it stays marked")


func test_dangerous_terrain_end_of_turn() -> void:
	_setup()
	s.map.set_column(Vector2i(0, 0), 0, PackedStringArray([BattleMap.TAG_DANGEROUS]))
	F.load_dice(s, [2])
	F.act(e, s, "end_turn", "a")
	expect_eq(a.hp, 5)


func test_shut_down_and_boot_up() -> void:
	_setup()
	a.heat = 5
	a.statuses["Lock On"] = {"source": "t"}
	expect(F.ok(F.act(e, s, "shut_down", "a")))
	expect_eq(a.heat, 0)
	expect(not a.has_status("Lock On"))
	expect(a.has_status("Stunned"))
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [0, 1]})))
	_next_turn(t)
	expect(not F.ok(F.act(e, s, "lock_on", "t", {"target": "a"})), "immune to tech while shut down")
	_next_turn(a)
	expect(F.ok(F.act(e, s, "boot_up", "a")))
	expect(not a.has_status("Stunned"))


func test_hidden_unit_moves_are_filtered_from_enemy_events() -> void:
	_setup()
	s.seats = {"enemy_seat": {"side": "enemies"}}
	a.statuses["Hidden"] = {"source": "a"}
	var events := [{"type": "moved", "unit": "a", "path": []}, {"type": "hp_changed", "unit": "t", "hp": 3}]
	var seen := ViewFilter.new().events_for(s, "enemy_seat", events)
	expect_eq(seen.size(), 1)
	expect_eq(seen[0]["hp"], 3, "own unit's HP visible")
