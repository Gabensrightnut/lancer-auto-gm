class_name Tones
extends RefCounted
## How replies land (DESIGN.md section 11: no solution menus, data/game/story/tones.json).
## Every reply has a tone (courteous, warm, blunt, flatter, lie, push, insult, threaten, leave),
## given by the scene or read from its tags. It moves the NPC's temper (kept across visits,
## cools a little each day) and this conversation's patience. Out of patience, they end it;
## past their limit, someone armed draws and the fight starts right there (Core p.45: going
## from narrative play to combat), and anyone else throws you out. Nothing here is a choice
## called "fight": it's what happens when you keep pushing.

const FILE := "res://data/game/story/tones.json"
const REF := "Core p.45: switching to mech combat"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func tone_of(c: Dictionary) -> String:
	if c.has("tone"):
		return str(c["tone"])
	var m: Dictionary = data().get("from_tags", {})
	for t: Variant in c.get("tags", []):
		if m.has(str(t)):
			return str(m[str(t)])
	return ""


static func temper(story: StoryState, npc_id: String) -> int:
	return int(story.npcs.get(npc_id, {}).get("temper", 0))


static func _pers(npc: Dictionary) -> Dictionary:
	var p: Dictionary = data().get("personality", {})
	return p.get(str(npc.get("personality", "")), p.get("default", {}))


## Patience for a new conversation.
static func begin(story: StoryState, npc_id: String) -> void:
	var npc: Dictionary = story.npcs.get(npc_id, {})
	if npc.is_empty():
		return
	story.dialogue["patience"] = int(_pers(npc).get("patience", 4))


## Too angry to talk at all, after they've drawn on you or thrown you out (they cool off by a
## point a day).
static func refuses(story: StoryState, npc_id: String) -> String:
	if temper(story, npc_id) >= int(data().get("draws_at", 10)):
		var lines: Array = data().get("lines", {}).get("cold", ["They won't talk to you."])
		return "%s %s" % [story.npcs[npc_id].get("name", ""), str(lines[0]).replace("\"", "")]
	return ""


## The reply's tone, applied after its own effects. Returns the events; the conversation may
## be over (patience gone, thrown out) or a fight may have started (combat_requested).
static func land(story: StoryState, campaign: Campaign, c: Dictionary, ctx: Dictionary) -> Array:
	var npc_id := str(ctx.get("npc", ""))
	var npc: Dictionary = story.npcs.get(npc_id, {})
	var tone := tone_of(c)
	if npc.is_empty() or tone == "" or not Dialogue.is_open(story):
		return []
	var t: Dictionary = data().get("tones", {}).get(tone, {})
	var pers := _pers(npc)
	var before := temper(story, npc_id)
	var dt := int(t.get("temper", 0)) + int(pers.get("temper", {}).get(tone, 0))
	if tone == "lie" and story.dice.die(6) <= 2:
		dt += int(t.get("caught_temper", 3))
	npc["temper"] = clampi(before + dt, 0, 10)
	if not story.dialogue.has("patience"):
		begin(story, npc_id)
	story.dialogue["patience"] = int(story.dialogue["patience"]) + int(t.get("patience", 0))
	var events: Array = [{"type": "tone", "tone": tone, "npc": npc_id, "temper": npc["temper"]}]
	var lines: Dictionary = data().get("lines", {})
	var now := int(npc["temper"])
	if now >= int(data().get("draws_at", 10)):
		Dialogue.close(story, "fight")
		if (data().get("armed_roles", []) as Array).has(str(npc.get("role", ""))):
			events.append({"type": "npc_draws", "npc": npc_id, "text": _pick(story, lines.get("draws", []))})
			events.append({"type": "combat_requested", "spec": {"hook": "standoff", "on_foot": true, "in_town": true, "patron": npc_id,
				"reason": "%s drew on the squad." % npc.get("name", "")}, "rule_ref": REF})
		else:
			events.append({"type": "thrown_out", "npc": npc_id, "text": _pick(story, lines.get("thrown_out", []))})
			events.append_array(StoryEffects.apply({"standing": str(npc.get("faction", "")), "add": -1}, story, campaign, {}))
		return events
	if before < int(data().get("warn_at", 7)) and now >= int(data().get("warn_at", 7)):
		events.append({"type": "tension", "npc": npc_id, "text": _pick(story, lines.get("warn", []))})
		story.dialogue["expression"] = "angry"
	if int(story.dialogue["patience"]) <= 0 and tone != "leave":
		events.append({"type": "patience_out", "npc": npc_id, "text": _pick(story, lines.get("patience_out", []))})
		events.append_array(Dialogue.close(story, "patience"))
	return events


static func _pick(story: StoryState, list: Array) -> String:
	return str(list[story.dice.die(list.size()) - 1]) if not list.is_empty() else ""
