class_name Journeys
extends RefCounted
## Getting out of town and to the job (data/game/story/travel.json, DESIGN.md "Exploring vs.
## fighting"): no more teleporting to the fight.
##   - Mounting up: pilots walk to the gantry and climb into their mechs (mount_up {pilot}; AI
##     squadmates climb in with their human). When the whole squad is in, "squad_mounted"
##     tells the flow to put them on the world map at the town's site. They can climb out
##     anywhere safe (dismount {pilot}: a hub, or a safe point with no enemies).
##   - Jobs at real places: every job gets a site (the place, its world, near or far) and a
##     way to get there: walk (close, on the same world: the world map), or a dropship, ship or
##     hired vehicle (the story moves the clock on: travel_time).
##   - travel_time {hours, group: [seats]}: the world map's walking (host) passes on the clock:
##     people's days move on, food and water run down.
##   - war(story, campaign): the two sides at war on this world, or {} (ambushes need a war).
## Kept in story.flags["_mounted"] = {pilot: true}, "_clock_hours" (hours not yet a period).

const FILE := "res://data/game/story/travel.json"
const MOUNTED := "_mounted"
const REF := "Core p.30-31: mounting and dismounting are pilot actions; out of combat it just takes a moment"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


# --- The clock -----------------------------------------------------------------------------

static func travel_refusal(story: StoryState, hours: float) -> String:
	if hours <= 0.0 or hours > 240.0:
		return "How long?"
	if story.phase == "mission":
		return "Not in the middle of a fight."
	return ""


## Hours pass: the town clock moves a period every six hours, and everyone gets hungrier.
static func travel_time(story: StoryState, campaign: Campaign, hours: float, group: Array) -> Array:
	var acc := float(story.flags.get("_clock_hours", 0.0)) + hours
	var periods := int(floor(acc / 6.0))
	story.flags["_clock_hours"] = acc - periods * 6.0
	var events: Array = [{"type": "time_travelled", "hours": hours, "group": group.duplicate(), "text": "%s on the road." % _hours_text(hours)}]
	if periods > 0:
		events.append_array(TownLife.advance(story, periods))
	events.append_array(Survival.pass_hours(story, campaign, hours))
	return events


static func _hours_text(h: float) -> String:
	return ("%d hours" % roundi(h)) if h >= 1.5 else ("%d minutes" % roundi(h * 60.0))


# --- Mounting up ----------------------------------------------------------------------------

static func mounted(story: StoryState, pid: String) -> bool:
	return bool(story.flags.get(MOUNTED, {}).get(pid, false))


static func mount_refusal(story: StoryState, campaign: Campaign, pid: String, up: bool) -> String:
	if not campaign.pilots.has(pid) or not story.is_alive(pid):
		return "Which pilot?"
	if story.phase == "mission":
		return "In a fight, mounting and dismounting are actions on your turn (Core p.30)."
	if up:
		if mounted(story, pid):
			return "Already in the cockpit."
		if RepairBay.wrecked(story, pid) or Economy.wrecked(story, campaign).has(pid):
			return "That mech is wrecked: it has to be printed again first (a Full Repair at the repair bay)."
		return ""
	if not mounted(story, pid):
		return "Not in a mech."
	if story.hub.is_empty() and not bool(story.flags.get("_safe_point", false)):
		return "Not out here: climb out somewhere safe (a town, a base, or a cleared camp)."
	return ""


