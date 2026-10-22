class_name GameSettings
extends RefCounted
## Player settings, saved in user://settings.cfg (never touched by updates). The battle HUD
## reads these too: ui_scale, action_bar_scale, colorblind, animation_speed, popup_speed,
## graphics; keybinds go into the InputMap under the action names in ACTIONS.

const FILE := "user://settings.cfg"

## Rebindable actions: name -> [label, default key].
## Keys beyond the battle controls in data/game/keybinds.json (BattleKeys): action ->
## [label, default key]. Everything rebindable is actions().
const EXTRA_ACTIONS := {
	"end_turn": ["End turn", KEY_X],
	"toggle_log": ["Show battle log", KEY_L],
	"codex": ["Codex: look up what's under the mouse", KEY_F1],
}
## Saved key bindings from before this list (different action names and clashing defaults:
## E, Space and Tab) are dropped once.
const KEYS_VERSION := 2
const COLORBLIND := ["off", "deuteranopia", "protanopia", "tritanopia"]
## Battlefield quality presets (WorldQuality.PRESETS), lowest first.
const GRAPHICS := ["low", "medium", "high"]
const ANIMATION := ["cinematic", "normal", "fast"]

var ui_scale := 1.0
var text_size := 1.0
var action_bar_scale := 1.0
var colorblind := "off"
## WorldQuality preset. A new install gets default_graphics().
var graphics := "high"
var animation_speed := "normal"
## How long roll and damage pop-ups stay up (1 = normal, 2 = twice as long).
var popup_duration := 1.0
## Solo and hot-seat: AI squadmates take their turns on their own once only they are left to
## act (people can still pick them earlier). Online games start with it off.
var ai_squad_auto := true
## action name -> keycode
var keybinds: Dictionary = {}
## Mouse look while exploring (first and third person): how fast the view turns, and whether
## moving the mouse up looks down.
var mouse_sensitivity := 1.0
var invert_y := false
## This player's house rules (HouseRules: id -> on). They're the game's when this player
## decides: the GM, or the host when the AI is the GM.
var house_rules: Dictionary = {}


static func load_settings(path: String = FILE) -> GameSettings:
	var s := GameSettings.new()
	s.graphics = default_graphics()
	var table := actions()
	for a: String in table:
		s.keybinds[a] = int(table[a][1])
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	s.ui_scale = clampf(float(cfg.get_value("display", "ui_scale", 1.0)), 0.75, 1.5)
	s.text_size = clampf(float(cfg.get_value("display", "text_size", 1.0)), 0.8, 1.5)
	s.action_bar_scale = clampf(float(cfg.get_value("display", "action_bar_scale", 1.0)), 0.75, 1.5)
	s.colorblind = _one_of(cfg.get_value("display", "colorblind", "off"), COLORBLIND, "off")
	var gfx := str(cfg.get_value("graphics", "preset", s.graphics))
	s.graphics = _one_of("high" if gfx == "ultra" else gfx, GRAPHICS, s.graphics)  # "ultra" was folded into high
	s.animation_speed = _one_of(cfg.get_value("gameplay", "animation_speed", "normal"), ANIMATION, "normal")
	s.popup_duration = clampf(float(cfg.get_value("gameplay", "popup_duration", 1.0)), 0.5, 2.0)
	s.ai_squad_auto = bool(cfg.get_value("gameplay", "ai_squad_auto", true))
	s.mouse_sensitivity = clampf(float(cfg.get_value("mouse", "sensitivity", 1.0)), 0.25, 3.0)
	s.invert_y = bool(cfg.get_value("mouse", "invert_y", false))
	if int(cfg.get_value("keys", "_version", 1)) == KEYS_VERSION:
		for a: String in s.keybinds:
			s.keybinds[a] = int(cfg.get_value("keys", a, s.keybinds[a]))
	for id: String in HouseRules.defaults():
		if cfg.has_section_key("house_rules", id):
			s.house_rules[id] = bool(cfg.get_value("house_rules", id))
	return s


func save(path: String = FILE) -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("display", "text_size", text_size)
	cfg.set_value("display", "action_bar_scale", action_bar_scale)
	cfg.set_value("display", "colorblind", colorblind)
	cfg.set_value("graphics", "preset", graphics)
	cfg.set_value("gameplay", "animation_speed", animation_speed)
	cfg.set_value("gameplay", "popup_duration", popup_duration)
	cfg.set_value("gameplay", "ai_squad_auto", ai_squad_auto)
	cfg.set_value("mouse", "sensitivity", mouse_sensitivity)
	cfg.set_value("mouse", "invert_y", invert_y)
	cfg.set_value("keys", "_version", KEYS_VERSION)
	for a: String in keybinds:
		cfg.set_value("keys", a, keybinds[a])
	for id: String in house_rules:
		cfg.set_value("house_rules", id, bool(house_rules[id]))
	return cfg.save(path)


