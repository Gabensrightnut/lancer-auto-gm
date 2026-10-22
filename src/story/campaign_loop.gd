class_name CampaignLoop
extends RefCounted
## The campaign loop in the book's order (Core p.40-44):
##   briefing (pick a job: goal and stakes) -> reserves -> mission (boots on the ground)
##   -> debrief -> level up -> downtime (hub, downtime actions) -> next briefing.
## Story changes go through StoryEngine; this file only builds the battle for a mission and
## reads its result back. Consequences are carried in story flags, standing, contacts,
## obligations and the hooks that appear later.
##
## Use:
##   var story := StoryState.of(campaign); var engine := StoryEngine.new(db)
##   engine.submit(story, campaign, {"type": "choose_hook", "seat": "gm", "params": {"hook": id}})
##   engine.submit(story, campaign, {"type": "confirm_reserves", "seat": "gm"})
##   var gen := CampaignLoop.build_mission(campaign, story, db)    # {state, mission}
##   ... play it (Net / RulesEngine) ...
##   CampaignLoop.finish_mission(campaign, story, engine, gen.state, gen.mission)
##   engine.submit(... "level_up"), level_picks per pilot, "start_downtime", ..., "end_downtime"
##   story.save_to(campaign); SaveStore.save_campaign(campaign)

const REF_REPAIRS := "reserves: Extra repairs (+2 Repair Cap)"
const REF_BATTERY := "reserves: CORE battery (a second use of the CORE System)"


## The squad for MissionGenerator: living pilots in seat order, with their seat ids.
static func squad(campaign: Campaign, story: StoryState) -> Array:
	var out: Array = []
	var seats := story.seats.keys()
	seats.sort()
	for s: String in seats:
		var pid := story.pilot_of_seat(s)
		var p: Dictionary = campaign.pilots.get(pid, {})
		if p.is_empty() or not story.is_alive(pid):
			continue
		var mech: Dictionary = {}
		for m: Dictionary in p.get("mechs", []):
			if m["id"] == p.get("active_mech", "") or mech.is_empty():
				mech = m
		out.append({"seat": s, "pilot": p, "mech": mech})
	if out.is_empty():
		for entry: Dictionary in campaign.squad():
			if story.is_alive(str(entry["pilot"].get("id", ""))):
				out.append(entry)
	return out


## Builds the battle for the current hook. Pilots ride in their mechs (each a pilot Unit
## with their pilot weapons, for if they get out); a hook marked on_foot starts them
## dismounted beside their mechs. Mechanical reserves are applied; the rest are listed in
## mission.flavor["reserves"] for the table.
static func build_mission(campaign: Campaign, story: StoryState, db: ContentDB, opts: Dictionary = {}) -> Dictionary:
	var hook := story.current_hook
	var gen_opts := {"squad": squad(campaign, story), "db": db, "settings": GmSettings.from_dict(campaign.gm_settings) if not campaign.gm_settings.is_empty() else GmSettings.from_preset("Standard")}
	if hook.has("sitrep"):
		gen_opts["sitrep"] = hook["sitrep"]
	gen_opts.merge(opts, true)
	var gen := MissionGenerator.generate(int(hook.get("seed", story.mission_number)), gen_opts)
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	campaign.prepare_mission(state)
	mission.flavor["hook"] = hook.duplicate(true)
	if hook.has("operation"):
		mission.flavor["operation"] = hook["operation"]
	var manual: Array = []
	for entry: Dictionary in gen_opts["squad"]:
		var seat := str(entry["seat"])
		var mech := state.unit(seat)
		if mech == null:
			continue
		var p: Dictionary = entry["pilot"]
		var pid := str(p.get("id", ""))
		var pu := UnitFactory.build_pilot(db, seat + "_pilot", _pilot_for_battle(db, p), mech.side, seat)
		pu.name = str(p.get("callsign", pu.name))
		pu.hp = clampi(StoryEffects.current_hp(story, campaign, pid), 0, pu.max_hp)
		pu.armor = StoryEffects.pilot_armor(p)
		Pilots.seat(state, pu, mech)
		if bool(hook.get("on_foot", false)):
			var spot: Variant = Pilots.free_adjacent(state, mech)
			if spot != null:
				Pilots.unseat(state, pu, mech, spot[0], spot[1])
		for r: Dictionary in story.reserves.get(pid, []):
			match str(r["id"]):
				"reserve_extra_repairs":
					mech.repairs += 2
					r["applied"] = REF_REPAIRS
				"reserve_core_battery":
					mech.counters["core_power"] = int(mech.counters.get("core_power", 0)) + 1
					r["applied"] = REF_BATTERY
				_:
					manual.append({"pilot": pid, "callsign": p.get("callsign", ""), "reserve": r.duplicate()})
	mission.flavor["reserves"] = manual
	return gen


## Pilot weapons from their pilot gear, as UnitFactory.build_pilot expects.
static func _pilot_for_battle(db: ContentDB, p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	var weapons: Array = []
	for gid: String in p.get("pilot_gear", []):
		if str(db.get_entry("pilot_gear", gid).get("type", "")) == "Weapon":
			weapons.append(gid)
	out["weapons"] = weapons
	return out


## The result for StoryEngine's mission_finished: outcome, and which pilots died or are
## Down and Out (their pilot Units, matched back through the seat).
static func mission_result(state: GameState, mission: Mission, story: StoryState) -> Dictionary:
	var outcome := "victory" if mission.outcome == Mission.PLAYERS else ("defeat" if mission.outcome == Mission.ENEMIES else "draw")
	var dead: Array = []
	var down: Array = []
	for u: Unit in state.units.values():
		if u.kind != Unit.KIND_PILOT or u.side != Mission.PLAYERS:
			continue
		var pid := story.pilot_of_seat(u.controller)
		if pid == "":
			pid = str(state.seats.get(u.controller, {}).get("pilot_id", ""))
		if pid == "":
			continue
		if u.destroyed:
			dead.append(pid)
		elif u.has_status("Down and Out"):
			down.append(pid)
	return {"outcome": outcome, "reason": mission.outcome_reason, "dead": dead, "down": down}


static func finish_mission(campaign: Campaign, story: StoryState, engine: StoryEngine, state: GameState, mission: Mission) -> Dictionary:
	campaign.record_mission(state, mission)
	return engine.submit(story, campaign, {"type": "mission_finished", "seat": "gm", "params": mission_result(state, mission, story)})
