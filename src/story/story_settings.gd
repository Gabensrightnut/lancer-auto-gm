class_name StorySettings
extends RefCounted
## Per-player reading options for story text, kept on this machine (user://), not in the
## campaign: text size, and skipping lines you've already read. A settings screen can call
## the setters; story UI reads them when it builds (StoryStyle scales every label and button)
## and the dialogue re-reads them on every line.
##
##   StorySettings.set_text_scale(1.25)   # 0.8 .. 1.6
##   StorySettings.set_skip_seen(true)    # lines read before go by on their own
##   StorySettings.changed.connect(...)   # via StorySettings.notifier()

const FILE := "user://story_settings.cfg"
const SEEN_FILE := "user://story_seen.json"
const SCALES := [0.85, 1.0, 1.15, 1.3, 1.5]
const MAX_SEEN := 20000

## false: nothing is read from or written to disk (tests, previews).
static var persist := true
static var _loaded := false
static var _scale := 1.0
static var _skip_seen := false
static var _seen: Dictionary = {}
static var _notifier: Notifier


class Notifier:
	extends RefCounted
	signal changed


static func notifier() -> Notifier:
	if _notifier == null:
		_notifier = Notifier.new()
	return _notifier


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not persist:
		return
	var cfg := ConfigFile.new()
	if cfg.load(FILE) == OK:
		_scale = clampf(float(cfg.get_value("text", "scale", 1.0)), 0.8, 1.6)
		_skip_seen = bool(cfg.get_value("dialogue", "skip_seen", false))
	if FileAccess.file_exists(SEEN_FILE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEEN_FILE))
		if d is Array:
			for k: Variant in d:
				_seen[str(k)] = true


static func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("text", "scale", _scale)
	cfg.set_value("dialogue", "skip_seen", _skip_seen)
	cfg.save(FILE)


static func text_scale() -> float:
	_load()
	return _scale


static func set_text_scale(v: float) -> void:
	_load()
	_scale = clampf(v, 0.8, 1.6)
	_save()
	notifier().changed.emit()


## The next size in SCALES (for a single "text size" button).
static func cycle_text_scale() -> float:
	var i := 0
	for j in range(SCALES.size()):
		if absf(float(SCALES[j]) - text_scale()) < 0.01:
			i = j
	set_text_scale(float(SCALES[(i + 1) % SCALES.size()]))
	return _scale


## A font size scaled by the player's setting.
static func size(base: int) -> int:
	return maxi(8, roundi(base * text_scale()))


static func skip_seen() -> bool:
	_load()
	return _skip_seen


static func set_skip_seen(on: bool) -> void:
	_load()
	_skip_seen = on
	_save()
	notifier().changed.emit()


static func line_key(scene: String, node: String, text: String) -> String:
	return "%s:%s:%d" % [scene, node, hash(text)]


static func was_seen(key: String) -> bool:
	_load()
	return _seen.has(key)


static func mark_seen(key: String) -> void:
	_load()
	if _seen.has(key):
		return
	_seen[key] = true
	if _seen.size() > MAX_SEEN:
		_seen.erase(_seen.keys()[0])
	if persist:
		var f := FileAccess.open(SEEN_FILE, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(_seen.keys()))


## For tests: forget everything and stop touching disk.
static func reset_for_tests() -> void:
	persist = false
	_loaded = true
	_scale = 1.0
	_skip_seen = false
	_seen = {}
