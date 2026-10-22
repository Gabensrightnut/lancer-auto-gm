class_name BattleKeys
extends RefCounted
## Battle controls: action names, labels and default keys (common RTS/tactics layout). All are
## InputMap actions, so the Settings screen can list and rebind them (ACTIONS has the labels;
## GameSettings.rebind/apply_keys work on the same names). ensure() adds any that are missing
## with their defaults; a binding the player saved replaces them.
##
## Mouse (fixed): left click/drag = select, move, target; right click = context menu (or cancel
## while picking); middle drag = orbit; Shift + middle drag = pan; wheel = zoom; screen edges
## pan. Number keys 1-0 fire the action bar's buttons.

## action -> [label, default keys...]
const ACTIONS := {
	"cam_pan_up": ["Camera: pan forward", KEY_W, KEY_UP],
	"cam_pan_down": ["Camera: pan back", KEY_S, KEY_DOWN],
	"cam_pan_left": ["Camera: pan left", KEY_A, KEY_LEFT],
	"cam_pan_right": ["Camera: pan right", KEY_D, KEY_RIGHT],
	"cam_rotate_left": ["Camera: rotate left", KEY_Q],
	"cam_rotate_right": ["Camera: rotate right", KEY_E],
	"cam_zoom_in": ["Camera: zoom in", KEY_EQUAL, KEY_KP_ADD],
	"cam_zoom_out": ["Camera: zoom out", KEY_MINUS, KEY_KP_SUBTRACT],
	"cam_focus": ["Camera: focus your unit", KEY_F, KEY_HOME],
	"tactical_view": ["Hold: tactical view (threat, ranges, stats)", KEY_SPACE],
	"first_person": ["First person (cockpit) on/off", KEY_V],
	"next_target": ["Next target", KEY_TAB],
	"reload": ["Reload (Stabilize, or a reload system)", KEY_R],
	"brace": ["Brace (when offered)", KEY_B],
	"confirm": ["Confirm", KEY_ENTER, KEY_KP_ENTER],
	"cancel": ["Cancel / back", KEY_ESCAPE],
	"fly_toggle": ["Take off / land", KEY_T],
	"sky_up": ["Flying: higher", KEY_PAGEUP],
	"sky_down": ["Flying: lower", KEY_PAGEDOWN],
}


static func ensure() -> void:
	for a: String in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		if InputMap.action_get_events(a).is_empty():
			for i in range(1, (ACTIONS[a] as Array).size()):
				var ev := InputEventKey.new()
				ev.physical_keycode = int(ACTIONS[a][i])
				InputMap.action_add_event(a, ev)


## "W / Up" style text for the help panel and tooltips.
static func keys_text(a: String) -> String:
	var out: Array = []
	if InputMap.has_action(a):
		for ev: InputEvent in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var k := ev as InputEventKey
				out.append(OS.get_keycode_string(k.physical_keycode if k.physical_keycode != 0 else k.keycode))
	return " / ".join(out)


## The whole list as text: [[label, keys]...] (help panel, docs).
static func listing() -> Array:
	ensure()
	var out: Array = []
	for a: String in ACTIONS:
		out.append([ACTIONS[a][0], keys_text(a)])
	return out
