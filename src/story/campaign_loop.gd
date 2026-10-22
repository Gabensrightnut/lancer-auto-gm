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
		# Printer scarcity (house rule): a wrecked mech stays wrecked until it's reprinted.
		if Economy.wrecked(story, campaign).has(pid):
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
	# The map matches the hub: world/maps culture and landscape ids (cultures.json).
	if str(hook.get("landscape", "")) != "":
		gen_opts["landscape"] = hook["landscape"]
	if hook.has("map_culture"):
		gen_opts["culture"] = hook["map_culture"]
	# The same stretch of world as the last fight here keeps its look (world-maps' region).
	var region: Variant = story.flags.get("_regions", {}).get(region_key(story, hook))
	if region is Dictionary and not hook.has("boarding"):
		gen_opts["region"] = region
	if not (hook.get("environments", []) as Array).is_empty():
		gen_opts["environments"] = hook["environments"]
	# Boarding: world-maps builds the ships (opts.boarding: {kind, map}).
	if hook.has("boarding"):
		gen_opts["boarding"] = (hook["boarding"] as Dictionary).duplicate()
	# A fight in the hub itself: world-maps builds the battle from the town's own layout.
	var town := MissionHooks.town_for(story, hook)
	if not town.is_empty():
		gen_opts["town"] = town
	if bool(hook.get("tutorial", false)):
		# The drill: a small map, gentle GM, training targets only.
		var tm: Dictionary = Tutorial.data().get("mission", {})
		var all := UnitFactory.npc_templates()
		var only := {}
		for tid: String in tm.get("enemies", {"training_drone": 1}):
			if all.has(tid):
				only[tid] = all[tid]
		gen_opts["npc_templates"] = only if not only.is_empty() else all
		gen_opts["size"] = int(tm.get("size", 20))
		gen_opts["settings"] = GmSettings.from_preset(str(tm.get("gm_preset", "Teaching")))
	# The main campaign picks who you fight (its enemy mix for the chapter).
	if not (hook.get("npc_templates", []) as Array).is_empty() and not gen_opts.has("npc_templates"):
		var all_t := UnitFactory.npc_templates()
		var only_t := {}
		for tid: String in hook["npc_templates"]:
			if all_t.has(tid):
				only_t[tid] = all_t[tid]
		if not only_t.is_empty():
			gen_opts["npc_templates"] = only_t
	gen_opts.merge(opts, true)
	var gen := MissionGenerator.generate(int(hook.get("seed", story.mission_number)), gen_opts)
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	campaign.prepare_mission(state)
	mission.flavor["hook"] = hook.duplicate(true)
	# For the GM: the hidden twist to reveal mid-mission (Core p.43), and how the squad arrived.
	mission.flavor["twist"] = hook.get("twist", {}).duplicate(true)
	mission.flavor["arrived_late"] = bool(story.flags.get("arrived_late:%s" % hook.get("operation", ""), false))
	mission.flavor["arrived_spent"] = bool(story.flags.get("arrived_spent:%s" % hook.get("operation", ""), false))
	if hook.has("operation"):
		mission.flavor["operation"] = hook["operation"]
	mission.flavor["town"] = town
	mission.flavor["boarding"] = (hook.get("boarding", {}) as Dictionary).duplicate()
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
		if bool(hook.get("on_foot", false)) or bool(town.get("on_foot", false)):
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
	# Allies who came because of what the squad did (the main campaign's finales).
	var allies: Array = (hook.get("allies", []) as Array).duplicate()
	if hook.has("boarding"):
		allies.append_array(Plunder.boarders(story, campaign))
	_add_allies(state, mission, allies, int(hook.get("seed", 0)))
	# Someone leads the enemy force (Rivals): mission.flavor["commander"].
	Rivals.setup_battle(story, campaign, state, mission)
	return gen


## Allied NPC units on the squad's side, run by the AI as the "allies" seat.
static func _add_allies(state: GameState, mission: Mission, allies: Array, seed_value: int) -> void:
	if allies.is_empty():
		return
	var templates := UnitFactory.npc_templates()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "allies"])
	var free := MissionGenerator._free_cells(mission.deployment.get(Mission.PLAYERS, []), rng)
	state.seats["allies"] = {"name": "Allies", "side": Mission.PLAYERS}
	var n := 0
	var names: Array = []
	for a: Dictionary in allies:
		if not templates.has(str(a.get("template", ""))):
			continue
		for i in range(int(a.get("count", 1))):
			n += 1
			var u := MissionGenerator.build_enemy({"template": str(a["template"])}, templates, "ally%d" % n, n)
			u.name = "%s %d" % [a.get("name", "Ally"), i + 1]
			u.side = Mission.PLAYERS
			u.controller = "allies"
			if MissionGenerator._place(state, u, free):
				names.append(u.name)
	mission.flavor["allies"] = names


