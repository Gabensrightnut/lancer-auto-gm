class_name Downtime
extends RefCounted
## The book's downtime (Core p.50-55), driven by data/game/story/downtime.json and Massif's
## data/lancer-data/downtime_actions.json. Called by StoryEngine, which checks the phase.
##
## - Starting downtime gives every living pilot one downtime action (two in a long downtime,
##   Core p.50), and a FULL REPAIR: the squad has 10+ hours somewhere secure (Core p.82), so
##   pilot HP comes back and Down and Out ends.
## - Each action rolls 1d20 + a relevant trigger (triggers still apply, Core p.53) and gives
##   the result for 9 or less / 10-19 / 20+. Lists the book says "choose" from become a
##   pending choice for the pilot's player; Power at a Cost's costs are the GM's pick.
## - "Next time you get this result for the same ..., treat it as ..." is remembered per
##   situation / project / organization.
## - Organizations roll every downtime after the first; that roll isn't an action (Core p.55).
## PROVISIONAL (src/story/README.md): finishing a 10-19 Get Creative project next downtime
## uses that downtime's action; the organization roll adds no trigger.

const FILE := "res://data/game/story/downtime.json"
const BOOK_FILE := "res://data/lancer-data/downtime_actions.json"
const REF := "Core p.53-55: downtime actions"

static var _cfg: Dictionary = {}
static var _book: Dictionary = {}


static func config() -> Dictionary:
	if _cfg.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_cfg = data if data is Dictionary else {"actions": {}}
	return _cfg


static func action_cfg(action_id: String) -> Dictionary:
	return config().get("actions", {}).get(action_id, {})


## Massif's entry for the action: {id, name, terse, detail, table}.
static func book(action_id: String) -> Dictionary:
	if _book.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOOK_FILE))
		for a: Dictionary in (data if data is Array else []):
			_book[str(a["id"])] = a
	return _book.get(action_id, {})


static func action_ids() -> Array:
	var ids: Array = config().get("actions", {}).keys()
	ids.sort()
	return ids


static func band_of(total: int) -> String:
	if total >= 20:
		return "high"
	return "mid" if total >= 10 else "low"


# --- Starting downtime -------------------------------------------------------------------

static func start(story: StoryState, campaign: Campaign, long_downtime: bool = false) -> Array:
	var cfg := config()
	var n := int(cfg.get("long_downtime_actions", 2)) if long_downtime else int(cfg.get("actions_per_downtime", 1))
	var events: Array = [{"type": "downtime_started", "actions": n, "long": long_downtime, "rule_ref": "Core p.50: downtime",
		"narration": StoryText.line("@downtime_intro", story, campaign, {})}]
	story.downtime["log"] = []
	story.downtime["intro"] = events[0]["narration"]
	var left := {}
	var ids := campaign.pilots.keys()
	ids.sort()
	for pid: String in ids:
		if not story.is_alive(pid):
			continue
		left[pid] = n
		story.pilot_hp.erase(pid)
		story.down_and_out.erase(pid)
		events.append({"type": "full_repair", "pilot": pid, "hp": StoryEffects.max_hp(campaign.pilots[pid]), "rule_ref": "Core p.82: full repair"})
	story.downtime["actions_left"] = left
	story.downtime["queue"] = []
	story.pending_choice = {}
	# Organizations started in an earlier downtime roll now (not an action).
	for pid: String in story.downtime.get("orgs", {}):
		if not story.is_alive(pid):
			continue
		for org: Dictionary in story.downtime["orgs"][pid]:
			if not bool(org.get("folded", false)) and int(org.get("started", 0)) < story.mission_number:
				events.append_array(_org_roll(story, campaign, pid, org))
	return events


# --- Doing an action ---------------------------------------------------------------------

