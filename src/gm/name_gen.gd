class_name NameGen
extends RefCounted
## Seeded names and mission flavor from COMP/CON's generator lists (data/compcon/generators/,
## GPL-3.0, unmodified). Our own extra lists go in data/game/ and are added on top.

const DIR := "res://data/compcon/generators/"
const OWN_DIR := "res://data/game/names/"

var rng: RandomNumberGenerator
var _lists: Dictionary = {}  # file name -> PackedStringArray
var _used: Dictionary = {}  # value -> true (no repeats within one generator)


func _init(random: RandomNumberGenerator) -> void:
	rng = random


## A pilot callsign, e.g. "Blackjack".
func callsign() -> String:
	return _fresh("callsigns.txt")


## A full pilot name, with COMP/CON's chances of a middle name, a second surname and a
## suffix (name_mods.json).
func pilot_name() -> String:
	var mods := _mods()
	var parts := PackedStringArray([pick("firstnames.txt")])
	if rng.randf() < float(mods.get("middleNameChance", 0.0)):
		parts.append(pick("firstnames.txt"))
	parts.append(pick("lastnames.txt"))
	if rng.randf() < float(mods.get("secondSurnameChance", 0.0)):
		parts[parts.size() - 1] += "-" + pick("lastnames.txt")
	var suffixes: Array = mods.get("suffixes", [])
	if not suffixes.is_empty() and rng.randf() < float(mods.get("suffixChance", 0.0)):
		parts.append(str(suffixes[rng.randi_range(0, suffixes.size() - 1)]))
	return " ".join(parts)


func mech_name() -> String:
	return _fresh("mechnames.txt")


## "OPERATION SOLAR CAIRN" style codename from mission.json.
func operation() -> String:
	var m := _json("mission.json")
	var a: Array = m.get("a", ["FIRST"])
	var b: Array = m.get("b", ["LIGHT"])
	return "OPERATION %s %s" % [a[rng.randi_range(0, a.size() - 1)], b[rng.randi_range(0, b.size() - 1)]]


func planet() -> String:
	return pick("planets.txt")


func faction() -> String:
	return pick("factions.txt")


func station() -> String:
	return pick("stations.txt")


func team_name() -> String:
	return pick("teamnames.txt")


func cargo() -> String:
	return pick("cargo.txt")


## A random line from a list ("" if the list is missing).
func pick(file: String) -> String:
	var list := lines(file)
	return list[rng.randi_range(0, list.size() - 1)] if not list.is_empty() else ""


func _fresh(file: String) -> String:
	for i in range(20):
		var v := pick(file)
		if not _used.has(v):
			_used[v] = true
			return v
	return pick(file)


## A list: COMP/CON's lines plus ours from data/game/names/ with the same file name.
func lines(file: String) -> PackedStringArray:
	if not _lists.has(file):
		var out := PackedStringArray()
		for dir in [DIR, OWN_DIR]:
			if FileAccess.file_exists(dir + file):
				for line in FileAccess.get_file_as_string(dir + file).split("\n"):
					var t := line.strip_edges()
					if t != "":
						out.append(t)
		_lists[file] = out
	return _lists[file]


func _mods() -> Dictionary:
	return _json("name_mods.json")


func _json(file: String) -> Dictionary:
	if not _lists.has(file):
		var json := JSON.new()
		_lists[file] = json.data if json.parse(FileAccess.get_file_as_string(DIR + file)) == OK and json.data is Dictionary else {}
	return _lists[file]
