class_name ObjectivePanel
extends PanelContainer
## The mission's objectives in plain words, top left of the battle HUD: the sitrep's own
## (primary: it alone decides the mission) and any secondary GM objective, each with its state
## and how many rounds are left. Reads the Mission (sitrep, rounds, flavor.objectives/protect).

const PRIMARY := {
	"sitrep_standardcombat": "Defeat or drive off the enemy force",
	"sitrep_control": "Hold more of the zones than the enemy",
	"sitrep_holdout": "Hold the zone",
	"sitrep_gauntlet": "Get the squad through the zone",
	"sitrep_escort": "Get the Objective to safety",
	"sitrep_extraction": "Recover the Objective and extract",
	"sitrep_recon": "Find the true Control Zone",
}

var _list: VBoxContainer


func _ready() -> void:
	theme = MenuTheme.theme()
	add_theme_stylebox_override("panel", MenuTheme.box(Color(0.04, 0.05, 0.07, 0.82), MenuTheme.TEXT.darkened(0.6), 1, 4))
	position = Vector2(24, 96)
	custom_minimum_size = Vector2(420, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list = VBoxContainer.new()
	add_child(_list)


## Lines for a mission at a round: [{text, state, primary}]; also used by tests.
static func lines(m: Mission, round_now: int) -> Array:
	if m == null:
		return []
	var left := maxi(0, m.rounds - round_now + 1) if m.rounds > 0 else 0
	var head := str(PRIMARY.get(m.sitrep_id, "Complete the mission"))
	if m.flavor.has("protect"):
		head = "Hold the zone and protect the %s" % str(m.flavor["protect"]["kind"])
	if left > 0:
		head += ": %d more round%s" % [left, "" if left == 1 else "s"]
	var out: Array = [{"text": head, "state": m.outcome if m.outcome != "" else "open", "primary": true}]
	for o: Dictionary in m.flavor.get("objectives", []):
		if bool(o.get("secondary", false)):
			var st := str(o.get("state", "open"))
			var tail: String = {"held": " (held)", "done": " (done)", "failed": " (lost)"}.get(st, "")
			out.append({"text": "Secondary: %s%s. Reward: %s" % [str(o["text"]), tail, str(o.get("reward_name", ""))], "state": st, "primary": false})
	return out


func show_mission(m: Mission, round_now: int) -> void:
	for c in _list.get_children():
		c.queue_free()
	var ls := lines(m, round_now)
	visible = not ls.is_empty()
	for l: Dictionary in ls:
		var col: Color = MenuTheme.TEXT
		match str(l["state"]):
			"failed", Mission.ENEMIES:
				col = MenuTheme.WARN
			"done", "held", Mission.PLAYERS:
				col = Color(0.5, 0.9, 0.6)
		var lab := MenuTheme.label(("◆ " if bool(l["primary"]) else "◇ ") + str(l["text"]), 19 if bool(l["primary"]) else 17, col)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab.custom_minimum_size = Vector2(400, 0)
		_list.add_child(lab)