## Why this pilot can't take this action now ("" if they can).
static func refusal(story: StoryState, campaign: Campaign, pid: String, action_id: String, params: Dictionary) -> Dictionary:
	var cfg := action_cfg(action_id)
	if cfg.is_empty():
		return _no("There's no downtime action called %s." % action_id, REF)
	if not campaign.pilots.has(pid) or not story.is_alive(pid):
		return _no("That pilot isn't available.", REF)
	var in_mission := action_id == "dt_power_at_a_cost" and story.phase == "mission"
	if story.phase != "downtime" and not in_mission:
		return _no("Downtime actions happen in downtime, between missions. (Power at a Cost also works during a mission.)", "Core p.53")
	if not in_mission and int(story.downtime.get("actions_left", {}).get(pid, 0)) <= 0:
		return _no("%s has already used their downtime action. Usually a pilot gets one per downtime." % campaign.pilots[pid].get("name", "This pilot"), "Core p.53")
	if not story.first_choice_for(pid).is_empty():
		return _no("Finish the choice that's waiting for you first.", REF)
	if cfg.has("requires") and not StoryConditions.check(cfg["requires"], story, campaign, {"speaker": pid}):
		return _no(str(cfg.get("requires_reason", "Not possible here.")), REF)
	if bool(cfg.get("requires_contact", false)):
		var npc := str(params.get("npc", ""))
		if npc == "" or not story.contacts.has(npc):
			return _no(str(cfg.get("requires_reason", "You need a contact.")), "Core p.55")
	var trig := str(params.get("use_trigger", ""))
	if trig != "" and not (cfg.get("triggers", []) as Array).has(trig):
		return _no("The GM doesn't see how %s helps with %s. Pick a trigger that fits." % [NarrativeCheck.trigger_name(trig), book(action_id).get("name", action_id)], "Core p.25: the GM arbitrates triggers")
	if trig != "" and int(campaign.pilots[pid].get("skills", {}).get(trig, 0)) <= 0:
		return _no("This pilot doesn't have that trigger.", "Core p.25")
	match action_id:
		"dt_get_focused":
			var t := str(params.get("trigger", ""))
			if t == "" or t == "custom:":
				return _no("Name what you want to learn or improve.", "Core p.55: Get Focused")
			if int(campaign.pilots[pid].get("skills", {}).get(t, 0)) >= int(cfg.get("max_rank", 3)):
				return _no("That trigger is already +6, the most it can be.", "Core p.55: Get Focused")
		"dt_get_organized":
			if not (cfg.get("focuses", []) as Array).has(str(params.get("focus", ""))):
				return _no("Choose a focus: %s." % ", ".join(PackedStringArray(cfg.get("focuses", []))), "Core p.55: Get Organized")
		"dt_get_creative":
			var key := _key(action_id, params)
			if str(params.get("finish", "")) != "":
				var proj: Dictionary = story.downtime.get("projects", {}).get(str(params["finish"]), {})
				if proj.is_empty() or str(proj.get("state", "")) != "in_progress" or int(proj.get("since", 0)) >= story.mission_number:
					return _no("That project can only be finished in a later downtime, after you've made progress on it.", "Core p.54: Get Creative")
			elif str(story.downtime.get("projects", {}).get(key, {}).get("state", "")) == "done":
				return _no("That project is already finished.", "Core p.54")
	if not ["dt_get_focused", "dt_get_organized"].has(action_id) and str(params.get("finish", "")) == "" and _subject(params) == "":
		return _no(str(cfg.get("subject_prompt", "Say what you're doing.")), REF)
	return {}


static func perform(story: StoryState, campaign: Campaign, pid: String, action_id: String, params: Dictionary) -> Array:
	var events := _perform(story, campaign, pid, action_id, params)
	# Tell it as a story: one narrated line per result, kept for the downtime screen and the next briefing.
	for e: Dictionary in events:
		if str(e.get("type", "")) == "downtime_result" and not e.has("narration"):
			var pool := action_id + ("_" + str(e["band"]) if e.has("band") else "")
			var ctx := {"speaker": pid, "npc": str(params.get("npc", "")), "vars": {"subject": str(e.get("subject", ""))}}
			e["narration"] = StoryText.line("@" + pool, story, campaign, ctx) if StoryText.pools().has(pool) else str(e.get("summary", ""))
			if not story.downtime.has("log"):
				story.downtime["log"] = []
			(story.downtime["log"] as Array).append({"pilot": pid, "action": action_id, "band": e.get("band", ""), "text": e["narration"]})
	return events


