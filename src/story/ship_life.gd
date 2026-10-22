class_name ShipLife
extends RefCounted
## Life aboard a ship that's home to a whole society (the pirate career: the Saint Cadence
## under Corvo Hask, with families, markets, repair crews and factions in her holds). Read
## from the campaign script's "society" block:
##   {world, people: faction name, captain: npc, captain_if: condition, quell_at: [3, 5, ...],
##    quells: [{id, text, flag}], jobs: [{id, name, skills, spot, renown, pay, favor, text, fail}],
##    side_jobs: [{if, template, title, objective, place, enemy, foes, patron, renown, ...}]}
##
## - Renown: how much the people aboard love the squad (story.flags["_ship_life"].renown),
##   shown as standing with `people` (-3..+3). It grows with what the squad does for them.
## - The captain keeps the peace: when the squad's renown reaches the next mark, he quietly
##   cuts them down to size (takes credit, sidelines them, reassigns them). Each time, the
##   people who see the lancers as their protectors grow angrier with him (unrest). Renown and
##   unrest feed the mutiny and the captaincy (conditions {"renown": {min}}, {"unrest": {min}}).
## - Everyone aboard works: between missions a pilot can take a shift (`ship_work {job, pilot}`,
##   once per pilot per chapter): repairs, settling a dispute in the holds, guarding the
##   markets. A narrative skill check (Core p.45). Success earns renown, and pay with the
##   wallet house rule on, otherwise a favor (a reserve, Core p.48). Combat runs (escort runs,
##   market raiders) go on the job board as side jobs.

const KEY := "_ship_life"
const REF_RESERVE := "Core p.48: reserves"


static func society(campaign: Campaign) -> Dictionary:
	return CampaignScript.script(campaign).get("society", {}) if CampaignScript.active(campaign) else {}


static func state(story: StoryState) -> Dictionary:
	if not story.flags.has(KEY):
		story.flags[KEY] = {"renown": 0, "unrest": 0, "quells": 0, "worked": {}}
	return story.flags[KEY]


static func renown(story: StoryState) -> int:
	return int(story.flags.get(KEY, {}).get("renown", 0))


static func unrest(story: StoryState) -> int:
	return int(story.flags.get(KEY, {}).get("unrest", 0))


static func aboard(story: StoryState, campaign: Campaign) -> bool:
	var soc := society(campaign)
	return not soc.is_empty() and str(CampaignScript.state(story).get("worlds", {}).get(str(soc.get("world", "")), "")) == str(Sector.get_sector(story).get("at", ""))


static func _mirror(story: StoryState, campaign: Campaign) -> void:
	var people := str(society(campaign).get("people", ""))
	if people != "":
		story.standing[people] = clampi(int(floor(renown(story) / 2.0)), -3, 3)


## The squad's name grows (or sours) with the people aboard; the captain may react.
static func add_renown(story: StoryState, campaign: Campaign, n: int, why: String) -> Array:
	var soc := society(campaign)
	if soc.is_empty() or n == 0:
		return []
	var st := state(story)
	st["renown"] = int(st["renown"]) + n
	_mirror(story, campaign)
	var text := ("The holds are talking about the lance: %s." % why) if n > 0 else ("People aboard go quiet when the lance walks past: %s." % why)
	var events: Array = [{"type": "renown", "value": st["renown"], "add": n, "text": text, "faction": str(soc.get("people", ""))}]
	events.append_array(react(story, campaign))
	return events


## The captain keeps the peace: past the next mark, he takes the squad down a peg.
static func react(story: StoryState, campaign: Campaign) -> Array:
	var soc := society(campaign)
	var st := state(story)
	var marks: Array = soc.get("quell_at", [3, 5, 7, 9])
	var n := int(st["quells"])
	if n >= marks.size() or int(st["renown"]) < int(marks[n]):
		return []
	if not CampaignScript.check(story, campaign, soc.get("captain_if"), {}):
		return []
	var quells: Array = soc.get("quells", [])
	if quells.is_empty():
		return []
	var q: Dictionary = quells[n % quells.size()]
	st["quells"] = n + 1
	st["unrest"] = int(st["unrest"]) + 1
	st["renown"] = int(st["renown"]) - 1
	_mirror(story, campaign)
	if str(q.get("flag", "")) != "":
		story.flags[str(q["flag"])] = true
	var text := str(q.get("text", ""))
	story.add_log(text)
	return [{"type": "captain_quells", "id": q.get("id", ""), "text": text, "unrest": st["unrest"],
		"note": "Hask keeps the peace on his ship. The people who see the lance as their protectors don't like it."}]


# --- Work aboard -------------------------------------------------------------------------

static func job(campaign: Campaign, id: String) -> Dictionary:
	for j: Dictionary in society(campaign).get("jobs", []):
		if str(j["id"]) == id:
			return j
	return {}


