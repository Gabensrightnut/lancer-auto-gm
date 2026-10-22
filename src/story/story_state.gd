class_name StoryState
extends RefCounted
## Everything the story side remembers between scenes: story flags, faction standing, the
## hub and its people, contacts, reserves, downtime results the book says to remember
## ("next time you get this result..."), pilot HP outside the mech, the campaign phase and
## the story dice. Only StoryEngine changes it (like RulesEngine for GameState).
##
## Saved inside the campaign: plain flags live in campaign.story_flags (so anything can read
## them) and the rest under campaign.story_flags["_story"]. (Asked the main session to give
## it its own Campaign field; see src/story/README.md.)

const KEY := "_story"
const VERSION := 1
## Book order of play (Core p.40, p.44): briefing, preparation and reserves, boots on the
## ground, then debrief with level up, then downtime before the next mission.
const PHASES := ["briefing", "reserves", "mission", "debrief", "level_up", "downtime"]

var flags: Dictionary = {}
## faction name -> -3..+3. Our own bookkeeping, not a book number: it only decides which
## dialogue options are offered and what a contact is willing to grant (see README).
var standing: Dictionary = {}
var phase := "briefing"
var mission_number := 1
## seat -> {"pilot": pilot id, "ai": bool, "persona": "steady"}
var seats: Dictionary = {}
## npc id -> NPC record (NpcGen). Everyone the squad can meet in this campaign.
var npcs: Dictionary = {}
## The current hub (HubGen record) or {}.
var hub: Dictionary = {}
## npc ids the squad has met and can call on (Get Connected).
var contacts: Array = []
## pilot id -> [{"id", "name", "note", "source", "mission"}]. Last for the next mission only
## (Core p.51).
var reserves: Dictionary = {}
## pilot id -> current HP out of the mech; missing = full.
var pilot_hp: Dictionary = {}
## pilot id -> true while Down and Out (Core p.49).
var down_and_out: Dictionary = {}
## pilot id -> {"cause", "mission"}.
var dead: Dictionary = {}
## Downtime: {"actions_left": {pid: n}, "memory": {key: band}, "projects": {key: {...}},
## "orgs": {pid: [...]}, "obligations": [...], "first": bool}
var downtime: Dictionary = {"actions_left": {}, "memory": {}, "projects": {}, "orgs": {}, "obligations": []}
## Mission hooks on offer: [MissionHooks record]. current_hook = the one being played.
var hooks: Array = []
var current_hook: Dictionary = {}
## npc id -> {"state": "accepted"/"won"/"lost", "hook": id, "reward": reserve id, "mission": n}.
## A side job done for someone pays out a reserve (Core p.40-43); losing it withdraws the offer.
var deals: Dictionary = {}
## The arc running at this hub (StoryArc) or {}.
var arc: Dictionary = {}
## The guided first-time opening (Tutorial): {active, step, shown, turns, tips}.
var tutorial: Dictionary = {}
var last_mission: Dictionary = {}
## pilot id -> {"trigger": n, "mech_skill": n, "talent": n, "license": n, "core_bonus": n}
var pending_picks: Dictionary = {}
## Waiting for a choice from a list (downtime outcomes): {"pilot", "action", "band",
## "options", "count", "chooser"}.
var pending_choice: Dictionary = {}
## The open conversation (Dialogue runner state) or {}.
var dialogue: Dictionary = {}
## Goals a skill check failed on: goal -> {"level": "normal"/"risky"/"heroic"} (Core p.46).
var failed_goals: Dictionary = {}
## Last variant used per line pool, so lines don't repeat back to back.
var line_memory: Dictionary = {}
var log: Array = []
var story_seed := 0
var dice: Dice


func _init(seed_value: int = 0) -> void:
	story_seed = seed_value
	dice = Dice.new(hash([seed_value, "story"]))


# --- Pilots ------------------------------------------------------------------------------

func seat_of(pilot_id: String) -> String:
	for s: String in seats:
		if str(seats[s].get("pilot", "")) == pilot_id:
			return s
	return ""


func pilot_of_seat(seat: String) -> String:
	return str(seats.get(seat, {}).get("pilot", ""))


func is_ai(seat: String) -> bool:
	return bool(seats.get(seat, {}).get("ai", false))


func human_seats() -> Array:
	var out: Array = []
	for s: String in seats:
		if not is_ai(s) and not dead.has(pilot_of_seat(s)):
			out.append(s)
	out.sort()
	return out


func is_alive(pilot_id: String) -> bool:
	return not dead.has(pilot_id)


