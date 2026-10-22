class_name Ending
extends RefCounted
## How a campaign finishes (data/game/story/endings.json). It ends when it has told enough
## stories (campaign.options.campaign_arcs situations finished, default 3), when every living
## pilot is at License Level 12 (the top, Core p.18), when the whole squad has fallen, or when
## the host retires the squad. The kind of ending comes from the situations won and lost and
## who died: triumph, bittersweet or defeat. Every pilot gets an epilogue from their persona,
## their fate and what they remember. Then the same pilots can start a new campaign
## (CampaignLoop.sequel).

const FILE := "res://data/game/story/endings.json"
const KEY := "_ending"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


## Situations (arcs) finished so far: {"won": n, "lost": n}.
static func arc_record(story: StoryState) -> Dictionary:
	var rec := {"won": 0, "lost": 0}
	for k: String in story.flags:
		if k.begins_with("arc_done:"):
			rec["won" if str(story.flags[k]) == "won" else "lost"] += 1
	return rec


## Why the campaign should end now ("" if it shouldn't).
static func due(story: StoryState, campaign: Campaign) -> String:
	var alive: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
	if alive.is_empty():
		return "fallen"
	# The main campaign ends with its final battle (CampaignScript).
	if CampaignScript.active(campaign):
		return "campaign" if str(CampaignScript.state(story).get("ending", "")) != "" else ""
	var rec := arc_record(story)
	if int(rec["won"]) + int(rec["lost"]) >= int(campaign.options.get("campaign_arcs", 3)):
		return "arcs"
	if alive.all(func(p: String) -> bool: return int(campaign.pilots[p].get("ll", 0)) >= 12):
		return "ll12"
	return ""


static func kind_for(story: StoryState, campaign: Campaign) -> String:
	var rec := arc_record(story)
	var alive: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
	if alive.is_empty() or int(rec["lost"]) > int(rec["won"]):
		return "defeat"
	if story.dead.is_empty() and int(rec["won"]) > int(rec["lost"]):
		return "triumph"
	return "bittersweet"


## Ends the campaign: the ending kind, a summary, and one epilogue per pilot. `why` = due().
static func conclude(story: StoryState, campaign: Campaign, why: String) -> Array:
	var kind := kind_for(story, campaign)
	var d := data()
	var ctx := {"vars": {}}
	var title := StoryText.line(d.get("titles", {}).get(kind, [""]), story, campaign, ctx)
	var epilogues: Array = []
	var ids := campaign.pilots.keys()
	ids.sort()
	for pid: String in ids:
		epilogues.append(epilogue(story, campaign, pid, kind))
	var rec := arc_record(story)
	var summary := {"missions": maxi(campaign.history.size(), story.mission_number - 1), "arcs_won": rec["won"], "arcs_lost": rec["lost"],
		"fallen": story.dead.keys().map(func(p: String) -> String: return str(campaign.pilots.get(p, {}).get("callsign", "")))}
	var ending := {"kind": kind, "label": d.get("kinds", {}).get(kind, kind), "title": title, "why": why if why != "" else "retired",
		"summary": summary, "epilogues": epilogues, "name": campaign.name}
	if CampaignScript.active(campaign):
		CampaignScript.decorate(story, campaign, ending)
	story.flags[KEY] = ending
	story.phase = "ending"
	story.add_log("The campaign is over: %s." % ending["label"])
	return [{"type": "campaign_ended", "ending": ending}]


## One pilot's epilogue: their fate, a persona line, and what they remember.
static func epilogue(story: StoryState, campaign: Campaign, pid: String, kind: String) -> Dictionary:
	var d := data()
	var p: Dictionary = campaign.pilots[pid]
	var alive := story.is_alive(pid)
	var seat := story.seat_of(pid)
	var persona := str(story.seats.get(seat, {}).get("persona", Squadmate.suggest(p)))
	var m := Squadmate.memory(story, pid)
	var close := Bonds.closest(story, campaign, pid)
	var vars := {"death_place": str(story.dead.get(pid, {}).get("place", "the front")), "ll": str(p.get("ll", 0)),
		"friend": str(campaign.pilots.get(str(close.get("pilot", "")), {}).get("callsign", "")),
		"bond_label_lower": str(close.get("label", "")).to_lower(), "lost": ", ".join(PackedStringArray(m.get("lost", [])))}
	var ctx := {"speaker": pid, "vars": vars}
	var parts := PackedStringArray()
	parts.append(StoryText.line(d.get("alive" if alive else "dead", {}).get(kind, [""]), story, campaign, ctx))
	if alive:
		parts.append(StoryText.fill(str(d.get("persona", {}).get(persona, {}).get(kind, "")), story, campaign, ctx))
		var mem: Dictionary = d.get("memories", {})
		if not close.is_empty() and int(close.get("score", 0)) >= 3 and story.is_alive(str(close["pilot"])):
			parts.append(StoryText.fill(str(mem.get("bond", "")), story, campaign, ctx))
		if not (m.get("lost", []) as Array).is_empty():
			parts.append(StoryText.fill(str(mem.get("lost", "")), story, campaign, ctx))
		if int(m.get("mvp", 0)) >= 2:
			parts.append(StoryText.fill(str(mem.get("mvp", "")), story, campaign, ctx))
		parts.append(StoryText.fill(str(mem.get("ll", "")), story, campaign, ctx))
	var text := " ".join(parts).strip_edges().replace("  ", " ")
	return {"pilot": pid, "callsign": p.get("callsign", ""), "name": p.get("name", ""), "alive": alive, "ll": int(p.get("ll", 0)),
		"persona": persona, "closest": close, "text": text,
		"face": {"portrait": PortraitSpec.for_pilot(p), "expression": "smiling" if alive and kind == "triumph" else ("sad" if kind != "triumph" else "neutral")}}
