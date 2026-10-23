class_name StoryEffects
extends RefCounted
## Applies effects from story data (dialogue choices, downtime outcomes, mission hooks).
## Each returns the events it caused, so the UI can show them. Effects:
##   {"set_flag": "met_rep", "value": true}  {"add_flag": "favors", "amount": 1}  {"clear_flag": k}
##   {"standing": "$npc.faction", "add": 1}         -3..+3, clamped
##   {"reserve": "reserve_extra_repairs", "to": "speaker" | "squad" | pilot id, "note": "..."}
##   {"reserve": "custom", "name": "A borrowed sniper rifle", ...}
##   {"reserve_table": "Resource" | "Mech" | "Tactical", "to": ...}   roll 1d20 on the book table
##   {"contact": "$npc"}                            the squad can call on this NPC from now on
##   {"obligation": {"to": "$npc.faction", "what": "..."}}  a favor owed
##   {"pay_obligation": "$npc.faction"}             a favor paid back (+1 standing)
##   {"hook": "hook template id", "patron": "$npc"} add a mission hook to the board
##   {"harm": 2, "ap": false, "to": "speaker"}      narrative damage to a pilot (Core p.48-49)
##   {"rest": "squad"}                              an hour's rest: half max HP back, Down and Out cleared
##   {"npc_dead": "$npc"}                           {"log": "text"}
##   {"deal": {"template": "$npc.want_hook", "fallback": "clear_raiders"}}  take a side job from
##     this NPC: a job on the board that pays their deal reward (a reserve) if the squad wins
##   {"start_combat": {"hook": ..., "reason": "..."}}  ends the scene, the GM starts a mission
##   {"downtime": "dt_get_connected", "subject": "$npc"}  takes that downtime action now for the speaker
##   {"ui": "downtime", "action": "dt_get_a_damn_drink"}   asks the UI to open a panel (downtime
##     action with a subject to name, pilot gear picker "pilot_gear", job board "hooks")
##   {"world": {"set": {fact: value}}}             what the squad did to this place (WorldState)
##   {"agenda": {"pilot": "speaker", "kind", "why", "add"}}  a pilot's own grudge or goal (Agendas)
##   {"clone_template": {"pilot": id | "speaker" | "squad", "state": "corrupted" | "tampered" | "destroyed"}}
##   {"clone_template": {"pilot": ..., "store": "flash" | "facsimile"}}  store a template here (Cloning)
##   {"full_repair": true}                         10 hours at a repair bay (RepairBay, Core p.82)
##   {"renown": 1, "why": "..."}                  the people aboard the squad's ship love them more (ShipLife)
##   {"decision": {id, prompt, accept: [effects], decline: [effects]}}  a squad decision (Decisions)
##   {"trust": "$npc" | npc id, "add": 1}         how much this person trusts the squad (-5..5)
##   {"give_item": item id, "to": "speaker"}       hand over something kept in town (TownLife)
##   {"rival_fate": "captured" | "withdrew" | "won"}   what becomes of the enemy commander (parley)
##   {"end_battle": "players" | "enemies" | "none", "reason": "..."}  a parley ends the fight (Core p.60)
##   {"battle_refused": true}                       no terms: the fight goes on
## Unknown effects are refused when the data is checked (StoryData.lint) and skipped here.

const REF_RESERVES := "Core p.50-52: reserves"
const REF_HARM := "Core p.48: hit points, damage and injury"
const REF_DOWN := "Core p.49: down and out"
const RESERVE_TABLES := "res://data/game/story/reserve_tables.json"
const RESERVES_FILE := "res://data/lancer-data/reserves.json"

static var _reserve_names: Dictionary = {}


static func apply_all(effects: Array, story: StoryState, campaign: Campaign, ctx: Dictionary) -> Array:
	var events: Array = []
	for e: Dictionary in effects:
		events.append_array(apply(e, story, campaign, ctx))
	return events