static func _perform(story: StoryState, campaign: Campaign, pid: String, action_id: String, params: Dictionary) -> Array:
	var cfg := action_cfg(action_id)
	var pilot: Dictionary = campaign.pilots[pid]
	var subject := _subject(params)
	var ctx := {"speaker": pid, "npc": str(params.get("npc", "")), "vars": {"subject": subject},
		"preset_reserve": _preset_reserve(cfg, params)}
	if action_id == "dt_get_connected":
		ctx["vars"]["subject"] = str(story.npcs.get(ctx["npc"], {}).get("name", subject))
	if story.phase == "downtime":
		story.downtime["actions_left"][pid] = int(story.downtime["actions_left"].get(pid, 1)) - 1
	var name := str(book(action_id).get("name", action_id))
	var events: Array = []
	match action_id:
		"dt_get_focused":
			var t := str(params["trigger"])
			var skills: Dictionary = pilot["skills"]
			skills[t] = int(skills.get(t, 0)) + 1
			events.append({"type": "downtime_result", "pilot": pid, "action": action_id, "name": name, "subject": NarrativeCheck.trigger_name(t),
				"summary": "%s is now +%d." % [NarrativeCheck.trigger_name(t), int(skills[t]) * 2], "rule_ref": "Core p.55: Get Focused"})
			return events
		"dt_power_at_a_cost":
			return _power_at_a_cost(story, campaign, pid, cfg, params, ctx, name)
		"dt_get_organized":
			return _start_org(story, pid, cfg, params, name)
	if action_id == "dt_get_creative" and str(params.get("finish", "")) != "":
		var proj: Dictionary = story.downtime["projects"][str(params["finish"])]
		proj["state"] = "done"
		ctx["vars"]["subject"] = proj["name"]
		events.append({"type": "downtime_result", "pilot": pid, "action": action_id, "name": name, "subject": proj["name"],
			"summary": "You finish the project without rolling.", "rule_ref": "Core p.54: Get Creative"})
		events.append_array(StoryEffects.apply({"reserve": "custom", "name": "{subject}", "source": "Get Creative"}, story, campaign, ctx))
		return events

	var check := NarrativeCheck.roll(story.dice, pilot, {"skills": cfg.get("triggers", []), "use_trigger": str(params.get("use_trigger", "")),
		"tags": params.get("tags", []), "label": "%s: %s" % [name, ctx["vars"]["subject"]]})
	check["rule_ref"] = REF
	var band := band_of(int(check["total"]))
	var treated := _apply_memory(story, cfg, action_id, params, ctx, band)
	var band_cfg: Dictionary = cfg.get("bands", {}).get(treated, {})
	var ev := {"type": "downtime_result", "pilot": pid, "action": action_id, "name": name, "subject": ctx["vars"]["subject"],
		"check": check, "band": treated, "rolled_band": band, "summary": str(band_cfg.get("summary", "")),
		"book_text": _book_text(action_id, treated), "rule_ref": REF}
	if treated != band:
		ev["memory_note"] = "You've had this result before for the same %s, so the book says to treat it as %s." % [cfg.get("subject", "thing"), _band_words(treated)]
	events.append(ev)
	events.append_array(_apply_band(story, campaign, pid, action_id, cfg, band_cfg, ctx, params))
	return events