## Climbs in (or out). AI squadmates follow their human; the whole squad in: squad_mounted.
static func mount(story: StoryState, campaign: Campaign, pid: String, up: bool) -> Array:
	var all: Dictionary = (story.flags.get(MOUNTED, {}) as Dictionary).duplicate()
	var who: Array = [pid]
	var seat := story.seat_of(pid)
	for s: String in story.seats:
		if story.is_ai(s) and Decisions.leader_of(story, s) == seat and story.is_alive(story.pilot_of_seat(s)):
			who.append(story.pilot_of_seat(s))
	var events: Array = []
	for p: String in who:
		if up and (RepairBay.wrecked(story, p) or Economy.wrecked(story, campaign).has(p)):
			continue
		if up:
			all[p] = true
		else:
			all.erase(p)
		events.append({"type": "pilot_mounted" if up else "pilot_dismounted", "pilot": p,
			"text": "%s climbs %s." % [campaign.pilots[p].get("callsign", ""), "into the cockpit" if up else "down from the cockpit"]})
	story.flags[MOUNTED] = all
	if up:
		var everyone := campaign.pilots.keys().filter(func(p: String) -> bool:
			return story.is_alive(p) and story.seat_of(p) != "" and not RepairBay.wrecked(story, p) and not Economy.wrecked(story, campaign).has(p))
		if everyone.all(func(p: String) -> bool: return all.has(p)):
			var seats: Array = everyone.map(func(p: String) -> String: return story.seat_of(p))
			events.append({"type": "squad_mounted", "hub": str(story.hub.get("id", "")), "world": str(Sector.get_sector(story).get("at", "")), "seats": seats,
				"site": "town", "text": "The squad is mounted up. Walk out of town when you're ready."})
	return events


## Back in town after a job: everyone on foot again.
static func all_dismount(story: StoryState) -> void:
	story.flags.erase(MOUNTED)


# --- Where the job is ---------------------------------------------------------------------

## A job's site and how to get there (called when a job is made).
static func dress(story: StoryState, campaign: Campaign, hook: Dictionary) -> void:
	if hook.has("site"):
		return
	var world := str(Sector.get_sector(story).get("at", story.hub.get("id", "")))
	# Seeded from the job itself, so the story's dice aren't touched.
	var near := absi(hash([story.story_seed, str(hook.get("id", "")), str(hook.get("place", "")), "near"])) % 100 < int(data().get("near_chance", 70))
	var mode := "walk"
	if hook.has("boarding") and str(hook["boarding"].get("map", "")) != "own_ship":
		mode = "ship"
	elif bool(hook.get("in_town", false)) or hook.has("boarding"):
		mode = "walk"  # here in town, or aboard your own ship
	elif not near:
		mode = "dropship" if (data().get("dropship_patrons", []) as Array).has(str(campaign.options.get("patron", ""))) else "vehicle"
	var m: Dictionary = data().get("modes", {}).get(mode, {})
	hook["site"] = {"place": str(hook.get("place", "")), "world": world, "near": mode == "walk", "at": null, "area": null}
	hook["travel"] = mode
	hook["travel_hours"] = int(m.get("hours", 0))
	hook["travel_text"] = str(m.get("text", ""))


## The ride out for a job that isn't walking distance: the hours pass (host, on taking the job).
static func ride(story: StoryState, campaign: Campaign, hook: Dictionary) -> Array:
	var h := int(hook.get("travel_hours", 0))
	if str(hook.get("travel", "walk")) == "walk" or h <= 0:
		return []
	var events: Array = [{"type": "ride", "mode": hook["travel"], "text": str(hook.get("travel_text", ""))}]
	events.append_array(travel_time(story, campaign, h, story.seats.keys()))
	return events


# --- War on this world ----------------------------------------------------------------------

## The two sides fighting over this world, for ambushes on the roads ({factions: [a, b]}), or
## {} in peacetime. A campaign world can declare its own (worlds.<id>.war).
static func war(story: StoryState, campaign: Campaign) -> Dictionary:
	if story.hub.get("war") is Dictionary:
		return story.hub["war"]
	var c: Dictionary = story.hub.get("conflict", {})
	if c.is_empty() or not (data().get("war_conflicts", []) as Array).has(str(c.get("id", ""))):
		return {}
	return {"factions": [str(c.get("a", story.hub.get("faction", ""))), str(c.get("b", ""))], "why": str(c.get("summary", ""))}
