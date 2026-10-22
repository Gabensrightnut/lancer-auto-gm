class_name GameFlow
extends RefCounted
## The campaign loop (DESIGN.md milestone 1): menu → new campaign / continue / join → lobby →
## builder → GM-generated mission → battle → mission end → debrief and level up → save → next
## mission. Screens call these; tests drive them directly.
##
## Leveling: every pilot in the squad gains a License Level after each mission (CANON.md
## "Mission structure ... debrief, level up", Core p.40). PROVISIONAL (docs/RULES_TODO.md
## "Leveling pace"): one LL per mission played to the end, win or lose.

## The battle in progress (screens hand it to each other).
static var session: BattleSession
## The last debrief (debrief screen).
static var debrief: Dictionary = {}
## Seats played on this computer in the current battle.
static var local_seats: Array = []
## Room code of the last resumed mission (reopened so friends can rejoin).
static var last_room := ""


## Starts the lobby's mission. Returns the session, or null with `error` set on the lobby.
static func start_mission(lobby: LobbyModel, store: SaveStore) -> BattleSession:
	var r := lobby.start()
	if r.has("error"):
		lobby.messages.append({"kind": "error", "text": r["error"]})
		return null
	store.save_campaign(lobby.campaign)
	var settings := GmSettings.from_preset(str(lobby.options.get("preset", "Standard")))
	var save := MissionAutosave.new(r["host"], r["mission"], store, lobby.campaign.id, settings)
	local_seats = []
	for seat: String in lobby.modes:
		if lobby.modes[seat] == "you":
			local_seats.append(seat)
	local_seats.sort()
	session = BattleSession.for_host(r["host"], r["director"], r["mission"], local_seats, save)
	save.save_now()  # Even quitting before the first turn ends can be continued.
	return session


## Picks a saved mission back up (host). Returns the session or null.
static func resume_mission(store: SaveStore, campaign: Campaign) -> BattleSession:
	var r := MissionAutosave.resume(store, campaign.id)
	if r.get("error", "") != "":
		return null
	last_room = str(r.get("room", ""))
	var host: NetHost = r["host"]
	var director := AiDirector.new(host, r["settings"], r["mission"])
	var save := MissionAutosave.new(host, r["mission"], store, campaign.id, r["settings"])
	local_seats = Array(host.local_seats)
	session = BattleSession.for_host(host, director, r["mission"], local_seats, save)
	host.hold_until_back()
	return session


## After the mission: record it, level the squad up, save. Returns what the debrief shows:
## {outcome, reason, title, sitrep, operation, rounds, pilots: [{id, callsign, name, old_ll,
##  new_ll, mech, mech_destroyed}], campaign}
static func finish_mission(s: BattleSession, campaign: Campaign, store: SaveStore) -> Dictionary:
	var state := s.host.state
	var m := s.mission
	campaign.record_mission(state, m)
	var pilots: Array = []
	for seat: String in state.seats:
		var info: Dictionary = state.seats[seat]
		var pid := str(info.get("pilot_id", ""))
		if pid == "" or not campaign.pilots.has(pid):
			continue
		var old := int(campaign.pilots[pid]["ll"])
		campaign.level_up(pid)
		var u := state.unit(seat)
		pilots.append({"id": pid, "callsign": str(info.get("callsign", "")), "name": str(info.get("pilot", "")),
			"old_ll": old, "new_ll": int(campaign.pilots[pid]["ll"]), "mech": str(info.get("mech", "")),
			"mech_destroyed": u != null and u.destroyed})
	store.save_campaign(campaign)
	store.clear_mission(campaign.id)
	debrief = {"outcome": m.outcome, "reason": m.outcome_reason, "title": title_for(m.outcome),
		"sitrep": m.sitrep_name, "operation": str(m.flavor.get("operation", "")), "rounds": state.round_number,
		"pilots": pilots, "campaign": campaign.name}
	session = null
	return debrief


## The next mission's lobby: same squad and seats, a new battlefield.
static func next_lobby(previous: LobbyModel, campaign: Campaign, db: ContentDB) -> LobbyModel:
	var l := LobbyModel.for_host(campaign, db)
	if previous != null:
		for seat: String in previous.modes:
			if l.modes.has(seat):
				l.modes[seat] = previous.modes[seat]
		l._apply_modes()
		l.set_fill_empty(bool(previous.options.get("fill_empty_with_ai", false)))
		l.options["shape"] = previous.options.get("shape", "hex")
		l.set_preset(str(previous.options.get("preset", "Standard")))  # rebuilds the mission
	return l


static func title_for(the_outcome: String) -> String:
	match the_outcome:
		"players":
			return "Mission complete"
		"enemies":
			return "Mission failed"
	return "Withdrawn"