## Answers a pending choice with the picked option ids: the first one waiting for `pid`
## ("" = the one at the head of the queue).
static func choose(story: StoryState, campaign: Campaign, picks: Array, pid: String = "") -> Array:
	var pc := story.pending_choice if pid == "" else story.first_choice_for(pid)
	_take(story, pc)
	var ctx: Dictionary = pc.get("ctx", {})
	var events: Array = []
	var by_id := {}
	for o: Dictionary in pc.get("options", []):
		by_id[str(o["id"])] = o
	var step := str(pc.get("step", "options"))
	var chosen: Array = []
	for pick: Variant in picks:
		chosen.append(by_id[str(pick)])
	events.append({"type": "downtime_choice", "pilot": pc.get("pilot", ""), "action": pc.get("action", ""), "step": step,
		"picked": chosen.map(func(o: Dictionary) -> String: return str(o["label"]))})
	match step:
		"gain":
			for o: Dictionary in chosen:
				events.append_array(StoryEffects.apply_all(o.get("effects", []), story, campaign, ctx))
		"lose":
			for o: Dictionary in chosen:
				events.append_array(StoryEffects.apply_all(o.get("lose_effects", []), story, campaign, ctx))
		"needs":
			var proj: Dictionary = story.downtime["projects"][str(pc["project"])]
			proj["needs"] = chosen.map(func(o: Dictionary) -> String: return str(o["label"]))
		"help":
			for o: Dictionary in chosen:
				events.append_array(StoryEffects.apply({"reserve": str(o["id"]), "source": "$npc.name",
					"note": "From {npc} ({npc_faction})"}, story, campaign, ctx))
		"org":
			for o: Dictionary in chosen:
				events.append_array(_org_change(story, pc, o.get("org", {})))
				events.append_array(StoryEffects.apply_all(o.get("effects", []), story, campaign, ctx))
		_:
			for o: Dictionary in chosen:
				events.append_array(StoryEffects.apply_all(o.get("effects", []), story, campaign, ctx))
				if bool(o.get("help", false)):
					events.append_array(_help(story, campaign, ctx))
	# "Lose one" may not be the thing just gained (Get a Damn Drink).
	var then: Array = pc.get("then", [])
	var front: Array = []
	for nxt: Dictionary in then:
		if str(nxt.get("step", "")) == "lose":
			var gained: Array = picks.map(func(x: Variant) -> String: return str(x))
			nxt["options"] = (nxt["options"] as Array).filter(func(o: Dictionary) -> bool: return not gained.has(str(o["id"])))
		if not (nxt.get("options", []) as Array).is_empty():
			front.append(nxt)
	# Follow-up steps come next for the same pilot.
	if not front.is_empty():
		if not story.downtime.has("queue"):
			story.downtime["queue"] = []
		for i in range(front.size() - 1, -1, -1):
			(story.downtime["queue"] as Array).push_front(front[i])
	if story.pending_choice.is_empty():
		_pop(story)
	return events


## Takes a pending choice out of the head or the queue.
static func _take(story: StoryState, pc: Dictionary) -> void:
	if pc.is_empty():
		return
	if story.pending_choice == pc:
		story.pending_choice = {}
		_pop(story)
		return
	var q: Array = story.downtime.get("queue", [])
	var i := q.find(pc)
	if i >= 0:
		q.remove_at(i)


## {"ok", "reason"} for a pick list against the pending choice (the first one for `pid`).
static func choice_refusal(story: StoryState, picks: Array, pid: String = "") -> Dictionary:
	var pc := story.pending_choice if pid == "" else story.first_choice_for(pid)
	if pc.is_empty():
		return _no("Nothing is waiting for a choice.", REF)
	if picks.size() != int(pc.get("count", 1)):
		return _no("Choose %d." % int(pc.get("count", 1)), REF)
	var ids := {}
	for o: Dictionary in pc.get("options", []):
		ids[str(o["id"])] = true
	var seen := {}
	for p: Variant in picks:
		if not ids.has(str(p)) or seen.has(str(p)):
			return _no("That isn't one of the options.", REF)
		seen[str(p)] = true
	return {}


# --- Pieces ------------------------------------------------------------------------------

