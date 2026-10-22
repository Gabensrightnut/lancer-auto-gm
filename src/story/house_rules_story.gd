class_name StoryHouseRules
extends RefCounted
## The story's house rules (data/game/story/house_rules.json): the user's own ideas the book
## doesn't have (tracked wallet, printer scarcity, paid travel, fight-for-it deals, food and
## water). All off by default, switchable at any time, each labelled "Your idea, not a book
## rule". Stored in campaign.options["house_rules"] = {id: bool}, so clients see which are on.
## The settings registry (src/content/house_rules.gd, menus) lists them from definitions()
## and switches them with the StoryEngine "house_rule" action, which announces the change.
## While a rule is off nothing of it shows; turning it on mid-campaign starts it cleanly.

const FILE := "res://data/game/story/house_rules.json"
const KEY := "house_rules"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


## [{id, name, source, label, text}] for the House Rules page and the codex.
static func definitions() -> Array:
	return data().get("rules", [])


static func rule(id: String) -> Dictionary:
	for r: Dictionary in definitions():
		if str(r["id"]) == id:
			return r
	return {}


static func on(campaign: Campaign, id: String) -> bool:
	return campaign != null and bool((campaign.options.get(KEY, {}) as Dictionary).get(id, false))


static func any_on(campaign: Campaign, ids: Array) -> bool:
	return ids.any(func(id: String) -> bool: return on(campaign, id))


static func refusal(id: String) -> String:
	return "" if not rule(id).is_empty() else "No such house rule."


## Switches a rule (StoryEngine "house_rule"). Turning one on sets it up from where the
## campaign is now (Economy.start); turning it off hides it again (its state is kept quietly,
## so turning it back on doesn't hand out a second starting wallet).
static func set_rule(story: StoryState, campaign: Campaign, id: String, value: bool) -> Array:
	var all: Dictionary = (campaign.options.get(KEY, {}) as Dictionary).duplicate()
	all[id] = value
	campaign.options[KEY] = all
	var r := rule(id)
	var events: Array = [{"type": "house_rule_changed", "id": id, "name": str(r.get("name", id)), "on": value, "label": str(r.get("label", "")),
		"text": "House rule %s: %s (%s)." % ["on" if value else "off", r.get("name", id), r.get("label", "")]}]
	story.add_log(str(events[0]["text"]))
	if value:
		events.append_array(Economy.start(story, campaign, id))
	return events
