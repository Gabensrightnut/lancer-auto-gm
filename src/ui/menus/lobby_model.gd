class_name LobbyModel
extends RefCounted
## Everything the lobby screen shows and changes, without any UI (so it's testable):
## who sits where, which seats the AI plays, pilots, content packs, GM preset, grid shape,
## ready-up, and why the mission can't start yet.
##
## The host's lobby is the generated mission in its setup phase: friends join that NetHost,
## and changing the grid or preset regenerates the battlefield with the same seed.
## A joining player's lobby (is_host = false) mirrors what the host sends.
##
## Seat modes:
##   "you"       played on this computer (several = hot-seat)
##   "ai"        an AI pilot (a friend who joins takes over; the AI picks it back up)
##   "open"      waiting for a friend to join (gets an AI pilot if "fill empty seats" is on)
##   "reserved"  kept for a friend; never filled by the AI

signal changed

const MODES := ["you", "ai", "open", "reserved"]
const MODE_LABELS := {"you": "You (this screen)", "ai": "AI pilot", "open": "Open for a friend", "reserved": "Reserved for a friend"}
const PRESETS := ["Standard", "Ruthless", "Cautious", "Chaotic", "Teaching"]

var is_host := true
var campaign: Campaign
var db: ContentDB
var host: NetHost
var mission: Mission
var client: NetClient
## {"preset", "shape": "hex"/"square", "sitrep": "" (random), "seed": int, "fill_empty_with_ai": bool}
var options: Dictionary = {"preset": "Standard", "shape": "hex", "sitrep": "", "seed": 0, "fill_empty_with_ai": false}
## seat -> mode (host)
var modes: Dictionary = {}
## seat -> pilot id (host)
var assignment: Dictionary = {}
## seat -> true when that seat's player pressed Ready
var ready: Dictionary = {}
## Messages for the player: [{"kind": "error"/"warn"/"info", "text"}]
var messages: Array = []
## What the host last sent (joining players).
var remote: Dictionary = {}
## The host started the mission (joining players move to the battle).
var started := false


## A host lobby for `the_campaign`. The first seat is yours, the rest start as AI pilots.
static func for_host(the_campaign: Campaign, content: ContentDB, mission_seed: int = 0) -> LobbyModel:
	var m := LobbyModel.new()
	m.campaign = the_campaign
	m.db = content
	m.options["seed"] = mission_seed if mission_seed != 0 else int(Time.get_unix_time_from_system()) % 1000000
	m.options["preset"] = str(the_campaign.gm_settings.get("preset", "Standard"))
	var squad := the_campaign.squad()
	for i in range(squad.size()):
		var seat: String = squad[i]["seat"]
		m.assignment[seat] = squad[i]["pilot"]["id"]
		m.modes[seat] = "you" if i == 0 else "ai"
	m._rebuild()
	return m


## A joining player's lobby: mirrors the host through `net_client`.
static func for_client(net_client: NetClient) -> LobbyModel:
	var m := LobbyModel.new()
	m.is_host = false
	m.client = net_client
	net_client.lobby_updated.connect(m._on_remote_lobby)
	net_client.refused.connect(m._on_refused)
	net_client.join_failed.connect(m._on_join_failed)
	return m


func seats() -> Array:
	var out: Array = modes.keys()
	out.sort()
	return out


# --- Host changes ------------------------------------------------------------------------

func set_mode(seat: String, mode: String) -> void:
	if not is_host or not mode in MODES or not modes.has(seat):
		return
	modes[seat] = mode
	_apply_modes()
	_changed()


func set_fill_empty(on: bool) -> void:
	options["fill_empty_with_ai"] = on
	host.set_fill_empty_with_ai(on)
	_changed()


## Puts a pilot in a seat; if that pilot was in another seat, the two swap.
func assign_pilot(seat: String, pilot_id: String) -> void:
	if not campaign.pilots.has(pilot_id) or not assignment.has(seat):
		return
	for other: String in assignment:
		if assignment[other] == pilot_id and other != seat:
			assignment[other] = assignment[seat]
	assignment[seat] = pilot_id
	_rebuild()


