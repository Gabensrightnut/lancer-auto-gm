class_name BackgroundStory
extends RefCounted
## Pilot backgrounds (lancer-data backgrounds.json, Core p.20-24) in the story: each opens its
## own dialogue options with the kinds of people who'd care, and makes some jobs personal by
## tying the stakes to a pilot's past (Core p.43). Data: data/game/story/background_story.json.

const FILE := "res://data/game/story/background_story.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"backgrounds": {}}
	return _data


## Extra choices for a scene's "menu" node: the speaking pilot's background options for this
## NPC's role. They go back to the menu through the scene's "bg_ack" node (or the check nodes).
static func options_for(story: StoryState, campaign: Campaign, ctx: Dictionary, node_id: String) -> Array:
	if node_id != "menu":
		return []
	var npc: Dictionary = story.npcs.get(str(ctx.get("npc", "")), {})
	var pilot: Dictionary = campaign.pilots.get(str(ctx.get("speaker", "")), {}) if campaign != null else {}
	var bg := str(pilot.get("background", ""))
	var entry: Dictionary = data().get("backgrounds", {}).get(bg, {})
	var out: Array = []
	for o: Dictionary in entry.get("options", []):
		if not (o.get("roles", []) as Array).has(str(npc.get("role", ""))):
			continue
		var c := o.duplicate(true)
		c["priority"] = 2
		if c.has("check"):
			c["check"]["success"] = "check_ok"
			c["check"]["fail"] = "check_bad"
		else:
			c["next"] = "bg_ack"
		out.append(c)
	return out


## Makes a job personal for one pilot whose background fits it ({} if none). Adds a line to the
## stakes, the way the book ties stakes to a pilot's history.
static func personal_for(story: StoryState, campaign: Campaign, template_id: String, rng: RandomNumberGenerator) -> Dictionary:
	if campaign == null or rng.randf() > float(data().get("personal_chance", 0.6)):
		return {}
	var ids := campaign.pilots.keys()
	ids.sort()
	var fits: Array = []
	for pid: String in ids:
		if not story.is_alive(pid):
			continue
		var entry: Dictionary = data().get("backgrounds", {}).get(str(campaign.pilots[pid].get("background", "")), {})
		if (entry.get("personal", {}).get("templates", []) as Array).has(template_id):
			fits.append(pid)
	if fits.is_empty():
		return {}
	var pid: String = fits[rng.randi_range(0, fits.size() - 1)]
	var bg := str(campaign.pilots[pid].get("background", ""))
	var line := StoryText.fill(str(data()["backgrounds"][bg]["personal"].get("line", "")), story, campaign, {"speaker": pid})
	return {"pilot": pid, "background": bg, "line": line}