static func apply(e: Dictionary, story: StoryState, campaign: Campaign, ctx: Dictionary) -> Array:
	var R := func(v: Variant) -> Variant: return StoryConditions.resolve(v, story, ctx)
	if e.has("set_flag"):
		var k := StoryText.fill(str(R.call(e["set_flag"])), story, campaign, ctx)
		story.flags[k] = R.call(e.get("value", true))
		return [{"type": "flag_set", "flag": k, "value": story.flags[k]}]
	if e.has("add_flag"):
		var k := str(R.call(e["add_flag"]))
		story.flags[k] = int(story.flags.get(k, 0)) + int(e.get("amount", 1))
		return [{"type": "flag_set", "flag": k, "value": story.flags[k]}]
	if e.has("clear_flag"):
		story.flags.erase(str(R.call(e["clear_flag"])))
		return []
	if e.has("standing"):
		var f := str(R.call(e["standing"]))
		if f == "":
			return []
		var before := story.get_standing(f)
		story.standing[f] = clampi(before + int(e.get("add", 0)), -3, 3)
		return [{"type": "standing_changed", "faction": f, "from": before, "to": story.standing[f],
			"label": StoryText.standing_label(story.standing[f])}]
	if e.has("reserve"):
		return give_reserve(story, campaign, ctx, e)
	if e.has("reserve_table"):
		var ids: Array = _json(RESERVE_TABLES).get(str(e["reserve_table"]), [])
		if ids.is_empty():
			return []
		var roll := story.dice.die(20)
		var pick := e.duplicate()
		pick.erase("reserve_table")
		pick["reserve"] = ids[clampi((roll - 1) / 2, 0, ids.size() - 1)]
		var ev := give_reserve(story, campaign, ctx, pick)
		for x: Dictionary in ev:
			x["table_roll"] = roll
		return ev
	if e.has("contact"):
		var npc := str(R.call(e["contact"]))
		if npc != "" and not story.contacts.has(npc):
			story.contacts.append(npc)
			return [{"type": "contact_added", "npc": npc, "name": str(story.npcs.get(npc, {}).get("name", npc))}]
		return []
	if e.has("obligation"):
		var o: Dictionary = e["obligation"]
		var rec := {"to": str(R.call(o.get("to", "$npc.faction"))), "npc": str(ctx.get("npc", "")),
			"what": StoryText.fill(str(o.get("what", "a favor")), story, campaign, ctx),
			"by": str(ctx.get("speaker", "")), "mission": story.mission_number, "done": false}
		(story.downtime["obligations"] as Array).append(rec)
		return [{"type": "obligation_added", "obligation": rec}]
	if e.has("pay_obligation"):
		var who := str(R.call(e["pay_obligation"]))
		story.flags.erase("favor_job_posted:" + who)
		for o: Dictionary in story.downtime.get("obligations", []):
			if str(o["to"]) == who and not bool(o["done"]):
				o["done"] = true
				var ev: Array = [{"type": "obligation_paid", "obligation": o}]
				ev.append_array(apply({"standing": who, "add": 1}, story, campaign, ctx))
				return ev
		return []
	if e.has("hook"):
		var tid := str(R.call(e["hook"]))
		if tid == "":
			tid = str(e.get("fallback", ""))
		var hook := MissionHooks.make(story, campaign, tid, {"patron": str(R.call(e.get("patron", "")))})
		if hook.is_empty():
			return []
		story.hooks.append(hook)
		return [{"type": "hook_added", "hook": hook}]
	if e.has("harm"):
		var out: Array = []
		for pid: String in _targets(e.get("to", "speaker"), story, campaign, ctx):
			out.append_array(harm(story, campaign, pid, int(e["harm"]), bool(e.get("ap", false))))
		return out
	if e.has("rest"):
		var out: Array = []
		for pid: String in _targets(e["rest"], story, campaign, ctx):
			out.append_array(rest(story, campaign, pid))
		return out
	if e.has("npc_dead"):
		var npc := str(R.call(e["npc_dead"]))
		if story.npcs.has(npc):
			story.npcs[npc]["dead"] = true
			return [{"type": "npc_died", "npc": npc}]
		return []
	if e.has("world"):
		var vals: Dictionary = {}
		for k: String in (e["world"] as Dictionary).get("set", {}):
			vals[k] = StoryText.fill(str(e["world"]["set"][k]), story, campaign, ctx)
		return WorldState.set_facts(story, vals)
	if e.has("agenda"):
		var ag: Dictionary = e["agenda"]
		var who := str(ag.get("pilot", "speaker"))
		if who == "speaker":
			who = str(ctx.get("speaker", ""))
		return Agendas.add(story, campaign, who, str(ag.get("kind", "grievance")), StoryText.fill(str(ag.get("why", "")), story, campaign, ctx), int(ag.get("add", 1)))
	if e.has("full_repair"):
		var why_fr := RepairBay.refusal(story, campaign)
		return RepairBay.full_repair(story, campaign) if why_fr == "" else [{"type": "refused", "text": why_fr, "rule_ref": RepairBay.REF}]
	if e.has("renown"):
		return ShipLife.add_renown(story, campaign, int(e["renown"]), StoryText.fill(str(e.get("why", "what the lance did")), story, campaign, ctx))
	if e.has("clone_template"):
		var ct: Dictionary = e["clone_template"]
		var whose: Array = [str(ct.get("pilot", ctx.get("speaker", "")))]
		if whose[0] == "squad":
			whose = campaign.pilots.keys().filter(func(x: String) -> bool: return story.is_alive(x) or story.dead.has(x))
		elif whose[0] == "speaker":
			whose = [str(ctx.get("speaker", ""))]
		var cev: Array = []
		for w: String in whose:
			if ct.has("store"):
				if story.is_alive(w) and Cloning.template(story, w).is_empty():
					cev.append_array(Cloning.store(story, campaign, w, str(ct["store"])))
			else:
				cev.append_array(Cloning.damage(story, w, str(ct.get("state", "corrupted"))))
		return cev
	if e.has("decision"):
		return Decisions.open(story, e["decision"], campaign, story.seat_of(str(ctx.get("speaker", ""))))
	if e.has("trust"):
		var who := str(R.call(e["trust"]))
		if not story.npcs.has(who):
			who = CampaignScript.npc(who)
		if story.npcs.has(who):
			story.npcs[who]["trust"] = clampi(int(story.npcs[who].get("trust", 0)) + int(e.get("add", 0)), -5, 5)
			return [{"type": "trust_changed", "npc": who, "trust": story.npcs[who]["trust"]}]
		return []
	if e.has("give_item"):
		var it := TownLife.item(story, str(e["give_item"]))
		if it.is_empty():
			return []
		it["holder"] = str(ctx.get("speaker", ""))
		return [{"type": "item_given", "item": it["id"], "text": "You now have %s." % it["name"]}]
	if e.has("rival_fate"):
		return Rivals.set_fate(story, str(e["rival_fate"]))
	if e.has("end_battle"):
		return Rivals.end_battle(story, str(e["end_battle"]), StoryText.fill(str(e.get("reason", "")), story, campaign, ctx))
	if e.has("battle_refused"):
		return Rivals.refuse(story)
	if e.has("log"):
		var text := StoryText.fill(str(e["log"]), story, campaign, ctx)
		story.add_log(text)
		return [{"type": "story_log", "text": text}]
	if e.has("start_combat"):
		var spec: Dictionary = (e["start_combat"] as Dictionary).duplicate(true)
		spec["reason"] = StoryText.fill(str(spec.get("reason", "")), story, campaign, ctx)
		if spec.has("patron"):
			spec["patron"] = str(R.call(spec["patron"]))
		return [{"type": "combat_requested", "spec": spec, "rule_ref": "Core p.45: switching to mech combat"}]
	if e.has("deal"):
		var spec: Dictionary = e["deal"]
		var npc_id := str(ctx.get("npc", ""))
		var npc: Dictionary = story.npcs.get(npc_id, {})
		var tid := str(R.call(spec.get("template", "$npc.want_hook")))
		if tid == "" or not MissionHooks.data().get("templates", {}).has(tid):
			tid = str(spec.get("fallback", "clear_raiders"))
		var hook := MissionHooks.make(story, campaign, tid, {"patron": npc_id})
		if hook.is_empty():
			return []
		var reward := str(npc.get("deal_reward", "reserve_backing"))
		hook["deal"] = {"npc": npc_id, "reward": reward}
		hook["short_title"] = hook["title"]
		hook["title"] = "%s (deal with %s)" % [hook["title"], npc.get("name", "a contact")]
		story.hooks.append(hook)
		story.deals[npc_id] = {"state": "accepted", "hook": hook["id"], "reward": reward, "mission": story.mission_number,
			"by": str(ctx.get("speaker", ""))}
		return [{"type": "deal_made", "npc": npc_id, "reward": reward, "reward_name": reserve_name(reward), "hook": hook,
			"rule_ref": "Core p.40-43: reserves (a favor for a job done)"}]
	if e.has("ui"):
		var ev := e.duplicate()
		ev.erase("ui")
		return [{"type": "ui_requested", "ui": str(e["ui"]), "pilot": str(ctx.get("speaker", "")), "npc": str(ctx.get("npc", "")), "params": ev}]
	if e.has("downtime"):
		return [{"type": "downtime_offered", "action": str(e["downtime"]), "pilot": str(ctx.get("speaker", "")),
			"subject": str(R.call(e.get("subject", ""))), "npc": str(ctx.get("npc", ""))}]
	push_warning("StoryEffects: unknown effect %s" % [e])
	return []


