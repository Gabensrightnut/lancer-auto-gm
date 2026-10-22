extends TestCase
## Mechs an AI drives by its own rules (NhpAi): a cascading NHP (the pilot may still Shut Down),
## SEKHMET (charges the closest visible character, never shoots), COMP/CON (follows its pilot's
## command). The pilot's seat answers at the start of the turn; an AI pilot answers itself.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


## A battle with p1 played here (unless `p1_ai`) and everyone else AI, in combat, p1's turn.
func _battle(p1_ai: bool = false) -> Dictionary:
	var gen := MissionGenerator.generate(808, {"db": MissionTest.db(), "size": 20, "players": 2, "sitrep": "sitrep_standardcombat", "weather": "clear", "environments": []})
	var state: GameState = gen["state"]
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), gen["mission"])
	if p1_ai:
		host.set_seat_ai("p1", true)
	else:
		host.add_local_seat("p1")
	host.set_seat_ai("p2", true)
	host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": Mission.PLAYERS}})
	return {"state": state, "host": host, "director": director, "u": state.unit("p1")}


static func _cascade(state: GameState, u: Unit) -> void:
	u.loadout["ai"] = {"source": "ms_test_nhp", "cascade": true}
	u.counters["cascade"] = {"controller": u.controller}
	u.controller = "gm"
	u.counters["ai_control"] = true
	Combat.add_status(state, u, "Cascading", "NHP")


func test_cascade_pilot_can_still_shut_down() -> void:
	var b := _battle()
	var host: NetHost = b["host"]
	var u: Unit = b["u"]
	_cascade(b["state"], u)
	expect((host.submit("p1", {"type": "start_turn", "actor": "p1"})["result"] as RuleResult).ok, "the pilot's seat still picks its activation")
	var w := host.waiting_on("p1")
	expect_eq(w["state"], "nhp")
	expect(w["you"], "the question goes to the pilot's seat")
	expect_eq(w["question"]["kind"], "cascade")
	expect_eq((w["question"]["options"] as Array).map(func(o: Dictionary) -> String: return o["label"]), ["Shut Down", "Let it act"])
	expect(not host.waiting_on("p2").has("question"), "others just see who's deciding")
	var move := host.submit("p1", {"type": "move", "actor": "p1", "params": {"to": [u.cell.x, u.cell.y + 1]}})
	expect(not (move["result"] as RuleResult).ok, "the NHP has the controls")
	expect(not (host.submit("p2", {"type": "shut_down", "actor": "p1"})["result"] as RuleResult).ok, "only the pilot's own seat")
	var off := host.submit("p1", {"type": "shut_down", "actor": "p1", "params": {}})
	expect((off["result"] as RuleResult).ok, str((off["result"] as RuleResult).reason))
	expect(not AISystems.cascading(u), "stabilized")
	expect_eq(u.controller, "p1", "back to its pilot")
	expect(u.has_status("Shut Down"))


func test_cascade_let_it_act_then_the_ai_plays_it() -> void:
	var b := _battle()
	var host: NetHost = b["host"]
	var u: Unit = b["u"]
	_cascade(b["state"], u)
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	expect(not b["director"].step(), "the AI waits for the pilot's answer")
	expect((host.submit("p1", {"type": "nhp_answer", "actor": "p1", "params": {}})["result"] as RuleResult).ok)
	expect_eq(host.waiting_on("p1")["state"], "turn")
	expect(b["director"].step(), "now the AI plays the cascading mech")
	expect(b["state"].active_unit != "p1", "its turn was played and ended")
	expect(AISystems.cascading(u), "still cascading: nobody Shut it Down")


func test_an_ai_pilot_shuts_a_cascade_down() -> void:
	var b := _battle(true)
	var host: NetHost = b["host"]
	var u: Unit = b["u"]
	_cascade(b["state"], u)
	host.submit_ai({"type": "start_turn", "actor": "p1"})
	expect(b["director"].step())
	expect(not AISystems.cascading(u), "the AI pilot took the safe choice")


