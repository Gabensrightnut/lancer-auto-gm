class_name WorldStyle
extends RefCounted
## A battlefield's look: a landscape (data/game/biomes/landscapes.json) combined with an
## optional culture/era (cultures.json). Kit names are "landscape" or "landscape/culture",
## e.g. "grassy_hills", "desert_mesas/old_west", "city/cyberpunk". The style only changes
## how the board looks; the rules terrain is the BattleMap and nothing here edits it.
##
## A culture can override any landscape field (deep merge), so "city/cyberpunk" can turn the
## sun into a night sky while "grassy_hills/medieval" keeps the hills' light.

const LANDSCAPES := "res://data/game/biomes/landscapes.json"
const CULTURES := "res://data/game/biomes/cultures.json"
const WEATHER := "res://data/game/biomes/weather.json"
## Old kit names used by the demo and earlier saves.
const LEGACY := {"urban_ruins": "city/ruins", "alien": "alien_wilds"}

static var _data: Dictionary = {}


static func _load() -> void:
	if not _data.is_empty():
		return
	for key: String in ["landscapes", "cultures", "weather"]:
		var path: String = {"landscapes": LANDSCAPES, "cultures": CULTURES, "weather": WEATHER}[key]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_data[key] = parsed if parsed is Dictionary else {}


static func landscapes() -> Array:
	_load()
	return (_data["landscapes"] as Dictionary).keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


static func weathers() -> Array:
	_load()
	return (_data["weather"] as Dictionary).keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


static func cultures() -> Array:
	_load()
	return (_data["cultures"] as Dictionary).keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


## The merged style for a kit name. Unknown parts fall back to grassy hills / no culture.
static func resolve(kit: String) -> Dictionary:
	_load()
	var weather := ""
	if "+" in kit:
		weather = kit.get_slice("+", 1)
		kit = kit.get_slice("+", 0)
	kit = LEGACY.get(kit, kit)
	var parts := kit.split("/")
	var lands: Dictionary = _data["landscapes"]
	var cults: Dictionary = _data["cultures"]
	var land_id: String = parts[0] if lands.has(parts[0]) else "grassy_hills"
	var style: Dictionary = (lands.get(land_id, {}) as Dictionary).duplicate(true)
	var base: String = str(style.get("base", ""))
	if base != "" and lands.has(base):
		style = merge((lands[base] as Dictionary).duplicate(true), style)
	style["landscape"] = land_id
	style["culture"] = ""
	if parts.size() > 1 and cults.has(parts[1]):
		var cult := (cults[parts[1]] as Dictionary).duplicate(true)
		var in_city: Dictionary = cult.get("in_city", {})
		cult.erase("in_city")
		style = merge(style, cult)
		if bool(style.get("urban", false)) and not in_city.is_empty():
			style = merge(style, in_city)  # the culture's own city: its sky, light and palette
		style["culture"] = parts[1]
		style["culture_name"] = (cults[parts[1]] as Dictionary).get("name", parts[1])
		style["name"] = (lands[land_id] as Dictionary).get("name", land_id)
	style["kit"] = "%s/%s" % [land_id, style["culture"]] if style["culture"] != "" else land_id
	style["weather"] = ""
	var wd: Dictionary = _data["weather"]
	if weather != "" and wd.has(weather) and weather != "clear":
		var w: Dictionary = (wd[weather] as Dictionary).duplicate(true)
		var light: Dictionary = style.get("light", {})
		# Scales apply to the style's own values.
		if w.has("fog_scale"):
			light["fog_density"] = float(light.get("fog_density", 0.004)) * float(w["fog_scale"])
		var wl: Dictionary = w.get("light", {})
		if wl.has("sun_energy_scale"):
			light["sun_energy"] = float(light.get("sun_energy", 2.2)) * float(wl["sun_energy_scale"])
			wl.erase("sun_energy_scale")
		style["light"] = light
		w.erase("fog_scale")
		style = merge(style, w)
		style["weather"] = weather
		style["kit"] += "+" + weather
	return style


## Deep merge: dictionaries merge key by key, everything else in `over` replaces `base`.
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	for k: Variant in over:
		if base.get(k) is Dictionary and over[k] is Dictionary:
			base[k] = merge(base[k], over[k])
		else:
			base[k] = over[k]
	return base


## Reads a value from a nested path like "ground.top_a".
static func value(style: Dictionary, path: String, default: Variant = null) -> Variant:
	var cur: Variant = style
	for p in path.split("."):
		if not cur is Dictionary or not (cur as Dictionary).has(p):
			return default
		cur = cur[p]
	return cur


## Colors in the data are "#rrggbb" strings or [r, g, b(, a)] arrays.
static func color(v: Variant, default: Color = Color.MAGENTA) -> Color:
	if v is String:
		return Color.html(v)
	if v is Array:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	if v is Color:
		return v
	return default


static func col(style: Dictionary, path: String, default: Color = Color.MAGENTA) -> Color:
	return color(value(style, path), default)


static func num(style: Dictionary, path: String, default: float = 0.0) -> float:
	var v: Variant = value(style, path, default)
	return float(v) if (v is float or v is int) else default
