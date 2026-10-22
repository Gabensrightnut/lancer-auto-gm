class_name MapDoc
extends RefCounted
## A hand-made or edited battlefield: terrain (BattleMap), its look (kit: "landscape[/culture]"),
## weather, the sitrep it's laid out for, deployment zones and sitrep zones. Saved as JSON in
## user://maps/<name>.json; MissionGenerator.generate(seed, {"map_doc": doc}) uses it instead
## of generating terrain (opts.sitrep defaults to the doc's sitrep).

const DIR := "user://maps/"
const VERSION := 1

var name := "untitled"
var map: BattleMap
var landscape := "grassy_hills"
var culture := ""
var weather := ""
var sitrep := "sitrep_standardcombat"
## Rectangle the map was made on (col, row): needed for halves, mirroring and layouts.
var w := 30
var h := 26
## side -> [[x, y]]; zone name -> [[x, y]].
var deployment: Dictionary = {}
var zones: Dictionary = {}
var notes := ""


static func blank(width: int, height: int, shape: GridLayout.Shape, sitrep_id: String = "sitrep_standardcombat") -> MapDoc:
	var d := MapDoc.new()
	d.w = width
	d.h = height
	d.map = BattleMap.flat(shape, width, height)
	d.sitrep = sitrep_id
	d.relayout(RandomNumberGenerator.new())
	return d


## A generated battlefield to start editing from (same generator as missions).
static func generated(seed_value: int, width: int, height: int, shape: GridLayout.Shape, sitrep_id: String,
		landscape_id: String = "", culture_id: String = "") -> MapDoc:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "mission"])
	var wr := RandomNumberGenerator.new()
	wr.seed = hash([seed_value, "world"])
	var bf := MissionGenerator.battlefield(rng, wr, sitrep_id, width, height, shape, landscape_id, culture_id, int(GmSettings.new().approach))
	var d := MapDoc.new()
	d.w = width
	d.h = height
	d.map = bf["map"]
	d.sitrep = sitrep_id
	d.landscape = bf["world"][0]
	d.culture = bf["world"][1]
	d.deployment = bf["layout"]["deployment"]
	d.zones = bf["layout"]["zones"]
	return d


## Lays the sitrep's zones and deployment out afresh (SitrepLayout), keeping the terrain.
func relayout(rng: RandomNumberGenerator) -> void:
	var lay := SitrepLayout.layout(sitrep, w, h, map.grid.shape, rng)
	deployment = lay["deployment"]
	zones = lay["zones"]


func kit() -> String:
	var k := landscape if culture == "" else "%s/%s" % [landscape, culture]
	return k + ("+" + weather if weather != "" and weather != "clear" else "")


## The layout MapFairness and the mission use.
func layout() -> Dictionary:
	return {"deployment": deployment, "zones": zones, "clear": [], "first_side": "", "sitrep": sitrep}


func fairness() -> Dictionary:
	return MapFairness.check(map, layout(), h)


func to_dict() -> Dictionary:
	return {"version": VERSION, "name": name, "map": map.to_dict(), "landscape": landscape, "culture": culture,
		"weather": weather, "sitrep": sitrep, "w": w, "h": h, "deployment": deployment.duplicate(true),
		"zones": zones.duplicate(true), "notes": notes}


static func from_dict(d: Dictionary) -> MapDoc:
	var m := MapDoc.new()
	m.name = str(d.get("name", "untitled"))
	m.map = BattleMap.from_dict(d.get("map", {}))
	m.landscape = str(d.get("landscape", "grassy_hills"))
	m.culture = str(d.get("culture", ""))
	m.weather = str(d.get("weather", ""))
	m.sitrep = str(d.get("sitrep", "sitrep_standardcombat"))
	m.w = int(d.get("w", 30))
	m.h = int(d.get("h", 26))
	m.deployment = _cells_dict(d.get("deployment", {}))
	m.zones = _cells_dict(d.get("zones", {}))
	m.notes = str(d.get("notes", ""))
	return m


## JSON turns cell coordinates into floats; bring them back to ints.
static func _cells_dict(src: Variant) -> Dictionary:
	var out := {}
	if not src is Dictionary:
		return out
	for k: String in src:
		var list: Array = []
		for c: Variant in src[k]:
			list.append([int(c[0]), int(c[1])])
		out[k] = list
	return out


## A file-safe name: letters, digits, dash and underscore.
static func safe_name(n: String) -> String:
	var out := ""
	for ch in n.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch in ["-", "_"]:
			out += ch
		elif ch == " ":
			out += "_"
	return out if out != "" else "untitled"


func save(dir: String = DIR) -> Error:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(safe_name(name) + ".json"), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return OK


static func load_named(n: String, dir: String = DIR) -> MapDoc:
	var path := dir.path_join(safe_name(n) + ".json")
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(parsed) if parsed is Dictionary else null


## Saved map names, sorted.
static func list(dir: String = DIR) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out