static func give_reserve(story: StoryState, campaign: Campaign, ctx: Dictionary, e: Dictionary) -> Array:
	var rid := str(StoryConditions.resolve(e["reserve"], story, ctx))
	if rid == "":
		rid = "custom"
	var name := StoryText.fill(str(e.get("name", reserve_name(rid))), story, campaign, ctx)
	var events: Array = []
	for pid: String in _targets(e.get("to", "speaker"), story, campaign, ctx):
		var r := {"id": rid, "name": name, "note": StoryText.fill(str(e.get("note", "")), story, campaign, ctx),
			"source": StoryText.fill(str(e.get("source", "$npc.name")), story, campaign, ctx), "mission": story.mission_number}
		if str(r["source"]) == "":
			r["source"] = "Downtime"
		story.add_reserve(pid, r)
		var p: Dictionary = campaign.pilots.get(pid, {})
		if not p.is_empty() and rid != "custom":
			(p["reserves"] as Array).append(rid)
		events.append({"type": "reserve_gained", "pilot": pid, "reserve": r, "rule_ref": REF_RESERVES})
	return events


## Narrative damage (Core p.48): Armor is subtracted unless AP. At 0 HP roll 1d6 (Core p.49):
## 6 = back to 1 HP, 2-5 = Down and Out, 1 = dead. Damage while Down and Out kills.
static func harm(story: StoryState, campaign: Campaign, pid: String, amount: int, ap: bool = false) -> Array:
	var p: Dictionary = campaign.pilots.get(pid, {})
	if p.is_empty() or story.dead.has(pid):
		return []
	var armor := 0 if ap else pilot_armor(p)
	var taken := maxi(amount - armor, 0)
	var hp := current_hp(story, campaign, pid)
	var events: Array = [{"type": "pilot_harmed", "pilot": pid, "amount": taken, "armor": mini(armor, amount),
		"hp": maxi(hp - taken, 0), "rule_ref": REF_HARM}]
	if taken <= 0:
		return events
	if story.down_and_out.has(pid):
		events.append_array(kill(story, pid, "Took more damage while Down and Out."))
		return events
	hp -= taken
	if hp > 0:
		story.pilot_hp[pid] = hp
		return events
	var roll := story.dice.die(6)
	if roll == 6:
		story.pilot_hp[pid] = 1
		events.append({"type": "down_and_out_roll", "pilot": pid, "roll": roll, "result": "close_call", "rule_ref": REF_DOWN})
	elif roll >= 2:
		story.pilot_hp[pid] = 0
		story.down_and_out[pid] = true
		events.append({"type": "down_and_out_roll", "pilot": pid, "roll": roll, "result": "down_and_out", "rule_ref": REF_DOWN})
	else:
		story.pilot_hp[pid] = 0
		events.append({"type": "down_and_out_roll", "pilot": pid, "roll": roll, "result": "dead", "rule_ref": REF_DOWN})
		events.append_array(kill(story, pid, "Their luck ran out."))
	return events