static func work_refusal(story: StoryState, campaign: Campaign, id: String, pid: String) -> String:
	if society(campaign).is_empty():
		return "There's no ship's work here."
	if not aboard(story, campaign):
		return "That's work aboard the ship. You're not aboard."
	if story.phase == "mission":
		return "Not in the middle of a mission."
	if job(campaign, id).is_empty():
		return "What kind of work?"
	if not campaign.pilots.has(pid) or not story.is_alive(pid):
		return "Which pilot?"
	var cid := str(CampaignScript.state(story).get("chapter", ""))
	if (state(story)["worked"] as Dictionary).get(cid, []).has(pid):
		return "%s has already worked a shift since the last job." % campaign.pilots[pid].get("callsign", "")
	return ""


static func work(story: StoryState, campaign: Campaign, id: String, pid: String) -> Array:
	var j := job(campaign, id)
	var st := state(story)
	var cid := str(CampaignScript.state(story).get("chapter", ""))
	var worked: Dictionary = st["worked"]
	var list: Array = worked.get(cid, [])
	list.append(pid)
	worked[cid] = list
	var opts := {"skills": j.get("skills", []), "label": str(j.get("name", id)), "consequence": str(j.get("fail", "")), "tags": ["ship", "work"]}
	var rec := NarrativeCheck.roll(story.dice, campaign.pilots[pid], Economy.check_opts(story, campaign, pid, opts))
	var events: Array = [{"type": "narrative_check", "pilot": pid, "check": rec, "rule_ref": NarrativeCheck.REF}]
	events.append_array(TownLife.advance(story, 1))
	var cs := str(campaign.pilots[pid].get("callsign", ""))
	if str(rec.get("outcome", "fail")) == "fail":
		events.append({"type": "ship_work", "job": id, "pilot": pid, "success": false, "text": "%s: %s" % [cs, j.get("fail", "It doesn't go well.")]})
		return events
	events.append({"type": "ship_work", "job": id, "pilot": pid, "success": true, "text": "%s: %s" % [cs, j.get("text", "A shift's honest work.")]})
	if StoryHouseRules.on(campaign, Economy.R_WALLET):
		events.append_array(Economy.earn(story, int(j.get("pay", 40)), str(j.get("name", "ship's work"))))
	else:
		events.append_array(StoryEffects.apply({"reserve": "custom", "name": "A favor from %s" % j.get("favor", "the crew"), "to": "speaker", "source": str(j.get("favor", "the crew")),
			"note": str(j.get("name", ""))}, story, campaign, {"speaker": pid}))
	events.append_array(add_renown(story, campaign, int(j.get("renown", 1)), "%s %s" % [cs, j.get("talk", "pulled a shift with the crews")]))
	return events


## Combat runs for the people aboard (escort runs, raiders in the markets): one side job on
## the board per chapter, while the squad is aboard.
static func side_jobs(story: StoryState, campaign: Campaign) -> Array:
	var soc := society(campaign)
	if soc.is_empty() or not aboard(story, campaign):
		return []
	if story.hooks.any(func(h: Dictionary) -> bool: return h.has("ship_job")):
		return []
	var cid := str(CampaignScript.state(story).get("chapter", ""))
	if (state(story).get("side_done", []) as Array).has(cid):
		return []
	var options: Array = (soc.get("side_jobs", []) as Array).filter(func(s: Dictionary) -> bool: return CampaignScript.check(story, campaign, s.get("if"), {}))
	if options.is_empty():
		return []
	var sj: Dictionary = options[story.dice.die(options.size()) - 1]
	var h := MissionHooks.make(story, campaign, str(sj.get("template", "escort_convoy")), {"patron": CampaignScript.npc(str(sj.get("patron", "")))})
	if h.is_empty():
		return []
	h.erase("twist")
	for k: String in ["title", "objective", "stakes", "question", "place", "enemy"]:
		if sj.has(k):
			h[k] = str(sj[k])
	h["short_title"] = str(h["title"])
	h["npc_templates"] = CampaignScript.script(campaign).get("enemy_mixes", {}).get(str(sj.get("foes", "")), h.get("npc_templates", []))
	if bool(sj.get("in_town", false)):
		h["in_town"] = true
		h["town_spot"] = "market"
	h["ship_job"] = cid
	h["renown"] = int(sj.get("renown", 1))
	h["side_job"] = true
	story.hooks.append(h)
	return [h]


static func after_mission(story: StoryState, campaign: Campaign, hook: Dictionary, won: bool) -> Array:
	if not hook.has("ship_job"):
		return []
	var done: Array = state(story).get("side_done", [])
	done.append(str(hook["ship_job"]))
	state(story)["side_done"] = done
	if not won:
		return add_renown(story, campaign, -1, "the %s went badly" % str(hook.get("title", "job")).to_lower())
	return add_renown(story, campaign, int(hook.get("renown", 1)), "the lance came through on the %s" % str(hook.get("title", "job")).to_lower())