func set_preset(preset: String) -> void:
	if preset in PRESETS:
		options["preset"] = preset
		campaign.gm_settings = GmSettings.from_preset(preset).to_dict()
		_rebuild()


func set_shape(shape: String) -> void:
	if shape in ["hex", "square"]:
		options["shape"] = shape
		_rebuild()


## Turns content packs on for the campaign (summaries from PackLibrary).
func set_packs(pack_list: Array, content: ContentDB) -> void:
	campaign.packs = pack_list.duplicate(true)
	db = content
	_rebuild()


func set_ready(seat: String, is_ready: bool) -> void:
	if is_host:
		ready[seat] = is_ready
		_changed()
	elif client != null:
		client.send_ready(is_ready)


## Readies every seat played on this computer.
func set_local_ready(is_ready: bool) -> void:
	if is_host:
		for seat: String in modes:
			if modes[seat] == "you":
				ready[seat] = is_ready
		_changed()
	else:
		set_ready(client.seat, is_ready)


# --- What the screen shows ---------------------------------------------------------------

## One row per seat: {seat, callsign, pilot, pilot_id, mech, ll, mode, mode_label, player,
## connected, ready, ai, problems: [String]}
func rows() -> Array:
	if not is_host:
		return remote.get("rows", [])
	var out: Array = []
	var table := host.seat_table()
	for seat: String in seats():
		var p: Dictionary = campaign.pilots.get(assignment.get(seat, ""), {})
		var t: Dictionary = table.get(seat, {})
		var mech: Dictionary = {}
		for m: Dictionary in p.get("mechs", []):
			if m["id"] == p.get("active_mech", "") or mech.is_empty():
				mech = m
		var ai := host.is_ai_seat(seat)
		var connected: bool = modes[seat] == "you" or ai or bool(t.get("connected", false)) and t.get("where", "") == "remote"
		out.append({
			"seat": seat, "callsign": str(p.get("callsign", "")), "pilot": str(p.get("name", "")),
			"pilot_id": str(p.get("id", "")), "mech": str(mech.get("name", "")),
			"frame": str(db.frame(str(mech.get("frame", ""))).get("name", "")),
			"source": str(db.frame(str(mech.get("frame", ""))).get("source", "GMS")),
			"ll": int(p.get("ll", 0)), "mode": modes[seat], "mode_label": MODE_LABELS[modes[seat]],
			"player": str(t.get("player", "")) if t.get("where", "") == "remote" else ("You" if modes[seat] == "you" else ""),
			"connected": connected, "ready": ai or bool(ready.get(seat, false)), "ai": ai,
			"problems": campaign.validate_pilot(p, db) if not p.is_empty() else ["No pilot assigned."],
		})
	return out


## Why the mission can't start yet, in plain words (empty = ready to launch).
func start_problems() -> Array:
	if not is_host:
		return remote.get("problems", [])
	var out: Array = []
	var lib_missing: Array = PackLibrary.missing(campaign.packs, db.packs)
	if not lib_missing.is_empty():
		out.append("Content packs not installed on this computer: %s." % PackLibrary.describe(lib_missing))
	for r: Dictionary in rows():
		var who: String = r["callsign"] if r["callsign"] != "" else r["seat"]
		if not r["problems"].is_empty():
			out.append("%s's build isn't legal: %s" % [who, r["problems"][0]])
		if r["ai"]:
			continue
		match r["mode"]:
			"open", "reserved":
				if not r["connected"]:
					out.append("%s's seat is waiting for a friend to join. Set it to AI%s." % [who, "" if r["mode"] == "reserved" else ", or turn on \"Fill empty seats with AI\""])
				elif not r["ready"]:
					out.append("%s (%s) isn't ready yet." % [who, r["player"]])
			"you":
				if not r["ready"]:
					out.append("Press Ready when you're set.")
	var unique: Array = []
	for o in out:
		if not unique.has(o):
			unique.append(o)
	return unique