static func _apply_band(story: StoryState, campaign: Campaign, pid: String, action_id: String, cfg: Dictionary, band_cfg: Dictionary, ctx: Dictionary, params: Dictionary) -> Array:
	var events: Array = []
	var effects: Array = band_cfg.get("effects", [])
	var plain: Array = []
	var help := false
	for e: Dictionary in effects:
		if e.has("help"):
			help = true
		else:
			plain.append(e)
	events.append_array(StoryEffects.apply_all(plain, story, campaign, ctx))
	if help:
		events.append_array(_help(story, campaign, ctx))
	if band_cfg.has("options"):
		var opts: Array = []
		for o: Dictionary in band_cfg["options"]:
			var oo := o.duplicate(true)
			if (oo.get("effects", []) as Array).any(func(x: Dictionary) -> bool: return x.has("help")):
				oo["help"] = true
				oo["effects"] = (oo["effects"] as Array).filter(func(x: Dictionary) -> bool: return not x.has("help"))
			opts.append(oo)
		_push(story, {"pilot": pid, "action": action_id, "step": "options", "options": opts, "count": int(band_cfg.get("choose", 1)),
			"prompt": str(band_cfg.get("summary", "Choose.")), "ctx": ctx, "chooser": "player"})
	if band_cfg.has("gain"):
		var gains: Array = cfg.get("gains", [])
		var then: Array = []
		if int(band_cfg.get("lose", 0)) > 0:
			then.append({"pilot": pid, "action": action_id, "step": "lose", "options": gains.duplicate(true), "count": int(band_cfg["lose"]),
				"prompt": "Choose what you lose.", "ctx": ctx, "chooser": "player"})
		_push(story, {"pilot": pid, "action": action_id, "step": "gain", "options": gains.duplicate(true), "count": int(band_cfg["gain"]),
			"prompt": "Choose what you gain as reserves.", "ctx": ctx, "chooser": "player", "then": then})
	if action_id == "dt_get_creative":
		var key := _key(action_id, params)
		var needs := int(band_cfg.get("project_needs", 0))
		if band_cfg.has("complex_needs") and bool(params.get("complex", false)):
			needs = int(band_cfg["complex_needs"])
			# An especially complex project: treat 20+ as 10-19 but choose only one need. Undo the reserve.
			_drop_last_reserve(story, campaign, pid)
			events = events.filter(func(x: Dictionary) -> bool: return str(x.get("type", "")) != "reserve_gained")
		if needs > 0:
			story.downtime["projects"][key] = {"name": ctx["vars"]["subject"], "pilot": pid, "state": "in_progress", "since": story.mission_number, "needs": []}
			var options: Array = []
			for i in range((cfg.get("needs", []) as Array).size()):
				options.append({"id": "need%d" % i, "label": cfg["needs"][i]})
			_push(story, {"pilot": pid, "action": action_id, "step": "needs", "options": options, "count": needs, "project": key,
				"prompt": "Choose what you'll need to finish it.", "ctx": ctx, "chooser": "player"})
		elif not band_cfg.has("project_needs") and band_cfg.has("effects"):
			story.downtime["projects"][key] = {"name": ctx["vars"]["subject"], "pilot": pid, "state": "done", "since": story.mission_number}
	return events


## Get Connected: the contact helps. They offer what their role can give; better standing
## opens more (our own bookkeeping, see README). Picking one is the player's choice.
static func _help(story: StoryState, campaign: Campaign, ctx: Dictionary) -> Array:
	var npc: Dictionary = story.npcs.get(str(ctx.get("npc", "")), {})
	var offers: Array = (npc.get("offers", ["reserve_backing"]) as Array).duplicate()
	if story.get_standing(str(npc.get("faction", ""))) >= 2:
		for o: String in npc.get("trusted_offers", []):
			if not offers.has(o):
				offers.append(o)
	var options: Array = []
	for rid: String in offers:
		options.append({"id": rid, "label": StoryEffects.reserve_name(rid), "detail": StoryEffects.reserve_description(rid)})
	_push(story, {"pilot": ctx.get("speaker", ""), "action": "dt_get_connected", "step": "help", "options": options, "count": 1,
		"prompt": "What does %s help you with? (a reserve for the next mission)" % npc.get("name", "your contact"), "ctx": ctx, "chooser": "player"})
	return [{"type": "contact_helps", "npc": ctx.get("npc", ""), "offers": offers}]