static func kill(story: StoryState, pid: String, cause: String) -> Array:
	story.dead[pid] = {"cause": cause, "mission": story.mission_number, "place": str(story.current_hook.get("place", ""))}
	story.down_and_out.erase(pid)
	story.flags["dead_" + pid] = true
	return [{"type": "pilot_died", "pilot": pid, "cause": cause, "rule_ref": "Core p.49, p.83: death"}]


## An hour of rest with nothing strenuous: half max HP back and Down and Out ends (Core p.49).
static func rest(story: StoryState, campaign: Campaign, pid: String) -> Array:
	if story.dead.has(pid) or not campaign.pilots.has(pid):
		return []
	var mx := max_hp(campaign.pilots[pid])
	var hp := mini(current_hp(story, campaign, pid) + int(ceil(mx / 2.0)), mx)
	story.pilot_hp[pid] = hp
	story.down_and_out.erase(pid)
	return [{"type": "pilot_rested", "pilot": pid, "hp": hp, "rule_ref": "Core p.49: resting"}]


## LL0 pilots have 6 HP, plus Grit, plus armor HP (Core p.48, p.108).
static func max_hp(p: Dictionary) -> int:
	var hp := 6 + UnitFactory.grit(int(p.get("ll", 0)))
	for b: Dictionary in _gear_bonuses(p):
		if str(b.get("id", "")) == "pilot_hp":
			hp += int(b.get("val", 0))
	return hp


