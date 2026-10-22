class_name MenuSession
extends RefCounted
## What the menu screens share while the player moves between them: the open campaign, the
## lobby, the content database for the campaign's packs, settings.

const SCREENS := {
	"main": "res://scenes/menus/main_menu.tscn",
	"lobby": "res://scenes/menus/lobby.tscn",
	"builder": "res://scenes/menus/builder.tscn",
	"settings": "res://scenes/menus/settings.tscn",
	"battle": "res://scenes/flow/battle.tscn",
	"debrief": "res://scenes/flow/debrief.tscn",
	"hub": "res://scenes/flow/hub.tscn",
}
## The battle screen (src/flow/battle_screen.gd: the 3D view and HUD on a BattleSession).
const BATTLE_SCENE := "res://scenes/flow/battle.tscn"

static var store := SaveStore.new()
static var library := PackLibrary.new()
static var campaign: Campaign
static var lobby: LobbyModel
## Pilot being edited in the builder, and where to go back to.
static var builder_pilot := ""
static var back_to := "main"
## Open the pilot look creator as soon as the builder opens (a new pilot).
static var open_creator := false
static var _settings: GameSettings
static var _db: ContentDB
static var _db_key := "-"


## The Net autoload (looked up at run time so screens also open on their own, e.g. for
## screenshots, where autoloads aren't loaded).
static func net(from: Node) -> Node:
	return from.get_node_or_null("/root/Net")


static func go(from: Node, screen: String) -> void:
	from.get_tree().change_scene_to_file(SCREENS[screen])


static func settings() -> GameSettings:
	if _settings == null:
		_settings = GameSettings.load_settings()
		HouseRulesFlow.mine = _settings.house_rules  # this player's house rules (same dictionary)
	return _settings


## Core data plus the open campaign's packs (rebuilt when the pack list changes).
static func content() -> ContentDB:
	var packs: Array = campaign.packs if campaign != null else []
	var key := JSON.stringify(packs)
	if _db == null or key != _db_key:
		_db = library.load_db(packs)["db"]
		_db_key = key
	return _db


## A campaign with starting pilots, named from the COMP/CON lists.
static func new_campaign(name: String, pilots: int, start_ll: int, preset: String) -> Campaign:
	var c := Campaign.create(name, {"start_ll": start_ll, "gm_preset": preset})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([c.id, "names"])
	var names := NameGen.new(rng)
	for i in range(pilots):
		c.new_pilot(names.pilot_name(), names.callsign())
	return c


## When a screen is opened on its own (development, screenshots), make an unsaved example.
static func ensure_campaign() -> Campaign:
	if campaign == null:
		campaign = new_campaign("Example Campaign", 4, 0, "Standard")
	return campaign