func can_start() -> bool:
	return is_host and start_problems().is_empty()


## What joining players see (sent over the network on every change).
func summary() -> Dictionary:
	return {"options": options.duplicate(), "rows": rows(), "problems": start_problems(), "started": started,
		"campaign": campaign.name, "packs": campaign.packs.duplicate(true),
		"briefing": mission.briefing if mission != null else ""}


## Starts the mission: the GM (AI) begins the battle. Returns {host, director, mission} or
## {"error"} when something still blocks it.
func start() -> Dictionary:
	var problems := start_problems()
	if not problems.is_empty():
		return {"error": problems[0]}
	var director := AiDirector.new(host, GmSettings.from_preset(options["preset"]), mission)
	started = true
	_broadcast()
	return {"host": host, "director": director, "mission": mission}


# --- Internals ---------------------------------------------------------------------------

func _rebuild() -> void:
	var squad: Array = []
	for seat: String in seats():
		var p: Dictionary = campaign.pilots.get(assignment.get(seat, ""), {})
		if p.is_empty():
			continue
		var mech: Dictionary = {}
		for m: Dictionary in p.get("mechs", []):
			if m["id"] == p.get("active_mech", "") or mech.is_empty():
				mech = m
		squad.append({"seat": seat, "pilot": p, "mech": mech})
	var gen := MissionGenerator.generate(int(options["seed"]), {
		"squad": squad, "shape": options["shape"], "sitrep": options["sitrep"], "db": db,
		"settings": GmSettings.from_preset(options["preset"]), "players": squad.size()})
	var state: GameState = gen["state"]
	campaign.prepare_mission(state)
	mission = gen["mission"]
	if host == null:
		host = NetHost.new(state, RulesEngine.new())
		host.lobby_message.connect(_on_lobby_message)
		host.seats_changed.connect(_on_seats_changed)
	else:
		host.state = state
	_apply_modes()
	host.set_fill_empty_with_ai(bool(options["fill_empty_with_ai"]))
	host.send_updates()
	_changed()


func _apply_modes() -> void:
	for seat: String in modes:
		match modes[seat]:
			"you":
				host.add_local_seat(seat)
				host.set_seat_ai(seat, false)
				host.set_seat_reserved(seat, false)
			"ai":
				host.remove_local_seat(seat)
				host.set_seat_ai(seat, true)
				host.set_seat_reserved(seat, false)
			"open":
				host.remove_local_seat(seat)
				host.set_seat_ai(seat, false)
				host.set_seat_reserved(seat, false)
			"reserved":
				host.remove_local_seat(seat)
				host.set_seat_ai(seat, false)
				host.set_seat_reserved(seat, true)


func _on_seats_changed(_table: Dictionary) -> void:
	_broadcast()


func _on_lobby_message(seat: String, msg: Dictionary) -> void:
	if msg.has("ready"):
		ready[seat] = bool(msg["ready"])
		_changed()


func _on_remote_lobby(data: Dictionary) -> void:
	remote = data
	started = bool(data.get("started", false))
	options = (data.get("options", {}) as Dictionary).duplicate()
	changed.emit()


func _on_join_failed(why: String) -> void:
	_message("error", "Couldn't join: %s" % why)


func _on_refused(code: String, reason: String) -> void:
	match code:
		NetProtocol.REFUSE_VERSION:
			_message("error", "Version mismatch. %s" % reason)
		NetProtocol.REFUSE_PACKS:
			_message("error", "Content packs don't match. %s" % reason)
		_:
			_message("error", reason)


func _message(kind: String, text: String) -> void:
	messages.append({"kind": kind, "text": text})
	changed.emit()


func _changed() -> void:
	_broadcast()
	changed.emit()


func _broadcast() -> void:
	if is_host and host != null:
		host.send_lobby(summary())
