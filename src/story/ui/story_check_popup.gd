class_name StoryCheckPopup
extends PanelContainer
## Out-of-mech skill checks are rolled instantly: this shows the result as one big number,
## tinted blue on a success and red on a failure, with what it was for. No dice graphics
## (DESIGN.md: "Skill checks: rolled instantly in the background"). Hover it for the math:
## d20 + trigger + Accuracy/Difficulty against 10 (or 20 for HEROIC).

const SHOW_SECONDS := 3.2

var _number: Label
var _title: Label
var _verdict: Label
var _timer := 0.0
var _breakdown := ""
## Where it sits: "top" (above a conversation) or "bottom" (under an open menu).
var dock := "top"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.EDGE, Color(0.03, 0.04, 0.06, 0.92), 3, 6, 14))
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = StoryStyle.label("", 16, StoryStyle.DIM, 340)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_number = StoryStyle.label("", 64)
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.add_theme_constant_override("outline_size", 6)
	_number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	box.add_child(_number)
	_verdict = StoryStyle.label("", 18)
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_verdict)
	visible = false


## `check` = a NarrativeCheck record (or a downtime/organization roll record).
func show_check(check: Dictionary, who: String = "") -> void:
	var total := int(check.get("total", 0))
	var outcome := str(check.get("outcome", "success" if check.get("success", false) else "fail"))
	var good := outcome != "fail"
	var tint := StoryStyle.BLUE if good else StoryStyle.RED
	_title.text = ("%s: %s" % [who, check.get("label", "Skill check")]) if who != "" else str(check.get("label", "Skill check"))
	_number.text = str(total)
	_number.add_theme_color_override("font_color", tint)
	var level := str(check.get("level", "normal"))
	var words := {"success": "SUCCESS", "success_cost": "SUCCESS, WITH A COST", "fail": "FAILURE"}
	_verdict.text = "%s%s" % [words.get(outcome, outcome.to_upper()), "" if level == "normal" else "   (%s)" % level.to_upper()]
	_verdict.add_theme_color_override("font_color", tint.lightened(0.2))
	_breakdown = breakdown(check)
	tooltip_text = _breakdown
	(get_theme_stylebox("panel") as StyleBoxFlat).border_color = tint
	visible = true
	modulate.a = 1.0
	_timer = SHOW_SECONDS
	size = Vector2.ZERO
	reset_size()


## The math in plain words, e.g. "d20 rolled 12 + Charm +2 + Accuracy 1d6 (kept 4) = 18 vs 10".
static func breakdown(check: Dictionary) -> String:
	var parts := PackedStringArray(["d20 rolled %d" % int(check.get("d20", 0))])
	for b: Dictionary in check.get("bonus_sources", []):
		parts.append("%s %+d" % [b.get("label", "bonus"), int(b.get("value", 0))])
	var acc: Dictionary = check.get("accuracy_roll", {})
	var net := int(acc.get("net", 0))
	if net != 0:
		parts.append("%s %dd6 (kept %d) %+d" % ["Accuracy" if net > 0 else "Difficulty", absi(net), int(acc.get("kept", 0)), int(acc.get("value", 0))])
	var why := PackedStringArray()
	for s: Dictionary in check.get("sources", []):
		why.append("%s: +1 %s" % [s.get("label", ""), s.get("kind", "")])
	var line := " + ".join(parts) + " = %d vs %d" % [int(check.get("total", 0)), 20 if str(check.get("level", "")) == "heroic" else int(check.get("target", 10))]
	if not why.is_empty():
		line += "\n" + ", ".join(why)
	if str(check.get("level", "normal")) == "risky":
		line += "\nRISKY: under 20, there are consequences even on a success."
	if str(check.get("consequence_text", "")) != "" and str(check.get("outcome", "")) != "success":
		line += "\nConsequence: " + str(check["consequence_text"])
	line += "\n(%s)" % check.get("rule_ref", NarrativeCheck.REF)
	return line


func _process(delta: float) -> void:
	if visible:
		var vp := get_viewport_rect().size
		position = Vector2((vp.x - size.x) / 2.0, vp.y * 0.1 if dock == "top" else vp.y - size.y - 12.0)
	if not visible or get_global_rect().has_point(get_global_mouse_position()):
		return
	_timer -= delta
	if _timer < 0.6:
		modulate.a = maxf(_timer / 0.6, 0.0)
	if _timer <= 0.0:
		visible = false
