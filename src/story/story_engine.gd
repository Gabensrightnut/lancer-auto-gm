class_name StoryEngine
extends RefCounted
## The only thing that changes a StoryState, the way RulesEngine is the only thing that
## changes a GameState. Players, AI squadmates and network clients all submit actions:
##   {"type": "talk", "seat": "p1", "params": {"npc": "hub_1_npc0"}}
## and get {"ok", "reason", "rule_ref", "events"}. Illegal actions are refused with a reason.
## The host runs it; clients get the events (and StoryView.view_for for their seat).
##
## Actions (params):
##   set_seat {seat, pilot, ai, persona}             enter_hub {kind, seed, culture}
##   talk {npc}                                      dialogue_next {}
##   dialogue_choose {choice}   dialogue_help {on}   skill_check {goal, label, skills, tags, difficult, risky, heroic, consequence}
##   rest {}                                         set_pilot_gear {pilot, gear: [ids]}
##   choose_hook {hook}                              confirm_reserves {}
##   mission_finished {outcome, reason, dead: [pilot ids], down: [pilot ids]}
##   level_up {}                                     level_picks {pilot, trigger, mech_skill}
##   start_downtime {long}                           downtime_action {pilot, action, ...action params}
##   downtime_choose {picks: [option ids]}           end_downtime {}
##   set_bondmate {pilot, mate}                      end_campaign {}  (retire the squad)
##   session_zero {identity, patron, history: [{question, a, b}], tone, focus, content_off: []}
##   battle_events {events: [battle events]}  (host, each batch: the enemy commander may offer terms)
##   parley {}                                        the squad calls on the enemy commander to stand down
##   gm_scene / gm_twist / gm_standing / gm_reserve / gm_job / gm_edit_job / gm_remove_job / gm_npc
##                                                    a human GM's story tools (GmTools; gm seat)
##   house_rule {id, on}  (host / GM: switch one of the story's house rules, StoryHouseRules)
##   buy {item, pilot} / sell_salvage {} / use_printer {pilot} / restock {} / fight_for_it {item, pilot}
##                                                    the money-and-supplies house rules (Economy)
##   wait / go / follow / sneak / pick_lock / break_in / pickpocket / take_out / take / slip_away
##                                                    doing things yourself in town (TownLife)
##   set_origin {pilot, origin: {homeworld, upbringing, employer, specialty, perks}}  (Origin)
##   store_template {pilot, kind} / wake_clone {pilot} / add_second_pilot {seat, name, callsign, relation}
##   set_active_pilot {seat, pilot}                     death, cloning and a second pilot (Cloning)
##   ship_work {job, pilot}                              a shift's work aboard the squad's ship (ShipLife)
##   buy_upgrade {slot}                                   the squad's own ship (house rule; Plunder)
##   decide {accept}  / split_resolved {winner}           squad decisions and party splits (Decisions)
##   travel {world}                                   go to another world of the sector (between missions; Sector)
## "seat" "gm" (the host / procedural GM) may act for anyone.

const REF_FLOW := "Core p.40: the structure of play"
const MECH_SKILLS := ["hull", "agility", "systems", "engineering"]
const GEAR_REF := "Core p.108: pilot gear (armor, up to two weapons, up to three other gear)"

var db: ContentDB


func _init(content: ContentDB = null) -> void:
	db = content


func submit(story: StoryState, campaign: Campaign, action: Dictionary) -> Dictionary:
	var why := validate(story, campaign, action)
	if not why.is_empty():
		return {"ok": false, "reason": why["reason"], "rule_ref": why.get("rule_ref", ""), "events": []}
	var events := _resolve(story, campaign, action)
	events.append_array(_run_ai(story, campaign))
	Squadmate.observe(story, campaign, events)
	events.append_array(Bonds.observe(story, campaign, events))
	# AI squadmates talk it over after the debrief, and a little when downtime starts.
	if events.any(func(x: Dictionary) -> bool: return str(x.get("type", "")) == "debrief"):
		events.append_array(Squadmate.banter(story, campaign, int(campaign.options.get("banter_lines", 2))))
	elif events.any(func(x: Dictionary) -> bool: return str(x.get("type", "")) == "downtime_started"):
		events.append_array(Squadmate.banter(story, campaign, 1))
	events.append_array(Tutorial.observe_story(story, campaign, events))
	for e: Dictionary in events:
		if str(e.get("type", "")) == "combat_requested" and story.phase != "mission":
			events.append_array(_combat_from_scene(story, campaign, e["spec"]))
			break
	return {"ok": true, "reason": "", "rule_ref": "", "events": events}