static func _power_at_a_cost(story: StoryState, campaign: Campaign, pid: String, cfg: Dictionary, params: Dictionary, ctx: Dictionary, name: String) -> Array:
	var scale := str(params.get("scale", "modest"))
	var n := int(cfg.get("costs_by_scale", {}).get(scale, 1))
	var costs: Array = (cfg.get("costs", []) as Array).duplicate(true)
	var picked: Array = []
	for i in range(mini(n, costs.size())):
		picked.append(costs.pop_at(story.dice.die(costs.size()) - 1))
	var events: Array = [{"type": "downtime_result", "pilot": pid, "action": "dt_power_at_a_cost", "name": name, "subject": ctx["vars"]["subject"],
		"summary": "You can get it, but the GM chooses the cost: " + "; ".join(PackedStringArray(picked.map(func(c: Dictionary) -> String: return str(c["label"])))) + ".",
		"costs": picked, "rule_ref": "Core p.53: Power at a Cost"}]
	for c: Dictionary in picked:
		events.append_array(StoryEffects.apply_all(c.get("effects", []), story, campaign, ctx))
	events.append_array(StoryEffects.apply_all(cfg.get("effects", []), story, campaign, ctx))
	return events


static func _start_org(story: StoryState, pid: String, cfg: Dictionary, params: Dictionary, name: String) -> Array:
	var start := int(cfg.get("start", 2))
	var eff_first := str(params.get("start_stat", "efficiency")) == "efficiency"
	var org := {"name": _subject(params) if _subject(params) != "" else "Unnamed venture", "focus": str(params["focus"]),
		"efficiency": start if eff_first else 0, "influence": 0 if eff_first else start, "started": story.mission_number, "folded": false}
	if not story.downtime.has("orgs"):
		story.downtime["orgs"] = {}
	if not story.downtime["orgs"].has(pid):
		story.downtime["orgs"][pid] = []
	(story.downtime["orgs"][pid] as Array).append(org)
	return [{"type": "downtime_result", "pilot": pid, "action": "dt_get_organized", "name": name, "subject": org["name"],
		"summary": "%s (%s) starts with Efficiency +%d, Influence +%d." % [org["name"], org["focus"], org["efficiency"], org["influence"]],
		"org": org.duplicate(), "rule_ref": "Core p.55: Get Organized"}]


static func _org_roll(story: StoryState, _campaign: Campaign, pid: String, org: Dictionary) -> Array:
	var cfg := action_cfg("dt_get_organized")
	var roll := story.dice.check(0, 0, 0, 10, [])
	roll["label"] = "Organization: %s" % org["name"]
	var band := band_of(int(roll["total"]))
	var band_cfg: Dictionary = cfg.get("bands", {}).get(band, {})
	var events: Array = [{"type": "org_roll", "pilot": pid, "org": org["name"], "check": roll, "band": band,
		"summary": str(band_cfg.get("summary", "")), "rule_ref": "Core p.55: Get Organized (not a downtime action)"}]
	var idx := (story.downtime["orgs"][pid] as Array).find(org)
	if band_cfg.has("org"):
		events.append_array(_org_change(story, {"pilot": pid, "org_index": idx}, band_cfg["org"]))
	if band_cfg.has("options"):
		var opts: Array = []
		for o: Dictionary in band_cfg["options"]:
			if bool(o.get("needs_points", false)) and int(org["efficiency"]) == 0 and int(org["influence"]) == 0:
				continue  # "If both are already at 0, you may not choose this."
			opts.append(o.duplicate(true))
		_push(story, {"pilot": pid, "action": "dt_get_organized", "step": "org", "org_index": idx, "options": opts, "count": 1,
			"prompt": "%s: %s" % [org["name"], band_cfg.get("summary", "")], "ctx": {"speaker": pid}, "chooser": "player"})
	return events