func test_sekhmet_charges_the_closest_character_friend_or_foe() -> void:
	var b := _battle()
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var u: Unit = b["u"]
	u.loadout["ai"] = {"source": NhpAi.SEKHMET, "cascade": true}
	u.counters["ai_control"] = true
	expect_eq(NhpAi.kind(u), "sekhmet")
	var ally: Unit = state.unit("p2")
	var know := AiKnowledge.for_side(state, host.view_filter, u.side)
	var plan := NhpAi.plan_sekhmet(know, "p1")
	var closest := NhpAi._closest_character(state, u)
	expect(closest != null)
	expect(plan["steps"].all(func(a: Dictionary) -> bool: return a["type"] in ["move", "boost", "skirmish"]), str(plan["steps"]))
	for a: Dictionary in plan["steps"]:
		if a["type"] == "skirmish":
			expect(Weapons.is_melee(Weapons.find(u, str(a["params"]["weapon"]))), "melee only, never ranged")
	if closest == ally:
		expect(str(plan["log"]).contains("an ally"), "SEKHMET doesn't care whose side they're on: %s" % plan["log"])
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	var q := host.nhp_question()
	expect_eq(q.get("kind", ""), "sekhmet")
	host.submit("p1", {"type": "nhp_answer", "actor": "p1", "params": {}})
	var before := state.map.grid.distance(u.cell, closest.cell)
	expect(b["director"].step(), "the director plays SEKHMET's turn")
	expect(state.map.grid.distance(u.cell, closest.cell) <= before, "it closed in on %s" % closest.name)


func test_compcon_follows_its_pilots_command() -> void:
	var b := _battle()
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var u: Unit = b["u"]
	u.loadout["ai"] = {"source": NhpAi.COMPCON, "cascade": false}
	u.counters["ai_control"] = true
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	var q := host.nhp_question()
	expect_eq(q.get("kind", ""), "compcon")
	var labels: Array = (q["options"] as Array).map(func(o: Dictionary) -> String: return o["label"])
	expect(labels.has("Defend yourself") and labels.has("Hold this area"), str(labels))
	var attack: Array = (q["options"] as Array).filter(func(o: Dictionary) -> bool: return str(o["label"]).begins_with("Attack "))
	expect(not attack.is_empty(), "attack this enemy")
	var cmd: Dictionary = attack[0]["action"]
	expect((host.submit("p1", cmd)["result"] as RuleResult).ok)
	expect_eq(host.nhp_orders["p1"]["stance"], "aggressive")
	expect(state.units.has(str(host.nhp_orders["p1"]["focus"])))
	expect(b["director"].step(), "the COMP/CON acts on the command")
	expect(state.active_unit != "p1")


func test_fourth_gate_unit_fights_for_its_new_side() -> void:
	var b := _battle()
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	var foe: Unit = state.units_on_side(Mission.ENEMIES)[0]
	foe.counters["converted"] = {"side": foe.side, "controller": foe.controller, "by": "p1", "turns": 1}
	foe.side = Mission.PLAYERS
	foe.controller = "p1"
	expect_eq(NhpAi.kind(foe), "fourth_gate")
	expect((host.submit("p1", {"type": "start_turn", "actor": foe.id})["result"] as RuleResult).ok, "the squad activates it like an allied NPC")
	expect(host.nhp_question().is_empty(), "nothing to ask: the AI plays it")
	expect_eq(host.waiting_on("p1")["ai"], true)
	expect(not (host.submit("p1", {"type": "move", "actor": foe.id, "params": {"to": [foe.cell.x, foe.cell.y]}})["result"] as RuleResult).ok, "the player doesn't fly it")
	expect(b["director"].step(), "the AI plays it for its new side")
	expect(state.active_unit != foe.id)