## A parley that ended the fight (the story event "battle_end_requested", Core p.60) as the
## GM's gm_end_mission action, for the flow to submit through the rules engine.
static func end_by_parley(mission: Mission, e: Dictionary) -> Dictionary:
	var o := str(e.get("outcome", "none"))
	mission.outcome = Mission.PLAYERS if o == "players" else (Mission.ENEMIES if o == "enemies" else "none")
	mission.outcome_reason = str(e.get("reason", ""))
	return mission.end_action()


## Pilot weapons from their pilot gear, as UnitFactory.build_pilot expects.
static func _pilot_for_battle(db: ContentDB, p: Dictionary) -> Dictionary:
	var out := p.duplicate()
	var weapons: Array = []
	for gid: String in p.get("pilot_gear", []):
		if str(db.get_entry("pilot_gear", gid).get("type", "")) == "Weapon":
			weapons.append(gid)
	out["weapons"] = weapons
	return out


## Starts a new campaign the guided way (DESIGN.md section 8): a Union training base, a drill
## instructor, and the drill as the first job, briefing first (Core p.40). Seats must be set.
## Returns the events (tutorial prompts, the briefing conversation).
static func start_tutorial(campaign: Campaign, story: StoryState, engine: StoryEngine) -> Array:
	var cfg: Dictionary = Tutorial.data()
	var hub_cfg: Dictionary = cfg.get("hub", {})
	var events: Array = []
	events.append_array(engine.submit(story, campaign, {"type": "enter_hub", "seat": "gm", "params": {"kind": hub_cfg.get("kind", "base"),
		"seed": int(hub_cfg.get("seed", 1)), "culture": hub_cfg.get("culture", "union_core"), "no_jobs": true}})["events"])
	if hub_cfg.has("name"):
		story.hub["name"] = hub_cfg["name"]
	# A training base has no local feud: the first real situation waits for the first real hub.
	story.hub["conflict"] = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, "instructor"])
	var inst := NpcGen.make_npc(rng, NameGen.new(rng), campaign, story.hub, "instructor", "tutorial_instructor")
	story.npcs[inst["id"]] = inst
	(story.hub["npcs"] as Array).push_front(inst["id"])
	story.contacts.append(inst["id"])
	var hook := MissionHooks.make(story, campaign, str(cfg.get("mission", {}).get("template", "tutorial_drill")), {"patron": inst["id"], "twist": ""})
	hook.erase("twist")
	hook["tutorial"] = true
	hook["briefing_scene"] = "tutorial_briefing"
	story.hooks = [hook]
	story.arc = {}
	story.phase = "briefing"
	events.append_array(Tutorial.start(story))
	return events


## A new campaign with the same pilots, after an ending: the living pilots keep their License
## Level, builds and portraits (reserves are spent); bonds and memories come along; the dead
## stay dead. The new story starts at a new hub, briefing first. {"campaign", "story", "events"}.
static func sequel(campaign: Campaign, story: StoryState, engine: StoryEngine, hub_kind: String = "town") -> Dictionary:
	var suffix := str(Ending.data().get("sequel", {}).get("suffix", " II"))
	var c := Campaign.create(campaign.name + suffix, campaign.options.duplicate(true))
	c.packs = campaign.packs.duplicate(true)
	c.gm_settings = campaign.gm_settings.duplicate(true)
	c.rulings = campaign.rulings.duplicate(true)
	var alive: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
	alive.sort()
	for pid: String in alive:
		var p: Dictionary = (campaign.pilots[pid] as Dictionary).duplicate(true)
		p["reserves"] = []
		c.pilots[pid] = p
	var ending: Dictionary = story.flags.get(Ending.KEY, {})
	c.story_flags["_legacy"] = {"name": campaign.name, "kind": ending.get("kind", ""), "missions": campaign.history.size(),
		"fallen": ending.get("summary", {}).get("fallen", [])}
	var bonds := {}
	for k: String in story.flags.get(Bonds.KEY, {}):
		var pair := k.split("|")
		if alive.has(pair[0]) and alive.has(pair[1]):
			bonds[k] = (story.flags[Bonds.KEY][k] as Dictionary).duplicate(true)
	c.story_flags[Bonds.KEY] = bonds
	var mem := {}
	for pid: String in story.flags.get(Squadmate.KEY, {}):
		if alive.has(pid):
			var m: Dictionary = (story.flags[Squadmate.KEY][pid] as Dictionary).duplicate(true)
			m["recent"] = {}
			mem[pid] = m
	c.story_flags[Squadmate.KEY] = mem
	var s := StoryState.new(hash([c.id, "story"]))
	s.flags = c.story_flags
	var events: Array = []
	var seats := story.seats.keys()
	seats.sort()
	for seat: String in seats:
		var pid := story.pilot_of_seat(seat)
		if alive.has(pid):
			events.append_array(engine.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": seat, "pilot": pid,
				"ai": story.is_ai(seat), "persona": story.seats[seat].get("persona", "")}})["events"])
	events.append_array(engine.submit(s, c, {"type": "enter_hub", "seat": "gm", "params": {"kind": hub_kind, "seed": int(hash([c.id, "hub"])) % 100000}})["events"])
	return {"campaign": c, "story": s, "events": events}


