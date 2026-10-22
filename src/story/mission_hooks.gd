class_name MissionHooks
extends RefCounted
## Procedural mission hooks (DESIGN.md section 9): who wants what done, the goal and the
## stakes (a briefing sets both, Core p.40), from data/game/story/hooks.json, the hub's
## people and COMP/CON's name lists. Story events (a favor owed, stolen goods...) add their
## own hooks; the job board fills the rest.

const FILE := "res://data/game/story/hooks.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {"templates": {}}
	return _data


## A hook from template `template_id`. opts: patron (npc id). {} if the template is unknown.
static func make(story: StoryState, campaign: Campaign, template_id: String, opts: Dictionary = {}) -> Dictionary:
	var t: Dictionary = data().get("templates", {}).get(template_id, {})
	if t.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, story.mission_number, story.hooks.size(), template_id, story.dice.die(1000)])
	var names := NameGen.new(rng)
	var patron_id := str(opts.get("patron", ""))
	if patron_id == "" or not story.npcs.has(patron_id):
		patron_id = _pick_patron(story, rng)
	var patron: Dictionary = story.npcs.get(patron_id, {})
	var hook := {
		"id": "hook_%d_%d" % [story.mission_number, story.hooks.size() + rng.randi_range(0, 9999)],
		"template": template_id, "patron_id": patron_id,
		"patron": str(patron.get("name", "the local council")),
		"faction": str(patron.get("faction", story.hub.get("faction", ""))),
		"place": _pick(rng, data().get("places", ["the outskirts"])),
		"enemy": _pick(rng, data().get("enemies", ["raiders"])),
		"cargo": names.cargo(), "operation": names.operation(),
		"sitrep": _pick(rng, t.get("sitreps", ["sitrep_standardcombat"])),
		"seed": rng.randi(),
	}
	var ctx := {"hook": hook, "npc": patron_id, "vars": {"place": hook["place"], "enemy": hook["enemy"], "cargo": hook["cargo"],
		"patron": hook["patron"], "hub": story.hub.get("name", "the settlement")}}
	for k in ["title", "objective", "stakes"]:
		hook[k] = StoryText.fill(_pick(rng, t.get(k, [""])), story, campaign, ctx)
	hook["success"] = (t.get("success", []) as Array).duplicate(true)
	hook["failure"] = (t.get("failure", []) as Array).duplicate(true)
	return hook


## Fills the job board up to `count` hooks from the board templates (by weight), preferring
## the wants of people the squad has met.
static func fill_board(story: StoryState, campaign: Campaign, count: int = 3) -> Array:
	var added: Array = []
	var templates: Dictionary = data().get("templates", {})
	var guard := 0
	while story.hooks.size() < count and guard < 20:
		guard += 1
		var tid := ""
		var patron := ""
		for npc_id: String in story.contacts:
			var npc: Dictionary = story.npcs.get(npc_id, {})
			var want := str(npc.get("want_hook", ""))
			if want != "" and not _has_template_from(story, want, npc_id):
				tid = want
				patron = npc_id
				break
		if tid == "":
			tid = _weighted(story, templates)
		var hook := make(story, campaign, tid, {"patron": patron})
		if not hook.is_empty():
			story.hooks.append(hook)
			added.append(hook)
	return added


static func _has_template_from(story: StoryState, tid: String, patron: String) -> bool:
	for h: Dictionary in story.hooks:
		if str(h["template"]) == tid and str(h["patron_id"]) == patron:
			return true
	for done: Variant in story.flags.get("_hooks_done", []):
		if str(done) == tid + ":" + patron:
			return true
	return false


static func _weighted(story: StoryState, templates: Dictionary) -> String:
	var ids: Array = []
	var total := 0
	for tid: String in templates:
		if bool(templates[tid].get("board", false)):
			ids.append(tid)
			total += int(templates[tid].get("weight", 1))
	ids.sort()
	if ids.is_empty():
		return ""
	var roll := story.dice.die(maxi(total, 1))
	for tid: String in ids:
		roll -= int(templates[tid].get("weight", 1))
		if roll <= 0:
			return tid
	return ids[0]


static func _pick_patron(story: StoryState, rng: RandomNumberGenerator) -> String:
	var ids: Array = (story.hub.get("npcs", []) as Array).filter(func(n: String) -> bool:
		return not bool(story.npcs.get(n, {}).get("dead", false)) and str(story.npcs.get(n, {}).get("role", "")) in ["faction_agent", "local", "company_rep", "bartender"])
	return str(ids[rng.randi_range(0, ids.size() - 1)]) if not ids.is_empty() else ""


static func _pick(rng: RandomNumberGenerator, list: Variant) -> String:
	var arr: Array = list if list is Array else [list]
	return str(arr[rng.randi_range(0, arr.size() - 1)]) if not arr.is_empty() else ""