## {} when the action is allowed, else {"reason", "rule_ref"}.
func validate(story: StoryState, campaign: Campaign, action: Dictionary) -> Dictionary:
	var type := str(action.get("type", ""))
	var seat := str(action.get("seat", "gm"))
	var p: Dictionary = action.get("params", {})
	var me := story.pilot_of_seat(seat)
	# Doing things yourself in town (TownLife): waiting, sneaking, following, picking locks...
	if TownLife.handles(type):
		var tpid := str(p.get("pilot", me))
		if type != "wait" and seat != "gm" and not _controls(story, seat, tpid):
			return _no("That isn't your pilot.")
		var why_t := TownLife.refusal(story, campaign, type, p, tpid)
		return _no(why_t) if why_t != "" else {}
	# A human GM's story tools (GmTools): gm seat only.
	if GmTools.handles(type):
		var why_gm := GmTools.refusal(story, campaign, type, p, seat)
		return _no(why_gm) if why_gm != "" else {}
	match type:
		"set_seat":
			if not campaign.pilots.has(str(p.get("pilot", ""))):
				return _no("No such pilot in this campaign.")
			if seat != "gm":
				return _no("Only the host assigns seats.")
		"enter_hub":
			if story.phase == "mission":
				return _no("You're on a mission. The squad gets back to a hub after it.", REF_FLOW)
		"talk":
			if Dialogue.is_open(story):
				return _no("Someone is already talking. Finish that conversation first.")
			var npc: Dictionary = story.npcs.get(str(p.get("npc", "")), {})
			if npc.is_empty() or not (story.hub.get("npcs", []) as Array).has(npc["id"]) and not story.contacts.has(npc["id"]):
				return _no("Nobody like that is here.")
			if bool(npc.get("dead", false)):
				return _no("%s is dead." % npc["name"])
			var cold := Tones.refuses(story, str(npc["id"]))
			if cold != "":
				return _no(cold)
			var w := _able(story, campaign, me)
			if not w.is_empty():
				return w
		"dialogue_next":
			if not Dialogue.is_open(story):
				return _no("No one is talking.")
			if not Dialogue.offered(story).is_empty():
				return _no("Pick a reply first.")
		"dialogue_choose":
			if not Dialogue.is_open(story):
				return _no("No one is talking.")
			var choice := str(p.get("choice", ""))
			if not Dialogue.offered(story).any(func(o: Dictionary) -> bool: return o["id"] == choice):
				return _no("That reply isn't on offer.")
			var d := Dialogue.decider(story, campaign)
			if seat != "gm":
				if not (d["seats"] as Array).has(seat):
					var sp_pilot: Dictionary = campaign.pilots.get(story.pilot_of_seat(str(d["speaker_seat"])), {})
					return _no("%s is the one talking, so their player chooses (or switch the host setting to a squad vote)." % sp_pilot.get("callsign", "Another pilot"), "DESIGN.md section 10: dialogue choices")
				if story.is_ai(seat):
					return _no("That seat is an AI squadmate; it picks for itself.")
		"dialogue_help":
			if not Dialogue.is_open(story):
				return _no("No one is talking.")
			var w := _able(story, campaign, me)
			if not w.is_empty():
				return w
			if story.pilot_of_seat(seat) == str(story.dialogue.get("ctx", {}).get("speaker", "")):
				return _no("You're the one rolling; helpers are the rest of the squad.", NarrativeCheck.REF_TEAMWORK)
		"skill_check":
			var w := _able(story, campaign, me)
			if not w.is_empty():
				return w
			var goal := str(p.get("goal", ""))
			if goal != "" and story.failed_goals.has(goal) and not bool(p.get("push", false)):
				return _no("This already failed. Change the circumstances or push it (it becomes RISKY).", NarrativeCheck.REF_PUSH)
			if goal != "" and bool(p.get("push", false)):
				var push := NarrativeCheck.push_level(str(story.failed_goals.get(goal, "normal")), bool(campaign.options.get("allow_heroic_push", true)))
				if not push["ok"]:
					return _no(push["reason"], push["rule_ref"])
		"rest":
			if story.phase == "mission":
				return _no("Resting happens out of combat, with an hour of nothing strenuous.", "Core p.49")
		"set_pilot_gear":
			if story.phase == "mission":
				return _no("Gear is chosen before the mission starts.", "Core p.43")
			var why := gear_problem(p.get("gear", []))
			if why != "":
				return _no(why, GEAR_REF)
			if not _controls(story, seat, str(p.get("pilot", ""))):
				return _no("That isn't your pilot.")
		"choose_hook":
			if story.phase != "briefing":
				return _no("Missions are chosen at the briefing, between downtime and boots on the ground.", REF_FLOW)
			if not story.hooks.any(func(h: Dictionary) -> bool: return h["id"] == str(p.get("hook", ""))):
				return _no("That job isn't on offer.")
			var flyable: Array = campaign.pilots.keys().filter(func(x: String) -> bool: return story.is_alive(x) and not Economy.wrecked(story, campaign).has(x))
			if flyable.is_empty():
				return _no("Every mech is wrecked. Get them reprinted at a printer first (the map shows which worlds have one). House rule: %s." % Economy.LABEL)
		"confirm_reserves":
			if story.phase != "reserves":
				return _no("Reserves are set after the briefing, right before the mission.", "Core p.43: stage three, reserves")
		"mission_finished":
			if story.phase != "mission":
				return _no("No mission is underway.", REF_FLOW)
			if seat != "gm":
				return _no("The host reports the mission result.")
		"level_up":
			if story.phase != "debrief":
				return _no("Pilots level up in the debrief after a mission.", "Core p.44: debrief")
		"level_picks":
			var pid := str(p.get("pilot", ""))
			var picks: Dictionary = story.pending_picks.get(pid, {})
			if picks.is_empty():
				return _no("That pilot has nothing to pick right now.", "Core p.18: leveling up")
			if not _controls(story, seat, pid):
				return _no("That isn't your pilot.")
			var pilot: Dictionary = campaign.pilots.get(pid, {})
			if p.has("trigger"):
				if int(picks.get("trigger", 0)) <= 0:
					return _no("Trigger already picked this level.")
				if int(pilot.get("skills", {}).get(str(p["trigger"]), 0)) >= 3:
					return _no("That trigger is already +6, the most it can be.", "Core p.25")
			if p.has("mech_skill"):
				if int(picks.get("mech_skill", 0)) <= 0:
					return _no("Mech skill already picked this level.")
				if not MECH_SKILLS.has(str(p["mech_skill"])):
					return _no("Mech skills are Hull, Agility, Systems and Engineering.", "Core p.30")
				if int(pilot.get(str(p["mech_skill"]), 0)) >= 6:
					return _no("Mech skills go up to +6.", "Core p.30")
		"start_downtime":
			if story.phase != "level_up":
				return _no("Downtime comes after the debrief and leveling up.", REF_FLOW)
			for pid: String in story.pending_picks:
				var left: Dictionary = story.pending_picks[pid]
				if story.is_alive(pid) and (int(left.get("trigger", 0)) > 0 or int(left.get("mech_skill", 0)) > 0):
					return _no("%s still has to pick a new trigger and mech skill." % campaign.pilots.get(pid, {}).get("callsign", "A pilot"), "Core p.18: leveling up")
		"downtime_action":
			var pid := str(p.get("pilot", me))
			if not _controls(story, seat, pid):
				return _no("That isn't your pilot.")
			var w := _able(story, campaign, pid)
			if not w.is_empty():
				return w
			var r := Downtime.refusal(story, campaign, pid, str(p.get("action", "")), p)
			if not r.is_empty():
				return r
		"downtime_choose":
			var pid := _choice_pilot(story, seat, p)
			var pc := story.first_choice_for(pid) if pid != "" else story.pending_choice
			if pc.is_empty():
				return _no("Nothing is waiting for a choice.")
			if str(pc.get("chooser", "player")) == "player" and not _controls(story, seat, str(pc.get("pilot", ""))):
				return _no("This choice belongs to %s's player." % campaign.pilots.get(str(pc.get("pilot", "")), {}).get("callsign", "another pilot"))
			var r := Downtime.choice_refusal(story, p.get("picks", []), pid)
			if not r.is_empty():
				return r
		"set_bondmate":
			if not _controls(story, seat, str(p.get("pilot", ""))):
				return _no("That isn't your pilot.")
			var why := Bonds.bondmate_refusal(story, campaign, str(p.get("pilot", "")), str(p.get("mate", "")))
			if why != "":
				return _no(why, Bonds.REF_BONDED)
		"session_zero":
			if seat != "gm":
				return _no("The table sets this up together; the host enters it.")
			var why := SessionZero.refusal(story, campaign, p)
			if why != "":
				return _no(why, "Core p.40-41")
		"battle_events":
			if seat != "gm":
				return _no("The host reports the battle.")
		"store_template":
			var why_c := Cloning.store_refusal(story, campaign, str(p.get("pilot", me)), str(p.get("kind", "facsimile")))
			if why_c != "":
				return _no(why_c, Cloning.REF)
		"wake_clone":
			var why_w := Cloning.wake_refusal(story, campaign, str(p.get("pilot", "")))
			if why_w != "":
				return _no(why_w, Cloning.REF)
		"add_second_pilot":
			var sseat := str(p.get("seat", seat))
			if seat != "gm" and seat != sseat:
				return _no("That isn't your seat.")
			var why_s := Cloning.second_refusal(story, campaign, sseat, p)
			if why_s != "":
				return _no(why_s)
		"set_active_pilot":
			var aseat := str(p.get("seat", seat))
			var choices := [story.pilot_of_seat(aseat), str(story.seats.get(aseat, {}).get("second", ""))]
			if (seat != "gm" and seat != aseat) or not choices.has(str(p.get("pilot", ""))) or story.phase == "mission":
				return _no("Pick one of your pilots, between missions.")
		"decide":
			var why_d := Decisions.refusal(story, seat)
			if why_d != "":
				return _no(why_d)
		"ship_work":
			var wpid := str(p.get("pilot", me))
			if seat != "gm" and not _controls(story, seat, wpid):
				return _no("Pick one of your pilots.")
			var why_w2 := ShipLife.work_refusal(story, campaign, str(p.get("job", "")), wpid)
			if why_w2 != "":
				return _no(why_w2)
		"buy_upgrade":
			if story.phase == "mission":
				return _no("Not in the middle of a mission.")
			var why_u := Plunder.upgrade_refusal(story, campaign, str(p.get("slot", "")))
			if why_u != "":
				return _no(why_u)
		"split_resolved":
			if seat != "gm" or not Decisions.current(story).has("split"):
				return _no("There's no split to settle.")
		"set_origin":
			var opid := str(p.get("pilot", me))
			if not campaign.pilots.has(opid) or (seat != "gm" and not _controls(story, seat, opid)):
				return _no("Pick one of your pilots.")
			var why_o := Origin.refusal(p.get("origin", {}))
			if why_o != "":
				return _no(why_o, "Core p.20: backgrounds")
		"travel":
			if seat != "gm":
				return _no("The squad travels together; the host moves it.")
			var why_t := Sector.travel_refusal(story, str(p.get("world", "")))
			if why_t == "":
				why_t = Economy.travel_refusal(story, campaign, Sector.world(story, str(p.get("world", ""))))
			if why_t != "":
				return _no(why_t, Sector.REF)
		"house_rule":
			if seat != "gm":
				return _no("The host (or a human GM) sets the house rules.")
			var why_h := StoryHouseRules.refusal(str(p.get("id", "")))
			if why_h != "":
				return _no(why_h)
		"exchange":
			var why_x := Economy.exchange_refusal(story, campaign, bool(p.get("to_manna", true)), int(p.get("amount", 0)))
			if why_x != "":
				return _no(why_x)
		"buy", "sell_salvage", "use_printer", "restock", "fight_for_it":
			if story.phase == "mission":
				return _no("Not in the middle of a mission.")
			var who := str(p.get("pilot", me))
			if type in ["buy", "use_printer", "fight_for_it"] and (not campaign.pilots.has(who) or (seat != "gm" and not _controls(story, seat, who))):
				return _no("Pick one of your pilots.")
			var why_e := ""
			match type:
				"buy":
					why_e = Economy.buy_refusal(story, campaign, str(p.get("item", "")))
				"sell_salvage":
					why_e = "Nothing to sell." if not StoryHouseRules.on(campaign, Economy.R_WALLET) or int(Economy.wallet(story).get("salvage", 0)) <= 0 else ""
				"use_printer":
					why_e = Economy.printer_refusal(story, campaign, who)
				"restock":
					why_e = Economy.restock_refusal(story, campaign)
				"fight_for_it":
					why_e = Economy.fight_refusal(story, campaign, str(p.get("item", "")))
			if why_e != "":
				return _no(why_e)
		"parley":
			var why := Rivals.parley_refusal(story, seat)
			if why != "":
				return _no(why, Rivals.REF_EARLY)
		"end_campaign":
			if seat != "gm":
				return _no("The host decides when the campaign ends.")
			if story.phase not in ["downtime", "briefing"]:
				return _no("A campaign can end between missions: in downtime or at a briefing.")
		"end_downtime":
			if story.phase != "downtime":
				return _no("Not in downtime.")
			if not story.all_choices().is_empty():
				var who: String = campaign.pilots.get(str(story.all_choices()[0].get("pilot", "")), {}).get("callsign", "Someone")
				return _no("A downtime result is still waiting for %s's choice." % who)
			if not Decisions.current(story).is_empty():
				return _no("The squad still has to settle this: %s." % Decisions.current(story).get("prompt", "a decision"))
		_:
			return _no("Unknown story action '%s'." % type)
	return {}