## The result for StoryEngine's mission_finished: outcome, and which pilots died or are
## Down and Out (their pilot Units, matched back through the seat).
static func mission_result(state: GameState, mission: Mission, story: StoryState, events: Array = []) -> Dictionary:
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
	var summary := battle_summary(state, story, events)
	if mission.rounds > 0:
		summary["rounds"] = mini(int(summary["rounds"]), mission.rounds)
	return {"outcome": outcome, "reason": mission.outcome_reason, "dead": dead, "down": down, "summary": summary}


## What happened in the fight, for the debrief and later briefings: rounds, enemies
## destroyed, the squad's mechs lost (reprinted at the next full repair, Core p.82), pilots
## who got out, and who did the most damage (when the battle's events are given).
static func battle_summary(state: GameState, _story: StoryState, events: Array = []) -> Dictionary:
	var kills := 0
	var lost: Array = []
	var ejected: Array = []
	var names := {}
	for u: Unit in state.units.values():
		names[u.id] = u.name
		if u.side == Mission.ENEMIES and u.destroyed:
			kills += 1
		if u.side == Mission.PLAYERS and u.kind != Unit.KIND_PILOT:
			if u.destroyed:
				lost.append(u.name)
		if u.side == Mission.PLAYERS and u.kind == Unit.KIND_PILOT and not u.counters.has("mounted_in") and not u.destroyed:
			ejected.append(u.name)
	var dealt := {}
	var cascades: Array = []
	for e: Dictionary in events:
		# An NHP that cascaded in the squad (Core p.107), for the debrief and the squad's memory.
		if str(e.get("type", "")) == "cascade_check" and bool(e.get("cascade", false)):
			var cu: Unit = state.unit(str(e.get("unit", "")))
			if cu != null and cu.side == Mission.PLAYERS and not cascades.has(cu.name):
				cascades.append(cu.name)
		if str(e.get("type", "")) == "damage_dealt":
			var src := str(e.get("source", ""))
			var tgt: Unit = state.unit(str(e.get("target", "")))
			var su: Unit = state.unit(src)
			if su != null and su.side == Mission.PLAYERS and tgt != null and tgt.side != su.side:
				dealt[src] = int(dealt.get(src, 0)) + int(e.get("amount", 0))
	var mvp := ""
	var best := 0
	for k: String in dealt:
		if int(dealt[k]) > best:
			best = int(dealt[k])
			mvp = str(names.get(k, k))
	return {"rounds": state.round_number, "kills": kills, "lost": lost, "ejected": ejected, "mvp": mvp, "mvp_damage": best, "cascades": cascades}


## Which stretch of world a fight is in: the world and the place.
static func region_key(story: StoryState, hook: Dictionary) -> String:
	return "%s:%s" % [str(Sector.get_sector(story).get("at", story.hub.get("id", ""))), str(hook.get("place", ""))]


static func finish_mission(campaign: Campaign, story: StoryState, engine: StoryEngine, state: GameState, mission: Mission, events: Array = []) -> Dictionary:
	campaign.record_mission(state, mission)
	if mission.flavor.get("region") is Dictionary and not mission.flavor.get("hook", {}).has("boarding"):
		var regions: Dictionary = story.flags.get("_regions", {})
		regions[region_key(story, mission.flavor.get("hook", {}))] = (mission.flavor["region"] as Dictionary).duplicate()
		story.flags["_regions"] = regions
	return engine.submit(story, campaign, {"type": "mission_finished", "seat": "gm", "params": mission_result(state, mission, story, events)})
