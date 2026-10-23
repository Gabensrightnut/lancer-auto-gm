class_name RuleResult
extends RefCounted
## Answer from the rules engine: is this allowed, and if not, why (with a book reference).
## `grey_area` marks a legal-but-unclear case the table must rule on (DESIGN.md section 7).

var ok: bool = true
var reason: String = ""
## Where the rule comes from, e.g. "Core p.62 Engaged" or "glossary: Hidden".
var rule_ref: String = ""
## Set when the book is unclear: an id for the ruling, and the readings to choose from.
var grey_area: String = ""
var options: Array = []
## Every problem found, for checks that collect several (e.g. loadout legality):
## [{"reason": String, "rule_ref": String}].
var details: Array = []
## For developers and tools: which action parameter was missing or wrong ("params.target").
## Kept out of `reason`, which players read.
var hint: String = ""


static func allow() -> RuleResult:
	return RuleResult.new()


static func deny(why: String, ref: String) -> RuleResult:
	var r := RuleResult.new()
	r.ok = false
	var plain := plain_reason(why)
	r.reason = plain[0]
	r.hint = plain[1]
	r.rule_ref = ref
	return r


## Splits engine hints like "(params.target)" or "(params.aim = [x, y])" out of a reason, so the
## player sees plain words. "(params.setting: repulse or attract)" keeps "(repulse or attract)".
## Returns [plain reason, hint].
static func plain_reason(why: String) -> Array:
	if not why.contains("(params."):
		return [why, ""]
	var re := RegEx.create_from_string("\\s*\\((params\\.[A-Za-z_]+)([^)]*)\\)")
	var hints: PackedStringArray = []
	var out := why
	var m := re.search(out)
	while m != null:
		hints.append(m.get_string(1) + m.get_string(2))
		var rest := m.get_string(2).strip_edges()
		var keep := ""
		if rest.begins_with(":") and not rest.contains("[") and not rest.contains("{"):
			keep = " (" + rest.substr(1).strip_edges() + ")"
		out = out.substr(0, m.get_start()) + keep + out.substr(m.get_end())
		m = re.search(out)
	return [out, ", ".join(hints)]


static func ruling_needed(ruling_id: String, why: String, ref: String, choices: Array) -> RuleResult:
	var r := RuleResult.new()
	r.grey_area = ruling_id
	r.reason = why
	r.rule_ref = ref
	r.options = choices
	return r


func to_dict() -> Dictionary:
	return {"ok": ok, "reason": reason, "rule_ref": rule_ref, "grey_area": grey_area, "options": options, "details": details, "hint": hint}