func _resolve(story: StoryState, campaign: Campaign, action: Dictionary) -> Array:
	var seat := str(action.get("seat", "gm"))
	var p: Dictionary = action.get("params", {})
	var me := story.pilot_of_seat(seat)
	if TownLife.handles(str(action["type"])):
		return TownLife.apply(story, campaign, str(action["type"]), p, str(p.get("pilot", me)))
	if GmTools.handles(str(action["type"])):
		return GmTools.apply(story, campaign, str(action["type"]), p, _first_alive(story, campaign))
	match str(action["type"]):
		"set_seat":
			# An AI squadmate without a chosen persona gets the one their triggers and background suggest.
			var persona := str(p.get("persona", ""))
			if persona == "":
				persona = Squadmate.suggest(campaign.pilots[str(p["pilot"])])
			story.seats[str(p.get("seat", seat))] = {"pilot": str(p["pilot"]), "ai": bool(p.get("ai", false)), "persona": persona}
			# Every pilot who can speak has a full portrait (kept on the pilot record for the builder).
			var pilot_rec: Dictionary = campaign.pilots[str(p["pilot"])]
			if not pilot_rec.get("portrait") is Dictionary or int((pilot_rec["portrait"] as Dictionary).get("version", 1)) < 2:
				pilot_rec["portrait"] = PortraitSpec.for_pilot(pilot_rec)
			return [{"type": "seat_set", "seat": p.get("seat", seat), "pilot": p["pilot"], "ai": bool(p.get("ai", false))}]
		"enter_hub":
			var events: Array = []
			if story.hub.is_empty() or int(story.hub.get("seed", -1)) != int(p.get("seed", story.hub.get("seed", 0))):
				NpcGen.make_hub(story, campaign, int(p.get("seed", story.mission_number)), str(p.get("kind", "town")), str(p.get("culture", "")))
				Sector.adopt_hub(story)
				events.append({"type": "hub_entered", "hub": story.hub.duplicate(true)})
			Sector.ensure(story, campaign)
			TownLife.seed_items(story)
			if not bool(p.get("no_jobs", false)):
				for h: Dictionary in MissionHooks.fill_board(story, campaign):
					events.append({"type": "hook_added", "hook": h})
			return events
		"talk":
			var npc_id := str(p["npc"])
			var events := Dialogue.start(story, campaign, str(story.npcs[npc_id].get("scene", "local")), {"speaker": me, "npc": npc_id})
			if not story.contacts.has(npc_id):
				events.append_array(StoryEffects.apply({"contact": npc_id}, story, campaign, {}))
			return events
		"dialogue_next":
			return Dialogue.advance(story, campaign)
		"dialogue_choose":
			var d := Dialogue.decider(story, campaign)
			if d["mode"] == "speaker" or seat == "gm":
				return _downtime_follow(story, campaign, Dialogue.resolve_choice(story, campaign, str(p["choice"]), seat))
			story.dialogue["votes"][seat] = str(p["choice"])
			var events: Array = [{"type": "dialogue_vote", "seat": seat, "choice": p["choice"]}]
			var winner := Dialogue.vote_result(story, campaign)
			if winner != "":
				events.append_array(_downtime_follow(story, campaign, Dialogue.resolve_choice(story, campaign, winner, "vote")))
			return events
		"dialogue_help":
			if not story.dialogue.has("helpers"):
				story.dialogue["helpers"] = {}
			story.dialogue["helpers"][seat] = bool(p.get("on", true))
			return [{"type": "dialogue_help", "seat": seat, "on": bool(p.get("on", true)), "rule_ref": NarrativeCheck.REF_TEAMWORK}]
		"skill_check":
			var opts := p.duplicate(true)
			if bool(p.get("push", false)):
				var push := NarrativeCheck.push_level(str(story.failed_goals.get(str(p["goal"]), "normal")), bool(campaign.options.get("allow_heroic_push", true)))
				opts["risky"] = push["level"] == "risky"
				opts["heroic"] = push["level"] == "heroic"
			var rec := NarrativeCheck.roll(story.dice, campaign.pilots[me], Economy.check_opts(story, campaign, me, opts))
			var goal := str(p.get("goal", ""))
			if goal != "":
				if rec["success"]:
					story.failed_goals.erase(goal)
				else:
					story.failed_goals[goal] = rec["level"]
			var events: Array = [{"type": "narrative_check", "pilot": me, "check": rec, "rule_ref": NarrativeCheck.REF}]
			events.append_array(StoryEffects.apply_all(p.get("success_effects" if rec["success"] else "fail_effects", []), story, campaign, {"speaker": me}))
			return events
		"rest":
			return StoryEffects.apply({"rest": "squad"}, story, campaign, {})
		"set_pilot_gear":
			var pilot: Dictionary = campaign.pilots[str(p["pilot"])]
			pilot["pilot_gear"] = (p.get("gear", []) as Array).duplicate()
			return [{"type": "pilot_gear_set", "pilot": p["pilot"], "gear": pilot["pilot_gear"]}]
		"choose_hook":
			for h: Dictionary in story.hooks:
				if h["id"] == str(p["hook"]):
					story.current_hook = h
			story.hooks = story.hooks.filter(func(h: Dictionary) -> bool: return h["id"] != story.current_hook["id"])
			story.phase = "reserves"
			var events: Array = [{"type": "hook_chosen", "hook": story.current_hook.duplicate(true), "rule_ref": "Core p.40: briefing"}]
			var brief := str(story.current_hook.get("briefing_scene", "briefing"))
			if not Dialogue.is_open(story) and not Dialogue.scene_of(story, brief).is_empty():
				events.append_array(Dialogue.start(story, campaign, brief, {"speaker": _first_alive(story, campaign), "npc": str(story.current_hook.get("patron_id", "")), "hook": story.current_hook,
					"vars": StoryText.briefing_vars(story, campaign)}))
			return events
		"confirm_reserves":
			story.phase = "mission"
			return [{"type": "boots_on_the_ground", "hook": story.current_hook.duplicate(true), "reserves": story.reserves.duplicate(true),
				"rule_ref": "Core p.44: stage four, boots on the ground"}]
		"mission_finished":
			return _finish_mission(story, campaign, p)
		"level_up":
			return _level_up(story, campaign)
		"level_picks":
			var pid := str(p["pilot"])
			var pilot: Dictionary = campaign.pilots[pid]
			var picks: Dictionary = story.pending_picks[pid]
			var events: Array = []
			if p.has("trigger"):
				var t := str(p["trigger"])
				pilot["skills"][t] = int(pilot["skills"].get(t, 0)) + 1
				picks["trigger"] = int(picks["trigger"]) - 1
				events.append({"type": "trigger_improved", "pilot": pid, "trigger": t, "bonus": int(pilot["skills"][t]) * 2})
			if p.has("mech_skill"):
				var k := str(p["mech_skill"])
				pilot[k] = int(pilot.get(k, 0)) + 1
				picks["mech_skill"] = int(picks["mech_skill"]) - 1
				events.append({"type": "mech_skill_improved", "pilot": pid, "skill": k, "value": pilot[k]})
			return events
		"start_downtime":
			story.phase = "downtime"
			var events := Downtime.start(story, campaign, bool(p.get("long", campaign.options.get("long_downtime", false))))
			events.append_array(_ai_downtime(story, campaign))
			# Food and water house rule: tonight's meal, hosted or from the stores.
			events.append_array(Economy.downtime_night(story, campaign))
			# The main campaign: the conversation that follows the chapter's mission.
			if CampaignScript.active(campaign):
				events.append_array(CampaignScript.aftermath(story, campaign, _first_alive(story, campaign)))
			if not story.hub.is_empty():
				for h: Dictionary in MissionHooks.fill_board(story, campaign):
					events.append({"type": "hook_added", "hook": h})
			return events
		"downtime_action":
			var pid := str(p.get("pilot", me))
			return Downtime.perform(story, campaign, pid, str(p["action"]), p)
		"downtime_choose":
			return Downtime.choose(story, campaign, p.get("picks", []), _choice_pilot(story, seat, p))
		"set_bondmate":
			var bp: Dictionary = campaign.pilots[str(p["pilot"])]
			bp["bondmate"] = str(p["mate"])
			bp["bondmate_label"] = str(Bonds.get_bond(story, str(p["pilot"]), str(p["mate"]))["label"])
			return [{"type": "bondmate_set", "pilot": p["pilot"], "mate": p["mate"], "rule_ref": Bonds.REF_BONDED}]
		"end_campaign":
			return Ending.conclude(story, campaign, "")
		"session_zero":
			return SessionZero.apply(story, campaign, p)
		"battle_events":
			return Rivals.observe(story, campaign, p.get("events", []))
		"travel":
			var paid := Economy.pay_passage(story, campaign, Sector.world(story, str(p["world"])))
			return paid + Sector.travel(story, campaign, str(p["world"]))
		"store_template":
			return Cloning.store(story, campaign, str(p.get("pilot", me)), str(p.get("kind", "facsimile")))
		"wake_clone":
			var woke := Cloning.wake(story, campaign, str(p["pilot"]))
			woke.append_array(CampaignScript.on_clone(story, campaign, str(p["pilot"])))
			return woke
		"add_second_pilot":
			return Cloning.add_second(story, campaign, str(p.get("seat", seat)), p)
		"set_active_pilot":
			return Cloning.set_active(story, campaign, str(p.get("seat", seat)), str(p["pilot"]))
		"decide":
			return Decisions.vote(story, campaign, seat, bool(p.get("accept", true)))
		"ship_work":
			return ShipLife.work(story, campaign, str(p["job"]), str(p.get("pilot", me)))
		"buy_upgrade":
			return Plunder.buy_upgrade(story, campaign, str(p["slot"]))
		"split_resolved":
			return Decisions.resolve_split(story, campaign, str(p.get("winner", "accept")))
		"set_origin":
			var op: Dictionary = campaign.pilots[str(p.get("pilot", me))]
			op["origin"] = (p.get("origin", {}) as Dictionary).duplicate(true)
			return [{"type": "origin_set", "pilot": op["id"], "text": "%s: %s." % [op.get("callsign", ""), Origin.describe(op)], "rule_ref": "Core p.20: backgrounds"}]
		"house_rule":
			return StoryHouseRules.set_rule(story, campaign, str(p["id"]), bool(p.get("on", true)))
		"buy":
			return Economy.buy(story, campaign, str(p["item"]), str(p.get("pilot", me)))
		"sell_salvage":
			return Economy.sell_salvage(story)
		"exchange":
			return Economy.exchange(story, bool(p.get("to_manna", true)), int(p["amount"]))
		"use_printer":
			return Economy.use_printer(story, campaign, str(p.get("pilot", me)))
		"restock":
			return Economy.restock(story, campaign)
		"fight_for_it":
			return Economy.fight_for(story, campaign, str(p["item"]), str(p.get("pilot", me)))
		"parley":
			return Rivals.demand(story, campaign, seat)
		"end_downtime":
			story.phase = "briefing"
			var recap: Array = (story.downtime.get("log", []) as Array).duplicate(true)
			story.flags["_last_downtime"] = recap
			var events: Array = [{"type": "downtime_ended", "rule_ref": REF_FLOW, "recap": recap}]
			# The main campaign: the chapter's branch, then the next chapter (CampaignScript).
			events.append_array(CampaignScript.advance(story, campaign))
			for h: Dictionary in MissionHooks.fill_board(story, campaign):
				events.append({"type": "hook_added", "hook": h})
			return events
	return []