## Applies what takes effect right away: UI scale, key bindings and the graphics preset (for
## the next battlefield built).
func apply(tree: SceneTree) -> void:
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = ui_scale
		apply_graphics(tree.root)
	apply_keys()


## Sets the battlefield quality (WorldQuality) on `viewport`. Call before a board is built:
## scenery density is read when the board is made.
func apply_graphics(viewport: Viewport) -> void:
	WorldQuality.set_preset(graphics, viewport)


## "high", or "medium" on a weak GPU (integrated, software or virtual graphics).
static func default_graphics() -> String:
	if DisplayServer.get_name() == "headless":
		return "high"
	match RenderingServer.get_video_adapter_type():
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_CPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return "medium"
	return "high"


func apply_keys() -> void:
	var table := actions()
	var primary := {}  # key -> actions that have it as their own key
	for a: String in keybinds:
		if not primary.has(int(keybinds[a])):
			primary[int(keybinds[a])] = []
		primary[int(keybinds[a])].append(a)
	for a: String in keybinds:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		var keys: Array = [int(keybinds[a])]
		# The defaults' second keys (arrows, keypad...) stay, unless one is now the key of
		# another action in the same context.
		for i in range(2, (table.get(a, []) as Array).size()):
			var taken: Array = primary.get(int(table[a][i]), [])
			if not taken.any(func(b: String) -> bool: return b != a and shares_context(a, b)):
				keys.append(int(table[a][i]))
		for k: int in keys:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)


## Every rebindable key: the battle controls (data/game/keybinds.json via BattleKeys) and
## EXTRA_ACTIONS. action -> [label, default key, more default keys...]
static func actions() -> Dictionary:
	var out := BattleKeys.defaults().duplicate()
	out.merge(EXTRA_ACTIONS)
	return out


## Pairs of actions in the same context whose default keys are the same (none should be).
static func default_clashes() -> Array:
	var out: Array = []
	var table := actions()
	var ids := table.keys()
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			if not shares_context(ids[i], ids[j]):
				continue
			for k: Variant in (table[ids[i]] as Array).slice(1):
				if (table[ids[j]] as Array).slice(1).has(k):
					out.append([ids[i], ids[j], key_name(int(k))])
	return out


## Actions in this player's bindings that share a key with another in the same context (after
## a rebind elsewhere, or a saved file edited by hand): {action: [other actions]}.
func conflicts() -> Dictionary:
	var out := {}
	for a: String in keybinds:
		for b: String in keybinds:
			if a != b and int(keybinds[a]) == int(keybinds[b]) and shares_context(a, b):
				if not out.has(a):
					out[a] = []
				out[a].append(b)
	return out


## Where an action is used: "battle", "explore" or "both" (data/game/keybinds.json "context";
## battle when not given). The same key may do different things in different contexts (W pans
## the battle camera and walks while exploring).
static func context_of(action: String) -> String:
	if action in ["confirm", "cancel", "codex"]:
		return "both"
	return str(_contexts().get(action, "battle"))


static func shares_context(a: String, b: String) -> bool:
	var ca := context_of(a)
	var cb := context_of(b)
	return ca == cb or ca == "both" or cb == "both"


static var _ctx_cache: Dictionary = {}


static func _contexts() -> Dictionary:
	if _ctx_cache.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(BattleKeys.FILE)) if FileAccess.file_exists(BattleKeys.FILE) else null
		_ctx_cache["_loaded"] = true
		if d is Dictionary:
			for e: Dictionary in (d as Dictionary).get("actions", []):
				_ctx_cache[str(e.get("id", ""))] = str(e.get("context", "battle"))
	return _ctx_cache


## Binds `key` to `action`. If another action used that key, it's swapped onto the old key
## so nothing is left unbound. Returns the action that was swapped ("" if none).
func rebind(action: String, key: int) -> String:
	var old := int(keybinds.get(action, 0))
	for other: String in keybinds:
		if other != action and int(keybinds[other]) == key and shares_context(action, other):
			keybinds[other] = old
			keybinds[action] = key
			return other
	keybinds[action] = key
	return ""


static func key_name(key: int) -> String:
	return OS.get_keycode_string(key) if key != 0 else "(none)"


static func _one_of(v: Variant, allowed: Array, fallback: String) -> String:
	return str(v) if str(v) in allowed else fallback
