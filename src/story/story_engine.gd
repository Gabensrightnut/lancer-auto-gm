class_name StoryEngine
extends RefCounted
## The only thing that changes a StoryState, the way RulesEngine is the only thing that
## changes a GameState. Players, AI squadmates and network clients all submit actions:
##   {"type": "talk", "seat": "p1", "params": {"npc": "hub_1_npc0"}}
## and get {"ok", "reason", "rule_ref", "events"}. Illegal actions are refused with a reason.
## The host runs it; clients get the events (and StoryView.view_for for their seat).
##
## Actions (params):
##   set_seat {seat, pilot, ai, persona}             enter_hub {kind, seed}
##   talk {npc}                                      dialogue_next {}
##   dialogue_choose {choice}                        skill_check {goal, label, skills, tags, difficult, risky, heroic, consequence}
##   rest {}                                         set_pilot_gear {pilot, gear: [ids]}
##   choose_hook {hook}                              confirm_reserves {}
##   mission_finished {outcome, reason, dead: [pilot ids], down: [pilot ids]}
##   level_up {}                                     level_picks {pilot, trigger, mech_skill}
##   start_downtime {long}                           downtime_action {pilot, action, ...action params}
##   downtime_choose {picks: [option ids]}           end_downtime {}
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
			var pc := story.pending_choice
			if pc.is_empty():
				return _no("Nothing is waiting for a choice.")
			if str(pc.get("chooser", "player")) == "player" and not _controls(story, seat, str(pc.get("pilot", ""))):
				return _no("This choice belongs to %s's player." % campaign.pilots.get(str(pc.get("pilot", "")), {}).get("callsign", "another pilot"))
			var r := Downtime.choice_refusal(story, p.get("picks", []))
			if not r.is_empty():
				return r
		"end_downtime":
			if story.phase != "downtime":
				return _no("Not in downtime.")
			if not story.pending_choice.is_empty():
				return _no("A downtime result is still waiting for a choice.")
		_:
			return _no("Unknown story action '%s'." % type)
	return {}


func _resolve(story: StoryState, campaign: Campaign, action: Dictionary) -> Array:
	var seat := str(action.get("seat", "gm"))
	var p: Dictionary = action.get("params", {})
	var me := story.pilot_of_seat(seat)
	match str(action["type"]):
		"set_seat":
			story.seats[str(p.get("seat", seat))] = {"pilot": str(p["pilot"]), "ai": bool(p.get("ai", false)), "persona": str(p.get("persona", "steady"))}
			return [{"type": "seat_set", "seat": p.get("seat", seat), "pilot": p["pilot"], "ai": bool(p.get("ai", false))}]
		"enter_hub":
			var events: Array = []
			if story.hub.is_empty() or int(story.hub.get("seed", -1)) != int(p.get("seed", story.hub.get("seed", 0))):
				NpcGen.make_hub(story, campaign, int(p.get("seed", story.mission_number)), str(p.get("kind", "town")))
				events.append({"type": "hub_entered", "hub": story.hub.duplicate(true)})
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
		"skill_check":
			var opts := p.duplicate(true)
			if bool(p.get("push", false)):
				var push := NarrativeCheck.push_level(str(story.failed_goals.get(str(p["goal"]), "normal")), bool(campaign.options.get("allow_heroic_push", true)))
				opts["risky"] = push["level"] == "risky"
				opts["heroic"] = push["level"] == "heroic"
			var rec := NarrativeCheck.roll(story.dice, campaign.pilots[me], opts)
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
			if not Dialogue.is_open(story) and not Dialogue.scene("briefing").is_empty():
				events.append_array(Dialogue.start(story, campaign, "briefing", {"speaker": _first_alive(story, campaign), "npc": str(story.current_hook.get("patron_id", "")), "hook": story.current_hook}))
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
			if not story.hub.is_empty():
				for h: Dictionary in MissionHooks.fill_board(story, campaign):
					events.append({"type": "hook_added", "hook": h})
			return events
		"downtime_action":
			var pid := str(p.get("pilot", me))
			return Downtime.perform(story, campaign, pid, str(p["action"]), p)
		"downtime_choose":
			return Downtime.choose(story, campaign, p.get("picks", []))
		"end_downtime":
			story.phase = "briefing"
			var events: Array = [{"type": "downtime_ended", "rule_ref": REF_FLOW}]
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
	story.last_mission = {"number": story.mission_number, "outcome": outcome, "reason": str(p.get("reason", "")), "hook": hook.get("title", "")}
	story.current_hook = {}
	story.mission_number += 1
	story.phase = "debrief"
	if not Dialogue.scene("debrief").is_empty():
		events.append_array(Dialogue.start(story, campaign, "debrief", {"speaker": _first_alive(story, campaign), "npc": str(hook.get("patron_id", "")),
			"hook": hook, "vars": {"outcome": outcome}}))
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
	while guard < 8 and not story.pending_choice.is_empty():
		guard += 1
		var seat := story.seat_of(str(story.pending_choice.get("pilot", "")))
		if seat == "" or not story.is_ai(seat):
			break
		var opts: Array = story.pending_choice.get("options", [])
		var n := int(story.pending_choice.get("count", 1))
		# Least harmful first (no standing lost, no harm, no new trouble), ties broken by the dice.
		var ranked: Array = []
		for o: Dictionary in opts:
			ranked.append({"id": o["id"], "score": _option_cost(o) * 10 + story.dice.die(6)})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
		var uniq: Array = ranked.slice(0, n).map(func(x: Dictionary) -> Variant: return x["id"])
		events.append({"type": "ai_chose", "seat": seat, "picks": uniq, "why": "AI squadmate's downtime choice"})
		events.append_array(Downtime.choose(story, campaign, uniq))
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
			for aid: Variant in persona.get("downtime", ["dt_get_focused"]):
				var params := _ai_params(story, campaign, pid, str(aid))
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
