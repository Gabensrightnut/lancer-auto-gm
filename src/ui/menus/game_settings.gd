class_name GameSettings
extends RefCounted
## Player settings, saved in user://settings.cfg (never touched by updates). The battle HUD
## reads these too: ui_scale, action_bar_scale, colorblind, animation_speed, popup_speed,
## graphics; keybinds go into the InputMap under the action names in ACTIONS.

const FILE := "user://settings.cfg"

## Rebindable actions: name -> [label, default key].
const ACTIONS := {
	"confirm": ["Confirm action", KEY_ENTER],
	"cancel": ["Cancel / back", KEY_ESCAPE],
	"end_turn": ["End turn", KEY_E],
	"next_unit": ["Next unit", KEY_TAB],
	"camera_left": ["Camera: rotate left", KEY_Q],
	"camera_right": ["Camera: rotate right", KEY_R],
	"camera_up": ["Camera: pan up", KEY_W],
	"camera_down": ["Camera: pan down", KEY_S],
	"camera_pan_left": ["Camera: pan left", KEY_A],
	"camera_pan_right": ["Camera: pan right", KEY_D],
	"toggle_log": ["Show battle log", KEY_L],
	"skip_to_my_turn": ["Skip to my turn", KEY_SPACE],
	"codex": ["Codex: look up what's under the mouse", KEY_F1],
}
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
## This player's house rules (HouseRules: id -> on). They're the game's when this player
## decides: the GM, or the host when the AI is the GM.
var house_rules: Dictionary = {}


static func load_settings(path: String = FILE) -> GameSettings:
	var s := GameSettings.new()
	s.graphics = default_graphics()
	for a: String in ACTIONS:
		s.keybinds[a] = int(ACTIONS[a][1])
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
	for a: String in ACTIONS:
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
	for a: String in keybinds:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(keybinds[a])
		InputMap.action_add_event(a, ev)


## Binds `key` to `action`. If another action used that key, it's swapped onto the old key
## so nothing is left unbound. Returns the action that was swapped ("" if none).
func rebind(action: String, key: int) -> String:
	var old := int(keybinds.get(action, 0))
	for other: String in keybinds:
		if other != action and int(keybinds[other]) == key:
			keybinds[other] = old
			keybinds[action] = key
			return other
	keybinds[action] = key
	return ""


static func key_name(key: int) -> String:
	return OS.get_keycode_string(key) if key != 0 else "(none)"


static func _one_of(v: Variant, allowed: Array, fallback: String) -> String:
	return str(v) if str(v) in allowed else fallback