## A scene drops the squad into a fight (an ambush, talks gone wrong): it becomes this
## mission, straight to boots on the ground. Unused downtime actions are lost.
func _combat_from_scene(story: StoryState, campaign: Campaign, spec: Dictionary) -> Array:
	var hook := MissionHooks.make(story, campaign, str(spec.get("hook", "trouble_followed")), {"patron": str(spec.get("patron", ""))})
	if spec.has("sitrep"):
		hook["sitrep"] = str(spec["sitrep"])
	hook["on_foot"] = bool(spec.get("on_foot", false))
	hook["from_scene"] = true
	if hook.has("boarding") and not bool(spec.get("in_town", true)):
		spec["in_town"] = false
	# A fight that breaks out in a conversation happens right there, outside their door.
	if bool(spec.get("in_town", true)) and not story.hub.is_empty():
		hook["in_town"] = true
		var npc_spot := str(story.npcs.get(str(spec.get("patron", "")), {}).get("spot", ""))
		var spots: Array = (story.hub.get("spots", []) as Array).map(func(s: Dictionary) -> String: return str(s["id"]))
		hook["town_spot"] = npc_spot if spots.has(npc_spot) else str(spec.get("town_spot", "plaza"))
	story.current_hook = hook
	story.downtime["actions_left"] = {}
	story.pending_choice = {}
	story.phase = "mission"
	return [{"type": "boots_on_the_ground", "hook": hook.duplicate(true), "reserves": story.reserves.duplicate(true),
		"reason": str(spec.get("reason", "")), "rule_ref": "Core p.45: switching to mech combat"}]