static func pilot_armor(p: Dictionary) -> int:
	var armor := 0
	for b: Dictionary in _gear_bonuses(p):
		if str(b.get("id", "")) == "pilot_armor":
			armor = maxi(armor, int(b.get("val", 0)))
	return armor


static func current_hp(story: StoryState, campaign: Campaign, pid: String) -> int:
	return int(story.pilot_hp.get(pid, max_hp(campaign.pilots.get(pid, {}))))


static var _gear: Dictionary = {}


static func _gear_bonuses(p: Dictionary) -> Array:
	if _gear.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lancer-data/pilot_gear.json"))
		for g: Dictionary in (data if data is Array else []):
			_gear[str(g["id"])] = g
	var out: Array = []
	for gid: String in p.get("pilot_gear", []):
		var g: Dictionary = _gear.get(gid, {})
		if str(g.get("type", "")) == "Armor":
			out.append_array(g.get("bonuses", []))
	return out


static func reserve_name(rid: String) -> String:
	if _reserve_names.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESERVES_FILE))
		for r: Dictionary in (data if data is Array else []):
			_reserve_names[str(r["id"])] = str(r["name"])
	return str(_reserve_names.get(rid, rid.trim_prefix("reserve_").capitalize()))


## Is this one of the book's reserves (lancer-data reserves.json)?
static func is_book_reserve(rid: String) -> bool:
	reserve_name(rid)
	return _reserve_names.has(rid)


static func reserve_description(rid: String) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESERVES_FILE))
	for r: Dictionary in (data if data is Array else []):
		if str(r["id"]) == rid:
			return str(r.get("description", ""))
	return ""


static func _targets(to: Variant, story: StoryState, campaign: Campaign, ctx: Dictionary) -> Array:
	if str(to) == "squad":
		var out: Array = []
		for pid: String in campaign.pilots:
			if story.is_alive(pid):
				out.append(pid)
		out.sort()
		return out
	if to is Array:
		return to
	var pid := StoryConditions.pilot_id(to, story, ctx)
	return [pid] if pid != "" else []


static var _cache: Dictionary = {}


static func _json(path: String) -> Dictionary:
	if not _cache.has(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_cache[path] = data if data is Dictionary else {}
	return _cache[path]
