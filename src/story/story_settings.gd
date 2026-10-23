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
## "third": Lancer Tactics-style pop-up with portrait cards; "first": face to face (the camera
## holds on the person's face, subtitles at the bottom). Radio calls always use the comms frame.
static var _view := "third"
static var _seen: Dictionary = {}
## Walking in first person: mouse look speed (0.25..3) and invert-Y.
static var _look := 1.0
static var _invert_y := false
## The show-cursor key (show_cursor, Alt): "hold" while held, or "toggle" press to show/hide.
static var _cursor_mode := "hold"
static var _vote_picture := "pilot"
## Food and water (house rule): your pilots eat and drink from their pack when a bar gets low.
static var _auto_eat := true
## How many times the "Hold Alt to use the mouse" hint has been shown (stops after a few).
static var _cursor_hints := 0
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
		_view = str(cfg.get_value("dialogue", "view", "third"))
		_look = clampf(float(cfg.get_value("walking", "look_sensitivity", 1.0)), 0.25, 3.0)
		_invert_y = bool(cfg.get_value("walking", "invert_y", false))
		_cursor_mode = "toggle" if str(cfg.get_value("walking", "cursor_mode", "hold")) == "toggle" else "hold"
		_cursor_hints = int(cfg.get_value("walking", "cursor_hints", 0))
		_vote_picture = "mech" if str(cfg.get_value("dialogue", "vote_picture", "pilot")) == "mech" else "pilot"
		_auto_eat = bool(cfg.get_value("gameplay", "auto_eat", true))
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
	cfg.set_value("dialogue", "view", _view)
	cfg.set_value("walking", "look_sensitivity", _look)
	cfg.set_value("walking", "invert_y", _invert_y)
	cfg.set_value("walking", "cursor_mode", _cursor_mode)
	cfg.set_value("walking", "cursor_hints", _cursor_hints)
	cfg.set_value("dialogue", "vote_picture", _vote_picture)
	cfg.set_value("gameplay", "auto_eat", _auto_eat)
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


static func dialogue_view() -> String:
	_load()
	return _view


static func set_dialogue_view(v: String) -> void:
	_load()
	_view = "first" if v == "first" else "third"
	_save()
	notifier().changed.emit()


static func look_sensitivity() -> float:
	_load()
	return _look


static func set_look_sensitivity(v: float) -> void:
	_load()
	_look = clampf(v, 0.25, 3.0)
	_save()
	notifier().changed.emit()


static func invert_y() -> bool:
	_load()
	return _invert_y


static func set_invert_y(on: bool) -> void:
	_load()
	_invert_y = on
	_save()
	notifier().changed.emit()


## On the squad's vote screen: each voter shown by their "pilot" portrait or their "mech".
static func vote_picture() -> String:
	_load()
	return _vote_picture


static func set_vote_picture(v: String) -> void:
	_load()
	_vote_picture = "mech" if v == "mech" else "pilot"
	_save()
	notifier().changed.emit()


static func auto_eat() -> bool:
	_load()
	return _auto_eat


static func set_auto_eat(on: bool) -> void:
	_load()
	_auto_eat = on
	_save()
	notifier().changed.emit()


static func cursor_mode() -> String:
	_load()
	return _cursor_mode


static func set_cursor_mode(v: String) -> void:
	_load()
	_cursor_mode = "toggle" if v == "toggle" else "hold"
	_save()
	notifier().changed.emit()


## True the first few times (3): show "Hold Alt to use the mouse", and count it.
static func take_cursor_hint() -> bool:
	_load()
	if _cursor_hints >= 3:
		return false
	_cursor_hints += 1
	_save()
	return true


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
	_view = "third"
	_seen = {}