## A dialogue effect that opens a downtime action runs it right away for the speaker (the
## scene already named the subject), if they still have a downtime action.
func _downtime_follow(story: StoryState, campaign: Campaign, events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		out.append(e)
		if str(e.get("type", "")) == "downtime_offered":
			var params := {"pilot": e["pilot"], "action": e["action"], "subject": e.get("subject", ""), "npc": e.get("npc", "")}
			var why := Downtime.refusal(story, campaign, str(e["pilot"]), str(e["action"]), params)
			if why.is_empty():
				out.append_array(Downtime.perform(story, campaign, str(e["pilot"]), str(e["action"]), params))
			else:
				out.append({"type": "action_refused", "reason": why["reason"], "rule_ref": why.get("rule_ref", "")})
	return out


func _finish_mission(story: StoryState, campaign: Campaign, p: Dictionary) -> Array:
	var outcome := str(p.get("outcome", "victory"))
	var won := outcome in ["victory", "success"]
	var hook := story.current_hook
	var ctx := {"hook": hook, "npc": str(hook.get("patron_id", ""))}
	var events: Array = [{"type": "debrief", "mission": story.mission_number, "outcome": outcome, "reason": str(p.get("reason", "")),
		"hook": hook.duplicate(true), "rule_ref": "Core p.44: stage five, ending a mission and debrief"}]
	events.append_array(StoryEffects.apply_all(hook.get("success" if won else "failure", []), story, campaign, ctx))
	for pid: Variant in p.get("dead", []):
		if campaign.pilots.has(str(pid)) and story.is_alive(str(pid)):
			events.append_array(StoryEffects.kill(story, str(pid), str(p.get("death_cause", "Killed in action."))))
			events.append_array(Cloning.on_death(story, campaign, str(pid)))
	Cloning.tick(story)
	for pid: Variant in p.get("down", []):
		if campaign.pilots.has(str(pid)) and story.is_alive(str(pid)):
			story.down_and_out[str(pid)] = true
			story.pilot_hp[str(pid)] = 0
	story.flags["mission_%d_outcome" % story.mission_number] = outcome
	if hook.has("template"):
		var done: Array = story.flags.get("_hooks_done", [])
		done.append("%s:%s" % [hook["template"], hook.get("patron_id", "")])
		story.flags["_hooks_done"] = done
	# Reserves last for one mission only (Core p.51).
	for pid: String in story.reserves:
		for rid: Variant in story.reserves[pid].map(func(r: Dictionary) -> String: return str(r["id"])):
			var ids: Array = campaign.pilots.get(pid, {}).get("reserves", [])
			ids.erase(rid)
	if not story.reserves.is_empty():
		events.append({"type": "reserves_expired", "rule_ref": "Core p.51: reserves last for the next mission only"})
	story.reserves = {}
	# After the old reserves expire: what this mission earned is for the next one.
	# The twist the mission hid (Core p.43: goals change mid-mission) and its consequence.
	var twist: Dictionary = hook.get("twist", {})
	if not twist.is_empty():
		events.append({"type": "twist_revealed", "twist": twist.duplicate(true), "rule_ref": "Core p.43: goals can change mid-mission"})
		events.append_array(StoryEffects.apply_all(twist.get("effects", []), story, campaign, ctx))
	# A side job done for someone pays out their reserve; a lost one withdraws the offer.
	var deal: Dictionary = hook.get("deal", {})
	if not deal.is_empty():
		var npc_id := str(deal["npc"])
		var rec: Dictionary = story.deals.get(npc_id, {})
		rec["state"] = "won" if won else "lost"
		story.deals[npc_id] = rec
		if won:
			var to := str(rec.get("by", ""))
			if to == "" or not story.is_alive(to):
				to = _first_alive(story, campaign)
			var dctx := {"npc": npc_id, "speaker": to}
			events.append_array(StoryEffects.apply({"reserve": str(deal["reward"]), "to": "speaker", "source": "$npc.name", "note": "For the job you did for {npc}"}, story, campaign, dctx))
			events.append_array(StoryEffects.apply({"standing": "$npc.faction", "add": 1}, story, campaign, dctx))
		events.append({"type": "deal_" + ("kept" if won else "off"), "npc": npc_id, "reward": deal["reward"], "rule_ref": "Core p.40-43: reserves"})
	events.append_array(StoryArc.advance(story, campaign, hook, won))
	# What became of the enemy commander (Rivals).
	events.append_array(Rivals.after_mission(story, outcome, hook))
	# The main campaign remembers the chapter's mission (CampaignScript).
	events.append_array(CampaignScript.after_mission(story, campaign, hook, won))
	# What the mission did to the place, and what that leads to (WorldState).
	events.append_array(WorldState.after_mission(story, campaign, hook, won))
	# House rules that are on: pay, salvage, rations, wrecked mechs (Economy).
	events.append_array(Economy.after_mission(story, campaign, hook, won, p.get("summary", {})))
	# A raid's haul: money, loot for the ship, or a reserve by the book (Plunder).
	events.append_array(Plunder.after_mission(story, campaign, hook, won))
	# A run for the people aboard (ShipLife).
	events.append_array(ShipLife.after_mission(story, campaign, hook, won))
	# The GM's bond rewards were for this mission only (Core p.50).
	story.flags.erase(Bonds.REWARDS)
	# Has the campaign told its story? It ends after the level up (or now, if nobody's left).
	var why := Ending.due(story, campaign)
	if why == "fallen":
		events.append_array(Ending.conclude(story, campaign, why))
	elif why != "":
		story.flags["_ending_due"] = why
	story.last_mission = {"number": story.mission_number, "outcome": outcome, "reason": str(p.get("reason", "")), "hook": hook.get("short_title", hook.get("title", "")),
		"place": hook.get("place", ""), "patron": hook.get("patron", ""), "enemy": hook.get("enemy", ""), "summary": (p.get("summary", {}) as Dictionary).duplicate(true),
		"twist": hook.get("twist", {}).get("reveal", "")}
	story.current_hook = {}
	story.mission_number += 1
	story.phase = "debrief"
	if not Dialogue.scene("debrief").is_empty():
		events.append_array(Dialogue.start(story, campaign, "debrief", {"speaker": _first_alive(story, campaign), "npc": str(hook.get("patron_id", "")),
			"hook": hook, "vars": StoryText.mission_vars(story, campaign, outcome)}))
	return events


## Book: every pilot moves up one License Level after a mission, success or not, and gets
## +2 to a trigger (or a new +2), +1 mech skill, +1 talent rank, +1 license rank; a core
## bonus at LL 3, 6, 9 and 12 (Core p.18). Talent, license and core bonus picks are made in
## the pilot builder; this records them as pending.
func _level_up(story: StoryState, campaign: Campaign) -> Array:
	var events: Array = []
	var ids := campaign.pilots.keys()
	ids.sort()
	for pid: String in ids:
		if not story.is_alive(pid):
			continue
		if not campaign.level_up(pid):
			continue
		var ll := int(campaign.pilots[pid]["ll"])
		var picks := {"trigger": 1, "mech_skill": 1, "talent": 1, "license": 1, "core_bonus": 1 if ll % 3 == 0 else 0}
		var old: Dictionary = story.pending_picks.get(pid, {})
		for k: String in ["talent", "license", "core_bonus"]:
			picks[k] = int(picks[k]) + int(old.get(k, 0))
		story.pending_picks[pid] = picks
		events.append({"type": "level_up", "pilot": pid, "ll": ll, "grit": UnitFactory.grit(ll), "picks": picks.duplicate(),
			"rule_ref": "Core p.18: leveling up"})
		var seat := story.seat_of(pid)
		if seat != "" and story.is_ai(seat):
			events.append_array(_ai_level_picks(campaign, pid, picks))
	story.phase = "level_up"
	if story.flags.has("_ending_due"):
		var why := str(story.flags["_ending_due"])
		story.flags.erase("_ending_due")
		events.append_array(Ending.conclude(story, campaign, why))
	return events


## An AI squadmate's level-up picks: +2 to its best trigger that can still grow (else a new
## one), +1 to its lowest mech skill. (Talents and licenses: the builder, as for everyone.)
func _ai_level_picks(campaign: Campaign, pid: String, picks: Dictionary) -> Array:
	var pilot: Dictionary = campaign.pilots[pid]
	var grow := NarrativeCheck.triggers_of(pilot).filter(func(t: Dictionary) -> bool: return int(t["rank"]) < 3)
	var trig := str(grow[0]["id"]) if not grow.is_empty() else "sk_spot"
	pilot["skills"][trig] = int(pilot["skills"].get(trig, 0)) + 1
	var low := "hull"
	for k: String in MECH_SKILLS:
		if int(pilot.get(k, 0)) < int(pilot.get(low, 0)):
			low = k
	pilot[low] = int(pilot.get(low, 0)) + 1
	picks["trigger"] = 0
	picks["mech_skill"] = 0
	return [{"type": "trigger_improved", "pilot": pid, "trigger": trig, "bonus": int(pilot["skills"][trig]) * 2, "ai": true},
		{"type": "mech_skill_improved", "pilot": pid, "skill": low, "value": pilot[low], "ai": true}]


## AI squadmates decide their part of the open conversation and their downtime choices.
func _run_ai(story: StoryState, campaign: Campaign) -> Array:
	var events: Array = []
	var guard := 0
	while guard < 8 and Dialogue.is_open(story) and not Dialogue.offered(story).is_empty():
		guard += 1
		var d := Dialogue.decider(story, campaign)
		if d["mode"] == "speaker":
			var s := str(d["speaker_seat"])
			if s == "" or not story.is_ai(s):
				break
			var pick := Dialogue.ai_pick(story, campaign, s)
			events.append({"type": "ai_chose", "seat": s, "choice": pick["choice"], "why": pick["why"]})
			events.append_array(_downtime_follow(story, campaign, Dialogue.resolve_choice(story, campaign, pick["choice"], s)))
			continue
		var cast := false
		for s: String in d["seats"]:
			if story.is_ai(s) and not story.dialogue["votes"].has(s):
				var pick := Dialogue.ai_pick(story, campaign, s)
				story.dialogue["votes"][s] = pick["choice"]
				events.append({"type": "dialogue_vote", "seat": s, "choice": pick["choice"], "why": pick["why"], "ai": true})
				cast = true
		var winner := Dialogue.vote_result(story, campaign)
		if winner != "":
			events.append_array(_downtime_follow(story, campaign, Dialogue.resolve_choice(story, campaign, winner, "vote")))
			continue
		if not cast:
			break
	# Pending downtime choices that belong to an AI squadmate: take the first fitting option.
	guard = 0
	while guard < 16:
		guard += 1
		var pc: Dictionary = {}
		for c: Dictionary in story.all_choices():
			var s := story.seat_of(str(c.get("pilot", "")))
			if s != "" and story.is_ai(s):
				pc = c
				break
		if pc.is_empty():
			break
		var seat := story.seat_of(str(pc.get("pilot", "")))
		var opts: Array = pc.get("options", [])
		var n := int(pc.get("count", 1))
		# Least harmful first (no standing lost, no harm, no new trouble), ties broken by the dice.
		var ranked: Array = []
		for o: Dictionary in opts:
			ranked.append({"id": o["id"], "score": _option_cost(o) * 10 + story.dice.die(6)})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
		var uniq: Array = ranked.slice(0, n).map(func(x: Dictionary) -> Variant: return x["id"])
		events.append({"type": "ai_chose", "seat": seat, "picks": uniq, "why": "AI squadmate's downtime choice"})
		events.append_array(Downtime.choose(story, campaign, uniq, str(pc.get("pilot", ""))))
	return events


## How much a downtime option hurts the squad, for AI picks: lost standing, harm, new trouble.
## "Lose" steps count what's lost; "gain" steps prefer what's useful (reserves).
static func _option_cost(o: Dictionary) -> int:
	var cost := 0
	for e: Dictionary in (o.get("effects", []) as Array) + (o.get("lose_effects", []) as Array):
		if e.has("standing") and int(e.get("add", 0)) < 0:
			cost += 2
		if e.has("harm") or e.has("hook"):
			cost += 1
	if o.has("org") and (bool(o["org"].get("fold", false)) or int(o["org"].get("efficiency", 0)) < 0):
		cost += 3
	return cost


## AI squadmates spend their downtime actions in character (personas.json "downtime"):
## the first preferred action that's possible, with one of the book-flavored subjects.
func _ai_downtime(story: StoryState, campaign: Campaign) -> Array:
	var events: Array = []
	var seats := story.seats.keys()
	seats.sort()
	for s: String in seats:
		var pid := story.pilot_of_seat(s)
		if not story.is_ai(s) or not story.is_alive(pid):
			continue
		var persona: Dictionary = Dialogue.personas().get(str(story.seats[s].get("persona", "steady")), {})
		var guard := 0
		while int(story.downtime.get("actions_left", {}).get(pid, 0)) > 0 and guard < 4:
			guard += 1
			var done := false
			for want: Variant in Squadmate.downtime_prefs(story, pid, persona):
				var aid := str(want).split(":")[0]
				var params := _ai_params(story, campaign, pid, aid)
				if ":" in str(want):
					params["subject"] = str(want).split(":")[1]
				if Downtime.refusal(story, campaign, pid, str(aid), params).is_empty():
					events.append({"type": "ai_chose", "seat": s, "action": aid, "why": "%s spends downtime on %s." % [campaign.pilots[pid].get("callsign", ""), Downtime.book(str(aid)).get("name", aid)]})
					events.append_array(Downtime.perform(story, campaign, pid, str(aid), params))
					events.append_array(_run_ai(story, campaign))
					done = true
					break
			if not done:
				break
	return events


func _ai_params(story: StoryState, campaign: Campaign, pid: String, aid: String) -> Dictionary:
	var cfg := Downtime.action_cfg(aid)
	var pilot: Dictionary = campaign.pilots[pid]
	var params := {"pilot": pid, "action": aid}
	var presets: Array = cfg.get("subject_presets", [])
	if not presets.is_empty():
		var pick: Variant = presets[story.dice.die(presets.size()) - 1]
		params["subject"] = str(pick["label"]) if pick is Dictionary else str(pick)
	var best := NarrativeCheck.pick_trigger(pilot, cfg.get("triggers", []))
	if str(best["id"]) != "":
		params["use_trigger"] = best["id"]
	match aid:
		"dt_get_focused":
			var t := NarrativeCheck.triggers_of(pilot).filter(func(x: Dictionary) -> bool: return int(x["rank"]) < 3)
			params["trigger"] = str(t[0]["id"]) if not t.is_empty() else "sk_spot"
		"dt_get_connected":
			var c: Array = story.contacts.filter(func(n: String) -> bool: return not bool(story.npcs.get(n, {}).get("dead", false)))
			if not c.is_empty():
				params["npc"] = c[story.dice.die(c.size()) - 1]
				params["subject"] = params["npc"]
	return params


## Pilot gear limits (Core p.108): one set of armor, two weapons, three other pieces.
func gear_problem(gear: Array) -> String:
	if db == null:
		return ""
	var counts := {"Armor": 0, "Weapon": 0, "Gear": 0}
	for gid: Variant in gear:
		var g := db.get_entry("pilot_gear", str(gid))
		if g.is_empty():
			return "Unknown pilot gear '%s'." % gid
		counts[str(g.get("type", "Gear"))] = int(counts.get(str(g.get("type", "Gear")), 0)) + 1
	if int(counts["Armor"]) > 1:
		return "Pilots can wear only one set of personal armor."
	if int(counts["Weapon"]) > 2:
		return "Pilots can carry up to two weapons."
	if int(counts["Gear"]) > 3:
		return "Pilots can carry up to three other pieces of gear."
	return ""


func _able(story: StoryState, campaign: Campaign, pid: String) -> Dictionary:
	if pid == "" or not campaign.pilots.has(pid):
		return _no("Pick a pilot first (no pilot in this seat).")
	if not story.is_alive(pid):
		return _no("%s is dead." % campaign.pilots[pid].get("name", "That pilot"), "Core p.49")
	if story.down_and_out.has(pid):
		return _no("%s is Down and Out: unconscious and unable to act until they rest for an hour." % campaign.pilots[pid].get("callsign", "That pilot"), "Core p.49: down and out")
	return {}


## Whose choice a downtime_choose answers: params.pilot, else the seat's own pilot, else
## (for the host) the head of the queue.
func _choice_pilot(story: StoryState, seat: String, p: Dictionary) -> String:
	if str(p.get("pilot", "")) != "":
		return str(p["pilot"])
	var mine := story.pilot_of_seat(seat)
	if mine != "" and not story.first_choice_for(mine).is_empty():
		return mine
	return str(story.pending_choice.get("pilot", ""))


func _controls(story: StoryState, seat: String, pid: String) -> bool:
	return seat == "gm" or story.pilot_of_seat(seat) == pid


func _first_alive(story: StoryState, campaign: Campaign) -> String:
	var seats := story.seats.keys()
	seats.sort()
	for s: String in seats:
		var pid := story.pilot_of_seat(s)
		if story.is_alive(pid):
			return pid
	for pid: String in campaign.pilots:
		if story.is_alive(pid):
			return pid
	return ""


static func _no(reason: String, ref: String = "") -> Dictionary:
	return {"reason": reason, "rule_ref": ref}
