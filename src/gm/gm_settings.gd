class_name GmSettings
extends RefCounted
## The procedural GM's personality dials (DESIGN.md section 9). Presets and dial meanings live
## in data/game/gm/presets.json so they can be tuned without code.

const PRESETS_FILE := "res://data/game/gm/presets.json"
const BEHAVIORS_FILE := "res://data/game/gm/behaviors.json"
const MISSIONS_FILE := "res://data/game/gm/missions.json"
const DIALS := ["aggression", "caution", "focus_fire", "reinforcements", "difficulty", "randomness", "environments", "approach"]

var preset := "Standard"
var aggression := 0.6
var caution := 0.5
var focus_fire := 0.5
var reinforcements := 0.15
var difficulty := 1.0
var randomness := 0.25
## Chance that weather or a world that suggests a rules environment (a sandstorm, low gravity)
## actually brings that environment's rules into the mission (MissionGenerator).
var environments := 0.5
## Basic Combat: the most rows between the two deployment zones (SitrepLayout), so first contact
## comes by about the second turn; 0 = deploy at the map edges.
var approach := 14.0
## Write a log line for every AI decision (always on for "Teaching").
var explain := true


static func from_preset(name: String) -> GmSettings:
	var s := GmSettings.new()
	var p: Dictionary = presets().get(name, {})
	if p.is_empty():
		push_warning("Unknown GM preset '%s', using Standard." % name)
		p = presets().get("Standard", {})
		name = "Standard"
	s.preset = name
	for key: String in DIALS:
		if p.has(key):
			s.set(key, float(p[key]))
	s.explain = bool(p.get("explain", true))
	return s


static func preset_names() -> Array:
	return presets().keys()


static func presets() -> Dictionary:
	return load_json(PRESETS_FILE).get("presets", {})


func to_dict() -> Dictionary:
	return {"preset": preset, "aggression": aggression, "caution": caution, "focus_fire": focus_fire,
		"reinforcements": reinforcements, "difficulty": difficulty, "randomness": randomness, "environments": environments, "approach": approach, "explain": explain}


static func from_dict(d: Dictionary) -> GmSettings:
	var s := from_preset(str(d.get("preset", "Standard")))
	for key: String in DIALS:
		if d.has(key):
			s.set(key, float(d[key]))
	s.explain = bool(d.get("explain", s.explain))
	return s


static func load_json(path: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_error("Can't read " + path)
		return {}
	return json.data