func add_reserve(pilot_id: String, reserve: Dictionary) -> void:
	if not reserves.has(pilot_id):
		reserves[pilot_id] = []
	(reserves[pilot_id] as Array).append(reserve)


func has_reserve(pilot_id: String, reserve_id: String) -> bool:
	for r: Dictionary in reserves.get(pilot_id, []):
		if str(r.get("id", "")) == reserve_id:
			return true
	return false


## Every choice waiting on this pilot (the head first, then the queue).
func choices_for(pilot_id: String) -> Array:
	var out: Array = []
	if not pending_choice.is_empty() and str(pending_choice.get("pilot", "")) == pilot_id:
		out.append(pending_choice)
	for c: Dictionary in downtime.get("queue", []):
		if str(c.get("pilot", "")) == pilot_id:
			out.append(c)
	return out


func first_choice_for(pilot_id: String) -> Dictionary:
	var all := choices_for(pilot_id)
	return all[0] if not all.is_empty() else {}


## Every pending choice, for anyone.
func all_choices() -> Array:
	var out: Array = []
	if not pending_choice.is_empty():
		out.append(pending_choice)
	out.append_array(downtime.get("queue", []))
	return out


func get_standing(faction: String) -> int:
	return int(standing.get(faction, 0))


func add_log(text: String) -> void:
	log.append(text)
	if log.size() > 400:
		log = log.slice(log.size() - 400)


# --- Saving ------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": VERSION, "standing": standing.duplicate(true), "phase": phase,
		"mission_number": mission_number, "seats": seats.duplicate(true), "npcs": npcs.duplicate(true),
		"hub": hub.duplicate(true), "contacts": contacts.duplicate(), "reserves": reserves.duplicate(true),
		"pilot_hp": pilot_hp.duplicate(), "down_and_out": down_and_out.duplicate(), "dead": dead.duplicate(true),
		"downtime": downtime.duplicate(true), "hooks": hooks.duplicate(true), "current_hook": current_hook.duplicate(true),
		"deals": deals.duplicate(true), "arc": arc.duplicate(true), "tutorial": tutorial.duplicate(true),
		"last_mission": last_mission.duplicate(true), "pending_picks": pending_picks.duplicate(true),
		"pending_choice": pending_choice.duplicate(true), "dialogue": dialogue.duplicate(true),
		"failed_goals": failed_goals.duplicate(true), "line_memory": line_memory.duplicate(),
		"log": log.duplicate(), "story_seed": story_seed, "dice_state": str(dice.get_state()),
	}


static func from_dict(d: Dictionary, story_flags: Dictionary = {}) -> StoryState:
	var s := StoryState.new(int(d.get("story_seed", 0)))
	s.flags = story_flags
	for key in ["standing", "seats", "npcs", "hub", "reserves", "pilot_hp", "down_and_out", "dead", "downtime",
			"current_hook", "deals", "arc", "tutorial", "last_mission", "pending_picks", "pending_choice", "dialogue", "failed_goals", "line_memory"]:
		if d.get(key) is Dictionary:
			s.set(key, (d[key] as Dictionary).duplicate(true))
	for key in ["contacts", "hooks", "log"]:
		if d.get(key) is Array:
			s.set(key, (d[key] as Array).duplicate(true))
	s.phase = str(d.get("phase", "briefing"))
	s.mission_number = int(d.get("mission_number", 1))
	for f: String in s.standing:
		s.standing[f] = int(s.standing[f])
	for p: String in s.pilot_hp:
		s.pilot_hp[p] = int(s.pilot_hp[p])
	var left: Dictionary = s.downtime.get("actions_left", {})
	for p: String in left:
		left[p] = int(left[p])
	for p: String in s.pending_picks:
		for k: String in s.pending_picks[p]:
			s.pending_picks[p][k] = int(s.pending_picks[p][k])
	if d.has("dice_state"):
		s.dice.set_state(int(str(d["dice_state"])))
	return s


## The story kept in a campaign (a new one if it has none yet).
static func of(campaign: Campaign) -> StoryState:
	var raw: Variant = campaign.story_flags.get(KEY)
	if raw is Dictionary:
		return from_dict(raw, campaign.story_flags)
	var s := StoryState.new(hash([campaign.id, "story"]))
	s.flags = campaign.story_flags
	return s


## Writes the story back into the campaign before SaveStore saves it.
func save_to(campaign: Campaign) -> void:
	flags = campaign.story_flags
	campaign.story_flags[KEY] = to_dict()