static func _org_change(story: StoryState, pc: Dictionary, change: Dictionary) -> Array:
	var orgs: Array = story.downtime["orgs"][str(pc["pilot"])]
	var org: Dictionary = orgs[int(pc["org_index"])]
	var mx := int(action_cfg("dt_get_organized").get("max", 6))
	if bool(change.get("fold", false)):
		org["folded"] = true
		return [{"type": "org_changed", "pilot": pc["pilot"], "org": org.duplicate(), "folded": true}]
	org["efficiency"] = clampi(int(org["efficiency"]) + int(change.get("efficiency", 0)), 0, mx)
	org["influence"] = clampi(int(org["influence"]) + int(change.get("influence", 0)), 0, mx)
	return [{"type": "org_changed", "pilot": pc["pilot"], "org": org.duplicate(), "folded": false}]


## Applies "next time you get this result for the same X, treat it as Y" and remembers this one.
static func _apply_memory(story: StoryState, cfg: Dictionary, action_id: String, params: Dictionary, ctx: Dictionary, band: String) -> String:
	if not cfg.has("memory"):
		return band
	var key := _key(action_id, params, story)
	var mem: Dictionary = story.downtime["memory"]
	var treated := band
	var prev := str(mem.get(key, ""))
	var rule: Dictionary = cfg["memory"].get(prev, {})
	if rule.has("next_" + band):
		if not bool(rule.get("only_if_unpaid", false)) or StoryConditions.check({"obligation": "$npc.faction"}, story, null, ctx):
			treated = str(rule["next_" + band])
	mem[key] = treated
	return treated


static func _key(action_id: String, params: Dictionary, story: StoryState = null) -> String:
	if action_id == "dt_get_connected" and story != null:
		return action_id + ":" + str(story.npcs.get(str(params.get("npc", "")), {}).get("faction", params.get("npc", "")))
	return action_id + ":" + _subject(params).to_lower()


static func _subject(params: Dictionary) -> String:
	return str(params.get("subject", "")).strip_edges()


static func _preset_reserve(cfg: Dictionary, params: Dictionary) -> String:
	for p: Variant in cfg.get("subject_presets", []):
		if p is Dictionary and str(p["label"]) == _subject(params):
			return str(p.get("reserve", "custom"))
	return str(params.get("reserve", "reserve_knowledge" if cfg.get("subject", "") == "subject" else "custom"))


static func _book_text(action_id: String, band: String) -> String:
	var results: Array = book(action_id).get("table", {}).get("results", [])
	for r: Dictionary in results:
		var lo := int(r["min"])
		if (band == "low" and lo <= 9) or (band == "mid" and lo == 10) or (band == "high" and lo >= 20):
			return StoryText.plain(str(r["text"]))
	return ""


static func _band_words(band: String) -> String:
	return {"low": "9 or less", "mid": "10-19", "high": "20+"}.get(band, band)


static func _drop_last_reserve(story: StoryState, campaign: Campaign, pid: String) -> void:
	var list: Array = story.reserves.get(pid, [])
	if not list.is_empty():
		var r: Dictionary = list.pop_back()
		var ids: Array = campaign.pilots[pid].get("reserves", [])
		if ids.has(str(r["id"])):
			ids.erase(str(r["id"]))


static func _push(story: StoryState, choice: Dictionary) -> void:
	if (choice.get("options", []) as Array).is_empty():
		return
	if story.pending_choice.is_empty():
		story.pending_choice = choice
	else:
		if not story.downtime.has("queue"):
			story.downtime["queue"] = []
		(story.downtime["queue"] as Array).append(choice)


static func _pop(story: StoryState) -> void:
	var q: Array = story.downtime.get("queue", [])
	if not q.is_empty():
		story.pending_choice = q.pop_front()


static func _no(reason: String, ref: String) -> Dictionary:
	return {"reason": reason, "rule_ref": ref}
