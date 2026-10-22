class_name MissionAutosave
extends RefCounted
## Saves the mission in progress after every turn, and brings it back after a crash or quit.
##
##   var autosave := MissionAutosave.new(host, mission, store, campaign.id, gm_settings)
##   ...later, on the host:
##   var r := MissionAutosave.resume(store, campaign.id)   # {host, mission, settings, error}
##   Net.host = r["host"]; Net.open_online(r["host"], r["room"])  # same room code
##   r["host"].hold_until_back()   # waits for every remote player to reconnect
##
## The save holds the full GameState (including the dice, so rolls continue exactly), the
## Mission, the GM settings and the seat setup (reconnect tokens: host-only, never sent).

signal saved(round_number: int)

var host: NetHost
var mission: Mission
var store: SaveStore
var campaign_id := ""
var settings: GmSettings


func _init(net_host: NetHost, the_mission: Mission, save_store: SaveStore, the_campaign_id: String, gm: GmSettings = null) -> void:
	host = net_host
	mission = the_mission
	store = save_store
	campaign_id = the_campaign_id
	settings = gm if gm != null else GmSettings.from_preset("Standard")
	host.action_resolved.connect(_on_action_resolved)


## Saves right now. Returns "" or the problem.
func save_now() -> String:
	var err := store.save_mission(campaign_id, snapshot())
	if err == "":
		saved.emit(host.state.round_number)
	return err


func snapshot() -> Dictionary:
	return {"state": host.state.to_dict(), "mission": mission.to_dict() if mission != null else {},
		"gm": settings.to_dict(), "seats": host.export_seats(), "room": host.room_code,
		"view_intel": host.view_filter.intel.duplicate(true), "saved_at": int(Time.get_unix_time_from_system())}


func _on_action_resolved(_seat: String, _action: Dictionary, _result: RuleResult, events: Array) -> void:
	for e: Dictionary in events:
		if e.get("type", "") == "mission_ended":
			store.clear_mission(campaign_id)
			return
	for e: Dictionary in events:
		if e.get("type", "") == "turn_ended":
			save_now()
			return


## Loads a mission autosave into a new host. {host, mission, settings, room, error}.
## The host holds (nothing happens) until every remote player is back: see hold_until_back.
static func resume(save_store: SaveStore, the_campaign_id: String, engine: RulesEngine = null) -> Dictionary:
	var r := save_store.load_mission(the_campaign_id)
	if r["error"] != "":
		return {"error": r["error"]}
	var d: Dictionary = r["data"]
	var state := GameState.from_dict(d.get("state", {}))
	var h := NetHost.new(state, engine if engine != null else RulesEngine.new())
	h.view_filter.intel = (d.get("view_intel", {}) as Dictionary).duplicate(true)
	h.import_seats(d.get("seats", {}))
	var m: Mission = Mission.from_dict(d["mission"]) if not (d.get("mission", {}) as Dictionary).is_empty() else null
	return {"host": h, "mission": m, "settings": GmSettings.from_dict(d.get("gm", {})),
		"room": str(d.get("room", "")), "error": ""}
