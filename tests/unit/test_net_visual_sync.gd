extends TestCase
## What the renderer needs reaches remote players through ViewFilter: deployed drones and
## deployables where the host state has them, and parts torn off by System Trauma, on the
## friend's own side and on enemies they haven't scanned.

const F = preload("res://tests/unit/test_rules_fixtures.gd")
const Online := preload("res://tests/unit/test_flow_story_online.gd")


func test_drones_and_missing_parts_reach_a_friend() -> void:
	var s := F.state()
	s.seats = {"p1": {"name": "Ama", "side": "players"}, "p2": {"name": "Rin", "side": "players"}, "gm": {"name": "GM", "side": "enemies", "gm": true}}
	var mine := F.mech(s, "ama", "players", Vector2i(0, 0))
	mine.controller = "p1"
	F.mech(s, "rin", "players", Vector2i(2, 0)).controller = "p2"
	var foe := F.mech(s, "foe", "enemies", Vector2i(8, 8))
	foe.controller = "gm"
	foe.loadout["weapons"] = [{"key": "w_left", "name": "Gun", "mount": 0}, {"key": "w_right", "name": "Axe", "mount": 1}]
	var host := NetHost.new(s, RulesEngine.new())
	GmActions.register(host.engine)
	host.add_local_seat("p1")
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "VISUAL")
	var rin := NetClient.new(LoopbackTransport.new(hub))
	var heard: Array = []
	rin.view_updated.connect(func(_v: Dictionary, evs: Array) -> void: heard.append_array(evs))
	rin.join("VISUAL", "Rin", "p2")
	Online._pump(host, rin)

	# Ama's drone goes out: the friend sees it where the host put it.
	var drone := Unit.new()
	drone.id = "ama_drone"
	drone.kind = Unit.KIND_DEPLOYABLE
	drone.side = "players"
	drone.controller = "p1"
	drone.name = "Drone"
	drone.cell = Vector2i(1, 2)
	var out := host.submit(NetHost.GM_SEAT, {"type": "gm_spawn", "params": {"units": [drone.to_dict()], "reason": "deployed"}})
	expect((out["result"] as RuleResult).ok, (out["result"] as RuleResult).reason)
	Online._pump(host, rin)
	var seen: Dictionary = rin.view["units"].get("ama_drone", {})
	expect(not seen.is_empty() and Vector2i(int(seen["cell"][0]), int(seen["cell"][1])) == Vector2i(1, 2) and seen["kind"] == Unit.KIND_DEPLOYABLE, "the drone is where the host says: %s" % str(seen))

	# System Trauma tears the enemy's left arm off (the rules engine's own event and state).
	Weapons.state_of(foe, foe.loadout["weapons"][0])["destroyed"] = true
	host.send_updates([{"type": "equipment_destroyed", "unit": "foe", "weapon": "w_left", "name": "Gun"}])
	Online._pump(host, rin)
	expect(heard.any(func(e: Dictionary) -> bool: return e["type"] == "equipment_destroyed" and e["unit"] == "foe"), "the event reaches the friend")
	var foe_view: Dictionary = rin.view["units"]["foe"]
	expect_eq((foe_view.get("mounts_lost", []) as Array).map(func(m: Variant) -> int: return int(m)), [0], "the missing arm is in the view (for a resync too)")
	expect(not foe_view.has("loadout") and not foe_view.has("hp"), "but not the enemy's gear or stats")


func test_drone_owner_is_public_and_hidden_mines_stay_hidden() -> void:
	var s := F.state()
	s.seats = {"p1": {"name": "Ama", "side": "players"}, "gm": {"name": "GM", "side": "enemies", "gm": true}}
	var foe := F.mech(s, "foe", "enemies", Vector2i(8, 8))
	var drone := Unit.new()
	drone.id = "foe_drone"
	drone.kind = Unit.KIND_DEPLOYABLE
	drone.side = "enemies"
	drone.cell = Vector2i(7, 8)
	drone.counters = {"owner": "foe"}
	s.add_unit(drone)
	var mine := Unit.new()
	mine.id = "foe_mine"
	mine.kind = Unit.KIND_DEPLOYABLE
	mine.side = "enemies"
	mine.cell = Vector2i(3, 3)
	mine.counters = {"owner": "foe", "deploy_type": "Mine"}
	mine.statuses["Hidden"] = {"source": "foe"}
	s.add_unit(mine)
	var f := ViewFilter.new()
	var view := f.view_for(s, "p1")
	expect_eq(str(view["units"]["foe_drone"].get("owner", "")), "foe", "which mech the drone left is public")
	var deployed := {"type": "deployed", "unit": foe.id, "object": {"id": "foe_mine", "kind": "mine", "name": "Mine", "cells": [[3, 3, 0]]}}
	var seen: Array = f.events_for(s, "p1", [deployed])
	expect(seen.size() == 1 and not (seen[0]["object"] as Dictionary).has("cells"), "the throw is seen, not where the Hidden mine landed")
	var own: Array = f.events_for(s, "gm", [deployed])
	expect((own[0]["object"] as Dictionary).has("cells"), "its own side knows")
